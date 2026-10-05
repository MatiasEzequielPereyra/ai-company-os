# Gate authoritative evidence preservation

Project: AI Company OS
Revision: 1
Updated: 2026-10-04
Updated by: Principal Runtime / E2E Engineer
Base: 87435d470c6fd0ea3d6174d78f078fd7b8be4297

## Authorization

The user authorized two real headless runtime cycles on new diagnostic copies of
the canonical Python Task CLI V1, stopping on real defects and fixing deterministic
engine defects in isolated worktrees with regressions. Historical Runs 3/4/5/6,
main, historical evidence and the reference product must remain preserved. No
merge, Codex inference or paid provider route is authorized.

## Observed defect

In diagnostic Run A, AICO-001's second real Review requested explicit non-goals.
The primary PM report already contained a Scope & Non-Goals section with concrete
exclusions. The exact Ollama transport prompt omitted that middle section and
contained truncation markers. Its effective gate context budget was 7,000 chars;
input context was 59,517 chars. The review returned CHANGES_REQUIRED and the
canonical runtime returned the task to READY. Execution stopped before QA.

Evidence is retained outside the fixture under
`temp-tests/headless-runtime-e2e-2026-10-04/run-a/02-pm-corrected-gates-review`
and `temp-tests/headless-runtime-e2e-2026-10-04/pm-review-context-exact.txt`.
These local paths are evidence locations, not packaged runtime dependencies.

## Root cause and correction

`run-gate-agent.ps1` clipped explicit artifacts by a per-artifact quota.
`provider-router.ps1` then distributed the candidate budget across sections and
retained only heads/tails, dropping authoritative middle evidence. A valid JSON
review could therefore assess an incomplete owner deliverable.

The constructor now appends complete authoritative artifacts. The router protects
the complete suffix beginning at the first explicit authoritative gate label:
canonical task, dispatch, owner role contract, primary report, latest task result,
latest independent review and QA gate. Only generic context may be reduced.
If the required envelope exceeds a candidate's finite effective budget, explicit
selection fails before inference; Auto records provider_context_rejected and
tries the next configured candidate. Hardware/provider budgets are unchanged.
No lifecycle transitions, findings or gate approvals are rewritten.

## Regression coverage

`test-gate-authoritative-context.ps1` exercises the actual router and constructor
with fake adapters: 7k Auto rejection before local inference with complete cloud
fallback; explicit rejection; sufficiently budgeted local preservation; QA's prior
review; Security's prior review and QA; generic context clipping; a primary report
larger than 62k preserved under a 180k cloud budget. Middle findings and tail
markers are asserted, as are zero local calls on rejection.

The hardware reconciliation contract now checks central gate hardware budgeting
and prohibits constructor artifact truncation. The existing gate evidence
preservation regression remains unchanged. Full verification logs and subsequent
real E2E recovery remain external diagnostic evidence; CI is attached to the PR.

## Handoff

Local verification: Windows PowerShell 5.1 full smoke 55/55 PASS; Python full
suite 204 PASS; npm 2 PASS. Initial sandbox runs failed on a static assertion
updated for centralized budgets, inaccessible system temporaries, and inability
to terminate a fake timeout process. Those logs are retained; the complete
subsequent runs passed. No real provider was used by these regressions.

Recipient: CODEX-ORCHESTRATOR
Receipt: PENDING
Next permitted action: review this isolated correction and its verification;
continue the diagnostic task through canonical corrective activation and execution.
No merge permission is granted. Historical acceptance fixtures remain excluded.
