# SBX-002 DR-4b human ratification record V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-21T02:27:43Z
Updated by: Codex delegated documentary owner / engineering-manager
Task: SBX002_DR4B_RATIFICATION_RECORD_PUBLICATION_V1
Owner: engineering-manager (documentary preparation); Codex Orchestrator (integration)
Verified publication base: `5bf7a58c3789626c914d53f56497117e4be7d3a8`

DECISION_ID: SBX002-DR4B-POST-D6-V1
DECISION: APPROVED_WITH_CONDITIONS
DECISION_SCOPE: DESIGN_ONLY
DR4B_FORMAL_DISPOSITION: RATIFIED_BY_HUMAN_PROJECT_OWNER
AUTHORITY: HUMAN_PROJECT_OWNER
EXTERNAL_IDENTITY_AUTHENTICATION: NOT_PERFORMED

## Human act and authorization receipt

This successor records the Human Project Owner's explicit ratification of DR-4b
as APPROVED_WITH_CONDITIONS, DESIGN_ONLY, for the exact subject below. It does
not attribute a new institutional signature to CTO, Security or an external
orchestrator. The current direct user instruction confirms that ratification
and authorizes this documentary task end to end without repeated questions:
isolated worktree, successor record, validation, commit, push, draft PR,
independent exact-diff and CI review, and protected squash merge followed by
post-merge CI validation if no blockers or divergences remain.

Current direct instruction received on 2026-10-20, America/Buenos_Aires:

> El usuario ratificó explícitamente DR-4b APPROVED_WITH_CONDITIONS DESIGN_ONLY y ahora autoriza hacer todo el trabajo documental sin repetirle preguntas.

The same instruction expressly excludes code changes and S1, broker, writable
and E2E enablement. This authorization supersedes earlier no-merge restrictions
only for this documentary flow; it grants no product implementation permission.

