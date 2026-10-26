# D1/D5 test control ledger API contract V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-25T00:00:00Z
Updated by: CTO
Task: SBX002_D1_D5_TEST_CONTROL_LEDGER_V1
Base: dc313a01b487018ad27fdfd0591f6bb6dad37e38
Status: CTO_APPROVED_SECURITY_CONCURRENCE_PENDING

## Scope and sources

Human authorization is the attached `Texto pegado.txt` supplied for this task.
Governing sources: S1_API_CONTRACT_V1.md, canonical S0 decision/policy baseline,
historical decision record sections 5/7/9 and DR4b ratification. This increment
models only synthetic authority and ownership at g0. It does not implement a
second lifecycle reducer: no lifecycle transition, Start, Seal, Publish or retry
API exists. Existing contracts.py, model.py and S1 wire contracts remain intact.
All public result records AND LedgerError carry fixed fields scope=TEST_ONLY,
operational=False, authority_authenticated=False, execution_capability=NONE.
Construction of a Python object is never authenticated authority.

## Types and bounded inputs

All records below are frozen dataclasses; required fields have no defaults.
Enums are closed string enums. Integers require type(value) is int, excluding
bool; uint64 means 0..2**64-1, positive uint64 excludes zero. UUID means canonical
lowercase non-nil UUID string; digest means 64 lowercase hexadecimal characters.
Identifiers execution_id, epoch, owner_id and operation_id are UUIDs. Times are
uint64 nanoseconds in the explicit synthetic epoch, never wall-clock readings.
Exact bytes only; no callback mappings, subclass coercion, arbitrary serializers
or implicit conversions. Reject unknown fields and enums before persistence.

LedgerLimits fields/maximums (all mandatory positive exact integers):
record_bytes=65536, journal_rows=4096, operation_count=4096,
replay_row_visits=8192, busy_timeout_ms=1000,
sqlite_database_bytes=33554432. Each supplied value may be smaller, never larger.
These are parser/storage engineering limits for tests, not production policy.
Rows and operation counts are GLOBAL per database, not per execution. Each raw
request, event, stored snapshot and result individually obeys record_bytes.
Check lengths/counts before parsing, copying, hashing or iterating. JSON depth
maximum 8, collection entries maximum 64; reject duplicate keys, BOM, nonfinite
numbers, non-UTF8 and unsupported types with bounded pre-scan before json.loads.

SyntheticPolicy fields: freshness_ns, evaluation_duration_ns, lease_duration_ns
(all positive uint64). These are mandatory harness parameters, with no implied
production values. Changes require a new database; store and verify policy and
limits in each creation record and on open/recovery.

Observation fields: epoch, source_sequence (positive uint64), started_ns,
finished_ns (uint64, finished>=started), result (VALID|INVALID|UNPROVEN),
lease_valid (exact bool), continuity_valid (exact bool). Its execution binding
comes from the operation envelope. No arbitrary payloads or external authority
objects. VALID eligibility requires now_ns>=finished_ns, duration<=policy bound,
now_ns-started_ns<=freshness_ns, lease_valid, continuity_valid, and
now_ns<lease_expires_ns. At equality expiry invalidates. Source sequence must
increase strictly; started/finished timestamps must each never decrease; same
epoch is mandatory. Repeated/reversed/wrong-epoch observations never refresh.

Snapshot fields: execution_id, request_sha256, epoch, version (uint64),
journal_sequence (positive uint64), journal_sha256, owner_id (UUID or None),
invalidated (bool), last_observation (Observation or None), lease_expires_ns
(uint64), last_now_ns (uint64), generation (always 0), plus fixed scope fields.
Creation version=0, journal_sequence=1; each later committed operation increases
both independently by one. They are distinct fields, never compared as aliases.
No overflow permitted. invalidated is irreversible; no operation clears it.

OperationResult fields: operation_id, operation_digest, outcome (COMMITTED),
snapshot (the historical post-operation Snapshot), plus fixed scope fields.
LookupResult fields: status (FOUND|ABSENT), result (OperationResult or None),
plus fixed scope fields. FOUND is historical evidence only, never fresh lease.
RecoveryReport fields: status (VERIFIED|INVALID), snapshot (Snapshot or None),
operation (LookupResult or None), rows_visited (uint64), admission_open (always
False), recovered_invalidated (always True), plus fixed scope fields. INVALID reports no trusted snapshot.

