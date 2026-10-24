"""Deterministic S1 simulation. No record or fake observation authenticates a host."""

from __future__ import annotations
from dataclasses import dataclass, replace, fields
from enum import Enum
from uuid import UUID
import re
from .contracts import ContractError
from .puretypes import S1SyntheticLimits

CAUSE_CODES = frozenset(
    "AUTHORIZATION_CHANGED AUTHORIZATION_EXPIRED DEPENDENCY_CHANGED CANONICAL_SOURCE_AMBIGUOUS AUTHORITY_MONITOR_FAILED AUTHORITY_MONITOR_STALE AUTHORITY_JOURNAL_GAP LEASE_LOST OWNER_LOST HOST_RESTARTED TIME_DISCONTINUITY SOURCE_CHANGED GIT_COHERENCE_FAILED GUEST_RESULT_INVALID OUTPUT_LIMIT RESOURCE_LIMIT OPERATION_FAILED PREFLIGHT_FAILED PROFILE_NOT_CERTIFIED REQUEST_CONFLICT CANCEL_REQUESTED DEADLINE_EXCEEDED PRE_RUN_TRANSPORT_FAILURE POWER_STATE_UNCONFIRMED DESTRUCTION_INCOMPLETE CLEANUP_UNPROVEN OWNERSHIP_AMBIGUOUS JOURNAL_UNAVAILABLE PERSISTENCE_FAILED RETRY_NOT_ALLOWED RETENTION_UNCONFIGURED EVIDENCE_QUOTA EVIDENCE_ROLLBACK PUBLICATION_FENCE_UNAVAILABLE".split()
)
INVALIDATING = frozenset(
    "AUTHORIZATION_CHANGED AUTHORIZATION_EXPIRED DEPENDENCY_CHANGED CANONICAL_SOURCE_AMBIGUOUS AUTHORITY_MONITOR_FAILED AUTHORITY_MONITOR_STALE AUTHORITY_JOURNAL_GAP LEASE_LOST OWNER_LOST HOST_RESTARTED TIME_DISCONTINUITY SOURCE_CHANGED GIT_COHERENCE_FAILED GUEST_RESULT_INVALID JOURNAL_UNAVAILABLE PERSISTENCE_FAILED EVIDENCE_ROLLBACK PUBLICATION_FENCE_UNAVAILABLE".split()
)


class Lifecycle(str, Enum):
    REQUESTED = "REQUESTED"
    PREFLIGHT = "PREFLIGHT"
    CAPTURING = "CAPTURING"
    PREPARING = "PREPARING"
    READY = "READY"
    RUNNING = "RUNNING"
    COLLECTING = "COLLECTING"
    STOPPING = "STOPPING"
    DESTROYING = "DESTROYING"
    CLEANUP_VERIFY = "CLEANUP_VERIFY"
    REVALIDATING = "REVALIDATING"
    SEALED = "SEALED"
    PUBLISHED = "PUBLISHED"
    REJECTED = "REJECTED"
    QUARANTINED = "QUARANTINED"
    RECOVERING = "RECOVERING"


class Result(str, Enum):
    PENDING = "PENDING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"
    TIMED_OUT = "TIMED_OUT"
    INVALIDATED = "INVALIDATED"


class Resources(str, Enum):
    NONE = "NONE"
    PARTIAL_CREATION = "PARTIAL_CREATION"
    PREPARED = "PREPARED"
    POSSIBLY_ACTIVE = "POSSIBLY_ACTIVE"
    POWER_OFF_CONFIRMED = "POWER_OFF_CONFIRMED"
    DESTRUCTION_PENDING = "DESTRUCTION_PENDING"
    CLEANUP_CONFIRMED = "CLEANUP_CONFIRMED"
    QUARANTINED = "QUARANTINED"


class EventKind(str, Enum):
    ADVANCE = "ADVANCE"
    START = "START"
    COMPLETE = "COMPLETE"
    CANCEL = "CANCEL"
    DEADLINE = "DEADLINE"
    INVALIDATE = "INVALIDATE"
    OPERATION_FAILURE = "OPERATION_FAILURE"
    PRE_RUN_TRANSPORT_FAILURE = "PRE_RUN_TRANSPORT_FAILURE"
    JOURNAL_FAILURE = "JOURNAL_FAILURE"
    COMMIT_FAILURE = "COMMIT_FAILURE"
    RETRY = "RETRY"
    SEAL = "SEAL"
    PUBLISH = "PUBLISH"
    QUERY = "QUERY"


