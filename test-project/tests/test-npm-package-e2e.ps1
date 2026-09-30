param(
    [Parameter(Mandatory = $true)]
    [string]$TarballPath
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$resolvedTarball = (Resolve-Path $TarballPath).Path

$npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($null -eq $npmCommand) {
    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
}
if ($null -eq $npmCommand) {
    throw "npm is required for release package E2E validation."
}

$tempBase = if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    $env:RUNNER_TEMP
}
elseif (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
    $env:TEMP
}
else {
    [System.IO.Path]::GetTempPath()
}

$e2eRoot = Join-Path $tempBase (
    "AI Company OS Release E2E " + [Guid]::NewGuid().ToString("N")
)
$installRoot = Join-Path $e2eRoot "installed package"
$homeRoot = Join-Path $e2eRoot "isolated home"
$projectsRoot = Join-Path $e2eRoot "external projects"
$projectName = "release-smoke-project"
$projectPath = Join-Path $projectsRoot $projectName
$existingProjectPath = Join-Path $projectsRoot "existing repository smoke"

$requiredProjectRuntimeArtifacts = @(
    ".codex\managed-files.json",
    ".codex\provider-config.json",
    ".codex\local-runtime-config.json",
    ".codex\workflow-profiles.json",
    ".codex\writable-policy.json",
    "scripts\provider-router.ps1",
    "scripts\validate-engineering-plan-result.ps1",
    "scripts\validate-engineering-backlog-semantics.ps1",
    "scripts\validate-gate-result-semantics.ps1",
    "scripts\providers\invoke-codex.ps1",
    "scripts\providers\invoke-ollama.ps1",
    "schemas\agent-result.schema.json",
    "schemas\engineering-plan-result.schema.json"
)

function Assert-ManagedProjectRuntime {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        [Parameter(Mandatory = $true)]
        [string]$Scenario
    )

    foreach ($relative in $requiredProjectRuntimeArtifacts) {
        if (-not (Test-Path (Join-Path $ProjectPath $relative) -PathType Leaf)) {
            throw "$Scenario is missing required managed runtime artifact: $relative"
        }
    }
}

$oldHome = $env:HOME
$oldUserProfile = $env:USERPROFILE
$oldPythonPath = $env:PYTHONPATH
$oldNodePath = $env:NODE_PATH

New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
New-Item -ItemType Directory -Force -Path $homeRoot | Out-Null
New-Item -ItemType Directory -Force -Path $projectsRoot | Out-Null

