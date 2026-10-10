param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'test-project/helpers/grounded-review-fixture.ps1')
$tempRoot = Join-Path $repoRoot (".tmp-bug-gate-" + [Guid]::NewGuid().ToString("N"))
$candidateRoot = Join-Path $tempRoot 'candidate-worktree'
$candidateSourceRelative = 'src/bugfix.py'

function Invoke-FixtureGit {
    param([string]$Root,[string[]]$Arguments)

    $output = @(& git -c "safe.directory=$Root" -C $Root @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to verify fixture candidate Git state: git $($Arguments -join ' ')"
    }

    return $output
}

function Get-BugCandidateIdentity {
    param([string]$ProjectPath,[string]$Id,[string]$SourceRelativePath)

    $evidencePath = Join-Path $ProjectPath "docs/engineering/writable-evidence/$Id.md"
    $evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8
    $workspaceMatch = [regex]::Match($evidence,'(?m)^Worktree:[ \t]*([^\r\n]+)$')
    $branch = 'aico/' + $Id.ToLowerInvariant()
    if (-not $workspaceMatch.Success -or $evidence -cnotmatch ('(?m)^Branch:[ \t]*' + [regex]::Escape($branch) + '[ \t]*$')) {
        throw 'Fixture writable evidence does not identify the task candidate.'
    }

    $workspace = [IO.Path]::GetFullPath($workspaceMatch.Groups[1].Value.Trim()).TrimEnd('\','/')
    if ([string]::Equals($workspace,[IO.Path]::GetFullPath($ProjectPath).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Fixture candidate cannot be the primary checkout.'
    }

    $records = @(Invoke-FixtureGit -Root $ProjectPath -Arguments @('worktree','list','--porcelain'))
    $registered = $false
    $recordPath = ''
    foreach ($line in $records) {
        if ($line -match '^worktree (.+)$') { $recordPath = [IO.Path]::GetFullPath($Matches[1]).TrimEnd('\','/') }
        if ($line -ceq "branch refs/heads/$branch" -and [string]::Equals($recordPath,$workspace,[StringComparison]::OrdinalIgnoreCase)) { $registered = $true }
    }

    $actualBranch = (@(Invoke-FixtureGit -Root $workspace -Arguments @('branch','--show-current')) -join '').Trim()
    $projectCommon = (@(Invoke-FixtureGit -Root $ProjectPath -Arguments @('rev-parse','--git-common-dir')) -join '').Trim()
    $candidateCommon = (@(Invoke-FixtureGit -Root $workspace -Arguments @('rev-parse','--git-common-dir')) -join '').Trim()
    if (-not [IO.Path]::IsPathRooted($projectCommon)) { $projectCommon = Join-Path $ProjectPath $projectCommon }
    if (-not [IO.Path]::IsPathRooted($candidateCommon)) { $candidateCommon = Join-Path $workspace $candidateCommon }
    $projectCommon = [IO.Path]::GetFullPath($projectCommon).TrimEnd('\','/')
    $candidateCommon = [IO.Path]::GetFullPath($candidateCommon).TrimEnd('\','/')
    if (-not $registered -or $actualBranch -cne $branch -or -not [string]::Equals($candidateCommon,$projectCommon,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Fixture candidate is not a registered worktree on the task branch.'
    }

    $tracked = @(Invoke-FixtureGit -Root $workspace -Arguments @('-c','core.quotePath=false','diff','--name-only','HEAD','--'))
    $untracked = @(Invoke-FixtureGit -Root $workspace -Arguments @('-c','core.quotePath=false','ls-files','--others','--exclude-standard'))
    $inventory = @(@($tracked + $untracked) | Sort-Object -Unique)
    if ($inventory -cnotcontains $SourceRelativePath) { throw 'Fixture source is not in the live candidate change inventory.' }

    $policy = Get-Content -LiteralPath (Join-Path $ProjectPath '.codex/writable-policy.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($inventory.Count -gt [int]$policy.max_changed_files) { throw 'Fixture candidate exceeds writable policy file-count limit.' }
    $totalBytes = 0L
    $files = @(
        foreach ($relativePath in $inventory) {
            $lower = $relativePath.ToLowerInvariant()
            foreach ($prefix in $policy.protected_path_prefixes) {
                $protected = ([string]$prefix).Replace('\','/').TrimEnd('/').ToLowerInvariant()
                if ($lower -eq $protected -or $lower.StartsWith($protected + '/')) { throw "Fixture candidate path is policy protected: $relativePath" }
            }
            foreach ($pattern in $policy.secret_name_patterns) {
                if ($lower -match [string]$pattern) { throw "Fixture candidate path matches secret policy: $relativePath" }
            }

            $path = Join-Path $workspace $relativePath
            $bytes = [IO.File]::ReadAllBytes($path)
            $totalBytes += $bytes.Length
            if ($bytes.Length -gt [long]$policy.max_file_bytes) { throw "Fixture candidate exceeds writable policy file-size limit: $relativePath" }
            if ($totalBytes -gt [long]$policy.max_total_write_bytes) { throw 'Fixture candidate exceeds writable policy total-size limit.' }
            [ordered]@{
                path = $relativePath
                deleted = $false
                raw_sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    )

    return [ordered]@{
        root = $workspace
        branch = $branch
        common_directory = $candidateCommon
        registered = $registered
        files = $files
    }
}

function New-BugCandidatePrimaryArtifact {
    param([string]$ProjectPath,[string]$Id,[string]$SourceRelativePath)

    $identity = Get-BugCandidateIdentity -ProjectPath $ProjectPath -Id $Id -SourceRelativePath $SourceRelativePath
    $path = Join-Path ([string]$identity.root) $SourceRelativePath
    $bytes = [IO.File]::ReadAllBytes($path)
    return [pscustomobject]@{
        Path = $path
        RelativePath = $SourceRelativePath
        Namespace = 'implementation-candidate'
        CapturedRawBytes = $bytes
        CandidateIdentity = [ordered]@{
            root = $identity.root
            branch = $identity.branch
            common_directory = $identity.common_directory
            registered = $identity.registered
        }
    }
}

function Invoke-BugGroundedFixtureReview {
    param([string]$ProjectPath,[string]$Id,[string]$Recommendation='APPROVE',[string]$Reviewer='reviewer',
          [string]$Findings='Fixture delivery complete.',[string]$Verification='Fixture primary evidence inspected.')

    $sourceRelativePath = $candidateSourceRelative
    Initialize-GroundedReviewFixture -Root $ProjectPath -Id $Id -CreateReport
    . (Join-Path $ProjectPath 'scripts/task-execution-lock.ps1')
    . (Join-Path $ProjectPath 'scripts/review-grounding.ps1')
    $lease = Enter-TaskExecutionLock -ProjectPath $ProjectPath -Id $Id -Operation GATE
    try {
        $artifact = New-BugCandidatePrimaryArtifact -ProjectPath $ProjectPath -Id $Id -SourceRelativePath $candidateSourceRelative

        # Capture both real verification functions before entering the closure module.
        $candidateIdentityFunction = ${function:Get-BugCandidateIdentity}
        $fixtureGitFunction = ${function:Invoke-FixtureGit}

        $identityVerifier = {
            function Invoke-FixtureGit {
                param([string]$Root,[string[]]$Arguments)
                & $fixtureGitFunction -Root $Root -Arguments $Arguments
            }

            & $candidateIdentityFunction -ProjectPath $ProjectPath -Id $Id -SourceRelativePath $sourceRelativePath
        }.GetNewClosure()
        $context = New-ReviewGroundingContext `
            -ProjectPath $ProjectPath `
            -Id $Id `
            -Lease $lease `
            -PrimaryArtifacts @($artifact) `
            -CandidateIdentityVerifier $identityVerifier `
            -AdditionalSourcePaths @(
                (Join-Path $ProjectPath "docs/engineering/writable-evidence/$Id.md"),
                (Join-Path $ProjectPath '.codex/writable-policy.json')
            )
        $result = New-GroundedFixtureJudgment -Context $context -Recommendation $Recommendation -Findings $Findings -Verification $Verification
        $path = Join-Path $ProjectPath ('grounded-review-' + [Guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($path,($result | ConvertTo-Json -Depth 40),[Text.UTF8Encoding]::new($false))
        try {
            & (Join-Path $ProjectPath 'scripts/review-task.ps1') `
                -ProjectPath $ProjectPath `
                -Id $Id `
                -Recommendation $Recommendation `
                -Reviewer $Reviewer `
                -TaskExecutionLease $lease `
                -ResultPath $path `
                -GroundingContext $context
        }
        finally { Remove-Item -LiteralPath $path -Force }
    }
    finally { Exit-TaskExecutionLock -Lock $lease }
}

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
        "schemas",
        "docs\engineering\reviews",
        "docs\engineering\qa",
        "docs\engineering\diagnostics",
        "docs\engineering\results",
        "docs\engineering\dispatch",
        "docs\engineering\writable-evidence",
        "docs\engineering\work-requests",
        ".codex"
    )) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $dir) | Out-Null
    }

    foreach ($name in @(
        "review-task.ps1",
        "qa-task.ps1",
        "assert-bug-diagnostic-evidence.ps1",
        "validate-json-contract.ps1",
        "validate-diagnostic-evidence.ps1",
        "update-task.ps1",
        "advance-task.ps1"
    )) {
        Copy-Item `
            -LiteralPath (Join-Path $repoRoot ("scripts\" + $name)) `
            -Destination (Join-Path $tempRoot ("scripts\" + $name)) `
            -Force
    }

    Copy-Item -LiteralPath (Join-Path $repoRoot 'schemas\diagnostic-evidence.schema.json') -Destination (Join-Path $tempRoot 'schemas\diagnostic-evidence.schema.json') -Force

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
        "- [ ] The registered implementation candidate source src/bugfix.py records the verified fixture behavior.",
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

    # Real Review Grounding requires canonical result and dispatch sources.
    $resultPath = Join-Path $tempRoot "docs\engineering\results\AICO-901-result-001.md"
    $dispatchPath = Join-Path $tempRoot "docs\engineering\dispatch\AICO-901.md"

    Write-NoBom -Path $resultPath -Value (@(
        "# Task Result - AICO-901",
        "Task: AICO-901",
        "Owner: frontend",
        "Outcome: COMPLETED",
        "Changed artifacts: docs/engineering/agent-reports/AICO-901.md",
        "Summary: Diagnostic gate fixture implementation completed."
    ) -join "`n")

    Write-NoBom -Path $dispatchPath -Value (@(
        "# Dispatch - AICO-901",
        "Task: AICO-901",
        "Owner: frontend",
        "Scope: Validate BUG diagnostic Review and QA gates."
    ) -join "`n")

    Copy-Item -LiteralPath (Join-Path $repoRoot '.codex/writable-policy.json') -Destination (Join-Path $tempRoot '.codex/writable-policy.json') -Force
    Initialize-GroundedReviewFixture -Root $tempRoot -Id 'AICO-901' -CreateReport
    $candidateBaselinePath = Join-Path $tempRoot $candidateSourceRelative
    Write-NoBom -Path $candidateBaselinePath -Value "def fixed_value():`n    return 'baseline'`n"

    & git -C $tempRoot init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize the temporary candidate repository.' }
    & git -C $tempRoot config user.email 'aico-test@example.invalid'
    & git -C $tempRoot config user.name 'AI Company OS Test'
    & git -C $tempRoot config core.autocrlf false
    & git -C $tempRoot add .
    & git -C $tempRoot commit -m 'BUG gate fixture baseline' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to commit the temporary candidate repository baseline.' }

    & git -C $tempRoot worktree add -b 'aico/aico-901' $candidateRoot HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create the registered BUG candidate worktree.' }
    Write-NoBom -Path (Join-Path $candidateRoot $candidateSourceRelative) -Value "def fixed_value():`n    return 'fixed'`n"
    Write-NoBom -Path (Join-Path $tempRoot 'docs\engineering\writable-evidence\AICO-901.md') -Value (@(
        '# Writable Execution Evidence - AICO-901',
        'Outcome: COMPLETED',
        "Worktree: $candidateRoot",
        'Branch: aico/aico-901',
        '## Changed Paths',
        '- src/bugfix.py'
    ) -join "`n")
    $verifiedCandidate = Get-BugCandidateIdentity -ProjectPath $tempRoot -Id 'AICO-901' -SourceRelativePath $candidateSourceRelative
    $candidateHash = (Get-FileHash -LiteralPath (Join-Path $candidateRoot $candidateSourceRelative) -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "CANDIDATE: root=$($verifiedCandidate.root); branch=$($verifiedCandidate.branch); registered=$($verifiedCandidate.registered); common_directory=$($verifiedCandidate.common_directory)"
    Write-Host "CANDIDATE_INVENTORY: path=$candidateSourceRelative; sha256=$candidateHash; provenance=git worktree list + branch + common-directory + live HEAD diff inventory"

    # Guard classification must agree with the writable runner's Task/Work Request identity.
    $diagnosticGuardPath = Join-Path $tempRoot 'scripts\assert-bug-diagnostic-evidence.ps1'
    $originalTaskText = Get-Content -LiteralPath $taskPath -Raw -Encoding UTF8
    $workRequestPath = Join-Path $tempRoot 'docs\engineering\work-requests\WR-901.md'
    Write-NoBom -Path $workRequestPath -Value "# Work Request`nType: BUG`n"

    $taskWithoutType = $originalTaskText -replace '(?m)^Type: BUG\r?\n', "Work request: WR-901`n"
    Write-NoBom -Path $taskPath -Value $taskWithoutType
    $requestBugGuarded = $false
    try { & $diagnosticGuardPath -Id 'AICO-901' -ProjectPath $tempRoot -Stage REVIEW_APPROVE | Out-Null }
    catch { $requestBugGuarded = $_.Exception.Message -match 'diagnostic evidence artifact is required before REVIEW_APPROVE' }
    if (-not $requestBugGuarded) { throw 'BUG type from Work Request was ignored by the approval evidence guard.' }

    $conflictingTask = $originalTaskText -replace '(?m)^Type: BUG\r?$', "Type: FEATURE`nWork request: WR-901"
    Write-NoBom -Path $taskPath -Value $conflictingTask
    $taskRequestConflictRejected = $false
    try { & $diagnosticGuardPath -Id 'AICO-901' -ProjectPath $tempRoot -Stage REVIEW_APPROVE | Out-Null }
    catch { $taskRequestConflictRejected = $_.Exception.Message -match 'diagnostic identity mismatch' }
    if (-not $taskRequestConflictRejected) { throw 'Contradictory Task and Work Request types were not rejected.' }

    Write-NoBom -Path $workRequestPath -Value "# Work Request`n"
    $bugWithUntypedRequest = $originalTaskText -replace '(?m)^Type: BUG\r?$', "Work request: WR-901"
    Write-NoBom -Path $taskPath -Value $bugWithUntypedRequest
    $missingRequestTypeRejected = $false
    try { & $diagnosticGuardPath -Id 'AICO-901' -ProjectPath $tempRoot -Stage REVIEW_APPROVE | Out-Null }
    catch { $missingRequestTypeRejected = $_.Exception.Message -match 'work request has no Type' }
    if (-not $missingRequestTypeRejected) { throw 'Missing Work Request type was allowed to bypass diagnostic identity checks.' }

    Write-NoBom -Path $workRequestPath -Value "# Work Request`nType: BUG`n"
    $bugWithoutTaskTypeOrWorkKind = $originalTaskText -replace '(?m)^Type: BUG\r?\n', '' -replace '(?m)^Work kind: IMPLEMENTATION\r?\n', "Work request: WR-901`n"
    Write-NoBom -Path $taskPath -Value $bugWithoutTaskTypeOrWorkKind
    $requestBugWithoutKindRejected = $false
    try { & $diagnosticGuardPath -Id 'AICO-901' -ProjectPath $tempRoot -Stage REVIEW_APPROVE | Out-Null }
    catch { $requestBugWithoutKindRejected = $_.Exception.Message -match 'BUG task has no Work kind' }
    if (-not $requestBugWithoutKindRejected) { throw 'BUG Work Request with missing Task type and Work kind bypassed the diagnostic evidence guard.' }

    $incompleteTask = $originalTaskText -replace '(?m)^Type: BUG\r?\n', ''
    Write-NoBom -Path $taskPath -Value $incompleteTask
    $incompleteIdentityRejected = $false
    try { & $diagnosticGuardPath -Id 'AICO-901' -ProjectPath $tempRoot -Stage REVIEW_APPROVE | Out-Null }
    catch { $incompleteIdentityRejected = $_.Exception.Message -match 'identity is incomplete' }
    if (-not $incompleteIdentityRejected) { throw 'BUG implementation with incomplete workflow identity was not rejected.' }

    Write-NoBom -Path $taskPath -Value ($originalTaskText -replace '(?m)^Type: BUG\r?$', 'Type: FEATURE')
    $nonBugOutcome = & $diagnosticGuardPath -Id 'AICO-901' -ProjectPath $tempRoot -Stage REVIEW_APPROVE
    if (($nonBugOutcome -join '') -notmatch '^NOT_APPLICABLE: diagnostic evidence guard$') {
        throw 'A complete non-BUG implementation identity did not preserve the existing NOT_APPLICABLE behavior.'
    }

    Remove-Item -LiteralPath $workRequestPath -Force
    Write-NoBom -Path $taskPath -Value $originalTaskText
    Write-Host 'SCENARIO 0 PASS: Work Request BUG fallback, contradictory/incomplete identities fail closed, non-BUG identity remains unaffected.'

    # CASE 1:
    # Review APPROVE must fail closed without diagnostic evidence.
    $reviewRejected = $false

    try {
        Invoke-BugGroundedFixtureReview `
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
    Write-Host 'SCENARIO 1 PASS: missing diagnostic evidence rejected by REVIEW_APPROVE guard; no review artifact published.'

    # CASE 2:
    # COMPLETE evidence permits Review APPROVE -> QA.
    $diagnosticPath = Join-Path $tempRoot "docs\engineering\diagnostics\AICO-901-diagnostic-v1.json"
    $complete = New-CompleteEvidence

    Write-NoBom `
        -Path $diagnosticPath `
        -Value ($complete | ConvertTo-Json -Depth 100)

    & (Join-Path $tempRoot "scripts\validate-diagnostic-evidence.ps1") `
        -JsonPath $diagnosticPath | Out-Null

    Invoke-BugGroundedFixtureReview `
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
    Write-Host 'SCENARIO 2 PASS: COMPLETE diagnostic evidence allowed Review APPROVE and REVIEW -> QA.'

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
    Write-Host 'SCENARIO 3 PASS: FAILED_POST_FIX rejected by QA_PASS diagnostic guard; no QA artifact published.'

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
    Write-Host 'SCENARIO 4 PASS: COMPLETE + FIXED_OBSERVED allowed QA PASS and QA -> SECURITY.'

    Write-Host "PASS: BUG diagnostic Review/QA gate integration" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
