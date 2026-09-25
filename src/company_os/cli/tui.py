from __future__ import annotations

from pathlib import Path

from rich.console import Group
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, VerticalScroll
from textual.screen import Screen
from textual.widgets import Input
from textual.widgets import Footer, Header, Label, ListItem, ListView, Static

from company_os.application.config_service import ConfigService
from company_os.cli.screens.projects import ProjectManagerScreen
from company_os.cli.screens.work_requests import WorkRequestsScreen
from company_os.cli.screens.help import HelpScreen
from company_os.cli.i18n import navigation_label
from company_os.cli.screens.command_center import CommandCenterScreen
from company_os.application.project_service import ProjectService
from company_os.application.provider_service import ProviderService
from company_os.application.command_service import CommandService
from company_os.application.status_service import StatusService
from company_os.application.handoff_service import HandoffService
from company_os.application.runtime_service import RuntimeService
from company_os.application.activity_service import ActivityService
from company_os.application.workflow_service import WorkflowService
from company_os.application.doctor_service import DoctorService
from company_os.application.task_service import TaskService


NAVIGATION = [
    ("Overview", "overview"),
    ("Command Center", "command"),
    ("Projects", "projects"),
    ("Plans / Work Requests", "plans"),
    ("Providers", "providers"),
    ("Tasks", "tasks"),
    ("Agents", "agents"),
    ("Workflow", "workflow"),
    ("Activity", "activity"),
    ("Handoffs", "handoffs"),
    ("Runtime", "runtime"),
    ("Blockers", "blockers"),
    ("Quality Gates", "gates"),
    ("Doctor", "doctor"),
    ("Diagnostics", "diagnostics"),
    ("Help / Guide", "help"),
]


class TaskDetailScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("q", "back", "Back"),
    ]

    def __init__(self, task) -> None:
        super().__init__()
        self.task_data = task

    def compose(self) -> ComposeResult:
        yield Header()

        with VerticalScroll(id="task-detail-scroll"):
            yield Static(
                self._render_task(),
                id="task-detail",
            )

        yield Footer()

    def action_back(self) -> None:
        self.app.pop_screen()

    def _render_task(self):
        task = self.task_data

        metadata = Table(
            show_header=False,
            box=None,
            padding=(0, 2),
        )

        metadata.add_column(style="bold")
        metadata.add_column()

        metadata.add_row("ID", task.id)
        metadata.add_row("Title", task.title)
        metadata.add_row("Status", task.status.value)
        metadata.add_row("Priority", task.priority.value)
        metadata.add_row("Owner", task.owner)

        workflow_phase = (
            task.workflow_phase.value
            if task.workflow_phase is not None
            else "-"
        )

        metadata.add_row(
            "Workflow phase",
            workflow_phase,
        )

        created = (
            task.created.isoformat()
            if task.created is not None
            else "-"
        )

        updated = (
            task.updated.isoformat()
            if task.updated is not None
            else "-"
        )

        metadata.add_row("Created", created)
        metadata.add_row("Updated", updated)

        objective = (
            task.objective.strip()
            if task.objective
            else "-"
        )

        dependencies = (
            "\n".join(
                f"- {dependency}"
                for dependency in task.dependencies
            )
            if task.dependencies
            else "None"
        )

        evidence = (
            "\n".join(
                f"- {item}"
                for item in task.evidence
            )
            if task.evidence
            else "None"
        )

        return Group(
            Panel(metadata, title="Task"),
            Text(""),
            Panel(objective, title="Objective"),
            Text(""),
            Panel(dependencies, title="Dependencies"),
            Text(""),
            Panel(evidence, title="Evidence"),
            Text(""),
            Panel(
                str(task.source_path),
                title="Source",
            ),
        )


class TasksScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("q", "back", "Back"),
    ]

    def __init__(self, tasks) -> None:
        super().__init__()
        self.tasks = list(tasks)

    def compose(self) -> ComposeResult:
        yield Header()

        yield Static(
            "TASKS   UP/DOWN Select   Enter Open   Esc Back",
            id="tasks-heading",
        )

        yield ListView(
            *[
                ListItem(
                    Label(
                        f"{task.id} | "
                        f"{task.status.value} | "
                        f"{task.priority.value} | "
                        f"{task.owner} | "
                        f"{task.title}"
                    )
                )
                for task in self.tasks
            ],
            id="task-list",
        )

        yield Footer()

    def on_mount(self) -> None:
        task_list = self.query_one(
            "#task-list",
            ListView,
        )

        if self.tasks:
            task_list.index = 0

        task_list.focus()

    def action_back(self) -> None:
        self.app.pop_screen()

    def on_list_view_selected(
        self,
        event: ListView.Selected,
    ) -> None:
        index = event.list_view.index

        if index is None:
            return

        if index < 0 or index >= len(self.tasks):
            return

        self.app.push_screen(
            TaskDetailScreen(
                self.tasks[index]
            )
        )



class AgentDetailScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("q", "back", "Back"),
    ]

    def __init__(self, agent, tasks) -> None:
        super().__init__()
        self.agent_data = agent
        self.all_tasks = list(tasks)

    def compose(self) -> ComposeResult:
        yield Header()

        with VerticalScroll(id="agent-detail-scroll"):
            yield Static(
                self._render_agent(),
                id="agent-detail",
            )

        yield Footer()

    def action_back(self) -> None:
        self.app.pop_screen()

    def _render_agent(self):
        agent = self.agent_data

        metadata = Table(
            show_header=False,
            box=None,
            padding=(0, 2),
        )

        metadata.add_column(style="bold")
        metadata.add_column()

        metadata.add_row(
            "ID",
            agent.id,
        )

        metadata.add_row(
            "Agent",
            agent.display_name,
        )

        metadata.add_row(
            "Work state",
            agent.work_state.value,
        )

        metadata.add_row(
            "Runtime state",
            agent.runtime_state.value,
        )

        current_tasks = (
            ", ".join(agent.current_task_ids)
            if agent.current_task_ids
            else "None"
        )

        metadata.add_row(
            "Current tasks",
            current_tasks,
        )

        owned_tasks = [
            task
            for task in self.all_tasks
            if task.owner.casefold() == agent.id.casefold()
        ]

        tasks_table = Table()

        tasks_table.add_column("ID")
        tasks_table.add_column("Status")
        tasks_table.add_column("Priority")
        tasks_table.add_column("Title")

        for task in owned_tasks:
            tasks_table.add_row(
                task.id,
                task.status.value,
                task.priority.value,
                task.title,
            )

        if not owned_tasks:
            assigned_content = Text(
                "No tasks in the repository are assigned to this agent."
            )
        else:
            assigned_content = tasks_table

        runtime_note = Text(
            "Runtime state is UNKNOWN until AI Company OS exposes "
            "authoritative Codex runtime/process evidence."
        )

        return Group(
            Panel(
                metadata,
                title="Agent",
            ),
            Text(""),
            Panel(
                assigned_content,
                title="Repository Tasks",
            ),
            Text(""),
            Panel(
                runtime_note,
                title="Runtime",
            ),
        )


class AgentsScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("q", "back", "Back"),
    ]

    def __init__(self, agents, tasks) -> None:
        super().__init__()
        self.agent_items = list(agents)
        self.all_tasks = list(tasks)

    def compose(self) -> ComposeResult:
        yield Header()

        yield Static(
            "AGENTS   UP/DOWN Select   Enter Open   Esc Back",
            id="agents-heading",
        )

        yield ListView(
            *[
                ListItem(
                    Label(
                        f"{agent.display_name} | "
                        f"{agent.work_state.value} | "
                        f"runtime: {agent.runtime_state.value} | "
                        f"tasks: "
                        f"{', '.join(agent.current_task_ids) if agent.current_task_ids else '-'}"
                    )
                )
                for agent in self.agent_items
            ],
            id="agent-list",
        )

        yield Footer()

    def on_mount(self) -> None:
        agent_list = self.query_one(
            "#agent-list",
            ListView,
        )

        if self.agent_items:
            agent_list.index = 0

        agent_list.focus()

    def action_back(self) -> None:
        self.app.pop_screen()

    def on_list_view_selected(
        self,
        event: ListView.Selected,
    ) -> None:
        index = event.list_view.index

        if index is None:
            return

        if index < 0 or index >= len(self.agent_items):
            return

        self.app.push_screen(
            AgentDetailScreen(
                self.agent_items[index],
                self.all_tasks,
            )
        )


class LegacyCommandCenterScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()

        yield Static(
            Panel(
                "Talk to the AI Company CEO.\n"
                "This version proposes approaches only; "
                "nothing is executed yet.",
                title="Command Center",
            )
        )

        yield VerticalScroll(
            Static(
                "Enter a request below.",
                id="command-output",
            )
        )

        yield Input(
            placeholder=(
                "Example: Audit Vendify for production readiness"
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

        proposal = CommandService().propose(
            request
        )

        renderables = [
            Panel(
                proposal.request,
                title=f"Request / {proposal.intent}",
            )
        ]

        for number, option in enumerate(
            proposal.options,
            start=1,
        ):
            marker = (
                "RECOMMENDED"
                if option.recommended
                else "OPTION"
            )

            body = (
                f"{option.description}\n\n"
                f"Agents: {', '.join(option.agents)}\n"
                f"Approval: {option.approval}"
            )

            renderables.append(
                Panel(
                    body,
                    title=(
                        f"{number}. {option.title} "
                        f"[{marker}]"
                    ),
                )
            )

        renderables.append(
            Panel(
                "Execution is disabled in this phase. "
                "Next we will make these options selectable "
                "and send the chosen plan to the CEO.",
                title="Next action",
            )
        )

        self.query_one(
            "#command-output",
            Static,
        ).update(
            Group(*renderables)
        )

        event.input.value = ""


class ProvidersScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()

        yield Static(
            "",
            id="providers-content",
        )

        yield Input(
            placeholder=(
                "OpenRouter API key - Enter to save securely"
            ),
            password=True,
            id="openrouter-key",
        )

        yield Input(
            placeholder=(
                "Gemini API key - Enter to save securely"
            ),
            password=True,
            id="gemini-key",
        )

        yield Static(
            "Keys are stored through the operating system "
            "credential store, not inside the repository."
        )

        yield Footer()

    def on_mount(self) -> None:
        self._refresh()

    def action_back(self) -> None:
        self.app.pop_screen()

    def _refresh(self) -> None:
        statuses = (
            ProviderService()
            .get_statuses()
        )

        table = Table(
            title="Providers"
        )

        table.add_column("Provider")
        table.add_column("Configured")
        table.add_column("Source")
        table.add_column("Notes")

        for provider in statuses:
            table.add_row(
                provider.name,
                (
                    "YES"
                    if provider.configured
                    else "NO"
                ),
                provider.source,
                provider.description,
            )

        self.query_one(
            "#providers-content",
            Static,
        ).update(table)

    def on_input_submitted(
        self,
        event: Input.Submitted,
    ) -> None:
        mapping = {
            "openrouter-key": "openrouter",
            "gemini-key": "gemini",
        }

        provider = mapping.get(
            event.input.id
        )

        if not provider:
            return

        try:
            ProviderService().set_api_key(
                provider,
                event.value,
            )

            event.input.value = ""

            self.notify(
                f"{provider} configured securely."
            )

            self._refresh()

        except Exception as exc:
            self.notify(
                str(exc),
                severity="error",
            )


class LegacyProjectManagerScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()

        yield Static(
            "",
            id="projects-content",
        )

        yield Input(
            placeholder=(
                r"Local repository path, e.g. C:\Projects\Vendify"
            ),
            id="project-path",
        )

        yield Footer()

    def on_mount(self) -> None:
        self._refresh()

        self.query_one(
            "#project-path",
            Input,
        ).focus()

    def action_back(self) -> None:
        self.app.pop_screen()

    def _refresh(self) -> None:
        projects = (
            ProjectService()
            .list_recent()
        )

        table = Table(
            title="Recent Projects",
            show_lines=True,
        )

        table.add_column("Project")
        table.add_column("Path")

        if projects:
            for project in projects:
                table.add_row(
                    project.name,
                    project.path,
                )
        else:
            table.add_row(
                "-",
                "No recent projects.",
            )

        self.query_one(
            "#projects-content",
            Static,
        ).update(table)

    def on_input_submitted(
        self,
        event: Input.Submitted,
    ) -> None:
        if event.input.id != "project-path":
            return

        try:
            root = (
                ProjectService()
                .open_project(
                    event.value
                )
            )

            self.app.project = root
            self.app.sub_title = root.name

            if hasattr(
                self.app,
                "action_refresh",
            ):
                self.app.action_refresh()

            event.input.value = ""

            self.notify(
                f"Current project: {root.name}"
            )

            self._refresh()

        except Exception as exc:
            self.notify(
                str(exc),
                severity="error",
            )

class AICompanyTUI(App):
    TITLE = "AI Company OS"

    CSS = """
    Screen {
        layout: vertical;
    }

    #main {
        height: 1fr;
    }

    #nav {
        width: 26;
        min-width: 22;
        border: round $accent;
    }

    #content-scroll {
        width: 1fr;
        border: round $accent;
        padding: 1 2;
    }

    #content-title {
        text-style: bold;
        margin-bottom: 1;
    }

    #content {
        width: 1fr;
    }

    TasksScreen {
        layout: vertical;
    }

    #tasks-heading {
        height: auto;
        padding: 1 2;
        text-style: bold;
    }

    #task-list {
        height: 1fr;
        margin: 0 2 1 2;
        border: round $accent;
    }

    #task-detail-scroll {
        height: 1fr;
        padding: 1 2;
    }

    #task-detail {
        width: 100%;
    }

    AgentsScreen {
        layout: vertical;
    }

    #agents-heading {
        height: auto;
        padding: 1 2;
        text-style: bold;
    }

    #agent-list {
        height: 1fr;
        margin: 0 2 1 2;
        border: round $accent;
    }

    #agent-detail-scroll {
        height: 1fr;
        padding: 1 2;
    }

    #agent-detail {
        width: 100%;
    }
    """

    BINDINGS = [
        Binding(
            "q",
            "quit",
            "Salir / Quit",
        ),
        Binding(
            "r",
            "refresh_data",
            "Actualizar / Refresh",
        ),
        Binding(
            "f1",
            "open_help",
            "Ayuda / Help",
        ),
        Binding(
            "f2",
            "toggle_language",
            "ES / EN",
        ),
    ]

    def __init__(self, project: Path) -> None:
        super().__init__()

        self.language = "es"
        self.current_view = "overview"

        self.project = project
        self.snapshot = None
        self.tasks = []
        self.handoff_records = []
        self.runtime_source = None
        self.activity_events = []
        self.workflow_data = None
        self.doctor_findings = []

    def compose(self) -> ComposeResult:
        yield Header()

        with Horizontal(id="main"):
            yield ListView(
                *[
                    ListItem(
                        Label(self._nav_label(view)),
                        id=f"nav-{view}",
                    )
                    for label, view in NAVIGATION
                ],
                id="nav",
            )

            with VerticalScroll(id="content-scroll"):
                yield Static(
                    self._nav_label("overview"),
                    id="content-title",
                )

                yield Static(
                    id="content",
                )

        yield Footer()

    def on_mount(self) -> None:
        self._load_data()

        nav = self.query_one(
            "#nav",
            ListView,
        )

        nav.index = 0
        nav.focus()

        self._show_view("overview")

    def _load_data(self) -> None:
        self.snapshot = StatusService().get_status(
            self.project
        )

        self.project = Path(
            self.snapshot.project.root
        )

        self.tasks = TaskService().list_tasks(
            self.project
        )

        self.doctor_findings = DoctorService().get_findings(self.project)

        self.workflow_data = WorkflowService().get_workflow(self.project)

        self.activity_events = ActivityService().get_activity(self.project)

        self.handoff_records = HandoffService().get_handoffs(self.project)
        self.runtime_source = RuntimeService().get_runtime_source(self.project)

        self.sub_title = self.project.name

    def on_list_view_selected(
        self,
        event: ListView.Selected,
    ) -> None:
        if event.list_view.id != "nav":
            return

        index = event.list_view.index

        if index is None:
            return

        if index < 0 or index >= len(NAVIGATION):
            return

        _, view = NAVIGATION[index]

        if view == "command":
            self.push_screen(
                CommandCenterScreen()
            )
            return

        if view == "projects":
            self.push_screen(
                ProjectManagerScreen()
            )
            return

        if view == "providers":
            self.push_screen(
                ProvidersScreen()
            )
            return
        if view == "plans":
            self.push_screen(
                WorkRequestsScreen()
            )
            return

        if view == "tasks":
            self.push_screen(
                TasksScreen(self.tasks)
            )
            return

        if view == "agents":
            self.push_screen(
                AgentsScreen(
                    self.snapshot.agents,
                    self.tasks,
                )
            )
            return

        if view == "help":
            self.push_screen(
                HelpScreen()
            )
            return

        self._show_view(view)

    def _show_view(
        self,
        view: str,
    ) -> None:
        self.current_view = view

        titles = {
            key: self._nav_label(key)
            for _label, key in NAVIGATION
        }

        self.query_one(
            "#content-title",
            Static,
        ).update(
            titles.get(view, view)
        )

        renderers = {
            "overview": self._render_overview,
            "agents": self._render_agents,
            "workflow": self._render_workflow,
            "activity": self._render_activity,
            "handoffs": self._render_handoffs,
            "runtime": self._render_runtime,
            "blockers": self._render_blockers,
            "gates": self._render_gates,
            "doctor": self._render_doctor,
            "diagnostics": self._render_diagnostics,
        }

        renderer = renderers.get(view)

        if renderer is None:
            return

        self.query_one(
            "#content",
            Static,
        ).update(
            renderer()
        )

    def _render_overview(self):
        snapshot = self.snapshot

        project = Table(
            show_header=False,
            box=None,
            padding=(0, 2),
        )

        project.add_column()
        project.add_column()

        phase = snapshot.project.phase.value

        if snapshot.project.phase_derived:
            phase += " (derived)"

        project.add_row(
            "Project",
            snapshot.project.name,
        )

        project.add_row(
            "Phase",
            phase,
        )

        project.add_row(
            "Objective",
            snapshot.project.objective or "-",
        )

        project.add_row(
            "Repository",
            snapshot.project.root,
        )

        counts = Table(
            title="Task Summary"
        )

        counts.add_column("Status")
        counts.add_column(
            "Count",
            justify="right",
        )

        overview = snapshot.tasks

        values = [
            ("BACKLOG", overview.backlog),
            ("READY", overview.ready),
            ("ACTIVE", overview.active),
            ("REVIEW", overview.review),
            ("QA", overview.qa),
            ("SECURITY", overview.security),
            ("BLOCKED", overview.blocked),
            ("DONE", overview.done),
        ]

        for name, value in values:
            counts.add_row(
                name,
                str(value),
            )

        return Group(
            project,
            Text(""),
            counts,
        )

    def _render_agents(self):
        table = Table()

        table.add_column("Agent")
        table.add_column("Work state")
        table.add_column("Runtime")
        table.add_column("Tasks")

        for agent in self.snapshot.agents:
            table.add_row(
                agent.display_name,
                agent.work_state.value,
                agent.runtime_state.value,
                ", ".join(
                    agent.current_task_ids
                ) or "-",
            )

        return table

    def _render_workflow(self):
        workflow = self.workflow_data

        if workflow is None:
            return Text(
                "Workflow data unavailable."
            )

        table = Table()

        table.add_column("Task")
        table.add_column("Status")
        table.add_column("Execution")
        table.add_column("Owner")
        table.add_column("Waiting for")

        for node in workflow.nodes:
            table.add_row(
                node.task_id,
                node.status,
                node.execution_state,
                node.owner,
                ", ".join(
                    node.unmet_dependencies
                ) or "-",
            )

        parallel = (
            ", ".join(
                workflow.parallel_now
            )
            or "None"
        )

        waiting = (
            ", ".join(
                workflow.waiting
            )
            or "None"
        )

        edges = (
            "\n".join(
                f"{edge.source} -> {edge.target}"
                for edge in workflow.edges
            )
            or "No dependency edges."
        )

        return Group(
            table,
            Text(""),
            Panel(
                parallel,
                title="Can advance now",
            ),
            Text(""),
            Panel(
                waiting,
                title="Waiting",
            ),
            Text(""),
            Panel(
                edges,
                title="Dependency DAG",
            ),
        )
    def _render_activity(self):
        events = self.activity_events[:100]

        if not events:
            return Text(
                "No persisted activity found."
            )

        table = Table()

        table.add_column(
            "Time",
            no_wrap=True,
        )

        table.add_column(
            "Task",
            no_wrap=True,
        )

        table.add_column(
            "Kind",
            no_wrap=True,
        )

        table.add_column(
            "Owner",
            no_wrap=True,
        )

        table.add_column(
            "Activity",
        )

        for event in events:
            timestamp = (
                event.timestamp.isoformat(
                    timespec="seconds"
                )
                if event.timestamp
                else "-"
            )

            table.add_row(
                timestamp,
                event.task_id,
                event.kind,
                event.owner,
                event.message,
            )

        return table
    def _render_handoffs(self):
        records = self.handoff_records

        if not records:
            return Text(
                "No persisted handoff evidence found."
            )

        table = Table()

        table.add_column("Task")
        table.add_column("Kind")
        table.add_column("From")
        table.add_column("To")
        table.add_column("State")
        table.add_column("Message")

        for record in records:
            table.add_row(
                record.task_id,
                record.kind,
                record.from_actor or "-",
                record.to_actor,
                "STALE" if record.stale else "OK",
                record.message,
            )

        return table

    def _render_runtime(self):
        runtime = self.runtime_source

        if runtime is None:
            return Text(
                "Runtime information unavailable."
            )

        table = Table(
            show_header=False
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
            "Parsed events",
            str(runtime.parsed_event_count),
        )

        table.add_row(
            "Authoritative live state",
            str(runtime.authoritative_live_state),
        )

        return Group(
            table,
            Text(""),
            Panel(
                runtime.message,
                title="Runtime status",
            ),
        )
    def _render_blockers(self):
        blockers = self.snapshot.blockers

        if not blockers:
            return Text(
                "No active blockers."
            )

        table = Table()

        table.add_column("Task")
        table.add_column("Reason")

        for blocker in blockers:
            table.add_row(
                blocker.task_id,
                blocker.reason,
            )

        return table

    def _render_gates(self):
        table = Table()

        table.add_column("Gate")
        table.add_column("State")
        table.add_column("Stale")

        for gate in self.snapshot.gates:
            table.add_row(
                gate.name,
                gate.state.value,
                "YES" if gate.stale else "NO",
            )

        return table

    def _render_doctor(self):
        findings = self.doctor_findings

        if not findings:
            return Text(
                "No doctor findings."
            )

        table = Table()

        table.add_column("Severity")
        table.add_column("Code")
        table.add_column("Message")

        for finding in findings:
            table.add_row(
                finding.severity.value,
                finding.code,
                finding.message,
            )

        return table
    def _render_diagnostics(self):
        diagnostics = self.snapshot.diagnostics

        if not diagnostics:
            return Text(
                "No diagnostics."
            )

        table = Table()

        table.add_column("Severity")
        table.add_column("Code")
        table.add_column("Message")

        for diagnostic in diagnostics:
            table.add_row(
                diagnostic.severity.value,
                diagnostic.code,
                diagnostic.message,
            )

        return table

    def _nav_label(
        self,
        view: str,
    ) -> str:
        return navigation_label(
            self.language,
            view,
        )

    def action_open_help(self) -> None:
        current = self.screen

        if (
            current.__class__.__name__
            == "HelpScreen"
        ):
            return

        self.push_screen(
            HelpScreen()
        )

    def action_toggle_language(self) -> None:
        self.language = (
            "en"
            if self.language == "es"
            else "es"
        )

        self._refresh_navigation_language()

        current = self.screen

        refresh_language = getattr(
            current,
            "refresh_language",
            None,
        )

        if callable(refresh_language):
            refresh_language()

        language_name = (
            "English"
            if self.language == "en"
            else "Espa?ol"
        )

        self.notify(
            f"Interface: {language_name}"
        )

    def _refresh_navigation_language(
        self,
    ) -> None:
        for _label, view in NAVIGATION:
            matches = list(
                self.query(
                    f"#nav-{view} Label"
                )
            )

            if matches:
                matches[0].update(
                    self._nav_label(view)
                )

        titles = list(
            self.query(
                "#content-title"
            )
        )

        if titles:
            titles[0].update(
                self._nav_label(
                    self.current_view
                )
            )

    def action_refresh_data(self) -> None:
        try:
            self._load_data()
            self._show_view("overview")

            self.notify(
                "Project data refreshed."
            )

        except Exception as exc:
            self.notify(
                str(exc),
                severity="error",
            )


def run_tui() -> None:
    config = ConfigService()

    project = config.get_current_project()

    if project is None:
        project = Path.cwd()

    AICompanyTUI(project).run(mouse=False)
