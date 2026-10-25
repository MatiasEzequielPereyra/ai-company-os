# S1 P1-005 generation chronology corrective handoff

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-25T01:22:38Z
Updated by: Engineering Orchestrator A
Task: SBX002_S1_P1_005_GENERATION_CHRONOLOGY_FIX_V1
Base: 12439870d44ead5b538c2ecd33f776ebc15efe12
Predecessor: 2b50f44ada1ccf9fd5d0a5b5b6ab36127cd8d309
PR: 82, DRAFT
Receipt: PENDING

## Authorization and scope

The direct Human Project Owner instruction authorizes reproducing P1-005 on all
three public interfaces, correcting it if confirmed, regressions, complete tests,
Security review, and publishing the correction to existing draft PR82. It excludes
merge, V1 contract modifications, S2, broker, writable, providers, VMs, Run A and
real E2E. The stale shared company-state pointer is not execution authority and is
not replaced by this task-specific successor.

## Canonical basis and finding

[Historical decision record](../../sbx002-d6/NATIVE_SBX_002_CTO_SECURITY_DECISION_RECORD_V1.md)
section 5 (DR-2), especially the retry transaction and cause/generation precision,
requires a confirmed unique commit that consumes the retry and changes generation
before g1 effects. Section 7 requires ordered journal observations and the unique
generation transaction. [S1 API](../../sbx002/S1_API_CONTRACT_V1.md) retry paragraphs
bind RetryResolution to that transition and change g0 to g1 only after confirmation.
The design ratification and its conditions remain those already published in
[the ratification record](../../../decisions/SBX002_DR4B_HUMAN_RATIFICATION_RECORD_V1.md).

The predecessor checked retry commit after the resolved g0 cause, but never checked
other g1 causes against that commit. Public CoreState construction, live-state
decode_piece and host-evidence decode_piece all accepted g0 transport cause at 1,
g1 OPERATION_FAILED at 3, retry commit at 6, and FAILED with otherwise valid fields.
That encodes a g1 observation before g1 exists. CAS version is independent metadata;
it is not the generation boundary or a journal sequence ceiling.

## Minimal correction and compatibility

One shared validator requires every g1 cause journal sequence to be strictly greater
than retry_commit_sequence. CoreState and both composite wire kinds invoke it after
existing retry shape/binding checks. Before and equal sequence reject through
ContractError (S1_GENERATION_CHRONOLOGY). No public API signature, wire shape, cause
code, limits or production defaults change. No extra upper bound for g0 causes is
introduced. No comparison to live-state.version is made. Existing host seal bounds
remain intact. contracts.py, request.v1, receipt.v1 and V1 tests are unchanged.

## Reproduction and regressions

New tests/test_sandbox_s1_p1_005_chronology.py has 223 deterministic cases: three
public interfaces, before/equal/after boundary, all 34 causes, resolved retry
completion, and CAS versions 1/5/6/100 independent of journal commit 6 and cause 7.
Valid-fixture predecessor run: 114 FAIL / 109 PASS. Focused final regressions:
1030 PASS on Python 3.11 and 3.12, including all unchanged V1 and prior S1 tests.

Local evidence directory: Z:/repos/ai-company-os/temp-tests/
- s1-p1-005-before-valid-fixtures.log
- s1-p1-005-focused-after.log
- s1-p1-005-focused-after-python312.log

An earlier test draft included invalid CAS version 0 and produced 115 FAIL/109 PASS.
That separate draft log is preserved, but is not the valid-fixture baseline. The
invalid fixture was corrected before the final baseline; no existing guard or test
was weakened. The valid baseline has precisely the 114 chronology negatives failing.

## Verification and limits

Independent Security executed 411 tests on each Python runtime and found no
remaining scoped P0/P1. Full Python 3.12 completed with 1317 PASS and one existing
symlink-permission skip. The first full Python 3.11 attempt stopped advancing
without a completion result; its log is preserved as s1-p1-005-full-python-3.11.log
and is not counted as PASS. The separate diagnostic full Python 3.11 execution
completed with 1317 PASS and the same existing skip (178.27s); Python 3.12 took
175.33s. After both completed, only the identity-verified task-owned incomplete
pytest process (PID19912, exact executable/arguments/parent checked, no children)
was terminated. No test or unrelated product code is altered to conceal that
incomplete attempt. Diagnostic logs are s1-p1-005-full-python-3.11-diagnostic.log
and s1-p1-005-full-python-3.12.log in the local evidence directory above.

Full Python and published-HEAD CI results are supplied by the final delivery after
completion, never inferred from a pending run. Independent technical Security review
is recorded in [its successor report](../../sbx002/S1_P1_005_SECURITY_REVIEW_V1.md).
This is structural chronological consistency, not authenticated observation provenance
or proof of real atomicity, persistence, fencing, isolation or cleanup. P0 remains OPEN.

SKILLS_SELECTED: bug, code-review
SKILLS_APPLIED: bug, code-review
SKILL_SOURCES: C:/Users/LA NAVE/.agents/skills/bug/SKILL.md;
C:/Users/LA NAVE/.agents/skills/code-review/SKILL.md
SKILL_SELECTION_REASON: reproduce the alleged chronology defect and independently review the bounded repair.

NEXT_REVIEW: SBX002_S1_P1_005_REAUDIT_V1
MERGE_AUTHORIZED: FALSE
S2_AUTHORIZED: FALSE
WRITABLE_ENABLED: FALSE
RUN_EXECUTION_AUTHORIZED: FALSE
REAL_E2E_AUTHORIZED: FALSE
NATIVE_SANDBOX_P0: OPEN
