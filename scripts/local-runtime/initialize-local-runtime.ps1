param(
    [string]$ProjectPath = ".",
    [string]$Role = "pm",
    [string]$Model = "",
    [switch]$SkipBenchmark,
    [switch]$ForceBenchmark
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

$root = (Resolve-Path $ProjectPath).Path
$detectorPath = Join-Path $PSScriptRoot "detect-hardware.ps1"
$benchmarkPath = Join-Path $PSScriptRoot "benchmark-ollama.ps1"
$resolverPath = Join-Path $PSScriptRoot "resolve-local-runtime.ps1"
$runtimeDir = Join-Path $root ".codex\runtime"
$capabilityPath = Join-Path $runtimeDir "local-capability.json"

foreach ($required in @($detectorPath,$benchmarkPath,$resolverPath)) {
    if (-not (Test-Path $required -PathType Leaf)) { throw "Local runtime component not found: $required" }
}

New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
$hardware = & $detectorPath
Write-Utf8NoBom -Path $capabilityPath -Value ($hardware | ConvertTo-Json -Depth 20)

Write-Host ""
Write-Host "AI Company OS local runtime" -ForegroundColor Cyan
Write-Host ("Profile: " + $hardware.profile)
Write-Host ("RAM: " + $hardware.memory.total_gb + " GB")
Write-Host ("CPU: " + $hardware.cpu.name)
if (-not [string]::IsNullOrWhiteSpace([string]$hardware.gpu.name)) {
    Write-Host ("GPU: " + $hardware.gpu.name + " / VRAM: " + $hardware.gpu.vram_gb + " GB")
}
else {
    Write-Host "GPU: no supported discrete GPU detected"
}
Write-Host ("Ollama: " + $(if ($hardware.ollama.reachable) { "reachable" } else { "unavailable" }))
Write-Host ("Installed models: " + @($hardware.ollama.models).Count)

if (-not [bool]$hardware.ollama.reachable) {
    Write-Warning "Ollama is unavailable. Local routing will fall back to other configured providers."
    return $hardware
}

if (-not $SkipBenchmark) {
    $benchmarkArgs = @{ ProjectPath = $root }
    if (-not [string]::IsNullOrWhiteSpace($Model)) { $benchmarkArgs.Model = $Model }
    if ($ForceBenchmark) { $benchmarkArgs.Force = $true }
    $null = & $benchmarkPath @benchmarkArgs
}

$resolveArgs = @{
    ProjectPath = $root
    Role = $Role
    Workload = "analysis"
}
if (-not [string]::IsNullOrWhiteSpace($Model)) { $resolveArgs.ModelOverride = $Model }

$selection = & $resolverPath @resolveArgs
Write-Host ""
if ($selection.Available) {
    Write-Host ("Selected local model: " + $selection.Model) -ForegroundColor Green
    Write-Host ("Reason: " + $selection.Reason) -ForegroundColor DarkGray
    Write-Host ("num_ctx=" + $selection.NumCtx + "; num_predict=" + $selection.NumPredict + "; context_max_chars=" + $selection.ContextMaxChars) -ForegroundColor DarkGray
}
else {
    Write-Warning ("No local model selected: " + $selection.Reason)
}

[PSCustomObject]@{
    Hardware = $hardware
    Selection = $selection
    CapabilityPath = $capabilityPath
}
