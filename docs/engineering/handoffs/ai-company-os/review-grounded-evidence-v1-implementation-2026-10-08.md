# Review Grounded Evidence v1 — implementation checkpoint

Project: AI Company OS
Revision: 1
Updated: 2026-10-08T19:45:48Z
Updated by: CODEX-ORCHESTRATOR / implementation specialists
Status: IMPLEMENTED — DETERMINISTIC VALIDATION PASS — EXTERNAL REVIEW PENDING
Receipt: PENDING
Next owner: External Orchestrator
Predecessor: [maintenance writer architecture stop](review-grounding-maintenance-writer-stop-2026-10-07.md)

## Identity and authorization receipt

- BASE_SHA: `62485cdc7de9d3bc01b0aed4a1d5e7e710365fc9`.
- BRANCH: `fix/review-grounded-evidence-v1`.
- WORKTREE: `Z:\repos\ai-company-os\worktrees\review-grounded-evidence-v1`.
- FINAL_SHA: supplied in the final delivery/PR; this pre-commit immutable document does not embed its own commit SHA.
- Remote main rechecked unchanged immediately before publication. No reset/rebase or new baseline.
- Human authorization: implement frozen Review Grounded Evidence v1, deterministic regressions, packaging and release validation; preserve the existing implementation through both resolved architecture stops. The user reiterated continuation on 2026-10-08.
- Architecture authority: [frozen design](../../../architecture/REVIEW-GROUNDED-EVIDENCE-DESIGN.md), supplemented by the two explicit human architecture resolutions. Its historical PROPOSED label is not a new authorization requirement.
- Original implementation attachment `c72b669a-8160-4bad-9651-272abeea28b5/Texto pegado.txt`: SHA256 `270930897faddd1ab1d5147cbebe21b925c970bb9f67f742e505d07d92b66462`.
- First resolution attachment `371eecd4-cd7e-4b44-aea8-be5b1cf408da/Texto pegado.txt`: SHA256 `45bbc07f60abec18b837e853cdb0bb990859e907777c5afc11c8adfe48849be3`.
- Second resolution attachment `0545437e-86dd-4fff-8fd1-e921cce12023/Texto pegado.txt`: SHA256 `524909394c00ccadc80b71c38c5d951357530a8967e15fa20c4dc66f9072c87a`.
- Retained restrictions: no real providers, Headless Run A/B, historical evidence edits, TUI/Web UI production changes, provider ordering or free/paid changes, or merge. Repository publication submits implementation for review; it does not grant merge permission.

## Architecture and competing-writer audit

The approved per-task lock alone did not coordinate shared framework writers. Forced installation was reproduced replacing the CTO role under a live GATE lease; the second resolution authorizes the project barrier below. All confirmed participating writers fit either task coordination or exclusive project maintenance. No materially different synchronization architecture was introduced.

PROJECT_BARRIER_MODEL: persistent `.codex/runtime/locks/project-maintenance.lock`; OS-backed FileStream sharing. Normal task acquisition is PROJECT SHARED → TASK EXCLUSIVE; release reverses it. Shared uses read access/FileShare.Read; maintenance uses read-write/FileShare.None. Different task shared leases coexist. Acquisition fails fast, and failed task acquisition releases its project lease. Neither lock-file enumeration nor metadata proves ownership.

PROJECT_BARRIER_PARTICIPANTS:

- Task runtime: `run-agent-task`, `run-gate-agent`, `run-writable-agent`, `finalize-task`.
- Nested/task writers: `update-task`, `advance-task`, `submit-task-result`, `review-task`, `qa-task`, `security-task`, `dispatch-ready-tasks`, `new-task`, engineering backlog generation/materialization/reconciliation, and plan materialization. Readiness mutations delegate to the participating advance primitive.
- Maintenance: existing-project install, both normal and Force; runtime update; encoding repair APPLY. Read-only encoding inventory does not acquire maintenance ownership.
- Nested ownership is the same registered process-local lease/reference/live stream. Fabricated, mismatched, copied and expired ownership is rejected. No skip flag or unrelated reentrant lock.
- Maintenance takes exclusivity before authoritative target reads and retains it through preflight, apply, backup/rollback, synchronization and completion. Package-owned helpers coordinate against the same target path even while replacing target runtime scripts.

INSTALL_CONTENTION_REGRESSION: forced/non-force install rejected under a real held GATE lease; contract, runtime and manifest hashes unchanged; original ownership remained live. Includes independent-process installation.

