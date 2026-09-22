# Tasks

This directory stores durable AI Company OS work items.

## Source of truth

Each task is a Markdown file under `tasks/`.

The task `Status:` field is authoritative. Directory names are not used as status.

Recommended layout:

```text
tasks/
├── README.md
├── AICO-001.md
├── AICO-002.md
└── AICO-003.md
```

## Lifecycle

Valid task statuses:

```text
BACKLOG -> READY -> ACTIVE -> REVIEW -> QA -> SECURITY -> DONE
```

`BLOCKED` can be used from any unfinished state when work cannot proceed.

A task must not jump directly from `BACKLOG` to `DONE`.

## Required metadata

Every task should include:

- ID
- Title
- Status
- Priority
- Owner
- Created
- Updated
- Objective
- Acceptance Criteria
- Dependencies
- Testing Requirements
- Evidence
- Transition Log

## Scripts

Use the scripts in `scripts/`:

```powershell
.\scripts\new-task.ps1 -Title "Implement feature" -Owner "engineering-manager" -Priority P1
.\scripts\list-tasks.ps1
.\scripts\update-task.ps1 -Id AICO-001 -Status READY -Owner backend
.\scripts\advance-task.ps1 -Id AICO-001 -Status ACTIVE -Actor "engineering-manager" -Reason "Implementation authorized"
```

## Rules

- Do not rename task IDs.
- Do not delete transition history.
- Append evidence instead of replacing it.
- Keep scope changes explicit in the task notes or transition log.
- Update `.codex/state/current-sprint.md` when a task becomes active or done.
