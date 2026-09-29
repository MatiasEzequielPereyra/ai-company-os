from __future__ import annotations

import json
from pathlib import Path

import typer

from company_os.application.config_service import ConfigService
from company_os.application.status_service import StatusService
from company_os.application.handoff_service import HandoffService
from company_os.application.runtime_service import RuntimeService
from company_os.application.activity_service import ActivityService
from company_os.application.workflow_service import WorkflowService
from company_os.application.doctor_service import DoctorService
from company_os.application.task_service import TaskService
from company_os.cli.render import render_status
from company_os.cli.render_activity import render_activity
from company_os.cli.render_workflow import render_workflow
from company_os.cli.render_doctor import render_doctor
from company_os.cli.render_tasks import render_tasks
from company_os.cli.shell import run_shell
from company_os.cli.tui import run_tui


app = typer.Typer(
    no_args_is_help=False,
    invoke_without_command=True,
    help="AI Company OS command-line interface",
)


@app.callback()
def root(ctx: typer.Context) -> None:
    """AI Company OS CLI."""

    if ctx.invoked_subcommand is None:
        run_tui()



@app.command("shell")
def shell_command() -> None:
    """Open the interactive command shell."""
    run_shell()
@app.command("use")
def use_project(
    project: Path = typer.Argument(
        ...,
        help="AI Company OS repository path",
    ),
) -> None:
    """Set the default AI Company OS project."""

    try:
        snapshot = StatusService().get_status(project)
    except FileNotFoundError as exc:
        typer.echo(
            f"ERROR: {exc}",
            err=True,
        )
        raise typer.Exit(code=2)

    root = Path(snapshot.project.root)

    ConfigService().set_current_project(root)

    typer.echo(
        f"Current project: {root}"
    )


@app.command("current")
def current_project() -> None:
    """Show the configured project."""

    project = ConfigService().get_current_project()

    if project is None:
        typer.echo("No project configured.")
        raise typer.Exit(code=1)

    typer.echo(str(project))


