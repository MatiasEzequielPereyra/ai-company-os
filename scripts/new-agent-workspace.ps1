param(
    [Parameter(Mandatory = $true)][string]$Id,
    [string]$ProjectPath = ".",
    [string]$BaseRef = "HEAD",
    [string]$WorkspaceRoot = ""
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path $ProjectPath).Path
if (-not (Test-Path (Join-Path $root ".git"))) { throw "Project must be a Git repository for isolated writable execution." }
if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is required for isolated writable execution." }

$taskPath = Join-Path $root ("tasks\" + $Id + ".md")
if (-not (Test-Path $taskPath)) { throw "Task not found: $taskPath" }

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path (Split-Path -Parent $root) ((Split-Path $root -Leaf) + "-worktrees")
}
if (-not (Test-Path $WorkspaceRoot)) { New-Item -ItemType Directory -Force -Path $WorkspaceRoot | Out-Null }

$branchName = "aico/" + $Id.ToLowerInvariant()
$workspacePath = Join-Path $WorkspaceRoot $Id

if (Test-Path $workspacePath) { throw "Workspace already exists: $workspacePath" }

$existingBranch = (& git -C $root branch --list $branchName 2>$null).Trim()
if (-not [string]::IsNullOrWhiteSpace($existingBranch)) {
    & git -C $root worktree add $workspacePath $branchName
}
else {
    & git -C $root worktree add -b $branchName $workspacePath $BaseRef
}
if ($LASTEXITCODE -ne 0) { throw "git worktree add failed for $Id" }

Write-Host "Isolated agent workspace created:" -ForegroundColor Green
Write-Host "Task: $Id"
Write-Host "Branch: $branchName"
Write-Host "Path: $workspacePath"
Write-Host ""
Write-Host "This workspace provides filesystem/Git isolation only. Merge, rebase, push, deployment, and destructive changes still require explicit authorization."

[PSCustomObject]@{
    TaskId = $Id
    Branch = $branchName
    Path = $workspacePath
}
