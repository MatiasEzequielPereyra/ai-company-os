param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [string]$ProjectPath = ".",

    [ValidateSet("REVIEW_APPROVE","QA_PASS")]
    [string]$Stage = "REVIEW_APPROVE"
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

$root = (Resolve-Path $ProjectPath).Path
$taskPath = Join-Path (Join-Path $root "tasks") ($Id + ".md")
if (-not (Test-Path -LiteralPath $taskPath -PathType Leaf)) {
    throw "Task not found: $taskPath"
}

$task = Get-Content -LiteralPath $taskPath -Raw -Encoding UTF8
$type = (Read-Field -Content $task -Key "Type").Trim().ToUpperInvariant()
$workKind = (Read-Field -Content $task -Key "Work kind").Trim().ToUpperInvariant()

if ($type -ne "BUG" -or $workKind -ne "IMPLEMENTATION") {
    Write-Output "NOT_APPLICABLE: diagnostic evidence guard"
    return
}

$diagnosticPath = Join-Path $root ("docs\engineering\diagnostics\" + $Id + "-diagnostic-v1.json")
if (-not (Test-Path -LiteralPath $diagnosticPath -PathType Leaf)) {
    throw "BUG diagnostic evidence artifact is required before $Stage: $diagnosticPath"
}

$validatorPath = Join-Path $PSScriptRoot "validate-diagnostic-evidence.ps1"
if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
    throw "Diagnostic evidence validator missing: $validatorPath"
}

& $validatorPath -JsonPath $diagnosticPath | Out-Null

$diagnostic = Get-Content -LiteralPath $diagnosticPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$diagnostic.task_id -ne $Id) {
    throw "BUG diagnostic evidence task identity mismatch for $Stage."
}
if ([string]$diagnostic.state -ne "COMPLETE") {
    throw "BUG diagnostic evidence must be COMPLETE before $Stage. Current state: $($diagnostic.state)"
}
if ([string]$diagnostic.post_fix_replay.observation -ne "FIXED_OBSERVED") {
    throw "BUG diagnostic evidence must prove FIXED_OBSERVED before $Stage."
}
if ([string]$diagnostic.reproduction.signal_fingerprint -cne [string]$diagnostic.post_fix_replay.signal_fingerprint) {
    throw "BUG diagnostic evidence signal identity mismatch before $Stage."
}

Write-Output "PASS: BUG diagnostic evidence guard for $Stage"
