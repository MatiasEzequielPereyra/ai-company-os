import json

from company_os.application.runtime_adapter import RuntimeAdapter


def prepare_contract(root):
    files = [
        "scripts/run-agent-task.ps1",
        "scripts/run-active-agents.ps1",
        "scripts/provider-router.ps1",
        "scripts/providers/invoke-codex.ps1",
        "schemas/agent-result.schema.json",
    ]

    for relative in files:
        path = root / relative
        path.parent.mkdir(
            parents=True,
            exist_ok=True,
        )
        path.write_text(
            "fixture",
            encoding="utf-8",
        )


def test_runtime_contract_detection(tmp_path):
    prepare_contract(tmp_path)

    result = RuntimeAdapter().inspect(
        tmp_path
    )

    assert (
        result.runtime_contract_ready
        is True
    )


def test_runtime_reads_agent_result(tmp_path):
    prepare_contract(tmp_path)

    runtime = (
        tmp_path
        / ".codex"
        / "runtime"
    )

    runtime.mkdir(
        parents=True
    )

    result_path = (
        runtime
        / "AICO-002-result.json"
    )

    result_path.write_text(
        json.dumps(
            {
                "outcome": "COMPLETED",
                "summary": "Done",
            }
        ),
        encoding="utf-8",
    )

    reports = (
        tmp_path
        / "docs"
        / "engineering"
        / "agent-reports"
    )

    reports.mkdir(
        parents=True
    )

    (
        reports
        / "AICO-002.md"
    ).write_text(
        """# Agent Report - AICO-002

Generated: 2026-09-23T15:00:00Z
Owner: backend
Provider: Codex
Model: gpt-test
Outcome: COMPLETED
""",
        encoding="utf-8",
    )

    result = RuntimeAdapter().inspect(
        tmp_path
    )

    assert result.parsed_event_count == 1

    execution = result.executions[0]

    assert execution.task_id == "AICO-002"
    assert execution.owner == "backend"
    assert execution.provider == "Codex"
    assert execution.outcome == "COMPLETED"


def test_runtime_does_not_invent_live_state(tmp_path):
    prepare_contract(tmp_path)

    result = RuntimeAdapter().inspect(
        tmp_path
    )

    assert (
        result.authoritative_live_state
        is False
    )

    assert result.live_agents == []