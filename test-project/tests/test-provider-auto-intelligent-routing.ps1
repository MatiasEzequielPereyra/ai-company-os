param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$tempRoot = Join-Path `
    $env:TEMP `
    ("aico-provider-auto-" + [Guid]::NewGuid().ToString("N"))

$savedOpenRouter = $env:OPENROUTER_API_KEY
$savedGemini = $env:GEMINI_API_KEY
$savedFailProvider = $env:AICO_TEST_FAIL_PROVIDER


function Write-NoBom {
    param(
        [string]$Path,
        [string]$Value
    )

    $parent = Split-Path $Path -Parent

    if (-not (Test-Path $parent)) {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path $parent |
            Out-Null
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $Value,
        (New-Object System.Text.UTF8Encoding($false))
    )
}


function New-FakeAdapter {
    param(
        [string]$Path,
        [string]$ProviderName
    )

    $content = @"
param(
    [string]`$Prompt,
    [string]`$Context,
    [string]`$SchemaPath,
    [string]`$OutputPath,
    [string]`$Model,
    [int]`$NumCtx,
    [int]`$NumPredict
)

if (`$env:AICO_TEST_FAIL_PROVIDER -eq "$ProviderName") {
    throw "fixture forced failure for $ProviderName"
}

`$payload = @{
    outcome = "COMPLETED"
    summary = "Fake $ProviderName result"
    report_markdown = "# $ProviderName deliverable"
    verification = "Fixture"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"

    completion_check = @{
        substantive_role_deliverable_produced = `$true
        missing_required_outputs = @()
        evidence = "$ProviderName produced the deterministic fixture."
    }
} | ConvertTo-Json -Depth 20

