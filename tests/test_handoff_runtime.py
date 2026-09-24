from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

from company_os.application.handoff_service import build_handoffs
from company_os.domain.models import TaskStatus


def make_task(
    tmp_path,
    *,
    status=TaskStatus.ACTIVE,
    handoff="",
    transitions="",
):
    path = tmp_path / "AICO-001.md"

    path.write_text(
        f"""# AICO-001 - Test

## Handoff

{handoff}

## Transition Log

{transitions}
""",
        encoding="utf-8",
    )

    return SimpleNamespace(
        id="AICO-001",
        owner="engineering-manager",
        status=status,
        updated=datetime(
            2026,
            9,
            22,
            17,
            30,
            tzinfo=timezone.utc,
        ),
        source_path=path,
    )


def test_explicit_handoff(tmp_path):
    task = make_task(
        tmp_path,
        handoff="Next agent: qa",
    )

    result = build_handoffs([task])

    assert any(
        item.kind == "EXPLICIT"
        and item.to_actor == "qa"
        for item in result
    )


def test_done_task_handoff_is_stale(tmp_path):
    task = make_task(
        tmp_path,
        status=TaskStatus.DONE,
        handoff="Next agent: qa",
    )

    result = build_handoffs([task])

    explicit = next(
        item
        for item in result
        if item.kind == "EXPLICIT"
    )

    assert explicit.stale is True


def test_actor_change_is_detected(tmp_path):
    task = make_task(
        tmp_path,
        transitions=(
            "- 2026-09-22T17:20:00Z - "
            "engineering-manager - ACTIVE -> REVIEW - Done.\n"
            "- 2026-09-22T17:25:00Z - "
            "qa - QA -> SECURITY - QA passed."
        ),
    )

    result = build_handoffs([task])

    assert any(
        item.kind == "OBSERVED_ACTOR_CHANGE"
        and item.from_actor
        == "engineering-manager"
        and item.to_actor == "qa"
        for item in result
    )