param(
    [string]$ProjectPath = "."
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param([string]$Path, [string]$Value)
    [System.IO.File]::WriteAllText($Path, $Value, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-RelativeList {
    param([string]$Root, [string[]]$Names)
    $found = @()
    foreach ($name in $Names) {
        if (Test-Path (Join-Path $Root $name)) { $found += $name }
    }
    return $found
}

$resolved = (Resolve-Path $ProjectPath).Path
$projectName = Split-Path $resolved -Leaf
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       AI COMPANY OS PROJECT INTAKE       " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Project: $resolved" -ForegroundColor Yellow

$gitDetected = Test-Path (Join-Path $resolved ".git")
$branch = "UNKNOWN"
$remote = "UNKNOWN"
$commit = "UNKNOWN"

if ($gitDetected -and (Get-Command git -ErrorAction SilentlyContinue)) {
    try { $branch = (& git -C $resolved branch --show-current 2>$null).Trim() } catch {}
    try { $remote = (& git -C $resolved remote get-url origin 2>$null).Trim() } catch {}
    try { $commit = (& git -C $resolved rev-parse HEAD 2>$null).Trim() } catch {}
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = "DETACHED_OR_UNKNOWN" }
    if ([string]::IsNullOrWhiteSpace($remote)) { $remote = "UNKNOWN" }
    if ([string]::IsNullOrWhiteSpace($commit)) { $commit = "UNKNOWN" }
}

$languages = @()
$frameworks = @()
$packageManager = "UNKNOWN"
$commands = @()
$packageJsonPath = Join-Path $resolved "package.json"

if (Test-Path $packageJsonPath) {
    $languages += "JavaScript/TypeScript"
    try {
        $packageJson = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
        $deps = @{}
        if ($packageJson.dependencies) { $packageJson.dependencies.psobject.Properties | ForEach-Object { $deps[$_.Name] = $_.Value } }
        if ($packageJson.devDependencies) { $packageJson.devDependencies.psobject.Properties | ForEach-Object { $deps[$_.Name] = $_.Value } }

        if ($deps.ContainsKey("next")) { $frameworks += "Next.js" }
        if ($deps.ContainsKey("react")) { $frameworks += "React" }
        if ($deps.ContainsKey("vite")) { $frameworks += "Vite" }
        if ($deps.ContainsKey("@supabase/supabase-js")) { $frameworks += "Supabase" }
        if ($deps.ContainsKey("express")) { $frameworks += "Express" }

        if ($packageJson.scripts) {
            $packageJson.scripts.psobject.Properties | ForEach-Object {
                $commands += ($_.Name + ": " + $_.Value)
            }
        }
    }
    catch {
        Write-Host "[WARN] package.json could not be parsed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (Test-Path (Join-Path $resolved "pnpm-lock.yaml")) { $packageManager = "pnpm" }
elseif (Test-Path (Join-Path $resolved "yarn.lock")) { $packageManager = "yarn" }
elseif (Test-Path (Join-Path $resolved "package-lock.json")) { $packageManager = "npm" }
elseif (Test-Path $packageJsonPath) { $packageManager = "npm (lockfile not detected)" }

if ((Test-Path (Join-Path $resolved "requirements.txt")) -or (Test-Path (Join-Path $resolved "pyproject.toml"))) { $languages += "Python" }
if (Test-Path (Join-Path $resolved "go.mod")) { $languages += "Go" }
if (Test-Path (Join-Path $resolved "Cargo.toml")) { $languages += "Rust" }

$languages = @($languages | Select-Object -Unique)
$frameworks = @($frameworks | Select-Object -Unique)
if ($languages.Count -eq 0) { $languages = @("UNKNOWN") }
if ($frameworks.Count -eq 0) { $frameworks = @("UNKNOWN") }

$structure = Get-RelativeList $resolved @("src","app","pages","api","server","supabase","public","tests","test","scripts","docs",".github",".codex","tasks")
$docsDir = Join-Path $resolved "docs"
$engineeringDir = Join-Path $docsDir "engineering"
if (-not (Test-Path $engineeringDir)) { New-Item -ItemType Directory -Force -Path $engineeringDir | Out-Null }

function Format-Items {
    param($Items)
    $a = @($Items)
    if ($a.Count -eq 0) { return "-" }
    return (($a | ForEach-Object { "- " + $_ }) -join [Environment]::NewLine)
}

$intakePath = Join-Path $engineeringDir "project-intake.md"
$lines = @(
    "# Project Intake",
    "",
    "Generated: $now",
    "",
    "## Project",
    "",
    "Name: $projectName",
    "Path: $resolved",
    "",
    "## Git",
    "",
    "Repository detected: $gitDetected",
    "Branch: $branch",
    "Commit: $commit",
    "Origin: $remote",
    "",
    "## Detected Languages",
    "",
    (Format-Items $languages),
    "",
    "## Detected Frameworks and Services",
    "",
    (Format-Items $frameworks),
    "",
    "## Package Manager",
    "",
    $packageManager,
    "",
    "## Detected Repository Structure",
    "",
    (Format-Items $structure),
    "",
    "## Package Scripts",
    "",
    (Format-Items $commands),
    "",
    "## Intake Status",
    "",
    "- Automated repository discovery completed.",
    "- Product intent still requires PM validation from README, project brief, and user instructions.",
    "- Architecture assumptions require CTO validation before they become decisions.",
    "- Generated data is descriptive only; it does not authorize implementation.",
    "",
    "## Next Company Actions",
    "",
    "1. PM reviews product intent and confirmed scope.",
    "2. CTO reviews architecture and technical constraints.",
    "3. Engineering Manager converts approved work into tasks.",
    "4. Execution begins only after task readiness and authorization checks."
)

Write-Utf8NoBom $intakePath ($lines -join [Environment]::NewLine)

Write-Host ""
Write-Host "[OK] Project intake generated" -ForegroundColor Green
Write-Host $intakePath
Write-Host ""
Write-Host "Detected languages: $($languages -join ', ')"
Write-Host "Detected frameworks: $($frameworks -join ', ')"
Write-Host "Package manager: $packageManager"
Write-Host "Git branch: $branch"
Write-Host ""
Write-Host "Next: review docs/engineering/project-intake.md and continue PRODUCT/ARCHITECTURE planning." -ForegroundColor Cyan
