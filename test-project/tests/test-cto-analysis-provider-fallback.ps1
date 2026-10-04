param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('aico-cto-fallback-' + [Guid]::NewGuid().ToString('N'))
$savedKeys = @{}
foreach ($name in @('OPENROUTER_API_KEY','GEMINI_API_KEY','DEEPSEEK_API_KEY','XAI_API_KEY')) { $savedKeys[$name] = [Environment]::GetEnvironmentVariable($name) }
function Write-Fixture([string]$Path,[string]$Content) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path,$Content,[Text.UTF8Encoding]::new($false))
}
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
try {
    $canonical = Get-Content (Join-Path $repoRoot '.codex/provider-config.json') -Raw | ConvertFrom-Json
    Assert ((@($canonical.analysis_auto_order_by_role.cto) -join ',') -eq 'Ollama,OpenRouter,Gemini,Codex,DeepSeek,Grok') 'Canonical CTO analysis fallback chain regressed.'
    Assert (-not $canonical.allow_paid_fallback) 'Canonical paid fallback policy was relaxed.'
    foreach ($name in $savedKeys.Keys) { [Environment]::SetEnvironmentVariable($name,'deterministic-fake-key') }
    foreach ($scenario in @('fallback','repair','invalid','unavailable','unconfigured-next','paid')) {
        $env:OPENROUTER_API_KEY = if($scenario -eq 'unconfigured-next'){''}else{'deterministic-fake-key'}
        $root = Join-Path $tempRoot $scenario
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Copy-Item (Join-Path $repoRoot 'scripts') $root -Recurse
        Copy-Item (Join-Path $repoRoot 'schemas') $root -Recurse
        Copy-Item (Join-Path $repoRoot '.codex') $root -Recurse
        Write-Fixture (Join-Path $root 'mode.txt') $scenario
        $chain = if ($scenario -eq 'paid') { @('DeepSeek','Grok','Gemini') } elseif($scenario -eq 'unconfigured-next'){@('Ollama','OpenRouter','Gemini')} else { @('Ollama','OpenRouter') }
        $config = @{auto_order=@('Ollama'); analysis_auto_order_by_role=@{cto=$chain};allow_paid_fallback=$false;models=@{Ollama='fake';OpenRouter='fake';Gemini='fake';DeepSeek='fake';Grok='fake'};analysis_context_max_chars=20000;ollama_context_max_chars=12000;provider_timeout_seconds=@{Ollama=30;OpenRouter=30;Gemini=30;DeepSeek=30;Grok=30}}
        Write-Fixture (Join-Path $root '.codex/provider-config.json') ($config | ConvertTo-Json -Depth 12)
        Write-Fixture (Join-Path $root '.codex/local-runtime-config.json') '{}'
        Write-Fixture (Join-Path $root 'scripts/local-runtime/resolve-local-runtime.ps1') @'
param([string]$ProjectPath,[string]$Role,[string]$Workload,[string]$ModelOverride)
$mode=(Get-Content (Join-Path $ProjectPath 'mode.txt') -Raw).Trim()
[PSCustomObject]@{Available=($mode -ne 'unavailable');Profile='LOCAL_GPU_12GB';Model='fake';NumCtx=16384;NumPredict=2048;ContextMaxChars=20000;GateContextMaxChars=12000;GateArtifactMaxChars=7000;Reason='Fake local availability'}
'@
        Write-Fixture (Join-Path $root 'tasks/AICO-002.md') @'
# AICO-002 - CTO analysis fixture
ID: AICO-002
Status: ACTIVE
Owner: cto
Priority: P1
Work kind: PLANNING
Workflow profile: standard

## Objective

Produce architecture and ADR.

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

- Authorized fake-provider test.

---

## Notes

-
'@
        Write-Fixture (Join-Path $root 'docs/engineering/dispatch/AICO-002.md') "Task: AICO-002`nOwner: cto`nArchitecture analysis authorized."
        foreach ($adapter in @('ollama','openrouter','gemini','deepseek','xai')) {
            $providerName = @{ollama='Ollama';openrouter='OpenRouter';gemini='Gemini';deepseek='DeepSeek';xai='Grok'}[$adapter]
            $script = @'
param([string]$Prompt,[string]$Context,[string]$SchemaPath,[string]$OutputPath,[string]$Model,[int]$NumCtx,[int]$NumPredict,[int]$TimeoutSeconds)
$name='PROVIDER_NAME'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mode=(Get-Content (Join-Path $root 'mode.txt') -Raw).Trim()
$repair=$Prompt -match 'CORRECTION REQUIRED'
if($name -ne 'Ollama' -and $mode -eq 'fallback') {
 if(Test-Path $OutputPath){throw 'Invalid A output was not discarded before provider B'}
 if(Test-Path (Join-Path $root 'docs/engineering/agent-reports/AICO-002.md')){throw 'Invalid A report leaked before provider B'}
}
Add-Content (Join-Path $root 'calls.jsonl') (@{provider=$name;repair=$repair}|ConvertTo-Json -Compress)
$invalid=($mode -eq 'invalid') -or ($name -eq 'Ollama' -and -not($mode -eq 'repair' -and $repair))
$payload=@{outcome='COMPLETED';summary='Validated CTO analysis';report_markdown='VALID_DELIVERABLE Architecture CLI/API/store, ADR serialized writes, contract IDs, migration and concurrency risks.';verification='Fake deterministic evidence';decisions='Proposal';blockers='NONE';recommended_next='REVIEW';completion_check=@{substantive_role_deliverable_produced=$true;missing_required_outputs=@();evidence='Architecture and ADR produced'}}
if($invalid){
 $payload.report_markdown='INVALID_A_DELIVERABLE'
 $payload.execution_blocker=@{kind='external_decision';prerequisite='PM decision';evidence='Decision pending';resolution_owner='pm';why_role_cannot_resolve='PM owns decision';role_can_resolve=$false}
}
[IO.File]::WriteAllText($OutputPath,($payload|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
[PSCustomObject]@{Provider=$name;Model='fake'}
'@
            Write-Fixture (Join-Path $root "scripts/providers/invoke-$adapter.ps1") ($script.Replace('PROVIDER_NAME',$providerName))
        }
        $failed=$false
        try { & (Join-Path $root 'scripts/run-agent-task.ps1') -Id AICO-002 -ProjectPath $root -Provider Auto | Out-Null } catch { $failed=$true; if($scenario -ne 'invalid'){throw} }
        $calls=@(Get-Content (Join-Path $root 'calls.jsonl') | ForEach-Object {$_|ConvertFrom-Json})
        $task=Get-Content (Join-Path $root 'tasks/AICO-002.md') -Raw
        if($scenario -eq 'invalid') {
            Assert $failed 'Exhausted invalid provider chain was accepted.'
            Assert ($task -match '(?m)^Status: ACTIVE') 'Invalid chain mutated lifecycle.'
            Assert (-not(Test-Path (Join-Path $root 'docs/engineering/agent-reports/AICO-002.md'))) 'Invalid chain wrote a primary report.'
            Assert (-not(Test-Path (Join-Path $root '.codex/runtime/AICO-002-result.json'))) 'Invalid chain retained rejected structured output.'
            Assert (@(Get-ChildItem (Join-Path $root 'docs/engineering/results') -Filter 'AICO-002-result-*.md' -ErrorAction SilentlyContinue).Count -eq 0) 'Invalid chain wrote results.'
            Assert (($calls.provider -join ',') -eq 'Ollama,Ollama,OpenRouter,OpenRouter') 'Invalid chain did not exhaust same-provider repair before fallback.'
        } else {
            Assert ($task -match '(?m)^Status: REVIEW') "$scenario did not reach REVIEW."
            $report=Get-Content (Join-Path $root 'docs/engineering/agent-reports/AICO-002.md') -Raw
            Assert ($report.Contains('VALID_DELIVERABLE') -and -not $report.Contains('INVALID_A_DELIVERABLE')) 'Invalid provider deliverable leaked into intake.'
            $expected=@{fallback='Ollama,Ollama,OpenRouter';repair='Ollama,Ollama';unavailable='OpenRouter';'unconfigured-next'='Ollama,Ollama,Gemini';paid='Gemini'}[$scenario]
            Assert (($calls.provider -join ',') -eq $expected) "$scenario provider invocation order was incorrect."
            if($scenario -in @('fallback','repair')) { Assert ([bool]$calls[1].repair) "$scenario repair did not receive corrective feedback." }
        }
        $events=@(Get-Content (Join-Path $root '.codex/runtime/metrics/events.jsonl') | ForEach-Object {$_|ConvertFrom-Json})
        if($scenario -in @('fallback','repair','invalid','unconfigured-next')) { Assert (@($events|Where-Object event_type -eq provider_semantic_retry).Count -gt 0) 'Missing semantic retry metric.' }
        if($scenario -in @('fallback','invalid','unconfigured-next')) {
            $failure=@($events | Where-Object { $_.event_type -eq 'provider_attempt_finished' -and $_.provider -eq 'Ollama' -and -not $_.success -and $_.error_category -eq 'contract' })
            Assert ($failure.Count -eq 1) 'Exhausted Ollama semantic repair must record one failed candidate.'
            $repairs=@($events | Where-Object { $_.event_type -eq 'provider_semantic_retry' -and $_.provider -eq 'Ollama' })
            Assert ($repairs.Count -eq 1) 'Ollama must receive exactly one semantic repair.'
        }
        Write-Host "PASS: CTO Auto analysis $scenario" -ForegroundColor Green
    }
    Write-Host 'PASS: 6 deterministic CTO fallback scenarios and canonical role chain.' -ForegroundColor Green
}
finally {
    foreach($name in $savedKeys.Keys){[Environment]::SetEnvironmentVariable($name,$savedKeys[$name])}
    $resolved=[IO.Path]::GetFullPath($tempRoot)
    Assert ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) 'Unsafe test cleanup path.'
    if(Test-Path $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
