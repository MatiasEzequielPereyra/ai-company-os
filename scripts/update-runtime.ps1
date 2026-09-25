param(
    [Parameter(Mandatory = $true)]
    [string]$TargetProject
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText(
        $Path,
        $Value,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Merge-OrderedNames {
    param(
        [object[]]$Preferred,
        [object[]]$Existing
    )

    $result = @()

    foreach ($value in @($Preferred + $Existing)) {
        $name = ([string]$value).Trim()
        if (
            -not [string]::IsNullOrWhiteSpace($name) -and
            $result -notcontains $name
        ) {
            $result += $name
        }
    }

    return $result
}

function Ensure-Property {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

$sourceRoot = Split-Path -Parent $PSScriptRoot
$targetRoot = (Resolve-Path $TargetProject).Path

if (-not (Test-Path $targetRoot -PathType Container)) {
    throw "Target project does not exist: $TargetProject"
}

$requiredDirs = @(
    "scripts",
    "scripts\providers",
    "scripts\local-runtime",
    "schemas",
    ".codex",
    ".codex\runtime"
)

foreach ($relative in $requiredDirs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $targetRoot $relative) | Out-Null
}

$scriptNames = @(
    "initialize-project.ps1",
    "new-task.ps1",
    "list-tasks.ps1",
    "update-task.ps1",
    "advance-task.ps1",
    "sync-company-state.ps1",
    "new-work-request.ps1",
    "generate-plan.ps1",
    "materialize-plan-tasks.ps1",
    "evaluate-readiness.ps1",
    "dispatch-ready-tasks.ps1",
    "submit-task-result.ps1",
    "review-task.ps1",
    "qa-task.ps1",
    "security-task.ps1",
    "finalize-task.ps1",
    "refresh-dependencies.ps1",
    "orchestrate.ps1",
    "run-agent-task.ps1",
    "run-active-agents.ps1",
    "build-agent-context.ps1",
    "provider-router.ps1",
    "run-gate-agent.ps1",
    "run-pending-gates.ps1",
    "generate-engineering-backlog.ps1",
    "materialize-engineering-backlog.ps1",
    "reconcile-engineering-backlog.ps1",
    "repair-artifact-encoding.ps1",
    "validate-json-contract.ps1",
    "validate-artifacts.ps1",
    "write-operational-event.ps1",
    "summarize-metrics.ps1",
    "new-agent-workspace.ps1",
    "run-writable-agent.ps1",
    "resolve-writable-required-files.ps1",
    "task-execution-lock.ps1",
    "update-runtime.ps1"
)

foreach ($name in $scriptNames) {
    $source = Join-Path $sourceRoot ("scripts\" + $name)
    if (-not (Test-Path $source -PathType Leaf)) { continue }

    Copy-Item $source (Join-Path $targetRoot ("scripts\" + $name)) -Force
    Write-Host "UPDATED runtime script: $name" -ForegroundColor Green
}

foreach ($folder in @("providers","local-runtime")) {
    $sourceDir = Join-Path $sourceRoot ("scripts\" + $folder)
    $targetDir = Join-Path $targetRoot ("scripts\" + $folder)

    if (-not (Test-Path $sourceDir -PathType Container)) { continue }

    Get-ChildItem $sourceDir -File | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $targetDir $_.Name) -Force
        Write-Host ("UPDATED " + $folder + ": " + $_.Name) -ForegroundColor Green
    }
}

$schemasSource = Join-Path $sourceRoot "schemas"
if (Test-Path $schemasSource -PathType Container) {
    Get-ChildItem $schemasSource -Filter "*.schema.json" -File | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $targetRoot ("schemas\" + $_.Name)) -Force
        Write-Host ("UPDATED schema: " + $_.Name) -ForegroundColor Green
    }
}

$localConfigSource = Join-Path $sourceRoot ".codex\local-runtime-config.json"
$localConfigTarget = Join-Path $targetRoot ".codex\local-runtime-config.json"

if (Test-Path $localConfigSource -PathType Leaf) {
    Copy-Item $localConfigSource $localConfigTarget -Force
    Write-Host "UPDATED: .codex\local-runtime-config.json" -ForegroundColor Green
}

$providerSourcePath = Join-Path $sourceRoot ".codex\provider-config.json"
$providerTargetPath = Join-Path $targetRoot ".codex\provider-config.json"

if (Test-Path $providerSourcePath -PathType Leaf) {
    $sourceConfig = Get-Content $providerSourcePath -Raw -Encoding UTF8 | ConvertFrom-Json

    if (Test-Path $providerTargetPath -PathType Leaf) {
        $targetConfig = Get-Content $providerTargetPath -Raw -Encoding UTF8 | ConvertFrom-Json

        $backup = Join-Path $targetRoot (".codex\runtime\provider-config.backup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
        Copy-Item $providerTargetPath $backup -Force
        Write-Host ("BACKUP: " + $backup) -ForegroundColor DarkGray
    }
    else {
        $targetConfig = [PSCustomObject]@{}
    }

    Ensure-Property -Object $targetConfig -Name "auto_order" -Value @()
    $existingAutoOrder = @($targetConfig.auto_order) + @($sourceConfig.auto_order)
    $targetConfig.auto_order = @(
        Merge-OrderedNames -Preferred @("Ollama") -Existing $existingAutoOrder
    )

    Ensure-Property -Object $targetConfig -Name "allow_paid_fallback" -Value $false
    Ensure-Property -Object $targetConfig -Name "context_max_chars" -Value $sourceConfig.context_max_chars
    Ensure-Property -Object $targetConfig -Name "analysis_context_max_chars" -Value $sourceConfig.analysis_context_max_chars
    Ensure-Property -Object $targetConfig -Name "analysis_context_max_chars_by_role" -Value $sourceConfig.analysis_context_max_chars_by_role
    Ensure-Property -Object $targetConfig -Name "provider_timeout_seconds" -Value $sourceConfig.provider_timeout_seconds
    Ensure-Property -Object $targetConfig -Name "gate_context_max_chars" -Value $sourceConfig.gate_context_max_chars
    Ensure-Property -Object $targetConfig -Name "ollama_context_max_chars" -Value $sourceConfig.ollama_context_max_chars
    Ensure-Property -Object $targetConfig -Name "ollama_gate_context_max_chars" -Value $sourceConfig.ollama_gate_context_max_chars
    Ensure-Property -Object $targetConfig -Name "ollama_gate_artifact_max_chars" -Value $sourceConfig.ollama_gate_artifact_max_chars
    Ensure-Property -Object $targetConfig -Name "models" -Value ([PSCustomObject]@{})

    foreach ($name in @("Ollama","OpenRouter","Gemini","DeepSeek","Grok")) {
        $sourceProperty = $sourceConfig.models.PSObject.Properties[$name]
        if ($null -eq $sourceProperty) { continue }

        if ($null -eq $targetConfig.models.PSObject.Properties[$name]) {
            $targetConfig.models | Add-Member -NotePropertyName $name -NotePropertyValue $sourceProperty.Value
        }
    }

    Ensure-Property -Object $targetConfig -Name "writable_auto_order" -Value @()
    $existingWritableOrder = @($targetConfig.writable_auto_order) + @($sourceConfig.writable_auto_order)
    $targetConfig.writable_auto_order = @(
        Merge-OrderedNames -Preferred @("Ollama") -Existing $existingWritableOrder
    )

    Ensure-Property -Object $targetConfig -Name "writable_allow_paid_fallback" -Value $false
    Ensure-Property -Object $targetConfig -Name "writable_context_max_chars" -Value $sourceConfig.writable_context_max_chars
    Ensure-Property -Object $targetConfig -Name "writable_models" -Value ([PSCustomObject]@{})

    foreach ($name in @("OpenRouter","Gemini","DeepSeek","Grok")) {
        $sourceProperty = $sourceConfig.writable_models.PSObject.Properties[$name]
        if ($null -eq $sourceProperty) { continue }

        if ($null -eq $targetConfig.writable_models.PSObject.Properties[$name]) {
            $targetConfig.writable_models | Add-Member -NotePropertyName $name -NotePropertyValue $sourceProperty.Value
        }
    }

    Write-Utf8NoBom -Path $providerTargetPath -Value ($targetConfig | ConvertTo-Json -Depth 20)
    Write-Host "MERGED: .codex\provider-config.json" -ForegroundColor Green
}

$writableSourcePath = Join-Path $sourceRoot ".codex\writable-policy.json"
$writableTargetPath = Join-Path $targetRoot ".codex\writable-policy.json"

if (Test-Path $writableSourcePath -PathType Leaf) {
    $sourcePolicy = Get-Content $writableSourcePath -Raw -Encoding UTF8 | ConvertFrom-Json

    if (Test-Path $writableTargetPath -PathType Leaf) {
        $targetPolicy = Get-Content $writableTargetPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        $targetPolicy = $sourcePolicy
    }

    if ($null -ne $sourcePolicy.free_provider_models) {
        Ensure-Property -Object $targetPolicy -Name "free_provider_models" -Value ([PSCustomObject]@{})

        foreach ($name in @("Ollama","OpenRouter","Gemini")) {
            $sourceProperty = $sourcePolicy.free_provider_models.PSObject.Properties[$name]
            if ($null -eq $sourceProperty) { continue }

            if ($null -eq $targetPolicy.free_provider_models.PSObject.Properties[$name]) {
                $targetPolicy.free_provider_models | Add-Member -NotePropertyName $name -NotePropertyValue $sourceProperty.Value
            }
            else {
                $merged = @(
                    Merge-OrderedNames -Preferred @($targetPolicy.free_provider_models.$name) -Existing @($sourceProperty.Value)
                )
                $targetPolicy.free_provider_models.$name = $merged
            }
        }
    }

    Write-Utf8NoBom -Path $writableTargetPath -Value ($targetPolicy | ConvertTo-Json -Depth 30)
    Write-Host "MERGED: .codex\writable-policy.json" -ForegroundColor Green
}

$managedManifestPath = Join-Path $targetRoot ".codex\managed-files.json"
$managedSet = @{}

if (Test-Path $managedManifestPath -PathType Leaf) {
    try {
        $existingManaged = Get-Content $managedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($relative in @($existingManaged.managed_files)) {
            $value = ([string]$relative).Trim().Replace("\","/")
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $managedSet[$value] = $true
            }
        }
    }
    catch {
        throw "Invalid managed-files manifest: $managedManifestPath"
    }
}

foreach ($name in $scriptNames) {
    $pathToCheck = Join-Path $targetRoot ("scripts\" + $name)
    if (Test-Path $pathToCheck -PathType Leaf) {
        $managedSet[("scripts/" + $name)] = $true
    }
}

foreach ($folder in @("providers","local-runtime")) {
    $targetDir = Join-Path $targetRoot ("scripts\" + $folder)
    if (Test-Path $targetDir -PathType Container) {
        Get-ChildItem $targetDir -File | ForEach-Object {
            $managedSet[("scripts/" + $folder + "/" + $_.Name)] = $true
        }
    }
}

$schemasTarget = Join-Path $targetRoot "schemas"
if (Test-Path $schemasTarget -PathType Container) {
    Get-ChildItem $schemasTarget -Filter "*.schema.json" -File | ForEach-Object {
        $managedSet[("schemas/" + $_.Name)] = $true
    }
}

foreach ($relative in @(
    ".codex/provider-config.json",
    ".codex/local-runtime-config.json",
    ".codex/writable-policy.json",
    ".codex/managed-files.json"
)) {
    if (
        $relative -eq ".codex/managed-files.json" -or
        (Test-Path (Join-Path $targetRoot ($relative.Replace("/","\"))) -PathType Leaf)
    ) {
        $managedSet[$relative] = $true
    }
}

$managedPayload = [ordered]@{
    version = 1
    managed_files = @($managedSet.Keys | Sort-Object)
} | ConvertTo-Json -Depth 10

Write-Utf8NoBom -Path $managedManifestPath -Value $managedPayload
Write-Host "UPDATED: .codex\managed-files.json" -ForegroundColor Green

Write-Host ""
Write-Host "AI Company OS runtime upgraded." -ForegroundColor Green
Write-Host ("Target: " + $targetRoot)
Write-Host "Project source, tasks, docs and state were not modified."
Write-Host ""
Write-Host "Verify with:"
Write-Host ".\scripts\local-runtime\initialize-local-runtime.ps1 -SkipBenchmark"
