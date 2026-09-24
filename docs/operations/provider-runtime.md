# Provider Runtime

AI Company OS routes all model execution through `scripts/provider-router.ps1`. The router normalizes provider selection, model defaults, error handling, metrics, and final JSON-schema validation.

## Providers

| Provider | Authentication | Default model | Cost behavior |
| --- | --- | --- | --- |
| Ollama | none for local runtime | `qwen3:8b` | local compute, no per-token API billing |
| OpenRouter | `OPENROUTER_API_KEY` | `openrouter/free` | free route by default |
| Gemini | `GEMINI_API_KEY` | `gemini-3.5-flash-lite` | provider quota/tier applies |
| DeepSeek | `DEEPSEEK_API_KEY` | `deepseek-flash` | paid API |
| Grok / xAI | `XAI_API_KEY` | `grok-4.7` | paid API |
| Codex CLI | local Codex login | configured default | uses Codex CLI account/quota |

## Safe automatic routing

`.codex/provider-config.json` contains the fallback order. The default order is:

```text
Ollama -> OpenRouter -> Gemini -> DeepSeek -> Grok -> Codex
```

However, `allow_paid_fallback` defaults to `false`. In Auto mode the router therefore skips DeepSeek and Grok unless this flag is explicitly enabled. Selecting either provider directly always remains possible.

## Ollama setup

Verify the local server:

```powershell
ollama list
Invoke-RestMethod http://localhost:11434/api/tags
```

Install the default model if needed:

```powershell
ollama pull qwen3:8b
```

Use another Ollama server by setting:

```powershell
$env:OLLAMA_BASE_URL = "http://localhost:11434"
```

Run an active task with Ollama:

```powershell
.\scripts\run-agent-task.ps1 -Id AICO-XXX -Provider Ollama
```

Override the model:

```powershell
.\scripts\run-agent-task.ps1 -Id AICO-XXX -Provider Ollama -Model "qwen3:8b"
```

## DeepSeek

Configure the API key for the current PowerShell session:

```powershell
$env:DEEPSEEK_API_KEY = "YOUR_KEY"
```

Then run:

```powershell
.\scripts\run-agent-task.ps1 -Id AICO-XXX -Provider DeepSeek
```

DeepSeek Chat Completions currently guarantees valid JSON with `response_format=json_object`; AI Company OS additionally includes the requested schema in the prompt and rejects any response that fails the local canonical schema validator.

## Grok / xAI

Configure:

```powershell
$env:XAI_API_KEY = "YOUR_KEY"
```

Then run:

```powershell
.\scripts\run-agent-task.ps1 -Id AICO-XXX -Provider Grok
```

The xAI adapter requests strict JSON-schema structured output and the router performs the same local contract validation used by every other provider.

## Auto mode

Run:

```powershell
.\scripts\run-agent-task.ps1 -Id AICO-XXX -Provider Auto
```

To allow paid providers as automatic fallbacks, edit `.codex/provider-config.json`:

```json
{
  "allow_paid_fallback": true
}
```

Keep this disabled when the goal is to prevent accidental API spend.

## Validation

Run the runtime contract test:

```powershell
.\test-project\tests\test-agent-runtime-contract.ps1
```

Run the complete suite:

```powershell
.\test-project\tests\run-all-smoke-tests.ps1
```
