"""Controlled test-session subprocess proofs. Never launches candidate commands."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import time
from hashlib import sha256
from uuid import UUID, uuid4

import pytest

from company_os.sandbox import test_ledger as api
from company_os.sandbox.test_ledger_types import (
    ControlAction,
    FakeStopSink,
    Fault,
    LedgerError,
    LedgerLimits,
    OpenMode,
    SyntheticPolicy,
)


def uid(n):
    return str(UUID(int=n))


LIMITS = LedgerLimits(65536, 4096, 4096, 8192, 1000, 33554432)
POLICY = SyntheticPolicy(100, 10, 50)
EXECUTION, EPOCH, OWNER, SESSION, DATABASE = map(uid, range(1, 6))
REQUEST = b"process harness opaque test input"
DIGEST = sha256(REQUEST).hexdigest()


def opened(directory, mode, fault=Fault.NONE, limits=LIMITS):
    return api.open_test_ledger(
        directory=directory,
        limits=limits,
        policy=POLICY,
        mode=mode,
        session_id=SESSION,
        database_id=DATABASE,
        session_continuity=mode is not OpenMode.RECOVER,
        fault=fault,
        stop_sink=FakeStopSink(),
    )


def create(ledger):
    return api.create_execution(
        ledger,
        execution_id=EXECUTION,
        request_sha256=DIGEST,
        epoch=EPOCH,
        owner_id=OWNER,
        operation_id=uid(10),
        request_bytes=REQUEST,
        now_ns=0,
    )


def acquire(ledger, operation):
    return api.commit_control_update(
        ledger,
        execution_id=EXECUTION,
        request_sha256=DIGEST,
        epoch=EPOCH,
        owner_id=OWNER,
        operation_id=operation,
        expected_version=0,
        action=ControlAction.ACQUIRE_OWNER,
        new_owner_id=OWNER,
        now_ns=1,
    )


def wait_file(path, child=None, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
        if child is not None and child.poll() is not None:
            raise AssertionError(f"controlled child exited {child.returncode}")
        time.sleep(0.01)
    raise AssertionError("controlled handshake timed out")


def signal(path, token, **values):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(dict(token=token, **values)), encoding="utf-8")
    temporary.replace(path)


class Child:
    def __init__(self, directory, mode, operation):
        self.token = uuid4().hex
        self.root = directory
        self.ready = directory / (self.token + ".ready")
        self.go = directory / (self.token + ".go")
        self.result = directory / (self.token + ".result")
        env = os.environ.copy()
        env["PYTHONPATH"] = str(Path(__file__).resolve().parents[1] / "src")
        self.process = subprocess.Popen(
            [
                sys.executable,
                str(Path(__file__).resolve()),
                mode,
                str(directory / "db"),
                self.token,
                operation,
            ],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.identified = False

    def handshake(self):
        message = wait_file(self.ready, self.process)
        assert message["token"] == self.token
        assert message["pid"] == self.process.pid
        self.identified = True
        return message

    def release(self):
        signal(self.go, self.token)

    def terminate_owned(self):
        # No process discovery or group termination: only this Popen's PID.
        if self.process.poll() is None:
            if not self.identified:
                self.handshake()
            assert (
                self.identified
            ), "must identify unique owned child before termination"
            self.process.kill()
        self.process.wait(timeout=10)

    def finish(self):
        message = wait_file(self.result, self.process)
        assert message["token"] == self.token
        self.process.wait(timeout=10)
        assert self.process.returncode == 0
        return message


def prepare(tmp_path):
    assert (
        tmp_path.drive.upper() == "C:"
    ), "process tests require explicit C: pytest temporary root"
    directory = tmp_path / "db"
    directory.mkdir()
    ledger = opened(directory, OpenMode.NEW)
    create(ledger)
    return directory, ledger


def test_two_independent_connections_exact_cas(tmp_path):
    directory, creator = prepare(tmp_path)
    barrier = Barrier(2, timeout=10)

    def contender(operation):
        # SQLite handles are created and closed in their own owning threads.
        ledger = opened(directory, OpenMode.ATTACH)
        try:
            barrier.wait()
            try:
                return acquire(ledger, operation).outcome
            except LedgerError as exc:
                return exc.code
        finally:
            ledger.close()

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(contender, uid(n)) for n in (20, 21)]
            assert sorted(f.result(timeout=15) for f in futures) == [
                "CAS_CONFLICT",
                "COMMITTED",
            ]
        assert api.read_snapshot(creator, execution_id=EXECUTION).version == 1
    finally:
        creator.close()


def test_two_processes_exact_cas(tmp_path):
    directory, creator = prepare(tmp_path)
    children = []
    try:
        for n in (20, 21):
            children.append(Child(tmp_path, "race", uid(n)))
        for child in children:
            child.handshake()
        for child in children:
            child.release()
        results = [child.finish()["outcome"] for child in children]
        assert sorted(results) == ["CAS_CONFLICT", "COMMITTED"]
        assert api.read_snapshot(creator, execution_id=EXECUTION).version == 1
        with sqlite3.connect(directory / "ledger.sqlite3") as connection:
            assert connection.execute("SELECT count(*) FROM journal").fetchone()[0] == 2
            assert (
                connection.execute("SELECT count(*) FROM operations").fetchone()[0] == 2
            )
    finally:
        for child in children:
            child.terminate_owned()
        creator.close()


@pytest.mark.parametrize(
    "point,expected,version", [("before", "ABSENT", 0), ("after", "FOUND", 1)]
)
def test_owned_process_crash_recovery(tmp_path, point, expected, version):
    directory, creator = prepare(tmp_path)
    child = Child(tmp_path, point, uid(30))
    try:
        message = child.handshake()
        assert message["point"] == point
        if point == "before":
            assert message["journal_bytes"] > 0
            assert message["database_bytes"] <= LIMITS.sqlite_database_bytes
        # All cooperating writers are paused: child hook blocks and parent closes.
        creator.close()
        child.terminate_owned()
        recovered = opened(directory, OpenMode.RECOVER)
        try:
            report = api.recover(
                recovered,
                execution_id=EXECUTION,
                now_ns=2,
                uncertain_operation_id=uid(30),
            )
            assert report.status == "VERIFIED"
            assert report.operation.status == expected
            assert report.snapshot.version == version
            assert report.admission_open is False
            assert report.recovered_invalidated is True
            with pytest.raises(LedgerError):
                acquire(recovered, uid(31))
            assert (
                api.read_snapshot(recovered, execution_id=EXECUTION).version == version
            )
        finally:
            recovered.close()
    finally:
        child.terminate_owned()
        creator.close()


@pytest.mark.parametrize(
    "fault,code,expected",
    [
        (Fault.BEFORE_WRITE, "PERSISTENCE_FAILURE", "ABSENT"),
        (Fault.BEFORE_COMMIT, "PERSISTENCE_FAILURE", "ABSENT"),
        (Fault.AFTER_COMMIT_BEFORE_ACK, "COMMIT_UNCERTAIN", "FOUND"),
    ],
)
def test_fault_ack_recovery_no_replay(tmp_path, fault, code, expected):
    directory, creator = prepare(tmp_path)
    writer = opened(directory, OpenMode.ATTACH, fault)
    try:
        with pytest.raises(LedgerError) as caught:
            acquire(writer, uid(40))
        assert caught.value.code == code
        assert writer.state == "POISONED"
        with pytest.raises(LedgerError):
            api.read_snapshot(writer, execution_id=EXECUTION)
    finally:
        writer.close()
        creator.close()
    recovered = opened(directory, OpenMode.RECOVER)
    try:
        report = api.recover(
            recovered, execution_id=EXECUTION, now_ns=2, uncertain_operation_id=uid(40)
        )
        assert report.operation.status == expected
        assert not report.admission_open and report.recovered_invalidated
    finally:
        recovered.close()


def _child_main():
    mode, directory, token, operation = sys.argv[1:]
    directory = Path(directory)
    root = directory.parent
    ledger = opened(directory, OpenMode.ATTACH)
    try:
        if mode != "race":

            def pause(self):
                journal = directory / "ledger.sqlite3-journal"
                signal(
                    root / (token + ".ready"),
                    token,
                    pid=os.getpid(),
                    point=mode,
                    journal_bytes=journal.stat().st_size if journal.exists() else 0,
                    database_bytes=(directory / "ledger.sqlite3").stat().st_size,
                )
                # Parent alone controls own subprocess; no further admission occurs.
                wait_file(root / (token + ".go"), timeout=30)

            setattr(
                api.TestLedger,
                "_before_commit" if mode == "before" else "_after_commit",
                pause,
            )
        else:
            signal(root / (token + ".ready"), token, pid=os.getpid())
            assert wait_file(root / (token + ".go"))["token"] == token
        try:
            acquire(ledger, operation)
            outcome = "COMMITTED"
        except LedgerError as exc:
            outcome = exc.code
        signal(root / (token + ".result"), token, outcome=outcome)
    finally:
        ledger.close()


if __name__ == "__main__":
    _child_main()


def test_database_file_cap_is_not_journal_quota(tmp_path):
    from dataclasses import replace

    assert tmp_path.drive.upper() == "C:"
    directory = tmp_path / "small-db"
    directory.mkdir()
    limits = replace(LIMITS, sqlite_database_bytes=65536)
    ledger = opened(directory, OpenMode.NEW, limits=limits)
    committed = 0
    try:
        connection = ledger._connection
        assert (
            connection.execute("PRAGMA journal_mode").fetchone()[0].lower() == "delete"
        )
        assert connection.execute("PRAGMA synchronous").fetchone()[0] == 2
        assert connection.execute("PRAGMA foreign_keys").fetchone()[0] == 1
        assert (
            connection.execute("PRAGMA busy_timeout").fetchone()[0]
            == limits.busy_timeout_ms
        )
        page_size = connection.execute("PRAGMA page_size").fetchone()[0]
        assert (
            connection.execute("PRAGMA max_page_count").fetchone()[0]
            == limits.sqlite_database_bytes // page_size
        )
        for n in range(100):
            try:
                api.create_execution(
                    ledger,
                    execution_id=uid(1000 + n),
                    request_sha256=DIGEST,
                    epoch=EPOCH,
                    owner_id=OWNER,
                    operation_id=uid(2000 + n),
                    request_bytes=REQUEST,
                    now_ns=0,
                )
                committed += 1
            except LedgerError as exc:
                assert exc.code in {"CAPACITY_LIMIT", "PERSISTENCE_FAILURE"}
                assert ledger.state == "POISONED"
                break
        else:
            pytest.fail("small explicit database cap did not reject bounded growth")
        assert committed > 0
        assert (
            directory / "ledger.sqlite3"
        ).stat().st_size <= limits.sqlite_database_bytes
    finally:
        ledger.close()
    recovered = opened(directory, OpenMode.RECOVER, limits=limits)
    try:
        report = api.recover(
            recovered, execution_id=None, now_ns=1, uncertain_operation_id=None
        )
        assert report.status == "VERIFIED"
        assert report.rows_visited == committed * 3
        assert report.admission_open is False
    finally:
        recovered.close()