class Subphase(str, Enum):
    NONE = "NONE"
    CAPTURE_PENDING = "CAPTURE_PENDING"
    CAPTURE_CREATED = "CAPTURE_CREATED"
    CAPTURE_VERIFIED = "CAPTURE_VERIFIED"
    CAPTURE_CLEANED = "CAPTURE_CLEANED"
    FINAL_GATE = "FINAL_GATE"


def require(ok, code="MODEL_ARGUMENT"):
    if not ok:
        raise ContractError(code)


def uint(v, positive=False):
    require(type(v) is int and (1 if positive else 0) <= v < 2**64)


def digest(v):
    require(type(v) is str and re.fullmatch("[0-9a-f]{64}", v) is not None)


def epoch(v):
    require(type(v) is str)
    try:
        u = UUID(v)
    except (ValueError, AttributeError):
        raise ContractError("MODEL_ARGUMENT") from None
    require(str(u) == v and u.int != 0)


@dataclass(frozen=True)
class Cause:
    code: str
    event_sequence: int
    observed_tick: int
    generation: int

    def __post_init__(self):
        require(type(self.code) is str and self.code in CAUSE_CODES)
        uint(self.event_sequence, True)
        uint(self.observed_tick)
        require(type(self.generation) is int and self.generation in (0, 1))


@dataclass(frozen=True)
class RetryResolution:
    cause_event_sequence: int
    retry_commit_sequence: int
    from_generation: int
    to_generation: int
    request_sha256: str

    def __post_init__(self):
        uint(self.cause_event_sequence, True)
        uint(self.retry_commit_sequence, True)
        require(self.retry_commit_sequence > self.cause_event_sequence)
        require(
            type(self.from_generation) is int
            and self.from_generation == 0
            and type(self.to_generation) is int
            and self.to_generation == 1
        )
        digest(self.request_sha256)


def validate_state_dimensions(lifecycle, result, resources, started, invalidated):
    """Shared structural invariants for model and closed wire records."""
    require(type(lifecycle) is str and lifecycle in {x.value for x in Lifecycle})
    require(type(result) is str and result in {x.value for x in Result})
    require(type(resources) is str and resources in {x.value for x in Resources})
    require(type(started) is bool and type(invalidated) is bool)
    require(invalidated == (result == "INVALIDATED"))
    require(not (lifecycle in ("RUNNING", "COLLECTING") and not started))
    require(
        not (
            lifecycle in ("REQUESTED", "PREFLIGHT", "CAPTURING", "PREPARING", "READY")
            and started
        )
    )
    require(not (result == "COMPLETED" and not started))
    if lifecycle in ("SEALED", "PUBLISHED"):
        require(result != "PENDING" and resources == "CLEANUP_CONFIRMED")
    if lifecycle == "REJECTED":
        require(not started and resources == "NONE" and result != "PENDING")


def validate_cause_result(result, generation, resolved_cause_sequence, causes):
    """Shared cause dominance for validated model and wire records.

    The pending g0 transport cause and the exact resolved g0 transport event
    are the only exceptions; resolution never clears other causes or a latch.
    """
    codes = {code for code, _, _ in causes}
    if codes & INVALIDATING:
        require(result == "INVALIDATED")
    elif "DEADLINE_EXCEEDED" in codes:
        require(result in ("TIMED_OUT", "INVALIDATED"))
    elif "CANCEL_REQUESTED" in codes:
        require(result in ("CANCELLED", "TIMED_OUT", "INVALIDATED"))
    else:
        active = [
            code
            for code, cause_generation, sequence in causes
            if not (
                code == "PRE_RUN_TRANSPORT_FAILURE"
                and (
                    (generation == 0 and result == "PENDING")
                    or (
                        resolved_cause_sequence is not None
                        and cause_generation == 0
                        and sequence == resolved_cause_sequence
                    )
                )
            )
        ]
        if active:
            require(result in ("FAILED", "CANCELLED", "TIMED_OUT", "INVALIDATED"))


