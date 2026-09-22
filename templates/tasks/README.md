# Tasks

This directory stores durable AI Company OS work items.

Each task is a Markdown file under `tasks/`.

The task `Status:` field is authoritative. Directory names are not used as status.

## Lifecycle

```text
BACKLOG -> READY -> ACTIVE -> REVIEW -> QA -> SECURITY -> DONE
```

`BLOCKED` can be used from any unfinished state when work cannot proceed.

## Commands

```powershell
.\scripts\new-task.ps1 -Title "Implement feature" -Owner "engineering-manager" -Priority P1
.\scripts\list-tasks.ps1
.\scripts\update-task.ps1 -Id AICO-001 -Status READY -Owner backend
.\scripts\advance-task.ps1 -Id AICO-001 -Status ACTIVE -Actor "engineering-manager" -Reason "Implementation authorized"
.\scripts\sync-company-state.ps1
```
