from __future__ import annotations

from pathlib import Path

from company_os.application.status_service import StatusService
from company_os.domain.models import Priority, TaskStatus
from company_os.repository.task_repository import TaskRepository


def filter_tasks(
    tasks,
    *,
    status: str | None = None,
    owner: str | None = None,
    priority: str | None = None,
):
    result = list(tasks)

    if status:
        normalized = status.strip().upper()

        if normalized not in TaskStatus._value2member_map_:
            valid = ", ".join(TaskStatus._value2member_map_.keys())
            raise ValueError(
                f"Unknown task status '{status}'. Valid values: {valid}"
            )

        expected = TaskStatus(normalized)
        result = [task for task in result if task.status == expected]

    if owner:
        expected_owner = owner.strip().casefold()
        result = [
            task
            for task in result
            if task.owner.casefold() == expected_owner
        ]

    if priority:
        normalized = priority.strip().upper()

        if normalized not in Priority._value2member_map_:
            valid = ", ".join(Priority._value2member_map_.keys())
            raise ValueError(
                f"Unknown priority '{priority}'. Valid values: {valid}"
            )

        expected = Priority(normalized)
        result = [task for task in result if task.priority == expected]

    return sorted(result, key=lambda task: task.id)


class TaskService:
    def __init__(self) -> None:
        self.status_service = StatusService()
        self.repository = TaskRepository()

    def list_tasks(
        self,
        project: Path,
        *,
        status: str | None = None,
        owner: str | None = None,
        priority: str | None = None,
    ):
        # StatusService already resolves and validates the repository.
        snapshot = self.status_service.get_status(project)
        root = Path(snapshot.project.root)

        tasks = self.repository.list_tasks(root)

        return filter_tasks(
            tasks,
            status=status,
            owner=owner,
            priority=priority,
        )
