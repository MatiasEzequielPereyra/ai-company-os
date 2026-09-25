# AI Company OS — Documentation Usability Review v0.1

Date: 2026-09-25

## Scope

This review tests the user documentation as if the reader had no prior conversational context about AI Company OS.

Documentation branch:

```text
docs/user-manual-v0
```

Runtime baseline reviewed:

```text
main @ ed4820f8cbd8cf62a6b5d9494e0633b47b5fc9f3
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

## What was not tested in this documentation review

This review did **not** claim to perform a live provider execution on the user's Windows machine.

It also does not establish production maturity for:

- TUI;
- fully autonomous writable runtime;
- automatic merge/reconciliation;
- automatic push/deployment;
- configurable `provider_timeout_seconds` contract.

Those areas remain documented according to their current maturity.

## Known product limitations surfaced by documentation

### Review-role independence

Engineering Manager-owned tasks can be reviewed by the same role identity in the current gate runner.

This requires a product/architecture decision to change correctly.

### Upgrade mechanism

There is no version-aware update/migration command for an installed AI Company OS runtime.

The current safe process is Git-based review of an installer `-Force` update.

### Writable execution

Isolation helpers and authorization concepts exist, but full autonomous mutation-to-integration is not yet a stable end-to-end user contract.

### TUI

TUI work exists in development branches but is not part of stable `main`.

## Review result

```text
Documentation contract audit: PASS
Repository smoke CI: PASS
Live human first-run with external provider: PENDING HUMAN ACCEPTANCE TEST
PDF publication readiness: NOT YET — wait for v1/runtime stabilization
```

## Human acceptance test

The remaining useful test is intentionally simple:

1. A person follows only `README.md` and `docs/FIRST-RUN-CHECKLIST.md`.
2. They do not use prior chat history.
3. They note every point where they need information not present in the docs.
4. They complete the PM → CTO demo using an actually available provider.
5. Any friction is treated as a documentation or product defect, not as user error.

That test should be repeated after major TUI, writable-runtime, provider, lifecycle, or installer changes.
