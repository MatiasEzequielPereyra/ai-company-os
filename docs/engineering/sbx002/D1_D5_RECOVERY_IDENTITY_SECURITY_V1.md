# D1/D5 recovery identity Security successor V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-26T22:15:52Z
Updated by: /root/recovery_security, independent delegated Security reviewer
Task: SBX002_D1_D5_TEST_CONTROL_LEDGER_V1
Base reviewed: a5843d11670056516c2077b18652f7f91a49ef43
Decision: APPROVED_TEST_ONLY_FOR_SCOPED_RECOVERY_IDENTITY_CORRECTION

This successor records independent technical Security review of the PR83 recovery
identity correction under the existing human implementation/correction/test/draft
authorization. It does not replace published historical reviews, grant merge
permission, authenticate authority, or certify operational D1/D5.

## Exact reviewed sources

| Source | SHA-256 of actual local bytes |
| --- | --- |
| src/company_os/sandbox/test_ledger.py | 69f01974f67ac454e0a1b37c40d4611e2bf285aa3955b08777fb5838d8bdd44e |
| tests/test_sandbox_test_ledger_recovery_identity.py | 7351a46c9d6b534c7606dbfc3ae1f8ceddbbe4bcf8721dc86b6ba51b56b71ab3 |
| docs/engineering/sbx002/D1_D5_API_CONTRACT_V1.md | 7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30 |

The base plus these hashes identifies the reviewed functional delta before its
publication commit. Any later functional byte change needs corresponding review.
Read AGENTS, Security role, company-state protocol/index, project brief,
architecture/operations context, relevant S0/historical decisions, task receipt,
frozen contract, precode Security/CTO interpretation and recovery implementation.

## Finding and correction

High/P1 scoped evidence-integrity finding: the predecessor could combine the
historical snapshot of execution A with a FOUND uncertain operation committed
for execution B in one VERIFIED report. This creates misleading reconciliation
evidence, although the report remains TEST_ONLY and admission-closed.

The six-line guard now requires both the validated operation envelope's
execution_id and its historical result snapshot's execution_id to equal an
explicitly selected execution before constructing FOUND. Global bounded database
validation and irreversible latching of every recovered execution precede this
selection. The check adds no query, write, codec, schema, provider or public API.

OPERATION_CONFLICT is the correct existing rejection for an existing global
operation whose execution binding conflicts with the caller's explicit selection.
ABSENT would incorrectly deny that the operation exists. This is a request
selection conflict, rather than proof of corrupt storage: the first unsuccessful
recover remains RECOVERY_REQUIRED with _recovered=False and may be corrected
explicitly on the same handle. It returns no trusted partial report. Every
execution remains latched and stopped. A conflict after prior successful recovery
can retain READY/_recovered=True, but RECOVER mode still restricts new mutations
to explicit durable INVALIDATE; it cannot restore positive admission.

execution_id=None continues to validate the entire ledger, return snapshot=None,
and locate any exact historical uncertain operation globally. A missing operation
continues to return ABSENT with result=None; absence grants no replay permission.
A missing explicitly selected execution retains EXECUTION_NOT_FOUND. Unrelated
corruption still prevents selected or global success, and recovery corruption,
inconsistency and budget errors retain poison/close behavior. Existing historical
idempotency is historical evidence only.

## Executed independent evidence

- Independently inspected predecessor reproduction logs supplied by Backend:
  temp-tests/recovery-identity-before-3.11.log and corresponding 3.12 log under
  Z:/repos/ai-company-os: each records 2 FAIL / 9 PASS for the uncorrected source.
  These are observed Backend artifacts, not Security-executed predecessor runs.
- Security directly ran Python 3.11 focused recovery identity regressions against
  the exact corrected bytes: 11 PASS. Both mismatch directions, matched results,
  absent operations, global lookup, missing execution, fixed scope/error fields,
  all-execution latches/stops and byte-preserving recovery are covered.
- Security directly executed three additional independent disposable-database
  scenarios on Python 3.11: repeated successful recovery then mismatched selection
  preserves conservative admission and rejects new ACQUIRE_OWNER for both
  executions; selected/global absent operation remains absent; corruption in B
  rejects recovery selecting valid A with RECOVERY_INVALID and POISONED state.
  All three PASS. Corruption and recovery preserve the tampered bytes without
  repair. These were inline probes, not committed test additions.
- The first inline probe reached a Windows cleanup error because the test's
  external SQLite context manager did not close its tamper connection. Security
  corrected that probe cleanup, reran, and obtained the three PASS above. No
  implementation change resulted from that harness error.
- Security did not execute the full regression matrix or Python 3.12; independent
  QA/Backend evidence must supply those broader claims.

No remaining scoped Critical/High/Medium Security blocker was found in these
reviewed bytes. Approval is limited to this recovery correction and synthetic
tests. No providers, VM, privileged service, operational action, deployment or
merge was performed by this review. Native Sandbox P0 and operational limitations
remain open; synthetic reports still confer no execution capability.

FUNCTIONAL_CODE_MODIFIED: FALSE
REPOSITORY_MUTATIONS: this successor report only
SKILLS_SELECTED: code-review
SKILLS_APPLIED: code-review
SKILL_SOURCES: C:/Users/LA NAVE/.agents/skills/code-review/SKILL.md
SKILL_SELECTION_REASON: independent adversarial review of recovery identity and fail-closed semantics
