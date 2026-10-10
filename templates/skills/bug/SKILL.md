# Bug Investigation Skill

## Purpose

Investigate and resolve software defects systematically without confusing plausible explanations with demonstrated causes.

## Process

1. Understand symptom, expected behavior, actual behavior, environment, and reproduction steps.
2. Establish one concrete reproduction signal before changing source.
3. Record the pre-fix observation that demonstrates the defect.
4. Form explicit falsifiable hypotheses with predictions and falsifiers.
5. Run concrete experiments and preserve their receipts.
6. Mark root cause CONFIRMED only when experiment evidence supports it.
7. Distinguish REPAIR from WORKAROUND; never hide symptoms with a superficial workaround and call it repaired.
8. Apply the smallest appropriate authorized change.
9. Add or update regression protection.
10. Replay the exact frozen reproduction signal after the change.
11. Document the cause, resolution classification, tests, and verification.

## Rule

Models may propose diagnostic reasoning. Runtime or user-supplied evidence must justify the claims that close the bug.
