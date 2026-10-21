# SBX-002 decision and policy baseline V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-18T21:10:43Z
Updated by: CODEX_ORCHESTRATOR_A
Task: SBX002_S0_CANONICAL_DOCUMENTARY_PUBLICATION_V1
Publication base: `5d5fbf67630c48b98378e7f869acd90deec07057`
Status: DOCUMENTARY_REVIEW_PENDING

## Authority and scope

The Human Project Owner's `CENTRAL_DECISION_V1 — SBX-002 S0 PUBLICATION
AUTHORIZED` permits these documents, provenance evidence, commit, push and one
draft PR. Technical review is attributed by that instruction to
`ORCHESTRATOR_B_SBX002_S0_SOURCE_AUTHORITY_REVIEW_V1`; its complete review bytes
have not been independently recovered for this publication. This authorization
does not ratify individual decisions, authorize S1, or certify operation.

The direct user instruction recovered at `2026-10-17T15:03:54.343Z` delegates
the six technical selections and their preparation. Its exact scope excerpt is:

> Tomar las decisiones técnicas recomendadas con juicio independiente, sin pedirle que elija detalles.

The selections below preserve the exact delegated-decision source, including
its conditions. They are technical design selections, not institutional CTO or
Security signatures. External identity authentication is UNKNOWN; no new external
identity proof is claimed or required by this documentary publication.

The requested original `ORCHESTRATOR_A_SBX002_S0_BASELINE_DRAFT_V1` was not
recovered as exact draft bytes from the records inspected. Its exact provenance
is UNKNOWN. These are newly prepared successor documents based on the verified
sources, not a claimed byte-identical export of that draft. Source hashes,
verification boundaries and the complete delegated source accompany this delivery
in the [documentary manifest](../../engineering/sbx002/SBX002_SOURCE_MANIFEST_V1.json).

## Governing documents

Preserve C1–C5 and amendments P1-01/02/03. The original contracts were verified
locally by A; their hashes are in the manifest. They remain planning authorities,
not evidence of operational guarantees. This baseline does not replace their
complete requirements or weaken closed V1 shapes and limits.

The immutable [historical decision record](../../engineering/sbx002-d6/NATIVE_SBX_002_CTO_SECURITY_DECISION_RECORD_V1.md)
has SHA-256 `11de899585c2782f480c88243a2f0991731b09841f33183b97a4f7c4f4dd6949`.
The separate [D6 amendment](../../engineering/sbx002-d6/SBX002_D6_ENMIENDA_DOCUMENTAL_V1.md)
has SHA-256 `98f0902bf7f279fabc323188a0036baee9f892a536852d52faf3184a0bb31791`.
Both historical files retain their original bytes and historical statuses.

## Preserved delegated selections

### DR-1 — composite receipt

Technical selection: APPROVED under conditions, design only. Require a closed
composite package, acyclic references, separation of guest and host evidence and
a mandatory VerifyReceiptPackage consumer. An isolated receipt V1 is insufficient.
EXECUTION_EVIDENCE requires an actually observed V1; HOST_TERMINAL may omit an
unavailable guest result and always rejects. Every admissible sealed package
requires confirmed final cleanup. Verify origin, membership, identity, freshness
and continuity; hashes and dataclasses do not confer authority. Simulation cannot
be accepted as operational evidence. New limits and retention remain pending.
Durability, coherent rollback, global quotas and the real consumer are unproved.

### DR-2 — retry and lifecycle

Technical selection: APPROVED under conditions, design only. Preserve logical
snapshot identity and the sole additional edge
`CLEANUP_VERIFY[g0] -> CAPTURING[g1]` for PRE_RUN_TRANSPORT_FAILURE before code
is sent. Require confirmed g0 cleanup, a new VSS snapshot and VM, immutable
request, valid authority/lease/reservation, and durable consumption of the single
retry together with generation and intent. RetryResolution resolves only the g0
transport cause; it cannot clear invalidation. No retry after code submission,
uncertain commit, restart, lost continuity or consumed retry; no third attempt.
Capture/preparation budgets of 120/180 seconds accumulate without resetting
expiry. The retained 450-second closure horizon is a design constraint, not a
measured guarantee. Crash boundaries, durable commit and timings remain unproved.

### DR-3 — authority, fencing and invalidation

Technical selection: APPROVED as a design requirement under conditions. Require
an execution actor, canonical CAS/epoch, irreversible invalidation, independent
stop, and fencing inside the same canonical commit that publishes. A prior check
followed by a write or a local mutex is insufficient. Journal failure cannot
delay stop or permit optimistic success. Verify observation origin, order and
continuity. Post-seal revocation prevents new publication without rewriting the
historical receipt. Unknown operational mechanisms keep publication blocked.
Interprocess atomicity, antirollback, external writers, watchdog and latencies
remain unproved.

### DR-4a — profiles and certification

Technical selection: APPROVED for fail-closed admission. Certified profiles: NONE.
Only an exact protected, registered and certified profile may admit operation.
UNKNOWN, drift, inconsistency or missing certification blocks operational READY.
Smaller resource allocations do not inherit certification. No automatic install,
elevation or expansion. Schema compatibility and CI do not prove isolation.
Exact environments, reserves and E1–E5 certification remain pending.

### DR-4b — result mapping

Historical selection: CHANGES_REQUIRED. D6's identifier ambiguity was addressed
by the separately published amendment, using DEP-D6 for the dependency and MAP-D6
for REQUESTED/PREFLIGHT. The [successor disposition](../../../docs/decisions/SBX002_DR4B_POST_D6_DISPOSITION_V1.md)
records a proposal only: APPROVED_WITH_CONDITIONS; FORMAL_DISPOSITION: PENDING.
Neither the D6 merge nor this publication supplies that missing competent act.

### POLICIES — technical responsibilities

Technical selection: APPROVED only for role distribution. DevOps proposes
capacity/quotas and storage/maintenance operations; CTO owns architecture, chain,
recovery and compacting design; Security reviews minimization, access, integrity
and controls; PM supplies confirmed privacy requirements; EM coordinates. The
Human Project Owner identifies organizational owners and the competent legal-hold
authority if applicable. This assigns no named organizational officers and
approves no policy values or operational actions.

## Open gates and precedence

The [material policy and S1 gate](../../engineering/sbx002/SBX002_MATERIAL_POLICY_AND_S1_GATE_V1.md)
preserves each open dependency. This successor records the delegated design
scope without editing the historical record or resolving its operational UNKNOWNs.
The specific publication authorization overrides only earlier prohibitions on
this documentary publication. All excluded execution remains prohibited.

CANONICAL_PUBLICATION: PROPOSED_IN_DRAFT_PR
DR4B_FORMAL_DISPOSITION: PENDING
MATERIAL_POLICIES: PENDING_UNKNOWN
S1_IMPLEMENTATION_AUTHORIZED: FALSE
BROKER_IMPLEMENTATION_AUTHORIZED: FALSE
MERGE_AUTHORIZED: FALSE
WRITABLE_ENABLED: FALSE
RUN_EXECUTION_AUTHORIZED: FALSE
REAL_E2E_AUTHORIZED: FALSE
NATIVE_SANDBOX_P0: OPEN
