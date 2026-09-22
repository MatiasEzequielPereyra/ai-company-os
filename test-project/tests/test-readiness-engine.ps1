param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$newWorkRequest = Join-Path $repoRoot "scripts\new-work-request.ps1"
$generatePlan = Join-Path $repoRoot "scripts\generate-plan.ps1"
$materializePlan = Join-Path $repoRoot "scripts\materialize-plan-tasks.ps1"
$readiness = Join-Path $repoRoot "scripts\evaluate-readiness.ps1"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("aico-ready-" + [guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".codex\state") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\engineering") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "tasks") | Out-Null

    & $newWorkRequest -ProjectPath $tempRoot -Objective "Prepare project for production" -Type AUDIT -Priority P1
    & $generatePlan -ProjectPath $tempRoot -WorkRequestId WR-001
    & $materializePlan -ProjectPath $tempRoot -WorkRequestId WR-001
    & $readiness -ProjectPath $tempRoot -Apply

    $tasks = @(Get-ChildItem (Join-Path $tempRoot "tasks") -Filter "AICO-*.md" -File)
    $readyOwners = @()
    $backlogOwners = @()

    foreach ($task in $tasks) {
        $content = Get-Content $task.FullName -Raw
        $owner = if ($content -match '(?m)^Owner:\s*(.+)$') { $Matches[1].Trim() } else { "UNKNOWN" }
        $status = if ($content -match '(?m)^Status:\s*(.+)$') { $Matches[1].Trim() } else { "UNKNOWN" }

        if ($status -eq "READY") { $readyOwners += $owner }
        if ($status -eq "BACKLOG") { $backlogOwners += $owner }
    }

    foreach ($owner in @("pm","cto","qa","security","devops")) {
        if ($readyOwners -notcontains $owner) {
            throw "Expected READY owner missing: $owner"
        }
    }

    if ($backlogOwners -notcontains "engineering-manager") {
        throw "Engineering Manager should remain BACKLOG until audit dependencies are DONE"
    }

    Write-Host "PASS: readiness engine smoke test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
