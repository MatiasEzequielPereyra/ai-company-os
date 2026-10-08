param([string]$ProjectPath='')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repo 'scripts/task-execution-lock.ps1')
. (Join-Path $repo 'scripts/review-grounding.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "Assertion failed: $Name"};$script:checks++}
function WriteUtf8([string]$Path,[string]$Text){[IO.Directory]::CreateDirectory((Split-Path $Path -Parent))|Out-Null;[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Reject([scriptblock]$Action,[string]$Reason){$message='';try{& $Action|Out-Null}catch{$message=$_.Exception.Message};Check ($message-match[regex]::Escape($Reason)) "expected $Reason; got $message"}
$root=Join-Path ([IO.Path]::GetTempPath()) ('aico-grounded-planning-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $root|Out-Null
    Copy-Item (Join-Path $repo 'scripts') $root -Recurse
    Copy-Item (Join-Path $repo '.codex') $root -Recurse
    New-Item -ItemType Directory -Path (Join-Path $root 'tasks')|Out-Null
    WriteUtf8 (Join-Path $root 'docs/engineering/work-requests/WR-001.md') "Type: FEATURE`nPriority: P1`n`n## Objective`n`nAdd isolated persistent task storage.`n"
    WriteUtf8 (Join-Path $root 'docs/engineering/plans/WR-001-plan.md') "## Required Roles`n`n- qa`n- security`n- devops`n"
    & (Join-Path $root 'scripts/materialize-plan-tasks.ps1') -WorkRequestId WR-001 -ProjectPath $root|Out-Null
    $prefix=@{qa='Define functional, regression and release validation required for: ';security='Review applicable security boundaries, data handling and release risks for: ';devops='Review build, deployment, observability and rollback readiness for: '}
    $tasks=@(Get-ChildItem (Join-Path $root 'tasks') -Filter '*.md')
    Check ($tasks.Count-eq 3) 'WXY real materializer creates three known planning roles'
    foreach($task in $tasks){
        $text=Get-ReviewNormalizedText ([IO.File]::ReadAllBytes($task.FullName));$owner=[regex]::Match($text,'(?m)^Owner: (.+)$').Groups[1].Value;$id=$task.BaseName
        $decl=@(Get-ReviewDeclarations -Text $text -Section 'Acceptance Criteria' -SourceKind task-acceptance -RelativePath "tasks/$id.md")
        Check ($decl.Count-eq 5) "$owner ordinary criterion plus four preserved generic criteria"
        Check ($decl[0].declaration-ceq($prefix[$owner]+'Add isolated persistent task storage.')) "$owner literal engine roleObjective criterion"
        # Isolated preparation fixture: simulate owner submission after checking
        # actual generated BACKLOG declarations; no historical task is touched.
        $text=$text.Replace('Status: BACKLOG','Status: REVIEW')
        WriteUtf8 $task.FullName $text
        WriteUtf8 (Join-Path $root "docs/engineering/dispatch/$id.md") "Task: $id`nOwner: $owner`n"
        WriteUtf8 (Join-Path $root "docs/engineering/results/$id-result-001.md") "Task: $id`nOwner: $owner`n"
        WriteUtf8 (Join-Path $root "docs/engineering/agent-reports/$id.md") "# Agent Report - $id`nOwner: $owner`nConcrete assigned planning report.`n"
        $lease=Enter-TaskExecutionLock -ProjectPath $root -Id $id -Operation GATE
        try{
            $ctx=New-ReviewGroundingContext -ProjectPath $root -Id $id -Lease $lease
            $manifest=Get-ReviewGroundingManifest $ctx
            Check (@($manifest.obligations|Where-Object source_kind -eq 'role-output').Count-eq 0) "$owner has no invented role Output"
            Check ($manifest.obligations[0].required_output_id.StartsWith('v1/task-acceptance/')) "$owner ordinary frozen task identity"
            WriteUtf8 $task.FullName ($text.Replace("- [ ] $($decl[0].declaration)`n",''))
            Reject {New-ReviewGroundingContext -ProjectPath $root -Id $id -Lease $lease} 'OBLIGATION_SOURCE_NOT_CONCRETE'
        }finally{Exit-TaskExecutionLock $lease}
    }
    WriteUtf8 (Join-Path $root 'docs/engineering/work-requests/WR-002.md') "Type: FEATURE`nPriority: P1`n`n## Objective`n`nConcrete second objective.`n"
    WriteUtf8 (Join-Path $root 'docs/engineering/plans/WR-002-plan.md') "## Required Roles`n`n- qa`n- backend`n"
    $before=@(Get-ChildItem (Join-Path $root 'tasks') -File|ForEach-Object{[pscustomobject]@{Name=$_.Name;Hash=(Get-FileHash $_.FullName).Hash}})
    Reject {& (Join-Path $root 'scripts/materialize-plan-tasks.ps1') -WorkRequestId WR-002 -ProjectPath $root} 'OBLIGATION_SOURCE_NOT_CONCRETE'
    Check (@(Get-ChildItem (Join-Path $root 'tasks') -File).Count-eq $before.Count) 'Z unknown role causes no partial task batch'
    foreach($entry in $before){Check ((Get-FileHash (Join-Path $root ('tasks/'+$entry.Name))).Hash-ceq $entry.Hash) 'unknown batch preserves every prior task byte'}
    Check (-not(Test-Path (Join-Path $root 'docs/engineering/plans/WR-002-tasks.md'))) 'unknown batch creates no derived mapping'
    Write-Host "PASS review-grounding-materialization: $script:checks assertions"
}finally{
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if([IO.Path]::GetFullPath($root).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)-and(Test-Path -LiteralPath $root)){Remove-Item -LiteralPath $root -Recurse -Force}
}
