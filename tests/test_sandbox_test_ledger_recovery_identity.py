"""Independent recovery selection regressions using disposable two-execution DBs."""

from hashlib import sha256
from uuid import UUID

import pytest

from company_os.sandbox.test_ledger import (
    FakeStopSink,
    LedgerError,
    LedgerLimits,
    OpenMode,
    SyntheticPolicy,
    create_execution,
    open_test_ledger,
    recover,
)


def uid(value):
    return str(UUID(int=value))


A, B, A1, B1, ABSENT = (uid(value) for value in (1, 2, 11, 12, 99))


@pytest.fixture
def two_executions(tmp_path):
    directory = tmp_path / "exclusive-recovery-identity"
    directory.mkdir()
    handles = []

    def open_handle(mode):
        sink = FakeStopSink()
        handle = open_test_ledger(
            directory=directory,
            limits=LedgerLimits(65536, 4096, 4096, 8192, 100, 33554432),
            policy=SyntheticPolicy(100, 10, 50),
            mode=mode,
            session_id=uid(21),
            database_id=uid(22),
            session_continuity=mode is not OpenMode.RECOVER,
            stop_sink=sink,
        )
        handles.append(handle)
        return handle, sink

    writer, _ = open_handle(OpenMode.NEW)
    results = {}
    for execution, operation, request in ((A, A1, b"request-A"), (B, B1, b"request-B")):
        results[execution] = create_execution(
            writer,
            execution_id=execution,
            request_sha256=sha256(request).hexdigest(),
            epoch=uid(31),
            owner_id=uid(32),
            operation_id=operation,
            request_bytes=request,
            now_ns=0,
        )
    writer.close()
    handle, sink = open_handle(OpenMode.RECOVER)
    database = directory / "ledger.sqlite3"
    original = database.read_bytes()
    yield handle, sink, results
    for opened in handles:
        opened.close()
    assert database.read_bytes() == original, "Recovery must preserve database bytes"


@pytest.mark.parametrize("execution,operation,other", [(A, B1, B), (B, A1, A)])
def test_cross_execution_uncertain_operation_rejected(two_executions, execution, operation, other):
    handle, sink, results = two_executions
    assert handle.state == "RECOVERY_REQUIRED"
    try:
        report = recover(
            handle, execution_id=execution, now_ns=0, uncertain_operation_id=operation
        )
    except LedgerError as error:
        assert error.code == "OPERATION_CONFLICT"
        assert str(error) == "OPERATION_CONFLICT"
        assert error.scope == "TEST_ONLY"
        assert error.operational is False
        assert error.authority_authenticated is False
        assert error.execution_capability == "NONE"
    else:
        print(
            "CROSS_EXECUTION_REPORT",
            "status=" + report.status,
            "snapshot=" + report.snapshot.execution_id,
            "operation_status=" + report.operation.status,
            "operation_snapshot=" + report.operation.result.snapshot.execution_id,
            flush=True,
        )
        assert report.snapshot == results[execution].snapshot
        assert report.operation.status == "FOUND"
        assert report.operation.result == results[other]
        pytest.fail("Expected OPERATION_CONFLICT; received mixed-execution VERIFIED report")
    assert handle.state == "RECOVERY_REQUIRED"
    assert handle._recovered is False
    assert handle._session.latches == {A, B}
    assert {request[0] for request in sink.requests} == {A, B}
    # A selection conflict must not poison the connection or forbid reconciliation.
    corrected = recover(
        handle,
        execution_id=execution,
        now_ns=0,
        uncertain_operation_id=results[execution].operation_id,
    )
    assert corrected.operation.result == results[execution]


@pytest.mark.parametrize(
    "execution,operation,found",
    [(A, A1, A), (B, B1, B), (A, ABSENT, None),
     (None, A1, A), (None, B1, B), (None, ABSENT, None),
     (A, None, None), (None, None, None)],
)
def test_recovery_correct_absent_and_global_controls(two_executions, execution, operation, found):
    handle, _, results = two_executions
    report = recover(
        handle, execution_id=execution, now_ns=0, uncertain_operation_id=operation
    )
    assert report.status == "VERIFIED"
    assert report.snapshot == (None if execution is None else results[execution].snapshot)
    if operation is None:
        assert report.operation is None
    elif found is None:
        assert report.operation.status == "ABSENT"
        assert report.operation.result is None
    else:
        assert report.operation.status == "FOUND"
        assert report.operation.result == results[found]
    assert report.rows_visited == 6
    assert report.admission_open is False
    assert report.recovered_invalidated is True
    assert report.scope == "TEST_ONLY"
    assert report.operational is False
    assert report.authority_authenticated is False
    assert report.execution_capability == "NONE"
    assert handle._session.latches == {A, B}


def test_missing_execution_preserves_existing_rejection(two_executions):
    handle, _, _ = two_executions
    with pytest.raises(LedgerError) as caught:
        recover(handle, execution_id=ABSENT, now_ns=0, uncertain_operation_id=B1)
    assert caught.value.code == "EXECUTION_NOT_FOUND"
    assert handle.state == "RECOVERY_REQUIRED"
    assert handle._recovered is False
    assert handle._session.latches == {A, B}
