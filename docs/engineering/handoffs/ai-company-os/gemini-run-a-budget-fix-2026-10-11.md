# Gemini Run A budget fix — review handoff

Project: AI Company OS
Revision: 1
Updated: 2026-10-12T02:41:36Z
Updated by: CODEX-ORCHESTRATOR
Receipt: PENDING
Next owner: External Orchestrator
Predecessor: single-attempt-provider-execution-v1-implementation-2026-10-10.md

## Authorization receipt and ownership

Human request `AI COMPANY OS — RUN A — GEMINI BUDGET FIX` authorizes a new clean
worktree from origin/main, minimal optional Gemini budget/thinking parameters,
deterministic tests in WinPS5.1/PS7, Python/npm/packed E2E, and, if verification
passes, commit, push and one draft PR. Target: gemini-3.8-flash, 32768 output
tokens, thinking low, explicit Single-Attempt. No real provider, retry/fallback,
historical/candidate modification, global installation update, task transition,
Run A/B or merge. Later integration and real Review need independent authority.

This standalone handoff records the budget ticket only. The shared
`.codex/state/company-state.md` contains prior workstream pointers and unrelated
task records; their ownership is preserved. No competing shared pointer or task
transition is published. Source revisions not explicitly recorded are UNKNOWN.

## Delivery

- BASE_SHA: 294bdd776a189e5950c0e7983a5dc4dca77a9076 (origin/main and remote main verified directly).
- WORKTREE: Z:\repos\ai-company-os\worktrees\gemini-run-a-budget-fix
- BRANCH: fix/gemini-run-a-budget
- FINAL_SHA / PR_URL / CI: supplied in final external delivery after publication.
- ROOT_CAUSE: the Gemini adapter hardcoded 12000 and lacked thinking controls; gate/router could not transport explicit options.
- CONTRACT_DECISION: paired optional parameters, validation before side effects, Gemini exact model plus Single-Attempt, exact reported identity, legacy behavior unchanged.
- SCHEMA_COMPATIBILITY: canonical schemas unchanged; optional journal thinking_level field only when explicitly requested.
- Technical contract: [Gemini Single-Attempt budget](../../gemini-single-attempt-budget.md).

## Verification

- Focused WinPS5.1: 161 assertions PASS.
- Focused PS7: 162 assertions PASS (additional transport retry-option assertion).
- Full WinPS5.1 smoke: 74/74 PASS, 200.81 seconds.
- Full PS7 smoke: 74/74 PASS, 187.22 seconds.
- Full Python: 285 PASS, 1 SKIP, 190.95 seconds; deterministic TUI tests included as authorized.
- npm: 3/3 PASS.
- Exact packed release E2E: PASS for isolated new/install/update and Python/TUI bootstrap.
- Tarball SHA256: 05068f0e013c7a129e2f1f0dc93e062f41e5a563ef052f273d71703f0a0f126b.
- Independent implementation review: no confirmed scoped blocker; suggested gate preflight preservation regression was added and passed.
- Real provider calls: NONE. Default retry/fallback and Grounding/Citation Spans regressions remained in the complete smoke suite.

Evidence directory:
`Z:\repos\ai-company-os\temp-tests\gemini-run-a-budget-fix-20261011`.
Final logs: focused-winps.log, focused-ps7.log, winps-full-smoke-escalated.log,
ps7-full-smoke-escalated.log, python-full-escalated.log, npm-full.log,
package-e2e-escalated.log. Initial sandbox executions failed Python location or
dependency network access; their logs remain preserved under the same names
without `-escalated`. These failures were not reclassified or hidden; legitimate
execution outside that restriction produced the final full results above.

## Frozen integrity

`preservation-final.json` independently records:

- Current frozen fixture: 334/334 exact hashes.
- Historical engine source files: 467/467 exact hashes.
- Existing operational candidate: 3223/3223 exact hashes and unchanged inventory count.
- Original historical manifest: 1287/1287 matches.
- Older 340-file manifest: 339/340; only the previously documented `.git/index` difference remains. No index repair or rebaselining.
- Selected global runtime files: 4/4 exact hashes, no global install operations.
- AICO-002 remains REVIEW in the historical fixture and operational candidate.

The counts refer to different manifests and are not interchangeable. The known
historical maintenance-lease regression limitation is unchanged and is not
claimed as repaired by this ticket.

## Next permitted action

External Orchestrator reviews the draft PR, exact diff and validation evidence.
Do not merge or execute a provider from this handoff. After separate integration
authorization, prepare a new controlled operational copy and seek independent
authorization for one grounded Review of AICO-002.

## Exact source manifest

Raw SHA256 values; self-hash and shared derived indexes excluded.

| Source | SHA256 |
|---|---|
| scripts/provider-router.ps1 | 43e6c3e41a005c9b11ff44005750007e1688b583b0928848810d654c537dd3cb |
| scripts/providers/invoke-gemini.ps1 | 5f5835c62c9f3194e7a7e219652011ec1467b84438451ddb3c39b312819d1a35 |
| scripts/run-gate-agent.ps1 | c9ad73484c1cb75997eb35a81138ea4818ca8d89687c78702232b77f50b902d8 |
| scripts/single-attempt-execution.ps1 | c8d79fe2eede2eb539f85f6a67777de4d15a4436d32de3805254a9d11bf5af5c |
| test-project/tests/run-all-smoke-tests.ps1 | 5e79b3fc2a18d89f77ce23e27a54ae16fa9d61564deda837a0a6bb91a672544a |
| test-project/tests/test-gemini-single-attempt-budget.ps1 | bd2c7674198a1ea354a5c36a985d2840757e7dd6e19f7dc11e59a20003623f66 |
| docs/engineering/gemini-single-attempt-budget.md | dfd942fbcd1d75edd44b5ac785ee35fa3fe4568d12fc9348ab19e5bac9159bfe |
