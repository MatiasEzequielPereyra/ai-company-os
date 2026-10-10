# Single-Attempt Provider Execution v1

Project: AI Company OS
Revision: 1
Updated: 2026-10-10T15:29:48.6533786Z
Updated by: CODEX-ORCHESTRATOR
Base: 5aedfbbb0ed897e8b4c8076f44863379e5d03d53

## Authority and scope

Human authorization: SINGLE-ATTEMPT PROVIDER EXECUTION v1, pasted attachment
332de57f-0e38-4f66-8130-3044a0116b2a. Implement, test with simulated transports,
commit and publish a draft PR. Run A remains HOLD and AICO-002 REVIEW. No real
provider, acceptance continuation, existing user installation update or merge.
Parallel Skills, TUI UX and Error Intelligence work is outside this branch.

## Invocation audit of the approved baseline

Call sites below refer to the baseline before this implementation.

| Component | Call site | Retry behavior | Fallback behavior | Controllable | Proposed change |
|---|---|---|---|---|---|
| Gate runner | run-gate-agent.ps1:508 | Delegates to router | Delegates to router | Yes | Propagate explicit opt-in and shared execution context |
| Router | provider-router.ps1:712,774,812 | Initial invocation plus semantic repair | Auto candidate loop, including configured paid fallback | Yes | Require explicit identity, bypass repair, stop on failure |
| OpenRouter | providers/invoke-openrouter.ps1:162 | Up to three POST invocations | Upstream routing fallback enabled by omission | AICO calls and request settings | One POST invocation; pin endpoint, allow_fallbacks=false |
| Gemini | providers/invoke-gemini.ps1:163 | Up to three POST invocations | No adapter model/provider fallback | Yes | One POST invocation, metadata and completion checks |
| DeepSeek | providers/invoke-deepseek.ps1:107 | Up to three POST invocations | No adapter model/provider fallback | Yes | One POST invocation, metadata and completion checks |
| Grok | providers/invoke-xai.ps1:101 | Up to three POST invocations | No adapter model/provider fallback | Yes | One POST invocation, metadata and completion checks |
| Ollama | providers/invoke-ollama.ps1:130 | Up to three POST invocations | Local resolver selects model before generation | Yes | Require explicit installed model; one POST invocation |
| Codex | providers/invoke-codex.ps1:137,171 | External agent CLI can perform opaque internal invocations | External configuration | Not established | Reject SingleAttempt before spawning |
| JSON/schema validators | validate-json-contract.ps1 | Local parsing and validation only | None | Yes | Preserve local validation |
| Semantic validators | validate-gate-result-semantics.ps1 | Local validation only; router decides regeneration | None locally | Yes | Preserve guards; forbid router regeneration |

HTTP adapters use Invoke-RestMethod directly, without a provider SDK. Their
transient loops handle timeout, 429 and 5xx; authentication and contract failures
also return to the router. Default mode retains those paths. SingleAttempt uses
one loop iteration, zero redirects, and explicitly zero PowerShell 7 transport
retries. There is no schema regeneration path enabled by the new policy.

## Public contract

`provider-router.ps1` and `run-gate-agent.ps1` accept `-SingleAttempt`.
Provider must be explicit, model must be explicit, and OpenRouter additionally
requires `-ProviderEndpoint` (the upstream routing tag). Dynamic OpenRouter
routes and routing suffixes are rejected. Codex is unsupported. Explicitly
selected paid providers are possible; no fallback silently selects one.

Examples below describe commands only; this ticket executes no provider:

```powershell
.\scripts\run-gate-agent.ps1 -ProjectPath <project> -Id AICO-002 -Gate Review `
  -Provider OpenRouter -Model <explicit-model> -ProviderEndpoint <endpoint-tag> `
  -SingleAttempt
```

HTTP adapters receive the same opaque process-local execution context. Registered
reference identity, configured provider/model/endpoint and attempt state are
checked before transport. A reconstructed JSON context is not a capability.
The adapter increments and persists the counter immediately before entering its
generation POST invocation. Completed contexts cannot initiate another call.

`attempts_started` counts AICO's entries into the generation transport boundary,
not confirmed remote processing, packets, server-side inference or infrastructure
operations. Zero denotes a preflight stop; one may succeed or fail. A process
crash may leave an IN_FLIGHT record; it is not success evidence or permission to
resume. The policy does not control opaque operations inside external services.

## Fail-closed behavior

Preflight rejects ambiguous identity, unavailable credentials/components,
unsupported adapters and protected context that cannot fit the existing budget.
Known cloud output limits remain 12000; Ollama keeps the selected hardware budget
and rejects invalid explicit limits in this mode. No arbitrary budget increase or
promise of model quality is introduced. Model-reported completion state, refusal
and identity are checked before a usable output is returned. Revision aliases
that do not exactly match a reported pinned model can therefore fail closed.

