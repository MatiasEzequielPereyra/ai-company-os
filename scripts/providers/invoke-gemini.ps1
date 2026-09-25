param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$Context,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = "gemini-3.5-flash-lite",
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 240
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-HttpStatusCode {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    try {
        $response = $ErrorRecord.Exception.Response
        if ($null -eq $response -or $null -eq $response.StatusCode) { return 0 }
        return [int]$response.StatusCode
    }
    catch { return 0 }
}

function Test-TransientGeminiError {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord,[int]$StatusCode)

    if ($StatusCode -eq 429 -or $StatusCode -ge 500) { return $true }

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match '(?i)timed out|timeout|connection.*closed|connection reset|underlying connection was closed') {
        return $true
    }

    return $false
}

if ([string]::IsNullOrWhiteSpace($env:GEMINI_API_KEY)) {
    throw "GEMINI_API_KEY is not configured."
}

$schema = Get-Content $SchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$fullPrompt = $Prompt + [Environment]::NewLine + [Environment]::NewLine + "# Repository Context Pack" + [Environment]::NewLine + $Context

$body = @{
    contents = @(
        @{
            role = "user"
            parts = @(
                @{ text = $fullPrompt }
            )
        }
    )
    generationConfig = @{
        temperature = 0.1
        maxOutputTokens = 12000
        responseMimeType = "application/json"
        responseJsonSchema = $schema
    }
} | ConvertTo-Json -Depth 100 -Compress

try { $null = $body | ConvertFrom-Json }
catch { throw "Gemini request payload is invalid JSON before transport: $($_.Exception.Message)" }

$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$headers = @{ "x-goog-api-key" = $env:GEMINI_API_KEY }
$uri = "https://generativelanguage.googleapis.com/v1beta/models/$($Model):generateContent"

$response = $null
$maxAttempts = 3

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json; charset=utf-8" -Body $bodyBytes -TimeoutSec $TimeoutSeconds
        break
    }
    catch {
        $statusCode = Get-HttpStatusCode -ErrorRecord $_
        $message = $_.Exception.Message
        if ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            $message = $_.ErrorDetails.Message
        }

        $isTransient = Test-TransientGeminiError -ErrorRecord $_ -StatusCode $statusCode
        if ($isTransient -and $attempt -lt $maxAttempts) {
            $delaySeconds = [Math]::Pow(2,($attempt - 1))
            Write-Host ("Gemini transient failure on attempt " + $attempt + "/" + $maxAttempts + ". Retrying in " + $delaySeconds + "s...") -ForegroundColor Yellow
            Start-Sleep -Seconds $delaySeconds
            continue
        }

        throw "Gemini request failed: $message"
    }
}

if ($null -eq $response) {
    throw "Gemini request failed without a response after $maxAttempts attempts."
}

if ($null -eq $response.candidates -or $response.candidates.Count -lt 1) {
    throw "Gemini returned no candidates."
}

$parts = @()
foreach ($part in $response.candidates[0].content.parts) {
    if ($null -ne $part.text) { $parts += [string]$part.text }
}
$content = ($parts -join "").Trim()

try { $null = $content | ConvertFrom-Json }
catch { throw "Gemini returned invalid JSON for the agent result contract." }

[System.IO.File]::WriteAllText($OutputPath,$content,(New-Object System.Text.UTF8Encoding($false)))

[PSCustomObject]@{
    Provider = "Gemini"
    Model = $Model
}
