# AI Company OS

AI Company OS is an **experimental, Windows-first framework for structured AI-assisted software-engineering workflows around a real repository**.

It turns work requests, plans, tasks, agent results, review evidence, QA/security gates, and execution state into durable repository artifacts. It is not a fully autonomous software company, a deployment system, or a replacement for Git, CI, code review, security review, or human authorization.

## Current maturity

AI Company OS is pre-beta software under active development.

The current main branch includes project scaffolding, installation into existing repositories, an npm-distributed CLI, package-local Python bootstrap, a TUI, task lifecycle enforcement, provider routing, hardware-aware Ollama support, isolated writable execution, structured Engineering Manager planning, quality gates, managed runtime updates, and release/package validation.

Current limitations are documented rather than hidden. Merge, push, deploy, release, and package publication remain outside the writable agent runtime. Cross-platform support is not established. Some workflow operations still use PowerShell scripts directly.

## Tested and required environment

| Area | Current contract |
| --- | --- |
| Primary platform | Windows-first |
| CI host | GitHub windows-latest |
| Node.js | Package requires >=20; CI currently validates Node 20 |
| Python | Package requires >=3.11; CI validates Python 3.11 and 3.12 |
| PowerShell | Required; Windows PowerShell is used by smoke/release validation and PowerShell 7 by other CI steps |
| Git | Strongly recommended and required for isolated worktree-based writable execution |
| Linux/macOS | Not established as supported platforms by current CI |

Ollama is optional for installation. The **general Auto provider mode defaults to Ollama only**, so general Auto execution needs a usable local Ollama runtime unless project routing is deliberately changed.

## Install

~~~powershell
npm install -g @pereyram/ai-company-os

aico version
aico --help
aico doctor --system
~~~

The npm launcher creates a package-local Python virtual environment on first use and installs the bundled Python CLI into it.

## 5-minute quick start

For an existing repository:

~~~powershell
Set-Location "C:\path\to\your-project"
aico install .
aico use .
aico doctor --system
aico doctor
aico status
aico
~~~

The normal installer does not intentionally overwrite an existing file at a framework path. It records installed ownership in **.codex/managed-files.json**.

Continue with the [Quick Start](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/QUICKSTART.md).

## Create a new project

~~~powershell
aico new my-project
~~~

Or choose the parent directory:

~~~powershell
aico new my-project C:\Projects
~~~

The command creates the project, installs the AI Company OS project structure, bootstraps the Python CLI, and selects the new project as active.

**Current limitation:** aico new does not run git init. If the project will use Git-backed lifecycle or isolated writable worktrees, initialize Git explicitly:

~~~powershell
Set-Location "C:\Projects\my-project"
git init
git add .
git commit -m "chore: initialize project"
~~~

## Install into an existing repository

From the target repository:

~~~powershell
aico install .
~~~

The installer creates framework directories, runtime scripts, schemas, configuration, initial state, and **.codex/managed-files.json**. Existing framework-path files are skipped by normal installation rather than silently overwritten.

Git is not a hard precondition for copying the framework, but the installer warns when .git is absent and worktree-based writable execution requires Git.

**aico init** is currently an alias of **aico install**.

## Update AI Company OS

There are two separate updates.

### Update the globally installed package

~~~powershell
npm install -g @pereyram/ai-company-os@latest
aico version
~~~

### Update the managed runtime inside an existing project

~~~powershell
Set-Location "C:\path\to\your-project"
aico update .
~~~

The project updater requires a valid **.codex/managed-files.json** and fails closed when ownership cannot be proven. It refreshes the package-owned runtime namespace—PowerShell runtime scripts, provider/local-runtime adapters, JSON schemas—and merges the managed runtime configuration files while preserving supported project overrides.

It does **not** promise to update every agent, policy, protocol, workflow, template, skill, task, work request, project document, evidence file, or application source file.

Do not use a forced install as a substitute for the updater.

