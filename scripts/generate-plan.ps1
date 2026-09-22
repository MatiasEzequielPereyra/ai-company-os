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

$root = (Resolve-Path $ProjectPath).Path
$requestPath = Join-Path $root ("docs\engineering\work-requests\" + $WorkRequestId + ".md")
if (-not (Test-Path $requestPath)) { throw "Work request not found: $requestPath" }

$request = Get-Content $requestPath -Raw
$type = Read-Field $request "Type"
$priority = Read-Field $request "Priority"
$objective = "UNKNOWN"
if ($request -match '(?ms)^## Objective\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n##|\z)') { $objective = $Matches[1].Trim() }

$roles = @("engineering-manager")
$stages = @()

switch ($type) {
    "FEATURE" {
        $roles = @("pm","cto","engineering-manager","qa")
        $stages = @(
            "PM validates requirements, scope, non-goals and acceptance criteria.",
            "CTO validates architecture, contracts, migrations and technical risks.",
            "Engineering Manager decomposes approved work into executable tasks.",
            "Implementation tasks proceed through review, QA and security when applicable."
        )
    }
    "BUG" {
        $roles = @("engineering-manager","qa")
        $stages = @(
            "Engineering Manager reproduces and scopes the defect.",
            "Relevant engineer implements the smallest corrective change.",
            "QA verifies the fix and regression coverage."
        )
    }
    "REFACTOR" {
        $roles = @("cto","engineering-manager","qa")
        $stages = @(
            "CTO confirms target architecture and migration boundaries.",
            "Engineering Manager decomposes the refactor into reversible tasks.",
            "QA protects existing behavior with regression verification."
        )
    }
    "INFRASTRUCTURE" {
        $roles = @("cto","engineering-manager","devops","security","qa")
        $stages = @(
            "CTO validates infrastructure design and dependencies.",
            "DevOps defines implementation, observability and rollback.",
            "Security reviews changed trust boundaries.",
            "QA validates service behavior after the change."
        )
    }
    "AUDIT" {
        $roles = @("pm","cto","engineering-manager","qa","security","devops")
        $stages = @(
            "PM checks product completeness and user-facing gaps.",
            "CTO audits architecture, maintainability and technical debt.",
            "Engineering Manager converts findings into prioritized tasks.",
            "QA audits test coverage and release confidence.",
            "Security audits exposed trust boundaries and data handling.",
            "DevOps audits build, deployment, rollback and operations."
        )
    }
    "RELEASE" {
        $roles = @("engineering-manager","qa","security","devops")
        $stages = @(
            "Engineering Manager verifies release scope and dependency closure.",
            "QA verifies acceptance and regression evidence.",
            "Security verifies applicable release gate.",
            "DevOps validates deployment and rollback readiness."
        )
    }
    "RESEARCH" {
        $roles = @("pm","cto")
        $stages = @(
            "PM frames the decision and product constraints.",
            "CTO evaluates technical options and tradeoffs.",
            "CEO uses the evidence to select the next authorized action."
        )
    }
    "DOCUMENTATION" {
        $roles = @("engineering-manager")
        $stages = @(
            "Engineering Manager identifies authoritative sources.",
            "Documentation is updated without inventing product or architecture decisions.",
            "Review verifies links, consistency and freshness."
        )
    }
}

$planDir = Join-Path $root "docs\engineering\plans"
if (-not (Test-Path $planDir)) { New-Item -ItemType Directory -Force -Path $planDir | Out-Null }
$planPath = Join-Path $planDir ($WorkRequestId + "-plan.md")
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$roleLines = ($roles | ForEach-Object { "- " + $_ }) -join [Environment]::NewLine
$stageLines = @()
for ($i = 0; $i -lt $stages.Count; $i++) { $stageLines += (($i + 1).ToString() + ". " + $stages[$i]) }

$lines = @(
    "# Orchestration Plan - $WorkRequestId",
    "",
    "Generated: $now",
    "Status: PROPOSED",
    "",
    "## Objective",
    "",
    $objective,
    "",
    "## Request Classification",
    "",
    "Type: $type",
    "Priority: $priority",
    "",
    "## Required Roles",
    "",
    $roleLines,
    "",
    "## Execution Sequence",
    "",
    ($stageLines -join [Environment]::NewLine),
    "",
    "## Context Sources",
    "",
    "- docs/engineering/project-intake.md",
    "- docs/product/product-intake.md",
    "- docs/architecture/architecture-intake.md",
    "- docs/operations/operations-intake.md",
    "- docs/PROJECT-BRIEF.md",
    "- Relevant tasks and ADRs",
    "",
    "## Dependencies",
    "",
    "- Product decisions must be resolved by PM when required.",
    "- Architecture decisions must be resolved by CTO when required.",
    "- Engineering tasks must not start before their dependencies and authorization are satisfied.",
    "",
    "## Parallelization",
    "",
    "- Only independent tasks with stable contracts may run in parallel.",
    "- Shared-file or unresolved-contract work remains sequential.",
    "",
    "## Planning Gate",
    "",
    "- This plan prepares work only.",
    "- It does not authorize implementation by itself.",
    "- Engineering Manager must create executable tasks after PM/CTO outputs are validated where applicable.",
    "",
    "## Next Action",
    "",
    "Review this plan, resolve blocking decisions, then generate executable tasks."
)

Write-Utf8NoBom $planPath ($lines -join [Environment]::NewLine)
Write-Host "Orchestration plan generated:" -ForegroundColor Green
Write-Host $planPath
Write-Host "Roles: $($roles -join ', ')"
