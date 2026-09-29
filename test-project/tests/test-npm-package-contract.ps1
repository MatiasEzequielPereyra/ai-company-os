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

    $files = @($pack[0].files | ForEach-Object { ([string]$_.path).Replace("\","/") })

    foreach ($relative in @(
        "npm-bin/aico.js",
        "npm-bin/bootstrap.js",
        "scripts/update-runtime.ps1",
        "scripts/provider-router.ps1",
        "scripts/run-agent-task.ps1",
        "scripts/run-gate-agent.ps1",
        "scripts/run-writable-agent.ps1",
        "scripts/validate-engineering-plan-result.ps1",
        "scripts/providers/invoke-codex.ps1",
        "scripts/providers/invoke-ollama.ps1",
        "scripts/providers/invoke-openrouter.ps1",
        "scripts/providers/invoke-gemini.ps1",
        "scripts/providers/invoke-deepseek.ps1",
        "scripts/providers/invoke-xai.ps1",
        "scripts/local-runtime/resolve-local-runtime.ps1",
        ".codex/provider-config.json",
        ".codex/local-runtime-config.json",
        ".codex/workflow-profiles.json",
        ".codex/writable-policy.json",
        "schemas/agent-result.schema.json",
        "schemas/engineering-plan-result.schema.json",
        "src/company_os/cli/app.py",
        "INSTALL-QUICKSTART.txt"
    )) {
        if ($files -notcontains $relative) {
            throw "npm package is missing required runtime artifact: $relative"
        }
    }

    $allowedExact = @(
        "package.json",
        "README.md",
        "LICENSE",
        "AGENTS.md",
        "pyproject.toml",
        "INSTALL-QUICKSTART.txt",
        "tasks/README.md"
    )

    $allowedPrefixes = @(
        ".agents/",
        ".codex/agents/",
        ".codex/policies/",
        ".codex/protocols/",
        ".codex/templates/",
        ".codex/workflows/",
        "npm-bin/",
        "schemas/",
        "scripts/",
        "src/",
        "templates/"
    )

    $allowedCodexFiles = @(
        ".codex/config.toml",
        ".codex/provider-config.json",
        ".codex/local-runtime-config.json",
        ".codex/workflow-profiles.json",
        ".codex/writable-policy.json"
    )

    foreach ($relative in $files) {
        $allowed = (
            $allowedExact -contains $relative -or
            $allowedCodexFiles -contains $relative
        )

        if (-not $allowed) {
            foreach ($prefix in $allowedPrefixes) {
                if ($relative.StartsWith(
                    $prefix,
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                    $allowed = $true
                    break
                }
            }
        }

        if (-not $allowed) {
            throw "npm package contains undeclared repository artifact: $relative"
        }
    }

    $forbiddenPatterns = @(
        '(?i)(^|/)\.git($|/)',
        '(?i)(^|/)\.github($|/)',
        '(?i)(^|/)\.env($|[./])',
        '(?i)(^|/)node_modules($|/)',
        '(?i)(^|/)\.aico-python($|/)',
        '(?i)(^|/)(\.venv|venv)($|/)',
        '(?i)(^|/)coverage($|/)',
        '(?i)(^|/)\.pytest_cache($|/)',
        '(?i)(^|/)__pycache__($|/)',
        '(?i)^test-project/',
        '(?i)^npm-bin/package\.test\.js
        '(?i)^tasks/AICO-',
        '(?i)^\.codex/state/',
        '(?i)\.(pem|p12|pfx|key)$'
    )

    foreach ($relative in $files) {
        foreach ($pattern in $forbiddenPatterns) {
            if ($relative -match $pattern) {
                throw "npm package contains forbidden artifact: $relative"
            }
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

        & $npmCommand.Source install --prefix $installRoot --ignore-scripts --no-audit --no-fund $tarballPath
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
            "scripts\providers\invoke-ollama.ps1",
            "scripts\providers\invoke-openrouter.ps1",
            "scripts\providers\invoke-gemini.ps1",
            "scripts\providers\invoke-deepseek.ps1",
            "scripts\providers\invoke-xai.ps1",
            "scripts\local-runtime\resolve-local-runtime.ps1",
            ".codex\provider-config.json",
            ".codex\workflow-profiles.json",
            "schemas\engineering-plan-result.schema.json"
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

    Write-Host (
        "PASS: npm test, package allowlist/denylist inspection, " +
        "actual tarball creation, and isolated tarball installation"
    ) -ForegroundColor Green
}
finally {
    Pop-Location
}
,
        '(?i)^tasks/AICO-',
        '(?i)^\.codex/state/',
        '(?i)\.(pem|p12|pfx|key)$'
    )

    foreach ($relative in $files) {
        foreach ($pattern in $forbiddenPatterns) {
            if ($relative -match $pattern) {
                throw "npm package contains forbidden artifact: $relative"
            }
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

        & $npmCommand.Source install --prefix $installRoot --ignore-scripts --no-audit --no-fund $tarballPath
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
            "scripts\providers\invoke-ollama.ps1",
            "scripts\providers\invoke-openrouter.ps1",
            "scripts\providers\invoke-gemini.ps1",
            "scripts\providers\invoke-deepseek.ps1",
            "scripts\providers\invoke-xai.ps1",
            "scripts\local-runtime\resolve-local-runtime.ps1",
            ".codex\provider-config.json",
            ".codex\workflow-profiles.json",
            "schemas\engineering-plan-result.schema.json"
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

    Write-Host (
        "PASS: npm test, package allowlist/denylist inspection, " +
        "actual tarball creation, and isolated tarball installation"
    ) -ForegroundColor Green
}
finally {
    Pop-Location
}
