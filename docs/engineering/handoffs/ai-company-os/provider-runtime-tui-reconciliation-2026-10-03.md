# Provider / Runtime / TUI historical reconciliation

Project: ai-company-os
Handoff ID: provider-runtime-tui-reconciliation-2026-10-03
Revision: 1
Updated by: Senior Runtime / TUI / Integration Engineer (Codex)
Previous handoff: NONE for this workstream
Initial receipt status: PENDING
Next owner: Orchestrator
Next permitted action: audit this PR; merge requires separate authorization.

## Authorization and isolation

Human request received 2026-10-03: audit historical provider/runtime/TUI capabilities,
restore only demonstrated regressions compatible with current policy, test, document,
commit, push and create PR. Preserve P1 and workload routing. No merge, real provider
calls, paid actions, historical import/cherry-pick, acceptance fixture edits, or
Acceptance Run #4 creation/execution. Canonical checkout is development read-only.

REMOTE: https://github.com/MatiasEzequielPereyra/ai-company-os.git
BASE_SHA: feb6448943d98863d41e105f84a0d6f8e3c92b51
Branch: fix/provider-runtime-tui-reconciliation
Worktree: Z:\repos\ai-company-os\provider-runtime-tui-reconciliation
Fetch/main state: canonical fetch origin succeeded; origin/main still matched the
authorized P1 baseline. Dedicated new branch/worktree created from that exact SHA;
initial `git status --short` was empty. Canonical checkout initially clean.

Final commit/PR and status evidence are recorded below after publication. A file
cannot contain its own commit SHA; FINAL_SHA identifies the audited implementation
commit, and the documentation commit containing this handoff is the PR head.

## Classification A–I

| Category | Current evidence | Historical evidence | Classification | Action | Tests | Remaining risk |
| --- | --- | --- | --- | --- | --- | --- |
| A ProviderService catalog | PS adapters/router and current provider-runtime matrix admit six providers; main Python only had two credentials and Codex | 0b70dd7c added DeepSeek/Grok mapping | REGRESSED — RESTORED | Structured capability view; four secure mappings; six visible statuses | provider_reconciliation catalog/mapping/AST adapter variables/negative drift fixtures | Runtime contracts must remain covered as new providers are added |
| B Providers TUI | Main had only OpenRouter/Gemini inputs, no equivalent surface for other supported credentials | e3c8b30f secure inputs/submit mappings | REGRESSED — RESTORED | Generate masked credential widgets from catalog; save/update/delete; generic failures, clear inputs, worker status inspection, i18n | 8 actual Pilot tests; no CLI/local credential inputs; no secret rerender; navigation during slow status | Real OS credential backend deliberately NOT_RUN |
| C Secure credential propagation | AgentControl/Writable hardcoded OpenRouter/Gemini; GateControl lacked secure-store injection | 4bcb10a3/d1029254 delivered general stored credentials | REGRESSED — RESTORED | Scope credentials by explicit provider or configured workload/role candidate set; remove ambient provider keys; writable free model filter; no keys in control/metadata subprocesses | Explicit analysis/gate/writable subprocess capture; role union; paid flag; forbidden writable; invalid config; mock secure store/log/status tests | Eligible Auto candidates share a parent subprocess; child adapter policy remains PS-owned |
| D Ollama local status | Main lacked Ollama status; executable detection alone is weaker than current resolver contract | 828ea62a displayed executable detection | REGRESSED — RESTORED | Resolver availability including service/model usability; no selected project means unverified; Codex remains CLI detection | ProviderService unavailable resolver fixture and LocalRuntimeService available/unavailable fixtures | CLI detection does not prove Codex account authentication; real Ollama metadata NOT_RUN |
| E LocalRuntimeService | Current resolver owns hardware/model/budget computation; no equivalent Python service | ed2f4432 Python resolver bridge | REGRESSED — RESTORED | Invoke/parse/validate/normalize only; bounded subprocess, safe failures, unknown hardware stays unknown; credentials removed | Deterministic JSON/error/timeout/empty/missing/contradictory/unavailable fixtures; cache/invalidation | Resolver/output evolution requires corresponding contract review |
| F Plan Control local runtime | Modern RuntimeService is organizational status; no equivalent hardware/model surface | 48df01fe runtime panel | REGRESSED — RESTORED | Current Static/Panel/theme/i18n; worker thread; active task/role/workload; gate reviewer roles; stale result suppression; F5 refresh | Pilot rendered fields, ES/EN, unavailable/slow resolver, gate stages/reviewer mappings/task changes/navigation | Local candidate diagnostic does not predict final Auto provider/fallback |
| G Writable Ollama context budget | Runner omitted Role/Workload; router constrained analysis/gate only, so writable hardware budget could be exceeded | e693aa46 ContextMaxChars cap and role/workload | REGRESSED — RESTORED | Reuse canonical budget and Limit-ProviderContext; min writable/provider/runtime; reject invalid resolver budget | New PS budget test hardware lower/higher, below/above/tiny context, invalid/unavailable/missing resolver, cloud isolation; runner role/workload assertions | Real generation quality and truncated-context adequacy await post-merge acceptance |
| H DeepSeek/Grok writable | Current runner ValidateSet and free-model policy exclude DeepSeek/Grok and Codex; local-first order intentional | e693aa46 broader historical writable; later 932572a/present operations policy supersede | INTENTIONALLY SUPERSEDED | No providers/order/policy restored; credentials grant no writable capability | Explicit forbidden providers; Auto ignores them even with fake keys/stale paid flag; capability AST parity; P1 paid fallback tests | Explicit supported cloud selections retain account/quota semantics |
| I stale configuration | writable_allow_paid_fallback appears in config and guard/migration fixtures, no production consumer | Historical broad writable strategy differs from accepted present strategy | DEAD CONFIGURATION | Retained; removal classified NEEDS ARCHITECTURAL DECISION for migration/operator compatibility | Existing runtime migration/guard tests; negative writable fixture with flag=true | CTO/product compatibility decision required before deletion; no semantics invented |

