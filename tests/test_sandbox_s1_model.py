"""Literal mapping oracles and deterministic fake observations, not OS certification."""

from dataclasses import replace, fields
from itertools import product
import pytest
from company_os.sandbox.contracts import ContractError
from company_os.sandbox.model import *
from company_os.sandbox.puretypes import S1SyntheticLimits

EPOCH = "11111111-1111-4111-8111-111111111111"
DIGEST = "a" * 64
LIMITS = S1SyntheticLimits(4096, 32768, 8, 64, 16, 64)


def state(**kw):
    values = dict(
        lifecycle=Lifecycle.REQUESTED,
        result=Result.PENDING,
        resources=Resources.NONE,
        epoch=EPOCH,
        sequence=0,
        tick_ns=0,
        generation=0,
        retry_count=0,
        started=False,
        invalidated=False,
        causes=(),
        retry_resolution=None,
        request_sha256=DIGEST,
    )
    values.update(kw)
    return CoreState(**values)


def context(**kw):
    values = {f.name: True for f in fields(Context)}
    values.update(
        close_failure=False,
        ownership_ambiguous=False,
        commands_complete=False,
        collection_complete=False,
        collection_expired=False,
        commit_uncertain=False,
        start_committed=False,
        code_send_uncertain=False,
        restarted=False,
        subphase=Subphase.NONE,
        capture_elapsed_ns=0,
        prepare_elapsed_ns=0,
        first_close_elapsed_ns=0,
        planned_work_ns=1,
        now_ns=0,
        expires_ns=500_000_000_000,
        request_sha256=DIGEST,
    )
    values.update(kw)
    return Context(**values)


def event(kind=EventKind.ADVANCE, seq=1, tick=1, code=None, generation=0, epoch=EPOCH):
    return Event(
        kind, epoch, seq, tick, Cause(code, seq, tick, generation) if code else None
    )


def retry_state():
    return state(
        lifecycle=Lifecycle.CLEANUP_VERIFY,
        resources=Resources.CLEANUP_CONFIRMED,
        sequence=1,
        tick_ns=1,
        causes=(Cause("PRE_RUN_TRANSPORT_FAILURE", 1, 1, 0),),
    )


