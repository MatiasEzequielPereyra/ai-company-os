param(
    [Parameter(Mandatory = $true)]
    [string]$JsonPath
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+?)\r?$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Get-SubstantiveReportBody {
    param([string]$Report)

    if ([string]::IsNullOrWhiteSpace($Report)) { return "" }

    $body = $Report
    foreach ($pattern in @(
        '(?m)^# Agent Report[^\r\n]*\r?\n?',
        '(?m)^Generated:\s*[^\r\n]*\r?\n?',
        '(?m)^Owner:\s*[^\r\n]*\r?\n?',
        '(?m)^Provider:\s*[^\r\n]*\r?\n?',
        '(?m)^Model:\s*[^\r\n]*\r?\n?',
        '(?m)^Outcome:\s*[^\r\n]*\r?\n?'
    )) {
        $body = [regex]::Replace($body,$pattern,'')
    }

    $body = [regex]::Replace($body,'(?m)^\s*#{1,6}\s*[^\r\n]*\r?\n?','')
    return $body.Trim()
}

function Test-IsGenericImplementationText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }

    $normalized = (($Value.Trim().ToLowerInvariant()) -replace '\s+',' ').TrimEnd('.')
    return @(
        'produce the role-owned output required by the orchestration plan',
        'complete the scoped implementation work described by this ticket',
        'role-owned deliverable is produced',
        'verify the produced artifact is internally consistent and references authoritative sources',
        'implement the requested changes',
        'complete the requested implementation'
    ) -contains $normalized
}

function Test-IsExplicitImplementationAuthorizationDecision {
    param([object]$Item)

    if ($null -eq $Item -or [string]$Item.kind -ne "DECISION") { return $false }

    $haystack = @(
        [string]$Item.title,
        [string]$Item.objective,
        [string]$Item.context,
        (@($Item.acceptance_criteria) -join " ")
    ) -join " "

    return (
        $haystack -match
        '(?i)(\b(?:authori[sz]e(?:d|s)?|approv(?:e|ed|es|ing))\s+(?:the\s+)?implementation(?:\s+scope)?\b|\bimplementation(?:\s+scope)?\s+(?:is\s+)?(?:explicitly\s+)?(?:authori[sz]ed|approved)\b)'
    )
}

function Test-SourceExplicitlyRequiresNoImplementationAuthorization {
    param([string]$SourceEvidence)

    if ([string]::IsNullOrWhiteSpace($SourceEvidence)) { return $false }

    return (
        $SourceEvidence -match
        '(?i)\b(?:requires? no implementation authorization|no implementation authorization (?:is )?required|implementation authorization (?:is )?not required|does not require implementation authorization)\b'
    )
}

if (-not (Test-Path $JsonPath -PathType Leaf)) {
    throw "Engineering backlog semantic validator input not found: $JsonPath"
}

$resolvedJsonPath = (Resolve-Path $JsonPath).Path
$runtimeDir = Split-Path -Parent $resolvedJsonPath
$codexDir = Split-Path -Parent $runtimeDir
$root = Split-Path -Parent $codexDir

if ((Split-Path $runtimeDir -Leaf) -ne "runtime" -or (Split-Path $codexDir -Leaf) -ne ".codex") {
    throw "Semantic contract: engineering backlog JSON must live under <project>/.codex/runtime."
}

$backlog = Get-Content $resolvedJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceTaskId = [string]$backlog.source_task_id

if ([string]::IsNullOrWhiteSpace($sourceTaskId)) {
    throw "Semantic contract: engineering backlog source_task_id cannot be empty."
}

