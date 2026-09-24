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

They return only a structured writable change set matching `schemas/writable-change-set.schema.json`.

`Provider Auto` is restricted to configured free writable models. Explicit paid model selection, if ever allowed by a caller, must never be introduced as an automatic fallback.

## Local application boundary

The runtime applies validated `WRITE`/`DELETE` operations locally.

Verification commands are treated as untrusted suggestions until they pass `.codex/writable-policy.json` and the single-command literal parser.

The runtime must never use `Invoke-Expression` for model output.

## Corrective work

A task returned to `READY` after `CHANGES_REQUIRED` may reuse its existing task worktree and prior diff.

The runtime reactivates it through the normal lifecycle guard, applies the correction on top of the existing worktree state, verifies it, and submits a new result.

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
