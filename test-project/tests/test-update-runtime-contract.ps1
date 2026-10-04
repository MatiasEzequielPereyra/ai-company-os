param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$installScript = Join-Path $repoRoot "scripts\install-existing-project.ps1"
$updateScript = Join-Path $repoRoot "scripts\update-runtime.ps1"

$tempBase = if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
    $env:TEMP
}
else {
    [System.IO.Path]::GetTempPath()
}

$tempRoot = Join-Path $tempBase ("aico runtime update " + [Guid]::NewGuid().ToString("N"))

function Write-TestFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Get-RelativeFileHashes {
    param([string]$Root)

    $result = @{}

    Get-ChildItem $Root -File -Recurse -Force | ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length).TrimStart([char[]]@("\","/")).Replace("\","/")
        $result[$relative] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    }

    return $result
}

function Assert-SameHashMap {
    param(
        [hashtable]$Expected,
        [hashtable]$Actual,
        [string]$Description
    )

    if ($Expected.Count -ne $Actual.Count) {
        throw "$Description changed file count. Expected=$($Expected.Count) Actual=$($Actual.Count)"
    }

    foreach ($key in $Expected.Keys) {
        if (-not $Actual.ContainsKey($key)) {
            throw "$Description removed file: $key"
        }

        if ([string]$Expected[$key] -ne [string]$Actual[$key]) {
            throw "$Description changed file content: $key"
        }
    }
}

function Assert-ThrowsLike {
    param(
        [scriptblock]$Action,
        [string]$Pattern,
        [string]$Description
    )

    $threw = $false

    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "$Description failed with unexpected error: $($_.Exception.Message)"
        }

        $threw = $true
    }

    if (-not $threw) {
        throw "$Description did not fail as required."
    }
}

function New-InstalledFixture {
    param([string]$Path)

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    & $installScript -TargetProject $Path | Out-Null
}

