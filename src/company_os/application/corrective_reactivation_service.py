from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ReactivationResult:
    task_ids: list[str]


class CorrectiveReactivationService:
    def reactivate(
        self,
        project_root: str | Path,
        task_ids: list[str],
    ) -> ReactivationResult:
        root = Path(project_root).resolve()

        reactivated: list[str] = []

        for task_id in task_ids:
            task_path = (
                root
                / "tasks"
                / f"{task_id}.md"
            )

            if not task_path.exists():
                continue

            content = task_path.read_text(
                encoding="utf-8-sig"
            )

            status = self._field(
                content,
                "Status",
            )

            if status != "READY":
                continue

            dispatch = (
                root
                / "docs"
                / "engineering"
                / "dispatch"
                / f"{task_id}.md"
            )

            if not dispatch.exists():
                continue

            dispatch_content = dispatch.read_text(
                encoding="utf-8-sig"
            )

            if f"Task: {task_id}" not in dispatch_content:
                raise RuntimeError(
                    f"{task_id}: dispatch identity "
                    "does not match."
                )

            self._run_script(
                root
                / "scripts"
                / "advance-task.ps1",
                [
                    "-Id",
                    task_id,
                    "-Status",
                    "ACTIVE",
                    "-Actor",
                    "engineering-manager",
                    "-Reason",
                    (
                        "Corrective implementation "
                        "reactivated from existing "
                        "execution request."
                    ),
                    "-Evidence",
                    (
                        "Existing execution request: "
                        "docs/engineering/dispatch/"
                        f"{task_id}.md"
                    ),
                    "-TasksPath",
                    str(root / "tasks"),
                ],
            )

            reactivated.append(task_id)

        return ReactivationResult(
            task_ids=reactivated
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
            timeout=120,
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
