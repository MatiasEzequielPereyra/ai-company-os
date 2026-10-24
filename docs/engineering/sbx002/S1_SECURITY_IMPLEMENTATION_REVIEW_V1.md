# S1 Security implementation review V1

Project: AI_COMPANY_OS
Revision: 1
Task: SBX002_S1_PURE_CORE_IMPLEMENTATION_V1
Updated by: delegated Security/QA reviewer /root/s1_security_qa_resume
Base: 12439870d44ead5b538c2ecd33f776ebc15efe12
Decision: APPROVED_WITH_CONDITIONS_FOR_INDEPENDENT_DRAFT_REVIEW

## Scope and method

Read AGENTS.md, company-state protocol, S1_API_CONTRACT_V1.md, historical mapping
and trust boundaries, pre-code Security review, actual puretypes.py, codecs.py and
model.py. Applied code-review and bug skills. This is independent technical review
under the human S1 implementation authorization. It is not an institutional
signature, operational approval, merge permission or certification.

The review adds independent hostile tests in test_sandbox_s1_security.py. Shared
backend fixture constructors supply valid bytes; expected rejection cases and
simulation-only assertions are literal independent checks. Hash-valid host evidence
was re-encoded and all direct references updated for the semantic cause attacks;
those findings were not merely invalid digest failures.

## Findings discovered and closed

- P1: frozen S1SyntheticLimits could be mutated to bypass ceilings before decode.
  Three independently reproduced failures accepted piece_bytes above 8 MiB,
  depth 999 and negative piece count. Public boundaries now revalidate all limits.
- P1: model public entries trusted record construction and nested objects. They now
  revalidate exact types and nested records, including empty observation reduction.
  Tests reject forged truthy authority, negative clocks, malformed latch and cause.
- P1: unrelated Publish/Seal/Retry events could drive initial progression. Literal
  adversarial tests now require closed gates and unchanged initial lifecycle.
- P1: an otherwise consistent EXECUTION_EVIDENCE package accepted active
  AUTHORIZATION_CHANGED with COMPLETED/latch false, cause sequence beyond seal,
  and a future generation. All three initially failed independent rejection tests;
  cause/result and sequence/generation checks now reject them.
- Input ownership was tightened to validate then copy exact built-in dictionaries;
  subclasses with hostile items/values/iteration callbacks are rejected. Valid
  package roots are also used, so this test does not depend on malformed-root exit.

- P1: a preexisting invalidating cause could hide in CoreState behind COMPLETED/latch false. Constructor dominance checks and public boundary revalidation now reject it; the independent reproducer passes. All earlier P1 findings are closed on reviewed source bytes. Formatting is complete. No remaining confirmed P0/P1 was found in this scope.

- P1: impossible started/lifecycle combinations and COMPLETED without code started
  were accepted by live-state decoding. Eight independent literal negatives
  initially failed; shared state-dimension validation now rejects them.

## Executed evidence

Windows Python 3.11 and 3.12 each ran:

`python -m pytest tests/test_sandbox_s1_security.py tests/test_sandbox_s1_boundaries.py -q`

Result: 87 PASS on each runtime (81 independent adversarial cases plus six static
boundary cases). No skip/xfail, provider transport, VM, broker, IPC or operational
sandbox ran. Full Python, package and CI gates belong to the coordinating handoff;
they were not run or claimed by this reviewer.

Reviewed working-file SHA256 after formatting and dimension fixes:

- puretypes.py: D24141886263F002F397B43C46F032BEFBFB160768E4BB1EB6EF4138F1F91806
- codecs.py: ACA189710A07C39E968430DBEFD7B465BD044ED99809802DA91C5D7A388A2805
- model.py: D6DF01E89BF08935BB79B92B50B70A1A28FFB1434DB0118154FB73211D2D5278
- test_sandbox_s1_security.py: 0A81ACFC33FB346F3B6DF445682F4A84C0028FA5790B5612A8C9BEAC6ED0DC35

## Retained conditions and limitations

The report always says SIMULATION, operational=False, unauthenticated_audit=True.
An OPERATIONAL wire claim and structurally valid PolicyApproval never authenticate
provenance or create permission. Audit payload bytes remain opaque; references and
hashes do not prove real monitor continuity, ownership, cleanup or truthful claims.
Python object freezing is an API invariant, not security against arbitrary Python
code with process memory access. Revalidation protects supported API boundaries.
Fake Context facts and fake journal/commit outcomes do not prove a real host.

No evidence here proves durability, Windows authority, CAS/fencing, antirollback,
isolation, clocks/revocation latency, resource cleanup, profiles or E1–E5.
S1 remains a pure library with no runtime activation. Native Sandbox P0 is OPEN;
merge, S2, writable, Run A and real E2E remain unauthorized. Independent B review
and all official gates remain required before a separate merge decision.

FUNCTIONAL_CODE_MODIFIED_BY_REVIEWER: FALSE
REPOSITORY_MUTATIONS: independent tests and this review only
SKILLS_SELECTED: code-review, bug
SKILLS_APPLIED: code-review, bug
SKILL_SOURCES: C:/Users/LA NAVE/.agents/skills/code-review/SKILL.md; C:/Users/LA NAVE/.agents/skills/bug/SKILL.md
SKILL_SELECTION_REASON: independent boundary audit and deterministic reproduction of discovered defects
