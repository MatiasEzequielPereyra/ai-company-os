param()

$ErrorActionPreference="Stop"

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$newWorkRequest=Join-Path $repoRoot "scripts\new-work-request.ps1"
$generatePlan=Join-Path $repoRoot "scripts\generate-plan.ps1"
$materializePlan=Join-Path $repoRoot "scripts\materialize-plan-tasks.ps1"
$readiness=Join-Path $repoRoot "scripts\evaluate-readiness.ps1"
$dispatch=Join-Path $repoRoot "scripts\dispatch-ready-tasks.ps1"
$submit=Join-Path $repoRoot "scripts\submit-task-result.ps1"
$advance=Join-Path $repoRoot "scripts\advance-task.ps1"
$update=Join-Path $repoRoot "scripts\update-task.ps1"

$tempRoot=Join-Path ([System.IO.Path]::GetTempPath()) ("aico-result-"+[guid]::NewGuid().ToString("N"))

try{
    New-Item -ItemType Directory -Force -Path $tempRoot|Out-Null
    foreach($dir in @(".codex\state","docs\engineering","tasks","scripts")){
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $dir)|Out-Null
    }

    Copy-Item $advance (Join-Path $tempRoot "scripts\advance-task.ps1") -Force
    Copy-Item $update (Join-Path $tempRoot "scripts\update-task.ps1") -Force

    & $newWorkRequest -ProjectPath $tempRoot -Objective "Prepare project for production" -Type AUDIT -Priority P1
    & $generatePlan -ProjectPath $tempRoot -WorkRequestId WR-001
    & $materializePlan -ProjectPath $tempRoot -WorkRequestId WR-001
    & $readiness -ProjectPath $tempRoot -Apply
    & $dispatch -ProjectPath $tempRoot -Apply

    & $submit -ProjectPath $tempRoot -Id AICO-001 -Outcome COMPLETED -Summary "Product audit completed." -ChangedArtifacts "docs/product/product-audit.md" -Verification "Reviewed product scope and gaps." -Decisions "No new product decisions." -Blockers "NONE"

    $task=Get-Content (Join-Path $tempRoot "tasks\AICO-001.md") -Raw
    if($task -notmatch '(?m)^Status:\s*REVIEW$'){throw "Completed result did not move task to REVIEW"}

    $result=Join-Path $tempRoot "docs\engineering\results\AICO-001-result-001.md"
    if(-not(Test-Path $result)){throw "Result artifact missing"}

    & $submit -ProjectPath $tempRoot -Id AICO-002 -Outcome BLOCKED -Summary "Architecture audit blocked." -Blockers "Missing architecture source evidence."

    $blockedTask=Get-Content (Join-Path $tempRoot "tasks\AICO-002.md") -Raw
    if($blockedTask -notmatch '(?m)^Status:\s*BLOCKED$'){throw "Blocked result did not move task to BLOCKED"}

    Write-Host "PASS: result intake smoke test" -ForegroundColor Green
}
finally{
    if(Test-Path $tempRoot){Remove-Item $tempRoot -Recurse -Force}
}
