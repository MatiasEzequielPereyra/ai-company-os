param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-provider-contract-" + [Guid]::NewGuid().ToString("N"))
$savedKey = $env:OPENROUTER_API_KEY
$savedGeminiKey = $env:GEMINI_API_KEY

try {
    foreach ($relative in @("scripts","scripts\providers","schemas",".codex",".codex\runtime")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $relative) | Out-Null
    }

    foreach ($name in @("provider-router.ps1","validate-json-contract.ps1","write-operational-event.ps1")) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $tempRoot ("scripts\" + $name)) -Force
    }
    Copy-Item (Join-Path $repoRoot "schemas\agent-result.schema.json") (Join-Path $tempRoot "schemas\agent-result.schema.json") -Force

    $config = @{
        auto_order = @("OpenRouter","Gemini")
        models = @{
            OpenRouter = "openrouter/fake"
            Gemini = "gemini/fake"
        }
    } | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText((Join-Path $tempRoot ".codex\provider-config.json"),$config,(New-Object System.Text.UTF8Encoding($false)))

    $adapterPath = Join-Path $tempRoot "scripts\providers\invoke-openrouter.ps1"
    $invalidAdapter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [int]$TimeoutSeconds
)
$payload = @{
    outcome = "COMPLETED"
    report_markdown = "# Invalid"
    verification = "NONE"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
    completion_check = @{
        substantive_role_deliverable_produced = $true
        missing_required_outputs = @()
        evidence = "Completion self-check is valid so this fixture isolates the intentionally missing summary."
    }
} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutputPath,$payload,(New-Object System.Text.UTF8Encoding($false)))
[PSCustomObject]@{ Provider = "OpenRouter"; Model = $Model }
'@
    [System.IO.File]::WriteAllText($adapterPath,$invalidAdapter,(New-Object System.Text.UTF8Encoding($false)))

    $env:OPENROUTER_API_KEY = "provider-contract-secret"
    $env:GEMINI_API_KEY = "provider-contract-gemini-secret"
    $router = Join-Path $tempRoot "scripts\provider-router.ps1"
    $schema = Join-Path $tempRoot "schemas\agent-result.schema.json"
    $output = Join-Path $tempRoot "result.json"

    $contractRejected = $false
    try {
        & $router -Provider OpenRouter -ProjectPath $tempRoot -Prompt "fixture" -Context "fixture" -SchemaPath $schema -OutputPath $output
    }
    catch {
        if ($_.Exception.Message -match "summary") { $contractRejected = $true } else { throw }
    }
    if (-not $contractRejected) { throw "Provider router accepted syntactically valid JSON that violated the requested schema." }

    $validAdapter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [int]$TimeoutSeconds
)
$payload = @{
    outcome = "COMPLETED"
    summary = "Valid fake provider result"
    report_markdown = "# Valid"
    verification = "Fixture"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
    completion_check = @{
        substantive_role_deliverable_produced = $true
        missing_required_outputs = @()
        evidence = "Valid provider fixture produced the expected substantive role-owned deliverable."
    }
} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutputPath,$payload,(New-Object System.Text.UTF8Encoding($false)))
[PSCustomObject]@{ Provider = "OpenRouter"; Model = $Model }
'@
    [System.IO.File]::WriteAllText($adapterPath,$validAdapter,(New-Object System.Text.UTF8Encoding($false)))

    $result = & $router -Provider OpenRouter -ProjectPath $tempRoot -Prompt "fixture" -Context "fixture" -SchemaPath $schema -OutputPath $output
    if ([string]$result.Provider -ne "OpenRouter") { throw "Valid provider contract did not return successfully." }

    $semanticOpenRouter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [int]$TimeoutSeconds
)
$payload = @{
    outcome = "COMPLETED"
    summary = "SEMANTIC_BAD"
    report_markdown = "# Valid JSON but bad semantics"
    verification = "Fixture"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
    completion_check = @{
        substantive_role_deliverable_produced = $true
        missing_required_outputs = @()
        evidence = "Schema-valid fixture whose semantic contract is intentionally rejected."
    }} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutputPath,$payload,(New-Object System.Text.UTF8Encoding($false)))
[PSCustomObject]@{ Provider = "OpenRouter"; Model = $Model }
'@
    [System.IO.File]::WriteAllText($adapterPath,$semanticOpenRouter,(New-Object System.Text.UTF8Encoding($false)))

    $geminiAdapterPath = Join-Path $tempRoot "scripts\providers\invoke-gemini.ps1"
    $semanticGemini = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [int]$TimeoutSeconds
)
$payload = @{
    outcome = "COMPLETED"
    summary = "SEMANTIC_GOOD"
    report_markdown = "# Valid JSON and valid semantics"
    verification = "Fixture"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
    completion_check = @{
        substantive_role_deliverable_produced = $true
        missing_required_outputs = @()
        evidence = "Schema-valid fixture whose semantic contract is intentionally accepted."
    }} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutputPath,$payload,(New-Object System.Text.UTF8Encoding($false)))
