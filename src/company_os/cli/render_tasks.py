from __future__ import annotations

from rich.console import Console
from rich.table import Table


console = Console()


def render_tasks(tasks) -> None:
    table = Table(title="TASKS")

    table.add_column("ID", no_wrap=True)
    table.add_column("Status", no_wrap=True)
    table.add_column("Pri", no_wrap=True)
    table.add_column("Owner")
    table.add_column("Title")

    for task in tasks:
        table.add_row(
            task.id,
            task.status.value,
            task.priority.value,
            task.owner,
            task.title,
        )

    console.print(table)

    if not tasks:
        console.print("[dim]No tasks matched the requested filters.[/dim]")