## Public signatures

All arguments after the handle are keyword-only. A TestLedger is an explicit
closeable connection wrapper; no global connection or real external ports.

- open_test_ledger(*, directory: pathlib.Path, limits: LedgerLimits,
  policy: SyntheticPolicy, mode: OpenMode, session_id: UUID,
  database_id: UUID, session_continuity: bool, fault: Fault=NONE,
  stop_sink: FakeStopSink) -> TestLedger.
  directory is an existing exclusive temporary test directory, database name is
  fixed `ledger.sqlite3`; no URI or caller-selected SQL. The caller owns directory
  creation/removal. Existing DB is opened without repairing or migrating bytes.
- create_execution(ledger, *, execution_id, request_sha256, epoch, owner_id,
  operation_id, request_bytes: bytes, now_ns: uint64) -> OperationResult.
  Require sha256(request_bytes)==request_sha256. Store no candidate commands;
  bytes are opaque test request data. Creates unlatched control state, no
  observation, lease_expires_ns=0. No authority eligibility yet.
- apply_observation(ledger, *, execution_id, request_sha256, epoch, owner_id,
  operation_id, expected_version: uint64, observation: Observation,
  now_ns: uint64) -> OperationResult.
  Require matching owner and CAS, order, epoch and monotonic now. A valid
  observation records a synthetic lease ending at finished_ns+lease_duration_ns
  (checked uint64 addition). Negative result, lost lease/continuity, stale or
  expired observation irreversibly invalidates and records the negative fact.
  Already latched state may only append further negative observations; VALID
  cannot rehabilitate. Structurally invalid ordering raises OBSERVATION_ORDER
  and latches the handle; it never supplies freshness.
- commit_control_update(ledger, *, execution_id, request_sha256, epoch, owner_id,
  operation_id, expected_version: uint64, action: ControlAction,
  new_owner_id: UUID or None, now_ns: uint64) -> OperationResult.
  ControlAction=ACQUIRE_OWNER|CHANGE_OWNER|INVALIDATE|CHECK.
  ACQUIRE_OWNER requires new_owner_id=owner_id; explicit initial/live-session claim
  against the recorded owner (or unowned state) and matching CAS. CHANGE_OWNER
  requires current owner and distinct non-null new_owner_id. INVALIDATE/CHECK
  require new_owner_id=None. CHECK requires current eligible authority/lease.
  CHANGE_OWNER also requires current eligibility and clears observation/lease;
  the new owner must obtain a new observation. ACQUIRE_OWNER never renews a
  lease and clears observation/lease; it cannot clear invalidation. INVALIDATE
  latches before IO and records invalidation even when authority expired.
- recover(ledger, *, execution_id: UUID|None, now_ns: uint64,
  uncertain_operation_id: UUID or None) -> RecoveryReport.
  Read-only bounded full database validation, independent new connection after
  uncertainty; cannot run on a poisoned handle. RECOVER handles begin
  RECOVERY_REQUIRED. VERIFIED irreversibly invalidates recovered g0 in memory;
  only explicit durable INVALIDATE and reads may follow. Historical invalidation
  remains; no recovery acquisition or positive observation is permitted. If uncertain_operation_id is supplied, FOUND identifies
  the exact historical result; ABSENT means no confirmed operation and forbids
  automatic replay. Recovery is never itself a write or successful mutation.
- lookup_operation(ledger, *, execution_id, request_sha256, epoch, owner_id,
  operation_id, operation_digest: str) -> LookupResult.
  Search operation_id globally; mismatched identity/digest raises OPERATION_CONFLICT.
- read_snapshot(ledger, *, execution_id) -> Snapshot.
  Snapshot is historical; reading does not evaluate or grant current authority.

NEW and continuous-session ATTACH handles are READY. RECOVER handles require
recover before any writes, then permit only durable INVALIDATE.
Handle states are READY|RECOVERY_REQUIRED|POISONED|CLOSED, with an independent
per-execution irreversible in-memory latch and post-recovery admission closure.
A poisoned handle rejects every call except close; use a newly opened handle
for recovery. Close never clears state in an existing live handle. Restart always requires
RECOVER, including after uncertain commits; continuous-session ATTACH is not restart.
No implicit reopening, retries or replay occurs in any API.

## Exact operation identity and storage

