"""Bounded SQLite ledger for cooperative synthetic tests, never an execution port.

The harness owns exclusive temporary namespaces and cross-process continuity.
SQLite and these public Python values do not authenticate that assertion.
"""

from dataclasses import fields, replace
from enum import Enum
from hashlib import sha256
import json
from pathlib import Path
import sqlite3
import threading

from .test_ledger_types import (
    U64,
    CEILINGS,
    LedgerError,
    LedgerLimits,
    SyntheticPolicy,
    Observation,
    ObservationResult,
    ControlAction,
    Fault,
    OpenMode,
    Snapshot,
    OperationResult,
    LookupResult,
    RecoveryReport,
    FakeStopSink,
    require,
    integer,
    identifier,
    digest,
    validate_record,
)

__test__ = False
CODEC = "TEST_CONTROL_LEDGER_V1"
_EMPTY_HASH = sha256(b"").hexdigest()
_SCHEMA = (
    "CREATE TABLE heads (execution_id TEXT PRIMARY KEY NOT NULL, database_id TEXT NOT NULL, session_id TEXT NOT NULL, snapshot BLOB NOT NULL)",
    "CREATE TABLE journal (execution_id TEXT NOT NULL, sequence INTEGER NOT NULL, operation_id TEXT NOT NULL UNIQUE, event BLOB NOT NULL, prefix_sha256 TEXT NOT NULL, PRIMARY KEY (execution_id, sequence), FOREIGN KEY (execution_id) REFERENCES heads(execution_id))",
    "CREATE TABLE operations (operation_id TEXT PRIMARY KEY NOT NULL, execution_id TEXT NOT NULL, operation_digest TEXT NOT NULL, operation BLOB NOT NULL, result BLOB NOT NULL, FOREIGN KEY (execution_id) REFERENCES heads(execution_id))",
)
_COLUMNS = {
    "heads": (
        ("execution_id", "text", 36),
        ("database_id", "text", 36),
        ("session_id", "text", 36),
        ("snapshot", "blob", None),
    ),
    "journal": (
        ("execution_id", "text", 36),
        ("sequence", "integer", 0),
        ("operation_id", "text", 36),
        ("event", "blob", None),
        ("prefix_sha256", "text", 64),
    ),
    "operations": (
        ("operation_id", "text", 36),
        ("execution_id", "text", 36),
        ("operation_digest", "text", 64),
        ("operation", "blob", None),
        ("result", "blob", None),
    ),
}
_SESSION_LOCK = threading.RLock()
_SESSIONS = {}
_USED_NAMESPACES = set()


def _plain(value):
    if isinstance(value, Enum):
        return value.value
    if type(value) in (
        LedgerLimits,
        SyntheticPolicy,
        Observation,
        Snapshot,
        OperationResult,
        LookupResult,
        RecoveryReport,
    ):
        return {item.name: _plain(getattr(value, item.name)) for item in fields(value)}
    if type(value) is dict:
        return {key: _plain(item) for key, item in value.items()}
    return value


def _size(value, depth=0):
    """Conservative size before allocation, including JSON escaping overhead."""
    require(depth <= 8, "RECORD_LIMIT")
    if value is None:
        return 4
    if type(value) is bool:
        return 5
    if type(value) is int:
        integer(value)
        return 20
    if type(value) is str:
        # All generated text is ASCII. Unicode can only occur in hostile storage.
        require(value.isascii(), "INVALID_ARGUMENT")
        return 2 + sum(6 if ord(c) < 32 else 2 if c in '\\"' else 1 for c in value)
    require(type(value) is dict and len(value) <= 64)
    return 2 + sum(
        _size(k, depth + 1) + 1 + _size(v, depth + 1) + 1 for k, v in value.items()
    )


def _encode(value, limit):
    require(_size(value) <= limit, "RECORD_LIMIT")
    raw = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False
    ).encode("utf-8")
    require(len(raw) <= limit, "RECORD_LIMIT")
    return raw


def _decode(raw, limit):
    require(type(raw) is bytes and 0 < len(raw) <= limit, "STORAGE_CORRUPT")
    require(not raw.startswith(b"\xef\xbb\xbf"), "STORAGE_CORRUPT")
    # Bound depth AND collection entries before invoking the JSON parser.
    stack = []
    quoted = escaped = False
    for ch in raw:
        if quoted:
            if escaped:
                escaped = False
            elif ch == 92:
                escaped = True
            elif ch == 34:
                quoted = False
            continue
        if ch == 34:
            quoted = True
            if stack:
                stack[-1][1] = True
        elif ch in (123, 91):
            if stack:
                stack[-1][1] = True
            stack.append([0, False])
            require(len(stack) <= 8, "STORAGE_CORRUPT")
        elif ch in (125, 93):
            require(bool(stack), "STORAGE_CORRUPT")
            commas, nonempty = stack.pop()
            require(not nonempty or commas + 1 <= 64, "STORAGE_CORRUPT")
        elif ch == 44:
            require(bool(stack), "STORAGE_CORRUPT")
            stack[-1][0] += 1
            require(stack[-1][0] < 64, "STORAGE_CORRUPT")
        elif ch not in b" \r\n\t:" and stack:
            stack[-1][1] = True
    require(not stack and not quoted, "STORAGE_CORRUPT")

    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "STORAGE_CORRUPT")
            result[key] = value
        return result

    def bad(_):
        raise LedgerError("STORAGE_CORRUPT")

    def number(text):
        require(len(text) <= 20 and not text.startswith("-"), "STORAGE_CORRUPT")
        value = int(text)
        integer(value, code="STORAGE_CORRUPT")
        return value

    try:
        obj = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=pairs,
            parse_int=number,
            parse_float=bad,
            parse_constant=bad,
        )
        require(_encode(obj, limit) == raw, "STORAGE_CORRUPT")
        return obj
    except LedgerError:
        raise LedgerError("STORAGE_CORRUPT") from None
    except (UnicodeError, ValueError, RecursionError, TypeError):
        raise LedgerError("STORAGE_CORRUPT") from None


