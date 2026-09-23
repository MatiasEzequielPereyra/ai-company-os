# Tasks

This directory stores durable AI Company OS work items.

## Source of truth

Each task is a Markdown file under `tasks/`. The task `Status:` field is authoritative; directory names are not used as status.

## Lifecycle

```text
BACKLOG -> READY -> ACTIVE -> REVIEW -> QA -> SECURITY -> DONE
```

`BLOCKED` can interrupt any unfinished task. Project-level phases such as PRODUCT, ARCHITECTURE, RELEASE, or CANCELLED are not additional ticket statuses.

## Workflow profiles

Every new task records one of:

- `lightweight`
- `standard` (default)
- `high-assurance`

Legacy tasks without this field normalize to `standard`. High-assurance tasks require explicit security validation and cannot use `NOT_APPLICABLE` for the SECURITY gate.

## Required metadata

Every task should include ID, title, status, priority, owner, created/updated timestamps, workflow phase, workflow profile, objective, acceptance criteria, dependencies, testing requirements, evidence, and transition history.

## Commands

```powershell
.\scripts\new-task.ps1 -Title "Implement feature" -Owner backend -Priority P1 -WorkflowProfile standard
.\scripts\list-tasks.ps1
.\scripts\update-task.ps1 -Id AICO-001 -Owner backend -Note "Scope clarified"
.\scripts\advance-task.ps1 -Id AICO-001 -Status READY -Actor "engineering-manager" -Reason "Preparation complete"
.\scripts\sync-company-state.ps1
.\scripts\validate-artifacts.ps1
```

## Rules

- Do not rename task IDs.
- Do not delete transition history.
- Append evidence instead of replacing it.
- Keep scope changes explicit.
- READY/ACTIVE status is not by itself permission for destructive actions, merge/push, deployment, or secret access.
- Writable parallel work must use isolated task-specific Git worktrees.
- Regenerate derived company/sprint state after authoritative task changes.