@pytest.mark.parametrize(
    "s,c,e,row,target",
    [
        (
            state(lifecycle=Lifecycle.QUARANTINED),
            context(),
            event(),
            "D1",
            Lifecycle.QUARANTINED,
        ),
        (state(), context(close_failure=True), event(), "D2", Lifecycle.QUARANTINED),
        (state(result=Result.FAILED), context(), event(), "D3", Lifecycle.REJECTED),
        (
            state(result=Result.FAILED),
            context(absence_proven=False, power_off_confirmed=False),
            event(),
            "D4",
            Lifecycle.STOPPING,
        ),
        (
            state(lifecycle=Lifecycle.REVALIDATING, result=Result.FAILED),
            context(cleanup_confirmed=False),
            event(),
            "D5",
            Lifecycle.DESTROYING,
        ),
        (state(), context(), event(), "MAP_D6", Lifecycle.PREFLIGHT),
        (
            state(lifecycle=Lifecycle.CAPTURING),
            context(),
            event(),
            "D7",
            Lifecycle.PREPARING,
        ),
        (
            state(lifecycle=Lifecycle.RUNNING, started=True),
            context(),
            event(),
            "D8",
            Lifecycle.RUNNING,
        ),
        (
            state(lifecycle=Lifecycle.RUNNING, started=True),
            context(commands_complete=True),
            event(),
            "D9",
            Lifecycle.COLLECTING,
        ),
        (
            state(lifecycle=Lifecycle.COLLECTING, started=True),
            context(collection_complete=True),
            event(),
            "D10",
            Lifecycle.STOPPING,
        ),
        (
            state(lifecycle=Lifecycle.COLLECTING, started=True),
            context(),
            event(),
            "D11",
            Lifecycle.COLLECTING,
        ),
        (
            state(lifecycle=Lifecycle.STOPPING),
            context(),
            event(),
            "D12",
            Lifecycle.DESTROYING,
        ),
        (
            state(
                lifecycle=Lifecycle.REVALIDATING, started=True, result=Result.COMPLETED
            ),
            context(subphase=Subphase.CAPTURE_PENDING),
            event(),
            "D13",
            Lifecycle.REVALIDATING,
        ),
        (
            state(
                lifecycle=Lifecycle.REVALIDATING,
                started=True,
                result=Result.COMPLETED,
                resources=Resources.CLEANUP_CONFIRMED,
            ),
            context(subphase=Subphase.FINAL_GATE),
            event(EventKind.SEAL),
            "D14",
            Lifecycle.SEALED,
        ),
        (
            state(
                lifecycle=Lifecycle.REVALIDATING, started=True, result=Result.COMPLETED
            ),
            context(subphase=Subphase.FINAL_GATE, monitor_valid=False),
            event(),
            "D15",
            Lifecycle.REVALIDATING,
        ),
        (
            state(
                lifecycle=Lifecycle.REVALIDATING,
                result=Result.FAILED,
                resources=Resources.CLEANUP_CONFIRMED,
            ),
            context(),
            event(EventKind.SEAL),
            "D16",
            Lifecycle.SEALED,
        ),
        (
            state(
                lifecycle=Lifecycle.REVALIDATING,
                result=Result.CANCELLED,
                resources=Resources.CLEANUP_CONFIRMED,
            ),
            context(),
            event(EventKind.SEAL),
            "D17",
            Lifecycle.SEALED,
        ),
        (
            state(
                lifecycle=Lifecycle.REVALIDATING,
                result=Result.TIMED_OUT,
                resources=Resources.CLEANUP_CONFIRMED,
            ),
            context(),
            event(EventKind.SEAL),
            "D18",
            Lifecycle.SEALED,
        ),
        (
            state(
                lifecycle=Lifecycle.REVALIDATING,
                result=Result.INVALIDATED,
                invalidated=True,
                resources=Resources.CLEANUP_CONFIRMED,
            ),
            context(),
            event(EventKind.SEAL),
            "D19",
            Lifecycle.SEALED,
        ),
        (
            state(lifecycle=Lifecycle.REVALIDATING),
            context(),
            event(),
            "D20",
            Lifecycle.REVALIDATING,
        ),
    ],
)
def test_literal_mapping_rows(s, c, e, row, target):
    d = evaluate_transition(s, e, c)
    assert d.rule == row and d.next_state.lifecycle == target
    assert d.scope == "SIMULATION" and not d.operational


def test_cartesian_partition_constructor_or_unique_closed_rule():
    checked = rejected = 0
    for lc, res, rs, started, latch, generation in product(
        Lifecycle, Result, Resources, (False, True), (False, True), (0, 1)
    ):
        # Independent oracle: explicit semantic facts, not the implementation helper.
        valid = latch == (res is Result.INVALIDATED)
        valid &= lc not in (Lifecycle.RUNNING, Lifecycle.COLLECTING) or started
        valid &= (
            lc
            not in (
                Lifecycle.REQUESTED,
                Lifecycle.PREFLIGHT,
                Lifecycle.CAPTURING,
                Lifecycle.PREPARING,
                Lifecycle.READY,
            )
            or not started
        )
        valid &= res is not Result.COMPLETED or started
        valid &= lc not in (Lifecycle.SEALED, Lifecycle.PUBLISHED) or (
            res is not Result.PENDING and rs is Resources.CLEANUP_CONFIRMED
        )
        valid &= lc is not Lifecycle.REJECTED or (
            not started and rs is Resources.NONE and res is not Result.PENDING
        )
        kw = dict(
            lifecycle=lc,
            result=res,
            resources=rs,
            started=started,
            invalidated=latch,
            generation=generation,
            retry_count=generation,
        )
        if generation:
            kw.update(
                sequence=2,
                tick_ns=2,
                causes=(Cause("PRE_RUN_TRANSPORT_FAILURE", 1, 1, 0),),
                retry_resolution=RetryResolution(1, 2, 0, 1, DIGEST),
            )
        if not valid:
            with pytest.raises(ContractError):
                state(**kw)
            rejected += 1
            continue
        s = state(**kw)
        d = evaluate_transition(
            s, event(seq=s.sequence + 1, tick=s.tick_ns + 1), context()
        )
        assert d.rule in RULES and type(d.allowed) is bool
        assert not d.operational
        assert not (
            d.next_state.result is Result.COMPLETED and not d.next_state.started
        )
        assert d.next_state.invalidated == (d.next_state.result is Result.INVALIDATED)
        if latch:
            assert d.next_state.invalidated
        if lc in (Lifecycle.SEALED, Lifecycle.PUBLISHED, Lifecycle.REJECTED):
            assert d.rule == "B_TERMINAL" and d.next_state is s
        elif rs in (
            Resources.POSSIBLY_ACTIVE,
            Resources.PREPARED,
            Resources.PARTIAL_CREATION,
            Resources.DESTRUCTION_PENDING,
        ):
            assert d.rule == "A_REJECT" and not d.allowed
        elif lc in (Lifecycle.QUARANTINED, Lifecycle.RECOVERING):
            assert d.rule == "D1" and not d.allowed
        checked += 1
    assert checked + rejected == 6144 and checked > 100 and rejected > 100