def _shape(value, names):
    require(type(value) is dict and set(value) == set(names), "STORAGE_CORRUPT")


def _record(cls, value):
    _shape(value, [item.name for item in fields(cls)])
    values = dict(value)
    for item in fields(cls):
        if not item.init:
            require(
                type(values[item.name]) is type(item.default)
                and values.pop(item.name) == item.default,
                "STORAGE_CORRUPT",
            )
    try:
        if cls is Observation:
            values["result"] = ObservationResult(values["result"])
        elif cls is Snapshot and values["last_observation"] is not None:
            values["last_observation"] = _record(
                Observation, values["last_observation"]
            )
        elif cls is OperationResult:
            values["snapshot"] = _record(Snapshot, values["snapshot"])
        result = cls(**values)
        validate_record(result, cls)
        return result
    except (ValueError, TypeError, LedgerError):
        raise LedgerError("STORAGE_CORRUPT") from None


def _checked_copy(value, cls):
    require(type(value) is cls)
    validate_record(value, cls)
    # Reconstruct with the class, ignoring instance-shadowed methods and fields.
    return cls(
        **{item.name: getattr(value, item.name) for item in fields(cls) if item.init}
    )


class _Session:
    def __init__(self):
        self.latches = set()
        self.executions = set()
        self.failed = False


class TestLedger:
    """Explicit connection handle. Only close is legal after poison."""

    __test__ = False

    def __init__(
        self,
        connection,
        directory,
        limits,
        policy,
        mode,
        session_id,
        database_id,
        fault,
        stop_sink,
        session,
    ):
        self._connection = connection
        self._directory = directory
        self._limits = limits
        self._policy = policy
        self._mode = mode
        self._session_id = session_id
        self._database_id = database_id
        self._fault = fault
        self._stop_sink = stop_sink
        self._session = session
        self._state = "RECOVERY_REQUIRED" if mode is OpenMode.RECOVER else "READY"
        self._recovered = False

    @property
    def state(self):
        return self._state

    def close(self):
        if self._state != "CLOSED":
            self._connection.close()
            self._state = "CLOSED"

    def __enter__(self):
        self._check()
        return self

    def __exit__(self, *_):
        self.close()

    def _check(self):
        require(self._state != "POISONED", "CONNECTION_POISONED")
        require(self._state != "CLOSED", "CONNECTION_CLOSED")

    def _latch(self, execution_id, reason):
        with _SESSION_LOCK:
            self._session.executions.add(execution_id)
            self._session.latches.add(execution_id)
        try:
            FakeStopSink.stop(self._stop_sink, execution_id, reason)
        except Exception:
            self._poison("PERSISTENCE_FAILURE", execution_id, emit=False)
            raise LedgerError("PERSISTENCE_FAILURE") from None

    def _poison(self, reason, execution_id=None, *, emit=True):
        with _SESSION_LOCK:
            self._session.failed = True
            if execution_id is not None:
                self._session.executions.add(execution_id)
            self._session.latches.update(self._session.executions)
            executions = tuple(self._session.executions)
        self._state = "POISONED"
        try:
            self._connection.close()
        except sqlite3.Error:
            pass
        if emit:
            for item in executions:
                try:
                    FakeStopSink.stop(self._stop_sink, item, reason)
                except Exception:
                    pass

    def _before_write(self):
        if self._fault is Fault.BEFORE_WRITE:
            raise LedgerError("PERSISTENCE_FAILURE")

    def _before_commit(self):
        if self._fault is Fault.BEFORE_COMMIT:
            raise LedgerError("PERSISTENCE_FAILURE")

    def _after_commit(self):
        if self._fault is Fault.AFTER_COMMIT_BEFORE_ACK:
            raise LedgerError("COMMIT_UNCERTAIN")


