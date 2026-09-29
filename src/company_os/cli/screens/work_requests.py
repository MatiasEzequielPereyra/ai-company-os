from __future__ import annotations

from rich.panel import Panel

from textual.app import ComposeResult
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import (
    Footer,
    Header,
    Label,
    ListItem,
    ListView,
    Static,
)

from company_os.application.delete_plan_service import (
    DeletePlanService,
)
from company_os.application.work_request_service import (
    WorkRequestService,
)
from company_os.cli.screens.plan_control import (
    PlanControlScreen,
)


class DeleteWorkRequestScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Cancel"),
        Binding("y", "confirm_delete", "Delete"),
    ]

    def __init__(
        self,
        project_root,
        request,
    ) -> None:
        super().__init__()

        self.project_root = project_root
        self.request = request
        self.service = DeletePlanService()

    def compose(self) -> ComposeResult:
        allowed, reason = (
            self.service.can_delete(
                self.project_root,
                self.request.id,
            )
        )

        yield Header()

        yield Static(
            Panel(
                f"Work Request: {self.request.id}\n\n"
                f"{self.request.objective}\n\n"
                f"{reason}\n\n"
                + (
                    "Y = DELETE permanently\n"
                    "Esc = Cancel"
                    if allowed
                    else
                    "This Work Request cannot be "
                    "hard-deleted.\nEsc = Back"
                ),
                title="Delete Plan",
            )
        )

        yield Footer()

    def action_back(self) -> None:
        self.app.pop_screen()

    def action_confirm_delete(self) -> None:
        try:
            allowed, reason = (
                self.service.can_delete(
                    self.project_root,
                    self.request.id,
                )
            )

            if not allowed:
                self.notify(
                    reason,
                    severity="error",
                )
                return

            result = self.service.delete(
                self.project_root,
                self.request.id,
            )

            self.app.pop_screen()

            current = self.app.screen

            if hasattr(
                current,
                "_refresh",
            ):
                current._refresh()

            self.notify(
                f"{result.work_request_id} deleted."
            )

        except Exception as exc:
            self.notify(
                str(exc),
                severity="error",
            )


class WorkRequestsScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("r", "refresh_requests", "Refresh"),
        Binding("d", "delete_request", "Delete"),
    ]

    def __init__(self) -> None:
        super().__init__()

        self.service = WorkRequestService()
        self.requests = []

    def compose(self) -> ComposeResult:
        yield Header()

        yield Static(
            "PLANS / WORK REQUESTS\n"
            "UP/DOWN = Select   "
            "Enter = Open   "
            "D = Delete   "
            "R = Refresh   "
            "Esc = Back",
            id="work-requests-heading",
        )

        yield ListView(
            id="work-requests-list",
        )

        yield Footer()

    def on_mount(self) -> None:
        self._refresh()

    def action_back(self) -> None:
        self.app.pop_screen()

    def action_refresh_requests(
        self,
    ) -> None:
        self._refresh()

    def _selected_request(self):
        view = self.query_one(
            "#work-requests-list",
            ListView,
        )

        index = view.index

        if index is None:
            return None

        if (
            index < 0
            or index >= len(self.requests)
        ):
            return None

        return self.requests[index]

    def action_delete_request(self) -> None:
        request = self._selected_request()

        if request is None:
            return

        self.app.push_screen(
            DeleteWorkRequestScreen(
                self.app.project,
                request,
            )
        )

    def _refresh(self) -> None:
        self.requests = (
            self.service
            .list_work_requests(
                self.app.project
            )
        )

        view = self.query_one(
            "#work-requests-list",
            ListView,
        )

        view.clear()

        if not self.requests:
            view.append(
                ListItem(
                    Label(
                        "No Work Requests found "
                        "for this project."
                    )
                )
            )

            view.focus()
            return

        for request in self.requests:
            counts: dict[str, int] = {}

            for status in (
                request.task_statuses.values()
            ):
                counts[status] = (
                    counts.get(status, 0)
                    + 1
                )

            state_text = " ".join(
                f"{status}:{count}"
                for status, count
                in sorted(counts.items())
            )

            objective = (
                request.objective
                .replace("\n", " ")
            )

            if len(objective) > 90:
                objective = (
                    objective[:87]
                    + "..."
                )

            label = (
                f"{request.id}  "
                f"[{request.display_status}]  "
                f"{request.request_type}/"
                f"{request.priority}\n"
                f"{objective}\n"
                f"Tasks: "
                f"{len(request.task_ids)}"
            )

            if state_text:
                label += (
                    f"   {state_text}"
                )

            label += (
                "\n"
                + ("-" * 70)
            )

            view.append(
                ListItem(
                    Label(label)
                )
            )

        view.index = 0
        view.focus()

    def on_list_view_selected(
        self,
        event: ListView.Selected,
    ) -> None:
        request = self._selected_request()

        if request is None:
            return

        try:
            reopened = (
                self.service.reopen(
                    self.app.project,
                    request.id,
                )
            )

            if not reopened.summary.task_ids:
                self.notify(
                    "This Work Request has no "
                    "materialized tasks yet.",
                    severity="warning",
                )
                return

            self.app.push_screen(
                PlanControlScreen(
                    reopened.plan,
                    reopened.preparation,
                )
            )

        except Exception as exc:
            self.notify(
                str(exc),
                severity="error",
            )
