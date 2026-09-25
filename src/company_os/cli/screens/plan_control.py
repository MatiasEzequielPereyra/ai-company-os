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
from company_os.application.gate_control_service import (
    GateControlService,
)
from company_os.application.task_result_service import (
    TaskResultService,
)
from company_os.application.work_request_service import (
    WorkRequestService,
)
from company_os.application.local_runtime_service import (
    LocalRuntimeService,
)
from company_os.cli.operation_progress import (
    OperationProgressState,
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
        self.local_runtime = LocalRuntimeService()

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
        if self.busy:
            self.notify(
                "An operation is currently running.",
                severity="warning",
            )
            return

        self.app.pop_screen()

    def action_refresh_tasks(self) -> None:
        self.local_runtime.invalidate(
            self.plan_data.project_root
        )
        self._refresh_view()

    def _work_request_ids(self) -> list[str]:
        explicit = [
            value
            for value in (
                self.preparation_result.work_request_ids
            )
            if value
        ]

        if explicit:
            return explicit

        return self.work_requests.request_ids_for_task_ids(
            self.plan_data.project_root,
            list(
                self.preparation_result.created_task_ids
            ),
        )

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
        if self.busy:
            return

        active = [
            task.id
            for task in self._tasks()
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

        self.busy = True
        self._operation_owners = {
            task.id: task.owner
            for task in self._tasks()
            if task.id in active
        }

        self.progress.start(
            kind="analysis",
            title="RUN AGENTS",
            task_ids=active,
            initial_event="Starting analysis runtime...",
            provider="Auto",
        )
        self._render_operation_progress()

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
                    progress=self._progress_from_worker,
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
        backlog_ids = [
            source.task_id
            for source in pending
        ]
        self._operation_owners = {
            task.id: task.owner
            for task in self._tasks()
            if task.id in backlog_ids
        }

        self.progress.start(
            kind="backlog",
            title="ENGINEERING BACKLOG",
            task_ids=backlog_ids,
            initial_event="Starting engineering backlog generation...",
            provider="Auto",
        )
        self._render_operation_progress()

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
                    progress=self._progress_from_worker,
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
        if self.busy:
            return

        writable_ids = self._writable_task_ids()

        if not writable_ids:
            self.notify(
                "No READY/ACTIVE IMPLEMENTATION tasks are "
                "available for writable execution.",
                severity="warning",
            )
            return

        self.busy = True

        self._working(
            "Preparing isolated Git worktrees:\n\n"
            + "\n".join(writable_ids),
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
        self._operation_owners = {
            task.id: task.owner
            for task in self._tasks()
            if task.id in gate_tasks
        }

        self.progress.start(
            kind="gates",
            title="QUALITY GATES",
            task_ids=gate_tasks,
            initial_event="Starting quality gates...",
            provider="Auto",
        )
        self._render_operation_progress()

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
                    progress=self._progress_from_worker,
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

    def _progress_from_worker(
        self,
        line: str,
    ) -> None:
        self.app.call_from_thread(
            self._handle_progress_line,
            line,
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
            "__AICO_BACKLOG__|"
        ):
            parts = line.split("|")

            if len(parts) == 4:
                _marker, task_id, stage, state = parts
                self.progress.current_task = task_id
                self.progress.stage = stage

                labels = {
                    "GENERATE": "Generating structured backlog",
                    "MATERIALIZE": "Materializing tasks",
                }
                label = labels.get(stage, stage.title())

                if state == "START":
                    self.progress.add_event(
                        f"{label}..."
                    )
                elif state == "DONE":
                    self.progress.add_event(
                        f"{label} finished."
                    )

            self._render_operation_progress()
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
            r"(?i)^Running agent:\s*([^\s]+)\s*->\s*(AICO-\d+)",
            line,
        )
        if task_match:
            self.progress.current_task = (
                task_match.group(2)
            )

        provider_match = re.match(
            r"(?i)^Provider (?:attempt|succeeded|mode|requested):\s*(.+)$",
            line,
        )
        if provider_match:
            value = provider_match.group(1).strip()
            if (
                "attempt" in line.casefold()
                or "succeeded" in line.casefold()
            ):
                self.progress.provider = value

        model_match = re.match(
            r"(?i)^Ollama model:\s*(.+)$",
            line,
        )
        if model_match:
            self.progress.model = (
                model_match.group(1).strip()
            )

        context_match = re.search(
            r"(?i)^Context pack:\s*([0-9,]+)\s*characters",
            line,
        )
        if context_match:
            self.progress.context_chars = (
                context_match.group(1).replace(",", "")
            )

        lower = line.casefold()
        relevant_terms = (
            "building",
            "context",
            "provider",
            "ollama",
            "inference",
            "running agent",
            "task advanced",
            "task result",
            "outcome",
            "completed",
            "failed",
            "runtime",
            "review",
            "security",
            "gate",
            "qa",
            "backlog",
            "materializ",
            "structured",
        )

        if any(
            term in lower
            for term in relevant_terms
        ):
            self.progress.add_event(
                " ".join(line.split())[:180]
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
            or ", ".join(self.progress.task_ids)
            or "-"
        )
        owner = self._operation_owners.get(
            self.progress.current_task,
            "-"
        )

        lines = [
            f"Task: {task}",
            f"Agent: {owner}",
        ]

        if self.progress.kind == "backlog":
            stage_labels = {
                "GENERATE": "Generating structured backlog",
                "MATERIALIZE": "Materializing tasks",
            }
            if self.progress.stage:
                lines.extend(
                    [
                        "",
                        "Stage: "
                        + stage_labels.get(
                            self.progress.stage,
                            self.progress.stage.title(),
                        ),
                        "",
                    ]
                )

        if self.progress.kind == "gates":
            markers = {
                "DONE": "[OK]",
                "CURRENT": "[>>]",
                "PENDING": "[  ]",
            }
            lines.extend(
                [
                    "",
                    (
                        f"{markers.get(self.progress.gate_states['REVIEW'], '[  ]')} "
                        "Review"
                    ),
                    (
                        f"{markers.get(self.progress.gate_states['QA'], '[  ]')} "
                        "QA"
                    ),
                    (
                        f"{markers.get(self.progress.gate_states['SECURITY'], '[  ]')} "
                        "Security"
                    ),
                    "",
                ]
            )

        lines.extend(
            [
                f"Provider: {self.progress.provider or '-'}",
                f"Model: {self.progress.model or '-'}",
            ]
        )

        if self.progress.context_chars:
            lines.append(
                "Context: "
                + f"{int(self.progress.context_chars):,}"
                + " chars"
            )

        lines.extend(
            [
                f"Elapsed: {self.progress.elapsed_text()}",
                "",
                f"Activity: {self.progress.activity_bar()}",
                (
                    f"{self.progress.spinner()} "
                    f"{self.progress.last_event or 'Working...'}"
                ),
            ]
        )

        if self.progress.recent_events:
            lines.extend(
                [
                    "",
                    "Recent events:",
                    *[
                        f"- {item}"
                        for item
                        in self.progress.recent_events
                    ],
                ]
            )

        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Panel(
                Text("\n".join(lines)),
                title="Live Progress",
            )
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
                status="COMPLETED",
                summary=message,
            )
        self.busy = False
        self._refresh_view()
        self.notify(message)

    def _operation_failed(
        self,
        title: str,
        message: str,
    ) -> None:
        if self.progress.busy:
            self.progress.finish(
                status="FAILED",
                summary=message,
            )
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

        active_task = next(
            (
                task
                for task in tasks
                if task.status == "ACTIVE"
            ),
            None,
        )
        active_role = (
            active_task.owner
            if active_task is not None
            else "pm"
        )
        local_workload = (
            "writable"
            if (
                active_task is not None
                and active_task.work_kind == "IMPLEMENTATION"
            )
            else "analysis"
        )

        local_status = self.local_runtime.inspect(
            self.plan_data.project_root,
            role=active_role,
            workload=local_workload,
        )

        if local_status.available:
            gpu_text = (
                local_status.gpu_name
                or "CPU / shared memory"
            )

            local_runtime_text = (
                f"Profile: {local_status.profile}\n"
                f"Capability: "
                f"{local_status.capability_score}/100\n"
                f"Role: {active_role}\n"
                f"Selected model: "
                f"{local_status.model}\n"
                f"RAM: {local_status.ram_gb:.2f} GB\n"
                f"GPU: {gpu_text}\n"
                f"VRAM: "
                f"{local_status.vram_gb:.2f} GB\n"
                f"Context: "
                f"{local_status.num_ctx}\n"
                f"Output budget: "
                f"{local_status.num_predict}"
            )
        else:
            local_runtime_text = (
                "Local runtime unavailable\n"
                f"Reason: {local_status.reason}"
            )

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
                Panel(
                    local_runtime_text,
                    title="Local Runtime / Auto",
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
            )
        )
