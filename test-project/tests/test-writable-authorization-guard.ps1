param()

$ErrorActionPreference = "Stop"

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "SKIP: git is unavailable; writable authorization guard test requires Git." -ForegroundColor Yellow
    exit 0
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\writable-authorization-guard.ps1")
. (Join-Path $repoRoot "scripts\task-execution-lock.ps1")
$tempParent = Join-Path ([IO.Path]::GetTempPath()) ("aico-writable-auth-" + [Guid]::NewGuid().ToString("N"))
$fixtureRepo = Join-Path $tempParent "repo"
$workspaces = Join-Path $tempParent "worktrees"
$savedOpenRouter = $env:OPENROUTER_API_KEY

function Write-NoBom {
    param([string]$Path,[string]$Value)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

function Set-TestAuthorizationReceipt {
    param(
        [string]$TaskId,
        [string]$ImplementationAuthorization = "AUTHORIZED",
        [string]$AuthorizedTask = "",
        [string]$AuthorizedOperation = "WRITABLE",
        [string]$AuthorizedExecutionMode = "WRITABLE",
        [string]$AuthorizedProviderInvocation = "ALLOWED",
        [string]$AuthorizedWriteScope = "TASK_WORKTREE_ONLY",
        [string]$ScopeFingerprint = "",
        [string]$ExpiresAt = "2099-01-01T00:00:00Z",
        [string]$RetainedRestrictions = "NONE"
    )

    $taskContent = Get-Content (Join-Path $fixtureRepo ("tasks\" + $TaskId + ".md")) -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($ScopeFingerprint)) { $ScopeFingerprint = Get-WritableScopeFingerprint -TaskContent $taskContent }
    if ([string]::IsNullOrWhiteSpace($AuthorizedTask)) { $AuthorizedTask = $TaskId }
    $objectiveMatch = [regex]::Match($taskContent, "(?ms)^## Objective\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)")
    $request = @(
        "# WR-AUTH - Work Request", "", "## Metadata", "", "ID: WR-AUTH", "Type: FEATURE",
        "Requested by: explicit fixture requester", "Created: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))", "Status: PLANNING", "", "## Authorization Receipt", "",
        "Requested action: Implement task $TaskId - $($objectiveMatch.Groups[1].Value.Trim())",
        "Permitted scope: WRITABLE_IMPLEMENTATION",
        "Implementation authorization: $ImplementationAuthorization",
        "Authorized task: $AuthorizedTask",
        "Authorized operation: $AuthorizedOperation",
        "Authorized execution mode: $AuthorizedExecutionMode",
        "Authorized provider invocation: $AuthorizedProviderInvocation",
        "Authorized write scope: $AuthorizedWriteScope",
        "Authorized scope SHA-256: $ScopeFingerprint",
        "Authorization expires (UTC): $ExpiresAt",
        "Retained restrictions: $RetainedRestrictions"
    ) -join [Environment]::NewLine
    Write-NoBom (Join-Path $fixtureRepo "docs\engineering\work-requests\WR-AUTH.md") $request
}

function New-FixtureTask {
    param(
        [string]$Id,
        [string]$Status,
        [AllowEmptyString()][string]$WorkKind,
        [string]$FileName,
        [string[]]$Dependencies = @()
    )

    $metadata = @(
        "ID: $Id",
        "Status: $Status",
        "Priority: P1",
        "Owner: frontend",
        "Workflow phase: IMPLEMENTATION",
        "Type: FEATURE"
    )

    if (-not [string]::IsNullOrWhiteSpace($WorkKind)) {
        $metadata += "Work kind: $WorkKind"
    }

    $metadata += "Work request: WR-AUTH"

    $task = @(
        "# $Id - Writable authorization fixture",
        "",
        "## Metadata",
        ""
    ) + $metadata + @(
        "",
        "---",
        "",
        "## Objective",
        "",
        "Safely update $FileName.",
        "",
        "---",
        "",
        "## Context",
        "",
        "Authorization regression fixture.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] The requested source file is updated.",
        "",
        "---",
        "",
        "## Dependencies",
        "",
        $(if ($Dependencies.Count -gt 0) { $Dependencies | ForEach-Object { "- " + $_ } } else { "-" }),
        "",
        "---",
        "",
        "## Evidence",
        "",
        "-",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "-"
    )

    Write-NoBom (Join-Path $fixtureRepo ("tasks\" + $Id + ".md")) ($task -join [Environment]::NewLine)

    $dispatch = @(
        "# Execution Request - $Id",
        "",
        "Task: $Id",
        "Owner: frontend",
        "",
        "## Objective",
        "",
        "Safely update $FileName.",
        "",
        "## Required Context",
        "",
        "- tasks/$Id.md",
        "",
        "## Acceptance Criteria",
        "",
        "- Requested file is updated.",
        "",
        "## Testing Requirements",
        "",
        "- git diff --check"
    ) -join [Environment]::NewLine

    Write-NoBom (Join-Path $fixtureRepo ("docs\engineering\dispatch\" + $Id + ".md")) $dispatch
    Write-NoBom (Join-Path $fixtureRepo ("src\" + $FileName)) "original"
}

function Get-TaskContent {
    param([string]$Id)
    return Get-Content (Join-Path $fixtureRepo ("tasks\" + $Id + ".md")) -Raw -Encoding UTF8
}

function Get-TaskStatus {
    param([string]$Id)
    $content = Get-TaskContent -Id $Id
    $match = [regex]::Match($content,"(?m)^Status:\s*(\S+)")
    if (-not $match.Success) { throw "Task status missing for $Id" }
    return $match.Groups[1].Value.Trim()
}

function Add-DirectWorkspace {
    param([string]$Id)
    $workspace = Join-Path $workspaces $Id
    $branch = "aico/" + $Id.ToLowerInvariant()
    & git -C $fixtureRepo worktree add -b $branch $workspace HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to create direct test worktree for $Id" }
    return $workspace
}

function Assert-WritableRejected {
    param([string]$Id,[string]$Workspace)

    $taskPath = Join-Path $fixtureRepo ("tasks\" + $Id + ".md")
    $beforeBytes = [System.IO.File]::ReadAllBytes($taskPath)
    $beforeStatus = Get-TaskStatus -Id $Id
    $providerMarker = Join-Path $fixtureRepo ".codex\provider-called.txt"
    Remove-Item $providerMarker -Force -ErrorAction SilentlyContinue

    $rejected = $false
    try {
        & (Join-Path $fixtureRepo "scripts\run-writable-agent.ps1") -Id $Id -ProjectPath $fixtureRepo -WorkspacePath $Workspace -Provider Auto
    }
    catch {
        if ($_.Exception.Message -match "writable execution requires Work kind IMPLEMENTATION") { $rejected = $true } else { throw }
    }

    if (-not $rejected) { throw "${Id}: unauthorized writable execution was not rejected." }

    $afterBytes = [System.IO.File]::ReadAllBytes($taskPath)
    if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$beforeBytes,[byte[]]$afterBytes)) {
        throw "${Id}: rejection modified the canonical task file."
    }

    $afterStatus = Get-TaskStatus -Id $Id
    if ($afterStatus -ne $beforeStatus) { throw "${Id}: rejection changed task status from $beforeStatus to $afterStatus." }

    if (Test-Path $providerMarker) { throw "${Id}: provider was invoked before writable authorization was validated." }

    $evidencePath = Join-Path $fixtureRepo ("docs\engineering\writable-evidence\" + $Id + ".md")
    if (Test-Path $evidencePath) { throw "${Id}: rejection created writable evidence." }

    $workspaceStatus = @(& git -C $Workspace status --porcelain)
    if (@($workspaceStatus).Count -gt 0) { throw "${Id}: rejection modified the writable worktree." }
}

try {
    foreach ($dir in @("scripts","tasks","schemas",".codex",".codex\agents","docs\engineering\dispatch","docs\engineering\reviews","docs\engineering\work-requests","src")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRepo $dir) | Out-Null
    }

    New-Item -ItemType Directory -Force -Path $workspaces | Out-Null

    foreach ($name in @("run-writable-agent.ps1","writable-authorization-guard.ps1","task-execution-lock.ps1","new-agent-workspace.ps1","advance-task.ps1","update-task.ps1","submit-task-result.ps1","build-agent-context.ps1","build-corrective-analysis-context.ps1","resolve-writable-required-files.ps1")) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $fixtureRepo ("scripts\" + $name)) -Force
    }

    Copy-Item (Join-Path $repoRoot "schemas\writable-change-set.schema.json") (Join-Path $fixtureRepo "schemas\writable-change-set.schema.json") -Force
    Copy-Item (Join-Path $repoRoot ".codex\writable-policy.json") (Join-Path $fixtureRepo ".codex\writable-policy.json") -Force

    $fakeRouter = @'
param(
    [string]$Provider,
    [string]$ProjectPath,
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [string]$TaskId
)
$marker = Join-Path $ProjectPath ".codex\provider-called.txt"
[System.IO.File]::WriteAllText($marker,"called",(New-Object System.Text.UTF8Encoding($false)))
if ($env:AICO_POST_PROVIDER_CASE) {
    $calls = Join-Path $ProjectPath '.codex\post-provider-calls.txt'
    [IO.File]::AppendAllText($calls, "$Provider`n")
    [IO.File]::WriteAllText((Join-Path $ProjectPath '.codex\post-provider-output-path.txt'), $OutputPath)
    $requestPath = Join-Path $ProjectPath 'docs\engineering\work-requests\WR-AUTH.md'
    $request = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8
    switch ($env:AICO_POST_PROVIDER_CASE) {
        'REVOKE' { $request = $request.Replace('Implementation authorization: AUTHORIZED', 'Implementation authorization: NOT_INFERRED') }
        'REVOKE_AUTO' { $request = $request.Replace('Implementation authorization: AUTHORIZED', 'Implementation authorization: NOT_INFERRED') }
        'EXPIRE' { $request = $request -replace '(?m)^Authorization expires \(UTC\):.*$', 'Authorization expires (UTC): 2000-01-01T00:00:00Z' }
        'RECEIPT' { $request = $request.Replace('Requested by: explicit fixture requester', 'Requested by: changed fixture requester') }
        'DEPENDENCY' {
            $path = Join-Path $ProjectPath 'tasks\AICO-120.md'
            [IO.File]::WriteAllText($path, ((Get-Content $path -Raw).Replace('Status: DONE', 'Status: ACTIVE')))
        }
        'SCOPE' {
            $path = Join-Path $ProjectPath 'tasks\AICO-119.md'
            [IO.File]::WriteAllText($path, ((Get-Content $path -Raw).Replace('Safely update post-provider.txt.', 'Replace the authorized objective after provider invocation.')))
        }
        'REVOKE_THROW' { $request = $request.Replace('Implementation authorization: AUTHORIZED', 'Implementation authorization: NOT_INFERRED') }
    }
    [IO.File]::WriteAllText($requestPath, $request, (New-Object Text.UTF8Encoding($false)))
    if ($env:AICO_POST_PROVIDER_CASE -eq 'REVOKE_THROW') { throw 'Simulated provider transport failure after revocation.' }
    if ($env:AICO_POST_PROVIDER_CASE -eq 'VALID_FALLBACK' -and $Provider -eq 'OpenRouter') { throw 'Simulated recoverable transport failure with valid authorization.' }
}
$payload = @{
    outcome = "COMPLETED"
    summary = "Authorized implementation"
    report_markdown = "# Authorized implementation"
    changes = @(
        @{
            path = "src/implementation.txt"
            operation = "WRITE"
            content = "changed"
            reason = "Authorization regression fixture"
        }
    )
    verification_commands = @("git diff --check")
    verification = "git diff --check"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
} | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($OutputPath,$payload,(New-Object System.Text.UTF8Encoding($false)))
[PSCustomObject]@{ Provider = $Provider; Model = $Model }
'@
    Write-NoBom (Join-Path $fixtureRepo "scripts\provider-router.ps1") $fakeRouter

    $providerConfig = @{
        writable_auto_order = @("OpenRouter")
        writable_context_max_chars = 50000
        writable_models = @{ OpenRouter = "openrouter/free" }
        models = @{ OpenRouter = "openrouter/free" }
    } | ConvertTo-Json -Depth 10

    Write-NoBom (Join-Path $fixtureRepo ".codex\provider-config.json") $providerConfig
    Write-NoBom (Join-Path $fixtureRepo ".codex\agents\frontend.md") "Frontend fixture role."
    Write-NoBom (Join-Path $fixtureRepo "AGENTS.md") "Writable authorization fixture."
    Write-NoBom (Join-Path $fixtureRepo "docs\engineering\work-requests\WR-AUTH.md") "# WR-AUTH - Work Request`n`nID: WR-AUTH`nType: FEATURE`nRequested by: fixture requester`n`n## Authorization Receipt`n`nRequested action: Not authorized.`nPermitted scope: planning only.`nImplementation authorization: NOT_INFERRED`nAuthorized task: NONE`nAuthorized operation: NONE`nAuthorized scope SHA-256: NONE`nAuthorization expires (UTC): NONE`nRetained restrictions: Implementation is not authorized."

    New-FixtureTask -Id "AICO-101" -Status "READY"  -WorkKind "PLANNING"       -FileName "planning-ready.txt"
    New-FixtureTask -Id "AICO-102" -Status "ACTIVE" -WorkKind "PLANNING"       -FileName "planning-active.txt"
    New-FixtureTask -Id "AICO-103" -Status "READY"  -WorkKind ""               -FileName "missing-kind.txt"
    New-FixtureTask -Id "AICO-104" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "implementation.txt"
    New-FixtureTask -Id "AICO-105" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "no-receipt-ready.txt"
    New-FixtureTask -Id "AICO-106" -Status "ACTIVE" -WorkKind "IMPLEMENTATION" -FileName "no-receipt-active.txt"
    New-FixtureTask -Id "AICO-107" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "wrong-task.txt"
    New-FixtureTask -Id "AICO-108" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "wrong-operation.txt"
    New-FixtureTask -Id "AICO-109" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "expired-receipt.txt"
    New-FixtureTask -Id "AICO-110" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "dependency-unsatisfied.txt" -Dependencies @("AICO-111")
    New-FixtureTask -Id "AICO-111" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "dependency.txt"
    New-FixtureTask -Id "AICO-112" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "unregistered-worktree.txt"
    New-FixtureTask -Id "AICO-113" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "race-dependency.txt" -Dependencies @("AICO-114")
    New-FixtureTask -Id "AICO-114" -Status "DONE"   -WorkKind "IMPLEMENTATION" -FileName "race-dependency-done.txt"
    New-FixtureTask -Id "AICO-115" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "ambiguous-receipt.txt"
    New-FixtureTask -Id "AICO-116" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "race-dependency-status.txt" -Dependencies @("AICO-117")
    New-FixtureTask -Id "AICO-117" -Status "DONE"   -WorkKind "IMPLEMENTATION" -FileName "race-dependency-status-done.txt"
    New-FixtureTask -Id "AICO-118" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "retained-provider-restriction.txt"
    New-FixtureTask -Id "AICO-119" -Status "READY"  -WorkKind "IMPLEMENTATION" -FileName "post-provider.txt" -Dependencies @('AICO-120')
    New-FixtureTask -Id "AICO-120" -Status "DONE"   -WorkKind "IMPLEMENTATION" -FileName "post-provider-dependency.txt"
    Set-TestAuthorizationReceipt -TaskId "AICO-104"
    $sentinelEvidencePath = Join-Path $fixtureRepo "docs\engineering\writable-evidence\P0-preservation-sentinel.md"
    Write-NoBom $sentinelEvidencePath "preserve pre-existing evidence byte-for-byte"

    & git -C $fixtureRepo init | Out-Null
    & git -C $fixtureRepo config user.email "aico-test@example.invalid"
    & git -C $fixtureRepo config user.name "AI Company OS Test"
    & git -C $fixtureRepo add .
    & git -C $fixtureRepo commit -m "writable authorization fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fixture commit failed." }

    $planningReadyWorkspace = Add-DirectWorkspace -Id "AICO-101"
    $planningActiveWorkspace = Add-DirectWorkspace -Id "AICO-102"
    $missingKindWorkspace = Add-DirectWorkspace -Id "AICO-103"

    $workspaceCreationRejected = $false
    try {
        & (Join-Path $fixtureRepo "scripts\new-agent-workspace.ps1") -Id "AICO-101" -ProjectPath $fixtureRepo -WorkspaceRoot (Join-Path $tempParent "unauthorized-workspaces") | Out-Null
    }
    catch {
        if ($_.Exception.Message -match "Work kind IMPLEMENTATION") { $workspaceCreationRejected = $true } else { throw }
    }

    if (-not $workspaceCreationRejected) { throw "new-agent-workspace.ps1 accepted a PLANNING task." }

    Assert-WritableRejected -Id "AICO-101" -Workspace $planningReadyWorkspace
    Assert-WritableRejected -Id "AICO-102" -Workspace $planningActiveWorkspace
    Assert-WritableRejected -Id "AICO-103" -Workspace $missingKindWorkspace

    function Assert-AuthorizationBlocked {
        param([string]$TaskId,[string]$Workspace)
        $taskPath = Join-Path $fixtureRepo ("tasks\" + $TaskId + ".md")
        $beforeContent = Get-Content $taskPath -Raw -Encoding UTF8
        $beforeObjective = [regex]::Match($beforeContent,"(?ms)^## Objective\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)").Groups[1].Value
        $sentinelBefore = [System.IO.File]::ReadAllBytes($sentinelEvidencePath)
        $providerMarker = Join-Path $fixtureRepo ".codex\provider-called.txt"
        Remove-Item $providerMarker -Force -ErrorAction SilentlyContinue
        $rejected = $false
        try { & (Join-Path $fixtureRepo "scripts\run-writable-agent.ps1") -Id $TaskId -ProjectPath $fixtureRepo -WorkspacePath $Workspace -Provider Auto }
        catch { if ($_.Exception.Message -match "BLOCKED") { $rejected = $true } else { throw } }
        if (-not $rejected) {
            if ($TaskId -eq "AICO-113" -and -not (Test-Path (Join-Path $fixtureRepo ".codex\context-mutation-ran.txt"))) { throw "Race fixture did not run between guard checks." }
            throw "${TaskId}: writable authorization/dependency guard did not reject."
        }
        if ((Get-TaskStatus -Id $TaskId) -ne "BLOCKED") { throw "${TaskId}: rejected task was not BLOCKED." }
        if (Test-Path $providerMarker) { throw "${TaskId}: provider was called before the guard rejected execution." }
        $afterContent = Get-Content $taskPath -Raw -Encoding UTF8
        $afterObjective = [regex]::Match($afterContent,"(?ms)^## Objective\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)").Groups[1].Value
        if ($beforeObjective -cne $afterObjective) { throw "${TaskId}: rejection changed task scope." }
        if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$sentinelBefore,[System.IO.File]::ReadAllBytes($sentinelEvidencePath))) {
            throw "${TaskId}: rejection modified pre-existing evidence."
        }
        foreach ($artifact in @(
            (Join-Path $fixtureRepo ("docs\engineering\writable-evidence\" + $TaskId + ".md")),
            (Join-Path $fixtureRepo ("docs\engineering\results\" + $TaskId + "-result-001.md"))
        )) { if (Test-Path $artifact) { throw "${TaskId}: rejection created completion output." } }
        if ($Workspace -and (Test-Path (Join-Path $Workspace ".git"))) {
            $workspaceChanges = @(& git -C $Workspace status --porcelain)
            if ($workspaceChanges.Count -gt 0) { throw "${TaskId}: rejection changed the worktree." }
        }
        $lease = Enter-TaskExecutionLock -ProjectPath $fixtureRepo -Id $TaskId -Operation "LOCK-RELEASE-CHECK"
        Exit-TaskExecutionLock -Lock $lease
    }

    foreach ($taskId in @("AICO-105","AICO-106","AICO-107","AICO-108","AICO-109","AICO-110","AICO-113","AICO-115","AICO-116","AICO-118")) {
        $workspace = Join-Path $workspaces $taskId
        & git -C $fixtureRepo worktree add -b ("aico/" + $taskId.ToLowerInvariant()) $workspace HEAD | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Unable to create test worktree for $taskId." }
    }

    Set-TestAuthorizationReceipt -TaskId "AICO-105" -ImplementationAuthorization "NOT_INFERRED"
    Assert-AuthorizationBlocked -TaskId "AICO-105" -Workspace (Join-Path $workspaces "AICO-105")
    Set-TestAuthorizationReceipt -TaskId "AICO-106" -ImplementationAuthorization "NOT_INFERRED"
    Assert-AuthorizationBlocked -TaskId "AICO-106" -Workspace (Join-Path $workspaces "AICO-106")
    Set-TestAuthorizationReceipt -TaskId "AICO-107" -AuthorizedTask "AICO-999"
    Assert-AuthorizationBlocked -TaskId "AICO-107" -Workspace (Join-Path $workspaces "AICO-107")
    Set-TestAuthorizationReceipt -TaskId "AICO-108" -ScopeFingerprint ("0" * 64)
    Assert-AuthorizationBlocked -TaskId "AICO-108" -Workspace (Join-Path $workspaces "AICO-108")
    Set-TestAuthorizationReceipt -TaskId "AICO-109" -ExpiresAt "2000-01-01T00:00:00Z"
    Assert-AuthorizationBlocked -TaskId "AICO-109" -Workspace (Join-Path $workspaces "AICO-109")
    $env:OPENROUTER_API_KEY = "fixture-only-not-a-real-credential"
    Set-TestAuthorizationReceipt -TaskId "AICO-118" -RetainedRestrictions "No real provider calls; mock transport only."
    Assert-AuthorizationBlocked -TaskId "AICO-118" -Workspace (Join-Path $workspaces "AICO-118")
    Set-TestAuthorizationReceipt -TaskId "AICO-115"
    $ambiguousReceiptPath = Join-Path $fixtureRepo "docs\engineering\work-requests\WR-AUTH.md"
    Write-NoBom $ambiguousReceiptPath ((Get-Content $ambiguousReceiptPath -Raw -Encoding UTF8) + "`nAuthorized task: AICO-999")
    Assert-AuthorizationBlocked -TaskId "AICO-115" -Workspace (Join-Path $workspaces "AICO-115")
    Set-TestAuthorizationReceipt -TaskId "AICO-110"
    Assert-AuthorizationBlocked -TaskId "AICO-110" -Workspace (Join-Path $workspaces "AICO-110")
    Set-TestAuthorizationReceipt -TaskId "AICO-112"
    $unregisteredWorkspace = Join-Path $tempParent "unregistered-AICO-112"
    New-Item -ItemType Directory -Force -Path $unregisteredWorkspace | Out-Null
    Assert-AuthorizationBlocked -TaskId "AICO-112" -Workspace $unregisteredWorkspace

    Set-TestAuthorizationReceipt -TaskId "AICO-113"
    $mutatingContextBuilder = @'
param([string]$ProjectPath,[string]$Id,[string]$Owner,[int]$MaxChars,[string[]]$RequiredFiles)
if ($env:AICO_TEST_MUTATE_TASK_STATE -eq "1") {
    $racingTaskPath = Join-Path $env:AICO_TEST_PROJECT "tasks\AICO-113.md"
    [IO.File]::WriteAllText((Join-Path $env:AICO_TEST_PROJECT ".codex\context-mutation-ran.txt"),"ran")
    $racingTaskContent = Get-Content $racingTaskPath -Raw -Encoding UTF8
    $racingTaskContent = $racingTaskContent.Replace("Status: ACTIVE", "Status: READY")
    [IO.File]::WriteAllText($racingTaskPath,$racingTaskContent,(New-Object Text.UTF8Encoding($false)))
}
if ($env:AICO_TEST_MUTATE_DEPENDENCY -eq "1") {
    $racingDependencyPath = Join-Path $env:AICO_TEST_PROJECT "tasks\AICO-117.md"
    [IO.File]::WriteAllText((Join-Path $env:AICO_TEST_PROJECT ".codex\dependency-mutation-ran.txt"),"ran")
    $racingDependencyContent = Get-Content $racingDependencyPath -Raw -Encoding UTF8
    $racingDependencyContent = $racingDependencyContent.Replace("Status: DONE", "Status: ACTIVE")
    [IO.File]::WriteAllText($racingDependencyPath,$racingDependencyContent,(New-Object Text.UTF8Encoding($false)))
}
"mock context"
'@
    Write-NoBom (Join-Path $fixtureRepo "scripts\build-agent-context.ps1") $mutatingContextBuilder
    $env:AICO_TEST_PROJECT = $fixtureRepo
    $env:AICO_TEST_MUTATE_TASK_STATE = "1"
    try {
        Assert-AuthorizationBlocked -TaskId "AICO-113" -Workspace (Join-Path $workspaces "AICO-113")
        if (-not (Test-Path (Join-Path $fixtureRepo ".codex\context-mutation-ran.txt"))) { throw "Race fixture did not run between guard checks." }
    }
    finally { Remove-Item Env:AICO_TEST_MUTATE_TASK_STATE -ErrorAction SilentlyContinue; Remove-Item Env:AICO_TEST_PROJECT -ErrorAction SilentlyContinue }
    Copy-Item (Join-Path $repoRoot "scripts\build-agent-context.ps1") (Join-Path $fixtureRepo "scripts\build-agent-context.ps1") -Force
    Write-NoBom (Join-Path $fixtureRepo "scripts\build-agent-context.ps1") $mutatingContextBuilder
    Set-TestAuthorizationReceipt -TaskId "AICO-116"
    $env:AICO_TEST_PROJECT = $fixtureRepo
    $env:AICO_TEST_MUTATE_DEPENDENCY = "1"
    try {
        Assert-AuthorizationBlocked -TaskId "AICO-116" -Workspace (Join-Path $workspaces "AICO-116")
        if (-not (Test-Path (Join-Path $fixtureRepo ".codex\dependency-mutation-ran.txt"))) { throw "Dependency race fixture did not run between guard checks." }
    }
    finally { Remove-Item Env:AICO_TEST_MUTATE_DEPENDENCY -ErrorAction SilentlyContinue; Remove-Item Env:AICO_TEST_PROJECT -ErrorAction SilentlyContinue }
    Copy-Item (Join-Path $repoRoot "scripts\build-agent-context.ps1") (Join-Path $fixtureRepo "scripts\build-agent-context.ps1") -Force
    Set-TestAuthorizationReceipt -TaskId "AICO-104"

    $postWorkspace = Add-DirectWorkspace -Id 'AICO-119'
    $postTaskPath = Join-Path $fixtureRepo 'tasks\AICO-119.md'
    $postTask = Get-Content $postTaskPath -Raw -Encoding UTF8
    $postDependencyPath = Join-Path $fixtureRepo 'tasks\AICO-120.md'
    $postDependency = Get-Content $postDependencyPath -Raw -Encoding UTF8
    $postEvidence = Join-Path $fixtureRepo 'docs\engineering\writable-evidence\AICO-119.md'
    $postReport = Join-Path $fixtureRepo 'docs\engineering\agent-reports\AICO-119.md'
    $postDiagnostic = Join-Path $fixtureRepo 'docs\engineering\diagnostics\AICO-119-diagnostic-v1.json'
    foreach ($path in @($postEvidence,$postReport,$postDiagnostic)) { Write-NoBom $path 'preserve prior evidence' }
    $postConfig = Join-Path $fixtureRepo '.codex\provider-config.json'
    $configBefore = Get-Content $postConfig -Raw -Encoding UTF8
    $configValue = $configBefore | ConvertFrom-Json
    $configValue.writable_auto_order = @('OpenRouter','Ollama')
    Write-NoBom $postConfig ($configValue | ConvertTo-Json -Depth 10)
    $env:OPENROUTER_API_KEY = 'fixture-only-not-a-real-credential'
    try {
        foreach ($case in @('REVOKE','REVOKE_AUTO','EXPIRE','DEPENDENCY','RECEIPT','SCOPE','REVOKE_THROW')) {
            Write-NoBom $postTaskPath $postTask
            Write-NoBom $postDependencyPath $postDependency
            Set-TestAuthorizationReceipt -TaskId 'AICO-119'
            $callsPath = Join-Path $fixtureRepo '.codex\post-provider-calls.txt'
            Remove-Item $callsPath -Force -ErrorAction SilentlyContinue
            $env:AICO_POST_PROVIDER_CASE = $case
            $rejected = $false
            $provider = if ($case -eq 'REVOKE') { 'OpenRouter' } else { 'Auto' }
            try { & (Join-Path $fixtureRepo 'scripts\run-writable-agent.ps1') -Id 'AICO-119' -ProjectPath $fixtureRepo -WorkspacePath $postWorkspace -Provider $provider }
            catch { if ($_.Exception.Message -match 'BLOCKED') { $rejected = $true } else { throw } }
            if (-not $rejected) { throw "POST_PROVIDER_${case}: invalidated authorization was accepted." }
            if ((Get-TaskStatus -Id 'AICO-119') -ne 'BLOCKED') { throw "POST_PROVIDER_${case}: task not BLOCKED." }
            if (@(Get-Content $callsPath).Count -ne 1) { throw "POST_PROVIDER_${case}: fallback invoked another provider." }
            $outputPath = Get-Content (Join-Path $fixtureRepo '.codex\post-provider-output-path.txt') -Raw
            if (Test-Path -LiteralPath $outputPath) { throw "POST_PROVIDER_${case}: temporary provider output survived rejection." }
            if (@(& git -C $postWorkspace status --porcelain).Count -ne 0) { throw "POST_PROVIDER_${case}: source changed." }
            foreach ($path in @($postEvidence,$postReport,$postDiagnostic)) {
                if ((Get-Content $path -Raw) -cne 'preserve prior evidence') { throw "POST_PROVIDER_${case}: existing evidence changed." }
            }
            if (Test-Path (Join-Path $fixtureRepo 'docs\engineering\results\AICO-119-result-001.md')) { throw "POST_PROVIDER_${case}: result published." }
            $lease = Enter-TaskExecutionLock -ProjectPath $fixtureRepo -Id 'AICO-119' -Operation 'POST-PROVIDER-RELEASE-CHECK'
            Exit-TaskExecutionLock -Lock $lease
            Write-Host "PASS: POST_PROVIDER_$case; calls=1; state=BLOCKED; source/evidence preserved; no result."
        }
    }
    finally {
        Remove-Item Env:AICO_POST_PROVIDER_CASE -ErrorAction SilentlyContinue
        Write-NoBom $postConfig $configBefore
    }
    Set-TestAuthorizationReceipt -TaskId 'AICO-104'

    $implementationWorkspaceRoot = Join-Path $tempParent "implementation-workspaces"
    & (Join-Path $fixtureRepo "scripts\new-agent-workspace.ps1") -Id "AICO-104" -ProjectPath $fixtureRepo -WorkspaceRoot $implementationWorkspaceRoot | Out-Null

    $implementationWorkspace = Join-Path $implementationWorkspaceRoot "AICO-104"
    if (-not (Test-Path $implementationWorkspace)) { throw "IMPLEMENTATION READY task could not create an isolated writable workspace." }

    $env:OPENROUTER_API_KEY = "writable-auth-test-key"
    Write-NoBom $postConfig ($configValue | ConvertTo-Json -Depth 10)
    $env:AICO_POST_PROVIDER_CASE = 'VALID_FALLBACK'
    Remove-Item (Join-Path $fixtureRepo '.codex\post-provider-calls.txt') -Force -ErrorAction SilentlyContinue

    & (Join-Path $fixtureRepo "scripts\run-writable-agent.ps1") -Id "AICO-104" -ProjectPath $fixtureRepo -WorkspacePath $implementationWorkspace -Provider Auto
    Remove-Item Env:AICO_POST_PROVIDER_CASE -ErrorAction SilentlyContinue
    if (@(Get-Content (Join-Path $fixtureRepo '.codex\post-provider-calls.txt')).Count -ne 2) { throw 'Valid authorization incorrectly prevented recoverable provider fallback.' }

    if ((Get-TaskStatus -Id "AICO-104") -ne "REVIEW") {
        throw "Authorized IMPLEMENTATION READY task did not complete READY -> ACTIVE -> REVIEW."
    }

    $implementationValue = Get-Content (Join-Path $implementationWorkspace "src\implementation.txt") -Raw
    if ($implementationValue -ne "changed") { throw "Authorized IMPLEMENTATION task did not apply the writable change." }

    if (-not (Test-Path (Join-Path $fixtureRepo "docs\engineering\writable-evidence\AICO-104.md"))) {
        throw "Authorized IMPLEMENTATION task did not create writable evidence."
    }

    Write-Host "PASS: writable lower-layer authorization guard" -ForegroundColor Green
}
finally {
    Remove-Item Env:AICO_POST_PROVIDER_CASE -ErrorAction SilentlyContinue
    $env:OPENROUTER_API_KEY = $savedOpenRouter

    if (Test-Path $fixtureRepo) {
    foreach ($candidate in @(
            (Join-Path $workspaces "AICO-101"),
            (Join-Path $workspaces "AICO-102"),
            (Join-Path $workspaces "AICO-103"),
            (Join-Path $workspaces "AICO-105"),
            (Join-Path $workspaces "AICO-106"),
            (Join-Path $workspaces "AICO-107"),
            (Join-Path $workspaces "AICO-108"),
            (Join-Path $workspaces "AICO-109"),
            (Join-Path $workspaces "AICO-110"),
            (Join-Path $workspaces "AICO-113"),
            (Join-Path $workspaces "AICO-115"),
            (Join-Path $workspaces "AICO-116"),
            (Join-Path $workspaces "AICO-118"),
            (Join-Path $workspaces "AICO-119"),
            (Join-Path $tempParent "implementation-workspaces\AICO-104")
        )) {
            if (Test-Path $candidate) {
                try { & git -C $fixtureRepo worktree remove $candidate --force 2>$null | Out-Null } catch {}
            }
        }
        try { & git -C $fixtureRepo worktree prune 2>$null | Out-Null } catch {}
    }

    if (Test-Path $tempParent) { Remove-Item $tempParent -Recurse -Force -ErrorAction SilentlyContinue }
}