See [Update and ownership](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/operations/update-ownership.md).

## How work moves through the system

~~~text
idea / objective
→ Work Request
→ planning
→ structured Engineering Manager plan
→ executable backlog / tasks
→ dispatch
→ analysis or authorized implementation
→ result intake
→ Review
→ QA
→ Security disposition
→ explicit final approval
→ DONE
~~~

Task state is stored in **tasks/AICO-*.md**. Planning, dispatch, results, reviews, QA/security evidence, and final approvals live under **docs/engineering/**.

A task can be BLOCKED when a material dependency or decision prevents completion. DONE requires applicable quality evidence and explicit final approval.

## Providers

Current provider adapters:

- Ollama
- OpenRouter
- Gemini
- Codex CLI
- DeepSeek
- Grok / xAI

The default general routing policy is intentionally conservative:

~~~text
Auto → Ollama
~~~

Engineering Manager analysis has a role-specific routing override that can consider OpenRouter, Gemini, Ollama, Codex, DeepSeek, and Grok in configured order. On the LOCAL_CPU_LOW profile, local Ollama is skipped for that role. Paid DeepSeek/Grok fallback remains disabled while allow_paid_fallback is false.

Writable Auto is a separate policy and defaults to Ollama. Writable execution supports Ollama, OpenRouter, and Gemini; automatic cloud selection is constrained by the configured free-model allowlist.

Provider availability does not imply automatic selection, and explicit cloud-provider use can consume quota or incur cost.

See [Provider runtime](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/operations/provider-runtime.md).

## Safety and ownership model

AI Company OS separates:

- **project-owned work** — application source, normal project documents, business decisions, and user-owned files;
- **framework-managed runtime** — the subset safely refreshed by aico update;
- **workflow/control-plane evidence** — tasks, work requests, plans, results, gates, approvals, and state.

The read-only agent runner does not authorize source mutation.

Writable implementation requires an implementation task, explicit workflow authorization, a registered task-specific Git worktree/branch, writable policy checks, a structured change set, local application, and verification. It does not automatically commit, merge, rebase, push, deploy, publish, or retrieve secrets.

## Validation evidence

Current CI validates:

- Windows PowerShell smoke suite on windows-latest;
- Python CLI tests on Python 3.11 and 3.12;
- Node 20 package validation;
- npm package contract validation;
- an actual npm pack tarball;
- packaged aico new;
- packaged aico install;
- packaged aico update;
- package-local Python bootstrap;
- preservation of project-owned files;
- release validation against the exact packed artifact.

This is evidence for tested paths, not a claim that every provider, Windows client version, or external environment is exhaustively validated.

## Documentation

- [Documentation index](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/README.md)
- [Quick Start](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/QUICKSTART.md)
- [First Run Checklist](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/FIRST-RUN-CHECKLIST.md)
- [User Guide](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/USER-GUIDE.md)
- [Command Reference](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/COMMAND-REFERENCE.md)
- [End-to-End Walkthrough](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/END-TO-END-WALKTHROUGH.md)
- [Troubleshooting](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/TROUBLESHOOTING.md)
- [Provider Runtime](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/operations/provider-runtime.md)
- [Update and Ownership](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/operations/update-ownership.md)
- [FAQ](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/FAQ.md)
- [Documentation Status](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/docs/DOCUMENTATION-STATUS.md)
- [Contributing](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/CONTRIBUTING.md)
- [Security](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/SECURITY.md)
- [Changelog](https://github.com/MatiasEzequielPereyra/ai-company-os/blob/main/CHANGELOG.md)

The root README uses absolute GitHub links for detailed documentation because the npm package intentionally does not ship the full docs tree.

## Support

Use GitHub Issues for normal bugs and feature requests:

https://github.com/MatiasEzequielPereyra/ai-company-os/issues

For security-sensitive reports, follow SECURITY.md and do not post secrets or exploitable details in a public issue.
