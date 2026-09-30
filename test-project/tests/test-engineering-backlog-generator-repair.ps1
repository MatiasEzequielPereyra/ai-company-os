param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$generator = Join-Path $repoRoot "scripts\generate-engineering-backlog.ps1"
$semanticValidatorSource = Join-Path $repoRoot "scripts\validate-engineering-backlog-semantics.ps1"
$schemaSource = Join-Path $repoRoot "schemas\engineering-backlog.schema.json"

foreach ($required in @($generator,$semanticValidatorSource,$schemaSource)) {
    if (-not (Test-Path $required)) { throw "Required test input missing: $required" }
}

$generatorText = Get-Content $generator -Raw -Encoding UTF8
foreach ($requiredGeneratorContract in @(
    "Every IMPLEMENTATION objective must state the concrete repository/product change to make",
    "Every IMPLEMENTATION item must include at least one concrete behavioral acceptance criterion",
    "Testing requirements must be evidence-based",
    "Never invent test modules, test files, package scripts, commands, or verification targets",
    "use git diff --check instead of inventing a command",
    "===== CANONICAL EXECUTION PLAN =====",
    "SemanticValidatorPath",
    'Role "engineering-manager"',
    'Workload "analysis"'
)) {
    if ($generatorText -notmatch [regex]::Escape($requiredGeneratorContract)) {
        throw ("Engineering backlog generator is missing semantic-quality contract: " + $requiredGeneratorContract)
    }
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
    Copy-Item $semanticValidatorSource (Join-Path $tempRoot "scripts\validate-engineering-backlog-semantics.ps1") -Force
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

    $upstreamDoneTask = @(
        "# AICO-002 - Product Scope",
        "",
        "ID: AICO-002",
        "",
        "Status: DONE",
        "",
        "Owner: pm",
        "",
        "Work request: WR-001"
    ) -join [Environment]::NewLine

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "tasks\AICO-002.md"),
        $upstreamDoneTask,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $substantiveReport = @(
        "# Agent Report - AICO-006",
        "",
        "Generated: 2026-09-30T00:00:00Z",
        "Owner: engineering-manager",
        "Provider: fixture",
        "Model: fixture",
        "Outcome: COMPLETED",
        "",
        "## Engineering Execution Plan",
        "",
        "- Update scripts/build-release.mjs to produce a bootable release artifact.",
        "- Preserve startup behavior outside the scoped release composition change.",
        "- Verify the release artifact boots and run git diff --check.",
        "- Require explicit implementation authorization before writable execution."
    ) -join [Environment]::NewLine

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "docs\engineering\agent-reports\AICO-006.md"),
        $substantiveReport,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $executionPlan = @{
        source_task_id = "AICO-006"
        work_request_id = "WR-001"
        executable_work = @(
            @{
                key = "RELEASE_BUILD"
                kind = "IMPLEMENTATION"
                change = "Update scripts/build-release.mjs to produce a bootable release artifact."
                owner = "devops"
                areas = @("scripts/build-release.mjs")
                depends_on = @()
                verify = "Run browser smoke test and git diff --check."
            }
        )
    }
    $executionPlanJson = $executionPlan | ConvertTo-Json -Depth 20
    $executionPlanPath = Join-Path $tempRoot "docs\engineering\plans\AICO-006-execution-plan.json"
    [System.IO.File]::WriteAllText(
        $executionPlanPath,
        $executionPlanJson,
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
                dependencies = @("AICO-002")
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

    $decisionItem = @(
        $plan.items | Where-Object { [string]$_.key -eq "AICO-006-DISCARD-SEMANTICS" }
    ) | Select-Object -First 1

    if ($null -eq $decisionItem) {
        throw "Decision item disappeared during repair."
    }

    if (@($decisionItem.dependencies).Count -ne 0) {
        throw "DONE upstream planning task dependency was not removed during backlog repair."
    }

    $genericAuthorizationOutput = $runtimeOutput | ConvertFrom-Json
    $genericAuthorizationOutput.implementation_authorization_key = "AICO-006-DISCARD-SEMANTICS"

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot ".codex\runtime\AICO-006-engineering-backlog.json"),
        ($genericAuthorizationOutput | ConvertTo-Json -Depth 20),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $genericAuthorizationRejected = $false
    try {
        & $generator -SourceTaskId "AICO-006" -ProjectPath $tempRoot -ReuseExistingOutput
    }
    catch {
        if ($_.Exception.Message -match "does not explicitly authorize implementation") {
            $genericAuthorizationRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $genericAuthorizationRejected) {
        throw "Backlog generator accepted a non-authorizing DECISION as implementation authorization."
    }

    $noneAuthorizationOutput = $runtimeOutput | ConvertFrom-Json
    $noneAuthorizationOutput.implementation_authorization_key = "NONE"

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot ".codex\runtime\AICO-006-engineering-backlog.json"),
        ($noneAuthorizationOutput | ConvertTo-Json -Depth 20),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $unsupportedNoneRejected = $false
    try {
        & $generator -SourceTaskId "AICO-006" -ProjectPath $tempRoot -ReuseExistingOutput
    }
    catch {
        if ($_.Exception.Message -match "NONE is not supported by approved source evidence") {
            $unsupportedNoneRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $unsupportedNoneRejected) {
        throw "Backlog generator accepted NONE without explicit no-authorization source evidence."
    }

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "docs\engineering\agent-reports\AICO-006.md"),
        "# Approved engineering plan" + [Environment]::NewLine + "No implementation authorization is required for this work.",
        (New-Object System.Text.UTF8Encoding($false))
    )

    $explicitNoneOutput = @{
        source_task_id = "AICO-006"
        work_request_id = "WR-001"
        summary = "Explicit no-authorization fixture"
        implementation_authorization_key = "NONE"
        items = @(
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
                testing_requirements = @("git diff --check")
                risks = @("Startup failure.")
            }
        )
    }

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot ".codex\runtime\AICO-006-engineering-backlog.json"),
        ($explicitNoneOutput | ConvertTo-Json -Depth 20),
        (New-Object System.Text.UTF8Encoding($false))
    )

    & $generator -SourceTaskId "AICO-006" -ProjectPath $tempRoot -ReuseExistingOutput

    $explicitNonePlan = Get-Content $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$explicitNonePlan.implementation_authorization_key -ne "NONE") {
        throw "Backlog generator rejected NONE despite explicit no-authorization source evidence."
    }

    # Semantic-quality validation must reject generic implementation work even
    # when provider routing is bypassed through ReuseExistingOutput.
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "docs\engineering\agent-reports\AICO-006.md"),
        $substantiveReport,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $genericImplementationOutput = $runtimeOutput | ConvertFrom-Json
    $genericImplementation = @(
        $genericImplementationOutput.items |
        Where-Object { [string]$_.kind -eq "IMPLEMENTATION" }
    ) | Select-Object -First 1
    $genericImplementation.objective = "Produce the role-owned output required by the orchestration plan."
    $genericImplementation.acceptance_criteria = @("Role-owned deliverable is produced.")

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot ".codex\runtime\AICO-006-engineering-backlog.json"),
        ($genericImplementationOutput | ConvertTo-Json -Depth 20),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $genericImplementationRejected = $false
    try {
        & $generator -SourceTaskId "AICO-006" -ProjectPath $tempRoot -ReuseExistingOutput
    }
    catch {
        if ($_.Exception.Message -match "generic/non-executable objective|no concrete acceptance criteria") {
            $genericImplementationRejected = $true
        }
        else {
            throw
        }
    }
    if (-not $genericImplementationRejected) {
        throw "Backlog generator accepted generic non-executable IMPLEMENTATION work."
    }

    $missingVerificationOutput = $runtimeOutput | ConvertFrom-Json
    $missingVerificationImplementation = @(
        $missingVerificationOutput.items |
        Where-Object { [string]$_.kind -eq "IMPLEMENTATION" }
    ) | Select-Object -First 1
    $missingVerificationImplementation.testing_requirements = @()

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot ".codex\runtime\AICO-006-engineering-backlog.json"),
        ($missingVerificationOutput | ConvertTo-Json -Depth 20),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $missingVerificationRejected = $false
    try {
        & $generator -SourceTaskId "AICO-006" -ProjectPath $tempRoot -ReuseExistingOutput
    }
    catch {
        if ($_.Exception.Message -match "no verification requirement") {
            $missingVerificationRejected = $true
        }
        else {
            throw
        }
    }
    if (-not $missingVerificationRejected) {
        throw "Backlog generator accepted IMPLEMENTATION work without a verification requirement."
    }

    # Canonical structured execution work is the preferred source-quality
    # signal. Without it, a metadata-only report must fail before provider use.
    if (Test-Path $executionPlanPath) {
        Remove-Item $executionPlanPath -Force
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "docs\engineering\agent-reports\AICO-006.md"),
        "# Agent Report - AICO-006" + [Environment]::NewLine + "Outcome: COMPLETED",
        (New-Object System.Text.UTF8Encoding($false))
    )

    $shallowSourceRejected = $false
    try {
        & $generator -SourceTaskId "AICO-006" -ProjectPath $tempRoot -ReuseExistingOutput
    }
    catch {
        if ($_.Exception.Message -match "source evidence is not substantive enough") {
            $shallowSourceRejected = $true
        }
        else {
            throw
        }
    }
    if (-not $shallowSourceRejected) {
        throw "Backlog generator accepted shallow Engineering Manager source evidence."
    }

    [System.IO.File]::WriteAllText(
        $executionPlanPath,
        $executionPlanJson,
        (New-Object System.Text.UTF8Encoding($false))
    )
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}

Write-Host "PASS: engineering backlog authorization repair test" -ForegroundColor Green
