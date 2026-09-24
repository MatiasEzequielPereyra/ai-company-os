from __future__ import annotations

import asyncio
import json
import os
import shutil
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest
from textual.app import App
from textual.widgets import Static

from company_os.cli.screens.plan_control import (
    PlanControlScreen,
)


pytestmark = pytest.mark.skipif(
    os.name != "nt",
    reason="AI Company OS runtime E2E requires Windows PowerShell.",
)


TASK_ID = "AICO-900"


def run_git(root: Path, *args: str) -> str:
    process = subprocess.run(
        ["git", "-C", str(root), *args],
        capture_output=True,
        text=True,
        check=True,
    )
    return process.stdout.strip()


def write(path: Path, content: str) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )
    path.write_text(
        content,
        encoding="utf-8",
    )


def prepare_project(
    tmp_path: Path,
    engine_root: Path,
) -> Path:
    root = tmp_path / "tui-e2e-project"
    root.mkdir()

    shutil.copytree(
        engine_root / "scripts",
        root / "scripts",
    )
    shutil.copytree(
        engine_root / "schemas",
        root / "schemas",
    )

    (root / ".codex").mkdir()

    shutil.copy2(
        engine_root
        / ".codex"
        / "writable-policy.json",
        root
        / ".codex"
        / "writable-policy.json",
    )

    agents = root / ".codex" / "agents"
    agents.mkdir()

    shutil.copy2(
        engine_root
        / ".codex"
        / "agents"
        / "frontend.md",
        agents / "frontend.md",
    )

    shutil.copy2(
        engine_root / "AGENTS.md",
        root / "AGENTS.md",
    )

    provider_config = {
        "writable_auto_order": [
            "OpenRouter",
        ],
        "writable_models": {
            "OpenRouter": (
                "qwen/qwen3.8-27b:free"
            ),
        },
        "context_max_chars": 120000,
        "writable_context_max_chars": 120000,
        "gate_context_max_chars": 120000,
    }

    write(
        root
        / ".codex"
        / "provider-config.json",
        json.dumps(
            provider_config,
            indent=2,
        ),
    )

    write(
        root / "sample.txt",
        "original\n",
    )

    task = f"""# {TASK_ID} - TUI E2E source change

## Metadata

ID: {TASK_ID}
Status: READY
Priority: P1
Owner: frontend
Workflow phase: PLANNING
Workflow profile: standard
Work request: WR-E2E
Work kind: IMPLEMENTATION
Updated: 2026-09-24T00:00:00Z

---

## Objective

Update sample.txt so it contains the approved TUI E2E value.

---

## Context

This is an isolated deterministic TUI integration test.

---

## Acceptance Criteria

- Update sample.txt to contain changed by TUI E2E.
- The primary checkout sample.txt remains unchanged.
- Writable evidence is produced.

---

## Testing Requirements

- git diff --check

---

## Dependencies

-

---

## Evidence

-

---

## Transition Log

-
"""

    write(
        root
        / "tasks"
        / f"{TASK_ID}.md",
        task,
    )

    dispatch = f"""# Execution Request - {TASK_ID}

Task: {TASK_ID}
Owner: frontend

## Objective

Update sample.txt to contain changed by TUI E2E.

## Context

Use the isolated task worktree only.

## Acceptance Criteria

- Update sample.txt to contain changed by TUI E2E.
- Run git diff --check.

## Testing Requirements

- git diff --check
"""

    write(
        root
        / "docs"
        / "engineering"
        / "dispatch"
        / f"{TASK_ID}.md",
        dispatch,
    )

    fake_router = r'''param(
    [string]$Provider,
    [string]$ProjectPath,
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model
)

$ErrorActionPreference = "Stop"

$name = [System.IO.Path]::GetFileName($SchemaPath)

switch ($name) {
    "writable-change-set.schema.json" {
        $result = [ordered]@{
            outcome = "COMPLETED"
            summary = "Applied deterministic TUI E2E change."
            report_markdown = "# TUI E2E\nChanged sample.txt in the isolated worktree."
            changes = @(
                [ordered]@{
                    path = "sample.txt"
                    operation = "WRITE"
                    content = "changed by TUI E2E" + [Environment]::NewLine
                    reason = "Exercise real writable worktree application."
                }
            )
            verification_commands = @(
                "git diff --check"
            )
            verification = "git diff --check"
            decisions = "NONE"
            blockers = "NONE"
            recommended_next = "REVIEW"
        }
    }

    "review-result.schema.json" {
        $result = [ordered]@{
            recommendation = "APPROVE"
            findings = "NONE"
            verification = "Deterministic E2E review pass."
        }
    }

    "qa-gate-result.schema.json" {
        $result = [ordered]@{
            outcome = "PASS"
            evidence = "Deterministic E2E QA evidence."
            findings = "NONE"
        }
    }

    "security-gate-result.schema.json" {
        $result = [ordered]@{
            outcome = "PASS"
            evidence = "Deterministic E2E security evidence."
            findings = "NONE"
        }
    }

    default {
        throw "Unsupported E2E schema: $name"
    }
}

$directory = Split-Path -Parent $OutputPath

if (-not (Test-Path $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

[System.IO.File]::WriteAllText(
    $OutputPath,
    ($result | ConvertTo-Json -Depth 20),
    (New-Object System.Text.UTF8Encoding($false))
)

[PSCustomObject]@{
    Provider = "E2EStub"
    Model = "deterministic"
}
'''

    write(
        root
        / "scripts"
        / "provider-router.ps1",
        fake_router,
    )

    run_git(root, "init")
    run_git(
        root,
        "config",
        "user.email",
        "aico-e2e@example.invalid",
    )
    run_git(
        root,
        "config",
        "user.name",
        "AI Company OS E2E",
    )
    run_git(root, "add", ".")
    run_git(
        root,
        "commit",
        "-m",
        "TUI E2E fixture",
    )

    return root


