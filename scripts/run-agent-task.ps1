param(
    [Parameter(Mandatory = $true)]
    [string]$Id,
    [string]$ProjectPath = ".",
    [string]$Model = ""
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

$root = (Resolve-Path $ProjectPath).Path
$tasksPath = Join-Path $root "tasks"
$taskPath = Join-Path $tasksPath ($Id + ".md")
if (-not (Test-Path $taskPath)) { throw "Task not found: $taskPath" }

$task = Get-Content $taskPath -Raw
$status = Read-Field $task "Status"
$owner = Read-Field $task "Owner"
if ($status -ne "ACTIVE") { throw "Task $Id must be ACTIVE. Current status: $status" }
if ([string]::IsNullOrWhiteSpace($owner)) { throw "Task $Id has no owner." }

$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($null -eq $codex) {
    throw "Codex CLI was not found in PATH. Install/login to Codex CLI before running agents."
}

$dispatchPath = Join-Path $root ("docs\engineering\dispatch\" + $Id + ".md")
$rolePath = Join-Path $root (".codex\agents\" + $owner + ".md")
$schemaPath = Join-Path $root "schemas\agent-result.schema.json"

if (-not (Test-Path $dispatchPath)) { throw "Dispatch packet not found: $dispatchPath" }
if (-not (Test-Path $rolePath)) { throw "Role instructions not found: $rolePath" }
if (-not (Test-Path $schemaPath)) { throw "Agent result schema not found: $schemaPath" }

$runtimeDir = Join-Path $root ".codex\runtime"
$reportsDir = Join-Path $root "docs\engineering\agent-reports"
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

$jsonPath = Join-Path $runtimeDir ($Id + "-result.json")
$reportPath = Join-Path $reportsDir ($Id + ".md")

$prompt = @("
"You are executing an AI Company OS task inside this repository.",
"",
"Role: $owner",
"Task: $Id",
"",
"Read and obey these repository files before doing the task:",
"- AGENTS.md",
"- .codex/agents/$owner.md",
"- tasks/$Id.md",
"- docs/engineering/dispatch/$Id.md",
"- .codex/state/current-sprint.md",
"- docs/engineering/project-intake.md",
"- docs/product/product-intake.md",
"- docs/architecture/architecture-intake.md",
"- docs/operations/operations-intake.md",
"",
"This execution is AUDIT/ANALYSIS ONLY.",
"Do not edit, create, delete, rename or format project files.",
"Do not run destructive commands.",
"Do not change Git state.",
"Inspect the repository deeply enough to support your role-owned conclusions.",
"Separate verified evidence from assumptions.",
"Reference concrete repository-relative files and relevant symbols where useful.",
"If required evidence is unavailable, return BLOCKED rather than inventing it.",
"",
"The report_markdown field must contain the complete role report, with findings, evidence, risks and recommended actions.",
"The summary field should be concise.",
"The changed_artifacts concept is NONE because this execution is read-only.",
"Return only the structured result required by the supplied JSON schema."
") -join [Environment]::NewLine

$args = @("exec","--sandbox","read-only","--output-schema",$schemaPath,"-o",$jsonPath)
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $args += @("--model",$Model)
}
$args += $prompt

Write-Host "Running agent: $owner -> $Id" -ForegroundColor Cyan
Push-Location $root
try {
    & codex @args
    if ($LASTEXITCODE -ne 0) { throw "Codex exec failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

if (-not (Test-Path $jsonPath)) { throw "Codex did not produce structured output: $jsonPath" }

$result = Get-Content $jsonPath -Raw | ConvertFrom-Json
if ($null -eq $result.outcome -or $null -eq $result.summary -or $null -eq $result.report_markdown) {
    throw "Structured agent result is incomplete for $Id"
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$report = @(
    "# Agent Report - $Id",
    "",
    "Generated: $now",
    "Owner: $owner",
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
Write-Host "Report: $changed"