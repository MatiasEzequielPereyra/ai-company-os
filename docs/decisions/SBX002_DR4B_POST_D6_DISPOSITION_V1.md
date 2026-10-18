# SBX-002 DR-4b post-D6 proposed disposition V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-18T21:10:43Z
Updated by: CODEX_ORCHESTRATOR_A
Task: SBX002_S0_CANONICAL_DOCUMENTARY_PUBLICATION_V1
Publication base: `5d5fbf67630c48b98378e7f869acd90deec07057`

DECISION_ID: DR-4b
PROPOSED_DISPOSITION: APPROVED_WITH_CONDITIONS
FORMAL_DISPOSITION: PENDING
COMPETENT_ACT_REFERENCE: UNKNOWN

## Exact subject

Evaluate the mapping in the immutable
[historical record](../engineering/sbx002-d6/NATIVE_SBX_002_CTO_SECURITY_DECISION_RECORD_V1.md),
SHA-256 `11de899585c2782f480c88243a2f0991731b09841f33183b97a4f7c4f4dd6949`,
read together with the separate
[D6 amendment](../engineering/sbx002-d6/SBX002_D6_ENMIENDA_DOCUMENTAL_V1.md),
SHA-256 `98f0902bf7f279fabc323188a0036baee9f892a536852d52faf3184a0bb31791`.
Do not rewrite either source.

The amendment makes exactly three identifier replacements:

| Context | Historical text | Successor interpretation |
| --- | --- | --- |
| Table B | commit condicional D6 | commit condicional DEP-D6 |
| Table D | D6 REQUESTED/PREFLIGHT | MAP-D6 REQUESTED/PREFLIGHT |
| Section 11 | D6 consumidor compuesto | DEP-D6 consumidor compuesto |

DEP-D6 is the composite consumer/fenced-commit dependency. MAP-D6 is a row in
the state mapping. No predicates, terminal states, precedence, budgets or
lifecycle transitions change through these substitutions.

## Proposal and mandatory conditions

The identifier defect can be considered addressed for documentary review by
these exact bytes. Preserve all remaining conditions of the delegated decision:

- Historical terminal records remain immutable.
- Preserve invalidation and terminal precedence and residual rejection.
- Require final cleanup; absence of a guest result differs from uncertainty.
- COMPLETED, confirmed cleanup and ACCEPTED do not imply functional approval.
- Never fabricate a V1 guest receipt or accept V1 alone as sufficient evidence.
- Keep exhaustive and mutually exclusive mapping verification unproved until
  separately authorized deterministic model tests establish it.

This is the proposed disposition authorized for publication, not a new approval
attributed to CTO, Security, B or the human. A competent explicit successor act
must identify this document's exact revision/hash and conditions before
FORMAL_DISPOSITION may become approved. Publication, CI and the earlier D6 merge
cannot substitute for that act.

## Evidence and outstanding risks

A verified source hashes and the three unique, reversible replacements. B's
earlier documentary acceptance was reported in the central decisions; that
acceptance did not ratify the complete mapping. Operational atomicity, persistence,
timing, cleanup and isolation remain unproved. No tests or simulations are
executed by this document.

Implementation and operational authorization remain FALSE. Native Sandbox P0
remains OPEN. See the [S0 baseline](../architecture/native-sandbox/SBX002_DECISION_POLICY_BASELINE_V1.md)
and [policy/S1 gate](../engineering/sbx002/SBX002_MATERIAL_POLICY_AND_S1_GATE_V1.md).
