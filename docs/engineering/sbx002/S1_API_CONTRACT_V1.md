# S1 pure core API contract V1

Project: AI_COMPANY_OS
Revision: 1
Task: SBX002_S1_PURE_CORE_IMPLEMENTATION_V1
Base: 12439870d44ead5b538c2ecd33f776ebc15efe12
Status: CTO_VALIDATED_SECURITY_REVIEW_PENDING

## Authority and trust

Human Project Owner authorizes implementation through a draft PR, tests and CI.
No merge, S2, broker, runner, provider, VM, filesystem backend or operational
authority is authorized. DR4b's ratified mapping governs. Preserve closed V1
contracts without editing contracts.py. New modules may import its public APIs.
Python data objects, PolicyApproval and fake port observations never authenticate
any real principal. All results carry simulation-only scope. No API emits
VerifiedHostEvidence or calls an operating-system service.

## Limits and APIs

All new codecs require S1SyntheticLimits, a frozen value with six REQUIRED integer
fields: piece_bytes, total_bytes, depth, items, pieces, events. No defaults.
CTO-reviewed safety ceilings for synthetic use ONLY: piece_bytes <= 8 MiB,
total_bytes <= 32 MiB, depth <= 12, items <= 256 per collection,
pieces <= 64, events <= 256. Values must be positive exact integers (not bool).
These ceilings are engineering parser protections, not ratified evidence quotas
or production profiles. B's precise numerical ceilings were not supplied in the
handoff; CTO/Security must explicitly review these proposed synthetic ceilings.
Existing V1 byte and output limits remain unchanged. A synthetic envelope limit
may reject a larger otherwise-valid V1 without changing its standalone validator.
Nested JSON is pre-scanned before json.loads to bound nesting; duplicates,
nonfinite, BOM, invalid UTF-8, invalid types and unknown keys fail closed.
Count all supplied resolved bytes, including unreferenced pieces; reject unused
pieces. Hash raw bytes without canonicalizing or reserializing inputs.

Public API (keyword arguments where indicated):

- decode_piece(raw: bytes, *, expected_digest: str, kind: str,
  limits: S1SyntheticLimits) -> DecodedPiece. Supported new schemas are the exact
  closed shapes in historical §4: capture-evidence, cleanup-evidence,
  host-evidence, receipt-package, rejection-record, live-state; auxiliary
  PolicyApproval has an explicitly selected kind, without adding a schema field.
  DecodedPiece retains immutable raw bytes and a recursively frozen view.
- check_package_consistency(raw: bytes, *, expected_digest: str,
  pieces: Mapping[str, bytes], payloads: Mapping[str, bytes],
  outputs: Mapping[str, bytes], now: datetime,
  limits: S1SyntheticLimits) -> ConsistencyReport. Resolve refs only from supplied
  digest mapping. Validate request/V1 with existing public validators. Check all
  identity, generation, epoch, sizes, digests, output bindings, acyclic references,
  cleanup, monitor, causes, retry and package discriminants. Missing required
  audit references is rejection, never inferred trust. Audit payloads are opaque
  bounded exact bytes: S1 verifies references/digests, not operational meaning,
  authenticated continuity or truthful observations. The report includes
  unauthenticated_audit=True; no claim of substantiated real host facts.
  Report says structural consistency only, scope SIMULATION, operational=False.
  Wire provenance OPERATIONAL is parsed but cannot elevate this report.
- reduce_causes(state: CoreState, observations: tuple[Event,...], *,
  limits: S1SyntheticLimits) -> CoreState. Pure ordered reduction, same epoch,
  increasing sequence and monotonic ticks; preserve causes and irreversible latch.
- evaluate_transition(state: CoreState, event: Event, context: Context) -> Decision.
  Implements A/B/C/D, explicit phase/guards and residual D20; effects are tuples of
  symbolic descriptions only. No implicit truth for missing/UNPROVEN facts.
- evaluate_retry(state: CoreState, context: Context) -> Decision. Exactly g0 to g1,
  pre-code, matching immutable request, cleanup and authority confirmed, no latch,
  gaps, restart, timeout, uncertain commit or consumed retry. Context includes
  accumulated capture/preparation times (<=120/180 s), unchanged expiry and
  first-close budget (<=450 s), plus planned work and 100 s closing reserve.

