param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$TaskId
)

$ErrorActionPreference = "Stop"
$project = [System.IO.Path]::GetFullPath($ProjectPath)
$taskPath = Join-Path $project ("tasks\" + $TaskId + ".md")
if (-not (Test-Path -LiteralPath $taskPath -PathType Leaf)) { throw "Fixture task does not exist: $TaskId" }

. (Join-Path $project "scripts\writable-authorization-guard.ps1")
$task = Get-Content -LiteralPath $taskPath -Raw -Encoding UTF8
$field = { param($key) [regex]::Matches($task, "(?m)^" + [regex]::Escape($key) + ":\s*(.*?)\s*$") }
$requestMatches = & $field "Work request"
$typeMatches = & $field "Type"
if ($requestMatches.Count -ne 1 -or $typeMatches.Count -ne 1) { throw "Fixture task has ambiguous Work Request or Type: $TaskId" }
$requestId = $requestMatches[0].Groups[1].Value.Trim()
$type = $typeMatches[0].Groups[1].Value.Trim()
if ($requestId -notmatch '^WR-[A-Z0-9-]+$' -or [string]::IsNullOrWhiteSpace($type)) { throw "Fixture task has invalid Work Request identity or Type: $TaskId" }

$objective = [regex]::Match($task, "(?ms)^## Objective\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)")
if (-not $objective.Success) { throw "Fixture task objective is missing: $TaskId" }
$scope = Get-WritableScopeFingerprint -TaskContent $task
$created = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
$expires = [DateTimeOffset]::UtcNow.AddHours(2).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
$receipt = @"
## Authorization Receipt

Requested action: Implement task $TaskId - $($objective.Groups[1].Value.Trim())
Permitted scope: WRITABLE_IMPLEMENTATION
Implementation authorization: AUTHORIZED
Authorized task: $TaskId
Authorized operation: WRITABLE
Authorized execution mode: WRITABLE
Authorized provider invocation: ALLOWED
Authorized write scope: TASK_WORKTREE_ONLY
Authorized scope SHA-256: $scope
Authorization expires (UTC): $expires
Retained restrictions: NONE
"@
$requestPath = Join-Path $project ("docs\engineering\work-requests\" + $requestId + ".md")
$parent = Split-Path -Parent $requestPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$requestContent = ""
if (Test-Path -LiteralPath $requestPath -PathType Leaf) {
    $requestContent = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8
    $existingId = [regex]::Matches($requestContent, '(?m)^ID:\s*(.*?)\s*$')
    $existingType = [regex]::Matches($requestContent, '(?m)^Type:\s*(.*?)\s*$')
    if ($existingId.Count -ne 1 -or $existingId[0].Groups[1].Value.Trim() -cne $requestId -or
        $existingType.Count -ne 1 -or $existingType[0].Groups[1].Value.Trim() -cne $type) {
        throw "Existing fixture Work Request identity or Type does not match task $TaskId."
    }
    $requestContent = [regex]::Replace($requestContent, '(?ms)\r?\n## Authorization Receipt\s*\r?\n.*?(?=\r?\n---\s*\r?\n|\r?\n## |\z)', "")
}
else {
    $requestContent = "# $requestId - Test Fixture Work Request`r`n`r`n## Metadata`r`n`r`nID: $requestId`r`nType: $type`r`nPriority: P1`r`nRequested by: explicit deterministic test fixture`r`nCreated: $created`r`nStatus: PLANNING`r`n`r`n## Objective`r`n`r`n$($objective.Groups[1].Value.Trim())`r`n"
}
$requestContent = $requestContent.TrimEnd() + "`r`n`r`n" + $receipt.Trim() + "`r`n"
[System.IO.File]::WriteAllText($requestPath, $requestContent, (New-Object System.Text.UTF8Encoding($false)))
