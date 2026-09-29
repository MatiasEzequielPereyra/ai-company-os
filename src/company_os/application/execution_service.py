from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass
class PreparationResult:
    success: bool
    work_request_ids: list[str]
    created_task_ids: list[str]
    stdout: str
    project_root: str


class ExecutionService:
    COMPATIBLE_STRATEGIES = {
        ("AUDIT", "thorough"),
        ("FEATURE", "balanced"),
    }

    def check_compatibility(
        self,
        plan,
    ) -> tuple[bool, str]:
        key = (
            plan.engine_type,
            plan.strategy_id,
        )

        if key in self.COMPATIBLE_STRATEGIES:
            return (
                True,
                "The selected strategy maps directly "
                "to the current AI Company OS engine.",
            )

        return (
            False,
            (
                "The current engine cannot materialize "
                f"{plan.engine_type}/{plan.strategy_id} "
                "without changing the selected strategy."
            ),
        )

    def prepare(
        self,
        plan,
    ) -> PreparationResult:
        compatible, reason = (
            self.check_compatibility(plan)
        )

        if not compatible:
            raise RuntimeError(reason)

        root = Path(
            plan.project_root
        ).resolve()

        script = (
            root
            / "scripts"
            / "orchestrate.ps1"
        )

        if not script.exists():
            raise FileNotFoundError(
                f"Orchestrator not found: {script}"
            )

        powershell = (
            shutil.which("powershell.exe")
            or shutil.which("powershell")
            or shutil.which("pwsh.exe")
            or shutil.which("pwsh")
        )

        if not powershell:
            raise RuntimeError(
                "PowerShell runtime was not found."
            )

        requests_dir = (
            root
            / "docs"
            / "engineering"
            / "work-requests"
        )

        tasks_dir = root / "tasks"

        before_requests = self._names(
            requests_dir,
            "WR-*.md",
        )

        before_tasks = self._names(
            tasks_dir,
            "AICO-*.md",
        )

        command = [
            powershell,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script),
            "-Objective",
            plan.request,
            "-Type",
            plan.engine_type,
            "-Priority",
            "P1",
            "-RequestedBy",
            "tui",
            "-ProjectPath",
            str(root),
        ]

        process = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=120,
        )

        after_requests = self._names(
            requests_dir,
            "WR-*.md",
        )

        after_tasks = self._names(
            tasks_dir,
            "AICO-*.md",
        )

        new_requests = sorted(
            after_requests
            - before_requests
        )

        new_tasks = sorted(
            after_tasks
            - before_tasks
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
                "AI Company OS PREPARE failed.\n\n"
                + output[-4000:]
            )

        return PreparationResult(
            success=True,
            work_request_ids=[
                Path(name).stem
                for name in new_requests
            ],
            created_task_ids=[
                Path(name).stem
                for name in new_tasks
            ],
            stdout=output,
            project_root=str(root),
        )

    def _names(
        self,
        directory: Path,
        pattern: str,
    ) -> set[str]:
        if not directory.exists():
            return set()

        return {
            path.name
            for path in directory.glob(pattern)
            if path.is_file()
        }