@app.command()
def status(
    project: Path | None = typer.Option(
        None,
        "--project",
        "-p",
        help="Override configured AI Company OS repository",
    ),
    as_json: bool = typer.Option(
        False,
        "--json",
        help="Emit machine-readable JSON",
    ),
) -> None:
    """Show the current AI Company OS project snapshot."""

    project = ConfigService().resolve_project(project)

    try:
        snapshot = StatusService().get_status(project)
    except FileNotFoundError as exc:
        typer.echo(
            f"ERROR: {exc}",
            err=True,
        )
        raise typer.Exit(code=2)

    if as_json:
        typer.echo(
            json.dumps(
                snapshot.model_dump(mode="json"),
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        render_status(snapshot)






@app.command("handoffs")
def handoffs_command(
    project: Path | None = typer.Option(
        None,
        "--project",
        "-p",
    ),
    as_json: bool = typer.Option(
        False,
        "--json",
    ),
) -> None:
    """Show declared and observed agent handoffs."""

    project = ConfigService().resolve_project(
        project
    )

    records = (
        HandoffService()
        .get_handoffs(project)
    )

    if as_json:
        typer.echo(
            json.dumps(
                [
                    record.to_dict()
                    for record in records
                ],
                indent=2,
                ensure_ascii=False,
            )
        )
        return

    from rich.console import Console
    from rich.table import Table

    console = Console()

    table = Table(
        title="AI COMPANY OS HANDOFFS"
    )

    table.add_column("Time")
    table.add_column("Task")
    table.add_column("Kind")
    table.add_column("From")
    table.add_column("To")
    table.add_column("State")

    for record in records:
        table.add_row(
            (
                record.timestamp.isoformat(
                    timespec="seconds"
                )
                if record.timestamp
                else "-"
            ),
            record.task_id,
            record.kind,
            record.from_actor or "-",
            record.to_actor,
            "STALE" if record.stale else "OK",
        )

    console.print(table)


@app.command("runtime")
def runtime_command(
    project: Path | None = typer.Option(
        None,
        "--project",
        "-p",
    ),
    as_json: bool = typer.Option(
        False,
        "--json",
    ),
) -> None:
    """Inspect the available Codex runtime source."""

    project = ConfigService().resolve_project(
        project
    )

    runtime = (
        RuntimeService()
        .get_runtime_source(project)
    )

    if as_json:
        typer.echo(
            json.dumps(
                runtime.to_dict(),
                indent=2,
                ensure_ascii=False,
            )
        )
        return

    from rich.console import Console
    from rich.table import Table

    console = Console()

    table = Table(
        title="AI COMPANY OS RUNTIME"
    )

    table.add_column("Property")
    table.add_column("Value")

    table.add_row(
        "Source",
        runtime.path,
    )

    table.add_row(
        "Available",
        str(runtime.available),
    )

    table.add_row(
        "Events",
        str(runtime.event_count),
    )

    table.add_row(
        "Parsed",
        str(runtime.parsed_event_count),
    )

    table.add_row(
        "Malformed",
        str(runtime.malformed_event_count),
    )

    table.add_row(
        "Authoritative live state",
        str(runtime.authoritative_live_state),
    )

    table.add_row(
        "Status",
        runtime.message,
    )

    console.print(table)

@app.command("activity")
def activity_command(
    project: Path | None = typer.Option(
        None,
        "--project",
        "-p",
    ),
    limit: int = typer.Option(
        50,
        "--limit",
        "-n",
        min=1,
    ),
    as_json: bool = typer.Option(
        False,
        "--json",
    ),
) -> None:
    """Show persisted project activity."""

    project = ConfigService().resolve_project(
        project
    )

    try:
        events = (
            ActivityService()
            .get_activity(project)
        )
    except FileNotFoundError as exc:
        typer.echo(
            f"ERROR: {exc}",
            err=True,
        )
        raise typer.Exit(code=2)

    events = events[:limit]

    if as_json:
        typer.echo(
            json.dumps(
                [
                    event.to_dict()
                    for event in events
                ],
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        render_activity(events)

@app.command("workflow")
def workflow_command(
    project: Path | None = typer.Option(
        None,
        "--project",
        "-p",
    ),
    as_json: bool = typer.Option(
        False,
        "--json",
    ),
) -> None:
    """Show task dependencies and execution flow."""

    project = ConfigService().resolve_project(
        project
    )

    try:
        workflow = WorkflowService().get_workflow(
            project
        )
    except FileNotFoundError as exc:
        typer.echo(
            f"ERROR: {exc}",
            err=True,
        )
        raise typer.Exit(code=2)

    if as_json:
        typer.echo(
            json.dumps(
                workflow.to_dict(),
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        render_workflow(
            workflow
        )

@app.command("doctor")
def doctor_command(
    project: Path | None = typer.Option(
        None,
        "--project",
        "-p",
    ),
    as_json: bool = typer.Option(
        False,
        "--json",
    ),
) -> None:
    """Check AI Company OS repository consistency."""

    project = (
        ConfigService()
        .resolve_project(project)
    )

    try:
        findings = (
            DoctorService()
            .get_findings(project)
        )
    except FileNotFoundError as exc:
        typer.echo(
            f"ERROR: {exc}",
            err=True,
        )
        raise typer.Exit(code=2)

    if as_json:
        payload = [
            finding.model_dump(
                mode="json"
            )
            for finding in findings
        ]

        typer.echo(
            json.dumps(
                payload,
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        render_doctor(
            findings
        )

@app.command("tasks")
def tasks_command(
    project: Path | None = typer.Option(
        None,
        "--project",
        "-p",
        help="Override configured AI Company OS repository",
    ),
    status: str | None = typer.Option(
        None,
        "--status",
    ),
    owner: str | None = typer.Option(
        None,
        "--owner",
    ),
    priority: str | None = typer.Option(
        None,
        "--priority",
    ),
    as_json: bool = typer.Option(
        False,
        "--json",
    ),
) -> None:
    """List AI Company OS tasks."""

    project = ConfigService().resolve_project(project)

    try:
        tasks = TaskService().list_tasks(
            project,
            status=status,
            owner=owner,
            priority=priority,
        )
    except (FileNotFoundError, ValueError) as exc:
        typer.echo(
            f"ERROR: {exc}",
            err=True,
        )
        raise typer.Exit(code=2)

    if as_json:
        payload = [
            task.model_dump(mode="json")
            for task in tasks
        ]

        typer.echo(
            json.dumps(
                payload,
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        render_tasks(tasks)


def main() -> None:
    app()


if __name__ == "__main__":
    main()
