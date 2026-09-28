param(
    [Parameter(Mandatory = $true)]
    [string]$JsonPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $JsonPath -PathType Leaf)) {
    throw "Engineering plan result not found: $JsonPath"
}

$result = Get-Content $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($result.executable_work)

if ([string]$result.outcome -eq "BLOCKED") {
    if ($items.Count -ne 0) {
        throw "Semantic contract: BLOCKED Engineering Manager result must not contain executable work."
    }
    return
}

if ([string]$result.outcome -ne "COMPLETED") {
    throw "Semantic contract: unsupported Engineering Manager outcome: $($result.outcome)"
}

if ($items.Count -lt 1) {
    throw "Semantic contract: COMPLETED Engineering Manager result contains no executable_work items."
}

$keys = @{}
$implementationCount = 0

foreach ($item in $items) {
    $key = ([string]$item.key).Trim()
    $kind = ([string]$item.kind).Trim()
    $change = ([string]$item.change).Trim()
    $areas = @($item.areas | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    $dependsOn = @($item.depends_on | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })

    if ([string]::IsNullOrWhiteSpace($key)) {
        throw "Semantic contract: executable_work item key cannot be empty."
    }

    if ($keys.ContainsKey($key)) {
        throw "Semantic contract: duplicate executable_work key: $key"
    }

    $keys[$key] = $true

    if ($kind -eq "IMPLEMENTATION") {
        $implementationCount++

        $semanticText = @(
            $change,
            ($areas -join " ")
        ) -join " "

        if ($semanticText -match '(?i)\b(create|refine|materialize|generate|prepare|update)\b.{0,100}\b(executable tasks?|engineering tasks?|task set|backlog|work requests?|dispatch packets?|lifecycle state|gate evidence)\b') {
            throw "Semantic contract: recursive meta-implementation work: $change"
        }

        foreach ($area in $areas) {
            if ($area -match '(?i)^(tasks?|backlog|planning|lifecycle|docs[\\/]engineering[\\/](dispatch|results|reviews|qa|security|final-approvals))([\\/]|$)') {
                throw "Semantic contract: implementation targets control-plane area: $area"
            }
        }
    }

    if ($dependsOn -contains $key) {
        throw "Semantic contract: work item $key cannot depend on itself."
    }
}

foreach ($item in $items) {
    foreach ($dependency in @($item.depends_on)) {
        $dependencyKey = ([string]$dependency).Trim()

        if ([string]::IsNullOrWhiteSpace($dependencyKey)) {
            continue
        }

        if (-not $keys.ContainsKey($dependencyKey)) {
            throw "Semantic contract: work item $($item.key) references unknown dependency: $dependencyKey"
        }
    }
}

if ($implementationCount -lt 1) {
    throw "Semantic contract: executable plan contains no real IMPLEMENTATION work."
}
