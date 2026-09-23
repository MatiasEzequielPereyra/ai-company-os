param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$reconcile = Join-Path $repoRoot "scripts\reconcile-engineering-backlog.ps1"

if (-not (Test-Path $reconcile)) {
    throw "reconcile-engineering-backlog.ps1 missing"
}

$tempRoot = Join-Path $env:TEMP ("aico-backlog-reconcile-" + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "tasks") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\engineering\plans") | Out-Null

    $existingTask = @(
        "# AICO-007 - Old implementation title",
        "",
        "## Metadata",
        "",
        "ID: AICO-007",
        "",
        "Status: BACKLOG",
        "",
        "Priority: P1",
        "",
        "Owner: backend",
        "",
        "Created: 2026-09-23T00:00:00Z",
        "",
        "Updated: 2026-09-23T00:00:00Z",
        "",
        "Workflow phase: PLANNING",
        "",
        "Work request: WR-001",
        "",
        "Source plan: AICO-006",
        "",
        "Backlog key: BUILD",
        "",
        "Work kind: IMPLEMENTATION",
        "",
        "---",
        "",
        "## Objective",
        "",
        "Old objective",
        "",
        "---",
        "",
        "## Dependencies",
        "",
        "-",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "- existing",
        ""
    ) -join [Environment]::NewLine

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "tasks\AICO-007.md"),
        $existingTask,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $plan = @{
        source_task_id = "AICO-006"
        work_request_id = "WR-001"
        summary = "Fixture"
        implementation_authorization_key = "AUTH"
        items = @(
            @{
                key = "AUTH"; kind = "DECISION"; title = "Authorize implementation"; owner = "ceo"; priority = "P0"
                objective = "Authorize work."; context = "Approval required."
                acceptance_criteria = @("Authorization recorded."); dependencies = @()
                affected_areas = @("planning"); testing_requirements = @("Record evidence."); risks = @("Unauthorized work.")
            },
            @{
                key = "BUILD"; kind = "IMPLEMENTATION"; title = "Updated implementation title"; owner = "backend"; priority = "P1"
                objective = "Updated objective."; context = "Updated context."
                acceptance_criteria = @("Behavior verified."); dependencies = @("AUTH")
                affected_areas = @("src"); testing_requirements = @("Run regression."); risks = @("Regression.")
            },
            @{
                key = "VERIFY"; kind = "VALIDATION"; title = "Validate build"; owner = "qa"; priority = "P1"
                objective = "Validate build."; context = "New downstream task."
                acceptance_criteria = @("Validation passes."); dependencies = @("BUILD")
                affected_areas = @("tests"); testing_requirements = @("Run validation."); risks = @("Missed defect.")
            }
        )
    } | ConvertTo-Json -Depth 20

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "docs\engineering\plans\AICO-006-engineering-backlog.json"),
        $plan,
        (New-Object System.Text.UTF8Encoding($false))
    )

    & $reconcile -SourceTaskId "AICO-006" -ProjectPath $tempRoot

    $build = Get-Content (Join-Path $tempRoot "tasks\AICO-007.md") -Raw -Encoding UTF8
    if ($build -notmatch 'Updated implementation title') {
        throw "Existing BACKLOG task was not reconciled."
    }

    $created = @(Get-ChildItem (Join-Path $tempRoot "tasks") -Filter "AICO-*.md" -File | Sort-Object Name)
    if ($created.Count -ne 3) {
        throw "Expected existing BUILD plus two new tasks. Got $($created.Count)"
    }

    $auth = Get-Content (Join-Path $tempRoot "tasks\AICO-008.md") -Raw -Encoding UTF8
    $verify = Get-Content (Join-Path $tempRoot "tasks\AICO-009.md") -Raw -Encoding UTF8

    if ($auth -notmatch '(?m)^Backlog key:\s*AUTH\r?$') {
        throw "New authorization task mapping is incorrect."
    }
    if ($verify -notmatch '(?m)^Backlog key:\s*VERIFY\r?$') {
        throw "New validation task mapping is incorrect."
    }
    if ($verify -notmatch '(?m)^- AICO-007\r?$') {
        throw "New validation task did not map dependency to existing BUILD task ID."
    }

    $mapping = Get-Content (Join-Path $tempRoot "docs\engineering\plans\AICO-006-engineering-backlog-tasks.md") -Raw -Encoding UTF8
    if ($mapping -notmatch 'Total: 3') {
        throw "Reconciled mapping did not compute item counts."
    }
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}

Write-Host "PASS: engineering backlog reconcile test" -ForegroundColor Green
