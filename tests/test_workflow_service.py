from types import SimpleNamespace

from company_os.application.workflow_service import analyze_workflow
from company_os.domain.models import TaskStatus


def task(
    task_id,
    status,
    dependencies=None,
):
    return SimpleNamespace(
        id=task_id,
        title=task_id,
        owner="backend",
        status=status,
        dependencies=dependencies or [],
    )


def test_workflow_detects_parallel_tasks():
    tasks = [
        task(
            "AICO-001",
            TaskStatus.DONE,
        ),
        task(
            "AICO-002",
            TaskStatus.READY,
            ["AICO-001"],
        ),
        task(
            "AICO-003",
            TaskStatus.READY,
            ["AICO-001"],
        ),
    ]

    result = analyze_workflow(tasks)

    assert set(result.parallel_now) == {
        "AICO-002",
        "AICO-003",
    }


def test_workflow_detects_waiting_task():
    tasks = [
        task(
            "AICO-001",
            TaskStatus.ACTIVE,
        ),
        task(
            "AICO-002",
            TaskStatus.BACKLOG,
            ["AICO-001"],
        ),
    ]

    result = analyze_workflow(tasks)

    assert "AICO-002" in result.waiting


def test_workflow_detects_missing_dependency():
    tasks = [
        task(
            "AICO-002",
            TaskStatus.BACKLOG,
            ["AICO-999"],
        ),
    ]

    result = analyze_workflow(tasks)

    assert (
        "AICO-002 -> AICO-999"
        in result.missing_dependencies
    )


def test_workflow_detects_cycle():
    tasks = [
        task(
            "AICO-001",
            TaskStatus.BACKLOG,
            ["AICO-002"],
        ),
        task(
            "AICO-002",
            TaskStatus.BACKLOG,
            ["AICO-001"],
        ),
    ]

    result = analyze_workflow(tasks)

    assert result.cycles
