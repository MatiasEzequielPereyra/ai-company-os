param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = "",
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

function ConvertTo-PowerShellLiteral {
    param([string]$Value)

    return "'" + ([string]$Value).Replace("'","''") + "'"
}

function Stop-ProcessTree {
    param([int]$ProcessId)

    if ($ProcessId -le 0) { return }

    if ($env:OS -eq "Windows_NT") {
        $taskkill = Join-Path $env:SystemRoot "System32\taskkill.exe"
        if (Test-Path $taskkill) {
            & $taskkill /PID $ProcessId /T /F 2>$null | Out-Null
            return
        }
    }

    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($null -eq $codex) { throw "Codex CLI is not available in PATH." }

$codexPath = ""
foreach ($candidate in @(
    [string]$codex.Path,
    [string]$codex.Source,
    [string]$codex.Definition
)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate -PathType Leaf)) {
        $codexPath = (Resolve-Path $candidate).Path
        break
    }
}

if ([string]::IsNullOrWhiteSpace($codexPath)) {
    throw "Unable to resolve Codex CLI executable path."
}

$root = (Resolve-Path $ProjectPath).Path
$schema = (Resolve-Path $SchemaPath).Path
$outputParent = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputParent) -and -not (Test-Path $outputParent)) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Force
}

$arguments = @("exec","--sandbox","read-only","--output-schema",$schema,"-o",$OutputPath)
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $arguments += @("--model",$Model)
}
$arguments += "-"

$tempRoot = Join-Path $env:TEMP "ai-company-os-codex-runtime"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

$token = [Guid]::NewGuid().ToString("N")
$promptPath = Join-Path $tempRoot ($token + "-prompt.txt")
$runnerPath = Join-Path $tempRoot ($token + "-runner.ps1")

[System.IO.File]::WriteAllText(
    $promptPath,
    $Prompt,
    (New-Object System.Text.UTF8Encoding($false))
)

$argumentLiterals = @($arguments | ForEach-Object { ConvertTo-PowerShellLiteral -Value ([string]$_) }) -join ","
$rootLiteral = ConvertTo-PowerShellLiteral -Value $root
$promptLiteral = ConvertTo-PowerShellLiteral -Value $promptPath
$codexLiteral = ConvertTo-PowerShellLiteral -Value $codexPath

$runner = @"
`$ErrorActionPreference = "Stop"
`$env:CODEX_API_KEY = `$null
Set-Location $rootLiteral
`$codexArguments = @($argumentLiterals)
`$promptText = Get-Content $promptLiteral -Raw -Encoding UTF8
`$promptText | & $codexLiteral @codexArguments 2>&1
exit `$LASTEXITCODE
"@

[System.IO.File]::WriteAllText(
    $runnerPath,
    $runner,
    (New-Object System.Text.UTF8Encoding($false))
)

$hostExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ([string]::IsNullOrWhiteSpace($hostExecutable) -or -not (Test-Path $hostExecutable -PathType Leaf)) {
    $hostCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -eq $hostCommand) {
        $hostCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    }
    if ($null -eq $hostCommand) {
        throw "Unable to resolve a PowerShell host for bounded Codex execution."
    }
    $hostExecutable = [string]$hostCommand.Source
}

$savedApiKey = $env:CODEX_API_KEY
$env:CODEX_API_KEY = $null

$process = $null
$stdoutTask = $null
$stderrTask = $null

try {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $hostExecutable
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $runnerPath.Replace('"','\"') + '"'
    $startInfo.WorkingDirectory = $root
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    if (-not $process.Start()) {
        throw "Codex process could not be started."
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $timeoutMilliseconds = [int]([Math]::Min([long]$TimeoutSeconds * 1000L,[int]::MaxValue))
    $completed = $process.WaitForExit($timeoutMilliseconds)

    if (-not $completed) {
        $processId = $process.Id
        Stop-ProcessTree -ProcessId $processId

        try {
            [void]$process.WaitForExit(5000)
        }
        catch {}

        if (Test-Path $OutputPath) {
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }

        throw "Codex execution timed out after $TimeoutSeconds seconds. Process tree was terminated."
    }

    # Ensure redirected async streams have fully drained after process exit.
    $process.WaitForExit()

    $stdout = if ($null -ne $stdoutTask) { [string]$stdoutTask.Result } else { "" }
    $stderr = if ($null -ne $stderrTask) { [string]$stderrTask.Result } else { "" }

    foreach ($line in @($stdout -split "\r?\n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host $line
        }
    }
    foreach ($line in @($stderr -split "\r?\n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host $line
        }
    }

    $exitCode = $process.ExitCode
    if ($exitCode -ne 0) {
        if (Test-Path $OutputPath) {
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }

        $message = @($stdout,$stderr) -join [Environment]::NewLine
        if ($message -match "(?i)usage limit|purchase more credits|try again at|no credits remaining") {
            throw "Codex is unavailable because its current usage quota is exhausted."
        }

        throw "Codex exec failed with exit code $exitCode."
    }

    if (-not (Test-Path $OutputPath)) {
        throw "Codex did not produce the expected structured result."
    }
}
catch {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-ProcessTree -ProcessId $process.Id
        try { [void]$process.WaitForExit(5000) } catch {}
    }

    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
    }

    throw
}
finally {
    $env:CODEX_API_KEY = $savedApiKey

    if ($null -ne $process) {
        $process.Dispose()
    }

    foreach ($temporaryPath in @($promptPath,$runnerPath)) {
        if (Test-Path $temporaryPath) {
            Remove-Item $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

[PSCustomObject]@{
    Provider = "Codex"
    Model = $(if ([string]::IsNullOrWhiteSpace($Model)) { "configured-default" } else { $Model })
}
