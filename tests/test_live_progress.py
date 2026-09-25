from __future__ import annotations

import subprocess
import sys
from types import SimpleNamespace

from company_os.application.process_stream import (
    run_streamed_process,
)
from company_os.cli.operation_progress import (
    OperationProgressState,
)
from company_os.cli.screens import (
    plan_control as plan_control_module,
)
from company_os.cli.screens.plan_control import (
    PlanControlScreen,
)


def _screen() -> PlanControlScreen:
    return PlanControlScreen(
        SimpleNamespace(
            project_root=".",
            project_name="test",
        ),
        SimpleNamespace(
            created_task_ids=[],
            work_request_ids=[],
        ),
    )


def test_progress_state_updates_spinner_elapsed_and_bar():
    state = OperationProgressState()

    assert state.start(
        kind="gates",
        title="QUALITY GATES",
        task_ids=["AICO-001"],
        initial_event="Starting gates",
        now=100.0,
    )

    first_spinner = state.spinner()
    first_bar = state.activity_bar()

    state.tick()

    assert state.spinner() != first_spinner
    assert state.activity_bar() != first_bar
    assert state.elapsed_text(
        now=137.0
    ) == "00:37"
    assert state.busy


def test_progress_keeps_only_last_five_events():
    state = OperationProgressState()

    state.start(
        kind="analysis",
        title="RUN AGENTS",
        task_ids=["AICO-001"],
        initial_event="event-0",
        now=1.0,
    )

    for index in range(1, 8):
        state.add_event(
            f"event-{index}"
        )

    assert len(
        state.recent_events
    ) == 5
    assert state.recent_events == [
        "event-3",
        "event-4",
        "event-5",
        "event-6",
        "event-7",
    ]
    assert state.last_event == "event-7"


def test_gate_progress_tracks_each_stage():
    state = OperationProgressState()

    state.start(
        kind="gates",
        title="QUALITY GATES",
        task_ids=["AICO-001"],
        initial_event="Starting gates",
        now=1.0,
    )

    state.begin_gate(
        "AICO-001",
        "REVIEW",
    )

    assert (
        state.gate_states["REVIEW"]
        == "CURRENT"
    )

    state.complete_gate(
        "AICO-001",
        "REVIEW",
    )
    state.begin_gate(
        "AICO-001",
        "QA",
    )

    assert (
        state.gate_states["REVIEW"]
        == "DONE"
    )
    assert (
        state.gate_states["QA"]
        == "CURRENT"
    )


def test_gate_progress_infers_prior_stages_done():
    state = OperationProgressState()

    state.start(
        kind="gates",
        title="QUALITY GATES",
        task_ids=["AICO-001"],
        initial_event="Starting gates",
        now=1.0,
    )

    state.begin_gate(
        "AICO-001",
        "SECURITY",
    )

    assert state.gate_states == {
        "REVIEW": "DONE",
        "QA": "DONE",
        "SECURITY": "CURRENT",
    }


def test_streamed_process_reports_incremental_output():
    events: list[str] = []

    result = run_streamed_process(
        [
            sys.executable,
            "-c",
            (
                "import time;"
                "print('Building context...', flush=True);"
                "time.sleep(0.05);"
                "print('Response received', flush=True)"
            ),
        ],
        timeout=5,
        on_line=events.append,
    )

    assert result.returncode == 0
    assert events == [
        "Building context...",
        "Response received",
    ]
    assert "Building context..." in (
        result.output
    )
    assert "Response received" in (
        result.output
    )


def test_finish_returns_progress_to_idle():
    state = OperationProgressState()

    state.start(
        kind="writable",
        title="Writable",
        task_ids=["AICO-001"],
        initial_event="Starting",
        now=10.0,
    )

    state.finish(
        status="SUCCESS",
        summary="done",
        now=53.0,
    )

    assert not state.busy
    assert state.final_status == "SUCCESS"
    assert state.final_summary == "done"
    assert state.final_duration == "00:43"


