param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$helper = Join-Path $repoRoot "scripts\task-execution-lock.ps1"

if (-not (Test-Path $helper -PathType Leaf)) {
    throw "Task execution lock helper missing."
}

. $helper

$tempRoot = Join-Path $env:TEMP ("aico-task-lock-" + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".codex\runtime") | Out-Null

    $first = Enter-TaskExecutionLock -ProjectPath $tempRoot -Id "AICO-001" -Operation "ANALYSIS"

    $blocked = $false
    try {
        $second = Enter-TaskExecutionLock -ProjectPath $tempRoot -Id "AICO-001" -Operation "GATE"
        Exit-TaskExecutionLock -Lock $second
    }
    catch {
        if ($_.Exception.Message -notmatch "already has an AI Company OS execution in progress") {
            throw
        }

        $blocked = $true
    }

    if (-not $blocked) {
        throw "A second execution acquired the same task lock."
    }

    $otherTask = Enter-TaskExecutionLock -ProjectPath $tempRoot -Id "AICO-002" -Operation "ANALYSIS"
    Exit-TaskExecutionLock -Lock $otherTask

    Exit-TaskExecutionLock -Lock $first
    $first = $null

    $afterRelease = Enter-TaskExecutionLock -ProjectPath $tempRoot -Id "AICO-001" -Operation "GATE"
    Exit-TaskExecutionLock -Lock $afterRelease

    Write-Host "PASS: per-task execution lock contract" -ForegroundColor Green
}
finally {
    if ($null -ne $first) {
        Exit-TaskExecutionLock -Lock $first
    }

    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}
