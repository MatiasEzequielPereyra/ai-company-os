from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class WorkRequestSummary:
    id: str
    objective: str
    request_type: str
    priority: str
    created: str
    source_status: str
    display_status: str
    task_ids: list[str]
    task_statuses: dict[str, str]


@dataclass(frozen=True)
class WorkRequestTaskSummary:
    id: str
    status: str
    owner: str
    work_kind: str
    source_plan: str


@dataclass(frozen=True)
class ReopenedPlanContext:
    project_name: str
    project_root: str


@dataclass(frozen=True)
class ReopenedPreparationResult:
    success: bool
    work_request_ids: list[str]
    created_task_ids: list[str]
    stdout: str
    project_root: str


@dataclass(frozen=True)
class ReopenedWorkRequest:
    summary: WorkRequestSummary
    plan: ReopenedPlanContext
    preparation: ReopenedPreparationResult


class WorkRequestService:
    def list_work_requests(
        self,
        project_root: str | Path,
    ) -> list[WorkRequestSummary]:
        root = Path(project_root).resolve()

        request_dir = (
            root
            / "docs"
            / "engineering"
            / "work-requests"
        )

        if not request_dir.exists():
            return []

        results: list[WorkRequestSummary] = []

        for path in sorted(
            request_dir.glob("WR-*.md"),
            reverse=True,
        ):
            if not path.is_file():
                continue

            content = path.read_text(
                encoding="utf-8-sig",
            )

            request_id = (
                self._read_field(content, "ID")
                or path.stem
            )

            objective = (
                self._read_section(
                    content,
                    "Objective",
                )
                or "No objective"
            )

            request_type = (
                self._read_field(
                    content,
                    "Type",
                )
                or "UNKNOWN"
            )

            priority = (
                self._read_field(
                    content,
                    "Priority",
                )
                or "UNKNOWN"
            )

            created = (
                self._read_field(
                    content,
                    "Created",
                )
                or "UNKNOWN"
            )

            source_status = (
                self._read_field(
                    content,
                    "Status",
                )
                or "UNKNOWN"
            )

            request_tasks = self.tasks_for_request(
                root,
                request_id,
            )

            task_statuses = {
                task.id: task.status
                for task in request_tasks
            }

            task_work_kinds = {
                task.id: task.work_kind
                for task in request_tasks
            }

            results.append(
                WorkRequestSummary(
                    id=request_id,
                    objective=objective,
                    request_type=request_type,
                    priority=priority,
                    created=created,
                    source_status=source_status,
                    display_status=(
                        self._derive_status(
                            task_statuses,
                            request_type=request_type,
                            task_work_kinds=task_work_kinds,
                        )
                    ),
                    task_ids=sorted(
                        task_statuses
                    ),
                    task_statuses=task_statuses,
                )
            )

        return results

    def reopen(
        self,
        project_root: str | Path,
        work_request_id: str,
    ) -> ReopenedWorkRequest:
        root = Path(project_root).resolve()

        requests = {
            item.id: item
            for item in self.list_work_requests(
                root
            )
        }

        if work_request_id not in requests:
            raise FileNotFoundError(
                f"Work request not found: "
                f"{work_request_id}"
            )

        summary = requests[
            work_request_id
        ]

        return ReopenedWorkRequest(
            summary=summary,
            plan=ReopenedPlanContext(
                project_name=root.name,
                project_root=str(root),
            ),
            preparation=ReopenedPreparationResult(
                success=True,
                work_request_ids=[
                    summary.id
                ],
                created_task_ids=list(
                    summary.task_ids
                ),
                stdout="Reopened from repository state.",
                project_root=str(root),
            ),
        )

    def tasks_for_request(
        self,
        project_root: str | Path,
        request_id: str,
    ) -> list[WorkRequestTaskSummary]:
        root = Path(project_root).resolve()
        tasks_dir = root / "tasks"

        if not tasks_dir.exists():
            return []

        result: list[WorkRequestTaskSummary] = []

        for path in sorted(
            tasks_dir.glob("AICO-*.md")
        ):
            if not path.is_file():
                continue

            content = path.read_text(
                encoding="utf-8-sig",
            )

            task_request = self._read_field(
                content,
                "Work request",
            )

            if task_request != request_id:
                continue

            result.append(
                WorkRequestTaskSummary(
                    id=(
                        self._read_field(
                            content,
                            "ID",
                        )
                        or path.stem
                    ),
                    status=(
                        self._read_field(
                            content,
                            "Status",
                        )
                        or "UNKNOWN"
                    ),
                    owner=(
                        self._read_field(
                            content,
                            "Owner",
                        )
                        or "UNKNOWN"
                    ),
                    work_kind=self._read_field(
                        content,
                        "Work kind",
                    ).upper(),
                    source_plan=self._read_field(
                        content,
                        "Source plan",
                    ),
                )
            )

        return result

    def request_ids_for_task_ids(
        self,
        project_root: str | Path,
        task_ids: list[str],
    ) -> list[str]:
        root = Path(project_root).resolve()
        tasks_dir = root / "tasks"
        wanted = {
            task_id
            for task_id in task_ids
            if task_id
        }

        if not wanted or not tasks_dir.exists():
            return []

        request_ids: set[str] = set()

        for task_id in sorted(wanted):
            path = tasks_dir / f"{task_id}.md"

            if not path.exists():
                continue

            content = path.read_text(
                encoding="utf-8-sig",
            )
            request_id = self._read_field(
                content,
                "Work request",
            )

            if request_id:
                request_ids.add(request_id)

        return sorted(request_ids)

    def resolve_task_ids(
        self,
        project_root: str | Path,
        work_request_ids: list[str],
    ) -> list[str]:
        root = Path(project_root).resolve()
        task_ids: set[str] = set()

        for request_id in work_request_ids:
            if not request_id:
                continue

            task_ids.update(
                task.id
                for task in self.tasks_for_request(
                    root,
                    request_id,
                )
            )

        return sorted(task_ids)

    def _tasks_for_request(
        self,
        root: Path,
        request_id: str,
    ) -> dict[str, str]:
        return {
            task.id: task.status
            for task in self.tasks_for_request(
                root,
                request_id,
            )
        }

    def _derive_status(
        self,
        task_statuses: dict[str, str],
        request_type: str = "",
        task_work_kinds: dict[str, str] | None = None,
    ) -> str:
        if not task_statuses:
            return "PLANNING"

        statuses = set(
            task_statuses.values()
        )

        if statuses == {"DONE"}:
            if request_type.upper() == "FEATURE":
                work_kinds = {
                    value.upper()
                    for value in (
                        task_work_kinds or {}
                    ).values()
                    if value
                }

                if "IMPLEMENTATION" not in work_kinds:
                    return "ENGINEERING_PENDING"

            return "DONE"

        if "ACTIVE" in statuses:
            return "ACTIVE"

        if statuses & {
            "REVIEW",
            "QA",
            "SECURITY",
        }:
            return "GATES"

        if "READY" in statuses:
            return "READY"

        if "BLOCKED" in statuses:
            return "BLOCKED"

        if "BACKLOG" in statuses:
            return "PREPARED"

        return "UNKNOWN"

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
            rf"(?:\r?\n\r?\n##|\Z)"
        )

        match = re.search(
            pattern,
            content,
        )

        if not match:
            return ""

        return match.group(1).strip()
