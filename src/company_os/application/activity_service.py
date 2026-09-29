from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from company_os.application.status_service import StatusService
from company_os.repository.markdown_utils import bullet_lines, heading_section
from company_os.repository.task_repository import TaskRepository


_TIMESTAMP_RE = re.compile(
    r"^(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?)\s*(?:-|–|—)?\s*(?P<message>.*)$"
)


@dataclass
class ActivityEvent:
    timestamp: datetime | None
    task_id: str
    owner: str
    kind: str
    message: str
    source: str

    def to_dict(self) -> dict:
        return {
            "timestamp": (
                self.timestamp.isoformat()
                if self.timestamp is not None
                else None
            ),
            "task_id": self.task_id,
            "owner": self.owner,
            "kind": self.kind,
            "message": self.message,
            "source": self.source,
        }


def _parse_timestamp(value: str) -> datetime | None:
    value = value.strip()

    if value.endswith("Z"):
        value = value[:-1] + "+00:00"

    try:
        result = datetime.fromisoformat(value)
    except ValueError:
        return None

    if result.tzinfo is None:
        result = result.replace(
            tzinfo=timezone.utc
        )

    return result


def _parse_activity_line(
    line: str,
) -> tuple[datetime | None, str]:
    line = line.strip().lstrip("-").strip()

    match = _TIMESTAMP_RE.match(line)

    if not match:
        return None, line

    timestamp = _parse_timestamp(
        match.group("timestamp")
    )

    message = (
        match.group("message").strip()
        or line
    )

    return timestamp, message


def build_activity(tasks) -> list[ActivityEvent]:
    events: list[ActivityEvent] = []
    seen: set[tuple] = set()

    def add_event(event: ActivityEvent) -> None:
        key = (
            event.timestamp,
            event.task_id,
            event.kind,
            event.message,
        )

        if key in seen:
            return

        seen.add(key)
        events.append(event)

    for task in tasks:
        source = str(task.source_path)

        if task.created is not None:
            add_event(
                ActivityEvent(
                    timestamp=task.created,
                    task_id=task.id,
                    owner=task.owner,
                    kind="TASK_CREATED",
                    message=f"{task.id} created.",
                    source=source,
                )
            )

        if task.updated is not None:
            add_event(
                ActivityEvent(
                    timestamp=task.updated,
                    task_id=task.id,
                    owner=task.owner,
                    kind="TASK_UPDATED",
                    message=f"{task.id} last updated.",
                    source=source,
                )
            )

        for item in task.evidence:
            timestamp, message = (
                _parse_activity_line(item)
            )

            add_event(
                ActivityEvent(
                    timestamp=timestamp,
                    task_id=task.id,
                    owner=task.owner,
                    kind="EVIDENCE",
                    message=message,
                    source=source,
                )
            )

        if task.source_path.exists():
            text = task.source_path.read_text(
                encoding="utf-8",
                errors="replace",
            )

            transition_section = heading_section(
                text,
                "Transition Log",
            )

            for item in bullet_lines(
                transition_section
            ):
                timestamp, message = (
                    _parse_activity_line(item)
                )

                add_event(
                    ActivityEvent(
                        timestamp=timestamp,
                        task_id=task.id,
                        owner=task.owner,
                        kind="TRANSITION",
                        message=message,
                        source=source,
                    )
                )

    minimum = datetime.min.replace(
        tzinfo=timezone.utc
    )

    events.sort(
        key=lambda event: (
            event.timestamp is not None,
            event.timestamp or minimum,
        ),
        reverse=True,
    )

    return events


class ActivityService:
    def __init__(self) -> None:
        self.status_service = StatusService()
        self.repository = TaskRepository()

    def get_activity(
        self,
        project: Path,
    ) -> list[ActivityEvent]:
        snapshot = self.status_service.get_status(
            project
        )

        root = Path(
            snapshot.project.root
        )

        tasks = self.repository.list_tasks(
            root
        )

        return build_activity(tasks)