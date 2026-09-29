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
from company_os.application.engineering_backlog_service import (
    EngineeringBacklogService,
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
from company_os.application.task_result_service import (
    TaskResultService,
)
from company_os.application.work_request_service import (
    WorkRequestService,
)


def _t(widget, key: str) -> str:
    try:
        language = getattr(
            widget.app,
            "language",
            "es",
        )
    except Exception:
        language = "es"

    return ui_text(
        language,
        key,
    )


class PlanControlScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("a", "activate", "Activate"),
        Binding("r", "run_agents", "Analysis agent"),
        Binding("b", "engineering_backlog", "Engineering backlog"),
        Binding("w", "prepare_writable", "Writable implementation"),
        Binding("u", "unblock", "Retry blocked"),
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
        self.work_requests = WorkRequestService()
        self.engineering_backlog = EngineeringBacklogService()
        self.gates = GateControlService()
        self.writable = WritableWorkspaceService()
        self.writable_runner = WritableExecutionAdapter()
        self.corrective = CorrectiveReactivationService()
        self.results = TaskResultService()

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

    def action_back(self) -> None:
        if self._reject_if_busy():
            return

        self.app.pop_screen()

    def action_refresh_tasks(self) -> None:
        if self._reject_if_busy():
            return

        self._refresh_view()

    def _work_request_ids(self) -> list[str]:
        return [
            value
            for value in (
                self.preparation_result.work_request_ids
            )
            if value
        ]

    def _task_ids(self) -> list[str]:
        work_request_ids = self._work_request_ids()

        if work_request_ids:
            return self.work_requests.resolve_task_ids(
                self.plan_data.project_root,
                work_request_ids,
            )

        return list(
            self.preparation_result.created_task_ids
        )

    def _tasks(self):
        return self.control.get_tasks(
            self.plan_data.project_root,
            self._task_ids(),
        )


    @staticmethod
    def _compact(
        value: str,
        limit: int,
    ) -> str:
        value = " ".join(
            str(value).split()
        ).strip()

        if len(value) <= limit:
            return value

        return (
            value[: max(0, limit - 3)]
            + "..."
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

        return "Operation running"

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
                self.progress.stage = first.status

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
                _marker, task_id, gate, state = parts

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
                self.progress.provider = provider

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

        owner = self._operation_owners.get(
            self.progress.current_task,
            "-",
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

    def _analysis_task_ids(self) -> list[str]:
        return [
            task.id
            for task in self._tasks()
            if task.work_kind != "IMPLEMENTATION"
        ]

    def _writable_task_ids(self) -> list[str]:
        return [
            task.id
            for task in self._tasks()
            if (
                task.work_kind == "IMPLEMENTATION"
                and task.status in {
                    "READY",
                    "ACTIVE",
                }
            )
        ]

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
        if self._reject_if_busy():
            return

        tasks = self._tasks()

        active = [
            task.id
            for task in tasks
            if (
                task.status == "ACTIVE"
                and task.work_kind != "IMPLEMENTATION"
            )
        ]

        if not active:
            self.notify(
                "No ACTIVE tasks from this plan.",
                severity="warning",
            )
            return

        if not self._begin_progress(
            kind="analysis",
            title="RUN AGENTS",
            task_ids=active,
            initial_event="Running ACTIVE analysis agents",
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
                    self._analysis_task_ids(),
                    provider="Auto",
                    progress=self._worker_progress,
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

    def action_engineering_backlog(self) -> None:
        if self.busy:
            return

        pending = self.engineering_backlog.pending_sources(
            self.plan_data.project_root,
            self._work_request_ids(),
        )

        if not pending:
            self.notify(
                "No DONE Engineering Manager plan is ready "
                "for backlog materialization.",
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            "Generating and materializing engineering "
            "backlog from:\n\n"
            + "\n".join(
                source.task_id
                for source in pending
            ),
            "ENGINEERING BACKLOG",
        )

        self.engineering_backlog_worker()

    @work(
        thread=True,
        exclusive=True,
        group="engineering-backlog",
        exit_on_error=False,
    )
    def engineering_backlog_worker(self) -> None:
        try:
            result = (
                self.engineering_backlog
                .generate_and_materialize(
                    self.plan_data.project_root,
                    self._work_request_ids(),
                    provider="Auto",
                )
            )

            message = (
                "Materialized from: "
                + (
                    ", ".join(
                        result.materialized_source_ids
                    )
                    or "none"
                )
            )

            if result.skipped_source_ids:
                message += (
                    "\nAlready materialized: "
                    + ", ".join(
                        result.skipped_source_ids
                    )
                )

            self.app.call_from_thread(
                self._operation_finished,
                message,
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                "Engineering backlog failed",
                str(exc),
            )

    def action_prepare_writable(self) -> None:
        if self._reject_if_busy():
            return

        tasks = self._tasks()

        writable_ids = [
            task.id
            for task in tasks
            if (
                task.work_kind == "IMPLEMENTATION"
                and task.status in {
                    "READY",
                    "ACTIVE",
                }
            )
        ]

        if not writable_ids:
            self.notify(
                "No READY/ACTIVE IMPLEMENTATION tasks are "
                "available for writable execution.",
                severity="warning",
            )
            return

        if not self._begin_progress(
            kind="writable",
            title="WRITABLE IMPLEMENTATION",
            task_ids=writable_ids,
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
                self._writable_task_ids(),
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

                    if execution.changed_paths:
                        details.extend(
                            [
                                "",
                                "Changed paths:",
                                *[
                                    f"- {path}"
                                    for path in execution.changed_paths
                                ],
                            ]
                        )

                    if execution.verification:
                        details.extend(
                            [
                                "",
                                "Verification:",
                                execution.verification,
                            ]
                        )

                    if execution.result_path:
                        details.extend(
                            [
                                "",
                                "Result artifact:",
                                execution.result_path,
                            ]
                        )

                    if execution.evidence_path:
                        details.extend(
                            [
                                "",
                                "Evidence artifact:",
                                execution.evidence_path,
                            ]
                        )

                    if execution.diff_stat:
                        details.extend(
                            [
                                "",
                                "Git diff stat:",
                                execution.diff_stat,
                            ]
                        )

                    if execution.diff_text:
                        preview = execution.diff_text

                        if len(preview) > 12000:
                            preview = (
                                preview[:12000]
                                + "\n[DIFF PREVIEW TRUNCATED]"
                            )

                        details.extend(
                            [
                                "",
                                "Git diff preview:",
                                preview,
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
                    "Writable execution is BLOCKED. "
                    f"{_t(self, 'progress_duration')}: "
                    f"{self.progress.final_duration}"
                ),
                severity="warning",
            )
        else:
            self.notify(
                (
                    "Writable execution finished. "
                    f"{_t(self, 'progress_duration')}: "
                    f"{self.progress.final_duration}"
                )
            )

    def action_unblock(self) -> None:
        if self.busy:
            return

        blocked = [
            task.id
            for task in self._tasks()
            if task.status == "BLOCKED"
        ]

        if not blocked:
            self.notify(
                "No BLOCKED tasks are available for retry.",
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            "Returning reviewed blockers to READY:\n\n"
            + "\n".join(blocked),
            "BLOCKED RECOVERY",
        )

        self.unblock_worker()

    @work(
        thread=True,
        exclusive=True,
        group="unblock-plan",
        exit_on_error=False,
    )
    def unblock_worker(self) -> None:
        try:
            result = self.corrective.unblock(
                self.plan_data.project_root,
                self._task_ids(),
            )

            self.app.call_from_thread(
                self._operation_finished,
                "Ready for retry: "
                + (
                    ", ".join(result.task_ids)
                    or "none"
                ),
            )

        except Exception as exc:
            self.app.call_from_thread(
                self._operation_failed,
                "BLOCKED recovery failed",
                str(exc),
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
                "No pending gate tasks.",
                severity="warning",
            )
            return

        if not self._begin_progress(
            kind="gates",
            title="QUALITY GATES",
            task_ids=gate_tasks,
            initial_event="Running independent gates",
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
        was_live_progress = self.progress.busy

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
        table.add_column("Kind")
        table.add_column("Task")
        table.add_column("Retry / Evidence")

        for task in tasks:
            status = task.status

            if task.id in finalizable:
                status += " / FINAL READY"

            details = self.results.read_latest(
                self.plan_data.project_root,
                task.id,
            )

            indicator = details.retry_reason

            if (
                not indicator
                and task.status == "BLOCKED"
                and details.blockers
            ):
                indicator = details.blockers

            table.add_row(
                task.id,
                status,
                task.owner,
                task.work_kind or "PLANNING",
                task.title,
                indicator or "-",
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
            (
                task.status == "ACTIVE"
                and task.work_kind != "IMPLEMENTATION"
            )
            for task in tasks
        ):
            controls.append(
                "R = Run analysis-only agent"
            )

        pending_backlog = (
            self.engineering_backlog
            .pending_sources(
                self.plan_data.project_root,
                self._work_request_ids(),
            )
        )

        if pending_backlog:
            controls.append(
                "B = Generate/materialize engineering backlog"
            )

        if any(
            (
                task.status in {
                    "READY",
                    "ACTIVE",
                }
                and task.work_kind == "IMPLEMENTATION"
            )
            for task in tasks
        ):
            controls.append(
                "W = Run writable implementation / retry"
            )

        if any(
            task.status == "BLOCKED"
            for task in tasks
        ):
            controls.append(
                "U = Review blocker -> READY"
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
                self._work_request_ids()
            )
            or "unknown"
        )

        renderables = [
            Panel(
                f"Project: "
                f"{self.plan_data.project_name}\n"
                f"Work Request: {work_request}",
                title="Plan Control",
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
                    "Retry paths:\n"
                    "CHANGES_REQUIRED / QA FAIL / SECURITY FAIL "
                    "-> READY -> W\n"
                    "BLOCKED -> U -> READY -> W\n\n"
                    "Planning/non-IMPLEMENTATION ACTIVE -> R\n"
                    "Engineering Manager DONE -> B\n"
                    "IMPLEMENTATION READY/ACTIVE -> W\n\n"
                    "When a wave reaches DONE, press A "
                    "again to activate newly eligible "
                    "dependent tasks.",
                    title="Workflow",
                ),
            ]
        )

        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Group(
                *renderables,
            )
        )

        return
