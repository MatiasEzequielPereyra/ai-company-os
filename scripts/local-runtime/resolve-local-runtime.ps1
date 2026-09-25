param(
    [string]$ProjectPath = ".",
    [string]$Role = "",
    [string]$Workload = "general",
    [string]$ModelOverride = "",
    [string]$HardwareFixturePath = "",
    [string]$HardwareSnapshotPath = "",
    [string]$BenchmarkPath = ""
)

$ErrorActionPreference = "Stop"

function Get-PropertyValue {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

$root = (Resolve-Path $ProjectPath).Path
$configPath = Join-Path $root ".codex\local-runtime-config.json"
$detectorPath = Join-Path $PSScriptRoot "detect-hardware.ps1"

if (-not (Test-Path $configPath -PathType Leaf)) {
    throw "Local runtime configuration not found: $configPath"
}
if (-not (Test-Path $detectorPath -PathType Leaf)) {
    throw "Local hardware detector not found: $detectorPath"
}

$config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

$hardware = $null

if (-not [string]::IsNullOrWhiteSpace($HardwareSnapshotPath)) {
    if (-not (Test-Path $HardwareSnapshotPath -PathType Leaf)) {
        throw "Hardware snapshot not found: $HardwareSnapshotPath"
    }

    try {
        $hardware = Get-Content $HardwareSnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Invalid hardware snapshot: $HardwareSnapshotPath"
    }
}
else {
    $detectArgs = @{}
    if (-not [string]::IsNullOrWhiteSpace($HardwareFixturePath)) {
        $detectArgs.FixturePath = $HardwareFixturePath
    }
    $hardware = & $detectorPath @detectArgs
}

$profileName = [string]$hardware.profile
$profile = Get-PropertyValue -Object $config.profiles -Name $profileName
if ($null -eq $profile) {
    throw "No local runtime profile configured for hardware class: $profileName"
}

if ([string]::IsNullOrWhiteSpace($BenchmarkPath)) {
    $BenchmarkPath = Join-Path $root ".codex\runtime\local-benchmarks.json"
}

$benchmarksByModel = @{}
if (Test-Path $BenchmarkPath -PathType Leaf) {
    try {
        $benchmarkDocument = Get-Content $BenchmarkPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (
            [string]$benchmarkDocument.hardware_fingerprint -eq [string]$hardware.hardware_fingerprint -and
            $null -ne $benchmarkDocument.models
        ) {
            foreach ($entry in @($benchmarkDocument.models)) {
                $benchmarksByModel[[string]$entry.model] = $entry
            }
        }
    }
    catch {
        Write-Warning ("Ignoring invalid local benchmark cache: " + $_.Exception.Message)
    }
}

$installed = @($hardware.ollama.models)
$maxModelBytes = [long]$profile.max_model_bytes
$minimumTps = [double]$profile.minimum_generation_tps

function Test-ModelEligible {
    param([object]$Model)

    if ($null -eq $Model) { return $false }
    if ([long]$Model.size -gt $maxModelBytes) { return $false }

    $name = [string]$Model.name
    if ($benchmarksByModel.ContainsKey($name)) {
        $bench = $benchmarksByModel[$name]
        if ($null -ne $bench.success -and -not [bool]$bench.success) { return $false }
        if ($null -ne $bench.generation_tps -and [double]$bench.generation_tps -gt 0 -and [double]$bench.generation_tps -lt $minimumTps) {
            return $false
        }
    }

    return $true
}

$selected = $null
$reason = ""

if (-not [string]::IsNullOrWhiteSpace($ModelOverride)) {
    $selected = $installed | Where-Object { [string]$_.name -eq $ModelOverride } | Select-Object -First 1
    if ($null -eq $selected) {
        return [PSCustomObject]@{
            Available = $false
            Profile = $profileName
            CapabilityScore = [int]$hardware.capability_score
            Model = $ModelOverride
            Reason = "Requested Ollama model is not installed."
            NumCtx = [int]$profile.num_ctx
            NumPredict = [int]$profile.num_predict
            ContextMaxChars = [int]$profile.context_max_chars
            GateContextMaxChars = [int]$profile.gate_context_max_chars
            GateArtifactMaxChars = [int]$profile.gate_artifact_max_chars
            Hardware = $hardware
        }
    }

    if ([long]$selected.size -gt $maxModelBytes -and $env:AICO_OLLAMA_ALLOW_OVERSIZE -ne "1") {
        return [PSCustomObject]@{
            Available = $false
            Profile = $profileName
            CapabilityScore = [int]$hardware.capability_score
            Model = $ModelOverride
            Reason = "Requested Ollama model exceeds the safe model size for $profileName. Set AICO_OLLAMA_ALLOW_OVERSIZE=1 to force it."
            NumCtx = [int]$profile.num_ctx
            NumPredict = [int]$profile.num_predict
            ContextMaxChars = [int]$profile.context_max_chars
            GateContextMaxChars = [int]$profile.gate_context_max_chars
            GateArtifactMaxChars = [int]$profile.gate_artifact_max_chars
            Hardware = $hardware
        }
    }

    $reason = "Explicit local model override."
}
else {
    $preferences = @()
    $roleKey = ([string]$Role).Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($roleKey)) {
        $roleValues = Get-PropertyValue -Object $config.role_preferences -Name $roleKey
        if ($null -ne $roleValues) { $preferences = @($roleValues | ForEach-Object { [string]$_ }) }
    }

    if ($preferences.Count -eq 0) {
        $preferences = @($config.default_preferences | ForEach-Object { [string]$_ })
    }

    foreach ($preferredName in $preferences) {
        $candidate = $installed | Where-Object { [string]$_.name -eq $preferredName } | Select-Object -First 1
        if ($null -ne $candidate -and (Test-ModelEligible -Model $candidate)) {
            $selected = $candidate
            $reason = "Best installed role-preferred model that fits $profileName."
            break
        }
    }

    if ($null -eq $selected) {
        $selected = $installed |
            Where-Object { Test-ModelEligible -Model $_ } |
            Sort-Object @{ Expression = { [long]$_.size }; Descending = $true } |
            Select-Object -First 1

        if ($null -ne $selected) {
            $reason = "Largest installed model that fits $profileName."
        }
    }
}