Wire codec identifier is TEST_CONTROL_LEDGER_V1. Encode each closed operation
as UTF8 JSON, sort_keys=True, separators=(',', ':'), ensure_ascii=True,
allow_nan=False. Fields are api (exact public mutation name), execution_id,
request_sha256, epoch, owner_id, operation_id, session_id, database_id, and arguments (all mutation-specific
arguments above including expected_version when present, now_ns, observation,
action, new_owner_id, and request_bytes represented as lowercase hex). Hash the
exact resulting bytes with SHA256; do not normalize IDs or caller request bytes.
The operation digest includes owner/request/execution and the complete payload.
Fault and stop sink are test controls and never enter durable operation identity.

Mutation transaction order: bounded input validation; BEGIN IMMEDIATE; lookup
operation_id FIRST, before CAS, current lease, latch or other eligibility. Exact
match returns stored OperationResult unchanged (rollback read transaction);
mismatch rejects. A historical result cannot renew authority. Then verify head,
identity, CAS and the current explicit now_ns; now must never decrease. Evaluate
guards and append exactly one event, replace head and insert operation result
in the SAME transaction. Return success only after confirmed COMMIT and ACK.
A duplicate create with different operation_id rejects EXECUTION_EXISTS.
Ordinary guard rejection does not consume operation_id, version or sequence.
On known expiry discovered by CHECK, latch and stop precede persistence; record
an INVALIDATE event/result in that same operation, returning the invalidated
snapshot rather than optimistic CHECK success. outcome COMMITTED means durable
control fact, not eligible authority; inspect snapshot.invalidated.

Exactly three tables: heads (execution_id PK, database_id, session_id, exact snapshot bytes), journal
(execution_id, sequence composite PK, operation_id UNIQUE, exact event bytes,
prefix_sha256, FK execution_id), operations (operation_id PK, execution_id FK,
operation_digest, exact operation bytes, exact result bytes). No other table,
framework, trigger, opaque authority registry or history pruning. Event closed
shape: codec, operation bytes (hex), before_version (uint64 or None for create),
after_snapshot (Snapshot excluding journal_sha256), sequence. Prefix digest at n
is SHA256 of concatenated uint64 big-endian byte-length followed by exact event
bytes for rows 1..n for that execution. Empty prefix is SHA256(empty). The digest
is stored outside event bytes, avoiding self-reference. A later event referencing
a prefix never becomes part of that earlier prefix. Hash raw stored event bytes;
verify canonical encoding separately, never repair by reserializing.

Set/verify effective journal_mode=DELETE, synchronous=FULL, foreign_keys=ON,
busy_timeout=limits.busy_timeout_ms. Use BEGIN IMMEDIATE for each mutation.
Set max_page_count=floor(database_limit/page_size), verify effective cap and
actual database size. Reject too-small capacity or oversized existing DB.
The cap covers the database file ONLY, not rollback journal/directory; tests must
cover journal/temp/disk exhaustion. Do not delete journal/evidence to make room.
No PRAGMA modification of existing incompatible DB to silently make it pass.

## Invalidation, failures and recovery

FakeStopSink is an in-memory recorder only: stop(execution_id, reason) appends a
symbolic request; never invokes an OS command or callable supplied as payload.
Before persistence of a negative fact, latch the execution in memory and emit
stop; storage failure cannot delay stop. All persistence failures latch relevant
execution(s), stop and poison/close connection. Unexpected stop failure likewise
closes admission. No successful mutation result is synthesized on failure.

Fault enum: NONE|BEFORE_WRITE|BEFORE_COMMIT|AFTER_COMMIT_BEFORE_ACK. The first two
raise PERSISTENCE_FAILURE with confirmed rollback if possible, poison anyway;
last raises COMMIT_UNCERTAIN after commit attempt and poisons. Any actual COMMIT
exception/unknown rollback result is COMMIT_UNCERTAIN. Do not infer outcome from
SQLite exception text. Controlled process termination tests supply crash points
externally, with no candidate command execution. Fault selection is fixed on open.

