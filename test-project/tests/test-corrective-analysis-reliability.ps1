param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('aico-corrective-analysis-' + [Guid]::NewGuid().ToString('N'))

function Write-FixtureFile {
    param([string]$Path,[string]$Content)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    [IO.File]::WriteAllText($Path,$Content,[Text.UTF8Encoding]::new($false))
}
function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}
function Get-Status {
    param([string]$Root,[string]$Id)
    $text = Get-Content (Join-Path $Root "tasks/$Id.md") -Raw
    if ($text -match '(?m)^Status:\s*(\w+)') { return $Matches[1] }
    throw 'Missing task status'
}
function New-AnalysisFixture {
    param([string]$Name)
    $root = Join-Path $tempRoot $Name
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    # Keep the actual runtime, router, validators and lifecycle scripts together.
    Copy-Item (Join-Path $repoRoot 'scripts') $root -Recurse
    Copy-Item (Join-Path $repoRoot 'schemas') $root -Recurse
    Copy-Item (Join-Path $repoRoot '.codex') $root -Recurse
    Write-FixtureFile (Join-Path $root 'tasks/AICO-002.md') @'
# AICO-002 - Plan architecture
ID: AICO-002
Status: ACTIVE
Owner: cto
Priority: P1
Work kind: PLANNING
Work request: WR-001
Workflow profile: standard

## Objective

TASK_SENTINEL Produce architecture and an ADR for the client API.

---

## Requirements

- CTO owns the ADR; implementation is not authorized.

---

## Acceptance Criteria

- [ ] Architecture, contracts and ADR are supplied.

---

## Dependencies

-

---

## Evidence

-

---

## Transition Log

- Fixture authorized.

---

## Notes

-
'@
    Write-FixtureFile (Join-Path $root 'docs/engineering/dispatch/AICO-002.md') "# ORIGINAL_DISPATCH_SENTINEL`nTask: AICO-002`nOwner: cto`nCTO architecture planning, no implementation."
    Write-FixtureFile (Join-Path $root 'README.md') ('GENERAL_CONTEXT_BLOAT ' + ('x' * 60000))
    Write-FixtureFile (Join-Path $root '.codex/provider-config.json') (@{
        auto_order = @('Ollama'); allow_paid_fallback = $false
        models = @{ Ollama = 'fake-local-model' }
        analysis_context_max_chars = 80000; ollama_context_max_chars = 12000
        provider_timeout_seconds = @{ Ollama = 30 }
    } | ConvertTo-Json -Depth 10)
    Write-FixtureFile (Join-Path $root 'scripts/local-runtime/resolve-local-runtime.ps1') @'
param([string]$ProjectPath,[string]$Role,[string]$Workload,[string]$ModelOverride)
[PSCustomObject]@{ Available=$true; Profile='LOCAL_GPU_12GB'; CapabilityScore=78; Model='fake-local-model'; NumCtx=16384; NumPredict=2048; ContextMaxChars=80000; GateContextMaxChars=12000; GateArtifactMaxChars=7000; Reason='Deterministic test, no network.' }
'@
    Write-FixtureFile (Join-Path $root 'scripts/providers/invoke-ollama.ps1') @'
param([string]$Prompt,[string]$Context,[string]$SchemaPath,[string]$OutputPath,[string]$Model,[int]$NumCtx,[int]$NumPredict,[int]$TimeoutSeconds)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$log = Join-Path $root 'fake-calls.jsonl'
$mode = (Get-Content (Join-Path $root 'fake-mode.txt') -Raw).Trim()
$repair = $Prompt -match 'CORRECTION REQUIRED'
Add-Content $log (@{ mode=$mode; repair=$repair; context=$Context; prompt=$Prompt; length=$Context.Length } | ConvertTo-Json -Depth 5 -Compress)
$blocked = $mode -in @('retry','invalid','external') -and -not ($mode -eq 'retry' -and $repair)
$payload = @{
 outcome = $(if ($blocked) {'BLOCKED'} else {'COMPLETED'})
 summary = 'Deterministic CTO assessment'
 report_markdown = $(if ($blocked) {'ADR missing; pending CTO-owned output.'} elseif ($mode -eq 'first') {'PREVIOUS_DELIVERABLE_SENTINEL Architecture: CLI -> API -> store. Contracts: create/list. Risks: concurrent writes. Migration: preserve IDs.'} else {'CORRECTED_ADR_SENTINEL ADR: choose serialized writes and validate input. Architecture, interfaces, contracts, risks and migration are defined.'})
 verification = 'Deterministic evidence inspected'; decisions='Proposal only'; blockers=$(if($blocked){'Pending prerequisite'}else{'NONE'}); recommended_next='REVIEW'
 completion_check = @{ substantive_role_deliverable_produced = (-not $blocked); missing_required_outputs = @(); evidence='CTO role deliverable evaluated.' }
}
if ($blocked) {
 $payload.completion_check.missing_required_outputs = @('ADR')
 $external = $mode -eq 'external'
 $payload.execution_blocker = @{
  kind=$(if($external){'external_decision'}else{'owned_output_pending'})
  prerequisite=$(if($external){'Product owner must choose statutory data retention period.'}else{'CTO must draft ADR'})
  evidence=$(if($external){'WR-001 explicitly leaves retention undecided; CTO cannot invent legal requirements.'}else{'Review requests CTO ADR'})
  resolution_owner=$(if($external){'pm'}else{'cto'})
  why_role_cannot_resolve=$(if($external){'Product decision is reserved to PM and materially changes the data contract.'}else{'ADR still needs writing'})
  role_can_resolve=(-not $external)
 }
}
[IO.File]::WriteAllText($OutputPath,($payload | ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
[PSCustomObject]@{Provider='Ollama';Model=$Model}
'@
    return $root
}

try {
    $root = New-AnalysisFixture 'corrective'
    $runner = Join-Path $root 'scripts/run-agent-task.ps1'
    Write-FixtureFile (Join-Path $root 'fake-mode.txt') 'first'
    & $runner -Id AICO-002 -ProjectPath $root -Provider Ollama | Out-Null
    Assert-True ((Get-Status $root AICO-002) -eq 'REVIEW') 'Normal first analysis did not reach REVIEW.'
    $first = Get-Content (Join-Path $root 'fake-calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
    Assert-True (@($first).Count -eq 1) 'First valid analysis unexpectedly required repair.'
    Assert-True ($first.context -notmatch 'PREVIOUS_DELIVERABLE_SENTINEL') 'First attempt incorrectly received a corrective owner deliverable.'
    Assert-True ($first.context -notmatch 'BEGIN CORRECTIVE ANALYSIS EVIDENCE') 'First attempt received a corrective evidence envelope.'

    & (Join-Path $root 'scripts/review-task.ps1') -Id AICO-002 -Recommendation CHANGES_REQUIRED -Reviewer backend -Findings 'FINDINGS_SENTINEL: CTO must produce an ADR; no external dependency prevents drafting it.' -Verification 'Independent deterministic review' -ProjectPath $root | Out-Null
    Assert-True ((Get-Status $root AICO-002) -eq 'READY') 'Independent CHANGES_REQUIRED must return task to READY.'
    & (Join-Path $root 'scripts/advance-task.ps1') -Id AICO-002 -Status ACTIVE -Actor cto -Reason 'Authorized corrective retry' -TasksPath (Join-Path $root 'tasks') | Out-Null
    Write-FixtureFile (Join-Path $root 'fake-mode.txt') 'retry'
    & $runner -Id AICO-002 -ProjectPath $root -Provider Ollama | Out-Null
    Assert-True ((Get-Status $root AICO-002) -eq 'REVIEW') 'Owned-output BLOCKED leaked through intake instead of repairing to REVIEW.'
    $calls = @(Get-Content (Join-Path $root 'fake-calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    $retryCalls = @($calls | Where-Object mode -eq retry)
    Assert-True ($retryCalls.Count -eq 2) 'Expected one same-provider semantic repair.'
    Assert-True ($retryCalls[1].repair) 'Repair provider did not receive CORRECTION REQUIRED.'
    foreach ($call in $retryCalls) {
        Assert-True ($call.length -le 12000) 'Sent context exceeded effective Ollama budget.'
        foreach ($sentinel in @('TASK_SENTINEL','ORIGINAL_DISPATCH_SENTINEL','PREVIOUS_DELIVERABLE_SENTINEL','FINDINGS_SENTINEL','CHANGES_REQUIRED')) {
            Assert-True ($call.context.Contains($sentinel)) "Corrective sent context lost $sentinel."
        }
        foreach ($label in @('CANONICAL TASK','ORIGINAL OWNER ROLE CONTRACT','DISPATCH PACKET','PRIMARY AGENT REPORT','LATEST TASK RESULT','LATEST INDEPENDENT REVIEW','CORRECTIVE FINDINGS','END CORRECTIVE ANALYSIS EVIDENCE')) {
            Assert-True ($call.context.Contains($label)) "Corrective sent context lost required section $label."
        }
    }
    $report = Get-Content (Join-Path $root 'docs/engineering/agent-reports/AICO-002.md') -Raw
    Assert-True ($report.Contains('CORRECTED_ADR_SENTINEL')) 'Valid repair did not replace primary report.'
    $events = @(Get-Content (Join-Path $root '.codex/runtime/metrics/events.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True (@($events | Where-Object event_type -eq provider_semantic_retry).Count -gt 0) 'Semantic repair event was not recorded.'
    $boundedEvents = @($events | Where-Object { $_.context_input_chars -gt $_.context_chars -and $_.context_chars -eq 12000 })
    Assert-True ($boundedEvents.Count -gt 0) 'Provider metrics did not record constructed context greater than the effective sent budget.'

    # Exhausted repair during an actual corrective retry must preserve prior durable evidence.
    & (Join-Path $root 'scripts/review-task.ps1') -Id AICO-002 -Recommendation CHANGES_REQUIRED -Reviewer backend -Findings 'FINDINGS_SENTINEL: add ADR tradeoff detail.' -ProjectPath $root | Out-Null
    & (Join-Path $root 'scripts/advance-task.ps1') -Id AICO-002 -Status ACTIVE -Actor cto -Reason 'Authorized second corrective retry' -TasksPath (Join-Path $root 'tasks') | Out-Null
    $priorReportHash = (Get-FileHash (Join-Path $root 'docs/engineering/agent-reports/AICO-002.md')).Hash
    $priorResults = @(Get-ChildItem (Join-Path $root 'docs/engineering/results') -Filter 'AICO-002-result-*.md' | ForEach-Object { $_.Name + ':' + (Get-FileHash $_.FullName).Hash })
    Write-FixtureFile (Join-Path $root 'fake-mode.txt') 'invalid'
    $retryRejected = $false
    try { & $runner -Id AICO-002 -ProjectPath $root -Provider Ollama | Out-Null } catch { $retryRejected = $true }
    Assert-True $retryRejected 'Invalid corrective retry was accepted after failed semantic repair.'
    Assert-True ((Get-Status $root AICO-002) -eq 'ACTIVE') 'Rejected corrective retry mutated lifecycle.'
    Assert-True ((Get-FileHash (Join-Path $root 'docs/engineering/agent-reports/AICO-002.md')).Hash -eq $priorReportHash) 'Rejected corrective retry replaced the previous owner report.'
    $afterResults = @(Get-ChildItem (Join-Path $root 'docs/engineering/results') -Filter 'AICO-002-result-*.md' | ForEach-Object { $_.Name + ':' + (Get-FileHash $_.FullName).Hash })
    Assert-True (($priorResults -join '|') -eq ($afterResults -join '|')) 'Rejected corrective retry altered durable task results.'

    $externalRoot = New-AnalysisFixture 'external'
    Write-FixtureFile (Join-Path $externalRoot 'fake-mode.txt') 'external'
    & (Join-Path $externalRoot 'scripts/run-agent-task.ps1') -Id AICO-002 -ProjectPath $externalRoot -Provider Ollama | Out-Null
    Assert-True ((Get-Status $externalRoot AICO-002) -eq 'BLOCKED') 'Legitimate structured external decision was rejected.'
    Assert-True (@(Get-Content (Join-Path $externalRoot 'fake-calls.jsonl')).Count -eq 1) 'Legitimate BLOCKED unexpectedly required repair.'

    $invalidRoot = New-AnalysisFixture 'invalid'
    Write-FixtureFile (Join-Path $invalidRoot 'fake-mode.txt') 'invalid'
    $rejected = $false
    try { & (Join-Path $invalidRoot 'scripts/run-agent-task.ps1') -Id AICO-002 -ProjectPath $invalidRoot -Provider Ollama | Out-Null }
    catch { $rejected = $true }
    Assert-True $rejected 'Invalid BLOCKED was accepted after failed repair.'
    Assert-True ((Get-Status $invalidRoot AICO-002) -eq 'ACTIVE') 'Failed semantic repair mutated lifecycle.'
    Assert-True (-not (Test-Path (Join-Path $invalidRoot 'docs/engineering/agent-reports/AICO-002.md'))) 'Invalid BLOCKED wrote a primary report.'
    Assert-True (@(Get-ChildItem (Join-Path $invalidRoot 'docs/engineering/results') -Filter 'AICO-002-result-*.md' -ErrorAction SilentlyContinue).Count -eq 0) 'Invalid BLOCKED wrote a task result.'
    Write-Host 'PASS: corrective CTO retry repairs owned-output BLOCKED, preserves evidence under budget, accepts external BLOCKED and rejects exhausted invalid repair.' -ForegroundColor Green
}
finally {
    # Only remove this test-generated unique temporary root.
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resolvedTarget = [IO.Path]::GetFullPath($tempRoot)
    if (-not $resolvedTarget.StartsWith($resolvedTemp,[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside temporary directory.' }
    if (Test-Path $resolvedTarget) { Remove-Item -LiteralPath $resolvedTarget -Recurse -Force }
}