if (-not [bool]$hardware.ollama.reachable) {
    return [PSCustomObject]@{
        Available = $false
        Profile = $profileName
        Model = $(if ($null -ne $selected) { [string]$selected.name } else { "" })
        Reason = "Ollama is not reachable."
        NumCtx = [int]$profile.num_ctx
        NumPredict = [int]$profile.num_predict
        ContextMaxChars = [int]$profile.context_max_chars
        GateContextMaxChars = [int]$profile.gate_context_max_chars
        GateArtifactMaxChars = [int]$profile.gate_artifact_max_chars
        Hardware = $hardware
    }
}

if ($null -eq $selected) {
    return [PSCustomObject]@{
        Available = $false
        Profile = $profileName
        Model = ""
        Reason = "No installed Ollama model fits the detected hardware profile."
        NumCtx = [int]$profile.num_ctx
        NumPredict = [int]$profile.num_predict
        ContextMaxChars = [int]$profile.context_max_chars
        GateContextMaxChars = [int]$profile.gate_context_max_chars
        GateArtifactMaxChars = [int]$profile.gate_artifact_max_chars
        Hardware = $hardware
    }
}

$benchmark = $null
if ($benchmarksByModel.ContainsKey([string]$selected.name)) {
    $benchmark = $benchmarksByModel[[string]$selected.name]
}

[PSCustomObject]@{
    Available = $true
    Profile = $profileName
    CapabilityScore = [int]$hardware.capability_score
    Model = [string]$selected.name
    ModelSizeBytes = [long]$selected.size
    Reason = $reason
    NumCtx = [int]$profile.num_ctx
    NumPredict = [int]$profile.num_predict
    ContextMaxChars = [int]$profile.context_max_chars
    GateContextMaxChars = [int]$profile.gate_context_max_chars
    GateArtifactMaxChars = [int]$profile.gate_artifact_max_chars
    MinimumGenerationTps = $minimumTps
    Benchmark = $benchmark
    Hardware = $hardware
    Workload = $Workload
}
