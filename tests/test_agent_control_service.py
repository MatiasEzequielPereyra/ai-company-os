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
