from __future__ import annotations

from rich.console import Console
from rich.table import Table


console = Console()


def render_doctor(findings) -> None:
    table = Table(
        title="AI COMPANY OS DOCTOR"
    )

    table.add_column(
        "Severity",
        no_wrap=True,
    )

    table.add_column(
        "Code",
        no_wrap=True,
    )

    table.add_column(
        "Message",
    )

    for finding in findings:
        table.add_row(
            finding.severity.value,
            finding.code,
            finding.message,
        )

    console.print(table)
