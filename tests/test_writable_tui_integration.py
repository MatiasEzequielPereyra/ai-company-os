from __future__ import annotations

from pathlib import Path

from company_os.application.writable_execution_adapter import (
    WritableExecutionAdapter,
)
from company_os.application.task_result_service import TaskResultService


def test_writable_adapter_accepts_ready_and_active() -> None:
    source = Path(
        "src/company_os/application/writable_execution_adapter.py"
    ).read_text(encoding="utf-8")

    assert '"READY"' in source
    assert '"ACTIVE"' in source
    assert "changed_paths" in source
    assert "evidence_path" in source
    assert "diff_stat" in source
    assert "diff_text" in source


def test_plan_control_exposes_retry_and_canonical_gates() -> None:
    source = Path(
        "src/company_os/cli/screens/plan_control.py"
    ).read_text(encoding="utf-8")

    assert 'Binding("w", "prepare_writable"' in source
    assert 'Binding("u", "unblock"' in source
    assert "CHANGES_REQUIRED / QA FAIL / SECURITY FAIL" in source
    assert '"REVIEW"' in source
    assert '"QA"' in source
    assert '"SECURITY"' in source
    assert '"BLOCKED"' in source
    assert '"DONE"' in source
    assert "LocalRuntimeService" in source
    assert "Local Runtime / Auto" in source
    assert "_show_startup_error" in source
    assert "tui-startup-error.log" in source
    assert "Live Progress" in source
    assert "_progress_from_worker" in source
    assert "_handle_progress_line" in source


def test_task_result_service_surfaces_writable_evidence_and_retry() -> None:
    service = TaskResultService()
    assert callable(service.read_latest)

    source = Path(
        "src/company_os/application/task_result_service.py"
    ).read_text(encoding="utf-8")

    assert "Changed Paths" in source
    assert "Verification" in source
    assert "CHANGES_REQUIRED" in source
    assert "QA FAIL" in source
    assert "SECURITY FAIL" in source
