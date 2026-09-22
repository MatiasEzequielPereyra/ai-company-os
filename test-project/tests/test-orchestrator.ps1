param()

$ErrorActionPreference="Stop"

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$orchestrate=Join-Path $repoRoot "scripts\orchestrate.ps1"
$sourceScripts=Join-Path $repoRoot "scripts"
$tempRoot=Join-Path ([System.IO.Path]::GetTempPath()) ("aico-orchestrator-"+[guid]::NewGuid().ToString("N"))

try{
    New-Item -ItemType Directory -Force -Path $tempRoot|Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts")|Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".codex\state")|Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\engineering")|Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "tasks")|Out-Null

    foreach($name in @(
        "new-work-request.ps1",
        "generate-plan.ps1",
        "materialize-plan-tasks.ps1",
        "evaluate-readiness.ps1",
        "dispatch-ready-tasks.ps1",
        "sync-company-state.ps1",
        "advance-task.ps1"
    )){
        Copy-Item (Join-Path $sourceScripts $name) (Join-Path $tempRoot ("scripts\"+$name)) -Force
    }

    & $orchestrate -ProjectPath $tempRoot -Objective "Prepare project for production" -Type AUDIT -Priority P1

    $requests=@(Get-ChildItem (Join-Path $tempRoot "docs\engineering\work-requests") -Filter "WR-*.md" -File)
    if($requests.Count -ne 1){throw "Expected one work request after prepare mode"}

    $tasks=@(Get-ChildItem (Join-Path $tempRoot "tasks") -Filter "AICO-*.md" -File)
    if($tasks.Count -ne 6){throw "Expected six tasks after prepare mode"}

    $active=@()
    foreach($task in $tasks){
        $content=Get-Content $task.FullName -Raw
        if($content -match '(?m)^Status:\s*ACTIVE$'){$active+=$task.Name}
    }
    if($active.Count -ne 0){throw "Prepare mode activated tasks unexpectedly"}

    & $orchestrate -ProjectPath $tempRoot -WorkRequestId WR-001 -Apply

    $activeOwners=@()
    foreach($task in @(Get-ChildItem (Join-Path $tempRoot "tasks") -Filter "AICO-*.md" -File)){
        $content=Get-Content $task.FullName -Raw
        $owner=if($content -match '(?m)^Owner:\s*(.+)$'){$Matches[1].Trim()}else{"UNKNOWN"}
        $status=if($content -match '(?m)^Status:\s*(.+)$'){$Matches[1].Trim()}else{"UNKNOWN"}
        if($status -eq "ACTIVE"){$activeOwners+=$owner}
    }

    foreach($owner in @("pm","cto","qa","security","devops")){
        if($activeOwners -notcontains $owner){throw "Apply mode did not activate expected owner: $owner"}
    }

    if(-not(Test-Path (Join-Path $tempRoot ".codex\state\current-sprint.md"))){
        throw "Current sprint state was not generated"
    }

    Write-Host "PASS: master orchestrator smoke test" -ForegroundColor Green
}
finally{
    if(Test-Path $tempRoot){Remove-Item $tempRoot -Recurse -Force}
}
