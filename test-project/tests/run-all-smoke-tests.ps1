param()

$ErrorActionPreference = "Stop"

$testsRoot = $PSScriptRoot

$tests = @(
    "test-project-intake.ps1",
    "test-new-project-contract.ps1",
    "test-planning-engine.ps1",
    "test-readiness-engine.ps1",
    "test-dispatch-engine.ps1",
    "test-result-intake.ps1",
    "test-review-engine.ps1",
    "test-final-gates.ps1",
    "test-dependency-refresh.ps1",
    "test-orchestrator.ps1",
    "test-agent-runtime-contract.ps1",
    "test-canonical-contracts.ps1",
    "test-provider-router-contract.ps1",
    "test-workflow-profiles.ps1",
    "test-end-to-end-code-change.ps1",
    "test-engineering-backlog-materializer.ps1",
    "test-engineering-backlog-generator-repair.ps1"
)

$results = @()
$started = Get-Date

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       AI COMPANY OS - SMOKE TESTS        " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($test in $tests) {
    $path = Join-Path $testsRoot $test

    if (-not (Test-Path $path)) {
        throw "Smoke test missing: $path"
    }

    Write-Host "RUN  $test" -ForegroundColor Yellow
    $testStart = Get-Date

    try {
        & $path
        $duration = [math]::Round(((Get-Date) - $testStart).TotalSeconds, 2)

        $results += [PSCustomObject]@{
            Test = $test
            Result = "PASS"
            Seconds = $duration
        }

        Write-Host "PASS $test ($duration s)" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        $duration = [math]::Round(((Get-Date) - $testStart).TotalSeconds, 2)

        $results += [PSCustomObject]@{
            Test = $test
            Result = "FAIL"
            Seconds = $duration
        }

        Write-Host ""
        Write-Host "FAIL $test ($duration s)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""
        Write-Host "Stopping after first failure." -ForegroundColor Red

        Write-Host ""
        $results | Format-Table Test, Result, Seconds -AutoSize

        exit 1
    }
}

$total = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "              ALL TESTS PASS              " -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

$results | Format-Table Test, Result, Seconds -AutoSize

Write-Host ""
Write-Host "Passed: $($results.Count)/$($tests.Count)"
Write-Host "Total seconds: $total"
