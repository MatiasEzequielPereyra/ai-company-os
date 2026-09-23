param(
    [Parameter(Mandatory = $true)]
    [string]$SourceTaskId,

    [string]$ProjectPath = ".",

    [ValidateSet("Auto","Codex","OpenRouter","Gemini")]
    [string]$Provider = "Auto",

    [string]$Model = "",

    [switch]$ReuseExistingOutput
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

function Get-MojibakeScore {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return 0 }

    $score = 0
    foreach ($pattern in @("Ã","Â","â","ð","ƒ","€","™","œ","ž")) {
        $score += ([regex]::Matches($Value,[regex]::Escape($pattern))).Count
    }

    $score += 100 * ([regex]::Matches($Value,[regex]::Escape([char]0xFFFD))).Count
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
            $bytes = $strict1252.GetBytes($current)
            $candidate = $utf8.GetString($bytes)
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
        return $result
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

function Resolve-ImplementationAuthorizationKey {
    param([object]$Backlog)

    $requested = [string]$Backlog.implementation_authorization_key
    if ([string]::IsNullOrWhiteSpace($requested)) {
        throw "Backlog implementation_authorization_key cannot be empty."
    }

    if ($requested -eq "NONE") {
        return "NONE"
    }

    $items = @($Backlog.items)
    $exact = @($items | Where-Object { [string]$_.key -eq $requested })
    if ($exact.Count -eq 1) {
        if ([string]$exact[0].kind -ne "DECISION") {
            throw "Implementation authorization item '$requested' must be a DECISION."
        }
        return [string]$exact[0].key
    }

    # First repair by key identity. Models may return a shortened alias such as
    # "impl-auth" while the actual item key is "AICO-006-IMPL-AUTH".
    $normalizeKey = {
        param([string]$Value)
        return (($Value.ToUpperInvariant()) -replace '[^A-Z0-9]','')
    }

    $requestedNormalized = & $normalizeKey $requested
    $identityCandidates = @(
        $items | Where-Object {
            if ([string]$_.kind -ne "DECISION") { return $false }

            $candidateKey = [string]$_.key
            $candidateNormalized = & $normalizeKey $candidateKey

            return (
                $candidateNormalized -eq $requestedNormalized -or
                $candidateNormalized.EndsWith($requestedNormalized) -or
                $requestedNormalized.EndsWith($candidateNormalized)
            )
        }
    )

    if ($identityCandidates.Count -eq 1) {
        $resolved = [string]$identityCandidates[0].key
        Write-Host ("Repaired implementation authorization key by identity: '" + $requested + "' -> '" + $resolved + "'") -ForegroundColor Yellow
        return $resolved
    }

    if ($identityCandidates.Count -gt 1) {
        $candidateKeys = ($identityCandidates | ForEach-Object { [string]$_.key }) -join ", "
        throw "Implementation authorization key '$requested' is ambiguous by key identity: $candidateKeys"
    }

    # Fall back only to a single, semantically clear authorization decision.
    $candidates = @(
        $items | Where-Object {
            if ([string]$_.kind -ne "DECISION") { return $false }

            $haystack = @(
                [string]$_.key,
                [string]$_.title,
                [string]$_.objective,
                [string]$_.context
            ) -join " "

            return ($haystack -match '(?i)implement.*authori[sz]|authori[sz].*implement|approve.*implement|implementation scope|implementation approval')
        }
    )

    if ($candidates.Count -eq 1) {
        $resolved = [string]$candidates[0].key
        Write-Host ("Repaired implementation authorization key by semantics: '" + $requested + "' -> '" + $resolved + "'") -ForegroundColor Yellow
        return $resolved
    }

    if ($candidates.Count -eq 0) {
        throw "Implementation authorization key '$requested' does not reference a backlog item, and no unambiguous authorization DECISION item was found."
    }

    $candidateKeys = ($candidates | ForEach-Object { [string]$_.key }) -join ", "
    throw "Implementation authorization key '$requested' is invalid and multiple authorization DECISION candidates exist: $candidateKeys"
}


$root = (Resolve-Path $ProjectPath).Path
$taskPath = Join-Path $root ("tasks\" + $SourceTaskId + ".md")
$reportPath = Join-Path $root ("docs\engineering\agent-reports\" + $SourceTaskId + ".md")
$schemaPath = Join-Path $root "schemas\engineering-backlog.schema.json"
$routerPath = Join-Path $PSScriptRoot "provider-router.ps1"

foreach ($path in @($taskPath,$reportPath,$schemaPath,$routerPath)) {
    if (-not (Test-Path $path)) { throw "Required backlog-generation input not found: $path" }
}

$task = Get-Content $taskPath -Raw -Encoding UTF8
$status = Read-Field $task "Status"
$workRequestId = Read-Field $task "Work request"

if ($status -ne "DONE") {
    throw "Source planning task $SourceTaskId must be DONE before executable backlog generation. Current status: $status"
}

$report = Get-Content $reportPath -Raw -Encoding UTF8

$latestResult = Get-ChildItem (Join-Path $root "docs\engineering\results") -Filter ($SourceTaskId + "-result-*.md") -File -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

$resultText = ""
if ($null -ne $latestResult) {
    $resultText = Get-Content $latestResult.FullName -Raw -Encoding UTF8
}

$promptLines = @(
    "You are converting an approved Engineering Manager execution plan into a structured AI Company OS backlog.",
    "",
    "Source task: $SourceTaskId",
    "Work request: $workRequestId",
    "",
    "Create small, independently verifiable tasks rather than giant work-stream tickets.",
    "Each item must have exactly one primary owner from the allowed roles.",
    "Encode dependencies only by logical item key; the materializer will translate them to AICO IDs.",
    "Preserve the plan's priorities and critical path.",
    "Create explicit DECISION items for unresolved PM/CTO/CEO decisions before dependent implementation work.",
    "If implementation authorization is required, include an explicit DECISION task near the root of the graph and set implementation_authorization_key to that item key.",
    "Use implementation_authorization_key = NONE only when the approved source plan explicitly requires no implementation authorization.",
    "Do not silently resolve open product, architecture, security or operational decisions.",
    "IMPLEMENTATION items must be narrow enough for one specialist to execute and verify.",
    "VALIDATION items should depend on the implementation they validate.",
    "Acceptance criteria must be behavioral and testable.",
    "Do not duplicate findings that can be closed by the same tightly-scoped change.",
    "Every explicitly planned source finding/task that requires downstream work must be represented by a DECISION, IMPLEMENTATION, VALIDATION or OPERATIONS item; do not create a decision without the downstream work it gates.",
    "Every non-authorization DECISION item that exists to unblock engineering work must be referenced directly or transitively by at least one downstream item.",
    "Do not combine primary responsibilities from different specialist domains into one ticket. Split backend/database/performance work from frontend/CSS/UI work, and split implementation from validation when they have different owners.",
    "Do not create implementation work unrelated to the approved report.",
    "Return only JSON matching the supplied schema."
)
$prompt = $promptLines -join [Environment]::NewLine

$context = @(
    "===== SOURCE TASK =====",
    $task,
    "",
    "===== APPROVED ENGINEERING MANAGER REPORT =====",
    $report,
    "",
    "===== LATEST RESULT =====",
    $resultText
) -join [Environment]::NewLine

$runtimeDir = Join-Path $root ".codex\runtime"
$planDir = Join-Path $root "docs\engineering\plans"
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
New-Item -ItemType Directory -Force -Path $planDir | Out-Null

$outputPath = Join-Path $runtimeDir ($SourceTaskId + "-engineering-backlog.json")
$planPath = Join-Path $planDir ($SourceTaskId + "-engineering-backlog.json")

$execution = $null

if ($ReuseExistingOutput) {
    if (-not (Test-Path $outputPath)) {
        throw "Cannot reuse backlog output because it does not exist: $outputPath"
    }

    Write-Host "Reusing existing structured backlog output for $SourceTaskId..." -ForegroundColor Cyan
}
else {
    Write-Host "Generating structured engineering backlog from $SourceTaskId..." -ForegroundColor Cyan
    $execution = & $routerPath -Provider $Provider -ProjectPath $root -Prompt $prompt -Context $context -SchemaPath $schemaPath -OutputPath $outputPath -Model $Model

    if (-not (Test-Path $outputPath)) {
        throw "Backlog provider did not produce structured output: $outputPath"
    }
}

$backlog = Get-Content $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
$backlog = Repair-MojibakeObject -Value $backlog

if ([string]$backlog.source_task_id -ne $SourceTaskId) {
    throw "Backlog source_task_id mismatch. Expected $SourceTaskId, got $($backlog.source_task_id)"
}

if (-not [string]::IsNullOrWhiteSpace($workRequestId) -and [string]$backlog.work_request_id -ne $workRequestId) {
    throw "Backlog work_request_id mismatch. Expected $workRequestId, got $($backlog.work_request_id)"
}

$authorizationKey = Resolve-ImplementationAuthorizationKey -Backlog $backlog
$backlog.implementation_authorization_key = $authorizationKey

$keys = @{}
foreach ($item in @($backlog.items)) {
    $key = [string]$item.key
    if ($keys.ContainsKey($key)) { throw "Duplicate backlog item key: $key" }
    $keys[$key] = $true
}

foreach ($item in @($backlog.items)) {
    foreach ($dependency in @($item.dependencies)) {
        if (-not $keys.ContainsKey([string]$dependency)) {
            throw "Unknown dependency key '$dependency' referenced by item $($item.key)"
        }
        if ([string]$dependency -eq [string]$item.key) {
            throw "Backlog item $($item.key) cannot depend on itself."
        }
    }
}

if ($authorizationKey -ne "NONE" -and -not $keys.ContainsKey($authorizationKey)) {
    throw "Resolved implementation authorization key '$authorizationKey' does not reference a backlog item."
}

$normalizedJson = $backlog | ConvertTo-Json -Depth 100
Write-Utf8NoBom $planPath $normalizedJson

Write-Host "Structured engineering backlog generated:" -ForegroundColor Green
Write-Host $planPath
Write-Host ("Items: " + @($backlog.items).Count)
if ($null -ne $execution) {
    Write-Host ("Provider: " + $execution.Provider)
    Write-Host ("Model: " + $execution.Model)
}
else {
    Write-Host "Provider: REUSED_EXISTING_OUTPUT"
    Write-Host "Model: N/A"
}
