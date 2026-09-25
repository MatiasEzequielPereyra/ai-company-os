from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest

from company_os.application.corrective_reactivation_service import (
    CorrectiveReactivationService,
)
from company_os.application.gate_control_service import (
    GateControlService,
)
from company_os.application.task_result_service import (
    TaskResultDetails,
    TaskResultService,
)
from company_os.application.writable_execution_adapter import (
    WritableExecutionAdapter,
)
from company_os.application.writable_workspace_service import (
    WritableWorkspaceService,
)


def test_writable_workspace_accepts_ready_existing_workspace(
    tmp_path,
    monkeypatch,
):
    root = tmp_path / "project"
    root.mkdir()

    scripts = root / "scripts"
    scripts.mkdir()

    (
        scripts
        / "new-agent-workspace.ps1"
    ).write_text(
        "# fixture",
        encoding="utf-8",
    )

    workspace = (
        tmp_path
        / "project-worktrees"
        / "AICO-001"
    )
    workspace.mkdir(parents=True)

    service = WritableWorkspaceService()

    monkeypatch.setattr(
        service.control,
        "get_tasks",
        lambda *_args, **_kwargs: [
            SimpleNamespace(
                id="AICO-001",
                status="READY",
                work_kind="IMPLEMENTATION",
            )
        ],
    )

    result = service.prepare(
        root,
        ["AICO-001"],
    )

    assert len(result.workspaces) == 1
    assert result.workspaces[0].path == str(workspace)
    assert result.workspaces[0].created is False


def test_writable_adapter_accepts_ready_and_exposes_diff(
    tmp_path,
    monkeypatch,
):
    root = tmp_path / "project"
    workspace = tmp_path / "workspace"

    (root / "scripts").mkdir(parents=True)
    workspace.mkdir()

    (
        root
        / "scripts"
        / "run-writable-agent.ps1"
    ).write_text(
        "# fixture",
        encoding="utf-8",
    )

    adapter = WritableExecutionAdapter()

    statuses = iter(
        [
            [
                SimpleNamespace(
                    status="READY",
                    work_kind="IMPLEMENTATION",
                )
            ],
            [
                SimpleNamespace(
                    status="REVIEW",
                    work_kind="IMPLEMENTATION",
                )
            ],
        ]
    )

    monkeypatch.setattr(
        adapter.control,
        "get_tasks",
        lambda *_args, **_kwargs: next(statuses),
    )

    monkeypatch.setattr(
        adapter.providers,
        "build_environment_all",
        lambda *_args, **_kwargs: {},
    )

    monkeypatch.setattr(
        adapter.results,
        "read_latest",
        lambda *_args, **_kwargs: TaskResultDetails(
            outcome="COMPLETED",
            summary="Implemented",
            recommended_next="REVIEW",
            result_path="result.md",
            evidence_path="evidence.md",
            changed_paths=("index.html",),
            verification="git diff --check PASS",
        ),
    )

    monkeypatch.setattr(
        adapter,
        "_powershell",
        lambda: "powershell",
    )

    calls = []

    def fake_run(command, **_kwargs):
        calls.append(command)

        if command[0] == "git":
            if "--stat" in command:
                stdout = " index.html | 2 ++"
            else:
                stdout = "diff --git a/index.html b/index.html"
        else:
            stdout = (
                "Provider: OpenRouter\n"
                "Model: qwen-test\n"
            )

        return SimpleNamespace(
            returncode=0,
            stdout=stdout,
            stderr="",
        )

    monkeypatch.setattr(
        "company_os.application."
        "writable_execution_adapter."
        "subprocess.run",
        fake_run,
    )

    result = adapter.run(
        root,
        "AICO-001",
        workspace,
    )

    assert result.status == "REVIEW"
    assert result.changed_paths == ("index.html",)
    assert "index.html" in result.diff_stat
    assert "diff --git" in result.diff_text
    assert result.result_path == "result.md"
    assert result.evidence_path == "evidence.md"
    assert any(
        "run-writable-agent.ps1"
        in " ".join(command)
        for command in calls
        if command[0] != "git"
    )


def test_blocked_recovery_uses_canonical_ready_transition(
    tmp_path,
    monkeypatch,
):
    root = tmp_path
    tasks = root / "tasks"
    tasks.mkdir()

    (
        tasks
        / "AICO-001.md"
    ).write_text(
        """# AICO-001

Status: BLOCKED
Owner: frontend
""",
        encoding="utf-8",
    )

    service = CorrectiveReactivationService()
    calls = []

    monkeypatch.setattr(
        service,
        "_run_script",
        lambda script, arguments: calls.append(
            (Path(script), list(arguments))
        )
        or "",
    )

    result = service.unblock(
        root,
        ["AICO-001"],
    )

    assert result.task_ids == ["AICO-001"]
    assert calls[0][0].name == "advance-task.ps1"
    assert "-Status" in calls[0][1]

    index = calls[0][1].index("-Status")
    assert calls[0][1][index + 1] == "READY"