CoreState freezes lifecycle/result/resource enums, epoch, sequence, tick,
generation/retry count, started flag, invalidation latch and causes; captures
RetryResolution as explicit data. Event has kind, epoch, sequence, tick and cause.
Context consists of exact booleans/typed enums and explicit time/budget/commit
facts. Construction validates types; missing facts must not default to authority.
Terminal content is immutable; later permission to publish is separate.
Pure transitions model commit intent and confirmed fake outcomes separately.

ContractError is reused for closed, nonsensitive rejection codes. Bad arguments
reject with stable codes rather than generic exception coercion. Invalid model
combinations close gates; no exception is converted to acceptance. Cause codes
are the closed historical registry. Proposed auxiliary API/dataclass names may
be refined by CTO before implementation; any behavioral contract change requires
CTO/Security review before code proceeds.

## Tests and limitations

Exercise all codec shapes and nested types, boundary n/n+1, source/digest/reference
tampering, duplicate/cycle/unused inputs, fake authority and PolicyApproval,
missing/unproven cleanup/monitor, all lifecycle/result/resource combinations,
terminal-first and result precedence, g0/g1 retry guards, sequence/epoch/tick
errors, deterministic Start/Invalidate/Seal/Publish intercalados, fake journal and
commit failures. Include independent expected mapping cases (not self-generated
expected results), V1 regressions and full applicable suites/CI.
No test here certifies actual durability, cleanup, IPC, fencing or E1–E5.

## Exact pure-model representation

These internal Python records are distinct from historical closed wire objects.
All records are frozen, collections tuples or recursively read-only mappings;
public construction never confers trust. Required fields have no implicit grants.

CoreState required fields: lifecycle (16 historical C5 names), result (PENDING,
COMPLETED, FAILED, CANCELLED, TIMED_OUT, INVALIDATED), resources (NONE,
PARTIAL_CREATION, PREPARED, POSSIBLY_ACTIVE, POWER_OFF_CONFIRMED,
DESTRUCTION_PENDING, CLEANUP_CONFIRMED, QUARANTINED), epoch (canonical non-nil
UUID), sequence (uint64), tick_ns (uint64), generation (0/1), retry_count (0/1),
started (bool), invalidated (bool), causes (tuple of Cause), retry_resolution
(RetryResolution or None), request_sha256 (lowercase SHA256). Integers exclude
bool. Generation/retry_count agree. INVALIDATED implies invalidated=True and
cannot be reduced. Conversely invalidated=True requires result=INVALIDATED; a
latched state can never retain COMPLETED. Later post-seal permission observations
do not rewrite the sealed state or latch. SEALED/PUBLISHED require non-PENDING result and
CLEANUP_CONFIRMED. REJECTED requires started=False, resources=NONE, non-PENDING
result. Invalid state rejects before row selection, never silently repairs.

Event required fields: kind (ADVANCE, START, COMPLETE, CANCEL, DEADLINE,
INVALIDATE, OPERATION_FAILURE, PRE_RUN_TRANSPORT_FAILURE, JOURNAL_FAILURE,
COMMIT_FAILURE, RETRY, SEAL, PUBLISH, QUERY), epoch (UUID), sequence (uint64>0),
tick_ns (uint64), cause (Cause or None). Cause is exactly the historical
code/event_sequence/observed_tick/generation record. Cause sequence/tick match
the event; generation matches state except a historically bound retry resolution.
Invalidating/journal/commit failure events require an invalidating cause; CANCEL
and DEADLINE require matching cause; pre-run transport failure identifies g0.
Reject unknown events/codes, wrong epoch, non-increasing sequence or decreasing
tick. QUERY is observational, does not mutate or consume sequence. Accepted
nonterminal observations advance sequence/tick; terminal evidence stays immutable.

Context required bool fields: authority_valid, lease_valid, owner_valid,
monitor_valid, continuity_valid, preflight_valid, capacity_valid,
absence_proven, power_off_confirmed, cleanup_confirmed, close_failure,
ownership_ambiguous, commands_complete, collection_complete,
collection_expired, final_evidence_complete, capture_coherent,
commit_confirmed, commit_uncertain, fence_valid, request_unchanged,
start_committed, code_send_uncertain, restarted. False means not demonstrated,
never absence proven. absence_proven is an independent affirmative fact;
absence_proven=False cannot mean resources are absent. Additional required fields:
subphase (NONE, CAPTURE_PENDING, CAPTURE_CREATED, CAPTURE_VERIFIED,
CAPTURE_CLEANED, FINAL_GATE), capture_elapsed_ns, prepare_elapsed_ns,
first_close_elapsed_ns, planned_work_ns, now_ns, expires_ns (uint64, same epoch),
request_sha256 (SHA256). No live authority is obtained from these fake facts.

