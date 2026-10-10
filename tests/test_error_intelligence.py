from concurrent.futures import ThreadPoolExecutor

import pytest

from company_os.error_intelligence import (
    ErrorIntelligenceStore,
    InvalidIncidentError,
    StoreCorruptError,
)


def record(store, *, project="project-a", summary="Provider timed out after 30 seconds", evidence=None):
    return store.record_incident(
        project_id=project,
        component="provider-router",
        category="availability",
        error_type="TimeoutError",
        summary=summary,
        evidence=evidence or ["tests/fixtures/provider-timeout.txt: assertion 4"],
    )


def test_incident_survives_store_reopen_and_preserves_observation(tmp_path):
    path = tmp_path / "local state with spaces" / "incidents.sqlite3"
    first = ErrorIntelligenceStore(path)
    created = record(first)

    reopened = ErrorIntelligenceStore(path)
    restored = reopened.get(created.id)
    assert restored == created
    assert restored.status == "OBSERVED"
    assert restored.occurrence_count == 1


def test_validation_rejects_invalid_schema_fields_and_unknown_ids(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "errors.sqlite3")
    with pytest.raises(InvalidIncidentError):
        store.record_incident(project_id="../other", component="router", category="runtime", error_type="Timeout", summary="x", evidence=["e"])
    with pytest.raises(InvalidIncidentError):
        store.record_incident(project_id="p", component="router", category="runtime", error_type="Timeout", summary="", evidence=["e"])
    with pytest.raises(InvalidIncidentError):
        store.record_incident(project_id="p", component="router", category="runtime", error_type="Timeout", summary="x", evidence=[])
    with pytest.raises(InvalidIncidentError):
        store.record_incident(project_id="p", component="router", category="runtime", error_type="Timeout", summary="x", evidence={"not": "a sequence"})
    with pytest.raises(InvalidIncidentError):
        store.record_incident(project_id="p", component="router", category="runtime", error_type="Timeout", summary="x", evidence=None)
    with pytest.raises(InvalidIncidentError):
        store.get("missing")


def test_exact_duplicates_add_occurrences_without_replacing_original(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "errors.sqlite3")
    first = record(store, evidence=["first run evidence"])
    second = record(store, evidence=["second run evidence"])

    assert second.id == first.id
    assert second.occurrence_count == 2
    assert second.summary == first.summary
    assert second.evidence == ("first run evidence",)
    observations = store.observations(second.id)
    assert [observation.evidence[0] for observation in observations] == ["first run evidence", "second run evidence"]
    assert len(store.history(second.id)) == 2


def test_concurrent_writers_deduplicate_and_preserve_every_observation(tmp_path):
    path = tmp_path / "errors.sqlite3"
    stores = [ErrorIntelligenceStore(path) for _ in range(6)]

    with ThreadPoolExecutor(max_workers=6) as pool:
        incidents = list(pool.map(lambda n: record(stores[n % len(stores)], evidence=[f"run {n}"]), range(24)))

    assert len({incident.id for incident in incidents}) == 1
    assert ErrorIntelligenceStore(path).get(incidents[0].id).occurrence_count == 24


def test_corrupt_store_fails_closed_and_is_not_overwritten(tmp_path):
    path = tmp_path / "errors.sqlite3"
    corrupt = b"not a sqlite database; keep this evidence"
    path.write_bytes(corrupt)

    with pytest.raises(StoreCorruptError):
        ErrorIntelligenceStore(path)

    assert path.read_bytes() == corrupt


def test_invalid_paths_and_parent_traversal_are_rejected(tmp_path):
    with pytest.raises(InvalidIncidentError):
        ErrorIntelligenceStore("relative.sqlite3")
    with pytest.raises(InvalidIncidentError):
        ErrorIntelligenceStore(tmp_path / ".." / "outside.sqlite3")
    with pytest.raises(InvalidIncidentError):
        ErrorIntelligenceStore(tmp_path)


def test_default_path_is_scoped_to_installation_and_can_be_overridden(tmp_path, monkeypatch):
    from company_os.error_intelligence import default_store_path

    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path / "Local App Data"))
    monkeypatch.delenv("AICO_ERROR_INTELLIGENCE_PATH", raising=False)
    first = default_store_path()
    assert first.parent.name != "ErrorIntelligence"
    assert first.parent.parent.name == "ErrorIntelligence"
    monkeypatch.setenv("AICO_ERROR_INTELLIGENCE_PATH", str(tmp_path / "chosen" / "errors.sqlite3"))
    assert default_store_path() == tmp_path / "chosen" / "errors.sqlite3"


