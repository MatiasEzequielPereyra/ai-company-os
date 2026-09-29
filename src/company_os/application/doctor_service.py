from __future__ import annotations

from pathlib import Path

from company_os.application.status_service import StatusService
from company_os.domain.models import (
    Diagnostic,
    DiagnosticSeverity,
    GateState,
)


def analyze_snapshot(snapshot) -> list[Diagnostic]:
    findings: list[Diagnostic] = list(
        snapshot.diagnostics
    )

    tasks = snapshot.tasks

    unfinished = (
        tasks.backlog
        + tasks.ready
        + tasks.active
        + tasks.review
        + tasks.qa
        + tasks.security
        + tasks.blocked
    )

    if (
        snapshot.project.objective
        and unfinished == 0
    ):
        findings.append(
            Diagnostic(
                severity=DiagnosticSeverity.WARNING,
                code="OBJECTIVE_WITHOUT_ACTIONABLE_WORK",
                message=(
                    "A current objective exists but no unfinished task "
                    "represents remaining work."
                ),
                source=snapshot.project.root,
            )
        )

    if snapshot.meta.task_count == 0:
        findings.append(
            Diagnostic(
                severity=DiagnosticSeverity.WARNING,
                code="NO_TASKS",
                message=(
                    "The repository contains no AI Company OS tasks."
                ),
                source=snapshot.project.root,
            )
        )

    if (
        snapshot.gates
        and all(
            gate.state == GateState.UNKNOWN
            for gate in snapshot.gates
        )
    ):
        findings.append(
            Diagnostic(
                severity=DiagnosticSeverity.WARNING,
                code="QUALITY_GATES_UNAVAILABLE",
                message=(
                    "No authoritative global quality gate state "
                    "is currently available."
                ),
                source=snapshot.project.root,
            )
        )

    if not findings:
        findings.append(
            Diagnostic(
                severity=DiagnosticSeverity.INFO,
                code="DOCTOR_OK",
                message=(
                    "No repository consistency problems were detected."
                ),
                source=snapshot.project.root,
            )
        )

    return findings


class DoctorService:
    def __init__(self) -> None:
        self.status_service = StatusService()

    def get_findings(
        self,
        project: Path,
    ) -> list[Diagnostic]:
        snapshot = self.status_service.get_status(
            project
        )

        return analyze_snapshot(
            snapshot
        )