Antecedent conversation:
`6ac6b5f4-239c-83e8-a297-2b28d9399ac0` (SKILLS ORCHESTRATOR B ////).
Recovered user-message references are:

- `fcda135d-5ca7-49af-b6ae-e14a78417633`: "si confirmo".
- `704562e3-c2e4-4191-accd-e13474384d3b`: supplied A acknowledgement,
  output `ORCHESTRATOR_A_DR4B_HUMAN_RATIFICATION_ACK_V1`, identifying the
  decision, exact hashes, design-only scope and preservation of all eight
  conditions. This is a reported acknowledgement, not independently
  authenticated external identity evidence.
- `1cb81599-0df0-4953-b11a-49f3a906eb18`: subsequent broad documentary
  authorization. The current direct instruction supplies its precise scope.

The recovered antecedent preview is bounded; no absent or truncated text is
claimed as verified. The current direct human instruction is the authority for
publication and integration. No further human decision on DR-4b is requested.

## Exact ratified subject and source integrity

Hashes below identify exact Git blob bytes at the verified publication base,
not checkout bytes subject to CRLF conversion. All three source documents are
revision 1 and remain byte-for-byte intact.

| Source | SHA-256 |
| --- | --- |
| [Historical record](../engineering/sbx002-d6/NATIVE_SBX_002_CTO_SECURITY_DECISION_RECORD_V1.md), 61,485 bytes | `11de899585c2782f480c88243a2f0991731b09841f33183b97a4f7c4f4dd6949` |
| [D6 amendment](../engineering/sbx002-d6/SBX002_D6_ENMIENDA_DOCUMENTAL_V1.md), 2,631 bytes | `98f0902bf7f279fabc323188a0036baee9f892a536852d52faf3184a0bb31791` |
| [Post-D6 proposed disposition](SBX002_DR4B_POST_D6_DISPOSITION_V1.md), 3,066 bytes | `b1ab21abe72d4cb526642efeef8dd192bf4b49dc9f166652e387dc0d3280bd2e` |

The ratified interpretation is the historical record read with the D6 amendment
and the proposed disposition's complete conditions. Replacing each of the
following unique byte sequences exactly once in the historical Git blob gives
61,497 UTF-8 bytes with SHA-256
`bc6e2fad099ed6757ecf2105857049d2aa9910ca08527460e963093fc0144755`:

| Location | Historical sequence | Composed sequence |
| --- | --- | --- |
| Section 10, table B | `commit condicional D6` | `commit condicional DEP-D6` |
| Section 10, table D | `D6 REQUESTED/PREFLIGHT` | `MAP-D6 REQUESTED/PREFLIGHT` |
| Section 11 | `D6 consumidor compuesto` | `DEP-D6 consumidor compuesto` |

This composition changes only those identifiers, preserves all other bytes and
does not alter predicates, terminal states, precedence, budgets or lifecycle
transitions. It is an interpretation fingerprint, not a replacement historical
file or evidence of operational correctness.

## Eight preserved conditions

The following eight-item enumeration separates conjuncts of the proposal's
six bullets for traceability; it adds no requirement and waives none. The full
source conditions and existing C1-C5 and P1-01/02/03 requirements remain binding.

1. Historical terminal records remain immutable, including after revocation.
2. Preserve invalidation and terminal precedence, including dispatch B before
   C/D and `INVALIDATED > TIMED_OUT > CANCELLED > FAILED > COMPLETED > PENDING`.
3. Preserve residual rejection D20; an unmatched or inadmissible case cannot
   obtain optimistic acceptance.
4. Confirmed final cleanup remains mandatory for any admissible sealed package;
   no acceptance is permitted without it.
5. Absence of a guest result remains distinct from uncertainty; uncertainty
   cannot be converted into admissible evidence or success.
6. COMPLETED, confirmed cleanup and ACCEPTED do not imply functional approval
   of tests, tasks or the product.
7. Never fabricate a V1 guest receipt, and never accept V1 alone as sufficient
   evidence. Preserve the composite consumer and guest/host evidence boundary.
8. Exhaustiveness and mutual exclusion of the mapping remain UNPROVED until
   separately authorized deterministic model tests establish them.

## Effect, retained dependencies and precedence

This record succeeds only the pending human disposition of DR-4b for the exact
subject above. Earlier CHANGES_REQUIRED, NOT_RATIFIED and PENDING statements
remain accurate historical snapshots in their original documents; they are not
silently edited or treated as current refusals of this later human act.

DR-1, DR-2, DR-3 and DR-4a retain their existing design scopes and all conditions
in the [S0 baseline](../architecture/native-sandbox/SBX002_DECISION_POLICY_BASELINE_V1.md).
The [material policy and S1 gate](../engineering/sbx002/SBX002_MATERIAL_POLICY_AND_S1_GATE_V1.md)
continues to govern every other dependency. The human-ratification dependency
is resolved; separate S1 scope, owners, acceptance criteria, independent review
and material-policy classification remain required. No blanket policy waiver
or new technical or operational approval follows from this act.

Material policies, named organizational owners and legal-hold authority remain
PENDING/UNKNOWN. Proposed 128 MiB limits or 30-day retention are not approved.
Atomicity, persistence, fencing, timing, isolation and cleanup guarantees remain
unproved. Certified profiles: NONE; E1-E5 certification: PENDING. CI and schema
validation cannot certify those guarantees. Native Sandbox P0 remains OPEN.

S1_IMPLEMENTATION_AUTHORIZED: FALSE
BROKER_IMPLEMENTATION_AUTHORIZED: FALSE
WRITABLE_ENABLED: FALSE
RUN_EXECUTION_AUTHORIZED: FALSE
REAL_E2E_AUTHORIZED: FALSE
PROVIDERS_OR_VMS_AUTHORIZED: FALSE
NATIVE_SANDBOX_P0: OPEN

## Publication acceptance and verification boundary

Objective: publish this scoped human-ratification successor without modifying
code, historical sources, unrelated tickets or shared company-state indexes.
The existing S0 scope exception for shared indexes is preserved.

Acceptance criteria: exact source and composition hashes match; all eight
conditions and exclusions remain explicit; relative source links resolve; the
diff contains this documentary successor only; an independent reviewer checks
the exact commit/diff and official CI before any protected squash merge; no
bypass or force is used; the merged tree and post-merge CI are verified.

Preparation verification: the three source hashes, unique replacement counts
and composed hash above were independently recalculated from Git blobs and
matched. These are documentary integrity checks only. Deterministic model
tests, sandbox execution and real E2E: NOT_RUN. PR, independent review, merge
and official CI results are external publication evidence, not pre-asserted by
this immutable preparation record. Publication does not itself prove those
later gates passed.

SKILLS_SELECTED: []
SKILLS_APPLIED: []
SKILL_SOURCES: []
SKILL_SELECTION_REASON: Documentary transcription and provenance preparation;
no implementation or new architecture selection. Integration/review skills and
their results are recorded by the responsible orchestrator/reviewer separately.
