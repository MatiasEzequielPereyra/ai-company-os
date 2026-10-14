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
$variables = @('OPENROUTER_API_KEY','AICO_ERROR_INTELLIGENCE_ENABLED','AICO_ERROR_INTELLIGENCE_PATH','AICO_ERROR_INTELLIGENCE_MODULE_ROOT','AICO_ERROR_INTELLIGENCE_PYTHON','PYTHONPATH')
$saved = @{}
foreach ($name in $variables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }

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
    $type = [regex]::Match($task, '(?m)^Type:\s*(\S+)').Groups[1].Value
    if (-not $type) { return }
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
        "tests_ok","tests_probe_902"
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
        "validate-diagnostic-evidence.ps1",
        "write-operational-event.ps1",
        "error-intelligence.ps1"
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
    [string]$Workload,
    [string]$TaskId
)
if ($Role -ne "frontend" -or $Workload -ne "writable") { throw "Unexpected writable routing identity." }
if ([IO.Path]::GetFileName($SchemaPath) -ne "writable-bug-change-set.schema.json") { throw "BUG task did not select diagnostic writable schema." }
[IO.File]::AppendAllText((Join-Path $ProjectPath ".codex\provider-invocations.txt"), "one mock invocation`n")
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
    Write-NoBom (Join-Path $fixtureRepo "docs\engineering\work-requests\WR-TEST.md") "# Work Request`nType: BUG`n"

    $nl = [Environment]::NewLine
    Write-NoBom (Join-Path $fixtureRepo "bug_value2.py") ("def value():" + $nl + "    return 1" + $nl)

    Write-NoBom (Join-Path $fixtureRepo "tests_ok\test_ok.py") @'
import unittest

class AlwaysGreen(unittest.TestCase):
    def test_green(self):
        self.assertTrue(True)
'@

    Write-NoBom (Join-Path $fixtureRepo "tests_probe_902\test_probe.py") ("import pathlib" + $nl + "import unittest" + $nl + $nl + "class CauseProbe(unittest.TestCase):" + $nl + "    def test_wrong_value_is_present(self):" + $nl + "        ns = {}" + $nl + "        exec(pathlib.Path(`"bug_value2.py`").read_text(encoding=`"utf-8`"), ns)" + $nl + "        self.assertEqual(ns[`"value`"](), 1)" + $nl)

    New-BugTask -Id "AICO-902" -SourceFile "bug_value2.py" -TestDir "tests_ok"

    & git -C $fixtureRepo init | Out-Null
    & git -C $fixtureRepo config user.email "aico-test@example.invalid"
    & git -C $fixtureRepo config user.name "AI Company OS Test"
    & git -C $fixtureRepo add .
    & git -C $fixtureRepo commit -m "diagnostic runtime fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture commit failed." }

    foreach ($id in @("AICO-902")) {
        & (Join-Path $repoRoot "scripts\new-agent-workspace.ps1") -Id $id -ProjectPath $fixtureRepo -WorkspaceRoot $workspaces | Out-Null
    }

    $env:OPENROUTER_API_KEY = "diagnostic-fixture-key"
    $env:AICO_ERROR_INTELLIGENCE_ENABLED = '1'
    $env:AICO_ERROR_INTELLIGENCE_PATH = Join-Path $tempParent 'memory.sqlite3'
    $env:AICO_ERROR_INTELLIGENCE_MODULE_ROOT = Join-Path $repoRoot 'src'
    if (-not $env:AICO_ERROR_INTELLIGENCE_PYTHON) { $env:AICO_ERROR_INTELLIGENCE_PYTHON = (Get-Command python -CommandType Application | Select-Object -First 1).Source }
    $env:PYTHONPATH = Join-Path $repoRoot 'src' 

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

    # Diagnostic rejection remains authoritative; memory cannot advance lifecycle.
    $diagnostic = Join-Path $fixtureRepo 'docs\engineering\diagnostics\AICO-902-diagnostic-v1.json'
    $diagnosticHash = (Get-FileHash -LiteralPath $diagnostic -Algorithm SHA256).Hash
    if (@(Get-Content (Join-Path $fixtureRepo '.codex\provider-invocations.txt')).Count -ne 1) { throw 'Automatic capture performed an extra provider invocation.' }
    if ((Get-Content (Join-Path $fixtureRepo 'tasks\AICO-902.md') -Raw) -notmatch 'Status: ACTIVE') { throw 'Rejected diagnostic changed task lifecycle.' }
    if (@(Get-ChildItem (Join-Path $fixtureRepo 'docs\engineering\results') -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Rejected diagnostic published a Task Result.' }
    $query = @"
import sqlite3, sys
from company_os.error_intelligence.runtime import lookup
result = lookup(sys.argv[1], component="writable-runner")
con = sqlite3.connect("file:" + sys.argv[2].replace("\\", "/") + "?mode=ro", uri=True)
rows = con.execute("select i.status, count(o.id), i.task_id from incidents i join occurrences o on o.incident_id=i.id group by i.id").fetchall()
assert len(rows) == 1, rows
assert rows[0][0] == "OBSERVED" and rows[0][1] == 1 and rows[0][2] == "AICO-902", rows
assert not result.get("verified_solutions"), result
assert result.get("action_authorized") is False, result
print("PASS: observed diagnostic failure; no verified fix or authorized recovery")
"@
    $queryPath = Join-Path $tempParent 'assert-memory.py'
    Write-NoBom $queryPath $query
    & $env:AICO_ERROR_INTELLIGENCE_PYTHON $queryPath $fixtureRepo $env:AICO_ERROR_INTELLIGENCE_PATH
    if ($LASTEXITCODE -ne 0) { throw 'Diagnostic runtime / Error Intelligence coexistence query failed.' }
    if ((Get-FileHash -LiteralPath $diagnostic -Algorithm SHA256).Hash -cne $diagnosticHash) { throw 'Historical lookup changed diagnostic evidence.' }
    Write-Host 'PASS: diagnostic rejection, durable evidence, automatic incident, exactly one mock provider, unchanged lifecycle'
}
finally {
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
    if (Test-Path $tempParent) { Remove-Item -LiteralPath $tempParent -Recurse -Force -ErrorAction SilentlyContinue }
}
