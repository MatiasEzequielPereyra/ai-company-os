# AI Company OS System Architecture

## Architectural style

AI Company OS is a repository-native workflow engine. It intentionally avoids a database-backed control plane: durable Markdown and JSON artifacts live beside the code they govern, while PowerShell scripts enforce transitions and generate derived state.

The architecture favors inspectability and portability over centralized automation.

## Component model

### Authoritative artifacts

- `tasks/AICO-*.md`: task objective, status, owner, profile, acceptance criteria, dependencies, evidence, and transition history.
- `docs/product/`: product scope and requirements.
- `docs/architecture/` and `docs/decisions/`: architecture context and accepted decisions.
- `docs/engineering/`: plans, dispatch packets, result evidence, independent reviews, QA/security artifacts, and handoffs.

### Derived artifacts

- `.codex/state/current-sprint.md`
- `.codex/state/company-state.md`
- `.codex/state/blockers.md`

Derived state is an index. It must never override a task or owned product/architecture decision.

### Runtime

PowerShell scripts under `scripts/` implement intake, task materialization, readiness, dispatch, lifecycle transitions, provider routing, quality gates, validation, workspace isolation, and metrics.

### Provider boundary

`scripts/provider-router.ps1` is the only provider-selection boundary.

Provider adapters:

- Codex CLI: repository inspection in read-only sandbox.
- OpenRouter: bounded context pack plus JSON schema request.
- Gemini: bounded context pack plus JSON schema request.
- Ollama: local HTTP runtime with schema-constrained structured output.
- DeepSeek: OpenAI-compatible HTTP provider using JSON output plus local schema validation.
- xAI/Grok: OpenAI-compatible HTTP provider using strict JSON-schema structured output.

All provider output must pass the same local JSON contract validation before downstream workflow code trusts it. Automatic paid-provider fallback is disabled by default; explicit provider selection remains available.

### Validation boundary

JSON schemas under `schemas/` define canonical normalized contracts. Markdown tasks/state are parsed into normalized objects by `scripts/validate-artifacts.ps1`.

This keeps Markdown usable for humans while still providing a machine-enforceable contract.

## State model

Ticket status and project workflow phase are separate concepts.

Canonical ticket statuses:

```text
BACKLOG, READY, ACTIVE, REVIEW, QA, SECURITY, DONE, BLOCKED
```

The broader workflow policy may also describe PRODUCT, ARCHITECTURE, RELEASE, CANCELLED, and equivalent project-level phases.

The operational mapping is:

- ACTIVE -> IN_PROGRESS / implementation
- REVIEW -> CODE_REVIEW
- QA -> QA
- SECURITY -> SECURITY
- DONE -> completed

Scripts must not add project-level phases as ad-hoc ticket statuses.

## Workflow profiles

`.codex/workflow-profiles.json` defines three profiles:

- lightweight
- standard
- high-assurance

Profiles tune assurance expectations but do not create a second lifecycle. Existing tasks without a profile normalize to `standard`.

High-assurance tasks may not mark the security gate NOT_APPLICABLE.

## Concurrency and isolation

### Read-only shared execution

The existing `run-active-agents.ps1 -Parallel` path is safe only while its agents remain read-only analysis workers. They may generate task-specific runtime/report artifacts but must not edit shared production code.

### Writable isolated execution

Any agent authorized to mutate code must work on its own Git branch/worktree. Use `scripts/new-agent-workspace.ps1`.

The framework intentionally does not auto-merge those branches. Integration requires review because independent task branches can still have semantic conflicts even when filesystem isolation prevents write races.

## Failure model

- Invalid task metadata fails validation before trusted workflow automation.
- Invalid provider configuration fails before provider execution.
- Provider errors are sanitized so configured secrets are not echoed.
- Transient HTTP failures may be retried by adapters.
- Provider output that is syntactically valid JSON but violates the requested schema is rejected locally.
- Derived state can be regenerated from tasks.
- A failed gate returns work to READY rather than silently rewriting evidence.

## Observability

Operational events are appended to `.codex/runtime/metrics/events.jsonl`.

Event classes include lifecycle transitions and provider attempts. The log is append-only local telemetry and can be summarized with `scripts/summarize-metrics.ps1`.

See `docs/operations/observability.md`.

## Security posture

- Secret-bearing environment files are excluded from external context packs.
- Provider errors are redacted at the router boundary.
- Codex API key authentication is disabled in the built-in Codex adapter to avoid accidental paid API execution.
- Mutation authority is separate from task readiness.
- Worktree isolation prevents two writable agents from sharing the same checkout.
- Release/deployment remains outside implicit agent authority.
