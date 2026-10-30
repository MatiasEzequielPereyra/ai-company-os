"""Closed values for the synthetic g0 control ledger; none authenticates authority."""

from dataclasses import dataclass, field, fields
from enum import Enum
import re
from uuid import UUID

U64 = 2**64 - 1
CEILINGS = dict(
    record_bytes=65536,
    journal_rows=4096,
    operation_count=4096,
    replay_row_visits=8192,
    busy_timeout_ms=1000,
    sqlite_database_bytes=33554432,
)


class LedgerError(Exception):
    scope = "TEST_ONLY"
    operational = False
    authority_authenticated = False
    execution_capability = "NONE"

    def __init__(self, code):
        self.code = code
        super().__init__(code)


def require(condition, code="INVALID_ARGUMENT"):
    if not condition:
        raise LedgerError(code)


def integer(value, minimum=0, maximum=U64, code="INVALID_ARGUMENT"):
    require(type(value) is int and minimum <= value <= maximum, code)


def identifier(value):
    require(type(value) is str and len(value) == 36)
    try:
        parsed = UUID(value)
    except ValueError:
        raise LedgerError("INVALID_ARGUMENT") from None
    require(str(parsed) == value and parsed.int != 0)


def digest(value):
    require(type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value) is not None)


class OpenMode(str, Enum):
    NEW = "NEW"
    ATTACH = "ATTACH"
    RECOVER = "RECOVER"


class Fault(str, Enum):
    NONE = "NONE"
    BEFORE_WRITE = "BEFORE_WRITE"
    BEFORE_COMMIT = "BEFORE_COMMIT"
    AFTER_COMMIT_BEFORE_ACK = "AFTER_COMMIT_BEFORE_ACK"


class ObservationResult(str, Enum):
    VALID = "VALID"
    INVALID = "INVALID"
    UNPROVEN = "UNPROVEN"


class ControlAction(str, Enum):
    ACQUIRE_OWNER = "ACQUIRE_OWNER"
    CHANGE_OWNER = "CHANGE_OWNER"
    INVALIDATE = "INVALIDATE"
    CHECK = "CHECK"


@dataclass(frozen=True)
class LedgerLimits:
    record_bytes: int
    journal_rows: int
    operation_count: int
    replay_row_visits: int
    busy_timeout_ms: int
    sqlite_database_bytes: int

    def __post_init__(self):
        for name, ceiling in CEILINGS.items():
            integer(getattr(self, name), 1, ceiling, "LIMIT_CONFIGURATION")


@dataclass(frozen=True)
class SyntheticPolicy:
    freshness_ns: int
    evaluation_duration_ns: int
    lease_duration_ns: int

    def __post_init__(self):
        for name in ("freshness_ns", "evaluation_duration_ns", "lease_duration_ns"):
            integer(getattr(self, name), 1)


@dataclass(frozen=True)
class Observation:
    epoch: str
    source_sequence: int
    started_ns: int
    finished_ns: int
    result: ObservationResult
    lease_valid: bool
    continuity_valid: bool

    def __post_init__(self):
        identifier(self.epoch)
        integer(self.source_sequence, 1)
        integer(self.started_ns)
        integer(self.finished_ns, self.started_ns)
        require(type(self.result) is ObservationResult)
        require(type(self.lease_valid) is bool and type(self.continuity_valid) is bool)


@dataclass(frozen=True)
class Scoped:
    scope: str = field(default="TEST_ONLY", init=False)
    operational: bool = field(default=False, init=False)
    authority_authenticated: bool = field(default=False, init=False)
    execution_capability: str = field(default="NONE", init=False)


@dataclass(frozen=True)
class Snapshot(Scoped):
    execution_id: str
    request_sha256: str
    epoch: str
    version: int
    journal_sequence: int
    journal_sha256: str
    owner_id: str | None
    invalidated: bool
    last_observation: Observation | None
    lease_expires_ns: int
    last_now_ns: int
    generation: int

    def __post_init__(self):
        for value in (self.execution_id, self.epoch):
            identifier(value)
        digest(self.request_sha256)
        digest(self.journal_sha256)
        integer(self.version)
        integer(self.journal_sequence, 1)
        if self.owner_id is not None:
            identifier(self.owner_id)
        require(type(self.invalidated) is bool)
        if self.last_observation is not None:
            validate_record(self.last_observation, Observation)
        integer(self.lease_expires_ns)
        integer(self.last_now_ns)
        integer(self.generation, 0, 0)


@dataclass(frozen=True)
class OperationResult(Scoped):
    operation_id: str
    operation_digest: str
    outcome: str
    snapshot: Snapshot

    def __post_init__(self):
        identifier(self.operation_id)
        digest(self.operation_digest)
        require(type(self.outcome) is str and self.outcome == "COMMITTED")
        validate_record(self.snapshot, Snapshot)


@dataclass(frozen=True)
class LookupResult(Scoped):
    status: str
    result: OperationResult | None

    def __post_init__(self):
        require(type(self.status) is str and self.status in ("FOUND", "ABSENT"))
        require((self.result is None) == (self.status == "ABSENT"))
        if self.result is not None:
            validate_record(self.result, OperationResult)


@dataclass(frozen=True)
class RecoveryReport(Scoped):
    status: str
    snapshot: Snapshot | None
    operation: LookupResult | None
    rows_visited: int
    admission_open: bool = field(default=False, init=False)
    recovered_invalidated: bool = field(default=True, init=False)

    def __post_init__(self):
        require(type(self.status) is str and self.status in ("VERIFIED", "INVALID"))
        integer(self.rows_visited)
        if self.snapshot is not None:
            require(self.status == "VERIFIED")
            validate_record(self.snapshot, Snapshot)
        if self.operation is not None:
            validate_record(self.operation, LookupResult)


def validate_record(value, cls):
    """Invoke the defining validator, never an instance-shadowed hook."""
    require(type(value) is cls)
    cls.__post_init__(value)
    for item in fields(cls):
        if not item.init:
            require(
                type(getattr(value, item.name)) is type(item.default)
                and getattr(value, item.name) == item.default
            )


class FakeStopSink:
    """Symbolic in-memory requests only. No callable or OS command payload."""

    def __init__(self):
        self.requests = []

    def stop(self, execution_id, reason):
        identifier(execution_id)
        require(
            type(reason) is str
            and reason
            in {
                "INVALIDATED",
                "OBSERVATION_ORDER",
                "PERSISTENCE_FAILURE",
                "COMMIT_UNCERTAIN",
                "STORAGE_CORRUPT",
                "RECOVERED",
                "SESSION_LOST",
            }
        )
        require(type(self.requests) is list)
        self.requests.append((execution_id, reason))