@dataclass(frozen=True)
class CoreState:
    lifecycle: Lifecycle
    result: Result
    resources: Resources
    epoch: str
    sequence: int
    tick_ns: int
    generation: int
    retry_count: int
    started: bool
    invalidated: bool
    causes: tuple[Cause, ...]
    retry_resolution: RetryResolution | None
    request_sha256: str

    def __post_init__(self):
        require(
            type(self.lifecycle) is Lifecycle
            and type(self.result) is Result
            and type(self.resources) is Resources
        )
        validate_state_dimensions(
            self.lifecycle.value,
            self.result.value,
            self.resources.value,
            self.started,
            self.invalidated,
        )
        epoch(self.epoch)
        uint(self.sequence)
        uint(self.tick_ns)
        digest(self.request_sha256)
        require(
            type(self.generation) is int
            and self.generation in (0, 1)
            and type(self.retry_count) is int
            and self.retry_count == self.generation
        )
        require(type(self.started) is bool and type(self.invalidated) is bool)
        require(
            type(self.causes) is tuple
            and len(self.causes) <= 64
            and all(type(c) is Cause for c in self.causes)
        )
        require(len({c.event_sequence for c in self.causes}) == len(self.causes))
        require(
            all(
                c.event_sequence <= self.sequence
                and c.observed_tick <= self.tick_ns
                and c.generation <= self.generation
                for c in self.causes
            )
        )
        require(self.invalidated == (self.result is Result.INVALIDATED))
        if self.generation == 0:
            require(self.retry_resolution is None)
        else:
            r = self.retry_resolution
            require(
                type(r) is RetryResolution
                and r.request_sha256 == self.request_sha256
                and r.retry_commit_sequence <= self.sequence
            )
            require(
                any(
                    c.code == "PRE_RUN_TRANSPORT_FAILURE"
                    and c.generation == 0
                    and c.event_sequence == r.cause_event_sequence
                    for c in self.causes
                )
            )
        validate_cause_result(
            self.result.value,
            self.generation,
            (
                self.retry_resolution.cause_event_sequence
                if self.retry_resolution
                else None
            ),
            tuple(
                (cause.code, cause.generation, cause.event_sequence)
                for cause in self.causes
            ),
        )
        if self.lifecycle in TERMINAL:
            require(self.result is not Result.PENDING)
            if self.lifecycle is Lifecycle.REJECTED:
                require(not self.started and self.resources is Resources.NONE)
            else:
                require(self.resources is Resources.CLEANUP_CONFIRMED)


TERMINAL = frozenset((Lifecycle.SEALED, Lifecycle.PUBLISHED, Lifecycle.REJECTED))


@dataclass(frozen=True)
class Event:
    kind: EventKind
    epoch: str
    sequence: int
    tick_ns: int
    cause: Cause | None

    def __post_init__(self):
        require(type(self.kind) is EventKind)
        epoch(self.epoch)
        uint(self.sequence, True)
        uint(self.tick_ns)
        require(self.cause is None or type(self.cause) is Cause)
        if self.cause:
            require(
                self.cause.event_sequence == self.sequence
                and self.cause.observed_tick == self.tick_ns
            )
        matching = {
            EventKind.CANCEL: "CANCEL_REQUESTED",
            EventKind.DEADLINE: "DEADLINE_EXCEEDED",
            EventKind.PRE_RUN_TRANSPORT_FAILURE: "PRE_RUN_TRANSPORT_FAILURE",
        }
        if self.kind in matching:
            require(self.cause is not None and self.cause.code == matching[self.kind])
        if self.kind in (
            EventKind.INVALIDATE,
            EventKind.JOURNAL_FAILURE,
            EventKind.COMMIT_FAILURE,
        ):
            require(self.cause is not None and self.cause.code in INVALIDATING)
        if self.kind is EventKind.OPERATION_FAILURE:
            require(
                self.cause is not None
                and self.cause.code not in INVALIDATING
                and self.cause.code
                not in (
                    "CANCEL_REQUESTED",
                    "DEADLINE_EXCEEDED",
                    "PRE_RUN_TRANSPORT_FAILURE",
                )
            )


