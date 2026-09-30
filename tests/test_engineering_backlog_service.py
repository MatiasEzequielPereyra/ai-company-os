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

    def fake_run(
        script: Path,
        arguments: list[str],
        progress=None,
    ) -> str:
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



def test_feature_backlog_waits_for_all_initial_planning_tasks(
    tmp_path,
):
    write_work_request(
        tmp_path,
        "WR-300",
        "FEATURE",
    )

    write(
        tmp_path / "tasks" / "AICO-300.md",
        """# AICO-300 - Engineering plan

ID: AICO-300
Status: DONE
Owner: engineering-manager
Work request: WR-300
""",
    )

    write(
        tmp_path / "tasks" / "AICO-301.md",
        """# AICO-301 - QA planning

ID: AICO-301
Status: BACKLOG
Owner: qa
Work request: WR-300
""",
    )

    write(
        tmp_path
        / "docs"
        / "engineering"
        / "agent-reports"
        / "AICO-300.md",
        "# Engineering Manager plan\n",
    )

    service = EngineeringBacklogService()

    assert service.ready_sources(
        tmp_path,
        ["WR-300"],
    ) == []

    write(
        tmp_path / "tasks" / "AICO-301.md",
        """# AICO-301 - QA planning

ID: AICO-301
Status: DONE
Owner: qa
Work request: WR-300
""",
    )

    sources = service.ready_sources(
        tmp_path,
        ["WR-300"],
    )

    assert [source.task_id for source in sources] == [
        "AICO-300"
    ]



def test_downstream_engineering_manager_task_is_not_a_backlog_source(
    tmp_path,
):
    write_work_request(
        tmp_path,
        "WR-400",
        "FEATURE",
    )

    write(
        tmp_path / "tasks" / "AICO-400.md",
        """# AICO-400 - Engineering plan

ID: AICO-400
Status: DONE
Owner: engineering-manager
Work request: WR-400
""",
    )

    write(
        tmp_path / "tasks" / "AICO-401.md",
        """# AICO-401 - Implementation authorization

ID: AICO-401
Status: DONE
Owner: engineering-manager
Work request: WR-400
Source plan: AICO-400
Work kind: DECISION
""",
    )

    write(
        tmp_path
        / "docs"
        / "engineering"
        / "agent-reports"
        / "AICO-400.md",
        "# Engineering Manager plan\n",
    )

    write(
        tmp_path
        / "docs"
        / "engineering"
        / "agent-reports"
        / "AICO-401.md",
        "# Downstream decision report\n",
    )

    write(
        tmp_path
        / "docs"
        / "engineering"
        / "plans"
        / "AICO-400-engineering-backlog-tasks.md",
        "# mapping\n",
    )

    service = EngineeringBacklogService()

    sources = service.ready_sources(
        tmp_path,
        ["WR-400"],
    )

    assert [source.task_id for source in sources] == [
        "AICO-400"
    ]
    assert service.pending_sources(
        tmp_path,
        ["WR-400"],
    ) == []


