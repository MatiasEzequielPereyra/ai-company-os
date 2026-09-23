param()

$ErrorActionPreference = "Stop"

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "SKIP: git is unavailable; worktree isolation test requires Git." -ForegroundColor Yellow
    exit 0
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempParent = Join-Path $env:TEMP ("aico-worktree-" + [Guid]::NewGuid().ToString("N"))
$fixtureRepo = Join-Path $tempParent "repo"
$workspaces = Join-Path $tempParent "worktrees"
$workspace = Join-Path $workspaces "AICO-001"

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRepo "tasks") | Out-Null
    New-Item -ItemType Directory -Force -Path $workspaces | Out-Null

    & git -C $fixtureRepo init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git init failed." }
    & git -C $fixtureRepo config user.email "aico-test@example.invalid"
    & git -C $fixtureRepo config user.name "AI Company OS Test"

    $task = @(
        "# AICO-001 - Isolation fixture",
        "",
        "ID: AICO-001",
        "Status: ACTIVE"
    ) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText((Join-Path $fixtureRepo "tasks\AICO-001.md"),$task,(New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $fixtureRepo "README.md"),"fixture",(New-Object System.Text.UTF8Encoding($false)))

    & git -C $fixtureRepo add .
    & git -C $fixtureRepo commit -m "fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fixture commit failed." }

    $result = & (Join-Path $repoRoot "scripts\new-agent-workspace.ps1") -Id AICO-001 -ProjectPath $fixtureRepo -WorkspaceRoot $workspaces

    if (-not (Test-Path $workspace)) { throw "Isolated worktree was not created." }
    $branch = (& git -C $workspace branch --show-current).Trim()
    if ($branch -ne "aico/aico-001") { throw "Unexpected isolated branch: $branch" }

    [System.IO.File]::WriteAllText((Join-Path $workspace "isolated-change.txt"),"worktree only",(New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path (Join-Path $fixtureRepo "isolated-change.txt")) { throw "Writable worktree change leaked into the primary checkout." }

    if ([string]$result.Path -ne $workspace) { throw "Workspace helper returned an unexpected path." }

    Write-Host "PASS: writable agent worktree isolation test" -ForegroundColor Green
}
finally {
    if (Test-Path $fixtureRepo) {
        & git -C $fixtureRepo worktree remove $workspace --force 2>$null | Out-Null
    }
    if (Test-Path $tempParent) { Remove-Item $tempParent -Recurse -Force }
}
