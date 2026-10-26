# D1/D5 independent QA report V1

Project: AI_COMPANY_OS
Revision: 2
Updated: 2026-10-26T02:24:12Z
Updated by: /root/ledger_qa_resume (independent QA)
Task: SBX002_D1_D5_TEST_CONTROL_LEDGER_V1
Base: dc313a01b487018ad27fdfd0591f6bb6dad37e38
Status: QA_APPROVED_TEST_ONLY
Scope: TEST_ONLY; operational=False; authority_authenticated=False; execution_capability=NONE

## Grounding and ownership

Contract: D1_D5_API_CONTRACT_V1.md, SHA256
7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30.
Parent conveyed CTO and Security concurrence on this exact frozen hash.
Read AGENTS.md, QA role, company state protocol/index, task, project brief,
product context and API contract. Source-of-truth authorization is the task's
human authorization receipt, independently scoped by the parent assignment.
QA owns only this report and tests/test_sandbox_test_ledger_qa.py. Backend owns
all implementation corrections. Existing tests remain unchanged.

SKILLS_SELECTED: code-review
SKILLS_APPLIED: code-review
SKILL_SOURCES: C:/Users/LA NAVE/.agents/skills/code-review/SKILL.md
SKILL_SELECTION_REASON: independent correctness, contract edge cases and regression audit.

## Executed evidence and historical failures

All executions use the actual installed interpreter executables under
C:/Users/LA NAVE/AppData/Local/Python/pythoncore-3.11-64/python.exe and
pythoncore-3.12-64/python.exe. Commands set PYTHONPATH=src, use
`-m pytest -q -c pyproject.toml`, and explicit exclusive C: temporary basetemp
directories under C:/Users/LA NAVE/AppData/Local/Temp/. No database is written
in the source worktree. No providers, VM/services, operational sandbox,
global settings, commits or pushes are performed by QA.

| Execution | Python | Results | Interpretation |
| --- | --- | --- | --- |
| QA initial, incomplete module | 3.11 | 18 passed, 30 failed | Public API not yet written; all dependent failures AttributeError, not acceptance evidence. |
| QA complete initial surface | 3.11 | 50 passed, 5 failed | Two expiry projection defects, reported immediately and negatives retained. |
| QA expanded 67 cases | 3.11 | 66 passed, 1 failed | Previous five failures corrected; repeated CHECK after durable expiry invalidation still commits. |
| QA expanded 67 cases | 3.12 | 66 passed, 1 failed | Same CHECK behavior independently reproduced. |
| SBX001/S1 regressions | 3.11 | 1030 passed | Nine existing sandbox test files. |
| SBX001/S1 regressions | 3.12 | 1030 passed | Same selection, second actual interpreter. |

Regression selection: test_native_sandbox_contracts.py;
test_sandbox_s1_boundaries.py; test_sandbox_s1_codecs.py;
test_sandbox_s1_model.py; test_sandbox_s1_security.py;
test_sandbox_s1_p1_codecs.py; test_sandbox_s1_p1_model.py;
test_sandbox_s1_p1_security.py; test_sandbox_s1_p1_005_chronology.py.

## Findings retained

1. P1 corrected: create, VALID observation sequence1 started10 finished12 now12
   gives expiry62; CHECK/ACQUIRE_OWNER/CHANGE_OWNER/INVALIDATE at now62 commits
   invalidation. New otherwise valid observation sequence2 started62 finished63
   now63 previously committed despite already latched state. Four independent
   parameterized tests now pass after backend correction.
2. P1 corrected: after the same prior observation, INVALID sequence2 started61
   finished62 now62 previously left last_observation=VALID sequence1. The negative
   fact must be recorded; regression now passes after backend correction.
3. Interpretation pending: after expiry CHECK invalidates, exact historical
   observation replay returns unchanged historical evidence correctly. A new
   CHECK now63 then commits another invalidated result instead of INVALIDATED.
   It does not restore authority; backend/parent informed of exact reproduction.
   QA retains the negative test pending contract interpretation/correction.

## Coverage and limits

67 QA cases cover creation, historical replay and independent digest encoding,
CAS/owner/clock and identity collision, exact scope fields, all four expiry
actions, missed renewal, negative observations, ordering reversal/shared latch,
owner change, faults before write/before commit/after commit before ACK,
poison and independent recovery, absent/found uncertain identity, read-only
historical recovery, corrupted head/journal, exact positive integer limits,
global row capacity, selected-head replay visit budget, record representation
ceiling, malformed UUID/bytes/integer inputs, continuity modes, database/session
identity, arithmetic overflow and close semantics.

