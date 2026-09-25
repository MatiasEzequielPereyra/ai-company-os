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

from company_os.application.work_request_service import (
    WorkRequestService,
)
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
    "agent-result.schema.json" {
        $result = [ordered]@{
            outcome = "COMPLETED"
            summary = "Completed deterministic analysis/planning task."
            report_markdown = "# Deterministic analysis report`nCompleted the assigned planning or analysis work without modifying production files."
            verification = "E2E deterministic analysis pass."
            decisions = "NONE"
            blockers = "NONE"
            recommended_next = "REVIEW"
        }
    }

    "engineering-backlog.schema.json" {
        if ($Prompt -notmatch '(?m)^Source task:\s*(AICO-\d+)\s*$') {
            throw "Engineering backlog stub could not resolve source task."
        }
        $sourceTaskId = $Matches[1]

        if ($Prompt -notmatch '(?m)^Work request:\s*(\S+)\s*$') {
            throw "Engineering backlog stub could not resolve work request."
        }
        $workRequestId = $Matches[1]

        $result = [ordered]@{
            source_task_id = $sourceTaskId
            work_request_id = $workRequestId
            summary = "Deterministic executable backlog for full TUI E2E."
            implementation_authorization_key = "NONE"
            items = @(
                [ordered]@{
                    key = "IMPLEMENT-SAMPLE"
                    kind = "IMPLEMENTATION"
                    title = "Implement sample.txt objective"
                    owner = "frontend"
                    priority = "P0"
                    objective = "Modify sample.txt so it contains changed by full TUI E2E."
                    context = "This is the only task authorized to modify sample.txt."
                    acceptance_criteria = @(
                        "sample.txt contains changed by full TUI E2E."
                    )
                    dependencies = @()
                    affected_areas = @(
                        "sample.txt"
                    )
                    testing_requirements = @(
                        "git diff --check"
                    )
                    risks = @(
                        "Keep the primary checkout unchanged."
                    )
                },
                [ordered]@{
                    key = "VALIDATE-SAMPLE"
                    kind = "VALIDATION"
                    title = "Validate sample implementation"
                    owner = "qa"
                    priority = "P0"
                    objective = "Validate the completed sample.txt implementation."
                    context = "Validation is analysis-only and follows implementation."
                    acceptance_criteria = @(
                        "Implementation evidence is reviewed."
                    )
                    dependencies = @(
                        "IMPLEMENT-SAMPLE"
                    )
                    affected_areas = @(
                        "sample.txt"
                    )
                    testing_requirements = @(
                        "Review implementation evidence."
                    )
                    risks = @(
                        "Do not modify production files."
                    )
                },
                [ordered]@{
                    key = "OPERATE-SAMPLE"
                    kind = "OPERATIONS"
                    title = "Record operational readiness"
                    owner = "devops"
                    priority = "P1"
                    objective = "Record operational readiness after validation."
                    context = "Operations is analysis-only for this fixture."
                    acceptance_criteria = @(
                        "Operational readiness is recorded."
                    )
                    dependencies = @(
                        "VALIDATE-SAMPLE"
                    )
                    affected_areas = @(
                        "sample.txt"
                    )
                    testing_requirements = @(
                        "Review validation evidence."
                    )
                    risks = @(
                        "Do not modify production files."
                    )
                }
            )
        }
    }

    "writable-change-set.schema.json" {
        if ($Prompt -notmatch '(?m)^Task:\s*(AICO-\d+)\s*$') {
            throw "Writable stub could not resolve task id."
        }
        $writableTaskId = $Matches[1]

        if ($Prompt -notmatch '(?m)^Work kind:\s*IMPLEMENTATION\s*$') {
            throw "P0 regression: writable-change-set requested for non-IMPLEMENTATION task $writableTaskId"
        }

        $result = [ordered]@{
            outcome = "COMPLETED"
            summary = "Applied full TUI objective E2E change from $writableTaskId."
            report_markdown = "# Full TUI E2E`nApplied deterministic implementation worktree change."
            changes = @(
                [ordered]@{
                    path = "sample.txt"
                    operation = "WRITE"
                    content = "changed by full TUI E2E" + [Environment]::NewLine
                    reason = "Exercise downstream IMPLEMENTATION writable execution."
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

            initial_task_ids = list(
                control.preparation_result
                .created_task_ids
            )

            assert initial_task_ids
            assert control._task_ids() == sorted(
                initial_task_ids
            )

            work_request_ids = (
                control._work_request_ids()
            )

            assert len(work_request_ids) == 1
            work_request_id = work_request_ids[0]

            requests = (
                root
                / "docs"
                / "engineering"
                / "work-requests"
            )

            assert any(
                requests.glob("WR-*.md")
            )

            for _wave in range(20):
                statuses = read_statuses(
                    root,
                    initial_task_ids,
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

                current_tasks = {
                    task.id: task
                    for task in control._tasks()
                    if task.id in initial_task_ids
                }

                if any(
                    task.status == "ACTIVE"
                    for task in current_tasks.values()
                ):
                    assert all(
                        task.work_kind != "IMPLEMENTATION"
                        for task in current_tasks.values()
                        if task.status == "ACTIVE"
                    )

                    await pilot.press("r")
                    await wait_idle(
                        pilot,
                        control,
                        attempts=1600,
                    )

                statuses = read_statuses(
                    root,
                    initial_task_ids,
                )

                if any(
                    value in {
                        "REVIEW",
                        "QA",
                        "SECURITY",
                    }
                    for value in statuses.values()
                ):
                    await pilot.press("g")
                    await wait_idle(
                        pilot,
                        control,
                        attempts=1600,
                    )

                finalizable = (
                    control.gates
                    .finalizable_task_ids(
                        root,
                        initial_task_ids,
                    )
                )

                if finalizable:
                    await pilot.press("f")
                    await wait_idle(
                        pilot,
                        control,
                        attempts=1200,
                    )

            initial_statuses = read_statuses(
                root,
                initial_task_ids,
            )

            assert set(
                initial_statuses.values()
            ) == {"DONE"}

            request_service = WorkRequestService()

            summary = next(
                item
                for item in (
                    request_service
                    .list_work_requests(root)
                )
                if item.id == work_request_id
            )

            assert (
                summary.display_status
                == "ENGINEERING_PENDING"
            )

            initial_tasks = {
                task.id: task
                for task in control._tasks()
                if task.id in initial_task_ids
            }

            engineering_manager_ids = [
                task.id
                for task in initial_tasks.values()
                if task.owner == "engineering-manager"
            ]

            assert len(engineering_manager_ids) == 1
            engineering_manager_id = (
                engineering_manager_ids[0]
            )

            assert (
                root
                / "docs"
                / "engineering"
                / "agent-reports"
                / f"{engineering_manager_id}.md"
            ).exists()

            assert (
                root
                / "sample.txt"
            ).read_text(
                encoding="utf-8"
            ) == "original\n"

            pending = (
                control.engineering_backlog
                .pending_sources(
                    root,
                    work_request_ids,
                )
            )

            assert [
                source.task_id
                for source in pending
            ] == [engineering_manager_id]

            await pilot.press("b")
            await wait_idle(
                pilot,
                control,
                attempts=1600,
            )

            dynamic_task_ids = control._task_ids()
            downstream_ids = sorted(
                set(dynamic_task_ids)
                - set(initial_task_ids)
            )

            assert downstream_ids

            downstream_tasks = {
                task.id: task
                for task in control._tasks()
                if task.id in downstream_ids
            }

            implementation_ids = [
                task.id
                for task in downstream_tasks.values()
                if task.work_kind == "IMPLEMENTATION"
            ]

            assert len(implementation_ids) == 1

            for _wave in range(30):
                task_ids = control._task_ids()
                statuses = read_statuses(
                    root,
                    task_ids,
                )

                summary = next(
                    item
                    for item in (
                        request_service
                        .list_work_requests(root)
                    )
                    if item.id == work_request_id
                )

                if (
                    summary.display_status == "DONE"
                    and all(
                        value == "DONE"
                        for value in statuses.values()
                    )
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

                tasks = control._tasks()

                if any(
                    (
                        task.status == "ACTIVE"
                        and task.work_kind == "IMPLEMENTATION"
                    )
                    for task in tasks
                ):
                    await pilot.press("w")
                    await wait_idle(
                        pilot,
                        control,
                        attempts=1600,
                    )

                tasks = control._tasks()

                if any(
                    (
                        task.status == "ACTIVE"
                        and task.work_kind != "IMPLEMENTATION"
                    )
                    for task in tasks
                ):
                    await pilot.press("r")
                    await wait_idle(
                        pilot,
                        control,
                        attempts=1600,
                    )

                task_ids = control._task_ids()
                statuses = read_statuses(
                    root,
                    task_ids,
                )

                if any(
                    value in {
                        "REVIEW",
                        "QA",
                        "SECURITY",
                    }
                    for value in statuses.values()
                ):
                    await pilot.press("g")
                    await wait_idle(
                        pilot,
                        control,
                        attempts=1600,
                    )

                task_ids = control._task_ids()
                finalizable = (
                    control.gates
                    .finalizable_task_ids(
                        root,
                        task_ids,
                    )
                )

                if finalizable:
                    await pilot.press("f")
                    await wait_idle(
                        pilot,
                        control,
                        attempts=1200,
                    )

            final_task_ids = control._task_ids()
            final_statuses = read_statuses(
                root,
                final_task_ids,
            )

            assert set(
                final_statuses.values()
            ) == {"DONE"}

            final_summary = next(
                item
                for item in (
                    request_service
                    .list_work_requests(root)
                )
                if item.id == work_request_id
            )

            assert final_summary.display_status == "DONE"

            worktree_root = (
                root.parent
                / f"{root.name}-worktrees"
            )

            changed_worktrees = []

            for task_id in final_task_ids:
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

            assert changed_worktrees == implementation_ids

            implementation_task_id = (
                changed_worktrees[0]
            )

            implementation_markdown = (
                root
                / "tasks"
                / f"{implementation_task_id}.md"
            ).read_text(
                encoding="utf-8-sig"
            )

            assert (
                "Work kind: IMPLEMENTATION"
                in implementation_markdown
            )
            assert (
                f"Source plan: {engineering_manager_id}"
                in implementation_markdown
            )

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

            for task_id in final_task_ids:
                assert (
                    approvals
                    / f"{task_id}-final.md"
                ).exists()

    asyncio.run(scenario())
