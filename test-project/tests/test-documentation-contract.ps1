param()

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

$publicDocs = @(
    "README.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "CHANGELOG.md",
    "docs\README.md",
    "docs\QUICKSTART.md",
    "docs\FIRST-RUN-CHECKLIST.md",
    "docs\USER-GUIDE.md",
    "docs\COMMAND-REFERENCE.md",
    "docs\TROUBLESHOOTING.md",
    "docs\FAQ.md",
    "docs\END-TO-END-WALKTHROUGH.md",
    "docs\DOCUMENTATION-STATUS.md",
    "docs\DOCUMENTATION-USABILITY-REVIEW.md",
    "docs\operations\provider-runtime.md",
    "docs\operations\local-runtime.md",
    "docs\operations\update-ownership.md"
)

foreach ($relative in $publicDocs) {
    $path = Join-Path $root $relative
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Public documentation file missing: $relative"
    }
}

# Repository-relative Markdown links must resolve without network access.
$linkPattern = '\[[^\]]+\]\(([^)]+)\)'

foreach ($relative in $publicDocs) {
    if (-not $relative.EndsWith(".md",[System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    $path = Join-Path $root $relative
    $content = Get-Content $path -Raw -Encoding UTF8

    foreach ($match in [regex]::Matches($content,$linkPattern)) {
        $target = [string]$match.Groups[1].Value
        if (
            [string]::IsNullOrWhiteSpace($target) -or
            $target.StartsWith("#") -or
            $target -match '^(?i:https?|mailto):'
        ) {
            continue
        }

        $target = ($target -split '#',2)[0]
        $target = ($target -split '\?',2)[0]
        if ([string]::IsNullOrWhiteSpace($target)) {
            continue
        }

        $base = Split-Path $path -Parent
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $base $target))

        if (-not (Test-Path $resolved)) {
            throw "Broken local documentation link in $relative -> $target"
        }
    }
}

# The npm README is packaged without docs/**, so detailed docs links must remain
# absolute GitHub links rather than package-relative links.
$readme = Get-Content (Join-Path $root "README.md") -Raw -Encoding UTF8
if ($readme -match '\]\(\.?/?docs/') {
    throw "Root README contains a package-relative docs/ link. Use an absolute GitHub URL."
}

# Public docs must not leak a developer-local path.
foreach ($relative in $publicDocs) {
    $content = Get-Content (Join-Path $root $relative) -Raw -Encoding UTF8
    if ($content -match [regex]::Escape('C:\Users\pereyram')) {
        throw "Public documentation contains a developer-local path: $relative"
    }
}

# Known stale default routing claim from the old manual must not reappear.
foreach ($relative in $publicDocs) {
    $content = Get-Content (Join-Path $root $relative) -Raw -Encoding UTF8

    if ($content -match 'Ollama\s*(?:->|→)\s*OpenRouter') {
        throw "Stale multi-provider general Auto claim found in $relative"
    }
}

# Docs must reflect the actual general Auto configuration.
$providerConfigPath = Join-Path $root ".codex\provider-config.json"
$providerConfig = Get-Content $providerConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$autoOrder = @($providerConfig.auto_order | ForEach-Object { [string]$_ })

if (($autoOrder -join ",") -ne "Ollama") {
    throw "Documentation contract expects current general Auto policy to be Ollama-only; update the docs test with the product change."
}

$providerDoc = Get-Content (Join-Path $root "docs\operations\provider-runtime.md") -Raw -Encoding UTF8
if ($providerDoc -notmatch 'General Auto' -or $providerDoc -notmatch 'Auto\s*(?:→|->)\s*Ollama') {
    throw "Provider runtime documentation does not state the current general Auto policy."
}

# The command reference must contain every public npm/Python CLI command.
$commandReference = Get-Content (Join-Path $root "docs\COMMAND-REFERENCE.md") -Raw -Encoding UTF8
$expectedCommands = @(
    "aico",
    "aico shell",
    "aico version",
    "aico --help",
    "aico new",
    "aico install",
    "aico init",
    "aico update",
    "aico use",
    "aico current",
    "aico status",
    "aico tasks",
    "aico workflow",
    "aico activity",
    "aico handoffs",
    "aico runtime",
    "aico doctor"
)

foreach ($command in $expectedCommands) {
    if ($commandReference.IndexOf($command,[System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "Command reference is missing public command: $command"
    }
}

# Force install may be documented as an explicit reinstall option, but never as
# the supported upgrade path.
if (
    $commandReference -match '(?is)(recommended|recomendado|upgrade|actualizar)[^\r\n]{0,100}aico install \. --force'
) {
    throw "Command reference presents forced install as an upgrade path."
}

Write-Host "PASS: public documentation links, routing claims, package README links and command surface are consistent." -ForegroundColor Green
