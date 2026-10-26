# D1/D5 same-owner continuity correction V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-26T02:44:00Z
Updated by: Engineering Orchestrator A
Task: SBX002_D1_D5_TEST_CONTROL_LEDGER_V1
Base: dc313a01b487018ad27fdfd0591f6bb6dad37e38
Predecessor HEAD: 902d0c7767a2ef96183e83013c77df08fb0c4f3e
PR: 83, DRAFT
Receipt: PENDING_EXTERNAL_ORCHESTRATOR_B

## Authority and disposition

This successor corrects the [first draft handoff](sbx002-d1-d5-test-control-ledger-v1.md)
without editing that published historical snapshot or its source manifest. The
existing Human Project Owner authorization covers corrective implementation,
independent tests/reviews and update of the same draft PR. No new contract,
authority, operational permission, provider/VM execution or merge is implied.

After first-draft publication, a concrete additional Security check confirmed
a P1. Earlier implementation approvals and checks at predecessor HEAD are
historical, not final readiness evidence. EM coordination recorded corrective
REVIEW -> READY -> ACTIVE; renewed submission follows corrected verification.

## Reproduction and canonical basis

Create at now=0; VALID same-owner observation source sequence1, start10/finish12,
lease expiry62; same-owner ACQUIRE at20 cleared the public observation/expiry.
A later VALID source sequence1 at100 then established expiry150 without
invalidation, and recovery accepted that history. It erased source continuity
and used the unobserved-initial-state exception to bypass an already known lease.

The frozen API's final continuity paragraph forbids that erasure. Acquisition
must still clear the visible Snapshot fields as specified; a genuine successful
CHANGE_OWNER separately permits the new owner to establish its first observation.
No new invariant or public shape was invented to resolve this finding.

Independent predecessor evidence: four failing and 25 passing Security tests,
including six new cases. The authoritative local log is
C:/tmp/sbx002-security-continuity-before-corrected.log. A prior draft fixture
count typo was corrected before that capture and is not the authoritative baseline.

## Minimal correction

The existing bounded journal validation pass reconstructs private per-execution
last-observed continuity. The shared control projection uses it for source
sequence/time and lease/freshness guards during both current mutation and
historical replay. Only initial creation or an actual successful owner change
resets that context; same-owner acquisition does not erase it. No extra SQL
payload traversal, stored table, wire field, public API, retry logic or g1 is added.
Visible Snapshot clearing and CAS/journal-sequence independence remain intact.

Frozen API SHA256 remains
7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30.
Corrected checkout source test_ledger.py SHA256 is
ae7c9de161ed2f56cf0986a3717c95af07f9e7d95a94bfaa04ed75f2af229ed7.
test_ledger_types.py remains
1e71d6a2c789e6e8cfb563d3e79d0d726ca4d2a31db3dc06451de6c8bf4c0361.

## Renewed independent evidence

- All four ledger suites: 116 PASS on Python 3.11 and 3.12.
- Ledger plus complete existing SBX-001/S1 selection: 1146 PASS per runtime.
- Independent Security subset: 29 PASS per runtime, with four negative
  regressions and two valid controls for live refresh and genuine owner change.
- Security revision2 records withdrawal of the initial approval and renewed
  TEST_ONLY approval of corrected bytes. CTO delta review revision2 and QA
  successor revision3 independently approve the correction within their scopes.
- Existing V1/S1 implementation and tests remain unchanged.

Full corrected Python 3.11.9 completed 1433 PASS and one existing symlink skip
(127.38s); Python 3.12.10 completed the same results (123.19s). The corrected
installed tarball E2E also passed. Supporting local logs are
Z:/repos/ai-company-os/temp-tests/d1-d5-continuity-python-3.11.log and the 3.12
counterpart, plus d1-d5-continuity-package-e2e.log. Final published-HEAD CI must
conclude; predecessor CI never substitutes for corrected-HEAD checks.

The corrected local tarball SHA256 is
8df3d360f83f73350c509c3ec2a3381414aaa4665bb12f29333dc963aa39ed35.
Its evidence is separate from the predecessor tarball. The corrected source
manifest is D1_D5_CONTINUITY_SOURCE_MANIFEST_V1.json under docs/engineering/sbx002;
it records checkout and Git-normalized domains and excludes itself/this envelope.

## Retained boundaries

All outputs remain TEST_ONLY, operational=False, authority_authenticated=False,
execution_capability=NONE. Session continuity is a cooperative harness assertion;
this is not Windows authentication, operational lease monitoring, power-loss
durability, hostile whole-store rollback resistance, D6 fencing or certification
E1-E5. Native Sandbox P0 remains OPEN. Full test processes retain the isolated
PATH described in the predecessor handoff; no model inference or global provider
configuration change is performed.

SKILLS_SELECTED: bug, feature, code-review, architecture, release
SKILLS_APPLIED: bug, feature, code-review, architecture, release
SKILL_SOURCES: C:/Users/LA NAVE/.agents/skills/bug/SKILL.md;
C:/Users/LA NAVE/.agents/skills/feature/SKILL.md;
C:/Users/LA NAVE/.agents/skills/code-review/SKILL.md;
C:/Users/LA NAVE/.agents/skills/architecture/SKILL.md;
C:/Users/LA NAVE/.agents/skills/release/SKILL.md
SKILL_SELECTION_REASON: reproduce a concrete new finding, enforce existing
continuity requirements, independently verify the correction and publish safely.

NEXT_OWNER: EXTERNAL_ORCHESTRATOR_B
NEXT_ACTION: Independently audit corrected exact HEAD of PR83.
MERGE_AUTHORIZED: FALSE
OPERATIONAL_EXECUTION_AUTHORIZED: FALSE
NATIVE_SANDBOX_P0: OPEN
