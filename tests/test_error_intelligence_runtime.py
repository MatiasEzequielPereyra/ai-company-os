import io
import json
import sqlite3
import sys

import pytest

from company_os.error_intelligence import ErrorIntelligenceStore
from company_os.error_intelligence import runtime


@pytest.fixture
def setup(tmp_path, monkeypatch):
    project = tmp_path / "project"
    project.mkdir()
    path = tmp_path / "memory" / "incidents.sqlite3"
    monkeypatch.setenv("AICO_ERROR_INTELLIGENCE_PATH", str(path))
    monkeypatch.delenv("AICO_ERROR_INTELLIGENCE_ENABLED", raising=False)
    return project, path


def failure(**extra):
    return dict(event_type="provider_attempt_finished", provider="OpenRouter",
                success=False, error_category="timeout", task_id="AICO-002", **extra)


def test_automatic_capture_and_explicit_optout(setup, monkeypatch):
    project, path = setup
    assert runtime.capture_event(project, failure())["status"] == "captured"
    assert path.is_file()
    monkeypatch.setenv("AICO_ERROR_INTELLIGENCE_ENABLED", "0")
    before = path.read_bytes()
    assert runtime.capture_event(project, failure())["status"] == "disabled"
    assert runtime.lookup(project)["status"] == "disabled"
    assert path.read_bytes() == before


def test_canonical_identity_and_project_isolation(setup):
    project, _ = setup
    other = project.parent / "other"
    other.mkdir()
    assert runtime.project_identity(project) == runtime.project_identity(project / ".")
    assert runtime.project_identity(project) != runtime.project_identity(other)
    runtime.capture_event(project, failure())
    assert runtime.lookup(other)["matches"] == []
    assert len(runtime.lookup(project)["matches"]) == 1


@pytest.mark.parametrize("kind", ["provider_timeout", "provider_attempt", "provider_attempt_started", "provider_semantic_retry"])
def test_duplicate_provider_event_aliases_are_ignored(setup, kind):
    project, path = setup
    event = failure()
    event["event_type"] = kind
    assert runtime.capture_event(project, event)["status"] == "ignored"
    assert not path.exists()


def test_repeat_counts_and_typed_metadata_exclude_raw_content(setup):
    project, path = setup
    secret = "SUPER_PRIVATE_MODEL_PROMPT_AND_TOKEN_12345"
    event = failure(reason=secret, prompt=secret, error=secret, model=secret, actor=secret)
    first = runtime.capture_event(project, event)
    second = runtime.capture_event(project, event)
    assert first["incident"]["id"] == second["incident"]["id"]
    assert second["incident"]["occurrence_count"] == 2
    assert secret not in json.dumps(second)
    store = ErrorIntelligenceStore(path)
    observations = store.observations(first["incident"]["id"])
    assert len(observations) == 2
    assert all(secret not in json.dumps(item.evidence) for item in observations)
    assert secret.encode() not in path.read_bytes()


def test_only_relevant_verified_solutions_are_recommended(setup):
    project, path = setup
    captured = runtime.capture_event(project, failure())
    incident_id = captured["incident"]["id"]
    store = ErrorIntelligenceStore(path)
    store.propose_fix(incident_id, action="Check local network")
    assert runtime.capture_event(project, failure())["verified_solutions"] == []
    store.verify_fix(incident_id, action="Check local network", verified_by="operator", evidence=["deterministic verification"])
    result = runtime.capture_event(project, failure())
    assert len(result["verified_solutions"]) == 1
    assert result["verified_solutions"][0]["verified_solution"] == "Check local network"
    assert result["action_authorized"] is False
    assert result["verified_solutions"][0]["trust"] == "UNTRUSTED_HISTORICAL_ADVICE"
    unrelated = failure()
    unrelated["provider"] = "Gemini"
    assert runtime.capture_event(project, unrelated)["verified_solutions"] == []
    store.record_recovery_failure(incident_id, action="Check local network", recorded_by="operator", evidence=["failed verification"])
    after_failure = runtime.capture_event(project, failure())
    assert after_failure["verified_solutions"] == []
    assert all("verified_solution" not in item and "contraindications" not in item for item in after_failure["matches"])
    lookup = runtime.lookup(project)
    assert lookup["verified_solutions"] == []
    assert all("verified_solution" not in item and "contraindications" not in item for item in lookup["matches"])


def test_corrupt_store_is_unavailable_and_preserved(setup):
    project, path = setup
    path.parent.mkdir()
    original = b"historical corrupt store must remain intact"
    path.write_bytes(original)
    assert runtime.capture_event(project, failure())["status"] == "unavailable"
    assert runtime.lookup(project)["status"] == "unavailable"
    assert path.read_bytes() == original


