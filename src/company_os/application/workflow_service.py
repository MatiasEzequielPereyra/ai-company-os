from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path

from company_os.application.status_service import StatusService
from company_os.domain.models import TaskStatus
from company_os.repository.task_repository import TaskRepository


@dataclass
class WorkflowNode:
    task_id: str
    title: str
    owner: str
    status: str
    execution_state: str
    dependencies: list[str]
    unmet_dependencies: list[str]


@dataclass
class WorkflowEdge:
    source: str
    target: str


@dataclass
class WorkflowAnalysis:
    nodes: list[WorkflowNode]
    edges: list[WorkflowEdge]
    parallel_now: list[str]
    waiting: list[str]
    completed: list[str]
    missing_dependencies: list[str]
    cycles: list[list[str]]

    def to_dict(self) -> dict:
        return asdict(self)


def _find_cycles(tasks) -> list[list[str]]:
    graph = {
        task.id: [
            dep
            for dep in task.dependencies
            if dep
        ]
        for task in tasks
    }

    known = set(graph)
    visiting: set[str] = set()
    visited: set[str] = set()
    path: list[str] = []
    cycles: list[list[str]] = []

    def visit(node: str) -> None:
        if node in visiting:
            if node in path:
                start = path.index(node)
                cycle = path[start:] + [node]

                if cycle not in cycles:
                    cycles.append(cycle)

            return

        if node in visited:
            return

        visiting.add(node)
        path.append(node)

        for dependency in graph.get(node, []):
            if dependency in known:
                visit(dependency)

        path.pop()
        visiting.remove(node)
        visited.add(node)

    for node in graph:
        visit(node)

    return cycles


def analyze_workflow(tasks) -> WorkflowAnalysis:
    tasks = list(tasks)

    by_id = {
        task.id: task
        for task in tasks
    }

    done_ids = {
        task.id
        for task in tasks
        if task.status == TaskStatus.DONE
    }

    nodes: list[WorkflowNode] = []
    edges: list[WorkflowEdge] = []

    parallel_now: list[str] = []
    waiting: list[str] = []
    completed: list[str] = []
    missing_dependencies: list[str] = []

    for task in tasks:
        missing = [
            dependency
            for dependency in task.dependencies
            if dependency not in by_id
        ]

        for dependency in missing:
            item = f"{task.id} -> {dependency}"

            if item not in missing_dependencies:
                missing_dependencies.append(item)

        unmet = [
            dependency
            for dependency in task.dependencies
            if dependency in by_id
            and dependency not in done_ids
        ]

        for dependency in task.dependencies:
            if dependency in by_id:
                edges.append(
                    WorkflowEdge(
                        source=dependency,
                        target=task.id,
                    )
                )

        if task.status == TaskStatus.DONE:
            execution_state = "COMPLETED"
            completed.append(task.id)

        elif task.status == TaskStatus.BLOCKED:
            execution_state = "BLOCKED"
            waiting.append(task.id)

        elif unmet or missing:
            execution_state = "WAITING"
            waiting.append(task.id)

        elif task.status == TaskStatus.ACTIVE:
            execution_state = "RUNNING"
            parallel_now.append(task.id)

        elif task.status in {
            TaskStatus.READY,
            TaskStatus.BACKLOG,
        }:
            execution_state = "RUNNABLE"
            parallel_now.append(task.id)

        elif task.status in {
            TaskStatus.REVIEW,
            TaskStatus.QA,
            TaskStatus.SECURITY,
        }:
            execution_state = task.status.value
            parallel_now.append(task.id)

        else:
            execution_state = "UNKNOWN"

        nodes.append(
            WorkflowNode(
                task_id=task.id,
                title=task.title,
                owner=task.owner,
                status=task.status.value,
                execution_state=execution_state,
                dependencies=list(task.dependencies),
                unmet_dependencies=unmet + missing,
            )
        )

    return WorkflowAnalysis(
        nodes=nodes,
        edges=edges,
        parallel_now=parallel_now,
        waiting=waiting,
        completed=completed,
        missing_dependencies=missing_dependencies,
        cycles=_find_cycles(tasks),
    )


class WorkflowService:
    def __init__(self) -> None:
        self.status_service = StatusService()
        self.repository = TaskRepository()

    def get_workflow(
        self,
        project: Path,
    ) -> WorkflowAnalysis:
        snapshot = self.status_service.get_status(project)

        root = Path(
            snapshot.project.root
        )

        tasks = self.repository.list_tasks(
            root
        )

        return analyze_workflow(
            tasks
        )
