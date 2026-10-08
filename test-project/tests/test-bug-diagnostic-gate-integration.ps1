param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("aico-bug-gate-" + [Guid]::NewGuid().ToString("N"))

function Write-NoBom {
    param([string]$Path,[string]$Value)

    $parent = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    [IO.File]::WriteAllText(
        $Path,
        $Value,
        [Text.UTF8Encoding]::new($false)
    )
}

function Get-TaskStatus {
    param([string]$TaskPath)

    $line = Get-Content -LiteralPath $TaskPath |
        Where-Object { $_ -match '^Status:' } |
        Select-Object -First 1

    if ($null -eq $line) {
        throw "Task status line missing."
    }

    return ($line -replace '^Status:\s*','').Trim()
}

function New-CompleteEvidence {
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
            [ordered]@{
                id = "pre"
                phase = "PRE_FIX"
                source = "RUNTIME"
                command = "python -B -m unittest discover -s tests_bug"
                exit_code = 1
                output_sha256 = ("b" * 64)
                output_excerpt = "original defect reproduced"
            },

            [ordered]@{
                id = "h1"
                phase = "HYPOTHESIS"
                source = "RUNTIME"
                command = "python -B -m unittest tests_bug.test_root_cause_probe"
                exit_code = 1
                output_sha256 = ("c" * 64)
                output_excerpt = "causal experiment supported"
            },

            [ordered]@{
                id = "reg"
                phase = "REGRESSION"
                source = "RUNTIME"
                command = "python -B -m unittest discover -s tests_bug"
                exit_code = 0
                output_sha256 = ("d" * 64)
                output_excerpt = "regression passed"
            },

            [ordered]@{
                id = "post"
                phase = "POST_FIX"
                source = "RUNTIME"
                command = "python -B -m unittest discover -s tests_bug"
                exit_code = 0
                output_sha256 = ("e" * 64)
                output_excerpt = "original signal fixed"
            }
        )

        attempts = @(
            [ordered]@{
                index = 1
                corrective = $false

                hypotheses = @(
                    [ordered]@{
                        id = "H1"
                        statement = "The implementation returns the wrong value."
                        prediction = "The causal experiment exits non-zero."
                        falsifier = "The causal experiment exits zero."
                        experiment_command = "python -B -m unittest tests_bug.test_root_cause_probe"
                        supported_when = "EXIT_NONZERO"
                        result = "SUPPORTED"
                        receipt_ref = "h1"
                    }
                )

                cause = [ordered]@{
                    status = "CONFIRMED"
                    statement = "The implementation returns the wrong value."
                    hypothesis_refs = @("H1")
                    receipt_refs = @("h1")
                }

                resolution = [ordered]@{
                    classification = "REPAIR"
                    summary = "Return the expected value."
                    residual_risk = ""
                }
            }
        )

        regression = [ordered]@{
            receipt_refs = @("reg")
        }

        post_fix_replay = [ordered]@{
            signal_fingerprint = ("a" * 64)
            observation = "FIXED_OBSERVED"
            receipt_ref = "post"
        }
    }
}

