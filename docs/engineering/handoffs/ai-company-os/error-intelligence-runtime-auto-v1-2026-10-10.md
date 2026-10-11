# Automatic Error Intelligence runtime integration handoff

Project: AI Company OS
Revision: 1
Updated: 2026-10-10T20:37:57.8443638Z
Updated by: CODEX-ORCHESTRATOR / Runtime Engineering
Receipt: PENDING
Next owner: User / External Orchestrator
Predecessor: error-intelligence-v1-completion-2026-10-10.md

## Authorization receipt

Human request: 'bueno armemos eso quiiero que funcione automaticamente'. Human separately approved 'Sí, validar con simulados' for deterministic tests and installed packed E2E. This authorizes connecting the previously isolated store to operational failure capture and diagnosis. The former isolated-v1 restriction on runtime integration is superseded for this new workstream. No real provider, acceptance continuation, historical evidence rewrite, existing project upgrade or merge was performed. Shared state pointers owned by other workstreams remain unchanged.

## Delivery and contract

Base: eebc633009b09b6cce354aecbf0dfa4938e90b41; freshly fetched main unchanged.
Worktree: Z:\repos\ai-company-os\worktrees\error-intelligence-runtime-auto
Branch: feature/error-intelligence-runtime-auto
Final commit / PR / CI: supplied in external delivery after publication.
Design: [runtime integration](../../error-intelligence-runtime-auto-v1.md).
Automatic typed capture through operational writer and analysis/gate/writable rejection boundaries; process launch/timeout capture; relevant same-project historical lookup; aico errors and doctor summaries. Existing SQLite schema1 unchanged. No memory-based action, auto-verification, provider prompt injection, or task transition is authorized.
Runtime discovery uses current installed Python/module, and a source SHA marker prevents unchanged-version packages retaining stale Python. Legacy markers refresh once. Source drift during installation aborts marker publication.

## Verification

Python full: 285 PASS,1 SKIP,115.16s, including deterministic TUI tests.
WinPS5.1 full: 69/69 PASS,108.38s. Automatic bridge regression29 assertions PASS.
PS7 automatic bridge:29 assertions PASS. SingleAttempt294 PASS; citation spans, grounding router/evidence/intake and provider router contract PASS.
PS7 full smoke FAIL at preexisting test-new-project-contract generated-string contract. Gemini engineering-plan compatibility FAIL at preexisting array contract. Failures retained without unrelated repair.
Npm:3/3 PASS including unchanged-version fingerprint regression.
Final installed packed E2E: PASS, real installed Python -> project operational writer -> temporary SQLite -> installed aico errors; two observations become one incident withcount2. Same-version source change reinstalls actual module bytes and refreshes SHA marker; new/install/update managed helper hashes/ownership checked.
Final tarball SHA256: 0b9483b2c950e325da3fe38882ecb9b95c8225e9e1eaddaF972092e110840157.
Evidence directory: Z:\repos\ai-company-os\temp-tests\error-intelligence-runtime-auto-validation; final package under release-runtime-refresh. Previous pack artifacts retained as superseded validation steps.
Independent final read-only review found no concrete blocker; original exceptions, project lease exclusion, credential projection, default provider retries/fallback, grounding and citation validation preserved.

## Historical integrity and limitations

Historical manifest comparison:339/340 exacthashes unchanged. Only the fixture .git/index differs. Its LastWriteTimeUtc2026-10-10T20:09:16.2808933Z precedes creation of this worktree2026-10-10T20:21:27.6722287Z. No index repair/reset performed. AICO-002 remainsREVIEW and Run A HOLD; no acceptance engine/fixture writes were issued. Historical sixth maintenance regression remains insufficient proof and was not changed or reclassified.
Direct standalone PS needs the packaged Python/module or explicit bridge environment; unavailable capture is visible and does not change execution behavior. Category-family matching does not prove common root cause. Manual fix verification still requires explicit evidence. New version requires normal installation/update in an authorized nonfrozen project; none was deployed here.

## Next exact action

Review the PR and CI, then authorize installing the updated package and applying aico update to the intended nonfrozen project. Do not update Run A or continue acceptance implicitly.

