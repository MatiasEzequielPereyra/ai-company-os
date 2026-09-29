from __future__ import annotations

import re
from pathlib import Path

from company_os.domain.models import Priority, Task, TaskStatus, WorkflowPhase
from company_os.repository.markdown_utils import bullet_lines, heading_section, metadata_value, parse_datetime


class TaskRepository:
    def list_tasks(self, root: Path) -> list[Task]:
        task_dir = root / "tasks"
        if not task_dir.exists():
            return []

        tasks: list[Task] = []
        for path in sorted(task_dir.glob("AICO-*.md")):
            tasks.append(self._parse(path))
        return tasks

    def _parse(self, path: Path) -> Task:
        text = path.read_text(encoding="utf-8", errors="replace")
        title_match = re.search(r"^#\s+([A-Z0-9-]+)\s+-\s+(.+?)\s*$", text, flags=re.MULTILINE)
        task_id = metadata_value(text, "ID") or (title_match.group(1) if title_match else path.stem)
        title = title_match.group(2).strip() if title_match else task_id

        raw_status = (metadata_value(text, "Status") or "UNKNOWN").upper()
        raw_priority = (metadata_value(text, "Priority") or "UNKNOWN").upper()
        raw_phase = (metadata_value(text, "Workflow phase") or "").upper()

        status = TaskStatus(raw_status) if raw_status in TaskStatus._value2member_map_ else TaskStatus.UNKNOWN
        priority = Priority(raw_priority) if raw_priority in Priority._value2member_map_ else Priority.UNKNOWN
        phase = WorkflowPhase(raw_phase) if raw_phase in WorkflowPhase._value2member_map_ else None

        dep_section = heading_section(text, "Dependencies")
        dependencies = []
        for line in bullet_lines(dep_section):
            dependencies.extend(re.findall(r"AICO-\d+", line))

        evidence = bullet_lines(heading_section(text, "Evidence"))

        return Task(
            id=task_id,
            title=title,
            status=status,
            priority=priority,
            owner=metadata_value(text, "Owner") or "UNKNOWN",
            created=parse_datetime(metadata_value(text, "Created")),
            updated=parse_datetime(metadata_value(text, "Updated")),
            workflow_phase=phase,
            objective=heading_section(text, "Objective"),
            dependencies=dependencies,
            evidence=evidence,
            source_path=path,
        )
