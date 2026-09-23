param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-profiles-" + [Guid]::NewGuid().ToString("N"))

try {
    foreach ($relative in @(
        "scripts",
        "tasks",
        "docs\engineering\results",
        "docs\engineering\reviews",
        "docs\engineering\qa",
        "docs\engineering\security",
        ".codex\runtime"
    )) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $relative) | Out-Null
    }

    foreach ($name in @("new-task.ps1","update-task.ps1","advance-task.ps1","security-task.ps1","write-operational-event.ps1")) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $tempRoot ("scripts\" + $name)) -Force
    }

    $tasksPath = Join-Path $tempRoot "tasks"
    $newTask = Join-Path $tempRoot "scripts\new-task.ps1"
    $advance = Join-Path $tempRoot "scripts\advance-task.ps1"
    $security = Join-Path $tempRoot "scripts\security-task.ps1"

    & $newTask -Title "High assurance change" -Owner backend -Priority P0 -WorkflowProfile "standard" -Objective "Exercise profile enforcement." -TasksPath $tasksPath
    & (Join-Path $tempRoot "scripts\update-task.ps1") -Id AICO-001 -WorkflowProfile "high-assurance" -TasksPath $tasksPath

    $taskPath = Join-Path $tasksPath "AICO-001.md"
    $task = Get-Content $taskPath -Raw -Encoding UTF8
    if ($task -notmatch '(?m)^Workflow profile:\s*high-assurance\r?$') { throw "Task did not persist high-assurance profile." }

    & $advance -Id AICO-001 -Status READY -Actor "test" -Reason "Profile test transition." -TasksPath $tasksPath
    & $advance -Id AICO-001 -Status ACTIVE -Actor "test" -Reason "Profile test transition." -TasksPath $tasksPath

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "docs\engineering\results\AICO-001-result-001.md"),
        @"
# Result
Outcome: COMPLETED
"@,
        (New-Object System.Text.UTF8Encoding($false))
    )

    & $advance -Id AICO-001 -Status REVIEW -Actor "test" -Reason "Profile test transition." -TasksPath $tasksPath

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "docs\engineering\reviews\AICO-001-review-001.md"),
        @"
# Review
Recommendation: APPROVE
"@,
        (New-Object System.Text.UTF8Encoding($false))
    )

    & $advance -Id AICO-001 -Status QA -Actor "test" -Reason "Profile test transition." -TasksPath $tasksPath

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "docs\engineering\qa\AICO-001-qa.md"),
        @"
# QA
Outcome: PASS
"@,
        (New-Object System.Text.UTF8Encoding($false))
    )

    & $advance -Id AICO-001 -Status SECURITY -Actor "test" -Reason "Profile test transition." -TasksPath $tasksPath

    $profileMutationRejected = $false
    try {
        & (Join-Path $tempRoot "scripts\update-task.ps1") -Id AICO-001 -WorkflowProfile "lightweight" -TasksPath $tasksPath
    }
    catch {
        if ($_.Exception.Message -match "BACKLOG or READY") { $profileMutationRejected = $true } else { throw }
    }
    if (-not $profileMutationRejected) { throw "Active/high-assurance task profile was allowed to weaken mid-flight." }

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
    if ($artifact -notmatch '(?m)^Outcome:\s*PASS\r?$') { throw "Security PASS artifact was not recorded." }

    Write-Host "PASS: workflow profile enforcement test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
