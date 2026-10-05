param(
    [ValidateSet("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok")]
    [string]$Provider = "Auto",
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [string]$Context = "",
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = "",
    [string]$Role = "",
    [string]$Workload = "general",
    [string]$SemanticValidatorPath = "",
    [string]$CorrectiveContext = ""
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
    param(
        [object]$Config,
        [string]$Name,
        [string]$Role,
        [string]$Workload
    )

    if (
        $Workload -eq "analysis" -and
        -not [string]::IsNullOrWhiteSpace($Role) -and
        $null -ne $Config -and
        $null -ne $Config.analysis_models_by_role
    ) {
        $roleProperty = $Config.analysis_models_by_role.PSObject.Properties[$Role]

        if ($null -ne $roleProperty -and $null -ne $roleProperty.Value) {
            $providerProperty = $roleProperty.Value.PSObject.Properties[$Name]

            if ($null -ne $providerProperty -and -not [string]::IsNullOrWhiteSpace([string]$providerProperty.Value)) {
                return [string]$providerProperty.Value
            }
        }
    }

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
        Ollama = 1800
        DeepSeek = 300
        Grok = 300
    }

    $fallback = if ($defaults.ContainsKey($Name)) {
        [int]$defaults[$Name]
    }
    else {
        240
    }

    if ($null -eq $Config -or $null -eq $Config.provider_timeout_seconds) {
        return $fallback
    }

    $property = $Config.provider_timeout_seconds.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $fallback
    }

    $value = 0
    if (-not [int]::TryParse([string]$property.Value,[ref]$value)) {
        throw "Invalid provider timeout for $Name. Expected an integer from 1 to 3600 seconds."
    }

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
    if ($Message -match "(?i)schema|structured|invalid json|contract|semantic") { return "contract" }
    if ($Message -match "(?i)connection|network|transport|5\d\d") { return "transport" }
    return "unknown"
}

