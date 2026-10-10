from __future__ import annotations

import asyncio
from pathlib import Path

from textual.app import App
from textual.widgets import Input

from company_os.application.project_service import ProjectService, RecentProject
from company_os.cli.screens.projects import ProjectManagerScreen


class ProjectsHarness(App):
    def __init__(self, project: Path) -> None:
        super().__init__()
        self.project = project

    def on_mount(self) -> None:
        self.push_screen(ProjectManagerScreen())


def test_project_path_is_reachable_with_tab_and_direct_shortcut(
    monkeypatch,
    tmp_path,
):
    monkeypatch.setattr(
        ProjectService,
        "list_recent",
        lambda _self: [RecentProject("Recent", str(tmp_path))],
    )

    async def scenario():
        app = ProjectsHarness(tmp_path)
        async with app.run_test(size=(100, 30)) as pilot:
            screen = app.screen
            assert screen.focused.id == "projects-list"

            await pilot.press("tab")
            assert screen.focused.id == "project-path"

            await pilot.press("shift+tab")
            assert screen.focused.id == "projects-list"

            await pilot.press("ctrl+l")
            assert screen.focused.id == "project-path"

    asyncio.run(scenario())


def test_project_path_submission_preserves_windows_path_with_spaces(
    monkeypatch,
    tmp_path,
):
    monkeypatch.setattr(
        ProjectService,
        "list_recent",
        lambda _self: [RecentProject("Recent", str(tmp_path))],
    )
    opened = []
    monkeypatch.setattr(
        ProjectManagerScreen,
        "_open_project",
        lambda _self, value: opened.append(value),
    )
    path = r"C:\Users\Example User\AI Company OS"

    async def scenario():
        app = ProjectsHarness(tmp_path)
        async with app.run_test(size=(100, 30)) as pilot:
            await pilot.press("ctrl+l")
            field = app.screen.query_one("#project-path", Input)
            await pilot.press(*list(path))
            assert field.value == path

            await pilot.press("left", "x")
            assert field.value == path[:-1] + "x" + path[-1:]
            await pilot.press("backspace")
            assert field.value == path

            await pilot.press("up", "down")
            assert field.value == path
            assert app.screen.focused is field
            assert app.screen.query_one("#projects-list").index == 0

            await pilot.press("enter")
            assert opened == [path]

    asyncio.run(scenario())


def test_escape_cancels_path_entry_without_changing_project(
    monkeypatch,
    tmp_path,
):
    monkeypatch.setattr(
        ProjectService,
        "list_recent",
        lambda _self: [],
    )

    async def scenario():
        app = ProjectsHarness(tmp_path)
        async with app.run_test(size=(100, 30)) as pilot:
            screen = app.screen
            await pilot.press("ctrl+l")
            await pilot.press(*list("C:\\missing project"))
            await pilot.press("escape")

            assert app.project == tmp_path
            assert app.screen is not screen

    asyncio.run(scenario())
