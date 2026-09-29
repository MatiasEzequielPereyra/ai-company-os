from __future__ import annotations

from datetime import datetime, timezone
from enum import StrEnum
from pathlib import Path
from typing import Optional

from pydantic import BaseModel, Field


class TaskStatus(StrEnum):
    BACKLOG = "BACKLOG"
    READY = "READY"
    ACTIVE = "ACTIVE"
    REVIEW = "REVIEW"
    QA = "QA"
    SECURITY = "SECURITY"
    BLOCKED = "BLOCKED"
    DONE = "DONE"
    UNKNOWN = "UNKNOWN"


class WorkflowPhase(StrEnum):
    IDEA = "IDEA"
    PRODUCT = "PRODUCT"
    ARCHITECTURE = "ARCHITECTURE"
    READY = "READY"
    IN_PROGRESS = "IN_PROGRESS"
    CODE_REVIEW = "CODE_REVIEW"
    QA = "QA"
    SECURITY = "SECURITY"
    APPROVED = "APPROVED"
    RELEASE = "RELEASE"
    DONE = "DONE"
    BLOCKED = "BLOCKED"
    CANCELLED = "CANCELLED"
    UNKNOWN = "UNKNOWN"


class AgentWorkState(StrEnum):
    IDLE = "IDLE"
    ASSIGNED = "ASSIGNED"
    WORKING = "WORKING"
    WAITING = "WAITING"
    BLOCKED = "BLOCKED"
    REVIEWING = "REVIEWING"
    DONE = "DONE"
    UNKNOWN = "UNKNOWN"


class RuntimeState(StrEnum):
    UNKNOWN = "UNKNOWN"
    OFFLINE = "OFFLINE"
    RUNNING = "RUNNING"
    FAILED = "FAILED"


class GateState(StrEnum):
    NOT_STARTED = "NOT_STARTED"
    IN_PROGRESS = "IN_PROGRESS"
    PASSED = "PASSED"
    FAILED = "FAILED"
    NOT_APPLICABLE = "NOT_APPLICABLE"
    BLOCKED = "BLOCKED"
    UNKNOWN = "UNKNOWN"


class DiagnosticSeverity(StrEnum):
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"


class Priority(StrEnum):
    P0 = "P0"
    P1 = "P1"
    P2 = "P2"
    P3 = "P3"
    UNKNOWN = "UNKNOWN"


class Task(BaseModel):
    id: str
    title: str
    status: TaskStatus
    priority: Priority = Priority.UNKNOWN
    owner: str = "UNKNOWN"
    created: Optional[datetime] = None
    updated: Optional[datetime] = None
    workflow_phase: Optional[WorkflowPhase] = None
    objective: Optional[str] = None
    dependencies: list[str] = Field(default_factory=list)
    evidence: list[str] = Field(default_factory=list)
    source_path: Path


class ProjectSnapshot(BaseModel):
    name: str
    root: str
    phase: WorkflowPhase = WorkflowPhase.UNKNOWN
    objective: Optional[str] = None
    sprint_goal: Optional[str] = None
    phase_derived: bool = False


class AgentSnapshot(BaseModel):
    id: str
    display_name: str
    work_state: AgentWorkState
    runtime_state: RuntimeState = RuntimeState.UNKNOWN
    current_task_ids: list[str] = Field(default_factory=list)


class TaskSummary(BaseModel):
    id: str
    title: str
    owner: str
    status: TaskStatus
    priority: Priority
    blocked: bool
    dependencies: list[str] = Field(default_factory=list)


class TaskOverview(BaseModel):
    total: int = 0
    backlog: int = 0
    ready: int = 0
    active: int = 0
    review: int = 0
    qa: int = 0
    security: int = 0
    blocked: int = 0
    done: int = 0
    active_tasks: list[TaskSummary] = Field(default_factory=list)


class BlockerSnapshot(BaseModel):
    task_id: str
    reason: str
    impact: Optional[str] = None
    required_decision: Optional[str] = None
    escalation_owner: Optional[str] = None


class GateSnapshot(BaseModel):
    name: str
    state: GateState
    source: str
    stale: bool = False


class NextAction(BaseModel):
    kind: str
    description: str
    owner: Optional[str] = None
    task_ids: list[str] = Field(default_factory=list)


class Diagnostic(BaseModel):
    severity: DiagnosticSeverity
    code: str
    message: str
    source: Optional[str] = None


class SnapshotMeta(BaseModel):
    generated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    repository_valid: bool
    task_count: int
    has_warnings: bool


class CompanySnapshot(BaseModel):
    project: ProjectSnapshot
    agents: list[AgentSnapshot]
    tasks: TaskOverview
    blockers: list[BlockerSnapshot]
    gates: list[GateSnapshot]
    next_action: Optional[NextAction]
    diagnostics: list[Diagnostic]
    meta: SnapshotMeta
