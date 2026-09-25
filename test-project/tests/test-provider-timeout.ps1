param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path $repoRoot ".codex\provider-config.json"
$codexPath = Join-Path $repoRoot "scripts\providers\invoke-codex.ps1"
$routerPath = Join-Path $repoRoot "scripts\provider-router.ps1"

$config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $config.provider_timeout_seconds) {
    throw "Provider config must define provider_timeout_seconds before timeout behavior can be exercised."
}

$codexTimeout = [int]$config.provider_timeout_seconds.Codex
if ($codexTimeout -lt 1 -or $codexTimeout -gt 600) {
    throw "Codex provider timeout must be bounded. Actual: $codexTimeout"
}

$codexSource = Get-Content $codexPath -Raw -Encoding UTF8
if ($codexSource -notmatch 'TimeoutSeconds') {
    throw "Codex adapter must expose a configurable timeout."
}
if ($codexSource -notmatch 'taskkill|Stop-ProcessTree|Kill\(') {
    throw "Codex adapter must terminate its process tree on timeout."
}

$routerSource = Get-Content $routerPath -Raw -Encoding UTF8
foreach ($eventName in @("provider_attempt_started","provider_attempt_finished","provider_timeout")) {
    if ($routerSource -notmatch [regex]::Escape($eventName)) {
        throw "Provider router must emit $eventName operational events."
    }
}
if ($routerSource -notmatch 'TimeoutSeconds') {
    throw "Provider router must pass configured timeout values to provider adapters."
}

$tempRoot = Join-Path $env:TEMP ("aico-provider-timeout-" + [Guid]::NewGuid().ToString("N"))
$savedPath = $env:PATH
$savedOpenRouterKey = $env:OPENROUTER_API_KEY
$savedChildPidFile = $env:AICO_FAKE_CODEX_CHILD_PID_FILE

function Wait-ProcessGone {
    param([int]$ProcessId,[int]$MaxMilliseconds = 5000)

    $deadline = (Get-Date).AddMilliseconds($MaxMilliseconds)
    do {
        if ($null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            return $true
        }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)

    return $false
}

try {
    foreach ($relative in @("bin","scripts","scripts\providers","schemas",".codex",".codex\runtime")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $relative) | Out-Null
    }

    foreach ($name in @("provider-router.ps1","validate-json-contract.ps1","write-operational-event.ps1")) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $tempRoot ("scripts\" + $name)) -Force
    }
    Copy-Item $codexPath (Join-Path $tempRoot "scripts\providers\invoke-codex.ps1") -Force
    Copy-Item (Join-Path $repoRoot "schemas\agent-result.schema.json") (Join-Path $tempRoot "schemas\agent-result.schema.json") -Force

    $fakeCodexPath = Join-Path $tempRoot "bin\codex.ps1"
    $fakeCodex = @'
$outputPath = ""
for ($i = 0; $i -lt ($args.Count - 1); $i++) {
    if ([string]$args[$i] -eq "-o") {
        $outputPath = [string]$args[$i + 1]
        break
    }
}

if (-not [string]::IsNullOrWhiteSpace($outputPath)) {
    [System.IO.File]::WriteAllText(
        $outputPath,
        '{"partial":',
        (New-Object System.Text.UTF8Encoding($false))
    )
}

$child = Start-Process powershell.exe -ArgumentList @(
    "-NoProfile",
    "-Command",
    "Start-Sleep -Seconds 60"
) -PassThru

[System.IO.File]::WriteAllText(
    $env:AICO_FAKE_CODEX_CHILD_PID_FILE,
    [string]$child.Id,
    (New-Object System.Text.UTF8Encoding($false))
)

Start-Sleep -Seconds 60
'@
    [System.IO.File]::WriteAllText($fakeCodexPath,$fakeCodex,(New-Object System.Text.UTF8Encoding($false)))

    $env:PATH = (Join-Path $tempRoot "bin") + [System.IO.Path]::PathSeparator + $savedPath
    $childPidFile = Join-Path $tempRoot "fake-child.pid"
    $env:AICO_FAKE_CODEX_CHILD_PID_FILE = $childPidFile

    $schema = Join-Path $tempRoot "schemas\agent-result.schema.json"
    $directOutput = Join-Path $tempRoot "codex-partial.json"
    $directAdapter = Join-Path $tempRoot "scripts\providers\invoke-codex.ps1"

    $timedOut = $false
    $started = Get-Date
    try {
        & $directAdapter -ProjectPath $tempRoot -Prompt "timeout fixture" -SchemaPath $schema -OutputPath $directOutput -TimeoutSeconds 2
    }
    catch {
        if ($_.Exception.Message -match '(?i)timed out|timeout') {
            $timedOut = $true
        }
        else {
            throw
        }
    }
    $elapsed = ((Get-Date) - $started).TotalSeconds

    if (-not $timedOut) { throw "Fake Codex execution did not time out." }
    if ($elapsed -gt 12) { throw "Codex timeout took too long to abort. Seconds: $elapsed" }
    if (Test-Path $directOutput) { throw "Timed-out Codex execution left partial structured output behind." }
    if (-not (Test-Path $childPidFile)) { throw "Fake Codex child PID evidence was not produced." }

    $childPid = [int](Get-Content $childPidFile -Raw)
    if (-not (Wait-ProcessGone -ProcessId $childPid)) {
        throw "Codex timeout left a child process alive: $childPid"
    }

    $openRouterAdapter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [int]$TimeoutSeconds = 240
)
$payload = @{
    outcome = "COMPLETED"
    summary = "Fallback succeeded after Codex timeout"
    report_markdown = "# Fallback"
    verification = "Fixture"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutputPath,$payload,(New-Object System.Text.UTF8Encoding($false)))
