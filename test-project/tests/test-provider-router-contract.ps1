param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-provider-contract-" + [Guid]::NewGuid().ToString("N"))
$savedKey = $env:OPENROUTER_API_KEY

try {
    foreach ($relative in @("scripts","scripts\providers","schemas",".codex",".codex\runtime")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $relative) | Out-Null
    }

    foreach ($name in @("provider-router.ps1","validate-json-contract.ps1","write-operational-event.ps1")) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $tempRoot ("scripts\" + $name)) -Force
    }
    Copy-Item (Join-Path $repoRoot "schemas\agent-result.schema.json") (Join-Path $tempRoot "schemas\agent-result.schema.json") -Force

    $config = @{
        auto_order = @("OpenRouter")
        models = @{ OpenRouter = "openrouter/fake" }
    } | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText((Join-Path $tempRoot ".codex\provider-config.json"),$config,(New-Object System.Text.UTF8Encoding($false)))

    $adapterPath = Join-Path $tempRoot "scripts\providers\invoke-openrouter.ps1"
    $invalidAdapter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model
)
$payload = @{
    outcome = "COMPLETED"
    report_markdown = "# Invalid"
    verification = "NONE"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutputPath,$payload,(New-Object System.Text.UTF8Encoding($false)))
[PSCustomObject]@{ Provider = "OpenRouter"; Model = $Model }
'@
    [System.IO.File]::WriteAllText($adapterPath,$invalidAdapter,(New-Object System.Text.UTF8Encoding($false)))

    $env:OPENROUTER_API_KEY = "provider-contract-secret"
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
    [string]$Model
)
$payload = @{
    outcome = "COMPLETED"
    summary = "Valid fake provider result"
    report_markdown = "# Valid"
    verification = "Fixture"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutputPath,$payload,(New-Object System.Text.UTF8Encoding($false)))
[PSCustomObject]@{ Provider = "OpenRouter"; Model = $Model }
'@
    [System.IO.File]::WriteAllText($adapterPath,$validAdapter,(New-Object System.Text.UTF8Encoding($false)))

    $result = & $router -Provider OpenRouter -ProjectPath $tempRoot -Prompt "fixture" -Context "fixture" -SchemaPath $schema -OutputPath $output
    if ([string]$result.Provider -ne "OpenRouter") { throw "Valid provider contract did not return successfully." }

    $leakyAdapter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model
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
    if ($providerEvents.Count -lt 3) { throw "Expected provider metrics for invalid, valid, and redaction attempts." }
    if (@($providerEvents | Where-Object { $_.success -eq $true }).Count -lt 1) { throw "Successful provider attempt metric missing." }
    if (@($providerEvents | Where-Object { $_.success -ne $true }).Count -lt 2) { throw "Failed provider attempt metrics missing." }

    Write-Host "PASS: provider router contract and error-handling test" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedKey
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
