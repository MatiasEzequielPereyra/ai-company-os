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
from company_os.application.task_result_service import (
    TaskResultService,
)
from company_os.application.work_request_service import (
    WorkRequestService,
)
from company_os.application.writable_workspace_service import WritableWorkspaceService
from company_os.application.writable_execution_adapter import WritableExecutionAdapter
from company_os.application.corrective_reactivation_service import CorrectiveReactivationService
from company_os.cli.i18n import ui_text
from company_os.application.gate_control_service import (
    GateControlService,
)


def _t(widget, key: str) -> str:
    return ui_text(
        getattr(
            widget.app,
            "language",
            "es",
        ),
        key,
    )


class PlanControlScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Atras / Back"),
        Binding("a", "activate", "Activar / Activate"),
        Binding("r", "run_agents", "Analisis / Analysis"),
        Binding("w", "prepare_writable", "Writable"),
        Binding("g", "run_gates", "Gates"),
        Binding("f", "finalize", "Aprobacion / Approval"),
        Binding("f5", "refresh_tasks", "Actualizar / Refresh"),
        Binding("c", "copy_error", "Copiar / Copy"),
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
        self.task_results = TaskResultService()
        self.work_requests = WorkRequestService()
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

    def refresh_language(self) -> None:
        if not self.busy:
            self._refresh_view()

    def action_back(self) -> None:
        if self.busy:
            self.notify(
                _t(self, "pc_busy"),
                severity="warning",
            )
            return

        self.app.pop_screen()

    def action_refresh_tasks(self) -> None:
        self._refresh_view()

    def _task_ids(self) -> list[str]:
        task_ids = set(
            self.preparation_result.created_task_ids
        )

        request_ids = (
            getattr(
                self.preparation_result,
                "work_request_ids",
                [],
            )
            or []
        )

        for request_id in request_ids:
            try:
                reopened = (
                    self.work_requests.reopen(
                        self.plan_data.project_root,
                        request_id,
                    )
                )
            except FileNotFoundError:
                continue

            task_ids.update(
                reopened.summary.task_ids
            )

        return sorted(task_ids)

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
                    f"{_t(self, 'pc_reactivated')}: "
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
                _t(self, "pc_no_backlog_ready"),
                severity="warning",
            )
            return

        self.busy = True
        self._working(
            _t(self, "pc_evaluating"),
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
                    f"{_t(self, 'pc_activated')}: "
                    + (
                        ", ".join(
                            result.active_task_ids
                        )
                        or _t(self, "pc_none")
                    )
                ),
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                _t(self, "pc_activate_failed"),
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
                _t(self, "pc_no_active_analysis"),
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            _t(self, "pc_running_agents")
            + ":\n\n"
            + "\n".join(active)
            + "\n\nProvider: Auto",
            _t(self, "pc_run_agents_title"),
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
                f"{_t(self, 'pc_agent_batch_finished')}: "
                + ", ".join(
                    result.task_ids
                ),
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                _t(self, "pc_agent_execution_failed"),
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
                _t(self, "pc_no_active_writable"),
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            _t(self, "pc_preparing_worktrees")
            + ":\n\n"
            + "\n".join(active),
            _t(self, "pc_writable_workspaces"),
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
                    "\n"
                    + _t(
                        self,
                        "pc_writable_runner_available",
                    )
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
                            _t(self, "pc_implementation_complete")
                        )
                    elif execution.status == "BLOCKED":
                        heading = (
                            _t(self, "pc_writable_blocked")
                        )
                        blocked_execution = True
                    elif execution.status == "ACTIVE":
                        heading = (
                            _t(
                                self,
                                "pc_execution_unchanged",
                            )
                        )
                    else:
                        heading = (
                            f"{_t(self, 'pc_writable_finished')} "
                            f"- {execution.status}"
                        )

                    details = [
                        f"\n{heading}",
                        f"Task: {execution.task_id}",
                        f"{_t(self, 'pc_provider')}: {execution.provider}",
                        f"{_t(self, 'pc_model')}: {execution.model}",
                        f"Status: {execution.status}",
                        f"{_t(self, 'pc_outcome')}: {execution.outcome}",
                        (
                            f"{_t(self, 'pc_worktree')}: "
                            f"{execution.workspace_path}"
                        ),
                    ]

                    if execution.summary:
                        details.extend(
                            [
                                "",
                                f"{_t(self, 'pc_summary')}:",
                                execution.summary,
                            ]
                        )

                    if execution.blockers:
                        details.extend(
                            [
                                "",
                                f"{_t(self, 'pc_blocker')}:",
                                execution.blockers,
                            ]
                        )

                    if execution.recommended_next:
                        details.extend(
                            [
                                "",
                                f"{_t(self, 'pc_recommended_next')}:",
                                execution.recommended_next,
                            ]
                        )

                    lines.append(
                        "\n".join(details)
                    )

            else:
                lines.append(
                    "\n"
                    + _t(
                        self,
                        "pc_writable_runner_missing",
                    )
                )

            self.app.call_from_thread(
                self._writable_finished,
                "\n\n".join(lines),
                blocked_execution,
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                _t(self, "pc_writable_failed"),
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
                "\n\n"
                + _t(self, "pc_copy_details")
                + "\n"
                + _t(self, "pc_return_plan")
            )
        else:
            self.last_error_text = ""
            footer = (
                "\n\n"
                + _t(self, "pc_return_plan")
            )

        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Panel(
                message + footer,
                title=_t(self, "pc_writable_title"),
            )
        )

        if blocked:
            self.notify(
                _t(self, "pc_writable_blocked_notify"),
                severity="warning",
            )
        else:
            self.notify(
                _t(self, "pc_writable_finished_notify")
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
                _t(self, "pc_no_gate_tasks"),
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            _t(self, "pc_running_gates")
            + ":\n\n"
            + "\n".join(gate_tasks)
            + "\n\nReview -> QA -> Security",
            _t(self, "pc_quality_gates"),
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
                f"{_t(self, 'pc_gate_batch_finished')}: "
                + (
                    ", ".join(
                        result.task_ids
                    )
                    or _t(self, "pc_no_changes")
                ),
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                _t(self, "pc_gate_failed"),
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
                _t(self, "pc_no_finalizable"),
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            _t(self, "pc_recording_final")
            + ":\n\n"
            + "\n".join(finalizable)
            + "\n\n"
            + _t(self, "pc_final_impact"),
            _t(self, "pc_final_approval"),
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
                _t(self, "pc_final_failed"),
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
                    _t(self, "pc_copy_error")
                    + "\n"
                    + _t(self, "pc_refresh_control")
                    + "\n"
                    + _t(self, "pc_back_control"),
                    title=_t(self, "pc_recovery"),
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
                _t(self, "pc_no_error"),
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
                _t(self, "pc_error_copied")
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
                    _t(self, "pc_error_copied")
                )

            except Exception:
                self.notify(
                    f"{_t(self, 'pc_copy_failed')}: {exc}",
                    severity="error",
                )

    @staticmethod
    def _compact(
        value: str,
        limit: int = 70,
    ) -> str:
        if not value:
            return "-"

        result = " ".join(
            value.split()
        )

        if len(result) <= limit:
            return result

        return (
            result[: limit - 3]
            + "..."
        )

    def _refresh_view(self) -> None:
        tasks = self._tasks()

        finalizable = set(
            self.gates.finalizable_task_ids(
                self.plan_data.project_root,
                self._task_ids(),
            )
        )

        result_details = {}
        result_errors = []

        for task in tasks:
            try:
                result_details[task.id] = (
                    self.task_results.read_latest(
                        self.plan_data.project_root,
                        task.id,
                    )
                )
            except Exception as exc:
                result_errors.append(
                    f"{task.id}: {exc}"
                )

        table = Table(
            title=_t(
                self,
                "pc_plan_tasks",
            ),
            show_lines=True,
        )

        table.add_column("ID")
        table.add_column(
            _t(self, "status")
        )
        table.add_column(
            _t(self, "owner")
        )
        table.add_column(
            _t(self, "task")
        )
        table.add_column(
            _t(
                self,
                "pc_task_next",
            )
        )

        for task in tasks:
            details = result_details.get(
                task.id
            )

            if task.status == "DONE":
                next_action = _t(
                    self,
                    "pc_task_next_done",
                )

            elif task.id in finalizable:
                next_action = _t(
                    self,
                    "pc_task_next_final",
                )

            elif task.status == "BLOCKED":
                if (
                    details is not None
                    and details.recommended_next
                ):
                    next_action = self._compact(
                        details.recommended_next
                    )
                else:
                    next_action = _t(
                        self,
                        "pc_task_next_blocked",
                    )

            elif task.status in {
                "BACKLOG",
                "READY",
            }:
                next_action = _t(
                    self,
                    "pc_task_next_activate",
                )

            elif task.status == "ACTIVE":
                next_action = _t(
                    self,
                    "pc_task_next_execute",
                )

            elif task.status in {
                "REVIEW",
                "QA",
                "SECURITY",
            }:
                next_action = _t(
                    self,
                    "pc_task_next_gates",
                )

            else:
                next_action = "-"

            table.add_row(
                task.id,
                task.status,
                task.owner,
                task.title,
                next_action,
            )

        evidence_table = Table(
            title=_t(
                self,
                "pc_execution_evidence",
            ),
            show_lines=True,
        )

        evidence_table.add_column("ID")
        evidence_table.add_column(
            _t(
                self,
                "pc_provider",
            )
        )
        evidence_table.add_column(
            _t(
                self,
                "pc_model",
            )
        )
        evidence_table.add_column(
            _t(
                self,
                "pc_outcome",
            )
        )
        evidence_table.add_column(
            _t(
                self,
                "pc_task_blocker",
            )
        )

        evidence_count = 0
        result_notes = []

        for task in tasks:
            details = result_details.get(
                task.id
            )

            if details is None:
                continue

            has_evidence = any(
                (
                    details.result_path,
                    details.evidence_path,
                    details.provider,
                    details.model,
                    details.outcome,
                    details.summary,
                    details.blockers,
                    details.recommended_next,
                )
            )

            if not has_evidence:
                continue

            evidence_count += 1

            evidence_table.add_row(
                task.id,
                details.provider or "-",
                details.model or "-",
                details.outcome or "-",
                (
                    _t(self, "yes")
                    if details.blockers
                    else _t(self, "no")
                ),
            )

            note_lines = []

            if details.summary:
                note_lines.extend(
                    [
                        f"{task.id} - "
                        f"{_t(self, 'pc_summary')}:",
                        details.summary,
                    ]
                )

            if details.blockers:
                if note_lines:
                    note_lines.append("")

                note_lines.extend(
                    [
                        f"{_t(self, 'pc_blocker')}:",
                        details.blockers,
                    ]
                )

            if details.recommended_next:
                if note_lines:
                    note_lines.append("")

                note_lines.extend(
                    [
                        f"{_t(self, 'pc_recommended_next')}:",
                        details.recommended_next,
                    ]
                )

            if note_lines:
                result_notes.append(
                    "\n".join(note_lines)
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

        summary.add_column(
            _t(self, "status")
        )
        summary.add_column(
            _t(
                self,
                "pc_count",
            )
        )

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
                _t(
                    self,
                    "pc_activate_control",
                )
            )

        if any(
            task.status == "ACTIVE"
            for task in tasks
        ):
            controls.append(
                _t(
                    self,
                    "pc_analysis_control",
                )
            )
            controls.append(
                _t(
                    self,
                    "pc_writable_control",
                )
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
                _t(
                    self,
                    "pc_gates_control",
                )
            )

        if finalizable:
            controls.append(
                _t(
                    self,
                    "pc_final_control",
                )
            )

        controls.extend(
            [
                _t(
                    self,
                    "pc_refresh_control",
                ),
                _t(
                    self,
                    "pc_back_control",
                ),
            ]
        )

        statuses = {
            task.status
            for task in tasks
        }

        if "BLOCKED" in statuses:
            next_action = _t(
                self,
                "pc_next_blocked",
            )

        elif finalizable:
            next_action = _t(
                self,
                "pc_next_final",
            )

        elif pending_gates:
            next_action = _t(
                self,
                "pc_next_gates",
            )

        elif "ACTIVE" in statuses:
            next_action = _t(
                self,
                "pc_next_active",
            )

        elif statuses.intersection(
            {
                "BACKLOG",
                "READY",
            }
        ):
            next_action = _t(
                self,
                "pc_next_activate",
            )

        elif (
            tasks
            and all(
                task.status == "DONE"
                for task in tasks
            )
        ):
            next_action = _t(
                self,
                "pc_next_done",
            )

        else:
            next_action = _t(
                self,
                "pc_next_wait",
            )

        work_request = (
            ", ".join(
                self.preparation_result
                .work_request_ids
            )
            or "unknown"
        )

        renderables = [
            Panel(
                f"{_t(self, 'pc_project')}: "
                f"{self.plan_data.project_name}\n"
                f"{_t(self, 'pc_work_request')}: "
                f"{work_request}",
                title=_t(
                    self,
                    "pc_control_title",
                ),
            ),
            Text(""),
            summary,
            Text(""),
            table,
            Text(""),
        ]

        if evidence_count:
            renderables.extend(
                [
                    evidence_table,
                    Text(""),
                ]
            )
        else:
            renderables.extend(
                [
                    Panel(
                        _t(
                            self,
                            "pc_no_execution_evidence",
                        ),
                        title=_t(
                            self,
                            "pc_execution_evidence",
                        ),
                    ),
                    Text(""),
                ]
            )

        if result_notes:
            renderables.extend(
                [
                    Panel(
                        "\n\n"
                        + ("\n\n" + ("-" * 50) + "\n\n").join(
                            result_notes
                        ),
                        title=_t(
                            self,
                            "pc_result_details",
                        ),
                    ),
                    Text(""),
                ]
            )

        if result_errors:
            renderables.extend(
                [
                    Panel(
                        "\n".join(
                            result_errors
                        ),
                        title=_t(
                            self,
                            "pc_result_read_errors",
                        ),
                    ),
                    Text(""),
                ]
            )

        renderables.extend(
            [
                Panel(
                    "\n".join(controls),
                    title=_t(
                        self,
                        "pc_controls",
                    ),
                ),
                Text(""),
                Panel(
                    next_action,
                    title=_t(
                        self,
                        "pc_next_action",
                    ),
                ),
                Text(""),
                Panel(
                    _t(
                        self,
                        "pc_workflow_body",
                    ),
                    title=_t(
                        self,
                        "pc_workflow_title",
                    ),
                ),
            ]
        )

        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Group(
                *renderables
            )
        )
