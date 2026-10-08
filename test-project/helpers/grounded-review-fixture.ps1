# Test-only builders. These invoke the real grounding and intake boundaries;
# they never replace or mock production validation.
$script:GroundedFixtureRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function Initialize-GroundedReviewFixture {
    param([string]$Root,[string]$Id,[switch]$CreateReport)
    foreach($directory in @('scripts','schemas','.codex/agents','docs/engineering/agent-reports')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Root $directory) | Out-Null
    }
    foreach($name in @('task-execution-lock.ps1','review-grounding.ps1','validate-json-contract.ps1','review-task.ps1','update-task.ps1','advance-task.ps1')) {
        Copy-Item (Join-Path $script:GroundedFixtureRepoRoot ('scripts/'+$name)) (Join-Path $Root ('scripts/'+$name)) -Force
    }
    Copy-Item (Join-Path $script:GroundedFixtureRepoRoot 'schemas/review-result.schema.json') (Join-Path $Root 'schemas/review-result.schema.json') -Force
    $taskPath=Join-Path $Root "tasks/$Id.md"
    if(-not(Test-Path -LiteralPath $taskPath)){return}
    $task=Get-Content -LiteralPath $taskPath -Raw -Encoding UTF8
    $owner=[regex]::Match($task,'(?m)^Owner:\s*([^\r\n]+)').Groups[1].Value.Trim()
    $rolePath=Join-Path $Root ".codex/agents/$owner.md"
    if(-not(Test-Path -LiteralPath $rolePath)) {
        Copy-Item (Join-Path $script:GroundedFixtureRepoRoot ".codex/agents/$owner.md") $rolePath -Force
    }
    $reportPath=Join-Path $Root "docs/engineering/agent-reports/$Id.md"
    if($CreateReport -and -not(Test-Path -LiteralPath $reportPath)) {
        # A small explicit lifecycle fixture deliverable; no production task or
        # previously submitted owner report is rewritten by this builder.
        $body=@(
            "# Agent Report - $Id", "Owner: $owner", '',
            'Architecture proposal: use the existing isolated fixture component; no product writes are required.',
            'Technical implementation plan: inspect source, execute its local check, then hand off the recorded result.',
            'Component boundaries and API/data contracts: the fixture component exposes only the locally verified function; caller owns lifecycle intake.',
            'Risks and migration strategy: no deployed data migration; retain the original fixture source on failure.',
            'ADR: retain the existing standard-library implementation to avoid an unnecessary new dependency.',
            'Product requirements, user stories and acceptance criteria: complete the requested isolated verification; report exact output.',
            'Scope and non-goals: fixture verification only; no network, release, deployment or historical edits.',
            'Engineering plan, executable task set and dependency graph: assigned task precedes its dependent handoff; dependency readiness uses canonical DONE.',
            'Assignments, handoffs, lifecycle state and delivery status: the assigned owner submitted verified work; gate controls the next transition.',
            'Open questions and blockers: NONE. Product risks: isolated fixture only. Blocker escalation: NONE.',
            'Verification: the result artifact records the actual fixture check; applicable downstream work waits for its canonical gate.'
        ) -join "`n"
        [IO.File]::WriteAllText($reportPath,$body,[Text.UTF8Encoding]::new($false))
    }
}
function New-GroundedFixtureJudgment {
    param([object]$Context,[ValidateSet('APPROVE','CHANGES_REQUIRED')][string]$Recommendation='APPROVE',
          [string[]]$UnsatisfiedOutputIds=@(),[string]$Findings='Fixture deliverable verified.',[string]$Verification='Inspected actual immutable fixture snapshot.')
    $manifest=Get-ReviewGroundingManifest -Context $Context
    $prompt=Get-ReviewGroundingPrompt -Context $Context
    $primary=@($manifest.artifacts)[0]
    $pattern='(?ms)^Artifact: '+[regex]::Escape([string]$primary.artifact_id)+';[^\r\n]*\r?\n(.*?)(?=^Artifact: |^===== LATEST TASK RESULT =====|\z)'
    $capture=[regex]::Match($prompt,$pattern)
    if(-not $capture.Success){throw 'Fixture primary snapshot frame missing.'}
    $lines=@($capture.Groups[1].Value -split '\r?\n' | Where-Object {$_ -match '^\d+\|'} | ForEach-Object {$_ -replace '^\d+\|',''})
    $end=[Math]::Min(16,$lines.Count)
    # Choose a bounded exact block from the captured source, never result claims.
    while($end -gt 0 -and [Text.Encoding]::UTF8.GetByteCount(($lines[0..($end-1)] -join "`n")) -gt 2048){$end--}
    if($end -lt 1){throw 'Fixture primary line exceeds quote limit.'}
    $quote=$lines[0..($end-1)] -join "`n"
    if($Recommendation -eq 'CHANGES_REQUIRED' -and -not $UnsatisfiedOutputIds.Count) {
        $UnsatisfiedOutputIds=@([string]@($manifest.obligations)[0].required_output_id)
    }
    $rows=@(foreach($obligation in $manifest.obligations) {
        $negative=$UnsatisfiedOutputIds -ccontains [string]$obligation.required_output_id
        [ordered]@{
            required_output_id=[string]$obligation.required_output_id
            status=$(if($negative){'UNSATISFIED'}else{'SATISFIED'})
            rationale=$(if($negative){$Findings}else{'The captured fixture primary source records the scoped deliverable and verification.'})
            evidence=@(if(-not $negative){[ordered]@{artifact_id=[string]$primary.artifact_id;start_line=1;end_line=$end;excerpt=$quote}})
        }
    })
    return [ordered]@{
        contract_version='review-grounding-v1';snapshot_id=[string]$manifest.snapshot_id
        recommendation=$Recommendation;findings=$Findings;verification=$Verification
        missing_required_outputs=@(if($Recommendation -eq 'CHANGES_REQUIRED'){$Findings})
        deliverable_defects=@();assessments=$rows
    }
}
function Invoke-GroundedFixtureReview {
    param([string]$ProjectPath,[string]$Id,[string]$Recommendation='APPROVE',[string]$Reviewer='reviewer',
          [string]$Findings='Fixture delivery complete.',[string]$Verification='Fixture primary evidence inspected.')
    Initialize-GroundedReviewFixture -Root $ProjectPath -Id $Id -CreateReport
    . (Join-Path $ProjectPath 'scripts/task-execution-lock.ps1')
    . (Join-Path $ProjectPath 'scripts/review-grounding.ps1')
    $lease=Enter-TaskExecutionLock -ProjectPath $ProjectPath -Id $Id -Operation GATE
    try {
        $context=New-ReviewGroundingContext -ProjectPath $ProjectPath -Id $Id -Lease $lease
        $result=New-GroundedFixtureJudgment -Context $context -Recommendation $Recommendation -Findings $Findings -Verification $Verification
        $path=Join-Path $ProjectPath ('grounded-review-'+[Guid]::NewGuid().ToString('N')+'.json')
        [IO.File]::WriteAllText($path,($result|ConvertTo-Json -Depth 40),[Text.UTF8Encoding]::new($false))
        try {
            & (Join-Path $ProjectPath 'scripts/review-task.ps1') -ProjectPath $ProjectPath -Id $Id -Recommendation $Recommendation -Reviewer $Reviewer -TaskExecutionLease $lease -ResultPath $path -GroundingContext $context
        } finally { Remove-Item -LiteralPath $path -Force }
    } finally { Exit-TaskExecutionLock -Lock $lease }
}
function New-GroundedRouterFixture {
    param([string]$Root)
    $id='AICO-001'
    foreach($dir in @('tasks','docs/engineering/results','docs/engineering/dispatch')) {New-Item -ItemType Directory -Force -Path (Join-Path $Root $dir)|Out-Null}
    [IO.File]::WriteAllText((Join-Path $Root 'tasks/AICO-001.md'),"# Task`nID: AICO-001`nOwner: cto`nStatus: REVIEW`nWork kind: PLANNING`n## Acceptance Criteria`n- [ ] The isolated fixture architecture and verification are recorded.",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $Root 'docs/engineering/results/AICO-001-result-001.md'),"Task: AICO-001`nOwner: cto`nOutcome: COMPLETED`nSummary: Isolated fixture verified.",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $Root 'docs/engineering/dispatch/AICO-001.md'),"Task: AICO-001`nOwner: cto`nScope: Isolated fixture verification.",[Text.UTF8Encoding]::new($false))
    Initialize-GroundedReviewFixture -Root $Root -Id $id -CreateReport
    . (Join-Path $Root 'scripts/task-execution-lock.ps1')
    . (Join-Path $Root 'scripts/review-grounding.ps1')
    $lease=Enter-TaskExecutionLock -ProjectPath $Root -Id $id -Operation GATE
    try {
        $context=New-ReviewGroundingContext -ProjectPath $Root -Id $id -Lease $lease
        $result=New-GroundedFixtureJudgment -Context $context
        [IO.File]::WriteAllText((Join-Path $Root 'fixture-grounded-review.json'),($result|ConvertTo-Json -Depth 40),[Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{Lease=$lease;Context=$context}
    } catch {Exit-TaskExecutionLock -Lock $lease;throw}
}
