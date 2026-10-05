param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = "",
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

function Test-SchemaAllowsNull {
    param([object]$Node)
    if (@($Node.type) -contains 'null') { return $true }
    return $false
}

function ConvertTo-CodexSchema {
    param([object]$Node)
    if ($null -eq $Node) { return }
    foreach ($keyword in @('anyOf','oneOf','allOf','$ref','$defs','definitions')) {
        if ($null -ne $Node.PSObject.Properties[$keyword]) { throw "Unsupported canonical Codex schema keyword: $keyword" }
    }
    if ($null -ne $Node.additionalProperties -and $Node.additionalProperties -ne $false) { throw 'Codex schema adaptation cannot narrow additionalProperties.' }
    if ($null -ne $Node.items) { ConvertTo-CodexSchema $Node.items }
    if ($null -eq $Node.properties) { return }
    $originalRequired = @($Node.required)
    $names = @($Node.properties.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($property in @($Node.properties.PSObject.Properties)) {
        $wasNullable = Test-SchemaAllowsNull $property.Value
        ConvertTo-CodexSchema $property.Value
        if ($originalRequired -notcontains $property.Name -and -not $wasNullable) {
            $Node.properties.PSObject.Properties[$property.Name].Value = [pscustomobject]@{ anyOf=@($property.Value,[pscustomobject]@{type='null'}) }
        }
    }
    $Node | Add-Member -NotePropertyName required -NotePropertyValue $names -Force
    $Node | Add-Member -NotePropertyName additionalProperties -NotePropertyValue $false -Force
}

function Remove-AdapterNulls {
    param([object]$Value,[object]$Node)
    if ($null -eq $Value -or $null -eq $Node) { return }
    if ($null -ne $Node.properties -and $Value -is [pscustomobject]) {
        foreach ($property in @($Node.properties.PSObject.Properties)) {
            $actual = $Value.PSObject.Properties[$property.Name]
            if ($null -eq $actual) { continue }
            if ($null -eq $actual.Value -and @($Node.required) -notcontains $property.Name -and -not (Test-SchemaAllowsNull $property.Value)) {
                $Value.PSObject.Properties.Remove($property.Name)
            } else { Remove-AdapterNulls $actual.Value $property.Value }
        }
    }
    if ($null -ne $Node.items -and $Value -is [array]) { foreach ($item in $Value) { Remove-AdapterNulls $item $Node.items } }
}

function ConvertTo-PowerShellLiteral {
    param([string]$Value)

    return "'" + ([string]$Value).Replace("'","''") + "'"
}

function Remove-TemporaryFileBestEffort {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    try {
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Delete($Path)
        }
    }
    catch {
        # Cleanup must never replace the provider's primary failure.
        Write-Host (
            "Codex temporary-file cleanup warning: " +
            [System.IO.Path]::GetFileName($Path)
        ) -ForegroundColor DarkYellow
    }
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

$temporarySchemaPath = $null
$promptPath = $null
$runnerPath = $null
$savedApiKey = $env:CODEX_API_KEY
$process = $null
try {
    $canonicalSchema = Get-Content -LiteralPath $schema -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($canonicalSchema.type -ne 'object' -or $null -ne $canonicalSchema.anyOf -or $null -ne $canonicalSchema.oneOf) { throw 'Codex structured output requires a root object schema without a root union.' }
    $providerSchema = Get-Content -LiteralPath $schema -Raw -Encoding UTF8 | ConvertFrom-Json
    ConvertTo-CodexSchema $providerSchema

    $arguments = @("exec","--sandbox","read-only","-o",$OutputPath)
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $arguments += @("--model",$Model)
    }
    $arguments += "-"

    $tempBase = if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    $tempRoot = Join-Path $tempBase "ai-company-os-codex-runtime"
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $token = [Guid]::NewGuid().ToString("N")
    $promptPath = Join-Path $tempRoot ($token + "-prompt.txt")
    $runnerPath = Join-Path $tempRoot ($token + "-runner.ps1")
    $temporarySchemaPath = Join-Path $tempRoot ($token + "-schema.json")
    [IO.File]::WriteAllText($temporarySchemaPath,($providerSchema | ConvertTo-Json -Depth 100),(New-Object Text.UTF8Encoding($false)))
    $arguments = @("exec","--output-schema",$temporarySchemaPath) + $arguments[1..($arguments.Count-1)]

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

    $env:CODEX_API_KEY = $null

    $process = $null
    $stdoutTask = $null
    $stderrTask = $null

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
    $normalized = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Remove-AdapterNulls $normalized $canonicalSchema
    [IO.File]::WriteAllText($OutputPath,($normalized | ConvertTo-Json -Depth 100),(New-Object Text.UTF8Encoding($false)))
    & (Join-Path (Split-Path -Parent $PSScriptRoot) 'validate-json-contract.ps1') -JsonPath $OutputPath -SchemaPath $schema | Out-Null
}
catch {
    if ($null -ne $process) {
        try {
            if (-not $process.HasExited) {
                Stop-ProcessTree -ProcessId $process.Id
                [void]$process.WaitForExit(5000)
            }
        } catch { } # A preparation/start failure may have no process handle yet.
    }

    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
    }

    throw
}
finally {
    try {
        $env:CODEX_API_KEY = $savedApiKey
    }
    catch {
        Write-Host "Codex environment cleanup warning: unable to restore CODEX_API_KEY." -ForegroundColor DarkYellow
    }

    if ($null -ne $process) {
        try {
            $process.Dispose()
        }
        catch {
            Write-Host "Codex process cleanup warning: process handle could not be disposed." -ForegroundColor DarkYellow
        }
    }

    foreach ($temporaryPath in @($promptPath,$runnerPath,$temporarySchemaPath)) {
        Remove-TemporaryFileBestEffort -Path $temporaryPath
    }
}

[PSCustomObject]@{
    Provider = "Codex"
    Model = $(if ([string]::IsNullOrWhiteSpace($Model)) { "configured-default" } else { $Model })
}
