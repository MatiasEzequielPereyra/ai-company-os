from __future__ import annotations

from company_os.application.phase_resolver import derive_project_phase


from collections import Counter
from pathlib import Path

from company_os.domain.models import (
    AgentSnapshot,
    AgentWorkState,
    BlockerSnapshot,
    CompanySnapshot,
    Diagnostic,
    DiagnosticSeverity,
    GateSnapshot,
    GateState,
    NextAction,
    ProjectSnapshot,
    RuntimeState,
    SnapshotMeta,
    TaskOverview,
    TaskStatus,
    TaskSummary,
    WorkflowPhase,
)
from company_os.repository.agent_repository import AgentRepository
from company_os.repository.blocker_index_reader import BlockerIndexReader
from company_os.repository.company_state_reader import CompanyStateReader
from company_os.repository.sprint_reader import SprintReader
from company_os.repository.task_repository import TaskRepository


class SnapshotBuilder:
    def __init__(self) -> None:
        self.tasks = TaskRepository()
        self.state = CompanyStateReader()
        self.sprint = SprintReader()
        self.agents = AgentRepository()
        self.blockers = BlockerIndexReader()

    def build(self, root: Path) -> CompanySnapshot:
        tasks = self.tasks.list_tasks(root)
        state = self.state.read(root)
        sprint = self.sprint.read(root)
        agent_defs = self.agents.list_agents(root)
        blocker_index = self.blockers.read(root)
        diagnostics: list[Diagnostic] = []

        phase = state["phase"]
        phase_derived = False
        if phase is None:
            phase = derive_project_phase(tasks)
            phase_derived = True
            diagnostics.append(Diagnostic(
                severity=DiagnosticSeverity.WARNING,
                code="PROJECT_PHASE_UNKNOWN" if phase == WorkflowPhase.UNKNOWN else "PROJECT_PHASE_DERIVED",
                message=("No explicit project phase exists and task state alone cannot prove the current project phase." if phase == WorkflowPhase.UNKNOWN else f"Project phase was derived as {phase} because company-state has no valid phase."),
                source=state["source"],
            ))

        objective = state["objective"] or sprint["goal"]
        if not objective:
            diagnostics.append(Diagnostic(
                severity=DiagnosticSeverity.WARNING,
                code="MISSING_OBJECTIVE",
                message="No current objective or sprint goal was found.",
            ))

        task_overview = self._task_overview(tasks)
        blockers = [
            BlockerSnapshot(task_id=t.id, reason=t.objective or "Task is marked BLOCKED")
            for t in tasks if t.status == TaskStatus.BLOCKED
        ]

        if blockers and not blocker_index["raw_active"]:
            diagnostics.append(Diagnostic(
                severity=DiagnosticSeverity.WARNING,
                code="STATE_STALE_BLOCKER_INDEX",
                message="Blocked tasks exist but the derived blocker index is empty.",
                source=blocker_index["source"],
            ))

        gates = []
        for name, gate_state in state["gates"].items():
            stale = self._gate_is_stale(name, gate_state, tasks)
            if stale:
                diagnostics.append(Diagnostic(
                    severity=DiagnosticSeverity.WARNING,
                    code="STATE_STALE_GATE_INDEX",
                    message=f"Global {name} gate is {gate_state.value} but authoritative task state/evidence indicates downstream activity.",
                    source=state["source"],
                ))
            gates.append(GateSnapshot(name=name, state=gate_state, source=state["source"], stale=stale))

        agent_snapshots = self._agent_snapshots(agent_defs, tasks)
        next_action = self._next_action(tasks)

        return CompanySnapshot(
            project=ProjectSnapshot(
                name=root.name,
                root=str(root),
                phase=phase,
                objective=objective,
                sprint_goal=sprint["goal"],
                phase_derived=phase_derived,
            ),
            agents=agent_snapshots,
            tasks=task_overview,
            blockers=blockers,
            gates=gates,
            next_action=next_action,
            diagnostics=diagnostics,
            meta=SnapshotMeta(
                repository_valid=True,
                task_count=len(tasks),
                has_warnings=any(d.severity != DiagnosticSeverity.INFO for d in diagnostics),
            ),
        )

    def _derive_phase(self, tasks) -> WorkflowPhase:
        unfinished = [t for t in tasks if t.status != TaskStatus.DONE]
        if not tasks:
            return WorkflowPhase.UNKNOWN
        if not unfinished:
            return WorkflowPhase.DONE
        priority = [
            (TaskStatus.BLOCKED, WorkflowPhase.BLOCKED),
            (TaskStatus.SECURITY, WorkflowPhase.SECURITY),
            (TaskStatus.QA, WorkflowPhase.QA),
            (TaskStatus.REVIEW, WorkflowPhase.CODE_REVIEW),
            (TaskStatus.ACTIVE, WorkflowPhase.IN_PROGRESS),
            (TaskStatus.READY, WorkflowPhase.READY),
            (TaskStatus.BACKLOG, WorkflowPhase.READY),
        ]
        statuses = {t.status for t in unfinished}
        for task_status, phase in priority:
            if task_status in statuses:
                return phase
        return WorkflowPhase.UNKNOWN

    def _task_overview(self, tasks) -> TaskOverview:
        counts = Counter(t.status for t in tasks)
        active_like = [t for t in tasks if t.status != TaskStatus.DONE]
        return TaskOverview(
            total=len(tasks),
            backlog=counts[TaskStatus.BACKLOG],
            ready=counts[TaskStatus.READY],
            active=counts[TaskStatus.ACTIVE],
            review=counts[TaskStatus.REVIEW],
            qa=counts[TaskStatus.QA],
            security=counts[TaskStatus.SECURITY],
            blocked=counts[TaskStatus.BLOCKED],
            done=counts[TaskStatus.DONE],
            active_tasks=[TaskSummary(
                id=t.id,
                title=t.title,
                owner=t.owner,
                status=t.status,
                priority=t.priority,
                blocked=t.status == TaskStatus.BLOCKED,
                dependencies=t.dependencies,
            ) for t in active_like],
        )

    def _agent_snapshots(self, agent_defs, tasks):
        result = []
        done_ids = {t.id for t in tasks if t.status == TaskStatus.DONE}
        for agent in agent_defs:
            aliases = {agent["id"], agent["config_key"]}
            owned = [t for t in tasks if t.owner in aliases]
            current_tasks = [t for t in owned if t.status != TaskStatus.DONE]
            current = [t.id for t in current_tasks]
            statuses = {t.status for t in current_tasks}

            if TaskStatus.BLOCKED in statuses:
                work_state = AgentWorkState.BLOCKED
            elif TaskStatus.ACTIVE in statuses:
                work_state = AgentWorkState.WORKING
            elif TaskStatus.REVIEW in statuses:
                work_state = AgentWorkState.REVIEWING
            elif any(t.dependencies and any(dep not in done_ids for dep in t.dependencies) for t in current_tasks):
                work_state = AgentWorkState.WAITING
            elif any(s in statuses for s in (TaskStatus.QA, TaskStatus.SECURITY)):
                work_state = AgentWorkState.WORKING
            elif TaskStatus.READY in statuses:
                work_state = AgentWorkState.ASSIGNED
            elif TaskStatus.BACKLOG in statuses:
                work_state = AgentWorkState.ASSIGNED
            elif owned and all(t.status == TaskStatus.DONE for t in owned):
                work_state = AgentWorkState.DONE
            else:
                work_state = AgentWorkState.IDLE

            result.append(AgentSnapshot(
                id=agent["id"],
                display_name=agent["display_name"],
                work_state=work_state,
                runtime_state=RuntimeState.UNKNOWN,
                current_task_ids=current,
            ))
        return result

    def _next_action(self, tasks):
        order = [
            TaskStatus.BLOCKED,
            TaskStatus.ACTIVE,
            TaskStatus.REVIEW,
            TaskStatus.QA,
            TaskStatus.SECURITY,
            TaskStatus.READY,
            TaskStatus.BACKLOG,
        ]
        labels = {
            TaskStatus.BLOCKED: "Resolve blocked work",
            TaskStatus.ACTIVE: "Continue active work",
            TaskStatus.REVIEW: "Complete code review",
            TaskStatus.QA: "Run QA validation",
            TaskStatus.SECURITY: "Run security validation",
            TaskStatus.READY: "Start ready work",
            TaskStatus.BACKLOG: "Prepare backlog work",
        }
        for status in order:
            candidates = [t for t in tasks if t.status == status]
            if not candidates:
                continue

            owners = {t.owner for t in candidates if t.owner and t.owner != "UNKNOWN"}
            owner = next(iter(owners)) if len(owners) == 1 else None
            ids = [t.id for t in candidates]
            shown = ids[:4]
            suffix = f" (+{len(ids) - len(shown)} more)" if len(ids) > len(shown) else ""
            if len(candidates) > 1:
                description = f"{labels[status]} across {len(candidates)} tasks: {', '.join(shown)}{suffix}"
            else:
                description = f"{labels[status]}: {shown[0]}"

            return NextAction(
                kind=status.value,
                description=description,
                owner=owner,
                task_ids=ids,
            )
        return None

    def _gate_is_stale(self, name: str, gate_state: GateState, tasks) -> bool:
        if gate_state != GateState.NOT_STARTED:
            return False

        statuses = {t.status for t in tasks}
        evidence = "\n".join(e.lower() for t in tasks for e in t.evidence)

        if name == "IMPLEMENTATION":
            return bool(statuses & {TaskStatus.ACTIVE, TaskStatus.REVIEW, TaskStatus.QA, TaskStatus.SECURITY, TaskStatus.DONE})
        if name == "REVIEW":
            return bool(statuses & {TaskStatus.QA, TaskStatus.SECURITY}) or "review" in evidence
        if name == "QA":
            return TaskStatus.SECURITY in statuses or "qa" in evidence or "test" in evidence
        if name == "SECURITY":
            return "security" in evidence
        return False



