param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$packageJsonPath = Join-Path $repoRoot "package.json"
$pyprojectPath = Join-Path $repoRoot "pyproject.toml"

$package = Get-Content $packageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$packageVersion = [string]$package.version

if ([string]::IsNullOrWhiteSpace($packageVersion)) {
    throw "package.json must declare a non-empty version."
}

$pyprojectText = Get-Content $pyprojectPath -Raw -Encoding UTF8
$projectBlock = [regex]::Match(
    $pyprojectText,
    '(?ms)^\[project\]\s*(?<body>.*?)(?=^\[|\z)'
)

if (-not $projectBlock.Success) {
    throw "pyproject.toml is missing a [project] section."
}

$pythonVersionMatch = [regex]::Match(
    $projectBlock.Groups["body"].Value,
    '(?m)^version\s*=\s*"(?<version>[^"]+)"\s*$'
)

if (-not $pythonVersionMatch.Success) {
    throw "pyproject.toml [project] must declare version."
}

$pythonVersion = $pythonVersionMatch.Groups["version"].Value

if ($packageVersion -ne $pythonVersion) {
    throw (
        "Release version mismatch. package.json is authoritative: " +
        "package.json=$packageVersion pyproject.toml=$pythonVersion"
    )
}

$semverPattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)' +
    '(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$'

if ($packageVersion -notmatch $semverPattern) {
    throw "Release version is not valid SemVer: $packageVersion"
}

Write-Host (
    "PASS: release versions are synchronized at $packageVersion " +
    "(package.json authoritative)"
) -ForegroundColor Green
