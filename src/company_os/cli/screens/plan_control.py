from __future__ import annotations

import re
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
from company_os.cli.operation_progress import (
    OperationProgressState,
)
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
        self.progress = OperationProgressState()
        self._operation_owners: dict[str, str] = {}

    def compose(self) -> ComposeResult:
        yield Header()

        with VerticalScroll():
            yield Static(
                id="plan-control-content",
            )

        yield Footer()

    def on_mount(self) -> None:
        self.set_interval(
            0.25,
            self._tick_operation_progress,
        )
        self._refresh_view()

    def refresh_language(self) -> None:
        if not self.busy:
            self._refresh_view()

    def action_back(self) -> None:
        if self._reject_if_busy():
            return

        self.app.pop_screen()

    def action_refresh_tasks(self) -> None:
        if self._reject_if_busy():
            return

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

    def _busy_description(self) -> str:
        if self.progress.busy:
            task = (
                self.progress.current_task
                or ", ".join(
                    self.progress.task_ids
                )
                or "-"
            )

            return (
                f"{self.progress.title} / "
                f"{task}"
            )

        return _t(
            self,
            "pc_busy",
        )

    def _reject_if_busy(self) -> bool:
        if not self.busy:
            return False

        self.notify(
            f"{_t(self, 'progress_already_running')}: "
            f"{self._busy_description()}",
            severity="warning",
        )
        return True

    def _begin_progress(
        self,
        *,
        kind: str,
        title: str,
        task_ids: list[str],
        initial_event: str,
        tasks,
        provider: str = "Auto",
    ) -> bool:
        if self._reject_if_busy():
            return False

        started = self.progress.start(
            kind=kind,
            title=title,
            task_ids=task_ids,
            initial_event=initial_event,
            provider=provider,
        )

        if not started:
            return False

        self._operation_owners = {
            task.id: task.owner
            for task in tasks
        }

        if task_ids:
            first = next(
                (
                    task
                    for task in tasks
                    if task.id == task_ids[0]
                ),
                None,
            )

            if first is not None:
                self.progress.stage = (
                    first.status
                )

        self.busy = True
        self._render_operation_progress()
        return True

    def _worker_progress(
        self,
        line: str,
    ) -> None:
        value = str(line).strip()

        if not value:
            return

        lower = value.casefold()

        relevant_terms = (
            "__aico_gate__|",
            "building",
            "context",
            "provider",
            "model",
            "sending",
            "waiting",
            "response",
            "validat",
            "submitting",
            "submit",
            "refresh",
            "starting",
            "workspace",
            "worktree",
            "runtime",
            "dispatch",
            "review",
            "security",
            "gate",
            "task:",
        )

        if not any(
            term in lower
            for term in relevant_terms
        ):
            return

        self.app.call_from_thread(
            self._handle_progress_line,
            value,
        )

    def _handle_progress_line(
        self,
        line: str,
    ) -> None:
        if not self.progress.busy:
            return

        line = re.sub(
            r"\x1b\[[0-?]*[ -/]*[@-~]",
            "",
            str(line),
        ).strip()

        if not line:
            return

        if line.startswith(
            "__AICO_GATE__|"
        ):
            parts = line.split("|")

            if len(parts) == 4:
                _marker, task_id, gate, state = (
                    parts
                )

                if state == "START":
                    self.progress.begin_gate(
                        task_id,
                        gate,
                    )
                    self.progress.add_event(
                        f"Running {gate} gate..."
                    )

                elif state == "DONE":
                    self.progress.complete_gate(
                        task_id,
                        gate,
                    )
                    self.progress.add_event(
                        f"{gate} gate finished."
                    )

            self._render_operation_progress()
            return

        task_match = re.match(
            r"(?i)^Task:\s*(.+)$",
            line,
        )

        if task_match:
            self.progress.current_task = (
                task_match.group(1).strip()
            )

        provider_match = re.match(
            (
                r"(?i)^(?:Provider(?: selected| requested)?"
                r"|Selected provider):\s*(.+)$"
            ),
            line,
        )

        if provider_match:
            provider = (
                provider_match
                .group(1)
                .strip()
            )

            if (
                provider.casefold() != "auto"
                or self.progress.provider
                in {"", "Auto"}
            ):
                self.progress.provider = (
                    provider
                )

        model_match = re.match(
            (
                r"(?i)^(?:Model(?: selected)?"
                r"|Selected model):\s*(.+)$"
            ),
            line,
        )

        if model_match:
            self.progress.model = (
                model_match
                .group(1)
                .strip()
            )

        context_match = re.search(
            (
                r"(?i)Context(?: pack)?\s*:\s*"
                r"([0-9,]+)\s*"
                r"(?:characters|chars)?"
            ),
            line,
        )

        if context_match:
            self.progress.context_chars = (
                context_match
                .group(1)
                .replace(",", "")
            )

        lower = line.casefold()

        relevant_terms = (
            "building",
            "context",
            "provider",
            "model",
            "sending",
            "waiting",
            "response",
            "validat",
            "submitting",
            "submit",
            "refresh",
            "starting",
            "workspace",
            "worktree",
            "runtime",
            "dispatch",
            "review",
            "security",
            "gate",
            "task:",
        )

        if any(
            term in lower
            for term in relevant_terms
        ):
            self.progress.add_event(
                self._compact(
                    line,
                    120,
                )
            )

            if "sending request" in lower:
                self.progress.add_event(
                    _t(
                        self,
                        "progress_waiting_provider",
                    )
                )

        self._render_operation_progress()

    def _tick_operation_progress(
        self,
    ) -> None:
        if not (
            self.busy
            and self.progress.busy
        ):
            return

        self.progress.tick()
        self._render_operation_progress()

    def _render_operation_progress(
        self,
    ) -> None:
        if not self.progress.busy:
            return

        task = (
            self.progress.current_task
            or ", ".join(
                self.progress.task_ids
            )
            or "-"
        )

        owner = (
            self._operation_owners.get(
                self.progress.current_task,
                "-",
            )
        )

        lines = [
            (
                f"{_t(self, 'progress_task')}: "
                f"{task}"
            ),
            (
                f"{_t(self, 'progress_action')}: "
                f"{self.progress.title}"
            ),
        ]

        if self.progress.stage:
            lines.append(
                f"{_t(self, 'progress_stage')}: "
                f"{self.progress.stage}"
            )

        lines.append(
            f"{_t(self, 'progress_agent')}: "
            f"{owner}"
        )

        if self.progress.kind == "gates":
            lines.append("")

            labels = (
                ("REVIEW", "Review"),
                ("QA", "QA"),
                ("SECURITY", "Security"),
            )

            markers = {
                "DONE": "[EXEC]",
                "CURRENT": "[>>]",
                "PENDING": "[  ]",
            }

            for key, label in labels:
                lines.append(
                    f"{markers.get(self.progress.gate_states[key], '[  ]')} "
                    f"{label}"
                )

        lines.extend(
            [
                "",
                (
                    f"Provider: "
                    f"{self.progress.provider or '-'}"
                ),
                (
                    f"Model: "
                    f"{self.progress.model or '-'}"
                ),
            ]
        )

        if self.progress.context_chars:
            try:
                context_value = (
                    f"{int(self.progress.context_chars):,}"
                )
            except ValueError:
                context_value = (
                    self.progress.context_chars
                )

            lines.append(
                f"{_t(self, 'progress_context')}: "
                f"{context_value} chars"
            )

        lines.extend(
            [
                (
                    f"{_t(self, 'progress_elapsed')}: "
                    f"{self.progress.elapsed_text()}"
                ),
                "",
                (
                    f"{_t(self, 'progress_activity')}: "
                    f"{self.progress.activity_bar()}"
                ),
                (
                    f"{self.progress.spinner()} "
                    f"{self.progress.last_event or _t(self, 'progress_working')}"
                ),
            ]
        )

        if self.progress.recent_events:
            lines.extend(
                [
                    "",
                    (
                        f"{_t(self, 'progress_recent_events')}:"
                    ),
                ]
            )

            lines.extend(
                f"- {item}"
                for item
                in self.progress.recent_events
            )

        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Panel(
                Text(
                    "\n".join(lines)
                ),
                title=_t(
                    self,
                    "progress_title",
                ),
            )
        )

    def action_activate(self) -> None:
        if self._reject_if_busy():
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
        if self._reject_if_busy():
            return

        tasks = self._tasks()

        active = [
            task.id
            for task in tasks
            if task.status == "ACTIVE"
        ]

        if not active:
            self.notify(
                _t(self, "pc_no_active_analysis"),
                severity="warning",
            )
            return

        if not self._begin_progress(
            kind="analysis",
            title=_t(
                self,
                "pc_run_agents_title",
            ),
            task_ids=active,
            initial_event=_t(
                self,
                "pc_running_agents",
            ),
            tasks=tasks,
            provider="Auto",
        ):
            return

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
                    progress=self._worker_progress,
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
        if self._reject_if_busy():
            return

        tasks = self._tasks()

        active = [
            task.id
            for task in tasks
            if task.status == "ACTIVE"
        ]

        if not active:
            self.notify(
                _t(self, "pc_no_active_writable"),
                severity="warning",
            )
            return

        if not self._begin_progress(
            kind="writable",
            title=_t(
                self,
                "pc_writable_title",
            ),
            task_ids=active,
            initial_event=_t(
                self,
                "progress_preparing_worktree",
            ),
            tasks=tasks,
            provider="Auto",
        ):
            return

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
                    self._worker_progress(
                        f"Task: {workspace.task_id}"
                    )
                    self._worker_progress(
                        "Starting writable implementation..."
                    )

                    execution = (
                        self.writable_runner.run(
                            self.plan_data.project_root,
                            workspace.task_id,
                            workspace.path,
                            provider="Auto",
                            progress=self._worker_progress,
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
        status = (
            "BLOCKED"
            if blocked
            else "SUCCESS"
        )

        if self.progress.busy:
            self.progress.finish(
                status=status,
                summary=self._compact(
                    message,
                    180,
                ),
            )

        self.busy = False

        if blocked:
            self.last_error_text = message
        else:
            self.last_error_text = ""

        self._refresh_view()

        if blocked:
            self.notify(
                (
                    f"{_t(self, 'pc_writable_blocked_notify')} "
                    f"{_t(self, 'progress_duration')}: "
                    f"{self.progress.final_duration}"
                ),
                severity="warning",
            )
        else:
            self.notify(
                (
                    f"{_t(self, 'pc_writable_finished_notify')} "
                    f"{_t(self, 'progress_duration')}: "
                    f"{self.progress.final_duration}"
                )
            )

    def action_run_gates(self) -> None:
        if self._reject_if_busy():
            return

        tasks = self._tasks()

        gate_tasks = [
            task.id
            for task in tasks
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

        if not self._begin_progress(
            kind="gates",
            title=_t(
                self,
                "pc_quality_gates",
            ),
            task_ids=gate_tasks,
            initial_event=_t(
                self,
                "pc_running_gates",
            ),
            tasks=tasks,
            provider="Auto",
        ):
            return

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
                    progress=self._worker_progress,
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
        if self._reject_if_busy():
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
        if self.progress.busy:
            self.progress.finish(
                status="SUCCESS",
                summary=self._compact(
                    message,
                    180,
                ),
            )

        self.busy = False
        self._refresh_view()

        if self.progress.final_duration:
            self.notify(
                (
                    f"{message} "
                    f"{_t(self, 'progress_duration')}: "
                    f"{self.progress.final_duration}"
                )
            )
        else:
            self.notify(message)

    def _operation_failed(
        self,
        title: str,
        message: str,
    ) -> None:
        was_live_progress = (
            self.progress.busy
        )

        if was_live_progress:
            self.progress.finish(
                status="ERROR",
                summary=self._compact(
                    message,
                    180,
                ),
            )

        self.busy = False

        self.last_error_text = (
            f"{title}\n\n{message}"
        )

        if was_live_progress:
            self._refresh_view()

            self.notify(
                (
                    f"{title}. "
                    f"{_t(self, 'progress_duration')}: "
                    f"{self.progress.final_duration}"
                ),
                severity="error",
            )
            return

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
        ]

        if self.progress.final_status:
            last_lines = [
                (
                    f"Status: "
                    f"{self.progress.final_status}"
                ),
                (
                    f"{_t(self, 'progress_duration')}: "
                    f"{self.progress.final_duration or '-'}"
                ),
            ]

            if self.progress.final_summary:
                last_lines.extend(
                    [
                        "",
                        (
                            f"{_t(self, 'progress_summary')}: "
                            f"{self.progress.final_summary}"
                        ),
                    ]
                )

            renderables.extend(
                [
                    Panel(
                        Text(
                            "\n".join(
                                last_lines
                            )
                        ),
                        title=_t(
                            self,
                            "progress_last_operation",
                        ),
                    ),
                    Text(""),
                ]
            )

        renderables.extend(
            [
                summary,
                Text(""),
                table,
                Text(""),
            ]
        )

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
