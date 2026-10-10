# Single-Attempt Provider Execution v1 implementation checkpoint

Project: AI Company OS
Revision: 1
Updated: 2026-10-10T15:30:49.8982047Z
Updated by: CODEX-ORCHESTRATOR
Receipt: PENDING
Next owner: External Orchestrator
Predecessor: grounded-citation-spans-v1-implementation-2026-10-10.md

## Authorization receipt

Human attachment332de57f-0e38-4f66-8130-3044a0116b2a explicitly authorizes SINGLE-ATTEMPT PROVIDER EXECUTION v1 implementation, deterministic verification, isolated branch, commit and draft PR. It supersedes the earlier citation-spans-only restriction for this separate implementation. Human clarification also permits both Python deterministic TUI tests, with simulated providers only. No real provider, Run A/B, acceptance/TUI continuation, existing user installation update, governance changes, protected workstream changes or merge.

## Mandatory checkpoint

BASE_SHA: 5aedfbbb0ed897e8b4c8076f44863379e5d03d53
WORKTREE: Z:\repos\ai-company-os\worktrees\single-attempt-provider-execution-v1
BRANCH: feature/single-attempt-provider-execution-v1
FINAL_SHA / PR_URL / GITHUB_CI: supplied in external delivery after commit/draft publication; no invented identity.
ROOT_CAUSE: router semantic regeneration and Auto fallback combine with up to three HTTP adapter invocations; previous router candidate counts do not count actual transport attempts.
INVOKE_PATH_AUDIT / RETRY_SITES_FOUND / FALLBACK_SITES_FOUND: [complete baseline matrix and contract](../../single-attempt-provider-execution-v1.md).
CONTRACT_DECISION: opt-in -SingleAttempt propagated gate/router/adapters; explicit provider/model and OpenRouter upstream endpoint; private registered execution context bound to identity.
SINGLE_ATTEMPT_INVARIANT: at most one AICO generation transport-boundary entry, no repair/fallback, normal defaults unchanged, canonical validators retained.
SUPPORTED_PROVIDERS: OpenRouter, Gemini, Ollama, DeepSeek, Grok HTTP adapters.
UNSUPPORTED_ADAPTERS: Codex external-agent CLI; cannot establish its internal invocation bound.
FILES_CHANGED: source manifest below.
TESTS_ADDED: one deterministic regression suite; 262 assertions each on WinPS5.1 and PS7; user24cases plus exact lease contention and preserved output.
POWERSHELL_SMOKE: WinPS5.1 68/68 PASS,96.8s. PS7 full smoke FAIL at preexisting generated-string contract; targeted current feature/gates/grounding/spans PASS.
PYTHON_FULL_SUITE: final209/209 PASS,89.37s.
NPM_TESTS: 2/2 PASS.
PACKAGE_E2E: final packed installed new/install/update PASS; helper presence/hash/ownership checked; tarball01061194b63f46b5c0560bd0dc501cbdbd04b5c058188cbe338debdbd1f91683. Earlierb1f55package superseded after contention fix.
COMPATIBILITY: no switch retains three transport attempts, semantic repair and existing fallback; Grounding/Citation Spans/schema contracts unchanged.
KNOWN_LIMITATIONS: external infrastructure operations not counted; strict reported model revision mismatch fails closed; unknown usage null; pre-lease rejection creates no record and truthfully reports zero calls.
BLOCKERS: PS7 full smoke preexisting failure, plus separately reproduced preexisting Gemini array-contract test. Technical record contains exact baseline blobs and errors. No scoped implementation blocker found after independent re-review.
NEXT_EXACT_ACTION: External Orchestrator reviews draft PR, execution audit, invariant proofs, CI and documented PS7 failures. No acceptance/provider continuation or merge.

## Independent review and preserved evidence