Recovery validates ALL tables and all executions under one read transaction:
closed codecs/types/limits, PK/FK integrity, no orphan/duplicate/missing rows,
contiguous per-execution sequences, prefix hashes, operation digests/identities,
exact stored results, version progression, owner changes, epoch/time/source
continuity, generation=0 and monotonic invalidation. Recompute expected control
projection using the SAME control rules as mutation; verify every head against
last row and each operation/result against its row. No second S1 lifecycle
reducer. Reject inconsistent persisted policy/limits. Check row counts before
fetch; stream bounded rows. Count each journal/operation/head row visit; exceed
replay_row_visits => RECOVERY_LIMIT, no partial verified success. SQLite
integrity_check and foreign_key_check must be bounded by the database cap and
counts; unavailable/corrupt input fails closed. Stored evidence cannot prove
antirollback against a coherent replacement of all three tables.

Stable LedgerError codes: INVALID_ARGUMENT, LIMIT_CONFIGURATION, RECORD_LIMIT,
CAPACITY_LIMIT, DATABASE_CONFIGURATION, STORAGE_CORRUPT, EXECUTION_NOT_FOUND,
EXECUTION_EXISTS, IDENTITY_MISMATCH, OPERATION_CONFLICT, CAS_CONFLICT,
OWNER_MISMATCH, OBSERVATION_ORDER, CLOCK_ORDER, AUTHORITY_DENIED, INVALIDATED,
RECOVERY_REQUIRED, RECOVERY_LIMIT, RECOVERY_INVALID, PERSISTENCE_FAILURE,
COMMIT_UNCERTAIN, CONNECTION_POISONED, CONNECTION_CLOSED, BUSY.
Errors expose only code and fixed scope fields, no SQL/path/request payload.
BUSY is a confirmed pre-write lock failure, no automatic retry and no successful
result. Bound arithmetic overflow is INVALID_ARGUMENT before mutation. Corrupt
storage closes admission; failed recovery cannot permit writes. Unknown errors
are never coerced into acceptance. Test-only durability does not certify power
loss, real Windows authority, independent real stop or operational D1/D5.

## Explicit test-session boundary

OpenMode is NEW|ATTACH|RECOVER; session_continuity is exact bool. NEW requires an empty exclusive test
directory and no existing DB; creates once. ATTACH requires an existing DB,
session_continuity=True and matching session_id in all creation records; it
joins only a continuously running controlled test session. A missing database
is an error in ATTACH/RECOVER, never recreated. NEW cannot reuse a failed or
previously used namespace. The harness keeps that namespace ownership evidence;
SQLite cannot prove that a deleted namespace never existed. A new namespace
cannot claim to recover the identity of a prior execution.

The harness is responsible for sharing failure/latch notifications among its
controlled writers and terminating/closing every writer when session continuity
is lost. ATTACH is an explicitly unauthenticated test assertion, not a recovery
mechanism or proof against arbitrary independent processes. In-process handles
for the same directory/session share a monotonic latch; cross-process tests use
the harness stop recorder/channel to close all writers upon observed failure.
No claim of instantaneous unseen failure detection or real independent watchdog
is made. Operation eligibility always checks the shared in-process latch.
Concurrency tests may ATTACH two connections/processes to the same live synthetic
session. They may not use ATTACH after a crash, failure or lost continuity.

RECOVER requires session_continuity=False, opens admission-closed, validates the
entire database independently, and irreversibly invalidates every recovered g0
in memory before returning. RecoveryReport.recovered_invalidated is always True. snapshot remains the historical verified
snapshot, never a rewritten claim of committed invalidation. The report's
admission_open remains False. The only subsequent allowed mutation on that
handle is INVALIDATE, which may append the invalidation durably with a NEW
operation_id after CAS and historical lookup; it never clears the latch.
ACQUIRE_OWNER cannot rehabilitate recovered g0. No command or positive authority
update follows recovery. Unresolved absent uncertain operations remain absent;
the original operation is never replayed. Failure to persist recovery invalidation
leaves the local latch and all admissions closed. Opening another RECOVER handle
repeats conservative invalidation even if the disk never recorded the failure.

Creation records and operation envelopes include session_id. All executions
in one ledger use one session_id. ATTACH of an empty database is rejected
RECOVERY_REQUIRED. RECOVER of an empty DB is VERIFIED with no snapshot only
when execution_id is None; requested missing execution yields EXECUTION_NOT_FOUND. No new execution
may be created through RECOVER. Repeated RECOVER calls remain read-only and
cannot clear recovered_invalidated. Close/poison cannot transfer recovery rights.

