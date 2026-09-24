from company_os.domain.models import GateState
from company_os.repository.company_state_reader import CompanyStateReader
from company_os.repository.sprint_reader import SprintReader


def test_real_format_sprint_goal(tmp_path):
    state_dir = tmp_path / ".codex" / "state"
    state_dir.mkdir(parents=True)

    (state_dir / "current-sprint.md").write_text(
        """# Current Sprint

Generated: 2026-09-22T17:26:39Z

## Sprint Goal

Complete the AI Company OS task management core and make project work persistent.

## Priorities

### P0

-
""",
        encoding="utf-8",
    )

    result = SprintReader().read(tmp_path)

    assert result["goal"] == (
        "Complete the AI Company OS task management core "
        "and make project work persistent."
    )


def test_real_format_quality_gates(tmp_path):
    state_dir = tmp_path / ".codex" / "state"
    state_dir.mkdir(parents=True)

    (state_dir / "company-state.md").write_text(
        """# Company State

## Current Project Phase

-

## Current Objective

-

## Quality Gates

### Product

NOT_STARTED

### Architecture

NOT_STARTED

### Implementation

NOT_STARTED

### Review

NOT_STARTED

### QA

NOT_STARTED

### Security

NOT_STARTED

### Release

NOT_STARTED

### Final

NOT_STARTED

## Last Updated

-
""",
        encoding="utf-8",
    )

    result = CompanyStateReader().read(tmp_path)

    assert result["phase"] is None
    assert result["objective"] is None

    assert result["gates"]["PRODUCT"] == GateState.NOT_STARTED
    assert result["gates"]["ARCHITECTURE"] == GateState.NOT_STARTED
    assert result["gates"]["IMPLEMENTATION"] == GateState.NOT_STARTED
    assert result["gates"]["REVIEW"] == GateState.NOT_STARTED
    assert result["gates"]["QA"] == GateState.NOT_STARTED
    assert result["gates"]["SECURITY"] == GateState.NOT_STARTED
    assert result["gates"]["RELEASE"] == GateState.NOT_STARTED
    assert result["gates"]["FINAL"] == GateState.NOT_STARTED
