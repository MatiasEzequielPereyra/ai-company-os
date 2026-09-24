param(
    [Parameter(Mandatory = $true)]
    [string]$Id,
    [string]$ProjectPath = ".",
    [ValidateSet("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok")]
    [string]$Provider = "Auto",
    [string]$Model = "",
    [ValidateSet("Auto","ChatGPT","ApiKey")]
    [string]$AuthMode = "Auto"
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

if ($PSBoundParameters.ContainsKey("AuthMode") -and -not $PSBoundParameters.ContainsKey("Provider")) {
    if ($AuthMode -eq "ChatGPT") {
        $Provider = "Codex"
    }
    elseif ($AuthMode -eq "ApiKey") {
        throw "Legacy -AuthMode ApiKey is disabled to prevent accidental OpenAI API spend. Select an explicit provider such as OpenRouter, Gemini, Ollama, DeepSeek, or Grok."
    }
}

$root = (Resolve-Path $ProjectPath).Path
$tasksPath = Join-Path $root "tasks"
$taskPath = Join-Path $tasksPath ($Id + ".md")
if (-not (Test-Path $taskPath)) { throw "Task not found: $taskPath" }

$task = Get-Content $taskPath -Raw -Encoding UTF8
$status = Read-Field $task "Status"
$owner = Read-Field $task "Owner"
if ($status -ne "ACTIVE") { throw "Task $Id must be ACTIVE. Current status: $status" }
if ([string]::IsNullOrWhiteSpace($owner)) { throw "Task $Id has no owner." }

$dispatchPath = Join-Path $root ("docs\engineering\dispatch\" + $Id + ".md")
$rolePath = Join-Path $root (".codex\agents\" + $owner + ".md")
$schemaPath = Join-Path $root "schemas\agent-result.schema.json"
$routerPath = Join-Path $PSScriptRoot "provider-router.ps1"
$contextBuilderPath = Join-Path $PSScriptRoot "build-agent-context.ps1"
$localResolverPath = Join-Path $PSScriptRoot "local-runtime\resolve-local-runtime.ps1"
$localRuntimeConfigPath = Join-Path $root ".codex\local-runtime-config.json"

if (-not (Test-Path $dispatchPath)) { throw "Dispatch packet not found: $dispatchPath" }
if (-not (Test-Path $rolePath)) { throw "Role instructions not found: $rolePath" }
if (-not (Test-Path $schemaPath)) { throw "Agent result schema not found: $schemaPath" }
if (-not (Test-Path $routerPath)) { throw "Provider router not found: $routerPath" }

$runtimeDir = Join-Path $root ".codex\runtime"
$reportsDir = Join-Path $root "docs\engineering\agent-reports"
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

$jsonPath = Join-Path $runtimeDir ($Id + "-result.json")
$reportPath = Join-Path $reportsDir ($Id + ".md")

$promptLines = @(
    "You are executing an AI Company OS task.",
    "",
    "Role: $owner",
    "Task: $Id",
    "",
    "Follow the role authority, task objective, dispatch packet and supplied project evidence.",
    "For Codex, inspect the repository directly in read-only mode.",
    "For external or local providers, use only the supplied Repository Context Pack and never claim access to omitted files.",
    "",
    "This execution is AUDIT/ANALYSIS ONLY.",
    "Do not edit production code or change Git state.",
    "Separate verified evidence from assumptions.",
    "Reference concrete repository-relative files and symbols when supported by evidence.",
    "The external Repository Context Pack is intentionally bounded.",
    "Do not return BLOCKED merely because some repository files are omitted or canonical context templates are absent.",
    "Record non-material evidence gaps as unresolved questions and complete the assigned role deliverable when the available evidence is sufficient.",
    "Return BLOCKED only when a materially required decision cannot be supported without missing evidence.",
    "Outcome semantics are strict:",
    "- COMPLETED means you completed the assigned audit, analysis, review or planning deliverable. Use COMPLETED even when you discover P0/P1 defects, release blockers, failed checks or production-readiness issues.",
    "- BLOCKED means you could not complete the assigned agent task itself because evidence, access, authorization or a prerequisite was materially unavailable.",
    "The blockers field is only for execution blockers that prevented task completion. Product defects, release blockers, security findings and QA failures belong in report_markdown/decisions/recommended_next.",
    "If the report contains a substantive completed assessment and no execution prerequisite prevented delivery, outcome must be COMPLETED and blockers should be NONE.",
    "",
    "Keep the structured result concise and evidence-dense.",
    "Do not reproduce repository files or large code excerpts.",
    "summary must stay within 800 characters.",
    "report_markdown must stay within 8000 characters and should prefer concise evidence-backed bullets.",
    "verification and decisions must each stay within 2000 characters.",
    "blockers and recommended_next must each stay within 1500 characters.",
    "The report_markdown field must still contain the complete role deliverable within those limits.",
    "The summary field must be concise.",
    "Return only the structured result required by the supplied JSON schema."
)
$prompt = $promptLines -join [Environment]::NewLine

$localRuntime = $null
$localRuntimeConfigured = (
    (Test-Path $localResolverPath -PathType Leaf) -and
    (Test-Path $localRuntimeConfigPath -PathType Leaf)
)

if ($Provider -eq "Ollama" -and -not $localRuntimeConfigured) {
    throw "Ollama local runtime is not configured for this project. Run initialize-local-runtime.ps1 first."
}

if ($Provider -in @("Auto","Ollama") -and $localRuntimeConfigured) {
    $localArgs = @{
        ProjectPath = $root
        Role = $owner
        Workload = "analysis"
    }

    if ($Provider -eq "Ollama" -and -not [string]::IsNullOrWhiteSpace($Model)) {
        $localArgs.ModelOverride = $Model
    }

    $localRuntime = & $localResolverPath @localArgs
    if ($Provider -eq "Ollama" -and -not [bool]$localRuntime.Available) {
        throw ("Ollama local runtime unavailable: " + [string]$localRuntime.Reason)
    }

    if ([bool]$localRuntime.Available) {
        Write-Host ("Local runtime: " + $localRuntime.Profile + " -> " + $localRuntime.Model) -ForegroundColor DarkGray
    }
}

$context = ""
# Codex can inspect the repository directly. Every other provider, including
# local Ollama, requires the bounded Repository Context Pack. Auto builds it
# because the selected fallback provider is not known until routing time.
$needsExternalContext = ($Provider -ne "Codex")

if ($needsExternalContext) {
    if (-not (Test-Path $contextBuilderPath)) { throw "Context builder not found: $contextBuilderPath" }

    $defaultGlobalAnalysisMax = 120000
    $defaultRoleBudgets = @{
        "pm" = 70000
        "cto" = 110000
        "engineering-manager" = 120000
        "qa" = 90000
        "security" = 100000
        "devops" = 90000
    }

    $globalAnalysisMax = $defaultGlobalAnalysisMax
    $maxChars = if ($defaultRoleBudgets.ContainsKey($owner.ToLowerInvariant())) {
        [int]$defaultRoleBudgets[$owner.ToLowerInvariant()]
    }
    else {
        $defaultGlobalAnalysisMax
    }

    $configPath = Join-Path $root ".codex\provider-config.json"
    $providerConfig = $null
    if (Test-Path $configPath) {
        try {
            $providerConfig = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

            if ($null -ne $providerConfig.analysis_context_max_chars) {
                $globalAnalysisMax = [int]$providerConfig.analysis_context_max_chars
            }
            elseif ($null -ne $providerConfig.context_max_chars) {
                # Legacy configs may still contain the old 320k generic budget.
                # Clamp that legacy value so upgraded runtimes become safe without
                # requiring an immediate provider-config rewrite in client projects.
                $globalAnalysisMax = [Math]::Min(
                    [int]$providerConfig.context_max_chars,
                    $defaultGlobalAnalysisMax
                )
            }

            $maxChars = if ($defaultRoleBudgets.ContainsKey($owner.ToLowerInvariant())) {
                [Math]::Min(
                    [int]$defaultRoleBudgets[$owner.ToLowerInvariant()],
                    $globalAnalysisMax
                )
            }
            else {
                $globalAnalysisMax
            }

            if ($null -ne $providerConfig.analysis_context_max_chars_by_role) {
                $roleProperty = $providerConfig.analysis_context_max_chars_by_role.PSObject.Properties[$owner]
                if ($null -ne $roleProperty -and $null -ne $roleProperty.Value) {
                    $maxChars = [int]$roleProperty.Value
                }
            }
        }
        catch {
            throw "Invalid provider configuration: $configPath"
        }
    }

    if ($null -ne $localRuntime -and [bool]$localRuntime.Available) {
        $maxChars = [Math]::Min($maxChars,[int]$localRuntime.ContextMaxChars)
    }
    elseif (
        $Provider -eq "Ollama" -and
        $null -ne $providerConfig -and
        $null -ne $providerConfig.ollama_context_max_chars
    ) {
        $maxChars = [Math]::Min($maxChars,[int]$providerConfig.ollama_context_max_chars)
    }

    if ($maxChars -lt 10000) {
        throw "Analysis context budget is too small for canonical task context: $maxChars"
    }

    Write-Host "Building role-aware repository context for $owner..." -ForegroundColor DarkGray
    $context = & $contextBuilderPath -ProjectPath $root -Id $Id -Owner $owner -MaxChars $maxChars
    Write-Host ("Context pack: " + $context.Length + " characters") -ForegroundColor DarkGray
}

Write-Host "Running agent: $owner -> $Id" -ForegroundColor Cyan
Write-Host "Provider mode: $Provider" -ForegroundColor DarkGray

$execution = & $routerPath -Provider $Provider -ProjectPath $root -Prompt $prompt -Context $context -SchemaPath $schemaPath -OutputPath $jsonPath -Model $Model -Role $owner -Workload "analysis"

if (-not (Test-Path $jsonPath)) { throw "Provider runtime did not produce structured output: $jsonPath" }

$result = Get-Content $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($field in @("outcome","summary","report_markdown","verification","decisions","blockers","recommended_next")) {
    if ($null -eq $result.PSObject.Properties[$field]) {
        throw "Structured agent result is missing field: $field"
    }
}

$providerUsed = [string]$execution.Provider
$modelUsed = [string]$execution.Model
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$report = @(
    "# Agent Report - $Id",
    "",
    "Generated: $now",
    "Owner: $owner",
    "Provider: $providerUsed",
    "Model: $modelUsed",
    "Outcome: $($result.outcome)",
    "",
    $result.report_markdown
) -join [Environment]::NewLine

Write-Utf8NoBom $reportPath $report

$submit = Join-Path $PSScriptRoot "submit-task-result.ps1"
if (-not (Test-Path $submit)) { throw "submit-task-result.ps1 not found: $submit" }

$changed = "docs/engineering/agent-reports/" + (Split-Path $reportPath -Leaf)
& $submit -ProjectPath $root -Id $Id -Outcome $result.outcome -Summary $result.summary -ChangedArtifacts $changed -Verification $result.verification -Decisions $result.decisions -Blockers $result.blockers -RecommendedNext $result.recommended_next

Write-Host ""
Write-Host "Agent task completed:" -ForegroundColor Green
Write-Host "$Id - $owner - $($result.outcome)"
Write-Host "Provider: $providerUsed"
Write-Host "Model: $modelUsed"
Write-Host "Report: $changed"
