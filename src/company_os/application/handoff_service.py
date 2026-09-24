from __future__ import annotations

import re
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

from company_os.application.status_service import StatusService
from company_os.domain.models import TaskStatus
from company_os.repository.markdown_utils import bullet_lines, heading_section
from company_os.repository.task_repository import TaskRepository


_HANDOFF_RE = re.compile(
    r"^\s*Next agent:\s*(?P<agent>.+?)\s*$",
    re.IGNORECASE | re.MULTILINE,
)

_TRANSITION_RE = re.compile(
    r"^(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?)"
    r"\s*-\s*"
    r"(?P<actor>.+?)"
    r"\s*-\s*"
    r"(?P<from_state>[A-Z_]+)"
    r"\s*->\s*"
    r"(?P<to_state>[A-Z_]+)"
    r"(?:\s*-\s*(?P<reason>.*))?$"
)


@dataclass
class HandoffRecord:
    task_id: str
    kind: str
    from_actor: str | None
    to_actor: str
    timestamp: datetime | None
    message: str
    stale: bool
    source: str

    def to_dict(self) -> dict:
        result = asdict(self)

        result["timestamp"] = (
            self.timestamp.isoformat()
            if self.timestamp
            else None
        )

        return result


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


def build_handoffs(tasks) -> list[HandoffRecord]:
    records: list[HandoffRecord] = []

    for task in tasks:
        path = task.source_path

        if not path.exists():
            continue

        text = path.read_text(
            encoding="utf-8",
            errors="replace",
        )

        source = str(path)

        handoff_section = heading_section(
            text,
            "Handoff",
        )

        explicit = _HANDOFF_RE.search(
            handoff_section or ""
        )

        if explicit:
            next_agent = (
                explicit
                .group("agent")
                .strip()
            )

            records.append(
                HandoffRecord(
                    task_id=task.id,
                    kind="EXPLICIT",
                    from_actor=task.owner,
                    to_actor=next_agent,
                    timestamp=task.updated,
                    message=(
                        f"Explicit next agent: "
                        f"{next_agent}"
                    ),
                    stale=(
                        task.status
                        == TaskStatus.DONE
                    ),
                    source=source,
                )
            )

        transition_section = heading_section(
            text,
            "Transition Log",
        )

        transitions = []

        for line in bullet_lines(
            transition_section
        ):
            match = _TRANSITION_RE.match(
                line.strip()
            )

            if not match:
                continue

            transitions.append(
                {
                    "timestamp": _parse_timestamp(
                        match.group("timestamp")
                    ),
                    "actor": (
                        match.group("actor")
                        .strip()
                    ),
                    "from_state": (
                        match.group("from_state")
                        .strip()
                    ),
                    "to_state": (
                        match.group("to_state")
                        .strip()
                    ),
                    "reason": (
                        match.group("reason")
                        or ""
                    ).strip(),
                }
            )

        transitions.sort(
            key=lambda item: (
                item["timestamp"]
                or datetime.min.replace(
                    tzinfo=timezone.utc
                )
            )
        )

        previous_actor = None

        for transition in transitions:
            actor = transition["actor"]

            if (
                previous_actor is not None
                and actor.casefold()
                != previous_actor.casefold()
            ):
                records.append(
                    HandoffRecord(
                        task_id=task.id,
                        kind="OBSERVED_ACTOR_CHANGE",
                        from_actor=previous_actor,
                        to_actor=actor,
                        timestamp=transition[
                            "timestamp"
                        ],
                        message=(
                            f"{transition['from_state']} "
                            f"-> {transition['to_state']}"
                            + (
                                f": {transition['reason']}"
                                if transition["reason"]
                                else ""
                            )
                        ),
                        stale=False,
                        source=source,
                    )
                )

            previous_actor = actor

    records.sort(
        key=lambda record: (
            record.timestamp
            is not None,
            record.timestamp
            or datetime.min.replace(
                tzinfo=timezone.utc
            ),
        ),
        reverse=True,
    )

    return records


class HandoffService:
    def __init__(self) -> None:
        self.status_service = StatusService()
        self.repository = TaskRepository()

    def get_handoffs(
        self,
        project: Path,
    ) -> list[HandoffRecord]:
        snapshot = (
            self.status_service
            .get_status(project)
        )

        root = Path(
            snapshot.project.root
        )

        tasks = self.repository.list_tasks(
            root
        )

        return build_handoffs(tasks)