## Historical evidence and preserved policy

Both `7fa569399c1bc0b26415f53a69182e9891302573` and
`e3c8b30f93d901b0d9a05bd4bdc19f5ec09af12f` were verified as accessible commit objects.
Directed historical inspection: 0b70dd7c, 4bcb10a3, d1029254, ed2f4432,
48df01fe, 828ea62a, e3c8b30f, e693aa46; later writable policy 932572a.
No whole historical files were copied, reverted, merged or cherry-picked.

Preserved: General Auto auto_order; Engineering Manager analysis role order/models/
profile skips; gate_auto_order; writable_auto_order local-first; explicit no cross
provider fallback; allow_paid_fallback=false; DeepSeek/Grok non-writable; P1 gate
compaction/evidence/provider-specific limits/truncated structured-output rejection/
schema/semantic validation; free writable model allowlists. Gate compaction was not
generalized to writable. Historical blanket secret propagation and binary-only
Ollama availability were deliberately improved rather than restored literally.

No AICO-019 verification/diagnosis document existed in fetched origin/main at the
specified paths. No concurrent/uncommitted AICO-019 changes were copied or included.

## Validation and limits

Python interpreter: Z:\repos\ai-company-os\ai-company-os\.venv\Scripts\python.exe
(existing environment, Python 3.14.7). Bundled Python lacked pytest; existing venv
required approved execution outside sandbox. CI's Python 3.11/3.12 matrix is NOT_RUN
locally, pending CI. No dependency manifests changed.

TEMP/TMP were absolute `.validation-temp` paths under the isolated worktree to
avoid Windows short-path aliases. Commands from worktree:

- `python -m compileall -q src/company_os`: PASS.
- `python -m pytest -q`: final result appended below. Full suite repeated only
  after review fixed the gate-role display bug and invalidated earlier validation.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-project\tests\run-all-smoke-tests.ps1`: **49/49 PASS**, 25.67 s. Includes P1 provider fallback/evidence/schema/semantic validation, explicit Ollama no fallback, runtime migration, writable and TUI integration contracts.
- `npm test`: **2/2 PASS**.
- `npm pack --json --ignore-scripts --pack-destination .validation-temp`: PASS.
- `.\test-project\tests\test-npm-package-e2e.ps1 -TarballPath .validation-temp\pereyram-ai-company-os-0.1.1.tgz`: PASS exact installed artifact, new/install, Python bootstrap/TUI import, user preservation and managed-runtime update. Repacked/rechecked after final TUI fix.
- `git diff --check`, changed-file scope review and secret diff audit: PASS.

Targeted Python: provider_reconciliation 20 PASS; providers_tui 8 PASS;
local_runtime_service + plan_local_runtime 36 PASS. These are included in the final
full Python suite, not additional independent acceptance runs.
Targeted PS: writable budget/runtime and P1 context/reliability/evidence tests PASS,
then included in canonical final smoke. Do not add their counts to suite totals.

Environmental first-attempt failures: PS7 date coercion broke a pre-existing
new-project timestamp fixture; sandbox taskkill blocked provider-timeout test;
canonical Windows PowerShell with approved execution passed. Initial npm pack
cache permission failure passed on approved retry. No product workaround added.

NOT_RUN: real OpenRouter/Gemini/DeepSeek/xAI calls, real Codex execution, real
Ollama generation, real credential storage/hardware verification, paid actions,
Acceptance Run #4. Explicitly prohibited or deferred until post-merge acceptance.
Acceptance engines/fixtures were not edited. This is fixture/mock and packaging
validation, not real-provider acceptance.

Technical peer review found/fixed Plan Control gate reviewer display; final review
reported no remaining blocker. This is not Orchestrator approval, lifecycle DONE,
QA/Security owner approval, or permission to merge.

Architectural decision remaining: compatibility-safe removal of dead
writable_allow_paid_fallback. No blocker for restored independent capabilities.

Next sequence remains: Orchestrator audit → separately authorized merge → final
main → freeze a new engine → Acceptance Run #4 REAL COMPLETO.

## Published commit, scope and source manifest

Publication evidence and exact source hashes follow.

Updated (UTC ISO 8601): 2026-10-03T18:11:51Z
FINAL_SHA (audited implementation): 701b7b446b1768dc541ba2babefbabd8d30de3ab
PR URL: https://github.com/MatiasEzequielPereyra/ai-company-os/pull/40
Final Python suite: 185/185 PASS in 78.31 s.
Final package artifact: 215 entries; installed-artifact E2E PASS.
Ahead/behind origin/main at implementation publication: 1/0.
Ahead/behind origin/branch after push: 0/0.
Final documentation publication adds one commit; verify exact PR head with gh pr view 40 --json headRefOid.
git status --short after final docs commit/cleanup: empty (verified in final publication check).
Scope audit: 19 implementation/test/documentation files plus this handoff and derived company-state pointer; no Acceptance/AICO-019 artifacts.

### Files changed and exact content SHA-256

| Source | Revision/provenance | SHA-256 | State |
| --- | --- | --- | --- |
| docs/operations/provider-runtime.md | 701b7b446b1768dc541ba2babefbabd8d30de3ab | 925656FA35C14451FDA485FA305FD783A3A7C5A7731844E2EA4E856E3603C69D | committed |
| scripts/provider-router.ps1 | 701b7b446b1768dc541ba2babefbabd8d30de3ab | BADC3F670FEA97D23CA53CA18CEDC49199BD90F828F024EAF2A7BC2B44BB5C20 | committed |
| scripts/run-writable-agent.ps1 | 701b7b446b1768dc541ba2babefbabd8d30de3ab | AD965776BA9440FFA15A1B69993CA7D6E47450ECBF48D94B87971B3EDEE9D18E | committed |
| src/company_os/application/agent_control_service.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | F326676A543F7CDEF3257F3DB620810BF5EC081D5181648B576A8F0AD8BB4EFD | committed |
| src/company_os/application/gate_control_service.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | 18660987BB9ED2FD836523679D1DEDDDD258A87C0D7455D0DB4DC173A53C964B | committed |
| src/company_os/application/local_runtime_service.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | 1780BE415CAE9ADE63711D0E6B98034F4EDCC0B811FE8D63C165357240CDD808 | committed |
| src/company_os/application/provider_capabilities.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | 61C0B39CE98A71F8239DB78BD150247C89A60AE05B150D256E740146B6C96AE1 | committed |
| src/company_os/application/provider_service.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | CB015D785F7DD8F799847975B3A3D6243EE511107E0225230583284EDF7822D7 | committed |
| src/company_os/application/writable_execution_adapter.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | E740AECCC3EE2B046B319779DDCF9786B067B9166BFCA1BEA5CC74808BBDBC42 | committed |
| src/company_os/cli/i18n.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | FB64706F6E2579B8C73E5CA5A31F63B03374A0B66DB992ED1707298E34122F2D | committed |
| src/company_os/cli/screens/plan_control.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | 1CAC1370AE5633F0EE777583A97965ADB52930409FDEAAE0D2AE8837702D4EA8 | committed |
| src/company_os/cli/tui.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | B5222A57C72ABF7246262D59F895839D678DDA06C649D65B3C98E65BBD0051F8 | committed |
| test-project/tests/run-all-smoke-tests.ps1 | 701b7b446b1768dc541ba2babefbabd8d30de3ab | 4EBD825DA2FA5C647E4E3DA5CF351705F4613212EC34F29675A57964F9EBCAD3 | committed |
| test-project/tests/test-writable-agent-runtime.ps1 | 701b7b446b1768dc541ba2babefbabd8d30de3ab | E51A80791FACA5A4380A54407D70C74013DEE9A8192E8FCFFA151FC982D100A4 | committed |
| test-project/tests/test-writable-ollama-context-budget.ps1 | 701b7b446b1768dc541ba2babefbabd8d30de3ab | 73EBB2FDF2532F27936ABA68270C12F0B2AF48FC29674D8EC6EBF9E954DB2A35 | committed |
| tests/test_local_runtime_service.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | ABCE5514CF73A8C55A8D3DA2D01205CCF4BA9CAAE3860A12C8D55F4DE550F3BD | committed |
| tests/test_plan_local_runtime.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | 1FE0D92D507F391115021D0D28757066297EABFC8E4E0B5D6C717DB7E2A2B811 | committed |
| tests/test_provider_reconciliation.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | 208A82A54869D57565E864675B5EEFACD9D3DC9E09521C1C9EB0C21207344270 | committed |
| tests/test_providers_tui.py | 701b7b446b1768dc541ba2babefbabd8d30de3ab | A43CF9ED9C2FD4A3AE0F90EC9D5D57982F181EB207190E31E7D98A72F69C6454 | committed |
| AGENTS.md | BASE_SHA | E0582A802088A0DCAD937E2369D94AC16E41F4DD4E7AE33CB3F9750436BFD2F9 | committed baseline |
| .codex/protocols/company-state.md | BASE_SHA | A141728BFF428F91FAEE050663EDCAB1F2F8F3FCD8E0C797B39A3F25D29F2F7C | committed baseline |
| docs/operations/local-runtime.md | BASE_SHA | C3D12D450E133C37DBF2BF8C88B65790A851D5A091188EDEF88ECD273F026A10 | committed baseline |
| .codex/provider-config.json | BASE_SHA | 3F174264E8AC1501D0C1CF782FD0CD3BDED0528B9E72D160FBAE0EE18D337898 | committed baseline |
| .codex/writable-policy.json | BASE_SHA | B949B4FF1A128F2B1E723EAD8EBAF13E9CEF1E9B326A459DE909E87C4E619D72 | committed baseline |
| scripts/local-runtime/resolve-local-runtime.ps1 | BASE_SHA | 2D559DE19F2A1B81F734816C05750EABD28257B699C05B6E0D99A2E626A52AF0 | committed baseline |

Authorization attachment SHA-256: E7F931602BC1FEB903A85E8D7AB115252EEA7C721EE37E58F683398E0E415A1A
