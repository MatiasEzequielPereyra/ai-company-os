param(
    [string]$ProjectPath = ".",
    [string]$Model = "",
    [string]$HardwareFixturePath = "",
    [string]$OutputPath = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Get-PropertyValue {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

$root = (Resolve-Path $ProjectPath).Path
$configPath = Join-Path $root ".codex\local-runtime-config.json"
$detectorPath = Join-Path $PSScriptRoot "detect-hardware.ps1"

if (-not (Test-Path $configPath -PathType Leaf)) { throw "Local runtime configuration not found: $configPath" }
if (-not (Test-Path $detectorPath -PathType Leaf)) { throw "Hardware detector not found: $detectorPath" }

$config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$detectArgs = @{}
if (-not [string]::IsNullOrWhiteSpace($HardwareFixturePath)) {
    $detectArgs.FixturePath = $HardwareFixturePath
}
$hardware = & $detectorPath @detectArgs

if (-not [bool]$hardware.ollama.reachable) {
    throw "Ollama is not reachable; local benchmark cannot run."
}

$profile = Get-PropertyValue -Object $config.profiles -Name ([string]$hardware.profile)
if ($null -eq $profile) { throw "No benchmark profile configured for $($hardware.profile)" }

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $runtimeDir = Join-Path $root ".codex\runtime"
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
    $OutputPath = Join-Path $runtimeDir "local-benchmarks.json"
}

$ttlHours = [double]$config.benchmark.cache_ttl_hours
if (-not $Force -and [string]::IsNullOrWhiteSpace($Model) -and (Test-Path $OutputPath -PathType Leaf)) {
    try {
        $existing = Get-Content $OutputPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $generated = [DateTime]::Parse([string]$existing.generated_at).ToUniversalTime()
        $ageHours = ((Get-Date).ToUniversalTime() - $generated).TotalHours
        if (
            [string]$existing.hardware_fingerprint -eq [string]$hardware.hardware_fingerprint -and
            $ageHours -ge 0 -and
            $ageHours -lt $ttlHours
        ) {
            Write-Host ("Local benchmark cache is fresh (" + [math]::Round($ageHours,1) + "h old).") -ForegroundColor DarkGray
            return $existing
        }
    }
    catch {
        Write-Warning ("Ignoring invalid benchmark cache: " + $_.Exception.Message)
    }
}

$installed = @($hardware.ollama.models)
$maxModelBytes = [long]$profile.max_model_bytes
$candidates = @()

if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $candidate = $installed | Where-Object { [string]$_.name -eq $Model } | Select-Object -First 1
    if ($null -eq $candidate) { throw "Requested benchmark model is not installed: $Model" }
    if ([long]$candidate.size -gt $maxModelBytes -and $env:AICO_OLLAMA_ALLOW_OVERSIZE -ne "1") {
        throw "Requested benchmark model exceeds the safe size for $($hardware.profile). Set AICO_OLLAMA_ALLOW_OVERSIZE=1 to force it."
    }
    $candidates = @($candidate)
}
else {
    $orderedNames = @($config.default_preferences | ForEach-Object { [string]$_ })
    foreach ($name in $orderedNames) {
        $candidate = $installed | Where-Object { [string]$_.name -eq $name -and [long]$_.size -le $maxModelBytes } | Select-Object -First 1
        if ($null -ne $candidate) { $candidates += $candidate }
    }

    foreach ($candidate in ($installed | Where-Object { [long]$_.size -le $maxModelBytes } | Sort-Object size -Descending)) {
        if (@($candidates | Where-Object { [string]$_.name -eq [string]$candidate.name }).Count -eq 0) {
            $candidates += $candidate
        }
    }

    $limit = [int]$profile.benchmark_max_models
    if ($limit -gt 0) { $candidates = @($candidates | Select-Object -First $limit) }
}

if ($candidates.Count -eq 0) {
    throw "No installed Ollama models fit hardware profile $($hardware.profile)."
}

$baseUrl = [string]$hardware.ollama.base_url
$prompt = [string]$config.benchmark.prompt
$numPredict = [int]$config.benchmark.num_predict
$numCtx = [int]$config.benchmark.num_ctx
$timeoutSeconds = [int]$config.benchmark.timeout_seconds

$results = @()
foreach ($candidate in $candidates) {
    $name = [string]$candidate.name
    Write-Host ("Benchmarking Ollama model: " + $name) -ForegroundColor Cyan

    $body = @{
        model = $name
        prompt = $prompt
        stream = $false
        keep_alive = "2m"
        options = @{
            temperature = 0
            num_ctx = $numCtx
            num_predict = $numPredict
        }
    } | ConvertTo-Json -Depth 20 -Compress

    $started = Get-Date
    try {
        $response = Invoke-RestMethod -Method Post -Uri ($baseUrl.TrimEnd('/') + "/api/generate") -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec $timeoutSeconds

        $generationTps = 0.0
        if ([long]$response.eval_duration -gt 0 -and [int]$response.eval_count -gt 0) {
            $generationTps = [double]$response.eval_count / ([double]$response.eval_duration / 1000000000.0)
        }

        $promptTps = 0.0
        if ([long]$response.prompt_eval_duration -gt 0 -and [int]$response.prompt_eval_count -gt 0) {
            $promptTps = [double]$response.prompt_eval_count / ([double]$response.prompt_eval_duration / 1000000000.0)
        }

        $result = [PSCustomObject]@{
            model = $name
            size_bytes = [long]$candidate.size
            success = $true
            elapsed_seconds = [math]::Round(((Get-Date) - $started).TotalSeconds,2)
            load_seconds = [math]::Round(([double]$response.load_duration / 1000000000.0),2)
            prompt_tps = [math]::Round($promptTps,2)
            generation_tps = [math]::Round($generationTps,2)
            eval_count = [int]$response.eval_count
            error = ""
        }
        $results += $result
        Write-Host ("  generation=" + $result.generation_tps + " tok/s; load=" + $result.load_seconds + "s") -ForegroundColor DarkGray
    }
    catch {
        $result = [PSCustomObject]@{
            model = $name
            size_bytes = [long]$candidate.size
            success = $false
            elapsed_seconds = [math]::Round(((Get-Date) - $started).TotalSeconds,2)
            load_seconds = 0
            prompt_tps = 0
            generation_tps = 0
            eval_count = 0
            error = $_.Exception.Message
        }
        $results += $result
        Write-Warning ("Benchmark failed for " + $name + ": " + $_.Exception.Message)
    }
}

$document = [PSCustomObject]@{
    schema_version = 1
    generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    hardware_fingerprint = [string]$hardware.hardware_fingerprint
    profile = [string]$hardware.profile
    models = @($results)
}

Write-Utf8NoBom -Path $OutputPath -Value ($document | ConvertTo-Json -Depth 20)
Write-Host ("Local benchmark cache: " + $OutputPath) -ForegroundColor Green
return $document
