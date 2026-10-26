"""Independent contract tests: synthetic TEST_ONLY control facts, never authority."""

from dataclasses import replace
from hashlib import sha256
import json
import sqlite3
from uuid import UUID

import pytest

from company_os.sandbox import test_ledger as api
from company_os.sandbox.test_ledger_types import (
    ControlAction,
    FakeStopSink,
    Fault,
    LedgerError,
    LedgerLimits,
    Observation,
    ObservationResult,
    OpenMode,
    SyntheticPolicy,
)


def uid(number):
    return str(UUID(int=number))


LIMITS = LedgerLimits(65536, 4096, 4096, 8192, 1000, 33554432)
POLICY = SyntheticPolicy(100, 10, 50)
REQUEST = b"opaque synthetic input"
DIGEST = sha256(REQUEST).hexdigest()
EXECUTION, EPOCH, OWNER, SESSION, DATABASE = map(uid, range(1, 6))


def scoped(value):
    assert value.scope == "TEST_ONLY"
    assert value.operational is False
    assert value.authority_authenticated is False
    assert value.execution_capability == "NONE"
    return value


def error(code, function, *args, **kwargs):
    with pytest.raises(LedgerError) as caught:
        function(*args, **kwargs)
    scoped(caught.value)
    assert caught.value.code == code
    assert str(caught.value) == code


class Harness:
    def __init__(self, path, limits=LIMITS):
        self.path, self.limits = path, limits
        self.handles = []
        self.sink = FakeStopSink()

    def open(self, mode=OpenMode.NEW, **changes):
        values = dict(
            directory=self.path,
            limits=self.limits,
            policy=POLICY,
            mode=mode,
            session_id=SESSION,
            database_id=DATABASE,
            session_continuity=mode is not OpenMode.RECOVER,
            stop_sink=self.sink,
        )
        values.update(changes)
        ledger = api.open_test_ledger(**values)
        self.handles.append(ledger)
        return ledger

    def create(self, ledger, operation_id=uid(10), **changes):
        values = dict(
            execution_id=EXECUTION,
            request_sha256=DIGEST,
            epoch=EPOCH,
            owner_id=OWNER,
            operation_id=operation_id,
            request_bytes=REQUEST,
            now_ns=0,
        )
        values.update(changes)
        return scoped(api.create_execution(ledger, **values))

    def observe(self, ledger, version=0, operation_id=uid(11), now=12, **changes):
        obs = dict(
            epoch=EPOCH,
            source_sequence=1,
            started_ns=10,
            finished_ns=12,
            result=ObservationResult.VALID,
            lease_valid=True,
            continuity_valid=True,
        )
        obs.update(changes)
        return scoped(
            api.apply_observation(
                ledger,
                execution_id=EXECUTION,
                request_sha256=DIGEST,
                epoch=EPOCH,
                owner_id=OWNER,
                operation_id=operation_id,
                expected_version=version,
                observation=Observation(**obs),
                now_ns=now,
            )
        )

    def control(
        self,
        ledger,
        version,
        action=ControlAction.CHECK,
        now=13,
        operation_id=uid(12),
        owner=OWNER,
        new_owner=None,
    ):
        return scoped(
            api.commit_control_update(
                ledger,
                execution_id=EXECUTION,
                request_sha256=DIGEST,
                epoch=EPOCH,
                owner_id=owner,
                operation_id=operation_id,
                expected_version=version,
                action=action,
                new_owner_id=new_owner,
                now_ns=now,
            )
        )


@pytest.fixture
def harness(tmp_path):
    # Explicit C: pytest base is supplied by the verification command.
    harness = Harness(tmp_path)
    yield harness
    for ledger in harness.handles:
        ledger.close()


