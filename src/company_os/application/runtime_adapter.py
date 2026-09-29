from __future__ import annotations

import json
import re
import shutil
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path


_REPORT_FIELD = re.compile(
    r"^(?P<key>Generated|Owner|Provider|Model|Outcome):\s*(?P<value>.+?)\s*$",
    re.MULTILINE | re.IGNORECASE,
)

_GATE_PATTERN = re.compile(
    r"^(?P<task>AICO-\d+)-(?P<gate>review|qa|security)-gate$",
    re.IGNORECASE,
)


@dataclass
class RuntimeExecution:
    task_id: str
    kind: str
    timestamp: datetime
    artifact_path: str
    owner: str | None = None
    provider: str | None = None
    model: str | None = None
    outcome: str | None = None
    valid_json: bool = True

    def to_dict(self) -> dict:
        result = asdict(self)
        result["timestamp"] = self.timestamp.isoformat()
        return result


@dataclass
class RuntimeSnapshot:
    path: str
    available: bool
    event_count: int
    parsed_event_count: int
    malformed_event_count: int

    authoritative_live_state: bool
    live_agents: list[str] = field(default_factory=list)

    runtime_contract_ready: bool = False
    codex_cli_available: bool = False

    executions: list[RuntimeExecution] = field(
        default_factory=list
    )

    message: str = ""

    def to_dict(self) -> dict:
        return {
            "path": self.path,
            "available": self.available,
            "event_count": self.event_count,
            "parsed_event_count": self.parsed_event_count,
            "malformed_event_count": self.malformed_event_count,
            "authoritative_live_state": self.authoritative_live_state,
            "live_agents": self.live_agents,
            "runtime_contract_ready": self.runtime_contract_ready,
            "codex_cli_available": self.codex_cli_available,
            "executions": [
                item.to_dict()
                for item in self.executions
            ],
            "message": self.message,
        }


