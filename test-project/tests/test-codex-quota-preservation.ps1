param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$baseTemp = $env:TEMP
$tempRoot = Join-Path $baseTemp ("aico codex p1 spaces " + [Guid]::NewGuid().ToString("N"))
$binPath = Join-Path $tempRoot "fake bin"
$runtimeTemp = Join-Path $tempRoot "runtime temp"
$savedPath = $env:PATH
$savedTemp = $env:TEMP

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

try {
    foreach ($dir in @($tempRoot,$binPath,$runtimeTemp)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $schemaPath = Join-Path $tempRoot "schema.json"
    $outputPath = Join-Path $tempRoot "result.json"
    Write-Utf8NoBom $schemaPath '{"type":"object"}'

    $fakeCodexPath = Join-Path $binPath "codex.ps1"
    Write-Utf8NoBom $fakeCodexPath @'
[Console]::Out.WriteLine("You've hit your usage limit. Try again at 21:00.")
[Console]::Error.WriteLine("Secondary CLI diagnostic after quota exhaustion.")
exit 1
'@

    $env:PATH = $binPath + [System.IO.Path]::PathSeparator + $savedPath
    $env:TEMP = $runtimeTemp

    function Remove-Item {
        param(
            [Parameter(Position = 0)]
            [string]$Path,
            [switch]$Force,
            [switch]$Recurse,
            [System.Management.Automation.ActionPreference]$ErrorAction = [System.Management.Automation.ActionPreference]::Continue
        )

        if ([string]$Path -like "*-prompt.txt") {
            throw "No existe ningún objeto en la ruta de acceso especificada, C:\Users\LANAVE~1."
        }

        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $Path -Force:$Force -Recurse:$Recurse -ErrorAction $ErrorAction
    }

    $quotaPreserved = $false

    try {
        $invokeArgs = @{
            ProjectPath = $tempRoot
            Prompt = "Codex quota preservation fixture"
            SchemaPath = $schemaPath
            OutputPath = $outputPath
            TimeoutSeconds = 30
        }

        & (Join-Path $repoRoot "scripts\providers\invoke-codex.ps1") @invokeArgs | Out-Null
    }
    catch {
        $message = [string]$_.Exception.Message

        if ($message -match 'C:\\Users\\LANAVE~1') {
            throw "Incidental cleanup path error replaced the primary Codex quota failure."
        }

        if ($message -match '(?i)usage quota is exhausted') {
            $quotaPreserved = $true
        }
        else {
            throw "Codex quota failure was not preserved. Actual: $message"
        }
    }

    if (-not $quotaPreserved) {
        throw "Codex quota exhaustion was not preserved as the authoritative provider error."
    }

    if (Test-Path $outputPath) {
        throw "Failed Codex quota execution must not leave structured output behind."
    }

    Write-Host "PASS: Codex quota preservation and Windows space-path cleanup" -ForegroundColor Green
}
finally {
    Microsoft.PowerShell.Management\Remove-Item Function:\Remove-Item -ErrorAction SilentlyContinue
    $env:PATH = $savedPath
    $env:TEMP = $savedTemp

    if (Test-Path $tempRoot) {
        Microsoft.PowerShell.Management\Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