def test_creation_observation_check_and_historical_replay(harness):
    ledger = harness.open()
    created = harness.create(ledger)
    assert (created.snapshot.version, created.snapshot.journal_sequence) == (0, 1)
    assert created.snapshot.last_observation is None
    assert created.snapshot.lease_expires_ns == 0
    observed = harness.observe(ledger)
    assert observed.snapshot.lease_expires_ns == 62
    checked = harness.control(ledger, 1)
    assert (checked.snapshot.version, checked.snapshot.journal_sequence) == (2, 3)
    assert harness.create(ledger) == created
    assert harness.observe(ledger) == observed
    found = scoped(
        api.lookup_operation(
            ledger,
            execution_id=EXECUTION,
            request_sha256=DIGEST,
            epoch=EPOCH,
            owner_id=OWNER,
            operation_id=observed.operation_id,
            operation_digest=observed.operation_digest,
        )
    )
    assert found.status == "FOUND" and found.result == observed
    assert scoped(api.read_snapshot(ledger, execution_id=EXECUTION)) == checked.snapshot


@pytest.mark.parametrize(
    "field,value",
    [
        ("request_sha256", "0" * 64),
        ("epoch", uid(99)),
        ("owner_id", uid(99)),
        ("execution_id", uid(99)),
    ],
)
def test_operation_identity_collision(harness, field, value):
    ledger = harness.open()
    harness.create(ledger)
    changes = {field: value}
    if field == "request_sha256":
        changes = dict(
            request_bytes=b"different", request_sha256=sha256(b"different").hexdigest()
        )
    error("OPERATION_CONFLICT", harness.create, ledger, **changes)


def test_cas_owner_and_clock_rejections_do_not_consume_operation(harness):
    ledger = harness.open()
    harness.create(ledger)
    harness.observe(ledger)
    error("CAS_CONFLICT", harness.control, ledger, 0)
    error("OWNER_MISMATCH", harness.control, ledger, 1, owner=uid(99))
    error("CLOCK_ORDER", harness.control, ledger, 1, now=11)
    assert harness.control(ledger, 1).snapshot.version == 2


@pytest.mark.parametrize("action", list(ControlAction))
def test_expiry_equality_is_irreversible_for_every_control_action(harness, action):
    ledger = harness.open()
    harness.create(ledger)
    harness.observe(ledger)
    new_owner = (
        OWNER
        if action is ControlAction.ACQUIRE_OWNER
        else (uid(99) if action is ControlAction.CHANGE_OWNER else None)
    )
    expired = harness.control(ledger, 1, action, now=62, new_owner=new_owner)
    assert expired.snapshot.invalidated is True
    assert harness.sink.requests
    error(
        "INVALIDATED",
        harness.observe,
        ledger,
        version=2,
        operation_id=uid(30),
        now=63,
        source_sequence=2,
        started_ns=62,
        finished_ns=63,
    )
    assert api.read_snapshot(ledger, execution_id=EXECUTION).invalidated is True


def test_positive_replacement_cannot_hide_expired_prior_lease(harness):
    ledger = harness.open()
    harness.create(ledger)
    harness.observe(ledger)
    result = harness.observe(
        ledger,
        version=1,
        operation_id=uid(30),
        now=62,
        source_sequence=2,
        started_ns=61,
        finished_ns=62,
    )
    assert result.snapshot.invalidated is True
    assert harness.sink.requests


@pytest.mark.parametrize(
    "changes",
    [
        dict(result=ObservationResult.INVALID),
        dict(result=ObservationResult.UNPROVEN),
        dict(lease_valid=False),
        dict(continuity_valid=False),
        dict(started_ns=0, finished_ns=12),
    ],
)
def test_negative_observations_latch_and_stop(harness, changes):
    ledger = harness.open()
    harness.create(ledger)
    result = harness.observe(ledger, **changes)
    assert result.snapshot.invalidated is True
    assert harness.sink.requests
    error("INVALIDATED", harness.control, ledger, 1)


@pytest.mark.parametrize(
    "changes",
    [
        dict(source_sequence=1),
        dict(epoch=uid(99)),
        dict(source_sequence=2, started_ns=9),
        dict(source_sequence=2, finished_ns=11),
    ],
)
def test_order_reversal_latches_without_appending(harness, changes):
    ledger = harness.open()
    harness.create(ledger)
    before = harness.observe(ledger)
    error(
        "OBSERVATION_ORDER",
        harness.observe,
        ledger,
        version=1,
        operation_id=uid(30),
        now=13,
        **changes,
    )
    assert api.read_snapshot(ledger, execution_id=EXECUTION) == before.snapshot
    error("INVALIDATED", harness.control, ledger, 1)
    assert harness.sink.requests


