# Hardware-Aware Local Runtime

AI Company OS treats Ollama as a local execution pool, not as one fixed model.

The local runtime combines:

1. hardware detection;
2. safe capability classification;
3. installed-model discovery;
4. role-aware model preference;
5. optional measured Ollama throughput;
6. dynamic context and generation budgets.

## Detection

`scripts/local-runtime/detect-hardware.ps1` detects:

- total RAM;
- CPU name and logical processor count;
- discrete GPU when available;
- NVIDIA VRAM through `nvidia-smi` when available;
- fallback Windows video-controller information;
- Ollama reachability;
- installed Ollama model names and sizes.

It emits a stable hardware fingerprint, a capability profile, and a 0-100 capability score.

## Capability profiles

The canonical thresholds live in `.codex/local-runtime-config.json`.

| Profile | Intended class | Local behavior |
| --- | --- | --- |
| `LOCAL_CPU_LOW` | low-memory / integrated-GPU machines | conservative model size, 8K context |
| `LOCAL_CPU_HIGH` | high-RAM CPU machines | larger model allowance, moderate context |
| `LOCAL_GPU_6GB` | entry discrete GPU | small/medium models |
| `LOCAL_GPU_8GB` | mid local GPU | larger context and output |
| `LOCAL_GPU_12GB` | strong local GPU | coder 14B-class models can fit when installed |
| `LOCAL_GPU_16GB_PLUS` | high local GPU memory | largest configured local budgets |

These are safety defaults, not claims that every model with a matching file size will perform equally well.

## Role-aware selection

`scripts/local-runtime/resolve-local-runtime.ps1` selects only installed models.

General roles such as PM/CEO/QA prefer the configured general model. Technical roles such as backend/frontend/CTO/engineering-manager prefer configured coder models when the detected profile can safely host them.

A model that exceeds the profile's `max_model_bytes` is excluded. Explicit oversized overrides are also rejected unless:

```powershell
$env:AICO_OLLAMA_ALLOW_OVERSIZE = "1"
```

## Benchmarking

Run:

```powershell
.\scripts\local-runtime\initialize-local-runtime.ps1
```

Initialization writes:

```text
.codex/runtime/local-capability.json
.codex/runtime/local-benchmarks.json
```

Both are machine-local runtime artifacts and are ignored by Git.

The benchmark uses a short deterministic Ollama generation and records:

- load time;
- prompt throughput;
- generation throughput;
- total elapsed time;
- success/failure.

Models known to be too large for the detected profile are not benchmarked automatically.

Force a specific safe benchmark:

```powershell
.\scripts\local-runtime\benchmark-ollama.ps1 -Model "qwen2.5-coder:14b" -Force
```

A cached model whose generation throughput falls below the profile minimum is excluded from automatic selection even if its file size fits.

## Dynamic execution budgets

The selected profile supplies:

- `NumCtx`;
- `NumPredict`;
- analysis repository-context budget;
- gate base-context budget;
- gate artifact budget.

`run-agent-task.ps1`, `run-gate-agent.ps1`, `provider-router.ps1`, and `invoke-ollama.ps1` consume those values.

This means the same repository can run conservatively on a 16 GB CPU-only workstation and automatically use larger local models/context on a 32 GB / 12 GB VRAM development PC.

## Fallback behavior

In `-Provider Auto`:

1. the resolver checks whether a suitable local model exists;
2. if not, Ollama is skipped cleanly;
3. routing continues to the configured cloud/free fallbacks;
4. paid DeepSeek/Grok fallbacks remain disabled unless explicitly allowed.

If Ollama is usable but later fails during inference, Auto can still continue to the next provider. The repository context for that execution remains bounded to the local profile because context is built before provider fallback.

## Validation

Run:

```powershell
.\test-project\tests\test-local-runtime-profile.ps1
.\test-project\tests\run-all-smoke-tests.ps1
```

The deterministic profile test simulates both a low-resource integrated-GPU machine and a 32 GB RAM / 12 GB discrete-GPU machine without requiring real Ollama hardware in CI.
