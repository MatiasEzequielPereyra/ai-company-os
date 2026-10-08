param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts/task-execution-lock.ps1')
. (Join-Path $repoRoot 'scripts/review-grounding.ps1')
. (Join-Path $repoRoot 'test-project/helpers/grounded-review-fixture.ps1')
$groundedFixture=$null
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('aico-gate-authoritative-' + [guid]::NewGuid().ToString('N'))
$savedKey = $env:OPENROUTER_API_KEY
function Write-Text([string]$Path,[string]$Value) { [IO.File]::WriteAllText($Path,$Value,(New-Object Text.UTF8Encoding($false))) }
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Set-Budget([int]$LocalBudget,[int]$GlobalBudget=22000) {
    $config = @{ auto_order=@('Ollama','OpenRouter'); gate_auto_order=@('Ollama','OpenRouter'); allow_paid_fallback=$true; models=@{Ollama='qwen3:8b';OpenRouter='fake'}; gate_context_max_chars=$GlobalBudget; ollama_gate_context_max_chars=$LocalBudget; provider_timeout_seconds=@{Ollama=30;OpenRouter=30} }
    Write-Text (Join-Path $tempRoot '.codex/provider-config.json') ($config | ConvertTo-Json -Depth 10)
}
function Invoke-Case([string]$Name,[string]$Provider,[string]$Context,[string]$Schema='review-result.schema.json') {
    $script:caseRoot = Join-Path $tempRoot $Name
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    & (Join-Path $tempRoot 'scripts/provider-router.ps1') -Provider $Provider -ProjectPath $tempRoot -Prompt 'Deterministic authoritative gate regression' -Context $Context -SchemaPath (Join-Path $tempRoot ('schemas/'+$Schema)) -OutputPath (Join-Path $caseRoot 'result.json') -Role 'engineering-manager' -Workload 'gate' -SemanticValidatorPath (Join-Path $tempRoot 'scripts/validate-gate-result-semantics.ps1') -SemanticValidationContext $groundedFixture.Context
}
try {
    foreach ($dir in @('scripts/providers','scripts/local-runtime','schemas','.codex/runtime')) { New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $dir) | Out-Null }
    foreach ($name in @('provider-router.ps1','validate-json-contract.ps1','write-operational-event.ps1','validate-gate-result-semantics.ps1')) { Copy-Item (Join-Path $repoRoot ('scripts/'+$name)) (Join-Path $tempRoot ('scripts/'+$name)) }
    foreach ($name in @('review-result.schema.json','qa-gate-result.schema.json','security-gate-result.schema.json')) { Copy-Item (Join-Path $repoRoot ('schemas/'+$name)) (Join-Path $tempRoot ('schemas/'+$name)) }
    Write-Text (Join-Path $tempRoot '.codex/local-runtime-config.json') '{}'
    Write-Text (Join-Path $tempRoot 'scripts/local-runtime/resolve-local-runtime.ps1') @'
param([string]$ProjectPath,[string]$Role,[string]$Workload,[string]$ModelOverride)
[pscustomobject]@{Available=$true;Profile='FAKE';CapabilityScore=78;Model='qwen3:8b';NumCtx=16384;NumPredict=2048;ContextMaxChars=50000;GateContextMaxChars=22000;GateArtifactMaxChars=7000;Reason='Deterministic fake'}
'@
    $adapter = @'
