param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Context,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = "qwen2.5-coder:14b"
)

$ErrorActionPreference = "Stop"

function Get-HttpStatusCode {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    try {
        $response = $ErrorRecord.Exception.Response
        if ($null -eq $response -or $null -eq $response.StatusCode) { return 0 }
        return [int]$response.StatusCode
    }
    catch { return 0 }
}

function Test-TransientOllamaError {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord,[int]$StatusCode)

    if ($StatusCode -eq 429 -or $StatusCode -ge 500) { return $true }

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match '(?i)timed out|timeout|connection.*closed|connection reset|actively refused|unable to connect|underlying connection was closed') {
        return $true
    }

    return $false
}

function Get-HttpErrorBody {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($null -ne $ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        return [string]$ErrorRecord.ErrorDetails.Message
    }

    try {
        $response = $ErrorRecord.Exception.Response
        if ($null -eq $response) { return "" }

        $stream = $response.GetResponseStream()
        if ($null -eq $stream) { return "" }

        $reader = New-Object System.IO.StreamReader($stream)
        try { return $reader.ReadToEnd() }
        finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    }
    catch { return "" }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$baseUrl = if ([string]::IsNullOrWhiteSpace($env:OLLAMA_BASE_URL)) {
    "http://localhost:11434"
}
else {
    $env:OLLAMA_BASE_URL.TrimEnd('/')
}

$schemaText = Get-Content $SchemaPath -Raw -Encoding UTF8
$schema = $schemaText | ConvertFrom-Json

$fullPrompt = @(
    $Prompt,
    "",
    "# Repository Context Pack",
    $Context,
    "",
    "# Required JSON Schema",
    "Return only one JSON object matching this schema exactly:",
    $schemaText
) -join [Environment]::NewLine

$body = @{
    model = $Model
    messages = @(
        @{
            role = "user"
            content = $fullPrompt
        }
    )
    stream = $false
    format = $schema
    options = @{
        temperature = 0
        num_ctx = 16384
        num_predict = 4096
    }
} | ConvertTo-Json -Depth 100 -Compress

try { $null = $body | ConvertFrom-Json }
catch { throw "Ollama request payload is invalid JSON before transport: $($_.Exception.Message)" }

$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$response = $null
$maxAttempts = 3

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        $response = Invoke-RestMethod -Method Post -Uri ($baseUrl + "/api/chat") -ContentType "application/json; charset=utf-8" -Body $bodyBytes -TimeoutSec 600
        break
    }
    catch {
        $statusCode = Get-HttpStatusCode -ErrorRecord $_
        $message = Get-HttpErrorBody -ErrorRecord $_
        if ([string]::IsNullOrWhiteSpace($message)) { $message = $_.Exception.Message }

        $isTransient = Test-TransientOllamaError -ErrorRecord $_ -StatusCode $statusCode
        if ($isTransient -and $attempt -lt $maxAttempts) {
            $delaySeconds = [Math]::Pow(2,($attempt - 1))
            Write-Host ("Ollama transient failure on attempt " + $attempt + "/" + $maxAttempts + ". Retrying in " + $delaySeconds + "s...") -ForegroundColor Yellow
            Start-Sleep -Seconds $delaySeconds
            continue
        }

        if ($statusCode -eq 404 -and $message -match '(?i)model') {
            throw ("Ollama model is not available locally. Run: ollama pull " + $Model + ". Details: " + $message)
        }

        throw "Ollama request failed: $message"
    }
}

if ($null -eq $response) {
    throw "Ollama request failed without a response after $maxAttempts attempts."
}

if ($null -eq $response.message -or [string]::IsNullOrWhiteSpace([string]$response.message.content)) {
    throw "Ollama returned no completion content."
}

$content = ([string]$response.message.content).Trim()

try {
    $parsed = $content | ConvertFrom-Json
}
catch {
    throw "Ollama returned invalid JSON for the structured result contract."
}

$normalized = $parsed | ConvertTo-Json -Depth 100 -Compress
[System.IO.File]::WriteAllText($OutputPath,$normalized,(New-Object System.Text.UTF8Encoding($false)))

[PSCustomObject]@{
    Provider = "Ollama"
    Model = $(if ($null -ne $response.model) { [string]$response.model } else { $Model })
}
