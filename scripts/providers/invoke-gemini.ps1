param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$Context,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = "gemini-3.5-flash-lite"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

$headers = @{
    "x-goog-api-key" = $env:GEMINI_API_KEY
}

$uri = "https://generativelanguage.googleapis.com/v1beta/models/$($Model):generateContent"

try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 240
}
catch {
    $message = $_.Exception.Message
    if ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
        $message = $_.ErrorDetails.Message
    }
    throw "Gemini request failed: $message"
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
