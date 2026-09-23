param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$Context,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = "openrouter/free"
)

$ErrorActionPreference = "Stop"

function Get-HttpStatusCode {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    try {
        $response = $ErrorRecord.Exception.Response
        if ($null -eq $response -or $null -eq $response.StatusCode) { return 0 }
        return [int]$response.StatusCode
    }
    catch {
        return 0
    }
}

function Test-TransientOpenRouterError {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [int]$StatusCode
    )

    if ($StatusCode -eq 429 -or $StatusCode -ge 500) { return $true }

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match 'timed out|timeout|connection.*closed|conexi[oó]n.*cerrada|forcibly closed|connection reset|underlying connection was closed|se ha terminado la conexi[oó]n') {
        return $true
    }

    return $false
}

function Get-HttpErrorBody {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    try {
        $response = $ErrorRecord.Exception.Response
        if ($null -eq $response) { return "" }

        $stream = $response.GetResponseStream()
        if ($null -eq $stream) { return "" }

        $reader = New-Object System.IO.StreamReader($stream)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    }
    catch {
        return ""
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ([string]::IsNullOrWhiteSpace($env:OPENROUTER_API_KEY)) {
    throw "OPENROUTER_API_KEY is not configured."
}

$schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json
$fullPrompt = $Prompt + [Environment]::NewLine + [Environment]::NewLine + "# Repository Context Pack" + [Environment]::NewLine + $Context

$body = @{
    model = $Model
    messages = @(
        @{
            role = "user"
            content = $fullPrompt
        }
    )
    temperature = 0.1
    max_tokens = 12000
    response_format = @{
        type = "json_schema"
        json_schema = @{
            name = "agent_result"
            strict = $true
            schema = $schema
        }
    }
} | ConvertTo-Json -Depth 100 -Compress

# Validate the exact serialized payload before it leaves the machine.
try {
    $null = $body | ConvertFrom-Json
}
catch {
    throw "OpenRouter request payload is invalid JSON before transport: $($_.Exception.Message)"
}

# Windows PowerShell 5.1 can choose an unexpected encoding for large string bodies.
# Send explicit UTF-8 bytes so OpenRouter receives the same JSON we validated locally.
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
Write-Host ("OpenRouter payload: " + $body.Length + " chars / " + $bodyBytes.Length + " UTF-8 bytes") -ForegroundColor DarkGray

$headers = @{
    Authorization = "Bearer $($env:OPENROUTER_API_KEY)"
    "X-Title" = "AI Company OS"
}

$response = $null
$maxAttempts = 3

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        $response = Invoke-RestMethod -Method Post -Uri "https://openrouter.ai/api/v1/chat/completions" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $bodyBytes -TimeoutSec 240
        break
    }
    catch {
        $statusCode = Get-HttpStatusCode -ErrorRecord $_
        $message = $_.Exception.Message
        $errorBody = Get-HttpErrorBody -ErrorRecord $_

        if (-not [string]::IsNullOrWhiteSpace($errorBody)) {
            $message = $errorBody
        }
        elseif ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            $message = $_.ErrorDetails.Message
        }

        $isTransient = Test-TransientOpenRouterError -ErrorRecord $_ -StatusCode $statusCode

        if ($isTransient -and $attempt -lt $maxAttempts) {
            $delaySeconds = [Math]::Pow(2,($attempt - 1))
            Write-Host ("OpenRouter transient failure on attempt " + $attempt + "/" + $maxAttempts + ". Retrying in " + $delaySeconds + "s...") -ForegroundColor Yellow
            Start-Sleep -Seconds $delaySeconds
            continue
        }

        throw "OpenRouter request failed: $message"
    }
}

if ($null -eq $response) {
    throw "OpenRouter request failed without a response after $maxAttempts attempts."
}

if ($null -eq $response.choices -or $response.choices.Count -lt 1) {
    throw "OpenRouter returned no completion choices."
}

$content = $response.choices[0].message.content
if ($content -isnot [string]) {
    $parts = @()
    foreach ($part in $content) {
        if ($null -ne $part.text) { $parts += [string]$part.text }
    }
    $content = $parts -join ""
}

$content = ([string]$content).Trim()

try { $null = $content | ConvertFrom-Json }
catch { throw "OpenRouter returned invalid JSON for the agent result contract." }

[System.IO.File]::WriteAllText($OutputPath,$content,(New-Object System.Text.UTF8Encoding($false)))

[PSCustomObject]@{
    Provider = "OpenRouter"
    Model = $(if ($null -ne $response.model) { [string]$response.model } else { $Model })
}
