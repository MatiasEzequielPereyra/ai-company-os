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
$qa=Join-Path $repoRoot "scripts\qa-task.ps1"
$security=Join-Path $repoRoot "scripts\security-task.ps1"
$finalize=Join-Path $repoRoot "scripts\finalize-task.ps1"
$advance=Join-Path $repoRoot "scripts\advance-task.ps1"
$update=Join-Path $repoRoot "scripts\update-task.ps1"

$tempRoot=Join-Path ([System.IO.Path]::GetTempPath()) ("aico-gates-"+[guid]::NewGuid().ToString("N"))

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

    & $submit -ProjectPath $tempRoot -Id AICO-001 -Outcome COMPLETED -Summary "Audit completed."
    & $review -ProjectPath $tempRoot -Id AICO-001 -Recommendation APPROVE -Reviewer "reviewer" -Findings "No blocking findings."
    & $qa -ProjectPath $tempRoot -Id AICO-001 -Outcome PASS -Evidence "Acceptance criteria verified."
    & $security -ProjectPath $tempRoot -Id AICO-001 -Outcome NOT_APPLICABLE -Evidence "No changed security boundary."
    & $finalize -ProjectPath $tempRoot -Id AICO-001 -Decision APPROVE -Verification "Objective and applicable gates verified."

    $done=Get-Content (Join-Path $tempRoot "tasks\AICO-001.md") -Raw
    if($done -notmatch '(?m)^Status:\s*DONE$'){throw "Final approval did not move task to DONE"}

    foreach($artifact in @(
        "docs\engineering\qa\AICO-001-qa.md",
        "docs\engineering\security\AICO-001-security.md",
        "docs\engineering\final-approvals\AICO-001-final.md"
    )){
        if(-not(Test-Path (Join-Path $tempRoot $artifact))){throw "Expected gate artifact missing: $artifact"}
    }

    Write-Host "PASS: final gates smoke test" -ForegroundColor Green
}
finally{
    if(Test-Path $tempRoot){Remove-Item $tempRoot -Recurse -Force}
}