def test_plan_control_duplicate_operation_is_rejected(
    monkeypatch,
):
    monkeypatch.setattr(
        plan_control_module,
        "_t",
        lambda _widget, key: key,
    )

    screen = _screen()

    screen.progress.start(
        kind="gates",
        title="QUALITY GATES",
        task_ids=["AICO-001"],
        initial_event="Running",
        now=1.0,
    )
    screen.busy = True

    messages = []

    monkeypatch.setattr(
        screen,
        "notify",
        lambda message, **kwargs:
            messages.append(message),
    )

    assert screen._reject_if_busy()
    assert len(messages) == 1
    assert "AICO-001" in messages[0]


def test_gate_action_does_not_start_twice_while_busy(
    monkeypatch,
):
    monkeypatch.setattr(
        plan_control_module,
        "_t",
        lambda _widget, key: key,
    )

    screen = _screen()

    screen.progress.start(
        kind="gates",
        title="QUALITY GATES",
        task_ids=["AICO-001"],
        initial_event="Running",
        now=1.0,
    )
    screen.busy = True

    monkeypatch.setattr(
        screen,
        "notify",
        lambda *args, **kwargs: None,
    )

    def should_not_run():
        raise AssertionError(
            "Task lookup should not run while busy"
        )

    monkeypatch.setattr(
        screen,
        "_tasks",
        should_not_run,
    )

    screen.action_run_gates()


def test_success_finishes_and_refreshes_plan_control(
    monkeypatch,
):
    monkeypatch.setattr(
        plan_control_module,
        "_t",
        lambda _widget, key: key,
    )

    screen = _screen()

    screen.progress.start(
        kind="analysis",
        title="RUN AGENTS",
        task_ids=["AICO-001"],
        initial_event="Running",
        now=1.0,
    )
    screen.busy = True

    refreshes = []
    notifications = []

    monkeypatch.setattr(
        screen,
        "_refresh_view",
        lambda: refreshes.append(True),
    )
    monkeypatch.setattr(
        screen,
        "notify",
        lambda message, **kwargs:
            notifications.append(message),
    )

    screen._operation_finished(
        "Agent batch finished"
    )

    assert not screen.busy
    assert not screen.progress.busy
    assert (
        screen.progress.final_status
        == "SUCCESS"
    )
    assert refreshes == [True]
    assert notifications


def test_error_finishes_and_refreshes_without_crashing(
    monkeypatch,
):
    monkeypatch.setattr(
        plan_control_module,
        "_t",
        lambda _widget, key: key,
    )

    screen = _screen()

    screen.progress.start(
        kind="gates",
        title="QUALITY GATES",
        task_ids=["AICO-001"],
        initial_event="Running",
        now=1.0,
    )
    screen.busy = True

    refreshes = []
    notifications = []

    monkeypatch.setattr(
        screen,
        "_refresh_view",
        lambda: refreshes.append(True),
    )
    monkeypatch.setattr(
        screen,
        "notify",
        lambda message, **kwargs:
            notifications.append(
                (
                    message,
                    kwargs.get("severity"),
                )
            ),
    )

    screen._operation_failed(
        "Gate execution failed",
        "provider timeout",
    )

    assert not screen.busy
    assert not screen.progress.busy
    assert (
        screen.progress.final_status
        == "ERROR"
    )
    assert refreshes == [True]
    assert notifications[-1][1] == "error"


def test_progress_text_is_ascii_safe_and_bilingual():
    from company_os.cli import i18n

    assert set(
        i18n.PROGRESS_TEXT["es"]
    ) == set(
        i18n.PROGRESS_TEXT["en"]
    )

    assert (
        i18n.ui_text(
            "es",
            "progress_task",
        )
        == "Tarea"
    )

    for value in (
        i18n.PROGRESS_TEXT["es"].values()
    ):
        assert value.isascii(), value



def test_streamed_process_isolates_child_stdin(
    monkeypatch,
):
    calls = []

    class FakeProcess:
        def __init__(self):
            self.stdout = []

        def poll(self):
            return 0

        def wait(self):
            return 0

        def kill(self):
            return None

    def fake_popen(command, **kwargs):
        calls.append(
            (command, kwargs)
        )
        return FakeProcess()

    monkeypatch.setattr(
        "company_os.application."
        "process_stream.subprocess.Popen",
        fake_popen,
    )

    result = run_streamed_process(
        ["fake-runtime"],
        timeout=1,
    )

    assert result.returncode == 0
    assert len(calls) == 1
    assert (
        calls[0][1]["stdin"]
        is subprocess.DEVNULL
    )