try {
    foreach ($dir in @(
        "tasks",
        "scripts",
        "docs\engineering\reviews",
        "docs\engineering\qa",
        "docs\engineering\diagnostics"
    )) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $dir) | Out-Null
    }

    foreach ($name in @(
        "review-task.ps1",
        "qa-task.ps1",
        "assert-bug-diagnostic-evidence.ps1",
        "validate-diagnostic-evidence.ps1",
        "update-task.ps1",
        "advance-task.ps1"
    )) {
        Copy-Item `
            -LiteralPath (Join-Path $repoRoot ("scripts\" + $name)) `
            -Destination (Join-Path $tempRoot ("scripts\" + $name)) `
            -Force
    }

    $taskPath = Join-Path $tempRoot "tasks\AICO-901.md"

    $task = @(
        "# AICO-901 - BUG diagnostic gate fixture",
        "",
        "## Metadata",
        "",
        "ID: AICO-901",
        "Status: REVIEW",
        "Priority: P1",
        "Owner: frontend",
        "Workflow phase: CODE_REVIEW",
        "Work kind: IMPLEMENTATION",
        "Type: BUG",
        "",
        "---",
        "",
        "## Objective",
        "",
        "Verify diagnostic evidence gates.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] Review and QA fail closed without qualifying diagnostic evidence.",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "- fixture",
        "",
        "---",
        "",
        "## Evidence",
        "",
        "- fixture"
    ) -join [Environment]::NewLine

    Write-NoBom -Path $taskPath -Value $task

    # CASE 1:
    # Review APPROVE must fail closed without diagnostic evidence.
    $reviewRejected = $false

    try {
        & (Join-Path $tempRoot "scripts\review-task.ps1") `
            -ProjectPath $tempRoot `
            -Id "AICO-901" `
            -Recommendation APPROVE `
            -Reviewer "gate-test" `
            -Findings "Missing diagnostic evidence."

        throw "Review unexpectedly approved BUG without diagnostic evidence."
    }
    catch {
        if ($_.Exception.Message -match "diagnostic evidence artifact is required before REVIEW_APPROVE") {
            $reviewRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $reviewRejected) {
        throw "Review did not fail closed without diagnostic evidence."
    }

    if ((Get-TaskStatus -TaskPath $taskPath) -ne "REVIEW") {
        throw "Rejected Review changed task status."
    }

    $reviewArtifacts = @(
        Get-ChildItem `
            -LiteralPath (Join-Path $tempRoot "docs\engineering\reviews") `
            -File `
            -ErrorAction SilentlyContinue
    )

    if ($reviewArtifacts.Count -ne 0) {
        throw "Rejected Review persisted a review artifact."
    }

    # CASE 2:
    # COMPLETE evidence permits Review APPROVE -> QA.
    $diagnosticPath = Join-Path $tempRoot "docs\engineering\diagnostics\AICO-901-diagnostic-v1.json"
    $complete = New-CompleteEvidence

    Write-NoBom `
        -Path $diagnosticPath `
        -Value ($complete | ConvertTo-Json -Depth 100)

    & (Join-Path $tempRoot "scripts\validate-diagnostic-evidence.ps1") `
        -JsonPath $diagnosticPath | Out-Null

    & (Join-Path $tempRoot "scripts\review-task.ps1") `
        -ProjectPath $tempRoot `
        -Id "AICO-901" `
        -Recommendation APPROVE `
        -Reviewer "gate-test" `
        -Findings "Complete diagnostic evidence verified." `
        -Verification "Frozen signal verified before and after repair."

    if ((Get-TaskStatus -TaskPath $taskPath) -ne "QA") {
        throw "Valid diagnostic evidence did not allow REVIEW -> QA."
    }

    $reviewArtifacts = @(
        Get-ChildItem `
            -LiteralPath (Join-Path $tempRoot "docs\engineering\reviews") `
            -Filter "AICO-901-review-*.md" `
            -File
    )

    if ($reviewArtifacts.Count -ne 1) {
        throw "Expected exactly one approved Review artifact."
    }

    # CASE 3:
    # Valid FAILED_POST_FIX evidence must not authorize QA PASS.
    $failed = Get-Content -LiteralPath $diagnosticPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $failed.state = "FAILED_POST_FIX"
    $failed.post_fix_replay.observation = "BROKEN_OBSERVED"

    $postReceipt = @(
        $failed.receipts |
            Where-Object { $_.id -eq "post" }
    )

    if ($postReceipt.Count -ne 1) {
        throw "Expected exactly one POST_FIX receipt."
    }

    $postReceipt[0].exit_code = 1
    $postReceipt[0].output_excerpt = "original defect still reproduced"

    Write-NoBom `
        -Path $diagnosticPath `
        -Value ($failed | ConvertTo-Json -Depth 100)

    & (Join-Path $tempRoot "scripts\validate-diagnostic-evidence.ps1") `
        -JsonPath $diagnosticPath | Out-Null

    $qaRejected = $false

    try {
        & (Join-Path $tempRoot "scripts\qa-task.ps1") `
            -ProjectPath $tempRoot `
            -Id "AICO-901" `
            -Outcome PASS `
            -Evidence "Attempted QA approval with failed post-fix replay."

        throw "QA unexpectedly accepted FAILED_POST_FIX evidence."
    }
    catch {
        if ($_.Exception.Message -match "diagnostic evidence must be COMPLETE before QA_PASS") {
            $qaRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $qaRejected) {
        throw "QA did not reject FAILED_POST_FIX evidence."
    }

    if ((Get-TaskStatus -TaskPath $taskPath) -ne "QA") {
        throw "Rejected QA PASS changed task status."
    }

    $qaArtifacts = @(
        Get-ChildItem `
            -LiteralPath (Join-Path $tempRoot "docs\engineering\qa") `
            -File `
            -ErrorAction SilentlyContinue
    )

    if ($qaArtifacts.Count -ne 0) {
        throw "Rejected QA PASS persisted a QA artifact."
    }

    # CASE 4:
    # Restored COMPLETE evidence permits QA PASS -> SECURITY.
    $restored = Get-Content -LiteralPath $diagnosticPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $restored.state = "COMPLETE"
    $restored.post_fix_replay.observation = "FIXED_OBSERVED"

    $postReceipt = @(
        $restored.receipts |
            Where-Object { $_.id -eq "post" }
    )

    if ($postReceipt.Count -ne 1) {
        throw "Expected exactly one POST_FIX receipt while restoring evidence."
    }

    $postReceipt[0].exit_code = 0
    $postReceipt[0].output_excerpt = "original reproduction signal fixed"

    Write-NoBom `
        -Path $diagnosticPath `
        -Value ($restored | ConvertTo-Json -Depth 100)

    & (Join-Path $tempRoot "scripts\validate-diagnostic-evidence.ps1") `
        -JsonPath $diagnosticPath | Out-Null

    & (Join-Path $tempRoot "scripts\qa-task.ps1") `
        -ProjectPath $tempRoot `
        -Id "AICO-901" `
        -Outcome PASS `
        -Evidence "Original frozen reproduction signal verified fixed." `
        -Findings "No remaining defect in the canonical reproduction."

    if ((Get-TaskStatus -TaskPath $taskPath) -ne "SECURITY") {
        throw "Valid COMPLETE evidence did not allow QA -> SECURITY."
    }

    $qaPath = Join-Path $tempRoot "docs\engineering\qa\AICO-901-qa.md"

    if (-not (Test-Path -LiteralPath $qaPath -PathType Leaf)) {
        throw "QA PASS artifact missing."
    }

    $qaOutcome = Get-Content -LiteralPath $qaPath |
        Where-Object { $_ -match '^Outcome:' } |
        Select-Object -First 1

    if ($qaOutcome.Trim() -ne "Outcome: PASS") {
        throw "QA artifact does not record PASS."
    }

    Write-Host "PASS: BUG diagnostic Review/QA gate integration" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}