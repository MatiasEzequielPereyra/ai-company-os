"""DR-2 generation chronology through the three public validation interfaces."""

import json

import pytest

from company_os.sandbox.codecs import decode_piece
from company_os.sandbox.contracts import ContractError, sha256
from company_os.sandbox.model import (
    CAUSE_CODES,
    INVALIDATING,
    Cause,
    CoreState,
    Lifecycle,
    Resources,
    Result,
    RetryResolution,
)
from test_sandbox_s1_codecs import E, LIMITS, make_package


def chronology(
    entry, sequence, *, code="OPERATION_FAILED", cas_version=1, resolved_only=False
):
    result = (
        "COMPLETED"
        if resolved_only
        else (
            "INVALIDATED"
            if code in INVALIDATING
            else (
                "TIMED_OUT"
                if code == "DEADLINE_EXCEEDED"
                else "CANCELLED" if code == "CANCEL_REQUESTED" else "FAILED"
            )
        )
    )
    causes = [
        dict(
            code="PRE_RUN_TRANSPORT_FAILURE",
            generation=0,
            event_sequence=1,
            observed_tick=1,
        )
    ]
    if not resolved_only:
        causes.append(
            dict(code=code, generation=1, event_sequence=sequence, observed_tick=7)
        )
    resolution = dict(
        cause_event_sequence=1,
        retry_commit_sequence=6,
        from_generation=0,
        to_generation=1,
        request_sha256="a" * 64,
    )
    if entry == "CoreState":
        return CoreState(
            lifecycle=Lifecycle.SEALED,
            result=Result(result),
            resources=Resources.CLEANUP_CONFIRMED,
            epoch=E,
            sequence=20,
            tick_ns=20,
            generation=1,
            retry_count=1,
            started=True,
            invalidated=result == "INVALIDATED",
            causes=tuple(Cause(**c) for c in causes),
            retry_resolution=RetryResolution(**resolution),
            request_sha256="a" * 64,
        )
    package, pieces, _, _ = make_package()
    if entry == "host-evidence":
        value = json.loads(pieces[package["host_evidence"]["sha256"]])
        value.update(
            execution_result=result,
            terminal_outcome=("ACCEPTED" if result == "COMPLETED" else result),
        )
    else:
        value = dict(
            schema="aico.sandbox.live-state.v1",
            identity=package["identity"],
            lifecycle_state="COLLECTING",
            execution_result=result,
            resource_state="POSSIBLY_ACTIVE",
            started_untrusted_code=True,
            journal_epoch=E,
            version=cas_version,
        )
    value.update(
        generation=1,
        retry_count=1,
        retry_resolution=resolution,
        invalidation_latched=result == "INVALIDATED",
        causes=causes,
    )
    raw = json.dumps(value, separators=(",", ":")).encode()
    return decode_piece(raw, expected_digest=sha256(raw), kind=entry, limits=LIMITS)


@pytest.mark.parametrize("entry", ["CoreState", "live-state", "host-evidence"])
@pytest.mark.parametrize("sequence", [2, 3, 5, 6])
def test_g1_cause_cannot_precede_or_share_generation_commit(entry, sequence):
    with pytest.raises(ContractError):
        chronology(entry, sequence)


@pytest.mark.parametrize("entry", ["CoreState", "live-state", "host-evidence"])
@pytest.mark.parametrize("code", sorted(CAUSE_CODES))
def test_every_g1_cause_requires_prior_generation_commit(entry, code):
    with pytest.raises(ContractError):
        chronology(entry, 3, code=code)


@pytest.mark.parametrize("entry", ["CoreState", "live-state", "host-evidence"])
@pytest.mark.parametrize("code", sorted(CAUSE_CODES))
def test_cause_after_generation_commit_is_valid(entry, code):
    assert chronology(entry, 7, code=code) is not None


@pytest.mark.parametrize("entry", ["CoreState", "live-state", "host-evidence"])
def test_exact_resolved_transport_retry_can_complete(entry):
    assert chronology(entry, 7, resolved_only=True) is not None


@pytest.mark.parametrize("version", [1, 5, 6, 100])
def test_live_cas_version_is_not_a_journal_sequence(version):
    piece = chronology("live-state", 7, cas_version=version)
    assert piece.value["version"] == version
    assert piece.value["retry_resolution"]["retry_commit_sequence"] == 6
    assert piece.value["causes"][1]["event_sequence"] == 7
