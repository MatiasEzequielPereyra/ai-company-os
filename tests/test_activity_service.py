from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

from company_os.application.activity_service import build_activity


def make_task(
    tmp_path,
    *,
    task_id="AICO-001",
    evidence=None,
    transition_log="",
):
    path = tmp_path / f"{task_id}.md"

    path.write_text(
        f"""# {task_id} - Test task

## Transition Log

{transition_log}
""",
        encoding="utf-8",
    )

    return SimpleNamespace(
        id=task_id,
        owner="backend",
        created=datetime(
            2026,
            9,
            22,
            10,
            0,
            tzinfo=timezone.utc,
        ),
        updated=datetime(
            2026,
            9,
            22,
            12,
            0,
            tzinfo=timezone.utc,
        ),
        evidence=evidence or [],
        source_path=path,
    )


def test_activity_contains_created_and_updated(tmp_path):
    task = make_task(tmp_path)

    events = build_activity([task])

    kinds = {
        event.kind
        for event in events
    }

    assert "TASK_CREATED" in kinds
    assert "TASK_UPDATED" in kinds


def test_activity_reads_evidence(tmp_path):
    task = make_task(
        tmp_path,
        evidence=[
            "2026-09-22T11:00:00Z - Tests passed."
        ],
    )

    events = build_activity([task])

    assert any(
        event.kind == "EVIDENCE"
        and event.message == "Tests passed."
        for event in events
    )


def test_activity_reads_transition_log(tmp_path):
    task = make_task(
        tmp_path,
        transition_log=(
            "- 2026-09-22T10:30:00Z - "
            "BACKLOG -> READY"
        ),
    )

    events = build_activity([task])

    assert any(
        event.kind == "TRANSITION"
        and "BACKLOG -> READY" in event.message
        for event in events
    )


def test_activity_is_newest_first(tmp_path):
    task = make_task(
        tmp_path,
        evidence=[
            "2026-09-22T15:00:00Z - Latest event."
        ],
    )

    events = build_activity([task])

    assert (
        events[0].timestamp
        >= events[-1].timestamp
    )