def _config(ledger):
    c = ledger._connection
    limits = ledger._limits
    for key, expected in (
        ("journal_mode", "delete"),
        ("synchronous", 2),
        ("foreign_keys", 1),
        ("busy_timeout", limits.busy_timeout_ms),
    ):
        require(
            c.execute("PRAGMA " + key).fetchone()[0] == expected,
            "DATABASE_CONFIGURATION",
        )
    require(
        c.getlimit(sqlite3.SQLITE_LIMIT_LENGTH) == 8 * limits.record_bytes,
        "DATABASE_CONFIGURATION",
    )
    page_size = c.execute("PRAGMA page_size").fetchone()[0]
    cap = limits.sqlite_database_bytes // page_size
    require(
        c.execute("PRAGMA max_page_count").fetchone()[0] == cap,
        "DATABASE_CONFIGURATION",
    )
    require(c.execute("PRAGMA page_count").fetchone()[0] <= cap, "CAPACITY_LIMIT")
    require(
        (ledger._directory / "ledger.sqlite3").stat().st_size
        <= limits.sqlite_database_bytes,
        "CAPACITY_LIMIT",
    )
    # Bound schema text BEFORE fetching it. SQLite metadata is untrusted too.
    count = c.execute("SELECT count(*) FROM sqlite_master").fetchone()[0]
    require(count == 7, "DATABASE_CONFIGURATION")
    bad = c.execute(
        "SELECT count(*) FROM sqlite_master WHERE typeof(name)!='text' OR length(name)>128 OR typeof(type)!='text' OR length(type)>16 OR typeof(tbl_name)!='text' OR length(tbl_name)>128 OR (sql IS NOT NULL AND (typeof(sql)!='text' OR length(sql)>2048))"
    ).fetchone()[0]
    require(bad == 0, "DATABASE_CONFIGURATION")
    tables = {}
    indexes = []
    for kind, name, table, sql in c.execute(
        "SELECT type,name,tbl_name,sql FROM sqlite_master"
    ):
        if kind == "table":
            tables[name] = sql
        else:
            require(kind == "index" and sql is None, "DATABASE_CONFIGURATION")
            indexes.append((name, table))
    require(
        tables == dict(zip(("heads", "journal", "operations"), _SCHEMA)),
        "DATABASE_CONFIGURATION",
    )
    require(
        set(indexes)
        == {
            ("sqlite_autoindex_heads_1", "heads"),
            ("sqlite_autoindex_journal_1", "journal"),
            ("sqlite_autoindex_journal_2", "journal"),
            ("sqlite_autoindex_operations_1", "operations"),
        },
        "DATABASE_CONFIGURATION",
    )


def _precheck(ledger):
    """Scalar checks never materialize a text/blob cell."""
    _config(ledger)
    c, limits = ledger._connection, ledger._limits
    counts = {}
    for table, maximum in (
        ("heads", limits.journal_rows),
        ("journal", limits.journal_rows),
        ("operations", limits.operation_count),
    ):
        count = c.execute("SELECT count(*) FROM " + table).fetchone()[0]
        require(count <= maximum, "CAPACITY_LIMIT")
        counts[table] = count
        conditions = []
        for name, kind, length in _COLUMNS[table]:
            conditions.append("typeof(" + name + ")!='" + kind + "'")
            if kind != "integer":
                bound = limits.record_bytes if length is None else length
                conditions.append("length(" + name + ")>" + str(bound))
                if length is not None:
                    conditions.append("length(" + name + ")!=" + str(length))
            else:
                conditions.append(name + "<1")
        bad = c.execute(
            "SELECT count(*) FROM " + table + " WHERE " + " OR ".join(conditions)
        ).fetchone()[0]
        require(bad == 0, "STORAGE_CORRUPT")
    return counts


def _envelope(
    ledger, api, execution_id, request_sha256, epoch, owner_id, operation_id, arguments
):
    for value in (execution_id, epoch, owner_id, operation_id):
        identifier(value)
    digest(request_sha256)
    result = dict(
        api=api,
        execution_id=execution_id,
        request_sha256=request_sha256,
        epoch=epoch,
        owner_id=owner_id,
        operation_id=operation_id,
        session_id=ledger._session_id,
        database_id=ledger._database_id,
        arguments=arguments,
    )
    return _encode(result, ledger._limits.record_bytes)


def _validate_envelope(ledger, raw):
    value = _decode(raw, ledger._limits.record_bytes)
    _shape(
        value,
        (
            "api",
            "execution_id",
            "request_sha256",
            "epoch",
            "owner_id",
            "operation_id",
            "session_id",
            "database_id",
            "arguments",
        ),
    )
    try:
        for name in (
            "execution_id",
            "epoch",
            "owner_id",
            "operation_id",
            "session_id",
            "database_id",
        ):
            identifier(value[name])
        digest(value["request_sha256"])
        require(
            value["session_id"] == ledger._session_id
            and value["database_id"] == ledger._database_id,
            "IDENTITY_MISMATCH",
        )
        args = value["arguments"]
        api = value["api"]
        if api == "create_execution":
            _shape(
                args,
                (
                    "request_bytes",
                    "now_ns",
                    "limits",
                    "policy",
                    "session_id",
                    "database_id",
                ),
            )
            require(
                _encode(args["limits"], ledger._limits.record_bytes)
                == _encode(_plain(ledger._limits), ledger._limits.record_bytes)
                and _encode(args["policy"], ledger._limits.record_bytes)
                == _encode(_plain(ledger._policy), ledger._limits.record_bytes),
                "DATABASE_CONFIGURATION",
            )
            require(
                args["session_id"] == ledger._session_id
                and args["database_id"] == ledger._database_id,
                "IDENTITY_MISMATCH",
            )
            text = args["request_bytes"]
            require(
                type(text) is str
                and len(text) % 2 == 0
                and len(text) <= ledger._limits.record_bytes
            )
            require(all(ch in "0123456789abcdef" for ch in text))
            request = bytes.fromhex(text)
            require(sha256(request).hexdigest() == value["request_sha256"])
        elif api == "apply_observation":
            _shape(args, ("expected_version", "observation", "now_ns"))
            integer(args["expected_version"])
            _record(Observation, args["observation"])
        elif api == "commit_control_update":
            _shape(args, ("expected_version", "action", "new_owner_id", "now_ns"))
            integer(args["expected_version"])
            require(type(args["action"]) is str)
            action = ControlAction(args["action"])
            new_owner = args["new_owner_id"]
            if new_owner is not None:
                identifier(new_owner)
            if action is ControlAction.ACQUIRE_OWNER:
                require(new_owner == value["owner_id"])
            elif action is ControlAction.CHANGE_OWNER:
                require(new_owner is not None and new_owner != value["owner_id"])
            else:
                require(new_owner is None)
        else:
            raise LedgerError("STORAGE_CORRUPT")
        integer(args["now_ns"])
    except (ValueError, TypeError):
        raise LedgerError("STORAGE_CORRUPT") from None
    return value