def test_search_and_recommendations_are_isolated_by_project(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "errors.sqlite3")
    a = record(store, project="project-a")
    record(store, project="project-b")

    matches = store.search(project_id="project-a", component="provider-router", error_type="TimeoutError")
    assert [match.incident.id for match in matches] == [a.id]
    assert [match.incident.id for match in store.search(project_id="project-a")] == [a.id]
    assert not store.search(project_id="project-c", component="provider-router")


def test_credentials_are_redacted_before_persistence(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "errors.sqlite3")
    secret = "sk-THIS_IS_A_FAKE_CREDENTIAL_123456"
    incident = store.record_incident(
        project_id="p", component="router", category="provider", error_type="Failure",
        summary=f"Authorization: Bearer abcdefghijklmno and api_key={secret}",
        evidence=[f"response contained {secret}", "https://user:password@example.invalid/path"],
    )

    reopened = ErrorIntelligenceStore(tmp_path / "errors.sqlite3").get(incident.id)
    serialized = repr(reopened)
    assert secret not in serialized
    assert "abcdefghijklmno" not in serialized
    assert "user:password@" not in serialized
    assert "[REDACTED]" in serialized


def test_observation_and_diagnosis_do_not_verify_root_cause_or_fix(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "errors.sqlite3")
    incident = record(store)
    assert not incident.root_cause_verified
    assert not store.verified_solutions(project_id="project-a")

    diagnosed = store.diagnose(incident.id, root_cause="Provider request timed out", evidence=["trace: request duration 30s"])
    assert diagnosed.status == "DIAGNOSED"
    assert not diagnosed.root_cause_verified
    verified_cause = store.verify_root_cause(
        incident.id, verified_by="operator", evidence=["trace confirms configured deadline elapsed"]
    )
    assert verified_cause.root_cause_verified
    assert verified_cause.root_cause_evidence
    store.propose_fix(incident.id, action="Increase bounded provider timeout", contraindications=["Adds waiting time"])
    assert not store.verified_solutions(project_id="project-a")


def test_verified_fix_requires_matching_proposal_and_evidence(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "errors.sqlite3")
    incident = record(store)
    store.propose_fix(incident.id, action="Use bounded timeout configuration")
    with pytest.raises(InvalidIncidentError):
        store.verify_fix(incident.id, action="Unrelated action", verified_by="operator", evidence=["check passed"])
    with pytest.raises(InvalidIncidentError):
        store.verify_fix(incident.id, action="Use bounded timeout configuration", verified_by="operator", evidence=[])

    verified = store.verify_fix(
        incident.id, action="Use bounded timeout configuration", verified_by="operator",
        evidence=["regression test passed: tests/test_provider.py::test_timeout"],
    )
    solutions = store.verified_solutions(project_id="project-a", component="provider-router")
    assert verified.status == "FIX_VERIFIED"
    assert len(solutions) == 1
    assert solutions[0].incident.verified_fix == "Use bounded timeout configuration"
    assert solutions[0].incident.fix_evidence


def test_failed_recovery_suppresses_previously_verified_recommendation(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "errors.sqlite3")
    incident = record(store)
    action = "Use bounded timeout configuration"
    store.propose_fix(incident.id, action=action)
    store.verify_fix(incident.id, action=action, verified_by="operator", evidence=["regression test passed"])
    assert store.verified_solutions(project_id="project-a")

    store.record_recovery_failure(incident.id, action=action, recorded_by="operator", evidence=["retry failed on run 2"])
    assert not store.verified_solutions(project_id="project-a")


def test_similarity_is_not_reported_as_equivalence_and_exact_fingerprint_is(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "errors.sqlite3")
    incident = record(store)
    similar = store.search(project_id="project-a", component="provider-router", error_type="TimeoutError")
    exact = store.search(project_id="project-a", fingerprint=incident.fingerprint)

    assert similar[0].confidence < 1.0
    assert similar[0].equivalent is False
    assert exact[0].confidence == 1.0
    assert exact[0].equivalent is True


def test_regression_is_an_explicit_status_with_evidence(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "errors.sqlite3")
    incident = record(store)
    store.propose_fix(incident.id, action="Increase bounded provider timeout")
    store.verify_fix(incident.id, action="Increase bounded provider timeout", verified_by="operator", evidence=["test passed"])
    regressed = store.mark_regression(incident.id, evidence=["same test failed after rollback"])
    assert regressed.status == "REGRESSION_DETECTED"
    assert not store.verified_solutions(project_id="project-a")
