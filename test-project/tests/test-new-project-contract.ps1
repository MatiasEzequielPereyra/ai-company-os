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
        ".codex\managed-files.json",
        ".codex\provider-config.json",
        ".codex\local-runtime-config.json",
        ".codex\workflow-profiles.json",
        ".codex\policies\workflow-policy.md",
        ".codex\protocols\task-lifecycle.md",
        ".codex\protocols\writable-execution.md",
        ".codex\templates\ticket.md",
        "scripts\validate-artifacts.ps1",
        "scripts\new-agent-workspace.ps1",
        "scripts\run-writable-agent.ps1",
        "scripts\resolve-writable-required-files.ps1",
        "scripts\task-execution-lock.ps1",
        "scripts\provider-router.ps1",
        "scripts\providers\invoke-ollama.ps1",
        "scripts\local-runtime\detect-hardware.ps1",
        "scripts\local-runtime\resolve-local-runtime.ps1",
        "scripts\local-runtime\initialize-local-runtime.ps1",
        "scripts\local-runtime\benchmark-ollama.ps1",
        ".codex\writable-policy.json",
        "schemas\writable-change-set.schema.json",
        "schemas\task.schema.json",
        "schemas\company-state.schema.json",
        "docs\PROJECT-BRIEF.md",
        ".codex\state\company-state.json"
    )) {
        if (-not (Test-Path (Join-Path $projectPath $relative))) {
            throw "Generated project is missing required runtime artifact: $relative"
        }
    }

    $manifest = Get-Content (Join-Path $projectPath ".codex\managed-files.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $managed = @($manifest.managed_files)
    foreach ($relative in @(
        "scripts/build-agent-context.ps1",
        "scripts/run-agent-task.ps1",
        "scripts/task-execution-lock.ps1",
        "scripts/provider-router.ps1",
        "scripts/local-runtime/resolve-local-runtime.ps1",
        ".codex/provider-config.json",
        ".codex/local-runtime-config.json",
        "schemas/agent-result.schema.json",
        ".codex/agents/pm.md",
        "docs/PROJECT-BRIEF.md"
    )) {
        if ($managed -notcontains $relative) {
            throw "Generated-project managed manifest missing: $relative"
        }
    }

    $sourceValidator = Join-Path $repoRoot "scripts\validate-artifacts.ps1"
    $generatedValidator = Join-Path $projectPath "scripts\validate-artifacts.ps1"

    $sourceHash = (Get-FileHash $sourceValidator -Algorithm SHA256).Hash
    $generatedHash = (Get-FileHash $generatedValidator -Algorithm SHA256).Hash
    if ($sourceHash -ne $generatedHash) {
        throw "Generated validate-artifacts.ps1 differs from source runtime. Source=$sourceValidator Generated=$generatedValidator"
    }

    foreach ($relative in @(
        ".codex\provider-config.json",
        ".codex\local-runtime-config.json",
        "scripts\provider-router.ps1",
        "scripts\local-runtime\detect-hardware.ps1",
        "scripts\local-runtime\resolve-local-runtime.ps1",
        "scripts\local-runtime\initialize-local-runtime.ps1",
        "scripts\local-runtime\benchmark-ollama.ps1"
    )) {
        $sourcePath = Join-Path $repoRoot $relative
        $generatedPath = Join-Path $projectPath $relative

        $sourceRuntimeHash = (Get-FileHash $sourcePath -Algorithm SHA256).Hash
        $generatedRuntimeHash = (Get-FileHash $generatedPath -Algorithm SHA256).Hash

        if ($sourceRuntimeHash -ne $generatedRuntimeHash) {
            throw "Generated runtime artifact differs from source: $relative"
        }
    }

    $generatedProviderConfig = Get-Content (Join-Path $projectPath ".codex\provider-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($generatedProviderConfig.analysis_skip_local_profiles_by_role."engineering-manager") -notcontains "LOCAL_CPU_LOW") {
        throw "Generated project is missing Engineering Manager LOCAL_CPU_LOW skip policy"
    }

    $generatedLocalRuntimeConfig = Get-Content (Join-Path $projectPath ".codex\local-runtime-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $generatedLocalRuntimeConfig.profiles.LOCAL_GPU_12GB) {
        throw "Generated project is missing LOCAL_GPU_12GB hardware profile"
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
