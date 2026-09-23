param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$Context,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = "openrouter/free"
)

$ErrorActionPreference = "Stop"

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

$headers = @{
    Authorization = "Bearer $($env:OPENROUTER_API_KEY)"
    "X-Title" = "AI Company OS"
}

try {
    $response = Invoke-RestMethod -Method Post -Uri "https://openrouter.ai/api/v1/chat/completions" -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 240
}
catch {
    $message = $_.Exception.Message
    $body = Get-HttpErrorBody -ErrorRecord $_

    if (-not [string]::IsNullOrWhiteSpace($body)) {
        $message = $body
    }
    elseif ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
        $message = $_.ErrorDetails.Message
    }

    throw "OpenRouter request failed: $message"
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
