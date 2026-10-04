$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

$config = Get-Content (Join-Path $repoRoot ".codex\provider-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json

$analysisAutoOrder = @($config.auto_order)

if (($analysisAutoOrder -join ",") -ne "Ollama") {
    throw "Analysis Auto must be local-only Ollama"
}

foreach ($remoteProvider in @("OpenRouter","Gemini","DeepSeek","Grok","Codex")) {
    if ($analysisAutoOrder -contains $remoteProvider) {
        throw "$remoteProvider must not be an automatic analysis fallback"
    }
}

if ([bool]$config.allow_paid_fallback) {
    throw "Paid analysis fallback must remain disabled by default"
}

if ([int]$config.context_max_chars -gt 160000) {
    throw "Generic provider context must not regress to the historical oversized budget"
}
if ([int]$config.analysis_context_max_chars -gt 160000) {
    throw "Analysis context P0 budget must remain bounded"
}
if ($null -eq $config.analysis_context_max_chars_by_role) {
    throw "Role-aware analysis budgets must be preserved"
}
if ([int]$config.analysis_context_max_chars_by_role.pm -gt 100000) {
    throw "PM analysis budget must remain below the historical oversized budget"
}

if ([int]$config.ollama_context_max_chars -lt 10000 -or [int]$config.ollama_context_max_chars -gt 60000) {
    throw "Ollama analysis context must be explicitly bounded for local hardware"
}
if ([int]$config.ollama_gate_context_max_chars -lt 4000 -or [int]$config.ollama_gate_context_max_chars -gt 30000) {
    throw "Ollama gate context must be explicitly bounded"
}
if ([int]$config.ollama_gate_artifact_max_chars -lt 1000 -or [int]$config.ollama_gate_artifact_max_chars -gt 10000) {
    throw "Ollama gate artifact budget must be explicitly bounded"
}

if (@($config.writable_auto_order) -join "," -ne "Ollama") {
    throw "Writable Auto must be local-only Ollama"
}
if ($null -ne $config.writable_allow_paid_fallback -and [bool]$config.writable_allow_paid_fallback) {
    throw "Writable paid fallback must remain disabled"
}

$router = Get-Content (Join-Path $repoRoot "scripts\provider-router.ps1") -Raw -Encoding UTF8
if ($router -notmatch 'ValidateSet\("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok"\)') {
    throw "Provider router must expose the reconciled analysis provider set"
}
foreach ($needle in @(
    'local-runtime\\resolve-local-runtime\.ps1',
    'local-runtime-config\.json',
    'allow_paid_fallback',
    'invoke-ollama\.ps1',
    'invoke-deepseek\.ps1',
    'invoke-xai\.ps1',
    'DEEPSEEK_API_KEY',
    'XAI_API_KEY',
    'Workload',
    'Role'
)) {
    if ($router -notmatch $needle) {
        throw "Provider router reconciliation contract missing: $needle"
    }
}

$agentRunner = Get-Content (Join-Path $repoRoot "scripts\run-agent-task.ps1") -Raw -Encoding UTF8
if ($agentRunner -notmatch 'ValidateSet\("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok"\)') {
    throw "Analysis runner must expose the reconciled provider set"
}
foreach ($needle in @(
    'analysis_context_max_chars_by_role',
    'analysis_context_max_chars',
    'local-runtime\\resolve-local-runtime\.ps1',
    'local-runtime-config\.json',
    'ContextMaxChars'
)) {
    if ($agentRunner -notmatch $needle) {
        throw "Analysis runner reconciliation contract missing: $needle"
    }
}

$directRoleRouting = (
    $agentRunner -match '-Role \$owner' -and
    $agentRunner -match '-Workload "analysis"'
)

$splatRoleRouting = (
    $agentRunner -match '(?s)\$routerArgs\s*=\s*@\{.*?Role\s*=\s*\$owner.*?Workload\s*=\s*"analysis".*?\}' -and
    $agentRunner -match '\$execution\s*=\s*&\s*\$routerPath\s+@routerArgs'
)

if (-not ($directRoleRouting -or $splatRoleRouting)) {
    throw "Analysis runner must pass owner role and analysis workload to provider routing"
}

$gateRunner = Get-Content (Join-Path $repoRoot "scripts\run-gate-agent.ps1") -Raw -Encoding UTF8
if ($gateRunner -notmatch 'ValidateSet\("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok"\)') {
    throw "Gate runner must expose the reconciled provider set"
}
foreach ($needle in @(
    'local-runtime\\resolve-local-runtime\.ps1',
    'local-runtime-config\.json',
    '-Role \$reviewerRole',
    '-Workload "gate"'
)) {
    if ($gateRunner -notmatch $needle) {
        throw "Gate runner reconciliation contract missing: $needle"
    }
}

# Candidate budgets are applied centrally, after the complete authoritative
# envelope has been assembled. Per-artifact clipping would lose gate evidence.
if ($router -notmatch 'GateContextMaxChars' -or $router -notmatch 'Limit-GateProviderContext') {
    throw "Provider router must enforce the hardware gate context budget"
}
if ($gateRunner -match '\$content\s*=\s*\$content\.Substring') {
    throw "Gate runner must not truncate authoritative artifacts before routing"
}

if ($router -notmatch 'localRuntimeConfigPath') {
    throw "Provider router must guard optional local runtime configuration"
}
if ($agentRunner -notmatch 'localRuntimeConfigured') {
    throw "Auto must tolerate projects without local runtime configuration in analysis"
}
if ($gateRunner -notmatch 'localRuntimeConfigured') {
    throw "Auto must tolerate projects without local runtime configuration in gates"
}

$writableRunner = Get-Content (Join-Path $repoRoot "scripts\run-writable-agent.ps1") -Raw -Encoding UTF8
if ($writableRunner -notmatch 'ValidateSet\("Auto","Ollama","OpenRouter","Gemini"\)') {
    throw "Writable runtime must expose Auto/Ollama/OpenRouter/Gemini"
}
if ($writableRunner -notmatch '\$order = @\("Ollama"\)') {
    throw "Writable Auto fallback must default to local-only Ollama"
}
if ($writableRunner -notmatch '\$candidate -notin @\("Ollama","OpenRouter","Gemini"\)') {
    throw "Writable provider filter must allow Ollama, OpenRouter and Gemini"
}
if ($writableRunner -notmatch '\$candidate -ne "Ollama"') {
    throw "Writable local Ollama must bypass remote free-model validation"
}

$parseTargets = @(
    "scripts\provider-router.ps1",
    "scripts\run-agent-task.ps1",
    "scripts\run-gate-agent.ps1"
)
foreach ($relative in $parseTargets) {
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

Write-Host "PASS: hardware/provider reconciliation contract" -ForegroundColor Green
