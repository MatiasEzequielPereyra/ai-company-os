# Single-Attempt PR71 external review corrections

Project: AI Company OS
Revision: 1
Updated: 2026-10-10T19:37:02.4228668Z
Updated by: CODEX-ORCHESTRATOR
Receipt: PENDING
Next owner: External Orchestrator
Predecessor: single-attempt-provider-execution-v1-implementation-2026-10-10.md

## Authorization receipt
Human PR71 REQUEST CHANGES authorizes narrowly correcting preflight output preservation, reconciling actual main, deterministic full verification and pushing existing PR71. No providers, Run A continuation or merge. Prior published handoff remains immutable. Shared derived pointer restored exactly to main to avoid competing ownership.

## Source and decision
Previous HEAD: ef6dc0ab033de6e87de8b7718c400c240ff61796.
Verified GitHub and fetched main/base: a724464232025f953630ad6abdb2dba172b62e89.
Local merge incorporates main without changing Error Intelligence relative to that base.
Root cause: initial cleanup and outer catch both deleted caller output on rejected configuration. Configuration validation now precedes cleanup; a local authorization flag guards catch cleanup. Valid configurations retain stale output cleanup. Gate lease, validators, default repair/fallback, Grounding and Citation Spans unchanged.
Router raw SHA256: 38F466F494AC499BDB381D04CB189AA771D54B8C3573AF942A42388C3E2A737E
Regression raw SHA256: DB307CB6C0B4FA247790223A76F381133F89927353FC4329083F2C454DABF4E0
Source revisions: UNKNOWN; Git identities above.

## Verification
SingleAttempt focused: WinPS5.1 and PS7 294 assertions PASS.
Regressions added: existing output Auto rejection, invalid model, missing OpenRouter endpoint; exact SHA preserved, journal attempts_started=0, transport spy0; valid configured call clears stale output and invokes once.
WinPS full smoke: 68/68 PASS,102.31s.
Python full: 238 PASS,1 SKIP,102.60s; deterministic TUI tests included.
Npm: 2/2 PASS.
Packed installed new/install/update E2E: PASS.
PS7 full smoke: FAIL preexisting test-new-project-contract, generated must be string. PS7 Gemini engineering-plan compatibility: FAIL preexisting array contract. Failures retained; baseline reproductions in predecessor evidence. PS7 Citation Spans and provider-router contract PASS. Initial targeted batch stopped on a wrong filename; corrected verified filenames then executed explicitly.
Logs and exact package: Z:\repos\ai-company-os\temp-tests\single-attempt-pr71-corrections.
Frozen fixture/preflight evidence: 340 hashes unchanged.
Historical sixth maintenance-lease regression remains insufficient proof; no 6/6 claim.

## Delivery
Final SHA and GitHub CI are supplied in external delivery after publication.
Blockers: documented PS7 baseline failures; no scoped defect identified.
Next exact action: External Orchestrator re-review PR71 correction, reconciliation, CI and retained baseline failures. Run A HOLD. No provider call or acceptance advancement.