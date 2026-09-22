param()

$ErrorActionPreference="Stop"

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$newWorkRequest=Join-Path $repoRoot "scripts\new-work-request.ps1"
$generatePlan=Join-Path $repoRoot "scripts\generate-plan.ps1"
$materializePlan=Join-Path $repoRoot "scripts\materialize-plan-tasks.ps1"
$readiness=Join-Path $repoRoot "scripts\evaluate-readiness.ps1"
$dispatch=Join-Path $repoRoot "scripts\dispatch-ready-tasks.ps1"
$advance=Join-Path $repoRoot "scripts\advance-task.ps1"

$tempRoot=Join-Path ([System.IO.Path]::GetTempPath()) ("aico-dispatch-"+[guid]::NewGuid().ToString("N"))

try{
    New-Item -ItemType Directory -Force -Path $tempRoot|Out-Null
    foreach($dir in @(".codex\state","docs\engineering","tasks","scripts")){
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $dir)|Out-Null
    }

    Copy-Item $advance (Join-Path $tempRoot "scripts\advance-task.ps1") -Force

    & $newWorkRequest -ProjectPath $tempRoot -Objective "Prepare project for production" -Type AUDIT -Priority P1
    & $generatePlan -ProjectPath $tempRoot -WorkRequestId WR-001
    & $materializePlan -ProjectPath $tempRoot -WorkRequestId WR-001
    & $readiness -ProjectPath $tempRoot -Apply
    & $dispatch -ProjectPath $tempRoot

    $packets=@(Get-ChildItem (Join-Path $tempRoot "docs\engineering\dispatch") -Filter "AICO-*.md" -File)
    if($packets.Count -ne 5){throw "Expected 5 prepared execution packets, found $($packets.Count)"}

    $activeBefore=@()
    Get-ChildItem (Join-Path $tempRoot "tasks") -Filter "AICO-*.md" -File|ForEach-Object{
        $c=Get-Content $_.FullName -Raw
        if($c -match '(?m)^Status:\s*ACTIVE$'){$activeBefore+=$_.Name}
    }
    if($activeBefore.Count -ne 0){throw "Dry-run dispatch must not activate tasks"}

    & $dispatch -ProjectPath $tempRoot -Apply

    $activeOwners=@()
    $backlogOwners=@()

    Get-ChildItem (Join-Path $tempRoot "tasks") -Filter "AICO-*.md" -File|ForEach-Object{
        $c=Get-Content $_.FullName -Raw
        $owner=if($c -match '(?m)^Owner:\s*(.+)$'){$Matches[1].Trim()}else{"UNKNOWN"}
        $status=if($c -match '(?m)^Status:\s*(.+)$'){$Matches[1].Trim()}else{"UNKNOWN"}
        if($status -eq "ACTIVE"){$activeOwners+=$owner}
        if($status -eq "BACKLOG"){$backlogOwners+=$owner}
    }

    foreach($owner in @("pm","cto","qa","security","devops")){
        if($activeOwners -notcontains $owner){throw "Expected ACTIVE owner missing: $owner"}
    }

    if($backlogOwners -notcontains "engineering-manager"){
        throw "Engineering Manager should remain BACKLOG while audit dependencies are incomplete"
    }

    Write-Host "PASS: dispatch engine smoke test" -ForegroundColor Green
}
finally{
    if(Test-Path $tempRoot){Remove-Item $tempRoot -Recurse -Force}
}
