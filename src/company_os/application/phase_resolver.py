from __future__ import annotations

from company_os.domain.models import TaskStatus, WorkflowPhase


def derive_project_phase(tasks) -> WorkflowPhase:
    """
    Conservatively infer project phase from task state.

    Important:
    - A collection of DONE tasks does NOT prove the whole project is DONE.
    - DONE must come from an explicit project/company state.
    """

    statuses = {task.status for task in tasks}

    if TaskStatus.BLOCKED in statuses:
        return WorkflowPhase.BLOCKED

    if TaskStatus.ACTIVE in statuses:
        return WorkflowPhase.IN_PROGRESS

    if TaskStatus.REVIEW in statuses:
        return WorkflowPhase.CODE_REVIEW

    if TaskStatus.QA in statuses:
        return WorkflowPhase.QA

    if TaskStatus.SECURITY in statuses:
        return WorkflowPhase.SECURITY

    if TaskStatus.READY in statuses:
        return WorkflowPhase.READY

    # BACKLOG means work exists, but it is not yet ready to execute.
    # We cannot infer a stronger workflow phase from it.
    if TaskStatus.BACKLOG in statuses:
        return WorkflowPhase.UNKNOWN

    # Only DONE tasks, or no tasks at all, do not prove the
    # project itself is complete.
    return WorkflowPhase.UNKNOWN