def test_generate_and_materialize_forwards_progress_callback(
    tmp_path,
    monkeypatch,
):
    write_work_request(
        tmp_path,
        "WR-500",
        "FEATURE",
    )

    write(
        tmp_path / "tasks" / "AICO-500.md",
        """# AICO-500 - Plan feature

ID: AICO-500
Status: DONE
Owner: engineering-manager
Work request: WR-500
""",
    )

    write(
        tmp_path
        / "docs"
        / "engineering"
        / "agent-reports"
        / "AICO-500.md",
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

    progress_events: list[str] = []
    received_callbacks = []

    def fake_run(
        script: Path,
        arguments: list[str],
        progress=None,
    ) -> str:
        received_callbacks.append(progress)

        if progress is not None:
            progress(
                f"stream:{script.name}"
            )

        if script.name == "generate-engineering-backlog.ps1":
            write(
                tmp_path
                / "docs"
                / "engineering"
                / "plans"
                / "AICO-500-engineering-backlog.json",
                "{}\n",
            )
        else:
            write(
                tmp_path
                / "docs"
                / "engineering"
                / "plans"
                / "AICO-500-engineering-backlog-tasks.md",
                "# mapping\n",
            )

        return "ok"

    monkeypatch.setattr(
        service,
        "_run_script",
        fake_run,
    )

    result = service.generate_and_materialize(
        tmp_path,
        ["WR-500"],
        progress=progress_events.append,
    )

    assert result.materialized_source_ids == [
        "AICO-500"
    ]

    assert received_callbacks == [
        progress_events.append,
        progress_events.append,
    ]

    assert (
        "stream:generate-engineering-backlog.ps1"
        in progress_events
    )
    assert (
        "stream:materialize-engineering-backlog.ps1"
        in progress_events
    )

    assert progress_events.index(
        "stream:generate-engineering-backlog.ps1"
    ) < progress_events.index(
        "stream:materialize-engineering-backlog.ps1"
    )


def test_generate_and_materialize_reports_phases_and_runtime_lines(
    tmp_path,
    monkeypatch,
):
    write_work_request(
        tmp_path,
        "WR-501",
        "FEATURE",
    )

    write(
        tmp_path / "tasks" / "AICO-501.md",
        """# AICO-501 - Plan feature

ID: AICO-501
Status: DONE
Owner: engineering-manager
Work request: WR-501
""",
    )

    write(
        tmp_path
        / "docs"
        / "engineering"
        / "agent-reports"
        / "AICO-501.md",
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
    events: list[str] = []

    def fake_run(
        script: Path,
        arguments: list[str],
        progress=None,
    ) -> str:
        if script.name == "generate-engineering-backlog.ps1":
            if progress is not None:
                progress(
                    "Engineering backlog semantic repair retry: "
                    "Ollama / llama3.1:8b"
                )
                progress(
                    "Engineering backlog semantic fallback: "
                    "OpenRouter"
                )

            write(
                tmp_path
                / "docs"
                / "engineering"
                / "plans"
                / "AICO-501-engineering-backlog.json",
                "{}\n",
            )
        else:
            write(
                tmp_path
                / "docs"
                / "engineering"
                / "plans"
                / "AICO-501-engineering-backlog-tasks.md",
                "# mapping\n",
            )

        return "ok"

    monkeypatch.setattr(
        service,
        "_run_script",
        fake_run,
    )

    result = service.generate_and_materialize(
        tmp_path,
        ["WR-501"],
        progress=events.append,
    )

    assert result.materialized_source_ids == [
        "AICO-501"
    ]

    assert events == [
        "Generating engineering backlog from AICO-501",
        "Generating structured engineering backlog...",
        (
            "Engineering backlog semantic repair retry: "
            "Ollama / llama3.1:8b"
        ),
        (
            "Engineering backlog semantic fallback: "
            "OpenRouter"
        ),
        "Materializing engineering backlog...",
        "Engineering backlog materialized.",
    ]


def test_run_script_streams_runtime_lines_to_progress(
    monkeypatch,
):
    from company_os.application.process_stream import (
        StreamedProcessResult,
    )
    from company_os.application import (
        engineering_backlog_service as service_module,
    )

    service = EngineeringBacklogService()
    events: list[str] = []

    monkeypatch.setattr(
        service,
        "_powershell",
        lambda: "powershell.exe",
    )

    def fake_stream(
        command,
        *,
        timeout,
        env=None,
        cwd=None,
        on_line=None,
    ):
        assert timeout == 1800
        assert on_line is not None

        on_line(
            "Engineering backlog semantic repair retry: "
            "Ollama / llama3.1:8b"
        )
        on_line(
            "Engineering backlog semantic fallback: "
            "OpenRouter"
        )

        return StreamedProcessResult(
            returncode=0,
            output=(
                "Engineering backlog semantic repair retry: "
                "Ollama / llama3.1:8b\n"
                "Engineering backlog semantic fallback: "
                "OpenRouter"
            ),
        )

    monkeypatch.setattr(
        service_module,
        "run_streamed_process",
        fake_stream,
    )

    output = service._run_script(
        Path("generate-engineering-backlog.ps1"),
        [
            "-SourceTaskId",
            "AICO-502",
        ],
        progress=events.append,
    )

    assert events == [
        (
            "Engineering backlog semantic repair retry: "
            "Ollama / llama3.1:8b"
        ),
        (
            "Engineering backlog semantic fallback: "
            "OpenRouter"
        ),
    ]

    assert "semantic repair retry" in output
    assert "semantic fallback" in output


def test_run_script_failure_preserves_runtime_output(
    monkeypatch,
):
    import pytest

    from company_os.application.process_stream import (
        StreamedProcessResult,
    )
    from company_os.application import (
        engineering_backlog_service as service_module,
    )

    service = EngineeringBacklogService()

    monkeypatch.setattr(
        service,
        "_powershell",
        lambda: "powershell.exe",
    )

    def fake_stream(
        command,
        *,
        timeout,
        env=None,
        cwd=None,
        on_line=None,
    ):
        return StreamedProcessResult(
            returncode=17,
            output=(
                "Provider failed: Ollama\n"
                "specific backlog runtime failure"
            ),
        )

    monkeypatch.setattr(
        service_module,
        "run_streamed_process",
        fake_stream,
    )

    with pytest.raises(
        RuntimeError,
        match="specific backlog runtime failure",
    ):
        service._run_script(
            Path("generate-engineering-backlog.ps1"),
            [],
        )


def test_run_script_preserves_timeout_contract(
    monkeypatch,
):
    import subprocess
    import pytest

    from company_os.application import (
        engineering_backlog_service as service_module,
    )

    service = EngineeringBacklogService()
    observed_timeouts: list[int] = []

    monkeypatch.setattr(
        service,
        "_powershell",
        lambda: "powershell.exe",
    )

    def fake_stream(
        command,
        *,
        timeout,
        env=None,
        cwd=None,
        on_line=None,
    ):
        observed_timeouts.append(timeout)

        raise subprocess.TimeoutExpired(
            command,
            timeout,
            output="partial backlog output",
        )

    monkeypatch.setattr(
        service_module,
        "run_streamed_process",
        fake_stream,
    )

    with pytest.raises(
        subprocess.TimeoutExpired,
    ) as exc_info:
        service._run_script(
            Path("generate-engineering-backlog.ps1"),
            [],
        )

    assert observed_timeouts == [1800]
    assert exc_info.value.output == (
        "partial backlog output"
    )
