param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,

    [string]$Destination = "."
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       AI COMPANY OS - NEW PROJECT       " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$ProjectPath = Join-Path $Destination $ProjectName
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

if (Test-Path $ProjectPath) {
    Write-Host "ERROR: El proyecto ya existe:" -ForegroundColor Red
    Write-Host $ProjectPath
    exit 1
}

Write-Host "Creando proyecto:" -ForegroundColor Green
Write-Host $ProjectPath
Write-Host ""

New-Item -ItemType Directory -Force -Path $ProjectPath | Out-Null

# ------------------------------------------------------------
# Core directories
# ------------------------------------------------------------

$Directories = @(
    ".codex",
    ".codex\agents",
    ".codex\policies",
    ".codex\protocols",
    ".codex\state",
    ".codex\workflows",

    ".agents",
    ".agents\skills",

    "docs",
    "docs\product",
    "docs\architecture",
    "docs\engineering",
    "docs\operations",
    "docs\decisions",
    "schemas",

    "tasks",

    "scripts",
    "scripts\providers"
)

foreach ($Directory in $Directories) {
    $Path = Join-Path $ProjectPath $Directory
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

Write-Host "Directorios creados." -ForegroundColor Green

# ------------------------------------------------------------
# Resolve template roots
# ------------------------------------------------------------

$ScriptRoot = Split-Path -Parent $PSScriptRoot
$TemplateRoot = Join-Path $ScriptRoot "templates"
$ScriptsRoot = Join-Path $ScriptRoot "scripts"

if (-not (Test-Path $TemplateRoot)) {
    throw "Template root not found: $TemplateRoot"
}

Write-Host ""
Write-Host "Instalando Company OS..." -ForegroundColor Cyan

# ------------------------------------------------------------
# Copy Company OS templates
# ------------------------------------------------------------

Copy-Item `
    (Join-Path $TemplateRoot "AGENTS.md") `
    (Join-Path $ProjectPath "AGENTS.md") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "config.toml") `
    (Join-Path $ProjectPath ".codex\config.toml") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "agents\*.md") `
    (Join-Path $ProjectPath ".codex\agents\") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "agents\*.toml") `
    (Join-Path $ProjectPath ".codex\agents\") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "docs\PROJECT-BRIEF.md") `
    (Join-Path $ProjectPath "docs\PROJECT-BRIEF.md") `
    -Force

$ProjectBriefPath = Join-Path $ProjectPath "docs\PROJECT-BRIEF.md"
$ProjectBrief = Get-Content $ProjectBriefPath -Raw -Encoding UTF8
$ProjectBrief = $ProjectBrief.Replace("{{PROJECT_NAME}}",$ProjectName).Replace("{{DATE}}",$now)
[System.IO.File]::WriteAllText($ProjectBriefPath,$ProjectBrief,(New-Object System.Text.UTF8Encoding($false)))

Copy-Item `
    (Join-Path $TemplateRoot "docs\product-context.md") `
    (Join-Path $ProjectPath "docs\product\product-context.md") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "docs\architecture-context.md") `
    (Join-Path $ProjectPath "docs\architecture\architecture-context.md") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "docs\engineering-context.md") `
    (Join-Path $ProjectPath "docs\engineering\engineering-context.md") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "docs\operations-context.md") `
    (Join-Path $ProjectPath "docs\operations\operations-context.md") `
    -Force

if (Test-Path (Join-Path $TemplateRoot "tasks\README.md")) {
    Copy-Item `
        (Join-Path $TemplateRoot "tasks\README.md") `
        (Join-Path $ProjectPath "tasks\README.md") `
        -Force
}

# ------------------------------------------------------------
# Copy operational scripts
# ------------------------------------------------------------

