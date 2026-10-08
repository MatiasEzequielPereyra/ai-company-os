param()
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts/task-execution-lock.ps1')
$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('aico-project-barrier-'+[guid]::NewGuid().ToString('N'))
$project=Join-Path $tempRoot 'project'
$first=$null;$second=$null;$exclusive=$null;$deniedFile=$null
$install=Join-Path $repoRoot 'scripts/install-existing-project.ps1'
$update=Join-Path $repoRoot 'scripts/update-runtime.ps1'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Snapshot {
    return (@(Get-ChildItem -LiteralPath $project -File -Recurse -Force | Where-Object {$_.FullName -notmatch '[\\/]runtime[\\/]locks[\\/]'} | ForEach-Object {$_.FullName.Substring($project.Length)+':'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} | Sort-Object) -join "`n")
}
function Reject([scriptblock]$Action,[string]$Pattern,[string]$Case){
    $before=Snapshot;$rejected=$false
    try{& $Action|Out-Null}catch{Assert ($_.Exception.Message -match $Pattern) "$Case wrong failure: $($_.Exception.Message)";$rejected=$true}
    Assert $rejected "$Case did not reject."
    Assert ((Snapshot) -ceq $before) "$Case mutated authoritative bytes or created artifacts."
}
function Assert-Exclusive {
    Assert-ProjectExecutionLease -ProjectPath $project -Mode Maintenance -Lease $exclusive
    Reject { $unexpected=Enter-TaskExecutionLock -ProjectPath $project -Id AICO-009 -Operation GATE;Exit-TaskExecutionLock $unexpected } 'task execution cannot start while project maintenance is active' 'maintenance vs new task'
    Reject { $unexpected=Enter-ProjectExecutionLease -ProjectPath $project -Mode Maintenance;Exit-ProjectExecutionLease $unexpected } 'project maintenance cannot run' 'maintenance vs maintenance'
}
function Assert-MaintenanceExcludesTask {
    Reject {$unexpected=Enter-TaskExecutionLock -ProjectPath $project -Id AICO-009 -Operation GATE;Exit-TaskExecutionLock $unexpected} 'task execution cannot start while project maintenance is active' 'updater-owned maintenance vs new task'
    Reject {$unexpected=Enter-ProjectExecutionLease -ProjectPath $project -Mode Maintenance;Exit-ProjectExecutionLease $unexpected} 'project maintenance cannot run' 'updater-owned maintenance vs competitor'
}
try{
    New-Item -ItemType Directory -Path $project -Force|Out-Null
    & $install -TargetProject $project|Out-Null
    $first=Enter-TaskExecutionLock -ProjectPath $project -Id AICO-001 -Operation GATE
    $second=Enter-TaskExecutionLock -ProjectPath $project -Id AICO-002 -Operation ANALYSIS
    Assert-TaskExecutionLease -ProjectPath $project -Id AICO-001 -Lease $first
    Assert-TaskExecutionLease -ProjectPath $project -Id AICO-002 -Lease $second
    Assert (-not [object]::ReferenceEquals($first.ProjectLease.Stream,$second.ProjectLease.Stream)) 'Distinct tasks must have independently live shared project handles.'
    $barrierPath=$first.ProjectLease.Path
    Reject {& $install -TargetProject $project -Force} 'project maintenance cannot run' 'forced install during gate'
    Reject {& $install -TargetProject $project} 'project maintenance cannot run' 'non-force install during gate'
    Reject {& $update -TargetProject $project} 'project maintenance cannot run' 'update during gate'
    foreach($maintenanceScript in @($install,$update)){
        $beforeChild=Snapshot
        $forceArgument=if($maintenanceScript -eq $install){' -Force'}else{''}
        $childCommand="try { & '"+$maintenanceScript.Replace("'","''")+"' -TargetProject '"+$project.Replace("'","''")+"'"+$forceArgument+"; exit 9 } catch { if (`$_.Exception.Message -match 'project maintenance cannot run') { exit 0 }; Write-Error `$_.Exception.Message; exit 8 }"
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $childCommand
        Assert ($LASTEXITCODE -eq 0) 'Independent maintenance process did not fail with barrier contention.'
        Assert ((Snapshot) -ceq $beforeChild) 'Independent maintenance process mutated project.'
    }
    Exit-TaskExecutionLock $first;$first=$null
    Reject {$unexpected=Enter-ProjectExecutionLease -ProjectPath $project -Mode Maintenance;Exit-ProjectExecutionLease $unexpected} 'project maintenance cannot run' 'remaining shared task excludes maintenance'
    Exit-TaskExecutionLock $second;$second=$null
    Assert (Test-Path -LiteralPath $barrierPath) 'Project barrier file was deleted on release.'
    $exclusive=Enter-ProjectExecutionLease -ProjectPath $project -Mode Maintenance
    Assert-Exclusive
    $scope=Enter-ProjectExecutionScope -ProjectPath $project -Mode Maintenance -Lease $exclusive
    Assert (-not $scope.OwnsLock) 'Inherited project scope claims parent ownership.'
    Exit-ProjectExecutionScope $scope
    Assert-Exclusive
    $targetHelper=Join-Path $project 'scripts/task-execution-lock.ps1'
    [IO.File]::WriteAllText($targetHelper,"# old installed helper`n"+(Get-Content -LiteralPath $targetHelper -Raw),[Text.UTF8Encoding]::new($false))
    $originalProjectStream=$exclusive.Stream
    & $update -TargetProject $project -ProjectMaintenanceLease $exclusive|Out-Null
    Assert ([object]::ReferenceEquals($exclusive.Stream,$originalProjectStream)) 'Replacing the installed helper replaced the maintenance handle.'
    Assert ((Get-FileHash -LiteralPath $targetHelper).Hash -eq (Get-FileHash -LiteralPath (Join-Path $repoRoot 'scripts/task-execution-lock.ps1')).Hash) 'Updater did not replace stale installed helper.'
    Assert-Exclusive
    $fake=[pscustomobject]@{Path=$exclusive.Path;Stream=$exclusive.Stream;Mode=$exclusive.Mode}
    Reject {& $update -TargetProject $project -ProjectMaintenanceLease $fake} 'fabricated|registered|another process' 'fabricated maintenance lease'
    $other=Join-Path $tempRoot 'other';New-Item -ItemType Directory -Path $other -Force|Out-Null
    $mismatchRejected=$false
    try{Assert-ProjectExecutionLease -ProjectPath $other -Mode Maintenance -Lease $exclusive}catch{Assert ($_.Exception.Message -match 'identity|invalid|mismatch') 'Wrong-project lease failed for unexpected reason.';$mismatchRejected=$true}
    Assert $mismatchRejected 'Wrong-project maintenance lease accepted.'

    Exit-ProjectExecutionLease -Lease $exclusive;$exclusive=$null
    # Intercept only the controlled fixture's actual apply Copy-Item boundary.
    # All other copies, including rollback, use the real filesystem cmdlet.
    $early=Join-Path $project 'scripts/advance-task.ps1';$late=Join-Path $project 'scripts/provider-router.ps1'
    [IO.File]::WriteAllText($early,"# old early runtime`n"+(Get-Content -LiteralPath $early -Raw),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($late,"# old late runtime`n"+(Get-Content -LiteralPath $late -Raw),[Text.UTF8Encoding]::new($false))
    $beforeRollback=Snapshot
    $auditState=[pscustomobject]@{Apply=$false;Rollback=$false};$failedApply=$false
    $applySource=Join-Path $repoRoot 'scripts/provider-router.ps1'
    function Copy-Item {
        param([string]$Path,[string]$Destination,[switch]$Force,[switch]$Recurse)
        if($Path -eq $applySource -and $Destination -eq $late){
            $auditState.Apply=$true
            Assert ((Get-FileHash -LiteralPath $early).Hash -eq (Get-FileHash -LiteralPath (Join-Path $repoRoot 'scripts/advance-task.ps1')).Hash) 'Failure injection preceded any actual replacement.'
            Assert-MaintenanceExcludesTask
            throw 'Deterministic filesystem failure at updater apply boundary.'
        }
        if($Destination -eq $early -and $Path -ne (Join-Path $repoRoot 'scripts/advance-task.ps1')){
            $auditState.Rollback=$true
            Assert-MaintenanceExcludesTask
        }
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath $Path -Destination $Destination -Force:$Force -Recurse:$Recurse
    }
    try{
        & $update -TargetProject $project|Out-Null
    }catch{
        Assert ($_.Exception.Message -match 'Runtime update failed and changes were rolled back: Deterministic filesystem failure') "Expected actual apply/rollback failure, received: $($_.Exception.Message)"
        $failedApply=$true
    }finally{Remove-Item Function:\Copy-Item}
    Assert $auditState.Apply 'Failure occurred before any actual managed replacement.'
    Assert $auditState.Rollback 'Updater did not enter real backup restoration.'
    Assert $failedApply 'Filesystem denial did not fail updater.'
    Assert ((Snapshot) -ceq $beforeRollback) 'Updater rollback did not restore authoritative target bytes.'
    Assert (Test-Path -LiteralPath $barrierPath) 'Maintenance release deleted persistent barrier.'
    $first=Enter-TaskExecutionLock -ProjectPath $project -Id AICO-001 -Operation FINAL_CHECK
    Exit-TaskExecutionLock $first;$first=$null
    $exclusive=Enter-ProjectExecutionLease -ProjectPath $project -Mode Maintenance
    Exit-ProjectExecutionLease -Lease $exclusive;$exclusive=$null

    # Existing deployment inventory must still carry the same helper filename.
    foreach($scriptName in @('new-project.ps1','install-existing-project.ps1','update-runtime.ps1')){
        Assert ((Get-Content -LiteralPath (Join-Path $repoRoot ('scripts/'+$scriptName)) -Raw).Contains('task-execution-lock.ps1')) "$scriptName omitted execution/barrier helper from deployment."
    }
    Write-Host 'PASS: shared coexistence, install/update contention, exclusive exclusion, inherited leases, filesystem rollback exclusivity, releases and helper delivery.' -ForegroundColor Green
}finally{
    if($null -ne $deniedFile){$deniedFile.Dispose()}
    if($null -ne $first){Exit-TaskExecutionLock $first}
    if($null -ne $second){Exit-TaskExecutionLock $second}
    if($null -ne $exclusive){Exit-ProjectExecutionLease -Lease $exclusive}
    $resolved=[IO.Path]::GetFullPath($tempRoot);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/'))+[IO.Path]::DirectorySeparatorChar
    Assert ($resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) 'Unsafe project fixture cleanup.'
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
