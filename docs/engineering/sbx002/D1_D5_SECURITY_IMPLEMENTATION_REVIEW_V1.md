# D1/D5 Security implementation review V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-25
Updated by: /root/ledger_security_resume, independent delegated Security reviewer
Task: SBX002_D1_D5_TEST_CONTROL_LEDGER_V1
Base: dc313a01b487018ad27fdfd0591f6bb6dad37e38
Disposition: APPROVED_TEST_ONLY_NO_OPEN_P0_P1

## Scope and finding disposition

Reviewed the actual final formatted implementation against the frozen API and
CTO recovery-error addendum, following the repository code-review skill. This is
an implementation review, not a repetition of precode approval or an external
institutional signature. Read AGENTS, durable-state protocol/index, Security role,
project/context documents, current task/assignment, precode approvals, both new
implementation modules and the backend, independent QA, process and Security tests.

No open P0/Critical or P1/High implementation finding was identified in this
synthetic slice. No additional Medium or Low finding is submitted. Approval is
limited to the exact source bytes below and the cooperative TEST_ONLY contract.
It does not authorize merge or certify operational D1/D5 or Native Sandbox P0.

The prior-expiry replacement/acquisition cases and historical-result projection
forgery were specifically reread after the earlier corrections. `_project`
checks persisted expiry/freshness before owner reset or positive replacement;
negative observations preserve their negative fact. Historical exact operation
replay verifies the full stored journal/result projection before returning the
unchanged historical result. It does not clear any latch or grant current lease.

## Reviewed properties

- Exact validated inputs, closed records and enums, fixed TEST_ONLY scope fields,
  byte/canonical JSON bounds, duplicate keys/nonfinite/deep or oversized storage
  rejection, and no supplied command/callback execution port.
- BEGIN IMMEDIATE and atomic head/journal/operation persistence; exact global
  operation identity before current eligibility; CAS, owner, epoch and time/order
  fences; irreversible shared local latches and symbolic stop before negative IO.
- Effective SQLite configuration/schema checks, scalar typeof/length inspection
  before payload materialization, bounded row counts and recovery visits, bounded
  SQLite cell envelope, database page cap and absence of additional schema code.
- Poison on uncertain commit/ACK or persistence failure; independent recovery
  verifies full projections and keeps admission closed. Recovery snapshots and
  FOUND outcomes remain historical. Missing uncertain operations do not replay.
- NEW/ATTACH/RECOVER boundaries and cooperative continuity responsibility; no
  lifecycle reducer fork, S1/V1 functional edit, g1 or operational integration.

## Executed independent Security verification

Executed this review's own Security subset using each actual local interpreter:

| Runtime | Test command scope | Result | Exclusive temporary storage |
| --- | --- | --- | --- |
| Python 3.11 | pytest tests/test_sandbox_test_ledger_security.py -q -p no:cacheprovider | 23 passed, 0 failed (0.40 s) | C:/tmp/sbx002-security-resume-311 |
| Python 3.12 | pytest tests/test_sandbox_test_ledger_security.py -q -p no:cacheprovider | 23 passed, 0 failed (0.41 s) | C:/tmp/sbx002-security-resume-312 |

Interpreters: C:/Users/LA NAVE/AppData/Local/Python/pythoncore-3.11-64/python.exe
and C:/Users/LA NAVE/AppData/Local/Python/pythoncore-3.12-64/python.exe.
PYTHONPATH=src; explicit --basetemp paths above. All SQLite writes from these
runs were confined to pytest-owned exclusive C: temporary test directories.

The 23 cases exercise hostile snapshot framing/types/bounds, unexpected index,
trigger/view and effective configuration tampering, oversized-cell scalar
rejection before decoder entry, instance-shadowed observation validator forgery,
stop/latch-before-storage failure and forged stored authority scope. Existing
negative assertions were retained. No functional code was edited by this reviewer.

Independent QA/process tests were read, including controlled owned-child CAS and
before/after COMMIT termination, ACK uncertainty, conservative recovery and DB
capacity exhaustion. Their execution is owned by QA/DevOps/Orchestrator and is
not counted as a Security run here. Full suite, CI and installed-package checks
were NOT_RUN by this reviewer; consult their separate exact-source evidence.

## Exact source manifest

SHA-256 values are hashes of actual final formatted bytes, not Git-only claims.

| Source | SHA-256 |
| --- | --- |
| src/company_os/sandbox/test_ledger.py | 4d6db55f18f73396ebd9eda7803058eda27bd65b6e41dddc862621fd674de8e2 |
| src/company_os/sandbox/test_ledger_types.py | 1e71d6a2c789e6e8cfb563d3e79d0d726ca4d2a31db3dc06451de6c8bf4c0361 |
| tests/test_sandbox_test_ledger_security.py | 84e5a144e1bee7bb8ae53f4532a44164b6931b3a8ce58796d8ac03b1e416d564 |
| tests/test_sandbox_test_ledger_qa.py | 05b9af7b992088c2ad68df1e88d366d8ec62733d4e78c4ccb7edfe15c156467d |
| tests/test_sandbox_test_ledger_process.py | 54289e095191bc8b8410b80423127791965e78b96a6680b321dc4e2d011a3bdb |
| docs/engineering/sbx002/D1_D5_API_CONTRACT_V1.md | 7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30 |

## Retained limits and handoff

