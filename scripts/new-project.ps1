param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,

    [string]$Destination = "."
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       AI COMPANY OS - NEW PROJECT       " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$ProjectPath = Join-Path $Destination $ProjectName

if (Test-Path $ProjectPath) {
    Write-Host "ERROR: El proyecto ya existe:" -ForegroundColor Red
    Write-Host $ProjectPath
    exit 1
}

Write-Host "Creando proyecto:" -ForegroundColor Green
Write-Host $ProjectPath
Write-Host ""

New-Item -ItemType Directory -Force -Path $ProjectPath | Out-Null

# ------------------------------------------------------------
# Core directories
# ------------------------------------------------------------

$Directories = @(
    ".codex",
    ".codex\agents",
    ".codex\policies",
    ".codex\protocols",
    ".codex\workflows",

    ".agents",
    ".agents\skills",

    "docs",
    "docs\product",
    "docs\architecture",
    "docs\engineering",
    "docs\operations",
    "docs\decisions",

    "tasks",
    "tasks\backlog",
    "tasks\ready",
    "tasks\active",
    "tasks\review",
    "tasks\qa",
    "tasks\done",

    "scripts"
)

foreach ($Directory in $Directories) {

    $Path = Join-Path $ProjectPath $Directory

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $Path | Out-Null
}

Write-Host "Directorios creados." -ForegroundColor Green

# ------------------------------------------------------------
# Core files
# ------------------------------------------------------------

$Files = @(
    "AGENTS.md",

    "docs\PROJECT-BRIEF.md",

    "docs\product\product-context.md",
    "docs\architecture\architecture-context.md",
    "docs\engineering\engineering-context.md",
    "docs\operations\operations-context.md",

    ".codex\config.toml",

    ".codex\agents\ceo.toml",
    ".codex\agents\pm.toml",
    ".codex\agents\cto.toml",
    ".codex\agents\engineering-manager.toml",
    ".codex\agents\backend.toml",
    ".codex\agents\frontend.toml",
    ".codex\agents\devops.toml",
    ".codex\agents\qa.toml",
    ".codex\agents\security.toml"
)

foreach ($File in $Files) {

    $Path = Join-Path $ProjectPath $File

    if (-not (Test-Path $Path)) {

        New-Item `
            -ItemType File `
            -Force `
            -Path $Path | Out-Null
    }
}

Write-Host "Archivos base creados." -ForegroundColor Green

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       PROJECT CREATED SUCCESSFULLY       " -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Proyecto:" -ForegroundColor Yellow
Write-Host $ProjectPath

Write-Host ""
Write-Host "Siguiente paso:" -ForegroundColor Yellow
Write-Host "cd `"$ProjectPath`""
Write-Host ""

# ------------------------------------------------------------
# Copy Company OS templates
# ------------------------------------------------------------

$ScriptRoot = Split-Path -Parent $PSScriptRoot

$TemplateRoot = Join-Path $ScriptRoot "templates"

Write-Host ""
Write-Host "Instalando Company OS..." -ForegroundColor Cyan

# AGENTS.md

Copy-Item `
    (Join-Path $TemplateRoot "AGENTS.md") `
    (Join-Path $ProjectPath "AGENTS.md") `
    -Force

# Codex configuration

Copy-Item `
    (Join-Path $TemplateRoot "config.toml") `
    (Join-Path $ProjectPath ".codex\config.toml") `
    -Force

# Agent instructions

Copy-Item `
    (Join-Path $TemplateRoot "agents\*.md") `
    (Join-Path $ProjectPath ".codex\agents\") `
    -Force

# Project documentation

Copy-Item `
    (Join-Path $TemplateRoot "docs\PROJECT-BRIEF.md") `
    (Join-Path $ProjectPath "docs\PROJECT-BRIEF.md") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "docs\product-context.md") `
    (Join-Path $ProjectPath "docs\product\product-context.md") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "docs\architecture-context.md") `
    (Join-Path $ProjectPath "docs\architecture\architecture-context.md") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "docs\engineering-context.md") `
    (Join-Path $ProjectPath "docs\engineering\engineering-context.md") `
    -Force

Copy-Item `
    (Join-Path $TemplateRoot "docs\operations-context.md") `
    (Join-Path $ProjectPath "docs\operations\operations-context.md") `
    -Force

Write-Host "Company OS instalado." -ForegroundColor Green

Copy-Item `
    (Join-Path $TemplateRoot "agents\*.toml") `
    (Join-Path $ProjectPath ".codex\agents\") `
    -Force