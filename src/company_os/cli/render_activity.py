from __future__ import annotations

from rich.console import Console
from rich.table import Table


console = Console()


def render_activity(events) -> None:
    table = Table(
        title="AI COMPANY OS ACTIVITY"
    )

    table.add_column(
        "Time",
        no_wrap=True,
    )

    table.add_column(
        "Task",
        no_wrap=True,
    )

    table.add_column(
        "Kind",
        no_wrap=True,
    )

    table.add_column(
        "Owner",
        no_wrap=True,
    )

    table.add_column(
        "Activity",
    )

    for event in events:
        timestamp = (
            event.timestamp.isoformat(
                timespec="seconds"
            )
            if event.timestamp
            else "-"
        )

        table.add_row(
            timestamp,
            event.task_id,
            event.kind,
            event.owner,
            event.message,
        )

    console.print(table)

    if not events:
        console.print(
            "[dim]No persisted activity found.[/dim]"
        )