# TUI-UX-01 completion review

Project: AI Company OS

Handoff ID: tui-ux-01-completion-review-2026-10-10

Revision: 1

Updated: 2026-10-10T15:13:46Z

Updated by: Codex, assigned TUI engineer

Previous handoff: NONE for this completion review

Git base commit: 5aedfbbb0ed897e8b4c8076f44863379e5d03d53

Initial receipt status: PENDING

Recipient: External Orchestrator / independent reviewer

## Authorization

Human request, 2026-10-10: continue the existing TUI-UX-01 implementation, prove the real installed entrypoint, reconcile with main, run complete verification, publish the branch and a draft PR, then stop for independent review. The user confirmed their command is `aico`.

Restrictions retained: no merge, providers, acceptance-engine update, other branches/worktrees, Run A/B, Grounded, Skills or Error Intelligence changes. Existing global installations were inspected, not updated. Global company-state indexes currently describe Grounded work; their pointer is preserved under the explicit scope protection. This scoped handoff is delivered through the draft PR; any shared-index integration belongs to the recipient.

## Identity and reconciliation

Repository: MatiasEzequielPereyra/ai-company-os.

Worktree: `Z:\repos\ai-company-os\worktrees\tui-ux-01-projects`.

Branch: `fix/tui-ux-01-projects-navigation`.

The initially clean branch matched approved SHA `aa028f6891458b221a16e1718aa2efd2d0026b3a`. GitHub connectivity recovered using authorized execution outside the network-restricted sandbox. Fetch and GitHub API independently confirmed main at the base above, checked again before publication. Related branch PR lookup returned none; the open PR #66 concerns diagnostic evidence and is outside this workstream.

Clean rebase onto origin/main produced `060e4c5cd72d9bf247298014cf385d1bf25aef17`. Git range-diff reported the approved patch unchanged. Completion adds only an entrypoint regression test and this evidence. Final commit and PR identities are supplied in the delivery checkpoint, avoiding a self-referential commit identifier here.

## Real entrypoint and screen identity

The user's resolved command is `Z:\npm-global\aico.ps1` (also `.cmd` and shell shims). It invokes Node on `Z:\npm-global\node_modules\@pereyram\ai-company-os\npm-bin\aico.js`, which starts its private `.aico-python\Scripts\python.exe -m company_os.cli.app` with no arguments. The CLI runs AICompanyTUI; the Projects navigation pushes `company_os.cli.screens.projects.ProjectManagerScreen`. The legacy class is not the Projects navigation target. The npm alias `ai-company-os` uses the same bootstrap.

Python packaging declares `company = company_os.cli.app:main`. The current PATH `company.exe` is a Python-manager proxy targeting the separate global Python 3.14 installation; that target currently cannot import company_os. This is a separate launcher installation issue, and the user uses `aico`.

The user's global npm private runtime loads `company_os/cli/screens/projects.py` from its own site-packages, but still lacks Ctrl+L. It is an older copy of the SAME implementation, not ARCHITECTURE_MISMATCH. Compatibility is confirmed; the user's existing global installation has not yet received this candidate. The bootstrap's version-only 0.1.1 cache can retain the old Python package, so an approved release must explicitly address runtime refresh. This review does not change installer policy.

An isolated installed npm candidate was built under `.pytest_cache/candidate`: npm pack, offline npm install with scripts disabled, copy of the existing private Python runtime, then explicit `pip install --no-deps --force-reinstall` of the candidate package into that private copy. This exercised installed code without modifying the user's global runtime; it is not evidence of a fresh environment bootstrap.

Tarball SHA-256: `58FE6C3AABF6A1F7C3832CEAA2F21C12BDDBC0B85650D2C07136DEFC64E2CD4F`.

Both source and installed candidate projects.py SHA-256: `4DC79A8031BDB926C92E5FD5AC8509B5F0551CCD149BCF509C123F571B99CD6C`.

The installed `.bin/aico.cmd` loaded the candidate's `.aico-python/Lib/site-packages/company_os/cli/screens/projects.py`. The CLI probe replaced only the terminal run boundary with real AICompanyTUI.run_test; project discovery, configuration and opening services remained real and used isolated fixtures.

## Executed verification

