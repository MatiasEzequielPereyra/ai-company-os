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

function Get-MojibakeScore {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return 0 }

    $score = 0
    $suspiciousCodePoints = @(
        0x00C3, # LATIN CAPITAL LETTER A WITH TILDE
        0x00C2, # LATIN CAPITAL LETTER A WITH CIRCUMFLEX
        0x00E2, # LATIN SMALL LETTER A WITH CIRCUMFLEX
        0x00F0, # LATIN SMALL LETTER ETH
        0x0192, # LATIN SMALL LETTER F WITH HOOK
        0x20AC, # EURO SIGN
        0x2122, # TRADE MARK SIGN
        0x0153, # LATIN SMALL LIGATURE OE
        0x017E  # LATIN SMALL LETTER Z WITH CARON
    )

    foreach ($codePoint in $suspiciousCodePoints) {
        $pattern = [string][char]$codePoint
        $score += ([regex]::Matches($Value,[regex]::Escape($pattern))).Count
    }

    $replacementCharacter = [string][char]0xFFFD
    $score += 100 * ([regex]::Matches($Value,[regex]::Escape($replacementCharacter))).Count
    return $score
}

function Repair-MojibakeText {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return $Value }

    $current = $Value
    $strict1252 = [System.Text.Encoding]::GetEncoding(
        1252,
        [System.Text.EncoderFallback]::ExceptionFallback,
        [System.Text.DecoderFallback]::ExceptionFallback
    )
    $utf8 = New-Object System.Text.UTF8Encoding($false,$true)

    for ($i = 0; $i -lt 4; $i++) {
        $currentScore = Get-MojibakeScore $current
        if ($currentScore -eq 0) { break }

        try {
            $byteList = New-Object "System.Collections.Generic.List[byte]"

            foreach ($character in $current.ToCharArray()) {
                $codePoint = [int][char]$character

                if ($codePoint -le 255) {
                    $byteList.Add([byte]$codePoint)
                    continue
                }

                $encodedCharacter = $strict1252.GetBytes([string]$character)
                if ($encodedCharacter.Length -ne 1) {
                    throw "Character cannot be represented as a single legacy byte."
                }

                $byteList.Add($encodedCharacter[0])
            }

            $candidate = $utf8.GetString($byteList.ToArray())
        }
        catch {
            break
        }

        $candidateScore = Get-MojibakeScore $candidate
        if ($candidateScore -ge $currentScore) { break }

        $current = $candidate
    }

    return $current
}

function Repair-MojibakeObject {
    param([object]$Value)

    if ($null -eq $Value) { return $null }

    if ($Value -is [string]) {
        return (Repair-MojibakeText -Value ([string]$Value))
    }

    if ($Value -is [System.Array]) {
        $result = @()

        foreach ($entry in $Value) {
            $result += ,(Repair-MojibakeObject -Value $entry)
        }

        # PowerShell normally enumerates arrays returned from functions.
        # -NoEnumerate preserves [] as an actual empty array instead of $null.
        Write-Output -NoEnumerate $result
        return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) {
            $Value[$key] = Repair-MojibakeObject -Value $Value[$key]
        }
        return $Value
    }

    if ($Value -is [pscustomobject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            $property.Value = Repair-MojibakeObject -Value $property.Value
        }
        return $Value
    }

    return $Value
}

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+?)\r?$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
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

function Assert-Acyclic {
    param([object[]]$Items)

    $remaining = @{}
    $dependents = @{}

    foreach ($item in $Items) {
        $key = [string]$item.key
        $remaining[$key] = @($item.dependencies).Count
        if (-not $dependents.ContainsKey($key)) { $dependents[$key] = @() }
    }

    foreach ($item in $Items) {
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
            if ([int]$remaining[$dependent] -eq 0) {
                $queue.Enqueue([string]$dependent)
            }
        }
    }

    if ($visited -ne $Items.Count) {
        throw "Engineering backlog contains a dependency cycle. Reconciliation aborted before writing tasks."
    }
}

