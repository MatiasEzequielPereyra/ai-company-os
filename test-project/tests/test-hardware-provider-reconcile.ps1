$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

$config = Get-Content (Join-Path $repoRoot ".codex\provider-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json

$expectedAnalysisProviders = @("Ollama","OpenRouter","Gemini","DeepSeek","Grok","Codex")
foreach ($provider in $expectedAnalysisProviders) {
    if (@($config.auto_order) -notcontains $provider) {
        throw "Analysis Auto provider order must include $provider"
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

if (@($config.writable_auto_order) -join "," -ne "OpenRouter,Gemini") {
    throw "Writable Auto must remain restricted to OpenRouter then Gemini"
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
    'ContextMaxChars',
    '-Role \$owner',
    '-Workload "analysis"'
)) {
    if ($agentRunner -notmatch $needle) {
        throw "Analysis runner reconciliation contract missing: $needle"
    }
}

$gateRunner = Get-Content (Join-Path $repoRoot "scripts\run-gate-agent.ps1") -Raw -Encoding UTF8
if ($gateRunner -notmatch 'ValidateSet\("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok"\)') {
    throw "Gate runner must expose the reconciled provider set"
}
foreach ($needle in @(
    'local-runtime\\resolve-local-runtime\.ps1',
    'local-runtime-config\.json',
    'GateContextMaxChars',
    'GateArtifactMaxChars',
    '-Role \$reviewerRole',
    '-Workload "gate"'
)) {
    if ($gateRunner -notmatch $needle) {
        throw "Gate runner reconciliation contract missing: $needle"
    }
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
if ($writableRunner -notmatch 'ValidateSet\("Auto","OpenRouter","Gemini"\)') {
    throw "Writable runtime provider surface must remain unchanged"
}
if ($writableRunner -match 'ValidateSet\([^\r\n]*Ollama') {
    throw "Ollama must not be enabled in writable execution by this reconciliation"
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
