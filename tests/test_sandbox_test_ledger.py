"""Backend public API and bounded-storage regressions, in exclusive test dirs."""

from dataclasses import replace
from hashlib import sha256
import sqlite3
from uuid import UUID

import pytest

from company_os.sandbox.test_ledger import (
    LedgerLimits,
    SyntheticPolicy,
    Observation,
    ObservationResult,
    ControlAction,
    OpenMode,
    Fault,
    FakeStopSink,
    LedgerError,
    open_test_ledger,
    create_execution,
    apply_observation,
    commit_control_update,
    recover,
    lookup_operation,
    read_snapshot,
)


def uid(number):
    return str(UUID(int=number))


LIMITS = LedgerLimits(65536, 4096, 4096, 8192, 100, 33554432)
POLICY = SyntheticPolicy(100, 10, 50)
REQUEST = b"opaque synthetic request"
IDENTITY = dict(
    execution_id=uid(1),
    request_sha256=sha256(REQUEST).hexdigest(),
    epoch=uid(2),
    owner_id=uid(3),
)


@pytest.fixture
def store(tmp_path):
    directory = tmp_path / "exclusive"
    directory.mkdir()
    handles = []

    def open_(mode=OpenMode.NEW, limits=LIMITS, policy=POLICY, fault=Fault.NONE):
        handle = open_test_ledger(
            directory=directory,
            limits=limits,
            policy=policy,
            mode=mode,
            session_id=uid(4),
            database_id=uid(5),
            session_continuity=mode is not OpenMode.RECOVER,
            fault=fault,
            stop_sink=FakeStopSink(),
        )
        handles.append(handle)
        return handle

    yield directory, open_
    for handle in handles:
        handle.close()


def create(handle, op=10):
    return create_execution(
        handle, **IDENTITY, operation_id=uid(op), request_bytes=REQUEST, now_ns=0
    )


def observe(handle, op=11, version=0, now=12, **changes):
    obs = Observation(uid(2), 1, 10, 12, ObservationResult.VALID, True, True)
    return apply_observation(
        handle,
        **IDENTITY,
        operation_id=uid(op),
        expected_version=version,
        observation=replace(obs, **changes),
        now_ns=now,
    )


def check(handle, version=1, op=12, now=13):
    return commit_control_update(
        handle,
        **IDENTITY,
        operation_id=uid(op),
        expected_version=version,
        action=ControlAction.CHECK,
        new_owner_id=None,
        now_ns=now,
    )


def fails(code, function, *args, **kwargs):
    with pytest.raises(LedgerError) as caught:
        function(*args, **kwargs)
    assert caught.value.code == code
    assert str(caught.value) == code
    assert caught.value.scope == "TEST_ONLY"
    assert caught.value.operational is False


def test_three_tables_and_exact_hash_chains(store):
    directory, open_ = store
    handle = open_()
    first = create(handle)
    second = observe(handle)
    third = check(handle)
    assert (first.snapshot.version, first.snapshot.journal_sequence) == (0, 1)
    assert (third.snapshot.version, third.snapshot.journal_sequence) == (2, 3)
    db = sqlite3.connect(directory / "ledger.sqlite3")
    try:
        assert {
            r[0]
            for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")
        } == {"heads", "journal", "operations"}
        prefix = sha256()
        for event, expected in db.execute(
            "SELECT event,prefix_sha256 FROM journal ORDER BY sequence"
        ):
            prefix.update(len(event).to_bytes(8, "big"))
            prefix.update(event)
            assert prefix.hexdigest() == expected
    finally:
        db.close()
    assert third.snapshot.scope == "TEST_ONLY"
    assert second.snapshot.generation == 0


def test_historical_operation_lookup_exact_and_absent(store):
    _, open_ = store
    handle = open_()
    initial = create(handle)
    observed = observe(handle)
    assert create(handle) == initial
    result = lookup_operation(
        handle,
        **IDENTITY,
        operation_id=uid(11),
        operation_digest=observed.operation_digest,
    )
    assert result.result == observed
    assert (
        lookup_operation(
            handle, **IDENTITY, operation_id=uid(99), operation_digest="0" * 64
        ).status
        == "ABSENT"
    )
    fails(
        "OPERATION_CONFLICT",
        lookup_operation,
        handle,
        **IDENTITY,
        operation_id=uid(11),
        operation_digest="0" * 64,
    )


