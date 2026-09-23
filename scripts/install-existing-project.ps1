param(
    [Parameter(Mandatory = $true)]
    [string]$TargetProject,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

$sourceRoot = Split-Path -Parent $PSScriptRoot
$targetRoot = (Resolve-Path $TargetProject).Path

if (-not (Test-Path (Join-Path $targetRoot ".git"))) {
    Write-Host "WARNING: target does not appear to be a Git repository." -ForegroundColor Yellow
}

$directories = @(
    ".codex", ".codex\agents", ".codex\policies", ".codex\protocols", ".codex\state", ".codex\workflows",
    ".agents", ".agents\skills", "docs", "docs\product", "docs\architecture", "docs\engineering",
    "docs\operations", "docs\decisions", "tasks", "scripts", "scripts\providers", "schemas"
)
foreach ($dir in $directories) { New-Item -ItemType Directory -Force -Path (Join-Path $targetRoot $dir) | Out-Null }

$frameworkFiles = @(
    @{ Source="AGENTS.md"; Target="AGENTS.md" },
    @{ Source=".codex\config.toml"; Target=".codex\config.toml" },
    @{ Source=".codex\provider-config.json"; Target=".codex\provider-config.json" }
)
foreach ($entry in $frameworkFiles) {
    $source = Join-Path $sourceRoot $entry.Source
    $target = Join-Path $targetRoot $entry.Target
    if (-not (Test-Path $source)) { continue }
    if ((Test-Path $target) -and -not $Force) { Write-Host "SKIP existing: $($entry.Target)" -ForegroundColor DarkYellow }
    else { Copy-Item $source $target -Force; Write-Host "INSTALLED: $($entry.Target)" -ForegroundColor Green }
}

foreach ($folder in @(".codex\agents",".codex\policies",".codex\protocols",".codex\workflows")) {
    $sourceFolder = Join-Path $sourceRoot $folder
    $targetFolder = Join-Path $targetRoot $folder
    if (Test-Path $sourceFolder) {
        Get-ChildItem $sourceFolder -File | ForEach-Object {
            $target = Join-Path $targetFolder $_.Name
            if ((Test-Path $target) -and -not $Force) { Write-Host "SKIP existing: $folder\$($_.Name)" -ForegroundColor DarkYellow }
            else { Copy-Item $_.FullName $target -Force; Write-Host "INSTALLED: $folder\$($_.Name)" -ForegroundColor Green }
        }
    }
}

$skillsSource = Join-Path $sourceRoot ".agents\skills"
if (Test-Path $skillsSource) {
    Get-ChildItem $skillsSource -Directory | ForEach-Object {
        $destination = Join-Path $targetRoot (".agents\skills\" + $_.Name)
        if ((Test-Path $destination) -and -not $Force) { Write-Host "SKIP existing skill: $($_.Name)" -ForegroundColor DarkYellow }
        else { Copy-Item $_.FullName $destination -Recurse -Force; Write-Host "INSTALLED skill: $($_.Name)" -ForegroundColor Green }
    }
}

$scriptNames = @(
    "initialize-project.ps1","new-task.ps1","list-tasks.ps1","update-task.ps1","advance-task.ps1","sync-company-state.ps1",
    "new-work-request.ps1","generate-plan.ps1","materialize-plan-tasks.ps1","evaluate-readiness.ps1","dispatch-ready-tasks.ps1",
    "submit-task-result.ps1","review-task.ps1","qa-task.ps1","security-task.ps1","finalize-task.ps1","refresh-dependencies.ps1","orchestrate.ps1",
    "run-agent-task.ps1","run-active-agents.ps1","build-agent-context.ps1","provider-router.ps1","run-gate-agent.ps1","run-pending-gates.ps1"
)
foreach ($name in $scriptNames) {
    $source = Join-Path $sourceRoot ("scripts\" + $name)
    $target = Join-Path $targetRoot ("scripts\" + $name)
    if (-not (Test-Path $source)) { continue }
    if ((Test-Path $target) -and -not $Force) { Write-Host "SKIP existing script: $name" -ForegroundColor DarkYellow }
    else { Copy-Item $source $target -Force; Write-Host "INSTALLED script: $name" -ForegroundColor Green }
}

$providersSource = Join-Path $sourceRoot "scripts\providers"
$providersTarget = Join-Path $targetRoot "scripts\providers"
if (Test-Path $providersSource) {
    Get-ChildItem $providersSource -File | ForEach-Object {
        $target = Join-Path $providersTarget $_.Name
        if ((Test-Path $target) -and -not $Force) {
            Write-Host "SKIP existing provider: $($_.Name)" -ForegroundColor DarkYellow
        }
        else {
            Copy-Item $_.FullName $target -Force
            Write-Host "INSTALLED provider: $($_.Name)" -ForegroundColor Green
        }
    }
}

$schemaNames = @(
    "agent-result.schema.json",
    "review-result.schema.json",
    "qa-gate-result.schema.json",
    "security-gate-result.schema.json"
)
foreach ($schemaName in $schemaNames) {
    $schemaSource = Join-Path $sourceRoot ("schemas\" + $schemaName)
    $schemaTarget = Join-Path $targetRoot ("schemas\" + $schemaName)
    if (-not (Test-Path $schemaSource)) { continue }

    if ((Test-Path $schemaTarget) -and -not $Force) {
        Write-Host "SKIP existing schema: $schemaName" -ForegroundColor DarkYellow
    }
    else {
        Copy-Item $schemaSource $schemaTarget -Force
        Write-Host "INSTALLED schema: $schemaName" -ForegroundColor Green
    }
}

$nl = [Environment]::NewLine
$stateFiles = @{}
$stateFiles[".codex\state\current-sprint.md"] = "# Current Sprint" + $nl + $nl + "## Sprint Goal" + $nl + $nl + "-" + $nl
$stateFiles[".codex\state\company-state.md"] = "# Company State" + $nl + $nl + "## Current Handoff" + $nl + $nl + "-" + $nl + $nl + "## Current Sprint" + $nl + $nl + ".codex/state/current-sprint.md" + $nl
$stateFiles[".codex\state\blockers.md"] = "# Blockers" + $nl + $nl + "-" + $nl
foreach ($relative in $stateFiles.Keys) {
    $path = Join-Path $targetRoot $relative
    if (-not (Test-Path $path)) { Write-Utf8NoBom $path $stateFiles[$relative]; Write-Host "CREATED: $relative" -ForegroundColor Green }
}

$tasksReadme = Join-Path $targetRoot "tasks\README.md"
if (-not (Test-Path $tasksReadme)) {
    $sourceTasksReadme = Join-Path $sourceRoot "tasks\README.md"
    if (Test-Path $sourceTasksReadme) { Copy-Item $sourceTasksReadme $tasksReadme -Force }
}

Write-Host ""
Write-Host "AI Company OS installed into existing project." -ForegroundColor Green
Write-Host "Target: $targetRoot"
Write-Host ""
Write-Host "Next:"
Write-Host ("cd " + [char]34 + $targetRoot + [char]34)
Write-Host ".\scripts\initialize-project.ps1"