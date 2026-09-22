# AICO-001 — Complete task management core

## Metadata

ID: AICO-001

Status: ACTIVE

Priority: P1

Owner: engineering-manager

Created: 2026-09-22T17:00:00Z

Updated: 2026-09-22T17:00:00Z

Workflow phase: IMPLEMENTATION

---

## Objective

Implement the first functional task management core for AI Company OS so work can be created, listed, updated, advanced through lifecycle states, and reflected in company sprint state.

---

## Context

The repository already had agent roles, workflows, policies, state files and a ticket template, but the operational `tasks/` system was missing. Empty folders were not versioned by Git, and no scripts existed to create or manage real task files.

---

## Requirements

- Add a durable `tasks/` structure based on flat Markdown files.
- Add scripts to create, list, update and advance tasks.
- Add a script to regenerate sprint/company task state.
- Keep `Status:` as the authoritative source of truth.
- Preserve transition history inside each task.
- Avoid relying on empty status folders.

---

## Acceptance Criteria

- [x] `tasks/README.md` explains the model and commands.
- [x] `scripts/new-task.ps1` creates a new `AICO-###.md` task.
- [x] `scripts/list-tasks.ps1` lists tasks and supports status filtering.
- [x] `scripts/update-task.ps1` updates metadata and appends notes/evidence.
- [x] `scripts/advance-task.ps1` validates lifecycle transitions.
- [x] `scripts/sync-company-state.ps1` regenerates `.codex/state/current-sprint.md` from task files.
- [ ] `scripts/new-project.ps1` installs the task scripts and task README into newly generated projects.
- [ ] Local PowerShell smoke test is executed from a clean pull.

---

## Non-Goals

- Build a web UI.
- Add a database.
- Automate agent execution.
- Replace GitHub Issues.

---

## Dependencies

- Existing `.codex/protocols/task-lifecycle.md`.
- Existing `.codex/protocols/company-state.md`.
- Existing `.codex/templates/ticket.md`.

---

## Technical Notes

- Current implementation is filesystem-based and intended to run from repository root.
- This is the foundation for future orchestrator and agent delegation.

---

## Affected Areas

- `tasks/`
- `scripts/`
- `.codex/state/current-sprint.md`
- `scripts/new-project.ps1`

---

## Testing Requirements

Run from repository root:

```powershell
.\scripts\list-tasks.ps1
.\scripts\new-task.ps1 -Title "Smoke test task" -Owner "qa" -Priority P3
.\scripts\advance-task.ps1 -Id AICO-002 -Status READY -Actor "qa" -Reason "Smoke test preparation"
.\scripts\sync-company-state.ps1
```

Then inspect:

```powershell
git diff
```

---

## Evidence

- 2026-09-22T17:00:00Z — Initial scripts and task documentation added directly to GitHub.

---

## Risks

- Scripts still need a local smoke test on Windows PowerShell.
- Manual edits can break metadata if required fields are deleted.

---

## Handoff

Next agent: engineering-manager

---

## Transition Log

- 2026-09-22T17:00:00Z — SYSTEM — CREATED — Task created in ACTIVE because implementation had already started with user authorization.

---

## Notes

- This ticket tracks the first operational version of task persistence.