Before selecting any stored text/blob column, verify its SQLite typeof and
length using scalar queries and bounded counts; reject oversized/nonexact cells
without materializing bytes. Set sqlite3 SQLITE_LIMIT_LENGTH to the maximum
bounded row envelope supported by this schema (no more than 8*record_bytes),
verify it, and retain stricter per-field record_bytes checks. No unbounded
fetchall of journal/operation payloads. Validate exact three-table schema,
columns/types/PK/FK/uniqueness, and absence of unexpected tables, triggers,
views or indexes beyond declared PK/UNIQUE indexes. Schema/config tamper fails
closed. Recheck effective configuration/schema before mutation and recovery;
set trusted_schema=OFF when supported, never execute supplied SQL/schema code.

Bounds include all encoded representations: hex doubles bytes and nested event
and result envelopes add overhead. Reject RECORD_LIMIT before encoding when
its conservative computed size exceeds the limit; check actual encoded length
as well. A request of record_bytes raw bytes may therefore be unrepresentable;
record_bytes is a per-record ceiling, not a guaranteed accepted payload size.
These constraints do not authorize increasing any limit. A checked, bounded
canonical byte buffer is the only input to JSON parse/digest operations.

database_id (UUID) is mandatory on open, supplied
by harness for NEW and expected unchanged for ATTACH/RECOVER. Store database_id
and session_id in every operation envelope/creation event and as non-null columns
on heads; recovery verifies equality across all rows. Create the execution through NEW first, then attach concurrent writers. Wrong
instance identity rejects IDENTITY_MISMATCH; no fallback to NEW. Coherent
replacement using the same IDs remains outside authenticated antirollback proof.
The harness must pause/revoke all cooperating processes upon unexpected peer
termination before any further admission, close all handles and use RECOVER.
This test cooperation is not an implemented operational broker/watchdog or an
assertion that cross-process volatile poison is intrinsically shared by SQLite.

Recovery visits count logical rows read from heads, journal and operations,
INCLUDING the selected head; scalar count/type/length prechecks do not grant
extra payload visits. Each streamed payload row is counted once; recomputing
its projection in memory does not add a visit. No join may hide multiple source
rows behind one visit. 4096 events + 4096 operations + 1 head is 8193 and exceeds
8192: recovery fails RECOVERY_LIMIT conservatively at that combination. Smaller
configured recovery budgets may make otherwise bounded stores unrecoverable;
never claim that maximum count ceilings guarantee budget fit.

recover execution_id is UUID|None: None validates the complete ledger and returns
snapshot=None; a UUID selects a historical snapshot after complete validation.
All scalar length/type/count checks and their corresponding payload reads share
one SQLite read transaction (or the mutation BEGIN IMMEDIATE transaction), so
concurrent writes cannot race the prechecks. The creation operation arguments
include the exact LedgerLimits and SyntheticPolicy field objects as well as
session_id/database_id; their canonical bytes are part of the operation digest,
event and durable configuration verification. Changed configuration rejects
DATABASE_CONFIGURATION before admission. No separate metadata table exists.

For apply_observation, lease_expires_ns in the eligibility formula is the newly
derived finished_ns+policy.lease_duration_ns; CHECK/CHANGE_OWNER use the persisted
expiry. This allows a first valid observation after creation/explicit acquisition,
without treating the initial expires=0 as authority. NEW requires
session_continuity=True; RECOVER requires False; ATTACH requires True.

Lease renewal cannot rehabilitate missed continuity: when a prior observation
exists, apply_observation first checks now_ns against the PERSISTED expiry and
prior observation freshness. If now_ns>=persisted lease_expires_ns or
now_ns-prior.started_ns>freshness_ns, latch/stop before considering replacement,
commit an invalidated control snapshot, and never accept positive replacement
as renewed authority. Only an unobserved initial or explicitly changed-owner
state may establish its first lease from the new observation. An invalidated
state remains invalidated regardless of either expiry calculation.

The persisted-expiry/freshness check above applies to EVERY new mutation,
including ACQUIRE_OWNER, before any clearing/replacement of observation state.
An observed expired/stale execution therefore cannot hide the loss by acquiring
the same owner, changing owner or resetting observation. Historical idempotency
lookup remains first and returns unchanged historical evidence. A new operation
that discovers expiry/staleness records invalidation (if possible), never a
successful acquisition. The unobserved initial-state exemption is not a means
to remove previously observed history; recovery validates this progression.