@pytest.mark.parametrize(
    "field,value",
    [
        ("authority_valid", False),
        ("lease_valid", False),
        ("owner_valid", False),
        ("monitor_valid", False),
        ("continuity_valid", False),
        ("fence_valid", False),
        ("request_unchanged", False),
        ("request_sha256", "b" * 64),
        ("cleanup_confirmed", False),
        ("start_committed", True),
        ("code_send_uncertain", True),
        ("restarted", True),
        ("commit_uncertain", True),
        ("close_failure", True),
        ("ownership_ambiguous", True),
        ("now_ns", 500_000_000_000),
        ("capture_elapsed_ns", 120_000_000_000),
        ("prepare_elapsed_ns", 180_000_000_000),
        ("first_close_elapsed_ns", 350_000_000_000),
    ],
)
def test_every_retry_context_guard(field, value):
    kw = {field: value}
    if field == "commit_uncertain":
        kw["commit_confirmed"] = False
    assert not evaluate_retry(retry_state(), context(**kw)).allowed


def test_retry_single_commit_and_transport_resolution():
    s = retry_state()
    c = context()
    d = evaluate_retry(s, c)
    assert d.allowed and d.next_state.generation == 1 and d.next_state.retry_count == 1
    assert d.next_state.causes == s.causes and d.next_state.result is Result.PENDING
    assert not evaluate_retry(d.next_state, c).allowed
    assert not evaluate_retry(s, context(commit_confirmed=False)).allowed
    e = event(EventKind.RETRY, seq=4, tick=9)
    result = evaluate_transition(s, e, c).next_state
    assert result.sequence == 4 and result.retry_resolution.retry_commit_sequence == 4
    assert result.retry_resolution.cause_event_sequence == 1
    running = replace(result, lifecycle=Lifecycle.RUNNING, started=True)
    completed = reduce_causes(
        running, (event(EventKind.COMPLETE, seq=5, tick=10),), limits=LIMITS
    )
    assert completed.result is Result.COMPLETED


@pytest.mark.parametrize(
    "updates",
    [
        {"started": True},
        {"result": Result.FAILED},
        {"resources": Resources.PREPARED},
        {"lifecycle": Lifecycle.DESTROYING},
    ],
)
def test_retry_state_guards(updates):
    assert not evaluate_retry(replace(retry_state(), **updates), context()).allowed


def test_retry_deadlines_exact_and_one_nanosecond_boundary():
    assert evaluate_retry(
        retry_state(),
        context(
            capture_elapsed_ns=119_999_999_999,
            prepare_elapsed_ns=179_999_999_999,
            first_close_elapsed_ns=349_999_999_999,
        ),
    ).allowed
    assert not evaluate_retry(retry_state(), context(expires_ns=0)).allowed


def test_irreversible_latch_precedence_and_reordered_rejection():
    s = state()
    events = (
        event(EventKind.CANCEL, code="CANCEL_REQUESTED"),
        event(EventKind.DEADLINE, seq=2, tick=2, code="DEADLINE_EXCEEDED"),
        event(EventKind.INVALIDATE, seq=3, tick=3, code="AUTHORIZATION_CHANGED"),
    )
    reduced = FakeJournal(events).replay(s, limits=LIMITS)
    assert reduced.result is Result.INVALIDATED and len(reduced.causes) == 3
    result = reduce_causes(reduced, (event(seq=4, tick=4),), limits=LIMITS)
    assert result.invalidated and result.result is Result.INVALIDATED
    for bad in (
        events[0],
        event(seq=4, tick=2),
        event(seq=4, tick=4, epoch="22222222-2222-4222-8222-222222222222"),
    ):
        with pytest.raises(ContractError):
            reduce_causes(reduced, (bad,), limits=LIMITS)


