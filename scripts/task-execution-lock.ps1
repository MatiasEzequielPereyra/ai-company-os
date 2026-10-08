function Get-ExecutionPathComparison {
    if ([IO.Path]::DirectorySeparatorChar -eq '\') { return [StringComparison]::OrdinalIgnoreCase }
    return [StringComparison]::Ordinal
}

# Project barrier is persistent: never unlink/recreate the coordination file.
if ($null -eq (Get-Variable -Name AicoProjectExecutionLeases -Scope Global -ErrorAction SilentlyContinue)) {
    $global:AicoProjectExecutionLeases = @{}
}
function Get-ProjectExecutionPath {
    param([string]$ProjectPath)
    $root=[IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path)
    $directory=Join-Path $root '.codex/runtime/locks'
    $path=Join-Path $directory 'project-maintenance.lock'
    # Check existing ancestors before creating runtime directories or opening files.
    $current=$path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item=Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Project execution barrier traverses a reparse point.' }
        }
        if ([string]::Equals($current,$root,(Get-ExecutionPathComparison))) { break }
        $current=Split-Path $current -Parent
    }
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    if (-not [IO.File]::Exists($path)) {
        $bootstrap=$null
        try {
            $bootstrap=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
        } catch [IO.IOException] {
            # Another first user may have created the persistent empty object.
            if (-not [IO.File]::Exists($path)) { throw }
        } finally { if($null -ne $bootstrap){$bootstrap.Dispose()} }
    }
    return $path
}
function Enter-ProjectExecutionLease {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,
          [Parameter(Mandatory=$true)][ValidateSet('Shared','Maintenance')][string]$Mode)
    $root=[IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path)
    $path=Get-ProjectExecutionPath -ProjectPath $root
    $stream=$null
    try {
        if($Mode -eq 'Shared') {
            $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        } else {
            $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        }
    } catch [IO.IOException] {
        if($Mode -eq 'Maintenance') {
            throw 'AI Company OS project maintenance cannot run while project executions are active. Finish the current agent/gate/writable/finalization operation and retry.'
        }
        throw 'AI Company OS task execution cannot start while project maintenance is active.'
    }
    $lease=[PSCustomObject]@{Path=$path;Stream=$stream;Mode=$Mode}
    $global:AicoProjectExecutionLeases[[Guid]::NewGuid().ToString('N')]=[PSCustomObject]@{
        Lease=$lease;Stream=$stream;Path=[IO.Path]::GetFullPath($path);Project=$root;Mode=$Mode;ProcessId=$PID
    }
    return $lease
}
function Assert-ProjectExecutionLease {
    param([string]$ProjectPath,[object]$Lease,[ValidateSet('Shared','Maintenance')][string]$Mode)
    $entries=@($global:AicoProjectExecutionLeases.Values | Where-Object {[object]::ReferenceEquals($_.Lease,$Lease)})
    if($entries.Count -ne 1){throw 'Project execution lease is fabricated, expired or belongs to another process.'}
    $entry=$entries[0];$root=[IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path)
    $expected=[IO.Path]::GetFullPath((Join-Path $root '.codex/runtime/locks/project-maintenance.lock'))
    if($entry.ProcessId -ne $PID -or $entry.Mode -cne $Mode -or $Lease.Mode -cne $entry.Mode -or
       -not [string]::Equals($entry.Project,$root,(Get-ExecutionPathComparison)) -or
       -not [string]::Equals($entry.Path,$expected,(Get-ExecutionPathComparison)) -or
       -not [string]::Equals($Lease.Path,$entry.Path,(Get-ExecutionPathComparison)) -or
       -not [object]::ReferenceEquals($Lease.Stream,$entry.Stream) -or
       $entry.Stream.SafeFileHandle.IsClosed -or $entry.Stream.SafeFileHandle.IsInvalid -or -not $entry.Stream.CanRead) {
        throw 'Project execution lease identity or live handle is invalid.'
    }
}
function Exit-ProjectExecutionLease {
    param([object]$Lease)
    if($null -eq $Lease){return}
    $keys=@($global:AicoProjectExecutionLeases.Keys | Where-Object {[object]::ReferenceEquals($global:AicoProjectExecutionLeases[$_].Lease,$Lease)})
    if($keys.Count -ne 1){throw 'Project execution lease is not registered in this process.'}
    $global:AicoProjectExecutionLeases[$keys[0]].Stream.Dispose()
    $global:AicoProjectExecutionLeases.Remove($keys[0])
}
function Enter-ProjectExecutionScope {
    param([string]$ProjectPath,[ValidateSet('Shared','Maintenance')][string]$Mode,[object]$Lease=$null)
    if($null -ne $Lease){
        Assert-ProjectExecutionLease -ProjectPath $ProjectPath -Lease $Lease -Mode $Mode
        return [PSCustomObject]@{Lease=$Lease;OwnsLock=$false}
    }
    return [PSCustomObject]@{Lease=(Enter-ProjectExecutionLease -ProjectPath $ProjectPath -Mode $Mode);OwnsLock=$true}
}
function Exit-ProjectExecutionScope {
    param([object]$Scope)
    if($null -ne $Scope -and $Scope.OwnsLock){Exit-ProjectExecutionLease -Lease $Scope.Lease}
}

