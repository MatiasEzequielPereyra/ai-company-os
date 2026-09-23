param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [ValidateSet("P0", "P1", "P2", "P3")]
    [string]$Priority,

    [string]$Owner,

    [string]$Note,

    [string]$Evidence,

    [string]$TasksPath = "tasks"
)

$ErrorActionPreference = "Stop"

function Replace-LineValue {
    param(
        [string]$Content,
        [string]$Key,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Content
    }

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

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Content
    }

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

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$content = Get-Content -Path $filePath -Raw -Encoding UTF8


if ($PSBoundParameters.ContainsKey("Priority")) {
    $content = Replace-LineValue -Content $content -Key "Priority" -Value $Priority
}

if ($PSBoundParameters.ContainsKey("Owner")) {
    $content = Replace-LineValue -Content $content -Key "Owner" -Value $Owner
}

$content = Replace-LineValue -Content $content -Key "Updated" -Value $now

if ($PSBoundParameters.ContainsKey("Note")) {
    $content = Append-SectionLine -Content $content -Section "Notes" -Line "$now - $Note"
}

if ($PSBoundParameters.ContainsKey("Evidence")) {
    $content = Append-SectionLine -Content $content -Section "Evidence" -Line "$now - $Evidence"
}

$summaryParts = @()

if ($PSBoundParameters.ContainsKey("Priority")) { $summaryParts += "Priority=$Priority" }
if ($PSBoundParameters.ContainsKey("Owner")) { $summaryParts += "Owner=$Owner" }
if ($PSBoundParameters.ContainsKey("Note")) { $summaryParts += "Note added" }
if ($PSBoundParameters.ContainsKey("Evidence")) { $summaryParts += "Evidence added" }

if ($summaryParts.Count -gt 0) {
    $content = Append-SectionLine -Content $content -Section "Transition Log" -Line "$now - SYSTEM - UPDATED - $($summaryParts -join '; ')."
}

[System.IO.File]::WriteAllText($filePath, $content, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Task updated:" -ForegroundColor Green
Write-Host $filePath