Independent review found and resolved a cache cleanup before lease bug. Gate now acquires its verified lease before journal or cache mutation. Tests hold actual GATE and verified Maintenance leases and assert existing cache bytes preserved, transport0, records0. Reviewer re-read the fix and found no new concrete blocker; did not claim test execution.
Frozen engine direct Git SHAa5c030cfb83bc98bc7d3d009df616cc7e3590cf0 and clean; AICO-002 REVIEW. 340 continuation fixture/preflight evidence files retained exact hashes. No historical sixth maintenance regression reclassified as PASS.

## Validation evidence

Directory: Z:\repos\ai-company-os\temp-tests\single-attempt-provider-execution-v1-validation
Final logs: winps-final.log, python-final.log, npm-final.log, release-final/e2e.log. Failed prior smoke logs retained. Baseline reproduction: baseline-ps7-new-project.log and baseline-ps7-gemini.log.
All source revisions UNKNOWN unless recorded; hashes are exact local bytes. Self-hash and subsequently updated derived state excluded.

| Source | Raw SHA256 |
|---|---|
| docs/engineering/single-attempt-provider-execution-v1.md | 10edd51f6b5ac3ded12d6b3e67d0d06d9f61bb0c8fc7b002a5baf221ba0a2cb2 |
| npm-bin/package.test.js | a3884d40bd40767d6e8e215e02f6fc78011942ffab0077fddcb04e6ed8164978 |
| scripts/install-existing-project.ps1 | 2f19e13c18c99e49c3f49085bb5559e44a888c35f192cad2749554b33c2efce7 |
| scripts/new-project.ps1 | f04fe5962dc36ffda6c5c7e97c313fd462d5101d9c38e50773a12303f6cbf802 |
| scripts/provider-router.ps1 | f39ae626f79e4bd64253cb2b9dac82b5e1996f461a6c1180116e9bbde20e082b |
| scripts/providers/invoke-deepseek.ps1 | 1c60f7b0045c15b69f32f321b2fa2b8e6648137cd5686eb196c3288be953f567 |
| scripts/providers/invoke-gemini.ps1 | 0122cb8082ba29b0ff5da4b1317dd1ff0bb6638ddfe011bfc0996deb27809b03 |
| scripts/providers/invoke-ollama.ps1 | 6820447bd030332b6c784471d8b747c3fa3c16a0ebc712523baac7c319b53b60 |
| scripts/providers/invoke-openrouter.ps1 | cb94524058678f5a3ba7ac634da9881952704a68f12a9f9624b7606a2d5b3ed3 |
| scripts/providers/invoke-xai.ps1 | 5b622c99c09f3c6817c7d84ab754c92e3869681289d390957d179d6758a38c86 |
| scripts/run-gate-agent.ps1 | 025bb0bddc100dde57a9057f6181ff164037af819d859820578f73ed8460b09f |
| scripts/single-attempt-execution.ps1 | 739dae60eebc5c41e4dd4c6acda0f226a79417142abcf7ba856d3a4e78eb7c0e |
| scripts/update-runtime.ps1 | f4e3d06e9aff31c40165fae42b420cdce2ec2af227357aed38598fdbb505981b |
| test-project/tests/run-all-smoke-tests.ps1 | bbd6f0aca8d5657361e6661e1943727fb35c8bf50e586beb23cb5ae91da9ecb5 |
| test-project/tests/test-agent-runtime-contract.ps1 | fdc971be5c0332940ec6e4cb29d66f341714f192cc5d563f3d7a391329976867 |
| test-project/tests/test-canonical-contracts.ps1 | 2a9744d6bd204d96328e825018b799dc85093db4adfd6ee8f02502238bba990b |
| test-project/tests/test-npm-package-e2e.ps1 | fcb47baed0d4eaae2d196635489f39bbea660917203eed64452199ca8212330c |
| test-project/tests/test-single-attempt-provider-execution.ps1 | c9491b036954ee0eb8144819c95890096add975b292d50d79a4409c29f5ae1b9 |
