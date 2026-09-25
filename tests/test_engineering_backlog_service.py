from __future__ import annotations

from pathlib import Path

from company_os.application.engineering_backlog_service import (
    EngineeringBacklogService,
)


def write(path: Path, value: str) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )
    path.write_text(
        value,
        encoding="utf-8",
    )



def write_work_request(
    root: Path,
    request_id: str,
    request_type: str,
) -> None:
    write(
        root
        / "docs"
        / "engineering"
        / "work-requests"
        / f"{request_id}.md",
        f"""# {request_id} - Work Request

ID: {request_id}
Type: {request_type}
Priority: P1
Created: 2026-09-24T00:00:00Z
Status: PLANNING

## Objective

Fixture objective
""",
    )


def test_detects_done_engineering_manager_with_report(tmp_path):
    write_work_request(
        tmp_path,
        "WR-100",
        "FEATURE",
    )

    write(
        tmp_path / "tasks" / "AICO-100.md",
        """# AICO-100 - Plan feature

ID: AICO-100
Status: DONE
Owner: engineering-manager
Work request: WR-100
""",
    )

    write(
        tmp_path
        / "docs"
        / "engineering"
        / "agent-reports"
        / "AICO-100.md",
        "# Engineering Manager plan\n",
    )

    service = EngineeringBacklogService()

    sources = service.ready_sources(
        tmp_path,
        ["WR-100"],
    )

    assert [source.task_id for source in sources] == [
        "AICO-100"
    ]
    assert sources[0].work_request_id == "WR-100"
    assert sources[0].materialized is False


def test_generate_and_materialize_uses_canonical_scripts_idempotently(
    tmp_path,
    monkeypatch,
):
    write_work_request(
        tmp_path,
        "WR-101",
        "FEATURE",
    )

    write(
        tmp_path / "tasks" / "AICO-101.md",
        """# AICO-101 - Plan feature

ID: AICO-101
Status: DONE
Owner: engineering-manager
Work request: WR-101
""",
    )

    write(
        tmp_path
        / "docs"
        / "engineering"
        / "agent-reports"
        / "AICO-101.md",
        "# Engineering Manager plan\n",
    )

    write(
        tmp_path
        / "scripts"
        / "generate-engineering-backlog.ps1",
        "# fixture\n",
    )
    write(
        tmp_path
        / "scripts"
        / "materialize-engineering-backlog.ps1",
        "# fixture\n",
    )

    service = EngineeringBacklogService()
    calls: list[tuple[str, list[str]]] = []

    def fake_run(script: Path, arguments: list[str]) -> str:
        calls.append(
            (
                script.name,
                list(arguments),
            )
        )

        if script.name == "generate-engineering-backlog.ps1":
            write(
                tmp_path
                / "docs"
                / "engineering"
                / "plans"
                / "AICO-101-engineering-backlog.json",
                "{}\n",
            )
        else:
            write(
                tmp_path
                / "docs"
                / "engineering"
                / "plans"
                / "AICO-101-engineering-backlog-tasks.md",
                "# mapping\n",
            )

        return "ok"

    monkeypatch.setattr(
        service,
        "_run_script",
        fake_run,
    )

    first = service.generate_and_materialize(
        tmp_path,
        ["WR-101"],
    )

    assert first.materialized_source_ids == [
        "AICO-101"
    ]
    assert first.skipped_source_ids == []
    assert [
        name
        for name, _arguments in calls
    ] == [
        "generate-engineering-backlog.ps1",
        "materialize-engineering-backlog.ps1",
    ]

    calls.clear()

    second = service.generate_and_materialize(
        tmp_path,
        ["WR-101"],
    )

    assert second.materialized_source_ids == []
    assert second.skipped_source_ids == [
        "AICO-101"
    ]
    assert calls == []


def test_documentation_request_does_not_offer_engineering_backlog(
    tmp_path,
):
    write_work_request(
        tmp_path,
        "WR-200",
        "DOCUMENTATION",
    )

    write(
        tmp_path / "tasks" / "AICO-200.md",
        """# AICO-200 - Prepare documentation

ID: AICO-200
Status: DONE
Owner: engineering-manager
Work request: WR-200
""",
    )

    write(
        tmp_path
        / "docs"
        / "engineering"
        / "agent-reports"
        / "AICO-200.md",
        "# Documentation report\n",
    )

    service = EngineeringBacklogService()

    assert service.ready_sources(
        tmp_path,
        ["WR-200"],
    ) == []
    assert service.pending_sources(
        tmp_path,
        ["WR-200"],
    ) == []
