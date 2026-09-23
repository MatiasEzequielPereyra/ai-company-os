param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$materializer = Join-Path $repoRoot "scripts\materialize-engineering-backlog.ps1"

if (-not (Test-Path $materializer)) {
    throw "materialize-engineering-backlog.ps1 missing"
}

$tempRoot = Join-Path $env:TEMP ("aico-backlog-materializer-" + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "tasks") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\engineering\plans") | Out-Null

    $sourceTask = @(
        "# AICO-006 - Engineering Plan",
        "",
        "## Metadata",
        "",
        "ID: AICO-006",
        "",
        "Status: DONE",
        "",
        "Priority: P1",
        "",
        "Owner: engineering-manager",
        "",
        "Work request: WR-001"
    ) -join [Environment]::NewLine

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "tasks\AICO-006.md"),
        $sourceTask,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $fixture = @{
        source_task_id = "AICO-006"
        work_request_id = "WR-001"
        summary = "Fixture backlog"
        implementation_authorization_key = "AUTH"
        items = @(
            @{
                key = "AUTH"
                kind = "DECISION"
                title = "Authorize implementation"
                owner = "pm"
                priority = "P0"
                objective = "Approve implementation scope."
                context = "Human authorization required."
                acceptance_criteria = @("Implementation scope is explicitly authorized.")
                dependencies = @()
                affected_areas = @("planning")
                testing_requirements = @("Record approval evidence.")
                risks = @("Unauthorized implementation.")
            },
            @{
                key = "BUILD"
                kind = "IMPLEMENTATION"
                title = "Fix release build"
                owner = "devops"
                priority = "P0"
                objective = "Produce a bootable release artifact."
                context = "Release composition is broken."
                acceptance_criteria = @("Release artifact boots.")
                dependencies = @()
                affected_areas = @("scripts/build-release.mjs")
                testing_requirements = @("Browser smoke test.")
                risks = @("Startup failure.")
            },
            @{
                key = "VERIFY"
                kind = "VALIDATION"
                title = "Verify release boot"
                owner = "qa"
                priority = "P0"
                objective = "Verify the release artifact."
                context = "Validate BUILD."
                acceptance_criteria = @("Boot smoke passes.")
                dependencies = @("BUILD")
                affected_areas = @("tests")
                testing_requirements = @("Run browser boot smoke.")
                risks = @("Regression not detected.")
            }
        )
    }

    $planPath = Join-Path $tempRoot "docs\engineering\plans\AICO-006-engineering-backlog.json"
    $fixtureJson = $fixture | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($planPath,$fixtureJson,(New-Object System.Text.UTF8Encoding($false)))

    & $materializer -SourceTaskId "AICO-006" -ProjectPath $tempRoot

    $created = @(Get-ChildItem (Join-Path $tempRoot "tasks") -Filter "AICO-*.md" -File | Where-Object { $_.BaseName -ne "AICO-006" } | Sort-Object Name)
    if ($created.Count -ne 3) {
        throw "Expected 3 materialized tasks, got $($created.Count)"
    }

    if ($created[0].BaseName -ne "AICO-007" -or $created[1].BaseName -ne "AICO-008" -or $created[2].BaseName -ne "AICO-009") {
        throw "Materialized IDs are not sequential from AICO-007"
    }

    $auth = Get-Content (Join-Path $tempRoot "tasks\AICO-007.md") -Raw -Encoding UTF8
    $build = Get-Content (Join-Path $tempRoot "tasks\AICO-008.md") -Raw -Encoding UTF8
    $verify = Get-Content (Join-Path $tempRoot "tasks\AICO-009.md") -Raw -Encoding UTF8

    if ($auth -notmatch '(?m)^Backlog key:\s*AUTH$') {
        throw "Authorization task mapping is incorrect"
    }

    if ($build -notmatch '(?ms)^## Dependencies\s*\r?\n\s*\r?\n- AICO-007') {
        throw "Implementation task did not inherit authorization dependency"
    }

    if ($verify -notmatch '(?ms)^## Dependencies\s*\r?\n\s*\r?\n(?:- AICO-008\s*\r?\n)?- AICO-007|^## Dependencies\s*\r?\n\s*\r?\n- AICO-008') {
        throw "Validation task dependency mapping is incorrect"
    }

    $mapping = Join-Path $tempRoot "docs\engineering\plans\AICO-006-engineering-backlog-tasks.md"
    if (-not (Test-Path $mapping)) {
        throw "Backlog mapping file was not created"
    }

    $duplicateRejected = $false
    try {
        & $materializer -SourceTaskId "AICO-006" -ProjectPath $tempRoot
    }
    catch {
        if ($_.Exception.Message -match 'already materialized') {
            $duplicateRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $duplicateRejected) {
        throw "Materializer did not reject duplicate materialization"
    }
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}

Write-Host "PASS: engineering backlog materializer test" -ForegroundColor Green