Decision required fields: rule (A_REJECT, B_TERMINAL, B_PUBLISH, C_REDUCE,
D1..D5, MAP_D6, D7..D20, RETRY_ALLOWED, RETRY_REJECTED), allowed (bool),
next_state (CoreState), effects (tuple of symbolic names), reason (closed
nonsensitive code), scope (always SIMULATION), operational (always False).
Effects are closed: NO_EFFECT, REJECT, STOP, DESTROY, QUARANTINE, RECOVER,
CAPTURE_INTENT, PREPARE_INTENT, START_INTENT, COLLECT, VERIFY_CLEANUP,
FINAL_CAPTURE_INTENT, SEAL_INTENT, PUBLISH_INTENT. No callable/path/command.
Effects describe simulation only. Missing commit_confirmed prevents committed
transition; commit uncertainty invalidates and closes gates. A B_PUBLISH model
transition changes SEALED to PUBLISHED only with current authority, fence and
confirmed fake commit, preserving sealed result/evidence fields.

Order is historical A/B/C/D, not global first-match across all rows. B consumes
terminals before cause reduction. evaluate_transition applies event causes then
C only to nonterminals. Invalidating causes dominate. Nonzero command exit is
not OPERATION_FAILURE by itself. Unsupported combinations fall through D20.
An observed irreversible failure cannot be removed by retry or later good facts.

Retry eligibility does not mutate state until commit_confirmed=True models the
single fake generation/intention transaction. Committed retry creates the exact
historical RetryResolution bound to g0 transport Cause, request hash and retry
event sequence. It changes g0->g1 only, preserves other causes and requires all
DR2 guards. At 120/180/450-second accumulated ceilings no positive extra work may
be admitted; expiry is exclusive (now_ns < expires_ns). Planned work plus the
100-second closure reserve must fit the remaining 450-second horizon. Uncertain
commit produces no successful retry, never a second chance to consume it.

## Owned inputs, graph and trust boundary

Bytes must be exact bytes. Mappings accepted by public functions must be exact
built-in dicts with exact str keys/bytes values, copied only after bounding counts
and byte totals; reject custom Mapping callbacks/subclasses. Freeze parsed trees.
The JSON pre-scan tracks escapes/quoted brackets and checks nesting before load.
Bound bytes, nesting, collections and graph counts before recursive work.
Count root + every supplied resolved piece + payload + output bytes against total,
including unused inputs (then reject unused inputs); do not exempt digest storage.

Edges are only the historical typed Ref fields and specified digest fields, not
arbitrary strings. Bind expected piece kind to each edge, detect cycles and reject
missing/dangling/wrong-type refs. Shared content reached through multiple edges
is not a cycle. Reject duplicate semantic output/audit entries even if digests
coincide. Resolve everything from supplied owned dictionaries; no store callbacks.

Audit payloads have no complete semantic wire codec in the approved sources.
S1 may verify bounded opaque bytes, digest, required audit kinds and reference
membership only. It MUST mark unauthenticated_audit=True and must NOT claim that
transcripts substantiate cleanup, continuity, observation freshness or real host
identity. Consumers needing those guarantees remain BLOCKED. Do not invent an
unratified audit envelope or accept client claims as authenticated observations.
This is a deliberately structural report, not VerifyReceiptPackage operational.

ConsistencyReport has package_sha256, package_kind, wire_provenance,
scope=SIMULATION, operational=False, unauthenticated_audit=True. No approved,
authorized or VerifiedHostEvidence member. Wire OPERATIONAL may be parsed as data
but never elevates the report or creates provenance. PolicyApproval/POL-13 may be
structurally parsed only; its principal/digest claims do not grant permission.
No production EvidencePolicy selection, retention, purge, registry or backend.

## Implementation boundaries

Recommended modules: puretypes.py owns limits/enums/frozen records; model.py owns
reduction/transitions/retry and in-memory fake event/journal ports; codecs.py owns
new shape decoding and structural package consistency. Names may be split into
small helper modules without behavioral change. Existing contracts.py stays
byte-identical. Implementers must agree shared record definitions before edits.

All fake observations and Context inputs are trusted test-harness statements
within the simulation only; their truth about any actual host is not established.
