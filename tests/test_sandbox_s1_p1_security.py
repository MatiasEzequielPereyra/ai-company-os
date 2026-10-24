"""Independent corrective adversarial oracles; no operational authority."""

import pytest

from company_os.sandbox.contracts import ContractError
from company_os.sandbox.model import (
    CAUSE_CODES,
    INVALIDATING,
    EventKind,
    Lifecycle,
    Resources,
    Result,
    evaluate_retry,
    evaluate_transition,
)
from test_sandbox_s1_model import state, context, event, retry_state
from test_sandbox_s1_p1_codecs import live, decode


@pytest.mark.parametrize("code", sorted(CAUSE_CODES))
@pytest.mark.parametrize("result", ["PENDING", "COMPLETED"])
def test_security_no_active_cause_can_claim_completion_or_pending(code, result):
    wire = live()
    wire["execution_result"] = result
    wire["causes"] = [dict(code=code, generation=0, event_sequence=1, observed_tick=0)]
    # Literal DR-4b C: only pre-run transport may retain PENDING in g0.
    if code == "PRE_RUN_TRANSPORT_FAILURE" and result == "PENDING":
        decode(wire)
    else:
        with pytest.raises(ContractError):
            decode(wire)


@pytest.mark.parametrize("code", sorted(CAUSE_CODES))
def test_security_retry_keeps_every_current_event_cause(code):
    decision = evaluate_transition(
        retry_state(), event(EventKind.RETRY, seq=2, tick=2, code=code), context()
    )
    assert not decision.allowed
    assert decision.next_state.generation == 0
    assert decision.next_state.retry_count == 0
    assert any(
        c.code == code and c.event_sequence == 2 for c in decision.next_state.causes
    )
    if code in INVALIDATING:
        assert decision.next_state.invalidated
        assert decision.next_state.result is Result.INVALIDATED


@pytest.mark.parametrize(
    "lifecycle", [Lifecycle.SEALED, Lifecycle.PUBLISHED, Lifecycle.REJECTED]
)
def test_security_retry_uncertain_commit_preserves_terminal_exactly(lifecycle):
    terminal = state(
        lifecycle=lifecycle,
        result=Result.FAILED,
        resources=(
            Resources.NONE
            if lifecycle is Lifecycle.REJECTED
            else Resources.CLEANUP_CONFIRMED
        ),
    )
    decision = evaluate_retry(
        terminal, context(commit_uncertain=True, commit_confirmed=False)
    )
    assert not decision.allowed
    assert decision.next_state == terminal
    assert decision.effects == ("NO_EFFECT",)


def test_security_retry_uncertainty_is_not_a_write_before_retry_eligibility():
    before = state()
    decision = evaluate_retry(
        before, context(commit_uncertain=True, commit_confirmed=False)
    )
    assert not decision.allowed
    assert decision.next_state == before


def test_security_real_eligible_retry_uncertainty_still_invalidates():
    before = retry_state()
    decision = evaluate_retry(
        before, context(commit_uncertain=True, commit_confirmed=False)
    )
    assert not decision.allowed
    assert decision.next_state.result is Result.INVALIDATED
    assert decision.next_state.invalidated
    assert decision.next_state.generation == 0
    assert any(c.code == "PERSISTENCE_FAILED" for c in decision.next_state.causes)
