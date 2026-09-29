param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Context,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = "deepseek-flash"
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

function Test-TransientDeepSeekError {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord,[int]$StatusCode)

    if ($StatusCode -eq 429 -or $StatusCode -ge 500) { return $true }

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match '(?i)timed out|timeout|connection.*closed|connection reset|underlying connection was closed') {
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

if ([string]::IsNullOrWhiteSpace($env:DEEPSEEK_API_KEY)) {
    throw "DEEPSEEK_API_KEY is not configured."
}

$schemaText = Get-Content $SchemaPath -Raw -Encoding UTF8
$null = $schemaText | ConvertFrom-Json

$fullPrompt = @(
    $Prompt,
    "",
    "# Repository Context Pack",
    $Context,
    "",
    "# Required JSON Contract",
    "Return only valid JSON. The object must satisfy this JSON Schema; local validation will reject any mismatch:",
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
    temperature = 0.1
    max_tokens = 12000
    response_format = @{
        type = "json_object"
    }
} | ConvertTo-Json -Depth 100 -Compress

try { $null = $body | ConvertFrom-Json }
catch { throw "DeepSeek request payload is invalid JSON before transport: $($_.Exception.Message)" }

$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$headers = @{
    Authorization = "Bearer $($env:DEEPSEEK_API_KEY)"
}

$response = $null
$maxAttempts = 3

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        $response = Invoke-RestMethod -Method Post -Uri "https://api.deepseek.com/chat/completions" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $bodyBytes -TimeoutSec 300
        break
    }
    catch {
        $statusCode = Get-HttpStatusCode -ErrorRecord $_
        $message = Get-HttpErrorBody -ErrorRecord $_
        if ([string]::IsNullOrWhiteSpace($message)) { $message = $_.Exception.Message }

        $isTransient = Test-TransientDeepSeekError -ErrorRecord $_ -StatusCode $statusCode
        if ($isTransient -and $attempt -lt $maxAttempts) {
            $delaySeconds = [Math]::Pow(2,($attempt - 1))
            Write-Host ("DeepSeek transient failure on attempt " + $attempt + "/" + $maxAttempts + ". Retrying in " + $delaySeconds + "s...") -ForegroundColor Yellow
            Start-Sleep -Seconds $delaySeconds
            continue
        }

        throw "DeepSeek request failed: $message"
    }
}

if ($null -eq $response) {
    throw "DeepSeek request failed without a response after $maxAttempts attempts."
}

if ($null -eq $response.choices -or $response.choices.Count -lt 1) {
    throw "DeepSeek returned no completion choices."
}

$content = ([string]$response.choices[0].message.content).Trim()
if ([string]::IsNullOrWhiteSpace($content)) {
    throw "DeepSeek returned empty completion content."
}

try {
    $parsed = $content | ConvertFrom-Json
}
catch {
    throw "DeepSeek returned invalid JSON for the structured result contract."
}

$normalized = $parsed | ConvertTo-Json -Depth 100 -Compress
[System.IO.File]::WriteAllText($OutputPath,$normalized,(New-Object System.Text.UTF8Encoding($false)))

[PSCustomObject]@{
    Provider = "DeepSeek"
    Model = $(if ($null -ne $response.model) { [string]$response.model } else { $Model })
}
