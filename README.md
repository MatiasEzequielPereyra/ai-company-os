# AI Company OS

AI Company OS is a **PowerShell-first engineering workflow framework for coordinating AI coding agents around a real software repository**.

It is not an autonomous software company and it is not a replacement for Git, CI, code review, or human authorization. Its purpose is to make AI-assisted engineering work **durable, inspectable, repeatable, and gated** instead of leaving important decisions and execution state inside chat history.

## What problem it solves

AI coding agents are useful at implementation and analysis, but multi-step work becomes unreliable when:

- product intent is implicit;
- architecture decisions are mixed with implementation;
- tasks have no durable lifecycle;
- multiple agents can conflict in the same workspace;
- provider output is not validated;
- review/QA/security evidence is informal;
- nobody can tell whether the workflow is improving delivery quality.

AI Company OS provides a filesystem-backed operating layer around those concerns.

## Intended operating model

The repository models an engineering organization with durable roles:

- CEO / Orchestrator
- Product Manager
- CTO
- Engineering Manager
- Backend Engineer
- Frontend Engineer
- DevOps Engineer
- QA Engineer
- Security Engineer

The canonical ticket lifecycle is:

```text
BACKLOG -> READY -> ACTIVE -> REVIEW -> QA -> SECURITY -> DONE
```

`BLOCKED` can interrupt unfinished work. Project-level phases such as PRODUCT, ARCHITECTURE, RELEASE, and CANCELLED are broader workflow phases and are intentionally separate from ticket status.

## What is operational today

The framework includes:

- project intake and repository discovery;
- durable Markdown tasks under `tasks/`;
- readiness, dispatch, result intake, review, QA, security, and final approval scripts;
- provider routing for Codex CLI, OpenRouter, and Gemini;
- structured provider result schemas;
- engineering backlog generation/materialization;
- state synchronization;
- workflow profiles;
- artifact validation;
- operational event logging and metrics summaries;
- an isolated-worktree helper for mutating parallel work;
- smoke and end-to-end workflow tests.

The default AI runtime remains **analysis/read-only by design**. Mutating code execution must occur in an explicitly authorized isolated workspace and then flow back through normal review and Git integration.

## Workflow profiles

Profiles live in `.codex/workflow-profiles.json`:

- **lightweight** — low-risk, reversible work; review + QA remain required, security can be not applicable.
- **standard** — default product engineering profile; review + QA required, security determined by risk.
- **high-assurance** — sensitive or release-critical work; review + QA + security required and mutating parallel work must use isolated Git worktrees.

Existing tasks without a `Workflow profile` field are treated as `standard` for backward compatibility.

## Core commands

Run from the repository root:

```powershell
.\scripts\initialize-project.ps1
.\scripts\new-task.ps1 -Title "Implement feature" -Owner backend -Priority P1
.\scripts\evaluate-readiness.ps1 -Apply
.\scripts\dispatch-ready-tasks.ps1 -Apply
.\scripts\run-active-agents.ps1
.\scripts\validate-artifacts.ps1
.\scripts\sync-company-state.ps1
.\scripts\summarize-metrics.ps1
```

For isolated mutating work:

```powershell
.\scripts\new-agent-workspace.ps1 -Id AICO-123
```

This creates a task-specific Git worktree and branch. Integration is intentionally not automatic.

## Source-of-truth rules

- `tasks/AICO-*.md` own ticket status, acceptance criteria, dependencies, evidence, and transition history.
- `docs/product/` owns confirmed product requirements.
- `docs/architecture/` and accepted ADRs own technical decisions.
- `docs/engineering/` owns plans, dispatch packets, results, reviews, and handoffs.
- `.codex/state/` contains derived indexes and must not override authoritative documents.
- JSON schemas under `schemas/` define machine-readable contracts for normalized artifacts and provider outputs.

See `docs/PROJECT-BRIEF.md` and `docs/architecture/system-architecture.md` for the product and architecture model.

## Safety boundaries

AI Company OS deliberately separates **analysis authority** from **mutation authority**.

The built-in Codex adapter uses a read-only sandbox. External API providers receive a bounded repository context pack. A task being READY or ACTIVE does not by itself authorize unrestricted code changes, deployment, secret access, or merge/push operations.

Parallel mutating agents must not share a writable checkout. Use task-specific branches/worktrees and explicit integration review.

## Validation

Run the full local suite:

```powershell
.\test-project\tests\run-all-smoke-tests.ps1
```

The suite includes a deterministic end-to-end test that performs a real source-code change in a temporary project and drives that change through task result intake, review, QA, security disposition, and final approval.

GitHub Actions also runs the suite on Windows PowerShell for pushes and pull requests.

## Current maturity

This repository is an engineering workflow framework, not yet a fully autonomous execution platform. The strongest current capabilities are durable coordination, structured analysis, lifecycle enforcement, and evidence capture. Remaining maturity work includes richer merge/reconciliation automation for isolated agent branches, deeper provider transport simulation, and longitudinal quality metrics across real projects.

## User documentation

For users who want to operate AI Company OS rather than inspect its internals:

- [Quick Start](docs/QUICKSTART.md) — install the framework and prepare the first workflow.
- [User Guide](docs/USER-GUIDE.md) — concepts, lifecycle, providers, quality gates, isolation, and troubleshooting-oriented operating guidance.
- [End-to-End Walkthrough](docs/END-TO-END-WALKTHROUGH.md) — verified path from Work Request and planning to lifecycle gates and DONE.
- [First Run Checklist](docs/FIRST-RUN-CHECKLIST.md) — controlled first execution for a fresh user.
- [Troubleshooting](docs/TROUBLESHOOTING.md) — recovery by symptom and verified failure modes.
- [Command Reference](docs/COMMAND-REFERENCE.md) — verified parameters for the main PowerShell commands.
- [FAQ](docs/FAQ.md) — concise answers about concepts, autonomy, providers, gates, and authorization.
- [Documentation Status](docs/DOCUMENTATION-STATUS.md) — coverage and known documentation gaps.

The user guide is living documentation. Experimental functionality is not presented as stable until it is integrated into the documented branch.