Canonical schema and semantic validation run locally. Invalid, partial, truncated
or unsupported output is removed from the consumable output path. No semantic
repair or provider/model fallback occurs. Grounded Review still requires the
immutable snapshot, exact obligation coverage, primary citations, drift guards
and publication receipt. Citation Spans v1 retains its existing contract.

The gate shares the execution record, preserves its final validation/publication
guards, and rejects failure before downstream gate execution. A later gate
rejection can downgrade a locally validated record to INVALID; it cannot enable
another invocation. Local validation is not equivalent to semantic correctness
of every reviewer judgment or real acceptance E2E success.

The gate acquires its verified execution lease before creating evidence or
cleaning the canonical output. A task or maintenance conflict therefore leaves
another invocation's output intact. Rejection before the lease/context exists
reports zero initiated calls and explicitly no execution record; it does not
write into a project held by maintenance or fabricate a receipt.

## Evidence and confidentiality

Records live in `.codex/runtime/single-attempt-executions/<execution-id>.json`.
They contain mode, selected provider/model/endpoint, observed attempt count,
duration, local validation status and typed error category. Requested output
limit and provider-reported model, finish reason and usage are retained when
available. Unavailable usage is null, never fabricated zero. Provider-reported
values are distinct from the locally observed counter.

No raw response, prompt, credential, HTTP body or hidden reasoning is added to
these records. Identity/metadata fields are bounded and filtered for configured
secrets. Failures expose typed diagnostics instead of arbitrary provider prose.
Persisted evidence is diagnostic data and cannot recreate process capabilities.

## Verification boundary

Deterministic tests invoke the real adapters with a simulated transport and spy
counts; they cover normal retries/repair, single success, zero-call preflight,
transport failures, invalid contracts, truncation, alternative models, blocked
fallback, partial files, secret handling and capability forgery/reuse. The real
gate fixture checks invalid output leaves REVIEW unchanged and valid grounded
CHANGES_REQUIRED publishes 11 assessments and a citation span in the sidecar.
All projects used by these tests and package new/install/update are disposable.
No simulated result is represented as real acceptance/provider success.

## Validation results and preexisting failures

- Windows PowerShell 5.1 full smoke: 68/68 PASS, 96.8 seconds.
- New deterministic regressions: 262 assertions PASS on WinPS 5.1 and PS7.
- Python full suite: 209/209 PASS, 89.37 seconds. Human clarification explicitly
  permits the two deterministic TUI tests, with simulated providers only.
- npm: 2/2 PASS. Packed installed new/install/update: PASS, including helper
  presence, byte hash and managed-file ownership. Tarball SHA256:
  01061194b63f46b5c0560bd0dc501cbdbd04b5c058188cbe338debdbd1f91683.
- Initial WinPS runs failed static checks for the former literal maxAttempts=3
  and unguarded lock release. Updated checks explicitly retain normal three
  attempts and single one attempt, with lock release still required. The final
  full run passes; these failed runs are retained in external validation logs.
- PS7 full smoke: FAIL, stops at test-new-project-contract.ps1 with
  `$.generated must be a string.` Reproduced on unchanged baseline c192634
  (source-identical to merged 5aedfbbb). Relevant Git blobs match both baselines:
  new-project.ps1 1ae0fe10e55f35ca1cdbebbd1c20c265cb02d658 and test
  dfdfdc8de4f22b1f0c89dcbca79ae63aaf491acd.
- Additional PS7 test-gemini-engineering-plan-compatibility.ps1 fails with
  `$ must be an array.` Also reproduced unchanged on that baseline. Matching
  baseline blobs: test a1e4ea599d4a64a649d557e27ca0f57bb8af61cf,
  validate-json-contract.ps1 1710f1d553c6b1d5eed6ce8b15faf2bb71709d1a,
  invoke-gemini.ps1 40adcdaded64e5fb752d6797d80d1c47e69edfaa.
- Remaining selected PS7 router, OpenRouter truncation, Ollama reliability,
  Gemini compatibility, gate reliability, runtime/canonical contracts and
  Grounding/Citation Spans regressions PASS. This does not represent a complete
  PS7 smoke PASS or omit either known failure.

Evidence directory:
Z:\repos\ai-company-os\temp-tests\single-attempt-provider-execution-v1-validation.
Frozen continuation fixture and preflight evidence: 340 recorded hashes unchanged.
No historical sixth maintenance-lease regression is reclassified as PASS.
