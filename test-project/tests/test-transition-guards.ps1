param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$advanceSource = Join-Path $repoRoot "scripts\advance-task.ps1"

if (-not (Test-Path $advanceSource)) {
    throw "advance-task.ps1 missing"
}

$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $advanceSource,
    [ref]$null,
    [ref]$parseErrors
)

if ($parseErrors.Count -gt 0) {
    throw ("advance-task.ps1 has PowerShell parse errors: " + (($parseErrors | ForEach-Object { $_.Message }) -join "; "))
}

$tempRoot = Join-Path $env:TEMP ("aico-transition-guards-" + [Guid]::NewGuid().ToString("N"))

function Expect-Failure {
    param([scriptblock]$Action,[string]$Contains)

    $failed = $false

    try {
        & $Action
    }
    catch {
        $failed = $true
        if ($_.Exception.Message -notmatch [regex]::Escape($Contains)) {
            throw "Expected failure containing '$Contains', got: $($_.Exception.Message)"
        }
    }

    if (-not $failed) {
        throw "Expected guarded transition to fail: $Contains"
    }
}

try {
    foreach ($dir in @(
        "scripts",
        "tasks",
        "docs\engineering\dispatch",
        "docs\engineering\results",
        "docs\engineering\reviews",
        "docs\engineering\qa",
        "docs\engineering\security",
        "docs\engineering\final-approvals"
    )) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $dir) | Out-Null
    }

    $task = @(
        "# AICO-001 - Guard fixture",
        "",
        "## Metadata",
        "",
        "ID: AICO-001",
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
        "---",
        "",
        "## Objective",
        "",
        "Verify guarded lifecycle transitions.",
        "",
        "---",
        "",
        "## Context",
        "",
        "Regression fixture.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] Guarded transitions require evidence.",
        "",
        "---",
        "",
        "## Dependencies",
        "",
        "-",
        "",
        "---",
        "",
        "## Evidence",
        "",
        "-",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "-",
        ""
    ) -join [Environment]::NewLine

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "tasks\AICO-001.md"),
        $task,
        (New-Object System.Text.UTF8Encoding($false))
    )

    # Invoke the repository script against an external absolute TasksPath.
    # This verifies evidence paths resolve from the task project, not from PSScriptRoot.
    $advance = $advanceSource

    & $advance -Id AICO-001 -Status READY -TasksPath (Join-Path $tempRoot "tasks")

    Expect-Failure {
        & $advance -Id AICO-001 -Status ACTIVE -TasksPath (Join-Path $tempRoot "tasks")
    } "cannot become ACTIVE without a prepared dispatch packet"

    Set-Content -Path (Join-Path $tempRoot "docs\engineering\dispatch\AICO-001.md") -Encoding UTF8 -Value "# Dispatch"
    & $advance -Id AICO-001 -Status ACTIVE -TasksPath (Join-Path $tempRoot "tasks")

    Expect-Failure {
        & $advance -Id AICO-001 -Status REVIEW -TasksPath (Join-Path $tempRoot "tasks")
    } "cannot enter REVIEW without a task result artifact"

    Set-Content -Path (Join-Path $tempRoot "docs\engineering\results\AICO-001-result-001.md") -Encoding UTF8 -Value @"
# Result
Outcome: COMPLETED
"@
    & $advance -Id AICO-001 -Status REVIEW -TasksPath (Join-Path $tempRoot "tasks")

    Expect-Failure {
        & $advance -Id AICO-001 -Status QA -TasksPath (Join-Path $tempRoot "tasks")
    } "cannot enter QA without a review artifact"

    Set-Content -Path (Join-Path $tempRoot "docs\engineering\reviews\AICO-001-review-001.md") -Encoding UTF8 -Value @"
# Review
Recommendation: APPROVE
"@
    & $advance -Id AICO-001 -Status QA -TasksPath (Join-Path $tempRoot "tasks")

    Expect-Failure {
        & $advance -Id AICO-001 -Status SECURITY -TasksPath (Join-Path $tempRoot "tasks")
    } "required QA artifact is missing"

    Set-Content -Path (Join-Path $tempRoot "docs\engineering\qa\AICO-001-qa.md") -Encoding UTF8 -Value @"
# QA
Outcome: PASS
"@
    & $advance -Id AICO-001 -Status SECURITY -TasksPath (Join-Path $tempRoot "tasks")

    Set-Content -Path (Join-Path $tempRoot "docs\engineering\security\AICO-001-security.md") -Encoding UTF8 -Value @"
# Security
Outcome: PASS
"@

    Expect-Failure {
        & $advance -Id AICO-001 -Status DONE -TasksPath (Join-Path $tempRoot "tasks")
    } "required final approval artifact is missing"

    Set-Content -Path (Join-Path $tempRoot "docs\engineering\final-approvals\AICO-001-final.md") -Encoding UTF8 -Value @"
# Final
Decision: APPROVE
"@
    & $advance -Id AICO-001 -Status DONE -TasksPath (Join-Path $tempRoot "tasks")

    $finalTask = Get-Content (Join-Path $tempRoot "tasks\AICO-001.md") -Raw -Encoding UTF8
    if ($finalTask -notmatch '(?m)^Status:\s*DONE\s*$') {
        throw "Legitimate guarded lifecycle did not reach DONE."
    }
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}

Write-Host "PASS: lifecycle transition guard test" -ForegroundColor Green
