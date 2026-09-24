from __future__ import annotations

import subprocess

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
from company_os.application.writable_workspace_service import WritableWorkspaceService
from company_os.application.writable_execution_adapter import WritableExecutionAdapter
from company_os.application.corrective_reactivation_service import CorrectiveReactivationService
from company_os.application.gate_control_service import (
    GateControlService,
)


class PlanControlScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("a", "activate", "Activate"),
        Binding("r", "run_agents", "Analysis agent"),
        Binding("w", "prepare_writable", "Writable workspace"),
        Binding("g", "run_gates", "Run gates"),
        Binding("f", "finalize", "Final approval"),
        Binding("f5", "refresh_tasks", "Refresh"),
        Binding("c", "copy_error", "Copy error"),
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
        self.gates = GateControlService()
        self.writable = WritableWorkspaceService()
        self.writable_runner = WritableExecutionAdapter()
        self.corrective = CorrectiveReactivationService()

        self.busy = False
        self.last_error_text = ""

    def compose(self) -> ComposeResult:
        yield Header()

        with VerticalScroll():
            yield Static(
                id="plan-control-content",
            )

        yield Footer()

    def on_mount(self) -> None:
        self._refresh_view()

    def action_back(self) -> None:
        if self.busy:
            self.notify(
                "An operation is currently running.",
                severity="warning",
            )
            return

        self.app.pop_screen()

    def action_refresh_tasks(self) -> None:
        self._refresh_view()

    def _task_ids(self) -> list[str]:
        return list(
            self.preparation_result.created_task_ids
        )

    def _tasks(self):
        return self.control.get_tasks(
            self.plan_data.project_root,
            self._task_ids(),
        )

    def action_activate(self) -> None:
        if self.busy:
            return

        ready_ids = [
            task.id
            for task in self._tasks()
            if task.status == "READY"
        ]

        if ready_ids:
            result = self.corrective.reactivate(
                self.plan_data.project_root,
                ready_ids,
            )

            if result.task_ids:
                self._refresh_view()

                self.notify(
                    "Reactivated: "
                    + ", ".join(
                        result.task_ids
                    )
                )

                return

        if not any(
            task.status in {
                "BACKLOG",
                "READY",
            }
            for task in self._tasks()
        ):
            self.notify(
                "No BACKLOG/READY tasks from this plan.",
                severity="warning",
            )
            return

        self.busy = True
        self._working(
            "Evaluating scoped readiness and "
            "activating eligible tasks...",
            "ACTIVATE",
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
            result = self.control.activate_ready(
                self.plan_data.project_root,
                self._task_ids(),
            )

            self.app.call_from_thread(
                self._operation_finished,
                (
                    "Activated: "
                    + (
                        ", ".join(
                            result.active_task_ids
                        )
                        or "none"
                    )
                ),
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                "ACTIVATE failed",
                str(exc),
            )

    def action_run_agents(self) -> None:
        if self.busy:
            return

        active = [
            task.id
            for task in self._tasks()
            if task.status == "ACTIVE"
        ]

        if not active:
            self.notify(
                "No ACTIVE tasks from this plan.",
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            "Running ACTIVE agents:\n\n"
            + "\n".join(active)
            + "\n\nProvider: Auto",
            "RUN AGENTS",
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
                    self._task_ids(),
                    provider="Auto",
                )
            )

            self.app.call_from_thread(
                self._operation_finished,
                "Agent batch finished: "
                + ", ".join(
                    result.task_ids
                ),
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                "Agent execution failed",
                str(exc),
            )

    def action_prepare_writable(self) -> None:
        if self.busy:
            return

        active = [
            task.id
            for task in self._tasks()
            if task.status == "ACTIVE"
        ]

        if not active:
            self.notify(
                "No ACTIVE tasks are available "
                "for writable execution.",
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            "Preparing isolated Git worktrees:\n\n"
            + "\n".join(active),
            "WRITABLE WORKSPACES",
        )

        self.prepare_writable_worker()

    @work(
        thread=True,
        exclusive=True,
        group="prepare-writable",
        exit_on_error=False,
    )
    def prepare_writable_worker(self) -> None:
        try:
            result = self.writable.prepare(
                self.plan_data.project_root,
                self._task_ids(),
            )

            lines = []
            blocked_execution = False

            for workspace in result.workspaces:
                state = (
                    "CREATED"
                    if workspace.created
                    else "EXISTING"
                )

                lines.append(
                    f"{workspace.task_id} [{state}]\n"
                    f"Branch: {workspace.branch}\n"
                    f"Path: {workspace.path}"
                )

            if result.runner_available:
                lines.append(
                    "\nWritable runner: AVAILABLE"
                )

                for workspace in result.workspaces:
                    execution = (
                        self.writable_runner.run(
                            self.plan_data.project_root,
                            workspace.task_id,
                            workspace.path,
                            provider="Auto",
                        )
                    )

                    if execution.status == "REVIEW":
                        heading = (
                            "IMPLEMENTATION COMPLETE"
                        )
                    elif execution.status == "BLOCKED":
                        heading = (
                            "WRITABLE EXECUTION BLOCKED"
                        )
                        blocked_execution = True
                    elif execution.status == "ACTIVE":
                        heading = (
                            "EXECUTION FINISHED - "
                            "STATE UNCHANGED"
                        )
                    else:
                        heading = (
                            "WRITABLE EXECUTION FINISHED "
                            f"- {execution.status}"
                        )

                    details = [
                        f"\n{heading}",
                        f"Task: {execution.task_id}",
                        f"Provider: {execution.provider}",
                        f"Model: {execution.model}",
                        f"Status: {execution.status}",
                        f"Outcome: {execution.outcome}",
                        (
                            "Worktree: "
                            f"{execution.workspace_path}"
                        ),
                    ]

                    if execution.summary:
                        details.extend(
                            [
                                "",
                                "Summary:",
                                execution.summary,
                            ]
                        )

                    if execution.blockers:
                        details.extend(
                            [
                                "",
                                "Blocker:",
                                execution.blockers,
                            ]
                        )

                    if execution.recommended_next:
                        details.extend(
                            [
                                "",
                                "Recommended next:",
                                execution.recommended_next,
                            ]
                        )

                    lines.append(
                        "\n".join(details)
                    )

            else:
                lines.append(
                    "\nWritable runner: NOT INSTALLED\n"
                    "The workspace is ready, but the "
                    "engine cannot execute code-writing "
                    "agents yet."
                )

            self.app.call_from_thread(
                self._writable_finished,
                "\n\n".join(lines),
                blocked_execution,
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                "Writable execution failed",
                str(exc),
            )

    def _writable_finished(
        self,
        message: str,
        blocked: bool = False,
    ) -> None:
        self.busy = False

        if blocked:
            self.last_error_text = message
            footer = (
                "\n\nC = Copy details"
                "\nF5 = Return to plan"
            )
        else:
            self.last_error_text = ""
            footer = "\n\nF5 = Return to plan"

        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Panel(
                message + footer,
                title="Writable Execution",
            )
        )

        if blocked:
            self.notify(
                "Writable execution is BLOCKED.",
                severity="warning",
            )
        else:
            self.notify(
                "Writable execution finished."
            )

    def action_run_gates(self) -> None:
        if self.busy:
            return

        gate_tasks = [
            task.id
            for task in self._tasks()
            if task.status in {
                "REVIEW",
                "QA",
                "SECURITY",
            }
        ]

        if not gate_tasks:
            self.notify(
                "No pending gate tasks.",
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            "Running independent gates:\n\n"
            + "\n".join(gate_tasks)
            + "\n\nReview -> QA -> Security",
            "QUALITY GATES",
        )

        self.gates_worker()

    @work(
        thread=True,
        exclusive=True,
        group="run-gates",
        exit_on_error=False,
    )
    def gates_worker(self) -> None:
        try:
            result = (
                self.gates
                .run_pending_gates_scoped(
                    self.plan_data.project_root,
                    self._task_ids(),
                    provider="Auto",
                )
            )

            self.app.call_from_thread(
                self._operation_finished,
                "Gate batch finished: "
                + (
                    ", ".join(
                        result.task_ids
                    )
                    or "no changes"
                ),
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                "Gate execution failed",
                str(exc),
            )

    def action_finalize(self) -> None:
        if self.busy:
            return

        finalizable = (
            self.gates
            .finalizable_task_ids(
                self.plan_data.project_root,
                self._task_ids(),
            )
        )

        if not finalizable:
            self.notify(
                "No tasks are ready for final approval.",
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            "Recording final CEO approval for:\n\n"
            + "\n".join(finalizable)
            + "\n\nThis will move these tasks to DONE.",
            "FINAL APPROVAL",
        )

        self.finalize_worker()

    @work(
        thread=True,
        exclusive=True,
        group="finalize-plan",
        exit_on_error=False,
    )
    def finalize_worker(self) -> None:
        try:
            result = (
                self.gates
                .finalize_scoped(
                    self.plan_data.project_root,
                    self._task_ids(),
                )
            )

            self.app.call_from_thread(
                self._operation_finished,
                "DONE: "
                + ", ".join(
                    result.done_task_ids
                ),
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                "Final approval failed",
                str(exc),
            )

    def _working(
        self,
        message: str,
        title: str,
    ) -> None:
        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Panel(
                message,
                title=title,
            )
        )

    def _operation_finished(
        self,
        message: str,
    ) -> None:
        self.busy = False
        self._refresh_view()
        self.notify(message)

    def _operation_failed(
        self,
        title: str,
        message: str,
    ) -> None:
        self.busy = False

        self.last_error_text = (
            f"{title}\n\n{message}"
        )

        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Group(
                Panel(
                    message,
                    title=title,
                ),
                Text(""),
                Panel(
                    "C = Copy error\n"
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

    def action_copy_error(self) -> None:
        if not self.last_error_text:
            self.notify(
                "There is no error to copy.",
                severity="warning",
            )
            return

        try:
            copy_method = getattr(
                self.app,
                "copy_to_clipboard",
                None,
            )

            if callable(copy_method):
                copy_method(
                    self.last_error_text
                )

            else:
                subprocess.run(
                    ["clip.exe"],
                    input=self.last_error_text,
                    text=True,
                    check=True,
                )

            self.notify(
                "Error copied to clipboard."
            )

        except Exception as exc:
            try:
                subprocess.run(
                    ["clip.exe"],
                    input=self.last_error_text,
                    text=True,
                    check=True,
                )

                self.notify(
                    "Error copied to clipboard."
                )

            except Exception:
                self.notify(
                    f"Could not copy error: {exc}",
                    severity="error",
                )

    def _refresh_view(self) -> None:
        tasks = self._tasks()

        finalizable = set(
            self.gates.finalizable_task_ids(
                self.plan_data.project_root,
                self._task_ids(),
            )
        )

        table = Table(
            title="Plan Tasks",
            show_lines=True,
        )

        table.add_column("ID")
        table.add_column("Status")
        table.add_column("Owner")
        table.add_column("Task")

        for task in tasks:
            status = task.status

            if task.id in finalizable:
                status += " / FINAL READY"

            table.add_row(
                task.id,
                status,
                task.owner,
                task.title,
            )

        counts: dict[str, int] = {}

        for task in tasks:
            counts[task.status] = (
                counts.get(
                    task.status,
                    0,
                )
                + 1
            )

        summary = Table(
            show_header=False,
            box=None,
        )

        summary.add_column("Status")
        summary.add_column("Count")

        for status in (
            "BACKLOG",
            "READY",
            "ACTIVE",
            "REVIEW",
            "QA",
            "SECURITY",
            "BLOCKED",
            "DONE",
        ):
            summary.add_row(
                status,
                str(
                    counts.get(
                        status,
                        0,
                    )
                ),
            )

        controls = []

        if any(
            task.status in {
                "BACKLOG",
                "READY",
            }
            for task in tasks
        ):
            controls.append(
                "A = Activate eligible wave"
            )

        if any(
            task.status == "ACTIVE"
            for task in tasks
        ):
            controls.append(
                "R = Run analysis-only agent"
            )
            controls.append(
                "W = Run writable implementation"
            )

        pending_gates = False

        for task in tasks:
            if task.status in {
                "REVIEW",
                "QA",
            }:
                pending_gates = True

            elif (
                task.status == "SECURITY"
                and task.id not in finalizable
            ):
                pending_gates = True

        if pending_gates:
            controls.append(
                "G = Run Review/QA/Security gates"
            )

        if finalizable:
            controls.append(
                "F = Final CEO approval -> DONE"
            )

        controls.extend(
            [
                "F5 = Refresh",
                "Esc = Back",
            ]
        )

        work_request = (
            ", ".join(
                self.preparation_result
                .work_request_ids
            )
            or "unknown"
        )

        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Group(
                Panel(
                    f"Project: "
                    f"{self.plan_data.project_name}\n"
                    f"Work Request: {work_request}",
                    title="Plan Control",
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
                    "Lifecycle:\n\n"
                    "BACKLOG -> READY -> ACTIVE\n"
                    "ACTIVE -> REVIEW\n"
                    "REVIEW -> QA\n"
                    "QA -> SECURITY\n"
                    "SECURITY -> DONE\n\n"
                    "When a wave reaches DONE, press A "
                    "again to activate newly eligible "
                    "dependent tasks.",
                    title="Workflow",
                ),
            )
        )
