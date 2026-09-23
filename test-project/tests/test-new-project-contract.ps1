param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempParent = Join-Path $env:TEMP ("aico-new-project-" + [Guid]::NewGuid().ToString("N"))
$projectName = "FixtureProject"
$projectPath = Join-Path $tempParent $projectName

try {
    New-Item -ItemType Directory -Force -Path $tempParent | Out-Null

    & (Join-Path $repoRoot "scripts\new-project.ps1") -ProjectName $projectName -Destination $tempParent

    foreach ($relative in @(
        "AGENTS.md",
        ".codex\config.toml",
        ".codex\workflow-profiles.json",
        ".codex\policies\workflow-policy.md",
        ".codex\protocols\task-lifecycle.md",
        ".codex\templates\ticket.md",
        "scripts\validate-artifacts.ps1",
        "scripts\new-agent-workspace.ps1",
        "schemas\task.schema.json",
        "schemas\company-state.schema.json",
        "docs\PROJECT-BRIEF.md",
        ".codex\state\company-state.json"
    )) {
        if (-not (Test-Path (Join-Path $projectPath $relative))) {
            throw "Generated project is missing required runtime artifact: $relative"
        }
    }

    $sourceValidator = Join-Path $repoRoot "scripts\validate-artifacts.ps1"
    $generatedValidator = Join-Path $projectPath "scripts\validate-artifacts.ps1"

    $sourceHash = (Get-FileHash $sourceValidator -Algorithm SHA256).Hash
    $generatedHash = (Get-FileHash $generatedValidator -Algorithm SHA256).Hash
    if ($sourceHash -ne $generatedHash) {
        throw "Generated validate-artifacts.ps1 differs from source runtime. Source=$sourceValidator Generated=$generatedValidator"
    }

    $sourceValidatorContent = Get-Content $sourceValidator -Raw -Encoding UTF8
    if ($sourceValidatorContent -match 'Unsupported task status in \$id:') {
        throw "Source validate-artifacts.ps1 is stale and contains the Windows PowerShell 5.1 interpolation bug. Pull the latest hardening branch."
    }

    $brief = Get-Content (Join-Path $projectPath "docs\PROJECT-BRIEF.md") -Raw -Encoding UTF8
    if ($brief -match "\{\{PROJECT_NAME\}\}|\{\{DATE\}\}") { throw "Generated project brief retained unresolved template placeholders." }
    if ($brief -notmatch [regex]::Escape($projectName)) { throw "Generated project brief did not materialize project name." }

    & (Join-Path $projectPath "scripts\validate-artifacts.ps1") -ProjectPath $projectPath | Out-Null

    Write-Host "PASS: generated project runtime contract test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempParent) { Remove-Item $tempParent -Recurse -Force }
}