@dataclass(frozen=True)
class Context:
    authority_valid: bool
    lease_valid: bool
    owner_valid: bool
    monitor_valid: bool
    continuity_valid: bool
    preflight_valid: bool
    capacity_valid: bool
    absence_proven: bool
    power_off_confirmed: bool
    cleanup_confirmed: bool
    close_failure: bool
    ownership_ambiguous: bool
    commands_complete: bool
    collection_complete: bool
    collection_expired: bool
    final_evidence_complete: bool
    capture_coherent: bool
    commit_confirmed: bool
    commit_uncertain: bool
    fence_valid: bool
    request_unchanged: bool
    start_committed: bool
    code_send_uncertain: bool
    restarted: bool
    subphase: Subphase
    capture_elapsed_ns: int
    prepare_elapsed_ns: int
    first_close_elapsed_ns: int
    planned_work_ns: int
    now_ns: int
    expires_ns: int
    request_sha256: str

    def __post_init__(self):
        for f in fields(self):
            v = getattr(self, f.name)
            if f.name.endswith("_ns"):
                uint(v)
            elif f.name == "request_sha256":
                digest(v)
            elif f.name == "subphase":
                require(type(v) is Subphase)
            else:
                require(type(v) is bool)
        require(not (self.commit_confirmed and self.commit_uncertain))


RULES = frozenset(
    [
        "A_REJECT",
        "B_TERMINAL",
        "B_PUBLISH",
        "C_REDUCE",
        "MAP_D6",
        "RETRY_ALLOWED",
        "RETRY_REJECTED",
    ]
    + [f"D{i}" for i in range(1, 21) if i != 6]
)
EFFECTS = frozenset(
    "NO_EFFECT REJECT STOP DESTROY QUARANTINE RECOVER CAPTURE_INTENT PREPARE_INTENT START_INTENT COLLECT VERIFY_CLEANUP FINAL_CAPTURE_INTENT SEAL_INTENT PUBLISH_INTENT".split()
)
REASONS = frozenset(
    ("SIMULATED", "GUARD_CLOSED", "COMMIT_REQUIRED", "RETRY_GUARD", "INVALID_SEQUENCE")
)


@dataclass(frozen=True)
class Decision:
    rule: str
    allowed: bool
    next_state: CoreState
    effects: tuple[str, ...]
    reason: str
    scope: str = "SIMULATION"
    operational: bool = False

    def __post_init__(self):
        require(
            type(self.rule) is str
            and self.rule in RULES
            and type(self.allowed) is bool
            and type(self.next_state) is CoreState
        )
        require(
            type(self.effects) is tuple
            and bool(self.effects)
            and all(type(x) is str and x in EFFECTS for x in self.effects)
        )
        require(
            self.reason in REASONS
            and self.scope == "SIMULATION"
            and self.operational is False
        )


def _result(s, causes, complete=False):
    codes = {c.code for c in causes}
    if s.invalidated or codes & INVALIDATING:
        return Result.INVALIDATED
    if "DEADLINE_EXCEEDED" in codes or s.result is Result.TIMED_OUT:
        return Result.TIMED_OUT
    if "CANCEL_REQUESTED" in codes or s.result is Result.CANCELLED:
        return Result.CANCELLED
    active = [
        c
        for c in causes
        if not (
            c.code == "PRE_RUN_TRANSPORT_FAILURE"
            and (
                s.generation == 0
                or (
                    s.retry_resolution
                    and c.event_sequence == s.retry_resolution.cause_event_sequence
                    and c.generation == 0
                )
            )
        )
    ]
    if active or s.result is Result.FAILED:
        return Result.FAILED
    if complete or s.result is Result.COMPLETED:
        return Result.COMPLETED
    return Result.PENDING


def _observe(s, e):
    _validate_record(s, CoreState)
    _validate_record(e, Event)
    require(
        e.epoch == s.epoch and e.sequence > s.sequence and e.tick_ns >= s.tick_ns,
        "MODEL_EVENT_ORDER",
    )
    if e.cause:
        require(e.cause.generation == s.generation)
    if e.kind is EventKind.QUERY or s.lifecycle in TERMINAL:
        return s
    require(
        e.kind is not EventKind.COMPLETE
        or (s.started and s.lifecycle is Lifecycle.RUNNING),
        "MODEL_EVENT_PHASE",
    )
    causes = s.causes + ((e.cause,) if e.cause else ())
    result = _result(s, causes, e.kind is EventKind.COMPLETE)
    return replace(
        s,
        sequence=e.sequence,
        tick_ns=e.tick_ns,
        causes=causes,
        result=result,
        invalidated=result is Result.INVALIDATED,
    )


