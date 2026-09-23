param(
    [string]$TasksPath = "tasks",

    [ValidateSet("ALL", "BACKLOG", "READY", "ACTIVE", "REVIEW", "QA", "SECURITY", "DONE", "BLOCKED")]
    [string]$Status = "ALL"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $TasksPath)) {
    Write-Host "No tasks directory found: $TasksPath" -ForegroundColor Yellow
    exit 0
}

$tasks = Get-ChildItem -Path $TasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $content = Get-Content -Path $_.FullName -Raw -Encoding UTF8

    $id = if ($content -match '(?m)^ID:\s*(.+)$') { $Matches[1].Trim() } else { $_.BaseName }
    $title = if ($content -match '(?m)^#\s+(.+)$') { $Matches[1].Trim() } else { $_.BaseName }
    $taskStatus = if ($content -match '(?m)^Status:\s*(.+)$') { $Matches[1].Trim() } else { "UNKNOWN" }
    $priority = if ($content -match '(?m)^Priority:\s*(.+)$') { $Matches[1].Trim() } else { "" }
    $owner = if ($content -match '(?m)^Owner:\s*(.+)$') { $Matches[1].Trim() } else { "" }
    $updated = if ($content -match '(?m)^Updated:\s*(.+)$') { $Matches[1].Trim() } else { "" }

    [PSCustomObject]@{
        ID = $id
        Status = $taskStatus
        Priority = $priority
        Owner = $owner
        Updated = $updated
        File = $_.Name
        Title = $title
    }
}

if ($Status -ne "ALL") {
    $tasks = $tasks | Where-Object { $_.Status -eq $Status }
}

if (-not $tasks) {
    Write-Host "No tasks found." -ForegroundColor Yellow
    exit 0
}

$tasks |
    Sort-Object Status, Priority, ID |
    Format-Table ID, Status, Priority, Owner, Updated, Title -AutoSize
