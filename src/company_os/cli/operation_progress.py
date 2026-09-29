from __future__ import annotations

import time
from dataclasses import dataclass, field


SPINNER_FRAMES = (
    "|",
    "/",
    "-",
    "\\",
)


@dataclass
class OperationProgressState:
    busy: bool = False
    kind: str = ""
    title: str = ""
    task_ids: list[str] = field(
        default_factory=list
    )
    current_task: str = ""
    stage: str = ""
    provider: str = "Auto"
    model: str = ""
    context_chars: str = ""
    started_at: float = 0.0
    tick_index: int = 0
    last_event: str = ""
    recent_events: list[str] = field(
        default_factory=list
    )
    gate_states: dict[str, str] = field(
        default_factory=lambda: {
            "REVIEW": "PENDING",
            "QA": "PENDING",
            "SECURITY": "PENDING",
        }
    )
    final_status: str = ""
    final_summary: str = ""
    final_duration: str = ""

    def start(
        self,
        *,
        kind: str,
        title: str,
        task_ids: list[str],
        initial_event: str,
        provider: str = "Auto",
        now: float | None = None,
    ) -> bool:
        if self.busy:
            return False

        self.busy = True
        self.kind = kind
        self.title = title
        self.task_ids = list(
            task_ids
        )
        self.current_task = (
            self.task_ids[0]
            if self.task_ids
            else ""
        )
        self.stage = ""
        self.provider = provider
        self.model = ""
        self.context_chars = ""
        self.started_at = (
            time.monotonic()
            if now is None
            else now
        )
        self.tick_index = 0
        self.last_event = ""
        self.recent_events = []
        self.gate_states = {
            "REVIEW": "PENDING",
            "QA": "PENDING",
            "SECURITY": "PENDING",
        }
        self.final_status = ""
        self.final_summary = ""
        self.final_duration = ""

        self.add_event(
            initial_event
        )

        return True

    def tick(self) -> None:
        if self.busy:
            self.tick_index += 1

    def spinner(self) -> str:
        return SPINNER_FRAMES[
            self.tick_index
            % len(SPINNER_FRAMES)
        ]

    def activity_bar(
        self,
        width: int = 28,
        segment: int = 5,
    ) -> str:
        width = max(width, 8)
        segment = min(
            max(segment, 2),
            width - 2,
        )

        travel = (
            width
            - segment
        )

        if travel <= 0:
            return "[" + ("=" * width) + "]"

        cycle = travel * 2
        offset = (
            self.tick_index
            % cycle
        )

        if offset > travel:
            offset = (
                cycle
                - offset
            )

        cells = [" "] * width

        for index in range(
            offset,
            offset + segment,
        ):
            if index < width:
                cells[index] = "="

        direction = (
            ">"
            if (
                self.tick_index
                % cycle
            ) <= travel
            else "<"
        )

        edge = (
            offset + segment - 1
            if direction == ">"
            else offset
        )

        if 0 <= edge < width:
            cells[edge] = direction

        return "[" + "".join(cells) + "]"

    def elapsed_seconds(
        self,
        now: float | None = None,
    ) -> int:
        if not self.started_at:
            return 0

        value = (
            time.monotonic()
            if now is None
            else now
        )

        return max(
            0,
            int(
                value
                - self.started_at
            ),
        )

    def elapsed_text(
        self,
        now: float | None = None,
    ) -> str:
        total = self.elapsed_seconds(
            now
        )

        minutes, seconds = divmod(
            total,
            60,
        )

        hours, minutes = divmod(
            minutes,
            60,
        )

        if hours:
            return (
                f"{hours:02d}:"
                f"{minutes:02d}:"
                f"{seconds:02d}"
            )

        return (
            f"{minutes:02d}:"
            f"{seconds:02d}"
        )

    def add_event(
        self,
        message: str,
    ) -> None:
        message = " ".join(
            str(message).split()
        ).strip()

        if not message:
            return

        if (
            self.recent_events
            and self.recent_events[-1]
            == message
        ):
            self.last_event = message
            return

        self.last_event = message
        self.recent_events.append(
            message
        )
        self.recent_events = (
            self.recent_events[-5:]
        )

    def begin_gate(
        self,
        task_id: str,
        gate: str,
    ) -> None:
        gate = gate.upper()

        if (
            self.current_task
            and task_id != self.current_task
        ):
            self.gate_states = {
                "REVIEW": "PENDING",
                "QA": "PENDING",
                "SECURITY": "PENDING",
            }

        self.current_task = task_id
        self.stage = gate

        order = (
            "REVIEW",
            "QA",
            "SECURITY",
        )

        if gate in order:
            gate_index = order.index(
                gate
            )

            for completed in (
                order[:gate_index]
            ):
                self.gate_states[
                    completed
                ] = "DONE"

            self.gate_states[
                gate
            ] = "CURRENT"

    def complete_gate(
        self,
        task_id: str,
        gate: str,
    ) -> None:
        gate = gate.upper()
        self.current_task = task_id
        self.stage = gate

        if gate in self.gate_states:
            self.gate_states[
                gate
            ] = "DONE"

    def finish(
        self,
        *,
        status: str,
        summary: str,
        now: float | None = None,
    ) -> None:
        self.final_duration = (
            self.elapsed_text(now)
        )
        self.final_status = status
        self.final_summary = summary
        self.busy = False
