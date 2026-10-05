param()

$ErrorActionPreference = "Stop"

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "SKIP: git is unavailable; writable runtime test requires Git." -ForegroundColor Yellow
    exit 0
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempParent = Join-Path $env:TEMP ("aico-writable-runtime-" + [Guid]::NewGuid().ToString("N"))
$fixtureRepo = Join-Path $tempParent "repo"
$workspaces = Join-Path $tempParent "worktrees"
$savedOpenRouter = $env:OPENROUTER_API_KEY
$savedDeepSeek = $env:DEEPSEEK_API_KEY
$savedXai = $env:XAI_API_KEY
$savedPath = $env:PATH
# Resolve the required native test executable before running nested fixture scripts.
$fixturePython = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $fixturePython) { throw 'Python is required for real stdlib unittest regression.' }

function Write-NoBom {
    param([string]$Path,[string]$Value)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

function New-FixtureTask {
    param([string]$Id,[string]$Status,[string]$FileName)

    $task = @(
        "# $Id - Writable fixture",
        "",
        "## Metadata",
        "",
        "ID: $Id",
        "Status: $Status",
        "Priority: P1",
        "Owner: frontend",
        "Workflow phase: PLANNING",
        "Work kind: IMPLEMENTATION",
        "Work request: WR-TEST",
        "",
        "---",
        "",
        "## Objective",
        "",
        "Safely update $FileName.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] The requested source file is updated.",
        "- [ ] Verification passes.",
        "",
        "---",
        "",
        "## Dependencies",
        "",
        "-",
        "",
        "---",
        "",
        "## Evidence",
        "",
        "-",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "-"
    ) -join [Environment]::NewLine

    Write-NoBom (Join-Path $fixtureRepo ("tasks\" + $Id + ".md")) $task

    $dispatch = @(
        "# Execution Request - $Id",
        "Task: $Id",
        "Owner: frontend",
        "",
        "## Objective",
        "",
        "Safely update $FileName.",
        "",
        "## Required Context",
        "",
        "- tasks/$Id.md",
        "- .codex/state/company-state.md",
        "",
        "## Execution Restrictions",
        "",
        "- Do not modify .env."
    ) -join [Environment]::NewLine

    Write-NoBom (Join-Path $fixtureRepo ("docs\engineering\dispatch\" + $Id + ".md")) $dispatch
    Write-NoBom (Join-Path $fixtureRepo ("src\" + $FileName)) "original"
}

function Set-FakeResult {
    param([hashtable]$Payload)
    Write-NoBom (Join-Path $fixtureRepo ".codex\fake-writable-result.json") ($Payload | ConvertTo-Json -Depth 20)
}

function Get-TaskStatus {
    param([string]$Id)
    $content = Get-Content (Join-Path $fixtureRepo ("tasks\" + $Id + ".md")) -Raw -Encoding UTF8
    $match = [regex]::Match($content,"(?m)^Status:\s*(\S+)")
    if (-not $match.Success) { throw "Task status missing for $Id" }
    return $match.Groups[1].Value.Trim()
}


function Invoke-Runner {
    param([string]$Id)

    & (Join-Path $fixtureRepo "scripts\run-writable-agent.ps1") -Id $Id -ProjectPath $fixtureRepo -WorkspacePath (Join-Path $workspaces $Id) -Provider Auto
}

try {
    $env:DEEPSEEK_API_KEY = "obviously-fake-deepseek-writable-rejection"
    $env:XAI_API_KEY = "obviously-fake-xai-writable-rejection"
    foreach ($dir in @(
        "scripts",
        "tasks",
        "schemas",
        ".codex",
        ".codex\agents",
        "docs\engineering\dispatch",
        "docs\engineering\reviews",
        "src"
    )) {
        New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRepo $dir) | Out-Null
    }

    New-Item -ItemType Directory -Force -Path $workspaces | Out-Null

    foreach ($name in @(
        "run-writable-agent.ps1",
        "task-execution-lock.ps1",
        "advance-task.ps1",
        "update-task.ps1",
        "submit-task-result.ps1",
        "build-agent-context.ps1",
        "build-corrective-analysis-context.ps1",
        "resolve-writable-required-files.ps1"
    )) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $fixtureRepo ("scripts\" + $name)) -Force
    }

    Copy-Item (Join-Path $repoRoot "schemas\writable-change-set.schema.json") (Join-Path $fixtureRepo "schemas\writable-change-set.schema.json") -Force
    Copy-Item (Join-Path $repoRoot ".codex\writable-policy.json") (Join-Path $fixtureRepo ".codex\writable-policy.json") -Force

    $fakeRouter = @'
param(
    [string]$Provider,
    [string]$ProjectPath,
    [string]$Prompt,
    [string]$Context,
    [string]$CorrectiveContext,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [string]$Role,
    [string]$Workload
)
if ($Role -ne "frontend" -or $Workload -ne "writable") { throw "Writable runner must propagate its role/workload" }
if ($Provider -notin @("Ollama","OpenRouter","Gemini")) { throw "Forbidden writable provider reached router" }
[IO.File]::WriteAllText((Join-Path $ProjectPath '.codex/captured-corrective.txt'),$CorrectiveContext)
$source = Join-Path (Split-Path -Parent $PSScriptRoot) ".codex\fake-writable-result.json"
Copy-Item $source $OutputPath -Force
[PSCustomObject]@{ Provider = $Provider; Model = $Model }
'@
    Write-NoBom (Join-Path $fixtureRepo "scripts\provider-router.ps1") $fakeRouter

    $providerConfig = @{
        auto_order = @("OpenRouter","Gemini")
        writable_auto_order = @("DeepSeek","Grok","OpenRouter","Gemini")
        writable_allow_paid_fallback = $true
        context_max_chars = 50000
        models = @{
            OpenRouter = "openrouter/free"
            Gemini = "gemini-3.5-flash-lite"
        }
        writable_models = @{
            OpenRouter = "openrouter/free"
            Gemini = "gemini-3.5-flash-lite"
        }
    } | ConvertTo-Json -Depth 10
    Write-NoBom (Join-Path $fixtureRepo ".codex\provider-config.json") $providerConfig

    Write-NoBom (Join-Path $fixtureRepo ".codex\agents\frontend.md") "Frontend fixture role."
    Write-NoBom (Join-Path $fixtureRepo "AGENTS.md") "Writable runtime fixture."
    Write-NoBom (Join-Path $fixtureRepo "package.json") '{"name":"writable-fixture","private":true}'

    New-FixtureTask -Id "AICO-001" -Status "ACTIVE" -FileName "value1.txt"
    New-FixtureTask -Id "AICO-002" -Status "ACTIVE" -FileName "value2.txt"
    New-FixtureTask -Id "AICO-003" -Status "ACTIVE" -FileName "value3.txt"
    New-FixtureTask -Id "AICO-004" -Status "READY" -FileName "value4.txt"
    New-FixtureTask -Id "AICO-005" -Status "ACTIVE" -FileName "value5.txt"
    New-FixtureTask -Id "AICO-006" -Status "ACTIVE" -FileName "value6.txt"
    New-FixtureTask -Id "AICO-007" -Status "ACTIVE" -FileName "value7.txt"
    New-FixtureTask -Id "AICO-008" -Status "ACTIVE" -FileName "value8.txt"
    New-FixtureTask -Id "AICO-009" -Status "ACTIVE" -FileName "value9.txt"
    Write-NoBom (Join-Path $fixtureRepo 'src/value9.txt') "original`r`n"
    Write-NoBom (Join-Path $fixtureRepo 'tests/test_native.py') "import unittest`nclass NativeSuccess(unittest.TestCase):`n    def test_actual_product_verification(self):`n        self.assertEqual(2 + 2, 4)`n"
    Write-NoBom (Join-Path $fixtureRepo 'tests_failure/test_native.py') "import unittest`nclass NativeFailure(unittest.TestCase):`n    def test_actual_product_verification(self):`n        self.assertEqual(2 + 2, 5)`n"
    Write-NoBom (Join-Path $fixtureRepo 'warn-success.js') "process.stdout.write('NATIVE_STDOUT_SUCCESS\n'); process.stderr.write('NATIVE_STDERR_WARNING_SUCCESS\n'); process.exit(0);"
    Write-NoBom (Join-Path $fixtureRepo 'warn-failure.js') "process.stdout.write('NATIVE_STDOUT_FAILURE\n'); process.stderr.write('NATIVE_STDERR_WARNING_FAILURE\n'); process.exit(7);"

    Write-NoBom (Join-Path $fixtureRepo "docs\engineering\reviews\AICO-004-review-001.md") @"
# Review
Task: AICO-004
Task owner: frontend

Recommendation: CHANGES_REQUIRED
## Findings

The prior writable implementation needs correction.
"@

    Write-NoBom (Join-Path $fixtureRepo 'docs/engineering/results/AICO-004-result-001.md') "Task: AICO-004`nOwner: frontend`nPrevious result"
    Write-NoBom (Join-Path $fixtureRepo 'docs/engineering/agent-reports/AICO-004.md') "# Agent Report - AICO-004`nOwner: frontend`nPrevious deliverable"

    & git -C $fixtureRepo init | Out-Null
    & git -C $fixtureRepo config user.email "aico-test@example.invalid"
    & git -C $fixtureRepo config user.name "AI Company OS Test"
    & git -C $fixtureRepo add .
    & git -c core.autocrlf=true -C $fixtureRepo add src/value9.txt
    & git -C $fixtureRepo commit -m "writable runtime fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fixture commit failed." }
    & git -C $fixtureRepo config core.autocrlf true

    foreach ($id in @("AICO-001","AICO-002","AICO-003","AICO-004","AICO-005","AICO-006","AICO-007","AICO-008","AICO-009")) {
        & (Join-Path $repoRoot "scripts\new-agent-workspace.ps1") -Id $id -ProjectPath $fixtureRepo -WorkspaceRoot $workspaces | Out-Null
    }

    $env:OPENROUTER_API_KEY = "writable-fixture-key"

    Set-FakeResult @{
        outcome = "COMPLETED"
        summary = "Updated fixture source"
        report_markdown = "# Implementation - Safe fixture change."
        changes = @(
            @{
                path = "src/value1.txt"
                operation = "WRITE"
                content = "changed"
                reason = "Fixture implementation"
            }
        )
        verification_commands = @("git diff --check")
        verification = "Fixture verification requested"
        decisions = "NONE"
        blockers = "NONE"
        recommended_next = "REVIEW"
    }

    Invoke-Runner -Id "AICO-001"

    if ((Get-Content (Join-Path $fixtureRepo "src\value1.txt") -Raw) -ne "original") {
        throw "Writable runtime modified source in the primary checkout."
    }

    $workspaceValue = Get-Content (Join-Path $workspaces "AICO-001\src\value1.txt") -Raw
    if ($workspaceValue -ne "changed") {
        throw "Writable runtime did not apply the validated change inside the worktree."
    }

    if ((Get-TaskStatus -Id "AICO-001") -ne "REVIEW") {
        throw "Successful writable execution did not advance ACTIVE -> REVIEW."
    }

    if (-not (Test-Path (Join-Path $fixtureRepo "docs\engineering\writable-evidence\AICO-001.md"))) {
        throw "Writable execution evidence artifact was not generated."
    }

    $primaryReportPath = Join-Path `
        $fixtureRepo `
        "docs\engineering\agent-reports\AICO-001.md"

    if (-not (Test-Path $primaryReportPath -PathType Leaf)) {
        throw "Successful writable execution did not publish the canonical primary agent report."
    }

    $primaryReport = Get-Content `
        $primaryReportPath `
        -Raw `
        -Encoding UTF8

    foreach ($requiredReportEvidence in @(
        "Owner: frontend",
        "Work kind: IMPLEMENTATION",
        "# Implementation - Safe fixture change.",
        "docs/engineering/writable-evidence/AICO-001.md"
    )) {
        if ($primaryReport -notmatch [regex]::Escape($requiredReportEvidence)) {
            throw (
                "Primary writable agent report is missing required evidence: " +
                $requiredReportEvidence
            )
        }
    }

    $resultPath = Join-Path `
        $fixtureRepo `
        "docs\engineering\results\AICO-001-result-001.md"

    if (-not (Test-Path $resultPath -PathType Leaf)) {
        throw "Successful writable execution did not create its task result."
    }

    $resultText = Get-Content `
        $resultPath `
        -Raw `
        -Encoding UTF8

    if (
        $resultText -notmatch
        [regex]::Escape(
            "docs/engineering/agent-reports/AICO-001.md"
        )
    ) {
        throw "Writable task result does not reference the canonical primary agent report."
    }

    Set-FakeResult @{
        outcome = "COMPLETED"
        summary = "Traversal attempt"
        report_markdown = "# Invalid"
        changes = @(
            @{
                path = "../escape.txt"
                operation = "WRITE"
                content = "escape"
                reason = "Should be rejected"
            }
        )
        verification_commands = @("git diff --check")
        verification = "NONE"
        decisions = "NONE"
        blockers = "NONE"
        recommended_next = "REVIEW"
    }

    $traversalRejected = $false
    try {
        Invoke-Runner -Id "AICO-002"
    }
    catch {
        if ($_.Exception.Message -match "cannot contain|escapes the task worktree") {
            $traversalRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $traversalRejected) { throw "Writable runtime accepted path traversal." }
    if (Test-Path (Join-Path $tempParent "escape.txt")) { throw "Traversal attempt created a file outside the worktree." }

    Set-FakeResult @{
        outcome = "COMPLETED"
        summary = "Command injection attempt"
        report_markdown = "# Invalid verification"
        changes = @(
            @{
                path = "src/value3.txt"
                operation = "WRITE"
                content = "should-roll-back"
                reason = "Fixture"
            }
        )
        verification_commands = @("git diff --check; git status --short")
        verification = "NONE"
        decisions = "NONE"
        blockers = "NONE"
        recommended_next = "REVIEW"
    }

    $commandRejected = $false
    try {
        Invoke-Runner -Id "AICO-003"
    }
    catch {
        if ($_.Exception.Message -match "not allowed by writable policy|exactly one simple command|pipelines are prohibited") {
            $commandRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $commandRejected) { throw "Writable runtime accepted command composition." }

    $rolledBack = Get-Content (Join-Path $workspaces "AICO-003\src\value3.txt") -Raw
    if ($rolledBack -ne "original") {
        throw "Rejected writable execution did not restore the planned file."
    }

    $task3Status = Get-TaskStatus -Id "AICO-003"
    if ($task3Status -ne "ACTIVE") {
        throw ("Rejected writable execution should leave task ACTIVE. Actual: " + $task3Status)
    }

    Write-NoBom (Join-Path $workspaces "AICO-004\src\value4.txt") "prior-rejected-change"

    Set-FakeResult @{
        outcome = "COMPLETED"
        summary = "Corrected rejected implementation"
        report_markdown = "# Correction"
        changes = @(
            @{
                path = "src/value4.txt"
                operation = "WRITE"
                content = "corrected"
                reason = "Address CHANGES_REQUIRED"
            }
        )
        verification_commands = @("git diff --check")
        verification = "Correction verified"
        decisions = "NONE"
        blockers = "NONE"
        recommended_next = "REVIEW"
    }

    Invoke-Runner -Id "AICO-004"

    $task4Status = Get-TaskStatus -Id "AICO-004"
    if ($task4Status -ne "REVIEW") {
        throw ("Corrective writable execution did not complete READY -> ACTIVE -> REVIEW. Actual: " + $task4Status)
    }

    $corrected = Get-Content (Join-Path $workspaces "AICO-004\src\value4.txt") -Raw
    if ($corrected -ne "corrected") {
        throw "Corrective writable execution did not update the existing worktree diff."
    }

    # Equivalent corrective gates must admit the existing dirty candidate and
    # send only the current authoritative findings to the writable router.
    foreach ($kind in @('QA','Security')) {
        New-FixtureTask -Id 'AICO-004' -Status 'ACTIVE' -FileName 'value4.txt'
        $ticket = Join-Path $fixtureRepo 'tasks/AICO-004.md'
        $history = if ($kind -eq 'QA') { 'QA gate failed.' } else { 'Security gate failed.' }
        [IO.File]::AppendAllText($ticket,"`n- 2026-10-04T01:00:00Z - gate - QA -> READY - $history`n")
        Write-NoBom (Join-Path $fixtureRepo 'docs/engineering/reviews/AICO-004-review-002.md') "Task: AICO-004`nTask owner: frontend`nRecommendation: APPROVE`n## Findings`nSTALE_REVIEW_MARKER"
        Write-NoBom (Join-Path $fixtureRepo 'docs/engineering/qa/AICO-004-qa.md') "# QA Gate - AICO-004`nOutcome: $(if ($kind -eq 'QA') {'FAIL'} else {'PASS'})`n## Findings`nQA_AUTHORITATIVE_START$('Q'*4000)QA_AUTHORITATIVE_END"
        if ($kind -eq 'Security') {
            Write-NoBom (Join-Path $fixtureRepo 'docs/engineering/security/AICO-004-security.md') "# Security Gate - AICO-004`nOutcome: FAIL`n## Findings`nSECURITY_AUTHORITATIVE_START$('S'*4000)SECURITY_AUTHORITATIVE_END"
        }
        if ($kind -eq 'QA') {
            # Historical runner output joined exactly these canonical paths with a space.
            Write-NoBom (Join-Path $fixtureRepo 'docs/engineering/results/AICO-004-result-999.md') "Task: AICO-004`nOwner: frontend`nOutcome: COMPLETED`n## Changed Artifacts`ndocs/engineering/writable-evidence/AICO-004.md docs/engineering/agent-reports/AICO-004.md`n## Verification`nPrevious real verification"
        }
        $currentPath = Join-Path $workspaces 'AICO-004/src/value4.txt'
        $currentSource = [IO.File]::ReadAllText($currentPath)
        $currentHash = (Get-FileHash -LiteralPath $currentPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $extraPath = Join-Path $workspaces 'AICO-004/src/extra.py'
        $extraSource = "# UNTRACKED_CURRENT_SOURCE`n" + ('# full corrective source evidence'+"`n")*100
        Write-NoBom $extraPath $extraSource
        $extraHash = (Get-FileHash -LiteralPath $extraPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($kind -eq 'QA') {
            $captureGuard = Join-Path $fixtureRepo '.codex/captured-corrective.txt'
            if (Test-Path $captureGuard) { Remove-Item -LiteralPath $captureGuard }
            $secretPath = Join-Path $workspaces 'AICO-004/.env'
            Write-NoBom $secretPath 'SYNTHETIC_SECRET_MUST_NOT_ENTER_CONTEXT'
            $secretRejected = $false
            try { Invoke-Runner -Id 'AICO-004' } catch { $secretRejected = $true }
            Remove-Item -LiteralPath $secretPath
            if (-not $secretRejected -or (Test-Path $captureGuard)) { throw 'Secret candidate context must fail before provider invocation.' }
        }
        Set-FakeResult @{outcome='COMPLETED';summary='Gate correction';report_markdown='# Gate correction';changes=@(@{path='src/value4.txt';operation='WRITE';content=('corrected-'+$kind);reason='Current findings'});verification_commands=@('git diff --check');verification='Verified';decisions='NONE';blockers='NONE';recommended_next='REVIEW'}
        Invoke-Runner -Id 'AICO-004'
        $resultFiles = @(Get-ChildItem (Join-Path $fixtureRepo 'docs/engineering/results') -Filter 'AICO-004-result-*.md' | Sort-Object { [int]([regex]::Match($_.BaseName,'(\d+)$').Value) })
        $latestResult = [IO.File]::ReadAllText($resultFiles[-1].FullName)
        if (-not $latestResult.Contains('docs/engineering/writable-evidence/AICO-004.md; docs/engineering/agent-reports/AICO-004.md')) { throw 'Writable result did not delimit canonical changed artifacts.' }
        if ((Get-TaskStatus 'AICO-004') -ne 'REVIEW') { throw "$kind corrective writable retry failed." }
        $captured = [IO.File]::ReadAllText((Join-Path $fixtureRepo '.codex/captured-corrective.txt'))
        foreach ($exact in @($currentSource,$currentHash,$extraSource,$extraHash,'original')) {
            if (-not $captured.Contains($exact)) { throw 'Protected writable source content, raw-byte hash or primary comparison missing.' }
        }
        $marker = if ($kind -eq 'QA') {'QA_AUTHORITATIVE'} else {'SECURITY_AUTHORITATIVE'}
        $whole = $marker+'_START'+$(if ($kind -eq 'QA') {'Q'*4000} else {'S'*4000})+$marker+'_END'
        if (-not $captured.Contains($whole)) { throw 'Corrective findings were partially truncated.' }
        if (-not $captured.Contains($marker+'_START') -or -not $captured.Contains($marker+'_END')) { throw "$kind full corrective findings lost." }
        if ($captured.Contains('STALE_REVIEW_MARKER') -or ($kind -eq 'Security' -and $captured.Contains('QA_AUTHORITATIVE_START'))) { throw 'Stale successful gate findings contaminated correction.' }
    }
    # A later successful canonical review invalidates the failed Security source.
    New-FixtureTask -Id 'AICO-004' -Status 'ACTIVE' -FileName 'value4.txt'
    [IO.File]::AppendAllText((Join-Path $fixtureRepo 'tasks/AICO-004.md'),"`n- 2026-10-04T02:00:00Z - reviewer - REVIEW -> QA - Independent review approved.`n")
    $capturePath = Join-Path $fixtureRepo '.codex/captured-corrective.txt'
    Remove-Item -LiteralPath $capturePath
    $staleRejected = $false
    try { Invoke-Runner -Id 'AICO-004' } catch { $staleRejected = $_.Exception.Message -match 'clean' }
    if (-not $staleRejected -or (Test-Path $capturePath)) { throw 'Stale corrective gate permitted dirty workspace/provider call.' }

    # Exercise a real native executable under Windows PowerShell ErrorActionPreference=Stop.
    # A warning on stderr is evidence; only a nonzero exit rejects the change.
    if ($null -eq (Get-Command node -ErrorAction SilentlyContinue)) { throw 'node is required for native stderr regression.' }
    foreach ($case in @(
        @{Id='AICO-005';File='value5.txt';Command='node warn-success.js';Exit=0},
        @{Id='AICO-006';File='value6.txt';Command='node warn-failure.js';Exit=7}
    )) {
        $workspaceFile = Join-Path $workspaces ($case.Id+'\src\'+$case.File)
        $beforeHash = (Get-FileHash -LiteralPath $workspaceFile -Algorithm SHA256).Hash
        Set-FakeResult @{
            outcome='COMPLETED';summary='Native stderr regression';report_markdown='# Native verification fixture'
            changes=@(@{path=('src/'+$case.File);operation='WRITE';content='native-verified-change';reason='Test native stderr behavior'})
            verification_commands=@($case.Command);verification='Native verifier';decisions='NONE';blockers='NONE';recommended_next='REVIEW'
        }
        $failed = $false
        try { Invoke-Runner -Id $case.Id } catch {
            if ($case.Exit -ne 0 -and $_.Exception.Message -match 'exit code 7') { $failed=$true } else { throw }
        }
        if ($case.Exit -eq 0) {
            if ((Get-TaskStatus $case.Id) -ne 'REVIEW') { throw 'Native stderr warning with exit zero must advance to REVIEW.' }
            $nativeEvidence = Get-Content (Join-Path $fixtureRepo ('docs/engineering/writable-evidence/'+$case.Id+'.md')) -Raw
            foreach ($marker in @('NATIVE_STDOUT_SUCCESS','NATIVE_STDERR_WARNING_SUCCESS')) {
                if ($nativeEvidence -notmatch $marker) { throw ('Native output missing from evidence: '+$marker) }
            }
            if ((Get-Content -LiteralPath $workspaceFile -Raw) -ne 'native-verified-change') { throw 'Successful native verification lost validated change.' }
        }
        else {
            if (-not $failed) { throw 'Nonzero native verifier must fail with actual exit code.' }
            if ((Get-FileHash -LiteralPath $workspaceFile -Algorithm SHA256).Hash -ne $beforeHash) { throw 'Native verification failure must restore exact original bytes.' }
            if ((Get-TaskStatus $case.Id) -ne 'ACTIVE') { throw 'Native verification failure must leave task ACTIVE.' }
            if (Test-Path (Join-Path $fixtureRepo ('docs/engineering/results/'+$case.Id+'-result-001.md'))) { throw 'Failed native verification must not publish task result.' }
            if (Test-Path (Join-Path $fixtureRepo ('docs/engineering/agent-reports/'+$case.Id+'.md'))) { throw 'Failed native verification must not publish owner report.' }
        }
        if ((Get-Content (Join-Path $fixtureRepo ('src/'+$case.File)) -Raw) -ne 'original') { throw 'Native fixture execution modified primary checkout product file.' }
    }

    foreach ($case in @(
        @{Id='AICO-007';File='value7.txt';Tests='tests';Pass=$true},
        @{Id='AICO-008';File='value8.txt';Tests='tests_failure';Pass=$false}
    )) {
        $workspaceFile = Join-Path $workspaces ($case.Id+'\src\'+$case.File)
        $beforeHash = (Get-FileHash -LiteralPath $workspaceFile -Algorithm SHA256).Hash
        Set-FakeResult @{
            outcome='COMPLETED';summary='Python unittest verification';report_markdown='# Python verifier fixture'
            changes=@(@{path=('src/'+$case.File);operation='WRITE';content='python-verified-change';reason='Test Python stdlib verification'})
            verification_commands=@('python -B -m unittest discover -s '+$case.Tests+' -v');verification='Stdlib unittest';decisions='NONE';blockers='NONE';recommended_next='REVIEW'
        }
        $failed = $false
        try { Invoke-Runner -Id $case.Id } catch { if (-not $case.Pass -and $_.Exception.Message -match 'exit code 1') { $failed=$true } else { throw } }
        if ($case.Pass) {
            if ((Get-TaskStatus $case.Id) -ne 'REVIEW') { throw 'Passing stdlib unittest must advance task to REVIEW.' }
            $evidence = Get-Content (Join-Path $fixtureRepo ('docs/engineering/writable-evidence/'+$case.Id+'.md')) -Raw
            foreach ($marker in @('test_actual_product_verification','Ran 1 test','OK')) { if ($evidence -notmatch [regex]::Escape($marker)) { throw ('Actual unittest evidence missing: '+$marker) } }
            if ((Get-Content -LiteralPath $workspaceFile -Raw) -ne 'python-verified-change') { throw 'Passing unittest lost approved change.' }
        } else {
            if (-not $failed) { throw 'Failing unittest must reject verification.' }
            if ((Get-FileHash -LiteralPath $workspaceFile -Algorithm SHA256).Hash -ne $beforeHash) { throw 'Failing unittest must restore exact original bytes.' }
            if ((Get-TaskStatus $case.Id) -ne 'ACTIVE') { throw 'Failing unittest must retain ACTIVE.' }
            if (Test-Path (Join-Path $fixtureRepo ('docs/engineering/results/'+$case.Id+'-result-001.md'))) { throw 'Failing unittest must not publish result.' }
        }
    }
    $tokens=$null; $parseErrors=$null
    $runnerAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts/run-writable-agent.ps1'),[ref]$tokens,[ref]$parseErrors)
    foreach ($functionName in @('Assert-SafeArgument','Get-SafeCommand')) {
        $functionAst=$runnerAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName},$true)
        Invoke-Expression $functionAst.Extent.Text
    }
    $verificationPolicy = Get-Content (Join-Path $repoRoot '.codex/writable-policy.json') -Raw | ConvertFrom-Json
    foreach ($command in @('python -m unittest','python -B -m unittest discover -s tests -v')) { Get-SafeCommand -Command $command -Policy $verificationPolicy | Out-Null }
    foreach ($command in @(
        'python -B -m unittest && git status --short',
        'python -B -m unittest; git status --short',
        'python -B -m unittest | node warn-success.js',
        'python -B -m unittest discover -s ../tests',
        'python -B -m unittest discover -s C:\tests',
        'python -B -m unittest discover -s /tests',
        'python -B -m unittest discover -s $(Get-Location)',
        'python -B -m unittest discover -s:$env:TEMP',
        'python -c "print(1)"'
    )) {
        $rejected=$false
        try { Get-SafeCommand -Command $command -Policy $verificationPolicy | Out-Null } catch { $rejected=$true }
        if (-not $rejected) { throw ('Unittest authorization weakened command safety: '+$command) }
    }
    Set-FakeResult @{
        outcome='COMPLETED';summary='Git warning inventory regression';report_markdown='# Complete validated native inventory'
        changes=@(
            @{path='src/value9.txt';operation='WRITE';content="changed-with-LF`n";reason='Tracked LF implementation'},
            @{path='src/new9.txt';operation='WRITE';content="new-untracked-file`n";reason='New implementation artifact'}
        )
        verification_commands=@('node warn-success.js');verification='Native stdout and warning pass';decisions='NONE';blockers='NONE';recommended_next='REVIEW'
    }
    Invoke-Runner -Id 'AICO-009'
    if ((Get-TaskStatus 'AICO-009') -ne 'REVIEW') { throw 'Git newline warning with exit zero must not reject valid writable execution.' }
    $inventoryWorkspace = Join-Path $workspaces 'AICO-009'
    $nativeStderr = Join-Path $tempParent 'real-git-newline-warning.txt'
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $realGitPaths = @(& git -C $inventoryWorkspace diff --name-only -- 2> $nativeStderr)
        $realGitExit = $LASTEXITCODE
    } finally { $ErrorActionPreference=$savedPreference }
    $warningText = Get-Content -LiteralPath $nativeStderr -Raw
    if ($realGitExit -ne 0 -or $warningText -notmatch 'LF.*CRLF|CRLF.*LF') { throw 'Native inventory fixture must produce an actual Git LF/CRLF warning while exiting zero.' }
    $inventoryFunction=$runnerAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ChangedPaths'},$true)
    $gitOutputFunction=$runnerAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-GitOutput'},$true)
    Invoke-Expression $gitOutputFunction.Extent.Text
    Invoke-Expression $inventoryFunction.Extent.Text
    $nativePreferenceBefore = Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $inventory=@(Get-ChangedPaths -Workspace $inventoryWorkspace)
    if ($inventory.Count -ne 2 -or $inventory -notcontains 'src/value9.txt' -or $inventory -notcontains 'src/new9.txt') { throw ('Git inventory must contain exact tracked/untracked paths only: '+($inventory -join ',')) }
    if ($ErrorActionPreference -ne 'Stop') { throw 'Inventory must restore error preference after successful Git warning.' }
    $nonRepo=Join-Path $tempParent 'not-a-git-repo'; New-Item -ItemType Directory -Path $nonRepo | Out-Null
    $failed=$false
    try { Get-ChangedPaths -Workspace $nonRepo | Out-Null } catch { $failed=$_.Exception.Message -match 'git diff --name-only failed' }
    if (-not $failed) { throw 'Git inventory failure must throw rather than report empty inventory.' }
    if ($ErrorActionPreference -ne 'Stop') { throw 'Inventory must restore error preference after Git failure.' }
    $nativePreferenceAfter = Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    if (($null -eq $nativePreferenceBefore) -ne ($null -eq $nativePreferenceAfter)) { throw 'Git inventory must preserve presence or absence of native error preference.' }
    if ($null -ne $nativePreferenceBefore -and $nativePreferenceAfter.Value -ne $nativePreferenceBefore.Value) { throw 'Git inventory must restore native error preference value.' }
    $inventoryEvidence=Get-Content (Join-Path $fixtureRepo 'docs/engineering/writable-evidence/AICO-009.md') -Raw
    foreach ($path in @('src/value9.txt','src/new9.txt')) { if ($inventoryEvidence -notmatch [regex]::Escape($path)) { throw ('Changed artifact missing from evidence: '+$path) } }
    $runnerText = Get-Content (Join-Path $repoRoot "scripts\run-writable-agent.ps1") -Raw -Encoding UTF8

    foreach ($requiredPromptContract in @(
        "Do not invent test modules, test files, package scripts, commands, or verification targets",
        "If no project-specific verifier is evidenced, use git diff --check rather than inventing one.",
        "Exact local verification-command allowlist patterns:"
    )) {
        if ($runnerText -notmatch [regex]::Escape($requiredPromptContract)) {
            throw ("Writable prompt is missing verification-policy guidance: " + $requiredPromptContract)
        }
    }

    $preflightIndex = $runnerText.IndexOf('$safeVerificationCommands = @()')
    $writeIndex = $runnerText.IndexOf('Write-Utf8NoBom -Path $safe.FullPath -Value $contentValue')

    if ($preflightIndex -lt 0 -or $writeIndex -lt 0 -or $preflightIndex -gt $writeIndex) {
        throw "Writable verification commands are not preflighted before planned file writes."
    }

    Write-Host "PASS: isolated writable agent runtime" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedOpenRouter
    $env:DEEPSEEK_API_KEY = $savedDeepSeek
    $env:XAI_API_KEY = $savedXai
    $env:PATH = $savedPath

    if (Test-Path $fixtureRepo) {
        foreach ($id in @("AICO-001","AICO-002","AICO-003","AICO-004","AICO-005","AICO-006","AICO-007","AICO-008","AICO-009")) {
            $workspace = Join-Path $workspaces $id
            if (Test-Path $workspace) {
                try { & git -C $fixtureRepo worktree remove $workspace --force 2>$null | Out-Null } catch {}
            }
        }
        try { & git -C $fixtureRepo worktree prune 2>$null | Out-Null } catch {}
    }

    if (Test-Path $tempParent) {
        $cleanupTarget = [IO.Path]::GetFullPath($tempParent)
        $cleanupRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd([char[]]@('\','/')) + [IO.Path]::DirectorySeparatorChar
        if (-not $cleanupTarget.StartsWith($cleanupRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $cleanupTarget -Leaf) -notlike 'aico-writable-runtime-*') { throw 'Unsafe writable fixture cleanup path.' }
        Remove-Item -LiteralPath $cleanupTarget -Recurse -Force -ErrorAction SilentlyContinue
    }
}
