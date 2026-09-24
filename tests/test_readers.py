from pathlib import Path

from company_os.domain.models import GateState, TaskStatus
from company_os.repository.agent_repository import AgentRepository
from company_os.repository.blocker_index_reader import BlockerIndexReader
from company_os.repository.company_state_reader import CompanyStateReader
from company_os.repository.project_locator import ProjectLocator
from company_os.repository.sprint_reader import SprintReader
from company_os.repository.task_repository import TaskRepository


FIXTURE = Path(__file__).parent / "fixtures" / "minimal_repo"


def test_project_locator():
    assert ProjectLocator().locate(FIXTURE / "tasks") == FIXTURE.resolve()


def test_task_repository():
    tasks = TaskRepository().list_tasks(FIXTURE)
    assert len(tasks) == 1
    assert tasks[0].id == "AICO-001"
    assert tasks[0].status == TaskStatus.ACTIVE
    assert tasks[0].owner == "backend"


def test_company_state_reader():
    state = CompanyStateReader().read(FIXTURE)
    assert state["phase"] is None
    assert state["objective"] is None
    assert state["gates"]["PRODUCT"] == GateState.NOT_STARTED


def test_sprint_reader():
    assert SprintReader().read(FIXTURE)["goal"] == "Ship the first CLI status vertical slice."


def test_agent_repository():
    agents = AgentRepository().list_agents(FIXTURE)
    assert [agent["id"] for agent in agents] == ["ceo", "backend"]


def test_blocker_index_reader():
    assert BlockerIndexReader().read(FIXTURE)["raw_active"] is None


def test_sprint_reader_tolerates_bom_crlf_and_spacing(tmp_path):
    state_dir = tmp_path / ".codex" / "state"
    state_dir.mkdir(parents=True)
    (state_dir / "current-sprint.md").write_text(
        "\ufeff# Current Sprint\r\n\r\nGenerated: 2026-09-23T00:00:00Z\r\n\r\n## Sprint Goal   \r\n\r\nShip the real repository status.\r\n\r\n## Priorities\r\n- P1\r\n",
        encoding="utf-8",
    )
    assert SprintReader().read(tmp_path)["goal"] == "Ship the real repository status."


def test_company_state_reader_parses_gate_subsections_with_blank_lines(tmp_path):
    state_dir = tmp_path / ".codex" / "state"
    state_dir.mkdir(parents=True)
    (state_dir / "company-state.md").write_text(
        "# Company State\n\n## Current Project Phase\n\n-\n\n## Current Objective\n\n-\n\n"
        "## Quality Gates\n\n### Product\n\nNOT_STARTED\n\n### Architecture\n\nPASSED\n\n"
        "### Implementation\n\nIN_PROGRESS\n\n### Review\n\nNOT_STARTED\n\n### QA\n\nNOT_STARTED\n\n"
        "### Security\n\nNOT_APPLICABLE\n\n### Release\n\nBLOCKED\n\n### Final\n\nUNKNOWN\n",
        encoding="utf-8",
    )
    state = CompanyStateReader().read(tmp_path)
    assert state["gates"]["PRODUCT"] == GateState.NOT_STARTED
    assert state["gates"]["ARCHITECTURE"] == GateState.PASSED
    assert state["gates"]["IMPLEMENTATION"] == GateState.IN_PROGRESS
    assert state["gates"]["SECURITY"] == GateState.NOT_APPLICABLE
    assert state["gates"]["RELEASE"] == GateState.BLOCKED
