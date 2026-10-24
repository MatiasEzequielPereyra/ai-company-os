"""Independent adversarial checks of S1's synthetic trust boundaries."""

from dataclasses import fields
from datetime import datetime, timezone
import hashlib
import json

import pytest

from company_os.sandbox.contracts import ContractError
from company_os.sandbox.puretypes import S1SyntheticLimits, ConsistencyReport
from company_os.sandbox.codecs import decode_piece, check_package_consistency


def limits(**changes):
    values = dict(
        piece_bytes=8192, total_bytes=32768, depth=8, items=32, pieces=16, events=32
    )
    values.update(changes)
    return S1SyntheticLimits(**values)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


@pytest.mark.parametrize(
    "name", ["piece_bytes", "total_bytes", "depth", "items", "pieces", "events"]
)
@pytest.mark.parametrize("value", [True, False, 0, -1, 1.5, "2", None])
def test_security_limits_reject_nonpositive_or_noninteger(name, value):
    with pytest.raises(ContractError):
        limits(**{name: value})


@pytest.mark.parametrize(
    "raw",
    [
        b"\xef\xbb\xbf{}",
        b"\xff",
        b'{"schema":NaN}',
        b'{"schema":1,"schema":2}',
        b"[[[[[[[[[0]]]]]]]]]",
    ],
)
def test_security_malformed_wire_never_yields_a_piece(raw):
    with pytest.raises(ContractError):
        decode_piece(
            raw, expected_digest=digest(raw), kind="PolicyApproval", limits=limits()
        )


def test_security_required_limits_have_no_defaults():
    with pytest.raises(TypeError):
        S1SyntheticLimits()


def test_security_report_cannot_be_constructed_with_operational_flags():
    with pytest.raises(TypeError):
        ConsistencyReport(
            package_sha256="a" * 64,
            package_kind="HOST_TERMINAL",
            wire_provenance="OPERATIONAL",
            operational=True,
        )
    report = ConsistencyReport("a" * 64, "HOST_TERMINAL", "OPERATIONAL")
    assert report.scope == "SIMULATION"
    assert report.operational is False
    assert report.unauthenticated_audit is True
    assert not {"approved", "authorized", "VerifiedHostEvidence"} & {
        f.name for f in fields(report)
    }


class CallbackDict(dict):
    def items(self):
        raise AssertionError("Untrusted mapping callback executed")

    def values(self):
        raise AssertionError("Untrusted mapping callback executed")

    def __iter__(self):
        raise AssertionError("Untrusted mapping callback executed")


@pytest.mark.parametrize("slot", ["pieces", "payloads", "outputs"])
def test_security_custom_mapping_rejected_without_callbacks(slot):
    raw = b"{}"
    kwargs = dict(pieces={}, payloads={}, outputs={})
    kwargs[slot] = CallbackDict()
    with pytest.raises(ContractError):
        check_package_consistency(
            raw,
            expected_digest=digest(raw),
            now=datetime(2026, 10, 22, tzinfo=timezone.utc),
            limits=limits(),
            **kwargs,
        )


POLICY = {
    "policy_sha256": "a" * 64,
    "approval_id": "11111111-1111-4111-8111-111111111111",
    "approver_principal": "synthetic-principal",
    "approved_utc": "2026-10-22T00:00:00Z",
    "scope": "EVIDENCE_POLICY",
    "revoked": False,
}


def test_security_decoded_policy_is_immutable_data_not_authority():
    raw = json.dumps(POLICY).encode()
    result = decode_piece(
        raw, expected_digest=digest(raw), kind="PolicyApproval", limits=limits()
    )
    assert result.raw is raw
    with pytest.raises(TypeError):
        result.value["revoked"] = True
    assert not hasattr(result, "authorized")
    assert not hasattr(result, "approved")


@pytest.mark.parametrize(
    "field,value",
    [("piece_bytes", 8388609), ("depth", 999), ("items", True), ("pieces", -1)],
)
def test_security_forged_limits_cannot_bypass_boundary_validation(field, value):
    configured = limits()
    object.__setattr__(configured, field, value)
    raw = json.dumps(POLICY).encode()
    with pytest.raises(ContractError):
        decode_piece(
            raw, expected_digest=digest(raw), kind="PolicyApproval", limits=configured
        )


from test_sandbox_s1_codecs import make_package, package_check, encode


def replace_host(package, pieces, mutation):
    old = package["host_evidence"]["sha256"]
    host = json.loads(pieces.pop(old))
    mutation(host)
    raw = encode(host)
    package["host_evidence"] = {"sha256": digest(raw), "bytes": len(raw)}
    pieces[digest(raw)] = raw


def test_security_wire_operational_label_never_elevates_report():
    package, pieces, payloads, outputs = make_package()
    package["provenance"] = "OPERATIONAL"
    report = package_check(package, pieces, payloads, outputs)
    assert report.operational is False
    assert report.scope == "SIMULATION"
    assert report.unauthenticated_audit is True