## Exact source hashes

Source revisions UNKNOWN unless recorded above. Raw worktree SHA256; self and shared derived index excluded.

| Source | SHA256 |
|---|---|
| docs/engineering/error-intelligence-runtime-auto-v1.md | 25157cd68c382f2811615b1579ea5f4fd81be3ea4fe0399403ecad6620fcdd35 |
| docs/engineering/error-intelligence-v1.md | c9624b44f19a5f604947373234cbc84578d132c1612cd3015fc50abe20b0c1d9 |
| npm-bin/bootstrap.js | c52c52b6920b7a709d3164ced02f45b198bce0c99f9659f8b39ba2c3d83d69e9 |
| npm-bin/package.test.js | b70d7d05c10de25ac8a09fb168a8d1430d531014975e1227f2e36572666761d3 |
| README.md | 7c9ceb7739fed216746a5c6223a26c71ad93e0d9944e4eae842235040cf83dbf |
| scripts/error-intelligence.ps1 | 488b45447a0ca025ff9acf697b25d6861b26b72dd269e5cd228fc00cac07c5f0 |
| scripts/install-existing-project.ps1 | b9cb571e409dfe5eb02bbcefa9c9070484ca4b06835b5fdad74153c3c6e51849 |
| scripts/new-project.ps1 | a563780a6b917f192a002a541cfef25e7ec6f5657559a861118c2adb91729b7c |
| scripts/provider-router.ps1 | a1aaff026c247e847a697b8a963f7d12c616d6eb879284ecee90cc876027270b |
| scripts/run-agent-task.ps1 | 8d0838e1bb98868b37637902d0a31009fc6f2108403e24933f6bcb996465e3d0 |
| scripts/run-gate-agent.ps1 | 95f9d0866c54ae4e50f11ade19f8eca49713ba3e6c350964beed9edc25366651 |
| scripts/run-writable-agent.ps1 | d988e01b9d8bdfa9162ba137ed24f58b500a29f9f93b1b901e91202158b307ef |
| scripts/update-runtime.ps1 | 99bd87427f1a7848ff194bcfa3b01df33d24611dd045d569d2d2ed5edeba3e89 |
| scripts/write-operational-event.ps1 | bb6d6d1ee458b20b39410d98a907dd3f2ef1325fc883058ca1bdcb58996cad14 |
| src/company_os/application/doctor_service.py | e6cd0832c75000bd0af27c17000d0826c16dbf74cdc472dd71263defa69bb53b |
| src/company_os/application/process_stream.py | 1b695ba5de8c4bde79e2b53d05aa228630bab9a2561ee5dc058175dca7c20a9e |
| src/company_os/application/provider_service.py | 7b4090fb94ab386844475929311a62624490dbd50971059e8ab0a3feeb40e30c |
| src/company_os/cli/app.py | 037e40e7a5fb0d46312bee1c8751db9391a458291fd8045b2b32786453b8aaf8 |
| src/company_os/error_intelligence/__init__.py | c143376ed525a0f718a5d5d327d7238f8ced204fee80ecc5c8558d7127ecf68c |
| src/company_os/error_intelligence/runtime.py | 2c25860b2e9409a694df602cfeb92fee5e18db7438bb32f075e2b30aa797c267 |
| test-project/tests/run-all-smoke-tests.ps1 | e356bd32a24ff28863a4b03c3169465d20cb6b3132bcfb5dad623488a1cdd185 |
| test-project/tests/test-error-intelligence-runtime.ps1 | e4e4637645daf1ab769f186f0a5ab6c60c5e1905b437edca53bdeffd2373415a |
| test-project/tests/test-npm-package-e2e.ps1 | 3d371e4fe50a3dae6514fb0a022d675cf80f3007992e9dc97ada6db3ab799e94 |
| tests/test_error_intelligence_application.py | 10157a12b0bc34f19fc49539d7aed40e214a6a566e2b665ebf85f74fed004b6c |
| tests/test_error_intelligence_runtime.py | ea7d061e0617de5e27d0dbf4e7bed9675a4b65bd167aad92f22518c904d4b669 |