"""Independent hostile storage and value checks; exclusive synthetic test storage."""

from dataclasses import replace
from hashlib import sha256
import sqlite3
from uuid import UUID

import pytest

from company_os.sandbox import test_ledger as api


def uid(n):
    return str(UUID(int=n))


LIMITS = api.LedgerLimits(65536, 4096, 4096, 8192, 100, 33554432)
POLICY = api.SyntheticPolicy(100, 10, 50)
IDENTITY = dict(
    execution_id=uid(1),
    request_sha256=sha256(b"test").hexdigest(),
    epoch=uid(2),
    owner_id=uid(3),
)


@pytest.fixture
def ledger(tmp_path):
    directory = tmp_path / "security"
    directory.mkdir()
    sink = api.FakeStopSink()
    handle = api.open_test_ledger(
        directory=directory,
        limits=LIMITS,
        policy=POLICY,
        mode=api.OpenMode.NEW,
        session_id=uid(4),
        database_id=uid(5),
        session_continuity=True,
        stop_sink=sink,
    )
    api.create_execution(
        handle, **IDENTITY, operation_id=uid(6), request_bytes=b"test", now_ns=0
    )
    yield handle, directory, sink
    handle.close()


@pytest.mark.parametrize(
    "payload",
    [
        b"\xef\xbb\xbf{}",
        b'{"a":1,"a":2}',
        b'{"a":NaN}',
        b'{"a":Infinity}',
        b'{"a":1.0}',
        b'{"a":-1}',
        b'{"a":18446744073709551616}',
        b'{"a":' + b"9" * 10000 + b"}",
        b'{"a":"\xff"}',
        b'{"a":' * 9 + b"0" + b"}" * 9,
        b"{" + b",".join(('"k%d":0' % n).encode() for n in range(65)) + b"}",
        b'{ "a":1}',
        b'{"a":true,"unknown":0}',
    ],
)
def test_hostile_snapshot_codec_poisoned_without_partial_result(ledger, payload):
    handle, directory, _ = ledger
    with sqlite3.connect(directory / "ledger.sqlite3") as connection:
        connection.execute("UPDATE heads SET snapshot=?", (payload,))
    with pytest.raises(api.LedgerError):
        api.read_snapshot(handle, execution_id=uid(1))
    assert handle.state == "POISONED"


@pytest.mark.parametrize("change", ["index", "trigger", "view", "configuration"])
def test_schema_and_effective_configuration_tamper_close_admission(ledger, change):
    handle, directory, _ = ledger
    if change == "configuration":
        handle._connection.execute("PRAGMA foreign_keys=OFF")
    else:
        sql = dict(
            index="CREATE INDEX hostile ON heads(session_id)",
            trigger="CREATE TRIGGER hostile AFTER UPDATE ON heads BEGIN SELECT 1; END",
            view="CREATE VIEW hostile AS SELECT * FROM heads",
        )[change]
        with sqlite3.connect(directory / "ledger.sqlite3") as connection:
            connection.execute(sql)
    with pytest.raises(api.LedgerError) as caught:
        api.read_snapshot(handle, execution_id=uid(1))
    assert caught.value.code == "DATABASE_CONFIGURATION"
    assert handle.state == "POISONED"


def test_oversized_cell_scalar_rejection_precedes_payload_decode(ledger, monkeypatch):
    handle, directory, _ = ledger
    with sqlite3.connect(directory / "ledger.sqlite3") as connection:
        connection.execute(
            "UPDATE operations SET result=zeroblob(?)", (LIMITS.record_bytes + 1,)
        )

    def forbidden(*args):
        pytest.fail("oversized storage reached decoder")

    monkeypatch.setattr(api, "_decode", forbidden)
    with pytest.raises(api.LedgerError) as caught:
        api.read_snapshot(handle, execution_id=uid(1))
    assert caught.value.code == "STORAGE_CORRUPT"
    assert handle.state == "POISONED"


@pytest.mark.parametrize(
    "field,value",
    [("source_sequence", True), ("lease_valid", 1), ("epoch", "not-a-uuid")],
)
def test_frozen_observation_forgery_cannot_shadow_validation(ledger, field, value):
    handle, _, _ = ledger
    obs = api.Observation(uid(2), 1, 1, 2, api.ObservationResult.VALID, True, True)
    object.__setattr__(obs, field, value)
    object.__setattr__(obs, "__post_init__", lambda: None)
    with pytest.raises(api.LedgerError) as caught:
        api.apply_observation(
            handle,
            **IDENTITY,
            operation_id=uid(7),
            expected_version=0,
            observation=obs,
            now_ns=2,
        )
    assert caught.value.code == "INVALID_ARGUMENT"
    assert api.read_snapshot(handle, execution_id=uid(1)).version == 0


def test_invalidation_latches_and_stops_before_storage_failure(ledger, monkeypatch):
    handle, _, sink = ledger

    def fail_write():
        assert uid(1) in handle._session.latches
        assert (uid(1), "INVALIDATED") in sink.requests
        raise api.LedgerError("PERSISTENCE_FAILURE")

    monkeypatch.setattr(handle, "_before_write", fail_write)
    with pytest.raises(api.LedgerError) as caught:
        api.commit_control_update(
            handle,
            **IDENTITY,
            operation_id=uid(7),
            expected_version=0,
            action=api.ControlAction.INVALIDATE,
            new_owner_id=None,
            now_ns=1,
        )
    assert caught.value.code == "PERSISTENCE_FAILURE"
    assert handle.state == "POISONED"


def test_forged_scope_fields_are_rejected_from_storage(ledger):
    handle, directory, _ = ledger
    with sqlite3.connect(directory / "ledger.sqlite3") as connection:
        raw = connection.execute("SELECT snapshot FROM heads").fetchone()[0]
        raw = raw.replace(
            b'"authority_authenticated":false', b'"authority_authenticated":true'
        )
        connection.execute("UPDATE heads SET snapshot=?", (raw,))
    with pytest.raises(api.LedgerError):
        api.read_snapshot(handle, execution_id=uid(1))
    assert handle.state == "POISONED"
