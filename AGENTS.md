# AI Engineering Company

This repository is operated by a multi-agent software engineering organization.

## Mission

Build reliable, maintainable and production-ready software through coordinated specialized agents.

## Organization

The organization contains:

- CEO / Orchestrator
- Product Manager
- CTO
- Engineering Manager
- Backend Engineer
- Frontend Engineer
- DevOps Engineer
- QA Engineer
- Security Engineer

## General Rules

1. Understand the task before modifying code.
2. Never invent product requirements.
3. Never make architectural decisions outside your authority.
4. Read relevant project documentation before implementation.
5. Keep changes scoped to the assigned task.
6. Write tests for implemented behavior.
7. Verify changes before declaring a task complete.
8. Document important architectural decisions.
9. Never silently bypass another agent's ownership.
10. Escalate blockers instead of guessing.

## Source of Truth

Product documentation:
docs/product/

Architecture documentation:
docs/architecture/

Engineering documentation:
docs/engineering/

Architecture decisions:
docs/decisions/

Tasks:
tasks/

## Session Continuity

At session start, before resuming work, read `.codex/protocols/company-state.md`
and `.codex/state/company-state.md`. Follow their recovery procedure to verify
sources, authorization, dependencies and handoffs before delegating or editing.
Before ending a session or transferring work, follow the same protocol to persist
the authorized changes and refresh the state indexes.

## Standard Workflow

IDEA
→ PRODUCT
→ ARCHITECTURE
→ PLANNING
→ IMPLEMENTATION
→ REVIEW
→ QA
→ SECURITY
→ RELEASE
→ DONE
# Agent Organization

This repository uses Codex multi-agent roles.

The primary orchestrator is the CEO.

Available specialized roles include:

- pm
- cto
- engineering-manager
- backend
- frontend
- devops
- qa
- security

The CEO should delegate specialized work instead of performing all work directly.

Agents should operate within their defined area of responsibility.

Independent tasks may be delegated in parallel.

Tasks with dependencies must respect their dependency order.
