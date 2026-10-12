param()
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('aico-gemini-budget-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch)|Out-Null
$saved=[Environment]::GetEnvironmentVariable('GEMINI_API_KEY')
$eiSaved=[Environment]::GetEnvironmentVariable('AICO_ERROR_INTELLIGENCE_ENABLED')
$global:GeminiBudgetSpy=@{calls=0;mode='valid';assertions=0}
class GeminiBudgetHttpException : System.Exception {
 [object]$Response
 GeminiBudgetHttpException([int]$status):base('simulated HTTP failure'){$this.Response=[pscustomobject]@{StatusCode=$status}}
}
function Assert($condition,$message){if(-not $condition){throw $message};$global:GeminiBudgetSpy.assertions++}
function Invoke-RestMethod {
 param($Method,$Uri,$Headers,$ContentType,[byte[]]$Body,$TimeoutSec,$MaximumRedirection,$MaximumRetryCount)
 $global:GeminiBudgetSpy.calls++
 $p=[Text.Encoding]::UTF8.GetString($Body)|ConvertFrom-Json
 $global:GeminiBudgetSpy.payload=$p
 $global:GeminiBudgetSpy.redirect=$MaximumRedirection;$global:GeminiBudgetSpy.retry=$MaximumRetryCount
 $mode=$global:GeminiBudgetSpy.mode
 if($mode -eq 'timeout'){throw [TimeoutException]::new('simulated timeout')}
 if($mode -in @('429','503')){throw [GeminiBudgetHttpException]::new([int]$mode)}
 $content='{"value":"ok"}'
 if($mode -eq 'invalid-json'){$content='{bad'}
 if($mode -eq 'partial-json'){$content='{"value":'}
 if($mode -match '^grounded'){
  $prompt=[string]$p.contents[0].parts[0].text
  $capture=[regex]::Match($prompt,'(?m)^\{"contract_version":"review-grounding-v1"[^\r\n]*')
  if(-not $capture.Success){throw 'No grounding manifest in Gemini request'}
  $manifest=$capture.Value|ConvertFrom-Json
  $primary=@($manifest.artifacts)[0]
  $line=[regex]::Match($prompt,'(?ms)^Artifact: '+[regex]::Escape([string]$primary.artifact_id)+';[^\r\n]*\r?\n1\|([^\r\n]+)')
  if(-not $line.Success){throw 'No primary citation text in Gemini request'}
  $quote=$line.Groups[1].Value
  $rows=@(foreach($o in $manifest.obligations){[ordered]@{required_output_id=$o.required_output_id;status='SATISFIED';rationale='Scoped synthetic primary source records this required deliverable.';evidence=@([ordered]@{artifact_id=$primary.artifact_id;start_line=1;end_line=1;byte_start=0;byte_end=[Text.Encoding]::UTF8.GetByteCount($quote);excerpt=$quote})}})
  $global:GeminiBudgetSpy.obligations=$rows.Count
  $rows[0].status='UNSATISFIED';$rows[0].evidence=@();$rows[0].rationale='A corrective architecture detail is missing.'
  if($mode -eq 'grounded-missing-obligation'){$rows=@($rows|Select-Object -Skip 1)}
  if($mode -eq 'grounded-bad-citation'){$rows[1].evidence[0].excerpt='fabricated citation'}
  $content=[ordered]@{contract_version='review-grounding-v1';snapshot_id=$manifest.snapshot_id;recommendation='CHANGES_REQUIRED';findings='A corrective architecture detail is missing.';verification='Assessed immutable primary source.';missing_required_outputs=@('A corrective architecture detail is missing.');deliverable_defects=@();assessments=$rows}|ConvertTo-Json -Depth 40 -Compress
 }
 $model='gemini-3.8-flash'
 if($mode -eq 'model-missing'){$model=$null}
 if($mode -eq 'model-blank'){$model=''}
 if($mode -eq 'model-whitespace'){$model=' gemini-3.8-flash '}
 if($mode -eq 'model-other'){$model='gemini-3.5-flash'}
 if($mode -eq 'model-prefix'){$model='gemini-3.8-flash-preview-001'}
 [pscustomobject]@{modelVersion=$model;usageMetadata=[pscustomobject]@{promptTokenCount=13;candidatesTokenCount=21;totalTokenCount=41;thoughtsTokenCount=7};candidates=@([pscustomobject]@{finishReason=$(if($mode -eq 'max-tokens'){'MAX_TOKENS'}else{'STOP'});content=[pscustomobject]@{parts=@([pscustomobject]@{text=$content})}})}
}
function Case($name,$override,$calls,$success,$preserve=$false){
 $root=Join-Path $scratch ([guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($root)|Out-Null
 $output=Join-Path $root 'result.json';[IO.File]::WriteAllText($output,'EXISTING OUTPUT SENTINEL');$before=(Get-FileHash $output).Hash
 $args=@{ProjectPath=$root;Provider='Gemini';Model='gemini-3.8-flash';SingleAttempt=$true;GeminiMaxOutputTokens=32768;GeminiThinkingLevel='low';Prompt='fixture';Context='context';SchemaPath=$schema;OutputPath=$output}
 foreach($key in $override.Keys){if($null -eq $override[$key]){$args.Remove($key)}else{$args[$key]=$override[$key]}}
 $global:GeminiBudgetSpy.calls=0;$ok=$true;$reason=''
 try{& (Join-Path $repo 'scripts/provider-router.ps1') @args|Out-Null}catch{$ok=$false;$reason=$_.Exception.Message}
 Assert ($ok -eq $success) "$name acceptance mismatch: $reason"
 Assert ($global:GeminiBudgetSpy.calls -eq $calls) "$name calls mismatch"
 if($preserve){Assert ((Test-Path $output) -and (Get-FileHash $output).Hash -eq $before) "$name changed existing output"}
 elseif(-not $success){Assert (-not(Test-Path $output)) "$name consumable rejected output remains"}
 $records=@(Get-ChildItem (Join-Path $root '.codex/runtime/single-attempt-executions') -Filter '*.json' -ErrorAction SilentlyContinue)
 foreach($r in $records){$record=Get-Content $r.FullName -Raw|ConvertFrom-Json;Assert ($record.attempts_started -eq $calls) "$name attempts evidence";if($calls -eq 1 -and $args.ContainsKey('GeminiMaxOutputTokens')){Assert ($record.thinking_level -ceq 'low') "$name thinking metadata";Assert ($record.prompt_tokens -eq 13 -or $global:GeminiBudgetSpy.mode -in @('timeout','429','503')) "$name prompt usage metadata"};if($calls -eq 1){Assert ($record.output_limit -eq 32768 -or ($override.ContainsKey('GeminiMaxOutputTokens') -and $null -eq $override.GeminiMaxOutputTokens -and $record.output_limit -eq 12000)) "$name output limit metadata"}}
 if($success -and $args.ContainsKey('GeminiMaxOutputTokens')){Assert ($global:GeminiBudgetSpy.payload.generationConfig.maxOutputTokens -eq 32768) "$name budget payload";Assert ($global:GeminiBudgetSpy.payload.generationConfig.thinkingConfig.thinkingLevel -ceq 'low') "$name thinking payload"}
}
try{
 $env:GEMINI_API_KEY='DETERMINISTIC-MOCK-KEY'
 $env:AICO_ERROR_INTELLIGENCE_ENABLED='0'
 $schema=Join-Path $scratch 'schema.json';[IO.File]::WriteAllText($schema,'{"type":"object","properties":{"value":{"type":"string"}},"required":["value"],"additionalProperties":false}')
 Case 'explicit 32768 low' @{} 1 $true
 Assert ($global:GeminiBudgetSpy.redirect -eq 0) 'redirects enabled'
 if($PSVersionTable.PSVersion.Major -ge 7){Assert ($global:GeminiBudgetSpy.retry -eq 0) 'HTTP retries enabled'}
 Case 'legacy default' @{GeminiMaxOutputTokens=$null;GeminiThinkingLevel=$null} 1 $true
 Assert ($global:GeminiBudgetSpy.payload.generationConfig.maxOutputTokens -eq 12000) 'legacy budget changed'
 Assert ($null -eq $global:GeminiBudgetSpy.payload.generationConfig.thinkingConfig) 'legacy thinking changed'
 foreach($invalid in @(@{Provider='Auto'},@{Provider='OpenRouter'},@{SingleAttempt=$null},@{Model='gemini-3.5-flash'},@{Model='gemini-3.8-flash-preview'},@{GeminiMaxOutputTokens=0},@{GeminiMaxOutputTokens=65537},@{GeminiThinkingLevel='medium'},@{GeminiThinkingLevel='high'},@{GeminiThinkingLevel=''},@{GeminiMaxOutputTokens=$null},@{GeminiThinkingLevel=$null})) {Case 'invalid preserves output' $invalid 0 $false $true}
 foreach($mode in @('timeout','429','503','max-tokens','invalid-json','partial-json','model-missing','model-blank','model-whitespace','model-other','model-prefix')){$global:GeminiBudgetSpy.mode=$mode;Case $mode @{} 1 $false}
 . (Join-Path $repo 'scripts/single-attempt-execution.ps1')
 $handle=New-SingleAttemptExecution -ProjectPath $scratch -Provider Gemini -Model gemini-3.8-flash
 $direct=Join-Path $scratch 'adapter-preserved.json';[IO.File]::WriteAllText($direct,'ADAPTER OUTPUT SENTINEL');$hash=(Get-FileHash $direct).Hash
 $global:GeminiBudgetSpy.calls=0;$rejected=$false
 try{& (Join-Path $repo 'scripts/providers/invoke-gemini.ps1') -Prompt fixture -Context context -SchemaPath $schema -OutputPath $direct -Model gemini-3.8-flash -SingleAttempt -SingleAttemptContext $handle -GeminiMaxOutputTokens 32768 -GeminiThinkingLevel medium|Out-Null}catch{$rejected=$true}
 Assert ($rejected -and $global:GeminiBudgetSpy.calls -eq 0) 'adapter invalid options invoked transport'
 Assert ((Get-FileHash $direct).Hash -eq $hash) 'adapter invalid options changed output'
 $journal=Get-Content (Join-Path $scratch ('.codex/runtime/single-attempt-executions/'+$handle.Id+'.json')) -Raw|ConvertFrom-Json
 Assert ($journal.attempts_started -eq 0) 'adapter invalid options started an attempt'
 . (Join-Path $repo 'test-project/helpers/grounded-review-fixture.ps1')
 . (Join-Path $repo 'scripts/task-execution-lock.ps1')
 foreach($mode in @('grounded-valid','grounded-missing-obligation','grounded-bad-citation')){
  $root=Join-Path $scratch ([guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($root)|Out-Null
  foreach($dir in @('scripts','schemas','.codex')){Copy-Item (Join-Path $repo $dir) $root -Recurse}
  $fixture=New-GroundedRouterFixture -Root $root;Exit-TaskExecutionLock -Lock $fixture.Lease
  $task=Join-Path $root 'tasks/AICO-001.md';$text=[IO.File]::ReadAllText($task).Replace("## Acceptance Criteria`n","## Acceptance Criteria`n`n")
  $text+="`n- [ ] The component boundaries are recorded.`n- [ ] The migration risks are recorded.`n- [ ] The open questions are recorded.`n`n## Objective`n`nReview the isolated architecture fixture."
  [IO.File]::WriteAllText($task,$text,(New-Object Text.UTF8Encoding($false)));$hash=(Get-FileHash $task).Hash
  [IO.File]::WriteAllText((Join-Path $root '.codex/provider-config.json'),'{"gate_context_max_chars":180000,"allow_paid_fallback":true}')
  $cache=Join-Path $root '.codex/runtime/AICO-001-review-gate.json';[IO.Directory]::CreateDirectory((Split-Path $cache -Parent))|Out-Null
  [IO.File]::WriteAllText($cache,'EXISTING GATE CACHE');$cacheHash=(Get-FileHash $cache).Hash
  $journalRoot=Join-Path $root '.codex/runtime/single-attempt-executions'
  $journalsBefore=@(Get-ChildItem $journalRoot -File -ErrorAction SilentlyContinue).Count
  $locksBefore=@(Get-ChildItem (Join-Path $root '.codex/runtime/locks') -Recurse -File -ErrorAction SilentlyContinue|ForEach-Object {$_.FullName+':'+(Get-FileHash $_.FullName).Hash}) -join '|'
  $global:GeminiBudgetSpy.calls=0;$rejected=$false
  try{& (Join-Path $root 'scripts/run-gate-agent.ps1') -ProjectPath $root -Id AICO-001 -Gate Review -Provider Gemini -Model gemini-3.8-flash -SingleAttempt -GeminiMaxOutputTokens 65537 -GeminiThinkingLevel low|Out-Null}catch{$rejected=$true}
  Assert ($rejected -and $global:GeminiBudgetSpy.calls -eq 0) 'invalid gate budget invoked transport'
  Assert ((Get-FileHash $cache).Hash -eq $cacheHash -and (Get-FileHash $task).Hash -eq $hash) 'invalid gate budget mutated cache/task'
  Assert (@(Get-ChildItem $journalRoot -File -ErrorAction SilentlyContinue).Count -eq $journalsBefore) 'invalid gate budget created journal'
  $locksAfter=@(Get-ChildItem (Join-Path $root '.codex/runtime/locks') -Recurse -File -ErrorAction SilentlyContinue|ForEach-Object {$_.FullName+':'+(Get-FileHash $_.FullName).Hash}) -join '|'
  Assert ($locksAfter -ceq $locksBefore) 'invalid gate budget changed locks'
  $global:GeminiBudgetSpy.mode=$mode;$global:GeminiBudgetSpy.calls=0;$ok=$true;$reason=''
  try{& (Join-Path $root 'scripts/run-gate-agent.ps1') -ProjectPath $root -Id AICO-001 -Gate Review -Provider Gemini -Model gemini-3.8-flash -SingleAttempt -GeminiMaxOutputTokens 32768 -GeminiThinkingLevel low|Out-Null}catch{$ok=$false;$reason=$_.Exception.Message}
  Assert ($ok -eq ($mode -eq 'grounded-valid')) "$mode gate acceptance: $reason"
  Assert ($global:GeminiBudgetSpy.calls -eq 1) "$mode gate call count"
  Assert ($global:GeminiBudgetSpy.obligations -eq 11) "$mode eleven obligations absent"
  Assert ($global:GeminiBudgetSpy.payload.generationConfig.maxOutputTokens -eq 32768) "$mode gate budget not forwarded"
  $sidecars=@(Get-ChildItem (Join-Path $root 'docs/engineering/reviews') -Filter '*.grounding.json' -ErrorAction SilentlyContinue)
  if($ok){Assert ($sidecars.Count -eq 1) 'canonical grounding missing';Assert ([IO.File]::ReadAllText($sidecars[0].FullName) -match 'byte_start') 'canonical citation spans missing'}else{Assert ((Get-FileHash $task).Hash -eq $hash) 'failed Review mutated task';Assert ($sidecars.Count -eq 0) 'failed Review published'}
 }
 Write-Host "PASS: Gemini single-attempt budget ($($global:GeminiBudgetSpy.assertions) assertions); scratch=$scratch" -ForegroundColor Green
}finally{[Environment]::SetEnvironmentVariable('AICO_ERROR_INTELLIGENCE_ENABLED',$eiSaved);[Environment]::SetEnvironmentVariable('GEMINI_API_KEY',$saved);Remove-Variable GeminiBudgetSpy -Scope Global -ErrorAction SilentlyContinue}
