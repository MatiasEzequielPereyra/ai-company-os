# Bug Resolution Workflow

## 1. Report

Capture:

- Symptoms
- Expected behavior
- Actual behavior
- Environment
- Reproduction steps

## 2. Freeze Reproduction Signal

Define one concrete signal that demonstrates the reported defect.

For automated repairs the signal must be executable under the writable verification policy. Its identity is frozen before the first source mutation.

## 3. Reproduce

Run the frozen signal before changing source and record the observed broken behavior.

If the defect cannot be reproduced, do not mutate source and do not claim a repair.

## 4. Diagnose

Create explicit falsifiable hypotheses.

Each hypothesis must contain:

- statement;
- prediction;
- falsifier;
- experiment.

Run the experiments and preserve receipts.

Root cause may be marked CONFIRMED only when supported by concrete evidence.

## 5. Plan

Determine:

- REPAIR or WORKAROUND;
- fix;
- affected components;
- regression risks;
- tests.

A WORKAROUND must state residual risk and must not be silently represented as REPAIR.

## 6. Implement

Apply the smallest appropriate fix within the existing implementation authorization and isolated writable-worktree boundary.

## 7. Test

Add or update regression protection and run the approved verification commands.

## 8. Replay Original Signal

Replay the exact frozen reproduction signal.

For an automated REPAIR, the pre-fix and post-fix signal fingerprints must be identical and the post-fix observation must demonstrate that the original defect no longer occurs.

## 9. Review

Review implementation and diagnostic evidence independently.

Reject unsupported confirmed causes, signal substitution, workaround-as-repair classification, or missing same-signal replay.

## 10. QA

Verify the original broken behavior as an acceptance criterion using the diagnostic evidence and independent QA evidence.

## 11. Security

Use the existing conditional Security gate when the change is security-relevant.

## 12. Release

Deploy through the standard release process.

## 13. Close

Document root cause, resolution classification, diagnostic artifact, regression evidence, and final verification.
