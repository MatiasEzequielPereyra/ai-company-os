# Task Lifecycle

Every meaningful unit of work should have a task.

## Lifecycle

BACKLOG
↓
READY
↓
ACTIVE
↓
REVIEW
↓
QA
↓
SECURITY
↓
DONE

---

## BACKLOG

Idea or identified work that has not been prepared.

---

## READY

Task has:

- Owner.
- Objective.
- Acceptance criteria.
- Dependencies identified.
- Required context.

---

## ACTIVE

An agent is actively implementing the task.

---

## REVIEW

Implementation is complete and awaiting review.

---

## QA

Implementation passed code review and is ready for functional validation.

---

## SECURITY

Security validation is required.

Not every task requires this stage.

---

## DONE

All applicable quality gates passed.

---

## BLOCKED

The task cannot proceed.

A blocked task must contain:

- Reason.
- Impact.
- Required decision.
- Escalation owner.

---

# Rules

A task may not skip directly from BACKLOG to DONE.

A task may skip a quality stage only when that stage is explicitly marked NOT_APPLICABLE.