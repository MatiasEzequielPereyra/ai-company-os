from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import uuid
from collections.abc import Iterable as IterableABC, Mapping
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


SCHEMA_VERSION = 1
MAX_TEXT_LENGTH = 8000
MAX_EVIDENCE_ITEMS = 32
MAX_EVIDENCE_LENGTH = 2000
STATUSES = {
    "OBSERVED",
    "DIAGNOSED",
    "FIX_PROPOSED",
    "FIX_VERIFIED",
    "REGRESSION_DETECTED",
}
_SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/ -]{0,159}$")
_SECRET_PATTERNS = (
    (re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}"), "Bearer [REDACTED]"),
    (re.compile(r"(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret|credential)\b\s*[:=]\s*([^\s,;]+)"), "[REDACTED]=[REDACTED]"),
    (re.compile(r"\b(?:sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{12,}|AKIA[A-Z0-9]{16})\b"), "[REDACTED]"),
    (re.compile(r"(?is)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"), "[REDACTED PRIVATE KEY]"),
    (re.compile(r"(?i)(://[^:/\s]+:)[^@/\s]+(@)"), r"\1[REDACTED]\2"),
)


class ErrorIntelligenceError(ValueError):
    """Base class for fail-closed input and storage errors."""


class InvalidIncidentError(ErrorIntelligenceError):
    pass


class StoreCorruptError(ErrorIntelligenceError):
    """The database is invalid; it is preserved and never reset automatically."""


@dataclass(frozen=True)
class Incident:
    id: str
    installation_id: str
    project_id: str
    task_id: str | None
    run_id: str | None
    component: str
    category: str
    error_type: str
    fingerprint: str
    summary: str
    status: str
    created_at: str
    occurrence_count: int
    root_cause: str | None = None
    root_cause_verified: bool = False
    root_cause_evidence: tuple[str, ...] = ()
    proposed_fix: str | None = None
    contraindications: tuple[str, ...] = ()
    verified_fix: str | None = None
    fix_verified_by: str | None = None
    fix_evidence: tuple[str, ...] = ()
    evidence: tuple[str, ...] = ()


@dataclass(frozen=True)
class IncidentObservation:
    id: str
    observed_at: str
    task_id: str | None
    run_id: str | None
    evidence: tuple[str, ...]


@dataclass(frozen=True)
class IncidentEvent:
    occurred_at: str
    event_type: str
    details: dict[str, object]


@dataclass(frozen=True)
class IncidentMatch:
    incident: Incident
    confidence: float
    equivalent: bool
    matched_by: tuple[str, ...]


def default_store_path() -> Path:
    """Return a per-user, installation-scoped path without persisting its source path."""
    override = os.environ.get("AICO_ERROR_INTELLIGENCE_PATH")
    if override:
        return _validate_path_text(override)
    install_path = str(Path(__file__).resolve())
    if os.name == "nt":
        install_path = install_path.casefold()
    install_key = hashlib.sha256(install_path.encode("utf-8")).hexdigest()[:24]
    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA")
        if not base:
            raise InvalidIncidentError("LOCALAPPDATA is required to choose the default store path.")
        return Path(base) / "AICompanyOS" / "ErrorIntelligence" / install_key / "incidents.sqlite3"
    base = os.environ.get("XDG_STATE_HOME")
    if base:
        return Path(base) / "ai-company-os" / "error-intelligence" / install_key / "incidents.sqlite3"
    return Path.home() / ".local" / "state" / "ai-company-os" / "error-intelligence" / install_key / "incidents.sqlite3"


def _validate_path_text(value: str | os.PathLike[str]) -> Path:
    try:
        raw = os.fspath(value)
    except TypeError as exc:
        raise InvalidIncidentError("Storage path must be a path or text value.") from exc
    if not raw or "\x00" in raw:
        raise InvalidIncidentError("Storage path is empty or invalid.")
    path = Path(raw).expanduser()
    if not path.is_absolute():
        raise InvalidIncidentError("Storage path must be absolute.")
    if ".." in path.parts:
        raise InvalidIncidentError("Storage path may not contain parent traversal.")
    return path


def _clean_text(value: str, field: str, *, required: bool = True, limit: int = MAX_TEXT_LENGTH) -> str:
    if not isinstance(value, str):
        raise InvalidIncidentError(f"{field} must be text.")
    result = value.strip()
    if required and not result:
        raise InvalidIncidentError(f"{field} is required.")
    if len(result) > limit:
        raise InvalidIncidentError(f"{field} exceeds {limit} characters.")
    for pattern, replacement in _SECRET_PATTERNS:
        result = pattern.sub(replacement, result)
    return result


