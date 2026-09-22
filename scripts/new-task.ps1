param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$Owner = "engineering-manager",

    [ValidateSet("P0", "P1", "P2", "P3")]
    [string]$Priority = "P2",

    [string]$Objective = "",

    [string]$TasksPath = "tasks"
)

$ErrorActionPreference = "Stop"

function Get-NextTaskId {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }

    $existing = Get-ChildItem -Path $Path -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.BaseName -match '^AICO-(\d+)$') {
                [int]$Matches[1]
            }
        }

    $next = 1
    if ($existing) {
        $next = ($existing | Measure-Object -Maximum).Maximum + 1
    }

    return ([string]::Format("AICO-{0:D3}", $next))
}

function ConvertTo-SafeFileText {
    param([string]$Value)
    return ($Value -replace "`r", "" -replace "`n", " ").Trim()
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$id = Get-NextTaskId -Path $TasksPath
$filePath = Join-Path $TasksPath "$id.md"
$safeTitle = ConvertTo-SafeFileText $Title
$safeOwner = ConvertTo-SafeFileText $Owner
$safeObjective = ConvertTo-SafeFileText $Objective

if ([string]::IsNullOrWhiteSpace($safeObjective)) {
    $safeObjective = "Define and complete the work described by this task."
}

$content = @"
# $id — $safeTitle

## Metadata

ID: $id

Status: BACKLOG

Priority: $Priority

Owner: $safeOwner

Created: $now

Updated: $now

Workflow phase: PLANNING

---

## Objective

$safeObjective

---

## Context

-

---

## Requirements

-

---

## Acceptance Criteria

- [ ] Objective is satisfied.
- [ ] Required evidence is recorded.
- [ ] Applicable quality gates are complete or explicitly marked NOT_APPLICABLE.

---

## Non-Goals

-

---

## Dependencies

-

---

## Technical Notes

-

---

## Affected Areas

-

---

## Testing Requirements

-

---

## Evidence

-

---

## Risks

-

---

## Handoff

Next agent: $safeOwner

---

## Transition Log

- $now — SYSTEM — CREATED — Task created in BACKLOG.

---

## Notes

-
"@

Set-Content -Path $filePath -Value $content -Encoding UTF8

Write-Host "Task created:" -ForegroundColor Green
Write-Host $filePath
Write-Host ""
Write-Host "ID: ${id}"
Write-Host "Status: BACKLOG"
Write-Host "Owner: ${safeOwner}"
