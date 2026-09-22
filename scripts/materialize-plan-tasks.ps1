param(
    [Parameter(Mandatory = $true)]
    [string]$WorkRequestId,

    [string]$ProjectPath = "."
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param([string]$Path, [string]$Value)
    [System.IO.File]::WriteAllText($Path, $Value, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-Field {
    param([string]$Content, [string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return "UNKNOWN"
}

function Get-NextTaskId {
    param([string]$TasksPath)
    $existing = @(Get-ChildItem -Path $TasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.BaseName -match '^AICO-(\d+)$') { [int]$Matches[1] }
    })
    $next = 1
    if ($existing.Count -gt 0) { $next = [int](($existing | Measure-Object -Maximum).Maximum) + 1 }
    return "AICO-" + $next.ToString().PadLeft(3, '0')
}

function New-GeneratedTask {
    param(
        [string]$TasksPath,
        [string]$Title,
        [string]$Owner,
        [string]$Priority,
        [string]$Objective,
        [string[]]$Dependencies,
        [string]$WorkRequestId
    )

    $id = Get-NextTaskId $TasksPath
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $filePath = Join-Path $TasksPath ($id + ".md")
    $dependencyLines = "-"
    if ($Dependencies -and $Dependencies.Count -gt 0) {
        $dependencyLines = ($Dependencies | ForEach-Object { "- " + $_ }) -join [Environment]::NewLine
    }

    $lines = @(
        "# $id - $Title",
        "",
        "## Metadata",
        "",
        "ID: $id",
        "",
        "Status: BACKLOG",
        "",
        "Priority: $Priority",
        "",
        "Owner: $Owner",
        "",
        "Created: $now",
        "",
        "Updated: $now",
        "",
        "Workflow phase: PLANNING",
        "",
        "Work request: $WorkRequestId",
        "",
        "---",
        "",
        "## Objective",
        "",
        $Objective,
        "",
        "---",
        "",
        "## Context",
        "",
        "- Generated from orchestration plan for $WorkRequestId.",
        "- Planning output only; implementation authorization is not inferred.",
        "",
        "---",
        "",
        "## Requirements",
        "",
        "- Produce the role-owned output required by the orchestration plan.",
        "- Record unresolved blockers instead of guessing.",
        "- Preserve source-of-truth ownership boundaries.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] Role-owned deliverable is produced.",
        "- [ ] Open questions and blockers are explicit.",
        "- [ ] Evidence is recorded in this task.",
        "- [ ] Applicable downstream dependencies are ready.",
        "",
        "---",
        "",
        "## Dependencies",
        "",
        $dependencyLines,
        "",
        "---",
        "",
        "## Testing Requirements",
        "",
        "- Verify the produced artifact is internally consistent and references authoritative sources.",
        "",
        "---",
        "",
        "## Evidence",
        "",
        "-",
        "",
        "---",
        "",
        "## Handoff",
        "",
        "Next agent: $Owner",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "- $now - SYSTEM - CREATED - Generated from $WorkRequestId orchestration plan.",
        "",
        "---",
        "",
        "## Notes",
        "",
        "-"
    )

    Write-Utf8NoBom $filePath ($lines -join [Environment]::NewLine)
    return $id
}

$root = (Resolve-Path $ProjectPath).Path
$tasksPath = Join-Path $root "tasks"
if (-not (Test-Path $tasksPath)) { New-Item -ItemType Directory -Force -Path $tasksPath | Out-Null }

$requestPath = Join-Path $root ("docs\engineering\work-requests\" + $WorkRequestId + ".md")
$planPath = Join-Path $root ("docs\engineering\plans\" + $WorkRequestId + "-plan.md")

if (-not (Test-Path $requestPath)) { throw "Work request not found: $requestPath" }
if (-not (Test-Path $planPath)) { throw "Plan not found: $planPath" }

$request = Get-Content $requestPath -Raw
$plan = Get-Content $planPath -Raw

$type = Read-Field $request "Type"
$priority = Read-Field $request "Priority"
$objective = "UNKNOWN"
if ($request -match '(?ms)^## Objective\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n##|\z)') {
    $objective = $Matches[1].Trim()
}

$roles = @()
if ($plan -match '(?ms)^## Required Roles\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n##|\z)') {
    $roles = @($Matches[1] -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^-\s+' } | ForEach-Object { $_ -replace '^-\s+', '' })
}
if ($roles.Count -eq 0) { throw "No required roles found in plan: $planPath" }

$existingForRequest = @(Get-ChildItem $tasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue | Where-Object {
    (Get-Content $_.FullName -Raw) -match ("(?m)^Work request:\s*" + [regex]::Escape($WorkRequestId) + "$")
})
if ($existingForRequest.Count -gt 0) {
    throw "Tasks already materialized for $WorkRequestId. Existing count: $($existingForRequest.Count)"
}

$created = @()
$taskByRole = @{}

foreach ($role in $roles) {
    $title = switch ($role) {
        "pm" { "Define product scope for $WorkRequestId" }
        "cto" { "Define technical architecture for $WorkRequestId" }
        "engineering-manager" { "Prepare engineering execution plan for $WorkRequestId" }
        "qa" { "Prepare QA validation for $WorkRequestId" }
        "security" { "Prepare security review for $WorkRequestId" }
        "devops" { "Prepare release and operations review for $WorkRequestId" }
        default { "Complete $role work for $WorkRequestId" }
    }

    $roleObjective = switch ($role) {
        "pm" { "Validate product requirements, scope, non-goals and acceptance criteria for: $objective" }
        "cto" { "Validate architecture, technical constraints, contracts and risks for: $objective" }
        "engineering-manager" { "Convert approved product and architecture outputs into executable engineering work for: $objective" }
        "qa" { "Define functional, regression and release validation required for: $objective" }
        "security" { "Review applicable security boundaries, data handling and release risks for: $objective" }
        "devops" { "Review build, deployment, observability and rollback readiness for: $objective" }
        default { "Complete the $role responsibilities required for: $objective" }
    }

    $deps = @()

    if ($type -eq "AUDIT") {
        if ($role -eq "engineering-manager") {
            foreach ($dependencyRole in @("pm","cto","qa","security","devops")) {
                if ($taskByRole.ContainsKey($dependencyRole)) {
                    $deps += $taskByRole[$dependencyRole]
                }
            }
        }
    }
    else {
        if ($role -eq "cto" -and $taskByRole.ContainsKey("pm")) {
            $deps = @($taskByRole["pm"])
        }
        elseif ($role -eq "engineering-manager") {
            foreach ($dependencyRole in @("pm","cto")) {
                if ($taskByRole.ContainsKey($dependencyRole)) {
                    $deps += $taskByRole[$dependencyRole]
                }
            }
        }
        elseif ($role -in @("qa","security","devops") -and $taskByRole.ContainsKey("engineering-manager")) {
            $deps = @($taskByRole["engineering-manager"])
        }
    }

    $id = New-GeneratedTask -TasksPath $tasksPath -Title $title -Owner $role -Priority $priority -Objective $roleObjective -Dependencies $deps -WorkRequestId $WorkRequestId
    $created += $id
    $taskByRole[$role] = $id
}

$mappingPath = Join-Path $root ("docs\engineering\plans\" + $WorkRequestId + "-tasks.md")
$mapLines = @(
    "# Materialized Tasks - $WorkRequestId",
    "",
    "Type: $type",
    "Priority: $priority",
    "",
    "## Tasks"
)
foreach ($id in $created) {
    $taskContent = Get-Content (Join-Path $tasksPath ($id + ".md")) -Raw
    $owner = Read-Field $taskContent "Owner"
    $mapLines += "- $id - Owner: $owner"
}
$mapLines += ""
$mapLines += "## Rule"
$mapLines += ""
$mapLines += "- Tasks are created in BACKLOG."
$mapLines += "- They must pass readiness and authorization checks before ACTIVE."
$mapLines += "- This file is a derived mapping; task files remain authoritative."

Write-Utf8NoBom $mappingPath ($mapLines -join [Environment]::NewLine)

Write-Host "Tasks materialized:" -ForegroundColor Green
$created | ForEach-Object { Write-Host $_ }
Write-Host "Mapping:"
Write-Host $mappingPath
