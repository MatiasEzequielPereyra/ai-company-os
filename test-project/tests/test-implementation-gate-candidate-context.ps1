param()
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot=Join-Path $tempBase ('aico-candidate-gates-'+[guid]::NewGuid().ToString('N'))
$project=Join-Path $tempRoot 'repo'
$candidate=Join-Path $tempRoot 'custom-workspaces[1]/AICO-006'
$savedKey=$env:OPENROUTER_API_KEY
function Write-Text([string]$Path,[string]$Text) { New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null; [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false))) }
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Write-Evidence([string]$Workspace=$candidate) { Write-Text (Join-Path $project 'docs/engineering/writable-evidence/AICO-006.md') ("# Writable Execution Evidence - AICO-006`nOutcome: COMPLETED`nWorktree: $Workspace`nBranch: aico/aico-006`n## Changed Paths`n- src/taskcli/__main__.py`n- src/taskcli/storage.py`n") }
function Invoke-GateCapture([string]$Gate,[bool]$ExpectCapture=$true) {
    $status=switch($Gate){Review{'REVIEW'} QA{'QA'} Security{'SECURITY'}}
    Write-Text (Join-Path $project 'tasks/AICO-006.md') ("# AICO-006`nID: AICO-006`nStatus: $status`nOwner: backend`nWork kind: IMPLEMENTATION`n## Objective`nImplement TaskCLI storage commands.`n")
    $capture=Join-Path $project '.codex/runtime/captured-context.txt'
    if (Test-Path $capture) { Remove-Item -LiteralPath $capture }
    $failed=$false
    try { & (Join-Path $project 'scripts/run-gate-agent.ps1') -Id 'AICO-006' -Gate $Gate -ProjectPath $project -Provider OpenRouter | Out-Null } catch { $failed=$true; $script:lastGateError=$_.Exception.Message }
    Assert-True $failed 'Capture-only fake adapter must stop before lifecycle writes.'
    Assert-True ((Test-Path $capture) -eq $ExpectCapture) ('Unexpected provider capture for '+$Gate)
    Assert-True ((Get-Content (Join-Path $project 'tasks/AICO-006.md') -Raw) -match ('Status: '+$status)) 'Gate fixture lifecycle status must remain unchanged.'
    if ($ExpectCapture) { return Get-Content $capture -Raw }
}
try {
    New-Item -ItemType Directory -Path $project | Out-Null
    foreach($name in @('run-gate-agent.ps1','provider-router.ps1','validate-json-contract.ps1','validate-gate-result-semantics.ps1','write-operational-event.ps1','task-execution-lock.ps1')) { Write-Text (Join-Path $project ('scripts/'+$name)) (Get-Content (Join-Path $repoRoot ('scripts/'+$name)) -Raw) }
    foreach($name in @('review-result.schema.json','qa-gate-result.schema.json','security-gate-result.schema.json')) { Write-Text (Join-Path $project ('schemas/'+$name)) (Get-Content (Join-Path $repoRoot ('schemas/'+$name)) -Raw) }
    Write-Text (Join-Path $project '.codex/writable-policy.json') (Get-Content (Join-Path $repoRoot '.codex/writable-policy.json') -Raw)
    Write-Text (Join-Path $project '.codex/provider-config.json') '{"gate_context_max_chars":22000,"models":{"OpenRouter":"fake"}}'
    Write-Text (Join-Path $project '.codex/agents/backend.md') '# Backend implementation contract'
    Write-Text (Join-Path $project 'docs/engineering/dispatch/AICO-006.md') 'Implement TaskCLI JSON storage commands.'
    Write-Text (Join-Path $project 'docs/engineering/agent-reports/AICO-006.md') '# Implemented add complete remove and JSON persistence.'
    Write-Text (Join-Path $project 'docs/engineering/results/AICO-006-result-001.md') 'Outcome: COMPLETED'
    Write-Text (Join-Path $project 'docs/engineering/reviews/AICO-006-review-001.md') 'Recommendation: APPROVE'
    Write-Text (Join-Path $project 'docs/engineering/qa/AICO-006-qa.md') 'Outcome: PASS'
    Write-Text (Join-Path $project 'scripts/build-agent-context.ps1') 'param($ProjectPath,$Id,$Owner,$MaxChars); "GENERIC_BASELINE_NONAUTHORITATIVE_" * 3000'
    Write-Text (Join-Path $project 'scripts/providers/invoke-openrouter.ps1') @'
param($Prompt,$Context,$SchemaPath,$OutputPath,$Model,$TimeoutSeconds)
[IO.File]::WriteAllText((Join-Path (Split-Path $OutputPath) 'captured-context.txt'),$Context)
throw 'CAPTURE_COMPLETE_NO_PROVIDER_NO_LIFECYCLE'
'@
    $baseline="# BASELINE_UNIQUE_PRIMARY_CHECKOUT`nprint('list only')`n"
    $changed="# CHANGED_UNIQUE_CANDIDATE_IMPLEMENTATION`nfrom .storage import load_tasks`nprint('add complete remove')`n"
    $storage="# STORAGE_UNIQUE_UNTRACKED_IMPLEMENTATION`ndef load_tasks():`n    return []`n"
    Write-Text (Join-Path $project 'src/taskcli/__main__.py') $baseline
    Write-Text (Join-Path $project 'src/taskcli/obsolete.py') '# obsolete implementation'
    & git -C $project init | Out-Null
    & git -C $project config user.email 'aico-test@example.invalid'
    & git -C $project config user.name 'AI Company OS Test'
    & git -C $project config core.autocrlf false
    & git -C $project add .
    & git -C $project commit -m 'Candidate gate fixture baseline' | Out-Null
    & git -C $project worktree add -b aico/aico-006 $candidate HEAD | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Unable to create registered candidate worktree.'}
    Write-Text (Join-Path $candidate 'src/taskcli/__main__.py') $changed
    Write-Text (Join-Path $candidate 'src/taskcli/storage.py') $storage
    Write-Evidence
    $env:OPENROUTER_API_KEY='deterministic-fake-no-network'
    foreach($gate in @('Review','QA','Security')) {
        $capture=Invoke-GateCapture $gate
        Assert-True ($capture.Contains($changed) -and $capture.Contains($storage)) ($gate+' must receive full candidate implementation and untracked storage source.')
        foreach($path in @('src/taskcli/__main__.py','src/taskcli/storage.py')) {
            $hash=(Get-FileHash -LiteralPath (Join-Path $candidate $path) -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert-True ($capture.ToLowerInvariant().Contains($hash)) ($gate+' missing exact candidate source hash '+$path)
        }
        Assert-True ($capture.Length -le 22000) ($gate+' protected candidate envelope exceeded provider budget.')
        Assert-True ($capture.Contains('aico/aico-006')) ($gate+' candidate branch provenance missing.')
        Assert-True ((Get-Content (Join-Path $project 'src/taskcli/__main__.py') -Raw) -ceq $baseline) 'Primary checkout source changed during gate context construction.'
    }
    Remove-Item -LiteralPath (Join-Path $candidate 'src/taskcli/obsolete.py')
    $deleteCapture=Invoke-GateCapture Review
    Assert-True ($deleteCapture.Contains('src/taskcli/obsolete.py') -and $deleteCapture.Contains('Candidate operation: DELETE')) 'Deleted tracked source must be represented explicitly.'
    $policyPath=Join-Path $project '.codex/writable-policy.json'
    $policyText=Get-Content $policyPath -Raw
    try {
        $policy=$policyText | ConvertFrom-Json
        $policy.max_changed_files=1
        Write-Text $policyPath ($policy | ConvertTo-Json -Depth 20)
        Invoke-GateCapture Review $false
        $policy=$policyText | ConvertFrom-Json
        $policy.max_total_write_bytes=1
        Write-Text $policyPath ($policy | ConvertTo-Json -Depth 20)
        Invoke-GateCapture Review $false
    } finally { Write-Text $policyPath $policyText }
    Write-Evidence (Join-Path $tempRoot 'missing-workspace')
    Invoke-GateCapture Review $false
    $unregistered=Join-Path $tempRoot 'unregistered'; New-Item -ItemType Directory -Path $unregistered | Out-Null
    Write-Evidence $unregistered
    Invoke-GateCapture Review $false
    Write-Evidence
    $heldCandidate=Join-Path $tempRoot 'held-candidate'
    $tempPrefix=[IO.Path]::GetFullPath($tempRoot).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    foreach($targetPath in @($candidate,$heldCandidate)) {
        if(-not [IO.Path]::GetFullPath($targetPath).StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Candidate substitution must remain inside disposable fixture.'}
    }
    Move-Item -LiteralPath $candidate -Destination $heldCandidate
    try {
        Invoke-GateCapture Review $false
        New-Item -ItemType Directory -Path $candidate | Out-Null
        & git -C $candidate init | Out-Null
        & git -C $candidate config user.email 'aico-test@example.invalid'
        & git -C $candidate config user.name 'AI Company OS Test'
        & git -C $candidate symbolic-ref HEAD refs/heads/aico/aico-006
        Write-Text (Join-Path $candidate 'src/standalone.py') 'standalone baseline'
        & git -C $candidate add .
        & git -C $candidate commit -m 'Unrelated repository with matching task branch' | Out-Null
        if($LASTEXITCODE -ne 0){throw 'Standalone repository guard fixture must have valid HEAD.'}
        Write-Text (Join-Path $candidate 'src/standalone.py') 'standalone dirty implementation'
        Invoke-GateCapture Review $false
        Assert-True ($script:lastGateError -match 'different Git repository') 'Valid unrelated repository must be rejected specifically for common-directory identity mismatch.'
    } finally {
        $expectedCandidate=[IO.Path]::GetFullPath((Join-Path $tempRoot 'custom-workspaces[1]/AICO-006'))
        if(-not [string]::Equals([IO.Path]::GetFullPath($candidate),$expectedCandidate,[StringComparison]::OrdinalIgnoreCase) -or
            -not [IO.Path]::GetFullPath($heldCandidate).StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe substituted candidate cleanup/restore path.'}
        Remove-Item -LiteralPath $candidate -Recurse -Force
        Move-Item -LiteralPath $heldCandidate -Destination $candidate
    }
    Write-Evidence (Join-Path $candidate '../escaped-workspace')
    Invoke-GateCapture Review $false
    Write-Evidence
    Remove-Item -LiteralPath (Join-Path $project 'docs/engineering/writable-evidence/AICO-006.md')
    Write-Text (Join-Path $project 'docs/engineering/agent-reports/AICO-006.md') 'Declared implementation: docs/engineering/writable-evidence/AICO-006.md'
    Invoke-GateCapture Review $false
    Write-Evidence
    Write-Text (Join-Path $candidate '.env') 'SECRET_CANDIDATE_MUST_NOT_BE_READ'
    Invoke-GateCapture Review $false
    Remove-Item -LiteralPath (Join-Path $candidate '.env')
    Write-Text (Join-Path $candidate 'src/oversized.py') ('X'*750001)
    Invoke-GateCapture Review $false
    Remove-Item -LiteralPath (Join-Path $candidate 'src/oversized.py')
    $outside=Join-Path $tempRoot 'outside'; New-Item -ItemType Directory -Path $outside | Out-Null
    Write-Text (Join-Path $outside 'escape.py') 'OUTSIDE_REPARSE_SOURCE_MUST_NOT_BE_READ'
    $junctionParent=Join-Path $candidate 'src'
    foreach($reparseName in @('reparse-source','reparse[x]')) {
        $junction=Join-Path $junctionParent $reparseName
        New-Item -ItemType Junction -Path $junctionParent -Name $reparseName -Value $outside | Out-Null
        try { Invoke-GateCapture Review $false } finally { [IO.Directory]::Delete($junction) }
    }
    Write-Host 'PASS: registered candidate implementation reaches Review/QA/Security with full sources/hash/provenance; invalid workspace/secret/read-limit fail before inference' -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY=$savedKey
    if(Test-Path $project){try{& git -C $project worktree remove $candidate --force 2>$null | Out-Null}catch{}}
    $resolved=[IO.Path]::GetFullPath($tempRoot)
    if(-not $resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'aico-candidate-gates-*'){throw 'Unsafe candidate test cleanup path.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
