# S1 Security pre-code review V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-22T00:27:07Z
Updated by: delegated Security agent /root/s1_security_precode
Task: SBX002_S1_PURE_CORE_IMPLEMENTATION_V1
Base: 12439870d44ead5b538c2ecd33f776ebc15efe12
Reviewed contract: S1_API_CONTRACT_V1.md
Reviewed contract SHA-256 (current file bytes): d041ac2f1425e0dd17e025b3bc5e2ba60d7d7cc7f9c621eb08f23db367b1176b
Decision: APPROVED_WITH_CONDITIONS_FOR_PURE_CORE_IMPLEMENTATION

## Scope and source boundary

This is the configured Security role's technical pre-code review under the
explicit human S1 implementation authorization. It is not an institutional
signature, product acceptance, operational approval or proof of external identity.
Reviewed the Security role, code-review skill, AGENTS, historical sections 4–11,
the retained S0 boundaries, PR81 ratification and the exact final CTO-refined API
contract identified above. CTO owns the API contract; this review did not edit it.

## Resolved pre-code findings

1. Bound input ownership: exact bytes and exact built-in dictionaries reject
   custom Mapping callbacks/subclasses. Bound collection counts and all root,
   resolved piece, payload and output bytes before recursive work. Unused inputs
   still count and are rejected, preventing unaccounted external evidence.
2. Parser protection: required positive exact-integer synthetic limits, no
   defaults, bounded JSON nesting before load with quote/escape awareness,
   duplicate/nonfinite/BOM/UTF-8/type/shape rejection and exact raw-byte hashes.
3. Evidence integrity: typed edges, cycle and duplicate semantic-reference checks,
   identity/epoch/generation/sequence bindings, no resolver or filesystem callback.
4. Trust separation: opaque audit bytes can establish bounded reference/digest
   consistency only. The report permanently carries scope=SIMULATION,
   operational=False and unauthenticated_audit=True. It cannot substantiate real
   cleanup, monitor continuity, freshness or host provenance. No approved,
   authorized or VerifiedHostEvidence member may appear.
5. Model integrity: required typed facts distinguish absence proven from false
   or unproven facts, terminal content remains immutable, and invalidation latch
   and INVALIDATED result agree in both directions. Retry never removes a latch.
   Later post-seal permission changes do not rewrite historical evidence.
6. PolicyApproval/POL-13 stays structurally parsed data. A valid shape, principal
   claim or policy digest cannot grant authority. Fake observations are statements
   of a test harness within simulation only, not proven host observations.

No remaining Critical/High/Medium pre-code blocker was found in this exact
contract after those refinements. Implementations remain subject to review and
must not silently deviate from the contract.

## Synthetic ceiling decision

Approve the explicitly required engineering bounds for simulation: at most
8 MiB per piece, 32 MiB aggregate, depth 12, 256 collection items, 64 resolved
pieces and 256 events. Each configured value remains positive and bounded;
booleans are not integers. These are parser safety ceilings, not production
evidence quotas, profile certification, retention decisions or material-policy
ratification. The exact numerical proposal from B was not supplied; no claim of
having verified such absent bytes is made. Existing V1 contracts/limits remain
unchanged. A narrower synthetic envelope may reject inputs independently without
changing standalone SBX-001 behavior.

## Mandatory implementation verification

Require negative tests for every input boundary, n/n+1 limits, malformed nested
shapes, graph/digest/identity tampering, missing cleanup or required audit kinds,
fake authority escalation and unchanged V1 regressions. Exercise all mapping
dimensions with independent expected cases, terminal-first dispatch, D20,
irreversible invalidation, retry guards, accumulated budget boundaries and fake
Start/Invalidate/Seal/Publish/journal/commit interleavings. An uncertain commit is
not success; absent real audit authentication never becomes an operational claim.
Review the implementation separately before publication acceptance.

## Retained risks and exclusions

Python objects and supplied Context fields are not security credentials. This
slice proves no real CAS, atomicity, persistence, antirollback, runtime identity,
isolation, revocation latency, cleanup or E1–E5 guarantee. No broker, IPC, services,
Hyper-V, VSS, provider, runner, writable, real E2E or production policy is enabled.
No host inference, simulation execution, test suite or transport was run for this
pre-code review. Native Sandbox P0 remains OPEN; merge remains unauthorized.

REPOSITORY_MUTATIONS: this review file only.
FUNCTIONAL_CODE_MODIFIED: FALSE
TESTS_EXECUTED: NOT_RUN
SKILLS_APPLIED: code-review (.agents/skills/code-review/SKILL.md).
