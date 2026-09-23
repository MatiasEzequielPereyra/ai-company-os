param(
    [string]$ProjectPath = ".",
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path $ProjectPath).Path
$path = Join-Path $root ".codex\runtime\metrics\events.jsonl"

$events = @()
if (Test-Path $path) {
    $lineNumber = 0
    foreach ($line in Get-Content $path -Encoding UTF8) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $events += ($line | ConvertFrom-Json) }
        catch { throw "Invalid metrics JSON at line $lineNumber in $path" }
    }
}

$providerAttempts = @($events | Where-Object { $_.event_type -eq "provider_attempt" })
$providerSuccesses = @($providerAttempts | Where-Object { $_.success -eq $true })
$providerFailures = @($providerAttempts | Where-Object { $_.success -ne $true })
$durations = @($providerAttempts | Where-Object { $null -ne $_.duration_ms } | ForEach-Object { [double]$_.duration_ms })

$avgLatency = 0
if ($durations.Count -gt 0) {
    $avgLatency = [math]::Round((($durations | Measure-Object -Average).Average),2)
}

$failureCategories = @{}
foreach ($event in $providerFailures) {
    $category = [string]$event.error_category
    if ([string]::IsNullOrWhiteSpace($category)) { $category = "unknown" }
    if (-not $failureCategories.ContainsKey($category)) { $failureCategories[$category] = 0 }
    $failureCategories[$category]++
}

$summary = [PSCustomObject]@{
    event_count = $events.Count
    task_transition_count = @($events | Where-Object { $_.event_type -eq "task_transition" }).Count
    provider_attempt_count = $providerAttempts.Count
    provider_success_count = $providerSuccesses.Count
    provider_failure_count = $providerFailures.Count
    average_provider_duration_ms = $avgLatency
    failure_categories = $failureCategories
}

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 10
}
else {
    $summary | Format-List
}
