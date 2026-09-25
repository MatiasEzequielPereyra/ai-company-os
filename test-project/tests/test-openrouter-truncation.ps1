param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-openrouter-length-" + [Guid]::NewGuid().ToString("N"))
$previousKey = $env:OPENROUTER_API_KEY

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $schemaPath = Join-Path $tempRoot "schema.json"
    $outputPath = Join-Path $tempRoot "result.json"

    [System.IO.File]::WriteAllText(
        $schemaPath,
        '{"type":"object","properties":{"value":{"type":"string"}},"required":["value"],"additionalProperties":false}',
        (New-Object System.Text.UTF8Encoding($false))
    )

    $env:OPENROUTER_API_KEY = "test-key"

    function Invoke-RestMethod {
        param(
            [string]$Method,
            [string]$Uri,
            [hashtable]$Headers,
            [string]$ContentType,
            [byte[]]$Body,
            [int]$TimeoutSec
        )

        return [PSCustomObject]@{
            model = "stub/schema-model"
            choices = @(
                [PSCustomObject]@{
                    finish_reason = "length"
                    message = [PSCustomObject]@{
                        content = '{"value":"syntactically valid but truncated completion"}'
                    }
                }
            )
        }
    }

    $failed = $false
    try {
        $invokeArgs = @{
            Prompt = "structured test"
            Context = "context"
            SchemaPath = $schemaPath
            OutputPath = $outputPath
            Model = "openrouter/free"
        }
        & (Join-Path $repoRoot "scripts\providers\invoke-openrouter.ps1") @invokeArgs | Out-Null
    }
    catch {
        $failed = $true
        $message = [string]$_.Exception.Message
        if ($message -notmatch 'finish_reason:\s*length|finish_reason=length|truncated') {
            throw "OpenRouter length rejection must explain truncation. Actual: $message"
        }
    }

    if (-not $failed) {
        throw "OpenRouter finish_reason=length must be rejected even when content is valid JSON"
    }

    if (Test-Path $outputPath) {
        throw "Truncated OpenRouter structured output must never be persisted"
    }

    Write-Host "PASS: OpenRouter structured truncation rejection" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $previousKey
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}
