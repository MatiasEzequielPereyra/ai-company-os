from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from company_os.application.agent_control_service import (
    AgentControlService,
)


@dataclass(frozen=True)
class WritableWorkspace:
    task_id: str
    branch: str
    path: str
    created: bool


@dataclass(frozen=True)
class WritableWorkspaceResult:
    workspaces: list[WritableWorkspace]
    runner_available: bool


class WritableWorkspaceService:
    def __init__(self) -> None:
        self.control = AgentControlService()

    def prepare(
        self,
        project_root: str | Path,
        allowed_task_ids: list[str],
    ) -> WritableWorkspaceResult:
        root = Path(project_root).resolve()

        tasks = self.control.get_tasks(
            root,
            allowed_task_ids,
        )

        writable_tasks = [
            task
            for task in tasks
            if task.status in {
                "READY",
                "ACTIVE",
            }
        ]

        if not writable_tasks:
            raise RuntimeError(
                "No READY/ACTIVE tasks are available "
                "for writable workspace preparation."
            )

        script = (
            root
            / "scripts"
            / "new-agent-workspace.ps1"
        )

        if not script.exists():
            raise FileNotFoundError(
                "new-agent-workspace.ps1 was not found."
            )

        workspace_root = (
            root.parent
            / f"{root.name}-worktrees"
        )

        result: list[WritableWorkspace] = []

        for task in writable_tasks:
            workspace = (
                workspace_root
                / task.id
            )

            branch = (
                "aico/"
                + task.id.lower()
            )

            if workspace.exists():
                result.append(
                    WritableWorkspace(
                        task_id=task.id,
                        branch=branch,
                        path=str(workspace),
                        created=False,
                    )
                )
                continue

            self._run_script(
                script,
                [
                    "-Id",
                    task.id,
                    "-ProjectPath",
                    str(root),
                ],
            )

            if not workspace.exists():
                raise RuntimeError(
                    f"{task.id}: workspace script "
                    "completed but expected path "
                    f"does not exist: {workspace}"
                )

            result.append(
                WritableWorkspace(
                    task_id=task.id,
                    branch=branch,
                    path=str(workspace),
                    created=True,
                )
            )

        runner = (
            root
            / "scripts"
            / "run-writable-agent.ps1"
        )

        return WritableWorkspaceResult(
            workspaces=result,
            runner_available=runner.exists(),
        )

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

    def _run_script(
        self,
        script: Path,
        arguments: list[str],
    ) -> str:
        process = subprocess.run(
            [
                self._powershell(),
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script),
                *arguments,
            ],
            capture_output=True,
            text=True,
            timeout=180,
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
                    "Workspace creation failed: "
                    + script.name
                )
            )

        return output
