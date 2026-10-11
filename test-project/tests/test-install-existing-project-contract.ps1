param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-install-existing-" + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $tempRoot "existing-source.txt"),"preserve me",(New-Object System.Text.UTF8Encoding($false)))

    $preexistingScriptsDir = Join-Path $tempRoot "scripts"
    New-Item -ItemType Directory -Force -Path $preexistingScriptsDir | Out-Null
    $preexistingSyncPath = Join-Path $preexistingScriptsDir "sync-company-state.ps1"
    $preexistingSyncMarker = Join-Path $tempRoot "preexisting-sync-executed.txt"
    $preexistingSyncContent = @'
[System.IO.File]::WriteAllText(
    (Join-Path $PSScriptRoot "..\preexisting-sync-executed.txt"),
    "executed"
)
'@
    [System.IO.File]::WriteAllText(
        $preexistingSyncPath,
        $preexistingSyncContent,
        (New-Object System.Text.UTF8Encoding($false))
    )
    $preexistingSyncHashBefore = (Get-FileHash $preexistingSyncPath -Algorithm SHA256).Hash

    & (Join-Path $repoRoot "scripts\install-existing-project.ps1") -TargetProject $tempRoot

    if (Test-Path $preexistingSyncMarker) {
        throw "Existing-project installer executed a pre-existing project-owned sync-company-state.ps1."
    }

    $preexistingSyncHashAfter = (Get-FileHash $preexistingSyncPath -Algorithm SHA256).Hash
    if ($preexistingSyncHashAfter -ne $preexistingSyncHashBefore) {
        throw "Existing-project installer modified a pre-existing project-owned sync-company-state.ps1."
    }

    foreach ($relative in @(
        "existing-source.txt",
        ".codex\managed-files.json",
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
        "scripts\validate-engineering-plan-result.ps1",
        "scripts\validate-analysis-result-semantics.ps1",
        "scripts\build-corrective-analysis-context.ps1",
        "scripts\validate-engineering-backlog-semantics.ps1",
        "scripts\validate-gate-result-semantics.ps1",
        ".codex\writable-policy.json",
        ".codex\local-runtime-config.json",
        "scripts\local-runtime\detect-hardware.ps1",
        "scripts\local-runtime\resolve-local-runtime.ps1",
        "scripts\local-runtime\initialize-local-runtime.ps1",
        "scripts\local-runtime\benchmark-ollama.ps1",
        "schemas\engineering-plan-result.schema.json",
        "schemas\writable-change-set.schema.json",
        "schemas\writable-bug-change-set.schema.json",
        "schemas\diagnostic-evidence.schema.json",
        "scripts\validate-diagnostic-evidence.ps1",
        ".agents\skills\bug\SKILL.md",
        "schemas\task.schema.json",
        "schemas\company-state.schema.json",
        ".codex\state\company-state.json",
        "tasks\README.md"
    )) {
        if (-not (Test-Path (Join-Path $tempRoot $relative))) {
            throw "Existing-project installation is missing required artifact: $relative"
        }
    }

    $manifest = Get-Content (Join-Path $tempRoot ".codex\managed-files.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $managed = @($manifest.managed_files)
    foreach ($relative in @(
        "scripts/build-agent-context.ps1",
        "scripts/run-agent-task.ps1",
        "scripts/task-execution-lock.ps1",
        "schemas/agent-result.schema.json",
        "schemas/engineering-plan-result.schema.json",
        ".codex/agents/pm.md",
        ".codex/local-runtime-config.json",
        "scripts/local-runtime/detect-hardware.ps1",
        "scripts/local-runtime/resolve-local-runtime.ps1",
        "scripts/local-runtime/initialize-local-runtime.ps1",
        "scripts/local-runtime/benchmark-ollama.ps1"
    )) {
        if ($managed -notcontains $relative) {
            throw "Existing-project managed manifest missing: $relative"
        }
    }
    if ($managed -contains "existing-source.txt") {
        throw "Existing client files must never be claimed as AI Company OS-managed"
    }
    if ($managed -contains "scripts/sync-company-state.ps1") {
        throw "Skipped pre-existing sync-company-state.ps1 must remain project-owned and unmanaged."
    }

    & (Join-Path $tempRoot "scripts\validate-artifacts.ps1") -ProjectPath $tempRoot | Out-Null

    $state = Get-Content (Join-Path $tempRoot ".codex\state\company-state.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$state.task_count -ne 0) { throw "Fresh existing-project install should derive zero tasks." }

    Write-Host "PASS: existing-project installation contract test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
