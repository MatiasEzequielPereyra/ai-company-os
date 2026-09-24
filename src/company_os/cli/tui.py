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

from company_os.cli.widgets import CircularListView
from company_os.application.config_service import ConfigService
from company_os.cli.screens.projects import ProjectManagerScreen
from company_os.cli.screens.work_requests import WorkRequestsScreen
from company_os.cli.screens.help import HelpScreen
from company_os.cli.i18n import navigation_label, ui_text
from company_os.cli.interface_settings import InterfaceSettingsService
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
    ("Settings", "settings"),
    ("Help / Guide", "help"),
]


def _language_for(widget) -> str:
    language = getattr(
        widget,
        "language",
        None,
    )

    if language:
        return language

    app = getattr(
        widget,
        "app",
        None,
    )

    return getattr(
        app,
        "language",
        "es",
    )


def _t(widget, key: str) -> str:
    return ui_text(
        _language_for(widget),
        key,
    )


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
        metadata.add_row(_t(self, "title"), task.title)
        metadata.add_row(_t(self, "status"), task.status.value)
        metadata.add_row(_t(self, "priority"), task.priority.value)
        metadata.add_row(_t(self, "owner"), task.owner)

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

        metadata.add_row(_t(self, "created"), created)
        metadata.add_row(_t(self, "updated"), updated)

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
            Panel(objective, title=_t(self, "objective")),
            Text(""),
            Panel(dependencies, title=_t(self, "dependencies")),
            Text(""),
            Panel(evidence, title=_t(self, "evidence")),
            Text(""),
            Panel(
                str(task.source_path),
                title=_t(self, "source"),
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
            _t(self, "tasks_heading"),
            id="tasks-heading",
        )

        yield CircularListView(
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

    def refresh_language(self) -> None:
        heading = self.query_one(
            "#tasks-heading",
            Static,
        )

        heading.update(
            _t(self, "tasks_heading")
        )

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

    def refresh_language(self) -> None:
        self.query_one(
            "#agent-detail",
            Static,
        ).update(
            self._render_agent()
        )

    def _render_agent(self):
        agent = self.agent_data

        metadata = Table(
            title=agent.display_name,
            show_header=False,
            box=None,
            padding=(0, 2),
        )

        metadata.add_column(
            style="bold"
        )
        metadata.add_column()

        metadata.add_row(
            "ID",
            agent.id,
        )

        metadata.add_row(
            _t(
                self,
                "agent_work_label",
            ),
            agent.work_state.value,
        )

        metadata.add_row(
            _t(
                self,
                "agent_runtime_label",
            ),
            agent.runtime_state.value,
        )

        current_tasks = (
            ", ".join(
                agent.current_task_ids
            )
            if agent.current_task_ids
            else "-"
        )

        metadata.add_row(
            _t(
                self,
                "current_tasks",
            ),
            current_tasks,
        )

        owned_tasks = [
            task
            for task in self.all_tasks
            if (
                task.owner.casefold()
                == agent.id.casefold()
            )
        ]

        tasks_table = Table(
            title=_t(
                self,
                "agent_repository_tasks",
            ),
            show_lines=True,
        )

        tasks_table.add_column("ID")
        tasks_table.add_column(
            _t(self, "status")
        )
        tasks_table.add_column(
            _t(self, "priority")
        )
        tasks_table.add_column(
            _t(self, "title")
        )

        for task in owned_tasks:
            tasks_table.add_row(
                task.id,
                task.status.value,
                task.priority.value,
                task.title,
            )

        if owned_tasks:
            assigned_content = (
                tasks_table
            )
        else:
            assigned_content = Text(
                _t(
                    self,
                    "agent_no_repository_tasks",
                )
            )

        if (
            agent.runtime_state.value
            == "UNKNOWN"
        ):
            runtime_note = _t(
                self,
                "agent_runtime_unknown",
            )
        else:
            runtime_note = _t(
                self,
                "agent_runtime_known",
            )

        return Group(
            metadata,
            Text(""),
            assigned_content,
            Text(""),
            Panel(
                runtime_note,
                title=_t(
                    self,
                    "agent_runtime_evidence",
                ),
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
            _t(self, "agents_heading"),
            id="agents-heading",
        )

        yield CircularListView(
            *[
                ListItem(
                    Label(
                        f"{agent.display_name} | "
                        f"{_t(self, 'agent_work_label')}: "
                        f"{agent.work_state.value} | "
                        f"{_t(self, 'agent_runtime_label')}: "
                        f"{agent.runtime_state.value} | "
                        f"{_t(self, 'tasks')}: "
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

    def refresh_language(self) -> None:
        self.query_one(
            "#agents-heading",
            Static,
        ).update(
            _t(self, "agents_heading")
        )

        labels = list(
            self.query(
                "#agent-list Label"
            )
        )

        for label, agent in zip(
            labels,
            self.agent_items,
        ):
            tasks = (
                ", ".join(
                    agent.current_task_ids
                )
                if agent.current_task_ids
                else "-"
            )

            label.update(
                f"{agent.display_name} | "
                f"{_t(self, 'agent_work_label')}: "
                f"{agent.work_state.value} | "
                f"{_t(self, 'agent_runtime_label')}: "
                f"{agent.runtime_state.value} | "
                f"{_t(self, 'tasks')}: "
                f"{tasks}"
            )

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
        Binding(
            "escape",
            "back",
            "Atras / Back",
        ),
        Binding(
            "r",
            "refresh_providers",
            "Actualizar / Refresh",
        ),
    ]

    def compose(self) -> ComposeResult:
        yield Header()

        yield Static(
            "",
            id="providers-content",
        )

        yield Static(
            "",
            id="providers-readiness",
        )

        yield Input(
            placeholder=_t(
                self,
                "providers_openrouter_placeholder",
            ),
            password=True,
            id="openrouter-key",
        )

        yield Input(
            placeholder=_t(
                self,
                "providers_gemini_placeholder",
            ),
            password=True,
            id="gemini-key",
        )

        yield Static(
            _t(
                self,
                "providers_security_note",
            ),
            id="providers-security-note",
        )

        yield Static(
            _t(
                self,
                "providers_auto_policy",
            ),
            id="providers-auto-policy",
        )

        yield Static(
            _t(
                self,
                "providers_future_note",
            ),
            id="providers-future-note",
        )

        yield Footer()

    def on_mount(self) -> None:
        self._refresh()

    def action_back(self) -> None:
        self.app.pop_screen()

    def action_refresh_providers(
        self,
    ) -> None:
        self._refresh()

    def refresh_language(self) -> None:
        self.query_one(
            "#openrouter-key",
            Input,
        ).placeholder = _t(
            self,
            "providers_openrouter_placeholder",
        )

        self.query_one(
            "#gemini-key",
            Input,
        ).placeholder = _t(
            self,
            "providers_gemini_placeholder",
        )

        self.query_one(
            "#providers-security-note",
            Static,
        ).update(
            _t(
                self,
                "providers_security_note",
            )
        )

        self.query_one(
            "#providers-auto-policy",
            Static,
        ).update(
            _t(
                self,
                "providers_auto_policy",
            )
        )

        self.query_one(
            "#providers-future-note",
            Static,
        ).update(
            _t(
                self,
                "providers_future_note",
            )
        )

        self._refresh()

    @staticmethod
    def _provider_kind(
        name: str,
    ) -> str:
        normalized = name.casefold()

        if "ollama" in normalized:
            return "local"

        return "cloud"

    @staticmethod
    def _provider_visible(
        names: list[str],
        *terms: str,
    ) -> bool:
        return any(
            any(
                term in name
                for term in terms
            )
            for name in names
        )

    def _refresh(self) -> None:
        statuses = (
            ProviderService()
            .get_statuses()
        )

        table = Table(
            title=_t(
                self,
                "providers_title",
            ),
            show_lines=True,
        )

        table.add_column(
            _t(
                self,
                "providers_provider",
            )
        )

        table.add_column(
            _t(
                self,
                "providers_kind",
            )
        )

        table.add_column(
            _t(
                self,
                "providers_configured",
            )
        )

        table.add_column(
            _t(
                self,
                "providers_source",
            )
        )

        table.add_column(
            _t(
                self,
                "providers_notes",
            )
        )

        normalized_names = []

        for provider in statuses:
            normalized_names.append(
                provider.name.casefold()
            )

            kind = self._provider_kind(
                provider.name
            )

            table.add_row(
                provider.name,
                (
                    _t(
                        self,
                        "providers_local",
                    )
                    if kind == "local"
                    else _t(
                        self,
                        "providers_cloud",
                    )
                ),
                (
                    _t(self, "yes")
                    if provider.configured
                    else _t(self, "no")
                ),
                provider.source,
                provider.description,
            )

        integrations = [
            (
                "OpenRouter",
                self._provider_visible(
                    normalized_names,
                    "openrouter",
                ),
            ),
            (
                "Gemini",
                self._provider_visible(
                    normalized_names,
                    "gemini",
                ),
            ),
            (
                "DeepSeek",
                self._provider_visible(
                    normalized_names,
                    "deepseek",
                ),
            ),
            (
                "Grok / xAI",
                self._provider_visible(
                    normalized_names,
                    "grok",
                    "xai",
                    "x.ai",
                ),
            ),
            (
                "Ollama",
                self._provider_visible(
                    normalized_names,
                    "ollama",
                ),
            ),
        ]

        readiness = "\n".join(
            (
                f"{name}: "
                + (
                    _t(
                        self,
                        "providers_visible_core",
                    )
                    if visible
                    else _t(
                        self,
                        "providers_waiting_core",
                    )
                )
            )
            for name, visible
            in integrations
        )

        self.query_one(
            "#providers-content",
            Static,
        ).update(table)

        self.query_one(
            "#providers-readiness",
            Static,
        ).update(
            Panel(
                readiness,
                title=_t(
                    self,
                    "providers_readiness",
                ),
            )
        )

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

        value = event.value.strip()

        if not value:
            return

        try:
            ProviderService().set_api_key(
                provider,
                value,
            )

            event.input.value = ""

            self.notify(
                f"{provider} "
                f"{_t(self, 'providers_configured_notify')}."
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

        Binding(
            "left",
            "go_back",
            "Atras / Back",
            priority=True,
        ),
        Binding(
            "right",
            "activate_focused",
            "Abrir / Open",
            priority=True,
        ),
    ]

    def __init__(self, project: Path) -> None:
        super().__init__()

        self.interface_settings = (
            InterfaceSettingsService()
        )

        self.language = (
            self.interface_settings
            .load_language()
        )

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
            yield CircularListView(
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
            "settings": self._render_settings,
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
            phase += f" ({_t(self, 'derived')})"

        project.add_row(
            _t(self, "overview_project"),
            snapshot.project.name,
        )

        project.add_row(
            _t(self, "overview_phase"),
            phase,
        )

        project.add_row(
            _t(self, "overview_objective"),
            snapshot.project.objective or "-",
        )

        project.add_row(
            _t(self, "overview_repository"),
            snapshot.project.root,
        )

        counts = Table(
            title=_t(self, "overview_task_summary")
        )

        counts.add_column(_t(self, "status"))
        counts.add_column(
            _t(self, "overview_count"),
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
        agents = list(
            self.snapshot.agents
        )

        table = Table(
            title=_t(
                self,
                "agents_view_title",
            ),
            show_lines=True,
        )

        table.add_column(
            _t(self, "agent")
        )
        table.add_column(
            _t(
                self,
                "work_state",
            )
        )
        table.add_column(
            _t(
                self,
                "runtime_state",
            )
        )
        table.add_column(
            _t(self, "tasks")
        )

        runtime_counts: dict[str, int] = {}
        with_tasks = 0

        for agent in agents:
            runtime_value = (
                agent.runtime_state.value
            )

            runtime_counts[
                runtime_value
            ] = (
                runtime_counts.get(
                    runtime_value,
                    0,
                )
                + 1
            )

            if agent.current_task_ids:
                with_tasks += 1

            table.add_row(
                agent.display_name,
                agent.work_state.value,
                runtime_value,
                ", ".join(
                    agent.current_task_ids
                ) or "-",
            )

        summary = Table(
            title=_t(
                self,
                "agents_summary",
            ),
            show_header=False,
            box=None,
        )

        summary.add_column()
        summary.add_column(
            justify="right"
        )

        summary.add_row(
            _t(
                self,
                "agents_total",
            ),
            str(len(agents)),
        )

        summary.add_row(
            _t(
                self,
                "agents_with_tasks",
            ),
            str(with_tasks),
        )

        runtime_distribution = (
            "\n".join(
                f"{state}: {count}"
                for state, count
                in sorted(
                    runtime_counts.items()
                )
            )
            or "-"
        )

        return Group(
            summary,
            Text(""),
            Panel(
                runtime_distribution,
                title=_t(
                    self,
                    "agents_runtime_distribution",
                ),
            ),
            Text(""),
            table,
        )

    def _render_workflow(self):
        workflow = self.workflow_data

        if workflow is None:
            return Text(
                _t(
                    self,
                    "workflow_unavailable",
                )
            )

        nodes = list(workflow.nodes)

        table = Table(
            title=_t(
                self,
                "workflow_map_title",
            ),
            show_lines=True,
        )

        table.add_column(
            _t(self, "task")
        )
        table.add_column(
            _t(self, "status")
        )
        table.add_column(
            _t(self, "execution")
        )
        table.add_column(
            _t(self, "owner")
        )
        table.add_column(
            _t(self, "waiting_for")
        )

        for node in nodes:
            table.add_row(
                node.task_id,
                node.status,
                node.execution_state,
                node.owner,
                (
                    ", ".join(
                        node.unmet_dependencies
                    )
                    or "-"
                ),
            )

        runnable = list(
            workflow.parallel_now
        )

        waiting = list(
            workflow.waiting
        )

        blocked = [
            node.task_id
            for node in nodes
            if node.status == "BLOCKED"
        ]

        completed = [
            node.task_id
            for node in nodes
            if node.status == "DONE"
        ]

        def display(items) -> str:
            return (
                ", ".join(items)
                if items
                else _t(
                    self,
                    "workflow_none",
                )
            )

        summary = Table(
            title=_t(
                self,
                "workflow_summary_title",
            ),
            show_header=False,
            box=None,
        )

        summary.add_column()
        summary.add_column(
            justify="right"
        )

        summary.add_row(
            _t(
                self,
                "workflow_runnable",
            ),
            str(len(runnable)),
        )

        summary.add_row(
            _t(
                self,
                "workflow_waiting_tasks",
            ),
            str(len(waiting)),
        )

        summary.add_row(
            _t(
                self,
                "workflow_blocked_tasks",
            ),
            str(len(blocked)),
        )

        summary.add_row(
            _t(
                self,
                "workflow_done_tasks",
            ),
            str(len(completed)),
        )

        edges = (
            "\n".join(
                f"{edge.source} -> {edge.target}"
                for edge in workflow.edges
            )
            or _t(
                self,
                "workflow_no_edges",
            )
        )

        return Group(
            table,
            Text(""),
            summary,
            Text(""),
            Panel(
                display(runnable),
                title=_t(
                    self,
                    "workflow_runnable",
                ),
            ),
            Text(""),
            Panel(
                display(waiting),
                title=_t(
                    self,
                    "workflow_waiting_tasks",
                ),
            ),
            Text(""),
            Panel(
                display(blocked),
                title=_t(
                    self,
                    "workflow_blocked_tasks",
                ),
            ),
            Text(""),
            Panel(
                display(completed),
                title=_t(
                    self,
                    "workflow_done_tasks",
                ),
            ),
            Text(""),
            Panel(
                edges,
                title=_t(
                    self,
                    "dependency_dag",
                ),
            ),
        )

    def _render_activity(self):
        events = self.activity_events[:100]

        if not events:
            return Text(
                _t(self, "no_activity")
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
                _t(self, "no_handoffs")
            )

        table = Table()

        table.add_column("Task")
        table.add_column(_t(self, "kind"))
        table.add_column(_t(self, "from"))
        table.add_column(_t(self, "to"))
        table.add_column("State")
        table.add_column(_t(self, "message"))

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
                _t(
                    self,
                    "runtime_unavailable",
                )
            )

        table = Table(
            title=_t(
                self,
                "runtime_overview",
            ),
            show_header=False,
            box=None,
            padding=(0, 2),
        )

        table.add_column()
        table.add_column()

        table.add_row(
            _t(
                self,
                "runtime_source_path",
            ),
            str(runtime.path),
        )

        table.add_row(
            _t(
                self,
                "runtime_available_label",
            ),
            str(runtime.available),
        )

        table.add_row(
            _t(
                self,
                "runtime_events_label",
            ),
            str(runtime.event_count),
        )

        table.add_row(
            _t(
                self,
                "runtime_parsed_label",
            ),
            str(
                runtime.parsed_event_count
            ),
        )

        table.add_row(
            _t(
                self,
                "runtime_live_label",
            ),
            str(
                runtime.authoritative_live_state
            ),
        )

        authority_message = (
            _t(
                self,
                "runtime_authoritative",
            )
            if runtime.authoritative_live_state
            else _t(
                self,
                "runtime_not_authoritative",
            )
        )

        return Group(
            table,
            Text(""),
            Panel(
                authority_message,
                title=_t(
                    self,
                    "runtime_authority",
                ),
            ),
            Text(""),
            Panel(
                runtime.message,
                title=_t(
                    self,
                    "runtime_adapter_message",
                ),
            ),
        )

    def _render_blockers(self):
        blockers = self.snapshot.blockers

        if not blockers:
            return Text(
                _t(self, "no_blockers")
            )

        table = Table()

        table.add_column("Task")
        table.add_column(_t(self, "reason"))

        for blocker in blockers:
            table.add_row(
                blocker.task_id,
                blocker.reason,
            )

        return table

    def _render_gates(self):
        gates = list(
            self.snapshot.gates
        )

        table = Table(
            title=_t(
                self,
                "gates_title",
            ),
            show_lines=True,
        )

        table.add_column(
            _t(self, "gate")
        )

        table.add_column(
            _t(
                self,
                "gates_result",
            )
        )

        table.add_column(
            _t(
                self,
                "gates_evidence",
            )
        )

        stale_gates = []

        for gate in gates:
            evidence = (
                _t(
                    self,
                    "gates_stale",
                )
                if gate.stale
                else _t(
                    self,
                    "gates_current",
                )
            )

            if gate.stale:
                stale_gates.append(
                    gate.name
                )

            table.add_row(
                gate.name,
                gate.state.value,
                evidence,
            )

        if stale_gates:
            attention = (
                _t(
                    self,
                    "gates_stale_intro",
                )
                + "\n\n"
                + "\n".join(
                    f"- {name}"
                    for name in stale_gates
                )
            )
        else:
            attention = _t(
                self,
                "gates_no_attention",
            )

        return Group(
            table,
            Text(""),
            Panel(
                attention,
                title=_t(
                    self,
                    "gates_attention",
                ),
            ),
            Text(""),
            Panel(
                _t(
                    self,
                    "gates_interpretation_body",
                ),
                title=_t(
                    self,
                    "gates_interpretation",
                ),
            ),
        )

    def _render_doctor(self):
        findings = self.doctor_findings

        if not findings:
            return Text(
                _t(self, "no_doctor_findings")
            )

        table = Table()

        table.add_column(_t(self, "severity"))
        table.add_column(_t(self, "code"))
        table.add_column(_t(self, "message"))

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
                _t(self, "no_diagnostics")
            )

        table = Table()

        table.add_column(_t(self, "severity"))
        table.add_column(_t(self, "code"))
        table.add_column(_t(self, "message"))

        for diagnostic in diagnostics:
            table.add_row(
                diagnostic.severity.value,
                diagnostic.code,
                diagnostic.message,
            )

        return table

    def _render_settings(self):
        language_name = (
            "Espanol"
            if self.language == "es"
            else "English"
        )

        table = Table(
            title=_t(
                self,
                "settings_title",
            ),
            show_header=False,
            box=None,
        )

        table.add_column()
        table.add_column()

        table.add_row(
            _t(
                self,
                "settings_language",
            ),
            language_name,
        )

        table.add_row(
            _t(
                self,
                "settings_file",
            ),
            str(
                self.interface_settings.path
            ),
        )

        return Group(
            table,
            Text(""),
            Panel(
                _t(
                    self,
                    "settings_change_language",
                ),
                title="F2",
            ),
            Text(""),
            Panel(
                _t(
                    self,
                    "settings_scope",
                ),
                title=_t(
                    self,
                    "settings_title",
                ),
            ),
        )

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
        current_name = (
            current.__class__.__name__
        )

        if current_name == "HelpScreen":
            return

        screen_sections = {
            "ProjectManagerScreen": "getting-started",
            "CommandCenterScreen": "getting-started",
            "CommandProposalScreen": "getting-started",
            "PlanPreviewScreen": "getting-started",
            "PreparePlanScreen": "plans",
            "WorkRequestsScreen": "plans",
            "DeleteWorkRequestScreen": "plans",
            "PlanControlScreen": "plan-control",
            "TasksScreen": "tasks",
            "TaskDetailScreen": "tasks",
            "AgentsScreen": "agents",
            "AgentDetailScreen": "agents",
            "ProvidersScreen": "providers",
        }

        view_sections = {
            "overview": "getting-started",
            "command": "getting-started",
            "projects": "getting-started",
            "plans": "plans",
            "providers": "providers",
            "tasks": "tasks",
            "agents": "agents",
            "workflow": "workflow",
            "gates": "quality-gates",
            "blockers": "troubleshooting",
            "activity": "troubleshooting",
            "handoffs": "troubleshooting",
            "runtime": "troubleshooting",
            "doctor": "troubleshooting",
            "diagnostics": "troubleshooting",
            "settings": "getting-started",
        }

        section = screen_sections.get(
            current_name
        )

        if section is None:
            section = view_sections.get(
                self.current_view,
                "getting-started",
            )

        self.push_screen(
            HelpScreen(
                initial_section=section,
            )
        )

    def action_toggle_language(self) -> None:
        self.language = (
            "en"
            if self.language == "es"
            else "es"
        )

        try:
            self.interface_settings.save_language(
                self.language
            )
        except Exception as exc:
            self.notify(
                f"Settings save failed: {exc}",
                severity="warning",
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
            else "Espanol"
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


        self._show_view(
            self.current_view
        )

    def action_go_back(self) -> None:
        focused = getattr(
            self.screen,
            "focused",
            None,
        )

        if isinstance(focused, Input):
            action = getattr(
                focused,
                "action_cursor_left",
                None,
            )

            if callable(action):
                action()

            return

        current = self.screen

        action = getattr(
            current,
            "action_back",
            None,
        )

        if callable(action):
            action()

    def action_activate_focused(self) -> None:
        focused = getattr(
            self.screen,
            "focused",
            None,
        )

        if focused is None:
            return

        if isinstance(focused, Input):
            action = getattr(
                focused,
                "action_cursor_right",
                None,
            )

            if callable(action):
                action()

            return

        if isinstance(focused, ListView):
            action = getattr(
                focused,
                "action_select_cursor",
                None,
            )

            if callable(action):
                action()

    def action_refresh_data(self) -> None:
        try:
            self._load_data()
            self._show_view("overview")

            self.notify(
                (
                "Datos del proyecto actualizados."
                if self.language == "es"
                else "Project data refreshed."
            )
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

    AICompanyTUI(project).run()
