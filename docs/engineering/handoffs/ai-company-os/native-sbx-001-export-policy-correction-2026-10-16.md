# NATIVE-SBX-001 snapshot export policy correction

Project: AI Company OS
Handoff ID: NATIVE_SBX_001_EXPORT_POLICY_CORRECTION
Revision: 1
Updated: 2026-10-16
Updated by: Codex implementer
Previous handoff: native-sbx-001-contract-validators-2026-10-15.md
Initial receipt status: PENDING
Recipient: External Orchestrator / independent reviewer

## Authorization and identity

Human instruction: `NATIVE-SBX-001 - P1 SNAPSHOT CONTROL PLANE EXCLUSION`.
Permitted: correction of snapshot path admissibility, pure regressions and handoff
in the existing worktree only. Retained restrictions: no candidate execution,
VM/broker/providers, runner integration, authorization/lock changes, Run A/PR75
changes, new worktree, commit, push or merge.

BASE_SHA_VERIFIED: 5ce38da9281ddb4baaef4654a35cad447979f8a1
GitHub main was reverified and matches this base; local HEAD is unchanged.
WORKTREE: Z:/repos/ai-company-os/worktrees/native-sbx-001-contract-validators
BRANCH: feature/native-sbx-001-contract-validators

## Demonstrated cause and correction

ROOT_CAUSE: CONFIRMED. `_file_entries` used `validate_path`, which applied lexical
and runner-write restrictions. That is not the C4 snapshot export policy.
Prediction: complete, correctly hashed requests containing AGENTS.md,
.agents/skills/code-review/SKILL.md or scripts/run-writable-agent.ps1 would pass.
Falsifier: a pre-fix rejection on export admissibility.

Actual pre-fix replay: the three newly added negative tests all FAILED with
`DID NOT RAISE ContractError`; 236 original tests were deselected. This confirms
the reported acceptance, not merely a hypothetical path-parser weakness.

Classification: REPAIR. `_file_entries` now obligatorily uses
`validate_snapshot_path`, applying a separate fixed trusted export policy after
the existing safety checks. Frozen reproduction tests are unchanged and now pass.

EXPORT_POLICY_DECISION: reserved directories/names at any depth cover governance,
runtime scripts, docs/control artifacts, schemas/templates, CI/editor settings,
cloud/SSH/tool credentials and privileged configuration. Additional reserved
roots cover governance, policies, broker, runtime/services/config and deployment.
Whole reserved trees are conservatively excluded. Matching covers Windows
uppercase aliases such as dotless-I. Exact lists are in the validator and the
revision-2 contract documentation.

No exceptions are implemented. A manifest's policy ID/hash/profile cannot relax
the profile, and arbitrary exception fields remain rejected. Future exceptions
require separately reviewed trusted host policy. No JSON fields, IDs, hashes,
snapshot encoding or receipt validation were changed.

## Files and source manifest

Three existing files modified, one successor handoff added. The original handoff
and package initializer remain byte-for-byte unchanged.

| Path | Revision | SHA-256 | State |
| --- | --- | --- | --- |
| src/company_os/sandbox/contracts.py | correction 1 | 844e938b252f1a3d23e0f8a1bb98dec8d271ea2ef366451b1ce1a58340f93c1d | uncommitted/untracked |
| tests/test_native_sandbox_contracts.py | correction 1 | 3fef0d9dfff2cd704815b444f6f7fe3fbca80da75d947c5f2039ad67979ecfe8 | uncommitted/untracked |
| docs/engineering/native-sandbox-contract-validators.md | 2 | e105614b1611363f46c3c1fa3a884336deeaf33868f1ba3ce01e777dc1696003 | uncommitted/untracked |
| src/company_os/sandbox/__init__.py | 1 | 858dd8118ca97dd6faf62f39fa122b41bc894451f0894fb83dce129e75e41c6c | unchanged/untracked |
| docs/engineering/handoffs/ai-company-os/native-sbx-001-contract-validators-2026-10-15.md | 1 | ad3a3a3416c482a96c4343eeea9127627d0526d6dee0138d3c63c574377859b1 | unchanged/untracked |

This successor is also a new untracked file; self-hash intentionally excluded.

## Regressions and results

NEGATIVE_REGRESSIONS: complete requests containing all three review examples;
nested and mixed-case governance; CI/editor/cloud/SSH settings; reserved control
roots; aliases including dotless-I; manifest policy claims and injected exception
fields. Bytes and hashes are synthetic, internally consistent and never executed.

POSITIVE_REGRESSIONS: complete requests for source code, application-local config,
tests, fixture data, NFC Unicode product filenames, package.json, pyproject.toml,
requirements.txt and similarly named non-reserved files. Legacy write-path API
semantics are preserved while request export becomes stricter.

Original test prefix SHA-256 verified unchanged:
49138be3083ab68fa01c457e14d096584b15c774cb1f73809e4025a08cd53588.
All 236 original scenarios remain; 88 cases were appended.

| Runtime | Targeted suite | Duration |
| --- | --- | --- |
| Python 3.11 | 324 PASS, 0 FAIL | 0.59 s |
| Python 3.12 | 324 PASS, 0 FAIL | 0.60 s |

Executed only tests/test_native_sandbox_contracts.py with Python -B, pytest -q,
-p no:cacheprovider and private worktree temporary directories, removed afterward.
No full runtime/product suites or adversarial host experiments were run.

## Remaining limitations and next action

REMAINING_LIMITATIONS: fixed name-based exclusions cannot identify secrets or
project-specific control content renamed into ordinary product files. Future
trusted export classification and filesystem metadata checks remain necessary.
Reserved product scripts/docs require a later explicit trusted-policy design;
there is no automatic exception. Data validation does not authenticate a broker,
prove actual cleanup or enable runtime execution.

SKILLS_SELECTED: bug, code-review
SKILLS_APPLIED: demonstrated reproduction, cause confirmation, scoped repair,
same-signal replay, synthetic regressions and local static review. No independent
audit is claimed.
SKILL_SOURCES: .agents/skills/bug/SKILL.md; .agents/skills/code-review/SKILL.md
SKILL_SELECTION_REASON: repair the reproduced export-policy omission and review
its rejection boundaries without changing execution or authorization contracts.

READY_FOR_INDEPENDENT_REREVIEW: TRUE
NEXT_EXACT_ACTION: independently review this uncommitted correction.
COMMIT_CREATED: FALSE
PUSH_PERFORMED: FALSE
MERGE_AUTHORIZED: FALSE
WRITABLE_ENABLED: FALSE
