from pathlib import Path

from company_os.application.status_service import StatusService
from company_os.domain.models import AgentWorkState, TaskStatus, WorkflowPhase


FIXTURE = Path(__file__).parent / "fixtures" / "minimal_repo"


def test_status_snapshot_from_repository():
    snapshot = StatusService().get_status(FIXTURE)

    assert snapshot.project.name == "minimal_repo"
    assert snapshot.project.phase == WorkflowPhase.IN_PROGRESS
    assert snapshot.project.phase_derived is True
    assert snapshot.project.objective == "Ship the first CLI status vertical slice."
    assert snapshot.tasks.total == 1
    assert snapshot.tasks.active == 1
    assert snapshot.tasks.active_tasks[0].status == TaskStatus.ACTIVE
    backend = next(a for a in snapshot.agents if a.id == "backend")
    assert backend.work_state == AgentWorkState.WORKING
    assert backend.current_task_ids == ["AICO-001"]
    assert snapshot.next_action is not None
    assert snapshot.next_action.task_ids == ["AICO-001"]


def test_waiting_agent_stale_gates_and_multi_owner_next_action(tmp_path):
    (tmp_path / ".codex" / "state").mkdir(parents=True)
    (tmp_path / "tasks").mkdir()
    (tmp_path / "AGENTS.md").write_text("# Agents\n", encoding="utf-8")
    (tmp_path / ".codex" / "config.toml").write_text(
        '[agents]\nenabled = true\n\n'
        '[agents.pm]\ndescription = "PM"\nconfig_file = "./agents/pm.toml"\n\n'
        '[agents.cto]\ndescription = "CTO"\nconfig_file = "./agents/cto.toml"\n\n'
        '[agents.engineering_manager]\ndescription = "EM"\nconfig_file = "./agents/engineering-manager.toml"\n',
        encoding="utf-8",
    )
    (tmp_path / ".codex" / "state" / "company-state.md").write_text(
        "# Company State\n\n## Current Project Phase\n\n-\n\n## Current Objective\n\n-\n\n"
        "## Quality Gates\n\n### Product\nNOT_STARTED\n### Architecture\nNOT_STARTED\n"
        "### Implementation\nNOT_STARTED\n### Review\nNOT_STARTED\n### QA\nNOT_STARTED\n"
        "### Security\nNOT_STARTED\n### Release\nNOT_STARTED\n### Final\nNOT_STARTED\n",
        encoding="utf-8",
    )
    (tmp_path / ".codex" / "state" / "current-sprint.md").write_text(
        "# Current Sprint\n\n## Sprint Goal\n\nShip multi-agent work.\n",
        encoding="utf-8",
    )
    (tmp_path / ".codex" / "state" / "blockers.md").write_text("# Blockers\n\n## Active Blockers\n\n-\n", encoding="utf-8")

    def task(task_id, title, owner, status, deps="-", evidence="-"):
        return (
            f"# {task_id} - {title}\n\n## Metadata\n\nID: {task_id}\nStatus: {status}\nPriority: P1\nOwner: {owner}\n"
            f"Workflow phase: IN_PROGRESS\n\n## Objective\n\n{title}\n\n## Dependencies\n\n{deps}\n\n## Evidence\n\n{evidence}\n"
        )

    (tmp_path / "tasks" / "AICO-001.md").write_text(task("AICO-001", "Product work", "pm", "ACTIVE"), encoding="utf-8")
    (tmp_path / "tasks" / "AICO-002.md").write_text(task("AICO-002", "Architecture work", "cto", "ACTIVE"), encoding="utf-8")
    (tmp_path / "tasks" / "AICO-003.md").write_text(task("AICO-003", "Execution plan", "engineering-manager", "BACKLOG", "- AICO-001\n- AICO-002"), encoding="utf-8")
    (tmp_path / "tasks" / "AICO-004.md").write_text(task("AICO-004", "Prior completed work", "pm", "DONE", evidence="- Review passed\n- QA test passed\n- Security gate passed"), encoding="utf-8")

    snapshot = StatusService().get_status(tmp_path)

    em = next(a for a in snapshot.agents if a.id == "engineering-manager")
    assert em.work_state == AgentWorkState.WAITING
    assert em.current_task_ids == ["AICO-003"]
    assert snapshot.project.objective == "Ship multi-agent work."
    assert snapshot.next_action is not None
    assert snapshot.next_action.owner is None
    assert snapshot.next_action.task_ids == ["AICO-001", "AICO-002"]
    assert "across 2 tasks" in snapshot.next_action.description

    gates = {gate.name: gate for gate in snapshot.gates}
    assert gates["IMPLEMENTATION"].state.value == "NOT_STARTED"
    assert gates["IMPLEMENTATION"].stale is True
    assert gates["REVIEW"].stale is True
    assert gates["QA"].stale is True
    assert gates["SECURITY"].stale is True
