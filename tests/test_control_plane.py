from company_os.application.command_service import CommandService
from company_os.application.project_service import ProjectService


class FakeConfig:
    def __init__(self):
        self.current = None

    def set_current_project(self, path):
        self.current = path


def test_command_audit_proposes_options():
    proposal = CommandService().propose(
        "Auditar la aplicación para producción"
    )

    assert proposal.intent == "AUDIT"
    assert len(proposal.options) == 3

    assert any(
        option.recommended
        for option in proposal.options
    )


def test_command_fix_proposes_balanced_flow():
    proposal = CommandService().propose(
        "Corregir el error del dashboard"
    )

    assert proposal.intent == "FIX"

    recommended = next(
        option
        for option in proposal.options
        if option.recommended
    )

    assert "qa" in recommended.agents


def test_project_manager_tracks_recent(tmp_path):
    repository = tmp_path / "Vendify"

    repository.mkdir()
    (repository / ".git").mkdir()

    config = FakeConfig()

    service = ProjectService(
        config_service=config,
        storage_root=tmp_path / "settings",
    )

    opened = service.open_project(
        repository
    )

    assert config.current == opened

    recent = service.list_recent()

    assert recent[0].name == "Vendify"


def test_invalid_project_is_rejected(tmp_path):
    service = ProjectService(
        config_service=FakeConfig(),
        storage_root=tmp_path / "settings",
    )

    invalid = tmp_path / "empty"
    invalid.mkdir()

    try:
        service.open_project(invalid)
    except ValueError:
        pass
    else:
        raise AssertionError(
            "Invalid project should be rejected"
        )