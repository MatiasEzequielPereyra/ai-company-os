param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-update-runtime-" + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".codex") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "tasks") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts") | Out-Null

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "app-source.txt"),
        "preserve app source",
        (New-Object System.Text.UTF8Encoding($false))
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "tasks\AICO-999.md"),
        "preserve task",
        (New-Object System.Text.UTF8Encoding($false))
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "docs\project-note.md"),
        "preserve docs",
        (New-Object System.Text.UTF8Encoding($false))
    )

    $oldConfig = @{
        auto_order = @("OpenRouter","Gemini")
        models = @{
            OpenRouter = "custom/openrouter-model"
        }
        writable_auto_order = @("OpenRouter")
        writable_models = @{
            OpenRouter = "custom/writable-model"
        }
        analysis_context_max_chars_by_role = @{
            pm = 65000
        }
        provider_timeout_seconds = @{
            OpenRouter = 333
        }
    } | ConvertTo-Json -Depth 10

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot ".codex\provider-config.json"),
        $oldConfig,
        (New-Object System.Text.UTF8Encoding($false))
    )

    & (Join-Path $repoRoot "scripts\update-runtime.ps1") -TargetProject $tempRoot

    foreach ($relative in @(
        "scripts\provider-router.ps1",
        "scripts\run-agent-task.ps1",
        "scripts\run-gate-agent.ps1",
        "scripts\run-writable-agent.ps1",
        "scripts\update-runtime.ps1",
        "scripts\task-execution-lock.ps1",
        "scripts\local-runtime\resolve-local-runtime.ps1",
        "scripts\local-runtime\detect-hardware.ps1",
        "scripts\providers\invoke-ollama.ps1",
        ".codex\local-runtime-config.json",
        ".codex\writable-policy.json",
        ".codex\managed-files.json"
    )) {
        if (-not (Test-Path (Join-Path $tempRoot $relative))) {
            throw "Runtime upgrade is missing required artifact: $relative"
        }
    }

    if ((Get-Content (Join-Path $tempRoot "app-source.txt") -Raw) -ne "preserve app source") {
        throw "Runtime upgrade modified project source."
    }
    if ((Get-Content (Join-Path $tempRoot "tasks\AICO-999.md") -Raw) -ne "preserve task") {
        throw "Runtime upgrade modified tasks."
    }
    if ((Get-Content (Join-Path $tempRoot "docs\project-note.md") -Raw) -ne "preserve docs") {
        throw "Runtime upgrade modified docs."
    }

    $config = Get-Content (Join-Path $tempRoot ".codex\provider-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json

    if (@($config.auto_order)[0] -ne "Ollama") {
        throw "Runtime upgrade must prepend Ollama to Auto routing."
    }
    if (@($config.writable_auto_order)[0] -ne "Ollama") {
        throw "Runtime upgrade must prepend Ollama to writable Auto routing."
    }
    if ([string]$config.models.OpenRouter -ne "custom/openrouter-model") {
        throw "Runtime upgrade must preserve existing provider model overrides."
    }
    if ([string]$config.writable_models.OpenRouter -ne "custom/writable-model") {
        throw "Runtime upgrade must preserve existing writable model overrides."
    }
    if ([string]$config.models.Ollama -ne "llama3.1:8b") {
        throw "Runtime upgrade must add the local Ollama baseline."
    }
    if ([bool]$config.allow_paid_fallback -ne $false) {
        throw "Runtime upgrade must keep paid fallback disabled by default."
    }

    if ([int]$config.analysis_context_max_chars -ne 120000) {
        throw "Runtime upgrade must add the bounded analysis context budget."
    }
    if ([int]$config.analysis_context_max_chars_by_role.pm -ne 65000) {
        throw "Runtime upgrade must preserve existing role-specific context overrides."
    }
    if ([int]$config.analysis_context_max_chars_by_role.cto -ne 110000) {
        throw "Runtime upgrade must add missing role-specific analysis budgets."
    }
    if ([int]$config.provider_timeout_seconds.OpenRouter -ne 333) {
        throw "Runtime upgrade must preserve existing provider timeout overrides."
    }
    if ([int]$config.provider_timeout_seconds.Gemini -ne 240) {
        throw "Runtime upgrade must add missing cloud provider timeout defaults."
    }
    if ([int]$config.provider_timeout_seconds.Ollama -ne 1800) {
        throw "Runtime upgrade must add the local-inference-safe Ollama timeout."
    }

    $manifest = Get-Content (Join-Path $tempRoot ".codex\managed-files.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $managed = @($manifest.managed_files)

    foreach ($relative in @(
        "scripts/provider-router.ps1",
        "scripts/task-execution-lock.ps1",
        "scripts/local-runtime/resolve-local-runtime.ps1",
        ".codex/provider-config.json",
        ".codex/local-runtime-config.json"
    )) {
        if ($managed -notcontains $relative) {
            throw "Runtime upgrade managed manifest missing: $relative"
        }
    }

    if ($managed -contains "app-source.txt") {
        throw "Runtime upgrade must never claim application source as managed."
    }

    $backup = @(Get-ChildItem (Join-Path $tempRoot ".codex\runtime") -Filter "provider-config.backup-*.json" -File)
    if ($backup.Count -lt 1) {
        throw "Runtime upgrade must back up the previous provider config."
    }

    Write-Host "PASS: safe runtime upgrade contract test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}
