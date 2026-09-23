# Project Brief

## Project

AI Company OS

## One-Line Description

A PowerShell-first operating layer that coordinates AI-assisted software engineering through durable roles, tasks, quality gates, repository evidence, and explicit execution boundaries.

## Vision

Make multi-agent coding workflows behave more like a disciplined engineering organization: product intent is explicit, architecture decisions are durable, work is decomposed into traceable tickets, execution is gated, provider outputs are validated, and completion requires evidence.

The system should increase the reliability of AI-assisted engineering without pretending that AI agents replace human authorization, Git isolation, CI, or production ownership.

## Problem

AI coding workflows frequently fail at coordination rather than raw code generation. State is trapped in chat history, agents repeat discovery, tasks drift from the original objective, parallel work conflicts, and quality claims are difficult to audit.

AI Company OS turns that implicit coordination into repository-native artifacts and PowerShell workflows.

## Target Users

Primary users are individual developers and small engineering teams that use Codex or API-backed coding agents and want a more reproducible workflow for existing repositories.

Secondary users are maintainers experimenting with multi-agent engineering orchestration and needing an inspectable reference implementation.

## Primary User Journey

1. Install AI Company OS into a repository or create a managed project.
2. Run project intake to capture repository evidence.
3. Create a work request or task with explicit objective, owner, priority, profile, and acceptance criteria.
4. Validate readiness and dependencies.
5. Dispatch the task.
6. Run an AI analysis agent or create an isolated workspace for authorized implementation.
7. Submit implementation/result evidence.
8. Run independent review, QA, and security gates as required.
9. Complete final verification.
10. Synchronize derived state and inspect operational metrics.

## Product Goals

- Durable task and company state that survives conversation boundaries.
- Clear separation between product, architecture, implementation, and verification authority.
- Backward-compatible PowerShell workflows that work on Windows-first developer environments.
- Structured, validated provider output.
- Safe default behavior for multi-agent execution.
- Repeatable end-to-end tests that prove code-change workflows, not only document generation.
- Measurable execution signals such as transitions, provider attempts, failures, and durations.

## Non-Goals

- Replacing Git hosting, CI/CD platforms, issue trackers, or secret managers.
- Automatically granting AI agents permission to modify or deploy production systems.
- Fully autonomous merge/release decisions.
- Hiding uncertainty or fabricating evidence when repository context is unavailable.
- Supporting every model provider or programming language in the first implementation.

## Current Status

Functional framework with a working lifecycle, orchestration scripts, role definitions, provider adapters, structured result contracts, smoke tests, artifact validation, workflow profiles, isolation helpers, and baseline operational metrics.

## Current Architecture

The framework is filesystem-backed and repository-native:

- Markdown is used for human-readable durable product, architecture, task, and gate evidence.
- JSON is used for provider configuration, workflow profiles, schemas, runtime results, and operational event logs.
- PowerShell scripts implement lifecycle transitions and orchestration.
- Git remains the source of truth for code history and integration.
- External model providers are behind `scripts/provider-router.ps1`.
- Derived state under `.codex/state/` can always be rebuilt from authoritative task/document sources.

See `docs/architecture/system-architecture.md`.

## Important Constraints

- Preserve Windows PowerShell 5.1 compatibility where practical.
- Keep tasks usable as plain Markdown.
- Avoid requiring a database or hosted control plane for core operation.
- Never expose provider/API secrets in prompts, logs, or errors.
- Shared-workspace parallelism is limited to read-only analysis.
- Mutating parallel work requires isolated Git worktrees/branches.

## Known Risks

- Markdown metadata is intentionally simple and can still be corrupted by arbitrary manual edits.
- Worktree creation provides isolation but merge/reconciliation remains a human or explicitly authorized engineering action.
- Provider APIs can change response formats or structured-output behavior.
- Metrics are local JSONL telemetry, not a full distributed observability stack.
- Existing older tasks may omit newer metadata and rely on backward-compatible defaults.

## Success Criteria

The project is credible when a fresh checkout can:

- validate its canonical artifacts;
- run the full smoke suite without network access;
- prove a real code change can travel through lifecycle gates to DONE;
- reject malformed provider output;
- prevent unsafe assumptions about parallel writable execution;
- generate consistent task/company state;
- expose enough metrics to diagnose workflow/provider failures.

## Owner

CEO / Orchestrator owns overall workflow intent. Product, architecture, engineering, QA, security, and release decisions retain the role ownership defined under `.codex/`.
