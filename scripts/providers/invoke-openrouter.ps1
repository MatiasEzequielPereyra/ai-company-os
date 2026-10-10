param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$Context,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Model = "openrouter/free",
    [switch]$SingleAttempt,
    [object]$SingleAttemptContext,
    [string]$ProviderEndpoint,
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 240
)

$ErrorActionPreference = "Stop"

if ($SingleAttempt) {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'single-attempt-execution.ps1')
    if (-not $PSBoundParameters.ContainsKey('Model') -or [string]::IsNullOrWhiteSpace($Model)) { throw 'SINGLE_ATTEMPT_MODEL_REQUIRED' }
    if ($Model -notmatch '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$') { throw 'SINGLE_ATTEMPT_AMBIGUOUS_MODEL' }
    if ($null -eq $SingleAttemptContext) { throw 'SINGLE_ATTEMPT_CONTEXT_REQUIRED' }
    Assert-SingleAttemptConfiguration -Context $SingleAttemptContext -Provider 'OpenRouter' -Model $Model -ProviderEndpoint $ProviderEndpoint
}
if ($SingleAttempt -and [string]::IsNullOrWhiteSpace($ProviderEndpoint)) { throw 'SINGLE_ATTEMPT_ENDPOINT_REQUIRED' }
if ($SingleAttempt -and $Model -match '(?i)^(openrouter/(free|auto)|.*:nitro|.*:floor)$') { throw 'SINGLE_ATTEMPT_AMBIGUOUS_MODEL' }


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
    if ($message -match 'timed out|timeout|connection.*closed|conexi[o\u00f3]n.*cerrada|forcibly closed|connection reset|underlying connection was closed|se ha terminado la conexi[o\u00f3]n') {
        return $true
    }

    return $false
}

