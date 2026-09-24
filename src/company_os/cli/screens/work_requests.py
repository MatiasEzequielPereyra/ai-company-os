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
    Static,
)

from company_os.application.delete_plan_service import (
    DeletePlanService,
)
from company_os.application.work_request_service import (
    WorkRequestService,
)
from company_os.cli.i18n import ui_text
from company_os.cli.screens.plan_control import (
    PlanControlScreen,
)
from company_os.cli.widgets import CircularListView


def _t(widget, key: str) -> str:
    return ui_text(
        getattr(
            widget.app,
            "language",
            "es",
        ),
        key,
    )


class DeleteWorkRequestScreen(Screen):
    BINDINGS = [
        Binding(
            "escape",
            "back",
            "Cancelar / Cancel",
        ),
        Binding(
            "y",
            "confirm_delete",
            "Eliminar / Delete",
        ),
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
        yield Header()

        yield Static(
            self._render_content(),
            id="delete-work-request-content",
        )

        yield Footer()

    def _render_content(self):
        allowed, reason = (
            self.service.can_delete(
                self.project_root,
                self.request.id,
            )
        )

        instructions = (
            _t(self, "wr_delete_allowed")
            if allowed
            else _t(self, "wr_delete_denied")
        )

        return Panel(
            f"Work Request: {self.request.id}\n\n"
            f"{self.request.objective}\n\n"
            f"{reason}\n\n"
            f"{instructions}",
            title=_t(
                self,
                "wr_delete_title",
            ),
        )

    def refresh_language(self) -> None:
        self.query_one(
            "#delete-work-request-content",
            Static,
        ).update(
            self._render_content()
        )

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
                f"{result.work_request_id} "
                f"{_t(self, 'wr_deleted')}."
            )

        except Exception as exc:
            self.notify(
                str(exc),
                severity="error",
            )


class WorkRequestsScreen(Screen):
    BINDINGS = [
        Binding(
            "escape",
            "back",
            "Atras / Back",
        ),
        Binding(
            "r",
            "refresh_requests",
            "Actualizar / Refresh",
        ),
        Binding(
            "d",
            "delete_request",
            "Eliminar / Delete",
        ),
    ]

    def __init__(self) -> None:
        super().__init__()

        self.service = WorkRequestService()
        self.requests = []

    def compose(self) -> ComposeResult:
        yield Header()

        yield Static(
            _t(self, "wr_heading"),
            id="work-requests-heading",
        )

        yield CircularListView(
            id="work-requests-list",
        )

        yield Footer()

    def on_mount(self) -> None:
        self._refresh()

    def refresh_language(self) -> None:
        self.query_one(
            "#work-requests-heading",
            Static,
        ).update(
            _t(self, "wr_heading")
        )

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
            CircularListView,
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
            CircularListView,
        )

        view.clear()

        if not self.requests:
            view.append(
                ListItem(
                    Label(
                        _t(
                            self,
                            "wr_no_requests",
                        )
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
                    counts.get(
                        status,
                        0,
                    )
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
                f"{_t(self, 'wr_tasks')}: "
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
        event: CircularListView.Selected,
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
                    _t(
                        self,
                        "wr_no_materialized",
                    ),
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
