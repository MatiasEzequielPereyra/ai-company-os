# TUI Runtime Integration Protocol

## Purpose

The Company CLI/TUI is an operator surface over canonical AI Company OS state. It does not define task lifecycle semantics and must not synthesize status transitions.

## Source of truth

The TUI reads canonical project artifacts:

- `tasks/<ID>.md` for task metadata and current status;
- `docs/engineering/results/<ID>-result-*.md` for execution results;
- `docs/engineering/writable-evidence/<ID>.md` for writable execution evidence;
- `docs/engineering/reviews/<ID>-review-*.md` for review evidence;
- `docs/engineering/qa/<ID>-qa.md` for QA evidence;
- `docs/engineering/security/<ID>-security.md` for security evidence;
- `docs/engineering/final-approvals/<ID>-final.md` for final approval evidence.

The TUI may derive a display model from those artifacts, but it must never persist a competing lifecycle state.

## Canonical actions

### READY / ACTIVE implementation

Writable implementation is delegated only to:

`scripts/run-writable-agent.ps1`

Inputs:

- task ID;
- project path;
- task-specific worktree path;
- provider;
- optional model.

The runtime accepts `READY` or `ACTIVE`.

- `READY` is advanced canonically to `ACTIVE` before provider execution.
- successful implementation and verification are submitted through the Result Intake Engine and end in `REVIEW`;
- a provider/runtime implementation blocker is recorded canonically as `BLOCKED`;
- source changes remain in the isolated task worktree;
- the runtime performs no commit, merge, push, deploy or release.

### REVIEW

Review outcomes are canonicalized by `scripts/review-task.ps1`.

- `APPROVE` -> `QA`
- `CHANGES_REQUIRED` -> `READY`

The TUI must show `CHANGES_REQUIRED` as a review outcome/retry reason, not as a new task status.

A corrective retry reuses the task worktree and invokes the writable runtime again once the task is `READY` or `ACTIVE`.

### QA

QA outcomes are canonicalized by `scripts/qa-task.ps1`.

- `PASS` -> `SECURITY`
- `FAIL` -> `READY`

### SECURITY

Security outcomes are canonicalized by `scripts/security-task.ps1`.

- `FAIL` -> `READY`
- `PASS` or allowed `NOT_APPLICABLE` satisfies the gate but does not make the task `DONE`.

High-assurance tasks require explicit security `PASS`.

### DONE

Final approval is canonicalized only by `scripts/finalize-task.ps1`.

- `APPROVE` -> `DONE`
- `REJECT` -> `READY`

Final approval remains a human/CEO authorization step. The TUI may present the action, but must not auto-approve it.

## BLOCKED

`BLOCKED` is displayed from the canonical task status and latest result/evidence.

The TUI should surface:

- summary;
- blockers;
- recommended next action;
- provider/model when recorded;
- worktree path/branch when recorded.

The TUI must not silently convert `BLOCKED` to `READY`. Retry requires an explicit canonical transition/action.

## Evidence and diff

For writable tasks, the TUI should expose:

- changed paths from writable evidence;
- verification performed;
- provider/model;
- worktree/branch;
- Git diff summary or diff read from the isolated worktree;
- latest review/QA/security/final artifacts when present.

Evidence display is read-only. The TUI must not edit artifacts directly.

## Operator flow

A clean end-to-end implementation flow is:

`Objective -> planning/readiness -> READY -> writable execution -> ACTIVE -> REVIEW -> QA -> SECURITY -> human final approval -> DONE`

Corrective flow:

`REVIEW + CHANGES_REQUIRED -> READY -> writable retry -> REVIEW`

QA/security/final rejection likewise returns through canonical scripts to `READY`.

## Safety boundary

The TUI must never:

- write source files directly;
- execute provider-generated shell;
- mutate the primary checkout for implementation;
- create lifecycle transitions by editing task Markdown;
- merge, push, deploy or release as a side effect of writable execution;
- auto-approve final human authorization.

The TUI may execute canonical AI Company OS scripts and then reread canonical artifacts to refresh its display model.