@pytest.mark.parametrize(
    "fault,code,found",
    [
        (Fault.BEFORE_WRITE, "PERSISTENCE_FAILURE", False),
        (Fault.BEFORE_COMMIT, "PERSISTENCE_FAILURE", False),
        (Fault.AFTER_COMMIT_BEFORE_ACK, "COMMIT_UNCERTAIN", True),
    ],
)
def test_fault_requires_new_recovery_handle_and_never_replay(store, fault, code, found):
    _, open_ = store
    handle = open_(fault=fault)
    fails(code, create, handle)
    fails("CONNECTION_POISONED", read_snapshot, handle, execution_id=uid(1))
    recovered = open_(OpenMode.RECOVER)
    report = recover(
        recovered, execution_id=None, now_ns=20, uncertain_operation_id=uid(10)
    )
    assert (report.operation.status == "FOUND") is found
    assert report.admission_open is False and report.recovered_invalidated is True
    fails("INVALIDATED", create, recovered, op=20)


@pytest.mark.parametrize("column", ["event", "prefix_sha256"])
def test_readable_chain_tamper_fails_recovery(store, column):
    directory, open_ = store
    handle = open_()
    create(handle)
    handle.close()
    db = sqlite3.connect(directory / "ledger.sqlite3")
    try:
        if column == "event":
            db.execute("UPDATE journal SET event=?", (b"{}",))
        else:
            db.execute("UPDATE journal SET prefix_sha256=?", ("0" * 64,))
        db.commit()
    finally:
        db.close()
    recovered = open_(OpenMode.RECOVER)
    with pytest.raises(LedgerError) as caught:
        recover(recovered, execution_id=None, now_ns=20, uncertain_operation_id=None)
    assert caught.value.code in ("STORAGE_CORRUPT", "RECOVERY_INVALID")
    assert recovered.state == "POISONED"


def test_oversized_cell_rejected_before_payload_read(store):
    directory, open_ = store
    handle = open_()
    create(handle)
    handle.close()
    db = sqlite3.connect(directory / "ledger.sqlite3")
    try:
        db.execute("UPDATE operations SET result=zeroblob(65537)")
        db.commit()
    finally:
        db.close()
    fails("STORAGE_CORRUPT", open_, OpenMode.RECOVER)


def test_owner_change_requires_fresh_observation(store):
    _, open_ = store
    handle = open_()
    create(handle)
    observe(handle)
    changed = commit_control_update(
        handle,
        **IDENTITY,
        operation_id=uid(20),
        expected_version=1,
        action=ControlAction.CHANGE_OWNER,
        new_owner_id=uid(30),
        now_ns=13,
    )
    assert changed.snapshot.owner_id == uid(30)
    assert (
        changed.snapshot.last_observation is None
        and changed.snapshot.lease_expires_ns == 0
    )
    new_identity = dict(IDENTITY, owner_id=uid(30))
    fails(
        "AUTHORITY_DENIED",
        commit_control_update,
        handle,
        **new_identity,
        operation_id=uid(21),
        expected_version=2,
        action=ControlAction.CHECK,
        new_owner_id=None,
        now_ns=14,
    )
    fails("OWNER_MISMATCH", check, handle, version=2, op=22)


def test_limits_shadow_validator_is_ignored(store):
    _, open_ = store
    bad = replace(LIMITS)
    object.__setattr__(bad, "record_bytes", True)
    object.__setattr__(bad, "__post_init__", lambda: None)
    fails("LIMIT_CONFIGURATION", open_, limits=bad)


def test_opaque_request_growth_is_bounded_before_encoding(store):
    _, open_ = store
    handle = open_()
    raw = b"x" * 65536
    fails(
        "RECORD_LIMIT",
        create_execution,
        handle,
        **dict(IDENTITY, request_sha256=sha256(raw).hexdigest()),
        operation_id=uid(10),
        request_bytes=raw,
        now_ns=0,
    )
    assert create(handle).snapshot.version == 0