def test_change_owner_requires_new_observation(harness):
    ledger = harness.open()
    harness.create(ledger)
    harness.observe(ledger)
    changed = harness.control(ledger, 1, ControlAction.CHANGE_OWNER, new_owner=uid(99))
    assert changed.snapshot.owner_id == uid(99)
    assert changed.snapshot.last_observation is None
    assert changed.snapshot.lease_expires_ns == 0
    error(
        "AUTHORITY_DENIED",
        harness.control,
        ledger,
        2,
        owner=uid(99),
        operation_id=uid(31),
    )


@pytest.mark.parametrize(
    "fault,code,found",
    [
        (Fault.BEFORE_WRITE, "PERSISTENCE_FAILURE", False),
        (Fault.BEFORE_COMMIT, "PERSISTENCE_FAILURE", False),
        (Fault.AFTER_COMMIT_BEFORE_ACK, "COMMIT_UNCERTAIN", True),
    ],
)
def test_fault_poison_and_independent_recovery_without_replay(
    harness, fault, code, found
):
    first = harness.open()
    harness.create(first)
    first.close()
    ledger = harness.open(OpenMode.ATTACH, fault=fault)
    error(code, harness.observe, ledger)
    error("CONNECTION_POISONED", api.read_snapshot, ledger, execution_id=EXECUTION)
    ledger.close()
    recovered = harness.open(OpenMode.RECOVER)
    error("RECOVERY_REQUIRED", harness.control, recovered, 0, ControlAction.INVALIDATE)
    report = scoped(
        api.recover(
            recovered, execution_id=EXECUTION, now_ns=20, uncertain_operation_id=uid(11)
        )
    )
    assert report.status == "VERIFIED" and report.admission_open is False
    assert report.recovered_invalidated is True
    assert scoped(report.operation).status == ("FOUND" if found else "ABSENT")
    error(
        "INVALIDATED",
        harness.observe,
        recovered,
        version=report.snapshot.version,
        operation_id=uid(31),
        now=21,
        source_sequence=2,
        started_ns=20,
        finished_ns=21,
    )
    invalidated = harness.control(
        recovered,
        report.snapshot.version,
        ControlAction.INVALIDATE,
        now=21,
        operation_id=uid(32),
    )
    assert invalidated.snapshot.invalidated is True


@pytest.mark.parametrize("column,table", [("snapshot", "heads"), ("event", "journal")])
def test_corrupt_stored_payload_fails_recovery_closed(harness, column, table):
    ledger = harness.open()
    harness.create(ledger)
    ledger.close()
    # Derive physical blob column from declared schema; no backend private helpers.
    with sqlite3.connect(harness.path / "ledger.sqlite3") as connection:
        columns = connection.execute(f"PRAGMA table_info({table})").fetchall()
        candidates = [
            row[1] for row in columns if column in row[1] and "sha" not in row[1]
        ]
        assert len(candidates) == 1
        connection.execute(f'UPDATE {table} SET "{candidates[0]}"=?', (b"{}",))
    try:
        recovering = harness.open(OpenMode.RECOVER)
    except LedgerError as caught:
        assert scoped(caught).code in {"STORAGE_CORRUPT", "RECOVERY_INVALID"}
        return
    with pytest.raises(LedgerError) as caught:
        api.recover(
            recovering, execution_id=EXECUTION, now_ns=20, uncertain_operation_id=None
        )
    assert scoped(caught.value).code in {"STORAGE_CORRUPT", "RECOVERY_INVALID"}
    error("CONNECTION_POISONED", api.read_snapshot, recovering, execution_id=EXECUTION)


@pytest.mark.parametrize("field", list(LIMITS.__dataclass_fields__))
@pytest.mark.parametrize("value", [True, 0, -1])
def test_limits_require_exact_positive_integers(field, value):
    error("LIMIT_CONFIGURATION", replace, LIMITS, **{field: value})


