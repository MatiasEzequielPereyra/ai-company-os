# Operational Observability

AI Company OS records lightweight local telemetry so maintainers can determine whether the workflow is becoming more reliable rather than merely more complicated.

## Event log

Runtime events are appended as JSON Lines to:

```text
.codex/runtime/metrics/events.jsonl
```

The log is derived operational telemetry. It is not a source of task authority and can be deleted without changing task status.

## Event types

### task_transition

Recorded by `advance-task.ps1`.

Useful fields include timestamp, task ID, from/to status, actor, workflow profile, and success.

### provider_attempt

Recorded by `provider-router.ps1`.

Useful fields include timestamp, provider, model, duration, success, and error category.

Raw prompts, repository context, API keys, and provider response content are intentionally not logged.

## Summary command

```powershell
.\scripts\summarize-metrics.ps1
```

Use `-AsJson` for machine-readable output.

## Interpretation

These metrics can show provider reliability, workflow rework, and latency trends. They do not by themselves measure code quality. Longitudinal quality measurement should eventually correlate workflow events with escaped defects, test failures, review rework, and release outcomes.