def _expired(snapshot, now, policy, continuity=None):
    if continuity is not None:
        snapshot = continuity
    obs = snapshot.last_observation
    return obs is not None and (
        now >= snapshot.lease_expires_ns or now - obs.started_ns > policy.freshness_ns
    )


def _project(ledger, before, op, continuity=None):
    """The one control projection used by live writes and bounded recovery."""
    args, api = op["arguments"], op["api"]
    now = args["now_ns"]
    if api == "create_execution":
        require(before is None, "EXECUTION_EXISTS")
        return Snapshot(
            op["execution_id"],
            op["request_sha256"],
            op["epoch"],
            0,
            1,
            _EMPTY_HASH,
            op["owner_id"],
            False,
            None,
            0,
            now,
            0,
        )
    require(before is not None, "EXECUTION_NOT_FOUND")
    require(
        (before.execution_id, before.request_sha256, before.epoch)
        == (op["execution_id"], op["request_sha256"], op["epoch"]),
        "IDENTITY_MISMATCH",
    )
    require(before.version == args["expected_version"], "CAS_CONFLICT")
    require(before.owner_id in (None, op["owner_id"]), "OWNER_MISMATCH")
    require(now >= before.last_now_ns, "CLOCK_ORDER")
    integer(before.version + 1)
    integer(before.journal_sequence + 1, 1)
    after = replace(
        before,
        version=before.version + 1,
        journal_sequence=before.journal_sequence + 1,
        last_now_ns=now,
    )
    expired = _expired(before, now, ledger._policy, continuity)
    if api == "apply_observation":
        obs = _record(Observation, args["observation"])
        old = (before if continuity is None else continuity).last_observation
        require(
            obs.epoch == before.epoch
            and (
                old is None
                or (
                    obs.source_sequence > old.source_sequence
                    and obs.started_ns >= old.started_ns
                    and obs.finished_ns >= old.finished_ns
                )
            ),
            "OBSERVATION_ORDER",
        )
        expiry = obs.finished_ns + ledger._policy.lease_duration_ns
        integer(expiry)
        valid = (
            obs.result is ObservationResult.VALID
            and obs.lease_valid
            and obs.continuity_valid
            and now >= obs.finished_ns
            and obs.finished_ns - obs.started_ns
            <= ledger._policy.evaluation_duration_ns
            and now - obs.started_ns <= ledger._policy.freshness_ns
            and now < expiry
        )
        require(not before.invalidated or not valid, "INVALIDATED")
        if expired and valid:
            # Record the discovered loss, never a replacement positive lease.
            return replace(after, invalidated=True)
        return replace(
            after,
            last_observation=obs,
            lease_expires_ns=expiry,
            invalidated=before.invalidated or expired or not valid,
        )
    action = ControlAction(args["action"])
    require(not before.invalidated or action is ControlAction.INVALIDATE, "INVALIDATED")
    if expired:
        return replace(after, invalidated=True)
    if action is ControlAction.INVALIDATE:
        return replace(after, invalidated=True)
    require(not before.invalidated, "INVALIDATED")
    if action is ControlAction.ACQUIRE_OWNER:
        return replace(
            after, owner_id=op["owner_id"], last_observation=None, lease_expires_ns=0
        )
    require(before.owner_id == op["owner_id"], "OWNER_MISMATCH")
    obs = before.last_observation
    require(
        obs is not None
        and obs.result is ObservationResult.VALID
        and obs.lease_valid
        and obs.continuity_valid
        and now < before.lease_expires_ns,
        "AUTHORITY_DENIED",
    )
    if action is ControlAction.CHANGE_OWNER:
        return replace(
            after,
            owner_id=args["new_owner_id"],
            last_observation=None,
            lease_expires_ns=0,
        )
    return after