@pytest.mark.parametrize(
    "kind,code",
    [
        (EventKind.JOURNAL_FAILURE, "JOURNAL_UNAVAILABLE"),
        (EventKind.COMMIT_FAILURE, "PERSISTENCE_FAILED"),
    ],
)
def test_fake_failures_latch_independent_of_commit(kind, code):
    d = evaluate_transition(
        state(lifecycle=Lifecycle.RUNNING, started=True),
        event(kind, code=code),
        context(
            commit_confirmed=False, absence_proven=False, power_off_confirmed=False
        ),
    )
    assert d.next_state.invalidated and d.next_state.result is Result.INVALIDATED
    assert not d.allowed and "STOP" in d.effects


def test_terminal_observations_do_not_rewrite_and_publish_is_separate():
    s = state(
        lifecycle=Lifecycle.SEALED,
        started=True,
        result=Result.COMPLETED,
        resources=Resources.CLEANUP_CONFIRMED,
    )
    d = evaluate_transition(
        s, event(EventKind.INVALIDATE, code="AUTHORIZATION_CHANGED"), context()
    )
    assert d.next_state is s and d.rule == "B_TERMINAL"
    assert not evaluate_transition(
        s, event(EventKind.PUBLISH), context(authority_valid=False)
    ).allowed
    published = evaluate_transition(s, event(EventKind.PUBLISH), context()).next_state
    assert published.lifecycle is Lifecycle.PUBLISHED and published.result is s.result
    assert published.causes == s.causes and published.sequence == s.sequence


def test_final_capture_requires_fresh_cleanup_and_no_early_seal():
    s = state(
        lifecycle=Lifecycle.REVALIDATING,
        started=True,
        result=Result.COMPLETED,
        resources=Resources.CLEANUP_CONFIRMED,
    )
    d = evaluate_transition(s, event(), context(subphase=Subphase.CAPTURE_PENDING))
    assert d.next_state.resources is Resources.PARTIAL_CREATION
    assert not evaluate_transition(
        d.next_state,
        event(seq=2, tick=2),
        context(subphase=Subphase.FINAL_GATE, cleanup_confirmed=False),
    ).allowed


@pytest.mark.parametrize(
    "factory",
    [
        lambda: state(started=1),
        lambda: state(sequence=True),
        lambda: state(epoch="0" * 36),
        lambda: state(invalidated=True),
        lambda: state(lifecycle=Lifecycle.SEALED),
        lambda: context(lease_valid=1),
        lambda: context(commit_uncertain=True),
        lambda: Cause("UNREVIEWED", 1, 1, 0),
        lambda: event(EventKind.CANCEL),
    ],
)
def test_closed_strict_record_construction(factory):
    with pytest.raises(ContractError):
        factory()


@pytest.mark.parametrize(
    "field",
    [
        "authority_valid",
        "lease_valid",
        "owner_valid",
        "monitor_valid",
        "continuity_valid",
        "fence_valid",
    ],
)
def test_running_invalid_facts_never_keep_success(field):
    d = evaluate_transition(
        state(lifecycle=Lifecycle.RUNNING, started=True),
        event(),
        context(
            **{field: False, "absence_proven": False, "power_off_confirmed": False}
        ),
    )
    assert d.next_state.invalidated and d.next_state.result is Result.INVALIDATED
    assert d.rule == "D4" and d.effects == ("STOP",)


@pytest.mark.parametrize(
    "lc", [Lifecycle.REQUESTED, Lifecycle.CAPTURING, Lifecycle.RUNNING]
)
def test_publish_event_cannot_drive_nonterminal(lc):
    d = evaluate_transition(
        state(lifecycle=lc, started=lc is Lifecycle.RUNNING),
        event(EventKind.PUBLISH),
        context(),
    )
    assert not d.allowed and d.rule == "D20"


@pytest.mark.parametrize(
    "field,value", [("authority_valid", "false"), ("lease_valid", 1), ("now_ns", True)]
)
def test_forged_context_revalidated(field, value):
    c = context()
    object.__setattr__(c, field, value)
    with pytest.raises(ContractError):
        evaluate_transition(state(), event(), c)


def test_empty_reduction_validates_forged_state_and_nested_records():
    s = state()
    object.__setattr__(s, "invalidated", "false")
    with pytest.raises(ContractError):
        reduce_causes(s, (), limits=LIMITS)
    s = retry_state()
    object.__setattr__(s.causes[0], "code", "INJECTED")
    with pytest.raises(ContractError):
        reduce_causes(s, (), limits=LIMITS)


