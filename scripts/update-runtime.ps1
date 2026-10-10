param(
    [Parameter(Mandatory = $true)]
    [string]$TargetProject,
    [object]$ProjectMaintenanceLease = $null
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )

    [System.IO.File]::WriteAllText(
        $Path,
        $Value,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Normalize-RelativePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Managed file path cannot be empty."
    }

    $value = $Path.Trim().Replace("\","/")

    while ($value.StartsWith("./")) {
        $value = $value.Substring(2)
    }

    $value = $value.TrimStart("/")

    if (
        [string]::IsNullOrWhiteSpace($value) -or
        $value -match '(^|/)\.\.($|/)' -or
        $value -match '^[A-Za-z]:' -or
        $value.Contains(":")
    ) {
        throw "Unsafe managed file path: $Path"
    }

    return $value
}

function Get-TargetPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Relative
    )

    $normalized = Normalize-RelativePath -Path $Relative
    $combined = Join-Path $Root ($normalized.Replace("/","\"))
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@("\","/"))
    $fullTarget = [System.IO.Path]::GetFullPath($combined)

    if (
        -not [string]::Equals($fullTarget,$fullRoot,[System.StringComparison]::OrdinalIgnoreCase) -and
        -not $fullTarget.StartsWith(
            $fullRoot + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "Managed file path escapes target project: $Relative"
    }

    return $fullTarget
}

function Assert-NoReparseEscape {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@("\","/"))
    $current = Split-Path $TargetPath -Parent

    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $currentFull = [System.IO.Path]::GetFullPath($current).TrimEnd([char[]]@("\","/"))

        if ([string]::Equals($currentFull,$rootFull,[System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        if (
            -not $currentFull.StartsWith(
                $rootFull + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            throw "Runtime update path escaped the target project."
        }

        if (Test-Path $currentFull) {
            $item = Get-Item $currentFull -Force

            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Runtime update refuses symlink/junction/reparse path: $currentFull"
            }
        }

        $parent = Split-Path $currentFull -Parent
        if ($parent -eq $currentFull) { break }
        $current = $parent
    }

    if (Test-Path $TargetPath) {
        $targetItem = Get-Item $TargetPath -Force

        if (($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Runtime update refuses symlink/junction/reparse target: $TargetPath"
        }
    }
}

function Add-ManagedPath {
    param(
        [hashtable]$Set,
        [string]$Path
    )

    $normalized = Normalize-RelativePath -Path $Path
    $Set[$normalized] = $true
}

function Merge-Unique {
    param(
        [object[]]$Preferred,
        [object[]]$Existing
    )

    $result = @()

    foreach ($value in @($Preferred + $Existing)) {
        $text = [string]$value

        if (
            -not [string]::IsNullOrWhiteSpace($text) -and
            $result -notcontains $text
        ) {
            $result += $text
        }
    }

    return @($result)
}

function Merge-MissingProperties {
    param(
        [object]$Target,
        [object]$Source
    )

    if ($null -eq $Target -or $null -eq $Source) {
        return
    }

    foreach ($sourceProperty in $Source.PSObject.Properties) {
        $targetProperty = $Target.PSObject.Properties[$sourceProperty.Name]

        if ($null -eq $targetProperty) {
            $Target | Add-Member -NotePropertyName $sourceProperty.Name -NotePropertyValue $sourceProperty.Value
            continue
        }

        if (
            $null -ne $targetProperty.Value -and
            $null -ne $sourceProperty.Value -and
            $targetProperty.Value -is [System.Management.Automation.PSCustomObject] -and
            $sourceProperty.Value -is [System.Management.Automation.PSCustomObject]
        ) {
            Merge-MissingProperties -Target $targetProperty.Value -Source $sourceProperty.Value
        }
    }
}

function Read-JsonObject {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    try {
        $value = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Invalid $Description JSON: $Path. $($_.Exception.Message)"
    }

    if ($null -eq $value) {
        throw "Invalid $Description JSON: root cannot be null."
    }

    return $value
}

function Get-FileHashValue {
    param([string]$Path)

    if (-not (Test-Path $Path -PathType Leaf)) {
        return ""
    }

    return (Get-FileHash $Path -Algorithm SHA256).Hash
}

function Test-FrameworkRuntimeNamespace {
    param([string]$Relative)

    $value = Normalize-RelativePath -Path $Relative

    return (
        $value -match '^scripts/[^/]+\.ps1$' -or
        $value -match '^scripts/providers/[^/]+$' -or
        $value -match '^scripts/local-runtime/[^/]+$' -or
        $value -match '^schemas/[^/]+\.schema\.json$'
    )
}

$sourceRoot = Split-Path -Parent $PSScriptRoot
$targetRoot = (Resolve-Path $TargetProject).Path
# Use package-owned helper, not a target runtime that maintenance may replace.
. (Join-Path $PSScriptRoot "task-execution-lock.ps1")
$maintenanceScope = Enter-ProjectExecutionScope -ProjectPath $targetRoot -Mode Maintenance -Lease $ProjectMaintenanceLease
try {


if (-not (Test-Path $targetRoot -PathType Container)) {
    throw "Target project does not exist: $TargetProject"
}

$manifestPath = Join-Path $targetRoot ".codex\managed-files.json"

if (-not (Test-Path $manifestPath -PathType Leaf)) {
    throw (
        "Runtime update requires an existing AI Company OS managed-files manifest. " +
        "Refusing to guess ownership: $manifestPath"
    )
}

$manifest = Read-JsonObject -Path $manifestPath -Description "managed-files manifest"

if ([int]$manifest.version -ne 1) {
    throw "Unsupported managed-files manifest version: $($manifest.version)"
}

$managedSet = @{}

foreach ($entry in @($manifest.managed_files)) {
    Add-ManagedPath -Set $managedSet -Path ([string]$entry)
}

if (-not $managedSet.ContainsKey(".codex/managed-files.json")) {
    throw "Managed-files manifest does not claim its own AI Company OS contract."
}

$knownContract = @(
    "scripts/provider-router.ps1",
    "scripts/run-agent-task.ps1",
    ".codex/provider-config.json"
)

$contractFound = $false
foreach ($relative in $knownContract) {
    if ($managedSet.ContainsKey($relative)) {
        $contractFound = $true
        break
    }
}

if (-not $contractFound) {
    throw "Target does not contain a recognizable AI Company OS managed runtime contract."
}

if (-not (Test-Path (Join-Path $targetRoot ".git"))) {
    Write-Host "WARNING: target does not appear to be a Git repository." -ForegroundColor Yellow
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
    "build-corrective-analysis-context.ps1",
    "validate-analysis-result-semantics.ps1",
    "provider-router.ps1",
    "run-gate-agent.ps1",
    "run-pending-gates.ps1",
    "generate-engineering-backlog.ps1",
    "materialize-engineering-backlog.ps1",
    "reconcile-engineering-backlog.ps1",
    "repair-artifact-encoding.ps1",
    "validate-json-contract.ps1",
    "validate-engineering-plan-result.ps1","validate-engineering-backlog-semantics.ps1","validate-gate-result-semantics.ps1",
    "validate-artifacts.ps1",
    "write-operational-event.ps1",
    "summarize-metrics.ps1",
    "new-agent-workspace.ps1",
    "run-writable-agent.ps1",
    "resolve-writable-required-files.ps1",
    "task-execution-lock.ps1",
    "review-grounding.ps1",
    "single-attempt-execution.ps1"
)

$directSources = @{}

foreach ($name in $scriptNames) {
    $source = Join-Path $sourceRoot ("scripts\" + $name)

    if (-not (Test-Path $source -PathType Leaf)) {
        throw "AI Company OS package is missing required runtime script: scripts/$name"
    }

    $directSources[("scripts/" + $name)] = $source
}

foreach ($folder in @("providers","local-runtime")) {
    $sourceDir = Join-Path $sourceRoot ("scripts\" + $folder)

    if (-not (Test-Path $sourceDir -PathType Container)) {
        throw "AI Company OS package is missing runtime directory: scripts/$folder"
    }

    Get-ChildItem $sourceDir -File | ForEach-Object {
        $directSources[("scripts/" + $folder + "/" + $_.Name)] = $_.FullName
    }
}

$schemaDir = Join-Path $sourceRoot "schemas"
if (-not (Test-Path $schemaDir -PathType Container)) {
    throw "AI Company OS package is missing schemas directory."
}

Get-ChildItem $schemaDir -Filter "*.schema.json" -File | ForEach-Object {
    $directSources[("schemas/" + $_.Name)] = $_.FullName
}

$configRelativePaths = @(
    ".codex/provider-config.json",
    ".codex/local-runtime-config.json",
    ".codex/writable-policy.json",
    ".codex/workflow-profiles.json"
)

$configSources = @{}
foreach ($relative in $configRelativePaths) {
    $source = Join-Path $sourceRoot ($relative.Replace("/","\"))

    if (-not (Test-Path $source -PathType Leaf)) {
        throw "AI Company OS package is missing required runtime configuration: $relative"
    }

    $configSources[$relative] = $source
}

# ----------------------------
# Preflight ownership + paths
# ----------------------------

$conflicts = @()
$preflightPaths = @()
$preflightPaths += @($directSources.Keys)
$preflightPaths += @($configRelativePaths)

foreach ($relative in @($preflightPaths | Sort-Object -Unique)) {
    $target = Get-TargetPath -Root $targetRoot -Relative $relative
    Assert-NoReparseEscape -Root $targetRoot -TargetPath $target

    if (Test-Path $target) {
        if (-not (Test-Path $target -PathType Leaf)) {
            $conflicts += ($relative + " (expected file, found non-file)")
            continue
        }

        if (-not $managedSet.ContainsKey($relative)) {
            $conflicts += $relative
        }
    }
}

if ($conflicts.Count -gt 0) {
    throw (
        "Runtime update found existing files that are not AI Company OS-managed. " +
        "Refusing to overwrite: " + (($conflicts | Sort-Object) -join ", ")
    )
}

$deprecated = @()
foreach ($relative in @($managedSet.Keys)) {
    if (
        (Test-FrameworkRuntimeNamespace -Relative $relative) -and
        -not $directSources.ContainsKey($relative)
    ) {
        $target = Get-TargetPath -Root $targetRoot -Relative $relative
        Assert-NoReparseEscape -Root $targetRoot -TargetPath $target

        if (Test-Path $target -PathType Leaf) {
            $deprecated += $relative
        }
    }
}

# ----------------------------
# Precompute merged configs
# ----------------------------

$mergedConfigText = @{}

$sourceProvider = Read-JsonObject -Path $configSources[".codex/provider-config.json"] -Description "source provider configuration"
$providerTargetPath = Get-TargetPath -Root $targetRoot -Relative ".codex/provider-config.json"

if (Test-Path $providerTargetPath -PathType Leaf) {
    $targetProvider = Read-JsonObject -Path $providerTargetPath -Description "project provider configuration"
}
else {
    $targetProvider = [PSCustomObject]@{}
}

Merge-MissingProperties -Target $targetProvider -Source $sourceProvider

# Routing order is framework policy. Replace it with current package policy so
# old cloud fallback semantics cannot survive a runtime upgrade.
$targetProvider.auto_order = @($sourceProvider.auto_order)
$targetProvider.writable_auto_order = @($sourceProvider.writable_auto_order)
$targetProvider.gate_auto_order = @($sourceProvider.gate_auto_order)

$mergedConfigText[".codex/provider-config.json"] = (
    $targetProvider | ConvertTo-Json -Depth 50
)

$sourceLocal = Read-JsonObject -Path $configSources[".codex/local-runtime-config.json"] -Description "source local runtime configuration"
$localTargetPath = Get-TargetPath -Root $targetRoot -Relative ".codex/local-runtime-config.json"

if (Test-Path $localTargetPath -PathType Leaf) {
    $targetLocal = Read-JsonObject -Path $localTargetPath -Description "project local runtime configuration"
}
else {
    $targetLocal = [PSCustomObject]@{}
}

Merge-MissingProperties -Target $targetLocal -Source $sourceLocal
$mergedConfigText[".codex/local-runtime-config.json"] = (
    $targetLocal | ConvertTo-Json -Depth 50
)

$sourceWritable = Read-JsonObject -Path $configSources[".codex/writable-policy.json"] -Description "source writable policy"
$writableTargetPath = Get-TargetPath -Root $targetRoot -Relative ".codex/writable-policy.json"

if (Test-Path $writableTargetPath -PathType Leaf) {
    $targetWritable = Read-JsonObject -Path $writableTargetPath -Description "project writable policy"
}
else {
    $targetWritable = [PSCustomObject]@{}
}

Merge-MissingProperties -Target $targetWritable -Source $sourceWritable

foreach ($arrayName in @(
    "protected_path_prefixes",
    "secret_name_patterns",
    "verification_command_patterns"
)) {
    $sourceProperty = $sourceWritable.PSObject.Properties[$arrayName]
    $targetProperty = $targetWritable.PSObject.Properties[$arrayName]

    if ($null -ne $sourceProperty -and $null -ne $targetProperty) {
        $targetWritable.$arrayName = @(
            Merge-Unique -Preferred @($sourceProperty.Value) -Existing @($targetProperty.Value)
        )
    }
}

if (
    $null -ne $sourceWritable.PSObject.Properties["free_provider_models"] -and
    $null -ne $targetWritable.PSObject.Properties["free_provider_models"]
) {
    foreach ($property in $sourceWritable.free_provider_models.PSObject.Properties) {
        $targetProperty = $targetWritable.free_provider_models.PSObject.Properties[$property.Name]

        if ($null -eq $targetProperty) {
            $targetWritable.free_provider_models |
                Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
        else {
            $targetProperty.Value = @(
                Merge-Unique -Preferred @($targetProperty.Value) -Existing @($property.Value)
            )
        }
    }
}

$mergedConfigText[".codex/writable-policy.json"] = (
    $targetWritable | ConvertTo-Json -Depth 50
)

$sourceWorkflow = Read-JsonObject -Path $configSources[".codex/workflow-profiles.json"] -Description "source workflow profiles"
$workflowTargetPath = Get-TargetPath -Root $targetRoot -Relative ".codex/workflow-profiles.json"

if (Test-Path $workflowTargetPath -PathType Leaf) {
    $targetWorkflow = Read-JsonObject -Path $workflowTargetPath -Description "project workflow profiles"
}
else {
    $targetWorkflow = [PSCustomObject]@{}
}

Merge-MissingProperties -Target $targetWorkflow -Source $sourceWorkflow
$mergedConfigText[".codex/workflow-profiles.json"] = (
    $targetWorkflow | ConvertTo-Json -Depth 50
)

# ----------------------------
# Transaction-like apply
# ----------------------------

$tempBase = if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
    $env:TEMP
}
else {
    [System.IO.Path]::GetTempPath()
}

$backupRoot = Join-Path $tempBase ("aico-runtime-update-backup-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
# Enumeration emits provider-normalized FullName paths. Use the same identity
# for relative restoration paths, even when TEMP contains a short-name alias.
$backupRoot = (Get-Item -LiteralPath $backupRoot).FullName

$createdPaths = @()
$changed = 0
$added = 0
$unchanged = 0
$removed = 0
$configUpdated = 0

function Backup-Existing {
    param([string]$Relative)

    $target = Get-TargetPath -Root $targetRoot -Relative $Relative

    if (-not (Test-Path $target -PathType Leaf)) {
        return
    }

    $backup = Join-Path $backupRoot ($Relative.Replace("/","\"))
    $parent = Split-Path $backup -Parent

    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    Copy-Item $target $backup -Force
}

function Ensure-TargetParent {
    param([string]$Path)

    $parent = Split-Path $Path -Parent

    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
}

try {
    Backup-Existing -Relative ".codex/managed-files.json"

    foreach ($relative in @($directSources.Keys | Sort-Object)) {
        $source = $directSources[$relative]
        $target = Get-TargetPath -Root $targetRoot -Relative $relative
        Ensure-TargetParent -Path $target

        if (Test-Path $target -PathType Leaf) {
            if ((Get-FileHashValue -Path $source) -eq (Get-FileHashValue -Path $target)) {
                $unchanged++
            }
            else {
                Backup-Existing -Relative $relative
                Copy-Item $source $target -Force
                $changed++
                Write-Host "UPDATED runtime: $relative" -ForegroundColor Green
            }
        }
        else {
            Copy-Item $source $target -Force
            $createdPaths += $relative
            $added++
            Write-Host "ADDED runtime: $relative" -ForegroundColor Green
        }

        Add-ManagedPath -Set $managedSet -Path $relative
    }

    foreach ($relative in $configRelativePaths) {
        $target = Get-TargetPath -Root $targetRoot -Relative $relative
        Ensure-TargetParent -Path $target

        $newText = [string]$mergedConfigText[$relative]
        $oldText = if (Test-Path $target -PathType Leaf) {
            Get-Content $target -Raw -Encoding UTF8
        }
        else {
            ""
        }

        if ($oldText -eq $newText) {
            $unchanged++
        }
        else {
            if (Test-Path $target -PathType Leaf) {
                Backup-Existing -Relative $relative
            }
            else {
                $createdPaths += $relative
            }

            Write-Utf8NoBom -Path $target -Value $newText
            $configUpdated++
            Write-Host "MERGED config: $relative" -ForegroundColor Green
        }

        Add-ManagedPath -Set $managedSet -Path $relative
    }

    foreach ($relative in @($deprecated | Sort-Object)) {
        $target = Get-TargetPath -Root $targetRoot -Relative $relative

        if (Test-Path $target -PathType Leaf) {
            Backup-Existing -Relative $relative
            Remove-Item $target -Force
            $managedSet.Remove($relative) | Out-Null
            $removed++
            Write-Host "REMOVED deprecated runtime: $relative" -ForegroundColor DarkYellow
        }
    }

    Add-ManagedPath -Set $managedSet -Path ".codex/managed-files.json"

    $managedPayload = [ordered]@{
        version = 1
        managed_files = @($managedSet.Keys | Sort-Object)
    } | ConvertTo-Json -Depth 10

    Write-Utf8NoBom -Path $manifestPath -Value $managedPayload
}
catch {
    $applyError = $_.Exception.Message
    $rollbackErrors = @()

    try {
        foreach ($relative in @($createdPaths | Sort-Object -Unique)) {
            $target = Get-TargetPath -Root $targetRoot -Relative $relative

            if (Test-Path $target -PathType Leaf) {
                Remove-Item $target -Force -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path $backupRoot -PathType Container) {
            Get-ChildItem $backupRoot -File -Recurse | ForEach-Object {
                try {
                    $relative = $_.FullName.Substring($backupRoot.Length).TrimStart([char[]]@("\","/")).Replace("\","/")
                    $target = Get-TargetPath -Root $targetRoot -Relative $relative
                    Ensure-TargetParent -Path $target
                    Copy-Item $_.FullName $target -Force
                }
                catch {
                    $rollbackErrors += $_.Exception.Message
                }
            }
        }
    }
    catch {
        $rollbackErrors += $_.Exception.Message
    }

    if ($rollbackErrors.Count -gt 0) {
        throw (
            "Runtime update failed: $applyError. Rollback also reported: " +
            ($rollbackErrors -join " | ")
        )
    }

    throw "Runtime update failed and changes were rolled back: $applyError"
}
finally {
    if (Test-Path $backupRoot) {
        Remove-Item $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "AI Company OS runtime upgraded safely." -ForegroundColor Green
Write-Host ("Target: " + $targetRoot)
Write-Host ("Updated runtime files: " + $changed)
Write-Host ("Added runtime files: " + $added)
Write-Host ("Merged configs: " + $configUpdated)
Write-Host ("Removed deprecated runtime files: " + $removed)
Write-Host ("Unchanged managed files: " + $unchanged)
Write-Host "Project source, tasks, work requests, docs, evidence and state were not modified."

} finally { Exit-ProjectExecutionScope -Scope $maintenanceScope }
