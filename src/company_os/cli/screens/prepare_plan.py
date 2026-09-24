from __future__ import annotations

from rich.console import Group
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import VerticalScroll
from textual.screen import Screen
from textual.widgets import (
    Footer,
    Header,
    Static,
)

from company_os.application.agent_control_service import (
    AgentControlService,
)
from company_os.cli.screens.plan_control import PlanControlScreen

from company_os.application.execution_service import (
    ExecutionService,
)


class PreparedPlanScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("a", "activate", "Activate ready"),
        Binding("r", "run_agents", "Run agents"),
        Binding("f5", "refresh_tasks", "Refresh"),
    ]

    def __init__(
        self,
        plan,
        preparation_result,
    ) -> None:
        super().__init__()

        self.plan_data = plan
        self.preparation_result = preparation_result
        self.control = AgentControlService()
        self.busy = False

    def compose(self) -> ComposeResult:
        yield Header()

        with VerticalScroll():
            yield Static(
                id="prepared-content",
            )

        yield Footer()

    def on_mount(self) -> None:
        self._refresh_view()

    def action_back(self) -> None:
        if self.busy:
            self.notify(
                "An AI Company OS operation is running.",
                severity="warning",
            )
            return

        self.app.pop_screen()

    def action_refresh_tasks(self) -> None:
        self._refresh_view()

    def action_activate(self) -> None:
        if self.busy:
            return

        tasks = self._tasks()

        if any(
            task.status == "ACTIVE"
            for task in tasks
        ):
            self.notify(
                "This plan already has ACTIVE tasks.",
                severity="warning",
            )
            return

        self.busy = True

        self.query_one(
            "#prepared-content",
            Static,
        ).update(
            Panel(
                "Evaluating readiness and preparing "
                "dispatch packets...",
                title="ACTIVATE",
            )
        )

        self.activate_worker()

    @work(
        thread=True,
        exclusive=True,
        group="activate-plan",
        exit_on_error=False,
    )
    def activate_worker(self) -> None:
        try:
            result = (
                self.control
                .activate_ready(
                    self.plan_data.project_root,
                    self.preparation_result.created_task_ids,
                )
            )

            self.app.call_from_thread(
                self._activation_finished,
                result,
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                "ACTIVATE failed",
                str(exc),
            )

    def _activation_finished(
        self,
        result,
    ) -> None:
        self.busy = False
        self._refresh_view()

        if result.active_task_ids:
            self.notify(
                "Ready tasks activated: "
                + ", ".join(
                    result.active_task_ids
                )
            )
        else:
            self.notify(
                "No tasks became ACTIVE. "
                "Check dependencies.",
                severity="warning",
            )

    def action_run_agents(self) -> None:
        if self.busy:
            return

        tasks = self._tasks()

        active = [
            task.id
            for task in tasks
            if task.status == "ACTIVE"
        ]

        if not active:
            self.notify(
                "No ACTIVE tasks from this plan.",
                severity="warning",
            )
            return

        self.busy = True

        self.query_one(
            "#prepared-content",
            Static,
        ).update(
            Panel(
                "Running ACTIVE agents...\n\n"
                + "\n".join(active)
                + "\n\n"
                "Provider: Auto\n"
                "This may use Codex, OpenRouter or Gemini "
                "according to the project provider router.",
                title="RUN AGENTS",
            )
        )

        self.run_agents_worker()

    @work(
        thread=True,
        exclusive=True,
        group="run-agents",
        exit_on_error=False,
    )
    def run_agents_worker(self) -> None:
        try:
            result = (
                self.control
                .run_active_agents(
                    self.plan_data.project_root,
                    self.preparation_result.created_task_ids,
                    provider="Auto",
                )
            )

            self.app.call_from_thread(
                self._agents_finished,
                result,
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                "Agent execution failed",
                str(exc),
            )

    def _agents_finished(
        self,
        result,
    ) -> None:
        self.busy = False
        self._refresh_view()

        self.notify(
            "Agent batch finished: "
            + ", ".join(
                result.task_ids
            )
        )

    def _operation_failed(
        self,
        title: str,
        message: str,
    ) -> None:
        self.busy = False

        self.query_one(
            "#prepared-content",
            Static,
        ).update(
            Group(
                Panel(
                    message,
                    title=title,
                ),
                Text(""),
                Panel(
                    "No further automatic action was taken.\n"
                    "F5 = Refresh\n"
                    "Esc = Back",
                    title="Recovery",
                ),
            )
        )

        self.notify(
            title,
            severity="error",
        )

    def _tasks(self):
        return (
            self.control
            .get_tasks(
                self.plan_data.project_root,
                self.preparation_result.created_task_ids,
            )
        )

    def _refresh_view(self) -> None:
        tasks = self._tasks()

        table = Table(
            title="Prepared Plan Tasks",
            show_lines=True,
        )

        table.add_column("ID")
        table.add_column("Status")
        table.add_column("Owner")
        table.add_column("Task")

        for task in tasks:
            table.add_row(
                task.id,
                task.status,
                task.owner,
                task.title,
            )

        backlog = sum(
            task.status == "BACKLOG"
            for task in tasks
        )

        ready = sum(
            task.status == "READY"
            for task in tasks
        )

        active = sum(
            task.status == "ACTIVE"
            for task in tasks
        )

        review = sum(
            task.status == "REVIEW"
            for task in tasks
        )

        blocked = sum(
            task.status == "BLOCKED"
            for task in tasks
        )

        done = sum(
            task.status == "DONE"
            for task in tasks
        )

        summary = Table(
            show_header=False,
            box=None,
        )

        summary.add_column("State")
        summary.add_column("Count")

        summary.add_row(
            "BACKLOG",
            str(backlog),
        )
        summary.add_row(
            "READY",
            str(ready),
        )
        summary.add_row(
            "ACTIVE",
            str(active),
        )
        summary.add_row(
            "REVIEW",
            str(review),
        )
        summary.add_row(
            "BLOCKED",
            str(blocked),
        )
        summary.add_row(
            "DONE",
            str(done),
        )

        controls = []

        if backlog:
            controls.append(
                "A = Evaluate readiness + activate eligible tasks"
            )

        if active:
            controls.append(
                "R = Run ACTIVE agents"
            )

        if review:
            controls.append(
                "Tasks are waiting for independent review gates."
            )

        if blocked:
            controls.append(
                "One or more agent tasks reported BLOCKED."
            )

        controls.append(
            "F5 = Refresh"
        )

        controls.append(
            "Esc = Back"
        )

        self.query_one(
            "#prepared-content",
            Static,
        ).update(
            Group(
                Panel(
                    f"Project: {self.plan_data.project_name}\n"
                    f"Work Request: "
                    + (
                        ", ".join(
                            self.preparation_result.work_request_ids
                        )
                        or "unknown"
                    ),
                    title="Prepared",
                ),
                Text(""),
                summary,
                Text(""),
                table,
                Text(""),
                Panel(
                    "\n".join(controls),
                    title="Controls",
                ),
                Text(""),
                Panel(
                    "Safety model:\n\n"
                    "PREPARE creates planning artifacts.\n"
                    "ACTIVATE moves eligible tasks through "
                    "READY to ACTIVE.\n"
                    "RUN invokes the provider runtime.\n\n"
                    "The current agent runner is analysis/"
                    "planning only and does not modify "
                    "production code.",
                    title="Execution boundary",
                ),
            )
        )


class PreparePlanScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("y", "prepare", "Prepare"),
    ]

    def __init__(self, plan) -> None:
        super().__init__()

        self.plan_data = plan
        self.execution = ExecutionService()
        self.busy = False

    def compose(self) -> ComposeResult:
        yield Header()

        with VerticalScroll():
            yield Static(
                self._render_confirmation(),
                id="prepare-content",
            )

        yield Footer()

    def action_back(self) -> None:
        if self.busy:
            return

        self.app.pop_screen()

    def _render_confirmation(self):
        plan = self.plan_data

        compatible, reason = (
            self.execution
            .check_compatibility(plan)
        )

        table = Table(
            show_header=False,
            box=None,
        )

        table.add_column("Property")
        table.add_column("Value")

        table.add_row(
            "Project",
            plan.project_name,
        )

        table.add_row(
            "Type",
            plan.engine_type,
        )

        table.add_row(
            "Strategy",
            plan.strategy,
        )

        table.add_row(
            "Tasks previewed",
            str(len(plan.tasks)),
        )

        table.add_row(
            "Engine compatible",
            "YES" if compatible else "NO",
        )

        controls = (
            "Y = Confirm PREPARE\n"
            "Esc = Cancel"
            if compatible
            else (
                "This plan cannot currently be "
                "materialized without changing "
                "its meaning.\n\nEsc = Back"
            )
        )

        return Group(
            Panel(
                "PREPARE writes planning artifacts and "
                "BACKLOG tasks to the selected repository.\n\n"
                "It does NOT start agents.\n"
                "It does NOT activate tasks.\n"
                "It does NOT run Codex.",
                title="Safety boundary",
            ),
            Text(""),
            table,
            Text(""),
            Panel(
                reason,
                title="Engine compatibility",
            ),
            Text(""),
            Panel(
                controls,
                title="Confirmation",
            ),
        )

    def action_prepare(self) -> None:
        if self.busy:
            return

        compatible, reason = (
            self.execution
            .check_compatibility(
                self.plan_data
            )
        )

        if not compatible:
            self.notify(
                reason,
                severity="error",
            )
            return

        self.busy = True

        self.query_one(
            "#prepare-content",
            Static,
        ).update(
            Panel(
                "Preparing plan...",
                title="AI Company OS",
            )
        )

        self.prepare_worker()

    @work(
        thread=True,
        exclusive=True,
        group="prepare-plan",
        exit_on_error=False,
    )
    def prepare_worker(self) -> None:
        try:
            result = (
                self.execution
                .prepare(
                    self.plan_data
                )
            )

            self.app.call_from_thread(
                self._prepare_finished,
                result,
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._prepare_failed,
                str(exc),
            )

    def _prepare_finished(
        self,
        result,
    ) -> None:
        self.busy = False

        self.app.push_screen(
            PlanControlScreen(
                self.plan_data,
                result,
            )
        )

        self.notify(
            "Plan prepared successfully."
        )

    def _prepare_failed(
        self,
        message: str,
    ) -> None:
        self.busy = False

        self.query_one(
            "#prepare-content",
            Static,
        ).update(
            Panel(
                message,
                title="PREPARE failed",
            )
        )

        self.notify(
            "Plan preparation failed.",
            severity="error",
        )
