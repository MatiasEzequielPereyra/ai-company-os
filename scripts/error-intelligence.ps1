param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][hashtable]$Event
)

# This observer is deliberately isolated from provider execution and lifecycle decisions.
$ErrorActionPreference = 'Stop'
if ($env:AICO_ERROR_INTELLIGENCE_ENABLED -eq '0') { return }
$supported = ($Event.event_type -eq 'runtime_failure') -or
    ($Event.event_type -eq 'provider_context_rejected') -or
    ($Event.event_type -eq 'provider_attempt_finished' -and $Event.success -eq $false) -or
    ($Event.event_type -eq 'task_transition' -and
        ($Event.to_status -eq 'BLOCKED' -or
        ($Event.to_status -eq 'READY' -and $Event.from_status -in @('REVIEW','QA','SECURITY'))))
if (-not $supported) { return }
$process = $null
$captureStage = 'configuration'
$previousPythonPath = $env:PYTHONPATH
try {
    $engineRoot = Split-Path $PSScriptRoot -Parent
    $python = $env:AICO_ERROR_INTELLIGENCE_PYTHON
    if ([string]::IsNullOrWhiteSpace($python)) {
        foreach ($candidate in @((Join-Path $engineRoot '.aico-python/Scripts/python.exe'), (Join-Path $engineRoot '.aico-python/python.exe'), (Join-Path $engineRoot '.aico-python/bin/python'))) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $python = $candidate; break }
        }
    }
    if ([string]::IsNullOrWhiteSpace($python)) { $python = (Get-Command python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
    $moduleRoot = $env:AICO_ERROR_INTELLIGENCE_MODULE_ROOT
    if ([string]::IsNullOrWhiteSpace($moduleRoot) -and (Test-Path -LiteralPath (Join-Path $engineRoot 'src/company_os'))) { $moduleRoot = Join-Path $engineRoot 'src' }
    if (-not [string]::IsNullOrWhiteSpace($moduleRoot)) {
        $env:PYTHONPATH = $moduleRoot
        if (-not [string]::IsNullOrWhiteSpace($previousPythonPath)) { $env:PYTHONPATH += [IO.Path]::PathSeparator + $previousPythonPath }
    }
    $root = (Resolve-Path -LiteralPath $ProjectPath).Path
    # Project paths are a single Windows command-line argument. Backslashes before
    # the closing quote must be doubled, including drive-root paths.
    $quotedRoot = '"' + ([regex]::Replace($root, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $python
    $start.Arguments = '-m company_os.error_intelligence.runtime capture --project ' + $quotedRoot
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['PYTHONUTF8'] = '1'
    $start.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    $captureStage = 'start'
    if (-not $process.Start()) { throw 'START_FAILED' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Event | ConvertTo-Json -Depth 10 -Compress))
    $captureStage = 'stdin'
    $write = $process.StandardInput.BaseStream.WriteAsync($bytes, 0, $bytes.Length)
    if (-not $write.Wait(1000)) { throw 'STDIN_TIMEOUT' }
    $process.StandardInput.Close()
    $captureStage = 'execution'
    if (-not $process.WaitForExit(3500)) { throw 'CAPTURE_TIMEOUT' }
    if ($process.ExitCode -ne 0) {
        $captureStage = 'exit_' + $process.ExitCode
        if ($stderr.Wait(100) -and $stderr.Result -match 'No module named') { $captureStage = 'module_unavailable' }
        throw 'CAPTURE_FAILED'
    }
    if (-not $stdout.Wait(100) -or -not $stderr.Wait(100)) { throw 'CAPTURE_TIMEOUT' }
    $captureStage = 'result'
    $result = $stdout.Result | ConvertFrom-Json
    if ($null -eq $result -or $result.status -eq 'unavailable') { throw 'CAPTURE_UNAVAILABLE' }
    if ($null -ne $result -and [string]$result.incident_id -match '^[a-zA-Z0-9_-]{1,80}$') {
        Write-Host ('Error Intelligence: incident=' + $result.incident_id + '; occurrences=' + [int]$result.occurrence_count + '; verified_solution=' + [bool]$result.verified_solution_available) -ForegroundColor DarkYellow
        foreach ($solution in @($result.verified_solutions | Select-Object -First 3)) {
            if ($null -ne $solution -and $solution.verified_solution) {
                Write-Host ('Error Intelligence historical advice (requires revalidation): ' + ($solution | ConvertTo-Json -Depth 5 -Compress)) -ForegroundColor DarkYellow
            }
        }
    }
}
catch {
    Write-Host ('ERROR_INTELLIGENCE_CAPTURE_UNAVAILABLE; stage=' + $captureStage + '; exception=' + $_.Exception.GetType().Name) -ForegroundColor DarkYellow
}
finally {
    $env:PYTHONPATH = $previousPythonPath
    if ($null -ne $process) {
        try { if (-not $process.HasExited) { $process.Kill() } } catch { }
        $process.Dispose()
    }
}
