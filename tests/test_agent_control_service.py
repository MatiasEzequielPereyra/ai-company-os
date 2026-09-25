import pytest

from company_os.application.agent_control_service import (
    AgentControlService,
)


def test_agent_control_service_exists():
    service = AgentControlService()

    assert service is not None


def test_empty_activation_is_rejected(tmp_path):
    service = AgentControlService()

    try:
        service.activate_ready(
            tmp_path,
            [],
        )
    except RuntimeError as exc:
        assert "no prepared tasks" in str(exc).lower()
    else:
        raise AssertionError(
            "Expected empty activation to be rejected."
        )


def test_empty_active_run_is_rejected(tmp_path):
    service = AgentControlService()

    tasks = tmp_path / "tasks"
    tasks.mkdir()

    try:
        service.run_active_agents(
            tmp_path,
            ["AICO-001"],
        )
    except RuntimeError as exc:
        assert "no active tasks" in str(exc).lower()
    else:
        raise AssertionError(
            "Expected execution without ACTIVE tasks "
            "to be rejected."
        )


def test_gate_control_uses_streamed_process() -> None:
    from pathlib import Path

    source = Path(
        "src/company_os/application/gate_control_service.py"
    ).read_text(encoding="utf-8")

    assert "run_streamed_process" in source
    assert "__AICO_GATE__|" in source
    assert "build_environment_all" in source


def test_analysis_runner_rejects_active_implementation(
    tmp_path,
    monkeypatch,
):
    tasks = tmp_path / "tasks"
    tasks.mkdir()

    (
        tasks
        / "AICO-010.md"
    ).write_text(
        """# AICO-010 - Implement feature

ID: AICO-010
Status: ACTIVE
Priority: P0
Owner: frontend
Work request: WR-010
Work kind: IMPLEMENTATION

## Objective

Implement feature
""",
        encoding="utf-8",
    )

    service = AgentControlService()

    monkeypatch.setattr(
        service,
        "_run_script",
        lambda *_args, **_kwargs: "unexpected",
    )
    monkeypatch.setattr(
        service,
        "_sync_state",
        lambda *_args, **_kwargs: None,
    )

    with pytest.raises(
        RuntimeError,
        match="IMPLEMENTATION",
    ):
        service.run_active_agents(
            tmp_path,
            ["AICO-010"],
        )
