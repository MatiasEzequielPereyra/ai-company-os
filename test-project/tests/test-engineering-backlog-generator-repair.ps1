param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$generator = Join-Path $repoRoot "scripts\generate-engineering-backlog.ps1"
$schemaSource = Join-Path $repoRoot "schemas\engineering-backlog.schema.json"

foreach ($required in @($generator,$schemaSource)) {
    if (-not (Test-Path $required)) { throw "Required test input missing: $required" }
}

$tempRoot = Join-Path $env:TEMP ("aico-backlog-generator-repair-" + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "tasks") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\engineering\agent-reports") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\engineering\results") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\engineering\plans") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".codex\runtime") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "schemas") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts") | Out-Null

    Copy-Item $schemaSource (Join-Path $tempRoot "schemas\engineering-backlog.schema.json") -Force
    Set-Content (Join-Path $tempRoot "scripts\provider-router.ps1") "throw 'Provider router must not be invoked when ReuseExistingOutput is set.'"

    $sourceTask = @(
        "# AICO-006 - Engineering Plan",
        "",
        "ID: AICO-006",
        "",
        "Status: DONE",
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

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "docs\engineering\agent-reports\AICO-006.md"),
        "# Approved engineering plan",
        (New-Object System.Text.UTF8Encoding($false))
    )

    $runtimeOutput = @{
        source_task_id = "AICO-006"
        work_request_id = "WR-001"
        summary = "Repair fixture"
        implementation_authorization_key = "impl-auth"
        items = @(
            @{
                key = "AICO-006-IMPL-AUTH"
                kind = "DECISION"
                title = "Authorize implementation work"
                owner = "ceo"
                priority = "P0"
                objective = "Explicitly authorize implementation of the approved engineering backlog."
                context = "The approved source plan requires implementation authorization before code changes."
                acceptance_criteria = @("Implementation authorization is explicitly recorded.")
                dependencies = @()
                affected_areas = @("planning")
                testing_requirements = @("Record authorization evidence.")
                risks = @("Implementation starts without authorization.")
            },
            @{
                key = "AICO-006-DISCARD-SEMANTICS"
                kind = "DECISION"
                title = "Approve authorized discard semantics"
                owner = "pm"
                priority = "P1"
                objective = "Define approved resolution semantics for permanently unresolvable sales."
                context = "Implementation requires PM and Security approval before authorized discard behavior is introduced."
                acceptance_criteria = @("Discard semantics are explicitly approved.")
                dependencies = @()
                affected_areas = @("offline")
                testing_requirements = @("Record decision evidence.")
                risks = @("Incorrect discard authorization.")
            },
            @{
                key = "RELEASE_BUILD"
                kind = "IMPLEMENTATION"
                title = "Fix release build"
                owner = "devops"
                priority = "P0"
                objective = "Produce a bootable release artifact."
                context = "Release composition issue."
                acceptance_criteria = @("Release artifact boots.")
                dependencies = @()
                affected_areas = @("scripts/build-release.mjs")
                testing_requirements = @("Run browser smoke test.")
                risks = @("Startup failure.")
            }
        )
    } | ConvertTo-Json -Depth 20

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot ".codex\runtime\AICO-006-engineering-backlog.json"),
        $runtimeOutput,
        (New-Object System.Text.UTF8Encoding($false))
    )

    & $generator -SourceTaskId "AICO-006" -ProjectPath $tempRoot -ReuseExistingOutput

    $planPath = Join-Path $tempRoot "docs\engineering\plans\AICO-006-engineering-backlog.json"
    if (-not (Test-Path $planPath)) {
        throw "Repaired engineering backlog was not persisted."
    }

    $plan = Get-Content $planPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if ([string]$plan.implementation_authorization_key -ne "AICO-006-IMPL-AUTH") {
        throw "Authorization key was not repaired to the identity-matching implementation authorization DECISION item."
    }

    if (@($plan.items).Count -ne 3) {
        throw "Repair changed backlog item count unexpectedly."
    }

    $authorizationItem = @(
        $plan.items | Where-Object { [string]$_.key -eq "AICO-006-IMPL-AUTH" }
    ) | Select-Object -First 1

    if ($null -eq $authorizationItem) {
        throw "Authorization item disappeared during repair."
    }

    if (@($authorizationItem.dependencies | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -ne 0) {
        throw "Empty authorization dependencies were not preserved as an empty dependency set."
    }
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}

Write-Host "PASS: engineering backlog authorization repair test" -ForegroundColor Green
