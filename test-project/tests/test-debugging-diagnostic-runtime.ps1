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
$tempParent = Join-Path $env:TEMP ("aico-debug-runtime-" + [Guid]::NewGuid().ToString("N"))
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

function Invoke-Runner {
    param([string]$Id)
    & (Join-Path $fixtureRepo "scripts\run-writable-agent.ps1") -Id $Id -ProjectPath $fixtureRepo -WorkspacePath (Join-Path $workspaces $Id) -Provider Auto
}

function New-BugResult {
    param(
        [string]$SourceFile,
        [string]$FixedContent,
        [string]$ReproductionCommand,
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
                    prediction = "The regression command exits non-zero before the repair."
                    falsifier = "The regression command exits zero before the repair."
                    experiment_command = $ReproductionCommand
                    supported_when = "EXIT_NONZERO"
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
        "docs\engineering\dispatch","docs\engineering\reviews",
        "tests_bug","tests_ok","tests_still_broken"
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
        "resolve-writable-required-files.ps1",
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

    New-BugTask -Id "AICO-901" -SourceFile "bug_value.py" -TestDir "tests_bug"
    New-BugTask -Id "AICO-902" -SourceFile "bug_value2.py" -TestDir "tests_ok"
    New-BugTask -Id "AICO-903" -SourceFile "bug_value3.py" -TestDir "tests_still_broken"

    & git -C $fixtureRepo init | Out-Null
    & git -C $fixtureRepo config user.email "aico-test@example.invalid"
    & git -C $fixtureRepo config user.name "AI Company OS Test"
    & git -C $fixtureRepo add .
    & git -C $fixtureRepo commit -m "diagnostic runtime fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture commit failed." }

    foreach ($id in @("AICO-901","AICO-902","AICO-903")) {
        & (Join-Path $repoRoot "scripts\new-agent-workspace.ps1") -Id $id -ProjectPath $fixtureRepo -WorkspaceRoot $workspaces | Out-Null
    }

    $env:OPENROUTER_API_KEY = "diagnostic-fixture-key"

    $repro901 = "python -B -m unittest discover -s tests_bug"
    $fixed901 = "def value():" + $nl + "    return 2" + $nl
    Set-FakeResult (New-BugResult -SourceFile "bug_value.py" -FixedContent $fixed901 -ReproductionCommand $repro901 -VerificationCommand $repro901)
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
    Set-FakeResult (New-BugResult -SourceFile "bug_value2.py" -FixedContent $fixed902 -ReproductionCommand $repro902)
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
    Set-FakeResult (New-BugResult -SourceFile "bug_value3.py" -FixedContent $wrong903 -ReproductionCommand $repro903 -VerificationCommand "git diff --check")
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

    Write-Host "PASS: debugging diagnostic writable runtime" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedOpenRouter
    if (Test-Path $tempParent) { Remove-Item $tempParent -Recurse -Force -ErrorAction SilentlyContinue }
}