try {
    # -----------------------------------------------------------------
    # Positive fixture: old synthetic runtime + project-owned artifacts.
    # -----------------------------------------------------------------

    New-InstalledFixture -Path $tempRoot

    $projectOwned = @(
        @{ Path = "app-source.txt"; Content = "preserve application source" },
        @{ Path = "tasks\AICO-999.md"; Content = "preserve task history" },
        @{ Path = "docs\project-note.md"; Content = "preserve project docs" },
        @{ Path = "docs\engineering\work-requests\WR-999.md"; Content = "preserve work request" },
        @{ Path = "docs\engineering\reviews\AICO-999-review-001.md"; Content = "preserve review evidence" },
        @{ Path = "docs\engineering\qa\AICO-999-qa-001.md"; Content = "preserve qa evidence" },
        @{ Path = "docs\engineering\security\AICO-999-security-001.md"; Content = "preserve security evidence" },
        @{ Path = ".codex\state\project-decision.txt"; Content = "preserve project state" }
    )

    foreach ($entry in $projectOwned) {
        Write-TestFile -Path (Join-Path $tempRoot $entry.Path) -Content $entry.Content
    }

    $projectOwnedHashes = @{}
    foreach ($entry in $projectOwned) {
        $path = Join-Path $tempRoot $entry.Path
        $projectOwnedHashes[$entry.Path.Replace("\","/")] = (Get-FileHash $path -Algorithm SHA256).Hash
    }

    # Simulate stale managed runtime.
    Write-TestFile -Path (Join-Path $tempRoot "scripts\provider-router.ps1") -Content "OLD_PROVIDER_ROUTER"
    Remove-Item (Join-Path $tempRoot "scripts\providers\invoke-xai.ps1") -Force

    $deprecatedRelative = "scripts/deprecated-runtime.ps1"
    Write-TestFile -Path (Join-Path $tempRoot ($deprecatedRelative.Replace("/","\"))) -Content "OLD_DEPRECATED_RUNTIME"

    $manifestPath = Join-Path $tempRoot ".codex\managed-files.json"
    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $managed = @($manifest.managed_files)

    if ($managed -notcontains $deprecatedRelative) {
        $managed += $deprecatedRelative
    }

    $manifest.managed_files = @($managed | Sort-Object -Unique)
    Write-TestFile -Path $manifestPath -Content ($manifest | ConvertTo-Json -Depth 10)

    # Simulate an older project configuration with explicit user overrides.
    $oldProviderConfig = @{
        auto_order = @("OpenRouter","Gemini")
        gate_auto_order = @("Gemini")
        allow_paid_fallback = $false
        context_max_chars = 120000
        models = @{
            OpenRouter = "custom/openrouter-model"
        }
        writable_auto_order = @("OpenRouter")
        writable_allow_paid_fallback = $false
        writable_models = @{
            OpenRouter = "custom/writable-model"
        }
        analysis_context_max_chars_by_role = @{
            pm = 65000
        }
        provider_timeout_seconds = @{
            OpenRouter = 333
        }
    } | ConvertTo-Json -Depth 20

    Write-TestFile -Path (Join-Path $tempRoot ".codex\provider-config.json") -Content $oldProviderConfig

    $oldLocalConfig = @{
        schema_version = 1
        profiles = @{
            LOCAL_CPU_LOW = @{
                num_ctx = 4096
            }
        }
        custom_project_runtime_key = "preserve-me"
    } | ConvertTo-Json -Depth 20

    Write-TestFile -Path (Join-Path $tempRoot ".codex\local-runtime-config.json") -Content $oldLocalConfig

    $oldWritablePolicy = @{
        max_changed_files = 7
        protected_path_prefixes = @(".git","custom-protected")
        secret_name_patterns = @("custom-secret-pattern")
        verification_command_patterns = @("^git status --short$")
        free_provider_models = @{
            OpenRouter = @("custom/free-model")
        }
        custom_project_policy_key = "preserve-me"
    } | ConvertTo-Json -Depth 20

    Write-TestFile -Path (Join-Path $tempRoot ".codex\writable-policy.json") -Content $oldWritablePolicy

    & $updateScript -TargetProject $tempRoot

    # Framework runtime must be current.
    foreach ($relative in @(
        "scripts/provider-router.ps1",
        "scripts/run-agent-task.ps1",
        "scripts/task-execution-lock.ps1",
        "scripts/validate-engineering-plan-result.ps1",
        "scripts/validate-analysis-result-semantics.ps1",
        "scripts/build-corrective-analysis-context.ps1",
        "scripts/validate-engineering-backlog-semantics.ps1",
        "scripts/validate-gate-result-semantics.ps1",
        "scripts/providers/invoke-codex.ps1",
        "scripts/providers/invoke-xai.ps1",
        "scripts/local-runtime/resolve-local-runtime.ps1",
        "schemas/agent-result.schema.json",
        "schemas/engineering-plan-result.schema.json"
    )) {
        $sourcePath = Join-Path $repoRoot ($relative.Replace("/","\"))
        $targetPath = Join-Path $tempRoot ($relative.Replace("/","\"))

        if (-not (Test-Path $targetPath -PathType Leaf)) {
            throw "Runtime update is missing current framework artifact: $relative"
        }

        $sourceHash = (Get-FileHash $sourcePath -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash $targetPath -Algorithm SHA256).Hash

        if ($sourceHash -ne $targetHash) {
            throw "Runtime update did not refresh framework artifact: $relative"
        }
    }

    if (Test-Path (Join-Path $tempRoot ($deprecatedRelative.Replace("/","\")))) {
        throw "Runtime update did not remove deprecated managed runtime artifact."
    }

    if (Test-Path (Join-Path $tempRoot "scripts\update-runtime.ps1")) {
        throw "Package-owned updater must not be materialized into client projects."
    }

    # Project-owned content must remain byte-for-byte unchanged.
    foreach ($relative in $projectOwnedHashes.Keys) {
        $path = Join-Path $tempRoot ($relative.Replace("/","\"))
        $actual = (Get-FileHash $path -Algorithm SHA256).Hash

        if ([string]$actual -ne [string]$projectOwnedHashes[$relative]) {
            throw "Runtime update modified project-owned artifact: $relative"
        }
    }

    # Provider config: migrate framework routing policy but preserve user overrides.
    $providerConfig = Get-Content (Join-Path $tempRoot ".codex\provider-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json

    if ((@($providerConfig.auto_order) -join ",") -ne "Ollama") {
        throw "Runtime update must migrate Auto routing to current Ollama-local-first policy."
    }

    if (
        (@($providerConfig.gate_auto_order) -join ",") -ne
        "Ollama,OpenRouter,Gemini,Codex,DeepSeek,Grok"
    ) {
        throw (
            "Runtime update must migrate gate Auto routing to " +
            "current framework gate fallback policy."
        )
    }

    if ((@($providerConfig.writable_auto_order) -join ",") -ne "Ollama") {
        throw "Runtime update must migrate writable Auto routing to current Ollama-local-first policy."
    }

    if ([string]$providerConfig.models.OpenRouter -ne "custom/openrouter-model") {
        throw "Runtime update overwrote a project provider model override."
    }

    if ([string]$providerConfig.writable_models.OpenRouter -ne "custom/writable-model") {
        throw "Runtime update overwrote a project writable model override."
    }

    if ([int]$providerConfig.provider_timeout_seconds.OpenRouter -ne 333) {
        throw "Runtime update overwrote a project timeout override."
    }

    foreach ($providerName in @("Codex","Gemini","Ollama","DeepSeek","Grok")) {
        $property = $providerConfig.provider_timeout_seconds.PSObject.Properties[$providerName]

        if ($null -eq $property -or [int]$property.Value -lt 1) {
            throw "Runtime update did not add missing timeout contract for $providerName."
        }
    }

    if (@($providerConfig.analysis_skip_local_profiles_by_role."engineering-manager") -notcontains "LOCAL_CPU_LOW") {
        throw "Runtime update did not add current hardware-aware analysis policy."
    }

    if ((@($providerConfig.analysis_auto_order_by_role.cto) -join ",") -ne "Ollama,OpenRouter,Gemini,Codex,DeepSeek,Grok") {
        throw "Runtime update must add the missing CTO analysis fallback policy."
    }

    # Local runtime config: preserve project tuning while adding missing profiles.
    $localConfig = Get-Content (Join-Path $tempRoot ".codex\local-runtime-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json

    if ([int]$localConfig.profiles.LOCAL_CPU_LOW.num_ctx -ne 4096) {
        throw "Runtime update overwrote a project local runtime tuning."
    }

    if ([string]$localConfig.custom_project_runtime_key -ne "preserve-me") {
        throw "Runtime update removed project local runtime custom configuration."
    }

    if ($null -eq $localConfig.profiles.LOCAL_GPU_12GB) {
        throw "Runtime update did not add a missing current local runtime profile."
    }

    # Writable policy: preserve custom scalar limits and custom patterns, while
    # adding framework safety patterns.
    $writablePolicy = Get-Content (Join-Path $tempRoot ".codex\writable-policy.json") -Raw -Encoding UTF8 | ConvertFrom-Json

    if ([int]$writablePolicy.max_changed_files -ne 7) {
        throw "Runtime update overwrote a project writable limit."
    }

    if (@($writablePolicy.protected_path_prefixes) -notcontains "custom-protected") {
        throw "Runtime update removed a custom protected path."
    }

    if (@($writablePolicy.protected_path_prefixes) -notcontains ".codex") {
        throw "Runtime update did not add current framework protected paths."
    }

    if (@($writablePolicy.free_provider_models.OpenRouter) -notcontains "custom/free-model") {
        throw "Runtime update removed a custom free-provider model."
    }

    if ([string]$writablePolicy.custom_project_policy_key -ne "preserve-me") {
        throw "Runtime update removed project writable policy custom configuration."
    }

    # Manifest ownership must be accurate and must not expand into project state.
    $updatedManifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $updatedManaged = @($updatedManifest.managed_files)

    foreach ($relative in @(
        "scripts/provider-router.ps1",
        "scripts/providers/invoke-codex.ps1",
        "scripts/providers/invoke-xai.ps1",
        ".codex/provider-config.json",
        ".codex/local-runtime-config.json",
        ".codex/writable-policy.json"
    )) {
        if ($updatedManaged -notcontains $relative) {
            throw "Runtime update manifest is missing managed framework artifact: $relative"
        }
    }

    if ($updatedManaged -contains $deprecatedRelative) {
        throw "Runtime update manifest retained a deprecated managed artifact."
    }

    foreach ($entry in $projectOwned) {
        $relative = $entry.Path.Replace("\","/")
        if ($updatedManaged -contains $relative -and $relative -eq "app-source.txt") {
            throw "Runtime update claimed application source as managed."
        }
    }

    # Second update must be byte-for-byte idempotent.
    $firstSnapshot = Get-RelativeFileHashes -Root $tempRoot
    & $updateScript -TargetProject $tempRoot
    $secondSnapshot = Get-RelativeFileHashes -Root $tempRoot

    Assert-SameHashMap -Expected $firstSnapshot -Actual $secondSnapshot -Description "Second runtime update"

    # -----------------------------------------------------------------
    # Negative: missing project ownership contract.
    # -----------------------------------------------------------------

    $missingManifestRoot = Join-Path $tempBase ("aico-update-missing-manifest-" + [Guid]::NewGuid().ToString("N"))
    New-InstalledFixture -Path $missingManifestRoot
    Remove-Item (Join-Path $missingManifestRoot ".codex\managed-files.json") -Force

    Assert-ThrowsLike -Action {
        & $updateScript -TargetProject $missingManifestRoot
    } -Pattern "requires an existing AI Company OS managed-files manifest" -Description "Missing-manifest update"

    Remove-Item $missingManifestRoot -Recurse -Force

    # -----------------------------------------------------------------
    # Negative: malformed manifest.
    # -----------------------------------------------------------------

    $malformedRoot = Join-Path $tempBase ("aico-update-malformed-" + [Guid]::NewGuid().ToString("N"))
    New-InstalledFixture -Path $malformedRoot
    Write-TestFile -Path (Join-Path $malformedRoot ".codex\managed-files.json") -Content "{not-json"

    Assert-ThrowsLike -Action {
        & $updateScript -TargetProject $malformedRoot
    } -Pattern "Invalid managed-files manifest JSON" -Description "Malformed-manifest update"

    Remove-Item $malformedRoot -Recurse -Force

    # -----------------------------------------------------------------
    # Negative: malicious traversal in manifest.
    # -----------------------------------------------------------------

    $traversalRoot = Join-Path $tempBase ("aico-update-traversal-" + [Guid]::NewGuid().ToString("N"))
    New-InstalledFixture -Path $traversalRoot
    $traversalManifestPath = Join-Path $traversalRoot ".codex\managed-files.json"
    $traversalManifest = Get-Content $traversalManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $traversalManifest.managed_files = @($traversalManifest.managed_files) + "../escape.txt"
    Write-TestFile -Path $traversalManifestPath -Content ($traversalManifest | ConvertTo-Json -Depth 10)

    Assert-ThrowsLike -Action {
        & $updateScript -TargetProject $traversalRoot
    } -Pattern "Unsafe managed file path" -Description "Traversal-manifest update"

    Remove-Item $traversalRoot -Recurse -Force

    # -----------------------------------------------------------------
    # Negative: existing runtime-looking file not owned by manifest.
    # Preflight must fail without modifying it.
    # -----------------------------------------------------------------

    $conflictRoot = Join-Path $tempBase ("aico-update-conflict-" + [Guid]::NewGuid().ToString("N"))
    New-InstalledFixture -Path $conflictRoot

    $conflictPath = Join-Path $conflictRoot "scripts\provider-router.ps1"
    Write-TestFile -Path $conflictPath -Content "USER_OWNED_CONFLICT"
    $conflictHash = (Get-FileHash $conflictPath -Algorithm SHA256).Hash

    $conflictManifestPath = Join-Path $conflictRoot ".codex\managed-files.json"
    $conflictManifest = Get-Content $conflictManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $conflictManifest.managed_files = @(
        $conflictManifest.managed_files |
            Where-Object { [string]$_ -ne "scripts/provider-router.ps1" }
    )
    Write-TestFile -Path $conflictManifestPath -Content ($conflictManifest | ConvertTo-Json -Depth 10)

    Assert-ThrowsLike -Action {
        & $updateScript -TargetProject $conflictRoot
    } -Pattern "not AI Company OS-managed" -Description "Unmanaged-conflict update"

    $afterConflictHash = (Get-FileHash $conflictPath -Algorithm SHA256).Hash
    if ($conflictHash -ne $afterConflictHash) {
        throw "Runtime update modified an unmanaged conflicting file before failing."
    }

    Remove-Item $conflictRoot -Recurse -Force

    Write-Host "PASS: safe runtime upgrade, preservation, idempotency, migration, and negative contracts" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
