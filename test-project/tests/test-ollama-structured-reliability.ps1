param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("aico-ollama-structured-p1-" + [Guid]::NewGuid().ToString("N"))
$savedCapture = $env:AICO_P1_OLLAMA_CAPTURE
$savedMode = $env:AICO_P1_OLLAMA_MODE

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $schemaPath = Join-Path $tempRoot "schema.json"
    $outputPath = Join-Path $tempRoot "result.json"
    $capturePath = Join-Path $tempRoot "request.json"

    Write-Utf8NoBom $schemaPath @'
{
  "type": "object",
  "properties": {
    "schema_sentinel_9f3e": {
      "type": "string"
    }
  },
  "required": ["schema_sentinel_9f3e"],
  "additionalProperties": false
}
'@

    $env:AICO_P1_OLLAMA_CAPTURE = $capturePath

    function Invoke-RestMethod {
        param(
            [string]$Method,
            [string]$Uri,
            [string]$ContentType,
            [byte[]]$Body,
            [int]$TimeoutSec
        )

        [System.IO.File]::WriteAllText(
            $env:AICO_P1_OLLAMA_CAPTURE,
            [System.Text.Encoding]::UTF8.GetString($Body),
            (New-Object System.Text.UTF8Encoding($false))
        )

        switch ($env:AICO_P1_OLLAMA_MODE) {
            "length" {
                return [PSCustomObject]@{
                    model = "qwen3:8b"
                    done = $true
                    done_reason = "length"
                    prompt_eval_count = 14000
                    eval_count = 2048
                    message = [PSCustomObject]@{
                        content = '{"schema_sentinel_9f3e":"partial"}'
                    }
                }
            }
            "malformed" {
                return [PSCustomObject]@{
                    model = "qwen3:8b"
                    done = $true
                    done_reason = "stop"
                    prompt_eval_count = 6000
                    eval_count = 700
                    message = [PSCustomObject]@{
                        content = '{"schema_sentinel_9f3e":'
                    }
                }
            }
            default {
                return [PSCustomObject]@{
                    model = "qwen3:8b"
                    done = $true
                    done_reason = "stop"
                    prompt_eval_count = 6000
                    eval_count = 900
                    message = [PSCustomObject]@{
                        content = '{"schema_sentinel_9f3e":"ok"}'
                    }
                }
            }
        }
    }

    $adapter = Join-Path $repoRoot "scripts\providers\invoke-ollama.ps1"

    $baseArgs = @{
        Prompt = "Ollama structured fixture"
        Context = ("c" * 12000)
        SchemaPath = $schemaPath
        OutputPath = $outputPath
        Model = "qwen3:8b"
        NumCtx = 16384
        NumPredict = 2048
        TimeoutSeconds = 30
    }

    $env:AICO_P1_OLLAMA_MODE = "length"
    $truncatedRejected = $false

    try {
        & $adapter @baseArgs | Out-Null
    }
    catch {
        $message = [string]$_.Exception.Message
        if ($message -notmatch '(?i)done_reason.*length|truncat') {
            throw "Ollama truncation error lacks done_reason diagnostics. Actual: $message"
        }
        if ($message -notmatch '2048') {
            throw "Ollama truncation error lacks eval/output-token diagnostics. Actual: $message"
        }
        $truncatedRejected = $true
    }

    if (-not $truncatedRejected) {
        throw "Ollama done_reason=length must reject the structured response."
    }
    if (Test-Path $outputPath) {
        throw "Truncated Ollama structured output must never be persisted."
    }

    $env:AICO_P1_OLLAMA_MODE = "stop"
    $result = & $adapter @baseArgs

    $request = Get-Content $capturePath -Raw -Encoding UTF8 | ConvertFrom-Json

    if ([string]$request.messages[0].content -notmatch 'schema_sentinel_9f3e') {
        throw "Ollama structured prompt must retain schema grounding alongside format."
    }
    if ($null -eq $request.format.properties.schema_sentinel_9f3e) {
        throw "Ollama request must supply the structured schema through format."
    }

    if ([string]$result.DoneReason -ne "stop") {
        throw "Ollama adapter must expose done_reason for diagnostics."
    }
    if ([int]$result.PromptEvalCount -ne 6000) {
        throw "Ollama adapter must expose prompt_eval_count for diagnostics."
    }
    if ([int]$result.EvalCount -ne 900) {
        throw "Ollama adapter must expose eval_count for diagnostics."
    }

    Microsoft.PowerShell.Management\Remove-Item $outputPath -Force -ErrorAction SilentlyContinue

    $env:AICO_P1_OLLAMA_MODE = "malformed"
    $malformedRejected = $false

    try {
        & $adapter @baseArgs | Out-Null
    }
    catch {
        $message = [string]$_.Exception.Message
        if ($message -match '(?i)invalid JSON') {
            $malformedRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $malformedRejected) {
        throw "Malformed Ollama JSON must be rejected."
    }
    if (Test-Path $outputPath) {
        throw "Malformed Ollama JSON must never be persisted."
    }

    Write-Host "PASS: Ollama structured-output truncation and diagnostics" -ForegroundColor Green
}
finally {
    Microsoft.PowerShell.Management\Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
    $env:AICO_P1_OLLAMA_CAPTURE = $savedCapture
    $env:AICO_P1_OLLAMA_MODE = $savedMode

    if (Test-Path $tempRoot) {
        Microsoft.PowerShell.Management\Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
