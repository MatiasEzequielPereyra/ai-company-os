# S1 P1-005 independent Security/code review V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-24
Updated by: delegated independent reviewer `/root/p1005_security`
Task: SBX002_S1_P1_005_GENERATION_CHRONOLOGY_FIX_V1
Base: 12439870d44ead5b538c2ecd33f776ebc15efe12
Previous audited HEAD: 2b50f44ada1ccf9fd5d0a5b5b6ab36127cd8d309
Decision: APPROVED_WITH_CONDITIONS_FOR_INDEPENDENT_DRAFT_REAUDIT

## Scope, authority and sources

Read AGENTS.md, the company-state protocol and derived state, the integrated
decision-policy baseline DR-2, historical decision record section 5, the S1 API
contract, and the source/test diff. Applied `code-review` from
`C:/Users/LA NAVE/.agents/skills/code-review/SKILL.md` because the assigned work
is an independent correctness, regression and security review. The human task
permits only the scoped pure-core corrective patch and draft publication.
This agent modified no source or test; this successor review is its only write.

Historical section 5 requires a single confirmed transaction to consume the
retry, change generation to g1, record the transition and reserve capture intent.
Only after confirmation may g1 capture occur. It also requires the consumer to
check that cause, generation, request and transition commit agree. The S1 API
models retry resolution at that committed event sequence. Thus a g1 cause at or
before the commit cannot be an observation of that generation. This is a causal
ordering correction, not an additional operational authorization.

Sources:

- `docs/engineering/sbx002-d6/NATIVE_SBX_002_CTO_SECURITY_DECISION_RECORD_V1.md`, section 5.
- `docs/architecture/native-sandbox/SBX002_DECISION_POLICY_BASELINE_V1.md`, DR-2.
- `docs/engineering/sbx002/S1_API_CONTRACT_V1.md`, retry transaction and state contracts.

## Findings and resolution

P1-005 is addressed by the shared `validate_generation_chronology` check:
every g1 cause must have `event_sequence > retry_commit_sequence`. The CoreState
constructor and both public decode paths (live-state and host-evidence) invoke
the same check after their existing structural validation. The helper compares
journal sequences only. It does not compare any sequence to LiveState.version.

Existing checks continue to require the exact g0 transport cause and retry
resolution, permit no g1 without resolution, bind request/generation, and enforce
cause dominance and irreversible invalidation. The change does not clear causes
or accept a completed result merely because its chronology is valid. The exact
resolved g0 transport exception remains accepted for a genuinely healthy g1.

The narrow correction does not add a broader upper bound for every historical
g0 cause; no such unrelated restriction was inferred in this review.

No remaining P0/P1 was identified in this scoped static review and executed
subset. Standalone request.v1/receipt.v1 implementation and their original tests
have no diff relative to the previous audited HEAD. No public API signature,
wire shape, synthetic limit, provider or operational behavior is added.

## Executed verification

Executed independently on Python 3.11 and 3.12:

`python -m pytest -q tests/test_sandbox_s1_p1_005_chronology.py tests/test_sandbox_s1_security.py tests/test_sandbox_s1_p1_security.py`

- Python 3.11: **411 passed**, 0.67 seconds, exit 0.
- Python 3.12: **411 passed**, 0.68 seconds, exit 0.

The new tests cover all three public validation interfaces, before/equal commit
sequences including the exact g1 sequence 3 / commit 6 incident, every admitted
cause code with consistent result dimensions, valid sequence 7 / commit 6,
resolved transport completion, and live CAS versions 1, 5, 6 and 100 independent
of journal sequence. Existing security and prior P1 adversarial cases also pass.
Full suites and official CI are the orchestrator's separately reported evidence;
they were not executed or independently inspected by this reviewer.

## Reviewed checkout byte SHA-256

These are exact current-file bytes after backend confirmation that formatting
was complete; Git-normalized LF blob hashes can differ from checkout CRLF bytes.

| File | SHA-256 |
| --- | --- |
| `src/company_os/sandbox/model.py` | `17422b7ede5831fbbbcc2210cf37154cd7e42613d3b164213fd3a1d83021d7eb` |
| `src/company_os/sandbox/codecs.py` | `4094f210d1442f9631ce1f200d2320917ea4246b8e2e529aa481b8b6e3b2e062` |
| `tests/test_sandbox_s1_p1_005_chronology.py` | `d5cb0168f590f1347b16220e7b85de1796a4e0d36da662323097b73985ab1298` |

## Conditions and limitations

The verdict permits submission for independent draft re-audit only. B must review
the exact published HEAD and official gates. No merge, S2, writable, provider,
VM, broker or E2E operation is approved. Structural consistency and synthetic
tests do not prove authentic journal origin, durable commit, isolation or fencing.
Material policies and operational certification remain pending; Sandbox P0 is
OPEN. This is an agent technical opinion, not an institutional signature or
human ratification.