# Registry survives repeated dot-sourcing by nested scripts in this runspace.
if ($null -eq (Get-Variable -Name AicoTaskExecutionLeases -Scope Global -ErrorAction SilentlyContinue)) {
    $global:AicoTaskExecutionLeases = @{}
}

function Get-TaskExecutionLockPath {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$Id
    )

    # Windows PowerShell can preserve an 8.3 TEMP alias in Resolve-Path while
    # .NET expands it in registry identities. Use the same canonical spelling
    # before constructing both the live lease path and its registered identity.
    $root = [IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path)
    $runtimeDir = Join-Path $root ".codex\runtime\locks"
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

    $safeId = ($Id -replace '[^A-Za-z0-9_.-]','_')
    $path = Join-Path $runtimeDir ($safeId + ".lock")
    if (Test-Path -LiteralPath $path) {
        $item=Get-Item -LiteralPath $path -Force
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Task execution lock is a reparse point.' }
    }
    return $path
}

function Enter-TaskExecutionLock {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    $projectLease = Enter-ProjectExecutionLease -ProjectPath $ProjectPath -Mode Shared
    $stream = $null
    try {
    $path = Get-TaskExecutionLockPath -ProjectPath $ProjectPath -Id $Id
    try {
        $stream = New-Object System.IO.FileStream(
            $path,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
    }
    catch [System.IO.IOException] {
        throw (
            "Task $Id already has an AI Company OS execution in progress. " +
            "Wait for the current analysis/writable/gate/finalization operation to finish before starting another one."
        )
    }

    try {
        $metadata = [ordered]@{
            schema_version = 1
            task_id = $Id
            operation = $Operation
            process_id = $PID
            acquired_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        } | ConvertTo-Json -Depth 5

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($metadata)
        $stream.SetLength(0)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush()
        $stream.Position = 0
    }
    catch {
        $stream.Dispose()
        throw
    }

    $lease = [PSCustomObject]@{
        Path = $path
        Stream = $stream
        TaskId = $Id
        Operation = $Operation
        ProjectLease = $projectLease
    }
    $token = [Guid]::NewGuid().ToString('N')
    $global:AicoTaskExecutionLeases[$token] = [PSCustomObject]@{
        Lease=$lease; Stream=$stream; Path=[IO.Path]::GetFullPath($path)
        Project=[IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path)
        TaskId=$Id; ProcessId=$PID; Operation=$Operation; ProjectLease=$projectLease
    }
    return $lease
    } catch {
        if($null -ne $stream){$stream.Dispose()}
        Exit-ProjectExecutionLease -Lease $projectLease
        throw
    }
}

function Exit-TaskExecutionLock {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Lock
    )

    if ($null -eq $Lock) { return }

    try {
        $entryKey = @($global:AicoTaskExecutionLeases.Keys | Where-Object {
            [object]::ReferenceEquals($global:AicoTaskExecutionLeases[$_].Lease,$Lock)
        })
        if ($entryKey.Count -ne 1) { throw 'Task execution lease is not registered in this process.' }
        $entry = $global:AicoTaskExecutionLeases[$entryKey[0]]
        $entry.Stream.Dispose()
        Exit-ProjectExecutionLease -Lease $entry.ProjectLease
        $global:AicoTaskExecutionLeases.Remove($entryKey[0])
        foreach ($receiptKey in @($global:AicoReviewIntakeReceipts.Keys)) {
            if ([object]::ReferenceEquals($global:AicoReviewIntakeReceipts[$receiptKey].Lease,$Lock)) {
                $global:AicoReviewIntakeReceipts.Remove($receiptKey)
            }
        }
    }
    catch {
        Write-Warning (
            "Could not release execution lock for " +
            [string]$Lock.TaskId +
            ": " +
            $_.Exception.Message
        )
    }
}