def _validate_all(ledger, *, recovery=False, continuity=None):
    """Visit every payload row once after the scalar checks in this transaction."""
    counts = _precheck(ledger)
    visits = sum(counts.values())
    if recovery:
        require(visits <= ledger._limits.replay_row_visits, "RECOVERY_LIMIT")
    require(counts["journal"] == counts["operations"], "RECOVERY_INVALID")
    c, limit = ledger._connection, ledger._limits.record_bytes
    heads = {}
    for execution, database, session, raw in c.execute(
        "SELECT execution_id,database_id,session_id,snapshot FROM heads ORDER BY execution_id"
    ):
        require(
            database == ledger._database_id and session == ledger._session_id,
            "IDENTITY_MISMATCH",
        )
        snap = _record(Snapshot, _decode(raw, limit))
        require(snap.execution_id == execution, "RECOVERY_INVALID")
        heads[execution] = snap
    operations = {}
    for opid, execution, operation_digest, raw, result_raw in c.execute(
        "SELECT operation_id,execution_id,operation_digest,operation,result FROM operations ORDER BY operation_id"
    ):
        op = _validate_envelope(ledger, raw)
        require(
            opid == op["operation_id"] and execution == op["execution_id"],
            "RECOVERY_INVALID",
        )
        require(sha256(raw).hexdigest() == operation_digest, "RECOVERY_INVALID")
        result = _record(OperationResult, _decode(result_raw, limit))
        require(
            result.operation_id == opid and result.operation_digest == operation_digest,
            "RECOVERY_INVALID",
        )
        require(execution in heads and opid not in operations, "RECOVERY_INVALID")
        operations[opid] = (op, raw, result)
    projections, hashes, seen = {}, {}, set()
    # Private replay context retains the last observed lease across same-owner
    # acquisition, whose public snapshot must clear observation and expiry.
    # It is rebuilt in this bounded payload pass, never trusted from a cache.
    history = {}
    for execution, sequence, opid, event_raw, prefix in c.execute(
        "SELECT execution_id,sequence,operation_id,event,prefix_sha256 FROM journal ORDER BY execution_id,sequence"
    ):
        event = _decode(event_raw, limit)
        _shape(
            event,
            ("codec", "operation", "before_version", "after_snapshot", "sequence"),
        )
        require(
            event["codec"] == CODEC and execution in heads and opid in operations,
            "RECOVERY_INVALID",
        )
        op, opraw, result = operations[opid]
        require(
            op["execution_id"] == execution
            and event["operation"] == opraw.hex()
            and opid not in seen,
            "RECOVERY_INVALID",
        )
        seen.add(opid)
        before = projections.get(execution)
        require(
            sequence == (1 if before is None else before.journal_sequence + 1)
            and event["sequence"] == sequence
            and event["before_version"] == (None if before is None else before.version),
            "RECOVERY_INVALID",
        )
        try:
            after = _project(ledger, before, op, history.get(execution))
        except LedgerError:
            raise LedgerError("RECOVERY_INVALID") from None
        expected = _plain(after)
        del expected["journal_sha256"]
        # Exact canonical bytes distinguish JSON true from integer 1 everywhere.
        expected_event = dict(
            codec=CODEC,
            operation=opraw.hex(),
            before_version=None if before is None else before.version,
            after_snapshot=expected,
            sequence=after.journal_sequence,
        )
        require(event_raw == _encode(expected_event, limit), "RECOVERY_INVALID")
        hasher = hashes.setdefault(execution, sha256())
        hasher.update(len(event_raw).to_bytes(8, "big"))
        hasher.update(event_raw)
        require(hasher.hexdigest() == prefix, "RECOVERY_INVALID")
        after = replace(after, journal_sha256=prefix)
        require(result.snapshot == after, "RECOVERY_INVALID")
        projections[execution] = after
        if before is None or after.owner_id != before.owner_id:
            history[execution] = None
        if after.last_observation is not None:
            history[execution] = after
    require(set(operations) == seen and projections == heads, "RECOVERY_INVALID")
    # Bounded by database cap and row counts; stream at most one error.
    require(
        c.execute("PRAGMA integrity_check(1)").fetchone() == ("ok",), "STORAGE_CORRUPT"
    )
    require(
        c.execute("PRAGMA foreign_key_check").fetchone() is None, "RECOVERY_INVALID"
    )
    if continuity is not None:
        continuity.update(history)
    return heads, operations, hashes, visits


