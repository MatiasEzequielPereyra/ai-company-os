param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = ""
)

$ErrorActionPreference = "Stop"

$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($null -eq $codex) { throw "Codex CLI is not available in PATH." }

$args = @("exec","--sandbox","read-only","--output-schema",$SchemaPath,"-o",$OutputPath)
if (-not [string]::IsNullOrWhiteSpace($Model)) { $args += @("--model",$Model) }
$args += "-"

$savedApiKey = $env:CODEX_API_KEY
$env:CODEX_API_KEY = $null

Push-Location $ProjectPath
try {
    $output = New-Object System.Collections.Generic.List[string]

    $Prompt | & codex @args 2>&1 | ForEach-Object {
        $line = $_.ToString()
        [void]$output.Add($line)
        Write-Host $line
    }

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $message = ($output.ToArray()) -join [Environment]::NewLine
        if ($message -match "(?i)usage limit|purchase more credits|try again at|no credits remaining") {
            throw "Codex is unavailable because its current usage quota is exhausted."
        }
        throw "Codex exec failed with exit code $exitCode."
    }
}
finally {
    $env:CODEX_API_KEY = $savedApiKey
    Pop-Location
}

if (-not (Test-Path $OutputPath)) { throw "Codex did not produce the expected structured result." }

[PSCustomObject]@{
    Provider = "Codex"
    Model = $(if ([string]::IsNullOrWhiteSpace($Model)) { "configured-default" } else { $Model })
}
