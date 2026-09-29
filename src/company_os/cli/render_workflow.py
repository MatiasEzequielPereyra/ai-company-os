from __future__ import annotations

from rich.console import Console
from rich.panel import Panel
from rich.table import Table


console = Console()


def render_workflow(workflow) -> None:
    table = Table(
        title="AI COMPANY OS WORKFLOW"
    )

    table.add_column("Task")
    table.add_column("Status")
    table.add_column("Execution")
    table.add_column("Owner")
    table.add_column("Depends on")
    table.add_column("Waiting for")

    for node in workflow.nodes:
        table.add_row(
            node.task_id,
            node.status,
            node.execution_state,
            node.owner,
            ", ".join(node.dependencies) or "-",
            ", ".join(node.unmet_dependencies) or "-",
        )

    console.print(table)

    console.print(
        Panel(
            ", ".join(workflow.parallel_now)
            or "None",
            title="Can run / advance now",
        )
    )

    console.print(
        Panel(
            ", ".join(workflow.waiting)
            or "None",
            title="Waiting",
        )
    )

    if workflow.edges:
        graph = "\n".join(
            f"{edge.source}  ->  {edge.target}"
            for edge in workflow.edges
        )
    else:
        graph = "No dependency edges."

    console.print(
        Panel(
            graph,
            title="Dependency Graph",
        )
    )

    if workflow.cycles:
        cycle_text = "\n".join(
            " -> ".join(cycle)
            for cycle in workflow.cycles
        )

        console.print(
            Panel(
                cycle_text,
                title="Dependency Cycles",
            )
        )

    if workflow.missing_dependencies:
        console.print(
            Panel(
                "\n".join(
                    workflow.missing_dependencies
                ),
                title="Missing Dependencies",
            )
        )
