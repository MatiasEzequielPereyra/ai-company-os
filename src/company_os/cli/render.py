from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from company_os.domain.models import CompanySnapshot


console = Console()


def render_status(snapshot: CompanySnapshot) -> None:
    phase = snapshot.project.phase.value + (" (derived)" if snapshot.project.phase_derived else "")
    console.print(Panel.fit(
        f"[bold]Project[/bold]    {snapshot.project.name}\n"
        f"[bold]Phase[/bold]      {phase}\n"
        f"[bold]Objective[/bold]  {snapshot.project.objective or '-'}",
        title="AI COMPANY OS",
    ))

    agents = Table(title="AGENTS")
    agents.add_column("Agent")
    agents.add_column("Work state")
    agents.add_column("Tasks")
    for agent in snapshot.agents:
        agents.add_row(agent.display_name, agent.work_state.value, ", ".join(agent.current_task_ids) or "-")
    console.print(agents)

    tasks = Table(title="TASKS")
    tasks.add_column("Status")
    tasks.add_column("Count", justify="right")
    for label in ("backlog", "ready", "active", "review", "qa", "security", "blocked", "done"):
        tasks.add_row(label.upper(), str(getattr(snapshot.tasks, label)))
    console.print(tasks)

    if snapshot.blockers:
        blockers = Table(title="BLOCKERS")
        blockers.add_column("Task")
        blockers.add_column("Reason")
        for blocker in snapshot.blockers:
            blockers.add_row(blocker.task_id, blocker.reason)
        console.print(blockers)
    else:
        console.print("[bold]BLOCKERS[/bold]\nNone")

    gates = Table(title="QUALITY GATES")
    gates.add_column("Gate")
    gates.add_column("State")
    for gate in snapshot.gates:
        gates.add_row(gate.name, gate.state.value + (" ⚠" if gate.stale else ""))
    console.print(gates)

    console.print("[bold]NEXT ACTION[/bold]")
    console.print(snapshot.next_action.description if snapshot.next_action else "No actionable task found.")

    if snapshot.diagnostics:
        console.print("\n[bold]DIAGNOSTICS[/bold]")
        for diagnostic in snapshot.diagnostics:
            marker = "⚠" if diagnostic.severity.value == "WARNING" else "!"
            console.print(f"{marker} {diagnostic.code}: {diagnostic.message}")
