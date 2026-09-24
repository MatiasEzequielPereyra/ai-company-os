from __future__ import annotations

import json
import shlex
from pathlib import Path

from prompt_toolkit import PromptSession
from prompt_toolkit.completion import WordCompleter
from prompt_toolkit.history import FileHistory
from rich.console import Console
from rich.panel import Panel

from company_os.application.config_service import ConfigService
from company_os.application.status_service import StatusService
from company_os.application.task_service import TaskService
from company_os.cli.render import render_status
from company_os.cli.render_tasks import render_tasks


console = Console()


COMMANDS = [
    "status",
    "tasks",
    "use",
    "project",
    "help",
    "clear",
    "exit",
    "quit",
]


def _show_help() -> None:
    console.print(
        """
[bold]AI Company OS commands[/bold]

  status                   Show project status
  tasks                    List tasks
  tasks --status ACTIVE    Filter by status
  tasks --owner pm         Filter by owner
  tasks --priority P1      Filter by priority
  tasks --json             JSON output

  use "C:\\path\\project"   Change current project
  project                  Show current project

  clear                    Clear terminal
  help                     Show this help
  exit                     Exit AI Company OS
"""
    )


def _parse_tasks_options(tokens: list[str]) -> dict:
    result = {
        "status": None,
        "owner": None,
        "priority": None,
        "json": False,
    }

    index = 0

    while index < len(tokens):
        token = tokens[index]

        if token == "--json":
            result["json"] = True
            index += 1
            continue

        mapping = {
            "--status": "status",
            "--owner": "owner",
            "--priority": "priority",
        }

        if token in mapping:
            if index + 1 >= len(tokens):
                raise ValueError(
                    f"Missing value after {token}"
                )

            result[mapping[token]] = tokens[index + 1]
            index += 2
            continue

        raise ValueError(
            f"Unknown tasks option: {token}"
        )

    return result


def run_shell() -> None:
    config = ConfigService()

    session = PromptSession(
        history=FileHistory(str(config.history_path)),
        completer=WordCompleter(
            COMMANDS,
            ignore_case=True,
        ),
        complete_while_typing=False,
    )

    current = config.get_current_project()

    console.print(
        Panel.fit(
            "[bold]AI COMPANY OS[/bold]\n"
            + (
                f"Project: {current}"
                if current
                else "No project selected"
            )
            + "\n\nType [bold]help[/bold] for commands.",
            title="Interactive Client",
        )
    )

    while True:
        current = config.get_current_project()

        label = (
            current.name
            if current is not None
            else "no-project"
        )

        try:
            raw = session.prompt(
                f"{label} > "
            ).strip()
        except KeyboardInterrupt:
            continue
        except EOFError:
            console.print()
            break

        if not raw:
            continue

        try:
            tokens = shlex.split(
                raw,
                posix=False,
            )
        except ValueError as exc:
            console.print(
                f"[red]ERROR:[/red] {exc}"
            )
            continue

        command = tokens[0].lower()
        args = tokens[1:]

        try:
            if command in {"exit", "quit"}:
                break

            if command == "help":
                _show_help()
                continue

            if command == "clear":
                console.clear()
                continue

            if command == "project":
                project = config.get_current_project()

                if project:
                    console.print(
                        f"[bold]Current project:[/bold] {project}"
                    )
                else:
                    console.print(
                        "[yellow]No project selected.[/yellow]"
                    )

                continue

            if command == "use":
                if not args:
                    console.print(
                        '[yellow]Usage: use "C:\\path\\project"[/yellow]'
                    )
                    continue

                raw_path = " ".join(args).strip('"')
                requested = Path(raw_path)

                snapshot = StatusService().get_status(
                    requested
                )

                root = Path(snapshot.project.root)
                config.set_current_project(root)

                console.print(
                    f"[green]Project selected:[/green] {root}"
                )
                continue

            project = config.resolve_project()

            if command == "status":
                snapshot = StatusService().get_status(
                    project
                )

                if "--json" in args:
                    console.print_json(
                        json.dumps(
                            snapshot.model_dump(
                                mode="json"
                            ),
                            ensure_ascii=False,
                        )
                    )
                else:
                    render_status(snapshot)

                continue

            if command == "tasks":
                options = _parse_tasks_options(args)

                tasks = TaskService().list_tasks(
                    project,
                    status=options["status"],
                    owner=options["owner"],
                    priority=options["priority"],
                )

                if options["json"]:
                    payload = [
                        task.model_dump(mode="json")
                        for task in tasks
                    ]

                    console.print_json(
                        json.dumps(
                            payload,
                            ensure_ascii=False,
                        )
                    )
                else:
                    render_tasks(tasks)

                continue

            console.print(
                f"[yellow]Unknown command:[/yellow] {command}"
            )
            console.print(
                "Type [bold]help[/bold] to see available commands."
            )

        except (FileNotFoundError, ValueError) as exc:
            console.print(
                f"[red]ERROR:[/red] {exc}"
            )
        except Exception as exc:
            console.print(
                f"[red]Unexpected error:[/red] {exc}"
            )