[System.IO.File]::WriteAllText(
    `$OutputPath,
    `$payload,
    (New-Object System.Text.UTF8Encoding(`$false))
)

[PSCustomObject]@{
    Provider = "$ProviderName"
    Model = `$Model
}
"@

    Write-NoBom `
        -Path $Path `
        -Value $content
}


try {

    foreach ($relative in @(
        "scripts",
        "scripts\providers",
        "scripts\local-runtime",
        "schemas",
        ".codex",
        ".codex\runtime"
    )) {

        New-Item `
            -ItemType Directory `
            -Force `
            -Path (Join-Path $tempRoot $relative) |
            Out-Null
    }


    foreach ($name in @(
        "provider-router.ps1",
        "select-provider-attempt-order.ps1",
        "validate-json-contract.ps1",
        "write-operational-event.ps1"
    )) {

        Copy-Item `
            (Join-Path $repoRoot ("scripts\" + $name)) `
            (Join-Path $tempRoot ("scripts\" + $name)) `
            -Force
    }


    Copy-Item `
        (Join-Path $repoRoot "schemas\agent-result.schema.json") `
        (Join-Path $tempRoot "schemas\agent-result.schema.json") `
        -Force


    New-FakeAdapter `
        -Path (
            Join-Path `
                $tempRoot `
                "scripts\providers\invoke-ollama.ps1"
        ) `
        -ProviderName "Ollama"


    New-FakeAdapter `
        -Path (
            Join-Path `
                $tempRoot `
                "scripts\providers\invoke-openrouter.ps1"
        ) `
        -ProviderName "OpenRouter"


    New-FakeAdapter `
        -Path (
            Join-Path `
                $tempRoot `
                "scripts\providers\invoke-gemini.ps1"
        ) `
        -ProviderName "Gemini"


    # Build resolver without a nested here-string.
    $resolver = @(
        'param('
        '    [string]$ProjectPath,'
        '    [string]$Role,'
        '    [string]$Workload,'
        '    [string]$ModelOverride'
        ')'
        ''
        '[PSCustomObject]@{'
        '    Available = $true'
        '    Reason = ""'
        '    Profile = "TEST_LOCAL"'
        '    Model = "local-test"'
        '    NumCtx = 8192'
        '    NumPredict = 1024'
        '}'
    ) -join [Environment]::NewLine


    Write-NoBom `
        -Path (
            Join-Path `
                $tempRoot `
                "scripts\local-runtime\resolve-local-runtime.ps1"
        ) `
        -Value $resolver


    Write-NoBom `
        -Path (
            Join-Path `
                $tempRoot `
                ".codex\local-runtime-config.json"
        ) `
        -Value '{}'


    $config = @{
        auto_order = @(
            "Ollama",
            "OpenRouter",
            "Gemini"
        )

        allow_paid_fallback = $false

        models = @{
            Ollama = "local-test"
            OpenRouter = "openrouter-test"
            Gemini = "gemini-test"
        }

        auto_routing = @{
            enabled = $true

            health = @{
                enabled = $true
                lookback_minutes = 60
                cooldown_minutes = 15
                failure_penalty_weight = 0.10
                transient_categories = @(
                    "rate_limit",
                    "timeout",
                    "transport"
                )
            }

            providers = @{
                Ollama = @{
                    quality = 0.55
                    cost = 0.00
                    speed = 0.80
                    reliability = 0.70
                }

                OpenRouter = @{
                    quality = 0.72
                    cost = 0.10
                    speed = 0.70
                    reliability = 0.75
                }

                Gemini = @{
                    quality = 0.90
                    cost = 0.20
                    speed = 0.65
                    reliability = 0.90
                }
            }

            workloads = @{
                general = @{
                    minimum_quality = 0.50
                    quality_weight = 0.30
                    cost_weight = 0.40
                    speed_weight = 0.20
                    reliability_weight = 0.10
                }

                "high-risk" = @{
                    minimum_quality = 0.85
                    quality_weight = 0.65
                    cost_weight = 0.05
                    speed_weight = 0.05
                    reliability_weight = 0.25
                }

                impossible = @{
                    minimum_quality = 0.99
                    quality_weight = 0.65
                    cost_weight = 0.05
                    speed_weight = 0.05
                    reliability_weight = 0.25
                }

                "history-sensitive" = @{
                    minimum_quality = 0.50
                    quality_weight = 0.20
                    cost_weight = 0.20
                    speed_weight = 0.10
                    reliability_weight = 0.50
                }
            }

            roles = @{
                security = @{
                    minimum_quality = 0.85
                }
            }
        }
    } | ConvertTo-Json -Depth 20


    Write-NoBom `
        -Path (
            Join-Path `
                $tempRoot `
                ".codex\provider-config.json"
        ) `
        -Value $config


    $env:OPENROUTER_API_KEY = "fixture-openrouter"
    $env:GEMINI_API_KEY = "fixture-gemini"

    $router = Join-Path `
        $tempRoot `
        "scripts\provider-router.ps1"

    $schema = Join-Path `
        $tempRoot `
        "schemas\agent-result.schema.json"


    Write-Host ""
    Write-Host `
        "CASE 1: general should prefer cheapest sufficient provider"


    $generalOutput = Join-Path `
        $tempRoot `
        "general.json"


    $general = & $router `
        -Provider Auto `
        -ProjectPath $tempRoot `
        -Prompt "General low-risk analysis." `
        -Context "fixture" `
        -SchemaPath $schema `
        -OutputPath $generalOutput `
        -Role "pm" `
        -Workload "general"


    if ([string]$general.Provider -ne "Ollama") {
        throw (
            "General routing expected Ollama, got: " +
            [string]$general.Provider
        )
    }


    Write-Host `
        "PASS: general workload selected Ollama" `
        -ForegroundColor Green


    Write-Host ""
    Write-Host `
        "CASE 2: high-risk must respect minimum quality"


    $securityOutput = Join-Path `
        $tempRoot `
        "security.json"


    $security = & $router `
        -Provider Auto `
        -ProjectPath $tempRoot `
        -Prompt "Perform a security-critical review." `
        -Context "fixture" `
        -SchemaPath $schema `
        -OutputPath $securityOutput `
        -Role "security" `
        -Workload "high-risk"


    if ([string]$security.Provider -ne "Gemini") {
        throw (
            "High-risk routing expected Gemini because lower-quality " +
            "providers do not meet the minimum quality threshold. Got: " +
            [string]$security.Provider
        )
    }


    Write-Host `
        "PASS: high-risk workload selected Gemini" `
        -ForegroundColor Green


    Write-Host ""
    Write-Host "CASE 3: role threshold must raise required quality"


    $roleOutput = Join-Path `
        $tempRoot `
        "role-security.json"


    $roleSecurity = & $router `
        -Provider Auto `
        -ProjectPath $tempRoot `
        -Prompt "General task executed by the security role." `
        -Context "fixture" `
        -SchemaPath $schema `
        -OutputPath $roleOutput `
        -Role "security" `
        -Workload "general"


    if ([string]$roleSecurity.Provider -ne "Gemini") {
        throw (
            "Security role threshold expected Gemini even for general workload. Got: " +
            [string]$roleSecurity.Provider
        )
    }


    Write-Host `
        "PASS: security role raised minimum quality" `
        -ForegroundColor Green


    Write-Host ""
    Write-Host "CASE 4: provider failure must fall back to next eligible provider"


    $env:AICO_TEST_FAIL_PROVIDER = "Ollama"

    try {

        $fallbackOutput = Join-Path `
            $tempRoot `
            "fallback.json"


        $fallback = & $router `
            -Provider Auto `
            -ProjectPath $tempRoot `
            -Prompt "General task with forced Ollama failure." `
            -Context "fixture" `
            -SchemaPath $schema `
            -OutputPath $fallbackOutput `
            -Role "pm" `
            -Workload "general"
    }
    finally {
        $env:AICO_TEST_FAIL_PROVIDER = $savedFailProvider
    }


    if ([string]$fallback.Provider -ne "OpenRouter") {
        throw (
            "Fallback expected OpenRouter after Ollama failure. Got: " +
            [string]$fallback.Provider
        )
    }


    Write-Host `
        "PASS: routing fell back from Ollama to OpenRouter" `
        -ForegroundColor Green


    Write-Host ""
    Write-Host "CASE 5: impossible quality requirement must reject routing"


    $qualityRejected = $false

    try {

        $impossibleOutput = Join-Path `
            $tempRoot `
            "impossible.json"


        & $router `
            -Provider Auto `
            -ProjectPath $tempRoot `
            -Prompt "Impossible quality fixture." `
            -Context "fixture" `
            -SchemaPath $schema `
            -OutputPath $impossibleOutput `
            -Role "pm" `
            -Workload "impossible" |
            Out-Null
    }
    catch {

        if (
            $_.Exception.Message -match
            "No configured Auto provider meets the minimum quality threshold"
        ) {
            $qualityRejected = $true
        }
        else {
            throw
        }
    }


    if (-not $qualityRejected) {
        throw "Auto routing accepted a workload with no sufficiently capable provider."
    }


    Write-Host `
        "PASS: impossible minimum quality was rejected" `
        -ForegroundColor Green


    Write-Host ""
    Write-Host "CASE 6: recent rate limit must cool down preferred provider"


    $metricsDir = Join-Path `
        $tempRoot `
        ".codex\runtime\metrics"


    New-Item `
        -ItemType Directory `
        -Force `
        -Path $metricsDir |
        Out-Null


    $metricsPath = Join-Path `
        $metricsDir `
        "events.jsonl"


    $rateLimitEvent = @{
        schema_version = 1
        timestamp = (
            Get-Date
        ).ToUniversalTime().ToString(
            "yyyy-MM-ddTHH:mm:ss.fffZ"
        )
        event_type = "provider_attempt"
        provider = "Ollama"
        model = "local-test"
        duration_ms = 1200
        success = $false
        error_category = "rate_limit"
    } | ConvertTo-Json -Depth 10 -Compress


    Write-NoBom `
        -Path $metricsPath `
        -Value (
            $rateLimitEvent +
            [Environment]::NewLine
        )


    $healthOutput = Join-Path `
        $tempRoot `
        "health-rate-limit.json"


    $healthResult = & $router `
        -Provider Auto `
        -ProjectPath $tempRoot `
        -Prompt "General task after a recent Ollama rate limit." `
        -Context "fixture" `
        -SchemaPath $schema `
        -OutputPath $healthOutput `
        -Role "pm" `
        -Workload "general"


    if ([string]$healthResult.Provider -ne "OpenRouter") {
        throw (
            "Recent Ollama rate limit should temporarily prefer OpenRouter. Got: " +
            [string]$healthResult.Provider
        )
    }


    Write-Host `
        "PASS: recent rate limit cooled down Ollama" `
        -ForegroundColor Green


    Write-Host ""
    Write-Host "CASE 7: event outside lookback must not affect routing"


    $oldEvent = @{
        schema_version = 1

        timestamp = (
            Get-Date
        ).ToUniversalTime().AddMinutes(
            -120
        ).ToString(
            "yyyy-MM-ddTHH:mm:ss.fffZ"
        )

        event_type = "provider_attempt"
        provider = "Ollama"
        model = "local-test"
        duration_ms = 1000
        success = $false
        error_category = "rate_limit"
    } | ConvertTo-Json -Depth 10 -Compress


    Write-NoBom `
        -Path $metricsPath `
        -Value (
            $oldEvent +
            [Environment]::NewLine
        )


    $oldEventOutput = Join-Path `
        $tempRoot `
        "old-health-event.json"


    $oldEventResult = & $router `
        -Provider Auto `
        -ProjectPath $tempRoot `
        -Prompt "General task after expired health event." `
        -Context "fixture" `
        -SchemaPath $schema `
        -OutputPath $oldEventOutput `
        -Role "pm" `
        -Workload "general"


    if ([string]$oldEventResult.Provider -ne "Ollama") {
        throw (
            "Expired provider event must not affect routing. Expected Ollama, got: " +
            [string]$oldEventResult.Provider
        )
    }


    Write-Host `
        "PASS: expired provider event ignored" `
        -ForegroundColor Green



    Write-Host ""
    Write-Host "CASE 8: later success must clear transient cooldown"


    # Isolate cooldown semantics from historical failure-rate scoring.
    $recoveryConfig = $config |
        ConvertFrom-Json

    $recoveryConfig.auto_routing.health.failure_penalty_weight = 0.0


    Write-NoBom `
        -Path (
            Join-Path `
                $tempRoot `
                ".codex\provider-config.json"
        ) `
        -Value (
            $recoveryConfig |
            ConvertTo-Json -Depth 30
        )


    $failureBeforeSuccess = @{
        schema_version = 1

        timestamp = (
            Get-Date
        ).ToUniversalTime().AddMinutes(
            -2
        ).ToString(
            "yyyy-MM-ddTHH:mm:ss.fffZ"
        )

        event_type = "provider_attempt"
        provider = "Ollama"
        model = "local-test"
        duration_ms = 1500
        success = $false
        error_category = "timeout"
    } | ConvertTo-Json -Depth 10 -Compress


    $successAfterFailure = @{
        schema_version = 1

        timestamp = (
            Get-Date
        ).ToUniversalTime().AddMinutes(
            -1
        ).ToString(
            "yyyy-MM-ddTHH:mm:ss.fffZ"
        )

        event_type = "provider_attempt"
        provider = "Ollama"
        model = "local-test"
        duration_ms = 800
        success = $true
        error_category = ""
    } | ConvertTo-Json -Depth 10 -Compress


    Write-NoBom `
        -Path $metricsPath `
        -Value (
            $failureBeforeSuccess +
            [Environment]::NewLine +
            $successAfterFailure +
            [Environment]::NewLine
        )


    $recoveryOutput = Join-Path `
        $tempRoot `
        "health-recovery.json"


    $recoveryResult = & $router `
        -Provider Auto `
        -ProjectPath $tempRoot `
        -Prompt "General task after provider recovery." `
        -Context "fixture" `
        -SchemaPath $schema `
        -OutputPath $recoveryOutput `
        -Role "pm" `
        -Workload "general"


    if ([string]$recoveryResult.Provider -ne "Ollama") {
        throw (
            "A later successful attempt must clear transient cooldown. Got: " +
            [string]$recoveryResult.Provider
        )
    }


    Write-Host `
        "PASS: later success cleared transient cooldown" `
        -ForegroundColor Green


    # Restore normal health penalty policy for remaining cases.
    Write-NoBom `
        -Path (
            Join-Path `
                $tempRoot `
                ".codex\provider-config.json"
        ) `
        -Value $config



    Write-Host ""
    Write-Host "CASE 9: corrupt metrics JSONL must not break Auto routing"


    Write-NoBom `
        -Path $metricsPath `
        -Value (
            '{"this-is-not-valid-json":' +
            [Environment]::NewLine +
            'totally broken metrics line' +
            [Environment]::NewLine
        )


    $corruptOutput = Join-Path `
        $tempRoot `
        "corrupt-metrics.json"


    $corruptResult = & $router `
        -Provider Auto `
        -ProjectPath $tempRoot `
        -Prompt "General task with corrupt metrics history." `
        -Context "fixture" `
        -SchemaPath $schema `
        -OutputPath $corruptOutput `
        -Role "pm" `
        -Workload "general"


    if ([string]$corruptResult.Provider -ne "Ollama") {
        throw (
            "Corrupt operational history must be ignored safely. Expected Ollama, got: " +
            [string]$corruptResult.Provider
        )
    }


    Write-Host `
        "PASS: corrupt metrics history ignored safely" `
        -ForegroundColor Green



    Write-Host ""
    Write-Host "CASE 10: observed reliability must influence provider ranking"


    $historyConfig = $config |
        ConvertFrom-Json

    # Isolate dynamic reliability from the existing failure penalty.
    $historyConfig.auto_routing.health.failure_penalty_weight = 0.0

    $historyConfig.auto_routing.health |
        Add-Member `
            -NotePropertyName reliability_prior_attempts `
            -NotePropertyValue 4 `
            -Force

    # Fixture calibration:
    # static scoring must prefer Ollama by a small margin.
    # Historical failures should then be able to move OpenRouter ahead.
    $historyConfig.auto_routing.providers.Gemini.reliability = 0.60


    Write-NoBom `
        -Path (
            Join-Path `
                $tempRoot `
                ".codex\provider-config.json"
        ) `
        -Value (
            $historyConfig |
            ConvertTo-Json -Depth 30
        )


    $historyEvents = New-Object System.Collections.Generic.List[string]

    foreach ($minutesAgo in @(5,4,3,2,1)) {

        $event = @{
            schema_version = 1

            timestamp = (
                Get-Date
            ).ToUniversalTime().AddMinutes(
                -1 * $minutesAgo
            ).ToString(
                "yyyy-MM-ddTHH:mm:ss.fffZ"
            )

            event_type = "provider_attempt"
            provider = "Ollama"
            model = "local-test"
            duration_ms = 1000
            success = $false

            # Non-transient on purpose:
            # this must affect reliability without triggering cooldown.
            error_category = "contract"
        } | ConvertTo-Json -Depth 10 -Compress

        [void]$historyEvents.Add($event)
    }


    Write-NoBom `
        -Path $metricsPath `
        -Value (
            ($historyEvents.ToArray() -join [Environment]::NewLine) +
            [Environment]::NewLine
        )


    $historyOutput = Join-Path `
        $tempRoot `
        "historical-reliability.json"


    $historyResult = & $router `
        -Provider Auto `
        -ProjectPath $tempRoot `
        -Prompt "Choose provider using observed reliability." `
        -Context "fixture" `
        -SchemaPath $schema `
        -OutputPath $historyOutput `
        -Role "pm" `
        -Workload "history-sensitive"


    if ([string]$historyResult.Provider -ne "OpenRouter") {

        Write-Host (
            "RED_TARGET_DYNAMIC_RELIABILITY current=" +
            [string]$historyResult.Provider
        ) -ForegroundColor Yellow

        throw (
            "Observed repeated Ollama failures should reduce its effective " +
            "reliability and prefer OpenRouter. Got: " +
            [string]$historyResult.Provider
        )
    }


    Write-Host `
        "PASS: observed reliability changed provider ranking" `
        -ForegroundColor Green


    Write-Host ""
    Write-Host "CASE 11: quality weight must rank higher-quality eligible provider"


    $qualityConfig = $config |
        ConvertFrom-Json


    # Isolate quality from every other scoring dimension.
    $qualityConfig.auto_routing.health.failure_penalty_weight = 0.0


    $qualityWorkload = [PSCustomObject][ordered]@{
        minimum_quality = 0.50
        quality_weight = 1.0
        cost_weight = 0.0
        speed_weight = 0.0
        reliability_weight = 0.0
    }


    $qualityConfig.auto_routing.workloads |
        Add-Member `
            -NotePropertyName "quality-sensitive" `
            -NotePropertyValue $qualityWorkload `
            -Force


    foreach ($providerName in @(
        "Ollama",
        "OpenRouter",
        "Gemini"
    )) {
        $providerProfile =
            $qualityConfig.auto_routing.providers.PSObject.Properties[
                $providerName
            ].Value

        $providerProfile.cost = 0.20
        $providerProfile.speed = 0.70
        $providerProfile.reliability = 0.80
    }


    Write-NoBom `
        -Path (
            Join-Path `
                $tempRoot `
                ".codex\provider-config.json"
        ) `
        -Value (
            $qualityConfig |
            ConvertTo-Json -Depth 30
        )


    # Historical health must not influence this case.
    Write-NoBom `
        -Path $metricsPath `
        -Value ""


    $qualityOutput = Join-Path `
        $tempRoot `
        "quality-ranking.json"


    $qualityResult = & $router `
        -Provider Auto `
        -ProjectPath $tempRoot `
        -Prompt "Choose only by provider quality." `
        -Context "fixture" `
        -SchemaPath $schema `
        -OutputPath $qualityOutput `
        -Workload "quality-sensitive"


    if ([string]$qualityResult.Provider -ne "Gemini") {

        Write-Host (
            "RED_TARGET_QUALITY_WEIGHT current=" +
            [string]$qualityResult.Provider
        ) -ForegroundColor Yellow

        throw (
            "Quality weight must differentiate eligible providers. " +
            "Expected Gemini, got: " +
            [string]$qualityResult.Provider
        )
    }


    Write-Host `
        "PASS: quality weight influences eligible-provider ranking" `
        -ForegroundColor Green


    # Restore fixture config before legacy-compatibility case.
    Write-NoBom `
        -Path (
            Join-Path `
                $tempRoot `
                ".codex\provider-config.json"
        ) `
        -Value $config


    Write-Host ""
    Write-Host "CASE 12: legacy config without auto_routing keeps fixed auto_order"


    $legacyConfig = @{
        auto_order = @(
            "Ollama",
            "OpenRouter",
            "Gemini"
        )

        allow_paid_fallback = $false

        models = @{
            Ollama = "local-test"
            OpenRouter = "openrouter-test"
            Gemini = "gemini-test"
        }
    } | ConvertTo-Json -Depth 20


    Write-NoBom `
        -Path (
            Join-Path `
                $tempRoot `
                ".codex\provider-config.json"
        ) `
        -Value $legacyConfig


    $legacyOutput = Join-Path `
        $tempRoot `
        "legacy.json"


    $legacy = & $router `
        -Provider Auto `
        -ProjectPath $tempRoot `
        -Prompt "Legacy configuration fixture." `
        -Context "fixture" `
        -SchemaPath $schema `
        -OutputPath $legacyOutput `
        -Role "security" `
        -Workload "high-risk"


    if ([string]$legacy.Provider -ne "Ollama") {
        throw (
            "Legacy config must preserve fixed auto_order. Expected Ollama, got: " +
            [string]$legacy.Provider
        )
    }


    Write-Host `
        "PASS: legacy auto_order behavior preserved" `
        -ForegroundColor Green


    Write-Host ""
    Write-Host `
        "PASS: intelligent provider routing baseline" `
        -ForegroundColor Green
}
finally {

    $env:OPENROUTER_API_KEY = $savedOpenRouter
    $env:GEMINI_API_KEY = $savedGemini
    $env:AICO_TEST_FAIL_PROVIDER = $savedFailProvider

    if (Test-Path $tempRoot) {
        Remove-Item `
            $tempRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}