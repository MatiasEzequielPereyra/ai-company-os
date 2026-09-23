param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$materializer = Join-Path $repoRoot "scripts\materialize-engineering-backlog.ps1"

if (-not (Test-Path $materializer)) {
    throw "materialize-engineering-backlog.ps1 missing"
}

function Read-Field {
    param(
        [string]$Content,
        [string]$Key
    )

    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+?)\r?$"
    if ($Content -match $pattern) {
        return $Matches[1].Trim()
    }

    return ""
}

function Read-Dependencies {
    param([string]$Content)

    $pattern = "(?ms)^## Dependencies\s*\r?\n\s*\r?\n(.*?)(?=\r?\n\r?\n---|\z)"
    if ($Content -notmatch $pattern) {
        return @()
    }

    return @(
        $Matches[1] -split "\r?\n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match "^-\s+AICO-\d+$" } |
            ForEach-Object { $_ -replace "^-\s+", "" }
    )
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

    [System.IO.File]::WriteAllText(
        $planPath,
        $fixtureJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    & $materializer -SourceTaskId "AICO-006" -ProjectPath $tempRoot

    $created = @(
        Get-ChildItem (Join-Path $tempRoot "tasks") -Filter "AICO-*.md" -File |
            Where-Object { $_.BaseName -ne "AICO-006" } |
            Sort-Object Name
    )

    if ($created.Count -ne 3) {
        throw "Expected 3 materialized tasks, got $($created.Count)"
    }

    $expectedIds = @("AICO-007","AICO-008","AICO-009")
    $actualIds = @($created | ForEach-Object { $_.BaseName })

    if (($actualIds -join ",") -ne ($expectedIds -join ",")) {
        throw "Materialized IDs are not sequential from AICO-007. Got: $($actualIds -join ', ')"
    }

    $taskByKey = @{}
    $idByKey = @{}

    foreach ($file in $created) {
        $taskContent = Get-Content $file.FullName -Raw -Encoding UTF8
        $key = Read-Field -Content $taskContent -Key "Backlog key"

        if ([string]::IsNullOrWhiteSpace($key)) {
            throw "Materialized task $($file.BaseName) has no Backlog key"
        }

        if ($taskByKey.ContainsKey($key)) {
            throw "Duplicate materialized backlog key: $key"
        }

        $taskByKey[$key] = $taskContent
        $idByKey[$key] = $file.BaseName
    }

    foreach ($key in @("AUTH","BUILD","VERIFY")) {
        if (-not $taskByKey.ContainsKey($key)) {
            throw "Missing materialized task for backlog key: $key"
        }
    }

    $authDependencies = @(Read-Dependencies -Content $taskByKey["AUTH"])
    if ($authDependencies.Count -ne 0) {
        throw "Authorization task must not gain dependencies in this fixture"
    }

    $buildDependencies = @(Read-Dependencies -Content $taskByKey["BUILD"])
    if ($buildDependencies -notcontains $idByKey["AUTH"]) {
        throw "Implementation task did not inherit authorization dependency"
    }

    $verifyDependencies = @(Read-Dependencies -Content $taskByKey["VERIFY"])
    if ($verifyDependencies -notcontains $idByKey["BUILD"]) {
        throw "Validation task did not preserve BUILD dependency"
    }

    $mappingPath = Join-Path $tempRoot "docs\engineering\plans\AICO-006-engineering-backlog-tasks.md"
    if (-not (Test-Path $mappingPath)) {
        throw "Backlog mapping file was not created"
    }

    $mapping = Get-Content $mappingPath -Raw -Encoding UTF8
    foreach ($key in @("AUTH","BUILD","VERIFY")) {
        if ($mapping -notmatch ("(?m)^- " + [regex]::Escape($key) + " -> " + [regex]::Escape($idByKey[$key]) + "\b")) {
            throw "Mapping file does not contain correct entry for $key"
        }
    }

    $duplicateRejected = $false

    try {
        & $materializer -SourceTaskId "AICO-006" -ProjectPath $tempRoot
    }
    catch {
        if ($_.Exception.Message -match "already materialized") {
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
