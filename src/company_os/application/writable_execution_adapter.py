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
from company_os.application.process_stream import (
    ProgressCallback,
    run_streamed_process,
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
        progress: ProgressCallback | None = None,
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

        if tasks[0].status != "ACTIVE":
            raise RuntimeError(
                f"{task_id} must be ACTIVE before "
                "writable execution. "
                f"Current status: {tasks[0].status}"
            )

        if not workspace.exists():
            raise FileNotFoundError(
                f"Writable workspace not found: "
                f"{workspace}"
            )

        environment = os.environ.copy()

        environment.update(
            self.providers.build_environment(
                "OpenRouter"
            )
        )

        environment.update(
            self.providers.build_environment(
                "Gemini"
            )
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

        if progress is not None:
            progress(
                f"Task: {task_id}"
            )
            progress(
                f"Provider requested: {provider}"
            )
            progress(
                f"Worktree: {workspace}"
            )
            progress(
                "Starting writable runtime..."
            )

        process = run_streamed_process(
            command,
            timeout=1800,
            env=environment,
            on_line=progress,
        )

        output = process.output

        if process.returncode != 0:
            raise RuntimeError(
                output
                or (
                    "Writable agent execution "
                    "failed."
                )
            )

        if progress is not None:
            progress(
                "Refreshing task state..."
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

        if progress is not None:
            progress(
                "Execution result loaded."
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
            stdout=output,
        )

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
