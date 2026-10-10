param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('aico-single-attempt-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
$keys = @('OPENROUTER_API_KEY','GEMINI_API_KEY','DEEPSEEK_API_KEY','XAI_API_KEY')
$saved = @{}
class SingleAttemptMockHttpException : System.Exception {
    [object]$Response
    SingleAttemptMockHttpException([string]$message,[int]$status) : base($message) {$this.Response=[pscustomobject]@{StatusCode=$status}}
}
$global:AicoSingleAttemptTestSpy = @{}; $global:AicoSingleAttemptTestSpy.calls = 0; $global:AicoSingleAttemptTestSpy.mode = 'valid'; $global:AicoSingleAttemptTestSpy.assertions = 0
function Assert($condition, $message) { if (-not $condition) { throw $message }; $global:AicoSingleAttemptTestSpy.assertions++ }
function Invoke-RestMethod {
    param($Method,$Uri,$Headers,$ContentType,[byte[]]$Body,$TimeoutSec,$MaximumRedirection,$MaximumRetryCount)
    $global:AicoSingleAttemptTestSpy.calls++
    $payload = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
    $global:AicoSingleAttemptTestSpy.lastPayload=$payload
    if($global:AicoSingleAttemptTestSpy.mode -eq 'partial'){[IO.File]::WriteAllText($global:AicoSingleAttemptTestSpy.currentOutput,'{"value":');throw 'timeout after partial adapter output'}
    if ($global:AicoSingleAttemptTestSpy.mode -match '^error') {
        if($global:AicoSingleAttemptTestSpy.mode -eq 'error-timeout'){throw 'timeout SINGLE-ATTEMPT-SECRET'}
        $status=if($global:AicoSingleAttemptTestSpy.mode -eq 'error-auth'){401}else{[int]$global:AicoSingleAttemptTestSpy.mode.Substring(6)}
        throw [SingleAttemptMockHttpException]::new('HTTP failure SINGLE-ATTEMPT-SECRET',$status)
    }
    if ($global:AicoSingleAttemptTestSpy.mode -eq 'transient-first' -and $global:AicoSingleAttemptTestSpy.calls -eq 1) { throw 'timeout' }
    $content = '{"value":"ok"}'
    if($global:AicoSingleAttemptTestSpy.mode -match '^grounded'){
        $promptText=[string]$payload.messages[0].content
        $capture=[regex]::Match($promptText,'(?m)^\{"contract_version":"review-grounding-v1"[^\r\n]*')
        if(-not $capture.Success){throw 'actual grounding manifest missing from transport payload'}
        $manifest=$capture.Value|ConvertFrom-Json
        $primary=@($manifest.artifacts)[0]
        $lineCapture=[regex]::Match($promptText,'(?ms)^Artifact: '+[regex]::Escape([string]$primary.artifact_id)+';[^\r\n]*\r?\n1\|([^\r\n]+)')
        if(-not $lineCapture.Success){throw 'actual primary source line missing'}
        $quote=$lineCapture.Groups[1].Value
        $rows=@(foreach($obligation in $manifest.obligations){[ordered]@{required_output_id=$obligation.required_output_id;status='SATISFIED';rationale='Isolated fixture primary report records this scoped deliverable.';evidence=@([ordered]@{artifact_id=$primary.artifact_id;start_line=1;end_line=1;byte_start=0;byte_end=[Text.Encoding]::UTF8.GetByteCount($quote);excerpt=$quote})}})
        $rows[0].status='UNSATISFIED';$rows[0].evidence=@();$rows[0].rationale='Fixture requires a corrective architecture detail.'
        $judgment=[ordered]@{contract_version='review-grounding-v1';snapshot_id=$manifest.snapshot_id;recommendation='CHANGES_REQUIRED';findings='Fixture requires a corrective architecture detail.';verification='Assessed actual frozen primary source.';missing_required_outputs=@('Fixture requires a corrective architecture detail.');deliverable_defects=@();assessments=$rows}
        if($global:AicoSingleAttemptTestSpy.mode -eq 'grounded-schema'){$judgment.Remove('contract_version')}
        if($global:AicoSingleAttemptTestSpy.mode -eq 'grounded-semantic'){$judgment.assessments[1].evidence[0].artifact_id='secondary-result'}
        $content=$judgment|ConvertTo-Json -Depth 40 -Compress
        if($global:AicoSingleAttemptTestSpy.mode -eq 'grounded-json'){$content='{broken'}
        $global:AicoSingleAttemptTestSpy.obligations=@($manifest.obligations).Count
    }
    if ($global:AicoSingleAttemptTestSpy.mode -eq 'invalid-json') { $content = '{broken' }
    if ($global:AicoSingleAttemptTestSpy.mode -eq 'invalid-schema') { $content = '{"wrong":true}' }
    $finish = if ($global:AicoSingleAttemptTestSpy.mode -eq 'length') { 'length' } elseif($global:AicoSingleAttemptTestSpy.mode -eq 'missing-finish') {$null} else { 'stop' }
    return [pscustomobject]@{
        model=$payload.model; done=$true; done_reason=$finish; prompt_eval_count=13; eval_count=21
        message=[pscustomobject]@{content=$content}
        usage=$(if($global:AicoSingleAttemptTestSpy.mode -eq 'unknown-usage'){$null}else{[pscustomobject]@{prompt_tokens=13;completion_tokens=21;total_tokens=34;completion_tokens_details=[pscustomobject]@{reasoning_tokens=7}}})
        usageMetadata=[pscustomobject]@{promptTokenCount=13;candidatesTokenCount=21;totalTokenCount=34;thoughtsTokenCount=7}
        choices=@([pscustomobject]@{finish_reason=$finish;message=[pscustomobject]@{content=$content;refusal=$(if($global:AicoSingleAttemptTestSpy.mode -eq 'refusal'){'SINGLE-ATTEMPT-SECRET refusal prose'}else{$null})}})
        candidates=@([pscustomobject]@{finishReason=$(if($finish -eq 'length'){'MAX_TOKENS'}else{'STOP'});content=[pscustomobject]@{parts=@([pscustomobject]@{text=$content})}})
    }
}
function Invoke-Case($name,$overrides,$expectedCalls,$success) {
    $global:AicoSingleAttemptTestSpy.calls=0
    $project=Join-Path $scratch ([guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($project) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $project '.codex')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $project '.codex/provider-config.json'),'{"auto_order":["OpenRouter","Gemini","DeepSeek"],"allow_paid_fallback":true}')
    $output=Join-Path $project 'result.json'
    $global:AicoSingleAttemptTestSpy.currentOutput=$output
    $args=@{Provider='OpenRouter';ProjectPath=$project;Prompt='fixture';Context='context';SchemaPath=$schema;OutputPath=$output;Model='fixture/model:free';ProviderEndpoint='fixture-endpoint';SingleAttempt=$true}
    foreach($key in $overrides.Keys){if($null -eq $overrides[$key]){$args.Remove($key)}else{$args[$key]=$overrides[$key]}}
    $accepted=$true;$message=''
    try { & (Join-Path $repo 'scripts/provider-router.ps1') @args | Out-Null } catch {$accepted=$false;$message=$_.Exception.Message}
    Assert ($accepted -eq $success) "$name unexpected acceptance: $message"
    Assert ($global:AicoSingleAttemptTestSpy.calls -eq $expectedCalls) "$name transport count $($global:AicoSingleAttemptTestSpy.calls) expected $expectedCalls"
    if(-not $accepted){Assert (-not (Test-Path $output)) "$name left consumable output"}
    $records=@(Get-ChildItem (Join-Path $project '.codex/runtime/single-attempt-executions') -Filter '*.json' -ErrorAction SilentlyContinue)
    if($args.SingleAttempt){Assert ($records.Count -eq 1) "$name missing unique execution record"}
    foreach($record in $records){
        $raw=[IO.File]::ReadAllText($record.FullName)
        Assert ($raw -notmatch 'SINGLE-ATTEMPT-SECRET') "$name evidence leaked key"
        $evidence=$raw|ConvertFrom-Json
        Assert ($evidence.attempts_started -eq $expectedCalls) "$name evidence count"
        $categories=@{'error-timeout'='timeout';'error-429'='rate_limit';'error-500'='transport';'error-auth'='authentication';'length'='truncated';'missing-finish'='incomplete_response';'refusal'='provider_rejected'}
        if($categories.ContainsKey($global:AicoSingleAttemptTestSpy.mode)){Assert ($evidence.error_category -eq $categories[$global:AicoSingleAttemptTestSpy.mode]) "$name incorrect error category: $($evidence.error_category)"}
        if($global:AicoSingleAttemptTestSpy.mode -eq 'unknown-usage'){Assert ($null -eq $evidence.prompt_tokens -and $null -eq $evidence.completion_tokens -and $null -eq $evidence.reasoning_tokens) 'unknown usage fabricated as zero'}
        if($global:AicoSingleAttemptTestSpy.mode -eq 'missing-finish'){Assert ($null -eq $evidence.finish_reason) 'missing finish reason fabricated'}
        if($expectedCalls -eq 1 -and $global:AicoSingleAttemptTestSpy.mode -notmatch '^error|^partial|^unknown|^missing'){
            Assert ($null -ne $evidence.finish_reason) "$name finish metadata absent"
            Assert ($evidence.prompt_tokens -eq 13) "$name prompt metadata absent"
            Assert ($evidence.completion_tokens -eq 21) "$name completion metadata absent"
            Assert ($evidence.reasoning_tokens -eq 7) "$name reasoning metadata absent"
        }
    }
    Assert ($message -notmatch 'SINGLE-ATTEMPT-SECRET') "$name exception leaked key"
}
try {
    foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key);[Environment]::SetEnvironmentVariable($key,'SINGLE-ATTEMPT-SECRET')}
    $schema=Join-Path $scratch 'schema.json'
    [IO.File]::WriteAllText($schema,'{"type":"object","properties":{"value":{"type":"string"}},"required":["value"],"additionalProperties":false}')
    $semantic=Join-Path $scratch 'reject-semantic.ps1'
    [IO.File]::WriteAllText($semantic,'param($JsonPath) throw "semantic fixture rejection"')
    Invoke-Case 'valid single' @{} 1 $true
    Assert ($global:AicoSingleAttemptTestSpy.lastPayload.provider.allow_fallbacks -eq $false) 'OpenRouter remote fallback enabled'
    Assert (@($global:AicoSingleAttemptTestSpy.lastPayload.provider.only).Count -eq 1) 'OpenRouter endpoint not pinned'
    Invoke-Case 'Auto rejected' @{Provider='Auto'} 0 $false
    Invoke-Case 'missing model' @{Model=$null} 0 $false
    Invoke-Case 'dynamic free router' @{Model='openrouter/free'} 0 $false
    Invoke-Case 'missing endpoint' @{ProviderEndpoint=$null} 0 $false
    Invoke-Case 'credential as model rejected' @{Model='SINGLE-ATTEMPT-SECRET'} 0 $false
    Invoke-Case 'credential as endpoint rejected' @{ProviderEndpoint='SINGLE-ATTEMPT-SECRET'} 0 $false
    Invoke-Case 'Codex unsupported' @{Provider='Codex';ProviderEndpoint=$null} 0 $false
    $env:OPENROUTER_API_KEY=''
    Invoke-Case 'unavailable credentials' @{} 0 $false
    $env:OPENROUTER_API_KEY='SINGLE-ATTEMPT-SECRET'
    foreach($mode in @('error-timeout','error-429','error-500','error-auth','invalid-json','invalid-schema','length','partial','missing-finish','refusal')){$global:AicoSingleAttemptTestSpy.mode=$mode;Invoke-Case $mode @{} 1 $false}
    $global:AicoSingleAttemptTestSpy.mode='valid'
    Invoke-Case 'semantic rejection no repair' @{SemanticValidatorPath=$semantic} 1 $false
    $global:AicoSingleAttemptTestSpy.mode='unknown-usage'
    Invoke-Case 'usage unavailable remains null' @{} 1 $true
    $global:AicoSingleAttemptTestSpy.mode='transient-first'
    Invoke-Case 'default transient retry retained' @{SingleAttempt=$null;ProviderEndpoint=$null} 2 $true
    $repair=Join-Path $scratch 'repair-semantic.ps1'
    [IO.File]::WriteAllText($repair,'param($JsonPath) $marker=$JsonPath+".semanticseen"; if(-not(Test-Path $marker)){[IO.File]::WriteAllText($marker,"seen");throw "first semantic rejection"}')
    $global:AicoSingleAttemptTestSpy.mode='valid'
    Invoke-Case 'default semantic repair retained' @{SingleAttempt=$null;ProviderEndpoint=$null;SemanticValidatorPath=$repair} 2 $true
    $global:AicoSingleAttemptTestSpy.mode='valid'
    foreach($provider in @('Gemini','DeepSeek','Grok')){Invoke-Case "$provider real adapter mocked transport" @{Provider=$provider;ProviderEndpoint=$null} 1 $true}
    . (Join-Path $repo 'scripts/single-attempt-execution.ps1')
    $global:AicoSingleAttemptTestSpy.calls=0
    $handle=New-SingleAttemptExecution -ProjectPath $scratch -Provider Ollama -Model 'fixture-local'
    Assert-SingleAttemptConfiguration -Context $handle -Provider Ollama -Model fixture-local
    & (Join-Path $repo 'scripts/providers/invoke-ollama.ps1') -Prompt fixture -Context context -SchemaPath $schema -OutputPath (Join-Path $scratch 'ollama.json') -Model fixture-local -SingleAttempt -SingleAttemptContext $handle | Out-Null
    Assert ($global:AicoSingleAttemptTestSpy.calls -eq 1) 'Ollama one transport'
    $forged=[pscustomobject]@{Id=$handle.Id}
    $failed=$false
    try {Start-SingleAttemptProviderCall -Context $forged -Provider Ollama -Model fixture-local}catch{$failed=$true}
    Assert $failed 'forged context accepted'
    $failed=$false
    try {Start-SingleAttemptProviderCall -Context $handle -Provider Ollama -Model fixture-local}catch{$failed=$true}
    Assert $failed 'duplicate transport authorization accepted'
    $endpointHandle=New-SingleAttemptExecution -ProjectPath $scratch -Provider OpenRouter -Model 'fixture/model:free'
    Assert-SingleAttemptConfiguration -Context $endpointHandle -Provider OpenRouter -Model 'fixture/model:free' -ProviderEndpoint fixture-endpoint
    $failed=$false
    try{Assert-SingleAttemptConfiguration -Context $endpointHandle -Provider OpenRouter -Model 'fixture/model:free' -ProviderEndpoint alternate-endpoint}catch{$failed=$true}
    Assert $failed 'configured endpoint could be changed'
    $global:AicoSingleAttemptTestSpy.calls=0
    $badBudgetHandle=New-SingleAttemptExecution -ProjectPath $scratch -Provider Ollama -Model fixture-local
    $failed=$false
    try{& (Join-Path $repo 'scripts/providers/invoke-ollama.ps1') -Prompt fixture -Context context -SchemaPath $schema -OutputPath (Join-Path $scratch 'bad-budget.json') -Model fixture-local -NumPredict 0 -SingleAttempt -SingleAttemptContext $badBudgetHandle|Out-Null}catch{$failed=$true}
    Assert ($failed -and $global:AicoSingleAttemptTestSpy.calls -eq 0) 'invalid Ollama output budget must reject before transport'
    . (Join-Path $repo 'test-project/helpers/grounded-review-fixture.ps1')
    . (Join-Path $repo 'scripts/task-execution-lock.ps1')
    foreach($gateMode in @('grounded-json','grounded-schema','grounded-semantic','grounded-valid','grounded-budget')){
        $gateRoot=Join-Path $scratch ([guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($gateRoot)|Out-Null
        foreach($directory in @('scripts','schemas','.codex')){Copy-Item (Join-Path $repo $directory) $gateRoot -Recurse}
        $fixture=New-GroundedRouterFixture -Root $gateRoot
        Exit-TaskExecutionLock -Lock $fixture.Lease
        $taskPath=Join-Path $gateRoot 'tasks/AICO-001.md'
        $taskText=[IO.File]::ReadAllText($taskPath).Replace("## Acceptance Criteria`n","## Acceptance Criteria`n`n")
        $taskText+="`n- [ ] The component boundaries are recorded.`n- [ ] The migration risks are recorded.`n- [ ] The open questions are recorded.`n`n## Objective`n`nReview the isolated architecture fixture."
        [IO.File]::WriteAllText($taskPath,$taskText,(New-Object Text.UTF8Encoding($false)))
        $before=(Get-FileHash $taskPath).Hash
        $budget=if($gateMode -eq 'grounded-budget'){10}else{180000}
        [IO.File]::WriteAllText((Join-Path $gateRoot '.codex/provider-config.json'),('{"gate_context_max_chars":'+$budget+',"allow_paid_fallback":true,"gate_auto_order":["OpenRouter","Gemini","DeepSeek"]}'))
        $global:AicoSingleAttemptTestSpy.mode=$gateMode;$global:AicoSingleAttemptTestSpy.calls=0
        $ok=$true;$reason=''
        try{& (Join-Path $gateRoot 'scripts/run-gate-agent.ps1') -ProjectPath $gateRoot -Id AICO-001 -Gate Review -Provider OpenRouter -Model 'fixture/model:free' -ProviderEndpoint fixture-endpoint -SingleAttempt|Out-Null}catch{$ok=$false;$reason=$_.Exception.Message}
        $valid=$gateMode -eq 'grounded-valid'
        Assert ($ok -eq $valid) "$gateMode unexpected gate acceptance: $reason"
        Assert ($global:AicoSingleAttemptTestSpy.calls -eq $(if($gateMode -eq 'grounded-budget'){0}else{1})) "$gateMode transport count"
        $sidecars=@(Get-ChildItem (Join-Path $gateRoot 'docs/engineering/reviews') -Filter '*.grounding.json' -ErrorAction SilentlyContinue)
        Assert ($sidecars.Count -eq $(if($valid){1}else{0})) "$gateMode canonical publication count"
        if($valid){Assert ([IO.File]::ReadAllText($taskPath) -match 'Status: READY') 'valid corrective Review lifecycle';Assert ($global:AicoSingleAttemptTestSpy.obligations -eq 11) 'all11obligations frozen';$raw=[IO.File]::ReadAllText($sidecars[0].FullName);Assert ($raw -match 'byte_start') 'citation span retained in canonical sidecar'}else{Assert ((Get-FileHash $taskPath).Hash -eq $before) "$gateMode REVIEW task bytes changed";Assert (-not(Test-Path (Join-Path $gateRoot '.codex/runtime/AICO-001-review-gate.json'))) "$gateMode rejected gate output survives"}
    }
    foreach($contention in @('task-lease','maintenance-lease','missing-task')){
        $guardRoot=Join-Path $scratch ([guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($guardRoot)|Out-Null
        foreach($directory in @('scripts','schemas','.codex')){Copy-Item (Join-Path $repo $directory) $guardRoot -Recurse}
        $held=New-GroundedRouterFixture -Root $guardRoot
        $maintenance=$null
        if($contention -ne 'task-lease'){Exit-TaskExecutionLock -Lock $held.Lease;$held=$null}
        if($contention -eq 'maintenance-lease'){$maintenance=Enter-ProjectExecutionLease -ProjectPath $guardRoot -Mode Maintenance;Assert-ProjectExecutionLease -ProjectPath $guardRoot -Mode Maintenance -Lease $maintenance}
        if($contention -eq 'missing-task'){Remove-Item -LiteralPath (Join-Path $guardRoot 'tasks/AICO-001.md') -Force}
        $cache=Join-Path $guardRoot '.codex/runtime/AICO-001-review-gate.json'
        [IO.File]::WriteAllText($cache,'CONCURRENT_CANONICAL_OUTPUT_SENTINEL')
        $cacheHash=(Get-FileHash $cache).Hash
        $recordDir=Join-Path $guardRoot '.codex/runtime/single-attempt-executions'
        $recordsBefore=@(Get-ChildItem $recordDir -File -ErrorAction SilentlyContinue).Count
        $global:AicoSingleAttemptTestSpy.calls=0;$failed=$false;$reason=''
        try{& (Join-Path $guardRoot 'scripts/run-gate-agent.ps1') -ProjectPath $guardRoot -Id AICO-001 -Gate Review -Provider OpenRouter -Model 'fixture/model:free' -ProviderEndpoint fixture-endpoint -SingleAttempt|Out-Null}catch{$failed=$true;$reason=$_.Exception.Message}finally{if($null -ne $held){Exit-TaskExecutionLock -Lock $held.Lease};if($null -ne $maintenance){Exit-ProjectExecutionLease -Lease $maintenance}}
        Assert $failed "$contention did not reject"
        Assert ($global:AicoSingleAttemptTestSpy.calls -eq 0) "$contention made a provider call"
        Assert ((Get-FileHash $cache).Hash -eq $cacheHash) "$contention deleted another execution's canonical cache"
        Assert (@(Get-ChildItem $recordDir -File -ErrorAction SilentlyContinue).Count -eq $recordsBefore) "$contention wrote an execution record without a lease"
        Assert ($reason -match 'NOT_CREATED|no execution record was created') "$contention claimed a nonexistent evidence record: $reason"
    }
    Write-Host "PASS: single-attempt execution ($($global:AicoSingleAttemptTestSpy.assertions) assertions)" -ForegroundColor Green
} finally {
    foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$saved[$key])}
    Remove-Variable -Name AicoSingleAttemptTestSpy -Scope Global -ErrorAction SilentlyContinue
    # Scratch retained for inspectable deterministic evidence; never an acceptance project.
}
