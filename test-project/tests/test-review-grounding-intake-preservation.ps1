param([string]$ProjectPath='')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repo 'scripts/task-execution-lock.ps1')
. (Join-Path $repo 'scripts/review-grounding.ps1')
. (Join-Path $repo 'test-project/helpers/grounded-review-fixture.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "Assertion failed: $Name"};$script:checks++}
function WriteUtf8([string]$Path,[string]$Text){[IO.Directory]::CreateDirectory((Split-Path $Path -Parent))|Out-Null;[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Snapshot([string]$Root){(@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force|Where-Object{$_.FullName-notmatch '[\\/]runtime[\\/]locks[\\/]'}|Sort-Object FullName|ForEach-Object{$_.FullName.Substring($Root.Length)+' '+(Get-FileHash $_.FullName).Hash})-join "`n")}
$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('aico-intake-preservation-'+[guid]::NewGuid().ToString('N'))
$lease=$null;$junction=''
try{
    foreach($case in @('corrective','junction')){
        $root=Join-Path $tempRoot $case
        New-Item -ItemType Directory -Path $root -Force|Out-Null
        foreach($folder in @('scripts','schemas','.codex')){Copy-Item (Join-Path $repo $folder) $root -Recurse -Force}
        Copy-Item (Join-Path $repo 'test-project/fixtures/review-grounding-incident/task.md') (New-Item -ItemType Directory -Path (Join-Path $root 'tasks') -Force).FullName
        Move-Item -LiteralPath (Join-Path $root 'tasks/task.md') -Destination (Join-Path $root 'tasks/AICO-002.md')
        WriteUtf8 (Join-Path $root 'docs/engineering/dispatch/AICO-002.md') "Task: AICO-002`nOwner: cto`n"
        WriteUtf8 (Join-Path $root 'docs/engineering/results/AICO-002-result-001.md') "Task: AICO-002`nOwner: cto`nOutcome: COMPLETED`n"
        Initialize-GroundedReviewFixture -Root $root -Id AICO-002 -CreateReport
        $lease=Enter-TaskExecutionLock -ProjectPath $root -Id AICO-002 -Operation GATE
        $context=New-ReviewGroundingContext -ProjectPath $root -Id AICO-002 -Lease $lease
        $manifest=Get-ReviewGroundingManifest $context
        $planId=$manifest.obligations[1].required_output_id
        $judgment=New-GroundedFixtureJudgment -Context $context -Recommendation CHANGES_REQUIRED -UnsatisfiedOutputIds @($planId) -Findings 'Changes required; see structured assessment.' -Verification 'Exact primary snapshot checked.'
        $missing='MISSING_SENTINEL: provide ordered implementation steps and rollback checkpoints.'
        $defect='DEFECT_SENTINEL: data contract leaves the ID allocation policy contradictory.'
        $rationale='RATIONALE_SENTINEL: no executable migration sequence is supplied for the assigned storage change.'
        $judgment.missing_required_outputs=@($missing);$judgment.deliverable_defects=@($defect)
        ($judgment.assessments|Where-Object required_output_id -eq $planId).rationale=$rationale
        $json=Join-Path $root 'judgment.json';WriteUtf8 $json ($judgment|ConvertTo-Json -Depth 60)
        if($case-eq 'junction'){
            $outside=Join-Path $tempRoot 'outside-destination';New-Item -ItemType Directory -Path $outside -Force|Out-Null
            WriteUtf8 (Join-Path $outside 'sentinel.txt') 'Outside content must be unchanged.'
            $outsideBefore=Snapshot $outside;$projectBefore=Snapshot $root
            $junction=Join-Path $root 'docs/engineering/reviews'
            New-Item -ItemType Junction -Path $junction -Target $outside|Out-Null
            $errorText=''
            try{& (Join-Path $root 'scripts/review-task.ps1') -ProjectPath $root -Id AICO-002 -Recommendation CHANGES_REQUIRED -Reviewer regression -TaskExecutionLease $lease -GroundingContext $context -ResultPath $json|Out-Null}catch{$errorText=$_.Exception.Message}
            Check ($errorText-match 'REVIEW_DESTINATION_UNSAFE.*reparse point') 'destination junction rejected with exact stage/reason'
            Check ((Snapshot $outside)-ceq $outsideBefore) 'no outside write or artifact'
            [IO.Directory]::Delete($junction,$false);$junction=''
            Check ((Snapshot $root)-ceq $projectBefore) 'rejected intake preserves all project bytes and creates no artifact'
            Check ((Get-Content (Join-Path $root 'tasks/AICO-002.md') -Raw)-match '(?m)^Status: REVIEW\s*$') 'rejected destination cannot transition task'
            Assert-TaskExecutionLease -ProjectPath $root -Id AICO-002 -Lease $lease -Operation GATE
            Check ($lease.Stream.CanRead -and $lease.ProjectLease.Stream.CanRead) 'rejection retains inherited live ownership'
        }else{
            & (Join-Path $root 'scripts/review-task.ps1') -ProjectPath $root -Id AICO-002 -Recommendation CHANGES_REQUIRED -Reviewer regression -TaskExecutionLease $lease -GroundingContext $context -ResultPath $json|Out-Null
            $review=Get-Content (Join-Path $root 'docs/engineering/reviews/AICO-002-review-001.md') -Raw -Encoding UTF8
            $corrective=& (Join-Path $root 'scripts/build-corrective-analysis-context.ps1') -ProjectPath $root -Id AICO-002 -Owner cto
            foreach($value in @($missing,$defect,$rationale,'Technical implementation plan.',$planId)){
                Check ($review.Contains($value)) 'structured concrete detail survives actual canonical Markdown intake'
                Check ([string]$corrective -and ([string]$corrective).Contains($value)) 'structured detail survives corrective context building'
            }
            Check ($review.Contains('### missing_required_outputs') -and $review.Contains('### deliverable_defects') -and $review.Contains('### UNSATISFIED ')) 'canonical findings retain explicit structured groups'
            Check ((Get-Content (Join-Path $root 'tasks/AICO-002.md') -Raw)-match '(?m)^Status: READY\s*$') 'actual valid CR transitions READY'
            Check (([string]$corrective).Contains('CORRECTIVE FINDINGS')) 'corrective intake contains authoritative findings frame'
        }
        Exit-TaskExecutionLock $lease;$lease=$null
    }
    Write-Host "PASS review-grounding-intake-preservation: $script:checks assertions"
}finally{
    if($junction -and [IO.Directory]::Exists($junction)){[IO.Directory]::Delete($junction,$false)}
    if($null-ne $lease){Exit-TaskExecutionLock $lease}
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if([IO.Path]::GetFullPath($tempRoot).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)-and(Test-Path -LiteralPath $tempRoot)){Remove-Item -LiteralPath $tempRoot -Recurse -Force}
}