def _validate_record(value, expected):
    require(type(value) is expected)
    try:
        expected(**{f.name: getattr(value, f.name) for f in fields(expected)})
        if expected is CoreState:
            for cause in value.causes:
                _validate_record(cause, Cause)
            if value.retry_resolution is not None:
                _validate_record(value.retry_resolution, RetryResolution)
        if expected is Event and value.cause is not None:
            _validate_record(value.cause, Cause)
    except AttributeError:
        raise ContractError("MODEL_ARGUMENT") from None


def reduce_causes(state, observations, *, limits):
    _validate_record(state, CoreState)
    _validate_record(limits, S1SyntheticLimits)
    require(
        type(limits) is S1SyntheticLimits
        and type(observations) is tuple
        and len(observations) <= limits.events
    )
    for e in observations:
        state = _observe(state, e)
    return state


def _decision(rule, s, allowed=True, effect="NO_EFFECT", reason="SIMULATED"):
    return Decision(rule, allowed, s, (effect,), reason)


def _authority(c):
    return (
        c.authority_valid
        and c.lease_valid
        and c.owner_valid
        and c.monitor_valid
        and c.continuity_valid
        and c.fence_valid
        and not c.restarted
        and not c.commit_uncertain
    )


def evaluate_retry(state, context):
    _validate_record(state, CoreState)
    _validate_record(context, Context)
    s, c = state, context
    transport = [
        x
        for x in s.causes
        if x.code == "PRE_RUN_TRANSPORT_FAILURE" and x.generation == 0
    ]
    good = (
        s.lifecycle is Lifecycle.CLEANUP_VERIFY
        and s.generation == s.retry_count == 0
        and not s.started
        and not s.invalidated
        and s.result is Result.PENDING
        and len(transport) == len(s.causes) == 1
        and s.resources is Resources.CLEANUP_CONFIRMED
        and c.cleanup_confirmed
        and _authority(replace(c, commit_uncertain=False))
        and c.preflight_valid
        and c.capacity_valid
        and c.request_unchanged
        and c.request_sha256 == s.request_sha256
        and not c.start_committed
        and not c.code_send_uncertain
        and not c.close_failure
        and not c.ownership_ambiguous
        and c.now_ns < c.expires_ns
        and c.capture_elapsed_ns + c.planned_work_ns <= 120_000_000_000
        and c.prepare_elapsed_ns + c.planned_work_ns <= 180_000_000_000
        and c.first_close_elapsed_ns + c.planned_work_ns + 100_000_000_000
        <= 450_000_000_000
    )
    if not good:
        return _decision("RETRY_REJECTED", s, False, reason="RETRY_GUARD")
    if c.commit_uncertain:
        cause = Cause("PERSISTENCE_FAILED", s.sequence + 1, s.tick_ns, s.generation)
        n = replace(
            s,
            sequence=s.sequence + 1,
            causes=s.causes + (cause,),
            result=Result.INVALIDATED,
            invalidated=True,
        )
        return _decision("RETRY_REJECTED", n, False, reason="RETRY_GUARD")
    if not c.commit_confirmed:
        return _decision("RETRY_ALLOWED", s, False, "CAPTURE_INTENT", "COMMIT_REQUIRED")
    resolution = RetryResolution(
        transport[0].event_sequence, s.sequence + 1, 0, 1, s.request_sha256
    )
    return _decision(
        "RETRY_ALLOWED",
        replace(
            s,
            lifecycle=Lifecycle.CAPTURING,
            generation=1,
            retry_count=1,
            retry_resolution=resolution,
            sequence=s.sequence + 1,
            resources=Resources.PARTIAL_CREATION,
        ),
        True,
        "CAPTURE_INTENT",
    )


