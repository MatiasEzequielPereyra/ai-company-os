# Codex structured schema portability — handoff

Project: AI Company OS
Revision: 1
Updated: 2026-10-04
Updated by: CODEX-ORCHESTRATOR
Previous handoff: [CTO fallback](cto-analysis-provider-fallback-2026-10-04.md)
Base: 6e70d64029526cd65df791ddefc8de0065f3c83a
Branch: fix/codex-structured-schema-portability
Status: READY_FOR_EXTERNAL_ORCHESTRATOR_REVIEW
Receipt: PENDING
Recipient: External Orchestrator

## Authorization receipt

The user's Run 6 recovery incident request authorizes a minimal Codex structured schema portability fix, deterministic fake-provider regression tests, full validation, an isolated branch and review PR. Run 6 and all evidence must remain frozen; no real providers, retry, lifecycle mutation or merge. Exact request retained in external evidence/authorization.txt. A subsequent explicit clarification described the existing EM BLOCKED contradiction and proposed only executable_work.minItems 1 to 0 while retaining semantic validation. The user replied "lo que sea correcto en esta situacion", authorizing that minimum correction. No other canonical or semantic changes are authorized or included.

## Delivery

The baseline adapter submitted the canonical optional execution_blocker directly to Codex's strict response-schema interface. Temporary provider translation makes optional fields required and nullable, followed by normalization and original canonical validation. Semantic repair/fallback remains in the unchanged router. Generic and Engineering Manager COMPLETED/BLOCKED cases are covered; real blockers are never discarded. EM executable_work.minItems changes to 0 solely to allow its existing BLOCKED semantics; COMPLETED empty work and BLOCKED nonempty work remain rejected by unchanged validators.

[Design, evidence and separate follow-ups](../../codex-structured-schema-portability.md).
[Exact source hashes](codex-structured-schema-portability-2026-10-04-sources.json).

## Verification

- New deterministic fake Codex regression: 20 cases PASS, including specific negative stages/errors and cleanup.
- Full Python: 204 PASS; compilation: 63 files PASS.
- Windows PowerShell 5.1 smoke: 54/54 PASS, including canonical contracts, analysis/EM semantics, router, corrective repair, quota and timeout cleanup.
- npm: 2 PASS; release version contract PASS; exact installed tarball E2E PASS for new/existing/update with exact adapter/schema hashes.
- One earlier smoke timing failure retained in evidence; isolated timeout rerun and two subsequent full smoke runs passed unchanged timing thresholds. One initial source-string contract failure was fixed by preserving expected CLI argument quoting.
- Protected before/after inventory: 22,706 files, zero differences. Run 6 AICO-003 remains ACTIVE.

External logs, preservation manifests, package, final SHA, PR and GitHub CI checkpoint:
Z:/repos/ai-company-os/temp-tests/codex-structured-schema-portability-evidence

GitHub CI is recorded externally after publishing the commit; this immutable handoff is not rewritten. Local tests use fake providers only; live provider compatibility is not claimed as executed.

BLOCKERS: NONE locally; GitHub CI must pass before external review completion.
RUN_6_AICO_003_STATUS: ACTIVE
RUN_6_PRESERVED: PASS
PROVIDER_CALLS: NONE
NEXT_EXACT_ACTION: External Orchestrator reviews the final SHA, authorized EM schema correction, deterministic regressions and GitHub CI. Merge and acceptance recovery require later explicit authorization.
