param()
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'test-project/helpers/grounded-review-fixture.ps1')
. (Join-Path $repoRoot 'scripts/task-execution-lock.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('aico-grounded-router-'+[guid]::NewGuid().ToString('N'))
$fixture=$null;$checks=0
$savedRouterKey=$env:OPENROUTER_API_KEY;$savedGeminiKey=$env:GEMINI_API_KEY
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:checks++}
function WriteFixture([string]$Path,[string]$Value){[IO.File]::WriteAllText($Path,$Value,[Text.UTF8Encoding]::new($false))}
function codex {throw 'A deterministic adapter must never invoke a real CLI.'}
function InvokeRouter([string]$Provider='Auto') {
    & (Join-Path $root 'scripts/provider-router.ps1') -Provider $Provider -ProjectPath $root -Prompt 'Independent Review v1 fixture.' -Context $context -SchemaPath (Join-Path $root 'schemas/review-result.schema.json') -OutputPath (Join-Path $root 'out.json') -Workload gate -Role engineering-manager -SemanticValidatorPath (Join-Path $root 'scripts/validate-gate-result-semantics.ps1') -SemanticValidationContext $fixture.Context
}
function StartScenario([string]$Mode){
    WriteFixture (Join-Path $root 'mode.txt') $Mode
    if(Test-Path -LiteralPath (Join-Path $root 'attempts.jsonl')){Remove-Item -LiteralPath (Join-Path $root 'attempts.jsonl') -Force}
}
function Attempts {return @(Get-Content -LiteralPath (Join-Path $root 'attempts.jsonl') -ErrorAction SilentlyContinue|ForEach-Object{$_|ConvertFrom-Json})}
try {
    foreach($dir in @('scripts/providers','.codex','schemas')){New-Item -ItemType Directory -Force -Path (Join-Path $root $dir)|Out-Null}
    foreach($name in @('provider-router.ps1','validate-gate-result-semantics.ps1','write-operational-event.ps1')){Copy-Item (Join-Path $repoRoot "scripts/$name") (Join-Path $root "scripts/$name")}
    $config=[ordered]@{gate_auto_order=@('OpenRouter','Gemini');auto_order=@('OpenRouter','Gemini');allow_paid_fallback=$false;gate_context_max_chars=40000;models=@{OpenRouter='openrouter/free';Gemini='fixture-free'}}
    WriteFixture (Join-Path $root '.codex/provider-config.json') ($config|ConvertTo-Json -Depth 10)
    $fixture=New-GroundedRouterFixture -Root $root
    $protected=Get-ReviewGroundingPrompt -Context $fixture.Context
    WriteFixture (Join-Path $root 'frozen-context.txt') $protected
    $context=('generic inventory '+('g'*50000))+"`n"+$protected
    $adapter=@'
param([string]$ProjectPath,[string]$Prompt,[string]$Context,[string]$SchemaPath,[string]$OutputPath,[string]$Model,[int]$TimeoutSeconds)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $OutputPath
$provider=switch((Split-Path $PSCommandPath -Leaf)){'invoke-openrouter.ps1'{'OpenRouter'}'invoke-gemini.ps1'{'Gemini'}'invoke-codex.ps1'{'Codex'}}
$payload=Get-Content -LiteralPath (Join-Path $root 'fixture-grounded-review.json') -Raw -Encoding UTF8|ConvertFrom-Json
$mode=Get-Content -LiteralPath (Join-Path $root 'mode.txt') -Raw
$number=@(Get-Content -LiteralPath (Join-Path $root 'attempts.jsonl') -ErrorAction SilentlyContinue).Count+1
$supplied=if($provider-eq 'Codex'){$Prompt}else{$Context}
$expected=Get-Content -LiteralPath (Join-Path $root 'frozen-context.txt') -Raw -Encoding UTF8
$index=$supplied.IndexOf('===== CANONICAL TASK =====',[StringComparison]::Ordinal)
if($index-lt 0 -or $supplied.Length-$index-lt $expected.Length){throw 'Protected engine frame missing or clipped.'}
$frame=$supplied.Substring($index,$expected.Length)
$sha=[Security.Cryptography.SHA256]::Create()
try{$digest=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($frame)))).Replace('-','')}finally{$sha.Dispose()}
$record=[ordered]@{provider=$provider;snapshot=$payload.snapshot_id;protected_sha=$digest;context_chars=$supplied.Length;has_snapshot=$supplied.Contains($payload.snapshot_id);repair=$Prompt.Contains('CORRECTION REQUIRED:');leaks_private=$Prompt.Contains('PRIVATE_REASONING_SENTINEL')}
Add-Content -LiteralPath (Join-Path $root 'attempts.jsonl') -Value ($record|ConvertTo-Json -Compress) -Encoding UTF8
if($mode-eq 'all-invalid' -or ($mode-eq 'fallback'-and $provider-eq 'OpenRouter') -or ($mode-eq 'repair'-and $number-eq 1)){$payload.assessments[0].evidence[0].artifact_id='secondary-result'}
if($mode-eq 'schema'-and $number-eq 1){$payload.PSObject.Properties.Remove('contract_version');$payload|Add-Member -NotePropertyName hidden_reasoning -NotePropertyValue 'PRIVATE_REASONING_SENTINEL'}
[IO.File]::WriteAllText($OutputPath,($payload|ConvertTo-Json -Depth 40),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{Provider=$provider;Model=$Model;OutputPath=$OutputPath}
'@
    foreach($file in @('invoke-openrouter.ps1','invoke-gemini.ps1','invoke-codex.ps1')){WriteFixture (Join-Path $root "scripts/providers/$file") $adapter}
    $env:OPENROUTER_API_KEY='deterministic-no-network';$env:GEMINI_API_KEY='deterministic-no-network'
    $taskPath=Join-Path $root 'tasks/AICO-001.md';$before=(Get-FileHash -LiteralPath $taskPath).Hash
    StartScenario repair
    $execution=InvokeRouter OpenRouter
    $attempts=@(Attempts)
    Check ($execution.Provider-eq 'OpenRouter'-and $attempts.Count-eq 2) 'M one same-provider semantic repair.'
    Check ($attempts[1].repair-and -not $attempts[0].repair) 'Repair regenerates full judgment with corrective feedback.'
    Check ($attempts[0].protected_sha-ceq $attempts[1].protected_sha-and $attempts[0].has_snapshot-and $attempts[1].has_snapshot) 'M immutable evidence and snapshot survive repair.'
    Check ($attempts[0].context_chars-le 40000) 'Generic inventory exceeding provider budget does not consume protected snapshot.'
    StartScenario schema
    InvokeRouter OpenRouter|Out-Null
    $attempts=@(Attempts)
    Check ($attempts.Count-eq 2-and $attempts[1].repair) 'Schema failure receives exactly one full-result repair.'
    Check (-not $attempts[1].leaks_private) 'Repair feedback excludes rejected private reasoning.'
    StartScenario fallback
    $execution=InvokeRouter
    $attempts=@(Attempts)
    Check ($execution.Provider-eq 'Gemini'-and ($attempts.provider-join ',')-ceq 'OpenRouter,OpenRouter,Gemini') 'M bounded repair precedes unchanged configured Auto fallback.'
    Check (@($attempts.protected_sha|Select-Object -Unique).Count-eq 1-and @($attempts|Where-Object{-not $_.has_snapshot}).Count-eq 0) 'M all providers receive the same frozen IDs and primary frames.'
    StartScenario all-invalid
    $failed=$false
    try{InvokeRouter|Out-Null}catch{$failed=$_.Exception.Message-match 'All configured providers failed.*REVIEW_GROUNDING_PRIMARY_AUTHORITY'}
    Check $failed 'N exhaustion yields typed fatal reason.'
    $attempts=@(Attempts)
    Check (($attempts.provider-join ',')-ceq 'OpenRouter,OpenRouter,Gemini,Gemini') 'N each candidate gets only one repair.'
    Check (-not(Test-Path -LiteralPath (Join-Path $root 'out.json'))) 'N no consumable rejected result survives.'
    StartScenario all-invalid
    $failed=$false
    try{InvokeRouter OpenRouter|Out-Null}catch{$failed=$_.Exception.Message-match 'REVIEW_GROUNDING_PRIMARY_AUTHORITY'}
    Check ($failed-and @(Attempts).Count-eq 2) 'Explicit provider never gains hidden fallback.'
    Check ((Get-FileHash -LiteralPath $taskPath).Hash-ceq $before) 'Rejected router judgments preserve REVIEW task bytes.'
    Check (@(Get-ChildItem -LiteralPath (Join-Path $root 'docs/engineering/reviews') -File -ErrorAction SilentlyContinue).Count-eq 0) 'Rejected attempts are never canonical Reviews.'
    $records=@(Get-ChildItem -LiteralPath (Join-Path $root '.codex/runtime/rejected-review-attempts') -File)
    Check ($records.Count-ge 8) 'Rejected attempts retain separate provenance records.'
    foreach($record in $records){$raw=Get-Content -LiteralPath $record.FullName -Raw;Check (-not $raw.Contains('PRIVATE_REASONING_SENTINEL')-and -not $raw.Contains('deterministic-no-network')) 'Diagnostics contain no private prose or credential values.'}
    StartScenario valid
    InvokeRouter Codex|Out-Null
    $attempts=@(Attempts)
    Check ($attempts.Count-eq 1-and $attempts[0].has_snapshot) 'Codex prompt explicitly receives the immutable engine snapshot.'
    Check ($attempts[0].protected_sha-ceq (Get-ReviewGroundingPrompt $fixture.Context|ForEach-Object {$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($_)))).Replace('-','')}finally{$sha.Dispose()}})) 'Codex supplied protected snapshot is byte-identical.'
    $config.gate_context_max_chars=4000
    WriteFixture (Join-Path $root '.codex/provider-config.json') ($config|ConvertTo-Json -Depth 10)
    StartScenario valid
    $failed=$false
    try{InvokeRouter OpenRouter|Out-Null}catch{$failed=$_.Exception.Message-match 'authoritative|protected|budget'}
    Check ($failed-and @(Attempts).Count-eq 0) 'O unfit protected snapshot fails before any provider call.'
    Write-Host "PASS review-grounding-router: $script:checks assertions"
} finally {
    $env:OPENROUTER_API_KEY=$savedRouterKey;$env:GEMINI_API_KEY=$savedGeminiKey
    if($null-ne $fixture){Exit-TaskExecutionLock -Lock $fixture.Lease}
    $full=[IO.Path]::GetFullPath($root);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/'))+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($temp,(Get-ExecutionPathComparison))){throw 'Unsafe fixture cleanup.'}
    if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
