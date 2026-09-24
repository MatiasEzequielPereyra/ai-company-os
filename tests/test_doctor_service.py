from types import SimpleNamespace

from company_os.application.doctor_service import analyze_snapshot
from company_os.domain.models import GateState


def make_snapshot(
    *,
    objective="Current objective",
    task_count=1,
    unfinished=0,
    gates=None,
):
    if gates is None:
        gates = []

    return SimpleNamespace(
        project=SimpleNamespace(
            objective=objective,
            root="C:/repo",
        ),
        tasks=SimpleNamespace(
            backlog=unfinished,
            ready=0,
            active=0,
            review=0,
            qa=0,
            security=0,
            blocked=0,
        ),
        gates=gates,
        diagnostics=[],
        meta=SimpleNamespace(
            task_count=task_count,
        ),
    )


def test_doctor_detects_objective_without_work():
    snapshot = make_snapshot()

    findings = analyze_snapshot(snapshot)

    codes = {
        finding.code
        for finding in findings
    }

    assert (
        "OBJECTIVE_WITHOUT_ACTIONABLE_WORK"
        in codes
    )


def test_doctor_detects_unknown_gates():
    gates = [
        SimpleNamespace(
            state=GateState.UNKNOWN
        ),
        SimpleNamespace(
            state=GateState.UNKNOWN
        ),
    ]

    snapshot = make_snapshot(
        unfinished=1,
        gates=gates,
    )

    findings = analyze_snapshot(snapshot)

    codes = {
        finding.code
        for finding in findings
    }

    assert (
        "QUALITY_GATES_UNAVAILABLE"
        in codes
    )


def test_doctor_ok_when_consistent():
    gates = [
        SimpleNamespace(
            state=GateState.PASSED
        ),
    ]

    snapshot = make_snapshot(
        objective=None,
        unfinished=1,
        gates=gates,
    )

    findings = analyze_snapshot(snapshot)

    assert len(findings) == 1
    assert findings[0].code == "DOCTOR_OK"
