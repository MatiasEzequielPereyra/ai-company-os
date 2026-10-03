# Canonical Acceptance Reference Project v1 — handoff

Project: AI Company OS
Revision: 1
Updated: 2026-10-03T23:36:41.8497134Z
Updated by: CODEX-ORCHESTRATOR
Status: READY_FOR_EXTERNAL_ORCHESTRATOR_REVIEW
Base: dd2d6b0d114851d4ef7d55687b530c6fd4ca3e1f
Branch: test/canonical-acceptance-reference-v1
Worktree: Z:/repos/ai-company-os/worktrees/canonical-acceptance-reference-v1
Receipt: PENDING
Recipient: External Orchestrator

## Authorization

The user's 2026-10-03 Canonical Acceptance Reference Project v1 request authorizes independent minimal Python product, positive tests, explicit acceptance contract and deterministic preflight, an isolated branch/worktree, versioning and review. No providers, Run6, protected Run4/Run5 or historical checkout modifications, merge, general memory or scope guard. Full request retained externally with validation evidence.

## Delivery

[Reference README](../../../../acceptance/reference-projects/python-task-cli-v1/README.md), [run provenance rules](../../../../acceptance/reference-projects/README.md), [design and verification](../../canonical-acceptance-reference-v1.md). The flat taskcli package exposes only list and help. Empty stdout bytes No tasks. followed by LF, empty stderr, exit0. Persistence/add/complete/remove/IDs/status storage/env override/default task storage intentionally absent. No runtime dependencies on Company OS.

JSON contract records exact argv, capabilities, preserved output, language/version/root, required files, prohibited storage and line-ending-normalized product source pins. Specific preflight verifies reality, refuses drift, runs five positive tests and missing-feature checks. Ten independent regression cases run on temporary copies. Future runs must copy the canonical product and retain provenance; never work directly here. Canonical changes require v2 or reviewed controlled revision.

## Verification and evidence

Baseline5/5 PASS; preflight PASS; preflight regressions10/10 PASS; full AI Company OS Python195/195 PASS. Optional conventional installation of product into an isolated fresh-copy venv PASS without Company OS, with byte-exact output. npm runtime payload dry-run217 entries, acceptance0, unchanged. Existing PR CI and final commit recorded in external checkpoint after publication; no local runtime release E2E needed.

[Exact source manifest](canonical-acceptance-reference-v1-2026-10-03-sources.json) excludes this handoff and derived state index. External logs/authorization/protected-state evidence: Z:/repos/ai-company-os/temp-tests/canonical-acceptance-reference-v1-evidence. Protected acceptance/harness/dirty checkout hashes verified externally before/after. No historical evidence rewritten.

BLOCKERS: NONE
NEXT_EXACT_ACTION: External Orchestrator reviews the reference project contract, preflight and validation. Do not create Run6 or merge before subsequent explicit authorization.
PROVIDER_CALLS: NONE
RUN_6: NOT_CREATED
