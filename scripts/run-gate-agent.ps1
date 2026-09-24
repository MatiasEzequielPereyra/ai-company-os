param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Review","QA","Security")]
    [string]$Gate,

    [string]$ProjectPath = ".",

    [ValidateSet("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok")]
    [string]$Provider = "Auto",

    [string]$Model = ""
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Add-Artifact {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$Path,
        [string]$Label,
        [int]$MaxChars = 60000
    )

    if (-not (Test-Path $Path -PathType Leaf)) { return }

    $content = Get-Content $Path -Raw -Encoding UTF8
    if ($null -eq $content) { $content = "" }
    if ($content.Length -gt $MaxChars) {
        $content = $content.Substring(0,$MaxChars) + [Environment]::NewLine + "[TRUNCATED]"
    }

    [void]$Builder.AppendLine("")
    [void]$Builder.AppendLine("")
    [void]$Builder.AppendLine("===== " + $Label + " =====")
    [void]$Builder.AppendLine($content)
}

$root = (Resolve-Path $ProjectPath).Path
$taskPath = Join-Path $root ("tasks\" + $Id + ".md")
if (-not (Test-Path $taskPath)) { throw "Task not found: $taskPath" }

$taskContent = Get-Content $taskPath -Raw -Encoding UTF8
$status = Read-Field $taskContent "Status"
$owner = Read-Field $taskContent "Owner"

$expectedStatus = switch ($Gate) {
    "Review" { "REVIEW" }
    "QA" { "QA" }
    "Security" { "SECURITY" }
}

if ($status -ne $expectedStatus) {
    throw "Task $Id must be $expectedStatus for $Gate gate. Current status: $status"
}

$reviewerRole = switch ($Gate) {
    "Review" { "engineering-manager" }
    "QA" {
        if ($owner -eq "qa") { "engineering-manager" } else { "qa" }
    }
    "Security" {
        if ($owner -eq "security") { "engineering-manager" } else { "security" }
    }
}

$schemaName = switch ($Gate) {
    "Review" { "review-result.schema.json" }
    "QA" { "qa-gate-result.schema.json" }
    "Security" { "security-gate-result.schema.json" }
}

$schemaPath = Join-Path $root ("schemas\" + $schemaName)
$routerPath = Join-Path $PSScriptRoot "provider-router.ps1"
$contextBuilderPath = Join-Path $PSScriptRoot "build-agent-context.ps1"
$localResolverPath = Join-Path $PSScriptRoot "local-runtime\resolve-local-runtime.ps1"
$localRuntimeConfigPath = Join-Path $root ".codex\local-runtime-config.json"

foreach ($required in @($schemaPath,$routerPath,$contextBuilderPath)) {
    if (-not (Test-Path $required)) { throw "Required gate component not found: $required" }
}

$localRuntime = $null
if ($Provider -in @("Auto","Ollama") -and (Test-Path $localResolverPath -PathType Leaf) -and (Test-Path $localRuntimeConfigPath -PathType Leaf)) {
    $localArgs = @{
        ProjectPath = $root
        Role = $reviewerRole
        Workload = "gate"
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

$maxChars = 180000
$artifactMaxChars = 60000
$configPath = Join-Path $root ".codex\provider-config.json"
if (Test-Path $configPath) {
    try {
        $providerConfig = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $providerConfig.gate_context_max_chars) {
            $maxChars = [int]$providerConfig.gate_context_max_chars
        }

        if ($null -ne $localRuntime -and [bool]$localRuntime.Available) {
            $maxChars = [Math]::Min($maxChars,[int]$localRuntime.GateContextMaxChars)
            $artifactMaxChars = [Math]::Min($artifactMaxChars,[int]$localRuntime.GateArtifactMaxChars)
        }
        elseif ($Provider -eq "Ollama") {
            if ($null -ne $providerConfig.ollama_gate_context_max_chars) {
                $maxChars = [Math]::Min($maxChars,[int]$providerConfig.ollama_gate_context_max_chars)
            }
            if ($null -ne $providerConfig.ollama_gate_artifact_max_chars) {
                $artifactMaxChars = [int]$providerConfig.ollama_gate_artifact_max_chars
            }
        }
    }
    catch {
        throw "Invalid provider configuration: $configPath"
    }
}

Write-Host "Building gate context for $Gate / $reviewerRole..." -ForegroundColor DarkGray
$baseContext = & $contextBuilderPath -ProjectPath $root -Id $Id -Owner $reviewerRole -MaxChars $maxChars

$evidence = New-Object System.Text.StringBuilder
[void]$evidence.Append($baseContext)

$reportPath = Join-Path $root ("docs\engineering\agent-reports\" + $Id + ".md")
Add-Artifact -Builder $evidence -Path $reportPath -Label "PRIMARY AGENT REPORT" -MaxChars $artifactMaxChars

$latestResult = Get-ChildItem (Join-Path $root "docs\engineering\results") -Filter ($Id + "-result-*.md") -File -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1
if ($null -ne $latestResult) {
    Add-Artifact -Builder $evidence -Path $latestResult.FullName -Label "LATEST TASK RESULT" -MaxChars $artifactMaxChars
}

if ($Gate -in @("QA","Security")) {
    $latestReview = Get-ChildItem (Join-Path $root "docs\engineering\reviews") -Filter ($Id + "-review-*.md") -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -ne $latestReview) {
        Add-Artifact -Builder $evidence -Path $latestReview.FullName -Label "LATEST INDEPENDENT REVIEW" -MaxChars $artifactMaxChars
    }
}

if ($Gate -eq "Security") {
    $qaPath = Join-Path $root ("docs\engineering\qa\" + $Id + "-qa.md")
    Add-Artifact -Builder $evidence -Path $qaPath -Label "QA GATE" -MaxChars $artifactMaxChars
}

$promptLines = @(
    "You are executing an independent AI Company OS quality gate.",
    "",
    "Gate: $Gate",
    "Task: $Id",
    "Original owner: $owner",
    "Independent gate role: $reviewerRole",
    "",
    "Evaluate the assigned task deliverable against its objective, acceptance criteria, evidence quality, internal consistency and role boundaries.",
    "This gate evaluates whether the DELIVERABLE is good enough to progress through the workflow.",
    "Do not reject or fail merely because the underlying product has defects, P0/P1 findings, security issues, release blockers or failed product checks documented by the report.",
    "A strong audit report is allowed to conclude that the product is not production-ready.",
    "Reject/fail only when the report or task delivery itself is materially incomplete, unsupported, contradictory, outside role authority, or fails the assigned acceptance criteria.",
    "Do not invent repository evidence.",
    "Use only the supplied context and artifacts.",
    "",
    "For Review: APPROVE means the deliverable is fit to proceed to QA; CHANGES_REQUIRED means the deliverable itself needs corrective work.",
    "For QA: PASS means the deliverable satisfies its task-level acceptance and evidence requirements; FAIL means the deliverable itself does not.",
    "For Security: PASS means security-relevant aspects of the deliverable are adequately handled; FAIL means the deliverable itself has a security-quality defect; NOT_APPLICABLE is appropriate when an additional security gate provides no meaningful verification for an analysis-only deliverable.",
    "",
    "Return only the structured JSON required by the supplied schema."
)

$prompt = $promptLines -join [Environment]::NewLine

$runtimeDir = Join-Path $root ".codex\runtime"
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
$outputPath = Join-Path $runtimeDir ($Id + "-" + $Gate.ToLowerInvariant() + "-gate.json")

Write-Host ("Gate context budget: base=" + $maxChars + " chars, artifact=" + $artifactMaxChars + " chars") -ForegroundColor DarkGray
Write-Host "Running $Gate gate: $reviewerRole -> $Id" -ForegroundColor Cyan
$execution = & $routerPath -Provider $Provider -ProjectPath $root -Prompt $prompt -Context $evidence.ToString() -SchemaPath $schemaPath -OutputPath $outputPath -Model $Model -Role $reviewerRole -Workload "gate"

if (-not (Test-Path $outputPath)) {
    throw "Gate provider did not produce structured output: $outputPath"
}

$result = Get-Content $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json

switch ($Gate) {
    "Review" {
        foreach ($field in @("recommendation","findings","verification")) {
            if ($null -eq $result.PSObject.Properties[$field]) { throw "Review result missing field: $field" }
        }

        & (Join-Path $PSScriptRoot "review-task.ps1") -ProjectPath $root -Id $Id -Recommendation $result.recommendation -Reviewer ("ai-" + $reviewerRole) -Findings $result.findings -Verification $result.verification
    }

    "QA" {
        foreach ($field in @("outcome","evidence","findings")) {
            if ($null -eq $result.PSObject.Properties[$field]) { throw "QA result missing field: $field" }
        }

        & (Join-Path $PSScriptRoot "qa-task.ps1") -ProjectPath $root -Id $Id -Outcome $result.outcome -Evidence $result.evidence -Findings $result.findings
    }

    "Security" {
        foreach ($field in @("outcome","evidence","findings")) {
            if ($null -eq $result.PSObject.Properties[$field]) { throw "Security result missing field: $field" }
        }

        & (Join-Path $PSScriptRoot "security-task.ps1") -ProjectPath $root -Id $Id -Outcome $result.outcome -Evidence $result.evidence -Findings $result.findings
    }
}

Write-Host ""
Write-Host "$Gate gate completed for $Id" -ForegroundColor Green
Write-Host ("Provider: " + $execution.Provider)
Write-Host ("Model: " + $execution.Model)
