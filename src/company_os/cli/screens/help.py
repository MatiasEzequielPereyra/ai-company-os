from __future__ import annotations

from rich.panel import Panel

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, VerticalScroll
from textual.screen import Screen
from textual.widgets import (
    Footer,
    Header,
    Label,
    ListItem,
    ListView,
    Static,
)

from company_os.cli.i18n import (
    HELP_SECTION_IDS,
    help_section_content,
    help_section_label,
)


class HelpScreen(Screen):
    BINDINGS = [
        Binding(
            "escape",
            "back",
            "Volver / Back",
        ),
    ]

    CSS = """
    HelpScreen {
        layout: vertical;
    }

    #help-main {
        height: 1fr;
    }

    #help-sections {
        width: 31;
        min-width: 25;
        border: round $accent;
    }

    #help-content-scroll {
        width: 1fr;
        border: round $accent;
        padding: 1 2;
    }

    #help-content {
        width: 100%;
    }
    """

    def compose(self) -> ComposeResult:
        yield Header()

        with Horizontal(id="help-main"):
            yield ListView(
                *[
                    ListItem(
                        Label(
                            help_section_label(
                                self._language(),
                                section_id,
                            )
                        ),
                        id=f"help-{section_id}",
                    )
                    for section_id
                    in HELP_SECTION_IDS
                ],
                id="help-sections",
            )

            with VerticalScroll(
                id="help-content-scroll"
            ):
                yield Static(
                    id="help-content"
                )

        yield Footer()

    def on_mount(self) -> None:
        section_list = self.query_one(
            "#help-sections",
            ListView,
        )

        section_list.index = 0
        section_list.focus()

        self._show_section(0)

    def action_back(self) -> None:
        self.app.pop_screen()

    def on_list_view_selected(
        self,
        event: ListView.Selected,
    ) -> None:
        if event.list_view.id != "help-sections":
            return

        index = event.list_view.index

        if index is None:
            return

        self._show_section(index)

    def refresh_language(self) -> None:
        language = self._language()

        for section_id in HELP_SECTION_IDS:
            matches = list(
                self.query(
                    f"#help-{section_id} Label"
                )
            )

            if matches:
                matches[0].update(
                    help_section_label(
                        language,
                        section_id,
                    )
                )

        section_list = self.query_one(
            "#help-sections",
            ListView,
        )

        index = section_list.index

        if index is None:
            index = 0

        self._show_section(index)

    def _show_section(
        self,
        index: int,
    ) -> None:
        if (
            index < 0
            or index >= len(HELP_SECTION_IDS)
        ):
            return

        section_id = HELP_SECTION_IDS[index]

        title, body = help_section_content(
            self._language(),
            section_id,
        )

        self.query_one(
            "#help-content",
            Static,
        ).update(
            Panel(
                body,
                title=title,
            )
        )

    def _language(self) -> str:
        return getattr(
            self.app,
            "language",
            "es",
        )
