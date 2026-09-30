# Hardware-Aware Local Runtime

AI Company OS can resolve an installed Ollama model and safe inference budget from local hardware and cached benchmark evidence.

This capability supports local execution; it does not make Ollama mandatory for installation.

## Detection

**scripts/local-runtime/detect-hardware.ps1** gathers the information needed to classify the machine, including RAM, CPU and available GPU/VRAM signals, plus the locally visible Ollama models.

**scripts/local-runtime/resolve-local-runtime.ps1** combines that detection with **.codex/local-runtime-config.json**.

## Capability profiles

Current profile names:

| Profile | Intended class |
| --- | --- |
| LOCAL_CPU_LOW | constrained CPU-only or low local capability |
| LOCAL_CPU_HIGH | stronger CPU-only class |
| LOCAL_GPU_6GB | discrete GPU around 6 GB VRAM |
| LOCAL_GPU_8GB | discrete GPU around 8 GB VRAM |
| LOCAL_GPU_12GB | discrete GPU around 12 GB VRAM |
| LOCAL_GPU_16GB_PLUS | discrete GPU at or above the highest current configured class |

The exact model-size, context, generation and benchmark thresholds live in **.codex/local-runtime-config.json** and should not be duplicated as informal guesses elsewhere.

## Role-aware selection

The resolver uses role preferences before falling back to the largest installed model that fits the detected profile.

General roles prefer the configured general-purpose model order. Technical roles such as CTO, Engineering Manager, Backend, Frontend and DevOps prefer coder-oriented models first.

Only installed models are considered. AI Company OS does not automatically download a model.

## Benchmark cache

Initialization can write machine-local evidence under:

~~~text
.codex/runtime/local-capability.json
.codex/runtime/local-benchmarks.json
~~~

A cached model can be excluded from automatic selection when benchmark evidence reports failure or generation throughput below the profile minimum.

The benchmark cache is hardware-fingerprint-aware and has a configured TTL.

Run:

~~~powershell
.\scripts\local-runtime\initialize-local-runtime.ps1
~~~

## Dynamic execution budgets

The selected profile supplies:

- num_ctx;
- num_predict;
- general context budget;
- gate context budget;
- gate artifact budget;
- maximum safe model size;
- minimum benchmark throughput.

This allows the same project to use conservative limits on a CPU-only workstation and larger contexts/models on a stronger GPU machine.

## Explicit model override

For explicit Ollama execution, a model can be requested with -Model.

The resolver still rejects an installed model that exceeds the current safe profile unless the operator deliberately sets:

~~~powershell
$env:AICO_OLLAMA_ALLOW_OVERSIZE = "1"
~~~

That escape hatch is for intentional diagnostics. It can cause severe RAM pressure or timeouts and is not used by automatic resolution.

## Auto behavior

Do not confuse local resolution with provider fallback.

For **general Auto**, current provider configuration contains only:

~~~text
Ollama
~~~

If local resolution fails, general Auto has no default cloud candidate to continue to.

For **Engineering Manager analysis**, role-specific provider configuration can place cloud/Codex candidates before or after Ollama. On LOCAL_CPU_LOW, Ollama is explicitly skipped for this role.

For **writable Auto**, the current default is also Ollama. Cloud writable candidates participate automatically only when added to writable_auto_order and accepted by the free-model policy.

See [Provider Runtime](./provider-runtime.md).

## Common unavailable reasons

The resolver reports unavailable when, for example:

- Ollama is not reachable;
- no installed model fits the detected profile;
- the requested explicit model is not installed;
- an explicit model is too large for the profile and the operator did not opt into oversize execution.

Treat these as runtime diagnostics, not as reasons to alter task state manually.

## Validation

Relevant deterministic tests include:

~~~powershell
.\test-project\tests\test-local-runtime-profile.ps1
.\test-project\tests\test-hardware-provider-reconcile.ps1
.\test-project\tests\test-provider-router-contract.ps1
~~~
