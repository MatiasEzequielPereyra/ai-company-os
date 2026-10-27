"""Independent public API checks for recovery execution/operation binding."""

from hashlib import sha256
import sqlite3
from uuid import UUID

import pytest

from company_os.sandbox.test_ledger import (
    ControlAction, FakeStopSink, LedgerError, LedgerLimits, Observation,
    ObservationResult, OpenMode, SyntheticPolicy, apply_observation,
    commit_control_update, create_execution, open_test_ledger, read_snapshot,
    recover,
)


def uid(value):
    return str(UUID(int=value))


@pytest.fixture
def two_executions(tmp_path):
    directory = tmp_path / "identity-qa"
    directory.mkdir()
    handles = []

    def open_handle(mode):
        handle = open_test_ledger(
            directory=directory,
            limits=LedgerLimits(65536, 4096, 4096, 8192, 100, 33554432),
            policy=SyntheticPolicy(100, 10, 50), mode=mode,
            session_id=uid(900), database_id=uid(901),
            session_continuity=mode is not OpenMode.RECOVER,
            stop_sink=FakeStopSink(),
        )
        handles.append(handle)
        return handle

    writer = open_handle(OpenMode.NEW)
    identities, results = [], []
    for number in (1, 2):
        raw = ("synthetic request " + str(number)).encode("ascii")
        identity = dict(execution_id=uid(number), request_sha256=sha256(raw).hexdigest(),
                        epoch=uid(10 + number), owner_id=uid(20 + number))
        created = create_execution(writer, **identity, operation_id=uid(100 + number),
                                   request_bytes=raw, now_ns=0)
        observed = apply_observation(
            writer, **identity, operation_id=uid(200 + number), expected_version=0,
            observation=Observation(identity["epoch"], 1, 10, 12,
                                    ObservationResult.VALID, True, True), now_ns=12,
        )
        identities.append(identity)
        results.append((created, observed))
    writer.close()
    yield directory, open_handle, identities, results
    for handle in handles:
        handle.close()


def disk_evidence(directory):
    """Independent read-only connection plus exact database bytes."""
    path = directory / "ledger.sqlite3"
    with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True) as connection:
        assert connection.execute("PRAGMA integrity_check").fetchone() == ("ok",)
        assert connection.execute("PRAGMA foreign_key_check").fetchall() == []
        rows = tuple(
            tuple(connection.execute(query))
            for query in (
                "SELECT * FROM heads ORDER BY execution_id",
                "SELECT * FROM journal ORDER BY execution_id,sequence",
                "SELECT * FROM operations ORDER BY operation_id",
            )
        )
    return sha256(path.read_bytes()).hexdigest(), rows


def error(code, function, *args, **kwargs):
    with pytest.raises(LedgerError) as caught:
        function(*args, **kwargs)
    failure = caught.value
    assert failure.code == str(failure) == code
    assert failure.scope == "TEST_ONLY"
    assert failure.operational is False
    assert failure.authority_authenticated is False
    assert failure.execution_capability == "NONE"


@pytest.mark.parametrize("selected", [0, 1], ids=["A-selects-B", "B-selects-A"])
@pytest.mark.parametrize("operation_index", [0, 1], ids=["creation", "observation"])
@pytest.mark.parametrize("previous_success", [False, True], ids=["initial", "after-verified"])
def test_cross_execution_recovery_rejects_without_report_or_writes(
    two_executions, selected, operation_index, previous_success,
):
    directory, open_handle, identities, results = two_executions
    ledger = open_handle(OpenMode.RECOVER)
    before = disk_evidence(directory)
    if previous_success:
        report = recover(ledger, execution_id=identities[selected]["execution_id"],
                         now_ns=13, uncertain_operation_id=results[selected][1].operation_id)
        assert report.operation.result == results[selected][1]
    error("OPERATION_CONFLICT", recover, ledger,
          execution_id=identities[selected]["execution_id"], now_ns=14,
          uncertain_operation_id=results[1 - selected][operation_index].operation_id)
    assert ledger.state == ("READY" if previous_success else "RECOVERY_REQUIRED")
    # A failed selection never grants new recovery write rights. After a previous
    # success, recovery's irreversible admission closure still blocks CHECK.
    error("INVALIDATED" if previous_success else "RECOVERY_REQUIRED",
          commit_control_update, ledger, **identities[selected], operation_id=uid(500),
          expected_version=1, action=ControlAction.CHECK if previous_success
          else ControlAction.INVALIDATE, new_owner_id=None, now_ns=14)
    assert disk_evidence(directory) == before
    for identity, historical in zip(identities, results):
        assert read_snapshot(ledger, execution_id=identity["execution_id"]) == historical[1].snapshot
    # The same handle can reconcile with the correct historical identity; it
    # still cannot execute positive authority updates or replay an absent op.
    report = recover(ledger, execution_id=identities[selected]["execution_id"],
                     now_ns=15, uncertain_operation_id=results[selected][operation_index].operation_id)
    assert report.status == "VERIFIED"
    assert report.operation.result == results[selected][operation_index]
    assert report.snapshot == results[selected][1].snapshot
    assert report.admission_open is False and report.recovered_invalidated is True
    error("INVALIDATED", commit_control_update, ledger, **identities[selected],
          operation_id=uid(501), expected_version=1, action=ControlAction.ACQUIRE_OWNER,
          new_owner_id=identities[selected]["owner_id"], now_ns=15)
    assert disk_evidence(directory) == before


@pytest.mark.parametrize("selected", [None, 0, 1], ids=["global", "A", "B"])
def test_absent_operation_is_not_replayed(two_executions, selected):
    directory, open_handle, identities, _results = two_executions
    ledger = open_handle(OpenMode.RECOVER)
    before = disk_evidence(directory)
    for _ in range(2):
        report = recover(ledger, execution_id=None if selected is None else identities[selected]["execution_id"],
                         now_ns=13, uncertain_operation_id=uid(800))
        assert report.status == "VERIFIED"
        assert report.operation.status == "ABSENT" and report.operation.result is None
        assert report.admission_open is False and report.recovered_invalidated is True
        assert disk_evidence(directory) == before


@pytest.mark.parametrize("execution", [0, 1])
@pytest.mark.parametrize("operation_index", [0, 1])
def test_global_recovery_retains_historical_found(two_executions, execution, operation_index):
    directory, open_handle, _identities, results = two_executions
    ledger = open_handle(OpenMode.RECOVER)
    before = disk_evidence(directory)
    historical = results[execution][operation_index]
    report = recover(ledger, execution_id=None, now_ns=13,
                     uncertain_operation_id=historical.operation_id)
    assert report.status == "VERIFIED" and report.snapshot is None
    assert report.operation.status == "FOUND" and report.operation.result == historical
    assert report.rows_visited == 10
    assert report.admission_open is False and report.recovered_invalidated is True
    assert disk_evidence(directory) == before


@pytest.mark.parametrize("operation_id", [uid(101), uid(800), None])
def test_missing_execution_preserves_error_precedence(two_executions, operation_id):
    directory, open_handle, _identities, _results = two_executions
    ledger = open_handle(OpenMode.RECOVER)
    before = disk_evidence(directory)
    error("EXECUTION_NOT_FOUND", recover, ledger, execution_id=uid(999),
          now_ns=13, uncertain_operation_id=operation_id)
    assert ledger.state == "RECOVERY_REQUIRED"
    assert disk_evidence(directory) == before