function New-TaskContent {
    param(
        [string]$Id,
        [object]$Item,
        [string[]]$DependencyIds,
        [string]$WorkRequestId,
        [string]$SourceTaskId,
        [string]$Created,
        [string]$Updated,
        [string]$TransitionNote
    )

    $requirements = @(
        "Complete the scoped $($Item.kind.ToString().ToLowerInvariant()) work described by this ticket.",
        "Preserve tenant isolation, data integrity and existing product behavior outside this scope.",
        "Record concrete verification evidence before REVIEW."
    )

    if ([string]$Item.kind -eq "DECISION") {
        $requirements = @(
            "Resolve the named decision within the authority of the assigned owner.",
            "Record alternatives considered, selected direction and explicit non-goals.",
            "Do not begin dependent implementation until this decision reaches DONE."
        )
    }

    return @(
        "# $Id - $($Item.title)",
        "",
        "## Metadata",
        "",
        "ID: $Id",
        "",
        "Status: BACKLOG",
        "",
        "Priority: $($Item.priority)",
        "",
        "Owner: $($Item.owner)",
        "",
        "Created: $Created",
        "",
        "Updated: $Updated",
        "",
        "Workflow phase: PLANNING",
        "",
        "Work request: $WorkRequestId",
        "",
        "Source plan: $SourceTaskId",
        "",
        "Backlog key: $($Item.key)",
        "",
        "Work kind: $($Item.kind)",
        "",
        "---",
        "",
        "## Objective",
        "",
        [string]$Item.objective,
        "",
        "---",
        "",
        "## Context",
        "",
        [string]$Item.context,
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
        (Format-Checks -Values @($Item.acceptance_criteria)),
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
        (Format-Bullets -Values $DependencyIds),
        "",
        "---",
        "",
        "## Technical Notes",
        "",
        "- Source backlog key: $($Item.key)",
        "- Source approved plan: docs/engineering/agent-reports/$SourceTaskId.md",
        "",
        "---",
        "",
        "## Affected Areas",
        "",
        (Format-Bullets -Values @($Item.affected_areas)),
        "",
        "---",
        "",
        "## Testing Requirements",
        "",
        (Format-Bullets -Values @($Item.testing_requirements)),
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
        (Format-Bullets -Values @($Item.risks)),
        "",
        "---",
        "",
        "## Handoff",
        "",
        "Next agent: $($Item.owner)",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "- $Updated - SYSTEM - $TransitionNote",
        "",
        "---",
        "",
        "## Notes",
        "",
        "-"
    ) -join [Environment]::NewLine
}