@pytest.mark.parametrize("bad", [True, -1, 2**64, "1"])
def test_invalid_time_and_sequence_types(bad):
    with pytest.raises(ContractError):
        event(seq=bad)


def test_missing_authority_expiry_and_digest_prevent_seal():
    s = state(
        lifecycle=Lifecycle.REVALIDATING,
        started=True,
        result=Result.COMPLETED,
        resources=Resources.CLEANUP_CONFIRMED,
    )
    for c in (
        context(now_ns=500_000_000_000),
        context(request_sha256="b" * 64),
        context(request_unchanged=False),
    ):
        d = evaluate_transition(
            s, event(EventKind.SEAL), replace(c, subphase=Subphase.FINAL_GATE)
        )
        assert (
            d.next_state.lifecycle is not Lifecycle.SEALED and d.next_state.invalidated
        )


@pytest.mark.parametrize("extra", ["preflight_valid", "capacity_valid"])
def test_retry_additional_admission_guards(extra):
    assert not evaluate_retry(retry_state(), context(**{extra: False})).allowed


def test_uncertain_retry_commit_latches_and_cannot_be_retried():
    d = evaluate_retry(
        retry_state(), context(commit_confirmed=False, commit_uncertain=True)
    )
    assert not d.allowed and d.next_state.invalidated
    assert not evaluate_retry(d.next_state, context()).allowed


@pytest.mark.parametrize("lc", [Lifecycle.RUNNING, Lifecycle.COLLECTING])
def test_execution_lifecycle_requires_actual_start(lc):
    with pytest.raises(ContractError):
        state(lifecycle=lc, started=False)


@pytest.mark.parametrize(
    "lc",
    [
        Lifecycle.REQUESTED,
        Lifecycle.PREFLIGHT,
        Lifecycle.CAPTURING,
        Lifecycle.PREPARING,
        Lifecycle.READY,
    ],
)
def test_pre_execution_lifecycle_cannot_claim_started(lc):
    with pytest.raises(ContractError):
        state(lifecycle=lc, started=True)


def test_completed_requires_start_but_precode_closure_is_valid():
    with pytest.raises(ContractError):
        state(lifecycle=Lifecycle.REVALIDATING, result=Result.COMPLETED)
    for lc in (
        Lifecycle.STOPPING,
        Lifecycle.DESTROYING,
        Lifecycle.CLEANUP_VERIFY,
        Lifecycle.REVALIDATING,
    ):
        assert state(lifecycle=lc, result=Result.FAILED, started=False).started is False


def test_complete_event_cannot_fabricate_execution():
    with pytest.raises(ContractError):
        reduce_causes(state(), (event(EventKind.COMPLETE),), limits=LIMITS)


@pytest.mark.parametrize(
    "code,result",
    [
        ("AUTHORIZATION_CHANGED", Result.COMPLETED),
        ("JOURNAL_UNAVAILABLE", Result.PENDING),
        ("DEADLINE_EXCEEDED", Result.COMPLETED),
        ("DEADLINE_EXCEEDED", Result.CANCELLED),
        ("CANCEL_REQUESTED", Result.PENDING),
        ("OPERATION_FAILED", Result.COMPLETED),
        ("PRE_RUN_TRANSPORT_FAILURE", Result.COMPLETED),
    ],
)
def test_constructor_rejects_cause_result_dominance_conflicts(code, result):
    with pytest.raises(ContractError):
        state(
            lifecycle=Lifecycle.REVALIDATING,
            started=True,
            result=result,
            sequence=1,
            tick_ns=1,
            causes=(Cause(code, 1, 1, 0),),
        )


@pytest.mark.parametrize("query", [False, True])
def test_empty_reducer_and_query_reject_forged_cause_dominance(query):
    s = state(
        lifecycle=Lifecycle.REVALIDATING,
        started=True,
        result=Result.COMPLETED,
        sequence=1,
        tick_ns=1,
    )
    object.__setattr__(s, "causes", (Cause("AUTHORIZATION_CHANGED", 1, 1, 0),))
    with pytest.raises(ContractError):
        if query:
            evaluate_transition(s, event(EventKind.QUERY, seq=2, tick=2), context())
        else:
            reduce_causes(s, (), limits=LIMITS)