[PSCustomObject]@{ Provider = "Gemini"; Model = $Model }
'@
    [System.IO.File]::WriteAllText($geminiAdapterPath,$semanticGemini,(New-Object System.Text.UTF8Encoding($false)))

    $semanticValidator = Join-Path $tempRoot "scripts\validate-semantic-fixture.ps1"
    [System.IO.File]::WriteAllText(
        $semanticValidator,
        @'
param([Parameter(Mandatory = $true)][string]$JsonPath)
$result = Get-Content $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$result.summary -eq "SEMANTIC_BAD") {
    throw "Semantic contract: fixture rejected provider output."
}
if ([string]$result.summary -ne "SEMANTIC_GOOD") {
    throw "Semantic contract: unexpected fixture output."
}
'@,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $semanticRetryCounter = Join-Path $tempRoot ".codex\runtime\semantic-retry-count.txt"
    $semanticRetryAdapter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [int]$TimeoutSeconds
)
$counterPath = Join-Path (Split-Path -Parent $OutputPath) "semantic-retry-count.txt"
$count = 0
if (Test-Path $counterPath) {
    $count = [int](Get-Content $counterPath -Raw -Encoding UTF8)
}
$count++
[System.IO.File]::WriteAllText($counterPath,[string]$count,(New-Object System.Text.UTF8Encoding($false)))

$summary = if ($count -eq 1) { "SEMANTIC_BAD" } else { "SEMANTIC_GOOD" }
$payload = @{
    outcome = "COMPLETED"
    summary = $summary
    report_markdown = "# Schema-valid semantic retry fixture"
    verification = "Fixture"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
    completion_check = @{
        substantive_role_deliverable_produced = $true
        missing_required_outputs = @()
        evidence = "Schema-valid semantic retry fixture."
    }
} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutputPath,$payload,(New-Object System.Text.UTF8Encoding($false)))
[PSCustomObject]@{ Provider = "OpenRouter"; Model = $Model }
'@
    [System.IO.File]::WriteAllText($adapterPath,$semanticRetryAdapter,(New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path $semanticRetryCounter) { Remove-Item $semanticRetryCounter -Force }

    $semanticRetryResult = & $router -Provider Auto -ProjectPath $tempRoot -Prompt "fixture" -Context "fixture" -SchemaPath $schema -OutputPath $output -SemanticValidatorPath $semanticValidator

    if ([string]$semanticRetryResult.Provider -ne "OpenRouter") {
        throw "Provider router did not keep the same provider after a successful semantic corrective retry."
    }
    if (-not (Test-Path $semanticRetryCounter)) {
        throw "Semantic corrective retry counter was not created."
    }
    if ([int](Get-Content $semanticRetryCounter -Raw -Encoding UTF8) -ne 2) {
        throw "Provider router did not perform exactly one semantic corrective retry."
    }

    [System.IO.File]::WriteAllText($adapterPath,$semanticOpenRouter,(New-Object System.Text.UTF8Encoding($false)))

    $semanticResult = & $router -Provider Auto -ProjectPath $tempRoot -Prompt "fixture" -Context "fixture" -SchemaPath $schema -OutputPath $output -SemanticValidatorPath $semanticValidator

    if ([string]$semanticResult.Provider -ne "Gemini") {
        throw "Provider router did not fall back after semantic validation rejected the first provider."
    }

    $semanticOutput = Get-Content $output -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$semanticOutput.summary -ne "SEMANTIC_GOOD") {
        throw "Semantic fallback did not preserve the accepted provider output."
    }

    $leakyAdapter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [int]$TimeoutSeconds
)
throw ("adapter leaked " + $env:OPENROUTER_API_KEY)
'@
    [System.IO.File]::WriteAllText($adapterPath,$leakyAdapter,(New-Object System.Text.UTF8Encoding($false)))

    $redacted = $false
    try {
        & $router -Provider OpenRouter -ProjectPath $tempRoot -Prompt "fixture" -Context "fixture" -SchemaPath $schema -OutputPath $output
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match "provider-contract-secret") { throw "Provider router leaked a configured secret in an error." }
        if ($message -match "\[REDACTED\]") { $redacted = $true } else { throw }
    }
    if (-not $redacted) { throw "Provider error did not demonstrate secret redaction." }

    $metricsPath = Join-Path $tempRoot ".codex\runtime\metrics\events.jsonl"
    if (-not (Test-Path $metricsPath)) { throw "Provider attempt metrics were not written." }
    $events = @(Get-Content $metricsPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    $providerEvents = @($events | Where-Object { $_.event_type -eq "provider_attempt" })
    if ($providerEvents.Count -lt 5) { throw "Expected provider metrics for schema, valid, semantic fallback, and redaction attempts." }
    if (@($providerEvents | Where-Object { $_.success -eq $true }).Count -lt 2) { throw "Successful provider attempt metrics missing." }
    if (@($providerEvents | Where-Object { $_.success -ne $true }).Count -lt 3) { throw "Failed provider attempt metrics missing." }

    Write-Host "PASS: provider router contract and error-handling test" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedKey
    $env:GEMINI_API_KEY = $savedGeminiKey
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
