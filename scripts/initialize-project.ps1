param(
    [string]$ProjectPath = "."
)

$ErrorActionPreference = "Stop"

$ProjectPath = Resolve-Path $ProjectPath

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       AI COMPANY OS INITIALIZATION       " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Project:" -ForegroundColor Yellow
Write-Host $ProjectPath

Write-Host ""
Write-Host "Analizando proyecto..." -ForegroundColor Cyan

$GitExists = Test-Path (Join-Path $ProjectPath ".git")
$PackageJson = Test-Path (Join-Path $ProjectPath "package.json")
$Requirements = Test-Path (Join-Path $ProjectPath "requirements.txt")
$PyProject = Test-Path (Join-Path $ProjectPath "pyproject.toml")

Write-Host ""

if ($GitExists) {
    Write-Host "[OK] Git repository detected" -ForegroundColor Green
}
else {
    Write-Host "[INFO] Git repository not detected" -ForegroundColor Yellow
}

if ($PackageJson) {
    Write-Host "[OK] Node.js project detected" -ForegroundColor Green
}

if ($Requirements -or $PyProject) {
    Write-Host "[OK] Python project detected" -ForegroundColor Green
}

Write-Host ""

Write-Host "Company OS can now generate project context." -ForegroundColor Green

Write-Host ""