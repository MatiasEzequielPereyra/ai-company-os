# SBX-002 D1/D5 test control ledger V1

Project: AI_COMPANY_OS
Revision: 6
Updated: 2026-10-26T22:14:37Z
Updated by: Engineering Orchestrator A continuing EM coordination
Task ID: SBX002_D1_D5_TEST_CONTROL_LEDGER_V1
Owner: backend
Assigned by: engineering-manager
Status: REVIEW
Workflow phase: CODE_REVIEW
Functional implementation gate: APPROVED_TEST_ONLY
Base SHA: dc313a01b487018ad27fdfd0591f6bb6dad37e38
Worktree: Z:/repos/ai-company-os/worktrees/sbx002-d1-d5-test-ledger-v1
Final target: D1_D5_IMPLEMENTED_READY_FOR_EXTERNAL_B_AUDIT

## Recovery identity corrective authorization successor

Task: SBX002_D1_D5_P1_RECOVERY_IDENTITY_REVIEW_V1.
Human Project Owner explicitly requested reproduction of recover(A, B1) on two
executions, then a minimal correction if confirmed, independent CTO/Security/QA
review, Python 3.11/3.12 regressions and publication to the same draft PR83.
Audited predecessor: a5843d11670056516c2077b18652f7f91a49ef43. External B decision:
CHANGES_REQUIRED_PENDING_REPRODUCTION. Existing approvals remain historical;
they do not approve the new corrective delta. No merge, V1/S1 changes, services,
providers, VMs, operational writable, Run A or other increment is authorized.

2026-10-26T22:14:37Z: Engineering Orchestrator A continuing EM coordination
records REVIEW -> READY -> ACTIVE for the assigned backend corrective subtask.
The root ticket remains REVIEW pending corrected submission and external B.
Backend /root/recovery_backend owns the isolated reproducer and minimal patch;
/root/recovery_cto and /root/recovery_security independently selected existing
OPERATION_CONFLICT for a foreign existing operation, preserving global None,
actual ABSENT and full bounded validation. QA /root/recovery_qa independently
verifies the corrected boundary. Functional source remains unchanged until
the original observable failure is captured. Shared indexes remain outside
task-local ownership. Successor evidence and result are appended at submission.

## Authorization receipt

Human Project Owner explicitly authorized this exact task in “AI COMPANY OS —
AUTORIZACIÓN DE IMPLEMENTACIÓN D1/D5”, recovered 2026-10-25 from attachment
`C:/Users/LA NAVE/.codex/attachments/377aaf2f-6cc9-41a6-98d3-587a945946ff/Texto pegado.txt`.
The instruction authorizes the full implementation, corrections, independent
reviews, tests and one verified draft PR, without new permission for subtasks.
This receipt records scope; it does not authenticate an external authority.

Permitted: Python stdlib sqlite3; SQLite writes only in exclusive temporary test
directories; controlled connections and child test processes; fault injection
and termination of owned test processes; local tests/regressions; branch commit
and push without force; one draft PR. Required settings are BEGIN IMMEDIATE,
journal_mode=DELETE, synchronous=FULL, foreign_keys=ON, verified effectively.

Retained restrictions: no main merge, VM/Hyper-V/VSS, privileged service/broker,
operational sandbox or writable activation, Run A or operational E2E, real AI
providers, system permission changes, production deployment, V1 contract
changes, or other S2 increments. Native Sandbox P0 remains OPEN. Every result
must declare scope=TEST_ONLY, operational=False, authority_authenticated=False,
execution_capability=NONE. g0 only; no g1 retry or operational integration.

## Assignment and dependencies

Backend owns implementation after EM assignment and both CTO and Security approve
the same definitive API contract SHA-256. ACTIVE currently permits preparation,
not functional code. CTO owns API/transaction decisions; Security owns synthetic
trust/invalidation/recovery approval; QA independently validates; DevOps validates
SQLite storage/concurrency/failure/CI conditions. Orchestrator A coordinates.
External Orchestrator B owns the final contraaudit of the published draft.

- S1 baseline: PR82 merged at base dc313a01b487018ad27fdfd0591f6bb6dad37e38;
  administrative closure is recorded separately after all applicable approvals.
- DR-2 preserves single-retry restrictions; this slice permits only g0.
- DR-3 requires same-commit authority/CAS fencing and irreversible invalidation.
- Historical DEP-D1 is live authority/lease; this implements synthetic test control
  only. DEP-D5 is durable ledger/head/cleanup/ownership; SQLite test results do not
  discharge operational durability, antirollback or Windows authority guarantees.
