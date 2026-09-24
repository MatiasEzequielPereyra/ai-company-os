from __future__ import annotations

from pathlib import Path

from rich.console import Group
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import VerticalScroll
from textual.screen import Screen
from textual.widgets import (
    Footer,
    Header,
    Input,
    Label,
    ListItem,
    ListView,
    Static,
)

from company_os.application.ceo_planning_service import (
    CEOPlanningService,
)
from company_os.cli.screens.prepare_plan import PreparePlanScreen

from company_os.application.command_service import (
    CommandService,
)


class PlanPreviewScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("r", "run_plan", "Run plan"),
    ]

    def __init__(
        self,
        proposal,
        option,
    ) -> None:
        super().__init__()

        self.proposal_data = proposal
        self.option_data = option
        self.plan_data = None

    def compose(self) -> ComposeResult:
        yield Header()

        with VerticalScroll():
            yield Static(
                "Building CEO plan...",
                id="plan-preview",
            )

        yield Footer()

    def on_mount(self) -> None:
        try:
            project = Path(
                self.app.project
            )

            self.plan_data = (
                CEOPlanningService()
                .build_plan(
                    project,
                    self.proposal_data,
                    self.option_data,
                )
            )

            self.query_one(
                "#plan-preview",
                Static,
            ).update(
                self._render_plan()
            )

        except Exception as exc:
            self.query_one(
                "#plan-preview",
                Static,
            ).update(
                Panel(
                    str(exc),
                    title="Planning error",
                )
            )

    def action_back(self) -> None:
        self.app.pop_screen()

    def action_run_plan(self) -> None:
        if self.plan_data is None:
            return

        self.app.push_screen(
            PreparePlanScreen(
                self.plan_data
            )
        )

    def _render_plan(self):
        plan = self.plan_data

        summary = Table(
            show_header=False,
            box=None,
            padding=(0, 2),
        )

        summary.add_column(style="bold")
        summary.add_column()

        summary.add_row(
            "Project",
            plan.project_name,
        )

        summary.add_row(
            "Intent",
            plan.intent,
        )

        summary.add_row(
            "Engine type",
            plan.engine_type,
        )

        summary.add_row(
            "Strategy",
            plan.strategy,
        )

        summary.add_row(
            "Existing open tasks",
            str(plan.existing_open_tasks),
        )

        summary.add_row(
            "Engine ready",
            "YES" if plan.engine_ready else "NO",
        )

        facts = "\n".join(
            f"- {fact}"
            for fact in plan.project_facts
        )

        task_table = Table(
            title="Proposed Tasks",
            show_lines=True,
        )

        task_table.add_column("Key")
        task_table.add_column("Wave")
        task_table.add_column("Owner")
        task_table.add_column("Task")
        task_table.add_column("Depends on")

        for task in plan.tasks:
            task_table.add_row(
                task.key,
                str(task.wave),
                task.owner,
                task.title,
                (
                    ", ".join(
                        task.dependencies
                    )
                    or "-"
                ),
            )

        wave_renderables = []

        for number, wave in enumerate(
            plan.execution_waves,
            start=1,
        ):
            wave_renderables.append(
                Panel(
                    "\n".join(
                        f"{task.key}  {task.owner}  {task.title}"
                        for task in wave
                    ),
                    title=f"Execution Wave {number}",
                )
            )

        renderables = [
            Panel(
                plan.request,
                title="Your request",
            ),
            Text(""),
            summary,
            Text(""),
            Panel(
                facts,
                title="Repository inspection",
            ),
            Text(""),
            task_table,
            Text(""),
        ]

        renderables.extend(
            wave_renderables
        )

        if plan.warnings:
            renderables.extend(
                [
                    Text(""),
                    Panel(
                        "\n".join(
                            f"- {warning}"
                            for warning in plan.warnings
                        ),
                        title="Warnings",
                    ),
                ]
            )

        renderables.extend(
            [
                Text(""),
                Panel(
                    "No files have been created.\n"
                    "No task status has changed.\n"
                    "No agent has been executed.\n\n"
                    "R = Run Plan (currently disabled)\n"
                    "Esc = Back",
                    title="Safe preview",
                ),
            ]
        )

        return Group(
            *renderables
        )


class CommandProposalScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("q", "back", "Back"),
    ]

    def __init__(
        self,
        proposal,
    ) -> None:
        super().__init__()

        self.proposal_data = proposal

    def compose(self) -> ComposeResult:
        yield Header()

        yield Static(
            Panel(
                self.proposal_data.request,
                title=(
                    "Request / "
                    f"{self.proposal_data.intent}"
                ),
            )
        )

        yield Static(
            "Choose how AI Company OS should approach it\n"
            "Up/Down = Select   Enter = Build plan   Esc = Back",
            id="proposal-heading",
        )

        yield ListView(
            *[
                ListItem(
                    Label(
                        (
                            "* "
                            if option.recommended
                            else "  "
                        )
                        + option.title
                        + " | "
                        + ", ".join(
                            option.agents
                        )
                    )
                )
                for option
                in self.proposal_data.options
            ],
            id="proposal-list",
        )

        yield Footer()

    def on_mount(self) -> None:
        proposal_list = self.query_one(
            "#proposal-list",
            ListView,
        )

        recommended_index = 0

        for index, option in enumerate(
            self.proposal_data.options
        ):
            if option.recommended:
                recommended_index = index
                break

        proposal_list.index = (
            recommended_index
        )

        proposal_list.focus()

    def action_back(self) -> None:
        self.app.pop_screen()

    def on_list_view_selected(
        self,
        event: ListView.Selected,
    ) -> None:
        index = event.list_view.index

        if index is None:
            return

        options = (
            self.proposal_data.options
        )

        if (
            index < 0
            or index >= len(options)
        ):
            return

        self.app.push_screen(
            PlanPreviewScreen(
                self.proposal_data,
                options[index],
            )
        )


class CommandCenterScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()

        project_name = Path(
            self.app.project
        ).name

        yield Static(
            Panel(
                f"Current project: {project_name}\n\n"
                "Tell the CEO what result you want. "
                "The CEO will propose an approach and "
                "build a safe execution preview before "
                "anything is written to the repository.",
                title="Command Center",
            )
        )

        yield Static(
            Panel(
                "Examples:\n\n"
                "- Audit this project for production\n"
                "- Fix the authentication bug\n"
                "- Add payments\n"
                "- Prepare the application for release",
                title="Examples",
            )
        )

        yield Input(
            placeholder=(
                "Tell the CEO what you want to achieve..."
            ),
            id="command-input",
        )

        yield Footer()

    def on_mount(self) -> None:
        self.query_one(
            "#command-input",
            Input,
        ).focus()

    def action_back(self) -> None:
        self.app.pop_screen()

    def on_input_submitted(
        self,
        event: Input.Submitted,
    ) -> None:
        if event.input.id != "command-input":
            return

        request = event.value.strip()

        if not request:
            return

        try:
            proposal = (
                CommandService()
                .propose(request)
            )

            event.input.value = ""

            self.app.push_screen(
                CommandProposalScreen(
                    proposal
                )
            )

        except Exception as exc:
            self.notify(
                str(exc),
                severity="error",
            )