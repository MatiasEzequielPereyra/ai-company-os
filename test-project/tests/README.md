# AI Company OS Test Suite

This directory contains reproducible, network-independent validation scenarios for AI Company OS.

## Run the full smoke suite

From the repository root on Windows PowerShell:

```powershell
.\test-project\tests\run-all-smoke-tests.ps1
```

The runner executes tests in lifecycle order, stops on the first failure, and prints a final pass/fail summary.

## Validation areas

The suite covers:

- project initialization and repository intake;
- planning, readiness, dispatch, and result intake;
- review, QA, security, finalization, and dependency refresh;
- orchestrator behavior;
- multi-provider runtime contracts;
- canonical JSON contract validation;
- workflow profile enforcement;
- writable-agent isolation safeguards;
- engineering backlog generation/materialization;
- **a deterministic end-to-end code-change scenario**.

## Real code-change E2E

`test-end-to-end-code-change.ps1` creates an isolated temporary project containing a deliberately incorrect PowerShell function, creates a real AI Company OS task, moves it into ACTIVE, changes the source from subtraction to addition, executes the changed function, then drives the task through:

```text
ACTIVE -> REVIEW -> QA -> SECURITY -> DONE
```

It verifies the source behavior, result/review/QA/security/final artifacts, canonical company state, artifact validation, and lifecycle telemetry.

This test does not call an external model provider. Its purpose is to prove the workflow can govern a real code mutation deterministically.

## Provider tests

The suite validates provider contracts locally and checks adapter safety/error-handling behavior without spending API quota or depending on network availability. Live provider availability remains an integration concern rather than a smoke-test dependency.

## CI

`.github/workflows/powershell-smoke.yml` runs the same suite on `windows-latest` for pushes, pull requests, and manual dispatch.