def open_test_ledger(
    *,
    directory: Path,
    limits: LedgerLimits,
    policy: SyntheticPolicy,
    mode: OpenMode,
    session_id: str,
    database_id: str,
    session_continuity: bool,
    fault: Fault = Fault.NONE,
    stop_sink: FakeStopSink,
) -> TestLedger:
    limits = _checked_copy(limits, LedgerLimits)
    policy = _checked_copy(policy, SyntheticPolicy)
    require(
        isinstance(directory, Path) and directory.is_absolute() and directory.is_dir()
    )
    require(type(mode) is OpenMode and type(fault) is Fault)
    require(type(stop_sink) is FakeStopSink and type(stop_sink.requests) is list)
    require(type(session_continuity) is bool)
    require(session_continuity == (mode is not OpenMode.RECOVER))
    identifier(session_id)
    identifier(database_id)
    directory = directory.resolve()
    path = directory / "ledger.sqlite3"
    namespace = str(directory).casefold()
    key = (namespace, database_id, session_id)
    with _SESSION_LOCK:
        if mode is OpenMode.NEW:
            require(
                namespace not in _USED_NAMESPACES and not any(directory.iterdir()),
                "RECOVERY_REQUIRED",
            )
            _USED_NAMESPACES.add(namespace)
        else:
            require(path.is_file(), "RECOVERY_REQUIRED")
        session = _SESSIONS.setdefault(key, _Session())
        if mode is OpenMode.ATTACH:
            require(not session.failed, "RECOVERY_REQUIRED")
    connection = None
    ledger = None
    try:
        if mode is OpenMode.NEW:
            # Exclusive creation prevents a missing-file fallback or namespace race.
            with path.open("xb"):
                pass
        require(path.stat().st_size <= limits.sqlite_database_bytes, "CAPACITY_LIMIT")
        connection = sqlite3.connect(
            str(path), isolation_level=None, timeout=limits.busy_timeout_ms / 1000
        )
        connection.setlimit(sqlite3.SQLITE_LIMIT_LENGTH, 8 * limits.record_bytes)
        require(
            connection.getlimit(sqlite3.SQLITE_LIMIT_LENGTH) == 8 * limits.record_bytes,
            "DATABASE_CONFIGURATION",
        )
        connection.execute("PRAGMA trusted_schema=OFF")
        # journal_mode is persisted. Never convert a hostile existing WAL database.
        require(
            connection.execute("PRAGMA journal_mode").fetchone()[0] == "delete",
            "DATABASE_CONFIGURATION",
        )
        connection.execute("PRAGMA synchronous=FULL")
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("PRAGMA busy_timeout=" + str(limits.busy_timeout_ms))
        page_size = connection.execute("PRAGMA page_size").fetchone()[0]
        page_cap = limits.sqlite_database_bytes // page_size
        require(page_cap >= 8, "CAPACITY_LIMIT")
        require(
            connection.execute("PRAGMA max_page_count=" + str(page_cap)).fetchone()[0]
            == page_cap,
            "CAPACITY_LIMIT",
        )
        ledger = TestLedger(
            connection,
            directory,
            limits,
            policy,
            mode,
            session_id,
            database_id,
            fault,
            stop_sink,
            session,
        )
        if mode is OpenMode.NEW:
            connection.execute("BEGIN IMMEDIATE")
            for statement in _SCHEMA:
                connection.execute(statement)
            connection.execute("COMMIT")
        connection.execute("BEGIN")
        if mode is OpenMode.RECOVER:
            # Full projection validation remains the explicit recover operation.
            _precheck(ledger)
        else:
            heads, _, _, _ = _validate_all(ledger)
            if mode is OpenMode.ATTACH:
                require(bool(heads), "RECOVERY_REQUIRED")
            session.executions.update(heads)
        connection.execute("ROLLBACK")
        return ledger
    except LedgerError as exc:
        if ledger is not None:
            ledger._poison("STORAGE_CORRUPT")
        elif connection is not None:
            connection.close()
        raise LedgerError(exc.code) from None
    except (sqlite3.Error, OSError):
        if ledger is not None:
            ledger._poison("STORAGE_CORRUPT")
        elif connection is not None:
            connection.close()
        raise LedgerError("STORAGE_CORRUPT") from None


def _handle(ledger):
    require(type(ledger) is TestLedger)
    ledger._check()


def _rollback(ledger):
    try:
        if ledger._connection.in_transaction:
            ledger._connection.execute("ROLLBACK")
        return True
    except sqlite3.Error:
        return False


