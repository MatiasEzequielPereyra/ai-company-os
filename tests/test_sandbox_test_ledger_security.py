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


def establish_then_acquire(handle):
    api.apply_observation(
        handle,
        **IDENTITY,
        operation_id=uid(7),
        expected_version=0,
        observation=api.Observation(
            uid(2), 1, 10, 12, api.ObservationResult.VALID, True, True
        ),
        now_ns=12,
    )
    result = api.commit_control_update(
        handle,
        **IDENTITY,
        operation_id=uid(8),
        expected_version=1,
        action=api.ControlAction.ACQUIRE_OWNER,
        new_owner_id=uid(3),
        now_ns=20,
    )
    assert result.snapshot.last_observation is None
    assert result.snapshot.lease_expires_ns == 0
    return result


def replacement(handle, sequence, now):
    return api.apply_observation(
        handle,
        **IDENTITY,
        operation_id=uid(9),
        expected_version=2,
        observation=api.Observation(
            uid(2), sequence, now - 2, now, api.ObservationResult.VALID, True, True
        ),
        now_ns=now,
    )


def test_same_owner_acquire_cannot_reset_source_sequence(ledger):
    handle, _, sink = ledger
    establish_then_acquire(handle)
    with pytest.raises(api.LedgerError) as caught:
        replacement(handle, 1, 100)
    assert caught.value.code == "OBSERVATION_ORDER"
    assert api.read_snapshot(handle, execution_id=uid(1)).version == 2
    assert (uid(1), "OBSERVATION_ORDER") in sink.requests


def test_same_owner_acquire_cannot_hide_persisted_expiry(ledger):
    handle, _, sink = ledger
    establish_then_acquire(handle)
    result = replacement(handle, 2, 100)
    assert result.snapshot.invalidated is True
    assert (uid(1), "INVALIDATED") in sink.requests
    with pytest.raises(api.LedgerError):
        api.commit_control_update(
            handle,
            **IDENTITY,
            operation_id=uid(10),
            expected_version=3,
            action=api.ControlAction.CHECK,
            new_owner_id=None,
            now_ns=101,
        )


def test_same_owner_acquire_retains_live_observation_refresh(ledger):
    handle, _, _ = ledger
    establish_then_acquire(handle)
    result = replacement(handle, 2, 30)
    assert result.snapshot.invalidated is False
    assert result.snapshot.last_observation.source_sequence == 2
    assert result.snapshot.lease_expires_ns == 80


def test_explicit_owner_change_allows_new_owner_first_observation(ledger):
    handle, _, _ = ledger
    api.apply_observation(
        handle,
        **IDENTITY,
        operation_id=uid(7),
        expected_version=0,
        observation=api.Observation(
            uid(2), 5, 10, 12, api.ObservationResult.VALID, True, True
        ),
        now_ns=12,
    )
    api.commit_control_update(
        handle,
        **IDENTITY,
        operation_id=uid(8),
        expected_version=1,
        action=api.ControlAction.CHANGE_OWNER,
        new_owner_id=uid(30),
        now_ns=20,
    )
    identity = dict(IDENTITY, owner_id=uid(30))
    result = api.apply_observation(
        handle,
        **identity,
        operation_id=uid(9),
        expected_version=2,
        observation=api.Observation(
            uid(2), 1, 98, 100, api.ObservationResult.VALID, True, True
        ),
        now_ns=100,
    )
    assert result.snapshot.invalidated is False
    assert result.snapshot.owner_id == uid(30)


@pytest.mark.parametrize("sequence,now", [(1, 30), (2, 100)])
def test_recovery_rejects_coherent_legacy_acquire_continuity_bypass(
    ledger, sequence, now
):
    import json

    handle, directory, _ = ledger
    establish_then_acquire(handle)
    replacement(handle, 2, 30)
    handle.close()

    def encode(value):
        return json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True,
            allow_nan=False,
        ).encode("utf8")

    # Rewrite a bounded, canonical transcript exactly as the vulnerable projection
    # would have produced it. All identities, hashes, heads and results agree;
    # only historical source continuity or expiry semantics are impossible.
    with sqlite3.connect(directory / "ledger.sqlite3") as c:
        event_raw = c.execute("SELECT event FROM journal WHERE sequence=4").fetchone()[
            0
        ]
        event = json.loads(event_raw)
        op = json.loads(bytes.fromhex(event["operation"]))
        op["arguments"]["now_ns"] = now
        obs = op["arguments"]["observation"]
        obs.update(source_sequence=sequence, started_ns=now - 2, finished_ns=now)
        raw = encode(op)
        event["operation"] = raw.hex()
        snapshot = event["after_snapshot"]
        snapshot.update(
            last_observation=obs, last_now_ns=now, lease_expires_ns=now + 50
        )
        changed = encode(event)
        hasher = sha256()
        for (prior,) in c.execute(
            "SELECT event FROM journal WHERE sequence<4 ORDER BY sequence"
        ):
            hasher.update(len(prior).to_bytes(8, "big"))
            hasher.update(prior)
        hasher.update(len(changed).to_bytes(8, "big"))
        hasher.update(changed)
        prefix = hasher.hexdigest()
        snapshot = dict(snapshot, journal_sha256=prefix)
        result = json.loads(
            c.execute(
                "SELECT result FROM operations WHERE operation_id=?", (uid(9),)
            ).fetchone()[0]
        )
        result.update(operation_digest=sha256(raw).hexdigest(), snapshot=snapshot)
        c.execute(
            "UPDATE journal SET event=?,prefix_sha256=? WHERE sequence=4",
            (changed, prefix),
        )
        c.execute(
            "UPDATE operations SET operation=?,operation_digest=?,result=? WHERE operation_id=?",
            (raw, sha256(raw).hexdigest(), encode(result), uid(9)),
        )
        c.execute("UPDATE heads SET snapshot=?", (encode(snapshot),))
    recovering = api.open_test_ledger(
        directory=directory,
        limits=LIMITS,
        policy=POLICY,
        mode=api.OpenMode.RECOVER,
        session_id=uid(4),
        database_id=uid(5),
        session_continuity=False,
        stop_sink=api.FakeStopSink(),
    )
    try:
        with pytest.raises(api.LedgerError) as caught:
            api.recover(
                recovering, execution_id=uid(1), now_ns=101, uncertain_operation_id=None
            )
        assert caught.value.code == "RECOVERY_INVALID"
        assert recovering.state == "POISONED"
    finally:
        recovering.close()
