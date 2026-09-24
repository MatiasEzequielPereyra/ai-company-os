from pathlib import Path
from types import SimpleNamespace
import tomllib

from company_os.application.gate_control_service import (
    GateControlService,
)
from company_os.cli.screens.plan_control import (
    PlanControlScreen,
)


def test_release_dependencies_are_declared():
    data = tomllib.loads(
        Path("pyproject.toml").read_text(
            encoding="utf-8"
        )
    )

    dependencies = " ".join(
        data["project"]["dependencies"]
    ).lower()

    assert "textual" in dependencies
    assert "keyring" in dependencies
    assert "prompt-toolkit" in dependencies


def test_high_assurance_requires_security_pass(
    tmp_path,
):
    tasks = tmp_path / "tasks"
    security = (
        tmp_path
        / "docs"
        / "engineering"
        / "security"
    )

    tasks.mkdir(parents=True)
    security.mkdir(parents=True)

    (
        tasks / "AICO-999.md"
    ).write_text(
        "ID: AICO-999\n"
        "Workflow profile: high-assurance\n",
        encoding="utf-8",
    )

    (
        security / "AICO-999-security.md"
    ).write_text(
        "Outcome: NOT_APPLICABLE\n",
        encoding="utf-8",
    )

    service = GateControlService()

    assert not service._security_satisfied(
        tmp_path,
        "AICO-999",
    )

    (
        security / "AICO-999-security.md"
    ).write_text(
        "Outcome: PASS\n",
        encoding="utf-8",
    )

    assert service._security_satisfied(
        tmp_path,
        "AICO-999",
    )


def test_plan_control_refreshes_work_request_scope(
    tmp_path,
):
    plan = SimpleNamespace(
        project_root=str(tmp_path),
    )

    preparation = SimpleNamespace(
        created_task_ids=[
            "AICO-001",
        ],
        work_request_ids=[
            "WR-001",
        ],
    )

    screen = PlanControlScreen(
        plan,
        preparation,
    )

    screen.work_requests = SimpleNamespace(
        reopen=lambda root, request_id:
            SimpleNamespace(
                summary=SimpleNamespace(
                    task_ids=[
                        "AICO-001",
                        "AICO-010",
                        "AICO-011",
                    ]
                )
            )
    )

    assert screen._task_ids() == [
        "AICO-001",
        "AICO-010",
        "AICO-011",
    ]
