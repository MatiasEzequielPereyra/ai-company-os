"""Orchestrator B P1 reproductions: hostile limits and live cause invariants."""

import json

import pytest

from company_os.sandbox.codecs import decode_piece, check_package_consistency
from company_os.sandbox.contracts import ContractError, sha256
from company_os.sandbox.puretypes import S1SyntheticLimits
from test_sandbox_s1_codecs import E, LIMITS, make_package


def live():
    package, _, _, _ = make_package()
    return dict(
        schema="aico.sandbox.live-state.v1",
        identity=package["identity"],
        lifecycle_state="COLLECTING",
        execution_result="COMPLETED",
        resource_state="POSSIBLY_ACTIVE",
        started_untrusted_code=True,
        generation=0,
        retry_count=0,
        retry_resolution=None,
        invalidation_latched=False,
        causes=[],
        journal_epoch=E,
        version=5,
    )


def decode(value, *, limits=LIMITS):
    raw = json.dumps(value, separators=(",", ":")).encode()
    return decode_piece(
        raw, expected_digest=sha256(raw), kind="live-state", limits=limits
    )


@pytest.mark.parametrize(
    "name,ceiling",
    [
        ("piece_bytes", 8388608),
        ("total_bytes", 33554432),
        ("depth", 12),
        ("items", 256),
        ("pieces", 64),
        ("events", 256),
    ],
)
@pytest.mark.parametrize("bad", [0, -1, True, "1", "over"])
@pytest.mark.parametrize("entry", ["decode", "package"])
def test_combined_limits_field_and_method_tampering(name, ceiling, bad, entry):
    limits = S1SyntheticLimits(8388608, 33554432, 12, 256, 64, 256)
    object.__setattr__(limits, name, ceiling + 1 if bad == "over" else bad)
    called = []
    object.__setattr__(limits, "__post_init__", lambda: called.append(True))
    with pytest.raises(ContractError, match="S1_LIMIT_CONFIGURATION"):
        if entry == "decode":
            decode(live(), limits=limits)
        else:
            check_package_consistency(
                b"{}",
                expected_digest=sha256(b"{}"),
                pieces={},
                payloads={},
                outputs={},
                now=None,
                limits=limits,
            )
    assert called == []


def test_valid_limits_ignore_untrusted_instance_validation_method():
    limits = S1SyntheticLimits(8388608, 33554432, 12, 256, 64, 256)
    called = []
    object.__setattr__(limits, "__post_init__", lambda: called.append(True))
    decode(live(), limits=limits)
    assert called == []


@pytest.mark.parametrize(
    "code,result",
    [
        ("AUTHORIZATION_CHANGED", "COMPLETED"),
        ("AUTHORIZATION_CHANGED", "FAILED"),
        ("DEADLINE_EXCEEDED", "COMPLETED"),
        ("DEADLINE_EXCEEDED", "CANCELLED"),
        ("CANCEL_REQUESTED", "COMPLETED"),
        ("CANCEL_REQUESTED", "FAILED"),
        ("OPERATION_FAILED", "COMPLETED"),
        ("OPERATION_FAILED", "PENDING"),
    ],
)
def test_live_result_cannot_contradict_active_cause(code, result):
    v = live()
    v["execution_result"] = result
    v["causes"] = [dict(code=code, generation=0, event_sequence=1, observed_tick=0)]
    with pytest.raises(ContractError):
        decode(v)


def test_live_causes_cannot_come_from_future_generation():
    v = live()
    v["execution_result"] = "FAILED"
    c = dict(code="OPERATION_FAILED", generation=0, event_sequence=1, observed_tick=0)
    c["generation"] = 1
    v["causes"] = [c]
    with pytest.raises(ContractError):
        decode(v)


def test_live_event_sequence_is_independent_of_cas_version():
    # Historical section 4.2 does not equate CAS version and journal sequence.
    v = live()
    v["execution_result"] = "FAILED"
    v["causes"] = [
        dict(code="OPERATION_FAILED", generation=0, event_sequence=6, observed_tick=0)
    ]
    piece = decode(v)
    assert piece.value["version"] == 5
    assert piece.value["causes"][0]["event_sequence"] == 6


def retry_live(result="COMPLETED"):
    v = live()
    v.update(generation=1, retry_count=1, execution_result=result)
    v["causes"] = [
        dict(
            code="PRE_RUN_TRANSPORT_FAILURE",
            generation=0,
            event_sequence=1,
            observed_tick=0,
        )
    ]
    v["retry_resolution"] = dict(
        cause_event_sequence=1,
        retry_commit_sequence=2,
        from_generation=0,
        to_generation=1,
        request_sha256="a" * 64,
    )
    return v


def test_exact_resolved_retry_cause_is_compatible_with_completed_live_state():
    decode(retry_live())


def test_second_transport_cause_is_not_cleared_by_retry_resolution():
    v = retry_live()
    v["causes"].append(
        dict(
            code="PRE_RUN_TRANSPORT_FAILURE",
            generation=1,
            event_sequence=3,
            observed_tick=0,
        )
    )
    with pytest.raises(ContractError):
        decode(v)


def test_retry_commit_sequence_is_independent_of_live_cas_version():
    v = retry_live()
    v["retry_resolution"]["retry_commit_sequence"] = 6
    piece = decode(v)
    assert piece.value["version"] == 5
    assert piece.value["retry_resolution"]["retry_commit_sequence"] == 6
    # Preserve the real ordering guard: a retry commit must follow its cause.
    v["retry_resolution"]["retry_commit_sequence"] = 1
    with pytest.raises(ContractError):
        decode(v)


def test_generation_zero_pending_transport_exception_remains_valid():
    v = live()
    v.update(
        lifecycle_state="CLEANUP_VERIFY",
        execution_result="PENDING",
        resource_state="CLEANUP_CONFIRMED",
        started_untrusted_code=False,
    )
    v["causes"] = [
        dict(
            code="PRE_RUN_TRANSPORT_FAILURE",
            generation=0,
            event_sequence=1,
            observed_tick=0,
        )
    ]
    decode(v)


@pytest.mark.parametrize(
    "codes,result",
    [
        (["OPERATION_FAILED"], "FAILED"),
        (["OPERATION_FAILED", "CANCEL_REQUESTED"], "CANCELLED"),
        (["CANCEL_REQUESTED", "DEADLINE_EXCEEDED"], "TIMED_OUT"),
        (["DEADLINE_EXCEEDED", "AUTHORIZATION_CHANGED"], "INVALIDATED"),
    ],
)
def test_live_cause_precedence_valid_positive_controls(codes, result):
    v = live()
    v.update(execution_result=result, invalidation_latched=result == "INVALIDATED")
    v["causes"] = [
        dict(code=code, generation=0, event_sequence=i, observed_tick=0)
        for i, code in enumerate(codes, 1)
    ]
    decode(v)


def test_excessive_json_integer_is_a_contract_error():
    raw = b'{"version":' + b"9" * 5000 + b"}"
    with pytest.raises(ContractError):
        decode_piece(raw, expected_digest=sha256(raw), kind="live-state", limits=LIMITS)
