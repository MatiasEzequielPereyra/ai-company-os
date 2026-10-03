param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*$')][string]$Id,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z_-]+$')][string]$Owner
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectPath)
function Assert-SafeEvidencePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Corrective evidence escapes project root.' }
    $item = Get-Item -LiteralPath $full -ErrorAction Stop
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Corrective evidence traverses a link: $Path" }
        if ($item.FullName -eq $root) { break }
        $parentPath = Split-Path -Parent $item.FullName
        if ([string]::IsNullOrWhiteSpace($parentPath)) { throw 'Corrective evidence ancestor outside project.' }
        $item = Get-Item -LiteralPath $parentPath -ErrorAction Stop
    }
}
function Read-Required([string]$Relative) {
    $path = Join-Path $root $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Corrective evidence missing: $Relative" }
    Assert-SafeEvidencePath $path
    $text = [IO.File]::ReadAllText($path)
    if ([string]::IsNullOrWhiteSpace($text)) { throw "Corrective evidence empty: $Relative" }
    return $text
}
function Compact-TicketHistory([string]$Text) {
    # Canonical scope and acceptance sections stay verbatim. Only append-only operational
    # history is bounded; the exact complete source remains identifiable by SHA-256.
    $digest = (Get-FileHash -LiteralPath (Join-Path $root "tasks/$Id.md") -Algorithm SHA256).Hash.ToLowerInvariant()
    $pattern = '(?ms)^## (Evidence|Transition Log|Notes)[ \t]*\r?\n(.*?)(?=^## |\z)'
    $compacted = [regex]::Replace($Text,$pattern,[Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $body = $match.Groups[2].Value
        $lines = @($body -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($lines.Count -le 3) { return $match.Value }
        return '## ' + $match.Groups[1].Value + [Environment]::NewLine +
            "[Operational history compacted: retained last 3 nonempty lines; full source tasks/$Id.md SHA256=$digest]" + [Environment]::NewLine +
            (($lines | Select-Object -Last 3) -join [Environment]::NewLine) + [Environment]::NewLine + [Environment]::NewLine
    })
    return "Canonical task source SHA256: $digest" + [Environment]::NewLine + $compacted
}
function Assert-Field([string]$Text,[string]$Field,[string]$Expected) {
    $match = [regex]::Match($Text,'(?m)^'+[regex]::Escape($Field)+':\s*([^\r\n]+)\r?$')
    if (-not $match.Success -or $match.Groups[1].Value.Trim() -ne $Expected) {
        throw "Corrective evidence identity mismatch: $Field must be $Expected"
    }
}
function Latest-Numbered([string]$Directory,[string]$Kind) {
    $directoryPath = Join-Path $root $Directory
    if (Test-Path -LiteralPath $directoryPath) { Assert-SafeEvidencePath $directoryPath }
    $files = @(Get-ChildItem -LiteralPath (Join-Path $root $Directory) -Filter "$Id-$Kind-*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.BaseName -match ('^'+[regex]::Escape($Id)+'-'+$Kind+'-(\d+)$')) {
            [pscustomobject]@{ Path=$_.FullName; Sequence=[int]$Matches[1] }
        }
    } | Sort-Object Sequence -Descending)
    if ($files.Count) { return $files[0].Path }
    return ''
}
$reviewPath = Latest-Numbered 'docs/engineering/reviews' 'review'
$sources = @()
foreach ($kind in @('Review','QA','Security')) {
    $path = switch ($kind) {
        'Review' { $reviewPath }
        'QA' { Join-Path $root "docs/engineering/qa/$Id-qa.md" }
        'Security' { Join-Path $root "docs/engineering/security/$Id-security.md" }
    }
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    Assert-SafeEvidencePath $path
    $body = [IO.File]::ReadAllText($path)
    if ($kind -eq 'Review') {
        Assert-Field $body 'Task' $Id
        Assert-Field $body 'Task owner' $Owner
        $decision = [regex]::Match($body,'(?m)^Recommendation:[ \t]*(APPROVE|CHANGES_REQUIRED)[ \t]*\r?$')
    } else {
        if ($body -notmatch ('(?m)^# '+$kind+' Gate - '+[regex]::Escape($Id)+'[ \t]*\r?$')) { throw "Corrective $kind gate task identity mismatch." }
        $allowed = if ($kind -eq 'QA') { 'PASS|FAIL' } else { 'PASS|FAIL|NOT_APPLICABLE' }
        $decision = [regex]::Match($body,'(?m)^Outcome:[ \t]*('+$allowed+')[ \t]*\r?$')
    }
    if (-not $decision.Success) { throw "Corrective $kind gate outcome missing or invalid." }
    $recorded = [regex]::Match($body,'(?m)^Recorded:[ \t]*([^\r\n]+)\r?$')
    $time = [datetimeoffset]::MinValue
    if ($recorded.Success -and -not [datetimeoffset]::TryParse($recorded.Groups[1].Value.Trim(),[ref]$time)) { throw "Corrective $kind recorded timestamp invalid." }
    $sources += [pscustomobject]@{Kind=$kind;Path=$path;Body=$body;Decision=$decision.Groups[1].Value;Time=$time}
}
if (-not $sources.Count) { return '' }
$task = Read-Required "tasks/$Id.md"
Assert-Field $task 'ID' $Id
Assert-Field $task 'Owner' $Owner
# Canonical gate transitions are append-only. Their order, unlike second-precision
# timestamps or cross-stage file mtimes, identifies the current retry cycle.
$history = [regex]::Match($task,'(?ms)^## Transition Log[ \t]*\r?\n(.*?)(?=^## |\z)')
$currentKind = ''
$currentFailed = $false
if ($history.Success) {
    foreach ($line in ($history.Groups[1].Value -split '\r?\n')) {
        if ($line -notmatch '^(?:- )?\d{4}-\d{2}-\d{2}T[^ ]+ - .+? - [A-Z]+ -> [A-Z]+ - (.+)$') { continue }
        $reason = $Matches[1]
        if ($reason -match '^(Review requested changes\.|Independent review approved\.)') { $currentKind='Review'; $currentFailed=$reason.StartsWith('Review requested changes.') }
        elseif ($reason -match '^QA gate (failed|passed)\.') { $currentKind='QA'; $currentFailed=$reason.StartsWith('QA gate failed.') }
        elseif ($reason -match '^Security gate failed\.') { $currentKind='Security'; $currentFailed=$true }
    }
}
if ($currentKind) {
    $pending = @($sources | Where-Object { $_.Kind -eq $currentKind })
    if (-not $pending.Count) { throw "Current corrective gate evidence missing: $currentKind" }
    $pending = $pending[0]
    if (-not $currentFailed -and $pending.Decision -in @('CHANGES_REQUIRED','FAIL')) { throw 'Current corrective gate outcome contradicts successful canonical transition.' }
} else {
    # Legacy/synthetic records without transition provenance retain compatibility.
    $orderedSources = @($sources | Sort-Object Time -Descending)
    if ($orderedSources.Count -gt 1 -and $orderedSources[0].Time -eq $orderedSources[1].Time) { throw 'Ambiguous current corrective gate: equal or absent timestamps without canonical lifecycle provenance.' }
    $pending = $orderedSources[0]
}
if ($pending.Decision -notin @('CHANGES_REQUIRED','FAIL')) { return '' }
$role = Read-Required ".codex/agents/$Owner.md"
$dispatch = Read-Required "docs/engineering/dispatch/$Id.md"
Assert-Field $dispatch 'Task' $Id
Assert-Field $dispatch 'Owner' $Owner
$resultPath = Latest-Numbered 'docs/engineering/results' 'result'
if (-not $resultPath) { throw 'Corrective latest task result missing.' }
Assert-SafeEvidencePath $resultPath
$result = [IO.File]::ReadAllText($resultPath)
Assert-Field $result 'Task' $Id
Assert-Field $result 'Owner' $Owner
$report = Read-Required "docs/engineering/agent-reports/$Id.md"
if ($report -notmatch ('(?m)^# Agent Report - '+[regex]::Escape($Id)+'\s*\r?$')) { throw 'Corrective primary report task identity mismatch.' }
Assert-Field $report 'Owner' $Owner
$findings = [regex]::Match($pending.Body,'(?ms)^## Findings\s*\r?\n(.*?)(?=^## |\z)')
if (-not $findings.Success -or [string]::IsNullOrWhiteSpace($findings.Groups[1].Value)) { throw "Corrective $($pending.Kind) findings missing." }
$sections = [ordered]@{
    'CANONICAL TASK'=(Compact-TicketHistory $task)
    'ORIGINAL OWNER ROLE CONTRACT'=$role
    'DISPATCH PACKET'=$dispatch
    'PRIMARY AGENT REPORT'=$report
    'LATEST TASK RESULT'=$result
}
if ($pending.Kind -eq 'Review') { $sections['LATEST INDEPENDENT REVIEW']=$pending.Body }
if ($pending.Kind -ne 'Review') { $sections['LATEST '+$pending.Kind.ToUpperInvariant()+' GATE']=$pending.Body }
$sections['CORRECTIVE FINDINGS']=$findings.Groups[1].Value.Trim()
# Resolve concrete changed-artifact paths, without following links outside this fixture.
$changed = [regex]::Match($result,'(?ms)^## Changed Artifacts\s*\r?\n(.*?)(?=^## |\z)')
if ($changed.Success) {
    foreach ($line in ($changed.Groups[1].Value -split '[;\r\n]+')) {
        $relative = $line.Trim().TrimStart('-',' ').Trim('`')
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        if ($relative -match '(?i)(^|[/\\])(?:\.env(?:\..*)?|provider-config\.json|[^/\\]*(?:secret|credential|api[-_]?key)[^/\\]*)(?:$|[/\\])' -or $relative -match '^\.codex[/\\]') { throw "Unsafe corrective changed artifact reference: $relative" }
        if ($relative -notmatch '^(docs|tasks)/[^\r\n]+\.(md|json)$') { continue }
        if ($relative -eq "docs/engineering/agent-reports/$Id.md") { continue } # Already included in full above.
        $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
        if (-not $path.StartsWith($root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Corrective artifact escapes project root.' }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Corrective changed artifact missing: $relative" }
        Assert-SafeEvidencePath $path
        $sections["CHANGED ARTIFACT: $relative"] = [IO.File]::ReadAllText($path)
    }
}
$parts = @('===== BEGIN CORRECTIVE ANALYSIS EVIDENCE =====',"Task: $Id; Owner: $Owner; Corrective source: $($pending.Kind) $($pending.Decision); Artifact: $($pending.Path); Result source: $resultPath",'Correct the current gate findings within the assigned role. Missing role-owned outputs are corrective work, not an external execution dependency.')
foreach ($entry in $sections.GetEnumerator()) { $parts += "===== $($entry.Key) ====="; $parts += $entry.Value }
$parts += '===== END CORRECTIVE ANALYSIS EVIDENCE ====='
return ($parts -join [Environment]::NewLine)
