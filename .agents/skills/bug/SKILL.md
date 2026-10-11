---
name: bug
description: Investigate, reproduce, diagnose, fix, and verify software bugs with evidence-backed reasoning.
---

# Bug Skill

## Purpose

Investigate and resolve software defects systematically without confusing plausible explanations with demonstrated causes.

## Process

1. Understand the reported symptom, expected behavior, actual behavior, environment, and reproduction steps.
2. Establish one concrete reproduction signal before changing source.
3. Record the pre-fix observation that demonstrates the defect.
4. Form explicit falsifiable hypotheses. Each hypothesis needs a prediction and a falsifier.
5. Run concrete experiments and keep receipts for the observed results.
6. Mark root cause CONFIRMED only when supported by the experiment evidence. Otherwise keep it UNCONFIRMED.
7. Distinguish an actual REPAIR from a WORKAROUND. Never silently label symptom suppression as repair.
8. Determine affected components and implement the smallest appropriate authorized change.
9. Add or update regression protection.
10. Replay the exact frozen reproduction signal after the change.
11. Document root cause, resolution classification, regression evidence, and verification.

## Evidence Rules

- "I reproduced it" is not sufficient without an observable signal or procedure.
- A hypothesis that was not tested is not a confirmed cause.
- A regression check that already passed before the fix is not primary proof that the fix resolved the bug.
- For automated repairs, the same reproduction signal used before the change must be replayed after the change.
- Provider statements are reasoning; runtime receipts are execution evidence.
- Operational inability to investigate must not be confused with a product defect.

## Output

Reproduction evidence, falsifiable hypotheses, experiment receipts, evidence-backed root cause, REPAIR or WORKAROUND classification, implemented change, regression protection, and same-signal post-fix verification.
