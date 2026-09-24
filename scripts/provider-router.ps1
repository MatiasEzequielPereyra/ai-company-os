param(
    [ValidateSet("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok")]
    [string]$Provider = "Auto",
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [string]$Context = "",
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = ""
)

$ErrorActionPreference = "Stop"

function Sanitize-ProviderError {
    param([string]$Message)

    $result = $Message
    foreach ($secret in @(
        $env:CODEX_API_KEY,
        $env:OPENROUTER_API_KEY,
        $env:GEMINI_API_KEY,
        $env:DEEPSEEK_API_KEY,
        $env:XAI_API_KEY
    )) {
        if (-not [string]::IsNullOrWhiteSpace($secret)) {
            $result = $result.Replace($secret,"[REDACTED]")
        }
    }
    return $result
}

function Get-ConfiguredModel {
    param([object]$Config,[string]$Name)

    if ($null -eq $Config -or $null -eq $Config.models) { return "" }

    $property = $Config.models.PSObject.Properties[$Name]
    if ($null -eq $property) { return "" }
    return [string]$property.Value
}

function Get-ProviderErrorCategory {
    param([string]$Message)
    if ($Message -match "(?i)429|rate.?limit|quota|credits") { return "rate_limit" }
    if ($Message -match "(?i)401|403|unauthor|forbidden|api.?key|not configured") { return "authentication" }
    if ($Message -match "(?i)timeout|timed out") { return "timeout" }
    if ($Message -match "(?i)schema|structured|invalid json|contract") { return "contract" }
    if ($Message -match "(?i)connection|network|transport|5\d\d") { return "transport" }
    return "unknown"
}

$root = (Resolve-Path $ProjectPath).Path
$providersRoot = Join-Path $PSScriptRoot "providers"
$configPath = Join-Path $root ".codex\provider-config.json"
$validatorPath = Join-Path $PSScriptRoot "validate-json-contract.ps1"
$metricsWriterPath = Join-Path $PSScriptRoot "write-operational-event.ps1"

if (-not (Test-Path $validatorPath)) { throw "Provider contract validator not found: $validatorPath" }

$config = $null
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$autoOrder = @("Ollama","OpenRouter","Gemini","DeepSeek","Grok","Codex")
if ($null -ne $config -and $null -ne $config.auto_order -and @($config.auto_order).Count -gt 0) {
    $autoOrder = @($config.auto_order | ForEach-Object { [string]$_ })
}

$allowPaidFallback = $false
if ($null -ne $config -and $null -ne $config.allow_paid_fallback) {
    $allowPaidFallback = [bool]$config.allow_paid_fallback
}

if ($Provider -eq "Auto") {
    $attempts = $autoOrder
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        Write-Host "Provider Auto ignores -Model and uses provider-specific defaults." -ForegroundColor DarkYellow
    }
}
else {
    $attempts = @($Provider)
}

$errors = @()
$attempted = 0

