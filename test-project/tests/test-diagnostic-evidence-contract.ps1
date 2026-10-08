param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$validator = Join-Path $repoRoot "scripts\validate-diagnostic-evidence.ps1"
if (-not (Test-Path $validator -PathType Leaf)) {
    throw "Diagnostic validator missing: $validator"
}

$tempRoot = Join-Path $env:TEMP ("aico-diagnostic-contract-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

function Write-Fixture {
    param([string]$Name,[object]$Payload)
    $path = Join-Path $tempRoot ($Name + ".json")
    [IO.File]::WriteAllText($path,($Payload | ConvertTo-Json -Depth 100),(New-Object Text.UTF8Encoding($false)))
    return $path
}

function New-ValidEvidence {
    return [ordered]@{
        schema_version = "1"
        task_id = "AICO-901"
        workflow = "BUG"
        state = "COMPLETE"
        reproduction = [ordered]@{
            kind = "COMMAND"
            command = "python -B -m unittest discover -s tests_bug"
            working_directory = "."
            broken_when = "EXIT_NONZERO"
            signal_fingerprint = ("a" * 64)
            pre_fix = [ordered]@{
                observation = "BROKEN_OBSERVED"
                receipt_ref = "pre"
            }
        }
        receipts = @(
            [ordered]@{ id="pre"; phase="PRE_FIX"; source="RUNTIME"; command="python -B -m unittest discover -s tests_bug"; exit_code=1; output_sha256=("b"*64); output_excerpt="failed" },
            [ordered]@{ id="h1"; phase="HYPOTHESIS"; source="RUNTIME"; command="python -B -m unittest tests_bug.test_root_cause_probe"; exit_code=1; output_sha256=("c"*64); output_excerpt="failed" },
            [ordered]@{ id="reg"; phase="REGRESSION"; source="RUNTIME"; command="python -B -m unittest discover -s tests_bug"; exit_code=0; output_sha256=("d"*64); output_excerpt="passed" },
            [ordered]@{ id="post"; phase="POST_FIX"; source="RUNTIME"; command="python -B -m unittest discover -s tests_bug"; exit_code=0; output_sha256=("e"*64); output_excerpt="passed" }
        )
        attempts = @(
            [ordered]@{
                index = 1
                corrective = $false
                hypotheses = @(
                    [ordered]@{
                        id="H1"
                        statement="The implementation returns the wrong value."
                        prediction="The regression fails before correction."
                        falsifier="The regression passes before correction."
                        experiment_command="python -B -m unittest tests_bug.test_root_cause_probe"
                        supported_when="EXIT_NONZERO"
                        result="SUPPORTED"
                        receipt_ref="h1"
                    }
                )
                cause = [ordered]@{
                    status="CONFIRMED"
                    statement="The implementation returns the wrong value."
                    hypothesis_refs=@("H1")
                    receipt_refs=@("h1")
                }
                resolution = [ordered]@{
                    classification="REPAIR"
                    summary="Return the expected value."
                    residual_risk=""
                }
            }
        )
        regression = [ordered]@{ receipt_refs=@("reg") }
        post_fix_replay = [ordered]@{
            signal_fingerprint=("a"*64)
            observation="FIXED_OBSERVED"
            receipt_ref="post"
        }
    }
}

function Assert-Rejected {
    param([object]$Payload,[string]$Pattern,[string]$Label)
    $path = Write-Fixture -Name ([Guid]::NewGuid().ToString("N")) -Payload $Payload
    $rejected = $false
    try { & $validator -JsonPath $path | Out-Null }
    catch {
        if ($_.Exception.Message -match $Pattern) { $rejected = $true }
        else { throw }
    }
    if (-not $rejected) { throw "$Label was not rejected." }
}

try {
    $good = New-ValidEvidence
    & $validator -JsonPath (Write-Fixture -Name "good" -Payload $good) | Out-Null

    $changedSignal = New-ValidEvidence
    $changedSignal.post_fix_replay.signal_fingerprint = ("f" * 64)
    Assert-Rejected -Payload $changedSignal -Pattern "exact frozen reproduction signal" -Label "Signal substitution"

    $unsupportedCause = New-ValidEvidence
    $unsupportedCause.receipts[1].exit_code = 0
    $unsupportedCause.attempts[0].hypotheses[0].result = "FALSIFIED"
    Assert-Rejected -Payload $unsupportedCause -Pattern "SUPPORTED hypotheses" -Label "Confirmed cause from falsified hypothesis"

    $proseOnlyCause = New-ValidEvidence
    $proseOnlyCause.attempts[0].cause.hypothesis_refs = @()
    $proseOnlyCause.attempts[0].cause.receipt_refs = @()
    Assert-Rejected -Payload $proseOnlyCause -Pattern "requires hypothesis and receipt evidence" -Label "Prose-only confirmed cause"

    $workaround = New-ValidEvidence
    $workaround.attempts[0].resolution.classification = "WORKAROUND"
    $workaround.attempts[0].resolution.residual_risk = ""
    Assert-Rejected -Payload $workaround -Pattern "WORKAROUND requires explicit residual_risk" -Label "Silent workaround"

    $missingReceipt = New-ValidEvidence
    $missingReceipt.attempts[0].hypotheses[0].receipt_ref = "missing"
    Assert-Rejected -Payload $missingReceipt -Pattern "missing receipt" -Label "Invented hypothesis receipt"

    $failedVerification = New-ValidEvidence
    $failedVerification.state = "FAILED_VERIFICATION"
    $failedVerification.regression.receipt_refs = @()
    $failedVerification.post_fix_replay.observation = "NOT_RUN"
    $failedVerification.post_fix_replay.receipt_ref = ""
    & $validator -JsonPath (Write-Fixture -Name "failed-verification" -Payload $failedVerification) | Out-Null

    $failedPostFix = New-ValidEvidence
    $failedPostFix.state = "FAILED_POST_FIX"
    $failedPostFix.receipts[3].exit_code = 1
    $failedPostFix.post_fix_replay.observation = "BROKEN_OBSERVED"
    & $validator -JsonPath (Write-Fixture -Name "failed-post-fix" -Payload $failedPostFix) | Out-Null

    Write-Host "PASS: diagnostic evidence semantic contract" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
