from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from company_os.application.work_request_service import (
    WorkRequestService,
)


@dataclass(frozen=True)
class EngineeringBacklogSource:
    task_id: str
    work_request_id: str
    materialized: bool


@dataclass(frozen=True)
class EngineeringBacklogResult:
    materialized_source_ids: list[str]
    skipped_source_ids: list[str]
    task_ids: list[str]


class EngineeringBacklogService:
    def __init__(self) -> None:
        self.work_requests = WorkRequestService()

    def ready_sources(
        self,
        project_root: str | Path,
        work_request_ids: list[str],
    ) -> list[EngineeringBacklogSource]:
        root = Path(project_root).resolve()
        result: list[EngineeringBacklogSource] = []

        feature_requests = {
            request.id
            for request in self.work_requests.list_work_requests(
                root
            )
            if request.request_type.upper() == "FEATURE"
        }

        for request_id in work_request_ids:
            if (
                not request_id
                or request_id not in feature_requests
            ):
                continue

            for task in self.work_requests.tasks_for_request(
                root,
                request_id,
            ):
                if task.owner != "engineering-manager":
                    continue

                if task.status != "DONE":
                    continue

                report_path = (
                    root
                    / "docs"
                    / "engineering"
                    / "agent-reports"
                    / f"{task.id}.md"
                )

                if not report_path.exists():
                    continue

                mapping_path = (
                    root
                    / "docs"
                    / "engineering"
                    / "plans"
                    / (
                        f"{task.id}"
                        "-engineering-backlog-tasks.md"
                    )
                )

                result.append(
                    EngineeringBacklogSource(
                        task_id=task.id,
                        work_request_id=request_id,
                        materialized=mapping_path.exists(),
                    )
                )

        return sorted(
            result,
            key=lambda item: item.task_id,
        )

    def pending_sources(
        self,
        project_root: str | Path,
        work_request_ids: list[str],
    ) -> list[EngineeringBacklogSource]:
        return [
            source
            for source in self.ready_sources(
                project_root,
                work_request_ids,
            )
            if not source.materialized
        ]

    def generate_and_materialize(
        self,
        project_root: str | Path,
        work_request_ids: list[str],
        provider: str = "Auto",
        model: str = "",
    ) -> EngineeringBacklogResult:
        root = Path(project_root).resolve()
        sources = self.ready_sources(
            root,
            work_request_ids,
        )

        if not sources:
            raise RuntimeError(
                "No DONE Engineering Manager task with an "
                "approved agent report is available for "
                "engineering backlog generation."
            )

        generate_script = (
            root
            / "scripts"
            / "generate-engineering-backlog.ps1"
        )
        materialize_script = (
            root
            / "scripts"
            / "materialize-engineering-backlog.ps1"
        )

        for script in (
            generate_script,
            materialize_script,
        ):
            if not script.exists():
                raise FileNotFoundError(
                    f"Required engineering backlog runtime "
                    f"was not found: {script}"
                )

        materialized: list[str] = []
        skipped: list[str] = []

        for source in sources:
            plan_path = (
                root
                / "docs"
                / "engineering"
                / "plans"
                / (
                    f"{source.task_id}"
                    "-engineering-backlog.json"
                )
            )
            mapping_path = (
                root
                / "docs"
                / "engineering"
                / "plans"
                / (
                    f"{source.task_id}"
                    "-engineering-backlog-tasks.md"
                )
            )

            if mapping_path.exists():
                skipped.append(
                    source.task_id
                )
                continue

            if not plan_path.exists():
                generate_args = [
                    "-SourceTaskId",
                    source.task_id,
                    "-ProjectPath",
                    str(root),
                    "-Provider",
                    provider,
                ]

                if model:
                    generate_args.extend(
                        [
                            "-Model",
                            model,
                        ]
                    )

                self._run_script(
                    generate_script,
                    generate_args,
                )

                if not plan_path.exists():
                    raise RuntimeError(
                        "Engineering backlog generation "
                        "completed without producing the "
                        f"canonical plan: {plan_path}"
                    )

            self._run_script(
                materialize_script,
                [
                    "-SourceTaskId",
                    source.task_id,
                    "-ProjectPath",
                    str(root),
                ],
            )

            if not mapping_path.exists():
                raise RuntimeError(
                    "Engineering backlog materialization "
                    "completed without producing the "
                    f"canonical mapping: {mapping_path}"
                )

            materialized.append(
                source.task_id
            )

        return EngineeringBacklogResult(
            materialized_source_ids=materialized,
            skipped_source_ids=skipped,
            task_ids=self.work_requests.resolve_task_ids(
                root,
                work_request_ids,
            ),
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
            timeout=1800,
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
                    "Engineering backlog runtime failed: "
                    + script.name
                )
            )

        return output
