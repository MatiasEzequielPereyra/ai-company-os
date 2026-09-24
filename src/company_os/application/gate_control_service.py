from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from company_os.application.agent_control_service import (
    AgentControlService,
)


@dataclass
class GateBatchResult:
    task_ids: list[str]
    stdout: str


@dataclass
class FinalizeResult:
    done_task_ids: list[str]
    stdout: str


class GateControlService:
    def __init__(self) -> None:
        self.control = AgentControlService()

    def run_pending_gates_scoped(
        self,
        project_root: str | Path,
        allowed_task_ids: list[str],
        provider: str = "Auto",
        model: str = "",
    ) -> GateBatchResult:
        root = Path(project_root).resolve()
        allowed = set(allowed_task_ids)

        processed: list[str] = []
        output: list[str] = []

        for task_id in sorted(allowed):
            touched = False

            for _ in range(3):
                task = self._task(
                    root,
                    task_id,
                )

                if task is None:
                    break

                status = task.status

                if status == "REVIEW":
                    gate = "Review"

                elif status == "QA":
                    gate = "QA"

                elif status == "SECURITY":
                    if self._security_satisfied(
                        root,
                        task_id,
                    ):
                        break

                    gate = "Security"

                else:
                    break

                args = [
                    "-ProjectPath",
                    str(root),
                    "-Id",
                    task_id,
                    "-Gate",
                    gate,
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

                output.append(
                    self._run_script(
                        root
                        / "scripts"
                        / "run-gate-agent.ps1",
                        args,
                        timeout=1800,
                    )
                )

                touched = True

            if touched:
                processed.append(task_id)

        self._sync_state(root)

        return GateBatchResult(
            task_ids=processed,
            stdout="\n\n".join(
                item
                for item in output
                if item
            ),
        )

    def finalizable_task_ids(
        self,
        project_root: str | Path,
        allowed_task_ids: list[str],
    ) -> list[str]:
        root = Path(project_root).resolve()

        result: list[str] = []

        for task_id in allowed_task_ids:
            task = self._task(
                root,
                task_id,
            )

            if (
                task is not None
                and task.status == "SECURITY"
                and self._qa_satisfied(
                    root,
                    task_id,
                )
                and self._security_satisfied(
                    root,
                    task_id,
                )
            ):
                result.append(task_id)

        return sorted(result)

    def finalize_scoped(
        self,
        project_root: str | Path,
        allowed_task_ids: list[str],
    ) -> FinalizeResult:
        root = Path(project_root).resolve()

        finalizable = (
            self.finalizable_task_ids(
                root,
                allowed_task_ids,
            )
        )

        if not finalizable:
            raise RuntimeError(
                "There are no SECURITY tasks with "
                "satisfied QA and Security gates."
            )

        output: list[str] = []
        done: list[str] = []

        for task_id in finalizable:
            output.append(
                self._run_script(
                    root
                    / "scripts"
                    / "finalize-task.ps1",
                    [
                        "-Id",
                        task_id,
                        "-Decision",
                        "APPROVE",
                        "-Verification",
                        (
                            "Explicit CEO approval from "
                            "AI Company OS TUI after "
                            "verified QA and Security gates."
                        ),
                        "-ProjectPath",
                        str(root),
                    ],
                    timeout=120,
                )
            )

            done.append(task_id)

        self._sync_state(root)

        return FinalizeResult(
            done_task_ids=done,
            stdout="\n\n".join(output),
        )

    def _task(
        self,
        root: Path,
        task_id: str,
    ):
        tasks = self.control.get_tasks(
            root,
            [task_id],
        )

        if not tasks:
            return None

        return tasks[0]

    def _qa_satisfied(
        self,
        root: Path,
        task_id: str,
    ) -> bool:
        path = (
            root
            / "docs"
            / "engineering"
            / "qa"
            / f"{task_id}-qa.md"
        )

        return (
            self._artifact_field(
                path,
                "Outcome",
            )
            == "PASS"
        )

    def _security_satisfied(
        self,
        root: Path,
        task_id: str,
    ) -> bool:
        path = (
            root
            / "docs"
            / "engineering"
            / "security"
            / f"{task_id}-security.md"
        )

        outcome = self._artifact_field(
            path,
            "Outcome",
        )

        return outcome in {
            "PASS",
            "NOT_APPLICABLE",
        }

    def _artifact_field(
        self,
        path: Path,
        field: str,
    ) -> str:
        if not path.exists():
            return ""

        return self._field(
            path.read_text(
                encoding="utf-8-sig"
            ),
            field,
        )

    def _field(
        self,
        content: str,
        key: str,
    ) -> str:
        import re

        match = re.search(
            rf"(?m)^{re.escape(key)}:\s*(.+)$",
            content,
        )

        if not match:
            return ""

        return match.group(1).strip()

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
                f"Required script not found: {script}"
            )

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
            timeout=timeout,
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
                or f"Script failed: {script.name}"
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