$root = (Resolve-Path $ProjectPath).Path
$tasksPath = Join-Path $root "tasks"
$planPath = Join-Path $root ("docs\engineering\plans\" + $SourceTaskId + "-engineering-backlog.json")
$mappingPath = Join-Path $root ("docs\engineering\plans\" + $SourceTaskId + "-engineering-backlog-tasks.md")

if (-not (Test-Path $planPath)) { throw "Structured backlog not found: $planPath" }
if (-not (Test-Path $tasksPath)) { throw "Tasks directory not found: $tasksPath" }

$backlog = Get-Content $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
$backlog = Repair-MojibakeObject -Value $backlog

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
$itemByKey = @{}
foreach ($item in $items) {
    $key = [string]$item.key
    if ([string]::IsNullOrWhiteSpace($key)) { throw "Backlog item key cannot be empty." }
    if ($keys.ContainsKey($key)) { throw "Duplicate backlog item key: $key" }

    $keys[$key] = $true
    $itemByKey[$key] = $item
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

    $authorizationItem = $itemByKey[$authorizationKey]
    if ([string]$authorizationItem.kind -ne "DECISION") {
        throw "Implementation authorization item '$authorizationKey' must be a DECISION."
    }

    foreach ($item in $items) {
        $key = [string]$item.key
        if ($key -eq $authorizationKey -or [string]$item.kind -eq "DECISION") { continue }

        $visitedKeys = @{}
        if (-not (Test-DependsOnKey -ItemKey $key -TargetKey $authorizationKey -ItemByKey $itemByKey -Visited $visitedKeys)) {
            $item.dependencies = @($item.dependencies) + @($authorizationKey)
        }
    }
}

Assert-Acyclic -Items $items

# Persist the normalized structured backlog so repaired UTF-8 text becomes canonical.
$normalizedPlanJson = $backlog | ConvertTo-Json -Depth 100
Write-Utf8NoBom $planPath $normalizedPlanJson

# Discover existing materialized tasks by stable Backlog key.
$idByKey = @{}
$existingContentByKey = @{}

foreach ($file in @(Get-ChildItem $tasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue)) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $key = Read-Field -Content $content -Key "Backlog key"
    if ([string]::IsNullOrWhiteSpace($key)) { continue }

    if ($idByKey.ContainsKey($key)) {
        throw "Multiple task files claim backlog key '$key'."
    }

    $idByKey[$key] = $file.BaseName
    $existingContentByKey[$key] = $content
}

$nextNumber = Get-NextTaskNumber -ProjectRoot $root
foreach ($item in $items) {
    $key = [string]$item.key
    if ($idByKey.ContainsKey($key)) { continue }

    $id = "AICO-" + $nextNumber.ToString().PadLeft(3,'0')
    $idByKey[$key] = $id
    $nextNumber++
}

# Refuse to rewrite progressed tasks.
foreach ($item in $items) {
    $key = [string]$item.key
    if (-not $existingContentByKey.ContainsKey($key)) { continue }

    $status = Read-Field -Content $existingContentByKey[$key] -Key "Status"
    if ($status -ne "BACKLOG") {
        throw "Cannot reconcile backlog key '$key' because task $($idByKey[$key]) already progressed to $status."
    }
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$createdCount = 0
$updatedCount = 0

foreach ($item in $items) {
    $key = [string]$item.key
    $id = [string]$idByKey[$key]
    $dependencyIds = @($item.dependencies | ForEach-Object { [string]$idByKey[[string]$_] })

    $created = $now
    $transitionNote = "CREATED - Reconciled from approved engineering backlog $SourceTaskId / $key."

    if ($existingContentByKey.ContainsKey($key)) {
        $existing = [string]$existingContentByKey[$key]
        $existingCreated = Read-Field -Content $existing -Key "Created"
        if (-not [string]::IsNullOrWhiteSpace($existingCreated)) { $created = $existingCreated }
        $transitionNote = "RECONCILED - BACKLOG task refreshed from structured engineering backlog $SourceTaskId / $key."
        $updatedCount++
    }
    else {
        $createdCount++
    }

    $content = New-TaskContent -Id $id -Item $item -DependencyIds $dependencyIds -WorkRequestId ([string]$backlog.work_request_id) -SourceTaskId $SourceTaskId -Created $created -Updated $now -TransitionNote $transitionNote
    Write-Utf8NoBom (Join-Path $tasksPath ($id + ".md")) $content
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

foreach ($item in $items) {
    $key = [string]$item.key
    $mapping += "- $key -> $($idByKey[$key]) | $($item.priority) | $($item.kind) | $($item.owner) | $($item.title)"
}

$mapping += ""
$mapping += "## Rules"
$mapping += ""
$mapping += "- Every newly created task starts in BACKLOG."
$mapping += "- Existing tasks are reconciled only while still in BACKLOG."
$mapping += "- Dependencies are translated from logical backlog keys to authoritative AICO task IDs."
$mapping += "- Readiness may advance a task only after all dependencies are DONE."
$mapping += "- DECISION tasks must reach DONE before dependent implementation proceeds."
$mapping += "- This mapping is derived; task files remain authoritative."

Write-Utf8NoBom $mappingPath ($mapping -join [Environment]::NewLine)

Write-Host "Engineering backlog reconciled:" -ForegroundColor Green
Write-Host ("Created tasks: " + $createdCount)
Write-Host ("Updated BACKLOG tasks: " + $updatedCount)
Write-Host ("Total structured items: " + $items.Count)
Write-Host ("Mapping: " + $mappingPath)

if ($orphanDecisionKeys.Count -gt 0) {
    Write-Host ("WARNING orphan decisions: " + ($orphanDecisionKeys -join ", ")) -ForegroundColor Yellow
}
