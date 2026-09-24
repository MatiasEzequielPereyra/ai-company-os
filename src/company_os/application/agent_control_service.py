from __future__ import annotations

import os

import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from company_os.application.provider_service import ProviderService

from company_os.repository.task_repository import TaskRepository


@dataclass(frozen=True)
class ControlledTask:
    id: str
    title: str
    owner: str
    status: str


@dataclass
class ActivationResult:
    ready_task_ids: list[str]
    active_task_ids: list[str]
    stdout: str


@dataclass
class AgentRunResult:
    task_ids: list[str]
    stdout: str


class AgentControlService:
    def __init__(self) -> None:
        self.tasks = TaskRepository()

    def get_tasks(
        self,
        project_root: str | Path,
        task_ids: list[str] | None = None,
    ) -> list[ControlledTask]:
        root = Path(project_root).resolve()

        allowed = (
            set(task_ids)
            if task_ids is not None
            else None
        )

        result: list[ControlledTask] = []

        for task in self.tasks.list_tasks(root):
            task_id = str(task.id)

            if (
                allowed is not None
                and task_id not in allowed
            ):
                continue

            status = getattr(
                task.status,
                "value",
                str(task.status),
            )

            result.append(
                ControlledTask(
                    id=task_id,
                    title=str(task.title),
                    owner=str(task.owner),
                    status=str(status),
                )
            )

        return sorted(
            result,
            key=lambda item: item.id,
        )

    def activate_ready(
        self,
        project_root: str | Path,
        allowed_task_ids: list[str],
    ) -> ActivationResult:
        root = Path(project_root).resolve()
        allowed = set(allowed_task_ids)

        if not allowed:
            raise RuntimeError(
                "There are no prepared tasks to activate."
            )

        # Only READY/ACTIVE work can interfere with the
        # global dispatch/runtime scripts.
        self._assert_no_unrelated_execution_work(
            root,
            allowed,
        )

        advance_script = (
            root
            / "scripts"
            / "advance-task.ps1"
        )

        output: list[str] = []
        newly_ready: list[str] = []

        plan_tasks = self.get_tasks(
            root,
            list(allowed),
        )

        # Evaluate readiness ONLY for this plan.
        for task in plan_tasks:
            if task.status != "BACKLOG":
                continue

            reasons = self._readiness_reasons(
                root,
                task.id,
            )

            if reasons:
                continue

            result = self._run_script(
                advance_script,
                [
                    "-Id",
                    task.id,
                    "-Status",
                    "READY",
                    "-Actor",
                    "engineering-manager",
                    "-Reason",
                    (
                        "Scoped readiness evaluation passed "
                        "for the current prepared plan."
                    ),
                    "-Evidence",
                    (
                        "AI Company OS TUI scoped readiness "
                        "evaluation passed."
                    ),
                    "-TasksPath",
                    str(root / "tasks"),
                ],
                timeout=120,
            )

            output.append(result)
            newly_ready.append(task.id)

        ready = self._ids_with_status(
            root,
            "READY",
        )

        unexpected_ready = (
            ready - allowed
        )

        if unexpected_ready:
            raise RuntimeError(
                "Activation stopped because unrelated READY "
                "tasks exist: "
                + ", ".join(
                    sorted(unexpected_ready)
                )
            )

        if ready & allowed:
            dispatch = (
                root
                / "scripts"
                / "dispatch-ready-tasks.ps1"
            )

            output.append(
                self._run_script(
                    dispatch,
                    [
                        "-ProjectPath",
                        str(root),
                        "-Apply",
                    ],
                    timeout=120,
                )
            )

        active = self._ids_with_status(
            root,
            "ACTIVE",
        )

        unexpected_active = (
            active - allowed
        )

        if unexpected_active:
            raise RuntimeError(
                "Activation stopped because unrelated ACTIVE "
                "tasks exist: "
                + ", ".join(
                    sorted(unexpected_active)
                )
            )

        self._sync_state(root)

        return ActivationResult(
            ready_task_ids=sorted(
                newly_ready
            ),
            active_task_ids=sorted(
                active & allowed
            ),
            stdout="\n\n".join(
                part
                for part in output
                if part
            ),
        )

    def run_active_agents(
        self,
        project_root: str | Path,
        allowed_task_ids: list[str],
        provider: str = "Auto",
        model: str = "",
    ) -> AgentRunResult:
        root = Path(project_root).resolve()
        allowed = set(allowed_task_ids)

        active = self._ids_with_status(
            root,
            "ACTIVE",
        )

        unexpected = active - allowed

        if unexpected:
            raise RuntimeError(
                "Execution refused because unrelated ACTIVE "
                "tasks exist: "
                + ", ".join(
                    sorted(unexpected)
                )
            )

        selected = sorted(
            active & allowed
        )

        if not selected:
            raise RuntimeError(
                "There are no ACTIVE tasks from this plan."
            )

        script = (
            root
            / "scripts"
            / "run-active-agents.ps1"
        )

        args = [
            "-ProjectPath",
            str(root),
            "-Provider",
            provider,
        ]

        if model:
            args.extend(
                [
                    "-Model",
                    model,
                ]
            )

        if len(selected) > 1:
            args.append(
                "-Parallel"
            )

        output = self._run_script(
            script,
            args,
            timeout=1800,
        )

        self._sync_state(root)

        return AgentRunResult(
            task_ids=selected,
            stdout=output,
        )

    def _assert_no_unrelated_execution_work(
        self,
        root: Path,
        allowed: set[str],
    ) -> None:
        conflicts = []

        for task in self.get_tasks(root):
            if task.id in allowed:
                continue

            if task.status in {
                "READY",
                "ACTIVE",
            }:
                conflicts.append(
                    f"{task.id} [{task.status}]"
                )

        if conflicts:
            raise RuntimeError(
                "Activation is blocked because unrelated "
                "READY/ACTIVE tasks could be affected by "
                "the global runtime scripts:\n\n"
                + "\n".join(conflicts)
                + "\n\nFinish, move, or review those tasks "
                "before activating this plan."
            )

    def _readiness_reasons(
        self,
        root: Path,
        task_id: str,
    ) -> list[str]:
        path = (
            root
            / "tasks"
            / f"{task_id}.md"
        )

        if not path.exists():
            return [
                f"Task file not found: {task_id}"
            ]

        content = path.read_text(
            encoding="utf-8-sig",
        )

        reasons: list[str] = []

        owner = self._read_field(
            content,
            "Owner",
        )

        objective = self._read_section(
            content,
            "Objective",
        )

        context = self._read_section(
            content,
            "Context",
        )

        acceptance = self._read_section(
            content,
            "Acceptance Criteria",
        )

        if not owner:
            reasons.append(
                "Missing owner"
            )

        if (
            not objective
            or objective.strip() == "-"
        ):
            reasons.append(
                "Missing objective"
            )

        if (
            not context
            or context.strip() == "-"
        ):
            reasons.append(
                "Missing context"
            )

        if (
            not acceptance
            or acceptance.strip() == "-"
        ):
            reasons.append(
                "Missing acceptance criteria"
            )

        for dependency in self._dependencies(
            content
        ):
            dependency_path = (
                root
                / "tasks"
                / f"{dependency}.md"
            )

            if not dependency_path.exists():
                reasons.append(
                    f"Dependency not found: {dependency}"
                )
                continue

            dependency_content = (
                dependency_path.read_text(
                    encoding="utf-8-sig"
                )
            )

            status = self._read_field(
                dependency_content,
                "Status",
            )

            if status != "DONE":
                reasons.append(
                    f"Dependency not done: "
                    f"{dependency} ({status})"
                )

        return reasons

    def _read_field(
        self,
        content: str,
        key: str,
    ) -> str:
        match = re.search(
            rf"(?m)^{re.escape(key)}:\s*(.+)$",
            content,
        )

        if not match:
            return ""

        return match.group(1).strip()

    def _read_section(
        self,
        content: str,
        section: str,
    ) -> str:
        pattern = (
            rf"(?ms)^## {re.escape(section)}"
            rf"\s*\r?\n\s*\r?\n"
            rf"(.+?)"
            rf"(?:\r?\n\r?\n---|"
            rf"\r?\n\r?\n##|\Z)"
        )

        match = re.search(
            pattern,
            content,
        )

        if not match:
            return ""

        return match.group(1).strip()

    def _dependencies(
        self,
        content: str,
    ) -> list[str]:
        section = self._read_section(
            content,
            "Dependencies",
        )

        if not section:
            return []

        result = []

        for line in section.splitlines():
            match = re.match(
                r"^\s*-\s+(AICO-\d+)\s*$",
                line,
            )

            if match:
                result.append(
                    match.group(1)
                )

        return result

    def _ids_with_status(
        self,
        root: Path,
        status: str,
    ) -> set[str]:
        return {
            task.id
            for task in self.get_tasks(root)
            if task.status == status
        }

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
        timeout: int,
    ) -> str:
        if not script.exists():
            raise FileNotFoundError(
                f"Required AI Company OS script "
                f"not found: {script}"
            )

        command = [
            self._powershell(),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script),
            *arguments,
        ]

        environment = os.environ.copy()

        providers = ProviderService()

        environment.update(
            providers.build_environment(
                "OpenRouter"
            )
        )

        environment.update(
            providers.build_environment(
                "Gemini"
            )
        )

        process = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
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
                    "AI Company OS script failed: "
                    + script.name
                )
            )

        return output

    def _sync_state(
        self,
        root: Path,
    ) -> None:
        script = (
            root
            / "scripts"
            / "sync-company-state.ps1"
        )

        if not script.exists():
            return

        self._run_script(
            script,
            [
                "-TasksPath",
                str(root / "tasks"),
                "-SprintPath",
                str(
                    root
                    / ".codex"
                    / "state"
                    / "current-sprint.md"
                ),
            ],
            timeout=120,
        )
