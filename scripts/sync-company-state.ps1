param(
    [string]$TasksPath = "tasks",
    [string]$SprintPath = ".codex/state/current-sprint.md"
)

$ErrorActionPreference = "Stop"

function Get-TaskData {
    param([System.IO.FileInfo]$File)

    $content = Get-Content -Path $File.FullName -Raw -Encoding UTF8
    $id = if ($content -match '(?m)^ID:\s*(.+)
        Status = if ($content -match '(?m)^Status:\s*(.+)$') { $Matches[1].Trim() } else { "UNKNOWN" }
        Priority = if ($content -match '(?m)^Priority:\s*(.+)$') { $Matches[1].Trim() } else { "" }
        Owner = if ($content -match '(?m)^Owner:\s*(.+)$') { $Matches[1].Trim() } else { "" }
        Updated = if ($content -match '(?m)^Updated:\s*(.+)$') { $Matches[1].Trim() } else { "" }
    }
}

function Format-TaskLines {
    param($Items)

    $itemsArray = @($Items)
    if ($itemsArray.Count -eq 0) {
        return "-"
    }

    return (($itemsArray | Sort-Object Priority, ID | ForEach-Object {
        "- $($_.ID) [$($_.Status)/$($_.Priority)] $($_.Title) - Owner: $($_.Owner)"
    }) -join [Environment]::NewLine)
}

$scriptProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($TasksPath)) { $TasksPath = Join-Path $scriptProjectRoot $TasksPath }
if (-not [System.IO.Path]::IsPathRooted($SprintPath)) { $SprintPath = Join-Path $scriptProjectRoot $SprintPath }

if (-not (Test-Path $TasksPath)) {
    throw "Tasks directory not found: $TasksPath"
}

$tasks = @(
    Get-ChildItem -Path $TasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue |
        ForEach-Object { Get-TaskData $_ }
)

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$sprintGoal = "No current objective recorded."
$currentObjectivePath = Join-Path $scriptProjectRoot ".codex\state\current-objective.md"

if (Test-Path $currentObjectivePath) {
    $objectiveContent = Get-Content -Path $currentObjectivePath -Raw
    if ($objectiveContent -match '(?m)^Objective:\s*(.+)$') {
        $sprintGoal = $Matches[1].Trim()
    }
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
    $sprintGoal,
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
if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

[System.IO.File]::WriteAllText(
    $SprintPath,
    $content,
    (New-Object System.Text.UTF8Encoding($false))
)

$stateDir = Split-Path -Parent $SprintPath
$companyStateMarkdownPath = Join-Path $stateDir "company-state.md"
$companyStateJsonPath = Join-Path $stateDir "company-state.json"

$companyStateLines = @(
    "# Company State",
    "",
    "Generated: $now",
    "",
    "## Source of Truth",
    "",
    "- Task status and task evidence: tasks/AICO-*.md",
    "- Product decisions: docs/product/",
    "- Architecture decisions: docs/architecture/ and docs/decisions/",
    "- This file is a derived index and does not grant execution authorization.",
    "",
    "## Current Objective",
    "",
    $sprintGoal,
    "",
    "## Current Sprint",
    "",
    ".codex/state/current-sprint.md",
    "",
    "## Active Tasks",
    "",
    (Format-TaskLines $active),
    "",
    "## Blocked Tasks",
    "",
    (Format-TaskLines $blocked),
    "",
    "## Completed Tasks",
    "",
    (Format-TaskLines $done),
    "",
    "## Operational Metrics",
    "",
    ".codex/runtime/metrics/events.jsonl"
)
[System.IO.File]::WriteAllText($companyStateMarkdownPath,($companyStateLines -join [Environment]::NewLine),(New-Object System.Text.UTF8Encoding($false)))

$companyState = [ordered]@{
    schema_version = 1
    generated = $now
    sprint_goal = $sprintGoal
    task_count = $tasks.Count
    active_count = $active.Count
    blocked_count = $blocked.Count
    done_count = $done.Count
    active_task_ids = @($active | Sort-Object ID | ForEach-Object { $_.ID })
    blocked_task_ids = @($blocked | Sort-Object ID | ForEach-Object { $_.ID })
}
[System.IO.File]::WriteAllText($companyStateJsonPath,($companyState | ConvertTo-Json -Depth 10),(New-Object System.Text.UTF8Encoding($false)))

Write-Host "Company state synced:" -ForegroundColor Green
Write-Host $SprintPath
Write-Host $companyStateMarkdownPath
Write-Host $companyStateJsonPath
) { $Matches[1].Trim() } else { $File.BaseName }
    $title = if ($content -match '(?m)^#\s+(.+)
        Status = if ($content -match '(?m)^Status:\s*(.+)$') { $Matches[1].Trim() } else { "UNKNOWN" }
        Priority = if ($content -match '(?m)^Priority:\s*(.+)$') { $Matches[1].Trim() } else { "" }
        Owner = if ($content -match '(?m)^Owner:\s*(.+)$') { $Matches[1].Trim() } else { "" }
        Updated = if ($content -match '(?m)^Updated:\s*(.+)$') { $Matches[1].Trim() } else { "" }
    }
}

