# Review Grounded Evidence v1 — additional writer architecture stop

Project: ai-company-os
Revision: 1
Updated: 2026-10-07
Updated by: CODEX-ORCHESTRATOR
Status: ARCHITECTURE_STOP; partial implementation preserved, not deployable
Receipt: PENDING external Orchestrator
Base: 62485cdc7de9d3bc01b0aed4a1d5e7e710365fc9
Branch: fix/review-grounded-evidence-v1
Worktree: review-grounded-evidence-v1

## Authorization and scope

Implementation authorized by attachment c72b669a-8160-4bad-9651-272abeea28b5. Existing task writer lock correction authorized by attachment 371eecd4-cd7e-4b44-aea8-be5b1cf408da. That resolution requires another stop if a newly discovered writer needs materially different synchronization. No historical fixture, provider call, Headless Run A/B continuation, merge, TUI or Web UI change is authorized.

Architecture source: [frozen design](../../../architecture/REVIEW-GROUNDED-EVIDENCE-DESIGN.md).

## Newly confirmed writer

Public entry point: `scripts/install-existing-project.ps1 -TargetProject <project> -Force`.

At lines 92–100, the installer enumerates `.codex/agents` and copies role files with `Copy-Item -Force`; line 98 permits replacing an existing role when Force is set. It has no execution-lock participation. In particular, it can replace `.codex/agents/cto.md`, an authoritative Review obligation source, during an existing task's GATE operation. It can also replace schemas, scripts and policies in the same project.

The supported force reinstall is documented in [update ownership](../../../operations/update-ownership.md). This is a project-wide maintenance operation without a task ID. It changes shared sources consumed by multiple tasks, unlike the task-bound update/advance/review paths covered by the accepted architecture correction. No project-wide synchronization or offline maintenance contract was invented.

The normal `update-runtime.ps1` path preserves role contracts but replaces runtime scripts/schemas and merges writable/provider configuration without task execution-lock participation. Its namespace and mutation loop are at lines 210–220 and 576–595. This adjacent maintenance boundary also needs an explicit architectural disposition; no updater changes were made.

## Deterministic evidence

An isolated temporary project was created with task AICO-001 in REVIEW and owner cto, plus a synthetic pre-existing CTO role. The actual engine lock helper acquired `GATE` for AICO-001. The actual installer was invoked with Force against that temporary project while the handle remained held. It succeeded and replaced the CTO role. `Assert-TaskExecutionLease` confirmed the original exclusive lease was still live after installation.

Before role SHA256: `60e48a88e8c1e2b0f415f0ccf084880a8fde71f4a64e5346106420c375f5e552`

After role SHA256: `b22a27a23c822127f08174af30e1390c6b0b65f930c5d0a11e83b1ebee356360`

Result: RoleChanged=true; GateLeaseLive=true; ProviderCalls=0. Historical sources were untouched. Only the forced-install conflict was exercised; the updater conflict is established by its code path, not an additional executed updater scenario.

The final digest recheck would detect a completed earlier replacement. It does not serialize the maintenance writer with capture/validation/intake, so it cannot establish the approved continuous atomicity invariant or close a write between the final recheck and lifecycle mutation.

## Implemented before stop

Existing single lock helper now registers live ownership and verifies reference identity, canonical project/task/path, process identity and live exclusive handle. Nested callers reuse verified ownership; no skip boolean or second lock exists. Registered Review receipts require a grounded validation token and are bound to the live lease and canonical Review digest.

Modified task writer/caller paths:

- task-execution-lock.ps1
- update-task.ps1
- advance-task.ps1
- review-task.ps1
- run-gate-agent.ps1
- submit-task-result.ps1
- qa-task.ps1
- security-task.ps1
- run-agent-task.ps1
- run-writable-agent.ps1
- finalize-task.ps1
- dispatch-ready-tasks.ps1
- new-task.ps1
- generate-engineering-backlog.ps1
- materialize-engineering-backlog.ps1
- reconcile-engineering-backlog.ps1

Direct scalar Review fails with REVIEW_GROUNDING_REQUIRED before canonical mutation. Direct REVIEW→QA/READY requires a registered grounded intake receipt. GATE acquisition was moved before the authoritative task read and propagated through nested intake calls.

The Review intake integration is partial: it references the forthcoming grounding helper, which is not implemented yet. Do not install or run this partial branch as a release. Snapshot/schema/router/materializer/packaging implementation and full validation are unfinished.

## Verification

Command: Windows PowerShell 5.1 `-NoProfile -ExecutionPolicy Bypass -File test-project/tests/test-task-writer-lock-contract.ps1`.

Result: PASS, one focused test script. Ten rejection scenarios verify immutable fixture bytes: update contention; advance contention; review contention; fabricated lease; wrong task lease; wrong project lease; expired lease; scalar approval; legacy approval transition; forged corrective receipt. Valid inherited scope plus an actual nested task update retain the original exclusive handle without release/reacquire.

Actual nested grounded Review recording/transition remains NOT_RUN pending implementation. The focused ownership test is not a substitute for that integration case.

PowerShell parsing passed for all scripts after the initial lock edits; four final boundary scripts also passed parsing after Review intake edits. Grounding A–Z, full PowerShell, Python, packaging and release validation: NOT_RUN.

No commits, push, implementation PR or merge were performed. HEAD remains the authorized base. All partial changes remain in the existing worktree.

## Next exact action

External Orchestrator must define the shared project maintenance boundary for forced reinstall and runtime update during active Review execution. Resume this same worktree after that architectural disposition. Do not restart the ticket or silently broaden the task lock correction into a project-wide locking rewrite.
