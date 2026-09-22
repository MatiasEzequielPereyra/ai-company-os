param(
    [string]$TasksPath = "tasks",
    [string]$SprintPath = ".codex/state/current-sprint.md"
)

$ErrorActionPreference = "Stop"

function Get-TaskData {
    param([System.IO.FileInfo]$File)
    $content = Get-Content -Path $File.FullName -Raw
    [PSCustomObject]@{
        ID = if ($content -match '(?m)^ID:\s*(.+)$') { $Matches[1].Trim() } else { $File.BaseName }
        Title = if ($content -match '(?m)^#\s+(.+)$') { $Matches[1].Trim() } else { $File.BaseName }
        Status = if ($content -match '(?m)^Status:\s*(.+)$') { $Matches[1].Trim() } else { "UNKNOWN" }
        Priority = if ($content -match '(?m)^Priority:\s*(.+)$') { $Matches[1].Trim() } else { "" }
        Owner = if ($content -match '(?m)^Owner:\s*(.+)$') { $Matches[1].Trim() } else { "" }
        Updated = if ($content -match '(?m)^Updated:\s*(.+)$') { $Matches[1].Trim() } else { "" }
    }
}

if (-not (Test-Path $TasksPath)) { throw "Tasks directory not found: $TasksPath" }

$tasks = @(Get-ChildItem -Path $TasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue | ForEach-Object { Get-TaskData $_ })
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$sprintGoal = "No current objective recorded."
$currentObjectivePath = ".codex/state/current-objective.md"
if (Test-Path $currentObjectivePath) {
    $objectiveContent = Get-Content $currentObjectivePath -Raw
    if ($objectiveContent -match '(?m)^Objective:\s*(.+)

function Format-TaskLines {
    param($Items)
    $itemsArray = @($Items)
    if ($itemsArray.Count -eq 0) { return "-" }
    return (($itemsArray | Sort-Object Priority, ID | ForEach-Object {
        "- $($_.ID) [$($_.Status)/$($_.Priority)] $($_.Title) - Owner: $($_.Owner)"
    }) -join [Environment]::NewLine)
}

$active = @($tasks | Where-Object { $_.Status -eq "ACTIVE" })
$blocked = @($tasks | Where-Object { $_.Status -eq "BLOCKED" })
$done = @($tasks | Where-Object { $_.Status -eq "DONE" })
$backlog = @($tasks | Where-Object { $_.Status -in @("BACKLOG", "READY") })

$lines = @(
"# Current Sprint",
"",
"Generated: $now",
"",
"## Sprint Goal",
"",
"$sprintGoal",
"",
"## Priorities",
"",
"### P0",
"",
(Format-TaskLines ($tasks | Where-Object { $_.Priority -eq "P0" -and $_.Status -ne "DONE" })),
"",
"### P1",
"",
(Format-TaskLines ($tasks | Where-Object { $_.Priority -eq "P1" -and $_.Status -ne "DONE" })),
"",
"### P2",
"",
(Format-TaskLines ($tasks | Where-Object { $_.Priority -eq "P2" -and $_.Status -ne "DONE" })),
"",
"### P3",
"",
(Format-TaskLines ($tasks | Where-Object { $_.Priority -eq "P3" -and $_.Status -ne "DONE" })),
"",
"## Active Work",
"",
(Format-TaskLines $active),
"",
"## Completed Work",
"",
(Format-TaskLines $done),
"",
"## Blocked Work",
"",
(Format-TaskLines $blocked),
"",
"## Backlog / Ready",
"",
(Format-TaskLines $backlog),
"",
"## Decisions",
"",
"- Use flat tasks/*.md files. The Status field is the source of truth.",
"- Keep transition history inside each task.",
"",
"## Risks",
"",
"- Scripts are filesystem-based and should be run from the repository root.",
"- Manual edits can break metadata if required fields are removed."
)

$content = $lines -join [Environment]::NewLine
$dir = Split-Path -Parent $SprintPath
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
[System.IO.File]::WriteAllText($SprintPath, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Company sprint state synced:" -ForegroundColor Green
Write-Host $SprintPath
) {
        $sprintGoal = $Matches[1].Trim()
    }
}

function Format-TaskLines {
    param($Items)
    $itemsArray = @($Items)
    if ($itemsArray.Count -eq 0) { return "-" }
    return (($itemsArray | Sort-Object Priority, ID | ForEach-Object {
        "- $($_.ID) [$($_.Status)/$($_.Priority)] $($_.Title) - Owner: $($_.Owner)"
    }) -join [Environment]::NewLine)
}

$active = @($tasks | Where-Object { $_.Status -eq "ACTIVE" })
$blocked = @($tasks | Where-Object { $_.Status -eq "BLOCKED" })
$done = @($tasks | Where-Object { $_.Status -eq "DONE" })
$backlog = @($tasks | Where-Object { $_.Status -in @("BACKLOG", "READY") })

$lines = @(
"# Current Sprint",
"",
"Generated: $now",
"",
"## Sprint Goal",
"",
"Complete the AI Company OS task management core and make project work persistent.",
"",
"## Priorities",
"",
"### P0",
"",
(Format-TaskLines ($tasks | Where-Object { $_.Priority -eq "P0" -and $_.Status -ne "DONE" })),
"",
"### P1",
"",
(Format-TaskLines ($tasks | Where-Object { $_.Priority -eq "P1" -and $_.Status -ne "DONE" })),
"",
"### P2",
"",
(Format-TaskLines ($tasks | Where-Object { $_.Priority -eq "P2" -and $_.Status -ne "DONE" })),
"",
"### P3",
"",
(Format-TaskLines ($tasks | Where-Object { $_.Priority -eq "P3" -and $_.Status -ne "DONE" })),
"",
"## Active Work",
"",
(Format-TaskLines $active),
"",
"## Completed Work",
"",
(Format-TaskLines $done),
"",
"## Blocked Work",
"",
(Format-TaskLines $blocked),
"",
"## Backlog / Ready",
"",
(Format-TaskLines $backlog),
"",
"## Decisions",
"",
"- Use flat tasks/*.md files. The Status field is the source of truth.",
"- Keep transition history inside each task.",
"",
"## Risks",
"",
"- Scripts are filesystem-based and should be run from the repository root.",
"- Manual edits can break metadata if required fields are removed."
)

$content = $lines -join [Environment]::NewLine
$dir = Split-Path -Parent $SprintPath
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
[System.IO.File]::WriteAllText($SprintPath, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Company sprint state synced:" -ForegroundColor Green
Write-Host $SprintPath