function Assert-TaskExecutionLease {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,
          [Parameter(Mandatory=$true)][string]$Id,
          [Parameter(Mandatory=$true)][object]$Lease,
          [string]$Operation="")
    $entries = @($global:AicoTaskExecutionLeases.Values | Where-Object {
        [object]::ReferenceEquals($_.Lease,$Lease)
    })
    if ($entries.Count -ne 1) { throw 'Task execution lease is fabricated, expired or belongs to another process.' }
    $entry = $entries[0]
    if (-not [object]::ReferenceEquals($entry.ProjectLease,$Lease.ProjectLease)) {
        throw 'Task execution lease has fabricated or mismatched project ownership.'
    }
    Assert-ProjectExecutionLease -ProjectPath $ProjectPath -Lease $entry.ProjectLease -Mode Shared
    $root = [IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path)
    $expectedPath = [IO.Path]::GetFullPath((Join-Path $root ('.codex/runtime/locks/' + ($Id -replace '[^A-Za-z0-9_.-]','_') + '.lock')))
    if ($entry.ProcessId -ne $PID -or $entry.TaskId -cne $Id -or
        $Lease.TaskId -cne $entry.TaskId -or $Lease.Operation -cne $entry.Operation -or
        -not [string]::Equals($Lease.Path,$entry.Path,(Get-ExecutionPathComparison)) -or
        (-not [string]::IsNullOrWhiteSpace($Operation) -and $entry.Operation -cne $Operation) -or
        -not [string]::Equals($entry.Project,$root,(Get-ExecutionPathComparison)) -or
        -not [string]::Equals($entry.Path,$expectedPath,(Get-ExecutionPathComparison)) -or
        -not [object]::ReferenceEquals($entry.Stream,$Lease.Stream) -or
        $entry.Stream.SafeFileHandle.IsClosed -or $entry.Stream.SafeFileHandle.IsInvalid -or
        -not $entry.Stream.CanRead -or -not $entry.Stream.CanWrite) {
        throw 'Task execution lease identity or live exclusive handle is invalid.'
    }
}

function Enter-TaskExecutionScope {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,
          [Parameter(Mandatory=$true)][string]$Id,
          [Parameter(Mandatory=$true)][string]$Operation,
          [object]$Lease=$null)
    if ($null -ne $Lease) {
        Assert-TaskExecutionLease -ProjectPath $ProjectPath -Id $Id -Lease $Lease
        return [PSCustomObject]@{Lease=$Lease; OwnsLock=$false}
    }
    return [PSCustomObject]@{Lease=(Enter-TaskExecutionLock -ProjectPath $ProjectPath -Id $Id -Operation $Operation); OwnsLock=$true}
}

function Exit-TaskExecutionScope {
    param([object]$Scope)
    if ($null -ne $Scope -and $Scope.OwnsLock) { Exit-TaskExecutionLock -Lock $Scope.Lease }
}