function Get-EffectiveProviderContextBudget {
    param(
        [object]$Config,
        [string]$Role,
        [string]$ProviderName,
        [string]$Workload,
        [object]$LocalRuntime
    )

    if ($Workload -eq "analysis") {
        $defaultGlobal = 120000
        $defaultRoleBudgets = @{
            "pm" = 70000
            "cto" = 110000
            "engineering-manager" = 120000
            "qa" = 90000
            "security" = 100000
            "devops" = 90000
        }

        $globalMax = $defaultGlobal
        if ($null -ne $Config -and $null -ne $Config.analysis_context_max_chars) {
            $globalMax = [int]$Config.analysis_context_max_chars
        }
        elseif ($null -ne $Config -and $null -ne $Config.context_max_chars) {
            $globalMax = [Math]::Min([int]$Config.context_max_chars,$defaultGlobal)
        }

        $roleKey = ([string]$Role).Trim().ToLowerInvariant()
        $roleMax = if ($defaultRoleBudgets.ContainsKey($roleKey)) {
            [Math]::Min([int]$defaultRoleBudgets[$roleKey],$globalMax)
        }
        else {
            $globalMax
        }

        if (
            -not [string]::IsNullOrWhiteSpace($Role) -and
            $null -ne $Config -and
            $null -ne $Config.analysis_context_max_chars_by_role
        ) {
            $roleProperty = $Config.analysis_context_max_chars_by_role.PSObject.Properties[$Role]
            if ($null -ne $roleProperty -and $null -ne $roleProperty.Value) {
                $roleMax = [Math]::Min([int]$roleProperty.Value,$globalMax)
            }
        }

        $providerMax = 0
        $hardwareMax = 0
        $effectiveMax = $roleMax

        if ($ProviderName -eq "Ollama") {
            if ($null -ne $Config -and $null -ne $Config.ollama_context_max_chars) {
                $providerMax = [int]$Config.ollama_context_max_chars
                if ($providerMax -gt 0) {
                    $effectiveMax = [Math]::Min($effectiveMax,$providerMax)
                }
            }

            if (
                $null -ne $LocalRuntime -and
                [bool]$LocalRuntime.Available -and
                $null -ne $LocalRuntime.ContextMaxChars
            ) {
                $hardwareMax = [int]$LocalRuntime.ContextMaxChars
                if ($hardwareMax -gt 0) {
                    $effectiveMax = [Math]::Min($effectiveMax,$hardwareMax)
                }
            }
        }

        if ($effectiveMax -lt 10000) {
            throw "Effective analysis context budget is too small for canonical task context: $effectiveMax"
        }

        return [PSCustomObject]@{
            GlobalMaxChars = $globalMax
            RoleMaxChars = $roleMax
            ProviderMaxChars = $providerMax
            HardwareMaxChars = $hardwareMax
            EffectiveMaxChars = $effectiveMax
        }
    }

    if ($Workload -eq "gate") {
        $globalMax = 180000
        if ($null -ne $Config -and $null -ne $Config.gate_context_max_chars) {
            $globalMax = [int]$Config.gate_context_max_chars
        }

        $providerMax = 0
        $hardwareMax = 0
        $effectiveMax = $globalMax

        if ($ProviderName -eq "Ollama") {
            if ($null -ne $Config -and $null -ne $Config.ollama_gate_context_max_chars) {
                $providerMax = [int]$Config.ollama_gate_context_max_chars
                if ($providerMax -gt 0) {
                    $effectiveMax = [Math]::Min($effectiveMax,$providerMax)
                }
            }

            if (
                $null -ne $LocalRuntime -and
                [bool]$LocalRuntime.Available -and
                $null -ne $LocalRuntime.GateContextMaxChars
            ) {
                $hardwareMax = [int]$LocalRuntime.GateContextMaxChars
                if ($hardwareMax -gt 0) {
                    $effectiveMax = [Math]::Min($effectiveMax,$hardwareMax)
                }
            }
        }

        if ($effectiveMax -lt 4000) {
            throw "Effective gate context budget is too small for canonical gate evidence: $effectiveMax"
        }

        return [PSCustomObject]@{
            GlobalMaxChars = $globalMax
            RoleMaxChars = $globalMax
            ProviderMaxChars = $providerMax
            HardwareMaxChars = $hardwareMax
            EffectiveMaxChars = $effectiveMax
        }
    }

    if ($Workload -eq "writable") {
        $globalMax = 120000
        if ($null -ne $Config -and $null -ne $Config.writable_context_max_chars) {
            $globalMax = [int]$Config.writable_context_max_chars
        }
        elseif ($null -ne $Config -and $null -ne $Config.context_max_chars) {
            $globalMax = [Math]::Min([int]$Config.context_max_chars,120000)
        }

        if ($globalMax -le 0) { throw "Writable requires a valid positive context budget." }
        $hardwareMax = 0
        $providerMax = 0
        $effectiveMax = $globalMax
        if ($ProviderName -eq "Ollama") {
            if (
                $null -eq $LocalRuntime -or
                -not [bool]$LocalRuntime.Available -or
                -not [int]::TryParse([string]$LocalRuntime.ContextMaxChars,[ref]$hardwareMax) -or
                $hardwareMax -le 0
            ) {
                throw "Writable Ollama requires a valid positive runtime context budget."
            }
            $effectiveMax = [Math]::Min($globalMax,$hardwareMax)
            if ($null -ne $Config -and $null -ne $Config.ollama_context_max_chars) {
                $providerMax = [int]$Config.ollama_context_max_chars
                if ($providerMax -gt 0) {
                    $effectiveMax = [Math]::Min($effectiveMax,$providerMax)
                }
            }
        }
        return [PSCustomObject]@{
            GlobalMaxChars = $globalMax
            RoleMaxChars = $globalMax
            ProviderMaxChars = $providerMax
            HardwareMaxChars = $hardwareMax
            EffectiveMaxChars = $effectiveMax
        }
    }

    return $null
}

function Limit-ProviderContext {
    param(
        [AllowEmptyString()][string]$Context,
        [int]$MaxChars
    )

    if ($MaxChars -le 0 -or $Context.Length -le $MaxChars) {
        return $Context
    }

    $marker = [Environment]::NewLine + "[TRUNCATED BY AI COMPANY OS PROVIDER CONTEXT POLICY]"
    if ($MaxChars -le $marker.Length) { return $marker.Substring(0,$MaxChars) }
    $take = [Math]::Max(0,$MaxChars - $marker.Length)
    return $Context.Substring(0,$take) + $marker
}