class RuntimeAdapter:
    REQUIRED_COMPONENTS = [
        "scripts/run-agent-task.ps1",
        "scripts/run-active-agents.ps1",
        "scripts/provider-router.ps1",
        "scripts/providers/invoke-codex.ps1",
        "schemas/agent-result.schema.json",
    ]

    def inspect(
        self,
        root: Path,
    ) -> RuntimeSnapshot:
        root = root.resolve()

        runtime_dir = (
            root
            / ".codex"
            / "runtime"
        )

        contract_ready = all(
            (root / relative).exists()
            for relative in self.REQUIRED_COMPONENTS
        )

        codex_available = bool(
            shutil.which("codex")
            or shutil.which("codex.cmd")
            or shutil.which("codex.exe")
        )

        artifacts = []

        if runtime_dir.exists():
            artifacts.extend(
                runtime_dir.glob(
                    "AICO-*-result.json"
                )
            )

            artifacts.extend(
                runtime_dir.glob(
                    "AICO-*-review-gate.json"
                )
            )

            artifacts.extend(
                runtime_dir.glob(
                    "AICO-*-qa-gate.json"
                )
            )

            artifacts.extend(
                runtime_dir.glob(
                    "AICO-*-security-gate.json"
                )
            )

        artifacts = sorted(
            set(artifacts)
        )

        executions: list[RuntimeExecution] = []

        parsed = 0
        malformed = 0

        for path in artifacts:
            execution = self._read_artifact(
                root,
                path,
            )

            if execution.valid_json:
                parsed += 1
            else:
                malformed += 1

            executions.append(
                execution
            )

        executions.sort(
            key=lambda item: item.timestamp,
            reverse=True,
        )

        if executions:
            message = (
                "Completed runtime artifacts were found. "
                "Live agent state remains UNKNOWN because "
                "AI Company OS does not yet persist an "
                "authoritative start/heartbeat/finish state."
            )
        elif contract_ready:
            message = (
                "Runtime contract is installed, but no "
                "completed execution artifacts were found. "
                "Live agent state remains UNKNOWN."
            )
        else:
            message = (
                "The complete AI Company OS runtime contract "
                "was not found in this project."
            )

        return RuntimeSnapshot(
            path=str(runtime_dir),
            available=runtime_dir.exists(),
            event_count=len(artifacts),
            parsed_event_count=parsed,
            malformed_event_count=malformed,
            authoritative_live_state=False,
            live_agents=[],
            runtime_contract_ready=contract_ready,
            codex_cli_available=codex_available,
            executions=executions,
            message=message,
        )

    def _read_artifact(
        self,
        root: Path,
        path: Path,
    ) -> RuntimeExecution:
        valid_json = True
        data = {}

        try:
            data = json.loads(
                path.read_text(
                    encoding="utf-8",
                    errors="replace",
                )
            )

            if not isinstance(data, dict):
                valid_json = False
                data = {}

        except json.JSONDecodeError:
            valid_json = False
            data = {}

        stem = path.stem

        if stem.endswith("-result"):
            task_id = stem.removesuffix(
                "-result"
            )

            kind = "AGENT_RESULT"

            report_metadata = (
                self._read_report_metadata(
                    root,
                    task_id,
                )
            )

            timestamp = (
                report_metadata.get(
                    "generated"
                )
                or self._mtime(path)
            )

            return RuntimeExecution(
                task_id=task_id,
                kind=kind,
                timestamp=timestamp,
                artifact_path=str(path),
                owner=report_metadata.get(
                    "owner"
                ),
                provider=report_metadata.get(
                    "provider"
                ),
                model=report_metadata.get(
                    "model"
                ),
                outcome=(
                    report_metadata.get(
                        "outcome"
                    )
                    or self._result_outcome(
                        data
                    )
                ),
                valid_json=valid_json,
            )

        gate_match = _GATE_PATTERN.match(
            stem
        )

        if gate_match:
            task_id = gate_match.group(
                "task"
            )

            gate = gate_match.group(
                "gate"
            ).upper()

            return RuntimeExecution(
                task_id=task_id,
                kind=f"{gate}_GATE",
                timestamp=self._mtime(path),
                artifact_path=str(path),
                outcome=self._result_outcome(
                    data
                ),
                valid_json=valid_json,
            )

        return RuntimeExecution(
            task_id="UNKNOWN",
            kind="UNKNOWN",
            timestamp=self._mtime(path),
            artifact_path=str(path),
            outcome=self._result_outcome(
                data
            ),
            valid_json=valid_json,
        )

    def _result_outcome(
        self,
        data: dict,
    ) -> str | None:
        for key in (
            "outcome",
            "recommendation",
            "status",
        ):
            value = data.get(key)

            if value is not None:
                return str(value)

        return None

    def _read_report_metadata(
        self,
        root: Path,
        task_id: str,
    ) -> dict:
        path = (
            root
            / "docs"
            / "engineering"
            / "agent-reports"
            / f"{task_id}.md"
        )

        if not path.exists():
            return {}

        text = path.read_text(
            encoding="utf-8",
            errors="replace",
        )

        result = {}

        for match in _REPORT_FIELD.finditer(
            text
        ):
            key = (
                match.group("key")
                .strip()
                .lower()
            )

            value = (
                match.group("value")
                .strip()
            )

            if key == "generated":
                parsed = self._parse_datetime(
                    value
                )

                if parsed is not None:
                    result[key] = parsed
            else:
                result[key] = value

        return result

    def _parse_datetime(
        self,
        value: str,
    ) -> datetime | None:
        value = value.strip()

        if value.endswith("Z"):
            value = (
                value[:-1]
                + "+00:00"
            )

        try:
            result = datetime.fromisoformat(
                value
            )
        except ValueError:
            return None

        if result.tzinfo is None:
            result = result.replace(
                tzinfo=timezone.utc
            )

        return result

    def _mtime(
        self,
        path: Path,
    ) -> datetime:
        return datetime.fromtimestamp(
            path.stat().st_mtime,
            tz=timezone.utc,
        )