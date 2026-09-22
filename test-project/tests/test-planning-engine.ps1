param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$newWorkRequest = Join-Path $repoRoot "scripts\new-work-request.ps1"
$generatePlan = Join-Path $repoRoot "scripts\generate-plan.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("aico-plan-" + [guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".codex\state") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\engineering") | Out-Null

    & $newWorkRequest -ProjectPath $tempRoot -Objective "Prepare project for production" -Type AUDIT -Priority P1
    & $generatePlan -ProjectPath $tempRoot -WorkRequestId WR-001

    $request = Join-Path $tempRoot "docs\engineering\work-requests\WR-001.md"
    $objective = Join-Path $tempRoot ".codex\state\current-objective.md"
    $plan = Join-Path $tempRoot "docs\engineering\plans\WR-001-plan.md"

    foreach ($path in @($request, $objective, $plan)) {
        if (-not (Test-Path $path)) { throw "Expected file missing: $path" }
    }

    $planContent = Get-Content $plan -Raw
    foreach ($expected in @("pm","cto","engineering-manager","qa","security","devops","Status: PROPOSED")) {
        if ($planContent -notmatch [regex]::Escape($expected)) {
            throw "Expected planning value missing: $expected"
        }
    }

    Write-Host "PASS: planning engine smoke test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
