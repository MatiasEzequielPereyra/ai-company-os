"""Corrective retry regressions against literal DR-4b cause and terminal rules."""

from dataclasses import replace
import pytest
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


@pytest.mark.parametrize("code", sorted(CAUSE_CODES))
def test_retry_event_keeps_every_current_cause_and_closes_retry(code):
    before = retry_state()
    current = event(EventKind.RETRY, seq=2, tick=2, code=code)
    decision = evaluate_transition(before, current, context())
    assert not decision.allowed
    assert decision.next_state.generation == 0
    assert decision.next_state.retry_count == 0
    assert decision.next_state.retry_resolution is None
    assert decision.next_state.causes == before.causes + (current.cause,)
    assert decision.next_state.sequence == current.sequence
    assert decision.next_state.tick_ns == current.tick_ns
    if code in INVALIDATING:
        assert decision.next_state.result is Result.INVALIDATED
        assert decision.next_state.invalidated
    assert decision.effects == ("NO_EFFECT",)


@pytest.mark.parametrize(
    "lifecycle", [Lifecycle.SEALED, Lifecycle.PUBLISHED, Lifecycle.REJECTED]
)
def test_uncertain_retry_never_mutates_terminal_state(lifecycle):
    before = state(
        lifecycle=lifecycle,
        result=Result.FAILED,
        resources=(
            Resources.NONE
            if lifecycle is Lifecycle.REJECTED
            else Resources.CLEANUP_CONFIRMED
        ),
    )
    decision = evaluate_retry(
        before, context(commit_confirmed=False, commit_uncertain=True)
    )
    assert not decision.allowed
    assert decision.next_state == before
    assert decision.effects == ("NO_EFFECT",)


@pytest.mark.parametrize(
    "change",
    [
        {"lifecycle": Lifecycle.DESTROYING},
        {"resources": Resources.DESTRUCTION_PENDING},
        {"result": Result.FAILED},
    ],
)
def test_uncertain_commit_without_eligible_retry_does_not_invent_transaction(change):
    before = replace(retry_state(), **change)
    decision = evaluate_retry(
        before, context(commit_confirmed=False, commit_uncertain=True)
    )
    assert not decision.allowed
    assert decision.next_state == before


def test_uncertain_commit_for_eligible_retry_latches_persistence_failure():
    before = retry_state()
    decision = evaluate_retry(
        before, context(commit_confirmed=False, commit_uncertain=True)
    )
    assert not decision.allowed
    assert decision.next_state.result is Result.INVALIDATED
    assert decision.next_state.invalidated
    assert decision.next_state.generation == 0
    assert decision.next_state.causes[:-1] == before.causes
    assert decision.next_state.causes[-1].code == "PERSISTENCE_FAILED"
    assert not evaluate_retry(decision.next_state, context()).allowed


@pytest.mark.parametrize(
    "guard",
    [
        {"authority_valid": False},
        {"lease_valid": False},
        {"owner_valid": False},
        {"monitor_valid": False},
        {"continuity_valid": False},
        {"fence_valid": False},
        {"preflight_valid": False},
        {"capacity_valid": False},
        {"cleanup_confirmed": False},
        {"request_unchanged": False},
        {"start_committed": True},
        {"code_send_uncertain": True},
        {"restarted": True},
        {"close_failure": True},
        {"ownership_ambiguous": True},
        {"now_ns": 500_000_000_000},
        {"request_sha256": "b" * 64},
        {"capture_elapsed_ns": 120_000_000_000},
        {"prepare_elapsed_ns": 180_000_000_000},
        {"first_close_elapsed_ns": 350_000_000_000},
    ],
)
def test_uncertain_commit_only_applies_after_all_retry_eligibility_guards(guard):
    before = retry_state()
    decision = evaluate_retry(
        before,
        context(
            commit_confirmed=False,
            commit_uncertain=True,
            **guard,
        ),
    )
    assert not decision.allowed
    assert decision.next_state == before
    assert decision.effects == ("NO_EFFECT",)