foreach ($candidate in $attempts) {
    $candidateName = [string]$candidate

    if ($candidateName -eq "Codex" -and $null -eq (Get-Command codex -ErrorAction SilentlyContinue)) {
        $errors += "Codex: CLI not available"
        if ($Provider -ne "Auto") { throw "Codex CLI is not available in PATH." }
        continue
    }

    if ($candidateName -eq "OpenRouter" -and [string]::IsNullOrWhiteSpace($env:OPENROUTER_API_KEY)) {
        $errors += "OpenRouter: OPENROUTER_API_KEY not configured"
        if ($Provider -ne "Auto") { throw "OPENROUTER_API_KEY is not configured." }
        continue
    }

    if ($candidateName -eq "Gemini" -and [string]::IsNullOrWhiteSpace($env:GEMINI_API_KEY)) {
        $errors += "Gemini: GEMINI_API_KEY not configured"
        if ($Provider -ne "Auto") { throw "GEMINI_API_KEY is not configured." }
        continue
    }

    if ($candidateName -eq "DeepSeek" -and [string]::IsNullOrWhiteSpace($env:DEEPSEEK_API_KEY)) {
        $errors += "DeepSeek: DEEPSEEK_API_KEY not configured"
        if ($Provider -ne "Auto") { throw "DEEPSEEK_API_KEY is not configured." }
        continue
    }

    if ($candidateName -eq "Grok" -and [string]::IsNullOrWhiteSpace($env:XAI_API_KEY)) {
        $errors += "Grok: XAI_API_KEY not configured"
        if ($Provider -ne "Auto") { throw "XAI_API_KEY is not configured." }
        continue
    }

    if ($Provider -eq "Auto" -and -not $allowPaidFallback -and $candidateName -in @("DeepSeek","Grok")) {
        $errors += ($candidateName + ": paid fallback disabled by configuration")
        continue
    }

    if ($candidateName -eq "Ollama") {
        $ollamaBaseUrl = if ([string]::IsNullOrWhiteSpace($env:OLLAMA_BASE_URL)) {
            "http://localhost:11434"
        }
        else {
            $env:OLLAMA_BASE_URL.TrimEnd('/')
        }

        try {
            $null = Invoke-RestMethod -Method Get -Uri ($ollamaBaseUrl + "/api/tags") -TimeoutSec 3
        }
        catch {
            $errors += "Ollama: local server unavailable"
            if ($Provider -ne "Auto") {
                throw "Ollama is not reachable. Start Ollama or set OLLAMA_BASE_URL."
            }
            continue
        }
    }

    $scriptName = switch ($candidateName) {
        "Codex" { "invoke-codex.ps1" }
        "OpenRouter" { "invoke-openrouter.ps1" }
        "Gemini" { "invoke-gemini.ps1" }
        "Ollama" { "invoke-ollama.ps1" }
        "DeepSeek" { "invoke-deepseek.ps1" }
        "Grok" { "invoke-xai.ps1" }
        default { throw "Unknown provider: $candidateName" }
    }

    $providerScript = Join-Path $providersRoot $scriptName
    if (-not (Test-Path $providerScript)) {
        $errors += "${candidateName}: adapter missing"
        if ($Provider -ne "Auto") { throw "Provider adapter not found: $providerScript" }
        continue
    }

    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force
    }

    $providerModel = ""
    if ($Provider -ne "Auto" -and -not [string]::IsNullOrWhiteSpace($Model)) {
        $providerModel = $Model
    }
    else {
        $providerModel = Get-ConfiguredModel -Config $config -Name $candidateName
    }

    $attempted++
    $attemptStarted = Get-Date
    Write-Host ""
    Write-Host "Provider attempt: $candidateName" -ForegroundColor Cyan

    try {
        if ($candidateName -eq "Codex") {
            $result = & $providerScript -ProjectPath $root -Prompt $Prompt -SchemaPath $SchemaPath -OutputPath $OutputPath -Model $providerModel
        }
        else {
            $result = & $providerScript -Prompt $Prompt -Context $Context -SchemaPath $SchemaPath -OutputPath $OutputPath -Model $providerModel
        }

        if (-not (Test-Path $OutputPath)) {
            throw "$candidateName returned without creating the structured output file."
        }

        & $validatorPath -JsonPath $OutputPath -SchemaPath $SchemaPath | Out-Null

        $durationMs = [int][math]::Round(((Get-Date) - $attemptStarted).TotalMilliseconds)
        if (Test-Path $metricsWriterPath) {
            try {
                & $metricsWriterPath -ProjectPath $root -Event @{
                    event_type = "provider_attempt"
                    provider = $candidateName
                    model = [string]$result.Model
                    duration_ms = $durationMs
                    success = $true
                    error_category = ""
                } | Out-Null
            } catch { Write-Warning ("Provider succeeded, but metrics recording failed: " + $_.Exception.Message) }
        }

        Write-Host "Provider succeeded: $candidateName" -ForegroundColor Green
        return $result
    }
    catch {
        $safe = Sanitize-ProviderError -Message $_.Exception.Message
        $errors += ($candidateName + ": " + $safe)
        $durationMs = [int][math]::Round(((Get-Date) - $attemptStarted).TotalMilliseconds)
        if (Test-Path $metricsWriterPath) {
            try {
                & $metricsWriterPath -ProjectPath $root -Event @{
                    event_type = "provider_attempt"
                    provider = $candidateName
                    model = $providerModel
                    duration_ms = $durationMs
                    success = $false
                    error_category = (Get-ProviderErrorCategory -Message $safe)
                } | Out-Null
            } catch { Write-Warning ("Provider failure metrics could not be recorded: " + $_.Exception.Message) }
        }
        Write-Host "Provider failed: $candidateName" -ForegroundColor Yellow
        Write-Host $safe -ForegroundColor DarkYellow

        if ($Provider -ne "Auto") {
            throw $safe
        }
    }
}

if ($attempted -eq 0) {
    throw ("No configured provider is currently available. " + ($errors -join " | "))
}

throw ("All configured providers failed. " + ($errors -join " | "))
