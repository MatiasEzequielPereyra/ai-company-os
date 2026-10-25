# S1 P1 corrective patch V1

Project: AI_COMPANY_OS
Revision: 1
Task: SBX002_S1_P1_CORRECTIVE_PATCH_V1
Updated by: Engineering Orchestrator A
PR: 82 (DRAFT)
Base: 12439870d44ead5b538c2ecd33f776ebc15efe12
Audited previous HEAD: b4a0457abb9bc91dceeb940686f245a217e12ff1
Status: CORRECTIVE_REVIEW_PENDING

## Authority and exact scope

The Human Project Owner relays B's four P1 findings and authorizes their repair,
negative tests, full Python verification, independent Security review and update
of existing draft PR82. No merge, S2, broker, providers, VM, writable, Run A or
real E2E. This successor preserves earlier implementation evidence rather than
rewriting the historical handoff or old review.

## Defects and corrections

1. P1-001: evaluate_transition observed the RETRY event into s, but evaluated the
   original pre-event state. It now evaluates s, retaining every admitted cause.
   All 34 cause codes are exercised; AUTHORIZATION_CHANGED preserves invalidation
   and cannot enable g0 to g1.
2. P1-002: codecs dispatched limits.__post_init__ on an untrusted instance.
   Validation now calls the trusted class implementation. All six fields and
   existing synthetic ceilings remain mandatory; shadowed instance methods are
   never invoked. Tests combine method replacement with bad values in each field.
3. P1-003: wire live-state had dimension/latch checks without complete cause
   dominance. Model and wire validation now share the existing cause/result rule,
   retaining only the pending g0 and exact resolved transport-cause exceptions.
   Other causes, generations and invalidations cannot be resolved by that retry.
4. P1-004: evaluate_retry added PERSISTENCE_FAILED before checking eligibility.
   It now checks eligibility first. Terminal and ineligible states remain intact;
   an eligible retry with uncertain commit still invalidates and cannot retry.

The JSON loader additionally bounds integer lexical length before int(), returning
ContractError for excessive integer literals without altering process-wide Python
settings. The bound is compatible with the existing uint64 wire domains.

## Compatibility correction discovered during review

The patch briefly introduced cause/retry sequence ceilings using LiveState.version.
Independent source review found no such relationship: historical section 4.2
defines version, sections 5/7 use CAS versions, and section 7 explicitly orders
seal_sequence relative to journal events only. Those unsupported live-version
ceilings were withdrawn before publication. Corresponding newly written test
oracles were corrected to assert that CAS version and journal sequence remain
independent; valid controls and the real retry-commit-after-cause negative guard
remain tested. This corrects a test assumption, not an approved guard or a failing
product requirement. Host seal-sequence bounds remain unchanged.

The shared validator is passed stable tuples, avoiding an intermediate consumed
generator defect which independent regressions also detected. No existing test,
assertion, skip or xfail was removed to achieve PASS.

## Evidence and verification

Component reproductions before their respective corrections are retained locally:
Z:/repos/ai-company-os/temp-tests/s1-p1-model-before.log (40 FAIL / 1 PASS), and
s1-p1-codecs-before.log (73 FAIL / 2 PASS). These are component reproduction
records, not a claim that all later tests ran on an isolated pristine base.

Final focused tests: 807 PASS, including 324 unchanged SBX-001 regressions,
235 prior S1 tests and 248 corrective/adversarial regressions. Independent
Security subset: 335 PASS on each Python 3.11 and 3.12. Final full suites each
passed 1094 tests with one existing OS symlink-permission skip
(test_error_intelligence_safety.py:206). Their logs are
s1-p1-verified-python-3.11.log and s1-p1-verified-python-3.12.log under the same
local temp-tests directory. Published-commit CI results are reported by the final
delivery after completion; no pending check is counted as PASS.
Two preliminary full runs before the compatibility correction stopped progressing
near their end. They were superseded, their incomplete logs copied to
s1-p1-superseded-incomplete-python-3.11.log and the corresponding 3.12 file, and
only their verified task-owned test process trees terminated after both final
runs passed. Those incomplete runs are not reported as PASS.

See [Security review](../../sbx002/S1_P1_SECURITY_REVIEW_V1.md) for exact reviewed
file hashes, corrected reviewer assumptions, tests and limitations. Current-file
review hashes and canonical Git blob hashes can differ by CRLF normalization.

## Contract and remaining limits

No API signature, wire shape, six-field synthetic configuration or ceiling was
changed. Invalid combinations now reject consistently through ContractError;
live CAS versions are not redefined as journal sequence numbers. contracts.py,
request.v1, receipt.v1 and existing V1 tests remain byte-identical in Git.
The patch does not supply operational authority, persistence, fencing, cleanup
or isolation. Reports remain simulation-only; P0 certification stays OPEN.

SKILLS_SELECTED: bug, code-review, feature
SKILLS_APPLIED: bug, code-review, feature
SKILL_SOURCES: .agents/skills/bug/SKILL.md; .agents/skills/code-review/SKILL.md;
.agents/skills/feature/SKILL.md
SKILL_SELECTION_REASON: reproduce and fix bounded defects while preserving S1.

NEXT_REVIEW: SBX002_S1_P1_CORRECTIVE_REAUDIT_V1
MERGE_AUTHORIZED: FALSE
S2_AUTHORIZED: FALSE
BROKER_IMPLEMENTATION_AUTHORIZED: FALSE
WRITABLE_ENABLED: FALSE
RUN_EXECUTION_AUTHORIZED: FALSE
REAL_E2E_AUTHORIZED: FALSE
NATIVE_SANDBOX_P0: OPEN
