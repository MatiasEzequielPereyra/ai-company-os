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

function Test-RequiresConcreteEngineeringPlan {
    param(
        [string]$Owner,
        [string]$TaskContent
    )

    if ($Owner -ne "engineering-manager") { return $false }

    return (
        $TaskContent -match '(?i)engineering execution plan|engineering plan|execution plan|decompos.*engineering|executable engineering'
    )
}

function Assert-ConcreteEngineeringPlanResult {
    param(
        [object]$Result,
        [string]$TaskId
    )

    $items = @($Result.executable_work)

    if ([string]$Result.outcome -eq "BLOCKED") {
        if ($items.Count -ne 0) {
            throw "${TaskId}: BLOCKED Engineering Manager result must not contain executable work."
        }
        return
    }

    if ([string]$Result.outcome -ne "COMPLETED") {
        throw "${TaskId}: unsupported Engineering Manager outcome: $($Result.outcome)"
    }

    if ($items.Count -lt 1) {
        throw "${TaskId}: Engineering Manager COMPLETED result contains no executable_work items."
    }

    $keys = @{}
    $implementationCount = 0

    foreach ($item in $items) {
        $key = ([string]$item.key).Trim()
        $kind = ([string]$item.kind).Trim()
        $change = ([string]$item.change).Trim()
        $areas = @($item.areas | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        $dependsOn = @($item.depends_on | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })

        if ([string]::IsNullOrWhiteSpace($key)) {
            throw "${TaskId}: Engineering Manager executable_work item key cannot be empty."
        }

        if ($keys.ContainsKey($key)) {
            throw "${TaskId}: duplicate Engineering Manager executable_work key: $key"
        }

        $keys[$key] = $true

        if ($kind -eq "IMPLEMENTATION") {
            $implementationCount++

            $semanticText = @(
                $change,
                ($areas -join " ")
            ) -join " "

            if ($semanticText -match '(?i)\b(create|refine|materialize|generate|prepare|update)\b.{0,100}\b(executable tasks?|engineering tasks?|task set|backlog|work requests?|dispatch packets?|lifecycle state|gate evidence)\b') {
                throw "${TaskId}: Engineering Manager plan contains recursive meta-implementation work: $change"
            }

            foreach ($area in $areas) {
                if ($area -match '(?i)^(tasks?|backlog|planning|lifecycle|docs[\\/]engineering[\\/](dispatch|results|reviews|qa|security|final-approvals))([\\/]|$)') {
                    throw "${TaskId}: Engineering Manager implementation targets control-plane area: $area"
                }
            }
        }

        if ($dependsOn -contains $key) {
            throw "${TaskId}: Engineering Manager work item $key cannot depend on itself."
        }
    }

    foreach ($item in $items) {
        foreach ($dependency in @($item.depends_on)) {
            $dependencyKey = ([string]$dependency).Trim()
            if ([string]::IsNullOrWhiteSpace($dependencyKey)) { continue }
            if (-not $keys.ContainsKey($dependencyKey)) {
                throw "${TaskId}: Engineering Manager work item $($item.key) references unknown dependency: $dependencyKey"
            }
        }
    }

    if ($implementationCount -lt 1) {
        throw "${TaskId}: Engineering Manager executable plan contains no real IMPLEMENTATION work."
    }
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
$requiresConcreteEngineeringPlan = Test-RequiresConcreteEngineeringPlan -Owner $owner -TaskContent $task

$lockHelperPath = Join-Path $PSScriptRoot "task-execution-lock.ps1"
if (-not (Test-Path $lockHelperPath -PathType Leaf)) {
    throw "Task execution lock helper not found: $lockHelperPath"
}
. $lockHelperPath
$taskExecutionLock = Enter-TaskExecutionLock -ProjectPath $root -Id $Id -Operation "ANALYSIS"

try {

$dispatchPath = Join-Path $root ("docs\engineering\dispatch\" + $Id + ".md")
$rolePath = Join-Path $root (".codex\agents\" + $owner + ".md")
$schemaName = if ($requiresConcreteEngineeringPlan) {
    "engineering-plan-result.schema.json"
}
else {
    "agent-result.schema.json"
}
$schemaPath = Join-Path $root ("schemas\" + $schemaName)
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
    "For API providers, use only the supplied Repository Context Pack and never claim access to omitted files.",
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
    "The report_markdown field must contain the complete role report with findings, evidence, risks and recommended actions.",
    "The summary field must be concise.",
    "Keep the structured result concise and evidence-dense.",
    "Do not reproduce repository files or large code excerpts.",
    "summary must stay within 800 characters.",
    "report_markdown must stay within 8000 characters and should prefer concise evidence-backed bullets.",
    "verification and decisions must each stay within 2000 characters.",
    $(if ($requiresConcreteEngineeringPlan) {
        "For Engineering Manager execution planning, populate executable_work using the dedicated JSON schema. report_markdown is narrative context only; the runtime renders the canonical executable work section."
    } else { "" }),
    $(if ($requiresConcreteEngineeringPlan) {
        "Each executable_work item must name a stable key, kind, concrete change, responsible owner, real repository/product areas, dependency keys and a concrete verification."
    } else { "" }),
    $(if ($requiresConcreteEngineeringPlan) {
        "A COMPLETED plan MUST contain at least one real IMPLEMENTATION item against product/repository code, configuration, tests, data/schema, infrastructure or deployable behavior. Task/backlog/lifecycle authoring is never IMPLEMENTATION."
    } else { "" }),
    $(if ($requiresConcreteEngineeringPlan) {
        "Use BLOCKED with executable_work=[] only when evidence or an authoritative prerequisite is materially insufficient to produce a safe implementation plan."
    } else { "" }),
    "Return only the structured result required by the supplied JSON schema."
)
$prompt = $promptLines -join [Environment]::NewLine

$localRuntime = $null
if ($Provider -in @("Auto","Ollama") -and (Test-Path $localResolverPath -PathType Leaf) -and (Test-Path $localRuntimeConfigPath -PathType Leaf)) {
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
# local Ollama, requires the bounded Repository Context Pack. Auto always builds
# it because the selected fallback provider is not known until routing time.
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
    if (Test-Path $configPath) {
        try {
            $providerConfig = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

            if ($null -ne $providerConfig.analysis_context_max_chars) {
                $globalAnalysisMax = [int]$providerConfig.analysis_context_max_chars
            }
            elseif ($null -ne $providerConfig.context_max_chars) {
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
                    $maxChars = [Math]::Min([int]$roleProperty.Value,$globalAnalysisMax)
                }
            }

            if ($null -ne $localRuntime -and [bool]$localRuntime.Available) {
                $maxChars = [Math]::Min($maxChars,[int]$localRuntime.ContextMaxChars)
            }
            elseif (
                $Provider -eq "Ollama" -and
                $null -ne $providerConfig.ollama_context_max_chars
            ) {
                $maxChars = [Math]::Min($maxChars,[int]$providerConfig.ollama_context_max_chars)
            }
        }
        catch {
            throw "Invalid provider configuration: $configPath"
        }
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

if ($requiresConcreteEngineeringPlan) {
    if ($null -eq $result.PSObject.Properties["executable_work"]) {
        throw "Structured Engineering Manager result is missing field: executable_work"
    }
    Assert-ConcreteEngineeringPlanResult -Result $result -TaskId $Id
}

$providerUsed = [string]$execution.Provider
$modelUsed = [string]$execution.Model
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$reportBody = [string]$result.report_markdown
$executionPlanRelative = ""

if ($requiresConcreteEngineeringPlan -and [string]$result.outcome -eq "COMPLETED") {
    $plansDir = Join-Path $root "docs\engineering\plans"
    New-Item -ItemType Directory -Force -Path $plansDir | Out-Null

    $workRequestId = Read-Field $task "Work request"
    $executionPlanPath = Join-Path $plansDir ($Id + "-execution-plan.json")

    $canonicalPlan = [ordered]@{
        source_task_id = $Id
        work_request_id = $workRequestId
        generated = $now
        provider = $providerUsed
        model = $modelUsed
        summary = [string]$result.summary
        executable_work = @($result.executable_work)
    }

    Write-Utf8NoBom $executionPlanPath ($canonicalPlan | ConvertTo-Json -Depth 100)
    $executionPlanRelative = "docs/engineering/plans/" + (Split-Path $executionPlanPath -Leaf)

    $workLines = @(
        foreach ($item in @($result.executable_work)) {
            $areasText = (@($item.areas) -join ", ")
            $dependsText = if (@($item.depends_on).Count -eq 0) { "NONE" } else { @($item.depends_on) -join ", " }

            "- Kind: $($item.kind) | Key: $($item.key) | Change: $($item.change) | Owner: $($item.owner) | Areas: $areasText | Depends on: $dependsText | Verify: $($item.verify)"
        }
    )

    $reportBody = @(
        [string]$result.report_markdown,
        "",
        "## Executable Work",
        "",
        ($workLines -join [Environment]::NewLine),
        "",
        "Canonical plan: $executionPlanRelative"
    ) -join [Environment]::NewLine
}

$report = @(
    "# Agent Report - $Id",
    "",
    "Generated: $now",
    "Owner: $owner",
    "Provider: $providerUsed",
    "Model: $modelUsed",
    "Outcome: $($result.outcome)",
    "",
    $reportBody
) -join [Environment]::NewLine

Write-Utf8NoBom $reportPath $report

$submit = Join-Path $PSScriptRoot "submit-task-result.ps1"
if (-not (Test-Path $submit)) { throw "submit-task-result.ps1 not found: $submit" }

$changedParts = @("docs/engineering/agent-reports/" + (Split-Path $reportPath -Leaf))
if (-not [string]::IsNullOrWhiteSpace($executionPlanRelative)) {
    $changedParts += $executionPlanRelative
}
$changed = $changedParts -join "; "
& $submit -ProjectPath $root -Id $Id -Outcome $result.outcome -Summary $result.summary -ChangedArtifacts $changed -Verification $result.verification -Decisions $result.decisions -Blockers $result.blockers -RecommendedNext $result.recommended_next

Write-Host ""
Write-Host "Agent task completed:" -ForegroundColor Green
Write-Host "$Id - $owner - $($result.outcome)"
Write-Host "Provider: $providerUsed"
Write-Host "Model: $modelUsed"
Write-Host "Report: $changed"
}
finally {
    Exit-TaskExecutionLock -Lock $taskExecutionLock
}
