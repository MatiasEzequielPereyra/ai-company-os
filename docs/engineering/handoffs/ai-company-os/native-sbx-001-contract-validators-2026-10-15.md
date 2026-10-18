# NATIVE_SBX_001_CONTRACT_VALIDATORS

Project: AI Company OS
Handoff ID: NATIVE_SBX_001_CONTRACT_VALIDATORS
Revision: 1
Updated (UTC): 2026-10-15T23:56:55Z
Updated by: Codex implementer
Previous handoff: NONE (first implementation slice)
Git base commit: 5ce38da9281ddb4baaef4654a35cad447979f8a1
Initial receipt status: PENDING
Recipient: External Orchestrator / independent reviewer

## Authorization receipt

Requester: human user, conversation instruction `IMPLEMENTATION SLICE 001`,
TASK_ID `NATIVE-SBX-001`, 2026-10-15.

Permitted: new clean branch/worktree from verified main; isolated implementation
of strict sandbox data validators and pure tests. Current instruction supersedes
the earlier general implementation permission only for this first delivery.

Retained restrictions: no commit, push, merge, PR75 changes, Run A changes,
writable enablement, candidate process execution, VM creation, privileged services,
provider calls, lock/authorization changes or local execution fallback.

## Identity

OUTPUT_ID: NATIVE_SBX_001_CONTRACT_VALIDATORS
BASE_SHA_VERIFIED: 5ce38da9281ddb4baaef4654a35cad447979f8a1
GitHub verification: compare main with codex/writable-auth-guard returned this
base and merge base before worktree creation.
WORKTREE: Z:/repos/ai-company-os/worktrees/native-sbx-001-contract-validators
BRANCH: feature/native-sbx-001-contract-validators

## Sources and changes

Contract sources: NATIVE_SANDBOX_P0_CONTRACT_V1 and
NATIVE_SANDBOX_P0_CONTRACT_AMENDMENT_V1 in the authorizing conversation.
Their repository paths/hashes are UNKNOWN: they were delivered as conversation
artifacts, not claimed as existing canonical files.

| Source path | Revision | SHA-256 | State |
| --- | --- | --- | --- |
| src/company_os/sandbox/__init__.py | 1 | 858dd8118ca97dd6faf62f39fa122b41bc894451f0894fb83dce129e75e41c6c | untracked |
| src/company_os/sandbox/contracts.py | 1 | 9f2e217920a21969e91f09acdcfb4716fa5c5b93b0979243d8249dbb7254ddb2 | untracked |
| tests/test_native_sandbox_contracts.py | 1 | 49138be3083ab68fa01c457e14d096584b15c774cb1f73809e4025a08cd53588 | untracked |
| docs/engineering/native-sandbox-contract-validators.md | 1 | 311e0cbe74f6e53fcd2ed1d64f6f2436977a0322f25230a409b54074b99251b2 | untracked |

This handoff is also a new untracked file; its own hash is intentionally excluded.
No derived company-state index was changed: this slice is confined to validators,
their tests and delivery documentation, and does not advance canonical tasks.

## Validation contracts

`validate_request`: exact UTF-8 JSON and SHA-256 envelope, strict object shapes,
canonical IDs, aware host time, safe Windows paths, NFC/UTF-16 bounds, aliases,
protected names, collisions, exact payload membership, file hashes, binary root
transcript, count/size limits and bounded command/resource records.

`validate_receipt`: strict JSON and hash envelope; request/identity/image/policy
binding; ordered result references; output sizes/hashes/budgets; boolean and exit
code types; matching separately supplied cleanup digest. Eligibility is data for
later host revalidation, never permission or a claim of genuine cleanup.

Full API and serialization profile are documented in
docs/engineering/native-sandbox-contract-validators.md.

## Tests and actual evidence

Only `tests/test_native_sandbox_contracts.py` was executed. It uses synthetic
bytes and one pytest temporary sentinel. No supplied candidate code is run.

Command profile: Python -B -m pytest tests/test_native_sandbox_contracts.py -q
-p no:cacheprovider --basetemp=<private temporary directory within this worktree>.

| Runtime | Final result | Tool-observed duration |
| --- | --- | --- |
| Python 3.11 | 236 PASS, 0 FAIL | 0.51 s |
| Python 3.12 | 236 PASS, 0 FAIL | 0.52 s |

POSITIVE_TESTS: exact-byte round trips, immutable data, independent binary hash
vector, empty snapshots/files, Unicode NFC paths, empty literal arguments,
20,000-file limit, 64 MiB file limit, 12 commands, 16 MiB aggregate outputs,
nonzero diagnostic exit and rejected sealed receipts.

NEGATIVE_TESTS: altered manifest/output bytes, wrong digests, extra/missing fields,
escaped duplicate keys, invalid types/nonfinite JSON, identity/version mismatch,
Windows device/ADS/UNC/traversal paths, aliases, NFC violations, case and Unicode
collisions, parent collisions, excessive counts/bytes/resources, wrong command
references, partial eligible results and unconfirmed/mismatched cleanup.

Earlier runs: bundled Python lacked pytest (NOT_RUN there); the first added
UTF-16 test used an incorrectly escaped fixture literal (1 FAIL / 224 PASS on
3.11), then was corrected to chr(0x1F680). Final results above are after that fix
and additional boundary tests. Production behavior was not relaxed for that fix.

Full product suites, PowerShell runtime suites, packaging, Hyper-V, monitors,
VSS and real cleanup certification: NOT_RUN, outside this slice.

## Security boundaries and limitations

SECURITY_BOUNDARIES_PRESERVED: run-writable-agent.ps1, Task Execution Locks,
authorization/Review Grounding/provider code, PR75, Run A and historical fixtures
are untouched. No operational imports, command execution or filesystem access
exist in the validator module; a dedicated AST regression covers that boundary.

LIMITATIONS: consistent hashes are not authenticated broker evidence. Registry
approval, live leases/authorization, metadata capture, actual cleanup and OS
confinement require later slices. Filesystem object types cannot be inferred from
bytes. A valid path still needs safe handles and root validation when materialized.
No sandbox runtime or execution readiness is claimed.

## Skills and next action

SKILLS_SELECTED: feature, code-review
SKILLS_APPLIED: feature; local static code review (not independent audit)
SKILL_SOURCES: .agents/skills/feature/SKILL.md;
.agents/skills/code-review/SKILL.md
SKILL_SELECTION_REASON: implement a new pure data-contract component and review
strict validation, failure cases and test coverage.

READY_FOR_INDEPENDENT_REVIEW: TRUE (this slice only)
NEXT_EXACT_ACTION: independently review the uncommitted files and contract profile;
do not start the next slice without authorization.
COMMIT_CREATED: FALSE
PUSH_PERFORMED: FALSE
MERGE_AUTHORIZED: FALSE
WRITABLE_ENABLED: FALSE
