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


def test_feature_without_implementation_is_engineering_pending(tmp_path):
    write(
        tmp_path
        / "docs"
        / "engineering"
        / "work-requests"
        / "WR-003.md",
        """# WR-003

## Metadata

ID: WR-003
Type: FEATURE
Priority: P0
Created: 2026-09-24T00:00:00Z
Status: PLANNING

## Objective

Implement sample feature
""",
    )

    for task_id, owner in (
        ("AICO-020", "pm"),
        ("AICO-021", "cto"),
        ("AICO-022", "engineering-manager"),
    ):
        write(
            tmp_path
            / "tasks"
            / f"{task_id}.md",
            f"""# {task_id}

ID: {task_id}
Status: DONE
Owner: {owner}
Work request: WR-003
""",
        )

    items = WorkRequestService().list_work_requests(
        tmp_path
    )

    assert len(items) == 1
    assert items[0].request_type == "FEATURE"
    assert items[0].display_status == "ENGINEERING_PENDING"


def test_dynamic_scope_discovers_materialized_downstream_tasks(tmp_path):
    write(
        tmp_path
        / "tasks"
        / "AICO-030.md",
        """# AICO-030

ID: AICO-030
Status: DONE
Owner: engineering-manager
Work request: WR-030
""",
    )

    service = WorkRequestService()

    assert service.resolve_task_ids(
        tmp_path,
        ["WR-030"],
    ) == ["AICO-030"]

    write(
        tmp_path
        / "tasks"
        / "AICO-031.md",
        """# AICO-031

ID: AICO-031
Status: BACKLOG
Owner: frontend
Work request: WR-030
Source plan: AICO-030
Work kind: IMPLEMENTATION
""",
    )

    assert service.resolve_task_ids(
        tmp_path,
        ["WR-030"],
    ) == [
        "AICO-030",
        "AICO-031",
    ]

    downstream = service.tasks_for_request(
        tmp_path,
        "WR-030",
    )[1]

    assert downstream.work_kind == "IMPLEMENTATION"
    assert downstream.source_plan == "AICO-030"


def test_request_ids_for_task_ids_recovers_legacy_scope(
    tmp_path,
):
    tasks = tmp_path / "tasks"
    tasks.mkdir()

    (
        tasks
        / "AICO-001.md"
    ).write_text(
        """# AICO-001

ID: AICO-001
Status: DONE
Owner: engineering-manager
Work request: WR-001
""",
        encoding="utf-8",
    )

    service = WorkRequestService()

    assert service.request_ids_for_task_ids(
        tmp_path,
        ["AICO-001"],
    ) == ["WR-001"]