param([string]$Prompt,[string]$Context,[string]$SchemaPath,[string]$OutputPath,[string]$Model,[int]$NumCtx,[int]$NumPredict,[int]$TimeoutSeconds)
$provider = if ($PSCommandPath -match 'ollama') {'Ollama'} else {'OpenRouter'}
[IO.File]::WriteAllText((Join-Path (Split-Path $OutputPath) ($provider+'.txt')),$Context)
$payload = switch ([IO.Path]::GetFileName($SchemaPath)) {
 'review-result.schema.json' { [IO.File]::ReadAllText((Join-Path (Split-Path (Split-Path $OutputPath)) 'fixture-grounded-review.json')) | ConvertFrom-Json }
 'qa-gate-result.schema.json' { @{outcome='PASS';evidence='Fake';findings='Complete evidence';criteria_assessment=@(@{criterion='Non-goals';status='SATISFIED';evidence='Middle preserved'})} }
 'security-gate-result.schema.json' { @{outcome='PASS';evidence='Fake';findings='Complete evidence';security_relevant=$true;deliverable_security_defects=@()} }
}
[IO.File]::WriteAllText($OutputPath,($payload | ConvertTo-Json -Depth 10))
[pscustomobject]@{Provider=$provider;Model=$Model}
'@
    foreach ($name in @('invoke-ollama.ps1','invoke-openrouter.ps1')) { Write-Text (Join-Path $tempRoot ('scripts/providers/'+$name)) $adapter }
    $groundedFixture=New-GroundedRouterFixture -Root $tempRoot
    $env:OPENROUTER_API_KEY = 'deterministic-fake-not-a-real-key'
    $nl = [Environment]::NewLine
    $report = 'REPORT_START' + $nl + ('X'*4500) + $nl + '## Non-goals' + $nl + 'MIDDLE_NON_GOALS: persistence, telemetry and collaboration are excluded.' + $nl + ('Y'*4500) + $nl + 'REPORT_END'
    $authoritative = @('===== CANONICAL TASK =====','Task exact acceptance criteria','===== DISPATCH PACKET =====','Dispatch exact','===== ORIGINAL OWNER ROLE CONTRACT =====','Owner requires non-goals','===== PRIMARY AGENT REPORT =====','Repository-relative path: docs/engineering/agent-reports/AICO-001.md',$report,'===== LATEST TASK RESULT =====','Result references authoritative report') -join $nl
    $context = ('GENERIC_PADDING_'*5000) + $nl + $authoritative
    Set-Budget 7000
    $result = Invoke-Case 'small-auto' 'Auto' $context
    Assert-True ($result.Provider -eq 'OpenRouter') 'Auto must reject insufficient local evidence budget and use fake cloud.'
    Assert-True (-not (Test-Path (Join-Path $caseRoot 'Ollama.txt'))) 'Insufficient local budget must make no inference call.'
    $capture = Get-Content (Join-Path $caseRoot 'OpenRouter.txt') -Raw
    Assert-True ($capture.Contains($authoritative)) 'Cloud must receive every authoritative section verbatim, including report middle.'
    Assert-True ($capture.Length -le 22000) 'Cloud context must stay within effective budget.'
    $failed = $false
    try { Invoke-Case 'small-explicit' 'Ollama' $context | Out-Null } catch { $failed = $_.Exception.Message -match 'authoritative gate evidence exceeds' }
    Assert-True $failed 'Explicit local provider must fail closed with a concrete evidence budget error.'
    Assert-True (-not (Test-Path (Join-Path $caseRoot 'Ollama.txt'))) 'Explicit insufficient provider must not be called.'
    Set-Budget 16000
    Invoke-Case 'large-local' 'Ollama' $context | Out-Null
    $capture = Get-Content (Join-Path $caseRoot 'Ollama.txt') -Raw
    Assert-True ($capture.Contains($authoritative)) 'Sufficient local budget must preserve entire authoritative source.'
    Assert-True ($capture.Length -le 16000) 'Sufficient local context must stay within budget.'
    foreach ($gate in @('qa','security')) {
        Set-Budget 7000
        $review = '===== LATEST INDEPENDENT REVIEW ====='+$nl+'REVIEW_START'+('R'*1200)+'REVIEW_MIDDLE_APPROVE'+('S'*1200)+'REVIEW_END'
        $qa = '===== QA GATE ====='+$nl+'QA_START'+('Q'*1200)+'QA_MIDDLE_PASS'+('Z'*1200)+'QA_END'
        $required = $authoritative+$nl+$review
        if ($gate -eq 'security') { $required += $nl+$qa }
        $result = Invoke-Case ($gate+'-fallback') 'Auto' (('GENERIC_'*6000)+$nl+$required) ($gate+'-gate-result.schema.json')
        Assert-True ($result.Provider -eq 'OpenRouter') ($gate+' insufficient local budget must fallback before inference.')
        Assert-True (-not (Test-Path (Join-Path $caseRoot 'Ollama.txt'))) ($gate+' rejected local candidate must not be called.')
        $capture = Get-Content (Join-Path $caseRoot 'OpenRouter.txt') -Raw
        Assert-True ($capture.Contains($required)) ($gate+' must preserve prior review and QA evidence completely.')
        Assert-True ($capture.Length -le 22000) ($gate+' cloud budget exceeded.')
    }
    Set-Budget 7000
    Invoke-Case 'generic-only' 'Ollama' ('GENERIC_ONLY_'*6000) | Out-Null
    $capture = Get-Content (Join-Path $caseRoot 'Ollama.txt') -Raw
    Assert-True ($capture.Length -le 7000 -and $capture.Contains('TRUNCATED')) 'Generic oversized context may still truncate.'
    # Invoke the real artifact constructor without executing gate orchestration.
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts/run-gate-agent.ps1'),[ref]$tokens,[ref]$parseErrors)
    $fn = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Add-Artifact'},$true)
    Invoke-Expression $fn.Extent.Text
    $artifact = Join-Path $tempRoot 'owner-report.md'; Write-Text $artifact $report
    $builder = New-Object Text.StringBuilder
    Add-Artifact -Builder $builder -Root $tempRoot -Path $artifact -Label 'PRIMARY AGENT REPORT' -MaxChars 60000
    Assert-True ($builder.ToString().Contains($report)) 'Real gate construction must preserve report middle and complete content.'
    $largeReport = 'LARGE_REPORT_START'+('L'*31000)+'LARGE_REPORT_CRITICAL_MIDDLE'+('M'*31000)+'LARGE_REPORT_END'
    Write-Text $artifact $largeReport
    $builder = New-Object Text.StringBuilder
    Add-Artifact -Builder $builder -Root $tempRoot -Path $artifact -Label 'PRIMARY AGENT REPORT'
    Assert-True ($builder.ToString().Contains($largeReport)) 'Artifact larger than legacy 60000 limit must reach candidate budget evaluation completely.'
    Set-Budget 7000 180000
    $result = Invoke-Case 'large-construction-cloud' 'Auto' (('GENERIC_'*30000)+$builder.ToString())
    Assert-True ($result.Provider -eq 'OpenRouter') 'Large constructed artifact must skip local provider and reach fake cloud.'
    Assert-True (-not (Test-Path (Join-Path $caseRoot 'Ollama.txt'))) 'Large constructed artifact must reject local budget before inference.'
    $capture = Get-Content (Join-Path $caseRoot 'OpenRouter.txt') -Raw
    Assert-True ($capture.Contains($largeReport)) 'Large constructed artifact must arrive at cloud completely.'
    Assert-True ($capture.Length -le 180000) 'Large artifact cloud context must remain bounded.'
    Write-Host 'PASS: authoritative gate evidence, local rejection, Auto cloud fallback, QA/Security, generic truncation, full large artifact construction' -ForegroundColor Green
}
finally {
    if($null-ne $groundedFixture){Exit-TaskExecutionLock -Lock $groundedFixture.Lease}
    $env:OPENROUTER_API_KEY = $savedKey
    if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