UPDATE_CONTENTION_REGRESSION: updater rejected under held execution; runtime/schema/config/manifest unchanged, including independent-process update.

PARALLEL_TASK_REGRESSION: two distinct task exclusive leases simultaneously hold their project shared leases.

MAINTENANCE_EXCLUSIVITY_REGRESSION: maintenance excludes new tasks and other maintenance; release permits subsequent acquisition; stable file is retained; fake/inherited mismatch rejected.

UPDATE_ROLLBACK_LOCK_REGRESSION: actual updater failure after apply uses a test-only Copy-Item interceptor; rollback retains the original exclusive lease, rejects competing task/maintenance acquisition, and restores exact pre-apply hashes. No production failure hook.

PACKAGE_BARRIER_COMPATIBILITY: helper/schema are in new/install/update inventories and npm allowlist. Generated and installed projects verify exact source hashes, managed ownership and actual shared/exclusive contention. Packed update restores deliberately drifted grounding helper, lock helper, Review schema and router.

LEGACY_UPGRADE_BOUNDARY: the first upgrade from a pre-barrier runtime requires operational quiescence. Old execution helpers cannot retroactively honor the new barrier. The invariant holds once the barrier-aware runtime is installed; non-force installation preserves existing ownership/collisions. No task-lock scanning is presented as synchronization. External/manual mutations remain outside participating coordination and require the snapshot/raw drift guard.

## Grounding implementation

- Snapshot/manifest: module-private registered context; detached public manifest copy; frozen JSON/digests verified. Canonical task, owner role, dispatch, latest numbered result, primary report/candidate, candidate registration and full changed/deleted inventory are captured. Task result is secondary, never positive delivery proof. Caller/property mutation cannot manufacture trusted snapshot ownership.
- Normalization: strict UTF-8; remove only leading BOM; CRLF/lone CR become LF. Preserve whitespace, Unicode and trailing LF. Raw and normalized SHA256 plus byte/line identities come from the same captured byte stream. Raw drift still invalidates an invocation when normalized text is identical.
- Obligations: literal role `## Output` and canonical task `## Acceptance Criteria`, frozen supported bullet/checklist syntax and ordinal IDs incorporating declaration path/section digest/order. No Responsibilities/Objective synthesis or keyword completion. Malformed, duplicate, unsupported, empty or scaffold-only sources fail closed. Only exact shipped CTO ADR declaration/hash/ordinal admits conditional assessment, with exact authority ID, rationale and primary applicability facts.
- Review schema: portable v1 version/snapshot/assessments plus existing fields; exact IDs, statuses, rationale, primary artifact IDs, integer line ranges and excerpts. No provider-specific citation format.
- Semantic validator: complete exact obligation coverage; no duplicate/unknown IDs; primary-only citations; byte-exact normalized locator excerpts; conditional authority; limits; APPROVE contradictions; concrete negative findings. Invalid APPROVE is never coerced to CHANGES_REQUIRED.
- Router: same registered snapshot through the existing one same-provider repair and allowed fallback; canonical schema rechecked after transport adaptation. Codex receives the frozen context explicitly. Provider order, credentials policy, free/paid policy and unrelated workloads are preserved. Unfit protected evidence fails before provider invocation; nothing is clipped or dropped.
- Pre-intake: schema and grounding validation rerun, including raw source digests, latest result membership and candidate Git/inventory identity. Registered validation token binds result digest, same live GATE lease and recommendation; registered intake receipt guards REVIEW→QA/READY.
- Canonical intake: Markdown plus grounding audit sidecar. Structured missing outputs/defects and UNSATISFIED declarations/rationales are inside `## Findings`, so the real corrective envelope preserves them. Destination containment/reparse checks occur before writes; CreateNew preserves history; sidecar publication failure removes only this invocation's newly created Markdown. Scalar/legacy ungrounded intake and direct lifecycle bypass are rejected.
- GATE continuity: project shared/task exclusive remain held across preparation, snapshot, provider, repair/fallback, drift check, artifacts and lifecycle; actual nested intake tests retain the exact original task and project streams.
- QA/Security/DevOps materialization: first AC preserves the literal engine-owned role objective, then existing scaffold; ordinary v1 IDs. PM/CTO/EM contracts unchanged. Unknown/no-mapping planning role is rejected before any batch task write. Existing backend/frontend structured backlog criteria remain ordinary obligations.

