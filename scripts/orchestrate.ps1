param(
    [string]$Objective = "",
    [ValidateSet("FEATURE","BUG","REFACTOR","INFRASTRUCTURE","AUDIT","RELEASE","RESEARCH","DOCUMENTATION")]
    [string]$Type = "FEATURE",
    [ValidateSet("P0","P1","P2","P3")]
    [string]$Priority = "P1",
    [string]$WorkRequestId = "",
    [string]$RequestedBy = "user",
    [string]$ProjectPath = ".",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

$root = (Resolve-Path $ProjectPath).Path
$scripts = Join-Path $root "scripts"

function Require-Script {
    param([string]$Name)
    $path = Join-Path $scripts $Name
    if (-not (Test-Path $path)) { throw "Required script not found: $path" }
    return $path
}

$newWorkRequest = Require-Script "new-work-request.ps1"
$generatePlan = Require-Script "generate-plan.ps1"
$materializePlan = Require-Script "materialize-plan-tasks.ps1"
$evaluateReadiness = Require-Script "evaluate-readiness.ps1"
$dispatch = Require-Script "dispatch-ready-tasks.ps1"
$syncState = Require-Script "sync-company-state.ps1"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "        AI COMPANY OS ORCHESTRATOR        " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrWhiteSpace($WorkRequestId)) {
    if ([string]::IsNullOrWhiteSpace($Objective)) {
        throw "Provide -Objective when creating a new work request, or provide -WorkRequestId to continue an existing one."
    }

    & $newWorkRequest -ProjectPath $root -Objective $Objective -Type $Type -Priority $Priority -RequestedBy $RequestedBy

    $requestDir = Join-Path $root "docs\engineering\work-requests"
    $latest = Get-ChildItem $requestDir -Filter "WR-*.md" -File |
        Sort-Object Name |
        Select-Object -Last 1

    if ($null -eq $latest) { throw "Work request creation succeeded but no WR file was found." }

    $requestContent = Get-Content $latest.FullName -Raw
    $WorkRequestId = Read-Field $requestContent "ID"
}

$requestPath = Join-Path $root ("docs\engineering\work-requests\" + $WorkRequestId + ".md")
if (-not (Test-Path $requestPath)) { throw "Work request not found: $requestPath" }

$planPath = Join-Path $root ("docs\engineering\plans\" + $WorkRequestId + "-plan.md")
$mappingPath = Join-Path $root ("docs\engineering\plans\" + $WorkRequestId + "-tasks.md")

Write-Host "Work request: $WorkRequestId" -ForegroundColor Yellow

if (-not (Test-Path $planPath)) {
    Write-Host "Phase: generate plan" -ForegroundColor Cyan
    & $generatePlan -ProjectPath $root -WorkRequestId $WorkRequestId
}
else {
    Write-Host "Phase: generate plan - already exists" -ForegroundColor DarkGray
}

if (-not (Test-Path $mappingPath)) {
    Write-Host "Phase: materialize tasks" -ForegroundColor Cyan
    & $materializePlan -ProjectPath $root -WorkRequestId $WorkRequestId
}
else {
    Write-Host "Phase: materialize tasks - already exists" -ForegroundColor DarkGray
}

Write-Host "Phase: evaluate readiness" -ForegroundColor Cyan
if ($Apply) {
    & $evaluateReadiness -ProjectPath $root -Apply
}
else {
    & $evaluateReadiness -ProjectPath $root
}

Write-Host "Phase: dispatch" -ForegroundColor Cyan
if ($Apply) {
    & $dispatch -ProjectPath $root -Apply
}
else {
    & $dispatch -ProjectPath $root
}

Write-Host "Phase: sync company state" -ForegroundColor Cyan
& $syncState -TasksPath (Join-Path $root "tasks") -SprintPath (Join-Path $root ".codex\state\current-sprint.md")

Write-Host ""
Write-Host "Orchestration complete." -ForegroundColor Green
Write-Host "Work request: $WorkRequestId"
if ($Apply) {
    Write-Host "Mode: APPLY - eligible tasks may be ACTIVE." -ForegroundColor Yellow
}
else {
    Write-Host "Mode: PREPARE - no READY task was activated by the orchestrator." -ForegroundColor Yellow
}
