function Get-TaskExecutionLockPath {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$Id
    )

    $root = (Resolve-Path $ProjectPath).Path
    $runtimeDir = Join-Path $root ".codex\runtime\locks"
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

    $safeId = ($Id -replace '[^A-Za-z0-9_.-]','_')
    return (Join-Path $runtimeDir ($safeId + ".lock"))
}

function Enter-TaskExecutionLock {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    $path = Get-TaskExecutionLockPath -ProjectPath $ProjectPath -Id $Id
    $stream = $null

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

    return [PSCustomObject]@{
        Path = $path
        Stream = $stream
        TaskId = $Id
        Operation = $Operation
    }
}

function Exit-TaskExecutionLock {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Lock
    )

    if ($null -eq $Lock) { return }

    try {
        if ($null -ne $Lock.Stream) {
            $Lock.Stream.Dispose()
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
