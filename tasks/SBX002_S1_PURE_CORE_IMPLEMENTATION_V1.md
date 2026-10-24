# SBX-002 S1 pure core implementation V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-22T00:25:18Z
Updated by: /root/s1_em_registration (engineering_manager)
Task ID: SBX002_S1_PURE_CORE_IMPLEMENTATION_V1
Owner: backend
Assigned by: engineering-manager
Status: REVIEW
Workflow phase: CODE_REVIEW
Functional implementation gate: APPROVED_FOR_PURE_CORE_ONLY
Base SHA: 12439870d44ead5b538c2ecd33f776ebc15efe12
Branch: feature/sbx002-s1-pure-core-v1
Worktree: Z:/repos/ai-company-os/worktrees/sbx002-s1-pure-core-v1

## Objective and authorization receipt

Implement the S1 pure Python core, validate it and publish one verified draft PR
for independent Orchestrator B audit. The Human Project Owner's current direct
instruction, headed "AI COMPANY OS — AUTORIZACIÓN DE IMPLEMENTACIÓN S1", grants
IMPLEMENTATION_AUTHORIZED: TRUE for this exact task. Its scope includes:

> Ejecutar el ciclo completo de implementación del núcleo puro S1, desde las
> revisiones técnicas previas hasta publicar un PR draft verificado.
> No solicitar nuevas autorizaciones humanas para las subtareas comprendidas
> en este alcance.

The instruction authorizes ticket registration and backend assignment, CTO API
validation, Security review, objection resolution before functional code, scoped
implementation/tests, commit, push without force, a draft PR and verification of
official checks. This receipt records scope, not external identity authentication.
The authorization is the direct user instruction in the parent session; a
message-level durable source identifier is UNKNOWN in this registration.

No new decision or permission is inferred from task status. ACTIVE here permits
only preparation and precode review while the gate below is unresolved.
Backend must not modify functional code before both CTO and Security approve
the exact final contract. EM does not substitute for either reviewer.

## Assignment and reviews

- Responsible backend owner: backend specialist assigned by EM for this task.
- Coordination: Engineering Orchestrator A (/root).
- Architecture contract owner: CTO; review artifact S1_CTO_REVIEW_V1.md.
- Precode trust-boundary reviewer: Security; artifact S1_SECURITY_PRECODE_REVIEW_V1.md.
- Required downstream: independent implementation review, QA evidence, Security
  evidence and Orchestrator B exact-HEAD contraaudit before any merge decision.
- Final target is REVIEW, not DONE. No merge is authorized.

## Scoped deliverables and acceptance criteria

1. Closed immutable types and historical cause registry; strict enum/type errors,
   no claims of authenticated authority from Python objects or JSON.
2. Versioned composite codecs with mandatory S1SyntheticLimits, no productive
   defaults, bounded parsing and closed shapes. Reject duplicates, malformed
   UTF-8/JSON, BOM, nonfinite, bool-as-int and unapproved unknown fields.
3. Acyclic reference graph and cross-validation of digest, exact bytes, sizes,
   identity, epoch, generation, sequences and complete referenced pieces.
4. Structural consistency report distinct from operational authority; reject
   isolated V1 as sufficient evidence, fabricated guest data, absent/uncertain
   cleanup and simulation attempting operational elevation.
5. DR-4b deterministic A/B/C/D mapping, independent lifecycle/result/resources,
   immutable terminal evidence, precedence and residual D20 rejection.
6. Irreversible invalidation with all causes retained; pure ordered event reducer
   and deterministic fake failures/interleavings without clocks or real effects.
7. Exactly one g0-to-g1 retry before any code is sent, immutable request and
   confirmed g0 cleanup; no restart/uncertain commit/third attempt; accumulated
   capture/preparation/closing budgets and boundary behavior preserved.
8. Fake ports and deterministic tests prove only model behavior. Reuse SBX-001
   without changing request.v1, receipt.v1, their limits or semantics. Keep full
   SBX-001 regressions green and preserve source bytes of its validator/tests.

The exact API contract lives in
[S1_API_CONTRACT_V1.md](../docs/engineering/sbx002/S1_API_CONTRACT_V1.md).
Its current PRECODE_REVIEW state is not approval. CTO/Security must review exact
arguments, results, errors, representation and synthetic ceilings before code.

## Dependencies and policy classification

Resolved source baseline: SBX-001 integrated; S0 integrated by PR80; human DR-4b
design ratification recorded by PR81. Read together with
[S0](../docs/architecture/native-sandbox/SBX002_DECISION_POLICY_BASELINE_V1.md),
[human record](../docs/decisions/SBX002_DR4B_HUMAN_RATIFICATION_RECORD_V1.md),
the [historical record](../docs/engineering/sbx002-d6/NATIVE_SBX_002_CTO_SECURITY_DECISION_RECORD_V1.md)
and [D6 amendment](../docs/engineering/sbx002-d6/SBX002_D6_ENMIENDA_DOCUMENTAL_V1.md).
DR-1/2/3/4a scopes and conditions persist; do not request their ratification again.

