# PR83 recovery identity corrective handoff V1

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-26T22:16:51Z
Updated by: Engineering Orchestrator A
Task: SBX002_D1_D5_P1_RECOVERY_IDENTITY_REVIEW_V1
Parent ticket: SBX002_D1_D5_TEST_CONTROL_LEDGER_V1
Base: dc313a01b487018ad27fdfd0591f6bb6dad37e38
Audited predecessor: a5843d11670056516c2077b18652f7f91a49ef43
PR: 83, DRAFT
Receipt: PENDING_EXTERNAL_ORCHESTRATOR_B

## Authority and scope

The Human Project Owner explicitly requested a disposable two-execution
reproduction, minimal repair if confirmed, CTO/Security contract interpretation,
independent QA/Security, Python 3.11/3.12 regressions and update of the same draft
PR. External B disposition was CHANGES_REQUIRED_PENDING_REPRODUCTION. Previous
deliveries and approvals remain immutable historical evidence. This successor
does not grant merge, other increments, operational writable, providers, VMs,
broker, Run A or E2E permission. Native Sandbox P0 remains OPEN.

## Confirmed root cause and frozen signal

`recover()` fully validated the database, then selected a historical operation
globally without binding it to the optional execution selector. On a disposable
database with A/A1 and B/B1, `recover(execution_id=A,
uncertain_operation_id=B1)` returned VERIFIED with snapshot A and operation
FOUND whose result snapshot belonged to B. The reverse direction also failed.

Original source SHA256:
`ae7c9de161ed2f56cf0986a3717c95af07f9e7d95a94bfaa04ed75f2af229ed7`.
The unchanged executable reproducer is
`tests/test_sandbox_test_ledger_recovery_identity.py`, exact-byte SHA256
`7351a46c9d6b534c7606dbfc3ae1f8ceddbbe4bcf8721dc86b6ba51b56b71ab3`.
Both target runtimes produced 2 FAIL / 9 PASS before and 11 PASS after the
repair, using the exact same test file. Raw before/after outputs are published
under `docs/engineering/sbx002/recovery-identity-evidence/`.
Classification: CONFIRMED ROOT CAUSE; REPAIR, not workaround.

## Minimal repair and compatibility

Six added lines in `test_ledger.py` require both the already validated operation
envelope execution ID and historical result snapshot execution ID to equal the
supplied execution ID, before constructing FOUND. No second database traversal,
schema change or state mutation is added. Patched source SHA256:
`69f01974f67ac454e0a1b37c40d4611e2bf285aa3955b08777fb5838d8bdd44e`.

CTO and Security selected existing OPERATION_CONFLICT, consistent with the
frozen global lookup identity rule. An existing foreign operation is not ABSENT.
Global `execution_id=None` remains explicit, with snapshot=None and the exact
historical operation. Actual absent operation remains ABSENT and forbids replay;
missing requested execution retains EXECUTION_NOT_FOUND precedence.

Full bounded validation, all-execution irreversible RECOVERED latching and
corruption poisoning precede selection. A fresh identity conflict produces no
report, leaves RECOVERY_REQUIRED and does not poison valid storage. A previously
verified handle retains its invalidate-only restrictions after a later conflict.
No admission, authority, replay permission or operational guarantee is granted.

Public arguments, report types, errors, V1/S1 schemas and limits remain unchanged.
Frozen API SHA256 remains
`7af03df901c3b0698188a51ac9e8ab30ef4ae70fbd2dc5cec9c2fba7b4871b30`.
Old public acceptance of the mixed-identity report is the corrected defect.

## Independent role evidence

- [CTO successor](../../sbx002/D1_D5_RECOVERY_IDENTITY_CTO_V1.md): technical
  contract interpretation and final patch approval; tests attributed, not executed
  by CTO. No institutional ratification is inferred.
- [QA successor](../../sbx002/D1_D5_RECOVERY_IDENTITY_QA_V1.md): 18 independent
  tests PASS on each target runtime, including both directions, post-success
  conflict, unchanged DB hash/tables, global/absent and admission restrictions.
- [Security successor](../../sbx002/D1_D5_RECOVERY_IDENTITY_SECURITY_V1.md):
  11 focused tests plus three independent adversarial scenarios PASS on 3.11;
  unrelated corrupt execution still blocks and poisons recovery. A first ad-hoc
  harness cleanup error was corrected and is not reported as a ledger failure.

## Validation and publication

Full local validation completed before publication. Exact published-HEAD CI is
verified separately in the final external handoff, not inferred from these local
results. Full tests inherit a
process-local PATH excluding only the installed Ollama directory, following the
previously documented hanging version-probe condition. No global configuration,
tests, selections or skip markers are changed. Local-only evidence is separate
from official CI. No real inference is executed.

- Exact unchanged reproducer: 11 PASS on each Python 3.11.9 / 3.12.10; historical
  before result remains 2 FAIL / 9 PASS on each.
- Independent QA: 18 PASS per runtime; five original/backend ledger suites:
  127 PASS per runtime (before the additional independent QA selection).
- Complete ledger + SBX-001 + S1 selection: 1175 PASS per runtime.
- Full Python: 1462 PASS / 1 existing Windows symlink-permission skip per runtime;
  134.65 seconds on 3.11 and 134.81 seconds on 3.12. No test deselection.
- Python compileall: PASS; npm package tests: 3/3 PASS.
- Installed exact tarball E2E: PASS; artifact SHA256
  `c0efbe45d72d0a1a813ee0ddcd871d30a8fbfd382b810073abf47edec638308b`.
  This artifact predates documentary receipts only; functional bytes are final.
- `git diff --check`: PASS before commit. Source manifest records checkout and
  Git-normalized hashes; differing line-ending domains are explicitly separate.
- Full PowerShell smoke/release/CodeQL: official CI required on corrected HEAD;
  no predecessor green checks are reused as corrected verification.

## Next action and retained gates

External Orchestrator B must contraaudit the exact updated PR83 HEAD with this
successor and its source manifest. PR remains DRAFT. No merge or next increment.
Shared stale state indexes are outside this ticket's ownership and unchanged.

SKILLS_SELECTED / SKILLS_APPLIED: bug, code-review, release.
SKILL_SOURCES: .agents/skills/bug/SKILL.md;
.agents/skills/code-review/SKILL.md; .agents/skills/release/SKILL.md.
Reason: preserve pre-fix observation, repeat identical signal, independently
review identity/failure semantics and verify the corrected draft publication.
