param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$repairScript = Join-Path $repoRoot "scripts\repair-artifact-encoding.ps1"

if (-not (Test-Path $repairScript)) {
    throw "repair-artifact-encoding.ps1 missing"
}

$tempRoot = Join-Path $env:TEMP ("aico-encoding-repair-" + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\engineering") | Out-Null

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $cp1252 = [System.Text.Encoding]::GetEncoding(1252)

    $arrow = [string][char]0x2192
    $mojibake = $arrow

    for ($i = 0; $i -lt 3; $i++) {
        $bytes = $utf8.GetBytes($mojibake)
        $mojibake = $cp1252.GetString($bytes)
    }

    $path = Join-Path $tempRoot "docs\engineering\fixture.md"
    $content = "Critical path: A " + $mojibake + " B"

    [System.IO.File]::WriteAllText(
        $path,
        $content,
        (New-Object System.Text.UTF8Encoding($false))
    )

    & $repairScript -ProjectPath $tempRoot -Apply

    $repaired = Get-Content $path -Raw -Encoding UTF8

    if ($repaired -notmatch ([regex]::Escape($arrow))) {
        throw "Artifact encoding repair did not recover the original arrow."
    }

    if ($repaired -ne ("Critical path: A " + $arrow + " B")) {
        throw "Artifact encoding repair changed unrelated content."
    }
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}

Write-Host "PASS: artifact encoding repair test" -ForegroundColor Green
