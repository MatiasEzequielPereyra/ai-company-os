param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-install-existing-" + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $tempRoot "existing-source.txt"),"preserve me",(New-Object System.Text.UTF8Encoding($false)))

    & (Join-Path $repoRoot "scripts\install-existing-project.ps1") -TargetProject $tempRoot

    foreach ($relative in @(
        "existing-source.txt",
        ".codex\workflow-profiles.json",
        ".codex\policies\workflow-policy.md",
        ".codex\protocols\task-lifecycle.md",
        ".codex\templates\ticket.md",
        "scripts\validate-artifacts.ps1",
        "scripts\new-agent-workspace.ps1",
        "scripts\run-writable-agent.ps1",
        ".codex\writable-policy.json",
        "schemas\writable-change-set.schema.json",
        "schemas\task.schema.json",
        "schemas\company-state.schema.json",
        ".codex\state\company-state.json",
        "tasks\README.md"
    )) {
        if (-not (Test-Path (Join-Path $tempRoot $relative))) {
            throw "Existing-project installation is missing required artifact: $relative"
        }
    }

    & (Join-Path $tempRoot "scripts\validate-artifacts.ps1") -ProjectPath $tempRoot | Out-Null

    $state = Get-Content (Join-Path $tempRoot ".codex\state\company-state.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$state.task_count -ne 0) { throw "Fresh existing-project install should derive zero tasks." }

    Write-Host "PASS: existing-project installation contract test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
