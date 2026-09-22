param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [Parameter(Mandatory = $true)]
    [ValidateSet("BACKLOG", "READY", "ACTIVE", "REVIEW", "QA", "SECURITY", "DONE", "BLOCKED")]
    [string]$Status,

    [string]$Actor = "engineering-manager",

    [string]$Reason = "Status transition requested.",

    [string]$Evidence = "",

    [string]$TasksPath = "tasks"
)

$ErrorActionPreference = "Stop"

$validTransitions = @{
    "BACKLOG" = @("READY", "BLOCKED")
    "READY" = @("ACTIVE", "BACKLOG", "BLOCKED")
    "ACTIVE" = @("REVIEW", "BLOCKED")
    "REVIEW" = @("QA", "READY", "BLOCKED")
    "QA" = @("SECURITY", "DONE", "READY", "BLOCKED")
    "SECURITY" = @("DONE", "READY", "BLOCKED")
    "BLOCKED" = @("READY", "BACKLOG")
    "DONE" = @("BACKLOG", "BLOCKED")
}

function Replace-LineValue {
    param(
        [string]$Content,
        [string]$Key,
        [string]$Value
    )

    $escapedKey = [regex]::Escape($Key)
    $line = "$Key`: $Value"

    if ($Content -match "(?m)^$escapedKey`:.*$") {
        return [regex]::Replace($Content, "(?m)^$escapedKey`:.*$", $line)
    }

    return $Content
}

function Append-SectionLine {
    param(
        [string]$Content,
        [string]$Section,
        [string]$Line
    )

    $pattern = "(?ms)(## $([regex]::Escape($Section))\s*\n)(.*?)(\n---|\z)"

    if ($Content -match $pattern) {
        return [regex]::Replace($Content, $pattern, {
            param($match)
            $header = $match.Groups[1].Value
            $body = $match.Groups[2].Value.TrimEnd()
            $tail = $match.Groups[3].Value
            return "$header$body`n- $Line$tail"
        })
    }

    return "$Content`n`n## $Section`n`n- $Line`n"
}

$filePath = Join-Path $TasksPath "$Id.md"

if (-not (Test-Path $filePath)) {
    throw "Task not found: $filePath"
}

$content = Get-Content -Path $filePath -Raw
$currentStatus = if ($content -match '(?m)^Status:\s*(.+)$') { $Matches[1].Trim() } else { "UNKNOWN" }

if (-not $validTransitions.ContainsKey($currentStatus)) {
    throw "Invalid current status '$currentStatus' in $filePath"
}

if ($validTransitions[$currentStatus] -notcontains $Status) {
    throw "Invalid transition: $currentStatus -> $Status. Allowed: $($validTransitions[$currentStatus] -join ', ')"
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$content = Replace-LineValue -Content $content -Key "Status" -Value $Status
$content = Replace-LineValue -Content $content -Key "Updated" -Value $now

if ($Status -eq "ACTIVE") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "IMPLEMENTATION"
}
elseif ($Status -eq "REVIEW") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "CODE_REVIEW"
}
elseif ($Status -eq "QA") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "QA"
}
elseif ($Status -eq "SECURITY") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "SECURITY"
}
elseif ($Status -eq "DONE") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "DONE"
}
elseif ($Status -eq "BLOCKED") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "BLOCKED"
}

$logLine = "$now — $Actor — $currentStatus -> $Status — $Reason"
$content = Append-SectionLine -Content $content -Section "Transition Log" -Line $logLine

if (-not [string]::IsNullOrWhiteSpace($Evidence)) {
    $content = Append-SectionLine -Content $content -Section "Evidence" -Line "$now — $Evidence"
}

Set-Content -Path $filePath -Value $content -Encoding UTF8

Write-Host "Task advanced:" -ForegroundColor Green
Write-Host "$Id: $currentStatus -> $Status"
