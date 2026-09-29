param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($null -eq $npmCommand) {
    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
}
if ($null -eq $npmCommand) {
    throw "npm is required for package validation."
}

Push-Location $repoRoot
try {
    & $npmCommand.Source test
    if ($LASTEXITCODE -ne 0) {
        throw "npm test failed with exit code $LASTEXITCODE."
    }

    $packOutput = @(& $npmCommand.Source pack --dry-run --json --ignore-scripts)
    if ($LASTEXITCODE -ne 0) {
        throw "npm pack --dry-run failed with exit code $LASTEXITCODE."
    }

    $packText = $packOutput -join [Environment]::NewLine
    try {
        $pack = $packText | ConvertFrom-Json
    }
    catch {
        throw "npm pack --dry-run did not return valid JSON: $($_.Exception.Message)"
    }

    if (@($pack).Count -lt 1) {
        throw "npm pack --dry-run returned no package metadata."
    }

    $files = @($pack[0].files | ForEach-Object { [string]$_.path })

    foreach ($relative in @(
        "npm-bin/aico.js",
        "npm-bin/bootstrap.js",
        "scripts/update-runtime.ps1",
        "scripts/provider-router.ps1",
        "scripts/validate-engineering-plan-result.ps1",
        "scripts/providers/invoke-codex.ps1",
        "scripts/providers/invoke-ollama.ps1",
        ".codex/provider-config.json",
        ".codex/local-runtime-config.json",
        ".codex/writable-policy.json",
        "schemas/agent-result.schema.json",
        "schemas/engineering-plan-result.schema.json",
        "src/company_os/cli/app.py"
    )) {
        if ($files -notcontains $relative) {
            throw "npm package is missing required runtime artifact: $relative"
        }
    }

    foreach ($unexpected in @(
        "test-project/tests/test-provider-timeout.ps1",
        "test-project/tests/test-update-runtime-contract.ps1"
    )) {
        if ($files -contains $unexpected) {
            throw "npm package unexpectedly includes repository-only test artifact: $unexpected"
        }
    }

    $tempBase = if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        $env:TEMP
    }
    else {
        [System.IO.Path]::GetTempPath()
    }

    $packageTemp = Join-Path $tempBase ("aico-npm-package-" + [Guid]::NewGuid().ToString("N"))
    $installRoot = Join-Path $packageTemp "install"
    New-Item -ItemType Directory -Force -Path $packageTemp | Out-Null
    New-Item -ItemType Directory -Force -Path $installRoot | Out-Null

    try {
        $actualPackOutput = @(
            & $npmCommand.Source pack --json --ignore-scripts --pack-destination $packageTemp
        )

        if ($LASTEXITCODE -ne 0) {
            throw "npm pack failed with exit code $LASTEXITCODE."
        }

        try {
            $actualPack = ($actualPackOutput -join [Environment]::NewLine) | ConvertFrom-Json
        }
        catch {
            throw "npm pack did not return valid JSON: $($_.Exception.Message)"
        }

        if (@($actualPack).Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$actualPack[0].filename)) {
            throw "npm pack did not report a tarball filename."
        }

        $tarballPath = Join-Path $packageTemp ([string]$actualPack[0].filename)
        if (-not (Test-Path $tarballPath -PathType Leaf)) {
            throw "npm pack did not create the expected tarball: $tarballPath"
        }

        & $npmCommand.Source install --prefix $installRoot --ignore-scripts $tarballPath
        if ($LASTEXITCODE -ne 0) {
            throw "Installing the packed tarball failed with exit code $LASTEXITCODE."
        }

        $installedPackageRoot = Join-Path $installRoot "node_modules\@pereyram\ai-company-os"
        foreach ($relative in @(
            "npm-bin\aico.js",
            "scripts\update-runtime.ps1",
            "scripts\provider-router.ps1",
            "scripts\validate-engineering-plan-result.ps1",
            "scripts\providers\invoke-codex.ps1",
            ".codex\provider-config.json"
        )) {
            if (-not (Test-Path (Join-Path $installedPackageRoot $relative) -PathType Leaf)) {
                throw "Installed npm tarball is missing required artifact: $relative"
            }
        }

        $installedPackageJson = Get-Content (Join-Path $installedPackageRoot "package.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        $sourcePackageJson = Get-Content (Join-Path $repoRoot "package.json") -Raw -Encoding UTF8 | ConvertFrom-Json

        if ([string]$installedPackageJson.version -ne [string]$sourcePackageJson.version) {
            throw "Installed npm tarball version does not match source package version."
        }
    }
    finally {
        if (Test-Path $packageTemp) {
            Remove-Item $packageTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "PASS: npm test, npm pack inspection, and isolated tarball installation" -ForegroundColor Green
}
finally {
    Pop-Location
}
