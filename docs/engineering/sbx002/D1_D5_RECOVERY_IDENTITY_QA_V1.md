# D1/D5 recovery identity independent QA V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-26T22:15:59Z
Updated by: /root/recovery_qa (QA)
Task: SBX002_D1_D5_TEST_CONTROL_LEDGER_V1
Base: a5843d11670056516c2077b18652f7f91a49ef43
Status: APPROVED_TEST_ONLY_RECOVERY_IDENTITY_FIX

## Authorization and expected behavior

Engineering Orchestrator A assigned independent QA for the human-authorized PR83
recovery identity correction. Assignment permits this independent test file,
this report and focused local execution after backend reproduction/patch capture.
Backend readiness was received before executing these cases. The frozen
[API contract](D1_D5_API_CONTRACT_V1.md), revision 1, remains unchanged.
CTO/Security interpretation supplied by the Orchestrator requires
OPERATION_CONFLICT when a requested execution and found uncertain operation
belong to different executions. Global selection (execution_id=None) retains
FOUND, absent operation retains ABSENT and missing execution retains
EXECUTION_NOT_FOUND. A rejection must not return a verified report or grant
write eligibility.

QA read AGENTS, QA role, durable-state protocol/index, project brief/product
context, task, EM assignment and frozen contract. Historical state indexes are
not used as execution authorization. QA modifies neither backend source nor its
tests and does not alter lifecycle status or historical approvals.

## Independent scenarios and results

The new [QA suite](../../../tests/test_sandbox_test_ledger_recovery_identity_qa.py)
uses public ledger APIs and exclusive temporary SQLite directories. Independent
SQLite reads use mode=ro. Each scenario compares exact database SHA-256 and all
three tables, runs integrity_check and foreign_key_check, and confirms no
durable change. Fixture executions differ in execution, request, owner and epoch.

| Scenario | Cases per runtime | Result |
| --- | ---: | --- |
| A selecting B and B selecting A; creation or positive observation operation; initial recovery or after successful recovery | 8 | PASS |
| Missing uncertain operation with global, A or B selection; repeated read, ABSENT and no replay | 3 | PASS |
| Global selection finds exact historical creation or observation from A or B with snapshot=None | 4 | PASS |
| Missing execution with found, absent or omitted uncertain operation retains EXECUTION_NOT_FOUND | 3 | PASS |

The eight conflict cases require LedgerError with fixed TEST_ONLY fields, so no
RecoveryReport can escape. Initial failure preserves RECOVERY_REQUIRED and
rejects even a fresh durable INVALIDATE. Failure after prior VERIFIED preserves
READY but rejects CHECK. A subsequent correctly bound recovery on the same
handle returns the exact historical result and current historical head while
admission_open=False and recovered_invalidated=True. Fresh ACQUIRE_OWNER remains
INVALIDATED: conflict/corrected selection cannot clear recovery's latch. Snapshot
reads preserve both historical executions. Global validation visits all ten
logical rows (two heads, four journal rows, four operations).

Executed exact command on each target executable:

```text
<python> -m pytest tests/test_sandbox_test_ledger_recovery_identity_qa.py -q
```

| Executable | Version | Observed output |
| --- | --- | --- |
| C:/Users/LA NAVE/AppData/Local/Python/pythoncore-3.11-64/python.exe | 3.11.9 | 18 passed in 0.84s |
| C:/Users/LA NAVE/AppData/Local/Python/pythoncore-3.12-64/python.exe | 3.12.10 | 18 passed in 0.87s |

Failed cases: NONE. New defects: NONE. Open scoped P0/P1: NONE.
QA approval applies only to the exact correction/test bytes below. Backend's
prepatch reproduction is separate evidence; QA did not execute a prepatch copy.
Full suites and official CI are NOT_RUN by this QA agent and remain coordinated
Orchestrator evidence. This report grants no merge or operational approval.
No real providers, VMs, external authority, command execution or operational
D1/D5 verification were exercised.

## Exact source evidence

Hashes captured after both passing runs; working changes on the stated base are
identified by content, not represented as already committed evidence.

| Source | SHA-256 |
| --- | --- |
| src/company_os/sandbox/test_ledger.py | 69f01974f67ac454e0a1b37c40d4611e2bf285aa3955b08777fb5838d8bdd44e |
| src/company_os/sandbox/test_ledger_types.py | 1e71d6a2c789e6e8cfb563d3e79d0d726ca4d2a31db3dc06451de6c8bf4c0361 |
| tests/test_sandbox_test_ledger_recovery_identity_qa.py | 8775f90dc07caa37f7272cd494698e972bc4de3e73eb8bb892988ff043102b64 |
| tests/test_sandbox_test_ledger_recovery_identity.py (backend evidence reference, not QA execution) | 7351a46c9d6b534c7606dbfc3ae1f8ceddbbe4bcf8721dc86b6ba51b56b71ab3 |
| docs/engineering/sbx002/D1_D5_API_CONTRACT_V1.md (revision 1) | 7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30 |

SKILLS_SELECTED: bug
SKILLS_APPLIED: independent defect verification and regression scenarios; backend owns repair and initial reproduction
SKILL_SOURCES: C:/Users/LA NAVE/.agents/skills/bug/SKILL.md
SKILL_SELECTION_REASON: verify the scoped recovery identity defect against frozen expected behavior

Next owner: Engineering Orchestrator A; next action: combine exact-source role
evidence with coordinated regression and publication checks for External B audit.
