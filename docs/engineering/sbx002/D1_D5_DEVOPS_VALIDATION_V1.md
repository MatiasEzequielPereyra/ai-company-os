# D1/D5 DevOps validation V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-25
Updated by: delegated DevOps /root/ledger_devops
Task: SBX002_D1_D5_TEST_CONTROL_LEDGER_V1
Base: dc313a01b487018ad27fdfd0591f6bb6dad37e38
Disposition: targeted process/storage checks PASS; final release gates remain pending

## Authorization and sources

Human-authorized test-only ledger implementation task, delegated to DevOps for
process, crash, configuration and storage validation. Ownership is limited to
this document and tests/test_sandbox_test_ledger_process.py. No commit, push,
providers, VM, broker, real runner, permissions change or historical directory
access was performed. Applied AGENTS.md, company-state recovery protocol,
DevOps role, the release and feature skills, frozen API, CTO review/addendum and
Security precode approval. Derived historical state grants no new authority.

Frozen contract: D1_D5_API_CONTRACT_V1.md SHA256
7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30.

Tested implementation source SHA256 (subsequent source changes require rerun):

- src/company_os/sandbox/test_ledger.py:
  75433a850220e49849332f686c43b605f20bfa791d85e497a083dea6ebb5d1f6
- src/company_os/sandbox/test_ledger_types.py:
  aa654d0c1a01ef4515e5daafc591647326a6d29332a0c74fd9812f2af984f7a9

## Executed evidence

Windows 11 Pro 10.0.26200 x64, C: NTFS. Exact interpreter versions confirmed:
Python 3.11.9 / SQLite 3.45.1 and Python 3.12.10 / SQLite 3.49.1.
Final targeted runs: **8 passed** each (1.15s and 1.28s respectively).

| Scenario | Observed contract result |
| --- | --- |
| Two independent connections on two owning threads, simultaneous barrier release, same expected version | Exactly one COMMITTED and one CAS_CONFLICT; final version 1 |
| Two independent processes, identified ready handshakes, simultaneous parent release | Exactly one COMMITTED and one CAS_CONFLICT; two total journal and operation rows including creation |
| Kill own child at private before-COMMIT hook | Nonzero rollback journal observed; independent RECOVER verifies version 0 and uncertain operation ABSENT |
| Kill own child after COMMIT before ACK | Independent RECOVER verifies version 1 and uncertain operation FOUND |
| BEFORE_WRITE / BEFORE_COMMIT injected fault | PERSISTENCE_FAILURE, old handle poisoned, uncertain operation ABSENT |
| AFTER_COMMIT_BEFORE_ACK injected fault | COMMIT_UNCERTAIN, old handle poisoned, uncertain operation FOUND |
| Explicit 65536-byte database cap exhausted by bounded creation loop | Mutation fails closed, handle poisoned, file stays within cap; independent recovery verifies exactly three payload row visits per committed execution |
| Effective connection configuration | DELETE, FULL (2), FK ON, configured busy timeout, effective max_page_count=floor(cap/page_size) |

All recovery checks assert admission_open=False and recovered_invalidated=True.
Crash recovery additionally rejects acquisition and preserves the historical
version. No absent operation is replayed. Creation occurs through NEW before
ATTACH; session_id and expected database_id are explicit on every open.

The process harness launches only this pytest test file using sys.executable.
Each child has a random token, exclusive temporary signals and PID handshake;
parent termination targets only the Popen child after identity verification.
Signals are atomically renamed. Waits are bounded; finally blocks close handles
and wait for owned children. Parent and child are the only cooperating writers
in crash cases: child pauses in its hook, parent closes its connection before
termination, and subsequent access uses RECOVER. No cross-process failure permits
further admission. This cooperation is not a real independent watchdog or proof
of instantaneous unseen-failure detection.

Rollback-journal bytes were observed separately from database bytes before
COMMIT. The database cap does **not** cap rollback-journal, temporary files,
directory size or total disk consumption. Actual filesystem-wide disk/temp
exhaustion was NOT_RUN: no host volume was filled and no evidence was purged.
The explicit small database cap supplies real SQLite allocation-exhaustion
coverage; fault controls supply transaction/ACK failure coverage. These checks
are not a proof of arbitrary journal/temp allocation failure or power-loss safety.

## Reproduction

Run from this worktree. Each run must use a fresh exclusive base under the
existing C: temporary directory. Example final commands (use a fresh suffix):

```powershell
& 'C:/Users/LA NAVE/AppData/Local/Python/pythoncore-3.11-64/python.exe' -m pytest tests/test_sandbox_test_ledger_process.py -q --basetemp='C:/Users/LA NAVE/AppData/Local/Temp/sbx002-devops-311-b'
& 'C:/Users/LA NAVE/AppData/Local/Python/pythoncore-3.12-64/python.exe' -m pytest tests/test_sandbox_test_ledger_process.py -q --basetemp='C:/Users/LA NAVE/AppData/Local/Temp/sbx002-devops-312-b'
```

An initial run selected nonexistent C:/Temp and produced eight fixture setup
errors before any ledger work. Selecting the existing user C: Temp resolved
that environment invocation issue. No product source correction was necessary.

## Remaining gates and operational limits

Parent owns full regression, CI and exact installed npm package verification.
Those checks are NOT_RUN by this delegated DevOps task. Installed artifact must
contain both new stdlib sqlite ledger modules with source byte identity; no
extra Python dependency is introduced. Independent QA/Security implementation
review and CEO release approval remain required. No operational release or
production readiness is claimed. Rollback for this uncommitted increment is
removal of only its authorized new implementation/test artifacts by their owners;
no existing evidence, S1 contract or historical run should be changed.

SKILLS_SELECTED: release, feature
SKILLS_APPLIED: release, feature
SKILL_SOURCES: C:/Users/LA NAVE/.agents/skills/release/SKILL.md; C:/Users/LA NAVE/.agents/skills/feature/SKILL.md
SKILL_SELECTION_REASON: scoped process/storage failure acceptance and release evidence for the authorized test-only feature.