function Limit-CorrectiveAnalysisContext {
    param([AllowEmptyString()][string]$Context,[AllowEmptyString()][string]$RequiredContext,[int]$MaxChars)
    if ([string]::IsNullOrWhiteSpace($RequiredContext)) { return Limit-ProviderContext -Context $Context -MaxChars $MaxChars }
    if ($MaxChars -le 0) { throw 'Corrective analysis requires a finite positive context budget.' }
    $separator = [Environment]::NewLine
    if ($RequiredContext.Length -gt $MaxChars) { throw "Required corrective analysis evidence exceeds effective provider context budget ($($RequiredContext.Length) > $MaxChars). No provider call permitted; reconcile evidence or budget." }
    $remaining = $MaxChars - $RequiredContext.Length - $separator.Length
    if ($remaining -le 0 -or [string]::IsNullOrEmpty($Context)) { return $RequiredContext }
    return $RequiredContext + $separator + (Limit-ProviderContext -Context $Context -MaxChars $remaining)
}

function Limit-GateProviderContext {
    param([AllowEmptyString()][string]$Context,[int]$MaxChars)

    $labels = @(
        "CANONICAL TASK", "DISPATCH PACKET", "ORIGINAL OWNER ROLE CONTRACT",
        "PRIMARY AGENT REPORT", "LATEST TASK RESULT", "LATEST INDEPENDENT REVIEW", "QA GATE"
    )
    $escapedLabels = @($labels | ForEach-Object { [regex]::Escape($_) })
    $pattern = "(?m)^===== (?:" + ($escapedLabels -join "|") + ") =====\r?$"
    $firstSection = [regex]::Match($Context,$pattern)
    if (-not $firstSection.Success) {
        return Limit-ProviderContext -Context $Context -MaxChars $MaxChars
    }

    # run-gate-agent appends the complete authoritative envelope after generic context.
    # Preserve that entire suffix, including middle evidence and section separators.
    $requiredContext = $Context.Substring($firstSection.Index)
    if ($MaxChars -le 0 -or $requiredContext.Length -gt $MaxChars) {
        throw "Required authoritative gate evidence exceeds effective provider context budget ($($requiredContext.Length) > $MaxChars). No provider call permitted; reconcile evidence or budget."
    }
    if ($Context.Length -le $MaxChars) { return $Context }
    $separator = [Environment]::NewLine
    $remaining = $MaxChars - $requiredContext.Length - $separator.Length
    if ($remaining -le 0) { return $requiredContext }
    $genericContext = $Context.Substring(0,$firstSection.Index)
    return $requiredContext + $separator + (Limit-ProviderContext -Context $genericContext -MaxChars $remaining)
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
$contextInputChars = $Context.Length + $CorrectiveContext.Length
if (-not [string]::IsNullOrEmpty($Context) -and -not [string]::IsNullOrWhiteSpace($CorrectiveContext)) { $contextInputChars += [Environment]::NewLine.Length }
$providersRoot = Join-Path $PSScriptRoot "providers"
$configPath = Join-Path $root ".codex\provider-config.json"
$validatorPath = Join-Path $PSScriptRoot "validate-json-contract.ps1"
$metricsWriterPath = Join-Path $PSScriptRoot "write-operational-event.ps1"
$localResolverPath = Join-Path $PSScriptRoot "local-runtime\resolve-local-runtime.ps1"
$localRuntimeConfigPath = Join-Path $root ".codex\local-runtime-config.json"

if (-not (Test-Path $validatorPath)) { throw "Provider contract validator not found: $validatorPath" }

if (-not [string]::IsNullOrWhiteSpace($SemanticValidatorPath)) {
    $SemanticValidatorPath = [System.IO.Path]::GetFullPath($SemanticValidatorPath)

    if (-not (Test-Path $SemanticValidatorPath -PathType Leaf)) {
        throw "Provider semantic validator not found: $SemanticValidatorPath"
    }
}

$config = $null
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$autoOrder = @("Ollama")
if ($null -ne $config -and $null -ne $config.auto_order -and @($config.auto_order).Count -gt 0) {
    $autoOrder = @($config.auto_order | ForEach-Object { [string]$_ })
}

if (
    $Workload -eq "analysis" -and
    -not [string]::IsNullOrWhiteSpace($Role) -and
    $null -ne $config -and
    $null -ne $config.analysis_auto_order_by_role
) {
    $roleOrderProperty = $config.analysis_auto_order_by_role.PSObject.Properties[$Role]

    if ($null -ne $roleOrderProperty -and @($roleOrderProperty.Value).Count -gt 0) {
        $autoOrder = @($roleOrderProperty.Value | ForEach-Object { [string]$_ })
    }
}

if (
    $Workload -eq "gate" -and
    $null -ne $config -and
    $null -ne $config.gate_auto_order -and
    @($config.gate_auto_order).Count -gt 0
) {
    $autoOrder = @(
        $config.gate_auto_order |
            ForEach-Object { [string]$_ }
    )
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
    $localRuntime = $null

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
        if (
            -not (Test-Path $localResolverPath -PathType Leaf) -or
            -not (Test-Path $localRuntimeConfigPath -PathType Leaf)
        ) {
            $errors += "Ollama: local runtime resolver/configuration missing"
            if ($Provider -ne "Auto") {
                throw "Local Ollama runtime is not configured for this project. Run initialize-local-runtime.ps1 first."
            }
            continue
        }

        $localModelOverride = ""
        if ($Provider -ne "Auto" -and -not [string]::IsNullOrWhiteSpace($Model)) {
            $localModelOverride = $Model
        }

        try {
            $localRuntime = & $localResolverPath -ProjectPath $root -Role $Role -Workload $Workload -ModelOverride $localModelOverride
        }
        catch {
            $safeLocal = Sanitize-ProviderError -Message $_.Exception.Message
            $errors += ("Ollama: " + $safeLocal)
            if ($Provider -ne "Auto") { throw $safeLocal }
            continue
        }

        if (-not [bool]$localRuntime.Available) {
            $errors += ("Ollama: " + [string]$localRuntime.Reason)
            if ($Provider -ne "Auto") { throw ([string]$localRuntime.Reason) }
            continue
        }

        if (
            $Provider -eq "Auto" -and
            $Workload -eq "analysis" -and
            -not [string]::IsNullOrWhiteSpace($Role) -and
            $null -ne $config -and
            $null -ne $config.analysis_skip_local_profiles_by_role
        ) {
            $skipProperty = $config.analysis_skip_local_profiles_by_role.PSObject.Properties[$Role]

            if (
                $null -ne $skipProperty -and
                @($skipProperty.Value) -contains [string]$localRuntime.Profile
            ) {
                $errors += (
                    "Ollama: skipped for role " + $Role +
                    " on local profile " + [string]$localRuntime.Profile
                )
                Write-Host (
                    "Provider skipped: Ollama (" +
                    [string]$localRuntime.Profile +
                    " is not approved for " + $Role +
                    " analysis)"
                ) -ForegroundColor DarkYellow
                continue
            }
        }

        Write-Host ("Local runtime profile: " + $localRuntime.Profile + "; model=" + $localRuntime.Model + "; num_ctx=" + $localRuntime.NumCtx + "; num_predict=" + $localRuntime.NumPredict) -ForegroundColor DarkGray
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
    if ($candidateName -eq "Ollama" -and $null -ne $localRuntime) {
        $providerModel = [string]$localRuntime.Model
    }
    elseif ($Provider -ne "Auto" -and -not [string]::IsNullOrWhiteSpace($Model)) {
        $providerModel = $Model
    }
    else {
        $providerModel = Get-ConfiguredModel -Config $config -Name $candidateName -Role $Role -Workload $Workload
    }

    $providerTimeoutSeconds = Get-ConfiguredTimeoutSeconds -Config $config -Name $candidateName

    $candidateContext = $Context
    $contextBudget = $null

    if (
        ($Workload -in @("analysis","gate") -and $candidateName -ne "Codex") -or
        ($Workload -eq "writable")
    ) {
        $contextBudgetArgs = @{
            Config = $config
            Role = $Role
            ProviderName = $candidateName
            Workload = $Workload
            LocalRuntime = $localRuntime
        }
        if ($Workload -eq "gate") {
            try {
                $contextBudget = Get-EffectiveProviderContextBudget @contextBudgetArgs
                $candidateContext = Limit-GateProviderContext -Context $Context -MaxChars ([int]$contextBudget.EffectiveMaxChars)
            }
            catch {
                $safeBudgetError = Sanitize-ProviderError -Message $_.Exception.Message
                Write-ProviderEvent -Event @{
                    event_type = "provider_context_rejected"
                    provider = $candidateName
                    model = $providerModel
                    success = $false
                    error_category = "context"
                    reason = $safeBudgetError
                    context_input_chars = $Context.Length
                    context_max_chars = $(if ($null -ne $contextBudget) { [int]$contextBudget.EffectiveMaxChars } else { 0 })
                } -WarningPrefix "Provider context rejection metrics could not be recorded"
                if ($Provider -ne "Auto") { throw $safeBudgetError }
                $errors += ($candidateName + ": " + $safeBudgetError)
                Write-Host ("Provider skipped: " + $candidateName + "; " + $safeBudgetError) -ForegroundColor DarkYellow
                continue
            }
        }
        elseif ($Workload -in @("analysis","writable") -and -not [string]::IsNullOrWhiteSpace($CorrectiveContext)) {
            $contextBudget = Get-EffectiveProviderContextBudget @contextBudgetArgs
            try {
                $candidateContext = Limit-CorrectiveAnalysisContext -Context $Context -RequiredContext $CorrectiveContext -MaxChars ([int]$contextBudget.EffectiveMaxChars)
            }
            catch {
                $safeBudgetError = Sanitize-ProviderError -Message $_.Exception.Message
                if ($Provider -ne "Auto") { throw $safeBudgetError }
                $errors += ($candidateName + ": " + $safeBudgetError)
                Write-Host ("Provider skipped: " + $candidateName + "; " + $safeBudgetError) -ForegroundColor DarkYellow
                continue
            }
        }
        else {
            $contextBudget = Get-EffectiveProviderContextBudget @contextBudgetArgs
            $candidateContext = Limit-ProviderContext `
                -Context $Context `
                -MaxChars ([int]$contextBudget.EffectiveMaxChars)
        }

        Write-Host (
            "Provider context: " + $candidateName +
            "; input_chars=" + $contextInputChars +
            "; effective_max_chars=" + [int]$contextBudget.EffectiveMaxChars +
            "; sent_chars=" + $candidateContext.Length +
            "; role_max_chars=" + [int]$contextBudget.RoleMaxChars +
            "; provider_max_chars=" + [int]$contextBudget.ProviderMaxChars +
            "; hardware_max_chars=" + [int]$contextBudget.HardwareMaxChars
        ) -ForegroundColor DarkGray
    }

    $attempted++
    $attemptStarted = Get-Date
    Write-Host ""
    Write-Host "Provider attempt: $candidateName" -ForegroundColor Cyan

    Write-ProviderEvent -Event @{
        event_type = "provider_attempt_started"
        provider = $candidateName
        model = $providerModel
        timeout_seconds = $providerTimeoutSeconds
        context_chars = $candidateContext.Length
        context_input_chars = $contextInputChars
        context_max_chars = $(if ($null -ne $contextBudget) { [int]$contextBudget.EffectiveMaxChars } else { 0 })
        success = $false
        error_category = ""
    } -WarningPrefix "Provider start metrics could not be recorded"

    try {
        $invokeCandidate = {
            param([string]$EffectivePrompt)

            if ($candidateName -eq "Codex") {
                if (-not [string]::IsNullOrWhiteSpace($CorrectiveContext)) { $EffectivePrompt += [Environment]::NewLine + $CorrectiveContext }
                return (& $providerScript -ProjectPath $root -Prompt $EffectivePrompt -SchemaPath $SchemaPath -OutputPath $OutputPath -Model $providerModel -TimeoutSeconds $providerTimeoutSeconds)
            }
            elseif ($candidateName -eq "Ollama") {
                $candidateResult = & $providerScript -Prompt $EffectivePrompt -Context $candidateContext -SchemaPath $SchemaPath -OutputPath $OutputPath -Model $providerModel -NumCtx ([int]$localRuntime.NumCtx) -NumPredict ([int]$localRuntime.NumPredict) -TimeoutSeconds $providerTimeoutSeconds
                $candidateResult | Add-Member -NotePropertyName HardwareProfile -NotePropertyValue ([string]$localRuntime.Profile) -Force
                $candidateResult | Add-Member -NotePropertyName NumCtx -NotePropertyValue ([int]$localRuntime.NumCtx) -Force
                $candidateResult | Add-Member -NotePropertyName NumPredict -NotePropertyValue ([int]$localRuntime.NumPredict) -Force
                return $candidateResult
            }
            else {
                return (& $providerScript -Prompt $EffectivePrompt -Context $candidateContext -SchemaPath $SchemaPath -OutputPath $OutputPath -Model $providerModel -TimeoutSeconds $providerTimeoutSeconds)
            }
        }

        $result = & $invokeCandidate $Prompt

        if (-not (Test-Path $OutputPath)) {
            throw "$candidateName returned without creating the structured output file."
        }

        & $validatorPath -JsonPath $OutputPath -SchemaPath $SchemaPath | Out-Null

        if (-not [string]::IsNullOrWhiteSpace($SemanticValidatorPath)) {
            try {
                & $SemanticValidatorPath -JsonPath $OutputPath | Out-Null
            }
            catch {
                $semanticError = Sanitize-ProviderError -Message $_.Exception.Message
                $previousOutput = ""

                if (Test-Path $OutputPath -PathType Leaf) {
                    $previousOutput = Get-Content $OutputPath -Raw -Encoding UTF8
                    if ($previousOutput.Length -gt 20000) {
                        $previousOutput = $previousOutput.Substring(0,20000) + [Environment]::NewLine + "[TRUNCATED]"
                    }
                }

                Write-Host (
                    "Semantic validation failed for " + $candidateName +
                    ". Retrying the same provider once with corrective feedback."
                ) -ForegroundColor DarkYellow

                Write-ProviderEvent -Event @{
                    event_type = "provider_semantic_retry"
                    provider = $candidateName
                    model = $providerModel
                    success = $false
                    error_category = "contract"
                } -WarningPrefix "Provider semantic retry metrics could not be recorded"

                if (Test-Path $OutputPath) {
                    Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
                }

                $repairPrompt = @(
                    $Prompt,
                    "",
                    "CORRECTION REQUIRED:",
                    "The previous structured output failed local semantic validation.",
                    ("Validation error: " + $semanticError),
                    ("Previous structured output: " + $previousOutput),
                    "",
                    "Regenerate the complete structured result from the same authoritative evidence.",
                    "Do not weaken, bypass, reinterpret, or omit the validation requirement.",
                    "Return only JSON matching the supplied schema."
                ) -join [Environment]::NewLine

                $result = & $invokeCandidate $repairPrompt

                if (-not (Test-Path $OutputPath)) {
                    throw "$candidateName semantic retry returned without creating the structured output file."
                }

                & $validatorPath -JsonPath $OutputPath -SchemaPath $SchemaPath | Out-Null
                & $SemanticValidatorPath -JsonPath $OutputPath | Out-Null
            }
        }

        $durationMs = [int][math]::Round(((Get-Date) - $attemptStarted).TotalMilliseconds)

        Write-ProviderEvent -Event @{
            event_type = "provider_attempt"
            provider = $candidateName
            model = [string]$result.Model
            duration_ms = $durationMs
            timeout_seconds = $providerTimeoutSeconds
            success = $true
            error_category = ""
        } -WarningPrefix "Provider success metrics could not be recorded"

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

        # A failed or timed-out provider must never leave a consumable structured
        # result behind, regardless of whether the adapter wrote a partial file.
        if (Test-Path $OutputPath) {
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }

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
