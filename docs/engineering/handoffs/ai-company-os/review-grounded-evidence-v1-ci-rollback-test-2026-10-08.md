# Review Grounded Evidence v1 — CI rollback test successor

Project: AI Company OS
Revision: 3
Updated: 2026-10-08T20:03:58Z
Updated by: CODEX-ORCHESTRATOR
Status: IMPLEMENTED — LOCAL VALIDATION PASS — FINAL CI PENDING
Receipt: PENDING
Next owner: External Orchestrator
Predecessor: [checkout preservation successor](review-grounded-evidence-v1-checkout-preservation-2026-10-08.md)

## Authority and unchanged implementation

Continue the same authorized implementation and branch, preserving both published predecessors. Their authorization receipts, frozen design, implementation details, project barrier fields, calibrated limits and complete validation records remain applicable.

BASE_SHA: `62485cdc7de9d3bc01b0aed4a1d5e7e710365fc9`
BRANCH: `fix/review-grounded-evidence-v1`
WORKTREE: `Z:\repos\ai-company-os\worktrees\review-grounded-evidence-v1`
PREVIOUS_HEAD: `0133a5d77fe9a846a4b3be119ec0a2489b95cd2e`
PR: https://github.com/MatiasEzequielPereyra/ai-company-os/pull/67 (draft)
FINAL_SHA / final CI: supplied in the external delivery after publication.

## Confirmed CI failure and correction

On previous head, smoke run37835422219 and release run37835422110 failed at test-project-maintenance-barrier.ps1: `Updater did not enter real backup restoration.` Python3.11/3.12 and CodeQL passed. These failed runs are retained, not described as green.

The test compared lexical Copy-Item destination paths. Apply uses joined paths, while rollback canonicalizes destinations with GetFullPath. A deterministic equivalent `./scripts/advance-task.ps1` path reproduced the original callback failure even though the updater restored every snapshot hash. This establishes an instrumentation defect; production updater and lock implementation remain unchanged.

The corrected test deliberately retains that path variant, canonicalizes intercepted source/destination identities, records the exact original backup path, verifies its original-byte hash before restoration, and keeps both task and maintenance exclusion assertions during rollback. Final full snapshot equality and post-release acquisition assertions remain required. No assertion is relaxed.

UPDATE_ROLLBACK_LOCK_REGRESSION: PASS in WinPS5.1 and PS7, including real backup restoration and exclusivity under filesystem failure. Logs: Z:\repos\ai-company-os\temp-tests\barrier-ci-old-pathvariant.log and barrier-ci-new-pathvariant-{winps,ps7}.log.

## Validation

