param(
    [ValidateSet("Auto","Codex","OpenRouter","Gemini")]
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
    foreach ($secret in @($env:CODEX_API_KEY,$env:OPENROUTER_API_KEY,$env:GEMINI_API_KEY)) {
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

function Get-ConfiguredTimeoutSeconds {
    param([object]$Config,[string]$Name)

    $defaults = @{
        Codex = 180
        OpenRouter = 240
        Gemini = 240
    }

    $fallback = if ($defaults.ContainsKey($Name)) { [int]$defaults[$Name] } else { 240 }

    if ($null -eq $Config -or $null -eq $Config.provider_timeout_seconds) {
        return $fallback
    }

    $property = $Config.provider_timeout_seconds.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $fallback
    }

    $value = [int]$property.Value
    if ($value -lt 1 -or $value -gt 3600) {
        throw "Invalid provider timeout for $Name. Expected 1-3600 seconds, found $value."
    }

    return $value
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

function Write-ProviderEvent {
    param(
        [hashtable]$Event,
        [string]$WarningPrefix = "Provider metrics recording failed"
    )

    if (-not (Test-Path $metricsWriterPath)) { return }

    try {
        & $metricsWriterPath -ProjectPath $root -Event $Event | Out-Null
    }
    catch {
        Write-Warning ($WarningPrefix + ": " + $_.Exception.Message)
    }
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

$autoOrder = @("Codex","OpenRouter","Gemini")
if ($null -ne $config -and $null -ne $config.auto_order -and @($config.auto_order).Count -gt 0) {
    $autoOrder = @($config.auto_order | ForEach-Object { [string]$_ })
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

    $scriptName = switch ($candidateName) {
        "Codex" { "invoke-codex.ps1" }
        "OpenRouter" { "invoke-openrouter.ps1" }
        "Gemini" { "invoke-gemini.ps1" }
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

    $providerTimeoutSeconds = Get-ConfiguredTimeoutSeconds -Config $config -Name $candidateName
    $providerCommand = Get-Command $providerScript -ErrorAction Stop
    $supportsTimeout = $null -ne $providerCommand.Parameters["TimeoutSeconds"]

    $attempted++
    $attemptStarted = Get-Date

    Write-Host ""
    Write-Host "Provider attempt: $candidateName (timeout: $providerTimeoutSeconds s)" -ForegroundColor Cyan

    Write-ProviderEvent -Event @{
        event_type = "provider_attempt_started"
        provider = $candidateName
        model = $providerModel
        timeout_seconds = $providerTimeoutSeconds
        success = $false
        error_category = ""
    } -WarningPrefix "Provider start metrics could not be recorded"

    try {
        if ($candidateName -eq "Codex") {
            if ($supportsTimeout) {
                $result = & $providerScript -ProjectPath $root -Prompt $Prompt -SchemaPath $SchemaPath -OutputPath $OutputPath -Model $providerModel -TimeoutSeconds $providerTimeoutSeconds
            }
            else {
                $result = & $providerScript -ProjectPath $root -Prompt $Prompt -SchemaPath $SchemaPath -OutputPath $OutputPath -Model $providerModel
            }
        }
        else {
            if ($supportsTimeout) {
                $result = & $providerScript -Prompt $Prompt -Context $Context -SchemaPath $SchemaPath -OutputPath $OutputPath -Model $providerModel -TimeoutSeconds $providerTimeoutSeconds
            }
            else {
                $result = & $providerScript -Prompt $Prompt -Context $Context -SchemaPath $SchemaPath -OutputPath $OutputPath -Model $providerModel
            }
        }

        if (-not (Test-Path $OutputPath)) {
            throw "$candidateName returned without creating the structured output file."
        }

        & $validatorPath -JsonPath $OutputPath -SchemaPath $SchemaPath | Out-Null

        $durationMs = [int][math]::Round(((Get-Date) - $attemptStarted).TotalMilliseconds)

        Write-ProviderEvent -Event @{
            event_type = "provider_attempt"
            provider = $candidateName
            model = [string]$result.Model
            duration_ms = $durationMs
            timeout_seconds = $providerTimeoutSeconds
            success = $true
            error_category = ""
        } -WarningPrefix "Provider succeeded, but metrics recording failed"

        Write-ProviderEvent -Event @{
            event_type = "provider_attempt_finished"
            provider = $candidateName
            model = [string]$result.Model
            duration_ms = $durationMs
            timeout_seconds = $providerTimeoutSeconds
            success = $true
            error_category = ""
        } -WarningPrefix "Provider finish metrics could not be recorded"

        Write-Host "Provider succeeded: $candidateName" -ForegroundColor Green
        return $result
    }
    catch {
        $safe = Sanitize-ProviderError -Message $_.Exception.Message
        $errors += ($candidateName + ": " + $safe)
        $durationMs = [int][math]::Round(((Get-Date) - $attemptStarted).TotalMilliseconds)
        $errorCategory = Get-ProviderErrorCategory -Message $safe

        if ($errorCategory -eq "timeout") {
            Write-ProviderEvent -Event @{
                event_type = "provider_timeout"
                provider = $candidateName
                model = $providerModel
                duration_ms = $durationMs
                timeout_seconds = $providerTimeoutSeconds
                success = $false
                error_category = "timeout"
            } -WarningPrefix "Provider timeout metrics could not be recorded"
        }

        Write-ProviderEvent -Event @{
            event_type = "provider_attempt"
            provider = $candidateName
            model = $providerModel
            duration_ms = $durationMs
            timeout_seconds = $providerTimeoutSeconds
            success = $false
            error_category = $errorCategory
        } -WarningPrefix "Provider failure metrics could not be recorded"

        Write-ProviderEvent -Event @{
            event_type = "provider_attempt_finished"
            provider = $candidateName
            model = $providerModel
            duration_ms = $durationMs
            timeout_seconds = $providerTimeoutSeconds
            success = $false
            error_category = $errorCategory
        } -WarningPrefix "Provider finish metrics could not be recorded"

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