## Limits, sanitation and semantic boundary

Ceilings: 64 obligations; 20 primary artifacts; 3 citations per assessment; 16 lines/2048 UTF-8 bytes per excerpt; 32768 aggregate excerpt bytes; source read cap 5 MiB plus existing candidate policy and effective provider/hardware context budgets. Excess fails visibly, never shrinks coverage.

Calibration: PM/CTO/EM each 7 Output declarations, max declaration UTF-8 lengths 20/30/28 respectively; six other shipped roles have no Output. Incident has 11 obligations (CTO 7 + task 4). Actual normalized report is 1366 bytes/6 lines, max physical line 1308 bytes; task 1343/38/max888; role2556/105/max140. Long unneeded physical lines remain intact; selecting an excerpt beyond locator ceilings fails. These measurements do not certify model capability.

Sanitized incident: [fixture provenance](../../../../test-project/fixtures/review-grounding-incident/provenance.json) records five original/sanitized raw hashes and relative extraction locators. Actual incomplete primary, false-complete result, legacy message.content approval and literal task requirements retain the contradiction; no hidden reasoning, endpoints, credentials or absolute incident paths. Task metadata is explicitly reconstructed REVIEW for isolated replay. Directory Git attributes enforce LF to preserve exact sanitized hashes on Windows checkout. Historical originals remain untouched.

Rejected attempts: `.codex/runtime/rejected-review-attempts/<guid>.json` retains only version, snapshot/manifest digest, provider, phase, typed error and rejected output hash. No raw response/prose, excerpts, model/endpoints, secrets or hidden reasoning; repair feedback excludes the old provider payload. These diagnostic records are separate from canonical history and retained until operator removal; no automatic retention scheduler was added.

Limitations: genuine but semantically irrelevant primary quotes can pass provenance; deterministic tests do not prove architecture quality/completeness or provider honesty. DELETE-only/binary evidence has no supported positive text locator in v1 and fails closed rather than inventing authority. Real-provider semantic evaluation/TUI certification NOT_RUN and NOT_AUTHORIZED.

## Exact validation and deviations

All commands below ran from the WORKTREE above. Logs: `Z:\repos\ai-company-os\temp-tests\review-grounded-evidence-v1-validation-2026-10-07` (continued through 2026-10-08).

1. Focused new tests: writer/barrier first, then parser/evidence/materializer/router. Six initial scripts PASS. Dedicated grounding six: primitives29 + evidence58 + incident15 + materialization22 + intake18 + router28 = 170 assertions per runtime.
2. Existing relevant regressions: 15/15 PASS (Review, final gates, dependency refresh, code-change flow, corrective analysis, role deliverables, provider reliability, evidence/context, semantics/identity, intake/profiles/dispatch, candidate provenance).
3. Sanitized real incident: actual intake/lifecycle, 15 assertions PASS.
4. Complete [A–Z map](../../../../test-project/tests/REVIEW-GROUNDING-MATRIX.md): 10 scripts in each Windows PowerShell5.1 and PS7, 20/20 PASS; dedicated assertions 170 each/340 total. Both actual lock layers and implementation candidate tests included.
5. Packaging/new-project: Windows PowerShell new-project/npm contracts PASS; package existence/hash/ownership/real barrier assertions; PS7 npm contract PASS.
6. `powershell.exe -NoProfile -ExecutionPolicy Bypass -File test-project/tests/run-all-smoke-tests.ps1`: 66/66 PASS, 85.28s. Validation process TEMP/TMP canonicalized via `[IO.Path]::GetFullPath`.
7. Bundled Python3.12, PYTHONPATH=worktree/src plus existing `temp-tests/python312-deps`, `python -m pytest -q --basetemp <owned external pytest-final-2026-10-08-2>`: 204 PASS, 86.45s. Focused two migrated TUI fixture tests: 2 PASS, 65.06s. Production TUI untouched.
8. Release version contract PASS at0.1.1; `python -m compileall -q src/company_os` PASS; `npm test` 2/2 PASS; `npm pack --json --ignore-scripts --pack-destination <owned candidate-release>` and `pwsh -NoProfile -ExecutionPolicy Bypass -File test-project/tests/test-npm-package-e2e.ps1 -TarballPath <exact tarball>` PASS. Actual installed new/install/update, package-local Python/TUI import, collision/user-file preservation, runtime restoration and barrier assertions.

