# D1/D5 Security precode review V1

Project: AI_COMPANY_OS
Revision: 3
Updated: 2026-10-25T14:48:00Z
Updated by: /root/ledger_security_precode, delegated Security technical reviewer
Task: SBX002_D1_D5_TEST_CONTROL_LEDGER_V1
Base: dc313a01b487018ad27fdfd0591f6bb6dad37e38
Reviewed contract: [D1_D5_API_CONTRACT_V1.md](D1_D5_API_CONTRACT_V1.md)
Reviewed exact file SHA-256: 7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30
Decision: APPROVED_FOR_TEST_ONLY_IMPLEMENTATION

## Authority and evidence

This is the actual delegated Security agent's technical precode review, not an
institutional signature, external identity authentication, implementation audit,
operational acceptance or certification. Human authority is the scoped D1/D5
implementation-through-draft instruction in the supplied Texto pegado.txt.
Read AGENTS.md, company state/protocol, Security role, project/architecture/
operations context, repository code-review skill, canonical S0 decision/policy
baseline and material gate, source manifest, historical DR-2/DR-3 and dependency
sections, S1 API/security boundaries, the current task and the exact CTO contract
including all normative final refinements. Read the actual initial draft and
successive refinements; no absent draft or reported approval substitutes for bytes.

## Exact-byte consolidation review

Revision 3 reread the complete frozen consolidated contract after revision 2.
The source changed from d661092e2b91a69100384c365a4df39d01ef0bc0f1468c642c0a96315718b74c
to the exact SHA above. The semantic delta integrates already-binding session,
database and mode arguments into signatures, recovered_invalidated into the
report, and removes superseded recovery acquisition/empty-ATTACH allowances.
The normative expiry/freshness and bounded-read rules remain intact. Approval
is based on the actual complete final bytes, not assumed newline normalization.

## Findings resolved before approval

1. High: recovery could reacquire ownership and obtain fresh authority after a
   connection became uncertain. Final RECOVER is read-only validation followed by
   irreversible in-memory invalidation of every recovered g0; admission stays
   closed. Only a separately identified INVALIDATE operation may persist that
   negative fact. Historical snapshots are not rewritten as durable invalidation.
2. High: connection-only poison could be bypassed by reopening a missing/new DB.
   Final NEW/ATTACH/RECOVER modes bind database_id and session_id, deny empty
   ATTACH, never recreate missing databases on attach/recover, require namespace
   ownership evidence and forbid ATTACH after continuity loss. Cooperating test
   writers must pause/close upon peer termination or failure. A shared in-process
   latch is checked; cross-process notification is a test harness responsibility,
   not a claimed intrinsic SQLite authentication or watchdog mechanism.
3. High: row bounds alone could materialize an oversized hostile SQLite blob.
   Final contract requires scalar typeof/length checks before payload reads,
   SQLITE_LIMIT_LENGTH, exact schema/constraint/trigger/view/index validation,
   configuration rechecks, streaming bounded rows and one consistent transaction
   for precheck and fetch. Schema/config tampering fails closed.
4. Medium: nested operation/event hex expansion could exceed input bounds after
   accepting raw bytes. Conservative encoded-size checks precede encoding/copies;
   actual record length is checked too. record_bytes is a record ceiling, not a
   promise to accept that many raw request bytes. JSON depth/count pre-scan precedes
   parsing and rejects duplicate keys, nonfinite values, BOM and malformed UTF-8.
5. Medium: recovery budget accounting and stored configuration needed precision.
   All head/journal/operation payload visits count; 4096+4096+1 exceeds 8192 and
   must reject. Creation commits exact policy/limits and instance IDs into the
   operation digest/event, with no unreviewed metadata table or default policy.

6. High: a replacement observation or owner acquisition could hide a previously
   expired/stale lease. The final two normative paragraphs require persisted
   expiry and prior-observation freshness checks before EVERY new mutation,
   including ACQUIRE_OWNER, before clearing/replacement. Loss irreversibly
   latches/stops and records invalidation. First-lease initialization is exempt
   only when genuinely unobserved. Historical operation lookup remains first.

No remaining Critical, High or Medium precode blocker was found in these exact
contract bytes. Approval applies only to the complete contract, including its
integrated session/recovery definitions and final clarifications. Any changed bytes require fresh
CTO/Security concurrence before implementing the affected behavior.

## Required implementation properties

- Standard-library sqlite3, exclusive temporary test storage, BEGIN IMMEDIATE,
  effective DELETE/FULL/foreign_keys=ON and the configured busy timeout. Exactly
  three tables; database cap is not a rollback-journal or directory quota.
- Positive exact-integer required ceilings: record_bytes 65536; journal_rows 4096;
  operation_count 4096; replay_row_visits 8192; busy_timeout_ms 1000;
  sqlite_database_bytes 33554432. Lower explicit values may conservatively deny
  work. No bool coercion, unbounded payload fetch or evidence purge for capacity.
- Journal/head/CAS/operation result commit atomically. Operation identity binds
  request, execution, epoch, owner, session, database and full arguments; global
  operation lookup precedes current eligibility. A repeat returns historical
  bytes/state only; conflicting identity rejects and absence never permits replay.
- Negative facts latch and record symbolic stop before storage. Actual uncertain
  COMMIT/ACK poisons and closes the handle; no optimistic result or automatic
  retry. Persistence or stop failure cannot restore admission.
- Recovery verifies the full bounded chain, projections, owner/time/epoch/order,
  operation results, policy and heads independently. It never resumes commands,
  clears invalidation, restores authority or interprets absence as permission.
- Every result and LedgerError permanently declares scope=TEST_ONLY,
  operational=False, authority_authenticated=False, execution_capability=NONE.
  Public objects, flags, hashes and harness assertions are metadata, not credentials.
  g0 only; no Start/Seal/Publish/retry API, second lifecycle reducer or V1 changes.

## Mandatory later verification and retained limits

Implementation review and independent executed QA/Security remain required:
concurrent two-connection/two-process CAS, owner/request/epoch/order negatives,
revocation/expiry/loss, exact idempotency/collisions, before/after-COMMIT crash and
ACK loss, irreversible invalidation and stop/storage failure, missing/replaced
storage and reopen modes, tampered schema/config/large cells/JSON framing,
chain/head/result corruption, exact limits/overflow/exhaustion and bounded
recovery. Preserve full SBX-001/S1 regressions and requested Python 3.11/3.12
and CI evidence. Those are required checks, not results obtained by this review.

The cooperative test harness and synthetic authority do not discharge live DEP-D1,
operational DEP-D5, authentic Windows origin, real stop/cleanup, durable power-loss,
coherent replacement/antirollback or E1-E5. Loss of volatile poison on process
termination is handled by conservative RECOVER and harness continuity rules, not
by claiming failed writes persisted. Native Sandbox P0 remains OPEN. No merge,
providers, VM/VSS, privileged service, operational Run A/E2E or production gate
is authorized by this review.

FUNCTIONAL_CODE_MODIFIED: FALSE
TESTS_EXECUTED: NOT_RUN
REPOSITORY_MUTATIONS: this review file only
SKILLS_SELECTED: code-review
SKILLS_APPLIED: code-review
SKILL_SOURCES: .agents/skills/code-review/SKILL.md
SKILL_SELECTION_REASON: independent security and correctness review of the exact precode API contract