$taskPath = Join-Path $root ("tasks\" + $sourceTaskId + ".md")
$reportPath = Join-Path $root ("docs\engineering\agent-reports\" + $sourceTaskId + ".md")
$executionPlanPath = Join-Path $root ("docs\engineering\plans\" + $sourceTaskId + "-execution-plan.json")

if (-not (Test-Path $taskPath -PathType Leaf)) {
    throw "Semantic contract: engineering backlog source task not found: $taskPath"
}
if (-not (Test-Path $reportPath -PathType Leaf)) {
    throw "Semantic contract: Engineering Manager report not found: $reportPath"
}

$task = Get-Content $taskPath -Raw -Encoding UTF8
$owner = Read-Field -Content $task -Key "Owner"
$status = Read-Field -Content $task -Key "Status"
$workRequestId = Read-Field -Content $task -Key "Work request"

if ($owner -ne "engineering-manager") {
    throw "Semantic contract: engineering backlog source must be owned by engineering-manager. Current owner: $owner"
}
if ($status -ne "DONE") {
    throw "Semantic contract: engineering backlog source task must be DONE. Current status: $status"
}
if (
    -not [string]::IsNullOrWhiteSpace($workRequestId) -and
    [string]$backlog.work_request_id -ne $workRequestId
) {
    throw "Semantic contract: engineering backlog work_request_id does not match the source task."
}

$report = Get-Content $reportPath -Raw -Encoding UTF8
$executionPlanText = ""
$hasStructuredExecutionWork = $false

if (Test-Path $executionPlanPath -PathType Leaf) {
    $executionPlanText = Get-Content $executionPlanPath -Raw -Encoding UTF8
    try {
        $executionPlan = $executionPlanText | ConvertFrom-Json
        $hasStructuredExecutionWork = (@($executionPlan.executable_work).Count -gt 0)
    }
    catch {
        throw "Semantic contract: canonical Engineering Manager execution plan is invalid JSON."
    }
}

if (-not $hasStructuredExecutionWork) {
    $substantiveReportBody = Get-SubstantiveReportBody -Report $report
    if ($substantiveReportBody.Length -lt 80) {
        throw "Semantic contract: Engineering Manager source evidence is not substantive enough to generate an executable backlog."
    }
}

$items = @($backlog.items)
if ($items.Count -eq 0) {
    throw "Semantic contract: engineering backlog has no items."
}

$keys = @{}
foreach ($item in $items) {
    $key = [string]$item.key
    if ([string]::IsNullOrWhiteSpace($key)) {
        throw "Semantic contract: engineering backlog item key cannot be empty."
    }
    if ($keys.ContainsKey($key)) {
        throw "Semantic contract: duplicate engineering backlog item key: $key"
    }
    $keys[$key] = $true

    if ([string]$item.kind -eq "IMPLEMENTATION") {
        $objective = [string]$item.objective
        if (Test-IsGenericImplementationText -Value $objective) {
            throw "Semantic contract: IMPLEMENTATION backlog item '$key' has a generic/non-executable objective: $objective"
        }

        $criteria = @(
            @($item.acceptance_criteria) |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        $concreteCriteria = @($criteria | Where-Object { -not (Test-IsGenericImplementationText -Value $_) })
        if ($concreteCriteria.Count -lt 1) {
            throw "Semantic contract: IMPLEMENTATION backlog item '$key' has no concrete acceptance criteria."
        }

        $testingRequirements = @(
            @($item.testing_requirements) |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        if ($testingRequirements.Count -lt 1) {
            throw "Semantic contract: IMPLEMENTATION backlog item '$key' has no verification requirement."
        }
    }
}

$sourceEvidence = @($task,$report,$executionPlanText) -join [Environment]::NewLine
$authorizationKey = [string]$backlog.implementation_authorization_key

if ([string]::IsNullOrWhiteSpace($authorizationKey)) {
    throw "Semantic contract: implementation_authorization_key cannot be empty."
}

if ($authorizationKey -eq "NONE") {
    if (-not (Test-SourceExplicitlyRequiresNoImplementationAuthorization -SourceEvidence $sourceEvidence)) {
        throw "Semantic contract: implementation_authorization_key NONE is not supported by approved source evidence."
    }
}
else {
    $exact = @($items | Where-Object { [string]$_.key -eq $authorizationKey })

    if ($exact.Count -eq 1) {
        if (-not (Test-IsExplicitImplementationAuthorizationDecision -Item $exact[0])) {
            throw "Semantic contract: referenced implementation authorization DECISION does not explicitly authorize implementation."
        }
    }
    else {
        $explicitCandidates = @($items | Where-Object { Test-IsExplicitImplementationAuthorizationDecision -Item $_ })
        if ($explicitCandidates.Count -ne 1) {
            throw "Semantic contract: implementation authorization key cannot be resolved to one explicit authorization DECISION."
        }
    }
}

Write-Output "PASS: engineering backlog semantic validation"
