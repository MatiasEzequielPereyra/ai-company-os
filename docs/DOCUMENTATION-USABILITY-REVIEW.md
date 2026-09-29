# AI Company OS — Documentation Usability Review v0.1

Date: 2026-09-29

## Scope

This review tests the user documentation as if the reader had no prior conversational context about AI Company OS.

Documentation branch:

```text
docs/user-manual-v0
```

Initial runtime baseline used for the human acceptance path:

```text
main @ ed4820f8cbd8cf62a6b5d9494e0633b47b5fc9f3
```

Post-test source-level contract revalidation:

```text
main @ 816404c51c34e0bc3e7c23ab9772a0b4d8be1753
```

Documentation branch head validated during the review:

```text
a4df897f224f1e17d20cb52ccf3cde6fb0a3ce5a
```

GitHub Actions:

```text
PowerShell smoke tests
Run #617
Conclusion: success
Head: a4df897f224f1e17d20cb52ccf3cde6fb0a3ce5a
```

## Test path

The documentation was reviewed in the same order recommended to a new user:

```text
README
  ↓
QUICKSTART
  ↓
FIRST-RUN-CHECKLIST
  ↓
USER-GUIDE
  ↓
END-TO-END-WALKTHROUGH
  ↓
TROUBLESHOOTING / COMMAND-REFERENCE / FAQ
```

## Validation performed

The review checked:

- whether a user knows how to obtain the repository;
- prerequisites;
- installation into an existing project;
- creation of a disposable project;
- project initialization;
- provider availability;
- Work Request creation;
- real Work Request ID discovery;
- planning task behavior;
- readiness and dispatch;
- dependency ordering;
- agent execution;
- Review / QA / Security;
- explicit final approval;
- iterative lifecycle behavior;
- source-of-truth artifacts;
- Git/worktree boundaries;
- update behavior;
- command parameters;
- role identifiers;
- relative documentation links;
- script references;
- current smoke CI status.

## Findings corrected during the usability test

### 1. The Quick Start assumed AI Company OS was already cloned

Fixed by adding:

- prerequisites;
- repository clone command;
- provider requirement.

### 2. Documentation used fixed IDs as if they were reusable

Examples such as:

```text
WR-001
AICO-001
```

were unsafe in general onboarding.

Quick Start and First Run now resolve the current Work Request and task IDs from generated state/artifacts.

Fixture-specific IDs remain in the E2E walkthrough but are explicitly labeled as scenario IDs.

### 3. The lifecycle was presented too linearly

The real runtime is iterative.

A completed dependency can unlock more work:

```text
READY
→ ACTIVE
→ REVIEW
→ QA
→ SECURITY
→ FINAL APPROVAL
→ DONE
→ dependent task becomes READY
→ repeat
```

Quick Start and First Run now teach that loop explicitly.

### 4. Security was easy to confuse with task completion

The documentation now makes explicit that a satisfied Security gate does not imply `DONE`.

`finalize-task.ps1` performs a separate final approval.

### 5. The first demo used an Engineering Manager-owned task

The Review gate currently assigns `engineering-manager` as reviewer.

That means an Engineering Manager-owned task does not have review independence guaranteed by role identity.

The First Run demo now uses:

```text
PM → CTO
```

so the first user experience does not hide this limitation.

### 6. Engineering Manager had two identifiers without explanation

The runtime uses:

```text
engineering-manager
```

for task Owner values and role filenames, while Codex configuration registers:

```text
engineering_manager
```

The difference is now documented in:

- `AGENTS.md`;
- `templates/AGENTS.md`;
- `USER-GUIDE.md`.

### 7. New projects were not explicitly initialized as Git repositories

`new-project.ps1` currently does not run `git init`.

The First Run and User Guide now state this and initialize Git where appropriate.

### 8. Installer SKIP behavior was underexplained

Without `-Force`, the installer can preserve existing framework files.

This can be desirable, but it also means a rerun is not automatically an upgrade.

Quick Start now tells the user to inspect `SKIP existing:` output.

### 9. Framework update behavior was undocumented

The installer is not version-aware and does not perform semantic merges.

The User Guide and Troubleshooting now recommend controlled upgrades on a Git branch with:

```text
clean state
→ installer -Force
→ git diff
→ artifact validation
```

### 10. Work Request types were listed without decision guidance

The User Guide now explains when to use:

```text
FEATURE
BUG
REFACTOR
INFRASTRUCTURE
AUDIT
RELEASE
RESEARCH
DOCUMENTATION
```

and which planning roles each type currently produces.

### 11. README made low-level task creation look like the primary flow

The README now presents:

```text
Work Request
→ orchestrator
→ tasks
→ execution
→ gates
→ final approval
```

as the normal path.

Manual task creation remains an advanced capability.