def _mutation(ledger, raw):
    _handle(ledger)
    op = _validate_envelope(ledger, raw)
    execution = op["execution_id"]
    digest_value = sha256(raw).hexdigest()
    c = ledger._connection
    begun = False
    commit_attempted = False
    try:
        try:
            c.execute("BEGIN IMMEDIATE")
            begun = True
        except sqlite3.OperationalError as exc:
            if getattr(exc, "sqlite_errorcode", None) in (
                sqlite3.SQLITE_BUSY,
                sqlite3.SQLITE_LOCKED,
            ):
                raise LedgerError("BUSY") from None
            raise
        # Scalar-only validation precedes any stored byte materialization.
        counts = _precheck(ledger)
        stored = c.execute(
            "SELECT execution_id,operation_digest,operation,result FROM operations WHERE operation_id=?",
            (op["operation_id"],),
        ).fetchone()
        if stored is not None:
            require(
                stored[0] == execution
                and stored[1] == digest_value
                and stored[2] == raw,
                "OPERATION_CONFLICT",
            )
            result = _record(
                OperationResult, _decode(stored[3], ledger._limits.record_bytes)
            )
            require(
                result.operation_digest == digest_value
                and result.operation_id == op["operation_id"],
                "STORAGE_CORRUPT",
            )
            # The registry is historical evidence only after its journal/result
            # projection is verified. This performs no current lease eligibility.
            _validate_all(ledger)
            c.execute("ROLLBACK")
            return result
        require(ledger._state != "RECOVERY_REQUIRED", "RECOVERY_REQUIRED")
        if ledger._mode is OpenMode.RECOVER:
            require(
                ledger._recovered
                and op["api"] == "commit_control_update"
                and op["arguments"]["action"] == ControlAction.INVALIDATE.value,
                "INVALIDATED",
            )
        continuity = {}
        heads, _, hashes, _ = _validate_all(ledger, continuity=continuity)
        before = heads.get(execution)
        args = op["arguments"]
        negative_action = (
            op["api"] == "commit_control_update"
            and args["action"] == ControlAction.INVALIDATE.value
        )
        # _project first validates immutable identity/CAS/time, then computes loss.
        try:
            after = _project(ledger, before, op, continuity.get(execution))
        except LedgerError as exc:
            if exc.code == "OBSERVATION_ORDER":
                ledger._latch(execution, "OBSERVATION_ORDER")
            raise
        latched = execution in ledger._session.latches or ledger._session.failed
        negative_observation = op["api"] == "apply_observation" and after.invalidated
        if latched and not after.invalidated:
            raise LedgerError("INVALIDATED")
        if latched and not (
            negative_action
            or negative_observation
            or (
                before is not None
                and _expired(
                    before, args["now_ns"], ledger._policy, continuity.get(execution)
                )
            )
        ):
            raise LedgerError("INVALIDATED")
        # Loss/invalidation is visible to cooperating writers before any IO hook.
        if after.invalidated:
            ledger._latch(execution, "INVALIDATED")
        require(
            counts["journal"] < ledger._limits.journal_rows
            and counts["operations"] < ledger._limits.operation_count,
            "CAPACITY_LIMIT",
        )
        event_snapshot = _plain(after)
        del event_snapshot["journal_sha256"]
        # Hex expansion is checked before allocating the hexadecimal copy.
        require(
            2 * len(raw) + _size(event_snapshot) + 256 <= ledger._limits.record_bytes,
            "RECORD_LIMIT",
        )
        event = dict(
            codec=CODEC,
            operation=raw.hex(),
            before_version=None if before is None else before.version,
            after_snapshot=event_snapshot,
            sequence=after.journal_sequence,
        )
        event_raw = _encode(event, ledger._limits.record_bytes)
        hasher = hashes.get(execution, sha256()).copy()
        hasher.update(len(event_raw).to_bytes(8, "big"))
        hasher.update(event_raw)
        after = replace(after, journal_sha256=hasher.hexdigest())
        result = OperationResult(op["operation_id"], digest_value, "COMMITTED", after)
        snapshot_raw = _encode(_plain(after), ledger._limits.record_bytes)
        result_raw = _encode(_plain(result), ledger._limits.record_bytes)
        ledger._before_write()
        if before is None:
            c.execute(
                "INSERT INTO heads VALUES (?,?,?,?)",
                (execution, ledger._database_id, ledger._session_id, snapshot_raw),
            )
        else:
            c.execute(
                "UPDATE heads SET snapshot=? WHERE execution_id=?",
                (snapshot_raw, execution),
            )
        # SQLite INTEGER is signed. Sequence is also bounded by 4096 global rows.
        c.execute(
            "INSERT INTO journal VALUES (?,?,?,?,?)",
            (
                execution,
                after.journal_sequence,
                op["operation_id"],
                event_raw,
                after.journal_sha256,
            ),
        )
        c.execute(
            "INSERT INTO operations VALUES (?,?,?,?,?)",
            (op["operation_id"], execution, digest_value, raw, result_raw),
        )
        ledger._before_commit()
        commit_attempted = True
        c.execute("COMMIT")
        ledger._after_commit()
        ledger._session.executions.add(execution)
        return result
    except LedgerError as exc:
        if ledger._state == "POISONED":
            raise LedgerError(exc.code) from None
        if commit_attempted:
            ledger._poison("COMMIT_UNCERTAIN", execution)
            raise LedgerError("COMMIT_UNCERTAIN") from None
        confirmed = _rollback(ledger) if begun else True
        if not confirmed:
            ledger._poison("COMMIT_UNCERTAIN", execution)
            raise LedgerError("COMMIT_UNCERTAIN") from None
        if exc.code in (
            "PERSISTENCE_FAILURE",
            "STORAGE_CORRUPT",
            "RECOVERY_INVALID",
            "DATABASE_CONFIGURATION",
        ):
            ledger._poison(
                (
                    "PERSISTENCE_FAILURE"
                    if exc.code == "PERSISTENCE_FAILURE"
                    else "STORAGE_CORRUPT"
                ),
                execution,
            )
        raise LedgerError(exc.code) from None
    except (sqlite3.Error, OSError):
        confirmed = _rollback(ledger) if begun and not commit_attempted else False
        code = "PERSISTENCE_FAILURE" if confirmed else "COMMIT_UNCERTAIN"
        ledger._poison(code, execution)
        raise LedgerError(code) from None
    except Exception:
        confirmed = _rollback(ledger) if begun and not commit_attempted else False
        code = "PERSISTENCE_FAILURE" if confirmed else "COMMIT_UNCERTAIN"
        ledger._poison(code, execution)
        raise LedgerError(code) from None


def create_execution(
    ledger,
    *,
    execution_id,
    request_sha256,
    epoch,
    owner_id,
    operation_id,
    request_bytes: bytes,
    now_ns: int,
):
    _handle(ledger)
    integer(now_ns)
    require(type(request_bytes) is bytes)
    require(len(request_bytes) <= ledger._limits.record_bytes, "RECORD_LIMIT")
    # Request is embedded in operation hex, then event hex: bound both first.
    require(
        4 * len(request_bytes) + 4096 <= ledger._limits.record_bytes, "RECORD_LIMIT"
    )
    digest(request_sha256)
    require(sha256(request_bytes).hexdigest() == request_sha256)
    args = dict(
        request_bytes=request_bytes.hex(),
        now_ns=now_ns,
        limits=_plain(ledger._limits),
        policy=_plain(ledger._policy),
        session_id=ledger._session_id,
        database_id=ledger._database_id,
    )
    return _mutation(
        ledger,
        _envelope(
            ledger,
            "create_execution",
            execution_id,
            request_sha256,
            epoch,
            owner_id,
            operation_id,
            args,
        ),
    )