function Format-TaskLines {
    param($Items)

    $itemsArray = @($Items)
    if ($itemsArray.Count -eq 0) {
        return "-"
    }

    return (($itemsArray | Sort-Object Priority, ID | ForEach-Object {
        "- $($_.ID) [$($_.Status)/$($_.Priority)] $($_.Title) - Owner: $($_.Owner)"
    }) -join [Environment]::NewLine)
}

if (-not (Test-Path $TasksPath)) {
    throw "Tasks directory not found: $TasksPath"
}

$tasks = @(
    Get-ChildItem -Path $TasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue |
        ForEach-Object { Get-TaskData $_ }
)

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$sprintGoal = "No current objective recorded."
$currentObjectivePath = ".codex/state/current-objective.md"

if (Test-Path $currentObjectivePath) {
    $objectiveContent = Get-Content -Path $currentObjectivePath -Raw
    if ($objectiveContent -match '(?m)^Objective:\s*(.+)$') {
        $sprintGoal = $Matches[1].Trim()
    }
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
    $sprintGoal,
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
if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

[System.IO.File]::WriteAllText(
    $SprintPath,
    $content,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Company sprint state synced:" -ForegroundColor Green
Write-Host $SprintPath
) { $Matches[1].Trim() } else { $File.BaseName }
    if ($title -match ("^" + [regex]::Escape($id) + "\\s+-\\s+(.+)$")) { $title = $Matches[1].Trim() }

    [PSCustomObject]@{
        ID = $id
        Title = $title
        Status = if ($content -match '(?m)^Status:\s*(.+)$') { $Matches[1].Trim() } else { "UNKNOWN" }
        Priority = if ($content -match '(?m)^Priority:\s*(.+)$') { $Matches[1].Trim() } else { "" }
        Owner = if ($content -match '(?m)^Owner:\s*(.+)$') { $Matches[1].Trim() } else { "" }
        Updated = if ($content -match '(?m)^Updated:\s*(.+)$') { $Matches[1].Trim() } else { "" }
    }
}

function Format-TaskLines {
    param($Items)

    $itemsArray = @($Items)
    if ($itemsArray.Count -eq 0) {
        return "-"
    }

    return (($itemsArray | Sort-Object Priority, ID | ForEach-Object {
        "- $($_.ID) [$($_.Status)/$($_.Priority)] $($_.Title) - Owner: $($_.Owner)"
    }) -join [Environment]::NewLine)
}

if (-not (Test-Path $TasksPath)) {
    throw "Tasks directory not found: $TasksPath"
}

$tasks = @(
    Get-ChildItem -Path $TasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue |
        ForEach-Object { Get-TaskData $_ }
)

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$sprintGoal = "No current objective recorded."
$currentObjectivePath = ".codex/state/current-objective.md"

if (Test-Path $currentObjectivePath) {
    $objectiveContent = Get-Content -Path $currentObjectivePath -Raw
    if ($objectiveContent -match '(?m)^Objective:\s*(.+)$') {
        $sprintGoal = $Matches[1].Trim()
    }
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
    $sprintGoal,
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
if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

[System.IO.File]::WriteAllText(
    $SprintPath,
    $content,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Company sprint state synced:" -ForegroundColor Green
Write-Host $SprintPath