def test_global_row_capacity_and_bounded_recovery(tmp_path):
    harness = Harness(tmp_path, replace(LIMITS, journal_rows=1, operation_count=1))
    ledger = harness.open()
    try:
        harness.create(ledger)
        error(
            "CAPACITY_LIMIT",
            harness.create,
            ledger,
            operation_id=uid(30),
            execution_id=uid(31),
        )
    finally:
        ledger.close()


def test_recovery_row_visits_count_selected_head(tmp_path):
    harness = Harness(tmp_path, replace(LIMITS, replay_row_visits=2))
    first = harness.open()
    harness.create(first)
    first.close()
    recovered = harness.open(OpenMode.RECOVER)
    try:
        error(
            "RECOVERY_LIMIT",
            api.recover,
            recovered,
            execution_id=EXECUTION,
            now_ns=1,
            uncertain_operation_id=None,
        )
        error(
            "CONNECTION_POISONED", api.read_snapshot, recovered, execution_id=EXECUTION
        )
    finally:
        recovered.close()


def test_raw_request_record_ceiling_before_storage(harness):
    ledger = harness.open()
    request = b"x" * LIMITS.record_bytes
    error(
        "RECORD_LIMIT",
        harness.create,
        ledger,
        request_bytes=request,
        request_sha256=sha256(request).hexdigest(),
    )
    assert harness.create(ledger).snapshot.version == 0


def test_closed_handle_rejects_public_reads(harness):
    ledger = harness.open()
    harness.create(ledger)
    ledger.close()
    error("CONNECTION_CLOSED", api.read_snapshot, ledger, execution_id=EXECUTION)


def test_operation_digest_matches_independent_canonical_codec(harness):
    ledger = harness.open()
    result = harness.create(ledger)
    # Read the public durable operation evidence, then independently encode it.
    with sqlite3.connect(harness.path / "ledger.sqlite3") as connection:
        columns = connection.execute("PRAGMA table_info(operations)").fetchall()
        names = [row[1] for row in columns]
        rows = connection.execute("SELECT * FROM operations").fetchall()
    assert len(rows) == 1
    blobs = [value for value in rows[0] if type(value) is bytes]
    envelopes = [json.loads(value) for value in blobs]
    operation = next(value for value in envelopes if "api" in value)
    assert operation["api"] == "create_execution"
    assert operation["session_id"] == SESSION
    assert operation["database_id"] == DATABASE
    assert operation["arguments"]["request_bytes"] == REQUEST.hex()
    canonical = json.dumps(
        operation,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
        allow_nan=False,
    ).encode("utf8")
    assert canonical in blobs
    assert sha256(canonical).hexdigest() == result.operation_digest
    assert "operation_digest" in names


@pytest.mark.parametrize(
    "now,changes",
    [
        (113, dict(started_ns=10, finished_ns=12)),
        (11, {}),
        (63, dict(started_ns=10, finished_ns=12)),
    ],
)
def test_first_observation_ineligible_time_latches(harness, now, changes):
    ledger = harness.open()
    harness.create(ledger)
    assert harness.observe(ledger, now=now, **changes).snapshot.invalidated is True


def test_live_attach_shares_order_latch(harness):
    first = harness.open()
    harness.create(first)
    second = harness.open(OpenMode.ATTACH)
    harness.observe(first)
    error(
        "OBSERVATION_ORDER",
        harness.observe,
        first,
        version=1,
        operation_id=uid(30),
        now=13,
    )
    error("INVALIDATED", harness.control, second, 1)


def test_recovery_is_read_only_and_returns_historical_snapshot(harness):
    first = harness.open()
    historical = harness.create(first).snapshot
    first.close()
    before = (harness.path / "ledger.sqlite3").read_bytes()
    recovering = harness.open(OpenMode.RECOVER)
    report = scoped(
        api.recover(
            recovering, execution_id=EXECUTION, now_ns=20, uncertain_operation_id=None
        )
    )
    assert report.snapshot == historical and report.snapshot.invalidated is False
    assert report.rows_visited == 3
    assert (harness.path / "ledger.sqlite3").read_bytes() == before
    repeated = scoped(
        api.recover(
            recovering, execution_id=None, now_ns=21, uncertain_operation_id=None
        )
    )
    assert repeated.snapshot is None and repeated.recovered_invalidated is True
    assert (harness.path / "ledger.sqlite3").read_bytes() == before