def _clean_id(value: str | None, field: str, *, required: bool = False) -> str | None:
    if value is None and not required:
        return None
    cleaned = _clean_text(value or "", field, required=required, limit=160)
    if not _SAFE_ID.fullmatch(cleaned) or ".." in cleaned or cleaned.startswith(("/", "\\")):
        raise InvalidIncidentError(f"{field} has an invalid identifier format.")
    return cleaned


def _clean_evidence(items: Iterable[str]) -> tuple[str, ...]:
    if isinstance(items, (str, bytes, Mapping)) or not isinstance(items, IterableABC):
        raise InvalidIncidentError("Evidence must be a sequence of text items.")
    try:
        values = tuple(_clean_text(item, "evidence", limit=MAX_EVIDENCE_LENGTH) for item in items)
    except TypeError as exc:
        raise InvalidIncidentError("Evidence must be a sequence of text items.") from exc
    if not values or len(values) > MAX_EVIDENCE_ITEMS:
        raise InvalidIncidentError(f"Evidence must contain 1 to {MAX_EVIDENCE_ITEMS} items.")
    return values


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def _normalized(value: str) -> str:
    value = value.casefold()
    value = re.sub(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", "<email>", value)
    value = re.sub(r"\b\d+\b", "<n>", value)
    value = re.sub(r"[^a-z0-9<>]+", " ", value)
    return " ".join(value.split())


class ErrorIntelligenceStore:
    """SQLite incident history with explicit project-scoped queries.

    A duplicate fingerprint adds an immutable occurrence record to the existing
    incident family. It never discards new evidence or silently replaces the
    original incident summary.
    """

    def __init__(self, path: str | os.PathLike[str] | None = None):
        self.path = _validate_path_text(path if path is not None else default_store_path())
        self._reject_reparse_path(self.path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._reject_reparse_path(self.path)
        try:
            self._initialize()
            if os.name != "nt":
                os.chmod(self.path, 0o600)
        except (sqlite3.DatabaseError, OSError) as exc:
            if isinstance(exc, sqlite3.DatabaseError):
                raise StoreCorruptError("Incident store is invalid; its contents were preserved.") from exc
            raise

    @staticmethod
    def _reject_reparse_path(path: Path) -> None:
        current = Path(path.anchor)
        for part in path.parts[1:-1]:
            current = current / part
            is_junction = getattr(current, "is_junction", lambda: False)
            if current.is_symlink() or is_junction():
                raise InvalidIncidentError("Storage path traverses a symbolic link.")
        is_junction = getattr(path, "is_junction", lambda: False)
        if path.is_symlink() or is_junction() or (path.exists() and not path.is_file()):
            raise InvalidIncidentError("Storage path must be a regular file, not a link or directory.")

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout = 10000")
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    @contextmanager
    def _connection(self):
        connection = self._connect()
        try:
            yield connection
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._connection() as connection:
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            if version not in (0, SCHEMA_VERSION):
                raise StoreCorruptError(f"Unsupported incident store schema version {version}.")
            if version == 0:
                connection.executescript(
                    """
                    BEGIN IMMEDIATE;
                    CREATE TABLE store_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                    CREATE TABLE incidents (
                        id TEXT PRIMARY KEY,
                        installation_id TEXT NOT NULL,
                        project_id TEXT NOT NULL,
                        task_id TEXT,
                        run_id TEXT,
                        component TEXT NOT NULL,
                        category TEXT NOT NULL,
                        error_type TEXT NOT NULL,
                        fingerprint TEXT NOT NULL,
                        normalized_summary TEXT NOT NULL,
                        summary TEXT NOT NULL,
                        status TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        root_cause TEXT,
                        root_cause_verified INTEGER NOT NULL DEFAULT 0,
                        root_cause_evidence_json TEXT NOT NULL DEFAULT '[]',
                        root_cause_verified_by TEXT,
                        proposed_fix TEXT,
                        contraindications_json TEXT NOT NULL DEFAULT '[]',
                        verified_fix TEXT,
                        fix_verified_by TEXT,
                        fix_evidence_json TEXT NOT NULL DEFAULT '[]',
                        UNIQUE(project_id, component, error_type, fingerprint)
                    );
                    CREATE TABLE occurrences (
                        id TEXT PRIMARY KEY,
                        incident_id TEXT NOT NULL REFERENCES incidents(id),
                        observed_at TEXT NOT NULL,
                        task_id TEXT,
                        run_id TEXT,
                        evidence_json TEXT NOT NULL
                    );
                    CREATE INDEX occurrences_incident_idx ON occurrences(incident_id, observed_at);
                    CREATE TABLE incident_events (
                        id TEXT PRIMARY KEY,
                        incident_id TEXT NOT NULL REFERENCES incidents(id),
                        occurred_at TEXT NOT NULL,
                        event_type TEXT NOT NULL,
                        details_json TEXT NOT NULL
                    );
                    CREATE INDEX incident_events_incident_idx ON incident_events(incident_id, occurred_at);
                    CREATE TABLE recovery_attempts (
                        id TEXT PRIMARY KEY,
                        incident_id TEXT NOT NULL REFERENCES incidents(id),
                        action_key TEXT NOT NULL,
                        action TEXT NOT NULL,
                        outcome TEXT NOT NULL CHECK(outcome IN ('SUCCESS','FAILED','INCONCLUSIVE')),
                        attempted_at TEXT NOT NULL,
                        evidence_json TEXT NOT NULL,
                        recorded_by TEXT NOT NULL
                    );
                    CREATE INDEX recovery_action_idx ON recovery_attempts(incident_id, action_key, attempted_at);
                    INSERT INTO store_meta(key, value) VALUES ('installation_id', lower(hex(randomblob(16))));
                    PRAGMA user_version = 1;
                    COMMIT;
                    """
                )
            check = connection.execute("PRAGMA quick_check").fetchone()
            if check is None or check[0] != "ok":
                raise StoreCorruptError("Incident store integrity check failed; its contents were preserved.")

    def _installation_id(self, connection: sqlite3.Connection) -> str:
        row = connection.execute("SELECT value FROM store_meta WHERE key='installation_id'").fetchone()
        if row is None or not re.fullmatch(r"[0-9a-f]{32}", row[0]):
            raise StoreCorruptError("Incident store installation metadata is invalid.")
        return row[0]

    @staticmethod
    def _json(value: object) -> str:
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))

    def _incident(self, connection: sqlite3.Connection, incident_id: str) -> Incident:
        row = connection.execute("SELECT * FROM incidents WHERE id=?", (incident_id,)).fetchone()
        if row is None:
            raise InvalidIncidentError("Incident does not exist in this store.")
        occurrences = connection.execute(
            "SELECT evidence_json FROM occurrences WHERE incident_id=? ORDER BY observed_at ASC, rowid ASC",
            (incident_id,),
        ).fetchall()
        original_evidence = tuple(json.loads(occurrences[0][0])) if occurrences else ()
        return Incident(
            id=row["id"], installation_id=row["installation_id"], project_id=row["project_id"],
            task_id=row["task_id"], run_id=row["run_id"], component=row["component"],
            category=row["category"], error_type=row["error_type"], fingerprint=row["fingerprint"],
            summary=row["summary"], status=row["status"], created_at=row["created_at"],
            occurrence_count=len(occurrences), root_cause=row["root_cause"],
            root_cause_verified=bool(row["root_cause_verified"]),
            root_cause_evidence=tuple(json.loads(row["root_cause_evidence_json"])),
            proposed_fix=row["proposed_fix"],
            contraindications=tuple(json.loads(row["contraindications_json"])),
            verified_fix=row["verified_fix"],
            fix_verified_by=row["fix_verified_by"], fix_evidence=tuple(json.loads(row["fix_evidence_json"])),
            evidence=original_evidence,
        )

    @staticmethod
    def _event(connection: sqlite3.Connection, incident_id: str, kind: str, details: dict[str, object]) -> None:
        connection.execute(
            "INSERT INTO incident_events VALUES (?, ?, ?, ?, ?)",
            (uuid.uuid4().hex, incident_id, _utc_now(), kind, json.dumps(details, ensure_ascii=False, separators=(",", ":"))),
        )

    def record_incident(
        self,
        *,
        project_id: str,
        component: str,
        category: str,
        error_type: str,
        summary: str,
        evidence: Iterable[str],
        task_id: str | None = None,
        run_id: str | None = None,
        fingerprint: str | None = None,
    ) -> Incident:
        project_id = _clean_id(project_id, "project_id", required=True) or ""
        component = _clean_id(component, "component", required=True) or ""
        category = _clean_id(category, "category", required=True) or ""
        error_type = _clean_id(error_type, "error_type", required=True) or ""
        task_id = _clean_id(task_id, "task_id")
        run_id = _clean_id(run_id, "run_id")
        summary = _clean_text(summary, "summary")
        evidence = _clean_evidence(evidence)
        normalized = _normalized(summary)
        if fingerprint is None:
            fingerprint = hashlib.sha256(f"{component}\0{error_type}\0{normalized}".encode()).hexdigest()
        else:
            fingerprint = _clean_text(fingerprint, "fingerprint", limit=256)
        now = _utc_now()
        with self._connection() as connection:
            try:
                connection.execute("BEGIN IMMEDIATE")
                installation_id = self._installation_id(connection)
                row = connection.execute(
                    "SELECT id FROM incidents WHERE project_id=? AND component=? AND error_type=? AND fingerprint=?",
                    (project_id, component, error_type, fingerprint),
                ).fetchone()
                if row:
                    incident_id = row[0]
                    occurrence_id = uuid.uuid4().hex
                    connection.execute(
                        "INSERT INTO occurrences VALUES (?, ?, ?, ?, ?, ?)",
                        (occurrence_id, incident_id, now, task_id, run_id, self._json(evidence)),
                    )
                    self._event(connection, incident_id, "DUPLICATE_OBSERVED", {"occurrence_id": occurrence_id, "task_id": task_id, "run_id": run_id})
                else:
                    incident_id = uuid.uuid4().hex
                    connection.execute(
                        """INSERT INTO incidents(id, installation_id, project_id, task_id, run_id, component,
                           category, error_type, fingerprint, normalized_summary, summary, status, created_at)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'OBSERVED', ?)""",
                        (incident_id, installation_id, project_id, task_id, run_id, component, category, error_type,
                         fingerprint, normalized, summary, now),
                    )
                    occurrence_id = uuid.uuid4().hex
                    connection.execute(
                        "INSERT INTO occurrences VALUES (?, ?, ?, ?, ?, ?)",
                        (occurrence_id, incident_id, now, task_id, run_id, self._json(evidence)),
                    )
                    self._event(connection, incident_id, "OBSERVED", {"occurrence_id": occurrence_id, "summary": summary})
                connection.commit()
            except sqlite3.DatabaseError as exc:
                connection.rollback()
                raise StoreCorruptError("Incident could not be recorded; no partial record was accepted.") from exc
            return self._incident(connection, incident_id)

    def diagnose(self, incident_id: str, *, root_cause: str, evidence: Iterable[str]) -> Incident:
        cause = _clean_text(root_cause, "root_cause")
        evidence = _clean_evidence(evidence)
        return self._update_incident(incident_id, "DIAGNOSED", "DIAGNOSED", {
            "root_cause": cause, "root_cause_evidence_json": self._json(evidence), "root_cause_verified": 0,
            "root_cause_verified_by": None,
        }, {"root_cause": cause, "evidence": evidence})

    def verify_root_cause(self, incident_id: str, *, verified_by: str, evidence: Iterable[str]) -> Incident:
        incident_id = _clean_text(incident_id, "incident_id", limit=64)
        who = _clean_id(verified_by, "verified_by", required=True) or ""
        evidence = _clean_evidence(evidence)
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("SELECT root_cause FROM incidents WHERE id=?", (incident_id,)).fetchone()
            if row is None:
                raise InvalidIncidentError("Incident does not exist in this store.")
            if not row[0]:
                raise InvalidIncidentError("A diagnosis is required before root cause verification.")
            connection.execute(
                "UPDATE incidents SET status='DIAGNOSED', root_cause_verified=1, root_cause_verified_by=?, root_cause_evidence_json=? WHERE id=?",
                (who, self._json(evidence), incident_id),
            )
            self._event(connection, incident_id, "ROOT_CAUSE_VERIFIED", {"verified_by": who, "evidence": evidence})
            connection.commit()
            return self._incident(connection, incident_id)

    def propose_fix(self, incident_id: str, *, action: str, contraindications: Iterable[str] = ()) -> Incident:
        action = _clean_text(action, "action")
        if isinstance(contraindications, (str, bytes, Mapping)) or not isinstance(contraindications, IterableABC):
            raise InvalidIncidentError("Contraindications must be a sequence of text items.")
        contraindications = tuple(_clean_text(item, "contraindication", limit=MAX_EVIDENCE_LENGTH) for item in contraindications)
        if len(contraindications) > MAX_EVIDENCE_ITEMS:
            raise InvalidIncidentError("Too many contraindications.")
        return self._update_incident(incident_id, "FIX_PROPOSED", "FIX_PROPOSED", {
            "proposed_fix": action,
            "contraindications_json": self._json(contraindications),
        }, {"action": action, "contraindications": contraindications})

    def verify_fix(self, incident_id: str, *, action: str, verified_by: str, evidence: Iterable[str]) -> Incident:
        incident_id = _clean_text(incident_id, "incident_id", limit=64)
        action = _clean_text(action, "action")
        who = _clean_id(verified_by, "verified_by", required=True) or ""
        evidence = _clean_evidence(evidence)
        now = _utc_now()
        action_key = hashlib.sha256(_normalized(action).encode()).hexdigest()
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("SELECT proposed_fix FROM incidents WHERE id=?", (incident_id,)).fetchone()
            if row is None:
                raise InvalidIncidentError("Incident does not exist in this store.")
            if not row[0] or _normalized(row[0]) != _normalized(action):
                raise InvalidIncidentError("The verified action must match a recorded fix proposal.")
            connection.execute(
                "UPDATE incidents SET status='FIX_VERIFIED', verified_fix=?, fix_verified_by=?, fix_evidence_json=? WHERE id=?",
                (action, who, self._json(evidence), incident_id),
            )
            connection.execute(
                "INSERT INTO recovery_attempts VALUES (?, ?, ?, ?, 'SUCCESS', ?, ?, ?)",
                (uuid.uuid4().hex, incident_id, action_key, action, now, self._json(evidence), who),
            )
            self._event(connection, incident_id, "FIX_VERIFIED", {"action": action, "verified_by": who, "evidence": evidence})
            connection.commit()
            return self._incident(connection, incident_id)

    def record_recovery_failure(
        self, incident_id: str, *, action: str, evidence: Iterable[str], recorded_by: str,
        outcome: str = "FAILED",
    ) -> Incident:
        action = _clean_text(action, "action")
        who = _clean_id(recorded_by, "recorded_by", required=True) or ""
        evidence = _clean_evidence(evidence)
        if not isinstance(outcome, str) or outcome not in {"FAILED", "INCONCLUSIVE"}:
            raise InvalidIncidentError("Recovery outcome must be FAILED or INCONCLUSIVE.")
        incident_id = _clean_text(incident_id, "incident_id", limit=64)
        key = hashlib.sha256(_normalized(action).encode()).hexdigest()
        now = _utc_now()
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            self._assert_incident(connection, incident_id)
            connection.execute(
                "INSERT INTO recovery_attempts VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (uuid.uuid4().hex, incident_id, key, action, outcome, now, self._json(evidence), who),
            )
            self._event(connection, incident_id, "RECOVERY_" + outcome, {"action": action, "recorded_by": who, "evidence": evidence})
            connection.commit()
            return self._incident(connection, incident_id)

    def mark_regression(self, incident_id: str, *, evidence: Iterable[str]) -> Incident:
        evidence = _clean_evidence(evidence)
        return self._update_incident(incident_id, "REGRESSION_DETECTED", "REGRESSION_DETECTED", {}, {"evidence": evidence})

    def _assert_incident(self, connection: sqlite3.Connection, incident_id: str) -> None:
        if connection.execute("SELECT 1 FROM incidents WHERE id=?", (incident_id,)).fetchone() is None:
            raise InvalidIncidentError("Incident does not exist in this store.")

    def _update_incident(self, incident_id: str, status: str, event: str, fields: dict[str, object], details: dict[str, object]) -> Incident:
        if status not in STATUSES:
            raise InvalidIncidentError("Unknown incident status.")
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            self._assert_incident(connection, incident_id)
            fields["status"] = status
            assignments = ", ".join(f"{name}=?" for name in fields)
            connection.execute(
                f"UPDATE incidents SET {assignments} WHERE id=?",
                (*fields.values(), incident_id),
            )
            self._event(connection, incident_id, event, details)
            connection.commit()
            return self._incident(connection, incident_id)

    def get(self, incident_id: str) -> Incident:
        incident_id = _clean_text(incident_id, "incident_id", limit=64)
        with self._connection() as connection:
            return self._incident(connection, incident_id)

    def observations(self, incident_id: str) -> list[IncidentObservation]:
        incident_id = _clean_text(incident_id, "incident_id", limit=64)
        with self._connection() as connection:
            self._assert_incident(connection, incident_id)
            rows = connection.execute(
                "SELECT id, observed_at, task_id, run_id, evidence_json FROM occurrences "
                "WHERE incident_id=? ORDER BY observed_at ASC, rowid ASC",
                (incident_id,),
            ).fetchall()
            return [
                IncidentObservation(row["id"], row["observed_at"], row["task_id"], row["run_id"], tuple(json.loads(row["evidence_json"])))
                for row in rows
            ]

    def history(self, incident_id: str) -> list[IncidentEvent]:
        incident_id = _clean_text(incident_id, "incident_id", limit=64)
        with self._connection() as connection:
            self._assert_incident(connection, incident_id)
            rows = connection.execute(
                "SELECT occurred_at, event_type, details_json FROM incident_events "
                "WHERE incident_id=? ORDER BY occurred_at ASC, rowid ASC",
                (incident_id,),
            ).fetchall()
            return [IncidentEvent(row["occurred_at"], row["event_type"], json.loads(row["details_json"])) for row in rows]

    def search(
        self, *, project_id: str, component: str | None = None, error_type: str | None = None,
        fingerprint: str | None = None, text: str | None = None, limit: int = 50,
        verified_solutions_only: bool = False,
    ) -> list[IncidentMatch]:
        project_id = _clean_id(project_id, "project_id", required=True) or ""
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 200:
            raise InvalidIncidentError("limit must be between 1 and 200.")
        exact_fingerprint = _clean_text(fingerprint, "fingerprint", limit=256) if fingerprint is not None else None
        component = _clean_id(component, "component")
        error_type = _clean_id(error_type, "error_type")
        terms = set(_normalized(_clean_text(text, "text")).split()) if text is not None else set()
        if not isinstance(verified_solutions_only, bool):
            raise InvalidIncidentError("verified_solutions_only must be a boolean.")
        query = "SELECT id, fingerprint, component, error_type, normalized_summary FROM incidents WHERE project_id=?"
        params: list[object] = [project_id]
        if component:
            query += " AND component=?"; params.append(component)
        if error_type:
            query += " AND error_type=?"; params.append(error_type)
        if exact_fingerprint:
            query += " AND fingerprint=?"; params.append(exact_fingerprint)
        if verified_solutions_only:
            query += " AND verified_fix IS NOT NULL AND status='FIX_VERIFIED'"
        query += " ORDER BY created_at DESC LIMIT ?"; params.append(limit)
        with self._connection() as connection:
            rows = connection.execute(query, params).fetchall()
            matches: list[IncidentMatch] = []
            for row in rows:
                basis = []
                score = 0.0
                if exact_fingerprint and row["fingerprint"] == exact_fingerprint:
                    basis.append("fingerprint"); score = 1.0
                else:
                    if component and row["component"] == component:
                        basis.append("component"); score += 0.35
                    if error_type and row["error_type"] == error_type:
                        basis.append("error_type"); score += 0.35
                    if terms:
                        previous = set(row["normalized_summary"].split())
                        jaccard = len(terms & previous) / max(1, len(terms | previous))
                        if jaccard:
                            basis.append("text"); score += 0.3 * jaccard
                    if verified_solutions_only and not (component or error_type or terms or exact_fingerprint):
                        basis.append("verified_fix"); score = 0.5
                    elif not (component or error_type or terms or exact_fingerprint):
                        basis.append("project"); score = 0.1
                    score = min(score, 0.99)
                if not basis:
                    continue
                incident = self._incident(connection, row["id"])
                if verified_solutions_only and incident.verified_fix:
                    failures = connection.execute(
                        "SELECT outcome FROM recovery_attempts WHERE incident_id=? AND action_key=? ORDER BY attempted_at DESC, rowid DESC LIMIT 1",
                        (incident.id, hashlib.sha256(_normalized(incident.verified_fix).encode()).hexdigest()),
                    ).fetchone()
                    if failures and failures[0] != "SUCCESS":
                        continue
                matches.append(IncidentMatch(incident, round(score, 3), bool(exact_fingerprint and score == 1.0), tuple(basis)))
            return sorted(matches, key=lambda item: (-item.confidence, item.incident.created_at), reverse=False)

    def verified_solutions(self, *, project_id: str, component: str | None = None, error_type: str | None = None) -> list[IncidentMatch]:
        return self.search(project_id=project_id, component=component, error_type=error_type, verified_solutions_only=True)
