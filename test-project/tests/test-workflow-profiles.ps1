param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-profiles-" + [Guid]::NewGuid().ToString("N"))

try {
    foreach ($relative in @("scripts","tasks","docs\engineering\security",".codex\runtime")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $relative) | Out-Null
    }

    foreach ($name in @("new-task.ps1","update-task.ps1","advance-task.ps1","security-task.ps1","write-operational-event.ps1")) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $tempRoot ("scripts\" + $name)) -Force
    }

    $tasksPath = Join-Path $tempRoot "tasks"
    $newTask = Join-Path $tempRoot "scripts\new-task.ps1"
    $advance = Join-Path $tempRoot "scripts\advance-task.ps1"
    $security = Join-Path $tempRoot "scripts\security-task.ps1"

    & $newTask -Title "High assurance change" -Owner backend -Priority P0 -WorkflowProfile "high-assurance" -Objective "Exercise profile enforcement." -TasksPath $tasksPath

    $taskPath = Join-Path $tasksPath "AICO-001.md"
    $task = Get-Content $taskPath -Raw -Encoding UTF8
    if ($task -notmatch '(?m)^Workflow profile:\s*high-assurance$') { throw "Task did not persist high-assurance profile." }

    foreach ($status in @("READY","ACTIVE","REVIEW","QA","SECURITY")) {
        & $advance -Id AICO-001 -Status $status -Actor "test" -Reason "Profile test transition." -TasksPath $tasksPath
    }

    $rejected = $false
    try {
        & $security -ProjectPath $tempRoot -Id AICO-001 -Outcome NOT_APPLICABLE -Evidence "Fixture"
    }
    catch {
        if ($_.Exception.Message -match "High-assurance") { $rejected = $true } else { throw }
    }

    if (-not $rejected) { throw "High-assurance task accepted NOT_APPLICABLE security outcome." }

    & $security -ProjectPath $tempRoot -Id AICO-001 -Outcome PASS -Evidence "Security validation executed." -Findings "NONE"

    $artifact = Get-Content (Join-Path $tempRoot "docs\engineering\security\AICO-001-security.md") -Raw -Encoding UTF8
    if ($artifact -notmatch '(?m)^Outcome:\s*PASS$') { throw "Security PASS artifact was not recorded." }

    Write-Host "PASS: workflow profile enforcement test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
