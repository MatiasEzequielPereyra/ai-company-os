param(
    [Parameter(Mandatory = $true)]
    [string]$Objective,
    [ValidateSet("FEATURE","BUG","REFACTOR","INFRASTRUCTURE","AUDIT","RELEASE","RESEARCH","DOCUMENTATION")]
    [string]$Type = "FEATURE",
    [ValidateSet("P0","P1","P2","P3")]
    [string]$Priority = "P1",
    [string]$RequestedBy = "user",
    [string]$ProjectPath = "."
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param([string]$Path, [string]$Value)
    [System.IO.File]::WriteAllText($Path, $Value, (New-Object System.Text.UTF8Encoding($false)))
}

function Safe-OneLine {
    param([string]$Value)
    if ($null -eq $Value) { return "" }
    return ($Value -replace "\r", "" -replace "\n", " ").Trim()
}

$root = (Resolve-Path $ProjectPath).Path
$stateDir = Join-Path $root ".codex\state"
$requestDir = Join-Path $root "docs\engineering\work-requests"
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null }
if (-not (Test-Path $requestDir)) { New-Item -ItemType Directory -Force -Path $requestDir | Out-Null }

$existing = @(Get-ChildItem $requestDir -Filter "WR-*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.BaseName -match '^WR-(\d+)$') { [int]$Matches[1] }
})
$next = 1
if ($existing.Count -gt 0) { $next = [int](($existing | Measure-Object -Maximum).Maximum) + 1 }
$id = "WR-" + $next.ToString().PadLeft(3, '0')
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$safeObjective = Safe-OneLine $Objective
$safeRequestedBy = Safe-OneLine $RequestedBy

$requestPath = Join-Path $requestDir ($id + ".md")
$lines = @(
    "# $id - Work Request",
    "",
    "## Metadata",
    "",
    "ID: $id",
    "Type: $Type",
    "Priority: $Priority",
    "Requested by: $safeRequestedBy",
    "Created: $now",
    "Status: PLANNING",
    "",
    "## Objective",
    "",
    $safeObjective,
    "",
    "## Authorization Receipt",
    "",
    "Requested action: $safeObjective",
    "Permitted scope: planning and task preparation for this objective.",
    "Implementation authorization: NOT_INFERRED",
    "",
    "## Constraints",
    "",
    "- Preserve existing user restrictions and project conventions.",
    "- Do not invent product requirements.",
    "- Do not treat planning as implementation authorization.",
    "",
    "## Next Action",
    "",
    "Generate and review an orchestration plan."
)
Write-Utf8NoBom $requestPath ($lines -join [Environment]::NewLine)

$currentPath = Join-Path $stateDir "current-objective.md"
$current = @(
    "# Current Objective",
    "",
    "Work request: docs/engineering/work-requests/$id.md",
    "Objective: $safeObjective",
    "Type: $Type",
    "Priority: $Priority",
    "Updated: $now"
)
Write-Utf8NoBom $currentPath ($current -join [Environment]::NewLine)

Write-Host "Work request created:" -ForegroundColor Green
Write-Host $requestPath
Write-Host "ID: $id"
Write-Host "Type: $Type"
Write-Host "Priority: $Priority"
