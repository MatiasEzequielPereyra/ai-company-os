# Explicit Gemini Single-Attempt budget

Project: AI Company OS
Revision: 1
Updated: 2026-10-11
Updated by: CODEX-ORCHESTRATOR

## Contract boundary and correction

The Gemini adapter previously hardcoded `generationConfig.maxOutputTokens` and
reported `OutputLimit` to 12000, with no explicit thinking setting. Gate execution
and routing had no parameters to carry a different budget to that adapter.

The correction adds optional `-GeminiMaxOutputTokens` and
`-GeminiThinkingLevel` parameters to `run-gate-agent.ps1`, `provider-router.ps1`
and `providers/invoke-gemini.ps1`. Both parameters must be supplied together.
They require `-SingleAttempt`, exact provider `Gemini`, exact model
`gemini-3.8-flash`, an integer output limit from 1 through 65536, and exact
thinking level `low`. The authorized Run A target is 32768/low.

The process-local Single-Attempt module owns the shared side-effect-free
configuration assertion. Each entry point invokes it before output cleanup,
execution record creation or transport; the gate also checks before acquiring
its execution lease. Existing canonical validation and execution leases remain
required after configuration validation.

With neither parameter supplied, the adapter retains 12000 output tokens and
omits `thinkingConfig`. Other providers have no new payload or policy behavior.

## Payload, identity and evidence

Explicit options produce:

```json
{
  "generationConfig": {
    "maxOutputTokens": 32768,
    "thinkingConfig": { "thinkingLevel": "low" }
  }
}
```

The existing `responseJsonSchema` and grounded Review validation remain in
effect. The explicit budget contract additionally requires a nonempty
`modelVersion` exactly equal to the requested model. Missing identities,
different models, revision suffixes and prefix matches fail closed. This
deliberately does not accept a provider revision as an alias; compatibility
would require separate verified authority if the provider reports such a value.

`OutputLimit` and execution-record `output_limit` report the effective setting.
The opt-in record adds `thinking_level: low`; absent options retain the previous
record shape. Provider-reported prompt, completion, total and reasoning token
usage are preserved without inferring unknown usage. No schema or canonical
task-result contract changes are required; this is an additive optional journal
field, not a new acceptance or lifecycle authority.

Single-Attempt still permits one transport entry, with no automatic retry,
fallback or semantic repair. Timeout, 429/503, MAX_TOKENS, invalid JSON, rejected
identity and grounding failures retain failure evidence instead of being repaired
into approval. All frozen obligations and valid source citations are still
required for grounded Review publication.

## Operational restrictions

This implementation does not establish model availability, account quota or
Free Tier eligibility. A 32768 output ceiling also does not guarantee that a
particular response will complete; reasoning and finish metadata remain part of
the subsequent execution assessment.

No real provider was authorized for implementation validation. Historical Run A
and its existing operational candidate remain unchanged, AICO-002 remains
REVIEW, and no global installation is updated. After independent integration
authorization, prepare a separately verified operational copy and obtain separate
authority for one real Review. Do not run the existing candidate using this branch.

## Deterministic regressions

`test-project/tests/test-gemini-single-attempt-budget.ps1` verifies explicit and
legacy payloads, usage metadata, invalid arguments with output preservation and
zero transport, one-call transport failures, malformed results, strict model
identity, eleven-obligation coverage, exact citations and gate preflight
preservation of task/cache/locks. It is registered in the full smoke suite.

Full verification results and source hashes are recorded in the scoped handoff.
