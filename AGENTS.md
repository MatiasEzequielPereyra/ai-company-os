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

## Automatic Skill Selection Policy

For substantive engineering work, identify available skills in `.agents/skills/` that fit the task's actual intent; do not select by keywords alone. By default, select `bug` for bug diagnosis and repair, `architecture` for technical design, `feature` for feature implementation, `code-review` for code or PR audits, and `release` for release preparation.

Read a relevant `SKILL.md` before applying its process. Use multiple skills only when each contributes, do not load all skills by default, and avoid rereading skill content already available in context without need. Follow each applied skill's specific instructions. Do not invent skills or claim to have applied a skill that was not consulted. If no skill fits, continue with the standard workflow.

Skills do not replace or weaken implementation authorization, role boundaries, Review Grounding, QA and Security, task execution locks, Git protection, verifiable evidence, or the existing task sequencing and delegation rules.

For substantive handoffs, include `SKILLS_SELECTED`, `SKILLS_APPLIED`, `SKILL_SOURCES`, and `SKILL_SELECTION_REASON`, and list only skills actually used.
# Agent Organization

This repository uses Codex multi-agent roles.

The primary orchestrator is the CEO.

Available specialized roles include:

- pm
- cto
- engineering_manager
- backend
- frontend
- devops
- qa
- security

### Engineering Manager identifier note

The Codex agent registration key is `engineering_manager`.

PowerShell task metadata, task Owner values, and role filenames use `engineering-manager`.

These are two identifiers for the same conceptual role and must not be substituted blindly.

The CEO should delegate specialized work instead of performing all work directly.

Agents should operate within their defined area of responsibility.

Independent tasks may be delegated in parallel.

Tasks with dependencies must respect their dependency order.
