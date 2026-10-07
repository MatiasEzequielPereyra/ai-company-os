# AICO Debugging Capability v1 — Diagnostic Evidence Contract

Status: IMPLEMENTATION CONTRACT
Baseline: `62485cdc7de9d3bc01b0aed4a1d5e7e710365fc9`
Decision: ADAPT

## Trust rule

Models may propose diagnostic reasoning. AI Company OS must preserve the evidence that justifies it.

A repair is demonstrated only when the same frozen signal that proved the defect before the change demonstrates its absence after the change.

## Existing lifecycle

No lifecycle state is added. Debugging remains inside the existing task flow:

`ACTIVE -> REVIEW -> QA -> SECURITY -> DONE`

Existing implementation authorization, isolated writable worktrees, Result Intake, Review, QA, Security, and Final approval remain authoritative.

## Durable evidence

BUG implementation work produces a canonical control-plane artifact:

`docs/engineering/diagnostics/<TASK-ID>-diagnostic-v1.json`

The provider does not write that artifact. The runtime derives signal identity and execution receipts, persists the artifact, validates it, references it from the primary agent report/result, and supplies it to independent gates.

## Automated v1 boundary

Automated writable repair uses command-based reproduction and hypothesis experiments that pass the existing safe-command policy. Manual/procedure evidence remains representable by the durable evidence schema but cannot authorize automated source mutation without trusted user/runtime evidence.

## Required chain

`symptom -> frozen reproduction -> pre-fix observation -> falsifiable hypotheses -> experiments -> evidence-backed cause -> REPAIR/WORKAROUND -> change -> regression -> exact signal replay`

## Distribution

The canonical `.agents/skills/bug` capability and legacy template must stay semantically aligned. New projects must receive canonical skills. Existing-project reconciliation remains explicit and must not silently overwrite local skill customization.


## Runtime enforcement

The writable BUG runner selects a BUG-specific structured output contract. Before any source mutation it validates the reproduction command with the writable command policy, executes it, runs the declared hypothesis experiments, and refuses REPAIR when the runtime evidence does not support the claimed cause.

Corrective attempts reuse the original frozen signal fingerprint and append attempts/receipts rather than replacing diagnostic history. Automatic signal substitution is fail-closed; formal invalidation requires a separate explicit control-plane decision.


## Approval guard

Review APPROVE and QA PASS are fail-closed for BUG IMPLEMENTATION tasks. Both manual and AI-driven gate paths call the same diagnostic evidence guard, which requires a validated COMPLETE artifact with the original frozen signal observed broken before the change and FIXED_OBSERVED after it.

A missing artifact remains reviewable as a defect, but it cannot be approved or passed.

## Hypothesis discrimination

A root-cause experiment cannot be byte-for-byte the same command as the frozen reproduction signal. Reproducing the symptom is not evidence of its cause. Runtime receipts bind each hypothesis to its own experiment command and deterministically recompute SUPPORTED/FALSIFIED from the observed exit code.
