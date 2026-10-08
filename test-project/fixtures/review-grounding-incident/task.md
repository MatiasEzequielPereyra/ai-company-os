# AICO-002 - Sanitized incident replay

## Metadata

ID: AICO-002
Status: REVIEW
Priority: P1
Owner: cto
Workflow phase: REVIEW
Workflow profile: standard

## Objective

Validate architecture, technical constraints, contracts and risks for: Extend the existing Python task CLI with persistent JSON-backed task management. Required behavior: add a task with text; list all tasks; complete a task by ID; remove a task by ID; keep stable numeric task IDs; persist tasks across independent CLI process executions; represent completed and pending tasks clearly; unknown task IDs must return a non-zero exit status with a useful error message; invalid operations must not corrupt the stored task data; use `.taskcli/tasks.json` as the default project-local data location; support a `TASKCLI_DATA_FILE` environment variable so automated tests can isolate storage; add `.taskcli/` to `.gitignore`; preserve the existing empty-list behavior; add automated tests for the new behavior; update README usage documentation. The existing application must remain functional.

## Acceptance Criteria

- [ ] Role-owned deliverable is produced.
- [ ] Open questions and blockers are explicit.
- [ ] Evidence is recorded in this task.
- [ ] Applicable downstream dependencies are ready.

## Dependencies

- NONE

## Evidence

-

## Transition Log

-

## Notes

-
