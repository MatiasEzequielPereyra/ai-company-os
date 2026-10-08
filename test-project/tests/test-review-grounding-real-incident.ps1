param([string]$ProjectPath='')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$assets=Join-Path $repo 'test-project/fixtures/review-grounding-incident'
. (Join-Path $repo 'scripts/task-execution-lock.ps1')
. (Join-Path $repo 'scripts/review-grounding.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "Assertion failed: $Name"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Reason){$errorText='';try{& $Action|Out-Null}catch{$errorText=$_.Exception.Message};Check ($errorText -match [regex]::Escape($Reason)) "expected $Reason; got $errorText"}
$root=Join-Path ([IO.Path]::GetTempPath()) ('aico-real-incident-'+[guid]::NewGuid().ToString('N'))
$lease=$null
try{
    New-Item -ItemType Directory -Path $root|Out-Null
    foreach($folder in @('scripts','schemas','.codex')){Copy-Item (Join-Path $repo $folder) $root -Recurse -Force}
    foreach($folder in @('tasks','docs/engineering/dispatch','docs/engineering/agent-reports','docs/engineering/results','docs/engineering/reviews')){New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force|Out-Null}
    foreach($pair in @(@('task.md','tasks/AICO-002.md'),@('primary-report.md','docs/engineering/agent-reports/AICO-002.md'),@('secondary-result.md','docs/engineering/results/AICO-002-result-002.md'),@('cto-role.md','.codex/agents/cto.md'))){Copy-Item (Join-Path $assets $pair[0]) (Join-Path $root $pair[1]) -Force}
    [IO.File]::WriteAllText((Join-Path $root 'docs/engineering/dispatch/AICO-002.md'),"Task: AICO-002`nOwner: cto`n",(New-Object Text.UTF8Encoding($false)))
    $provenance=Get-Content (Join-Path $assets 'provenance.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($entry in $provenance.entries){Check ((Get-FileHash (Join-Path $assets $entry.sanitized_file)).Hash.ToLowerInvariant()-ceq $entry.sanitized_sha256) ('immutable fixture hash '+$entry.sanitized_file)}
    $taskPath=Join-Path $root 'tasks/AICO-002.md';$before=[IO.File]::ReadAllBytes($taskPath)
    $lease=Enter-TaskExecutionLock -ProjectPath $root -Id AICO-002 -Operation GATE
    $ctx=New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease
    $manifest=Get-ReviewGroundingManifest $ctx
    $legacy=Get-Content (Join-Path $assets 'legacy-approval.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Reject {Assert-ReviewGroundingResult -Result $legacy -Context $ctx} 'REVIEW_GROUNDING_SNAPSHOT_MISMATCH'
    $legacyPath=Join-Path $root 'legacy.json';[IO.File]::WriteAllText($legacyPath,($legacy|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))
    Reject {& (Join-Path $root 'scripts/review-task.ps1') -ProjectPath $root -Id AICO-002 -Recommendation APPROVE -Reviewer regression -TaskExecutionLease $lease -GroundingContext $ctx -ResultPath $legacyPath} 'contract_version'
    Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($taskPath))-ceq [Convert]::ToBase64String($before)) 'legacy false approval cannot mutate task'
    Check (@(Get-ChildItem (Join-Path $root 'docs/engineering/reviews') -File).Count-eq 0) 'no canonical approval or grounding sidecar'
    $adapted=[pscustomobject]@{contract_version='review-grounding-v1';snapshot_id=$manifest.snapshot_id;recommendation='APPROVE';findings=$legacy.findings;verification=$legacy.verification;missing_required_outputs=@();deliverable_defects=@();assessments=@($manifest.obligations|ForEach-Object{[pscustomobject]@{required_output_id=$_.required_output_id;status='SATISFIED';rationale='False completeness from result.';evidence=@([pscustomobject]@{artifact_id='secondary-result';start_line=1;end_line=1;excerpt='# Task Result - AICO-002'})}})}
    Reject {Assert-ReviewGroundingResult $adapted $ctx} 'REVIEW_GROUNDING_PRIMARY_AUTHORITY'
    $negative=$adapted|ConvertTo-Json -Depth 40|ConvertFrom-Json
    $negative.recommendation='CHANGES_REQUIRED';$negative.findings='Actual report ends inside the unfinished Data Contract JSON; no implementation plan, risks or migration strategy follows.';$negative.verification='Reviewed immutable actual primary report, not result self-attestation.';$negative.missing_required_outputs=@('Technical implementation plan is absent.','API/data contract is unfinished.','Risks and migration strategy are absent.');$negative.deliverable_defects=@('Data Contract JSON fence and object are unfinished.')
    foreach($row in $negative.assessments){$row.status='UNSATISFIED';$row.rationale='Captured truncated report does not substantiate complete assigned deliverable.';$row.evidence=@()}
    Check ($null-ne(Assert-ReviewGroundingResult $negative $ctx -CheckDrift)) 'truthful negative accepted without invented quotes'
    $jsonPath=Join-Path $root 'negative.json';[IO.File]::WriteAllText($jsonPath,($negative|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))
    $stream=$lease.Stream;$projectStream=$lease.ProjectLease.Stream
    & (Join-Path $root 'scripts/review-task.ps1') -ProjectPath $root -Id AICO-002 -Recommendation CHANGES_REQUIRED -Reviewer regression -TaskExecutionLease $lease -GroundingContext $ctx -ResultPath $jsonPath|Out-Null
    Check ((Get-Content $taskPath -Raw)-match '(?m)^Status: READY\s*$') 'truthful changes uses real REVIEW to READY transition'
    Check ([object]::ReferenceEquals($lease.Stream,$stream)-and[object]::ReferenceEquals($lease.ProjectLease.Stream,$projectStream)) 'nested review/update/advance retain both exact live handles'
    Assert-TaskExecutionLease -ProjectPath $root -Id AICO-002 -Lease $lease -Operation GATE
    Check (@(Get-ChildItem (Join-Path $root 'docs/engineering/reviews') -Filter '*.md').Count-eq 1) 'one valid canonical negative review'
    Check (@(Get-ChildItem (Join-Path $root 'docs/engineering/reviews') -Filter '*.grounding.json').Count-eq 1) 'validated grounded sidecar retained'
    Write-Host "PASS review-grounding-real-incident: $script:checks assertions"
} finally {
    if($null-ne $lease){Exit-TaskExecutionLock $lease}
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if([IO.Path]::GetFullPath($root).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)-and(Test-Path -LiteralPath $root)){Remove-Item -LiteralPath $root -Recurse -Force}
}