Cross-process crash/storage/configuration and package tests belong to DevOps;
their results are not claimed here. Full repository regression remains NOT_RUN
by QA at this checkpoint. No operational durability, antirollback, real lease
authentication, independent real stop or power-loss certification is claimed.

## Historical tested source hashes

At expanded 67-case execution (implementation remains under active backend edits):

| File | SHA256 |
| --- | --- |
| src/company_os/sandbox/test_ledger.py | 82b9d0768ceecb407323f45379d4650f381d30344fdb78d84e2c0503b661b2bb |
| src/company_os/sandbox/test_ledger_types.py | aa654d0c1a01ef4515e5daafc591647326a6d29332a0c74fd9812f2af984f7a9 |
| tests/test_sandbox_test_ledger_qa.py | 3713931364dc4f9f821cf47cbe90be861e8b650dc0c718774ba8ec4506df07a2 |

Historical checkpoint verdict: approval withheld pending final corrected source execution and final hashes. The successor below records the later disposition.


## Final corrected-source successor

The earlier execution results and failures above are retained as historical evidence.
They are not revised into successes. Parent confirmed final formatting complete
before these new executions. This resumed QA agent read the frozen contract,
CTO and Security precode reviews, QA role, project context and task receipt;
verified the base and contract hash; and executed all four ledger test files
against the final formatted bytes on both actual interpreters.

| New execution | Python | Actual result |
| --- | --- | --- |
| Four ledger files, final formatted source | 3.11 | 110 passed in 2.74s |
| Four ledger files, final formatted source | 3.12 | 110 passed in 3.07s |

Exact selection: tests/test_sandbox_test_ledger.py,
tests/test_sandbox_test_ledger_process.py,
tests/test_sandbox_test_ledger_qa.py,
tests/test_sandbox_test_ledger_security.py. The QA file now has 68 cases;
all are included in both successful executions. Each command used PYTHONPATH=src,
`-m pytest -q -c pyproject.toml` and an exclusive basetemp at
C:/Users/LA NAVE/AppData/Local/Temp/d1d5-qa-resume-311-final or
C:/Users/LA NAVE/AppData/Local/Temp/d1d5-qa-resume-312-final.

Finding 3 successor: CORRECTED. The retained
`test_idempotent_replay_does_not_clear_expiry_latch` now confirms that replay
returns the unchanged historical result and a later new CHECK raises INVALIDATED.
Findings 1 and 2 also remain passing in these new executions.
A further retained regression,
`test_exact_replay_rejects_structurally_valid_forged_historical_result`, checks
that changing the stored historical snapshot while keeping operation identity
and digest intact rejects replay as STORAGE_CORRUPT or RECOVERY_INVALID and
poisons the handle. It passes on both interpreters. No current failing case
or newly identified P0/P1 defect remains in this QA selection.

Final verdict: QA_APPROVED_TEST_ONLY for the exact bytes below and the covered
contract acceptance scenarios. This is independent QA acceptance of this
synthetic ledger slice, not CEO closure or operational acceptance. Full repository
suites are NOT_RUN by this resumed QA agent and remain parent-owned evidence.
The 1030-pass S1/SBX001 entries above belong to the earlier QA execution record;
this resumed agent does not claim to have rerun them. DevOps package evidence,
final Security review, full regression and external B audit retain their owners.
No functional source or tests were changed by this resumed QA agent.

## Final tested source hashes

| File | SHA256 |
| --- | --- |
| src/company_os/sandbox/test_ledger.py | 4d6db55f18f73396ebd9eda7803058eda27bd65b6e41dddc862621fd674de8e2 |
| src/company_os/sandbox/test_ledger_types.py | 1e71d6a2c789e6e8cfb563d3e79d0d726ca4d2a31db3dc06451de6c8bf4c0361 |
| tests/test_sandbox_test_ledger.py | d5159faa3ad9676c5512fcc08885fce2ede6283a93716884ead1a34eaed85bcf |
| tests/test_sandbox_test_ledger_process.py | 54289e095191bc8b8410b80423127791965e78b96a6680b321dc4e2d011a3bdb |
| tests/test_sandbox_test_ledger_qa.py | 05b9af7b992088c2ad68df1e88d366d8ec62733d4e78c4ccb7edfe15c156467d |
| tests/test_sandbox_test_ledger_security.py | 84e5a144e1bee7bb8ae53f4532a44164b6931b3a8ce58796d8ac03b1e416d564 |

Contract SHA256 remains
7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30.
Scope=TEST_ONLY; operational=False; authority_authenticated=False;
execution_capability=NONE. No commit or push performed by QA.
