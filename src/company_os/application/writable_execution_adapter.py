from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from company_os.application.agent_control_service import (
    AgentControlService,
)
from company_os.application.provider_service import (
    ProviderService,
)
from company_os.application.task_result_service import (
    TaskResultService,
)


@dataclass(frozen=True)
class WritableExecutionResult:
    task_id: str
    workspace_path: str
    provider: str
    model: str
    status: str
    outcome: str
    summary: str
    blockers: str
    recommended_next: str
    result_path: str
    evidence_path: str
    changed_paths: tuple[str, ...]
    verification: str
    diff_stat: str
    diff_text: str
    stdout: str


class WritableExecutionAdapter:
    def __init__(self) -> None:
        self.control = AgentControlService()
        self.providers = ProviderService()
        self.results = TaskResultService()

    def run(
        self,
        project_root: str | Path,
        task_id: str,
        workspace_path: str | Path,
        provider: str = "Auto",
        model: str = "",
    ) -> WritableExecutionResult:
        root = Path(project_root).resolve()
        workspace = Path(workspace_path).resolve()

        script = (
            root
            / "scripts"
            / "run-writable-agent.ps1"
        )

        if not script.exists():
            raise FileNotFoundError(
                "Writable runner is not installed: "
                f"{script}"
            )

        tasks = self.control.get_tasks(
            root,
            [task_id],
        )

        if not tasks:
            raise RuntimeError(
                f"Task not found: {task_id}"
            )

        if tasks[0].work_kind != "IMPLEMENTATION":
            raise RuntimeError(
                f"{task_id} is not an IMPLEMENTATION task "
                "and cannot use writable execution."
            )

        if tasks[0].status not in {
            "READY",
            "ACTIVE",
        }:
            raise RuntimeError(
                f"{task_id} must be READY or ACTIVE before "
                "writable execution. "
                f"Current status: {tasks[0].status}"
            )

        if not workspace.exists():
            raise FileNotFoundError(
                f"Writable workspace not found: "
                f"{workspace}"
            )

        environment = (
            self.providers
            .build_environment_all()
        )

        command = [
            self._powershell(),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script),
            "-Id",
            task_id,
            "-ProjectPath",
            str(root),
            "-WorkspacePath",
            str(workspace),
            "-Provider",
            provider,
        ]

        if model:
            command.extend(
                [
                    "-Model",
                    model,
                ]
            )

        process = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=1800,
            env=environment,
        )

        output = (
            (process.stdout or "")
            + (
                "\n" + process.stderr
                if process.stderr
                else ""
            )
        ).strip()

        if process.returncode != 0:
            raise RuntimeError(
                output
                or (
                    "Writable agent execution "
                    "failed."
                )
            )

        updated = self.control.get_tasks(
            root,
            [task_id],
        )

        status = (
            updated[0].status
            if updated
            else "UNKNOWN"
        )

        details = self.results.read_latest(
            root,
            task_id,
        )

        stdout_provider = self._output_field(
            output,
            "Provider",
        )

        stdout_model = self._output_field(
            output,
            "Model",
        )

        provider_name = (
            stdout_provider
            or details.provider
            or "not recorded"
        )

        model_name = (
            stdout_model
            or details.model
            or "not recorded"
        )

        diff_stat, diff_text = self._git_diff(
            workspace
        )

        return WritableExecutionResult(
            task_id=task_id,
            workspace_path=str(workspace),
            provider=provider_name,
            model=model_name,
            status=status,
            outcome=(
                details.outcome
                or status
            ),
            summary=details.summary,
            blockers=details.blockers,
            recommended_next=(
                details.recommended_next
            ),
            result_path=details.result_path,
            evidence_path=details.evidence_path,
            changed_paths=details.changed_paths,
            verification=details.verification,
            diff_stat=diff_stat,
            diff_text=diff_text,
            stdout=output,
        )

    def _git_diff(
        self,
        workspace: Path,
    ) -> tuple[str, str]:
        commands = [
            [
                "git",
                "-C",
                str(workspace),
                "diff",
                "--stat",
            ],
            [
                "git",
                "-C",
                str(workspace),
                "diff",
                "--no-ext-diff",
                "--",
            ],
        ]

        values: list[str] = []

        for command in commands:
            process = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=120,
            )

            if process.returncode != 0:
                values.append(
                    "Git diff unavailable: "
                    + (
                        process.stderr.strip()
                        or "unknown git error"
                    )
                )
                continue

            value = process.stdout.strip()

            if len(value) > 40000:
                value = (
                    value[:40000]
                    + "\n[DIFF TRUNCATED]"
                )

            values.append(value)

        return values[0], values[1]

    def _output_field(
        self,
        output: str,
        field: str,
    ) -> str:
        matches = re.findall(
            rf"(?mi)^{re.escape(field)}:\s*(.+)$",
            output,
        )

        if not matches:
            return ""

        return matches[-1].strip()

    def _powershell(self) -> str:
        executable = (
            shutil.which("powershell.exe")
            or shutil.which("powershell")
            or shutil.which("pwsh.exe")
            or shutil.which("pwsh")
        )

        if not executable:
            raise RuntimeError(
                "PowerShell runtime was not found."
            )

        return executable