[PSCustomObject]@{ Provider = "OpenRouter"; Model = $Model }
'@
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "scripts\providers\invoke-openrouter.ps1"),
        $openRouterAdapter,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $tempConfig = @{
        auto_order = @("Codex","OpenRouter")
        models = @{
            OpenRouter = "openrouter/fake"
        }
        provider_timeout_seconds = @{
            Codex = 2
            OpenRouter = 10
            Gemini = 10
        }
    } | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot ".codex\provider-config.json"),
        $tempConfig,
        (New-Object System.Text.UTF8Encoding($false))
    )

    Remove-Item $childPidFile -Force -ErrorAction SilentlyContinue
    $env:OPENROUTER_API_KEY = "provider-timeout-test-key"

    $router = Join-Path $tempRoot "scripts\provider-router.ps1"
    $routerOutput = Join-Path $tempRoot "router-result.json"
    $routerStarted = Get-Date
    $result = & $router -Provider Auto -ProjectPath $tempRoot -Prompt "fallback fixture" -Context "fixture" -SchemaPath $schema -OutputPath $routerOutput
    $routerElapsed = ((Get-Date) - $routerStarted).TotalSeconds

    if ([string]$result.Provider -ne "OpenRouter") {
        throw "Provider router did not fall back to OpenRouter after Codex timeout."
    }
    if ($routerElapsed -gt 15) {
        throw "Provider fallback did not recover promptly after Codex timeout. Seconds: $routerElapsed"
    }

    $routerJson = Get-Content $routerOutput -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$routerJson.summary -ne "Fallback succeeded after Codex timeout") {
        throw "Fallback provider output was not persisted correctly."
    }

    if (-not (Test-Path $childPidFile)) { throw "Fallback run did not execute fake Codex first." }
    $fallbackChildPid = [int](Get-Content $childPidFile -Raw)
    if (-not (Wait-ProcessGone -ProcessId $fallbackChildPid)) {
        throw "Provider-router timeout left a Codex child process alive: $fallbackChildPid"
    }

    $metricsPath = Join-Path $tempRoot ".codex\runtime\metrics\events.jsonl"
    if (-not (Test-Path $metricsPath)) { throw "Provider timeout metrics were not written." }

    $events = @(Get-Content $metricsPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })

    $codexStarted = @($events | Where-Object {
        $_.event_type -eq "provider_attempt_started" -and $_.provider -eq "Codex"
    })
    if ($codexStarted.Count -lt 1) { throw "Codex provider_attempt_started event missing." }

    $codexTimeoutEvents = @($events | Where-Object {
        $_.event_type -eq "provider_timeout" -and $_.provider -eq "Codex"
    })
    if ($codexTimeoutEvents.Count -lt 1) { throw "Codex provider_timeout event missing." }

    $codexAttempt = @($events | Where-Object {
        $_.event_type -eq "provider_attempt" -and
        $_.provider -eq "Codex" -and
        $_.success -ne $true -and
        $_.error_category -eq "timeout"
    })
    if ($codexAttempt.Count -lt 1) { throw "Codex timeout was not recorded as a failed timeout provider_attempt." }

    $openRouterSuccess = @($events | Where-Object {
        $_.event_type -eq "provider_attempt_finished" -and
        $_.provider -eq "OpenRouter" -and
        $_.success -eq $true
    })
    if ($openRouterSuccess.Count -lt 1) { throw "OpenRouter successful provider_attempt_finished event missing." }

    Write-Host "PASS: provider timeout, process-tree cleanup, metrics, and fallback regression" -ForegroundColor Green
}
finally {
    $env:PATH = $savedPath
    $env:OPENROUTER_API_KEY = $savedOpenRouterKey
    $env:AICO_FAKE_CODEX_CHILD_PID_FILE = $savedChildPidFile

    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
