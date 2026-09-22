param()

$ErrorActionPreference="Stop"

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$newWorkRequest=Join-Path $repoRoot "scripts\new-work-request.ps1"
$generatePlan=Join-Path $repoRoot "scripts\generate-plan.ps1"
$materializePlan=Join-Path $repoRoot "scripts\materialize-plan-tasks.ps1"
$readiness=Join-Path $repoRoot "scripts\evaluate-readiness.ps1"
$dispatch=Join-Path $repoRoot "scripts\dispatch-ready-tasks.ps1"
$submit=Join-Path $repoRoot "scripts\submit-task-result.ps1"
$review=Join-Path $repoRoot "scripts\review-task.ps1"
$advance=Join-Path $repoRoot "scripts\advance-task.ps1"
$update=Join-Path $repoRoot "scripts\update-task.ps1"

$tempRoot=Join-Path ([System.IO.Path]::GetTempPath()) ("aico-review-"+[guid]::NewGuid().ToString("N"))

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

    & $submit -ProjectPath $tempRoot -Id AICO-001 -Outcome COMPLETED -Summary "Product audit completed."
    & $review -ProjectPath $tempRoot -Id AICO-001 -Recommendation APPROVE -Reviewer "reviewer" -Findings "No blocking findings." -Verification "Reviewed result artifact."

    $approved=Get-Content (Join-Path $tempRoot "tasks\AICO-001.md") -Raw
    if($approved -notmatch '(?m)^Status:\s*QA$'){throw "Approved review did not move task to QA"}

    & $submit -ProjectPath $tempRoot -Id AICO-002 -Outcome COMPLETED -Summary "Architecture audit completed."
    & $review -ProjectPath $tempRoot -Id AICO-002 -Recommendation CHANGES_REQUIRED -Reviewer "reviewer" -Findings "Architecture evidence incomplete."

    $changes=Get-Content (Join-Path $tempRoot "tasks\AICO-002.md") -Raw
    if($changes -notmatch '(?m)^Status:\s*READY$'){throw "Changes-required review did not return task to READY"}

    $reviews=@(Get-ChildItem (Join-Path $tempRoot "docs\engineering\reviews") -Filter "AICO-*-review-*.md" -File)
    if($reviews.Count -ne 2){throw "Expected 2 review artifacts, found $($reviews.Count)"}

    Write-Host "PASS: review engine smoke test" -ForegroundColor Green
}
finally{
    if(Test-Path $tempRoot){Remove-Item $tempRoot -Recurse -Force}
}
