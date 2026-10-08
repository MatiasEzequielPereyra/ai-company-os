param([string]$ProjectPath='')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repo 'scripts/task-execution-lock.ps1')
. (Join-Path $repo 'scripts/review-grounding.ps1')
$script:checks=0
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "Assertion failed: $Name"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Reason){$caught='';try{& $Action|Out-Null}catch{$caught=$_.Exception.Message};Check ($caught -match [regex]::Escape($Reason)) "expected $Reason; got $caught"}
function Clone($Value){$Value|ConvertTo-Json -Depth 60|ConvertFrom-Json}
function WriteUtf8([string]$Path,[string]$Text){[IO.Directory]::CreateDirectory((Split-Path $Path -Parent))|Out-Null;[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
$root=Join-Path ([IO.Path]::GetTempPath()) ('aico-grounding-'+[guid]::NewGuid().ToString('N'))
$lease=$null
try{
    WriteUtf8 (Join-Path $root 'tasks/AICO-002.md') "# Task`nID: AICO-002`nOwner: cto`nStatus: REVIEW`n## Acceptance Criteria`n- Concrete assigned task output.`n"
    WriteUtf8 (Join-Path $root 'docs/engineering/dispatch/AICO-002.md') "Task: AICO-002`nOwner: cto`n"
    Copy-Item (Join-Path $repo '.codex/agents/cto.md') (New-Item -ItemType Directory -Path (Join-Path $root '.codex/agents') -Force).FullName
    $report=Join-Path $root 'docs/engineering/agent-reports/AICO-002.md'
    $body="# Agent Report - AICO-002`nOwner: cto`nComplete concrete implementation steps.`nDuplicate exact text.`nOther content.`nDuplicate exact text.`n"
    WriteUtf8 $report $body
    WriteUtf8 (Join-Path $root 'docs/engineering/results/AICO-002-result-001.md') "Task: AICO-002`nOwner: cto`nSelf-attestation: complete plan.`n"
    $lease=Enter-TaskExecutionLock -ProjectPath $root -Id AICO-002 -Operation GATE
    $ctx=New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease
    $manifest=Get-ReviewGroundingManifest $ctx
    $good=[pscustomobject]@{contract_version='review-grounding-v1';snapshot_id=$manifest.snapshot_id;recommendation='APPROVE';findings='Complete deliverable judged by fake reviewer.';verification='Exact captured primary citations.';missing_required_outputs=@();deliverable_defects=@();assessments=@($manifest.obligations|ForEach-Object{[pscustomobject]@{required_output_id=$_.required_output_id;status='SATISFIED';rationale='Fake semantic judgment; provenance only.';evidence=@([pscustomobject]@{artifact_id='primary-1';start_line=3;end_line=3;excerpt='Complete concrete implementation steps.'})}})}
    Check ($null-ne (Assert-ReviewGroundingResult -Result $good -Context $ctx -CheckDrift)) 'A valid complete coverage yields registered token'
    Check ($manifest.obligations.Count -eq 8) 'role seven plus task one, no inferred responsibilities'
    $copy=Get-ReviewGroundingManifest $ctx;$copy.obligations[0].declaration='forged';Check ((Get-ReviewGroundingManifest $ctx).obligations[0].declaration -cne 'forged') 'detached manifest cannot modify registry'
    $bad=Clone $good;$bad.assessments[0].evidence[0].artifact_id='secondary-result';Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_PRIMARY_AUTHORITY'
    foreach($range in @(@(0,3),@(3,2),@(3,99),@('3',3),@(3,3.5))){$bad=Clone $good;$bad.assessments[0].evidence[0].start_line=$range[0];$bad.assessments[0].evidence[0].end_line=$range[1];Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_LOCATOR'}
    foreach($quote in @('Complete concrete implementation steps. ','complete concrete implementation steps.','Fabricated quote.')){$bad=Clone $good;$bad.assessments[0].evidence[0].excerpt=$quote;Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_EXCERPT_MISMATCH'}
    foreach($id in @('primary-2','tasks/AICO-003.md','../outside','https://example.invalid')){$bad=Clone $good;$bad.assessments[0].evidence[0].artifact_id=$id;Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_PRIMARY_AUTHORITY'}
    $bad=Clone $good;$bad.snapshot_id='another-snapshot';Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_SNAPSHOT_MISMATCH'
    $bad=Clone $good;$bad.assessments=@($bad.assessments|Select-Object -Skip 1);Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_COVERAGE'
    $bad=Clone $good;$bad.assessments[1].required_output_id=$bad.assessments[0].required_output_id;Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_COVERAGE'
    $bad=Clone $good;$bad.assessments[0].required_output_id='unknown';Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_COVERAGE'
    $bad=Clone $good;$bad.assessments[0].status='NOT_APPLICABLE';Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_CONDITIONAL_UNAUTHORIZED'
    $conditional=Clone $good;$conditional.assessments[6].status='NOT_APPLICABLE';$conditional.assessments[6]|Add-Member -NotePropertyName conditional_authority -NotePropertyValue $manifest.obligations[6].required_output_id;Check ($null-ne(Assert-ReviewGroundingResult $conditional $ctx)) 'R exact conditional ADR allows fact-cited judgment'
    $negative=Clone $good;$negative.recommendation='CHANGES_REQUIRED';$negative.missing_required_outputs=@('Technical implementation plan is absent.');$negative.assessments[1].status='UNSATISFIED';$negative.assessments[1].evidence=@();Check ($null-ne(Assert-ReviewGroundingResult $negative $ctx)) 'J concrete negative permits no fabricated positive quote'
    $bad=Clone $negative;$bad.recommendation='APPROVE';Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_APPROVE_CONTRADICTION'
    $bad=Clone $negative;$bad.assessments[1].status='SATISFIED';$bad.assessments[1].evidence=$good.assessments[1].evidence;Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_NEGATIVE_REQUIRED'
    $duplicate=Clone $good;$duplicate.assessments[0].evidence[0].start_line=6;$duplicate.assessments[0].evidence[0].end_line=6;$duplicate.assessments[0].evidence[0].excerpt='Duplicate exact text.';Check ($null-ne(Assert-ReviewGroundingResult $duplicate $ctx)) 'H explicit duplicate location accepted'
    $bad=Clone $duplicate;$bad.assessments[0].evidence[0].start_line=5;$bad.assessments[0].evidence[0].end_line=5;Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_EXCERPT_MISMATCH'
    $irrelevant=Clone $good;$irrelevant.assessments[1].evidence[0].start_line=5;$irrelevant.assessments[1].evidence[0].end_line=5;$irrelevant.assessments[1].evidence[0].excerpt='Other content.';Check ($null-ne(Assert-ReviewGroundingResult $irrelevant $ctx)) 'S genuine irrelevant quote passes provenance, not semantic quality'
    $bad=Clone $good;$bad.assessments[0].evidence=@($bad.assessments[0].evidence[0],$bad.assessments[0].evidence[0],$bad.assessments[0].evidence[0],$bad.assessments[0].evidence[0]);Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_CITATION_REQUIRED'
    $bad=Clone $good;$bad.assessments[0].evidence[0].excerpt=('x'*2049);Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_LOCATOR_LIMIT'
    $bad=Clone $good;$bad.assessments[0].rationale=' ';Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_INVALID_ASSESSMENT'
    $prompt=Get-ReviewGroundingPrompt $ctx;Check ($prompt.Contains('SECONDARY SELF-ATTESTATION') -and $prompt.Contains('3|Complete concrete implementation steps.')) 'immutable prompt authority and labels'
    WriteUtf8 $report ($body.Replace("`n","`r`n"));Reject {Assert-ReviewGroundingResult $good $ctx -CheckDrift} 'REVIEW_GROUNDING_SOURCE_DRIFT'
    Check ($null-ne(Assert-ReviewGroundingResult $good $ctx)) 'F frozen capture still validates without reading changed source'
    WriteUtf8 $report $body
    Remove-Item -LiteralPath $report;Reject {Assert-ReviewGroundingResult $good $ctx -CheckDrift} 'REVIEW_GROUNDING_SOURCE_DRIFT'
    WriteUtf8 $report $body
    Reject {New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease -PrimaryArtifacts @([pscustomobject]@{Path=$report;RelativePath='../AICO-003.md';Namespace='project'})} 'REVIEW_GROUNDING_AUTHORITY'
    Reject {Get-ReviewGroundingManifest (Clone $ctx)} 'REVIEW_GROUNDING_UNTRUSTED_CONTEXT'
    foreach($unsafe in @('../outside.md','\\server\share\report.md','C:\private\report.md','.env','secrets/credential.md')){
        Reject {New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease -PrimaryArtifacts @([pscustomobject]@{Path=$report;RelativePath=$unsafe;Namespace='project'})} 'REVIEW_GROUNDING_AUTHORITY'
    }
    $taskPath=Join-Path $root 'tasks/AICO-002.md';$taskBytes=[IO.File]::ReadAllBytes($taskPath)
    WriteUtf8 $taskPath ("ID: AICO-002`nOwner: cto`nStatus: REVIEW`n## Acceptance Criteria`n"+((1..65|ForEach-Object{"- Distinct obligation $_."})-join "`n"))
    Reject {New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease} 'REVIEW_GROUNDING_LIMIT'
    [IO.File]::WriteAllBytes($taskPath,$taskBytes)
    WriteUtf8 $taskPath "ID: AICO-002`nOwner: cto`nStatus: REVIEW`n## Acceptance Criteria`n- Valid.`n  - Nested unsupported.`n"
    Reject {New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease} 'OBLIGATION_SOURCE_MALFORMED'
    [IO.File]::WriteAllBytes($taskPath,$taskBytes)
    $long='x'*1800;WriteUtf8 $report "# Agent Report - AICO-002`nOwner: cto`n$long`n"
    $budgetContext=New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease
    $budget=Clone $good;$budget.snapshot_id=(Get-ReviewGroundingManifest $budgetContext).snapshot_id
    foreach($row in $budget.assessments){$row.evidence=@(1..3|ForEach-Object{[pscustomobject]@{artifact_id='primary-1';start_line=3;end_line=3;excerpt=$long}})}
    Reject {Assert-ReviewGroundingResult $budget $budgetContext} 'REVIEW_GROUNDING_LOCATOR_LIMIT'
    $long='x'*2049;WriteUtf8 $report "# Agent Report - AICO-002`nOwner: cto`n$long`n"
    $lineContext=New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease
    $overline=Clone $good;$overline.snapshot_id=(Get-ReviewGroundingManifest $lineContext).snapshot_id;$overline.assessments[0].evidence[0].excerpt=$long
    Reject {Assert-ReviewGroundingResult $overline $lineContext} 'REVIEW_GROUNDING_LOCATOR_LIMIT'
    WriteUtf8 $report $body
    $variantManifests=@()
    foreach($variant in @($body,$body.Replace("`n","`r`n"),(([string][char]0xfeff)+$body))){
        WriteUtf8 $report $variant
        $variantContext=New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease
        $vm=Get-ReviewGroundingManifest $variantContext;$variantManifests+=$vm
        $judgment=Clone $good;$judgment.snapshot_id=$vm.snapshot_id
        Check ($null-ne(Assert-ReviewGroundingResult $judgment $variantContext -CheckDrift)) 'G independently captured LF/CRLF/BOM supports normalized exact citation'
        Reject {Assert-ReviewGroundingResult $good $variantContext} 'REVIEW_GROUNDING_SNAPSHOT_MISMATCH'
    }
    Check ($variantManifests[0].artifacts[0].normalized_sha256-ceq $variantManifests[1].artifacts[0].normalized_sha256 -and $variantManifests[1].artifacts[0].normalized_sha256-ceq $variantManifests[2].artifacts[0].normalized_sha256) 'G equivalent normalized hashes'
    Check ($variantManifests[0].artifacts[0].raw_sha256-cne $variantManifests[1].artifacts[0].raw_sha256 -and $variantManifests[1].artifacts[0].raw_sha256-cne $variantManifests[2].artifacts[0].raw_sha256) 'G distinct raw byte identities'
    $unicode="e$([char]0x301) $([char]::ConvertFromUtf32(0x1f680))`t  "
    WriteUtf8 $report "# Agent Report - AICO-002`rOwner: cto`r$unicode`r"
    $unicodeContext=New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease
    $unicodeJudgment=Clone $good;$unicodeJudgment.snapshot_id=(Get-ReviewGroundingManifest $unicodeContext).snapshot_id
    foreach($row in $unicodeJudgment.assessments){$row.evidence[0].excerpt=$unicode}
    Check ($null-ne(Assert-ReviewGroundingResult $unicodeJudgment $unicodeContext)) 'P astral/combining/tabs/spaces exact citation with lone CR'
    $unicodeJudgment.assessments[0].evidence[0].excerpt=$unicode.Normalize([Text.NormalizationForm]::FormC)
    Reject {Assert-ReviewGroundingResult $unicodeJudgment $unicodeContext} 'REVIEW_GROUNDING_EXCERPT_MISMATCH'
    WriteUtf8 $report $body
    Reject {New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease -TaskPath (Join-Path ([IO.Path]::GetTempPath()) 'not-readable-secret.md')} 'REVIEW_GROUNDING_UNSAFE_PATH'
    $realReports=Join-Path $root 'controlled-report-storage'
    New-Item -ItemType Directory -Path $realReports|Out-Null
    Copy-Item $report (Join-Path $realReports 'AICO-002.md')
    $reportsDirectory=Split-Path $report -Parent
    Remove-Item -LiteralPath $report
    Remove-Item -LiteralPath $reportsDirectory
    New-Item -ItemType Junction -Path $reportsDirectory -Target $realReports|Out-Null
    try {Reject {New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease} 'REVIEW_GROUNDING_UNSAFE_PATH'}
    finally {[IO.Directory]::Delete($reportsDirectory,$false)}
    Write-Host "PASS review-grounding-evidence: $script:checks assertions"
} finally {
    if($null-ne $lease){Exit-TaskExecutionLock $lease}
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if([IO.Path]::GetFullPath($root).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)-and(Test-Path -LiteralPath $root)){Remove-Item -LiteralPath $root -Recurse -Force}
}