function ConvertTo-StructuredObjectJson {
    param([string]$Content)

    $text = ([string]$Content).Trim()

    try {
        $parsed = $text | ConvertFrom-Json
    }
    catch {
        throw "OpenRouter returned invalid JSON for the structured result contract."
    }

    # Some free models ignore the requested root shape and wrap the object
    # in a JSON string. Unwrap one safe layer when it contains valid JSON.
    if ($parsed -is [string]) {
        $nested = ([string]$parsed).Trim()
        try {
            $parsed = $nested | ConvertFrom-Json
        }
        catch {
            throw "OpenRouter returned a JSON string instead of a structured object."
        }
    }

    # Some models wrap the single requested object in a one-element array.
    if ($parsed -is [System.Array]) {
        if ($parsed.Count -ne 1) {
            throw ("OpenRouter returned a JSON array with " + $parsed.Count + " items; expected one object.")
        }
        $parsed = $parsed[0]
    }

    if ($null -eq $parsed -or ($parsed -isnot [System.Management.Automation.PSCustomObject] -and $parsed -isnot [hashtable])) {
        $rootType = if ($null -eq $parsed) { "null" } else { $parsed.GetType().FullName }
        throw ("OpenRouter structured result root must be an object. Actual root type: " + $rootType)
    }

    return ($parsed | ConvertTo-Json -Depth 100 -Compress)
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

$schema = Get-Content $SchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$fullPrompt = $Prompt + [Environment]::NewLine + [Environment]::NewLine + "# Repository Context Pack" + [Environment]::NewLine + $Context

$maxOutputTokens = 12000

$body = @{
    model = $Model
    messages = @(
        @{
            role = "user"
            content = $fullPrompt
        }
    )
    temperature = 0.1
    max_tokens = $maxOutputTokens
    response_format = @{
        type = "json_schema"
        json_schema = @{
            name = "agent_result"
            strict = $true
            schema = $schema
        }
    }
    provider = $(if ($SingleAttempt) { @{ require_parameters = $true; allow_fallbacks = $false; only = @($ProviderEndpoint) } } else { @{ require_parameters = $true } })
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
$maxAttempts = if ($SingleAttempt) { 1 } else { 3 }

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        if ($SingleAttempt) { Set-SingleAttemptProviderMetadata -Context $SingleAttemptContext -Result ([PSCustomObject]@{ OutputLimit=12000 }) }
        if ($SingleAttempt) { Start-SingleAttemptProviderCall -Context $SingleAttemptContext -Provider 'OpenRouter' -Model $Model }
        $singleTransport = @{}
        if ($SingleAttempt) { $singleTransport.MaximumRedirection = 0; if ($PSVersionTable.PSVersion.Major -ge 7) { $singleTransport.MaximumRetryCount = 0 } }
        $response = Invoke-RestMethod @singleTransport -Method Post -Uri "https://openrouter.ai/api/v1/chat/completions" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $bodyBytes -TimeoutSec $TimeoutSeconds
        break
    }
    catch {
        $statusCode = Get-HttpStatusCode -ErrorRecord $_
        if ($SingleAttempt) {
            if ($_.Exception -is [TimeoutException] -or [string]$_.Exception.Message -match '(?i)timed out|timeout|tiempo.*agotado') { throw 'SINGLE_ATTEMPT_TIMEOUT' }
            throw ('SINGLE_ATTEMPT_TRANSPORT_FAILURE: HTTP ' + $statusCode)
        }
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

if ($SingleAttempt) {
    $actualModel = if ($null -ne $response.model) { [string]$response.model } else { $null }
    $finish = if ($null -ne $response.choices -and $response.choices.Count -gt 0) { [string]$response.choices[0].finish_reason } else { $null }
    $usage = $response.usage
    $reasoning = if ($null -ne $usage.completion_tokens_details) { $usage.completion_tokens_details.reasoning_tokens } else { $null }
    $meta = [PSCustomObject]@{ Model=$actualModel; FinishReason=$finish; OutputLimit=12000; PromptTokens=$usage.prompt_tokens; CompletionTokens=$usage.completion_tokens; TotalTokens=$usage.total_tokens; ReasoningTokens=$reasoning }
    Set-SingleAttemptProviderMetadata -Context $SingleAttemptContext -Result $meta
    if ($null -ne $actualModel -and $actualModel -cne $Model) { throw 'SINGLE_ATTEMPT_MODEL_MISMATCH' }
    if ($finish -eq 'content_filter' -or ($null -ne $response.choices -and $response.choices.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$response.choices[0].message.refusal))) { throw 'SINGLE_ATTEMPT_PROVIDER_REFUSAL' }
    if ($finish -eq 'length') { throw 'SINGLE_ATTEMPT_TRUNCATED_RESPONSE' }
    if ($finish -cne 'stop') { throw 'SINGLE_ATTEMPT_INCOMPLETE_RESPONSE' }
}


if ($null -eq $response) {
    throw "OpenRouter request failed without a response after $maxAttempts attempts."
}

if ($null -eq $response.choices -or $response.choices.Count -lt 1) {
    throw "OpenRouter returned no completion choices."
}

$finishReason = if ($null -ne $response.choices[0].finish_reason) {
    [string]$response.choices[0].finish_reason
}
else {
    "UNKNOWN"
}

$promptTokens = if ($SingleAttempt) { $null } else { 0 }
$completionTokens = if ($SingleAttempt) { $null } else { 0 }
$totalTokens = if ($SingleAttempt) { $null } else { 0 }
$reasoningTokens = if ($SingleAttempt) { $null } else { 0 }

if ($null -ne $response.usage) {
    if ($null -ne $response.usage.prompt_tokens) { $promptTokens = [int]$response.usage.prompt_tokens }
    if ($null -ne $response.usage.completion_tokens) { $completionTokens = [int]$response.usage.completion_tokens }
    if ($null -ne $response.usage.total_tokens) { $totalTokens = [int]$response.usage.total_tokens }

    if (
        $null -ne $response.usage.completion_tokens_details -and
        $null -ne $response.usage.completion_tokens_details.reasoning_tokens
    ) {
        $reasoningTokens = [int]$response.usage.completion_tokens_details.reasoning_tokens
    }
}

Write-Host (
    "OpenRouter response: finish_reason=" + $finishReason +
    ", max_tokens=" + $maxOutputTokens +
    ", prompt_tokens=" + $promptTokens +
    ", completion_tokens=" + $completionTokens +
    ", reasoning_tokens=" + $reasoningTokens +
    ", total_tokens=" + $totalTokens
) -ForegroundColor DarkGray

if ($finishReason -eq "length") {
    $responseModel = if ($null -ne $response.model) { [string]$response.model } else { $Model }
    throw (
        "OpenRouter structured completion was truncated before completion. " +
        "Model: $responseModel; finish_reason: length; " +
        "max_tokens: $maxOutputTokens; prompt_tokens: $promptTokens; " +
        "completion_tokens: $completionTokens; reasoning_tokens: $reasoningTokens; " +
        "total_tokens: $totalTokens. " +
        "The incomplete structured result was rejected and was not persisted."
    )
}

$message = $response.choices[0].message
$content = $message.content
if ($content -isnot [string]) {
    $parts = @()
    foreach ($part in $content) {
        if ($null -ne $part.text) { $parts += [string]$part.text }
    }
    $content = $parts -join ""
}

$content = ([string]$content).Trim()

if ([string]::IsNullOrWhiteSpace($content) -or $content -eq "null") {
    $responseModel = if ($null -ne $response.model) { [string]$response.model } else { $Model }
    $refusal = ""
    if ($null -ne $message.PSObject.Properties["refusal"] -and $null -ne $message.refusal) {
        $refusal = [string]$message.refusal
    }

    $detail = "OpenRouter returned empty/null structured content. Model: $responseModel; finish_reason: $finishReason"
    if (-not [string]::IsNullOrWhiteSpace($refusal)) {
        $detail += "; refusal: $refusal"
    }

    throw $detail
}

$normalizedContent = ConvertTo-StructuredObjectJson -Content $content

[System.IO.File]::WriteAllText($OutputPath,$normalizedContent,(New-Object System.Text.UTF8Encoding($false)))

[PSCustomObject]@{
    Provider = "OpenRouter"
    Model = $(if ($null -ne $response.model) { [string]$response.model } else { $Model })
    FinishReason = $finishReason
    MaxOutputTokens = $maxOutputTokens
    PromptTokens = $promptTokens
    CompletionTokens = $completionTokens
    ReasoningTokens = $reasoningTokens
    TotalTokens = $totalTokens
}
