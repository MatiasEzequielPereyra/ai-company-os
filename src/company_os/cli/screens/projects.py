from __future__ import annotations

from pathlib import Path

from textual.app import ComposeResult
from textual.binding import Binding
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

from company_os.application.activity_service import ActivityService
from company_os.application.doctor_service import DoctorService
from company_os.application.handoff_service import HandoffService
from company_os.application.project_service import ProjectService
from company_os.application.runtime_service import RuntimeService
from company_os.application.status_service import StatusService
from company_os.application.task_service import TaskService
from company_os.application.workflow_service import WorkflowService


class ProjectManagerScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("r", "refresh_projects", "Refresh"),
    ]

    def __init__(self) -> None:
        super().__init__()
        self.projects = []

    def compose(self) -> ComposeResult:
        yield Header()

        yield Static(
            "PROJECTS\n"
            "UP/DOWN = Select   Enter = Open   "
            "R = Refresh   Esc = Back",
            id="projects-heading",
        )

        yield ListView(
            id="projects-list",
        )

        yield Static(
            "Or enter a local repository path:",
            id="project-path-heading",
        )

        yield Input(
            placeholder=r"C:\Users\you\Projects\MyProject",
            id="project-path",
        )

        yield Footer()

    def on_mount(self) -> None:
        self._refresh_projects()

    def action_back(self) -> None:
        self.app.pop_screen()

    def action_refresh_projects(self) -> None:
        self._refresh_projects()

    def _refresh_projects(self) -> None:
        self.projects = (
            ProjectService()
            .list_recent()
        )

        project_list = self.query_one(
            "#projects-list",
            ListView,
        )

        project_list.clear()

        current = Path(
            self.app.project
        ).resolve()

        selected_index = 0

        for index, project in enumerate(
            self.projects
        ):
            project_path = Path(
                project.path
            ).expanduser().resolve()

            active = project_path == current

            if active:
                selected_index = index

            marker = (
                "[ACTIVE] "
                if active
                else ""
            )

            project_list.append(
                ListItem(
                    Label(
                        f"{marker}{project.name}\n"
                        f"{project.path}\n"
                        + ("-" * 60)
                    )
                )
            )

        if self.projects:
            project_list.index = (
                selected_index
            )

        else:
            project_list.append(
                ListItem(
                    Label(
                        "No recent projects."
                    )
                )
            )

        project_list.focus()

    def _load_tasks(
        self,
        root: Path,
    ):
        service = TaskService()

        if hasattr(
            service,
            "list_tasks",
        ):
            return service.list_tasks(
                root
            )

        if hasattr(
            service,
            "get_tasks",
        ):
            return service.get_tasks(
                root
            )

        raise RuntimeError(
            "TaskService has no supported "
            "task listing method."
        )

    def _reload_application_state(
        self,
        root: Path,
    ) -> None:
        app = self.app

        app.project = root
        app.sub_title = root.name

        app.snapshot = (
            StatusService()
            .get_status(root)
        )

        app.tasks = self._load_tasks(
            root
        )

        app.workflow_data = (
            WorkflowService()
            .get_workflow(root)
        )

        app.activity_events = (
            ActivityService()
            .get_activity(root)
        )

        app.handoff_records = (
            HandoffService()
            .get_handoffs(root)
        )

        app.runtime_source = (
            RuntimeService()
            .get_runtime_source(root)
        )

        app.doctor_findings = (
            DoctorService()
            .get_findings(root)
        )

    def _open_project(
        self,
        project_path: str,
    ) -> None:
        try:
            root = (
                ProjectService()
                .open_project(
                    project_path
                )
            )

            self._reload_application_state(
                root
            )

            app = self.app

            self.notify(
                f"Active project: {root.name}"
            )

            app.pop_screen()

            if hasattr(
                app,
                "_show_view",
            ):
                app._show_view(
                    "overview"
                )

            app.refresh(
                layout=True
            )

        except Exception as exc:
            self.notify(
                str(exc),
                severity="error",
            )

    def on_list_view_selected(
        self,
        event: ListView.Selected,
    ) -> None:
        index = event.list_view.index

        if index is None:
            return

        if (
            index < 0
            or index >= len(
                self.projects
            )
        ):
            return

        project = self.projects[
            index
        ]

        self._open_project(
            project.path
        )

    def on_input_submitted(
        self,
        event: Input.Submitted,
    ) -> None:
        if (
            event.input.id
            != "project-path"
        ):
            return

        value = event.value.strip()

        if not value:
            return

        self._open_project(
            value
        )