def test_unknown_schema_readonly_lookup_is_unavailable_and_preserves_bytes(setup):
    project, path = setup
    runtime.capture_event(project, failure())
    with sqlite3.connect(path) as connection:
        connection.execute("PRAGMA user_version = 999")
    before = path.read_bytes()
    assert runtime.lookup(project)["status"] == "unavailable"
    assert path.read_bytes() == before


def test_lookup_never_creates_absent_store(setup):
    project, path = setup
    result = runtime.lookup(project)
    assert result["status"] == "available"
    assert result["matches"] == []
    assert not path.exists()
    assert not path.parent.exists()


def test_lookup_is_read_only_and_does_not_add_occurrences(setup):
    project, path = setup
    captured = runtime.capture_event(project, failure())
    before = path.read_bytes()
    result = runtime.lookup(project)
    assert result["status"] == "available"
    assert result["matches"][0]["id"] == captured["incident"]["id"]
    assert result["matches"][0]["occurrence_count"] == 1
    assert path.read_bytes() == before


def test_context_rejection_is_observation_without_provider_call(setup):
    project, _ = setup
    result = runtime.capture_event(project, {"event_type": "provider_context_rejected", "provider": "Gemini", "error_category": "context", "reason": "private source material"})
    assert result["status"] == "captured"
    assert result["incident"]["error_type"] == "context_budget"
    assert "private source material" not in json.dumps(result)


def test_invalid_identity_metadata_is_dropped(setup):
    project, path = setup
    event = failure(role="malicious instructions", workload="secret", run_id="private", source_path="private")
    event["task_id"] = "../private-task"
    result = runtime.capture_event(project, event)
    assert result["incident"]["task_id"] is None
    observation = ErrorIntelligenceStore(path).observations(result["incident"]["id"])[0]
    metadata = json.loads(observation.evidence[0])
    assert not {"role", "workload", "run_id", "source_path", "task_id"} & metadata.keys()


@pytest.mark.parametrize("component", ["agent-runner", "gate-runner", "writable-runner"])
def test_runner_failures_capture_without_lifecycle_authority(setup, component):
    project, _ = setup
    result = runtime.capture_event(project, {"event_type": "runtime_failure", "component": component, "error_category": "runtime", "task_id": "AICO-002"})
    assert result["status"] == "captured"
    assert result["incident"]["component"] == component
    assert result["incident"]["status"] == "OBSERVED"
    assert result["action_authorized"] is False


@pytest.mark.parametrize("previous,target,expected", [("ACTIVE", "BLOCKED", "blocked"), ("REVIEW", "READY", "gate_rejection"), ("QA", "READY", "gate_rejection"), ("SECURITY", "READY", "gate_rejection")])
def test_lifecycle_observations_have_distinct_categories(setup, previous, target, expected):
    project, _ = setup
    result = runtime.capture_event(project, {"event_type": "task_transition", "from_status": previous, "to_status": target, "task_id": "AICO-002"})
    assert result["status"] == "captured"
    assert result["incident"]["component"] == "task-lifecycle"
    assert result["incident"]["error_type"] == expected
    assert result["incident"]["category"] == "lifecycle_observation"


def test_success_never_verifies_incident_or_fix(setup):
    project, path = setup
    captured = runtime.capture_event(project, failure())
    event = failure()
    event["success"] = True
    assert runtime.capture_event(project, event)["status"] == "ignored"
    assert runtime.capture_event(project, {"event_type": "task_transition", "from_status": "SECURITY", "to_status": "DONE"})["status"] == "ignored"
    incident = ErrorIntelligenceStore(path).get(captured["incident"]["id"])
    assert incident.status == "OBSERVED"
    assert not incident.root_cause_verified
    assert incident.verified_fix is None
    assert incident.occurrence_count == 1


@pytest.mark.parametrize("event", [None, [], {}, {"event_type": "runtime_failure", "component": "unknown"}, {"event_type": "provider_attempt_finished", "provider": "unknown", "success": False}])
def test_invalid_event_is_ignored_without_store_creation(setup, event):
    project, path = setup
    assert runtime.capture_event(project, event)["status"] == "ignored"
    assert not path.exists()


@pytest.mark.parametrize("limit", [0, 21, True, "3"])
def test_lookup_limits_are_bounded(setup, limit):
    project, path = setup
    assert runtime.lookup(project, limit=limit)["code"] == "INVALID_LIMIT"
    assert not path.exists()


@pytest.mark.parametrize("payload", [b"not-json", b"x" * (runtime.MAX_INPUT_BYTES + 1), b"\xff"])
def test_bridge_input_is_bounded_and_invalid_input_does_not_capture(setup, monkeypatch, capsys, payload):
    project, path = setup
    monkeypatch.setattr(sys, "argv", ["bridge", "capture", "--project", str(project)])
    monkeypatch.setattr(sys, "stdin", io.TextIOWrapper(io.BytesIO(payload)))
    assert runtime.main() == 0
    assert json.loads(capsys.readouterr().out)["code"] == "INVALID_INPUT"
    assert not path.exists()
