param()
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts/task-execution-lock.ps1')
$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('aico-writer-lock-'+[guid]::NewGuid().ToString('N'))
$held=$null
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Snapshot([string]$Root){
    $lines=@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Where-Object {$_.FullName -notmatch '[\\/]runtime[\\/]locks[\\/]'} | ForEach-Object { $_.FullName.Substring($Root.Length)+':'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } | Sort-Object)
    return ($lines -join "`n")
}
function Reject-Unchanged([scriptblock]$Action,[string]$Expected,[string]$Case){
    $before=Snapshot $tempRoot;$rejected=$false
    try{& $Action|Out-Null}catch{Assert ($_.Exception.Message -match $Expected) "$Case rejected for unexpected reason: $($_.Exception.Message)";$rejected=$true}
    Assert $rejected "$Case unexpectedly succeeded."
    Assert ((Snapshot $tempRoot) -ceq $before) "$Case changed task bytes or created artifacts."
}
function Assert-StillExclusive([object]$Lease){
    Assert-TaskExecutionLease -ProjectPath $tempRoot -Id AICO-001 -Lease $Lease
    $blocked=$false
    try{$unexpected=Enter-TaskExecutionLock -ProjectPath $tempRoot -Id AICO-001 -Operation COMPETING;Exit-TaskExecutionLock $unexpected}catch{Assert ($_.Exception.Message -match 'already has an AI Company OS execution') 'Exclusive check failed for another reason.';$blocked=$true}
    Assert $blocked 'Inherited writer released parent lock.'
}
try{
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'tasks') -Force|Out-Null
    Copy-Item (Join-Path $repoRoot 'scripts') $tempRoot -Recurse
    Copy-Item (Join-Path $repoRoot 'schemas') $tempRoot -Recurse
    Copy-Item (Join-Path $repoRoot '.codex') $tempRoot -Recurse
    $task=Join-Path $tempRoot 'tasks/AICO-001.md'
    [IO.File]::WriteAllText($task,@'
# AICO-001 - writer lock fixture
ID: AICO-001
Status: REVIEW
Owner: backend
Priority: P1
Workflow profile: standard
Workflow phase: CODE_REVIEW
Review: APPROVE

## Objective

Preserve task under competing writers.

---

## Acceptance Criteria

- [ ] Evidence remains unchanged.

---

## Dependencies

-

---

## Evidence

-

---

## Notes

-

---

## Transition Log

- Fixture.
'@,[Text.UTF8Encoding]::new($false))
    $update=Join-Path $tempRoot 'scripts/update-task.ps1';$advance=Join-Path $tempRoot 'scripts/advance-task.ps1';$review=Join-Path $tempRoot 'scripts/review-task.ps1';$tasks=Join-Path $tempRoot 'tasks'
    $held=Enter-TaskExecutionLock -ProjectPath $tempRoot -Id AICO-001 -Operation GATE
    Assert ([string]::Equals($held.Path,[IO.Path]::GetFullPath($held.Path),(Get-ExecutionPathComparison))) 'Live task path retained a Windows TEMP short alias instead of its registered canonical identity.'
    Assert-TaskExecutionLease -ProjectPath ([IO.Path]::GetFullPath($tempRoot)) -Id AICO-001 -Lease $held
    Reject-Unchanged {& $update -Id AICO-001 -TasksPath $tasks -Owner cto -Note 'must not write'} 'already has an AI Company OS execution' 'update contention'
    Reject-Unchanged {& $advance -Id AICO-001 -TasksPath $tasks -Status QA} 'already has an AI Company OS execution' 'advance contention'
    Reject-Unchanged {& $review -Id AICO-001 -ProjectPath $tempRoot -Recommendation APPROVE -Reviewer fixture} 'already has an AI Company OS execution' 'review contention'
    $originalStream=$held.Stream
    & $update -Id AICO-001 -TasksPath $tasks -Note 'authorized nested update' -TaskExecutionLease $held|Out-Null
    Assert ([object]::ReferenceEquals($held.Stream,$originalStream)) 'Nested update replaced the parent stream.'
    Assert ((Get-Content -LiteralPath $task -Raw).Contains('authorized nested update')) 'Nested update did not mutate authorized notes.'
    Assert-StillExclusive $held
    $scope=Enter-TaskExecutionScope -ProjectPath $tempRoot -Id AICO-001 -Operation NESTED -Lease $held
    Assert (-not $scope.OwnsLock) 'Inherited scope claims parent ownership.'
    Exit-TaskExecutionScope $scope
    Assert-StillExclusive $held
    $fake=[pscustomobject]@{Path=$held.Path;Stream=$held.Stream;TaskId=$held.TaskId;Operation=$held.Operation}
    Reject-Unchanged {& $update -Id AICO-001 -TasksPath $tasks -Note forged -TaskExecutionLease $fake} 'fabricated, expired or belongs' 'fabricated lease'
    Reject-Unchanged {& $update -Id AICO-002 -TasksPath $tasks -Note mismatch -TaskExecutionLease $held} 'identity or live exclusive handle is invalid' 'wrong task lease'
    $other=Join-Path $tempRoot 'other-project';New-Item -ItemType Directory -Path (Join-Path $other 'tasks') -Force|Out-Null
    Reject-Unchanged {& $update -Id AICO-001 -TasksPath (Join-Path $other 'tasks') -Note mismatch -TaskExecutionLease $held} 'identity or live (exclusive )?handle is invalid' 'wrong project lease'
    Assert-StillExclusive $held
    $expired=$held;Exit-TaskExecutionLock $held;$held=$null
    Reject-Unchanged {& $update -Id AICO-001 -TasksPath $tasks -Note expired -TaskExecutionLease $expired} 'fabricated, expired or belongs' 'expired lease'
    Reject-Unchanged {& $review -Id AICO-001 -ProjectPath $tempRoot -Recommendation APPROVE -Reviewer fixture -Findings NONE -Verification 'scalar text'} 'REVIEW_GROUNDING_REQUIRED' 'scalar review bypass'
    $reviewDir=Join-Path $tempRoot 'docs/engineering/reviews';New-Item -ItemType Directory -Path $reviewDir -Force|Out-Null
    [IO.File]::WriteAllText((Join-Path $reviewDir 'AICO-001-review-legacy.md'),"Recommendation: APPROVE`nReviewer: legacy`n",[Text.UTF8Encoding]::new($false))
    Reject-Unchanged {& $advance -Id AICO-001 -TasksPath $tasks -Status QA} 'registered process-local grounded receipt' 'legacy review artifact bypass'
    Reject-Unchanged {& $advance -Id AICO-001 -TasksPath $tasks -Status READY -ReviewIntakeReceipt ([pscustomobject]@{Recommendation='CHANGES_REQUIRED'})} 'registered process-local grounded receipt' 'forged corrective receipt bypass'
    $released=Enter-TaskExecutionLock -ProjectPath $tempRoot -Id AICO-001 -Operation FINAL_CHECK;Exit-TaskExecutionLock $released
    Write-Host 'PASS: writer contention, immutable rejection, inherited ownership, fabricated/mismatched/expired leases and legacy/scalar review bypass.' -ForegroundColor Green
}finally{
    if($null -ne $held){Exit-TaskExecutionLock $held}
    $resolved=[IO.Path]::GetFullPath($tempRoot);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/'))+[IO.Path]::DirectorySeparatorChar
    Assert ($resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) 'Unsafe fixture cleanup.'
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
