# Automatic Error Intelligence runtime integration

Project: AI Company OS
Revision: 1
Updated: 2026-10-10
Owner: Runtime Engineering
Authorization: Human requested automatic operation and approved deterministic tests and packed E2E with simulated providers.
Base: eebc633009b09b6cce354aecbf0dfa4938e90b41

## Behavior

The installed runtime automatically sends typed failure observations to the existing local Error Intelligence SQLite store. Operators do not need to call the Python API to record incidents. Capture is enabled by default; `AICO_ERROR_INTELLIGENCE_ENABLED=0` disables capture and historical lookup for that process and its children.

The operational JSONL writer is the shared capture boundary. Only the canonical failed `provider_attempt_finished` event is consumed: timeout/attempt alias events are ignored to avoid counting the same provider failure multiple times. Context budget rejection is also captured. Analysis, gate and writable catches capture failures outside provider execution. Python process launch errors and timeouts are captured for known AICO runner commands. A provider failure and a runner rejection are separate observations of separate components, not two occurrences of one provider incident.

BLOCKED and rejected Review/QA/Security transitions are stored as lifecycle observations, not proof of a runtime defect. READY, SUCCESS, DONE or a successful provider response never verifies a root cause or fix automatically.

Automatic capture searches the same project's relevant historical component/error family. It displays the incident ID, occurrence count, availability of verified historical recommendations and bounded recommendations as quoted JSON data. Recommendations remain untrusted historical advice requiring current verification. No recommendation is executed or injected into provider prompts, grounding evidence, role contracts or budgets.

## Boundaries and persistence

- Project identity hashes the canonical project root; absolute paths are not persisted. Moving the project changes its identity. Projects with identical names in different directories remain separate.
- Installation identity and SQLite location follow Error Intelligence v1. `AICO_ERROR_INTELLIGENCE_PATH` optionally selects an absolute local database path.
- Capture stores an allowlist of event kind, component, error category, task ID, UUID run ID, recognized role/workload/state and locally generated timestamp. Raw exception text, prompts, provider bodies, reasoning, arbitrary actor/reason/path fields and model identifiers are excluded.
- Grouping by component/category identifies a recurring operational family, not a verified shared root cause. Responses explicitly mark causal equivalence unverified.
- Lifecycle transitions and runner success do not prove a proposed action was applied or validated. Root cause and fix verification remain explicit evidence-bearing operations in the existing store API.
- Query APIs use SQLite URI read-only/query-only access, validate the schema version and integrity, and do not create a missing database.
- The bridge sends at most 16 KiB of input. The PowerShell process is bounded, uses explicit UTF-8 stdin and creates no visible window. It never invokes a provider.
- Database/interpreter/lock failures produce a typed unavailable diagnostic. They cannot replace the runner's original exception, alter its exit status, authorize retry/fallback, or mutate tasks. Existing operational JSONL remains intact where a lease permits it. Prelease failure capture writes only to the external incident store.

## Installed runtime discovery

`ProviderService.build_execution_environment` binds project scripts to the current installed Python executable and module location. This works when installed projects have scripts but no Python source tree. Direct PowerShell use can supply `AICO_ERROR_INTELLIGENCE_PYTHON` and `AICO_ERROR_INTELLIGENCE_MODULE_ROOT`; engine source/venv or an installed Python module can also be discovered. Unavailable discovery is reported visibly.

The helper is managed by new/install/update; npm includes the Python module and helper. Existing projects require the updated installed package and its normal `aico update <project>` operation. Frozen acceptance engines are deliberately not updated by this implementation.

The package-local Python marker also records a deterministic SHA256 of `pyproject.toml` and Python source files. Code changes with an unchanged package version therefore reinstall the Python runtime instead of retaining stale code. Legacy version-only markers trigger one refresh. Cache files are excluded; the fingerprint is recorded only after successful installation.

## Operator interface

```text
aico errors --project <project>
aico errors --project <project> --json
aico errors --project <project> --component provider-router/openrouter
aico doctor --project <project>
```

`errors` reads bounded history and verified historical recommendations; `doctor` automatically reports the presence of incident history or unavailable storage. TUI views that use DoctorService receive the same summary. No separate screen or automatic correction is added.

No background watcher, historical evidence import, provider configuration change, automatic model call, automatic fix verification or acceptance continuation is introduced.

## Verification

Deterministic regressions cover real PowerShell-to-Python capture to temporary SQLite on WinPS5.1 and PS7, duplicate filtering, optout, UTF-8 transport, unavailable storage, project isolation, rejected gates, stale recommendations, unknown schemas, read-only byte preservation, CLI and installed environment binding, process launch/timeout preservation, and existing grounding/SingleAttempt contracts.

Packed E2E exercises the actual installed package Python environment, installed project writer, two occurrences, SQLite history and `aico errors`, using a synthetic failure event and no provider. Full suite outcomes and exact package identity are recorded in the successor handoff.
