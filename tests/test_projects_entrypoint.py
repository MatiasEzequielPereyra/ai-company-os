"""Exercise the CLI entrypoint and real app; reusable by an installed npm probe."""
from __future__ import annotations

import asyncio
import inspect
import json
import sys
from pathlib import Path
from unittest.mock import patch


def install_entrypoint_probe(root: Path):
    from textual.events import Paste
    from textual.widgets import Input

    from company_os.application.config_service import ConfigService
    from company_os.cli.screens.projects import ProjectManagerScreen
    from company_os.cli.tui import AICompanyTUI

    root.mkdir(parents=True, exist_ok=True)
    original = root / "Original Project"
    target = root / "Windows Project With Spaces"
    for project in (original, target):
        (project / "tasks").mkdir(parents=True, exist_ok=True)
        (project / ".codex").mkdir(parents=True, exist_ok=True)
    home_patch = patch.object(Path, "home", return_value=root / "isolated-home")
    home_patch.start()
    ConfigService().set_current_project(original)
    evidence = {"screen_file": inspect.getfile(ProjectManagerScreen)}

    async def scenario(app):
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.press("down", "down", "enter")
            screen = app.screen
            assert type(screen) is ProjectManagerScreen
            assert screen.focused.id == "projects-list"
            await pilot.press("tab")
            field = screen.query_one("#project-path", Input)
            assert screen.focused is field
            await pilot.press("shift+tab")
            assert screen.focused.id == "projects-list"
            await pilot.press("ctrl+l")
            assert screen.focused is field
            await pilot.press(*list(str(target)))
            await pilot.press("left", "x")
            assert field.value == str(target)[:-1] + "x" + str(target)[-1:]
            await pilot.press("backspace")
            assert field.value == str(target)
            await pilot.press("up", "down")
            assert screen.focused is field
            await pilot.press("escape")
            assert app.screen is not screen
            assert app.project == original.resolve()
            assert ConfigService().get_current_project() == original.resolve()

            await pilot.press("enter", "ctrl+l")
            screen = app.screen
            field = screen.query_one("#project-path", Input)
            missing = root / "Missing Project"
            field.post_message(Paste(str(missing)))
            await pilot.pause()
            assert field.value == str(missing)
            await pilot.press("enter")
            assert app.screen is screen
            assert app.project == original.resolve()
            assert ConfigService().get_current_project() == original.resolve()
            await pilot.press("home", "shift+end", "backspace")
            assert field.value == ""
            field.post_message(Paste(str(target)))
            await pilot.pause()
            assert field.value == str(target)
            await pilot.press("enter")
            assert app.screen is not screen
            assert app.project == target.resolve()
            assert ConfigService().get_current_project() == target.resolve()
            assert app.current_view == "overview"

    def run(app, *, mouse):
        assert mouse is False
        asyncio.run(scenario(app))
        evidence.update(result="PASS", executable=sys.executable,
                        app_file=inspect.getfile(AICompanyTUI),
                        paste="Textual Paste event; OS clipboard pending manual validation")
        (root / "entrypoint-evidence.json").write_text(
            json.dumps(evidence, indent=2), encoding="utf-8"
        )

    run_patch = patch.object(AICompanyTUI, "run", run)
    run_patch.start()
    return home_patch, run_patch


def test_python_cli_uses_real_projects_screen(tmp_path, monkeypatch):
    from company_os.cli.app import main

    monkeypatch.setattr(sys, "argv", ["company"])
    patches = install_entrypoint_probe(tmp_path)
    try:
        try:
            main()
        except SystemExit as exc:
            assert exc.code == 0
        evidence = json.loads((tmp_path / "entrypoint-evidence.json").read_text())
        assert evidence["result"] == "PASS"
        assert evidence["screen_file"].endswith("projects.py")
    finally:
        for applied in reversed(patches):
            applied.stop()
