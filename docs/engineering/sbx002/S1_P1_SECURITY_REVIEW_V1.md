# S1 P1 corrective Security and code review V1

Project: AI_COMPANY_OS
Revision: 1
Task: SBX002_S1_P1_CORRECTIVE_PATCH_V1
Updated by: delegated independent Security/code-review agent /root/s1_p1_final_review
Reviewed predecessor: b4a0457abb9bc91dceeb940686f245a217e12ff1
Base: 12439870d44ead5b538c2ecd33f776ebc15efe12
Decision: APPROVED_WITH_CONDITIONS_FOR_INDEPENDENT_DRAFT_REAUDIT

## Scope and independence

Read AGENTS.md, company-state protocol and derived pointer, bug and code-review
skills, exact S1 API contract, prior Security implementation review, historical
DR4b sections 5, 9 and 10, and the complete corrective source/test diff. The old
derived pointer is not execution authority; this review is under the explicit
human corrective authorization. This is technical advice, not an institutional
signature, merge approval, operational authorization or P0 certification.

Reviewer modified no functional source and no test. Only this successor review
is added; the original Security review remains historical rather than rewritten.

## Findings and disposition

- P1-001 CLOSED: evaluate_transition now passes the post-observation state to
  evaluate_retry. A current RETRY cause therefore survives reduction, sequence
  and tick updates, and eligibility. Tests iterate every closed cause code;
  AUTHORIZATION_CHANGED latches INVALIDATED and cannot advance g0 to g1.
  No cause is discarded by reverting to the pre-event state.
- P1-002 CLOSED: codec limit boundaries call the class-bound
  S1SyntheticLimits.__post_init__(limits), not an instance-supplied method.
  Exact class checking remains. All six required fields and existing synthetic
  ceilings remain unchanged. Combined field/method tampering tests cover both
  decode and package entry points; model reduction reconstructs expected records.
- P1-003 CLOSED: live-state and host-evidence now share cause dominance validation
  with CoreState, in addition to latch and dimension checks. Cause generation,
  event sequence and retry commit bind to host seal_sequence; live-state.version
  is independent CAS metadata and is not used as a journal-sequence ceiling.
  Invalidating causes cannot claim COMPLETED, FAILED or PENDING. Deadline/cancel
  precedence and ordinary active failure are checked. Only the documented g0
  pending transport and exact resolved g0 transport fact are exceptions; another
  transport cause and other causes remain active. Callers materialize the cause
  triples as tuples, so repeated iteration cannot lose the cause list.
- P1-004 CLOSED: evaluate_retry first establishes eligibility with all non-commit
  guards, including phase, generation, resources, cause cardinality, authority,
  request, timing and pre-code facts. Ineligible or terminal input returns its
  state unchanged even when commit_uncertain is true. Uncertainty for a genuinely
  eligible transaction still appends PERSISTENCE_FAILED, latches invalidation and
  rejects further retry. This is not a relaxation of the actual commit guard.
- Long JSON integer CLOSED: the new parse_int callback rejects more than 20
  decimal digits before int(), raising ContractError regardless of interpreter
  process-wide integer-string settings. Existing typed U64 checks still reject
  out-of-range 20-digit values. No V1 parser was changed.

No remaining confirmed P0/P1 was identified in this scoped corrective review.

## Mapping and compatibility

The literal DR4b order remains A validation, B immutable terminal dispatch, C
cause reduction, D scoped actions and residual rejection. Retry keeps one exact
historically resolved cause and cannot resolve invalidation. A terminal record
is rejected if contradictory rather than repaired by a nonterminal rule.

No new wire fields, cause codes, synthetic ceilings or operational defaults were
introduced. Existing contracts.py and tests/test_native_sandbox_contracts.py are
byte-identical to the reviewed predecessor. Sharing dominance adds intended
rejections for inconsistent live-state records; accepted short valid cases and
retry-resolution positive controls remain present.

## Executed and inspected evidence

Reviewer executed, on Python 3.12 and Python 3.11 respectively:

`python -m pytest tests/test_sandbox_s1_p1_codecs.py tests/test_sandbox_s1_p1_model.py tests/test_sandbox_s1_p1_security.py tests/test_sandbox_s1_security.py tests/test_sandbox_s1_boundaries.py -q`

Result: **335 PASS on each runtime**, no skipped or weakened assertion.
The test selection includes all three corrective modules and previous independent
Security/boundary regressions. The parent coordinates full Python, V1, package and
CI gates; those results are not claimed as reviewer executions here.

Read the retained predecessor reproduction logs (not rerun by this reviewer):

- `Z:/repos/ai-company-os/temp-tests/s1-p1-model-before.log`: 40 failed, 1 passed.
- `Z:/repos/ai-company-os/temp-tests/s1-p1-codecs-before.log`: 73 failed, 2 passed.

These are recorded failures, not concealed or represented as passing evidence.
Final source hashes below identify working-file bytes after formatting:

- model.py: 0CCCE03624C7448DCD76B0F1545CF977717A34FE59AEB2A84A5F4527723CD4D5
- codecs.py: FF8F12FE2100E4EE63DC60007FAD08259D91A47491E13ACE66A229D768BB9D96
- puretypes.py: D24141886263F002F397B43C46F032BEFBFB160768E4BB1EB6EF4138F1F91806
- contracts.py: 0BBDEFE2D3EBAF1B4E9E7B94A1DB07CE86907BBC68880CA30D5281A3A231CB4A
- tests/test_native_sandbox_contracts.py: 0F74F21A0AC4216EEB18175770DF5870C6205641D02CA04BC36A3693988818A9

Git blob hashes and checkout hashes can differ under CRLF conversion; these are
explicitly checkout-byte SHA-256 hashes, not a claim about canonical Git bytes.

## Reviewer correction: CAS version is not journal sequence

During final counter-check, the parent identified an unsupported inference in
both the initial patch and this review: bounding live Cause.event_sequence and
RetryResolution.retry_commit_sequence by LiveState.version. Historical section
4.2 defines LiveState.version; section 5 and section 7 use expected epoch/version
for CAS. Only section 7 explicitly orders seal_sequence after the journal prefix.
There is no approved equality or upper-bound relation between CAS version and
event sequence. The reviewer withdraws the earlier live-version binding claim.

The final patch retains sequence bounds for host-evidence only and preserves
live-state cause generation, dominance, latch and exact retry-resolution checks.
Two unsupported negative test oracles became positive controls for independent
CAS/event counters, while retry commit ordering after its cause remains negative
coverage. This corrects a contract overreach, not a change made to obtain PASS:
the prior overconstrained implementation already passed the test selection.

After this correction and final formatting, the reviewer reran the exact subset
on Python 3.11 and Python 3.12: **335 PASS on each**. The source hashes in this
review identify that corrected final snapshot.
## Retained limits and conditions

Frozen Python objects and boundary revalidation do not establish security against
arbitrary code running inside the same Python process or class/global monkeypatch.
No such security boundary is claimed. Structural validation does not authenticate
PolicyApproval, monitor transcripts, identity, cleanup or authority. Reports remain
SIMULATION, operational=False and unauthenticated_audit=True. Fake persistence,
commit, journal and context facts do not prove real OS behavior or atomicity.

Full gates and independent B re-audit of the published exact HEAD remain required.
No provider, VM, broker, IPC, actual sandbox command or Run A was executed by this
reviewer. S2, merge, writable and real E2E remain unauthorized. P0 remains OPEN.

FUNCTIONAL_CODE_MODIFIED_BY_REVIEWER: FALSE
REPOSITORY_MUTATIONS: this review document only
SKILLS_SELECTED: bug, code-review
SKILLS_APPLIED: bug, code-review
SKILL_SOURCES: C:/Users/LA NAVE/.agents/skills/bug/SKILL.md; C:/Users/LA NAVE/.agents/skills/code-review/SKILL.md
SKILL_SELECTION_REASON: independent corrective root-cause and security boundary review
