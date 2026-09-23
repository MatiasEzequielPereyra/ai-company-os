# Workflow Policy

AI Company OS uses two related but distinct state vocabularies. Keeping them separate prevents project planning phases from being mistaken for executable ticket status.

## Project Workflow Phases

Project/work-request phases describe the broader engineering process:

```text
IDEA
PRODUCT
ARCHITECTURE
READY
IN_PROGRESS
CODE_REVIEW
QA
SECURITY
APPROVED
RELEASE
DONE
BLOCKED
CANCELLED
```

These phases describe where a project or coordinated workstream is in the company workflow. They are not all valid task `Status` values.

## Canonical Ticket Statuses

Task files under `tasks/` use only:

```text
BACKLOG
READY
ACTIVE
REVIEW
QA
SECURITY
DONE
BLOCKED
```

The `Status:` field in each task file is authoritative for ticket execution.

## Mapping

| Ticket status | Project workflow equivalent |
| --- | --- |
| BACKLOG | IDEA / PRODUCT / ARCHITECTURE / planning |
| READY | READY |
| ACTIVE | IN_PROGRESS |
| REVIEW | CODE_REVIEW |
| QA | QA |
| SECURITY | SECURITY |
| DONE | DONE |
| BLOCKED | BLOCKED |

`APPROVED` and `RELEASE` are project/release phases and gate evidence, not extra ticket statuses. `CANCELLED` is a project/work disposition requiring CEO/PM authorization and reconciliation; it must not be represented by falsely marking a task DONE.

## State Ownership

- IDEA: CEO / PM
- PRODUCT: PM
- ARCHITECTURE: CTO
- READY: Engineering Manager
- IN_PROGRESS / ACTIVE: assigned Engineering owner
- CODE_REVIEW / REVIEW: independent reviewer
- QA: QA
- SECURITY: Security
- APPROVED: CEO / CTO depending on change
- RELEASE: DevOps
- DONE: CEO final verification
- BLOCKED: current owner + escalation owner
- CANCELLED: CEO / PM

## Workflow Profiles

Every newly created task has one of these profiles:

- `lightweight`
- `standard`
- `high-assurance`

Tasks created before profiles existed are interpreted as `standard`.

Profiles change assurance requirements, not ticket status vocabulary. In particular, a high-assurance task cannot satisfy SECURITY using `NOT_APPLICABLE`; it requires an explicit PASS or FAIL.

The canonical profile configuration is `.codex/workflow-profiles.json`.

## Execution Boundary

A ticket becoming READY or ACTIVE confirms lifecycle preparation/assignment only. It does not implicitly authorize:

- unrestricted code mutation;
- destructive commands;
- secret access;
- merge or push;
- deployment or release.

Shared-workspace parallel execution is restricted to the analysis-only agent runner. Authorized writable parallel work must use isolated task-specific Git worktrees/branches and explicit integration review.