Exact tested tarball: `candidate-release/pereyram-ai-company-os-0.1.1.tgz`; SHA256 `b8c1d67613623aab7b005c3f7f5a135bfbd51698b42e659095a4727fa8bb5ab2`.

`git diff --check`: PASS before publication. Final clean-checkout pack, checkout byte-preservation probe, commit/push/PR and GitHub CI are reported with this immutable checkpoint in the external delivery, after its own commit exists.

Failures were not hidden:

- WinPS TEMP 8.3 alias mismatch in live vs registered task lock path: reproduced, canonicalized before live path construction, regression added; affected existing tests now PASS.
- Selective orchestrator fixture omitted lock helper; static contracts expected old direct semantic/lock/Role invocation or mistook BOM-only Substring for clipping; updated to verified scopes/context/splats, with real functional regressions retained.
- Transition guard and two Python TUI adapters fabricated legacy Review: migrated to the actual test helper/snapshot/intake; no receipt fabrication or lifecycle bypass. Initial Python202PASS/2FAIL → focused2PASS → full204PASS.
- Default host TEMP short path cannot be resolved by the existing child Codex runner and package E2E Push-Location. Canonical long TEMP/TMP environment makes both pass; no unrelated provider/product changes. First package failure occurred before product execution; same exact tarball passed afterward.
- Extra PS7 new-project probe fails `$.generated must be a string` due existing ConvertFrom-Json timestamp conversion. Reproduced with exact BASE validator/schema; WinPS passes same inputs. No unrelated production fix. Full WinPS release workflow is PASS; no claim of full PS7 project-validation PASS.

## Preservation and next action

No historical tasks, role contracts, acceptance fixtures or evidence were edited. No production provider config/order/free-paid, UI or lifecycle model change. Headless Run A and Run B were NOT resumed; no real provider calls or new acceptance runs. No merge.

NEXT_EXACT_ACTION: External Orchestrator reviews this implementation, the source manifest, PR diff and final checks. Merge only after separate explicit authorization; then separately authorize any real-provider semantic evaluation or acceptance continuation.

## Source manifest

Hashes below identify exact local source bytes at publication, including untracked sources, plus the frozen design. They are not normalized Git blob hashes; ordinary runtime checkout line endings can differ. Files without explicit document revision have Revision UNKNOWN. Self-hash and subsequently updated derived state index are excluded.

| Source | SHA256 (raw local bytes) |
|---|---|
| .codex/agents/cto.md | b22a27a23c822127f08174af30e1390c6b0b65f930c5d0a11e83b1ebee356360 |
| .codex/agents/engineering-manager.md | f73d4774708398384036bb4385dfef37f171b6db824a0468f0440fc460bcedf7 |
| .codex/agents/pm.md | 4164a0d4b8bb48e5e523960d26fa6a0710f20e92c444e9dcfecdfdda22871547 |
| docs/architecture/REVIEW-GROUNDED-EVIDENCE-DESIGN.md | f41ee7ec2adc2e9d20ac804c10233eb1b648990cf9c1766b0671a3de293a366e |
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
| test-project/fixtures/review-grounding-incident/.gitattributes | a79691a93b46e49ce460c26ef22afcc03d6eca1e63bf2edbc20e96159510f6c9 |
| test-project/fixtures/review-grounding-incident/cto-role.md | fccfbe0c54d8213f3eb497075495a90452f1ab5e9620d9c88f5a4776939d614e |
| test-project/fixtures/review-grounding-incident/legacy-approval.json | 8ca44bffe8a9b92784433deda5121aeec31e3e36438c7501b63c8f860b7ebda0 |
| test-project/fixtures/review-grounding-incident/primary-report.md | 24e9b52d6e1b9e7f4ce9b33ab8d70076303f27ae63ba528ce56bd9679dbf74d4 |
| test-project/fixtures/review-grounding-incident/provenance.json | 4d2fdae7f8f5e041b02518e35dc64b77c76e0e1841f59e8ab65b85519b890789 |
| test-project/fixtures/review-grounding-incident/README.md | e44057de80d137792ae945b09990496628f2a75266ebda3423325e5e2800b73f |
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
| test-project/tests/test-project-maintenance-barrier.ps1 | bd5aae7475608c50af32f1570a54809fbff8a6a879ec4ef14c2257e50f2f0d1f |
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
