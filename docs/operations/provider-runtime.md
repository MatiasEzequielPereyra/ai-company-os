# Provider Runtime

This document describes provider behavior implemented by the current main branch.

All normal model execution passes through **scripts/provider-router.ps1**, which applies provider selection, configured model defaults, bounded timeouts, output cleanup, metrics, JSON-schema validation, and optional semantic validation.

Provider availability and provider eligibility are different concepts. A provider adapter can exist without being selected by Auto.

## Provider matrix

| Provider | Authentication | Local/cloud | Current configured model | Timeout | Auto eligibility | Writable eligibility | Cost notes |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| Ollama | Local Ollama service | Local | Hardware/role selected; general config names qwen3:8b | 1800 s | General default; role-specific policies may skip it | Yes | Local compute; no per-token provider billing |
| OpenRouter | OPENROUTER_API_KEY | Cloud | openrouter/free; Engineering Manager analysis/writable override qwen/qwen3.8-27b:free | 240 s | Only when an Auto order explicitly includes it | Yes | Route/model behavior can change; explicit use can consume quota |
| Gemini | GEMINI_API_KEY | Cloud | gemini-3.5-flash-lite | 240 s | Only when an Auto order explicitly includes it | Yes | Provider quota/tier applies |
| Codex CLI | Local Codex CLI authentication/session | External service via CLI | No repository-wide fixed model name in provider config | 180 s | Role-specific Auto order can include it | No in writable runner | Uses Codex CLI account/quota |
| DeepSeek | DEEPSEEK_API_KEY | Cloud | deepseek-flash | 300 s | Can appear in configured analysis order, but paid fallback is skipped while allow_paid_fallback=false | No in writable runner | Treat as potentially paid |
| Grok / xAI | XAI_API_KEY | Cloud | grok-4.7 | 300 s | Can appear in configured analysis order, but paid fallback is skipped while allow_paid_fallback=false | No in writable runner | Treat as potentially paid |

Configured model names document repository configuration, not a promise that a remote provider will always continue serving the same model or pricing.

## General Auto

The default general order in **.codex/provider-config.json** is:

~~~text
Auto
└─ Ollama
~~~

There is no default general cloud fallback.

If Ollama is unavailable, unreachable, lacks an eligible installed model, or fails, general Auto fails after its configured candidates are exhausted.

Changing auto_order is an operator/project configuration decision. Do not assume that adding a provider to the config makes it free.

## Engineering Manager analysis Auto

Analysis routing can be overridden by role.

The current Engineering Manager order is:

~~~text
OpenRouter
→ Gemini
→ Ollama
→ Codex
→ DeepSeek
→ Grok
~~~

Important rules:

- OpenRouter and Gemini are skipped when their required keys are absent.
- On LOCAL_CPU_LOW, Ollama is explicitly skipped for Engineering Manager analysis.
- Codex is skipped when the CLI is not available.
- DeepSeek and Grok are skipped as automatic paid fallback while allow_paid_fallback=false.
- The order is not a guarantee that any candidate will succeed.
- Structured/semantic output validation still applies to every successful transport response.

This role-specific override is why documentation must not describe all Auto execution as identical.

## Gate Auto

Review, QA, and Security gate execution uses a separate routing policy from **.codex/provider-config.json**:

~~~text
gate_auto_order

Ollama -> OpenRouter -> Gemini -> Codex -> DeepSeek -> Grok
~~~

Gate Auto rules:

- Ollama remains the first candidate.
- Providers whose required credentials or CLI are unavailable are skipped.
- DeepSeek and Grok are skipped automatically while **allow_paid_fallback=false**.
- Explicit provider selection does not perform cross-provider fallback.
- JSON-schema validation still applies to every candidate response.
- When a gate supplies semantic validation, semantic validation also applies before a candidate result can be accepted.
- Truncated, invalid, or semantically unusable output is a failed candidate.

General Auto continues to use **auto_order**. Engineering Manager analysis can use **analysis_auto_order_by_role**. Writable Auto continues to use **writable_auto_order**.

## Writable Auto

Writable execution is a separate runtime implemented by **scripts/run-writable-agent.ps1**.

Supported writable providers:

~~~text
Auto
Ollama
OpenRouter
Gemini
~~~

Default writable Auto order:

~~~text
Auto → Ollama
~~~

When a non-Ollama provider is added to writable_auto_order, the writable runtime only treats it as an automatic candidate when its configured model is present in the **free_provider_models** allowlist in **.codex/writable-policy.json**.

This is a protection against accidental paid fallback. It is not a guarantee that the remote route has no quota, account, or pricing constraints.

Explicit provider selection remains an operator action and may consume provider quota.

