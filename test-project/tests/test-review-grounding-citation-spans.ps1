param([string]$ProjectPath='')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repo 'scripts/task-execution-lock.ps1')
. (Join-Path $repo 'scripts/review-grounding.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "Assertion failed: $Name"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Reason){$caught='';try{& $Action|Out-Null}catch{$caught=$_.Exception.Message};Check ($caught-match $Reason) "expected $Reason; got $caught"}
function Clone($Value){$Value|ConvertTo-Json -Depth 60|ConvertFrom-Json}
function WriteUtf8([string]$Path,[string]$Text){[IO.Directory]::CreateDirectory((Split-Path $Path -Parent))|Out-Null;[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Citation([int]$Start,[int]$End,[string]$Excerpt){[pscustomobject]@{artifact_id='primary-1';start_line=4;end_line=4;excerpt=$Excerpt;byte_start=$Start;byte_end=$End}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('aico-citation-spans-'+[guid]::NewGuid().ToString('N'))
$lease=$null
try{
    WriteUtf8 (Join-Path $root 'tasks/AICO-002.md') "ID: AICO-002`nOwner: cto`nStatus: REVIEW`n`n## Objective`n`nProduce a concrete assigned planning report.`n`n## Acceptance Criteria`n`n- Concrete assigned output.`n"
    WriteUtf8 (Join-Path $root 'docs/engineering/dispatch/AICO-002.md') "Task: AICO-002`nOwner: cto`n"
    Copy-Item (Join-Path $repo '.codex/agents/cto.md') (New-Item -ItemType Directory -Path (Join-Path $root '.codex/agents') -Force).FullName
    WriteUtf8 (Join-Path $root 'docs/engineering/results/AICO-002-result-001.md') "Task: AICO-002`nOwner: cto`n"
    # Construct the incident's exact byte length without importing or modifying acceptance evidence.
    $unicode=[string][char]0x00e9
    $long='BEGIN|'+('a'*1690)+$unicode+'|MID|'+('b'*1667)+'|END|duplicate|duplicate'
    $long=$long+('z'*(3405-[Text.Encoding]::UTF8.GetByteCount($long)))
    Check ([Text.Encoding]::UTF8.GetByteCount($long)-eq 3405) 'long source is exactly 3405 UTF-8 bytes'
    $body="# Agent Report - AICO-002`nOwner: cto`nShort exact evidence.`n$long"
    $report=Join-Path $root 'docs/engineering/agent-reports/AICO-002.md';WriteUtf8 $report $body
    $lease=Enter-TaskExecutionLock -ProjectPath $root -Id AICO-002 -Operation GATE
    $ctx=New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease
    $manifest=Get-ReviewGroundingManifest $ctx
    $good=[pscustomobject]@{contract_version='review-grounding-v1';snapshot_id=$manifest.snapshot_id;recommendation='APPROVE';findings='Deterministic fixture judgment.';verification='Exact captured source.';missing_required_outputs=@();deliverable_defects=@();assessments=@($manifest.obligations|ForEach-Object{[pscustomobject]@{required_output_id=$_.required_output_id;status='SATISFIED';rationale='Test provenance fixture only.';evidence=@([pscustomobject]@{artifact_id='primary-1';start_line=3;end_line=3;excerpt='Short exact evidence.'})}})}
    Check ($null-ne(Assert-ReviewGroundingResult $good $ctx -CheckDrift)) 'legacy short whole line remains accepted'
    $begin=Clone $good;$begin.assessments[0].evidence=@(Citation 0 6 'BEGIN|')
    Check ($null-ne(Assert-ReviewGroundingResult $begin $ctx)) 'long line bounded beginning'
    $middle=Clone $good;$middle.assessments[0].evidence=@(Citation 1696 1703 ($unicode+'|MID|'))
    Check ($null-ne(Assert-ReviewGroundingResult $middle $ctx)) 'long line bounded middle including complete UTF-8 character'
    $end=Clone $good;$end.assessments[0].evidence=@(Citation 3400 3405 $long.Substring($long.Length-5))
    Check ($null-ne(Assert-ReviewGroundingResult $end $ctx)) 'long line bounded end'
    foreach($range in @(@(-1,6),@(0,3406),@(6,0),@(0,0),@('0',6),@(0,6.5))){$bad=Clone $begin;$bad.assessments[0].evidence[0].byte_start=$range[0];$bad.assessments[0].evidence[0].byte_end=$range[1];Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_(LOCATOR|SPAN)'}
    foreach($range in @(@(1697,1703),@(1696,1697))){$bad=Clone $middle;$bad.assessments[0].evidence[0].byte_start=$range[0];$bad.assessments[0].evidence[0].byte_end=$range[1];Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_(UTF8|SPAN|LOCATOR)'}
    $bad=Clone $begin;$bad.assessments[0].evidence[0].excerpt='begin|';Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_EXCERPT_MISMATCH'
    $bad=Clone $begin;$bad.assessments[0].evidence[0].PSObject.Properties.Remove('byte_end');Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_(LOCATOR|SPAN)'
    $bad=Clone $begin;$bad.assessments[0].evidence[0].PSObject.Properties.Remove('byte_start');Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_(LOCATOR|SPAN)'
    $bad=Clone $good;$bad.assessments[0].evidence=@([pscustomobject]@{artifact_id='primary-1';start_line=4;end_line=4;excerpt='BEGIN|'});Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_EXCERPT_MISMATCH'
    $bad=Clone $good;$bad.assessments[0].evidence=@([pscustomobject]@{artifact_id='primary-1';start_line=4;end_line=4;excerpt=$long});Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_LOCATOR_LIMIT'
    foreach($identity in @('primary-2','tasks/AICO-003.md','../outside','https://example.invalid')){$bad=Clone $begin;$bad.assessments[0].evidence[0].artifact_id=$identity;Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_PRIMARY_AUTHORITY'}
    $bad=Clone $begin;$bad.snapshot_id='stale-snapshot';Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_SNAPSHOT_MISMATCH'
    foreach($field in @('relative_path','raw_sha256','normalized_sha256','task_id')){$bad=Clone $begin;$bad.assessments[0].evidence[0]|Add-Member -NotePropertyName $field -NotePropertyValue 'forged';Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_LOCATOR'}
    $first=$long.IndexOf('duplicate',[StringComparison]::Ordinal);$second=$long.IndexOf('duplicate',$first+1,[StringComparison]::Ordinal)
    foreach($position in @($first,$second)){$offset=[Text.Encoding]::UTF8.GetByteCount($long.Substring(0,$position));$duplicate=Clone $good;$duplicate.assessments[0].evidence=@(Citation $offset ($offset+9) 'duplicate');Check ($null-ne(Assert-ReviewGroundingResult $duplicate $ctx)) 'duplicate text accepted at explicit byte position'}
    $bad=Clone $duplicate;$bad.assessments[0].evidence[0].byte_start--; $bad.assessments[0].evidence[0].byte_end--;Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_EXCERPT_MISMATCH'
    $bad=Clone $begin;$bad.assessments=@($bad.assessments|Select-Object -Skip 1);Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_COVERAGE'
    $bad=Clone $begin;$bad.assessments[0].status='UNSATISFIED';Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_APPROVE_CONTRADICTION'
    $bad=Clone $begin;$bad.assessments[0].evidence=@();Reject {Assert-ReviewGroundingResult $bad $ctx} 'REVIEW_GROUNDING_CITATION_REQUIRED'
    Reject {Assert-ReviewGroundingValidation -ProjectPath $root -Id AICO-002 -Lease $lease -Validation ([pscustomobject]@{ValidationId='forged'}) -Recommendation APPROVE} 'REVIEW_GROUNDING_UNTRUSTED_VALIDATION'
    Reject {Assert-ReviewGroundingResult $begin (Clone $ctx)} 'REVIEW_GROUNDING_UNTRUSTED_CONTEXT'
    WriteUtf8 $report ($body+' drift');Reject {Assert-ReviewGroundingResult $begin $ctx -CheckDrift} 'REVIEW_GROUNDING_SOURCE_DRIFT';WriteUtf8 $report $body
    $taskPath=Join-Path $root 'tasks/AICO-002.md';$taskBytes=[IO.File]::ReadAllBytes($taskPath);WriteUtf8 $taskPath ([IO.File]::ReadAllText($taskPath).Replace('AICO-002','AICO-003'));Reject {Assert-ReviewGroundingResult $begin $ctx -CheckDrift} 'REVIEW_GROUNDING_SOURCE_DRIFT';[IO.File]::WriteAllBytes($taskPath,$taskBytes)
    Check ($null-ne(Assert-ReviewGroundingResult $begin $ctx -CheckDrift)) 'exact source and task restoration validates original snapshot'
    # Exercise actual canonical publication and permitted corrective lifecycle on
    # this disposable fixture, never on an acceptance workspace.
    foreach($folder in @('scripts','schemas')){Copy-Item (Join-Path $repo $folder) $root -Recurse -Force}
    $negative=Clone $begin;$negative.recommendation='CHANGES_REQUIRED';$negative.missing_required_outputs=@('Technical implementation plan remains incomplete.');$negative.assessments[1].status='UNSATISFIED';$negative.assessments[1].evidence=@()
    $resultPath=Join-Path $root 'judgment.json';WriteUtf8 $resultPath ($negative|ConvertTo-Json -Depth 60)
    & (Join-Path $root 'scripts/review-task.ps1') -ProjectPath $root -Id AICO-002 -Recommendation CHANGES_REQUIRED -Reviewer regression -TaskExecutionLease $lease -GroundingContext $ctx -ResultPath $resultPath|Out-Null
    $sidecars=@(Get-ChildItem (Join-Path $root 'docs/engineering/reviews') -Filter '*.grounding.json');Check ($sidecars.Count-eq 1) 'canonical publication emits one grounding sidecar'
    $audit=Get-Content -LiteralPath $sidecars[0].FullName -Raw|ConvertFrom-Json;$persisted=$audit.judgment.assessments[0].evidence[0]
    Check ($persisted.byte_start-eq 0-and $persisted.byte_end-eq 6-and $persisted.excerpt-ceq 'BEGIN|') 'exact byte offsets and quote survive publication roundtrip'
    Check ($audit.manifest.snapshot_id-ceq $manifest.snapshot_id-and $audit.manifest.artifacts[0].raw_sha256-ceq $manifest.artifacts[0].raw_sha256) 'published span retains immutable snapshot and raw source identity'
    Check ([IO.File]::ReadAllText($taskPath)-match '(?m)^Status: READY\r?$') 'legitimate grounded CHANGES_REQUIRED returns isolated fixture to READY'
    Write-Host "PASS review-grounding-citation-spans: $script:checks assertions"
}finally{
    if($null-ne $lease){Exit-TaskExecutionLock $lease}
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if([IO.Path]::GetFullPath($root).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)-and(Test-Path -LiteralPath $root)){Remove-Item -LiteralPath $root -Recurse -Force}
}