Focused corrected barrier: WinPS5.1 PASS; PS7 PASS.
Full Windows PowerShell command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File test-project/tests/run-all-smoke-tests.ps1`, with canonical long TEMP/TMP. Result: 66/66 PASS,81.64seconds. Log: Z:\repos\ai-company-os\temp-tests\review-grounded-evidence-v1-validation-2026-10-07\full-powershell-smoke-ci-correction.log.

Prior unchanged-code validation remains: dedicated170 assertions/runtime (340 total), A–Z20/20 scripts, relevant15/15, Python204/204, focused Python fixtures2/2, npm2/2, compile/version contracts and installed packed new/install/update E2E PASS. Final CI reruns all configured jobs. No additional local Python run for this test-only correction.

Test/docs are excluded from npm package payload. Tested exact tarball SHA256: `b8c1d67613623aab7b005c3f7f5a135bfbd51698b42e659095a4727fa8bb5ab2`; committed final package identity is checked externally.

All75 predecessor source hashes verified; only the authorized test changed. Main independently remains BASE. `git diff --check` PASS. Published predecessors unchanged. Final clean status, commit, push and CI are reported externally.

No real providers, historical fixture/evidence mutations, Headless Run A/B continuation, new acceptance runs, production TUI/Web changes, provider order/free-paid changes or merge.

NEXT_EXACT_ACTION: complete final CI on this PR, then External Orchestrator reviews current manifest, implementation checkpoint and final diff. Merge and real-provider/acceptance execution require separate authorization.

## Current exact source manifest

Raw local source bytes. Revision UNKNOWN where absent. Self-hash and subsequently updated derived index excluded.

| Source | SHA256 (raw local bytes) |
|---|---|
| .codex/agents/cto.md | b22a27a23c822127f08174af30e1390c6b0b65f930c5d0a11e83b1ebee356360 |
| .codex/agents/engineering-manager.md | f73d4774708398384036bb4385dfef37f171b6db824a0468f0440fc460bcedf7 |
| .codex/agents/pm.md | 4164a0d4b8bb48e5e523960d26fa6a0710f20e92c444e9dcfecdfdda22871547 |
| docs/architecture/REVIEW-GROUNDED-EVIDENCE-DESIGN.md | f41ee7ec2adc2e9d20ac804c10233eb1b648990cf9c1766b0671a3de293a366e |
| docs/engineering/handoffs/ai-company-os/review-grounded-evidence-v1-checkout-preservation-2026-10-08.md | 6746faacba0667e13fa0b16f260d097ed3ee9200d526e56bfa5a7f2687cf691a |
| docs/engineering/handoffs/ai-company-os/review-grounded-evidence-v1-implementation-2026-10-08.md | b9b98cc7e861fcd5dda38200f84877d07d0188a9cff0067bf2f009ffb9640c57 |
| docs/engineering/handoffs/ai-company-os/review-grounding-maintenance-writer-stop-2026-10-07.md | 3429dc4cfad614c7011db1642bfff56ac5195d7524f3918ca75aebd3c518e794 |
| docs/operations/update-ownership.md | 247b79fc42e6d55fec2442fed4291b8ca17f77aa59655820f7bacb84531efda7 |
| schemas/review-result.schema.json | 236a582dbf325409f4df79878307c1ec30884e757517fe202c973dedca2e7eb7 |
| scripts/advance-task.ps1 | 3f95e795e5203a1500b6cf385b59b8ef67aa20a13aa249a0511611ce79204259 |
| scripts/dispatch-ready-tasks.ps1 | ad36b1ecf3642a1b6efe7d27ad58b70c0624ad31e1f8c102e48e754685413ea4 |
| scripts/finalize-task.ps1 | 896ff1be23d940b126a1e37818a39abd90f1e52c8006570accb8743c0bf7c948 |
| scripts/generate-engineering-backlog.ps1 | 21c7a987b00f48ffa47b10427e88261197313de8af8e32303a1634cce1fa2b8a |
| scripts/install-existing-project.ps1 | 7c6b4baa5122f4b9c33d885a2623a1b6e4d1359c64d671fdb1e6511603428ca4 |
| scripts/materialize-engineering-backlog.ps1 | b55694845b07d35bd454e09519539a0a2e988022aa442ec1de3687c56e7c1835 |
| scripts/materialize-plan-tasks.ps1 | 695a12e528106398409872497c5ff3d467e4a312a946252e8bd801129c0b3451 |
| scripts/new-project.ps1 | f599a2a8db65a4aa5ea511a75cc29ec28942a12ec7835afe97150e65e3d3f363 |
| scripts/new-task.ps1 | 44c3fa38d10c0950995321bb9012c9fb2b1c33c1475f1cd361dfe99cebfa10d5 |
| scripts/provider-router.ps1 | 10523059af2a27c63a7a1b13b5e9aee45a36120cf3368beb6da65752ec2a46ab |
| scripts/qa-task.ps1 | 2439aae1005e6a029f80e756a6b822895e9c43346a4d05321548463c9218904c |
| scripts/reconcile-engineering-backlog.ps1 | a7b276bead970c99733ecad625e4163e726ddb5ac2dd4b5152df76ecbc8b87d7 |
| scripts/repair-artifact-encoding.ps1 | 8c4b6b7ca8c38c278a9e5255a70904ce504fc55be9b34626f63ae569cf6d9ce1 |
| scripts/review-grounding.ps1 | f51aa24a431780df248a6dd3ba3552630bcdb57468afa95c5a07e5be054e30d9 |
| scripts/review-task.ps1 | e44feceab6d01d67ea9f23245c6ed3a6472f9da69e509164fe799793551457b0 |
| scripts/run-agent-task.ps1 | b69ff73096c8b73e11d1517bb0105f6e0b3f2e5372ab3c497dab6c4d72ad7cdd |
| scripts/run-gate-agent.ps1 | 4d9af67f2724c41ca5de3f091be53c4c63f3d60baa20c5c0a520e45bb87232f0 |
| scripts/run-writable-agent.ps1 | 0471d4646c2766342970633dde410b7053ff80fbddbc46fc19f18f55c560b8ad |
| scripts/security-task.ps1 | cb656ed34ab6c84a705d89b67c0378fa177115f92e902101f1fd8d0604735834 |
| scripts/submit-task-result.ps1 | 7dc805d7574a9384825c24bc0835e4e37e27df3104f7d4490356b206f095e112 |
| scripts/task-execution-lock.ps1 | aa79248672f968e855defe90967cd822f5fcdf5c4885a629fa98ea7e6ef2f8a5 |
| scripts/update-runtime.ps1 | c7c532c7dbf5cb37497d02fc17ee19984d70438f959668dc9cff5905b374a194 |
| scripts/update-task.ps1 | 718c10a703118a202f0452ebd7faa60ca1a3b03761faa3df4c308fcbf4f075c6 |
| scripts/validate-gate-result-semantics.ps1 | 31d40489e38416989fa3912799c1a678cba2770f2f751ec1a535041505b0033d |
| test-project/fixtures/review-grounding-incident/.gitattributes | 74f87e207e3afa201b48083d91ed9e2c3ad19ecf225414a0653cbc3028cdbc77 |
| test-project/fixtures/review-grounding-incident/cto-role.md | fccfbe0c54d8213f3eb497075495a90452f1ab5e9620d9c88f5a4776939d614e |
| test-project/fixtures/review-grounding-incident/legacy-approval.json | 8ca44bffe8a9b92784433deda5121aeec31e3e36438c7501b63c8f860b7ebda0 |
| test-project/fixtures/review-grounding-incident/primary-report.md | 24e9b52d6e1b9e7f4ce9b33ab8d70076303f27ae63ba528ce56bd9679dbf74d4 |
| test-project/fixtures/review-grounding-incident/provenance.json | 4d2fdae7f8f5e041b02518e35dc64b77c76e0e1841f59e8ab65b85519b890789 |
| test-project/fixtures/review-grounding-incident/README.md | 7e9a3bcdc6e8101cbd1c0d01c3e9fea1aa2ca97b811ea5743c35d5524d5d8050 |
| test-project/fixtures/review-grounding-incident/secondary-result.md | 52a770cd3c08dcaf1094d2342c0862448acabc34c3cea398e5fe1cb5860aaec9 |
| test-project/fixtures/review-grounding-incident/task.md | 2eb6668941c90c0ab0c9e2356b3a786966d11988429aa64a04ab4f7c39ad7e5f |
| test-project/helpers/grounded-review-fixture.ps1 | 4f5ce90ff6d39df313ac93b56f59642f2b1e35f7e68b8b6ee6542e3ba55d9369 |
| test-project/tests/REVIEW-GROUNDING-MATRIX.md | 84478353c70855dffa2ad67ea0bfa096d02d9fbb5f822936830bf3fa1eb89633 |
| test-project/tests/run-all-smoke-tests.ps1 | 445d73245e6e123ac7814c46313149a02c7f9fe0bcdf245b34bd4c1834b6e2f8 |
| test-project/tests/test-agent-runtime-contract.ps1 | 3045a392948a2ac23e6873424c16eab8ba1af936f915ab566de19d45ee95aea9 |
| test-project/tests/test-corrective-analysis-reliability.ps1 | e32fe1dd1f75e2817c26e6492583c16a7f7109955bd16a9a954580d48be0feaf |
| test-project/tests/test-dependency-refresh.ps1 | dfb8f3edf4e09109ec70a1f6d28fba88d420db851911ab1c65abcbdacdc965b2 |
| test-project/tests/test-dispatch-engine.ps1 | 1995776c6b76994ac962fcb2e68f2b34aac4d016990668a5f04084ee1a72c769 |
| test-project/tests/test-end-to-end-code-change.ps1 | 9092701760916327b87a76f511bb5f2a9f68fb900946a0746f6620cd0c154e09 |
| test-project/tests/test-final-gates.ps1 | 88f7935f002cfced524efc82794ea460425a0e9be595a596a4dbc093c1fe68ae |
| test-project/tests/test-gate-artifact-identity.ps1 | cf39a8ec178998d48bb94f56119ee4056a78bf8060831dccb33cbba105d9aeb6 |
| test-project/tests/test-gate-authoritative-context.ps1 | bd51ff4e73fa1a26ed9e64f215739b11d54029d373ef22dfad8200d0eccc47f7 |
| test-project/tests/test-gate-evidence-preservation.ps1 | 106a302d918a433810350a2a829b62bf61a9511c2185a7fef8fdb3b512c4a559 |
| test-project/tests/test-gate-semantic-validator.ps1 | 1bd2af7d5138dad7af62531cc9974f12cd916fd8cef5c9dabbe131dfc4383c41 |
| test-project/tests/test-hardware-provider-reconcile.ps1 | 2618d328d75be175cb59de7e4313b8c102237b75c4d0471a3ddee4cff2048471 |
| test-project/tests/test-implementation-gate-candidate-context.ps1 | be23b07744e74ddb3af5645e3d07b2dee34d5ab1964ac16e4dd48c3dfa724851 |
| test-project/tests/test-new-project-contract.ps1 | cfc988ce90e7a6442769cd5cd22c9cfe9b6fc961caeae91fe48293d5594c617e |
| test-project/tests/test-npm-package-contract.ps1 | 40341a4bf8b0ce1d1edbe9a4173ef9c2ab3b338f1d8b33ee153f60286c316db7 |
| test-project/tests/test-npm-package-e2e.ps1 | 8e7ccae48e9ba26166cc073844dd75cd618f556d3d09651a52b7c128e672a13b |
| test-project/tests/test-orchestrator.ps1 | c2077cdfe9a19fdec504e754bd6e9bef3b146c0a36a55e51608b585f7ccacef9 |
| test-project/tests/test-project-maintenance-barrier.ps1 | 0c721d5d291726fca4d41ee19d2a49a580be7c9f8bd40a4a18c929a8d5e30bb7 |
| test-project/tests/test-result-intake.ps1 | edc07cc3b219e37c7cb9c83b1390ef5bbc18140585e9f3517df8dd77e842e5f3 |
| test-project/tests/test-review-engine.ps1 | c655cc658b2cc22294ee0ea1bbd9f0cf4630f7b4575f9e500749b57980876fbf |
| test-project/tests/test-review-gate-provider-reliability.ps1 | 685099740b9af062e3cd5a953805aea3dba660647e2dd145d91e2279d24a575a |
| test-project/tests/test-review-grounding-evidence.ps1 | 164c28ebbc092409facc5e45271bec5b66d954f23a1673b0f38a33fca34ca98d |
| test-project/tests/test-review-grounding-intake-preservation.ps1 | ab4e9df0898f5281d0e6d77b25a828d5b6482bebfe8a8535d5ec0af3046e7476 |
| test-project/tests/test-review-grounding-materialization.ps1 | 39aff334d1117278be709b4afcd6806f0ac0206be59d049bd6033f96d999d338 |
| test-project/tests/test-review-grounding-primitives.ps1 | 9e693dc8f077643a7311bd7fd5a0a2f43081a6832d55fdf5bad985b51a69d354 |
| test-project/tests/test-review-grounding-real-incident.ps1 | 1acdbbdf2618bf5626f3bda313492e66d405332c7d682d96995a87fda9958e54 |
| test-project/tests/test-review-grounding-router.ps1 | 99b58d4fe7630e6ca85659721d72e5d83e990de896f133d77c376b887ac30823 |
| test-project/tests/test-role-deliverable-gate-validation.ps1 | 53ad57e7f876de8fedba46d9c9979f2648604c058dc0f771e5d5917c54d53bb4 |
| test-project/tests/test-task-writer-lock-contract.ps1 | 5fea4bd8cf20e1678e31f23c69ccb25e7234cc87d4b066f55eb0087516217551 |
| test-project/tests/test-transition-guards.ps1 | 647cb5cc31bdf83e25bee561f367346c159751f4e7a78bcf274dafc08c7d95e7 |
| test-project/tests/test-workflow-profiles.ps1 | 0238fcdbf9e92e057b3cd1f4c57bd363aca3af9407cc7081e1d60b66459af283 |
| tests/test_tui_e2e.py | f597c0b2febd65e98f231fc275dee2c1c1540ecddf0a82d927aedf3616033d46 |
| tests/test_tui_objective_e2e.py | 5274d48b5d543fe88ffa72dd693819daa04762580768afd801a3f20f8def1a81 |
