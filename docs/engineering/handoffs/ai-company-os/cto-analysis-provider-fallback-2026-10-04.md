# CTO analysis provider fallback reliability — handoff

Project: AI Company OS
Revision: 1
Updated: 2026-10-04T05:15:46.2800017Z
Updated by: CODEX-ORCHESTRATOR
Previous handoff: NONE (new Run6 incident correction)
Base: 6551d45d38fd1659735f5bf4a4042dce31632166
Branch: fix/cto-analysis-provider-fallback
Status: READY_FOR_EXTERNAL_ORCHESTRATOR_REVIEW
Receipt: PENDING
Recipient: External Orchestrator

## Authorization receipt

User's 2026-10-04 Run6 incident request authorizes read-only forensic investigation followed by confirmed minimal CTO analysis fallback policy correction, deterministic tests, full suites/package/release/CI, isolated branch/worktree and review PR. Freeze Run6 and evidence; no U/R/G, real provider, workflow, merge, other acceptance run or UX implementation. Full receipt retained under external evidence/authorization.txt.

## Delivery

Root cause ANALYSIS_PROVIDER_FALLBACK_DEFECT in role configuration: CTO inherited generic Ollama-only; existing router already cleans rejected output, retries semantically once on same provider and continues Auto after exhausted validation/transport/timeout/schema failure. No validator/router changes.
New CTO order: Ollama,OpenRouter,Gemini,Codex,DeepSeek,Grok. Existing allow_paid_fallback=false and model/default/writable/gate/EM policies unchanged. OpenRouter inherits openrouter/free; missing keys/CLI/runtime skip; Gemini/Codex account cost/quota cannot be inferred from eligibility. Existing false guard skips DeepSeek/Grok only.

[Investigation and follow-ups](../../cto-analysis-provider-fallback.md), [provider policy](../../../operations/provider-runtime.md).
PM/QA/Security/DevOps owner analysis single-candidate exposure reported separately; no scope expansion. Persistent availability/exhaustion errors and CONFIGURED-vs-REACHABLE UX only recorded.

## Evidence and verification

Six deterministic runner/router/semantic/intake scenarios and canonical policy PASS. Five focused existing suites PASS; Python204 PASS; Windows PowerShell5.1 full53/53 PASS; npm2 PASS; compile/version contract PASS; exact packed release installed E2E PASS (new/existing/update). Canonical install/update assertions guard CTO-chain delivery.
Run6 metrics show three historical CTO attempts with one semantic repair each and contract failure; AICO-002 remains ACTIVE. Exact rejected JSON unavailable because cleanup worked; user's exception is provenance for precise contradiction.
Source manifest: [exact sources](cto-analysis-provider-fallback-2026-10-04-sources.json).
External logs/package/protected-state/checkpoint/PR/CI:
Z:/repos/ai-company-os/temp-tests/cto-analysis-provider-fallback-evidence
Final SHA/CI and protected comparison recorded externally after publication, without modifying this handoff.

BLOCKERS: NONE
RUN_6: FROZEN_PRESERVED
PROVIDER_CALLS: NONE
NEXT_EXACT_ACTION: External Orchestrator reviews policy, deterministic regressions and CI at FINAL_SHA; explicit later authorization required for merge or any functional acceptance.