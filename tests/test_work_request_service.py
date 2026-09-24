from company_os.application.work_request_service import (
    WorkRequestService,
)


def write(path, value):
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    path.write_text(
        value,
        encoding="utf-8",
    )


def test_lists_persistent_work_requests(tmp_path):
    write(
        tmp_path
        / "docs"
        / "engineering"
        / "work-requests"
        / "WR-001.md",
        """# WR-001

## Metadata

ID: WR-001
Type: AUDIT
Priority: P1
Created: 2026-09-23T00:00:00Z
Status: PLANNING

## Objective

Audit application for production
""",
    )

    write(
        tmp_path
        / "tasks"
        / "AICO-001.md",
        """# AICO-001

ID: AICO-001
Status: BACKLOG
Owner: pm
Work request: WR-001
""",
    )

    service = WorkRequestService()

    items = service.list_work_requests(
        tmp_path
    )

    assert len(items) == 1
    assert items[0].id == "WR-001"
    assert items[0].display_status == "PREPARED"
    assert items[0].task_ids == [
        "AICO-001"
    ]


def test_reopen_reconstructs_plan_context(tmp_path):
    write(
        tmp_path
        / "docs"
        / "engineering"
        / "work-requests"
        / "WR-002.md",
        """# WR-002

## Metadata

ID: WR-002
Type: FEATURE
Priority: P1
Created: 2026-09-23T00:00:00Z
Status: PLANNING

## Objective

Add feature
""",
    )

    write(
        tmp_path
        / "tasks"
        / "AICO-010.md",
        """# AICO-010

ID: AICO-010
Status: ACTIVE
Owner: cto
Work request: WR-002
""",
    )

    reopened = (
        WorkRequestService()
        .reopen(
            tmp_path,
            "WR-002",
        )
    )

    assert reopened.summary.display_status == "ACTIVE"

    assert (
        reopened.preparation.created_task_ids
        == ["AICO-010"]
    )

    assert reopened.plan.project_root == str(
        tmp_path.resolve()
    )
