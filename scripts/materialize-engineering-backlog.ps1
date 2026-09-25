param(
    [Parameter(Mandatory = $true)]
    [string]$SourceTaskId,

    [string]$ProjectPath = "."
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

function Get-NextTaskNumber {
    param([string]$ProjectRoot)

    $searchRoots = @(
        (Join-Path $ProjectRoot "tasks"),
        (Join-Path $ProjectRoot "docs\engineering"),
        (Join-Path $ProjectRoot ".codex\runtime")
    )

    $reserved = @()

    foreach ($searchRoot in $searchRoots) {
        if (-not (Test-Path $searchRoot)) { continue }

        $reserved += @(
            Get-ChildItem $searchRoot -File -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $matches = [regex]::Matches(
                        $_.Name,
                        '(?i)AICO-(\d+)'
                    )

                    foreach ($match in $matches) {
                        [int]$match.Groups[1].Value
                    }
                }
        )
    }

    if ($reserved.Count -eq 0) { return 1 }

    return [int](
        ($reserved | Measure-Object -Maximum).Maximum
    ) + 1
}

function Format-Bullets {
    param([object[]]$Values,[string]$Empty = "-")
    $items = @($Values | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) { return $Empty }
    return ($items | ForEach-Object { "- " + $_ }) -join [Environment]::NewLine
}

function Format-Checks {
    param([object[]]$Values)
    $items = @($Values | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) { return "- [ ] Objective is satisfied." }
    return ($items | ForEach-Object { "- [ ] " + $_ }) -join [Environment]::NewLine
}

