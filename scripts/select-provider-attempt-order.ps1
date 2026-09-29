param(
    [Parameter(Mandatory = $true)]
    [object]$Config,

    [Parameter(Mandatory = $true)]
    [string[]]$FallbackOrder,

    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [string]$Role = "",

    [string]$Workload = "general"
)

$ErrorActionPreference = "Stop"


function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}


function Convert-ToUtcDate {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        return [DateTime]::Parse(
            [string]$Value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AdjustToUniversal
        ).ToUniversalTime()
    }
    catch {
        return $null
    }
}


function Get-RecentProviderEvents {
    param(
        [string]$Root,
        [int]$LookbackMinutes
    )

    $metricsPath = Join-Path `
        $Root `
        ".codex\runtime\metrics\events.jsonl"

    if (-not (Test-Path $metricsPath -PathType Leaf)) {
        return @()
    }

    $cutoff = (Get-Date).ToUniversalTime().AddMinutes(
        -1 * $LookbackMinutes
    )

    $events = New-Object System.Collections.Generic.List[object]

    foreach ($line in Get-Content $metricsPath -Encoding UTF8) {

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $event = $line | ConvertFrom-Json
        }
        catch {
            # Operational history must never break routing.
            continue
        }

        if ([string]$event.event_type -ne "provider_attempt") {
            continue
        }

        $timestamp = Convert-ToUtcDate -Value $event.timestamp

        if ($null -eq $timestamp) {
            continue
        }

        if ($timestamp -lt $cutoff) {
            continue
        }

        $event |
            Add-Member `
                -NotePropertyName _parsed_timestamp `
                -NotePropertyValue $timestamp `
                -Force

        [void]$events.Add($event)
    }

    return $events.ToArray()
}


function Get-ProviderHealth {
    param(
        [string]$ProviderName,
        [object[]]$Events,
        [object]$HealthConfig
    )

    $result = [ordered]@{
        Attempts = 0
        Failures = 0
        Successes = 0
        FailureRate = 0.0
        Penalty = 0.0
        InCooldown = $false
        CooldownReason = ""
    }

    if ($null -eq $HealthConfig) {
        return [PSCustomObject]$result
    }

    $healthEnabled = [bool](
        Get-PropertyValue `
            -Object $HealthConfig `
            -Name "enabled" `
            -Default $false
    )

    if (-not $healthEnabled) {
        return [PSCustomObject]$result
    }

    $providerEvents = @(
        $Events |
        Where-Object {
            [string]$_.provider -eq $ProviderName
        } |
        Sort-Object _parsed_timestamp
    )

    if ($providerEvents.Count -eq 0) {
        return [PSCustomObject]$result
    }

    $result.Attempts = $providerEvents.Count

    $failures = @(
        $providerEvents |
        Where-Object {
            $_.success -ne $true
        }
    )

    $result.Failures = $failures.Count
    $result.Successes = $result.Attempts - $result.Failures

    if ($result.Attempts -gt 0) {
        $result.FailureRate =
            [double]$result.Failures /
            [double]$result.Attempts
    }

    $failurePenaltyWeight = [double](
        Get-PropertyValue `
            -Object $HealthConfig `
            -Name "failure_penalty_weight" `
            -Default 0.0
    )

    # Effective reliability already incorporates observed failures.
    # This separate short-window penalty is intentionally conservative:
    # it provides faster reaction without letting the same evidence
    # dominate the score twice.
    $result.Penalty =
        $result.FailureRate *
        $failurePenaltyWeight


    $cooldownMinutes = [int](
        Get-PropertyValue `
            -Object $HealthConfig `
            -Name "cooldown_minutes" `
            -Default 0
    )

    if ($cooldownMinutes -le 0) {
        return [PSCustomObject]$result
    }


    $transientCategories = @(
        Get-PropertyValue `
            -Object $HealthConfig `
            -Name "transient_categories" `
            -Default @(
                "rate_limit",
                "timeout",
                "transport"
            )
    )


    # A later successful attempt clears an earlier transient failure.
    $latest = $providerEvents[-1]

    if ($latest.success -eq $true) {
        return [PSCustomObject]$result
    }


    $category = [string]$latest.error_category

    if ($category -notin $transientCategories) {
        return [PSCustomObject]$result
    }


    $cooldownCutoff = (Get-Date).ToUniversalTime().AddMinutes(
        -1 * $cooldownMinutes
    )

    if ($latest._parsed_timestamp -ge $cooldownCutoff) {
        $result.InCooldown = $true
        $result.CooldownReason = $category
    }


    return [PSCustomObject]$result
}


$routing = Get-PropertyValue `
    -Object $Config `
    -Name "auto_routing"

if ($null -eq $routing) {
    return $FallbackOrder
}


$enabled = Get-PropertyValue `
    -Object $routing `
    -Name "enabled" `
    -Default $false

if (-not [bool]$enabled) {
    return $FallbackOrder
}


$providers = Get-PropertyValue `
    -Object $routing `
    -Name "providers"

$workloads = Get-PropertyValue `
    -Object $routing `
    -Name "workloads"

$roles = Get-PropertyValue `
    -Object $routing `
    -Name "roles"

$healthConfig = Get-PropertyValue `
    -Object $routing `
    -Name "health"


# Static provider profile values are routing-policy heuristics,
# not benchmark measurements.
$qualityHeadroomScale = [double](
    Get-PropertyValue `
        -Object $routing `
        -Name "quality_headroom_scale" `
        -Default 0.10
)

$qualityHeadroomScale = [Math]::Max(
    0.0,
    [Math]::Min(
        1.0,
        $qualityHeadroomScale
    )
)


$workloadConfig = $null

if ($null -ne $workloads) {
    $workloadConfig = Get-PropertyValue `
        -Object $workloads `
        -Name $Workload
}


if ($null -eq $workloadConfig) {
    if ($null -ne $workloads) {
        $workloadConfig = Get-PropertyValue `
            -Object $workloads `
            -Name "general"
    }
}


if ($null -eq $workloadConfig) {
    return $FallbackOrder
}


$minimumQuality = [double](
    Get-PropertyValue `
        -Object $workloadConfig `
        -Name "minimum_quality" `
        -Default 0.0
)


if (
    -not [string]::IsNullOrWhiteSpace($Role) -and
    $null -ne $roles
) {

    $roleConfig = Get-PropertyValue `
        -Object $roles `
        -Name $Role

    if ($null -ne $roleConfig) {

        $roleMinimum = [double](
            Get-PropertyValue `
                -Object $roleConfig `
                -Name "minimum_quality" `
                -Default 0.0
        )

        $minimumQuality = [Math]::Max(
            $minimumQuality,
            $roleMinimum
        )
    }
}


$qualityWeight = [double](
    Get-PropertyValue `
        -Object $workloadConfig `
        -Name "quality_weight" `
        -Default 0.35
)

$costWeight = [double](
    Get-PropertyValue `
        -Object $workloadConfig `
        -Name "cost_weight" `
        -Default 0.30
)

$speedWeight = [double](
    Get-PropertyValue `
        -Object $workloadConfig `
        -Name "speed_weight" `
        -Default 0.15
)

$reliabilityWeight = [double](
    Get-PropertyValue `
        -Object $workloadConfig `
        -Name "reliability_weight" `
        -Default 0.20
)


$lookbackMinutes = 60
$reliabilityPriorAttempts = 4

if ($null -ne $healthConfig) {
    $lookbackMinutes = [int](
        Get-PropertyValue `
            -Object $healthConfig `
            -Name "lookback_minutes" `
            -Default 60
    )

    $reliabilityPriorAttempts = [int](
        Get-PropertyValue `
            -Object $healthConfig `
            -Name "reliability_prior_attempts" `
            -Default 4
    )
}

if ($lookbackMinutes -lt 1) {
    $lookbackMinutes = 1
}

if ($reliabilityPriorAttempts -lt 0) {
    $reliabilityPriorAttempts = 0
}


$healthEvents = @(
    Get-RecentProviderEvents `
        -Root $ProjectPath `
        -LookbackMinutes $lookbackMinutes
)


$ranked = New-Object System.Collections.Generic.List[object]


foreach ($providerName in $FallbackOrder) {

    $providerConfig = $null

    if ($null -ne $providers) {
        $providerConfig = Get-PropertyValue `
            -Object $providers `
            -Name ([string]$providerName)
    }

    if ($null -eq $providerConfig) {
        continue
    }


    $quality = [double](
        Get-PropertyValue `
            -Object $providerConfig `
            -Name "quality" `
            -Default 0.0
    )

    $cost = [double](
        Get-PropertyValue `
            -Object $providerConfig `
            -Name "cost" `
            -Default 1.0
    )

    $speed = [double](
        Get-PropertyValue `
            -Object $providerConfig `
            -Name "speed" `
            -Default 0.5
    )

    $reliability = [double](
        Get-PropertyValue `
            -Object $providerConfig `
            -Name "reliability" `
            -Default 0.5
    )


    # Capability is a hard requirement.
    if ($quality -lt $minimumQuality) {
        continue
    }


    # Minimum quality is a hard eligibility threshold.
    # Above that threshold, additional quality receives only a bounded
    # concave bonus so ordinary work does not collapse into
    # "always choose the strongest provider".
    $normalizedQuality = [Math]::Max(
        0.0,
        [Math]::Min(
            1.0,
            $quality
        )
    )

    $normalizedMinimumQuality = [Math]::Max(
        0.0,
        [Math]::Min(
            1.0,
            $minimumQuality
        )
    )

    $qualityHeadroom = 0.0

    if (
        $normalizedQuality -gt $normalizedMinimumQuality -and
        $normalizedMinimumQuality -lt 1.0
    ) {
        $qualityHeadroom =
            (
                $normalizedQuality -
                $normalizedMinimumQuality
            ) /
            (
                1.0 -
                $normalizedMinimumQuality
            )
    }

    $qualityHeadroom = [Math]::Max(
        0.0,
        [Math]::Min(
            1.0,
            $qualityHeadroom
        )
    )

    $qualityFit =
        1.0 -
        $qualityHeadroomScale

    if (
        $qualityHeadroomScale -gt 0.0 -and
        $qualityHeadroom -gt 0.0
    ) {
        $qualityFit +=
            $qualityHeadroomScale *
            [Math]::Sqrt(
                $qualityHeadroom
            )
    }


    $costScore = [Math]::Max(
        0.0,
        (1.0 - $cost)
    )


    $health = Get-ProviderHealth `
        -ProviderName ([string]$providerName) `
        -Events $healthEvents `
        -HealthConfig $healthConfig


    # Configured reliability is a policy prior, not an observed fact.
    # As real attempts accumulate, observed success rate gradually
    # contributes more strongly to effective reliability.
    $effectiveReliability = [Math]::Max(
        0.0,
        [Math]::Min(
            1.0,
            $reliability
        )
    )


    if ([int]$health.Attempts -gt 0) {

        $denominator =
            [double]$reliabilityPriorAttempts +
            [double]$health.Attempts

        if ($denominator -gt 0.0) {

            $effectiveReliability =
                (
                    (
                        $reliability *
                        [double]$reliabilityPriorAttempts
                    ) +
                    [double]$health.Successes
                ) /
                $denominator
        }
    }


    $effectiveReliability = [Math]::Max(
        0.0,
        [Math]::Min(
            1.0,
            $effectiveReliability
        )
    )


    $baseScore =
        ($qualityFit * $qualityWeight) +
        ($costScore * $costWeight) +
        ($speed * $speedWeight) +
        ($effectiveReliability * $reliabilityWeight)


    $score = [Math]::Max(
        0.0,
        ($baseScore - [double]$health.Penalty)
    )


    $fallbackIndex = [Array]::IndexOf(
        $FallbackOrder,
        [string]$providerName
    )


    $ranked.Add(
        [PSCustomObject]@{
            Provider = [string]$providerName
            Score = [double]$score
            BaseScore = [double]$baseScore
            Quality = [double]$quality
            MinimumQuality = [double]$minimumQuality
            ConfiguredReliability = [double]$reliability
            EffectiveReliability = [double]$effectiveReliability
            FailureRate = [double]$health.FailureRate
            InCooldown = [bool]$health.InCooldown
            CooldownReason = [string]$health.CooldownReason
            FallbackIndex = [int]$fallbackIndex
        }
    )
}


if ($ranked.Count -eq 0) {

    throw (
        "No configured Auto provider meets the minimum quality threshold " +
        "for workload '$Workload' and role '$Role'. " +
        "Required quality: $minimumQuality"
    )
}


# Healthy providers always run before providers in transient cooldown.
# Providers in cooldown remain in the list as last-resort fallback.
$ordered = @(
    $ranked |
    Sort-Object `
        @{ Expression = { $_.InCooldown }; Ascending = $true }, `
        @{ Expression = { $_.Score }; Descending = $true }, `
        @{ Expression = { $_.FallbackIndex }; Ascending = $true } |
    ForEach-Object {
        $_.Provider
    }
)


return $ordered