Pending precode dependencies: CTO approval of exact contract and Security approval
of parser limits/trust boundary. These are required human-authorized technical
subtasks, not new requests for human implementation authorization.

POL-13 corresponds to PolicyApproval as clarified in B's accepted ticket handoff.
Structural validity never authenticates its approver or approves policy. Limits
are explicit bounded synthetic parameters; numerical production limits, quotas,
reserves, retention, privacy/hold, purging, maintenance and named organizational
authorities remain pending for operational tasks. No new production profile or
retention/purge behavior belongs to S1. Missing approval required by a simulated
operation must close its simulated gate, not default to approved.

## Required verification and delivery

The task-specific verification specification is
[S1_TEST_PLAN_V1.md](../docs/engineering/sbx002/S1_TEST_PLAN_V1.md), prepared by
the coordinating workstream. Its existence/content must be verified before
implementation acceptance; a link is not evidence that checks ran.

- Negative JSON/types/versions/limits/hashes/identity and malformed references.
- Missing/duplicate/cyclic/unused pieces; bounded resolved input and depth.
- SIMULATION/OPERATIONAL separation, PolicyApproval and trust-boundary negatives.
- Missing/unproven cleanup; complete mapping, precedence and D20.
- Valid retry and every negative guard, time boundaries and cumulative budgets.
- Repeated/inverted/wrong-epoch events; fake journal, persistence and commit
  failures; invalidation racing Start, Seal and Publish with controlled schedules.
- Full SBX-001 regressions, focused S1 tests, Python suite and applicable official
  CI. Do not weaken tests to get PASS. Preserve genuine failures as failures.
- Before publication: independent review and no P0/P1 blocker; record exact
  files/diff, source hashes, test results, reviewer identity and contract hash.
- Draft PR only, with exact HEAD for B/QA/Security. No READY-for-merge claim.

Tests at registration: NOT_RUN. Code at registration: NOT_IMPLEMENTED.

## Exclusions and retained controls

No broker, Windows services/IPC, Hyper-V, VSS, filesystem backend, runner,
provider, real persistence, operational fencing, product policy, global install,
writable activation or Run A/B/E2E. Do not execute operational sandbox processes,
services, VMs or providers. Host test processes for deterministic verification
are within the explicit test authorization and are not sandbox operation.

MERGE_AUTHORIZED: FALSE
BROKER_IMPLEMENTATION_AUTHORIZED: FALSE
OPERATIONAL_WRITABLE_ENABLED: FALSE
REAL_E2E_AUTHORIZED: FALSE
PROVIDERS_OR_VMS_AUTHORIZED: FALSE
NATIVE_SANDBOX_P0: OPEN

## Transition log

| UTC | From | To | Actor/role | Reason and evidence |
| --- | --- | --- | --- | --- |
| 2026-10-22T00:25:18Z | NONE | BACKLOG | /root/s1_em_registration / engineering-manager | Register current human-authorized task, backend owner, scope and known gates. |
| 2026-10-22T00:25:18Z | BACKLOG | READY | /root/s1_em_registration / engineering-manager | Preconditions for preparation only satisfied: exact base, scope, assignment and human authorization; no claim that functional precode reviews are complete. |
| 2026-10-22T00:25:18Z | READY | ACTIVE | /root/s1_em_registration / engineering-manager | Authorized precode/documentary work starts; functional code remains explicitly gated until exact CTO/Security approvals. |

## State ownership exception

The shared .codex/state indexes describe other historical workstreams and are
not overwritten by this narrow task. This ticket and the task-local
[EM assignment](../docs/engineering/sbx002/S1_EM_ASSIGNMENT_V1.md) are the durable
assignment sources for S1. Later integration handoff may link them without
claiming ownership of unrelated current-handoff pointers.

## Functional gate successor acknowledgement

Engineering Orchestrator A resumes the existing EM backend assignment after both
precode reviews approved exact API contract SHA-256
`d041ac2f1425e0dd17e025b3bc5e2ba60d7d7cc7f9c621eb08f23db367b1176b`.
See S1_CTO_REVIEW_V1.md and S1_SECURITY_PRECODE_REVIEW_V1.md under
docs/engineering/sbx002. Their approvals supersede the historical pending
metadata inside the immutable reviewed contract, without changing its bytes.
ACTIVE continues for authorized functional implementation; no task completion
or operational authorization is implied. Test/review evidence is still pending.

## Submission successor

2026-10-24T13:49:45Z — ACTIVE -> REVIEW, Engineering Orchestrator A continuing EM coordination.
Backend implementation and independent Security/QA corrections completed.
Final local evidence: 559 focused PASS, Python 3.11 and 3.12 each 846 PASS
with one pre-existing symlink-permission skip, WinPS smoke 74/74, npm 3/3,
installed packed artifact E2E PASS. No P0/P1 remains in the local review.
See [implementation handoff](../docs/engineering/handoffs/ai-company-os/sbx002-s1-pure-core-v1.md).
External B audit and official published-commit CI are pending at submission.
This is not DONE and grants no merge, S2 or operational permission.