Ollama writable execution passes the task role and `Workload=writable` to the
local resolver. Its effective context limit is the minimum of the writable
policy budget, a positive configured Ollama provider budget, and the resolver's
`ContextMaxChars`. Missing, invalid or unavailable runtime information rejects
execution before the provider adapter runs. Gate evidence compaction remains
specific to gates.

`writable_allow_paid_fallback` is retained for configuration/migration
compatibility but has no execution consumer. It does not override the free model
allowlist or enable additional writable providers; removal requires a separate
compatibility decision.

## Ollama and hardware-aware resolution

Ollama selection uses:

- **.codex/local-runtime-config.json**
- **scripts/local-runtime/detect-hardware.ps1**
- **scripts/local-runtime/resolve-local-runtime.ps1**

The resolver evaluates:

- detected RAM/CPU;
- discrete GPU/VRAM when available;
- installed Ollama models;
- configured maximum model size;
- role preferences;
- cached benchmark evidence;
- context and output budgets.

Current profiles are:

- LOCAL_CPU_LOW
- LOCAL_CPU_HIGH
- LOCAL_GPU_6GB
- LOCAL_GPU_8GB
- LOCAL_GPU_12GB
- LOCAL_GPU_16GB_PLUS

AI Company OS does not auto-pull Ollama models.

The Providers TUI manages OpenRouter, Gemini, DeepSeek and Grok/xAI credentials
through the secure credential store, with masked inputs and no saved-secret
prefill. Codex is shown as CLI detection; Ollama is shown as resolver availability
for the selected project's local analysis candidate, including service and model
usability. CLI detection alone does not assert an authenticated Codex session.
Plan Control inspects the local candidate for the active role/workload in a
background worker; it does not claim that every Auto workload selects Ollama.

Python execution services inject credentials only for explicit providers or
configured workload candidates. Analysis honors role orders and the paid fallback
switch; writable Auto additionally filters cloud candidates through the free
model allowlist. Control and local-inspection subprocesses receive no provider
keys. This filtering does not grant provider eligibility: PowerShell routing and
writable policy remain authoritative.

Initialize/benchmark the local runtime:

~~~powershell
.\scripts\local-runtime\initialize-local-runtime.ps1
~~~

Inspect installed models:

~~~powershell
ollama list
~~~

The system doctor specifically checks whether qwen3:8b is installed because it is the repository's configured general model. The hardware resolver can still choose another installed eligible model according to role preferences and profile limits.

## Explicit provider examples

Ollama:

~~~powershell
.\scripts\run-agent-task.ps1 -Id AICO-XXX -Provider Ollama
~~~

OpenRouter:

~~~powershell
$env:OPENROUTER_API_KEY = "..."
.\scripts\run-agent-task.ps1 -Id AICO-XXX -Provider OpenRouter
~~~

Gemini:

~~~powershell
$env:GEMINI_API_KEY = "..."
.\scripts\run-agent-task.ps1 -Id AICO-XXX -Provider Gemini
~~~

DeepSeek:

~~~powershell
$env:DEEPSEEK_API_KEY = "..."
.\scripts\run-agent-task.ps1 -Id AICO-XXX -Provider DeepSeek
~~~

Grok/xAI:

~~~powershell
$env:XAI_API_KEY = "..."
.\scripts\run-agent-task.ps1 -Id AICO-XXX -Provider Grok
~~~

Never commit provider keys.

## Timeouts and failure handling

Current configured provider timeouts:

| Provider | Seconds |
| --- | ---: |
| Codex | 180 |
| OpenRouter | 240 |
| Gemini | 240 |
| Ollama | 1800 |
| DeepSeek | 300 |
| Grok | 300 |

The router rejects timeout values outside 1–3600 seconds.

When a provider attempt fails or times out:

- the error is categorized for operational evidence;
- secrets present in known provider-key environment variables are redacted from router error messages;
- a partial structured output file is removed;
- Auto can continue only when another candidate actually exists in the applicable configured order.

No lifecycle state should be advanced manually merely because a provider failed.

## Structured output

Provider transport success is not enough.

The router requires the output file and validates it against the supplied JSON schema. Some workflows also add a semantic validator. Invalid or semantically unusable structured output is a failed provider attempt.

## Cost boundary

The repository cannot guarantee the price, quota, or future availability of third-party APIs.

Use these rules:

- local Ollama uses local compute;
- OpenRouter model names ending in a free route are intended as free-route configuration but remain subject to provider policy;
- Gemini is subject to the account/tier in use;
- DeepSeek and Grok should be treated as potentially paid;
- Codex uses the authentication/quota of the installed Codex CLI;
- allow_paid_fallback=false prevents DeepSeek/Grok from silently entering Auto as paid fallback, but does not make explicit cloud use free.

## Related documentation

- [Local runtime](./local-runtime.md)
- [Update and ownership](./update-ownership.md)
- [Troubleshooting](../TROUBLESHOOTING.md)
- [User Guide](../USER-GUIDE.md)