$ScriptFiles = @(
    "initialize-project.ps1",
    "new-task.ps1",
    "list-tasks.ps1",
    "update-task.ps1",
    "advance-task.ps1",
    "sync-company-state.ps1",
    "new-work-request.ps1",
    "generate-plan.ps1",
    "materialize-plan-tasks.ps1",
    "evaluate-readiness.ps1",
    "dispatch-ready-tasks.ps1",
    "submit-task-result.ps1",
    "review-task.ps1",
    "qa-task.ps1",
    "security-task.ps1",
    "finalize-task.ps1",
    "refresh-dependencies.ps1",
    "orchestrate.ps1",
    "run-agent-task.ps1",
    "run-active-agents.ps1",
    "build-agent-context.ps1",
    "provider-router.ps1",
    "run-gate-agent.ps1",
    "run-pending-gates.ps1",
    "generate-engineering-backlog.ps1",
    "materialize-engineering-backlog.ps1",
    "validate-json-contract.ps1",
    "validate-artifacts.ps1",
    "write-operational-event.ps1",
    "summarize-metrics.ps1",
    "new-agent-workspace.ps1"
)

foreach ($ScriptFile in $ScriptFiles) {
    $Source = Join-Path $ScriptsRoot $ScriptFile
    if (Test-Path $Source) {
        Copy-Item $Source (Join-Path $ProjectPath "scripts\$ScriptFile") -Force
    }
}

$ProvidersSource = Join-Path $ScriptsRoot "providers"
$ProvidersTarget = Join-Path $ProjectPath "scripts\providers"
if (Test-Path $ProvidersSource) {
    Get-ChildItem $ProvidersSource -File | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $ProvidersTarget $_.Name) -Force
    }
}

$ProviderConfigSource = Join-Path $ScriptRoot ".codex\provider-config.json"
if (Test-Path $ProviderConfigSource) {
    Copy-Item $ProviderConfigSource (Join-Path $ProjectPath ".codex\provider-config.json") -Force
}

$WorkflowProfilesSource = Join-Path $ScriptRoot ".codex\workflow-profiles.json"
if (Test-Path $WorkflowProfilesSource) {
    Copy-Item $WorkflowProfilesSource (Join-Path $ProjectPath ".codex\workflow-profiles.json") -Force
}

# ------------------------------------------------------------
# Copy runtime schemas
# ------------------------------------------------------------

$SchemasRoot = Join-Path $ScriptRoot "schemas"

if (Test-Path $SchemasRoot) {
    Get-ChildItem $SchemasRoot -Filter "*.schema.json" -File | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $ProjectPath ("schemas\" + $_.Name)) -Force
    }
}

# ------------------------------------------------------------
# Initial state files
# ------------------------------------------------------------

$CurrentSprintPath = Join-Path $ProjectPath ".codex\state\current-sprint.md"
$CompanyStatePath = Join-Path $ProjectPath ".codex\state\company-state.md"
$BlockersPath = Join-Path $ProjectPath ".codex\state\blockers.md"

if (-not (Test-Path $CurrentSprintPath)) {
    Set-Content -Path $CurrentSprintPath -Encoding UTF8 -Value @"
# Current Sprint

## Sprint Goal

-

## Active Work

-

## Completed Work

-

## Blocked Work

-
"@
}

if (-not (Test-Path $CompanyStatePath)) {
    Set-Content -Path $CompanyStatePath -Encoding UTF8 -Value @"
# Company State

## Current Handoff

-

## Current Sprint

.codex/state/current-sprint.md

## Notes

-
"@
}

if (-not (Test-Path $BlockersPath)) {
    Set-Content -Path $BlockersPath -Encoding UTF8 -Value @"
# Blockers

-
"@
}

Write-Host "Company OS instalado." -ForegroundColor Green

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       PROJECT CREATED SUCCESSFULLY       " -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Proyecto:" -ForegroundColor Yellow
Write-Host $ProjectPath

Write-Host ""
Write-Host "Siguiente paso:" -ForegroundColor Yellow
Write-Host "cd `"$ProjectPath`""
Write-Host ".\scripts\initialize-project.ps1"
Write-Host ".\scripts\new-task.ps1 -Title `"First task`" -Owner `"engineering-manager`" -Priority P1"
Write-Host ""
