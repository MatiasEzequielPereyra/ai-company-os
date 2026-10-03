from __future__ import annotations

import re
import subprocess

from rich import box
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
from company_os.application.local_runtime_service import LocalRuntimeService, LocalRuntimeStatus
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
from company_os.cli.theme import (
    HACKER_ERROR,
    HACKER_NEON,
    HACKER_NEON_DIM,
    is_hacker_interface,
    sync_hacker_screen_class,
    terminal_section_title,
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
        Binding("escape", "back", "Atras / Back"),
        Binding("a", "activate", "Activar / Activate"),
        Binding("r", "run_agents", "Analisis / Analysis"),
        Binding("b", "engineering_backlog", "Engineering backlog"),
        Binding("w", "prepare_writable", "Writable"),
        Binding("u", "unblock", "Retry blocked"),
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
        self.work_requests = WorkRequestService()
        self.engineering_backlog = EngineeringBacklogService()
        self.gates = GateControlService()
        self.writable = WritableWorkspaceService()
        self.writable_runner = WritableExecutionAdapter()
        self.corrective = CorrectiveReactivationService()
        self.results = TaskResultService()
        self.local_runtime = LocalRuntimeService()
        self._local_runtime_key: tuple[str, str] | None = None
        self._local_runtime_status: LocalRuntimeStatus | None = None
        self._local_runtime_generation = 0

        self.busy = False
        self.last_error_text = ""
        self.progress = OperationProgressState()
        self._operation_owners: dict[str, str] = {}

    def compose(self) -> ComposeResult:
        yield Header()

        with VerticalScroll():
            yield Static(id="plan-local-runtime")
            yield Static(
                id="plan-control-content",
            )

        yield Footer()

    def on_mount(self) -> None:
        sync_hacker_screen_class(
            self
        )

        self.set_interval(
            0.25,
            self._tick_operation_progress,
        )

        self._refresh_view()

    def refresh_language(self) -> None:
        if not self.busy:
            self._refresh_view()

    def _hacker_mode(self) -> bool:
        return is_hacker_interface(
            getattr(
                self.app,
                "interface_theme",
                "default",
            )
        )

    def _status_display(
        self,
        value: str,
    ):
        if not self._hacker_mode():
            return value

        normalized = value.upper()

        if any(
            marker in normalized
            for marker in (
                "BLOCKED",
                "FAIL",
                "ERROR",
                "CHANGES_REQUIRED",
            )
        ):
            style = f"bold {HACKER_ERROR}"

        elif any(
            marker in normalized
            for marker in (
                "BACKLOG",
                "WAIT",
                "UNKNOWN",
                "STALE",
            )
        ):
            style = HACKER_NEON_DIM

        else:
            style = f"bold {HACKER_NEON}"

        return Text(
            value,
            style=style,
        )

    def _panel_options(self) -> dict:
        if not self._hacker_mode():
            return {}

        return {
            "box": box.ASCII,
            "border_style": HACKER_NEON,
        }

    def _panel_title(
        self,
        title: str,
    ) -> str:
        if self._hacker_mode():
            return terminal_section_title(
                title
            )

        return title

    def action_back(self) -> None:
        if self._reject_if_busy():
            return

        self.app.pop_screen()

    def action_refresh_tasks(self) -> None:
        if self._reject_if_busy():
            return

        self.local_runtime.invalidate(self.plan_data.project_root)
        self._local_runtime_key = None
        self._refresh_view()

    def _refresh_local_runtime(self, tasks) -> None:
        active = next((task for task in tasks if task.status == "ACTIVE"), None)
        role = active.owner if active else "pm"
        workload = "writable" if active and active.work_kind == "IMPLEMENTATION" else "analysis"
        if self.progress.busy:
            workload = {"gates": "gate", "writable": "writable"}.get(self.progress.kind, "analysis")
            role = self._operation_owners.get(self.progress.current_task, role)
            if workload == "gate":
                # Match the independent reviewer contract in run-gate-agent.ps1.
                gate = self.progress.stage.upper()
                if gate == "REVIEW":
                    role = "engineering-manager"
                elif gate in {"QA", "SECURITY"}:
                    reviewer = gate.casefold()
                    role = "engineering-manager" if role.casefold() == reviewer else reviewer
        key = (role, workload)
        if key != self._local_runtime_key:
            self._local_runtime_key = key
            self._local_runtime_status = None
            self._local_runtime_generation += 1
            self._inspect_local_runtime(key, self._local_runtime_generation)
        self._render_local_runtime()

    @work(thread=True, exclusive=True, group="local-runtime")
    def _inspect_local_runtime(self, key: tuple[str, str], generation: int) -> None:
        try:
            status = self.local_runtime.inspect(self.plan_data.project_root, role=key[0], workload=key[1])
        except Exception:
            # A failed diagnostic must never abort the screen or reveal raw errors.
            status = LocalRuntimeStatus(reason="Local runtime inspection failed.")
        self.app.call_from_thread(self._apply_local_runtime, key, status, generation)

    def _apply_local_runtime(self, key: tuple[str, str], status: LocalRuntimeStatus, generation: int) -> None:
        if key == self._local_runtime_key and generation == self._local_runtime_generation and self.is_mounted:
            self._local_runtime_status = status
            self._render_local_runtime()

    def _render_local_runtime(self) -> None:
        status = self._local_runtime_status
        lines = [_t(self, "pc_local_candidate")]
        if self._local_runtime_key:
            role, workload = self._local_runtime_key
            lines.append(f"{_t(self, 'pc_local_role')}: {role} / {workload}")
        if status is None:
            lines.append(_t(self, "pc_local_loading"))
        else:
            lines.append(_t(self, "pc_local_available" if status.available else "pc_local_unavailable"))
            for label, value in (
                ("pc_local_profile", status.profile),
                ("pc_local_score", status.capability_score),
                ("pc_model", status.model),
                ("pc_local_ram", status.ram_gb),
                ("pc_local_gpu", status.gpu_name),
                ("pc_local_vram", status.vram_gb),
                ("pc_local_ctx", status.num_ctx),
                ("pc_local_predict", status.num_predict),
                ("pc_local_reason", status.reason),
            ):
                lines.append(f"{_t(self, label)}: {value if value is not None and value != '' else '-'}")
        self.query_one("#plan-local-runtime", Static).update(Panel(
            Text("\n".join(lines)), title=self._panel_title(_t(self, "pc_local_title")),
            **self._panel_options(),
        ))

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
        self._refresh_local_runtime(tasks)
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
            "backlog",
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
                    self._refresh_local_runtime(())

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
            self._refresh_local_runtime(())

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
            "backlog",
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

        panel_title = _t(
            self,
            "progress_title",
        )

        panel_options = {}

        if self._hacker_mode():
            terminal_lines = []

            for line in lines:
                if not line:
                    terminal_lines.append("")
                    continue

                if line.startswith("["):
                    terminal_lines.append(
                        line.upper()
                    )
                    continue

                if line.startswith("- "):
                    terminal_lines.append(
                        "> " + line[2:]
                    )
                    continue

                if ":" in line:
                    key, value = line.split(
                        ":",
                        1,
                    )

                    terminal_lines.append(
                        f"> {key.upper():<18} "
                        f"{value.strip()}"
                    )
                    continue

                terminal_lines.append(
                    f"> {line}"
                )

            lines = terminal_lines

            panel_title = (
                "LIVE PROCESS // "
                + self.progress.title.upper()
            )

            panel_options = {
                "box": box.ASCII,
                "border_style": HACKER_NEON,
            }

        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Panel(
                Text(
                    "\n".join(lines)
                ),
                title=panel_title,
                **panel_options,
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
        if self._reject_if_busy():
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

        tasks = self._tasks()
        source_ids = [
            source.task_id
            for source in pending
        ]

        if not self._begin_progress(
            kind="engineering-backlog",
            title="ENGINEERING BACKLOG",
            task_ids=source_ids,
            initial_event=(
                "Starting engineering backlog generation"
            ),
            tasks=tasks,
            provider="Auto",
        ):
            return

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
                    progress=self._worker_progress,
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
                title=self._panel_title(
                    title
                ),
                **self._panel_options(),
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
        self._refresh_local_runtime(tasks)

        finalizable = set(
            self.gates.finalizable_task_ids(
                self.plan_data.project_root,
                self._task_ids(),
            )
        )

        plan_tasks_title = _t(
            self,
            "pc_plan_tasks",
        )

        table = Table(
            title=self._panel_title(
                plan_tasks_title
            ),
            show_lines=True,
            **(
                {"box": box.ASCII}
                if self._hacker_mode()
                else {}
            ),
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
                self._status_display(
                    status
                ),
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
            title=(
                self._panel_title(
                    _t(
                        self,
                        "status",
                    )
                )
                if self._hacker_mode()
                else None
            ),
            show_header=False,
            box=(
                box.ASCII
                if self._hacker_mode()
                else None
            ),
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
                self._status_display(
                    status
                ),
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

        header_content = (
            (
                f"> {_t(self, 'pc_project').upper():<14} "
                f"{self.plan_data.project_name}\n"
                f"> {_t(self, 'pc_work_request').upper():<14} "
                f"{work_request}"
            )
            if self._hacker_mode()
            else (
                f"{_t(self, 'pc_project')}: "
                f"{self.plan_data.project_name}\n"
                f"{_t(self, 'pc_work_request')}: "
                f"{work_request}"
            )
        )

        renderables = [
            Panel(
                header_content,
                title=self._panel_title(
                    _t(
                        self,
                        "pc_control_title",
                    )
                ),
                **self._panel_options(),
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
                        title=self._panel_title(
                            _t(
                                self,
                                "progress_last_operation",
                            )
                        ),
                        **self._panel_options(),
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
                    (
                        "\n".join(
                            f"> {item}"
                            for item in controls
                        )
                        if self._hacker_mode()
                        else "\n".join(
                            controls
                        )
                    ),
                    title=self._panel_title(
                        _t(
                            self,
                            "pc_controls",
                        )
                    ),
                    **self._panel_options(),
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
                    title=self._panel_title(
                        _t(
                            self,
                            "pc_workflow_title",
                        )
                    ),
                    **self._panel_options(),
                ),
            ]
        )

        if self._hacker_mode():
            renderables = [
                item
                for item in renderables
                if not (
                    isinstance(
                        item,
                        Text,
                    )
                    and not item.plain.strip()
                )
            ]

        self.query_one(
            "#plan-control-content",
            Static,
        ).update(
            Group(
                *renderables,
            )
        )

        return
