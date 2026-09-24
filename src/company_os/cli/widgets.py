from __future__ import annotations

from textual.binding import Binding
from textual.widgets import ListView


class CircularListView(ListView):
    """ListView with circular Up/Down navigation."""

    BINDINGS = [
        Binding(
            "up",
            "wrap_up",
            "",
            show=False,
        ),
        Binding(
            "down",
            "wrap_down",
            "",
            show=False,
        ),
    ]

    def action_wrap_down(self) -> None:
        count = len(self.children)

        if count == 0:
            return

        if self.index is None:
            self.index = 0
            return

        self.index = (
            self.index + 1
        ) % count

    def action_wrap_up(self) -> None:
        count = len(self.children)

        if count == 0:
            return

        if self.index is None:
            self.index = count - 1
            return

        self.index = (
            self.index - 1
        ) % count
