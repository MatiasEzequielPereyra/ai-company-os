param()

$ErrorActionPreference = "Stop"

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "SKIP: git is unavailable; writable runtime test requires Git." -ForegroundColor Yellow
    exit 0
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempParent = Join-Path $env:TEMP ("aico-writable-runtime-" + [Guid]::NewGuid().ToString("N"))
$fixtureRepo = Join-Path $tempParent "repo"
$workspaces = Join-Path $tempParent "worktrees"
$savedOpenRouter = $env:OPENROUTER_API_KEY

function Write-NoBom {
    param([string]$Path,[string]$Value)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

function New-FixtureTask {
    param([string]$Id,[string]$Status,[string]$FileName)

    $task = @(
        "# $Id - Writable fixture",
        "",
        "## Metadata",
        "",
        "ID: $Id",
        "Status: $Status",
        "Priority: P1",
        "Owner: frontend",
        "Workflow phase: PLANNING",
        "Work request: WR-TEST",
        "",
        "---",
        "",
        "## Objective",
        "",
        "Safely update $FileName.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] The requested source file is updated.",
        "- [ ] Verification passes.",
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
        "-"
    ) -join [Environment]::NewLine

    Write-NoBom (Join-Path $fixtureRepo ("tasks\" + $Id + ".md")) $task

    $dispatch = @(
        "# Execution Request - $Id",
        "",
        "## Objective",
        "",
        "Safely update $FileName.",
        "",
        "## Required Context",
        "",
        "- tasks/$Id.md",
        "- .codex/state/company-state.md",
        "",
        "## Execution Restrictions",
        "",
        "- Do not modify .env."
    ) -join [Environment]::NewLine

    Write-NoBom (Join-Path $fixtureRepo ("docs\engineering\dispatch\" + $Id + ".md")) $dispatch
    Write-NoBom (Join-Path $fixtureRepo ("src\" + $FileName)) "original"
}

function Set-FakeResult {
    param([hashtable]$Payload)
    Write-NoBom (Join-Path $fixtureRepo ".codex\fake-writable-result.json") ($Payload | ConvertTo-Json -Depth 20)
}

function Get-TaskStatus {
    param([string]$Id)
    $content = Get-Content (Join-Path $fixtureRepo ("tasks\" + $Id + ".md")) -Raw -Encoding UTF8
    $match = [regex]::Match($content,"(?m)^Status:\s*(\S+)")
    if (-not $match.Success) { throw "Task status missing for $Id" }
    return $match.Groups[1].Value.Trim()
}


function Invoke-Runner {
    param([string]$Id)

    & (Join-Path $fixtureRepo "scripts\run-writable-agent.ps1") -Id $Id -ProjectPath $fixtureRepo -WorkspacePath (Join-Path $workspaces $Id) -Provider Auto
}

try {
    foreach ($dir in @(
        "scripts",
        "tasks",
        "schemas",
        ".codex",
        ".codex\agents",
        "docs\engineering\dispatch",
        "docs\engineering\reviews",
        "src"
    )) {
        New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRepo $dir) | Out-Null
    }

    New-Item -ItemType Directory -Force -Path $workspaces | Out-Null

    foreach ($name in @(
        "run-writable-agent.ps1",
        "advance-task.ps1",
        "update-task.ps1",
        "submit-task-result.ps1",
        "build-agent-context.ps1",
        "resolve-writable-required-files.ps1"
    )) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $fixtureRepo ("scripts\" + $name)) -Force
    }

    Copy-Item (Join-Path $repoRoot "schemas\writable-change-set.schema.json") (Join-Path $fixtureRepo "schemas\writable-change-set.schema.json") -Force
    Copy-Item (Join-Path $repoRoot ".codex\writable-policy.json") (Join-Path $fixtureRepo ".codex\writable-policy.json") -Force

    $fakeRouter = @'
param(
    [string]$Provider,
    [string]$ProjectPath,
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model
)
$source = Join-Path (Split-Path -Parent $PSScriptRoot) ".codex\fake-writable-result.json"
Copy-Item $source $OutputPath -Force
[PSCustomObject]@{ Provider = $Provider; Model = $Model }
'@
    Write-NoBom (Join-Path $fixtureRepo "scripts\provider-router.ps1") $fakeRouter

    $providerConfig = @{
        auto_order = @("OpenRouter","Gemini")
        writable_auto_order = @("OpenRouter","Gemini")
        context_max_chars = 50000
        models = @{
            OpenRouter = "openrouter/free"
            Gemini = "gemini-3.5-flash-lite"
        }
        writable_models = @{
            OpenRouter = "openrouter/free"
            Gemini = "gemini-3.5-flash-lite"
        }
    } | ConvertTo-Json -Depth 10
    Write-NoBom (Join-Path $fixtureRepo ".codex\provider-config.json") $providerConfig

    Write-NoBom (Join-Path $fixtureRepo ".codex\agents\frontend.md") "Frontend fixture role."
    Write-NoBom (Join-Path $fixtureRepo "AGENTS.md") "Writable runtime fixture."
    Write-NoBom (Join-Path $fixtureRepo "package.json") '{"name":"writable-fixture","private":true}'

    New-FixtureTask -Id "AICO-001" -Status "ACTIVE" -FileName "value1.txt"
    New-FixtureTask -Id "AICO-002" -Status "ACTIVE" -FileName "value2.txt"
    New-FixtureTask -Id "AICO-003" -Status "ACTIVE" -FileName "value3.txt"
    New-FixtureTask -Id "AICO-004" -Status "READY" -FileName "value4.txt"

    Write-NoBom (Join-Path $fixtureRepo "docs\engineering\reviews\AICO-004-review-001.md") @"
# Review

Recommendation: CHANGES_REQUIRED

The prior writable implementation needs correction.
"@

    & git -C $fixtureRepo init | Out-Null
    & git -C $fixtureRepo config user.email "aico-test@example.invalid"
    & git -C $fixtureRepo config user.name "AI Company OS Test"
    & git -C $fixtureRepo add .
    & git -C $fixtureRepo commit -m "writable runtime fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fixture commit failed." }

    foreach ($id in @("AICO-001","AICO-002","AICO-003","AICO-004")) {
        & (Join-Path $repoRoot "scripts\new-agent-workspace.ps1") -Id $id -ProjectPath $fixtureRepo -WorkspaceRoot $workspaces | Out-Null
    }

    $env:OPENROUTER_API_KEY = "writable-fixture-key"

    Set-FakeResult @{
        outcome = "COMPLETED"
        summary = "Updated fixture source"
        report_markdown = "# Implementation - Safe fixture change."
        changes = @(
            @{
                path = "src/value1.txt"
                operation = "WRITE"
                content = "changed"
                reason = "Fixture implementation"
            }
        )
        verification_commands = @("git diff --check")
        verification = "Fixture verification requested"
        decisions = "NONE"
        blockers = "NONE"
        recommended_next = "REVIEW"
    }

    Invoke-Runner -Id "AICO-001"

    if ((Get-Content (Join-Path $fixtureRepo "src\value1.txt") -Raw) -ne "original") {
        throw "Writable runtime modified source in the primary checkout."
    }

    $workspaceValue = Get-Content (Join-Path $workspaces "AICO-001\src\value1.txt") -Raw
    if ($workspaceValue -ne "changed") {
        throw "Writable runtime did not apply the validated change inside the worktree."
    }

    if ((Get-TaskStatus -Id "AICO-001") -ne "REVIEW") {
        throw "Successful writable execution did not advance ACTIVE -> REVIEW."
    }

    if (-not (Test-Path (Join-Path $fixtureRepo "docs\engineering\writable-evidence\AICO-001.md"))) {
        throw "Writable execution evidence artifact was not generated."
    }

    Set-FakeResult @{
        outcome = "COMPLETED"
        summary = "Traversal attempt"
        report_markdown = "# Invalid"
        changes = @(
            @{
                path = "../escape.txt"
                operation = "WRITE"
                content = "escape"
                reason = "Should be rejected"
            }
        )
        verification_commands = @("git diff --check")
        verification = "NONE"
        decisions = "NONE"
        blockers = "NONE"
        recommended_next = "REVIEW"
    }

    $traversalRejected = $false
    try {
        Invoke-Runner -Id "AICO-002"
    }
    catch {
        if ($_.Exception.Message -match "cannot contain|escapes the task worktree") {
            $traversalRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $traversalRejected) { throw "Writable runtime accepted path traversal." }
    if (Test-Path (Join-Path $tempParent "escape.txt")) { throw "Traversal attempt created a file outside the worktree." }

    Set-FakeResult @{
        outcome = "COMPLETED"
        summary = "Command injection attempt"
        report_markdown = "# Invalid verification"
        changes = @(
            @{
                path = "src/value3.txt"
                operation = "WRITE"
                content = "should-roll-back"
                reason = "Fixture"
            }
        )
        verification_commands = @("git diff --check; git status --short")
        verification = "NONE"
        decisions = "NONE"
        blockers = "NONE"
        recommended_next = "REVIEW"
    }

    $commandRejected = $false
    try {
        Invoke-Runner -Id "AICO-003"
    }
    catch {
        if ($_.Exception.Message -match "not allowed by writable policy|exactly one simple command|pipelines are prohibited") {
            $commandRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $commandRejected) { throw "Writable runtime accepted command composition." }

    $rolledBack = Get-Content (Join-Path $workspaces "AICO-003\src\value3.txt") -Raw
    if ($rolledBack -ne "original") {
        throw "Rejected writable execution did not restore the planned file."
    }

    $task3Status = Get-TaskStatus -Id "AICO-003"
    if ($task3Status -ne "ACTIVE") {
        throw ("Rejected writable execution should leave task ACTIVE. Actual: " + $task3Status)
    }

    Write-NoBom (Join-Path $workspaces "AICO-004\src\value4.txt") "prior-rejected-change"

    Set-FakeResult @{
        outcome = "COMPLETED"
        summary = "Corrected rejected implementation"
        report_markdown = "# Correction"
        changes = @(
            @{
                path = "src/value4.txt"
                operation = "WRITE"
                content = "corrected"
                reason = "Address CHANGES_REQUIRED"
            }
        )
        verification_commands = @("git diff --check")
        verification = "Correction verified"
        decisions = "NONE"
        blockers = "NONE"
        recommended_next = "REVIEW"
    }

    Invoke-Runner -Id "AICO-004"

    $task4Status = Get-TaskStatus -Id "AICO-004"
    if ($task4Status -ne "REVIEW") {
        throw ("Corrective writable execution did not complete READY -> ACTIVE -> REVIEW. Actual: " + $task4Status)
    }

    $corrected = Get-Content (Join-Path $workspaces "AICO-004\src\value4.txt") -Raw
    if ($corrected -ne "corrected") {
        throw "Corrective writable execution did not update the existing worktree diff."
    }

    Write-Host "PASS: isolated writable agent runtime" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedOpenRouter

    if (Test-Path $fixtureRepo) {
        foreach ($id in @("AICO-001","AICO-002","AICO-003","AICO-004")) {
            $workspace = Join-Path $workspaces $id
            if (Test-Path $workspace) {
                try { & git -C $fixtureRepo worktree remove $workspace --force 2>$null | Out-Null } catch {}
            }
        }
        try { & git -C $fixtureRepo worktree prune 2>$null | Out-Null } catch {}
    }

    if (Test-Path $tempParent) {
        Remove-Item $tempParent -Recurse -Force -ErrorAction SilentlyContinue
    }
}
