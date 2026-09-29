from types import SimpleNamespace

from company_os.application.ceo_planning_service import (
    CEOPlanningService,
)


def proposal(
    intent="AUDIT",
    request="Audit project",
):
    return SimpleNamespace(
        intent=intent,
        request=request,
    )


def option(
    option_id="balanced",
    title="Balanced",
):
    return SimpleNamespace(
        id=option_id,
        title=title,
    )


def test_audit_balanced_runs_specialists_in_parallel():
    service = CEOPlanningService()

    tasks = service._build_tasks(
        "AUDIT",
        "balanced",
        "Audit project",
    )

    wave_one = [
        task
        for task in tasks
        if task.wave == 1
    ]

    owners = {
        task.owner
        for task in wave_one
    }

    assert {
        "pm",
        "cto",
        "qa",
        "security",
    }.issubset(owners)


def test_audit_consolidation_depends_on_specialists():
    service = CEOPlanningService()

    tasks = service._build_tasks(
        "AUDIT",
        "balanced",
        "Audit project",
    )

    final = next(
        task
        for task in tasks
        if task.owner == "engineering-manager"
    )

    assert len(final.dependencies) >= 4


def test_feature_plan_has_dependency_chain():
    service = CEOPlanningService()

    tasks = service._build_tasks(
        "FEATURE",
        "balanced",
        "Add payments",
    )

    by_key = {
        task.key: task
        for task in tasks
    }

    assert by_key["PLAN-02"].dependencies == [
        "PLAN-01"
    ]

    assert set(
        by_key["PLAN-03"].dependencies
    ) == {
        "PLAN-01",
        "PLAN-02",
    }


def test_fix_thorough_adds_security():
    service = CEOPlanningService()

    tasks = service._build_tasks(
        "FIX",
        "thorough",
        "Fix authentication",
    )

    assert any(
        task.owner == "security"
        for task in tasks
    )