try {
    & $npmCommand.Source install --prefix $installRoot --ignore-scripts --no-audit --no-fund $resolvedTarball

    if ($LASTEXITCODE -ne 0) {
        throw "Installing the release tarball failed with exit code $LASTEXITCODE."
    }

    $installedPackageRoot = Join-Path (
        Join-Path $installRoot "node_modules"
    ) "@pereyram\ai-company-os"

    if (-not (Test-Path $installedPackageRoot -PathType Container)) {
        throw "Installed package root not found: $installedPackageRoot"
    }

    $repoFull = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd([char[]]@('\','/'))
    $installedFull = [System.IO.Path]::GetFullPath($installedPackageRoot).TrimEnd([char[]]@('\','/'))

    if ([string]::Equals(
        $repoFull,
        $installedFull,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Release E2E resolved the source checkout instead of the installed package."
    }

    $aicoCommand = Join-Path $installRoot "node_modules\.bin\aico.cmd"
    if (-not (Test-Path $aicoCommand -PathType Leaf)) {
        throw "Installed aico command not found: $aicoCommand"
    }

    $env:HOME = $homeRoot
    $env:USERPROFILE = $homeRoot
    $env:PYTHONPATH = ""
    $env:NODE_PATH = ""

    Push-Location $projectsRoot
    try {
        & $aicoCommand new $projectName $projectsRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Packaged aico new failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path $projectPath -PathType Container)) {
        throw "Packaged aico new did not create the expected project: $projectPath"
    }

    Assert-ManagedProjectRuntime -ProjectPath $projectPath -Scenario "Packaged aico new"

    $installedPackageJson = Get-Content (
        Join-Path $installedPackageRoot "package.json"
    ) -Raw -Encoding UTF8 | ConvertFrom-Json

    $runtimeMarker = Join-Path (
        Join-Path $installedPackageRoot ".aico-python"
    ) ".aico-installed-version"

    if (-not (Test-Path $runtimeMarker -PathType Leaf)) {
        throw (
            "Packaged CLI did not bootstrap Python from the installed package. " +
            "Missing marker: $runtimeMarker"
        )
    }

    $markerVersion = (Get-Content $runtimeMarker -Raw -Encoding UTF8).Trim()
    if ($markerVersion -ne [string]$installedPackageJson.version) {
        throw (
            "Installed Python runtime marker does not match package version. " +
            "marker=$markerVersion package=$($installedPackageJson.version)"
        )
    }

    & $aicoCommand version
    if ($LASTEXITCODE -ne 0) {
        throw "Installed aico version failed with exit code $LASTEXITCODE."
    }

    & $aicoCommand status --project $projectPath --json
    if ($LASTEXITCODE -ne 0) {
        throw "Installed aico status failed with exit code $LASTEXITCODE."
    }

    $installedPython = Join-Path (
        Join-Path $installedPackageRoot ".aico-python\Scripts"
    ) "python.exe"

    if (-not (Test-Path $installedPython -PathType Leaf)) {
        throw "Installed package Python runtime not found: $installedPython"
    }

    & $installedPython -c "from company_os.cli.tui import AICompanyTUI; print(AICompanyTUI.__name__)"
    if ($LASTEXITCODE -ne 0) {
        throw "Installed package TUI import failed with exit code $LASTEXITCODE."
    }

    New-Item -ItemType Directory -Force -Path $existingProjectPath | Out-Null

    $existingScriptsDir = Join-Path $existingProjectPath "scripts"
    New-Item -ItemType Directory -Force -Path $existingScriptsDir | Out-Null
    $existingSyncPath = Join-Path $existingScriptsDir "sync-company-state.ps1"
    $existingSyncMarker = Join-Path $existingProjectPath "preexisting-sync-executed.txt"
    $existingSyncContent = @'
[System.IO.File]::WriteAllText(
    (Join-Path $PSScriptRoot "..\preexisting-sync-executed.txt"),
    "executed"
)
'@
    [System.IO.File]::WriteAllText(
        $existingSyncPath,
        $existingSyncContent,
        (New-Object System.Text.UTF8Encoding($false))
    )
    $existingSyncHashBefore = (Get-FileHash $existingSyncPath -Algorithm SHA256).Hash

    $existingUserDir = Join-Path $existingProjectPath "src"
    New-Item -ItemType Directory -Force -Path $existingUserDir | Out-Null

    $existingUserPath = Join-Path $existingUserDir "existing-user-file.txt"
    [System.IO.File]::WriteAllText(
        $existingUserPath,
        "This file predates AI Company OS installation.",
        (New-Object System.Text.UTF8Encoding($false))
    )
    $existingUserHashBefore = (Get-FileHash $existingUserPath -Algorithm SHA256).Hash

    Push-Location $existingProjectPath
    try {
        git init --quiet
        if ($LASTEXITCODE -ne 0) {
            throw "Could not initialize existing-repository E2E Git repository."
        }

        & $aicoCommand install .
        if ($LASTEXITCODE -ne 0) {
            throw "Packaged aico install failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    $existingUserHashAfter = (Get-FileHash $existingUserPath -Algorithm SHA256).Hash
    if ($existingUserHashAfter -ne $existingUserHashBefore) {
        throw "Packaged aico install modified a pre-existing project-owned file."
    }

    $existingSyncHashAfter = (Get-FileHash $existingSyncPath -Algorithm SHA256).Hash
    if ($existingSyncHashAfter -ne $existingSyncHashBefore) {
        throw "Packaged aico install modified the pre-existing project-owned sync script."
    }
    if (Test-Path $existingSyncMarker) {
        throw "Packaged aico install executed the pre-existing project-owned sync script."
    }

    Assert-ManagedProjectRuntime -ProjectPath $existingProjectPath -Scenario "Packaged aico install"

    $existingManifest = Get-Content (
        Join-Path $existingProjectPath ".codex\managed-files.json"
    ) -Raw -Encoding UTF8 | ConvertFrom-Json

    foreach ($managedEntry in @(
        ".codex/provider-config.json",
        "scripts/provider-router.ps1",
        "scripts/validate-engineering-plan-result.ps1",
        "scripts/validate-engineering-backlog-semantics.ps1",
        "scripts/validate-gate-result-semantics.ps1",
        "schemas/engineering-plan-result.schema.json"
    )) {
        if (@($existingManifest.managed_files) -notcontains $managedEntry) {
            throw "Packaged aico install manifest is missing ownership entry: $managedEntry"
        }
    }

    if (@($existingManifest.managed_files) -contains "scripts/sync-company-state.ps1") {
        throw "Packaged aico install must not claim a skipped project-owned sync script."
    }

    & $aicoCommand status --project $existingProjectPath --json
    if ($LASTEXITCODE -ne 0) {
        throw "Installed aico status failed for existing project with exit code $LASTEXITCODE."
    }

    $userOwnedDir = Join-Path $projectPath "src"
    New-Item -ItemType Directory -Force -Path $userOwnedDir | Out-Null

    $userOwnedPath = Join-Path $userOwnedDir "user-owned.txt"
    [System.IO.File]::WriteAllText(
        $userOwnedPath,
        "This file belongs to the external project.",
        (New-Object System.Text.UTF8Encoding($false))
    )
    $userHashBefore = (Get-FileHash $userOwnedPath -Algorithm SHA256).Hash

    $managedRuntimeRelative = "scripts\provider-router.ps1"
    $managedRuntimeTarget = Join-Path $projectPath $managedRuntimeRelative
    $managedRuntimeSource = Join-Path $installedPackageRoot $managedRuntimeRelative

    Add-Content -Path $managedRuntimeTarget -Value (
        [Environment]::NewLine + "# release-e2e-drift"
    )

    $driftedHash = (Get-FileHash $managedRuntimeTarget -Algorithm SHA256).Hash
    $sourceHash = (Get-FileHash $managedRuntimeSource -Algorithm SHA256).Hash

    if ($driftedHash -eq $sourceHash) {
        throw "Release E2E could not create managed runtime drift before update."
    }

    Push-Location $projectPath
    try {
        & $aicoCommand update .
        if ($LASTEXITCODE -ne 0) {
            throw "Packaged aico update failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    $userHashAfter = (Get-FileHash $userOwnedPath -Algorithm SHA256).Hash
    if ($userHashAfter -ne $userHashBefore) {
        throw "Packaged aico update modified a project-owned file."
    }

    $updatedRuntimeHash = (Get-FileHash $managedRuntimeTarget -Algorithm SHA256).Hash
    if ($updatedRuntimeHash -ne $sourceHash) {
        throw (
            "Packaged aico update did not restore managed runtime from the " +
            "installed package artifact."
        )
    }

    $manifest = Get-Content (
        Join-Path $projectPath ".codex\managed-files.json"
    ) -Raw -Encoding UTF8 | ConvertFrom-Json

    if ([int]$manifest.version -ne 1) {
        throw "Packaged project has unsupported managed-files manifest version."
    }

    if (@($manifest.managed_files) -notcontains "scripts/provider-router.ps1") {
        throw "Managed-files manifest lost the provider-router runtime ownership entry."
    }

    Write-Host (
        "PASS: installed tarball validated aico new and aico install ., " +
        "bootstrapped Python/TUI, preserved user files, and safely updated managed runtime."
    ) -ForegroundColor Green
}
finally {
    $env:HOME = $oldHome
    $env:USERPROFILE = $oldUserProfile
    $env:PYTHONPATH = $oldPythonPath
    $env:NODE_PATH = $oldNodePath

    if (Test-Path $e2eRoot) {
        Remove-Item $e2eRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
