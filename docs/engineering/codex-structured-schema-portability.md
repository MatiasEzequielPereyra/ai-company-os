# Codex structured schema portability

Project: AI Company OS
Revision: 1
Updated: 2026-10-04
Updated by: CODEX-ORCHESTRATOR
Base: 6e70d64029526cd65df791ddefc8de0065f3c83a

## Incident and evidence

Run 6 recovery left AICO-003 (engineering-manager) ACTIVE. The operator reported Codex `invalid_json_schema`: root `required` omitted `execution_blocker`. The approved base adapter passed the canonical schema directly to `codex exec --output-schema`. Both result schemas deliberately make that field optional. Run 6 metrics events 62–74 corroborate provider failures and fallback; the exact API error is sourced from the user's incident receipt, not from the metrics (which record category `unknown`). No acceptance retry was executed in this change.

[OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs) requires all object properties to be required and objects to disallow additional properties. Optional values can be represented by a nullable field. This is a provider representation concern.

## Adapter boundary

`scripts/providers/invoke-codex.ps1` independently parses canonical and provider copies. It recursively closes objects, requires their declared properties and wraps originally optional nonnullable properties in `anyOf` with a null alternative. It writes a unique temporary schema and passes that path to Codex. Canonical schemas are never rewritten by the adapter.

The response is normalized against the original canonical tree: only null values for originally optional nonnullable fields are omitted. Required nulls, unknown fields and real blockers survive normalization and remain subject to validation. The adapter validates canonical structure; the router retains its existing semantic validation, same-provider repair and fallback. COMPLETED plus a real blocker remains invalid. BLOCKED still requires concrete external evidence and `role_can_resolve=false`.

This conversion supports the object/array schemas used by current provider results. Canonical unions/references/definitions and explicitly open objects fail before CLI execution; it does not claim arbitrary JSON Schema portability. No other provider adapter, routing order or semantic validator changed. Schema, prompt and runner temporary files share cleanup on success, preparation failure, CLI failure and timeout; invalid output is removed.

## Authorized canonical correction

Testing exposed a separate pre-existing contradiction: the Engineering Manager schema required `executable_work` with at least one item, while its semantic validator required zero items for BLOCKED. After a specific clarification, the user authorized the appropriate minimum correction. Only that array's `minItems` changes from 1 to 0. The field remains required, its item contract stays unchanged, and semantic validation still rejects COMPLETED with no executable work and BLOCKED with executable work. `execution_blocker` remains optional and nonnullable in both canonical schemas.

## Deterministic verification

`test-codex-schema-portability.ps1` invokes the real adapter through a fake CLI. The fake independently checks strict object structure and the nullable blocker branch. Cases cover generic/Engineering Manager COMPLETED and BLOCKED, exact semantic rejections, required-null rejection, nested optional-null normalization, unchanged canonical files during invocation, and cleanup on CLI error, timeout and malformed schema preparation. The existing canonical validator alone cannot validate `anyOf`; the independent strict checks are therefore essential.

The full smoke runner includes this regression. Packed release E2E checks exact adapter and schema hashes in new, existing and updated managed projects. All provider executions used for verification are deterministic fakes.

## Separate follow-ups

- Gemini HTTP 400 INVALID_ARGUMENT: retain the incident for separate diagnosis. Its adapter already translates schemas; no shared cause is established.
- OpenRouter invalid JSON: separate structured-result reliability investigation.
- Ollama qwen3:8b invalid COMPLETED plus blocker after repair: separate model reliability issue; semantic rejection remains required.
- Global Codex role TOML warnings about missing `developer_instructions`: separate configuration hygiene. The task prompt was delivered; no evidence ties these warnings to schema registration failure.
- One local smoke run exceeded the existing total fallback timing threshold although timeout and fake fallback succeeded. An isolated rerun passed without changes. Preserve logs; no threshold or process behavior was relaxed.

Run 6 and historical evidence remain frozen. Merge and any functional acceptance retry require a later explicit authorization.