def test_finalize_delegates_to_canonical_finalize_script(
    tmp_path,
    monkeypatch,
):
    service = GateControlService()

    monkeypatch.setattr(
        service,
        "finalizable_task_ids",
        lambda *_args, **_kwargs: ["AICO-001"],
    )

    monkeypatch.setattr(
        service,
        "_sync_state",
        lambda *_args, **_kwargs: None,
    )

    calls = []

    def fake_run(script, arguments, timeout):
        calls.append(
            (
                Path(script),
                list(arguments),
                timeout,
            )
        )
        return "approved"

    monkeypatch.setattr(
        service,
        "_run_script",
        fake_run,
    )

    result = service.finalize_scoped(
        tmp_path,
        ["AICO-001"],
    )

    assert result.done_task_ids == ["AICO-001"]
    assert calls[0][0].name == "finalize-task.ps1"
    assert "-Decision" in calls[0][1]
    assert "APPROVE" in calls[0][1]


def test_task_result_exposes_retry_reason_and_evidence(
    tmp_path,
):
    root = tmp_path

    results = (
        root
        / "docs"
        / "engineering"
        / "results"
    )
    reviews = (
        root
        / "docs"
        / "engineering"
        / "reviews"
    )
    evidence = (
        root
        / "docs"
        / "engineering"
        / "writable-evidence"
    )

    results.mkdir(parents=True)
    reviews.mkdir(parents=True)
    evidence.mkdir(parents=True)

    (
        results
        / "AICO-001-result-001.md"
    ).write_text(
        """# Result

Outcome: COMPLETED

## Summary

Implemented.
""",
        encoding="utf-8",
    )

    (
        reviews
        / "AICO-001-review-001.md"
    ).write_text(
        """# Review

Recommendation: CHANGES_REQUIRED
""",
        encoding="utf-8",
    )

    (
        evidence
        / "AICO-001.md"
    ).write_text(
        """# Evidence

Provider: OpenRouter
Model: qwen-test

## Changed Paths

- index.html

## Verification

git diff --check PASS
""",
        encoding="utf-8",
    )

    details = TaskResultService().read_latest(
        root,
        "AICO-001",
    )

    assert details.retry_reason == "CHANGES_REQUIRED"
    assert details.changed_paths == ("index.html",)
    assert details.verification == "git diff --check PASS"


def test_planning_task_is_never_prepared_for_writable_execution(
    tmp_path,
    monkeypatch,
):
    root = tmp_path / "project"
    root.mkdir()

    scripts = root / "scripts"
    scripts.mkdir()

    (
        scripts
        / "new-agent-workspace.ps1"
    ).write_text(
        "# fixture",
        encoding="utf-8",
    )

    implementation_workspace = (
        tmp_path
        / "project-worktrees"
        / "AICO-002"
    )
    implementation_workspace.mkdir(parents=True)

    service = WritableWorkspaceService()

    monkeypatch.setattr(
        service.control,
        "get_tasks",
        lambda *_args, **_kwargs: [
            SimpleNamespace(
                id="AICO-001",
                status="READY",
                work_kind="",
            ),
            SimpleNamespace(
                id="AICO-002",
                status="READY",
                work_kind="IMPLEMENTATION",
            ),
        ],
    )

    result = service.prepare(
        root,
        ["AICO-001", "AICO-002"],
    )

    assert [
        workspace.task_id
        for workspace in result.workspaces
    ] == ["AICO-002"]


def test_writable_rejects_scope_without_implementation(
    tmp_path,
    monkeypatch,
):
    root = tmp_path / "project"
    root.mkdir()

    (root / "scripts").mkdir()

    service = WritableWorkspaceService()

    monkeypatch.setattr(
        service.control,
        "get_tasks",
        lambda *_args, **_kwargs: [
            SimpleNamespace(
                id="AICO-001",
                status="ACTIVE",
                work_kind="",
            )
        ],
    )

    with pytest.raises(
        RuntimeError,
        match="IMPLEMENTATION",
    ):
        service.prepare(
            root,
            ["AICO-001"],
        )


def test_plan_control_preserves_local_runtime_live_progress_and_p0_routing() -> None:
    source = Path(
        "src/company_os/cli/screens/plan_control.py"
    ).read_text(encoding="utf-8")

    assert 'Binding("b", "engineering_backlog"' in source
    assert 'Binding("w", "prepare_writable"' in source
    assert 'Binding("u", "unblock"' in source
    assert "EngineeringBacklogService" in source
    assert "WorkRequestService" in source
    assert "work_kind" in source
    assert "IMPLEMENTATION" in source
    assert "_writable_task_ids" in source
    assert "_analysis_task_ids" in source
    assert "LocalRuntimeService" in source
    assert "Local Runtime / Auto" in source
    assert "Live Progress" in source
    assert "_progress_from_worker" in source
    assert "_handle_progress_line" in source
    assert "__AICO_GATE__|" in source
    assert "gate_states" in source
    assert "CHANGES_REQUIRED / QA FAIL / SECURITY FAIL" in source

    tui_source = Path(
        "src/company_os/cli/tui.py"
    ).read_text(encoding="utf-8")

    assert "_show_startup_error" in tui_source
    assert "tui-startup-error.log" in tui_source


def test_writable_adapter_requires_implementation_work_kind() -> None:
    source = Path(
        "src/company_os/application/writable_execution_adapter.py"
    ).read_text(encoding="utf-8")

    assert 'work_kind != "IMPLEMENTATION"' in source
    assert "changed_paths" in source
    assert "evidence_path" in source
    assert "diff_stat" in source
    assert "diff_text" in source
