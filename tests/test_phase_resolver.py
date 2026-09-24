from company_os.application.phase_resolver import derive_project_phase
from company_os.domain.models import TaskStatus, WorkflowPhase


class FakeTask:
    def __init__(self, status):
        self.status = status


def test_done_tasks_do_not_imply_project_done():
    tasks = [
        FakeTask(TaskStatus.DONE),
        FakeTask(TaskStatus.DONE),
    ]

    assert derive_project_phase(tasks) == WorkflowPhase.UNKNOWN


def test_active_task_implies_in_progress():
    tasks = [
        FakeTask(TaskStatus.DONE),
        FakeTask(TaskStatus.ACTIVE),
    ]

    assert derive_project_phase(tasks) == WorkflowPhase.IN_PROGRESS


def test_blocked_has_priority():
    tasks = [
        FakeTask(TaskStatus.ACTIVE),
        FakeTask(TaskStatus.BLOCKED),
    ]

    assert derive_project_phase(tasks) == WorkflowPhase.BLOCKED