def evaluate_transition(state, event, context):
    _validate_record(state, CoreState)
    _validate_record(event, Event)
    _validate_record(context, Context)
    original = state
    c = context
    s = _observe(state, event)
    if event.kind is EventKind.QUERY:
        return _decision("B_TERMINAL" if s.lifecycle in TERMINAL else "C_REDUCE", s)
    if original.lifecycle in TERMINAL:
        if original.lifecycle is Lifecycle.SEALED and event.kind is EventKind.PUBLISH:
            good = (
                _authority(c)
                and c.commit_confirmed
                and c.request_sha256 == s.request_sha256
                and c.now_ns < c.expires_ns
                and event.cause is None
            )
            return _decision(
                "B_PUBLISH",
                replace(s, lifecycle=Lifecycle.PUBLISHED) if good else s,
                good,
                "PUBLISH_INTENT" if good else "NO_EFFECT",
                "SIMULATED" if good else "GUARD_CLOSED",
            )
        return _decision("B_TERMINAL", s, False, reason="GUARD_CLOSED")
    invalid_facts = (
        ("authority_valid", "AUTHORIZATION_CHANGED"),
        ("lease_valid", "LEASE_LOST"),
        ("owner_valid", "OWNER_LOST"),
        ("monitor_valid", "AUTHORITY_MONITOR_FAILED"),
        ("continuity_valid", "AUTHORITY_JOURNAL_GAP"),
        ("fence_valid", "PUBLICATION_FENCE_UNAVAILABLE"),
    )
    observed = next(
        (code for name, code in invalid_facts if not getattr(c, name)), None
    )
    if c.now_ns >= c.expires_ns:
        observed = "AUTHORIZATION_EXPIRED"
    if not c.capture_coherent and s.lifecycle in (
        Lifecycle.CAPTURING,
        Lifecycle.REVALIDATING,
    ):
        observed = "GIT_COHERENCE_FAILED"
    if c.commit_uncertain or c.restarted or observed:
        code = (
            "PERSISTENCE_FAILED"
            if c.commit_uncertain
            else ("HOST_RESTARTED" if c.restarted else observed)
        )
        cause = Cause(code, event.sequence, event.tick_ns, s.generation)
        if not any(x.event_sequence == event.sequence for x in s.causes):
            s = replace(
                s,
                causes=s.causes + (cause,),
                result=Result.INVALIDATED,
                invalidated=True,
            )
        s = replace(s, result=Result.INVALIDATED, invalidated=True)

    def go(rule, lifecycle=None, resources=None, effect="NO_EFFECT", allowed=True):
        # A symbolic intent never pretends to be a committed transition.
        n = s
        if lifecycle is not None and c.commit_confirmed and not c.commit_uncertain:
            n = replace(
                s,
                lifecycle=lifecycle,
                resources=resources if resources is not None else s.resources,
            )
        return _decision(
            rule,
            n,
            allowed and (lifecycle is None or c.commit_confirmed),
            effect,
            (
                "SIMULATED"
                if lifecycle is None or c.commit_confirmed
                else "COMMIT_REQUIRED"
            ),
        )

    if c.absence_proven and s.resources in (
        Resources.POSSIBLY_ACTIVE,
        Resources.PREPARED,
        Resources.PARTIAL_CREATION,
        Resources.DESTRUCTION_PENDING,
    ):
        return _decision("A_REJECT", s, False, reason="GUARD_CLOSED")
    progression = (
        EventKind.ADVANCE,
        EventKind.START,
        EventKind.COMPLETE,
        EventKind.CANCEL,
        EventKind.DEADLINE,
        EventKind.INVALIDATE,
        EventKind.OPERATION_FAILURE,
        EventKind.PRE_RUN_TRANSPORT_FAILURE,
        EventKind.JOURNAL_FAILURE,
        EventKind.COMMIT_FAILURE,
        EventKind.RETRY,
        EventKind.SEAL,
    )
    if (
        event.kind not in progression
        or (event.kind is EventKind.START and s.lifecycle is not Lifecycle.READY)
        or (event.kind is EventKind.SEAL and s.lifecycle is not Lifecycle.REVALIDATING)
        or (
            event.kind is EventKind.RETRY
            and s.lifecycle is not Lifecycle.CLEANUP_VERIFY
        )
    ):
        return _decision("D20", s, False, reason="GUARD_CLOSED")
    if s.lifecycle in (Lifecycle.QUARANTINED, Lifecycle.RECOVERING):
        return go("D1", effect="RECOVER", allowed=False)
    if c.close_failure or c.ownership_ambiguous:
        return go("D2", Lifecycle.QUARANTINED, Resources.QUARANTINED, "QUARANTINE")
    early = (
        Lifecycle.REQUESTED,
        Lifecycle.PREFLIGHT,
        Lifecycle.CAPTURING,
        Lifecycle.PREPARING,
        Lifecycle.READY,
    )
    failed = s.result in (
        Result.INVALIDATED,
        Result.TIMED_OUT,
        Result.CANCELLED,
        Result.FAILED,
    )
    if (
        original.lifecycle is Lifecycle.REVALIDATING
        and original.result is Result.COMPLETED
        and c.subphase is Subphase.FINAL_GATE
        and (
            observed
            or not c.final_evidence_complete
            or not c.request_unchanged
            or c.request_sha256 != s.request_sha256
        )
    ):
        s = replace(s, result=Result.INVALIDATED, invalidated=True)
        return go("D15", effect="REJECT")
    if (
        s.lifecycle in early
        and failed
        and not s.started
        and c.absence_proven
        and not c.code_send_uncertain
    ):
        return go("D3", Lifecycle.REJECTED, Resources.NONE, "REJECT")
    if s.lifecycle in early + (Lifecycle.RUNNING, Lifecycle.COLLECTING) and failed:
        off = c.absence_proven or c.power_off_confirmed
        return go(
            "D4",
            Lifecycle.DESTROYING if off else Lifecycle.STOPPING,
            Resources.DESTRUCTION_PENDING if off else Resources.POSSIBLY_ACTIVE,
            "DESTROY" if off else "STOP",
        )
    if s.lifecycle is Lifecycle.REVALIDATING and failed and not c.cleanup_confirmed:
        return go(
            "D5",
            Lifecycle.DESTROYING if c.power_off_confirmed else Lifecycle.STOPPING,
            effect="DESTROY" if c.power_off_confirmed else "STOP",
        )
    if (
        s.lifecycle in (Lifecycle.REQUESTED, Lifecycle.PREFLIGHT)
        and s.result is Result.PENDING
    ):
        good = (
            _authority(c)
            and c.preflight_valid
            and c.capacity_valid
            and c.now_ns < c.expires_ns
        )
        return (
            go(
                "MAP_D6",
                (
                    Lifecycle.PREFLIGHT
                    if s.lifecycle is Lifecycle.REQUESTED
                    else Lifecycle.CAPTURING
                ),
                (
                    Resources.NONE
                    if s.lifecycle is Lifecycle.REQUESTED
                    else Resources.PARTIAL_CREATION
                ),
                "NO_EFFECT" if s.lifecycle is Lifecycle.REQUESTED else "CAPTURE_INTENT",
            )
            if good
            else _decision("MAP_D6", s, False, reason="GUARD_CLOSED")
        )
    if (
        s.lifecycle in (Lifecycle.CAPTURING, Lifecycle.PREPARING, Lifecycle.READY)
        and s.result is Result.PENDING
    ):
        good = (
            _authority(c)
            and c.capture_coherent
            and c.preflight_valid
            and c.now_ns < c.expires_ns
        )
        if s.lifecycle is Lifecycle.READY:
            good = (
                good
                and event.kind is EventKind.START
                and c.start_committed
                and not c.code_send_uncertain
            )
            if good and c.commit_confirmed:
                s = replace(s, started=True)
            return (
                go("D7", Lifecycle.RUNNING, Resources.POSSIBLY_ACTIVE, "START_INTENT")
                if good
                else _decision("D7", s, False, reason="GUARD_CLOSED")
            )
        return (
            go(
                "D7",
                (
                    Lifecycle.PREPARING
                    if s.lifecycle is Lifecycle.CAPTURING
                    else Lifecycle.READY
                ),
                Resources.PREPARED,
                "PREPARE_INTENT",
            )
            if good
            else _decision("D7", s, False, reason="GUARD_CLOSED")
        )
    if (
        s.lifecycle is Lifecycle.RUNNING
        and s.result is Result.PENDING
        and not c.commands_complete
    ):
        return go("D8")
    if s.lifecycle is Lifecycle.RUNNING and c.commands_complete:
        s = replace(s, result=_result(s, s.causes, True))
        if s.result is Result.COMPLETED:
            return go("D9", Lifecycle.COLLECTING, effect="COLLECT")
    if s.lifecycle is Lifecycle.COLLECTING:
        if c.collection_complete or c.collection_expired:
            if c.collection_expired:
                s = replace(s, result=Result.TIMED_OUT)
            return go("D10", Lifecycle.STOPPING, effect="STOP")
        return go("D11")
    if s.lifecycle in (
        Lifecycle.STOPPING,
        Lifecycle.DESTROYING,
        Lifecycle.CLEANUP_VERIFY,
    ):
        if event.kind is EventKind.RETRY:
            # Retry commits use the supplied event sequence, not an implicit second event.
            r = evaluate_retry(s, c)
            if r.allowed:
                rr = replace(
                    r.next_state.retry_resolution, retry_commit_sequence=event.sequence
                )
                return replace(
                    r,
                    next_state=replace(
                        r.next_state,
                        sequence=event.sequence,
                        tick_ns=event.tick_ns,
                        retry_resolution=rr,
                    ),
                )
            return r
        if s.lifecycle is Lifecycle.STOPPING and c.power_off_confirmed:
            return go(
                "D12", Lifecycle.DESTROYING, Resources.POWER_OFF_CONFIRMED, "DESTROY"
            )
        if s.lifecycle is Lifecycle.DESTROYING and c.absence_proven:
            return go(
                "D12",
                Lifecycle.CLEANUP_VERIFY,
                Resources.CLEANUP_CONFIRMED,
                "VERIFY_CLEANUP",
            )
        if (
            s.lifecycle is Lifecycle.CLEANUP_VERIFY
            and c.cleanup_confirmed
            and s.result is not Result.PENDING
        ):
            return go(
                "D12",
                Lifecycle.REVALIDATING,
                Resources.CLEANUP_CONFIRMED,
                "VERIFY_CLEANUP",
            )
        return _decision("D12", s, False, reason="GUARD_CLOSED")
    if s.lifecycle is Lifecycle.REVALIDATING:
        if s.result is Result.COMPLETED and c.subphase is not Subphase.FINAL_GATE:
            resource = {
                Subphase.CAPTURE_PENDING: Resources.PARTIAL_CREATION,
                Subphase.CAPTURE_CREATED: Resources.PARTIAL_CREATION,
                Subphase.CAPTURE_VERIFIED: Resources.DESTRUCTION_PENDING,
                Subphase.CAPTURE_CLEANED: Resources.CLEANUP_CONFIRMED,
            }.get(c.subphase)
            if resource is not None:
                return go(
                    "D13",
                    Lifecycle.REVALIDATING,
                    resource,
                    (
                        "FINAL_CAPTURE_INTENT"
                        if c.subphase is Subphase.CAPTURE_PENDING
                        else "VERIFY_CLEANUP"
                    ),
                )
        if s.result is Result.COMPLETED and c.subphase is Subphase.FINAL_GATE:
            if not (
                c.final_evidence_complete
                and c.capture_coherent
                and _authority(c)
                and c.request_unchanged
                and c.request_sha256 == s.request_sha256
                and c.now_ns < c.expires_ns
            ):
                s = replace(s, result=Result.INVALIDATED, invalidated=True)
                return go("D15", effect="REJECT")
            if (
                c.cleanup_confirmed
                and s.resources is Resources.CLEANUP_CONFIRMED
                and event.kind is EventKind.SEAL
            ):
                return go(
                    "D14", Lifecycle.SEALED, Resources.CLEANUP_CONFIRMED, "SEAL_INTENT"
                )
        rows = {
            Result.FAILED: "D16",
            Result.CANCELLED: "D17",
            Result.TIMED_OUT: "D18",
            Result.INVALIDATED: "D19",
        }
        if (
            s.result in rows
            and c.cleanup_confirmed
            and s.resources is Resources.CLEANUP_CONFIRMED
            and c.final_evidence_complete
            and c.continuity_valid
            and c.fence_valid
            and event.kind is EventKind.SEAL
        ):
            return go(
                rows[s.result],
                Lifecycle.SEALED,
                Resources.CLEANUP_CONFIRMED,
                "SEAL_INTENT",
            )
    return _decision("D20", s, False, reason="GUARD_CLOSED")


@dataclass(frozen=True)
class FakeJournal:
    """An immutable event fixture, never a durable or authenticated journal."""

    events: tuple[Event, ...]

    def __post_init__(self):
        require(
            type(self.events) is tuple and all(type(e) is Event for e in self.events)
        )

    def replay(self, state, *, limits):
        return reduce_causes(state, self.events, limits=limits)