$root = (Resolve-Path $ProjectPath).Path
$tasksPath = Join-Path $root "tasks"
$planPath = Join-Path $root ("docs\engineering\plans\" + $SourceTaskId + "-engineering-backlog.json")
$mappingPath = Join-Path $root ("docs\engineering\plans\" + $SourceTaskId + "-engineering-backlog-tasks.md")

if (-not (Test-Path $planPath)) { throw "Structured backlog not found: $planPath" }
if (Test-Path $mappingPath) { throw "Backlog already materialized for $SourceTaskId. Mapping exists: $mappingPath" }

$sourceTaskPath = Join-Path $tasksPath ($SourceTaskId + ".md")
if (-not (Test-Path $sourceTaskPath)) { throw "Source task not found: $sourceTaskPath" }

$sourceTask = Get-Content $sourceTaskPath -Raw -Encoding UTF8
if ($sourceTask -notmatch '(?m)^Status:\s*DONE\s*$') {
    throw "Source task $SourceTaskId must be DONE before materialization."
}

$backlog = Get-Content $planPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Canonicalize dependency arrays. Empty/null/whitespace entries mean no dependency.
foreach ($item in @($backlog.items)) {
    $normalizedDependencies = @(
        @($item.dependencies) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    $item.dependencies = @($normalizedDependencies)
}

$items = @($backlog.items)
if ($items.Count -eq 0) { throw "Structured backlog has no items." }

$keys = @{}
foreach ($item in $items) {
    $key = [string]$item.key
    if ([string]::IsNullOrWhiteSpace($key)) { throw "Backlog item key cannot be empty." }
    if ($keys.ContainsKey($key)) { throw "Duplicate backlog item key: $key" }
    $keys[$key] = $true
}

foreach ($item in $items) {
    foreach ($dependency in @($item.dependencies)) {
        $dependencyKey = [string]$dependency
        if (-not $keys.ContainsKey($dependencyKey)) {
            throw "Unknown dependency '$dependencyKey' in item $($item.key)"
        }
        if ($dependencyKey -eq [string]$item.key) {
            throw "Backlog item $($item.key) cannot depend on itself."
        }
    }
}

$authorizationKey = [string]$backlog.implementation_authorization_key
if ([string]::IsNullOrWhiteSpace($authorizationKey)) {
    throw "Backlog implementation_authorization_key cannot be empty."
}

if ($authorizationKey -ne "NONE") {
    if (-not $keys.ContainsKey($authorizationKey)) {
        throw "Implementation authorization key '$authorizationKey' does not reference a backlog item."
    }

    $authorizationItem = @($items | Where-Object { [string]$_.key -eq $authorizationKey })[0]
    if ([string]$authorizationItem.kind -ne "DECISION") {
        throw "Implementation authorization item '$authorizationKey' must be a DECISION."
    }
}

# Detect dependency cycles before creating any task files.
$remaining = @{}
$dependents = @{}
foreach ($item in $items) {
    $key = [string]$item.key
    $remaining[$key] = @($item.dependencies).Count
    if (-not $dependents.ContainsKey($key)) { $dependents[$key] = @() }
}
foreach ($item in $items) {
    $key = [string]$item.key
    foreach ($dependency in @($item.dependencies)) {
        $d = [string]$dependency
        $dependents[$d] = @($dependents[$d]) + @($key)
    }
}
$queue = New-Object System.Collections.Queue
foreach ($key in @($remaining.Keys)) {
    if ([int]$remaining[$key] -eq 0) { $queue.Enqueue($key) }
}
$visited = 0
while ($queue.Count -gt 0) {
    $key = [string]$queue.Dequeue()
    $visited++
    foreach ($dependent in @($dependents[$key])) {
        $remaining[$dependent] = [int]$remaining[$dependent] - 1
        if ([int]$remaining[$dependent] -eq 0) { $queue.Enqueue([string]$dependent) }
    }
}
if ($visited -ne $items.Count) {
    throw "Engineering backlog contains a dependency cycle. No tasks were created."
}

function Test-DependsOnKey {
    param(
        [string]$ItemKey,
        [string]$TargetKey,
        [hashtable]$ItemByKey,
        [hashtable]$Visited
    )

    if ($ItemKey -eq $TargetKey) { return $true }
    if ($Visited.ContainsKey($ItemKey)) { return $false }
    $Visited[$ItemKey] = $true

    $item = $ItemByKey[$ItemKey]
    foreach ($dependency in @($item.dependencies)) {
        $dependencyKey = [string]$dependency
        if ($dependencyKey -eq $TargetKey) { return $true }
        if (Test-DependsOnKey -ItemKey $dependencyKey -TargetKey $TargetKey -ItemByKey $ItemByKey -Visited $Visited) {
            return $true
        }
    }

    return $false
}

$itemByKey = @{}
foreach ($item in $items) { $itemByKey[[string]$item.key] = $item }

if ($authorizationKey -ne "NONE") {
    foreach ($item in $items) {
        $key = [string]$item.key
        if ($key -eq $authorizationKey -or [string]$item.kind -eq "DECISION") { continue }

        $visitedKeys = @{}
        if (-not (Test-DependsOnKey -ItemKey $key -TargetKey $authorizationKey -ItemByKey $itemByKey -Visited $visitedKeys)) {
            $item.dependencies = @($item.dependencies) + @($authorizationKey)
        }
    }
}

# Re-check acyclicity after authorization dependencies are injected.
$remaining = @{}
$dependents = @{}
foreach ($item in $items) {
    $key = [string]$item.key
    $remaining[$key] = @($item.dependencies).Count
    if (-not $dependents.ContainsKey($key)) { $dependents[$key] = @() }
}
foreach ($item in $items) {
    $key = [string]$item.key
    foreach ($dependency in @($item.dependencies)) {
        $d = [string]$dependency
        $dependents[$d] = @($dependents[$d]) + @($key)
    }
}
$queue = New-Object System.Collections.Queue
foreach ($key in @($remaining.Keys)) {
    if ([int]$remaining[$key] -eq 0) { $queue.Enqueue($key) }
}
$visited = 0
while ($queue.Count -gt 0) {
    $key = [string]$queue.Dequeue()
    $visited++
    foreach ($dependent in @($dependents[$key])) {
        $remaining[$dependent] = [int]$remaining[$dependent] - 1
        if ([int]$remaining[$dependent] -eq 0) { $queue.Enqueue([string]$dependent) }
    }
}
if ($visited -ne $items.Count) {
    throw "Engineering backlog contains a dependency cycle after authorization enforcement. No tasks were created."
}

$nextNumber = Get-NextTaskNumber -ProjectRoot $root
$idByKey = @{}

foreach ($item in $items) {
    $id = "AICO-" + $nextNumber.ToString().PadLeft(3,'0')
    $idByKey[[string]$item.key] = $id
    $nextNumber++
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$created = @()

foreach ($item in $items) {
    $key = [string]$item.key
    $id = $idByKey[$key]
    $dependencyIds = @($item.dependencies | ForEach-Object { $idByKey[[string]$_] })

    $dependencyLines = Format-Bullets -Values $dependencyIds
    $requirements = @(
        "Complete the scoped $($item.kind.ToString().ToLowerInvariant()) work described by this ticket.",
        "Preserve tenant isolation, data integrity and existing product behavior outside this scope.",
        "Record concrete verification evidence before REVIEW."
    )

    if ([string]$item.kind -eq "DECISION") {
        $requirements = @(
            "Resolve the named decision within the authority of the assigned owner.",
            "Record alternatives considered, selected direction and explicit non-goals.",
            "Do not begin dependent implementation until this decision reaches DONE."
        )
    }

    $content = @(
        "# $id - $($item.title)",
        "",
        "## Metadata",
        "",
        "ID: $id",
        "",
        "Status: BACKLOG",
        "",
        "Priority: $($item.priority)",
        "",
        "Owner: $($item.owner)",
        "",
        "Created: $now",
        "",
        "Updated: $now",
        "",
        "Workflow phase: PLANNING",
        "",
        "Workflow profile: standard",
        "",
        "Work request: $($backlog.work_request_id)",
        "",
        "Source plan: $SourceTaskId",
        "",
        "Backlog key: $key",
        "",
        "Work kind: $($item.kind)",
        "",
        "---",
        "",
        "## Objective",
        "",
        [string]$item.objective,
        "",
        "---",
        "",
        "## Context",
        "",
        [string]$item.context,
        "",
        "- Generated from approved Engineering Manager plan $SourceTaskId.",
        "",
        "---",
        "",
        "## Requirements",
        "",
        (Format-Bullets -Values $requirements),
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        (Format-Checks -Values @($item.acceptance_criteria)),
        "",
        "---",
        "",
        "## Non-Goals",
        "",
        "- Work outside this ticket's objective is excluded unless a dependency explicitly changes scope.",
        "",
        "---",
        "",
        "## Dependencies",
        "",
        $dependencyLines,
        "",
        "---",
        "",
        "## Technical Notes",
        "",
        "- Source backlog key: $key",
        "- Source approved plan: docs/engineering/agent-reports/$SourceTaskId.md",
        "",
        "---",
        "",
        "## Affected Areas",
        "",
        (Format-Bullets -Values @($item.affected_areas)),
        "",
        "---",
        "",
        "## Testing Requirements",
        "",
        (Format-Bullets -Values @($item.testing_requirements)),
        "",
        "---",
        "",
        "## Evidence",
        "",
        "-",
        "",
        "---",
        "",
        "## Risks",
        "",
        (Format-Bullets -Values @($item.risks)),
        "",
        "---",
        "",
        "## Handoff",
        "",
        "Next agent: $($item.owner)",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "- $now - SYSTEM - CREATED - Materialized from approved engineering backlog $SourceTaskId / $key.",
        "",
        "---",
        "",
        "## Notes",
        "",
        "-"
    ) -join [Environment]::NewLine

    $path = Join-Path $tasksPath ($id + ".md")
    Write-Utf8NoBom $path $content
    $created += [PSCustomObject]@{ Key=$key; ID=$id; Kind=[string]$item.kind; Owner=[string]$item.owner; Priority=[string]$item.priority; Title=[string]$item.title }
}

$kindCounts = @{}
foreach ($kind in @("DECISION","IMPLEMENTATION","VALIDATION","OPERATIONS")) {
    $kindCounts[$kind] = @($items | Where-Object { [string]$_.kind -eq $kind }).Count
}

$referencedDependencies = @{}
foreach ($item in $items) {
    foreach ($dependency in @($item.dependencies)) {
        $referencedDependencies[[string]$dependency] = $true
    }
}
$orphanDecisionKeys = @(
    $items |
        Where-Object {
            [string]$_.kind -eq "DECISION" -and
            [string]$_.key -ne $authorizationKey -and
            -not $referencedDependencies.ContainsKey([string]$_.key)
        } |
        ForEach-Object { [string]$_.key }
)

$mapping = @(
    "# Engineering Backlog Mapping - $SourceTaskId",
    "",
    "Generated: $now",
    "Work request: $($backlog.work_request_id)",
    "Source task: $SourceTaskId",
    "",
    "## Computed Counts",
    "",
    "- Total: $($items.Count)",
    "- DECISION: $($kindCounts["DECISION"])",
    "- IMPLEMENTATION: $($kindCounts["IMPLEMENTATION"])",
    "- VALIDATION: $($kindCounts["VALIDATION"])",
    "- OPERATIONS: $($kindCounts["OPERATIONS"])",
    "",
    "## Summary",
    "",
    [string]$backlog.summary,
    "",
    "## Orphan Decision Warnings",
    "",
    $(if ($orphanDecisionKeys.Count -eq 0) { "- NONE" } else { ($orphanDecisionKeys | ForEach-Object { "- " + $_ }) -join [Environment]::NewLine }),
    "",
    "## Materialized Tasks",
    ""
)

foreach ($entry in $created) {
    $mapping += "- $($entry.Key) -> $($entry.ID) | $($entry.Priority) | $($entry.Kind) | $($entry.Owner) | $($entry.Title)"
}

$mapping += ""
$mapping += "## Rules"
$mapping += ""
$mapping += "- Every task starts in BACKLOG."
$mapping += "- Dependencies are translated from logical backlog keys to authoritative AICO task IDs."
$mapping += "- Readiness may advance a task only after all dependencies are DONE."
$mapping += "- DECISION tasks must reach DONE before dependent implementation proceeds."
$mapping += "- This mapping is derived; task files remain authoritative."

Write-Utf8NoBom $mappingPath ($mapping -join [Environment]::NewLine)

Write-Host "Engineering backlog materialized:" -ForegroundColor Green
$created | Format-Table ID, Priority, Kind, Owner, Key, Title -AutoSize
Write-Host ("Mapping: " + $mappingPath)
