param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-gate-artifact-identity-" + [Guid]::NewGuid().ToString("N"))

function Write-NoBom {
    param([string]$Path,[string]$Value)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

function Read-TaskStatus {
    param([string]$TaskPath)
    $content = Get-Content $TaskPath -Raw -Encoding UTF8
    $match = [regex]::Match($content,"(?m)^Status:\s*(\S+)")
    if (-not $match.Success) { throw "Task status missing." }
    return $match.Groups[1].Value.Trim()
}

try {
    foreach ($dir in @(
        "scripts",
        "schemas",
        "tasks",
        ".codex",
        ".codex\agents",
        "docs\engineering\agent-reports",
        "docs\engineering\results",
        "docs\engineering\reviews",
        "docs\engineering\dispatch"
    )) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $dir) | Out-Null
    }

    foreach ($name in @("run-gate-agent.ps1","review-task.ps1","update-task.ps1","advance-task.ps1")) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $tempRoot ("scripts\" + $name)) -Force
    }

    Copy-Item (Join-Path $repoRoot "schemas\review-result.schema.json") (Join-Path $tempRoot "schemas\review-result.schema.json") -Force

    $task = @(
        "# AICO-001 - Gate artifact identity fixture",
        "",
        "## Metadata",
        "",
        "ID: AICO-001",
        "Status: REVIEW",
        "Priority: P1",
        "Owner: pm",
        "Workflow phase: CODE_REVIEW",
        "Work kind: PLANNING",
        "Work request: WR-001",
        "",
        "---",
        "",
        "## Objective",
        "",
        "Produce and verify the PM role-owned deliverable.",
        "",
        "---",
        "",
        "## Context",
        "",
        "- Gate artifact identity regression fixture.",
        "",
        "---",
        "",
        "## Requirements",
        "",
        "- Produce the role-owned report.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] Role-owned deliverable is produced.",
        "- [ ] Evidence is recorded in this task.",
        "",
        "---",
        "",
        "## Dependencies",
        "",
        "-",
        "",
        "---",
        "",
        "## Testing Requirements",
        "",
        "- Verify the explicit report artifact.",
        "",
        "---",
        "",
        "## Evidence",
        "",
        "- Result submitted: docs/engineering/results/AICO-001-result-001.md",
        "",
        "---",
        "",
        "## Handoff",
        "",
        "Next agent: engineering-manager",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "- 2026-09-25T00:00:00Z - pm - ACTIVE -> REVIEW - Fixture result submitted.",
        "",
        "---",
        "",
        "## Notes",
        "",
        "-"
    ) -join [Environment]::NewLine

    $taskPath = Join-Path $tempRoot "tasks\AICO-001.md"
    Write-NoBom $taskPath $task

    Write-NoBom (Join-Path $tempRoot ".codex\agents\engineering-manager.md") "Engineering manager fixture."

    $reportRelative = "docs/engineering/agent-reports/AICO-001.md"
    $reportContent = @(
        "# Agent Report - AICO-001",
        "",
        "Owner: pm",
        "Outcome: COMPLETED",
        "",
        "Verified product-scope deliverable for the artifact identity regression."
    ) -join [Environment]::NewLine
    Write-NoBom (Join-Path $tempRoot ($reportRelative.Replace("/","\"))) $reportContent

    $resultContent = @(
        "# Task Result - AICO-001",
        "",
        "Outcome: COMPLETED",
        "Changed artifacts: $reportRelative",
        "",
        "The PM deliverable was written to the canonical report artifact."
    ) -join [Environment]::NewLine
    Write-NoBom (Join-Path $tempRoot "docs\engineering\results\AICO-001-result-001.md") $resultContent

    $fakeContextBuilder = @'
param(
    [string]$ProjectPath,
    [string]$Id,
    [string]$Owner,
    [int]$MaxChars
)

@"
===== TASK =====
Task: $Id
Owner: $Owner

===== GENERIC REPOSITORY INVENTORY =====
docs/engineering/results/AICO-001-result-001.md
tasks/AICO-001.md

NOTE: docs/engineering/agent-reports is intentionally excluded from the generic inventory.
"@
'@
    Write-NoBom (Join-Path $tempRoot "scripts\build-agent-context.ps1") $fakeContextBuilder

    $fakeRouter = @'
param(
    [string]$Provider,
    [string]$ProjectPath,
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [string]$Role,
    [string]$Workload
)

$canonical = "docs/engineering/agent-reports/AICO-001.md"

$hasCanonicalIdentity = (
    $Context -match [regex]::Escape("Repository-relative path: " + $canonical)
)

$hasExplicitReport = (
    $Context -match [regex]::Escape("Verified product-scope deliverable for the artifact identity regression.")
)

$hasResultReference = (
    $Context -match [regex]::Escape("Changed artifacts: " + $canonical)
)

$promptAuthorizesExplicitEvidence = (
    $Prompt -match "(?i)explicit gate artifacts" -and
    $Prompt -match "(?i)authoritative" -and
    $Prompt -match "(?i)generic repository inventory"
)

$approved = (
    $hasCanonicalIdentity -and
    $hasExplicitReport -and
    $hasResultReference -and
    $promptAuthorizesExplicitEvidence
)

$payload = @{
    recommendation = $(if ($approved) { "APPROVE" } else { "CHANGES_REQUIRED" })
    findings = $(if ($approved) {
        "Explicit gate artifact identity verified from its canonical repository-relative path."
    } else {
        "Gate could not correlate the result reference with the explicit primary report artifact."
    })
    verification = $(if ($approved) {
        "Canonical explicit artifact path and referenced result agree."
    } else {
        "Canonical explicit artifact identity or authority instruction is missing."
    })
} | ConvertTo-Json -Depth 10

[System.IO.File]::WriteAllText(
    $OutputPath,
    $payload,
    (New-Object System.Text.UTF8Encoding($false))
)

[PSCustomObject]@{
    Provider = "Fixture"
    Model = "deterministic"
}
'@
    Write-NoBom (Join-Path $tempRoot "scripts\provider-router.ps1") $fakeRouter

    & (Join-Path $tempRoot "scripts\run-gate-agent.ps1") -Id "AICO-001" -Gate Review -ProjectPath $tempRoot -Provider OpenRouter

    $status = Read-TaskStatus -TaskPath $taskPath
    if ($status -ne "QA") {
        $review = Get-ChildItem (Join-Path $tempRoot "docs\engineering\reviews") -Filter "AICO-001-review-*.md" -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        $reviewText = if ($null -ne $review) { Get-Content $review.FullName -Raw -Encoding UTF8 } else { "No review artifact." }
        throw ("Review could not verify the existing explicit report artifact. Status=" + $status + [Environment]::NewLine + $reviewText)
    }

    $reviewArtifact = Get-ChildItem (Join-Path $tempRoot "docs\engineering\reviews") -Filter "AICO-001-review-*.md" -File | Sort-Object Name -Descending | Select-Object -First 1
    if ($null -eq $reviewArtifact) { throw "Review artifact was not generated." }

    $reviewContent = Get-Content $reviewArtifact.FullName -Raw -Encoding UTF8
    if ($reviewContent -notmatch "(?m)^Recommendation:\s*APPROVE$") {
        throw "Review did not approve the verifiable explicit report artifact."
    }

    Write-Host "PASS: explicit gate artifact canonical identity regression" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
