param(
    [string]$ProjectPath = "."
)

$ErrorActionPreference = "Stop"

$readiness = Join-Path $PSScriptRoot "evaluate-readiness.ps1"
if (-not (Test-Path $readiness)) {
    throw "evaluate-readiness.ps1 not found: $readiness"
}

Write-Host "Refreshing dependent task readiness..." -ForegroundColor Cyan
& $readiness -ProjectPath $ProjectPath -Apply