- Pending blockers for functional code: CTO and Security exact-contract approvals.
  No human reauthorization is needed for those already-authorized reviews.

Sources: [S0 decisions](../docs/architecture/native-sandbox/SBX002_DECISION_POLICY_BASELINE_V1.md),
[historical dependencies](../docs/engineering/sbx002-d6/NATIVE_SBX_002_CTO_SECURITY_DECISION_RECORD_V1.md),
[S1 contract](../docs/engineering/sbx002/S1_API_CONTRACT_V1.md),
[assignment](../docs/engineering/sbx002/D1_D5_EM_ASSIGNMENT_V1.md).

## Acceptance criteria

1. Atomic journal, head, CAS version and operation registry in one SQLite
   transaction; effective configuration rejected if incompatible.
2. Two connections and two child processes competing on one CAS cannot both commit.
3. Strict owner/request/execution/epoch/observation identity and order; synthetic
   lease expiry, revocation and loss fail closed; reuse S1 reducer invariants.
4. operation_id binds identity, owner and digest; exact replay returns historical
   result without renewed authority; conflicting identity/digest rejects.
5. Uncertain COMMIT/ACK closes writes until bounded reconciliation; no automatic
   retry, invented outcome or optimistic writes from uncertain connections.
6. Irreversible invalidation persists all causes; persistence failure closes
   admissions and requires safe recovery rather than rehabilitation.
7. Recovery verifies journal/head/operations/sequences/continuity; rejects tamper,
   incomplete records, inconsistent head and corruption; never resumes commands,
   restores authority or treats missing data as replay permission.
8. Mandatory exact positive integer limits reject bool: record_bytes=65536,
   journal_rows=4096, operation_count=4096, replay_row_visits=8192,
   busy_timeout_ms=1000, sqlite_database_bytes=33554432. Bound costly work,
   rollback journal/temp/storage exhaustion; no evidence purging.
9. Independent tests cover concurrency, lease/observation/identity negatives,
   idempotency collisions, crash before/after COMMIT, ACK loss, corruption,
   exact boundaries, exhaustion, bounded recovery and irreversible invalidation.
10. Full SBX-001/S1 regressions, Python 3.11/3.12, applicable CI and distributed
    package validation when applicable; distinguish actual PASS from NOT_RUN.
11. Independent CTO/reviewer, QA and Security evidence addresses exact delivered
    head; draft includes base/head, files, contract hash, tests, faults/corrections,
    limitations, Git state and acceptance recommendation for B. No merge.

## Transition log

| UTC | From | To | Actor/role | Reason and evidence |
| --- | --- | --- | --- | --- |
| 2026-10-25T14:39:45Z | NONE | BACKLOG | /root/ledger_em / engineering-manager | Register human-authorized scope, backend and dependencies. |
| 2026-10-25T14:39:45Z | BACKLOG | READY | /root/ledger_em / engineering-manager | Preparation has owner, criteria, base and explicit authorization; functional review remains gated. |
| 2026-10-25T14:39:45Z | READY | ACTIVE | /root/ledger_em / engineering-manager | Authorized precode preparation starts; no functional code before exact CTO+Security approvals. |

## Evidence at registration

Implementation and tests: NOT_RUN. Contract approval: PENDING. Shared historical
state indexes/current-handoff pointers remain outside this task-local ownership.
This ticket and its assignment are the durable coordination sources.
## Precode gate successor acknowledgement

Recorded 2026-10-25T14:46:08Z by /root/ledger_em (engineering-manager).
EM directly verified frozen D1_D5_API_CONTRACT_V1.md SHA-256
`7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30`,
[CTO approval and recovery interpretation](../docs/engineering/sbx002/D1_D5_CTO_PRECODE_REVIEW_V1.md),
and [Security revision 3 approval](../docs/engineering/sbx002/D1_D5_SECURITY_PRECODE_REVIEW_V1.md)
of those same bytes. Security document's declared Updated time is
2026-10-25T14:48:00Z; that is source metadata, not EM's recording time.
The approvals resolve the historical pending precode dependencies above.
Orchestrator A authorized the assigned backend to begin functional implementation
under this exact contract. ACTIVE continues, workflow IN_PROGRESS, gate
APPROVED_TEST_ONLY. This acknowledges technical permission only, not completion.

