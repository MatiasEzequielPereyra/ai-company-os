# CTO analysis provider fallback reliability

Project: AI Company OS
Revision: 1
Updated: 2026-10-04 (UTC)
Updated by: CODEX-ORCHESTRATOR
Base: 6551d45d38fd1659735f5bf4a4042dce31632166
Branch: fix/cto-analysis-provider-fallback
Status: READY_FOR_EXTERNAL_ORCHESTRATOR_REVIEW

## Authorization and scope

The user's Run6 incident authorizes investigating and correcting CTO analysis Auto fallback, deterministic regression tests, full validation, isolated Git work and a review PR. Frozen Run6 and its evidence, previous runs and historical dirty checkout are protected. No real providers, Run6 retry, functional acceptance, new run, merge or UX implementation.

## Confirmed root cause

Classification: ANALYSIS_PROVIDER_FALLBACK_DEFECT (role policy configuration).

The existing router selects generic auto_order and then the owner analysis role override (provider-router.ps1:533–549). Baseline generic order is only Ollama, with an override only for Engineering Manager. CTO therefore has no second candidate after Ollama cannot satisfy the semantic contract.

The router already validates schema, performs exactly one semantic repair with the same provider, and revalidates (804–865). Its outer catch deletes consumable output and records the failed attempt (894–940). Auto continues the provider loop; explicit selection throws; total exhaustion fails closed (943–951). Transport, timeout and schema exceptions use this same outer failure path. No router or semantic-validator changes are required.

The COMPLETED execution_blocker rejection remains in validate-analysis-result-semantics.ps1:23. The optional blocker must be omitted for COMPLETED; contradictory output is never intake evidence.

## Run6 evidence

Frozen fixture tasks/AICO-002.md:7 remains ACTIVE. Its runtime AICO-002-result.json is absent. Metrics events.jsonl:22–25,26–29,30–33 record three historical CTO attempts at 04:58:16Z,05:01:26Z,05:02:56Z on 2026-10-04, each Ollama/qwen3:8b with 42,399 input / 20,000 sent chars, one semantic retry and final contract-category failure. No next-provider attempt follows. Individual rejected JSON and exact exception text were not retained by metrics; the specific COMPLETED/execution_blocker contradiction is supplied by the user's incident, consistent with the unchanged validator. Forensic summary and before/after protected hashes are external evidence.

## Minimal policy change

Add only analysis_auto_order_by_role.cto = Ollama, OpenRouter, Gemini, Codex, DeepSeek, Grok. Preserve all generic, writable, gate and Engineering Manager orders and model configuration. See [provider policy](../operations/provider-runtime.md).

Local-first retains hardware/role selection. OpenRouter inherits openrouter/free. Gemini and Codex use existing configured models/account conventions; no key or quota availability is assumed. Existing eligibility skips missing keys/CLI/adapters/local availability; failed remote attempts continue Auto. Existing false paid guard skips DeepSeek/Grok. It does not universally classify billing of Gemini/Codex or operator model overrides; no paid setting or model was changed.

PM/QA/Security/DevOps owner analysis has the same default single-candidate exposure. This scoped CTO correction leaves those policies for separate role decisions. QA/Security gates already have multi-provider gate routing. PM's smaller product-analysis workload and successful Run6 PM path do not prove every future PM analysis can satisfy a local model; that remaining risk is explicit.

Installer copies canonical configuration; updater adds missing role properties while preserving project overrides. Frozen Run6 is not updated. Release E2E and update-contract assertions verify delivery of the new chain.

## Verification

New deterministic tests exercise real runner/router/schema/semantic validator/result intake with replaced provider adapters and hardware resolver in disposable projects. Cases: exhausted local repair to valid next provider/REVIEW, repair success without fallback, every candidate invalid leaves ACTIVE with no result/report, unavailable local provider skipped, missing next remote credentials skipped, and paid providers skipped despite fake keys. Invalid local outputs are checked absent before the next provider runs. Canonical CTO chain and paid setting are asserted. New suite is wired into PowerShell smoke/CI.

Full results, exact packed artifact, installed E2E, final SHA and CI receipt are recorded in the handoff/external checkpoint. No real providers are used.

## UX follow-up — recorded only

1. Show provider unavailability as persistent actionable error.
2. Show semantic provider exhaustion as persistent actionable error.
3. Distinguish CONFIGURED from REACHABLE during setup.

These are separate follow-ups with no UX implementation or ticket/lifecycle mutation in this correction.

## Local validation receipt

Updated: 2026-10-04T05:15:46.2800017Z
Six new deterministic scenarios and canonical role chain PASS; five focused existing router/timeout/semantics/corrective suites PASS. Full Python204/204 PASS (118.58s); full Windows PowerShell5.1 smoke53/53 PASS (43.82s final run); npm2/2 PASS; release version contract PASS; Python compilation PASS; exact packed artifact installed new/existing/update E2E PASS. Package0.1.1,217 entries, SHA256 9FCB5584A3735ABC2CB9F06D85EB946473920E9565926FA172508B1C703CBD2E. Final GitHub CI receipt is external after publication.
