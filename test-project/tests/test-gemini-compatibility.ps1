param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("aico-gemini-schema-p1-" + [Guid]::NewGuid().ToString("N"))
$savedKey = $env:GEMINI_API_KEY
$savedCapture = $env:AICO_P1_GEMINI_CAPTURE

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
    "value": {
      "type": "string",
      "minLength": 1,
      "maxLength": 20,
      "pattern": "^[a-z]+$"
    },
    "items": {
      "type": "array",
      "minItems": 1,
      "maxItems": 3,
      "items": {
        "type": "string"
      }
    }
  },
  "required": ["value", "items"],
  "additionalProperties": false
}
'@

    $env:GEMINI_API_KEY = "p1-gemini-fixture"
    $env:AICO_P1_GEMINI_CAPTURE = $capturePath

    function Invoke-RestMethod {
        param(
            [string]$Method,
            [string]$Uri,
            [hashtable]$Headers,
            [string]$ContentType,
            [byte[]]$Body,
            [int]$TimeoutSec
        )

        [System.IO.File]::WriteAllText(
            $env:AICO_P1_GEMINI_CAPTURE,
            [System.Text.Encoding]::UTF8.GetString($Body),
            (New-Object System.Text.UTF8Encoding($false))
        )

        return [PSCustomObject]@{
            candidates = @(
                [PSCustomObject]@{
                    content = [PSCustomObject]@{
                        parts = @(
                            [PSCustomObject]@{
                                text = '{"value":"ok","items":["one"]}'
                            }
                        )
                    }
                }
            )
        }
    }

    $invokeArgs = @{
        Prompt = "Gemini compatibility fixture"
        Context = "bounded context"
        SchemaPath = $schemaPath
        OutputPath = $outputPath
        Model = "gemini-3.5-flash-lite"
        TimeoutSeconds = 30
    }

    & (Join-Path $repoRoot "scripts\providers\invoke-gemini.ps1") @invokeArgs | Out-Null

    $request = Get-Content $capturePath -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($null -ne $request.generationConfig.PSObject.Properties["temperature"]) {
        throw "Gemini 3.5 Flash-Lite request must omit retired temperature sampling."
    }
    if ($null -ne $request.generationConfig.PSObject.Properties["top_p"]) {
        throw "Gemini 3.5 Flash-Lite request must omit retired top_p sampling."
    }
    if ($null -ne $request.generationConfig.PSObject.Properties["top_k"]) {
        throw "Gemini 3.5 Flash-Lite request must omit retired top_k sampling."
    }

    $translated = $request.generationConfig.responseJsonSchema
    $valueSchema = $translated.properties.value

    foreach ($unsupported in @("minLength","maxLength","pattern")) {
        if ($null -ne $valueSchema.PSObject.Properties[$unsupported]) {
            throw "Gemini schema translation retained unsupported keyword: $unsupported"
        }
    }

    if ([int]$translated.properties.items.minItems -ne 1) {
        throw "Gemini schema translation must preserve supported minItems."
    }
    if ([int]$translated.properties.items.maxItems -ne 3) {
        throw "Gemini schema translation must preserve supported maxItems."
    }
    if ([bool]$translated.additionalProperties) {
        throw "Gemini schema translation must preserve additionalProperties=false."
    }

    if (-not (Test-Path $outputPath)) {
        throw "Gemini compatibility fixture did not persist valid JSON."
    }

    Write-Host "PASS: Gemini request and JSON Schema compatibility" -ForegroundColor Green
}
finally {
    Microsoft.PowerShell.Management\Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
    $env:GEMINI_API_KEY = $savedKey
    $env:AICO_P1_GEMINI_CAPTURE = $savedCapture

    if (Test-Path $tempRoot) {
        Microsoft.PowerShell.Management\Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
