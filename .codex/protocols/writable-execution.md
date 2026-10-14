# Writable Execution Protocol

## Purpose

Writable execution is a separate runtime from the read-only audit/analysis runner.

- `scripts/run-agent-task.ps1` remains read-only.
- `scripts/run-writable-agent.ps1` is used only for authorized implementation tasks.

## Source plane

Production/source changes may be applied only inside the task-specific registered Git worktree:

- task `AICO-013`
- branch `aico/aico-013`
- isolated worktree such as `<project>-worktrees/AICO-013`

The primary checkout must never receive product/source writes from the writable runtime.

The runtime must reject:

- the primary checkout as a writable workspace;
- unregistered worktrees;
- branch/task mismatches;
- absolute paths;
- path traversal;
- `.git`;
- lifecycle/control-plane paths;
- environment/secret/key/credential paths;
- symlink, junction or reparse-point escapes.

## Authorization and dependency preflight

`READY` and `ACTIVE` describe task lifecycle only; neither status grants
implementation permission. Before a writable task can be activated or a
provider invoked, the runner requires the task's canonical Work Request at
`docs/engineering/work-requests/<Work request>.md` to contain exactly one
`Authorization Receipt` section and validates that receipt against the current
task.

The receipt reuses the Work Request's existing `Authorization Receipt`
contract. It must identify a requester and request date (`Requested by` and
`Created` metadata), requested action, permitted scope, retained restrictions,
and the following explicit implementation fields:

- `Implementation authorization: AUTHORIZED`
- `Authorized task: <exact task ID>`
- `Authorized operation: WRITABLE`
- `Authorized execution mode: WRITABLE`
- `Authorized provider invocation: ALLOWED`
- `Authorized write scope: TASK_WORKTREE_ONLY`
- `Authorized scope SHA-256: <64 lowercase or uppercase hex characters>`
- `Authorization expires (UTC): <yyyy-MM-ddTHH:mm:ssZ>`

The permitted scope must include `WRITABLE_IMPLEMENTATION`; the requested
action must name the task. The scope fingerprint binds the task ID, type, work
kind, owner, Work Request, complete Objective section and complete Acceptance
Criteria section. Task and Work Request types must match.
`scripts/writable-authorization-guard.ps1` exposes
`Get-WritableScopeFingerprint` to calculate the fingerprint from canonical task
content. A scope edit, wrong task/operation, expired or malformed receipt,
duplicate/ambiguous field, missing receipt, or retained restriction fails
closed. Writable execution requires `Retained restrictions: NONE`; the guard does
not interpret arbitrary natural-language restrictions. These explicit fields
bind authorization to writable execution, provider invocation and writes limited
to the registered task worktree. New Work Requests initialize all such fields to
`NONE`, so authorization is never inferred from request creation or task state.

Every dependency declared in the task's canonical `Dependencies` section must
resolve to exactly one matching task record whose status is `DONE`. Missing,
ambiguous, malformed or non-DONE dependencies fail closed.

Authorization, dependency state, the task worktree registration/branch and its
baseline are checked before any `READY -> ACTIVE` transition. They are checked
again immediately before provider invocation, and the authorization receipt
text must remain identical across those checks. A failed authorization,
dependency or worktree preflight records the task as `BLOCKED` through the
lifecycle transition engine; it does not invoke a provider or promote the task.
The existing task execution lease remains held throughout these checks and
transition attempts.

This receipt is a validated project authorization record, not a cryptographic
signature. Provider availability/selection remains independently governed by
the existing provider configuration and writable policy; this authorization
guard does not enable or add a provider.

## Control plane

After source application and verification succeed, the canonical control plane may record:

- writable execution evidence;
- task result artifacts;
- lifecycle transitions.

The existing Result Intake Engine remains authoritative for `ACTIVE -> REVIEW`.

This control-plane metadata is not permission to merge, push, deploy, publish or modify the primary checkout source tree.

## Provider boundary

External providers never receive shell access.

They receive:

- task;
- dispatch packet;
- role instructions;
- bounded repository context.

Before the provider call, the runtime resolves file paths explicitly named by the task or dispatch against the isolated worktree. Existing, unambiguous, policy-safe required files are included before generic context and must fit completely inside the writable context budget. Secret-sensitive, protected, ambiguous, oversized or reparse-point targets are rejected explicitly rather than guessed or silently omitted.

They return only a structured writable change set matching `schemas/writable-change-set.schema.json`.

`Provider Auto` is restricted to configured free writable models. Explicit paid model selection, if ever allowed by a caller, must never be introduced as an automatic fallback.

## Diagnostic evidence boundary

For canonical BUG implementation work, writable execution must establish diagnostic evidence before the first source mutation.

- the provider proposes a command-based reproduction signal and falsifiable hypotheses;
- the runtime validates every diagnostic command through the same local safe-command parser used for verification;
- the runtime executes the frozen reproduction signal before source writes and records the actual exit/result receipt;
- a runtime-generated SHA-256 fingerprint identifies the frozen signal;
- hypothesis experiments execute before mutation and their receipts determine whether a claimed confirmed cause is supportable;
- REPAIR requires an evidence-backed confirmed cause; WORKAROUND requires explicit residual risk;
- after application and regression verification, the runtime replays the exact frozen signal;
- the durable artifact is recorded under `docs/engineering/diagnostics/<TASK>-diagnostic-v1.json` and is control-plane evidence, not provider-authored source.

If the original signal does not reproduce the defect, source mutation is refused. If the exact post-fix replay still demonstrates the defect, source changes are restored and the failed attempt remains diagnostic evidence for corrective work.

Manual/procedure evidence may be represented by the diagnostic evidence schema, but automated writable source mutation requires trusted executable/runtime evidence.

## Local application boundary

The runtime applies validated `WRITE`/`DELETE` operations locally.

Verification commands are treated as untrusted suggestions until they pass `.codex/writable-policy.json` and the single-command literal parser.

The runtime must never use `Invoke-Expression` for model output.

## Corrective work

A task returned to `READY` after `CHANGES_REQUIRED` may reuse its existing task worktree and prior diff.

The runtime reactivates it through the normal lifecycle guard, applies the correction on top of the existing worktree state, verifies it, and submits a new result.

An authoritative corrective retry may correct only its owner handoff report when an existing policy-safe implementation candidate diff is present. In that case `changes=[]` is permitted, real verification commands remain required and are executed, and the runtime publishes `report_markdown` through its canonical control-plane path. Fresh implementation still requires an effective source change; a no-op WRITE does not qualify as report-only correction. Providers must not WRITE or DELETE agent reports, writable evidence, dispatch packets, work requests, plans, or other protected operational artifacts in the task source worktree.

## Prohibited automatic actions

Writable execution never performs:

- commit;
- merge;
- rebase;
- push;
- deploy;
- release;
- package publication;
- destructive Git reset;
- secret retrieval.

Those remain separate authorized human/company workflow actions.