def task_status(
    root: Path,
) -> str:
    content = (
        root
        / "tasks"
        / f"{TASK_ID}.md"
    ).read_text(
        encoding="utf-8-sig"
    )

    for line in content.splitlines():
        if line.startswith("Status:"):
            return line.split(
                ":",
                1,
            )[1].strip()

    raise AssertionError(
        "Task status field missing."
    )


async def wait_until_idle(
    pilot,
    screen: PlanControlScreen,
    *,
    attempts: int = 400,
) -> None:
    for _ in range(attempts):
        if not screen.busy:
            await pilot.pause()
            return

        await asyncio.sleep(0.05)
        await pilot.pause()

    raise AssertionError(
        "TUI operation did not become idle."
    )


class PlanHarness(App):
    def __init__(
        self,
        project_root: Path,
    ) -> None:
        super().__init__()

        self.project_root = project_root

    def compose(self):
        yield Static("TUI E2E harness")

    def on_mount(self) -> None:
        plan = SimpleNamespace(
            project_root=self.project_root,
            project_name=self.project_root.name,
        )

        preparation = SimpleNamespace(
            created_task_ids=[TASK_ID],
            work_request_ids=["WR-E2E"],
        )

        self.push_screen(
            PlanControlScreen(
                plan,
                preparation,
            )
        )


def test_tui_drives_real_worktree_change_to_done(
    tmp_path,
    monkeypatch,
):
    engine_root = Path(__file__).parents[1]

    root = prepare_project(
        tmp_path,
        engine_root,
    )

    monkeypatch.setenv(
        "OPENROUTER_API_KEY",
        "e2e-stub-key",
    )

    app = PlanHarness(root)

    async def scenario() -> None:
        async with app.run_test(
            size=(150, 55),
        ) as pilot:
            await pilot.pause()

            screen = app.screen

            assert isinstance(
                screen,
                PlanControlScreen,
            )

            assert task_status(root) == "READY"

            await pilot.press("w")
            await wait_until_idle(
                pilot,
                screen,
            )

            assert task_status(root) == "REVIEW"

            workspace = (
                root.parent
                / f"{root.name}-worktrees"
                / TASK_ID
            )

            assert workspace.exists()

            assert (
                workspace
                / "sample.txt"
            ).read_text(
                encoding="utf-8"
            ) == "changed by TUI E2E\n"

            assert (
                root
                / "sample.txt"
            ).read_text(
                encoding="utf-8"
            ) == "original\n"

            assert (
                root
                / "docs"
                / "engineering"
                / "writable-evidence"
                / f"{TASK_ID}.md"
            ).exists()

            await pilot.press("g")
            await wait_until_idle(
                pilot,
                screen,
            )

            assert task_status(root) == "SECURITY"

            assert (
                root
                / "docs"
                / "engineering"
                / "reviews"
                / f"{TASK_ID}-review-001.md"
            ).exists()

            assert (
                root
                / "docs"
                / "engineering"
                / "qa"
                / f"{TASK_ID}-qa.md"
            ).exists()

            assert (
                root
                / "docs"
                / "engineering"
                / "security"
                / f"{TASK_ID}-security.md"
            ).exists()

            await pilot.press("f")
            await wait_until_idle(
                pilot,
                screen,
            )

            assert task_status(root) == "DONE"

            assert (
                root
                / "docs"
                / "engineering"
                / "final-approvals"
                / f"{TASK_ID}-final.md"
            ).exists()

            rendered = screen.query_one(
                "#plan-control-content",
                Static,
            )

            assert rendered is not None

    asyncio.run(scenario())