## Automated consistency result

The final documentation audit found:

```text
Broken relative documentation links: 0
Referenced PowerShell scripts missing from repository: 0
Absolute Review-independence claims contradicted by known limitation: 0
```

The remaining `WR-001` / `AICO-001` commands are inside the E2E scenario and are explicitly documented as fixture/example IDs.

## Runtime/CI result

The documentation branch triggered the repository PowerShell smoke workflow.

Observed result:

```text
Run #617
Status: completed
Conclusion: success
Head SHA: a4df897f224f1e17d20cb52ccf3cde6fb0a3ce5a
```

This confirms the branch passed the existing Windows PowerShell smoke suite at that head.

## Live human first-run acceptance test

A live first-run was completed on Windows PowerShell using a disposable project at:

```text
%TEMP%\aico-first-run
```

The operator followed the documented lifecycle through:

```text
initialize-project
→ RESEARCH Work Request
→ PM task
→ Review
→ QA
→ Security
→ final approval
→ CTO dependency unlock
→ CTO task
→ Review
→ QA
→ Security
→ final approval
→ DONE
```

Observed successful external-provider execution included OpenRouter for PM, CTO, Review, QA and Security. The acceptance test reached:

```text
PM  = DONE
CTO = DONE
```

The test also surfaced runtime limitations that belong to the product/provider layer rather than to the conceptual workflow:

- the documented runtime baseline used `context_max_chars = 320000`, which produced an unnecessarily large external context for the CTO task;
- reducing the agent context budget to approximately 110000 characters allowed the CTO execution to complete;
- the default gate context budget of 180000 characters produced repeated OpenRouter structured-output failures in this environment;
- `openrouter/free` can route to a model that returns JSON `null` or otherwise fails the required structured-output contract;
- explicit provider/model selection can be necessary when the free router chooses an incompatible model;
- the runtime correctly rejected invalid structured output instead of recording it as trusted evidence.

These findings are documented as provider/runtime limitations. The First Run remains focused on the lifecycle and points provider-specific failures to Troubleshooting rather than teaching provider debugging inline.

## What this review still does not establish

This review does not establish production maturity for:

- exhaustive interactive CLI/TUI usability;
- fully autonomous mutation-to-integration;
- automatic merge/reconciliation;
- automatic push/deployment;
- configurable `provider_timeout_seconds` contract.

Those areas remain documented according to their current maturity.

## Known product limitations surfaced by documentation

### Review-role independence

Engineering Manager-owned tasks can be reviewed by the same role identity in the current gate runner.

This requires a product/architecture decision to change correctly.

### Upgrade mechanism

The global package can be updated through npm, and installed projects maintain a managed-files manifest.

Project runtime refresh still does not perform semantic merge of local customizations. The safe process remains a Git-reviewed `aico install . --force` update on a dedicated branch.

### Writable execution

`main` now includes an explicitly authorized writable runtime operating on isolated task worktrees with policy-bounded change sets. Automatic merge/push/deploy remain outside that authorization boundary.

### CLI / TUI

The `aico` CLI/TUI is now integrated in `main` and distributed through npm. This documentation review validated its source-level command contract, but the earlier human PM → CTO acceptance test primarily exercised the PowerShell lifecycle rather than the full interactive UI.

## Review result

```text
Documentation contract audit: PASS
Repository smoke CI: PASS at the previously recorded reviewed head
Live human first-run with external provider: PASS WITH RUNTIME FINDINGS
PDF publication readiness: NOT YET — wait for v1/runtime stabilization
```

## Human acceptance test status

The PM → CTO acceptance path has now been executed successfully with a real external provider.

The test should be repeated after major TUI, writable-runtime, provider, lifecycle, installer, or context-budget changes. Provider failures must be classified separately from documentation defects so the manual does not become a provider-debugging guide.


## Post-review reconciliation — current main

After the live PM → CTO acceptance test, `main` advanced substantially. Before considering the manual merge-ready, the documentation was reconciled against `main @ 816404c51c34e0bc3e7c23ab9772a0b4d8be1753`.

The reconciliation updated:

- npm installation and `aico` CLI onboarding;
- CLI/TUI status from experimental to integrated;
- default provider strategy from Codex/OpenRouter/Gemini fallback to local-first Ollama;
- provider support to include Ollama, DeepSeek and Grok;
- analysis context budgets from the earlier 320000-character baseline to current bounded/per-role limits;
- managed-files upgrade behavior;
- current writable runtime boundaries.

The earlier OpenRouter acceptance findings are retained as historical integration evidence. Current `main` already incorporates part of the context-budget hardening that the test exposed.

A fresh human acceptance pass on the final merged `main` is recommended after documentation integration, but the manual no longer knowingly describes the pre-CLI/pre-local-runtime contract.
