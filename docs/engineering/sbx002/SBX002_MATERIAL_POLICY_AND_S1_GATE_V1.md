# SBX-002 material policies and S1 gate V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-18T21:10:43Z
Updated by: CODEX_ORCHESTRATOR_A
Task: SBX002_S0_CANONICAL_DOCUMENTARY_PUBLICATION_V1
Publication base: `5d5fbf67630c48b98378e7f869acd90deec07057`
Status: DOCUMENTARY_REVIEW_PENDING

## Material policies remain open

The following are proposals to be prepared by the technical roles already
selected. Assigning a role does not approve a value, appoint a human officer,
establish legal applicability or authorize an operation.

| Matter | Technical preparation/review | Material decision and organizational authority |
| --- | --- | --- |
| Global quotas, capacity and final-resource reserve | DevOps; CTO and Security review | PENDING / UNKNOWN |
| New evidence/package limits | CTO and DevOps; Security review | PENDING / UNKNOWN |
| Retention, including the proposed 30 days | DevOps, Security and confirmed PM requirements | PENDING / UNKNOWN |
| Privacy, access and evidence minimization | Security; PM confirmed requirements | PENDING / UNKNOWN |
| Legal hold applicability and responsible authority | Human Project Owner identifies competent authority if applicable | PENDING / UNKNOWN |
| Purge and protected recovery/tombstone/chain retention | DevOps; CTO and Security review | PENDING / UNKNOWN |
| Maintenance and recovery capacity/time budgets | DevOps and CTO; Security review | PENDING / UNKNOWN |
| Compacting/checkpoint integrity and conservation | CTO and DevOps; Security review | PENDING / UNKNOWN |
| Named organizational owners | Human Project Owner; EM coordinates | PENDING / UNKNOWN |

New proposed limits in the historical record, including 128 MiB evidence or
30-day retention, are not ratified by S0. Existing C1–C5 and P1 requirements
remain intact. Do not reclaim mandatory evidence, recovery data, tombstones or
the integrity chain merely to regain capacity. Unresolved operational policy
must fail closed for the affected operation.

## Reconcile S1 with SBX-001

Reuse [contracts.py](../../../src/company_os/sandbox/contracts.py) and preserve
[its existing regressions](../../../tests/test_native_sandbox_contracts.py).
The [published limitations](../native-sandbox-contract-validators.md) apply.
The module validates bytes and consistency, not authority, isolation or cleanup.

| Existing SBX-001 surface | S1 compatibility requirement |
| --- | --- |
| Strict JSON parser, duplicate-key rejection, exact bytes/hashes and limits | Reuse existing validation; no alternate permissive parser |
| Closed aico.sandbox.request.v1 and aico.sandbox.receipt.v1 | Preserve fields, versions, export restrictions and limits |
| validate_request and validate_receipt | Keep existing caller behavior and negative cases |
| ValidatedRequest / ValidatedReceipt | Never treat public data objects as authenticated authority |
| Synthetic test fixtures | Keep simulation distinct from operational evidence |

Any future composite evidence belongs in separately versioned, closed contracts,
with explicit compatibility analysis. Do not extend receipt V1 with host fields
or accept it alone. HOST_TERMINAL without a guest result must not fabricate V1.

## Proposed S1 boundary and admission gate

S1 may be proposed as pure data contracts, composite codecs, deterministic
lifecycle/retry rules and fake authority/storage ports. It excludes IPC, privileged
brokers, Hyper-V, VSS, OS monitoring, runner wiring and operational publication.
No implementation starts under this document.

Before a separate S1 authorization:

1. B independently reviews this exact documentary PR and its provenance.
2. The competent authority explicitly disposes of DR-4b's exact successor.
3. The S1 ticket records exact scope, owners, dependencies and acceptance criteria.
4. Every unresolved material policy is classified as blocking a specific S1
   behavior or deferred exclusively to an operational gate. Unknown values must
   not silently become production defaults. No blanket policy waiver is granted.
5. Revalidate main and prepare an exclusive worktree for that separately
   authorized task; preserve SBX-001 compatibility and all historical documents.

Future tests to require, NOT_RUN here: closed-shape/parser boundaries, old V1
compatibility, evidence origin/replay rejection, missing host proof, absent vs
uncertain guest evidence, mapping partition/precedence, one durable pre-code retry,
irreversible invalidation and failure injection using fake ports. These tests
cannot certify real durability, fencing, isolation, cleanup or E1–E5.

S0 publication is distinct from S0 merge, DR-4b ratification, S1 authorization
and P0 certification. Shared company-state indexes owned by other workstreams
are not updated by this narrowly authorized publication.

S1_IMPLEMENTATION_AUTHORIZED: FALSE
BROKER_IMPLEMENTATION_AUTHORIZED: FALSE
MERGE_AUTHORIZED: FALSE
WRITABLE_ENABLED: FALSE
RUN_EXECUTION_AUTHORIZED: FALSE
REAL_E2E_AUTHORIZED: FALSE
NATIVE_SANDBOX_P0: OPEN