@pytest.mark.parametrize(
    "cause",
    [
        {
            "code": "AUTHORIZATION_CHANGED",
            "event_sequence": 3,
            "observed_tick": 1,
            "generation": 0,
        },
        {
            "code": "OPERATION_FAILED",
            "event_sequence": 999,
            "observed_tick": 1,
            "generation": 0,
        },
        {
            "code": "OPERATION_FAILED",
            "event_sequence": 3,
            "observed_tick": 1,
            "generation": 1,
        },
    ],
)
def test_security_host_cannot_hide_active_cause_or_future_identity(cause):
    package, pieces, payloads, outputs = make_package()
    replace_host(package, pieces, lambda h: h["causes"].append(cause))
    with pytest.raises(ContractError):
        package_check(package, pieces, payloads, outputs)


from dataclasses import replace
from company_os.sandbox.model import (
    CoreState,
    EventKind,
    Lifecycle,
    Result,
    Cause,
    evaluate_transition,
    evaluate_retry,
    reduce_causes,
)
from test_sandbox_s1_model import state, context, event, retry_state


@pytest.mark.parametrize("field,value", [("authority_valid", "false"), ("now_ns", -1)])
def test_security_forged_context_is_not_trusted(field, value):
    supplied = context()
    object.__setattr__(supplied, field, value)
    with pytest.raises(ContractError):
        evaluate_transition(state(), event(), supplied)


def test_security_empty_reduction_still_checks_state():
    supplied = state()
    object.__setattr__(supplied, "invalidated", True)
    with pytest.raises(ContractError):
        reduce_causes(supplied, (), limits=limits())


def test_security_nested_forged_cause_revalidated():
    observation = event(EventKind.INVALIDATE, code="AUTHORIZATION_CHANGED")
    object.__setattr__(observation.cause, "code", "UNRECOGNIZED")
    with pytest.raises(ContractError):
        evaluate_transition(state(), observation, context())


@pytest.mark.parametrize("kind", [EventKind.PUBLISH, EventKind.SEAL, EventKind.RETRY])
def test_security_unrelated_event_cannot_drive_initial_progression(kind):
    decision = evaluate_transition(state(), event(kind), context())
    assert decision.allowed is False
    assert decision.next_state.lifecycle is Lifecycle.REQUESTED


def test_security_irreversible_latch_survives_good_facts_and_retry():
    invalid = evaluate_transition(
        state(),
        event(EventKind.INVALIDATE, code="AUTHORIZATION_CHANGED"),
        context(absence_proven=False),
    ).next_state
    decision = evaluate_transition(invalid, event(seq=2, tick=2), context())
    assert decision.next_state.invalidated is True
    assert decision.next_state.result is Result.INVALIDATED
    assert evaluate_retry(invalid, context()).allowed is False


@pytest.mark.parametrize("slot", ["pieces", "payloads", "outputs"])
def test_security_valid_package_still_rejects_untrusted_dictionary(slot):
    package, pieces, payloads, outputs = make_package()
    inputs = dict(pieces=pieces, payloads=payloads, outputs=outputs)
    inputs[slot] = CallbackDict(inputs[slot])
    raw = encode(package)
    with pytest.raises(ContractError, match="OWNED_MAPPING"):
        check_package_consistency(
            raw,
            expected_digest=digest(raw),
            now=datetime(2026, 10, 15, 12, 0, tzinfo=timezone.utc),
            limits=S1SyntheticLimits(8388608, 33554432, 12, 256, 64, 256),
            **inputs,
        )


@pytest.mark.parametrize(
    "lifecycle,started",
    [
        ("RUNNING", False),
        ("COLLECTING", False),
        ("REQUESTED", True),
        ("PREFLIGHT", True),
        ("CAPTURING", True),
        ("PREPARING", True),
        ("READY", True),
    ],
)
def test_security_live_state_rejects_impossible_start_dimensions(lifecycle, started):
    package, _, _, _ = make_package(False)
    value = {
        "schema": "aico.sandbox.live-state.v1",
        "identity": package["identity"],
        "lifecycle_state": lifecycle,
        "execution_result": "PENDING",
        "resource_state": "NONE",
        "started_untrusted_code": started,
        "generation": 0,
        "retry_count": 0,
        "retry_resolution": None,
        "invalidation_latched": False,
        "causes": [],
        "journal_epoch": package["broker_epoch"],
        "version": 1,
    }
    raw = encode(value)
    with pytest.raises(ContractError):
        decode_piece(
            raw, expected_digest=digest(raw), kind="live-state", limits=limits()
        )


def test_security_live_completed_requires_code_started():
    package, _, _, _ = make_package(False)
    value = {
        "schema": "aico.sandbox.live-state.v1",
        "identity": package["identity"],
        "lifecycle_state": "REVALIDATING",
        "execution_result": "COMPLETED",
        "resource_state": "CLEANUP_CONFIRMED",
        "started_untrusted_code": False,
        "generation": 0,
        "retry_count": 0,
        "retry_resolution": None,
        "invalidation_latched": False,
        "causes": [],
        "journal_epoch": package["broker_epoch"],
        "version": 1,
    }
    raw = encode(value)
    with pytest.raises(ContractError):
        decode_piece(
            raw, expected_digest=digest(raw), kind="live-state", limits=limits()
        )


def test_security_preexisting_invalidating_cause_cannot_hide_in_state():
    with pytest.raises(ContractError):
        state(
            lifecycle=Lifecycle.REVALIDATING,
            result=Result.COMPLETED,
            started=True,
            sequence=1,
            tick_ns=1,
            causes=(Cause("AUTHORIZATION_CHANGED", 1, 1, 0),),
        )