After reconciliation, focused Projects/control-plane/entrypoint checks: **9 passed, 14.47 seconds**. Complete Python suite including the supplemental test: **214 passed, 109.15 seconds**. npm tests: **2 passed**. Git diff whitespace check: PASS. Tests required authorized execution outside the sandbox because its asyncio socketpair IPC failed. No provider was invoked.

The new [entrypoint test](../../../../tests/test_projects_entrypoint.py) invokes the Python CLI main and the real application's Projects navigation. It checks Ctrl+L, Tab, Shift+Tab, Windows paths with spaces, typing, cursor movement and correction, up/down retaining input focus, Escape preserving active project/configuration, Paste, nonexistent path rejection, and Enter opening a valid project with actual app and configuration updates.

The installed npm entrypoint passed the same scenario. This automated probe uses Textual Paste events; it does not establish native clipboard behavior.

Separate real terminal runs invoked installed candidate `aico.cmd` through a PTY with **WindowsDriver**, using the original AICompanyTUI.run, not run_test. Instrumentation isolated configuration, observed state, and supplied an exit timeout. Raw input verified Projects navigation, Ctrl+L, Tab, Shift+Tab, bracketed paste of a nonexistent spaced Windows path, Enter rejection and Escape preservation. A second run verified Ctrl+L, bracketed paste of a valid spaced Windows path and Enter changing the active project to `Opened Project With Spaces`. Both runs returned exit 0. Terminal traces remain locally at `.pytest_cache/candidate/terminal-probe/terminal-initial-evidence.json` and `terminal-evidence.json`; package identity trace is at `.pytest_cache/candidate/npm-probe/entrypoint-evidence.json`. These ignored local artifacts are supplementary; the reproducible test and this account are versioned.

An initial terminal replay combined Enter and Ctrl+L before screen mount, so the latter input was lost. Repeating with separate awaited inputs succeeded. This was replay sequencing, not an implementation change.

Manual Windows Terminal validation: **MANUAL_VALIDATION_PENDING**. This environment has no supported native UI control or human observation of Windows Terminal. PTY WindowsDriver results do not substitute for visual inspection or native clipboard validation. Lint: NOT_RUN.

## Scope and review disposition

TUI-UX-01: **TUI_UX_01_READY_FOR_EXTERNAL_ORCHESTRATOR_REVIEW**, not final user-install acceptance or task closure.

TUI-UX-02: **MOUSE_SUPPORT_DISABLED_BY_DESIGN**. The app continues to run with mouse=False; no mouse support fix is claimed.

TUI-UX-03: **NEEDS_MANUAL_REPRODUCTION**. No rendering correction is included.

Blockers to final acceptance: manual Windows Terminal check and verification of an approved refreshed user installation. No architecture mismatch blocks independent review. Independent approval, QA/release gates and receipt remain PENDING.

Next exact action: External Orchestrator reviews the draft's unchanged approved implementation, supplemental entrypoint evidence and installation-refresh limitation; then coordinates manual Windows Terminal validation on an explicitly refreshed candidate runtime. Do not merge or resume Run A/B from this handoff.

## Source manifest

Paths are repository-relative; exact hashes identify the reviewed content. Revision is the reconciled implementation commit unless indicated. This handoff excludes its own hash.

| Source | Revision | SHA-256 |
| --- | --- | --- |
| src/company_os/cli/screens/projects.py | 060e4c5 | 4DC79A8031BDB926C92E5FD5AC8509B5F0551CCD149BCF509C123F571B99CD6C |
| src/company_os/cli/i18n.py | 060e4c5 | 42AA9C057D502457AE01724E841A94AA96AC79D381E5B8B30CAD8166516FB49D |
| npm-bin/aico.js | unchanged base | 84C6986EF3749B302B7C1055A9FF09FD9C98DAE83FD34E56C0E6A50633808A0F |
| tests/test_projects_tui.py | 060e4c5 | BCA5466084D7099D6C88E5518C68AA01F0A614D864AF48E123321BC0DF33C288 |
| tests/test_control_plane.py | 060e4c5 | 5ABE24A10C8C5CBCCDFF842C9E8B604373C18983652025FC7531C675A7659760 |
| tests/test_projects_entrypoint.py | new, tested before commit | BA791A0FF3412FE07A82339B7AAF0B99D5B4BA003347207FD0966C1C35C0CC26 |
