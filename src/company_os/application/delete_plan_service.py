from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from company_os.application.work_request_service import (
    WorkRequestService,
)


@dataclass
class DeletePlanResult:
    work_request_id: str
    deleted_paths: list[str]


class DeletePlanService:
    SAFE_STATUSES = {
        "BACKLOG",
    }

    def __init__(self) -> None:
        self.requests = WorkRequestService()

    def can_delete(
        self,
        project_root: str | Path,
        work_request_id: str,
    ) -> tuple[bool, str]:
        root = Path(project_root).resolve()

        request = self.requests.reopen(
            root,
            work_request_id,
        )

        summary = request.summary

        unsafe = {
            status
            for status
            in summary.task_statuses.values()
            if status not in self.SAFE_STATUSES
        }

        if unsafe:
            return (
                False,
                (
                    "Hard delete is disabled because "
                    "this plan already contains lifecycle "
                    "history: "
                    + ", ".join(
                        sorted(unsafe)
                    )
                    + "."
                ),
            )

        artifacts = self._execution_artifacts(
            root,
            summary.task_ids,
        )

        if artifacts:
            return (
                False,
                (
                    "Hard delete is disabled because "
                    "execution evidence exists."
                ),
            )

        return (
            True,
            "Plan has not entered execution and can be deleted.",
        )

    def delete(
        self,
        project_root: str | Path,
        work_request_id: str,
    ) -> DeletePlanResult:
        root = Path(project_root).resolve()

        request = self.requests.reopen(
            root,
            work_request_id,
        )

        allowed, reason = self.can_delete(
            root,
            work_request_id,
        )

        if not allowed:
            raise RuntimeError(reason)

        deleted: list[str] = []

        for task_id in request.summary.task_ids:
            self._delete_file(
                root,
                root
                / "tasks"
                / f"{task_id}.md",
                deleted,
            )

        work_request_path = (
            root
            / "docs"
            / "engineering"
            / "work-requests"
            / f"{work_request_id}.md"
        )

        self._delete_file(
            root,
            work_request_path,
            deleted,
        )

        plans = (
            root
            / "docs"
            / "engineering"
            / "plans"
        )

        for name in (
            f"{work_request_id}-plan.md",
            f"{work_request_id}-tasks.md",
        ):
            self._delete_file(
                root,
                plans / name,
                deleted,
            )

        current_objective = (
            root
            / ".codex"
            / "state"
            / "current-objective.md"
        )

        if current_objective.exists():
            content = (
                current_objective.read_text(
                    encoding="utf-8-sig"
                )
            )

            if work_request_id in content:
                self._delete_file(
                    root,
                    current_objective,
                    deleted,
                )

        return DeletePlanResult(
            work_request_id=work_request_id,
            deleted_paths=deleted,
        )

    def _execution_artifacts(
        self,
        root: Path,
        task_ids: list[str],
    ) -> list[Path]:
        found: list[Path] = []

        evidence_roots = [
            root
            / "docs"
            / "engineering"
            / "dispatch",

            root
            / "docs"
            / "engineering"
            / "results",

            root
            / "docs"
            / "engineering"
            / "agent-reports",

            root
            / "docs"
            / "engineering"
            / "reviews",

            root
            / "docs"
            / "engineering"
            / "qa",

            root
            / "docs"
            / "engineering"
            / "security",

            root
            / "docs"
            / "engineering"
            / "final-approvals",

            root
            / ".codex"
            / "runtime",
        ]

        for evidence_root in evidence_roots:
            if not evidence_root.exists():
                continue

            for task_id in task_ids:
                found.extend(
                    path
                    for path
                    in evidence_root.rglob(
                        f"{task_id}*"
                    )
                    if path.is_file()
                )

        return found

    def _delete_file(
        self,
        root: Path,
        path: Path,
        deleted: list[str],
    ) -> None:
        if not path.exists():
            return

        relative = str(
            path.relative_to(root)
        )

        path.unlink()

        deleted.append(relative)