def test_negative_observation_retains_negative_fact_after_prior_expiry(harness):
    ledger = harness.open()
    harness.create(ledger)
    harness.observe(ledger)
    result = harness.observe(
        ledger,
        version=1,
        operation_id=uid(30),
        now=62,
        source_sequence=2,
        started_ns=61,
        finished_ns=62,
        result=ObservationResult.INVALID,
    )
    assert result.snapshot.invalidated is True
    assert result.snapshot.last_observation.result is ObservationResult.INVALID
    assert result.snapshot.last_observation.source_sequence == 2


@pytest.mark.parametrize(
    "field,value",
    [
        ("now_ns", True),
        ("now_ns", -1),
        ("now_ns", 2**64),
        ("execution_id", "00000000-0000-0000-0000-000000000000"),
        ("request_bytes", bytearray(REQUEST)),
        ("epoch", EPOCH.upper().replace("000", "ABC", 1)),
    ],
)
def test_invalid_mutation_inputs_reject_before_consuming_identity(
    harness, field, value
):
    ledger = harness.open()
    error("INVALID_ARGUMENT", harness.create, ledger, **{field: value})
    assert harness.create(ledger).snapshot.version == 0


@pytest.mark.parametrize(
    "mode,continuity",
    [(OpenMode.NEW, False), (OpenMode.ATTACH, False), (OpenMode.RECOVER, True)],
)
def test_session_continuity_modes_are_explicit(harness, mode, continuity):
    error("INVALID_ARGUMENT", harness.open, mode, session_continuity=continuity)


def test_wrong_database_and_session_identity_do_not_attach(harness):
    ledger = harness.open()
    harness.create(ledger)
    error("IDENTITY_MISMATCH", harness.open, OpenMode.ATTACH, database_id=uid(99))
    error("IDENTITY_MISMATCH", harness.open, OpenMode.ATTACH, session_id=uid(99))


def test_freshness_boundary_and_checked_lease_overflow(harness):
    ledger = harness.open()
    harness.create(ledger)
    # exact arithmetic overflow is a malformed request, never a durable event.
    error(
        "INVALID_ARGUMENT",
        harness.observe,
        ledger,
        now=2**64 - 1,
        started_ns=2**64 - 2,
        finished_ns=2**64 - 1,
    )
    assert api.read_snapshot(ledger, execution_id=EXECUTION).version == 0


def test_idempotent_replay_does_not_clear_expiry_latch(harness):
    ledger = harness.open()
    harness.create(ledger)
    historical = harness.observe(ledger)
    harness.control(ledger, 1, now=62)
    assert harness.observe(ledger) == historical
    error("INVALIDATED", harness.control, ledger, 2, now=63, operation_id=uid(30))


def test_exact_replay_rejects_structurally_valid_forged_historical_result(harness):
    ledger = harness.open()
    harness.create(ledger)
    # Keep operation identity/digest intact; only forge the stored result projection.
    with sqlite3.connect(harness.path / "ledger.sqlite3") as connection:
        raw = connection.execute(
            "SELECT result FROM operations WHERE operation_id=?", (uid(10),)
        ).fetchone()[0]
        forged = json.loads(raw)
        forged["snapshot"]["invalidated"] = True
        changed = json.dumps(
            forged,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True,
            allow_nan=False,
        ).encode("utf8")
        connection.execute(
            "UPDATE operations SET result=? WHERE operation_id=?", (changed, uid(10))
        )
    with pytest.raises(LedgerError) as caught:
        harness.create(ledger)
    assert scoped(caught.value).code in {"STORAGE_CORRUPT", "RECOVERY_INVALID"}
    error("CONNECTION_POISONED", api.read_snapshot, ledger, execution_id=EXECUTION)
