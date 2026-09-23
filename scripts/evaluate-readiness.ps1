param(
    [string]$ProjectPath = ".",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Read-Section {
    param([string]$Content,[string]$Section)
    $pattern = "(?ms)^## " + [regex]::Escape($Section) + "\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Get-Dependencies {
    param([string]$Content)
    $section = Read-Section $Content "Dependencies"
    if ([string]::IsNullOrWhiteSpace($section)) { return @() }

    return @(
        $section -split '\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^-\s+AICO-\d+$' } |
            ForEach-Object { $_ -replace '^-\s+', '' }
    )
}

$root = (Resolve-Path $ProjectPath).Path
$tasksPath = Join-Path $root "tasks"
if (-not (Test-Path $tasksPath)) { throw "Tasks directory not found: $tasksPath" }

$taskFiles = @(Get-ChildItem $tasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue)
$statusById = @{}

foreach ($file in $taskFiles) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $id = Read-Field $content "ID"
    if ([string]::IsNullOrWhiteSpace($id)) { $id = $file.BaseName }
    $statusById[$id] = Read-Field $content "Status"
}

$results = @()

foreach ($file in $taskFiles) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $id = Read-Field $content "ID"
    if ([string]::IsNullOrWhiteSpace($id)) { $id = $file.BaseName }

    $status = Read-Field $content "Status"
    if ($status -ne "BACKLOG") { continue }

    $owner = Read-Field $content "Owner"
    $objective = Read-Section $content "Objective"
    $context = Read-Section $content "Context"
    $acceptance = Read-Section $content "Acceptance Criteria"
    $dependencies = @(Get-Dependencies $content)

    $reasons = @()

    if ([string]::IsNullOrWhiteSpace($owner)) { $reasons += "Missing owner" }
    if ([string]::IsNullOrWhiteSpace($objective) -or $objective -eq "-") { $reasons += "Missing objective" }
    if ([string]::IsNullOrWhiteSpace($context) -or $context -eq "-") { $reasons += "Missing context" }
    if ([string]::IsNullOrWhiteSpace($acceptance) -or $acceptance -eq "-") { $reasons += "Missing acceptance criteria" }

    foreach ($dependency in $dependencies) {
        if (-not $statusById.ContainsKey($dependency)) {
            $reasons += "Dependency not found: $dependency"
        }
        elseif ($statusById[$dependency] -ne "DONE") {
            $reasons += "Dependency not done: $dependency ($($statusById[$dependency]))"
        }
    }

    $isReady = ($reasons.Count -eq 0)

    $results += [PSCustomObject]@{
        ID = $id
        Owner = $owner
        CurrentStatus = $status
        Ready = $isReady
        Dependencies = if ($dependencies.Count -gt 0) { $dependencies -join "," } else { "-" }
        Reason = if ($isReady) { "Prepared and dependencies satisfied" } else { $reasons -join "; " }
    }
}

if ($results.Count -eq 0) {
    Write-Host "No BACKLOG tasks found." -ForegroundColor Yellow
    exit 0
}

$results | Sort-Object ID | Format-Table ID, Owner, CurrentStatus, Ready, Dependencies, Reason -AutoSize

if ($Apply) {
    $advanceScript = Join-Path $PSScriptRoot "advance-task.ps1"
    if (-not (Test-Path $advanceScript)) { throw "advance-task.ps1 not found: $advanceScript" }

    $readyTasks = @($results | Where-Object { $_.Ready })

    foreach ($task in $readyTasks) {
        & $advanceScript -Id $task.ID -Status READY -Actor "engineering-manager" -Reason "Readiness engine verified required context and dependencies." -Evidence "Automated readiness evaluation passed." -TasksPath $tasksPath
    }

    Write-Host ""
    Write-Host "Readiness applied: $($readyTasks.Count) task(s) moved to READY." -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply to move eligible BACKLOG tasks to READY." -ForegroundColor Cyan
}