CTO's addendum requires corruption/inconsistency/recovery-budget errors to close
admission and poison/close the connection, emit no partially trusted snapshot or
report, and reconcile with a new RECOVER handle. API bytes remain unchanged.
All test-only ceilings, modes, identity/session requirements and exclusions remain
binding. Implementation verification, independent review, QA, Security implementation
review and verified draft publication remain pending. S1 administrative closure is
DONE only for its pure core; it supplies no operational authorization.

## Implementation submission successor

2026-10-26T02:33:47Z — ACTIVE -> REVIEW, Engineering Orchestrator A continuing
the EM backend assignment. Backend completed the frozen API implementation;
independent CTO, QA and Security implementation reports approve TEST_ONLY draft
submission with no open scoped P0/P1. Four ledger suites: 110 PASS per Python
runtime. Full Python 3.11.9 and 3.12.10 each completed with 1427 PASS and one
pre-existing OS symlink-permission skip. Existing SBX-001/S1 regressions remain
unchanged. npm 3/3 and the installed packed artifact E2E passed locally.

See [delivery and limitations](../docs/engineering/handoffs/ai-company-os/sbx002-d1-d5-test-control-ledger-v1.md)
and the linked exact-source role reports. The initial environment-probe hang and
all retained corrective findings are distinguished from passing final runs.
Official checks on the published commit and External Orchestrator B contraaudit
remain publication-stage gates. REVIEW is not DONE, merge permission, live D1
authentication, operational D5 certification or permission for other S2 work.

## Same-owner continuity corrective successor

2026-10-26T02:38:23Z — Internal Security /root/ledger_security_resume confirmed
a P1 after initial draft publication: same-owner ACQUIRE could clear the visible
observation and allow source sequence/expiry reset. Existing approval of HEAD
902d0c7767a2ef96183e83013c77df08fb0c4f3e is withdrawn for this finding. Six new
independent Security cases preserve four failures and two valid controls; the
authoritative predecessor reproduction is 4 FAIL / 25 PASS including prior cases.

Engineering Orchestrator A continuing EM coordination records REVIEW -> READY
on that failed criterion, then READY -> ACTIVE for assigned backend corrective
work under the existing human authorization. No API/V1/S1 contract change is
authorized or needed: retain hidden same-owner continuity from validated history
for mutation/recovery guards, preserve visible Snapshot clearing, and preserve
the explicit legitimate changed-owner exemption. PR83 remains draft. Earlier
checks/source manifests describe their historical commit, not corrected readiness.

2026-10-26T02:44:00Z — ACTIVE -> REVIEW, Engineering Orchestrator A continuing EM
coordination. Corrected same-owner continuity is enforced by the existing bounded
shared replay/projection, with no public API/schema/V1/S1 change. CTO delta review,
QA revision3 and Security revision2 approve corrected TEST_ONLY bytes. Ledger116
and ledger+SBX-001/S1 1146 cases pass on each target Python runtime. Corrected full
Python3.11/3.12 each completed 1433 PASS and the same pre-existing symlink skip;
the corrected installed tarball E2E passed. See the immutable successor
[correction handoff](../docs/engineering/handoffs/ai-company-os/sbx002-d1-d5-continuity-correction-v1.md).
PR83 stays draft; corrected published-HEAD official CI and B contraaudit remain
required. No operational authority, merge permission or other increment follows.

## Recovery identity corrected submission

2026-10-26T22:18:30Z: corrective subtask ACTIVE -> REVIEW, Engineering
Orchestrator A continuing EM coordination. Parent ticket remains REVIEW.
Original recover(A,B1) mixed A's snapshot with B's FOUND operation; the exact
unchanged regression gave 2 FAIL / 9 PASS before and 11 PASS after on both
target runtimes. CTO and Security approve existing OPERATION_CONFLICT before
constructing a report, retaining explicit global recovery and genuine absence.
Six source lines only; no public API/schema/V1/S1 changes. Independent QA18 per
runtime and scoped Security probes approve TEST_ONLY correction. Complete
ledger/SBX-001/S1: 1175 PASS per runtime; full Python: 1462 PASS / 1 existing
OS symlink skip per runtime. npm3 and installed package E2E PASS. See immutable
[recovery identity successor](../docs/engineering/handoffs/ai-company-os/sbx002-d1-d5-recovery-identity-correction-v1.md).
Exact corrected published-HEAD CI and External B reaudit remain required;
the prior implementation approvals are historical. No DONE/merge or operational
acceptance is claimed. All original retained restrictions remain binding.
