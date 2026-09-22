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
$refresh=Join-Path $repoRoot "scripts\refresh-dependencies.ps1"
$evaluate=Join-Path $repoRoot "scripts\evaluate-readiness.ps1"

$tempRoot=Join-Path ([System.IO.Path]::GetTempPath()) ("aico-deps-"+[guid]::NewGuid().ToString("N"))

try{
    New-Item -ItemType Directory -Force -Path $tempRoot|Out-Null
    foreach($dir in @(".codex\state","docs\engineering","tasks","scripts")){
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $dir)|Out-Null
    }

    foreach($script in @($advance,$update,$refresh,$evaluate)){
        Copy-Item $script (Join-Path $tempRoot ("scripts\"+[System.IO.Path]::GetFileName($script))) -Force
    }

    & $newWorkRequest -ProjectPath $tempRoot -Objective "Prepare project for production" -Type AUDIT -Priority P1
    & $generatePlan -ProjectPath $tempRoot -WorkRequestId WR-001
    & $materializePlan -ProjectPath $tempRoot -WorkRequestId WR-001
    & $readiness -ProjectPath $tempRoot -Apply
    & $dispatch -ProjectPath $tempRoot -Apply

    foreach($id in @("AICO-001","AICO-002","AICO-003","AICO-004","AICO-005")){
        & $submit -ProjectPath $tempRoot -Id $id -Outcome COMPLETED -Summary "Audit completed."
        & $review -ProjectPath $tempRoot -Id $id -Recommendation APPROVE -Reviewer "reviewer" -Findings "No blocking findings."
        & $qa -ProjectPath $tempRoot -Id $id -Outcome PASS -Evidence "Acceptance criteria verified."
        & $security -ProjectPath $tempRoot -Id $id -Outcome NOT_APPLICABLE -Evidence "No changed security boundary."
        & $finalize -ProjectPath $tempRoot -Id $id -Decision APPROVE -Verification "Objective and applicable gates verified."
    }

    $em=Get-Content (Join-Path $tempRoot "tasks\AICO-006.md") -Raw
    if($em -notmatch '(?m)^Status:\s*READY$'){
        throw "Dependent Engineering Manager task did not become READY automatically"
    }

    Write-Host "PASS: dependency refresh smoke test" -ForegroundColor Green
}
finally{
    if(Test-Path $tempRoot){Remove-Item $tempRoot -Recurse -Force}
}