Python objects/session assertions/hashes are unauthenticated test metadata.
Cross-process continuity and writer shutdown remain controlled harness duties;
there is no instantaneous independent watchdog. The file cap does not bound the
rollback journal or directory. Actual host disk exhaustion and power loss were
not induced by this Security subset. SQLite cannot prove namespace history or
reject coherent hostile replacement/rollback of all evidence. No Windows origin,
real stop/cleanup, isolation, VM/VSS, privileged broker, live DEP-D1/DEP-D5,
providers, operational Run A/E2E, production gate or E1-E5 claim follows.
Native Sandbox P0 remains OPEN. No commit, push, merge or provider call was made
by this reviewer. Next owner: Orchestrator for remaining aggregate verification,
one authorized draft and External B contraaudit; lifecycle transitions remain
with their assigned owners. Any change to reviewed functional bytes requires
revalidation of affected evidence.

SKILLS_SELECTED: code-review
SKILLS_APPLIED: code-review
SKILL_SOURCES: .agents/skills/code-review/SKILL.md
SKILL_SELECTION_REASON: independent security implementation and hostile-input review against frozen API
REPOSITORY_MUTATIONS: this implementation review report only; existing Security tests retained

## Revision 2: same-owner continuity correction and renewed implementation review

Revision: 2
Updated: 2026-10-25
Updated by: /root/ledger_security_resume, independent delegated Security reviewer
Current disposition: APPROVED_TEST_ONLY_NO_OPEN_P0_P1_AFTER_CONTINUITY_CORRECTION
Historical PR head reviewed before correction: 902d0c7767a2ef96183e83013c77df08fb0c4f3e

Revision 1 approval above was WITHDRAWN after an additional concrete P1/High
finding. Its original source hashes, 23-case results and limitations are retained
as historical evidence; they do not approve the vulnerable implementation.

Confirmed through public API: create at 0, VALID source sequence 1 at 12 with
expiry 62, same-owner ACQUIRE_OWNER at 20, then VALID sequence 1 at 100 produced
an uninvalidated lease ending 150. The visible snapshot clearing on ACQUIRE is
specified, but treating it as genuinely unobserved initial state violated the
frozen contract's explicit prohibition on removing previously observed history.
The prior source also VERIFIED that impossible history during recovery.

Added six independent Security cases, retaining all existing 23 negative cases:
source-sequence reset rejection after acquisition; expiry discovery commits an
invalidated snapshot; live refresh before expiry remains allowed; explicit
CHANGE_OWNER allows the new owner its first observation; and two canonical,
hash-consistent forged legacy transcripts that must fail recovery for source
reset or hidden expiry. The tamper fixtures recompute operation digest, event
bytes, length-framed journal prefix, historical result and head, so rejection
requires semantic continuity validation rather than merely a broken hash.

Authoritative pre-correction execution against the vulnerable source on Python
3.11: **4 failed, 25 passed**, 0.64 seconds. Exclusive C: test storage and local
log: C:/tmp/sbx002-security-continuity-before-corrected.log; temporary directory
C:/tmp/sbx002-security-continuity-before-corrected. All four failures were the
expected missing protections. An earlier fixture draft had a wrong journal-row
number; that draft was corrected before this authoritative capture and supplies
no evidence for the finding.

Backend correction independently reviewed: a private per-execution context is
rebuilt during the existing bounded journal payload pass and provided to the
same live/recovery projection. It retains the prior same-owner observation's
sequence, started/finished order, expiry and freshness even through repeated
ACQUIRE_OWNER operations. Explicit owner change resets that context. The public
Snapshot continues to clear observation/lease on acquisition as required. No
new table, public record, wire codec, contract change, second SQL payload pass,
trusted mutable cache or additional recovery visit is introduced. Exact replay
and other reads validate the corrected journal progression as well.

Final own execution AFTER final formatting, using the interpreter paths stated
above, PYTHONPATH=src and pytest tests/test_sandbox_test_ledger_security.py -q
-p no:cacheprovider with the exclusive --basetemp directories below:

| Runtime | Final Security result | Exclusive temporary storage |
| --- | --- | --- |
| Python 3.11 | 29 passed, 0 failed (0.53 s) | C:/tmp/sbx002-security-final-311 |
| Python 3.12 | 29 passed, 0 failed (0.53 s) | C:/tmp/sbx002-security-final-312 |

Current exact final-byte SHA-256 manifest (supersedes affected revision 1 rows):

| Source | SHA-256 |
| --- | --- |
| src/company_os/sandbox/test_ledger.py | ae7c9de161ed2f56cf0986a3717c95af07f9e7d95a94bfaa04ed75f2af229ed7 |
| src/company_os/sandbox/test_ledger_types.py | 1e71d6a2c789e6e8cfb563d3e79d0d726ca4d2a31db3dc06451de6c8bf4c0361 |
| tests/test_sandbox_test_ledger_security.py | 4086af2964c43078f6eb4ad6fad54f0dedcfe1fee5b89b0782eb94942ea6da4b |
| docs/engineering/sbx002/D1_D5_API_CONTRACT_V1.md | 7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30 |

Finding status: P1/High same-owner continuity bypass RESOLVED for these exact
bytes. No open P0/Critical or P1/High implementation finding remains in this
scoped review. The revised recommendation is approval for the synthetic test
slice and submission to External B after the Orchestrator's remaining gates.
Revision 1 retained operational limitations all still apply. Full suite, CI and
package execution remain NOT_RUN by this Security reviewer; their other-owner
evidence must identify the corrected head, not the historical PR head above.

This corrective review modified only the owned Security tests and this report;
no functional source edit, commit, push, merge or provider call was performed by
Security. SKILLS_SELECTED/APPLIED: code-review; source and reason unchanged.
