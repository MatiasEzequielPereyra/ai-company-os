param()

$ErrorActionPreference = "Stop"

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "SKIP: git unavailable." -ForegroundColor Yellow
    exit 0
}
if ($null -eq (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "SKIP: python unavailable." -ForegroundColor Yellow
    exit 0
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempParent = Join-Path ([IO.Path]::GetTempPath()) ("aico-debug-runtime-" + [Guid]::NewGuid().ToString("N"))
$fixtureRepo = Join-Path $tempParent "repo"
$workspaces = Join-Path $tempParent "worktrees"
$savedOpenRouter = $env:OPENROUTER_API_KEY

function Write-NoBom {
    param([string]$Path,[string]$Value)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path,$Value,(New-Object Text.UTF8Encoding($false)))
}

function New-BugTask {
    param([string]$Id,[string]$SourceFile,[string]$TestDir)

    $task = @(
        "# $Id - Diagnostic fixture",
        "",
        "## Metadata",
        "",
        "ID: $Id",
        "Status: ACTIVE",
        "Priority: P1",
        "Owner: frontend",
        "Workflow phase: IMPLEMENTATION",
        "Work kind: IMPLEMENTATION",
        "Work request: WR-TEST",
        "Type: BUG",
        "",
        "---",
        "",
        "## Objective",
        "",
        "Repair $SourceFile and prove the original defect with $TestDir.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] The original regression is observed before the change.",
        "- [ ] The same regression signal passes after the change.",
        "",
        "---",
        "",
        "## Dependencies",
        "",
        "-",
        "",
        "---",
        "",
        "## Testing Requirements",
        "",
        "Run python -B -m unittest discover -s $TestDir."
    ) -join [Environment]::NewLine

    Write-NoBom (Join-Path $fixtureRepo ("tasks\" + $Id + ".md")) $task

    $dispatch = @(
        "# Execution Request - $Id",
        "Task: $Id",
        "Owner: frontend",
        "",
        "## Objective",
        "",
        "Repair $SourceFile.",
        "",
        "## Context",
        "",
        "Source: $SourceFile",
        "Regression: $TestDir",
        "",
        "## Testing Requirements",
        "",
        "python -B -m unittest discover -s $TestDir"
    ) -join [Environment]::NewLine

    Write-NoBom (Join-Path $fixtureRepo ("docs\engineering\dispatch\" + $Id + ".md")) $dispatch
}

function Set-FakeResult {
    param([object]$Payload)
    Write-NoBom (Join-Path $fixtureRepo ".codex\fake-writable-result.json") ($Payload | ConvertTo-Json -Depth 100)
}

function Set-ValidAuthorizationReceipt {
    param([string]$Id)
    $task = Get-Content -LiteralPath (Join-Path $fixtureRepo ("tasks\" + $Id + ".md")) -Raw -Encoding UTF8
    $taskTypeMatches = [regex]::Matches($task, '(?m)^Type:\s*(\S+)\s*$')
    $requestPath = Join-Path $fixtureRepo 'docs\engineering\work-requests\WR-TEST.md'
    $requestTypeMatches = @()
    if (Test-Path -LiteralPath $requestPath -PathType Leaf) {
        $existingRequest = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8
        $requestTypeMatches = [regex]::Matches($existingRequest, '(?m)^Type:\s*(\S+)\s*$')
    }
    if ($taskTypeMatches.Count -ne 1 -or $requestTypeMatches.Count -gt 1) { return }
    $type = $taskTypeMatches[0].Groups[1].Value
    if (-not $type) { return }
    if ($requestTypeMatches.Count -eq 1 -and $requestTypeMatches[0].Groups[1].Value -cne $type) { return }
    . (Join-Path $repoRoot 'scripts\writable-authorization-guard.ps1')
    $scope = Get-WritableScopeFingerprint -TaskContent $task
    $created = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $expires = [DateTimeOffset]::UtcNow.AddHours(2).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $receipt = @"
# Work Request

ID: WR-TEST
Type: $type
Requested by: fixture authorization test
Created: $created

## Authorization Receipt

Requested action: Implement task $Id as described in its current objective and acceptance criteria.
Permitted scope: WRITABLE_IMPLEMENTATION
Implementation authorization: AUTHORIZED
Authorized task: $Id
Authorized operation: WRITABLE
Authorized execution mode: WRITABLE
Authorized provider invocation: ALLOWED
Authorized write scope: TASK_WORKTREE_ONLY
Authorized scope SHA-256: $scope
Authorization expires (UTC): $expires
Retained restrictions: NONE
"@
    Write-NoBom (Join-Path $fixtureRepo 'docs\engineering\work-requests\WR-TEST.md') $receipt
}

function Invoke-Runner {
    param([string]$Id)
    Set-ValidAuthorizationReceipt -Id $Id
    & (Join-Path $fixtureRepo "scripts\run-writable-agent.ps1") -Id $Id -ProjectPath $fixtureRepo -WorkspacePath (Join-Path $workspaces $Id) -Provider Auto
}

function New-BugResult {
    param(
        [string]$SourceFile,
        [string]$FixedContent,
        [string]$ReproductionCommand,
        [string]$HypothesisCommand,
        [string]$VerificationCommand = "git diff --check"
    )

    return [ordered]@{
        outcome = "COMPLETED"
        summary = "Evidence-backed bug repair fixture."
        report_markdown = "# Repair - diagnostic contract fixture."
        changes = @(
            [ordered]@{
                path = $SourceFile
                operation = "WRITE"
                content = $FixedContent
                reason = "Repair the reproduced defect."
            }
        )
        verification_commands = @($VerificationCommand)
        verification = "Runtime verification requested."
        decisions = "Use the smallest repair."
        blockers = "NONE"
        recommended_next = "REVIEW"
        diagnostic_plan = [ordered]@{
            reproduction_signal = [ordered]@{
                kind = "COMMAND"
                command = $ReproductionCommand
                working_directory = "."
                broken_when = "EXIT_NONZERO"
            }
            hypotheses = @(
                [ordered]@{
                    id = "H1"
                    statement = "The source returns the wrong value."
                    prediction = "A direct causal probe confirms the implementation returns the known wrong value."
                    falsifier = "The direct causal probe does not observe the known wrong value."
                    experiment_command = $HypothesisCommand
                    supported_when = "EXIT_ZERO"
                }
            )
            cause = [ordered]@{
                status = "CONFIRMED"
                statement = "The source returns the wrong value."
                hypothesis_refs = @("H1")
            }
            resolution = [ordered]@{
                classification = "REPAIR"
                summary = "Return the expected value."
                residual_risk = ""
            }
        }
    }
}

try {
    foreach ($dir in @(
        "scripts","schemas","tasks",".codex",".codex\agents",
        "docs\engineering\work-requests",
        "docs\engineering\dispatch","docs\engineering\reviews",
        "tests_bug","tests_ok","tests_still_broken","tests_probe_901","tests_probe_902","tests_probe_903"
    )) {
        New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRepo $dir) | Out-Null
    }
    New-Item -ItemType Directory -Force -Path $workspaces | Out-Null

    foreach ($name in @(
        "run-writable-agent.ps1",
        "writable-authorization-guard.ps1",
        "task-execution-lock.ps1",
        "advance-task.ps1",
        "update-task.ps1",
        "submit-task-result.ps1",
        "build-agent-context.ps1",
        "build-corrective-analysis-context.ps1",
        "resolve-writable-required-files.ps1",
        "validate-json-contract.ps1",
        "validate-diagnostic-evidence.ps1"
    )) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $fixtureRepo ("scripts\" + $name)) -Force
    }

    foreach ($name in @(
        "writable-change-set.schema.json",
        "writable-bug-change-set.schema.json",
        "diagnostic-evidence.schema.json"
    )) {
        Copy-Item (Join-Path $repoRoot ("schemas\" + $name)) (Join-Path $fixtureRepo ("schemas\" + $name)) -Force
    }

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
if ($Role -ne "frontend" -or $Workload -ne "writable") { throw "Unexpected writable routing identity." }
if ([IO.Path]::GetFileName($SchemaPath) -ne "writable-bug-change-set.schema.json") { throw "BUG task did not select diagnostic writable schema." }
Copy-Item (Join-Path $ProjectPath ".codex\fake-writable-result.json") $OutputPath -Force
if ($env:AICO_AUTH_MUTATION_TEST) {
    [IO.File]::AppendAllText((Join-Path $ProjectPath '.codex\mutation-provider-calls.txt'), "$Provider`n")
    [IO.File]::WriteAllText((Join-Path $ProjectPath '.codex\mutation-output-path.txt'), $OutputPath)
}
[PSCustomObject]@{ Provider = $Provider; Model = $Model }
'@
    Write-NoBom (Join-Path $fixtureRepo "scripts\provider-router.ps1") $fakeRouter

    Write-NoBom (Join-Path $fixtureRepo ".codex\provider-config.json") (@{
        writable_auto_order = @("OpenRouter")
        writable_models = @{ OpenRouter = "openrouter/free" }
        models = @{ OpenRouter = "openrouter/free" }
        context_max_chars = 50000
    } | ConvertTo-Json -Depth 10)

    Write-NoBom (Join-Path $fixtureRepo ".codex\agents\frontend.md") "Frontend diagnostic fixture role."
    Write-NoBom (Join-Path $fixtureRepo "AGENTS.md") "Diagnostic runtime fixture."
    Write-NoBom (Join-Path $fixtureRepo "docs\engineering\work-requests\WR-TEST.md") "# Work Request`nType: BUG`n"

    $nl = [Environment]::NewLine
    Write-NoBom (Join-Path $fixtureRepo "bug_value.py") ("def value():" + $nl + "    return 1" + $nl)
    Write-NoBom (Join-Path $fixtureRepo "bug_value2.py") ("def value():" + $nl + "    return 1" + $nl)
    Write-NoBom (Join-Path $fixtureRepo "bug_value3.py") ("def value():" + $nl + "    return 1" + $nl)

    Write-NoBom (Join-Path $fixtureRepo "tests_bug\test_bug.py") @'
import pathlib
import unittest

class Regression(unittest.TestCase):
    def test_value(self):
        ns = {}
        exec(pathlib.Path("bug_value.py").read_text(encoding="utf-8"), ns)
        self.assertEqual(ns["value"](), 2)
'@

    Write-NoBom (Join-Path $fixtureRepo "tests_ok\test_ok.py") @'
import unittest

class AlwaysGreen(unittest.TestCase):
    def test_green(self):
        self.assertTrue(True)
'@

    Write-NoBom (Join-Path $fixtureRepo "tests_still_broken\test_bug.py") @'
import pathlib
import unittest

class Regression(unittest.TestCase):
    def test_value(self):
        ns = {}
        exec(pathlib.Path("bug_value3.py").read_text(encoding="utf-8"), ns)
        self.assertEqual(ns["value"](), 2)
'@

    Write-NoBom (Join-Path $fixtureRepo "tests_probe_901\test_probe.py") ("import pathlib" + $nl + "import unittest" + $nl + $nl + "class CauseProbe(unittest.TestCase):" + $nl + "    def test_wrong_value_is_present(self):" + $nl + "        ns = {}" + $nl + "        exec(pathlib.Path(`"bug_value.py`").read_text(encoding=`"utf-8`"), ns)" + $nl + "        self.assertEqual(ns[`"value`"](), 1)" + $nl)

    Write-NoBom (Join-Path $fixtureRepo "tests_probe_902\test_probe.py") ("import pathlib" + $nl + "import unittest" + $nl + $nl + "class CauseProbe(unittest.TestCase):" + $nl + "    def test_wrong_value_is_present(self):" + $nl + "        ns = {}" + $nl + "        exec(pathlib.Path(`"bug_value2.py`").read_text(encoding=`"utf-8`"), ns)" + $nl + "        self.assertEqual(ns[`"value`"](), 1)" + $nl)

    Write-NoBom (Join-Path $fixtureRepo "tests_probe_903\test_probe.py") ("import pathlib" + $nl + "import unittest" + $nl + $nl + "class CauseProbe(unittest.TestCase):" + $nl + "    def test_wrong_value_is_present(self):" + $nl + "        ns = {}" + $nl + "        exec(pathlib.Path(`"bug_value3.py`").read_text(encoding=`"utf-8`"), ns)" + $nl + "        self.assertEqual(ns[`"value`"](), 1)" + $nl)


    New-BugTask -Id "AICO-901" -SourceFile "bug_value.py" -TestDir "tests_bug"
    New-BugTask -Id "AICO-902" -SourceFile "bug_value2.py" -TestDir "tests_ok"
    New-BugTask -Id "AICO-903" -SourceFile "bug_value3.py" -TestDir "tests_still_broken"
    foreach ($number in @(904,905)) {
        $suffix = [string]$number
        Write-NoBom (Join-Path $fixtureRepo "bug_value$suffix.py") ("def value():" + $nl + "    return 1" + $nl)
        $regression = @"
import pathlib
import unittest

class Regression(unittest.TestCase):
    def test_value(self):
        ns = {}
        exec(pathlib.Path('bug_value$suffix.py').read_text(encoding='utf-8'), ns)
        self.assertEqual(ns['value'](), 2)
"@
        Write-NoBom (Join-Path $fixtureRepo "tests_auth_$suffix\test_value.py") $regression
        Write-NoBom (Join-Path $fixtureRepo "tests_auth_probe_$suffix\test_probe.py") @'
import os
import pathlib
import re
import unittest

class Probe(unittest.TestCase):
    def test_probe(self):
        if os.environ.get('AICO_AUTH_MUTATION_TEST') == 'DIAGNOSTIC_EXPIRE':
            request = pathlib.Path(os.environ['AICO_AUTH_FIXTURE_REQUEST'])
            value = request.read_text(encoding='utf-8')
            request.write_text(re.sub(r'(?m)^Authorization expires \(UTC\):.*$', 'Authorization expires (UTC): 2000-01-01T00:00:00Z', value), encoding='utf-8')
        self.assertTrue(True)
'@
        if ($number -eq 905) {
            $regression += @'

        import os
        if os.environ.get('AICO_AUTH_MUTATION_TEST') == 'VERIFY_REVOKE' and ns['value']() == 2:
            request = pathlib.Path(os.environ['AICO_AUTH_FIXTURE_REQUEST'])
            request.with_name('verification-observed-applied-source.txt').write_text('source value was 2 before revocation', encoding='utf-8')
            value = request.read_text(encoding='utf-8')
            request.write_text(value.replace('Implementation authorization: AUTHORIZED', 'Implementation authorization: NOT_INFERRED'), encoding='utf-8')
'@
            Write-NoBom (Join-Path $fixtureRepo "tests_auth_$suffix\test_value.py") $regression
        }
        New-BugTask -Id "AICO-$suffix" -SourceFile "bug_value$suffix.py" -TestDir "tests_auth_$suffix"
    }

    & git -C $fixtureRepo init | Out-Null
    & git -C $fixtureRepo config user.email "aico-test@example.invalid"
    & git -C $fixtureRepo config user.name "AI Company OS Test"
    & git -C $fixtureRepo add .
    & git -C $fixtureRepo commit -m "diagnostic runtime fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture commit failed." }

    foreach ($id in @("AICO-901","AICO-902","AICO-903","AICO-904","AICO-905")) {
        & (Join-Path $repoRoot "scripts\new-agent-workspace.ps1") -Id $id -ProjectPath $fixtureRepo -WorkspaceRoot $workspaces | Out-Null
    }

    $env:OPENROUTER_API_KEY = "diagnostic-fixture-key"

    $repro901 = "python -B -m unittest discover -s tests_bug"
    $fixed901 = "def value():" + $nl + "    return 2" + $nl
    Set-FakeResult (New-BugResult -SourceFile "bug_value.py" -FixedContent $fixed901 -ReproductionCommand $repro901 -HypothesisCommand "python -B -m unittest discover -s tests_probe_901" -VerificationCommand $repro901)
    Invoke-Runner -Id "AICO-901"

    if ((Get-Content (Join-Path $fixtureRepo "bug_value.py") -Raw) -notmatch "return 1") {
        throw "Diagnostic runtime modified primary source."
    }
    if ((Get-Content (Join-Path $workspaces "AICO-901\bug_value.py") -Raw) -notmatch "return 2") {
        throw "Diagnostic runtime did not apply repair in isolated worktree."
    }

    $artifact901 = Join-Path $fixtureRepo "docs\engineering\diagnostics\AICO-901-diagnostic-v1.json"
    if (-not (Test-Path $artifact901 -PathType Leaf)) { throw "Diagnostic artifact was not persisted." }
    & (Join-Path $fixtureRepo "scripts\validate-diagnostic-evidence.ps1") -JsonPath $artifact901 | Out-Null
    $e901 = Get-Content $artifact901 -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($e901.state -ne "COMPLETE") { throw "Successful repair did not complete diagnostic artifact." }
    if ($e901.reproduction.signal_fingerprint -cne $e901.post_fix_replay.signal_fingerprint) { throw "Same-signal identity was not preserved." }
    if ($e901.reproduction.pre_fix.observation -ne "BROKEN_OBSERVED") { throw "Pre-fix broken observation missing." }
    if ($e901.post_fix_replay.observation -ne "FIXED_OBSERVED") { throw "Post-fix fixed observation missing." }
    if ($e901.attempts[0].hypotheses[0].result -ne "SUPPORTED") { throw "Hypothesis experiment was not bound to runtime evidence." }

    $result901 = Get-ChildItem (Join-Path $fixtureRepo "docs\engineering\results") -Filter "AICO-901-result-*.md" | Select-Object -First 1
    if ($null -eq $result901 -or (Get-Content $result901.FullName -Raw) -notmatch "docs/engineering/diagnostics/AICO-901-diagnostic-v1.json") {
        throw "Task Result did not preserve the diagnostic artifact identity."
    }

    $repro902 = "python -B -m unittest discover -s tests_ok"
    $fixed902 = "def value():" + $nl + "    return 2" + $nl
    Set-FakeResult (New-BugResult -SourceFile "bug_value2.py" -FixedContent $fixed902 -ReproductionCommand $repro902 -HypothesisCommand "python -B -m unittest discover -s tests_probe_902")
    $notReproduced = $false
    try { Invoke-Runner -Id "AICO-902" }
    catch {
        if ($_.Exception.Message -match "did not observe the broken state") { $notReproduced = $true }
        else { throw }
    }
    if (-not $notReproduced) { throw "Runtime did not fail closed when the bug was not reproduced." }
    if ((Get-Content (Join-Path $workspaces "AICO-902\bug_value2.py") -Raw) -notmatch "return 1") {
        throw "Source mutated even though reproduction failed."
    }
    $e902 = Get-Content (Join-Path $fixtureRepo "docs\engineering\diagnostics\AICO-902-diagnostic-v1.json") -Raw | ConvertFrom-Json
    if ($e902.state -ne "NOT_REPRODUCED") { throw "Non-reproduction was not recorded durably." }

    $repro903 = "python -B -m unittest discover -s tests_still_broken"
    $wrong903 = "def value():" + $nl + "    return 3" + $nl
    Set-FakeResult (New-BugResult -SourceFile "bug_value3.py" -FixedContent $wrong903 -ReproductionCommand $repro903 -HypothesisCommand "python -B -m unittest discover -s tests_probe_903" -VerificationCommand "git diff --check")
    $postFixRejected = $false
    try { Invoke-Runner -Id "AICO-903" }
    catch {
        if ($_.Exception.Message -match "post-fix replay still reproduces") { $postFixRejected = $true }
        else { throw }
    }
    if (-not $postFixRejected) { throw "Runtime accepted a repair that still reproduced the bug." }
    if ((Get-Content (Join-Path $workspaces "AICO-903\bug_value3.py") -Raw) -notmatch "return 1") {
        throw "Failed post-fix repair was not restored."
    }
    $e903 = Get-Content (Join-Path $fixtureRepo "docs\engineering\diagnostics\AICO-903-diagnostic-v1.json") -Raw | ConvertFrom-Json
    if ($e903.state -ne "FAILED_POST_FIX") { throw "Failed post-fix evidence was not preserved." }

    $env:AICO_AUTH_FIXTURE_REQUEST = Join-Path $fixtureRepo 'docs\engineering\work-requests\WR-TEST.md'
    try {
        foreach ($number in @(904,905)) {
            $id = "AICO-$number"
            $env:AICO_AUTH_MUTATION_TEST = if ($number -eq 904) { 'DIAGNOSTIC_EXPIRE' } else { 'VERIFY_REVOKE' }
            $evidencePath = Join-Path $fixtureRepo "docs\engineering\writable-evidence\$id.md"
            $reportPath = Join-Path $fixtureRepo "docs\engineering\agent-reports\$id.md"
            foreach ($path in @($evidencePath,$reportPath)) { Write-NoBom $path 'retain prior authorization evidence' }
            $callsPath = Join-Path $fixtureRepo '.codex\mutation-provider-calls.txt'
            Remove-Item $callsPath -Force -ErrorAction SilentlyContinue
            $repro = "python -B -m unittest discover -s tests_auth_$number"
            $fixed = "def value():" + $nl + '    return 2' + $nl
            Set-FakeResult (New-BugResult -SourceFile "bug_value$number.py" -FixedContent $fixed -ReproductionCommand $repro -HypothesisCommand "python -B -m unittest discover -s tests_auth_probe_$number" -VerificationCommand $repro)
            $rejected = $false
            try { Invoke-Runner -Id $id }
            catch { if ($_.Exception.Message -match 'BLOCKED') { $rejected = $true } else { throw } }
            if (-not $rejected) { throw "${id}: authorization invalidation was ignored." }
            if ($number -eq 905 -and -not (Test-Path (Join-Path (Split-Path $env:AICO_AUTH_FIXTURE_REQUEST) 'verification-observed-applied-source.txt'))) { throw "${id}: verification did not observe applied source before revoking authorization." }
            $taskContent = Get-Content (Join-Path $fixtureRepo "tasks\$id.md") -Raw
            if ($taskContent -notmatch '(?m)^Status: BLOCKED\s*$') { throw "${id}: task not BLOCKED." }
            if ((Get-Content (Join-Path $workspaces "$id\bug_value$number.py") -Raw) -notmatch 'return 1') { throw "${id}: source mutation survived rejection." }
            if (@(& git -C (Join-Path $workspaces $id) status --porcelain).Count -ne 0) { throw "${id}: source worktree changed after rejection." }
            foreach ($path in @($evidencePath,$reportPath)) {
                if ((Get-Content $path -Raw) -cne 'retain prior authorization evidence') { throw "${id}: prior evidence was overwritten." }
            }
            if (Test-Path (Join-Path $fixtureRepo "docs\engineering\results\$id-result-001.md")) { throw "${id}: success result published." }
            if (Test-Path (Join-Path $fixtureRepo "docs\engineering\diagnostics\$id-diagnostic-v1.json")) { throw "${id}: rejected attempt left a diagnostic artifact." }
            if (@(Get-Content $callsPath).Count -ne 1) { throw "${id}: unexpected fallback call." }
            $outputPath = Get-Content (Join-Path $fixtureRepo '.codex\mutation-output-path.txt') -Raw
            if (Test-Path -LiteralPath $outputPath) { throw "${id}: provider temporary output was not removed." }
            Write-Host "PASS: $env:AICO_AUTH_MUTATION_TEST; calls=1; state=BLOCKED; source/evidence preserved; temporary output removed."
        }
    }
    finally {
        Remove-Item Env:AICO_AUTH_MUTATION_TEST -ErrorAction SilentlyContinue
        Remove-Item Env:AICO_AUTH_FIXTURE_REQUEST -ErrorAction SilentlyContinue
    }

    $task902Path = Join-Path $fixtureRepo "tasks\AICO-902.md"
    $originalTask902 = Get-Content -LiteralPath $task902Path -Raw -Encoding UTF8
    Write-NoBom -Path $task902Path -Value ($originalTask902 -replace '(?m)^Type: BUG\r?$', 'Type: FEATURE')
    $typeConflictRejected = $false
    try { Invoke-Runner -Id "AICO-902" }
    catch { $typeConflictRejected = $_.Exception.Message -match 'Task/work-request type mismatch' }
    if (-not $typeConflictRejected) { throw "Writable runner accepted conflicting Task and Work Request types." }

    $task902WithoutType = $originalTask902 -replace '(?m)^Type: BUG\r?$', ''
    Write-NoBom -Path $task902Path -Value $task902WithoutType
    Write-NoBom -Path (Join-Path $fixtureRepo "docs\engineering\work-requests\WR-TEST.md") "# Work Request`n"
    $missingRequestTypeRejected = $false
    try { Invoke-Runner -Id "AICO-902" }
    catch { $missingRequestTypeRejected = $_.Exception.Message -match 'Work Request Type is required' }
    if (-not $missingRequestTypeRejected) { throw "Writable runner accepted incomplete Task/Work Request type identity." }

    Write-Host "PASS: debugging diagnostic writable runtime" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedOpenRouter
    if (Test-Path $tempParent) { Remove-Item $tempParent -Recurse -Force -ErrorAction SilentlyContinue }
}
