"""Best-effort runtime observations; historical advice never authorizes actions.

Only typed operational metadata crosses this bridge. Exception text, prompts,
model output, actor names, reasons and source paths are deliberately excluded.
The environment switch AICO_ERROR_INTELLIGENCE_ENABLED=0 disables the bridge.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys
from collections.abc import Mapping
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .store import SCHEMA_VERSION, ErrorIntelligenceStore, Incident, IncidentMatch, default_store_path

MAX_INPUT_BYTES = 16384
PROVIDERS = {"openrouter", "gemini", "ollama", "deepseek", "xai", "codex"}
COMPONENTS = {"agent-runner", "gate-runner", "writable-runner", "task-lifecycle"}
CATEGORIES = {"rate_limit", "authentication", "timeout", "contract", "transport", "unknown", "runtime", "context_budget", "gate_rejection", "blocked", "process_launch"}
ROLES = {"ceo", "cto", "engineering-manager", "em", "engineer", "review", "qa", "security", "product", "architect", "developer", "backend", "frontend", "devops", "product-manager"}
STATES = {"BACKLOG", "READY", "ACTIVE", "REVIEW", "QA", "SECURITY", "BLOCKED", "DONE"}
WORKLOADS = {"analysis", "implementation", "review", "qa", "security", "planning", "gate", "writable", "general"}


def project_identity(root: str | os.PathLike[str]) -> str:
    """Hash the canonical existing directory, never persist its source path."""
    path = Path(root).resolve(strict=True)
    if not path.is_dir():
        raise ValueError("INVALID_PROJECT")
    canonical = str(path)
    if os.name == "nt":
        canonical = canonical.casefold()
    return "project-" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _enabled() -> bool:
    return os.environ.get("AICO_ERROR_INTELLIGENCE_ENABLED", "1").strip() != "0"


def _member(value: object, allowed: set[str], fallback: str = "") -> str:
    return value if isinstance(value, str) and value in allowed else fallback


def _task(value: object) -> str | None:
    return value if isinstance(value, str) and re.fullmatch(r"AICO-[0-9]{3,8}", value) else None


def _summary(incident: Incident) -> dict[str, Any]:
    # Free-form manual fields are not emitted as executable instructions.
    return {"id": incident.id, "component": incident.component,
            "category": incident.category, "error_type": incident.error_type,
            "status": incident.status, "occurrence_count": incident.occurrence_count,
            "summary": incident.summary[:2000], "task_id": incident.task_id,
            "created_at": incident.created_at}


def _match(match: IncidentMatch, *, include_solution: bool = False) -> dict[str, Any]:
    result = _summary(match.incident)
    result.update(confidence=match.confidence, equivalent=match.equivalent,
                  trust="UNTRUSTED_HISTORICAL_ADVICE", action_authorized=False)
    if include_solution and match.incident.status == "FIX_VERIFIED" and match.incident.verified_fix:
        result["verified_solution"] = match.incident.verified_fix[:2000]
        result["contraindications"] = list(match.incident.contraindications[:8])
    return result


def capture_event(project_path: str | os.PathLike[str], event: Mapping[str, object],
                  store: ErrorIntelligenceStore | None = None) -> dict[str, Any]:
    """Capture one allowlisted observation without diagnosing or verifying fixes."""
    if not _enabled():
        return {"status": "disabled"}
    try:
        if not isinstance(event, Mapping):
            return {"status": "ignored", "code": "UNSUPPORTED_EVENT"}
        kind = event.get("event_type")
        component = ""
        category = ""
        if kind in {"provider_attempt_finished", "provider_context_rejected"}:
            if kind == "provider_attempt_finished" and event.get("success") is not False:
                return {"status": "ignored", "code": "NOT_FAILURE"}
            provider = event.get("provider")
            provider = provider.lower() if isinstance(provider, str) else ""
            if provider == "grok":
                provider = "xai"
            if provider not in PROVIDERS:
                return {"status": "ignored", "code": "UNSUPPORTED_PROVIDER"}
            component = "provider-router/" + provider
            category = _member(event.get("error_category"), CATEGORIES, "context_budget" if kind == "provider_context_rejected" else "unknown")
        elif kind == "runtime_failure":
            component = _member(event.get("component"), COMPONENTS - {"task-lifecycle"})
            category = _member(event.get("error_category"), CATEGORIES, "runtime")
        elif kind == "task_transition":
            previous = _member(event.get("from_state", event.get("from_status")), STATES)
            target = _member(event.get("to_state", event.get("to_status")), STATES)
            if target == "BLOCKED":
                category = "blocked"
            elif previous in {"REVIEW", "QA", "SECURITY"} and target == "READY":
                category = "gate_rejection"
            component = "task-lifecycle" if category else ""
        if not component:
            return {"status": "ignored", "code": "UNSUPPORTED_EVENT"}
        project_id = project_identity(project_path)
        metadata: dict[str, object] = {"event_type": kind, "observed_at": datetime.now(timezone.utc).isoformat(), "component": component, "category": category}
        for field, allowed in (("role", ROLES), ("workload", WORKLOADS), ("from_state", STATES), ("to_state", STATES)):
            value = _member(event.get(field, event.get(field.replace("_state", "_status"))), allowed)
            if value:
                metadata[field] = value
        task = _task(event.get("task_id"))
        if task:
            metadata["task_id"] = task
        run = event.get("run_id")
        run = run if isinstance(run, str) and re.fullmatch(r"(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})", run) else None
        if run:
            metadata["run_id"] = run
        fingerprint = hashlib.sha256(f"runtime-v1\0{component}\0{category}".encode()).hexdigest()
        database = store if store is not None else ErrorIntelligenceStore()
        incident = database.record_incident(project_id=project_id, component=component,
            category="lifecycle_observation" if component == "task-lifecycle" else category,
            error_type=category, summary=f"Runtime observation: {component} / {category}",
            evidence=[json.dumps(metadata, sort_keys=True, separators=(",", ":"))], task_id=task, run_id=run,
            fingerprint=fingerprint)
        matches = database.search(project_id=project_id, component=component, error_type=category, limit=3)
        solutions = database.search(project_id=project_id, component=component, error_type=category, limit=3, verified_solutions_only=True)
        return {"status": "captured", "incident": _summary(incident),
                "incident_id": incident.id, "occurrence_count": incident.occurrence_count,
                "verified_solution_available": bool(solutions),
                "matches": [_match(item) for item in matches], "verified_solutions": [_match(item, include_solution=True) for item in solutions],
                "matching_scope": "COMPONENT_CATEGORY_FAMILY", "causal_equivalence_verified": False,
                "action_authorized": False}
    except Exception:
        return {"status": "unavailable", "code": "ERROR_INTELLIGENCE_UNAVAILABLE"}


class _ReadOnlyStore(ErrorIntelligenceStore):
    """Use the existing query API without initialization or write permissions."""
    def __init__(self, path: Path):
        self.path = path
        self._reject_reparse_path(path)

    def _connect(self) -> sqlite3.Connection:
        self._reject_reparse_path(self.path)
        connection = sqlite3.connect(self.path.as_uri() + "?mode=ro", uri=True, timeout=1)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA query_only=ON")
        try:
            if connection.execute("PRAGMA user_version").fetchone()[0] != SCHEMA_VERSION:
                raise ValueError("UNSUPPORTED_SCHEMA")
            if connection.execute("PRAGMA quick_check").fetchone()[0] != "ok":
                raise ValueError("INVALID_STORE")
        except Exception:
            connection.close()
            raise
        return connection


def lookup(project_path: str | os.PathLike[str], component: str | None = None,
           *, limit: int = 20, store: ErrorIntelligenceStore | None = None) -> dict[str, Any]:
    """Read same-project history; absent stores remain absent."""
    if not _enabled():
        return {"status": "disabled", "matches": []}
    try:
        project_id = project_identity(project_path)
        if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 20:
            return {"status": "unavailable", "code": "INVALID_LIMIT", "matches": []}
        if component is not None and component not in COMPONENTS and component not in {"provider-router/" + name for name in PROVIDERS}:
            return {"status": "unavailable", "code": "INVALID_COMPONENT", "matches": []}
        path = store.path if store is not None else default_store_path()
        if not path.is_file():
            return {"status": "available", "matches": [], "verified_solutions": []}
        database = _ReadOnlyStore(path)
        matches = database.search(project_id=project_id, component=component, limit=limit)
        solutions = database.search(project_id=project_id, component=component, limit=limit, verified_solutions_only=True)
        return {"status": "available", "matches": [_match(item) for item in matches],
                "verified_solutions": [_match(item, include_solution=True) for item in solutions],
                "matching_scope": "PROJECT_OR_COMPONENT_HISTORY", "causal_equivalence_verified": False,
                "action_authorized": False}
    except Exception:
        return {"status": "unavailable", "code": "ERROR_INTELLIGENCE_UNAVAILABLE", "matches": []}


def main() -> int:
    """JSON bridge for local runtime callers; stdin is bounded before parsing."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("capture", "lookup"))
    parser.add_argument("--project", required=True)
    parser.add_argument("--component")
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()
    if args.command == "lookup":
        result = lookup(args.project, args.component, limit=args.limit)
    else:
        try:
            raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
            if len(raw) > MAX_INPUT_BYTES:
                raise ValueError
            envelope = json.loads(raw.decode("utf-8"))
            event = envelope.get("event", envelope) if isinstance(envelope, dict) else None
            result = capture_event(args.project, event)
        except Exception:
            result = {"status": "unavailable", "code": "INVALID_INPUT"}
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
