param()
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aico-corrective-context-'+[guid]::NewGuid().ToString('N'))
function Put([string]$Path,[string]$Text) {
    $full=Join-Path $temp $Path
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    [IO.File]::WriteAllText($full,$Text)
}
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    $builder=Join-Path $repo 'scripts/build-corrective-analysis-context.ps1'
    Put 'tasks/AICO-002.md' "ID: AICO-002`nOwner: cto`nTASK_END"
    Put '.codex/agents/cto.md' 'CTO_ROLE_END'
    Put 'docs/engineering/dispatch/AICO-002.md' "Task: AICO-002`nOwner: cto`nDISPATCH_END"
    Assert ([string]::IsNullOrEmpty((& $builder -ProjectPath $temp -Id AICO-002 -Owner cto))) 'First attempt must not invent corrective context.'
    Assert ([string]::IsNullOrEmpty((& $builder -ProjectPath $temp -Id AICO-P1-PLAN-03 -Owner engineering-manager))) 'Existing custom task IDs must remain supported on first attempt.'
    Put 'docs/engineering/reviews/AICO-002-review-001.md' "Task: AICO-002`nTask owner: cto`nRecommendation: CHANGES_REQUIRED`n## Findings`nADR_REQUIRED_REVIEW_END"
    Put 'docs/engineering/results/AICO-002-result-001.md' "Task: AICO-002`nOwner: cto`nRESULT_END"
    Put 'docs/engineering/agent-reports/AICO-002.md' "# Agent Report - AICO-002`nOwner: cto`nPREVIOUS_DELIVERABLE_END"
    $required=& $builder -ProjectPath $temp -Id AICO-002 -Owner cto
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'scripts/provider-router.ps1'),[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'Router syntax error.'
    foreach ($name in @('Limit-ProviderContext','Limit-CorrectiveAnalysisContext')) {
        $function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
        Invoke-Expression $function.Extent.Text
    }
    $sent=Limit-CorrectiveAnalysisContext -Context ('GENERAL' * 10000) -RequiredContext $required -MaxChars 20000
    Assert ($sent.Length -le 20000) 'Effective budget exceeded.'
    foreach ($marker in @('TASK_END','CTO_ROLE_END','DISPATCH_END','RESULT_END','PREVIOUS_DELIVERABLE_END','ADR_REQUIRED_REVIEW_END','END CORRECTIVE ANALYSIS EVIDENCE')) {
        Assert ($sent.Contains($marker)) "Critical corrective evidence lost: $marker"
    }
    $failed=$false
    try { Limit-CorrectiveAnalysisContext -Context 'GENERAL' -RequiredContext ('X'*21000) -MaxChars 20000 | Out-Null } catch { $failed=$true }
    Assert $failed 'Oversized required evidence must fail closed.'
    $history = (1..500 | ForEach-Object { "- historical operational entry $_ " + ('irrelevant-history ' * 10) }) -join "`n"
    Put 'tasks/AICO-002.md' "ID: AICO-002`nOwner: cto`n## Objective`nFULL_OBJECTIVE_END`n## Acceptance Criteria`nFULL_ACCEPTANCE_END`n## Dependencies`nFULL_DEPENDENCIES_END`n## Evidence`n$history`n## Transition Log`n$history`n## Notes`n$history`n## Testing`nFULL_TESTING_END"
    Put 'docs/architecture/contract.md' 'FULL_CHANGED_CONTRACT_END'
    Put 'docs/decisions/adr.md' 'FULL_CHANGED_ADR_END'
    Put 'docs/engineering/results/AICO-002-result-002.md' "Task: AICO-002`nOwner: cto`n## Changed Artifacts`ndocs/architecture/contract.md; docs/decisions/adr.md; docs/engineering/agent-reports/AICO-002.md`n## Verification`nRESULT_END"
    $required=& $builder -ProjectPath $temp -Id AICO-002 -Owner cto
    $sent=Limit-CorrectiveAnalysisContext -Context ('GENERAL'*10000) -RequiredContext $required -MaxChars 20000
    foreach ($marker in @('FULL_OBJECTIVE_END','FULL_ACCEPTANCE_END','FULL_DEPENDENCIES_END','FULL_TESTING_END','FULL_CHANGED_CONTRACT_END','FULL_CHANGED_ADR_END','PREVIOUS_DELIVERABLE_END','ADR_REQUIRED_REVIEW_END','history compacted','historical operational entry 500')) {
        Assert ($sent.Contains($marker)) "Compaction lost required content: $marker"
    }
    Assert (-not $sent.Contains('historical operational entry 1 ')) 'Old operational history was not compacted.'
    $digest=(Get-FileHash -LiteralPath (Join-Path $temp 'tasks/AICO-002.md') -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert ($sent.Contains($digest)) 'Exact source digest missing.'
    # Reproduce a child host where the module-provided hash command is unusable.
    # Mixed Unicode/CRLF and a BOM ensure the digest covers exact file bytes,
    # rather than a decoded/re-encoded task string.
    $taskPath=Join-Path $temp 'tasks/AICO-002.md'
    $unicodeEvidence='correcci' + [char]0x00f3 + 'n ' + [char]0x2014 + ' ' + [char]0x65e5 + [char]0x672c + [char]0x8a9e
    $byteSensitiveTask=([IO.File]::ReadAllText($taskPath)).Replace("`n","`r`n") + "`r`nUnicode evidence: $unicodeEvidence`r`n"
    [IO.File]::WriteAllText($taskPath,$byteSensitiveTask,(New-Object Text.UTF8Encoding($true)))
    $expectedHasher=[Security.Cryptography.SHA256]::Create()
    try { $expectedDigest=([BitConverter]::ToString($expectedHasher.ComputeHash([IO.File]::ReadAllBytes($taskPath)))).Replace('-','').ToLowerInvariant() }
    finally { $expectedHasher.Dispose() }
    & {
        function Get-FileHash { throw 'Synthetic unavailable Get-FileHash in inherited module environment.' }
        $unavailable=$false
        try { Get-FileHash -LiteralPath $taskPath -Algorithm SHA256 | Out-Null } catch { $unavailable=$true }
        Assert $unavailable 'Regression did not make Get-FileHash unavailable.'
        $portableRequired=& $builder -ProjectPath $temp -Id AICO-002 -Owner cto
        $portableSent=Limit-CorrectiveAnalysisContext -Context ('GENERAL'*10000) -RequiredContext $portableRequired -MaxChars 20000
        Assert ($portableSent.Length -le 20000) 'Portable hash context exceeded provider budget.'
        Assert ($portableSent.Contains("Canonical task source SHA256: $expectedDigest")) 'Portable hash did not cover exact Unicode/CRLF/BOM source bytes.'
        Assert ($portableSent.Contains("full source tasks/AICO-002.md SHA256=$expectedDigest")) 'Compaction marker did not preserve exact byte digest.'
        foreach ($marker in @('FULL_OBJECTIVE_END','FULL_ACCEPTANCE_END','FULL_DEPENDENCIES_END','FULL_TESTING_END','FULL_CHANGED_CONTRACT_END','FULL_CHANGED_ADR_END','PREVIOUS_DELIVERABLE_END','ADR_REQUIRED_REVIEW_END','historical operational entry 500','END CORRECTIVE ANALYSIS EVIDENCE')) {
            Assert ($portableSent.Contains($marker)) "Portable hash path lost corrective evidence: $marker"
        }
        Assert (-not $portableSent.Contains('historical operational entry 1 ')) 'Portable hash path did not compact old history.'
    }
    Put 'docs/engineering/writable-evidence/AICO-002.md' 'LEGACY_WRITABLE_EVIDENCE_END'
    Put 'docs/engineering/results/AICO-002-result-002.md' "Task: AICO-002`nOwner: cto`n## Changed Artifacts`ndocs/engineering/writable-evidence/AICO-002.md docs/engineering/agent-reports/AICO-002.md"
    $legacy=& $builder -ProjectPath $temp -Id AICO-002 -Owner cto
    Assert ($legacy.Contains('LEGACY_WRITABLE_EVIDENCE_END')) 'Exact historical writable artifact pair not resolved.'
    foreach ($badPair in @('docs/architecture/contract.md docs/decisions/adr.md','docs/engineering/writable-evidence/AICO-002.md docs/engineering/agent-reports/AICO-999.md')) {
        Put 'docs/engineering/results/AICO-002-result-002.md' "Task: AICO-002`nOwner: cto`n## Changed Artifacts`n$badPair"
        $failed=$false
        try { & $builder -ProjectPath $temp -Id AICO-002 -Owner cto | Out-Null } catch { $failed=$true }
        Assert $failed 'Arbitrary or mismatched whitespace pair must remain fail closed.'
    }
    Put 'docs/engineering/results/AICO-002-result-002.md' "Task: AICO-002`nOwner: cto`n## Changed Artifacts`n.codex/provider-config.json"
    $failed=$false
    try { & $builder -ProjectPath $temp -Id AICO-002 -Owner cto | Out-Null } catch { $failed=$true }
    Assert $failed 'Secret configuration reference must fail closed.'
    Put 'docs/engineering/results/AICO-002-result-002.md' "Task: AICO-002`nOwner: cto`n## Changed Artifacts`ndocs/../../escape.md"
    $failed=$false
    try { & $builder -ProjectPath $temp -Id AICO-002 -Owner cto | Out-Null } catch { $failed=$true }
    Assert $failed 'Escaping artifact reference must fail closed.'
    # A junction requires no symbolic-link privilege on Windows; reject any linked ancestor.
    $link=Join-Path $temp 'docs/linked'
    $target=Join-Path $temp 'link-target'
    New-Item -ItemType Directory -Path $target | Out-Null
    [IO.File]::WriteAllText((Join-Path $target 'artifact.md'),'LINKED_CONTENT')
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    try {
        Put 'docs/engineering/results/AICO-002-result-002.md' "Task: AICO-002`nOwner: cto`n## Changed Artifacts`ndocs/linked/artifact.md"
        $failed=$false
        try { & $builder -ProjectPath $temp -Id AICO-002 -Owner cto | Out-Null } catch { $failed=$true }
        Assert $failed 'Linked artifact ancestor must fail closed.'
    } finally { [IO.Directory]::Delete($link) }
    $reports=Join-Path $temp 'docs/engineering/agent-reports'
    $savedReports=Join-Path $temp 'saved-reports'
    Move-Item -LiteralPath $reports -Destination $savedReports
    New-Item -ItemType Junction -Path $reports -Target $savedReports | Out-Null
    try {
        Put 'docs/engineering/results/AICO-002-result-002.md' "Task: AICO-002`nOwner: cto`n## Changed Artifacts`nNone"
        $failed=$false
        try { & $builder -ProjectPath $temp -Id AICO-002 -Owner cto | Out-Null } catch { $failed=$true }
        Assert $failed 'Core primary report must reject linked ancestors before reading.'
    } finally {
        [IO.Directory]::Delete($reports)
        Move-Item -LiteralPath $savedReports -Destination $reports
    }
    Put 'docs/engineering/reviews/AICO-002-review-002.md' "Task: AICO-002`nTask owner: cto`nRecommendation: APPROVE`n## Findings`nApproved"
    Assert ([string]::IsNullOrEmpty((& $builder -ProjectPath $temp -Id AICO-002 -Owner cto))) 'Latest approval must supersede earlier changes required.'
    Put 'docs/engineering/reviews/AICO-002-review-003.md' "Task: AICO-999`nTask owner: cto`nRecommendation: CHANGES_REQUIRED`n## Findings`nMismatch"
    $failed=$false
    try { & $builder -ProjectPath $temp -Id AICO-002 -Owner cto | Out-Null } catch { $failed=$true }
    Assert $failed 'Mismatched corrective evidence must fail closed.'
    # Actual router, entirely synthetic local adapters: a small local budget cannot
    # discard corrective evidence, and Auto may use an already permitted larger one.
    foreach ($relative in @('scripts/providers','scripts/local-runtime','schemas','.codex/runtime')) { New-Item -ItemType Directory -Path (Join-Path $temp $relative) -Force | Out-Null }
    foreach ($name in @('provider-router.ps1','validate-json-contract.ps1','write-operational-event.ps1')) { Copy-Item -LiteralPath (Join-Path $repo "scripts/$name") -Destination (Join-Path $temp "scripts/$name") }
    Copy-Item -LiteralPath (Join-Path $repo 'schemas/agent-result.schema.json') -Destination (Join-Path $temp 'schemas/agent-result.schema.json')
    Put '.codex/local-runtime-config.json' '{}'
    Put '.codex/provider-config.json' (@{ auto_order=@('Ollama','OpenRouter'); allow_paid_fallback=$false; analysis_context_max_chars=30000; ollama_context_max_chars=10000; models=@{Ollama='fake';OpenRouter='fake'} } | ConvertTo-Json -Depth 10)
    Put 'scripts/local-runtime/resolve-local-runtime.ps1' @'
param($ProjectPath,$Role,$Workload,$ModelOverride)
[pscustomobject]@{Available=$true;Profile='FAKE';Model='fake';NumCtx=16384;NumPredict=2048;ContextMaxChars=30000;GateContextMaxChars=30000;GateArtifactMaxChars=30000}
'@
    Put 'scripts/providers/invoke-ollama.ps1' @'
param($Prompt,$Context,$SchemaPath,$OutputPath,$Model,$NumCtx,$NumPredict,$TimeoutSeconds)
[IO.File]::WriteAllText((Join-Path (Split-Path -Parent $OutputPath) 'unexpected-local-call'),'FAIL')
throw 'The undersized local adapter must not be called.'
'@
    Put 'scripts/providers/invoke-openrouter.ps1' @'
param($Prompt,$Context,$SchemaPath,$OutputPath,$Model,$TimeoutSeconds)
[IO.File]::WriteAllText((Join-Path (Split-Path -Parent $OutputPath) 'cloud-context.txt'),$Context)
$payload=@{outcome='COMPLETED';summary='fixture';report_markdown='fixture';verification='fixture';decisions='NONE';blockers='NONE';recommended_next='REVIEW';completion_check=@{substantive_role_deliverable_produced=$true;missing_required_outputs=@();evidence='fixture'}} | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($OutputPath,$payload)
[pscustomobject]@{Provider='OpenRouter';Model='fake'}
'@
    $savedKey=$env:OPENROUTER_API_KEY
    $savedDeepSeekKey=$env:DEEPSEEK_API_KEY
    try {
        $env:OPENROUTER_API_KEY='fake-test-only'
        $output=Join-Path $temp '.codex/runtime/fallback-result.json'
        $essential='FULL_CORRECTIVE_START'+('E'*12000)+'FULL_CORRECTIVE_END'
        & (Join-Path $temp 'scripts/provider-router.ps1') -Provider Auto -ProjectPath $temp -Prompt 'synthetic' -Context ('G'*40000) -CorrectiveContext $essential -Role cto -Workload analysis -SchemaPath (Join-Path $temp 'schemas/agent-result.schema.json') -OutputPath $output | Out-Null
        Assert (-not (Test-Path -LiteralPath (Join-Path $temp '.codex/runtime/unexpected-local-call'))) 'Auto invoked rejected local candidate.'
        $cloud=[IO.File]::ReadAllText((Join-Path $temp '.codex/runtime/cloud-context.txt'))
        Assert ($cloud.Contains($essential) -and $cloud.Length -le 30000) 'Auto fallback lost corrective evidence or exceeded cloud budget.'
        # The same protected envelope must survive every writable provider budget.
        Put '.codex/provider-config.json' (@{auto_order=@('OpenRouter');allow_paid_fallback=$false;context_max_chars=30000;analysis_context_max_chars=30000;models=@{OpenRouter='openrouter/free'}} | ConvertTo-Json -Depth 10)
        & (Join-Path $temp 'scripts/provider-router.ps1') -Provider OpenRouter -ProjectPath $temp -Prompt 'synthetic writable' -Context ('G'*40000) -CorrectiveContext $essential -Role frontend -Workload writable -SchemaPath (Join-Path $temp 'schemas/agent-result.schema.json') -OutputPath $output | Out-Null
        $cloud=[IO.File]::ReadAllText((Join-Path $temp '.codex/runtime/cloud-context.txt'))
        Assert ($cloud.Contains($essential) -and $cloud.Length -le 30000) 'Writable cloud context lost protected findings or exceeded finite budget.'
        Put '.codex/provider-config.json' (@{ auto_order=@('Ollama','OpenRouter'); allow_paid_fallback=$false; analysis_context_max_chars=30000; ollama_context_max_chars=10000; models=@{Ollama='fake';OpenRouter='fake'} } | ConvertTo-Json -Depth 10)
        $failed=$false
        try { & (Join-Path $temp 'scripts/provider-router.ps1') -Provider Ollama -ProjectPath $temp -Prompt 'synthetic' -Context 'G' -CorrectiveContext $essential -Role cto -Workload analysis -SchemaPath (Join-Path $temp 'schemas/agent-result.schema.json') -OutputPath $output | Out-Null } catch { $failed=$true }
        Assert $failed 'Explicit undersized provider must fail closed.'
        Put '.codex/provider-config.json' (@{auto_order=@('Ollama','DeepSeek');allow_paid_fallback=$false;analysis_context_max_chars=30000;ollama_context_max_chars=10000;models=@{Ollama='fake';DeepSeek='fake'}} | ConvertTo-Json -Depth 10)
        Copy-Item -LiteralPath (Join-Path $temp 'scripts/providers/invoke-openrouter.ps1') -Destination (Join-Path $temp 'scripts/providers/invoke-deepseek.ps1')
        Remove-Item -LiteralPath (Join-Path $temp '.codex/runtime/cloud-context.txt')
        $env:DEEPSEEK_API_KEY='fake-test-only'
        $failed=$false
        try { & (Join-Path $temp 'scripts/provider-router.ps1') -Provider Auto -ProjectPath $temp -Prompt 'synthetic' -Context 'G' -CorrectiveContext $essential -Role cto -Workload analysis -SchemaPath (Join-Path $temp 'schemas/agent-result.schema.json') -OutputPath $output | Out-Null } catch { $failed=$true }
        Assert ($failed -and -not (Test-Path -LiteralPath (Join-Path $temp '.codex/runtime/cloud-context.txt'))) 'Budget fallback must not bypass disabled paid provider policy.'
    } finally { $env:OPENROUTER_API_KEY=$savedKey; $env:DEEPSEEK_API_KEY=$savedDeepSeekKey }
    Write-Host 'PASS: corrective analysis evidence identity, latest decision, full retention and fail-closed budget.'
}
finally {
    if ((Test-Path -LiteralPath $temp) -and ([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase))) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
