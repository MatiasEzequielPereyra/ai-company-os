param()

$ErrorActionPreference = "Stop"

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "SKIP: git is unavailable; writable authorization guard test requires Git." -ForegroundColor Yellow
    exit 0
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempParent = Join-Path $env:TEMP ("aico-writable-auth-" + [Guid]::NewGuid().ToString("N"))
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
    param(
        [string]$Id,
        [string]$Status,
        [AllowEmptyString()][string]$WorkKind,
        [string]$FileName
    )

    $metadata = @(
        "ID: $Id",
        "Status: $Status",
        "Priority: P1",
        "Owner: frontend",
        "Workflow phase: IMPLEMENTATION"
    )

    if (-not [string]::IsNullOrWhiteSpace($WorkKind)) {
        $metadata += "Work kind: $WorkKind"
    }

    $metadata += "Work request: WR-AUTH"

    $task = @(
        "# $Id - Writable authorization fixture",
        "",
        "## Metadata",
        ""
    ) + $metadata + @(
        "",
        "---",
        "",
        "## Objective",
        "",
        "Safely update $FileName.",
        "",
        "---",
        "",
        "## Context",
        "",
        "Authorization regression fixture.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] The requested source file is updated.",
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
    )

    Write-NoBom (Join-Path $fixtureRepo ("tasks\" + $Id + ".md")) ($task -join [Environment]::NewLine)

    $dispatch = @(
        "# Execution Request - $Id",
        "",
        "Task: $Id",
        "Owner: frontend",
        "",
        "## Objective",
        "",
        "Safely update $FileName.",
        "",
        "## Required Context",
        "",
        "- tasks/$Id.md",
        "",
        "## Acceptance Criteria",
        "",
        "- Requested file is updated.",
        "",
        "## Testing Requirements",
        "",
        "- git diff --check"
    ) -join [Environment]::NewLine

    Write-NoBom (Join-Path $fixtureRepo ("docs\engineering\dispatch\" + $Id + ".md")) $dispatch
    Write-NoBom (Join-Path $fixtureRepo ("src\" + $FileName)) "original"
}

function Get-TaskContent {
    param([string]$Id)
    return Get-Content (Join-Path $fixtureRepo ("tasks\" + $Id + ".md")) -Raw -Encoding UTF8
}

function Get-TaskStatus {
    param([string]$Id)
    $content = Get-TaskContent -Id $Id
    $match = [regex]::Match($content,"(?m)^Status:\s*(\S+)")
    if (-not $match.Success) { throw "Task status missing for $Id" }
    return $match.Groups[1].Value.Trim()
}

function Add-DirectWorkspace {
    param([string]$Id)
    $workspace = Join-Path $workspaces $Id
    $branch = "aico/" + $Id.ToLowerInvariant()
    & git -C $fixtureRepo worktree add -b $branch $workspace HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to create direct test worktree for $Id" }
    return $workspace
}

function Assert-WritableRejected {
    param([string]$Id,[string]$Workspace)

    $taskPath = Join-Path $fixtureRepo ("tasks\" + $Id + ".md")
    $beforeBytes = [System.IO.File]::ReadAllBytes($taskPath)
    $beforeStatus = Get-TaskStatus -Id $Id
    $providerMarker = Join-Path $fixtureRepo ".codex\provider-called.txt"
    Remove-Item $providerMarker -Force -ErrorAction SilentlyContinue

    $rejected = $false
    try {
        & (Join-Path $fixtureRepo "scripts\run-writable-agent.ps1") -Id $Id -ProjectPath $fixtureRepo -WorkspacePath $Workspace -Provider Auto
    }
    catch {
        if ($_.Exception.Message -match "writable execution requires Work kind IMPLEMENTATION") { $rejected = $true } else { throw }
    }

    if (-not $rejected) { throw "${Id}: unauthorized writable execution was not rejected." }

    $afterBytes = [System.IO.File]::ReadAllBytes($taskPath)
    if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$beforeBytes,[byte[]]$afterBytes)) {
        throw "${Id}: rejection modified the canonical task file."
    }

    $afterStatus = Get-TaskStatus -Id $Id
    if ($afterStatus -ne $beforeStatus) { throw "${Id}: rejection changed task status from $beforeStatus to $afterStatus." }

    if (Test-Path $providerMarker) { throw "${Id}: provider was invoked before writable authorization was validated." }

    $evidencePath = Join-Path $fixtureRepo ("docs\engineering\writable-evidence\" + $Id + ".md")
    if (Test-Path $evidencePath) { throw "${Id}: rejection created writable evidence." }

    $workspaceStatus = @(& git -C $Workspace status --porcelain)
    if (@($workspaceStatus).Count -gt 0) { throw "${Id}: rejection modified the writable worktree." }
}

try {
    foreach ($dir in @("scripts","tasks","schemas",".codex",".codex\agents","docs\engineering\dispatch","docs\engineering\reviews","src")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRepo $dir) | Out-Null
    }

    New-Item -ItemType Directory -Force -Path $workspaces | Out-Null

    foreach ($name in @("run-writable-agent.ps1","new-agent-workspace.ps1","advance-task.ps1","update-task.ps1","submit-task-result.ps1","build-agent-context.ps1","resolve-writable-required-files.ps1")) {
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
$marker = Join-Path $ProjectPath ".codex\provider-called.txt"
[System.IO.File]::WriteAllText($marker,"called",(New-Object System.Text.UTF8Encoding($false)))
$payload = @{
    outcome = "COMPLETED"
    summary = "Authorized implementation"
    report_markdown = "# Authorized implementation"
    changes = @(
        @{
            path = "src/implementation.txt"
            operation = "WRITE"
            content = "changed"
            reason = "Authorization regression fixture"
        }
    )
    verification_commands = @("git diff --check")
    verification = "git diff --check"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
} | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($OutputPath,$payload,(New-Object System.Text.UTF8Encoding($false)))
[PSCustomObject]@{ Provider = "OpenRouter"; Model = $Model }
'@
    Write-NoBom (Join-Path $fixtureRepo "scripts\provider-router.ps1") $fakeRouter

    $providerConfig = @{
        writable_auto_order = @("OpenRouter")
        writable_context_max_chars = 50000
        writable_models = @{ OpenRouter = "openrouter/free" }
        models = @{ OpenRouter = "openrouter/free" }
    } | ConvertTo-Json -Depth 10

    Write-NoBom (Join-Path $fixtureRepo ".codex\provider-config.json") $providerConfig
    Write-NoBom (Join-Path $fixtureRepo ".codex\agents\frontend.md") "Frontend fixture role."
    Write-NoBom (Join-Path $fixtureRepo "AGENTS.md") "Writable authorization fixture."

    New-FixtureTask -Id "AICO-101" -Status "READY"  -WorkKind "PLANNING"       -FileName "planning-ready.txt"
    New-FixtureTask -Id "AICO-102" -Status "ACTIVE" -WorkKind "PLANNING"       -FileName "planning-active.txt"
    New-FixtureTask -Id "AICO-103" -Status "READY"  -WorkKind ""               -FileName "missing-kind.txt"
    New-FixtureTask -Id "AICO-104" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "implementation.txt"

    & git -C $fixtureRepo init | Out-Null
    & git -C $fixtureRepo config user.email "aico-test@example.invalid"
    & git -C $fixtureRepo config user.name "AI Company OS Test"
    & git -C $fixtureRepo add .
    & git -C $fixtureRepo commit -m "writable authorization fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fixture commit failed." }

    $planningReadyWorkspace = Add-DirectWorkspace -Id "AICO-101"
    $planningActiveWorkspace = Add-DirectWorkspace -Id "AICO-102"
    $missingKindWorkspace = Add-DirectWorkspace -Id "AICO-103"

    $workspaceCreationRejected = $false
    try {
        & (Join-Path $fixtureRepo "scripts\new-agent-workspace.ps1") -Id "AICO-101" -ProjectPath $fixtureRepo -WorkspaceRoot (Join-Path $tempParent "unauthorized-workspaces") | Out-Null
    }
    catch {
        if ($_.Exception.Message -match "Work kind IMPLEMENTATION") { $workspaceCreationRejected = $true } else { throw }
    }

    if (-not $workspaceCreationRejected) { throw "new-agent-workspace.ps1 accepted a PLANNING task." }

    Assert-WritableRejected -Id "AICO-101" -Workspace $planningReadyWorkspace
    Assert-WritableRejected -Id "AICO-102" -Workspace $planningActiveWorkspace
    Assert-WritableRejected -Id "AICO-103" -Workspace $missingKindWorkspace

    $implementationWorkspaceRoot = Join-Path $tempParent "implementation-workspaces"
    & (Join-Path $fixtureRepo "scripts\new-agent-workspace.ps1") -Id "AICO-104" -ProjectPath $fixtureRepo -WorkspaceRoot $implementationWorkspaceRoot | Out-Null

    $implementationWorkspace = Join-Path $implementationWorkspaceRoot "AICO-104"
    if (-not (Test-Path $implementationWorkspace)) { throw "IMPLEMENTATION READY task could not create an isolated writable workspace." }

    $env:OPENROUTER_API_KEY = "writable-auth-test-key"

    & (Join-Path $fixtureRepo "scripts\run-writable-agent.ps1") -Id "AICO-104" -ProjectPath $fixtureRepo -WorkspacePath $implementationWorkspace -Provider Auto

    if ((Get-TaskStatus -Id "AICO-104") -ne "REVIEW") {
        throw "Authorized IMPLEMENTATION READY task did not complete READY -> ACTIVE -> REVIEW."
    }

    $implementationValue = Get-Content (Join-Path $implementationWorkspace "src\implementation.txt") -Raw
    if ($implementationValue -ne "changed") { throw "Authorized IMPLEMENTATION task did not apply the writable change." }

    if (-not (Test-Path (Join-Path $fixtureRepo "docs\engineering\writable-evidence\AICO-104.md"))) {
        throw "Authorized IMPLEMENTATION task did not create writable evidence."
    }

    Write-Host "PASS: writable lower-layer authorization guard" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedOpenRouter

    if (Test-Path $fixtureRepo) {
        foreach ($candidate in @(
            (Join-Path $workspaces "AICO-101"),
            (Join-Path $workspaces "AICO-102"),
            (Join-Path $workspaces "AICO-103"),
            (Join-Path $tempParent "implementation-workspaces\AICO-104")
        )) {
            if (Test-Path $candidate) {
                try { & git -C $fixtureRepo worktree remove $candidate --force 2>$null | Out-Null } catch {}
            }
        }
        try { & git -C $fixtureRepo worktree prune 2>$null | Out-Null } catch {}
    }

    if (Test-Path $tempParent) { Remove-Item $tempParent -Recurse -Force -ErrorAction SilentlyContinue }
}
