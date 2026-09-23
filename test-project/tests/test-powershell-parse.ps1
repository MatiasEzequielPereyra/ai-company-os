param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$roots = @(
    (Join-Path $repoRoot "scripts"),
    (Join-Path $repoRoot "test-project\tests")
)

$failures = @()

foreach ($root in $roots) {
    Get-ChildItem $root -Filter "*.ps1" -File -Recurse | ForEach-Object {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $_.FullName,
            [ref]$tokens,
            [ref]$parseErrors
        )

        foreach ($parseError in @($parseErrors)) {
            $failures += [PSCustomObject]@{
                File = $_.FullName
                Line = $parseError.Extent.StartLineNumber
                Column = $parseError.Extent.StartColumnNumber
                Message = $parseError.Message
            }
        }
    }
}

if ($failures.Count -gt 0) {
    $details = $failures | ForEach-Object {
        "$($_.File):$($_.Line):$($_.Column) - $($_.Message)"
    }
    throw ("PowerShell parse validation failed:" + [Environment]::NewLine + ($details -join [Environment]::NewLine))
}

Write-Host "PASS: PowerShell parse validation" -ForegroundColor Green
