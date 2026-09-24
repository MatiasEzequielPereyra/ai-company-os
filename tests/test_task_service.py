from types import SimpleNamespace

import pytest

from company_os.application.task_service import filter_tasks
from company_os.domain.models import Priority, TaskStatus


def make_task(
    task_id,
    status,
    priority,
    owner,
):
    return SimpleNamespace(
        id=task_id,
        status=status,
        priority=priority,
        owner=owner,
    )


TASKS = [
    make_task(
        "AICO-001",
        TaskStatus.DONE,
        Priority.P1,
        "engineering-manager",
    ),
    make_task(
        "AICO-002",
        TaskStatus.ACTIVE,
        Priority.P0,
        "pm",
    ),
    make_task(
        "AICO-003",
        TaskStatus.READY,
        Priority.P1,
        "backend",
    ),
]


def test_filter_tasks_by_status():
    result = filter_tasks(
        TASKS,
        status="ACTIVE",
    )

    assert [task.id for task in result] == ["AICO-002"]


def test_filter_tasks_by_owner():
    result = filter_tasks(
        TASKS,
        owner="PM",
    )

    assert [task.id for task in result] == ["AICO-002"]


def test_filter_tasks_by_priority():
    result = filter_tasks(
        TASKS,
        priority="P1",
    )

    assert [task.id for task in result] == [
        "AICO-001",
        "AICO-003",
    ]


def test_invalid_status_is_rejected():
    with pytest.raises(ValueError):
        filter_tasks(
            TASKS,
            status="BANANA",
        )
