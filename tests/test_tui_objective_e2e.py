from __future__ import annotations

import asyncio
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest
from textual.app import App
from textual.widgets import Input, Static

from company_os.cli.screens.command_center import (
    CommandCenterScreen,
    CommandProposalScreen,
    PlanPreviewScreen,
)
from company_os.cli.screens.plan_control import (
    PlanControlScreen,
)
from company_os.cli.screens.prepare_plan import (
    PreparePlanScreen,
)


pytestmark = pytest.mark.skipif(
    os.name != "nt",
    reason="Full AI Company OS TUI E2E requires Windows PowerShell.",
)


OBJECTIVE = (
    "Implement sample.txt so it contains changed by full TUI E2E."
)


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


def prepare_engine_project(
    tmp_path: Path,
    engine_root: Path,
) -> Path:
    root = tmp_path / "objective-e2e-project"
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

    shutil.copytree(
        engine_root / ".codex" / "agents",
        root / ".codex" / "agents",
    )

    shutil.copy2(
        engine_root
        / ".codex"
        / "writable-policy.json",
        root
        / ".codex"
        / "writable-policy.json",
    )

    config_source = (
        engine_root
        / ".codex"
        / "config.toml"
    )

    if config_source.exists():
        shutil.copy2(
            config_source,
            root
            / ".codex"
            / "config.toml",
        )
    else:
        write(
            root
            / ".codex"
            / "config.toml",
            "[agents]\nenabled = true\n",
        )

    shutil.copy2(
        engine_root / "AGENTS.md",
        root / "AGENTS.md",
    )

    write(
        root / "sample.txt",
        "original\n",
    )

    (root / "tasks").mkdir()

    write(
        root
        / ".codex"
        / "state"
        / "blockers.md",
        "# Blockers\n\n## Active Blockers\n\n-\n",
    )

    write(
        root
        / ".codex"
        / "state"
        / "current-sprint.md",
        (
            "# Current Sprint\n\n"
            "## Sprint Goal\n\n"
            "Awaiting TUI objective.\n"
        ),
    )

    write(
        root
        / ".codex"
        / "state"
        / "company-state.md",
        (
            "# Company State\n\n"
            "## Current Project Phase\n\n"
            "-\n\n"
            "## Current Objective\n\n"
            "-\n\n"
            "## Quality Gates\n\n"
            "### Product\nNOT_STARTED\n"
            "### Architecture\nNOT_STARTED\n"
            "### Implementation\nNOT_STARTED\n"
            "### Review\nNOT_STARTED\n"
            "### QA\nNOT_STARTED\n"
            "### Security\nNOT_STARTED\n"
            "### Release\nNOT_STARTED\n"
            "### Final\nNOT_STARTED\n"
        ),
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
        "models": {
            "OpenRouter": "openrouter/free",
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

    fake_router = r'''param(
    [string]$Provider,
    [string]$ProjectPath,
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [string]$Role = "",
    [string]$Workload = "general"
)

$ErrorActionPreference = "Stop"

$name = [System.IO.Path]::GetFileName($SchemaPath)

switch ($name) {
    "writable-change-set.schema.json" {
        $result = [ordered]@{
            outcome = "COMPLETED"
            summary = "Applied full TUI objective E2E change."
            report_markdown = "# Full TUI E2E\nApplied deterministic worktree change."
            changes = @(
                [ordered]@{
                    path = "sample.txt"
                    operation = "WRITE"
                    content = "changed by full TUI E2E" + [Environment]::NewLine
                    reason = "Exercise full Objective-to-DONE TUI orchestration."
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
            verification = "Full TUI E2E review pass."
        }
    }

    "qa-gate-result.schema.json" {
        $result = [ordered]@{
            outcome = "PASS"
            evidence = "Full TUI E2E QA pass."
            findings = "NONE"
        }
    }

    "security-gate-result.schema.json" {
        $result = [ordered]@{
            outcome = "PASS"
            evidence = "Full TUI E2E security pass."
            findings = "NONE"
        }
    }

    default {
        throw "Unsupported full E2E schema: $name"
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
        "aico-full-e2e@example.invalid",
    )
    run_git(
        root,
        "config",
        "user.name",
        "AI Company OS Full E2E",
    )
    run_git(root, "add", ".")
    run_git(
        root,
        "commit",
        "-m",
        "Full TUI objective E2E fixture",
    )

    return root


def read_statuses(
    root: Path,
    task_ids: list[str],
) -> dict[str, str]:
    statuses = {}

    for task_id in task_ids:
        content = (
            root
            / "tasks"
            / f"{task_id}.md"
        ).read_text(
            encoding="utf-8-sig"
        )

        status = ""

        for line in content.splitlines():
            if line.startswith("Status:"):
                status = line.split(
                    ":",
                    1,
                )[1].strip()
                break

        statuses[task_id] = status

    return statuses


async def wait_for_screen(
    app: App,
    pilot,
    screen_type,
    *,
    attempts: int = 600,
):
    for _ in range(attempts):
        if isinstance(
            app.screen,
            screen_type,
        ):
            await pilot.pause()
            return app.screen

        await asyncio.sleep(0.05)
        await pilot.pause()

    raise AssertionError(
        f"Timed out waiting for {screen_type.__name__}."
    )


async def wait_idle(
    pilot,
    screen,
    *,
    attempts: int = 1200,
) -> None:
    for _ in range(attempts):
        if not getattr(
            screen,
            "busy",
            False,
        ):
            await pilot.pause()
            return

        await asyncio.sleep(0.05)
        await pilot.pause()

    raise AssertionError(
        "TUI operation did not become idle."
    )


class ObjectiveHarness(App):
    def __init__(
        self,
        project_root: Path,
    ) -> None:
        super().__init__()

        self.project = project_root

    def compose(self):
        yield Static(
            "Full Objective E2E harness"
        )

    def on_mount(self) -> None:
        self.push_screen(
            CommandCenterScreen()
        )


def test_objective_to_done_is_operated_from_tui(
    tmp_path,
    monkeypatch,
):
    engine_root = Path(__file__).parents[1]

    root = prepare_engine_project(
        tmp_path,
        engine_root,
    )

    monkeypatch.setenv(
        "OPENROUTER_API_KEY",
        "full-e2e-stub-key",
    )

    app = ObjectiveHarness(root)

    async def scenario() -> None:
        async with app.run_test(
            size=(160, 60),
        ) as pilot:
            command = await wait_for_screen(
                app,
                pilot,
                CommandCenterScreen,
            )

            input_widget = command.query_one(
                "#command-input",
                Input,
            )

            input_widget.value = OBJECTIVE

            await pilot.press("enter")

            proposal = await wait_for_screen(
                app,
                pilot,
                CommandProposalScreen,
            )

            assert (
                proposal.proposal_data.intent
                == "FEATURE"
            )

            await pilot.press("enter")

            preview = await wait_for_screen(
                app,
                pilot,
                PlanPreviewScreen,
            )

            assert preview.plan_data is not None
            assert (
                preview.plan_data.strategy_id
                == "balanced"
            )
            assert (
                preview.plan_data.request
                == OBJECTIVE
            )

            await pilot.press("r")

            await wait_for_screen(
                app,
                pilot,
                PreparePlanScreen,
            )

            await pilot.press("y")

            control = await wait_for_screen(
                app,
                pilot,
                PlanControlScreen,
                attempts=1200,
            )

            task_ids = control._task_ids()

            assert task_ids

            requests = (
                root
                / "docs"
                / "engineering"
                / "work-requests"
            )

            assert any(
                requests.glob("WR-*.md")
            )

            for _wave in range(12):
                statuses = read_statuses(
                    root,
                    task_ids,
                )

                if all(
                    value == "DONE"
                    for value in statuses.values()
                ):
                    break

                assert "BLOCKED" not in statuses.values()

                if any(
                    value in {
                        "BACKLOG",
                        "READY",
                    }
                    for value in statuses.values()
                ):
                    await pilot.press("a")
                    await wait_idle(
                        pilot,
                        control,
                    )

                statuses = read_statuses(
                    root,
                    task_ids,
                )

                assert any(
                    value == "ACTIVE"
                    for value in statuses.values()
                )

                await pilot.press("w")
                await wait_idle(
                    pilot,
                    control,
                    attempts=1600,
                )

                statuses = read_statuses(
                    root,
                    task_ids,
                )

                assert any(
                    value == "REVIEW"
                    for value in statuses.values()
                )

                await pilot.press("g")
                await wait_idle(
                    pilot,
                    control,
                    attempts=1600,
                )

                statuses = read_statuses(
                    root,
                    task_ids,
                )

                assert any(
                    value == "SECURITY"
                    for value in statuses.values()
                )

                await pilot.press("f")
                await wait_idle(
                    pilot,
                    control,
                    attempts=1200,
                )

            final_statuses = read_statuses(
                root,
                task_ids,
            )

            assert set(
                final_statuses.values()
            ) == {"DONE"}

            worktree_root = (
                root.parent
                / f"{root.name}-worktrees"
            )

            changed_worktrees = []

            for task_id in task_ids:
                workspace = (
                    worktree_root
                    / task_id
                )

                if not workspace.exists():
                    continue

                sample = workspace / "sample.txt"

                if (
                    sample.exists()
                    and sample.read_text(
                        encoding="utf-8"
                    )
                    == "changed by full TUI E2E\n"
                ):
                    changed_worktrees.append(
                        task_id
                    )

            assert changed_worktrees

            assert (
                root
                / "sample.txt"
            ).read_text(
                encoding="utf-8"
            ) == "original\n"

            approvals = (
                root
                / "docs"
                / "engineering"
                / "final-approvals"
            )

            for task_id in task_ids:
                assert (
                    approvals
                    / f"{task_id}-final.md"
                ).exists()

    asyncio.run(scenario())