if ($null -eq (Get-Variable -Name AicoReviewIntakeReceipts -Scope Global -ErrorAction SilentlyContinue)) {
    $global:AicoReviewIntakeReceipts = @{}
}
function Get-ReviewIntakeDigest {
    param([string]$ProjectPath,[string]$Id,[string]$ReviewPath)
    $root=[IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path).TrimEnd('\','/')
    $full=[IO.Path]::GetFullPath($ReviewPath)
    $expectedDirectory=Join-Path $root 'docs/engineering/reviews'
    if (-not [string]::Equals((Split-Path $full -Parent),$expectedDirectory,(Get-ExecutionPathComparison)) -or
        (Split-Path $full -Leaf) -notmatch ('^'+[regex]::Escape($Id)+'-review-[0-9]+\.md$')) {
        throw 'Review intake receipt path is not a canonical task review.'
    }
    $item=Get-Item -LiteralPath $full -Force
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Review intake receipt traverses a reparse point.' }
        if ([string]::Equals($item.FullName,$root,(Get-ExecutionPathComparison))) { break }
        $parent=Split-Path $item.FullName -Parent
        if (-not $parent) { throw 'Review intake receipt path escaped project.' }
        $item=Get-Item -LiteralPath $parent -Force
    }
    $stream=$null; $sha=$null
    try {
        $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha=[Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
    } finally {
        if($null -ne $sha){$sha.Dispose()}; if($null -ne $stream){$stream.Dispose()}
    }
}
function New-ReviewIntakeReceipt {
    param([string]$ProjectPath,[string]$Id,[object]$Lease,[string]$ReviewPath,
          [ValidateSet('APPROVE','CHANGES_REQUIRED')][string]$Recommendation,
          [Parameter(Mandatory=$true)][object]$GroundingValidation)
    Assert-TaskExecutionLease -ProjectPath $ProjectPath -Id $Id -Lease $Lease
    if (-not (Get-Command Assert-ReviewGroundingValidation -ErrorAction SilentlyContinue)) {
        throw 'Review intake receipt requires installed registered grounding validation.'
    }
    Assert-ReviewGroundingValidation -ProjectPath $ProjectPath -Id $Id -Lease $Lease -Validation $GroundingValidation -Recommendation $Recommendation
    $receipt=[PSCustomObject]@{ReceiptId=[Guid]::NewGuid().ToString('N')}
    $global:AicoReviewIntakeReceipts[$receipt.ReceiptId]=[PSCustomObject]@{
        Receipt=$receipt; Lease=$Lease; Project=[IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path)
        TaskId=$Id; Path=[IO.Path]::GetFullPath($ReviewPath); Recommendation=$Recommendation
        Digest=(Get-ReviewIntakeDigest -ProjectPath $ProjectPath -Id $Id -ReviewPath $ReviewPath); ProcessId=$PID
    }
    return $receipt
}
function Assert-ReviewIntakeReceipt {
    param([string]$ProjectPath,[string]$Id,[object]$Lease,[object]$Receipt,
          [ValidateSet('APPROVE','CHANGES_REQUIRED')][string]$Recommendation)
    Assert-TaskExecutionLease -ProjectPath $ProjectPath -Id $Id -Lease $Lease
    $entries=@($global:AicoReviewIntakeReceipts.Values | Where-Object { [object]::ReferenceEquals($_.Receipt,$Receipt) })
    if($entries.Count -ne 1){throw 'Review intake requires a registered process-local grounded receipt.'}
    $entry=$entries[0]
    if($entry.ProcessId -ne $PID -or $entry.TaskId -cne $Id -or $entry.Recommendation -cne $Recommendation -or
        -not [object]::ReferenceEquals($entry.Lease,$Lease) -or
        -not [string]::Equals($entry.Project,[IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path),(Get-ExecutionPathComparison)) -or
        $entry.Digest -cne (Get-ReviewIntakeDigest -ProjectPath $ProjectPath -Id $Id -ReviewPath $entry.Path)) {
        throw 'Review intake receipt identity, recommendation or artifact digest is stale or invalid.'
    }
}
