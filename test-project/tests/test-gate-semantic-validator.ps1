param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts/task-execution-lock.ps1')
. (Join-Path $repoRoot 'scripts/review-grounding.ps1')
. (Join-Path $repoRoot 'test-project/helpers/grounded-review-fixture.ps1')
$groundedFixture=$null
$validator = Join-Path $repoRoot "scripts\validate-gate-result-semantics.ps1"
if (-not (Test-Path $validator -PathType Leaf)) {
    throw "Gate semantic validator missing: $validator"
}

$tempRoot = Join-Path $env:TEMP ("aico-gate-semantic-validator-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

function Write-FixtureJson {
    param([string]$Name,[object]$Payload)
    $path = Join-Path $tempRoot ($Name + ".json")
    [System.IO.File]::WriteAllText($path,($Payload | ConvertTo-Json -Depth 20),(New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Assert-Rejected {
    param([string]$Path,[string]$Pattern,[string]$Label)
    $rejected = $false
    try {
        & $validator -JsonPath $Path -GroundingContext $groundedFixture.Context | Out-Null
    }
    catch {
        if ($_.Exception.Message -match $Pattern) {
            $rejected = $true
        }
        else {
            throw
        }
    }
    if (-not $rejected) { throw "$Label was not rejected." }
}

try {
    $groundedFixture=New-GroundedRouterFixture -Root $tempRoot
    $reviewGood=Join-Path $tempRoot 'fixture-grounded-review.json'
    & $validator -JsonPath $reviewGood -GroundingContext $groundedFixture.Context | Out-Null

    $reviewBad = Write-FixtureJson "review-bad" @{
        recommendation = "CHANGES_REQUIRED"
        findings = "No concrete issue."
        verification = "Reviewed."
        missing_required_outputs = @()
        deliverable_defects = @()
    }
    Assert-Rejected -Path $reviewBad -Pattern "invalid Review CHANGES_REQUIRED" -Label "Defectless Review CHANGES_REQUIRED"

    $qaGood = Write-FixtureJson "qa-good" @{
        outcome = "FAIL"
        evidence = "Acceptance criterion failed."
        findings = "Concrete failed criterion."
        criteria_assessment = @(
            @{ criterion = "Feature works"; status = "UNSATISFIED"; evidence = "Observed failure." }
        )
    }
    & $validator -JsonPath $qaGood | Out-Null

    $qaBad = Write-FixtureJson "qa-bad" @{
        outcome = "FAIL"
        evidence = "No failing criterion."
        findings = "NONE"
        criteria_assessment = @(
            @{ criterion = "Feature works"; status = "SATISFIED"; evidence = "Observed success." }
        )
    }
    Assert-Rejected -Path $qaBad -Pattern "invalid QA FAIL" -Label "QA FAIL without UNSATISFIED criterion"

    $securityGood = Write-FixtureJson "security-good" @{
        outcome = "NOT_APPLICABLE"
        evidence = "No additional security-relevant aspect."
        findings = "NONE"
        security_relevant = $false
        deliverable_security_defects = @()
    }
    & $validator -JsonPath $securityGood | Out-Null

    $securityBad = Write-FixtureJson "security-bad" @{
        outcome = "PASS"
        evidence = "No security-relevant aspect."
        findings = "NONE"
        security_relevant = $false
        deliverable_security_defects = @()
    }
    Assert-Rejected -Path $securityBad -Pattern "invalid Security PASS" -Label "Security PASS with security_relevant=false"

    $unknown = Write-FixtureJson "unknown" @{ foo = "bar" }
    Assert-Rejected -Path $unknown -Pattern "gate result type could not be determined" -Label "Unknown gate payload"

    Write-Host "PASS: gate semantic validator contract" -ForegroundColor Green
}
finally {
    if($null-ne $groundedFixture){Exit-TaskExecutionLock -Lock $groundedFixture.Lease}
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}