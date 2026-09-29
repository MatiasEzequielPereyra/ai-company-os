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

    $repoFull = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd([char[]]@("\\","/"))
    $installedFull = [System.IO.Path]::GetFullPath($installedPackageRoot).TrimEnd([char[]]@("\\","/"))

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

    foreach ($relative in @(
        ".codex\managed-files.json",
        ".codex\provider-config.json",
        ".codex\local-runtime-config.json",
        ".codex\workflow-profiles.json",
        ".codex\writable-policy.json",
        "scripts\update-runtime.ps1",
        "scripts\provider-router.ps1",
        "scripts\validate-engineering-plan-result.ps1",
        "scripts\providers\invoke-codex.ps1",
        "scripts\providers\invoke-ollama.ps1",
        "schemas\agent-result.schema.json",
        "schemas\engineering-plan-result.schema.json"
    )) {
        if (-not (Test-Path (Join-Path $projectPath $relative) -PathType Leaf)) {
            throw "Packaged project creation is missing required runtime artifact: $relative"
        }
    }

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
        "PASS: installed tarball created and inspected an isolated project, " +
        "bootstrapped Python/TUI, and safely updated managed runtime."
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