def apply_observation(
    ledger,
    *,
    execution_id,
    request_sha256,
    epoch,
    owner_id,
    operation_id,
    expected_version,
    observation: Observation,
    now_ns,
):
    _handle(ledger)
    observation = _checked_copy(observation, Observation)
    integer(now_ns)
    integer(expected_version)
    integer(observation.finished_ns + ledger._policy.lease_duration_ns)
    args = dict(
        expected_version=expected_version,
        observation=_plain(observation),
        now_ns=now_ns,
    )
    return _mutation(
        ledger,
        _envelope(
            ledger,
            "apply_observation",
            execution_id,
            request_sha256,
            epoch,
            owner_id,
            operation_id,
            args,
        ),
    )


def commit_control_update(
    ledger,
    *,
    execution_id,
    request_sha256,
    epoch,
    owner_id,
    operation_id,
    expected_version,
    action: ControlAction,
    new_owner_id,
    now_ns,
):
    _handle(ledger)
    require(type(action) is ControlAction)
    integer(expected_version)
    integer(now_ns)
    if new_owner_id is not None:
        identifier(new_owner_id)
    if action is ControlAction.ACQUIRE_OWNER:
        require(new_owner_id == owner_id)
    elif action is ControlAction.CHANGE_OWNER:
        require(new_owner_id is not None and new_owner_id != owner_id)
    else:
        require(new_owner_id is None)
    args = dict(
        expected_version=expected_version,
        action=action.value,
        new_owner_id=new_owner_id,
        now_ns=now_ns,
    )
    return _mutation(
        ledger,
        _envelope(
            ledger,
            "commit_control_update",
            execution_id,
            request_sha256,
            epoch,
            owner_id,
            operation_id,
            args,
        ),
    )


def _read(ledger, callback, *, recovery=False):
    _handle(ledger)
    try:
        ledger._connection.execute("BEGIN")
        values = _validate_all(ledger, recovery=recovery)
        result = callback(*values)
        ledger._connection.execute("ROLLBACK")
        return result
    except LedgerError as exc:
        _rollback(ledger)
        if exc.code not in ("EXECUTION_NOT_FOUND", "OPERATION_CONFLICT"):
            ledger._poison("STORAGE_CORRUPT")
        raise LedgerError(exc.code) from None
    except (sqlite3.Error, OSError, ValueError, TypeError):
        _rollback(ledger)
        ledger._poison("STORAGE_CORRUPT")
        raise LedgerError("STORAGE_CORRUPT") from None


def read_snapshot(ledger, *, execution_id):
    _handle(ledger)
    identifier(execution_id)

    def select(heads, _operations, _hashes, _visits):
        require(execution_id in heads, "EXECUTION_NOT_FOUND")
        return heads[execution_id]

    return _read(ledger, select)


def lookup_operation(
    ledger,
    *,
    execution_id,
    request_sha256,
    epoch,
    owner_id,
    operation_id,
    operation_digest,
):
    _handle(ledger)
    for value in (execution_id, epoch, owner_id, operation_id):
        identifier(value)
    digest(request_sha256)
    digest(operation_digest)

    def select(_heads, operations, _hashes, _visits):
        item = operations.get(operation_id)
        if item is None:
            return LookupResult("ABSENT", None)
        op, _raw, result = item
        require(
            (
                op["execution_id"],
                op["request_sha256"],
                op["epoch"],
                op["owner_id"],
                result.operation_digest,
            )
            == (execution_id, request_sha256, epoch, owner_id, operation_digest),
            "OPERATION_CONFLICT",
        )
        return LookupResult("FOUND", result)

    return _read(ledger, select)


def recover(ledger, *, execution_id, now_ns, uncertain_operation_id):
    _handle(ledger)
    require(ledger._mode is OpenMode.RECOVER, "RECOVERY_REQUIRED")
    if execution_id is not None:
        identifier(execution_id)
    if uncertain_operation_id is not None:
        identifier(uncertain_operation_id)
    integer(now_ns)

    def select(heads, operations, _hashes, visits):
        for execution in heads:
            ledger._latch(execution, "RECOVERED")
        if execution_id is not None:
            require(execution_id in heads, "EXECUTION_NOT_FOUND")
        operation = None
        if uncertain_operation_id is not None:
            stored = operations.get(uncertain_operation_id)
            if stored is not None and execution_id is not None:
                require(
                    stored[0]["execution_id"] == execution_id
                    and stored[2].snapshot.execution_id == execution_id,
                    "OPERATION_CONFLICT",
                )
            operation = (
                LookupResult("ABSENT", None)
                if stored is None
                else LookupResult("FOUND", stored[2])
            )
        return RecoveryReport(
            "VERIFIED",
            None if execution_id is None else heads[execution_id],
            operation,
            visits,
        )

    report = _read(ledger, select, recovery=True)
    ledger._recovered = True
    ledger._state = "READY"
    return report
