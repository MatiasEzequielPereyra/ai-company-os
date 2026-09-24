param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$detectPath = Join-Path $repoRoot "scripts\local-runtime\detect-hardware.ps1"
$resolvePath = Join-Path $repoRoot "scripts\local-runtime\resolve-local-runtime.ps1"
$configSource = Join-Path $repoRoot ".codex\local-runtime-config.json"

foreach ($required in @($detectPath,$resolvePath,$configSource)) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Local runtime test dependency missing: $required"
    }
}

$tempRoot = Join-Path $env:TEMP ("aico-local-runtime-" + [Guid]::NewGuid().ToString("N"))
$oldOversize = $env:AICO_OLLAMA_ALLOW_OVERSIZE

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".codex\runtime") | Out-Null
    Copy-Item $configSource (Join-Path $tempRoot ".codex\local-runtime-config.json")

    $lowFixture = Join-Path $tempRoot "hardware-low.json"
    @'
{
  "cpu_name": "Office CPU",
  "logical_processors": 8,
  "ram_bytes": 17179869184,
  "gpu_name": "Intel(R) UHD Graphics 630",
  "gpu_vendor": "Intel",
  "gpu_vram_bytes": 1073741824,
  "gpu_discrete": false,
  "ollama_reachable": true,
  "ollama_models": [
    { "name": "llama3.1:8b", "size": 4920753328 },
    { "name": "qwen2.5-coder:14b", "size": 8988124298 }
  ]
}
'@ | Set-Content $lowFixture -Encoding UTF8

    $highFixture = Join-Path $tempRoot "hardware-high.json"
    @'
{
  "cpu_name": "Desktop CPU",
  "logical_processors": 16,
  "ram_bytes": 34359738368,
  "gpu_name": "NVIDIA GeForce RTX 5070",
  "gpu_vendor": "NVIDIA",
  "gpu_vram_bytes": 12884901888,
  "gpu_discrete": true,
  "ollama_reachable": true,
  "ollama_models": [
    { "name": "llama3.1:8b", "size": 4920753328 },
    { "name": "qwen2.5-coder:14b", "size": 8988124298 }
  ]
}
'@ | Set-Content $highFixture -Encoding UTF8

    $lowHardware = & $detectPath -FixturePath $lowFixture
    if ([string]$lowHardware.profile -ne "LOCAL_CPU_LOW") {
        throw "16 GB integrated-GPU fixture must resolve to LOCAL_CPU_LOW"
    }

    $highHardware = & $detectPath -FixturePath $highFixture
    if ([string]$highHardware.profile -ne "LOCAL_GPU_12GB") {
        throw "32 GB / 12 GB discrete-GPU fixture must resolve to LOCAL_GPU_12GB"
    }

    $lowBackend = & $resolvePath -ProjectPath $tempRoot -Role "backend" -Workload "analysis" -HardwareFixturePath $lowFixture
    if (-not [bool]$lowBackend.Available) { throw "Low hardware fixture must have a usable local model" }
    if ([string]$lowBackend.Model -ne "llama3.1:8b") {
        throw "Low hardware must reject oversized qwen2.5-coder:14b and select llama3.1:8b"
    }

    $highBackend = & $resolvePath -ProjectPath $tempRoot -Role "backend" -Workload "analysis" -HardwareFixturePath $highFixture
    if (-not [bool]$highBackend.Available) { throw "High hardware fixture must have a usable local model" }
    if ([string]$highBackend.Model -ne "qwen2.5-coder:14b") {
        throw "12 GB discrete GPU must select the stronger installed coder model for backend work"
    }
    if ([int]$highBackend.NumCtx -le [int]$lowBackend.NumCtx) {
        throw "High hardware profile must expose a larger context window than low hardware"
    }
    if ([int]$highBackend.ContextMaxChars -le [int]$lowBackend.ContextMaxChars) {
        throw "High hardware profile must expose a larger repository context budget"
    }

    $highPm = & $resolvePath -ProjectPath $tempRoot -Role "pm" -Workload "analysis" -HardwareFixturePath $highFixture
    if ([string]$highPm.Model -ne "llama3.1:8b") {
        throw "PM should prefer the installed general model even on stronger hardware"
    }

    $env:AICO_OLLAMA_ALLOW_OVERSIZE = $null
    $unsafeOverride = & $resolvePath -ProjectPath $tempRoot -Role "backend" -ModelOverride "qwen2.5-coder:14b" -HardwareFixturePath $lowFixture
    if ([bool]$unsafeOverride.Available) {
        throw "Unsafe oversized explicit model override must be blocked by default"
    }

    $benchmarkPath = Join-Path $tempRoot ".codex\runtime\local-benchmarks.json"
    $benchmarkDocument = [PSCustomObject]@{
        schema_version = 1
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        hardware_fingerprint = [string]$highHardware.hardware_fingerprint
        profile = [string]$highHardware.profile
        models = @(
            [PSCustomObject]@{
                model = "qwen2.5-coder:14b"
                success = $true
                generation_tps = 2.0
            },
            [PSCustomObject]@{
                model = "llama3.1:8b"
                success = $true
                generation_tps = 35.0
            }
        )
    }
    [System.IO.File]::WriteAllText(
        $benchmarkPath,
        ($benchmarkDocument | ConvertTo-Json -Depth 10),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $benchAware = & $resolvePath -ProjectPath $tempRoot -Role "backend" -Workload "analysis" -HardwareFixturePath $highFixture -BenchmarkPath $benchmarkPath
    if ([string]$benchAware.Model -ne "llama3.1:8b") {
        throw "Resolver must reject a role-preferred model when its cached generation rate is below the profile minimum"
    }

    foreach ($relative in @(
        "scripts\local-runtime\detect-hardware.ps1",
        "scripts\local-runtime\resolve-local-runtime.ps1",
        "scripts\local-runtime\benchmark-ollama.ps1",
        "scripts\local-runtime\initialize-local-runtime.ps1",
        "scripts\providers\invoke-ollama.ps1",
        "scripts\provider-router.ps1",
        "scripts\run-agent-task.ps1",
        "scripts\run-gate-agent.ps1"
    )) {
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repoRoot $relative),
            [ref]$null,
            [ref]$parseErrors
        )
        if ($parseErrors.Count -gt 0) {
            throw ($relative + " has parse errors: " + (($parseErrors | ForEach-Object { $_.Message }) -join "; "))
        }
    }

    Write-Host "PASS: hardware-aware local runtime profiles" -ForegroundColor Green
}
finally {
    $env:AICO_OLLAMA_ALLOW_OVERSIZE = $oldOversize
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}
