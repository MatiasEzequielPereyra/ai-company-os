param(
    [Parameter(Mandatory = $true)]
    [string]$SourceTaskId,

    [string]$ProjectPath = ".",

    [ValidateSet("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok")]
    [string]$Provider = "Auto",

    [string]$Model = "",

    [switch]$ReuseExistingOutput,
    [object]$TaskExecutionLease = $null
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

function Test-IsExplicitImplementationAuthorizationDecision {
    param([object]$Item)

    if ($null -eq $Item -or [string]$Item.kind -ne "DECISION") {
        return $false
    }

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

    if ([string]::IsNullOrWhiteSpace($SourceEvidence)) {
        return $false
    }

    return (
        $SourceEvidence -match
        '(?i)\b(?:requires? no implementation authorization|no implementation authorization (?:is )?required|implementation authorization (?:is )?not required|does not require implementation authorization)\b'
    )
}

function Resolve-ImplementationAuthorizationKey {
    param(
        [object]$Backlog,
        [string]$SourceEvidence = ""
    )

    $requested = [string]$Backlog.implementation_authorization_key
    if ([string]::IsNullOrWhiteSpace($requested)) {
        throw "Backlog implementation_authorization_key cannot be empty."
    }

    if ($requested -eq "NONE") {
        if (-not (Test-SourceExplicitlyRequiresNoImplementationAuthorization -SourceEvidence $SourceEvidence)) {
            throw (
                "implementation_authorization_key NONE is not supported by approved source evidence. " +
                "Use NONE only when the approved source explicitly requires no implementation authorization."
            )
        }

        return "NONE"
    }

    $items = @($Backlog.items)
    $exact = @($items | Where-Object { [string]$_.key -eq $requested })
    if ($exact.Count -eq 1) {
        if ([string]$exact[0].kind -ne "DECISION") {
            throw "Implementation authorization item '$requested' must be a DECISION."
        }

        if (-not (Test-IsExplicitImplementationAuthorizationDecision -Item $exact[0])) {
            throw (
                "Implementation authorization item '" + $requested +
                "' does not explicitly authorize implementation."
            )
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
            if (-not (Test-IsExplicitImplementationAuthorizationDecision -Item $_)) {
                return $false
            }

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
            return (Test-IsExplicitImplementationAuthorizationDecision -Item $_)
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
. (Join-Path $PSScriptRoot "task-execution-lock.ps1")
$sourceScope = Enter-TaskExecutionScope -ProjectPath $root -Id $SourceTaskId -Operation "GENERATE-ENGINEERING-BACKLOG" -Lease $TaskExecutionLease
try {
$taskPath = Join-Path $root ("tasks\" + $SourceTaskId + ".md")
$reportPath = Join-Path $root ("docs\engineering\agent-reports\" + $SourceTaskId + ".md")
$schemaPath = Join-Path $root "schemas\engineering-backlog.schema.json"
$routerPath = Join-Path $PSScriptRoot "provider-router.ps1"
$semanticValidatorPath = Join-Path $PSScriptRoot "validate-engineering-backlog-semantics.ps1"

foreach ($path in @($taskPath,$reportPath,$schemaPath,$routerPath,$semanticValidatorPath)) {
    if (-not (Test-Path $path)) { throw "Required backlog-generation input not found: $path" }
}

$task = Get-Content $taskPath -Raw -Encoding UTF8
$status = Read-Field $task "Status"
$owner = Read-Field $task "Owner"
$workRequestId = Read-Field $task "Work request"

if ($owner -ne "engineering-manager") {
    throw "Engineering backlog source must be owned by engineering-manager. Current owner: $owner"
}

if ($status -ne "DONE") {
    throw "Source planning task $SourceTaskId must be DONE before executable backlog generation. Current status: $status"
}

$report = Get-Content $reportPath -Raw -Encoding UTF8

$executionPlanText = ""
$executionPlanPath = Join-Path $root ("docs\engineering\plans\" + $SourceTaskId + "-execution-plan.json")
if (Test-Path $executionPlanPath -PathType Leaf) {
    $executionPlanText = Get-Content $executionPlanPath -Raw -Encoding UTF8
}

$hasStructuredExecutionWork = $false
if (-not [string]::IsNullOrWhiteSpace($executionPlanText)) {
    try {
        $executionPlan = $executionPlanText | ConvertFrom-Json
        $hasStructuredExecutionWork = (@($executionPlan.executable_work).Count -gt 0)
    }
    catch {
        throw "Canonical Engineering Manager execution plan is invalid JSON: $executionPlanPath"
    }
}

if (-not $hasStructuredExecutionWork) {
    $substantiveReportBody = Get-SubstantiveReportBody -Report $report
    if ($substantiveReportBody.Length -lt 80) {
        throw (
            "Engineering Manager source evidence is not substantive enough to generate an executable backlog. " +
            "Provide a canonical execution plan with executable_work or a substantive approved report."
        )
    }
}

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
    "Do not copy AICO task IDs from the approved planning workflow into item dependencies; completed upstream planning tasks are already satisfied.",
    "Preserve the plan's priorities and critical path.",
    "When a canonical structured execution plan is supplied, treat its executable_work items as authoritative downstream scope and preserve their keys, kinds, owners, areas, dependencies and verification intent.",
    "Create explicit DECISION items for unresolved PM/CTO/CEO decisions before dependent implementation work.",
    "If implementation authorization is required, include an explicit DECISION task near the root of the graph and set implementation_authorization_key to that item key.",
    "Use implementation_authorization_key = NONE only when the approved source plan explicitly requires no implementation authorization.",
    "Do not use an unresolved-blockers decision or unrelated DECISION as implementation authorization.",
    "Implementation authorization must be explicit in the referenced DECISION.",
    "Do not silently resolve open product, architecture, security or operational decisions.",
    "IMPLEMENTATION items must be narrow enough for one specialist to execute and verify.",
    "Every IMPLEMENTATION objective must state the concrete repository/product change to make; never use generic orchestration boilerplate.",
    "Every IMPLEMENTATION item must include at least one concrete behavioral acceptance criterion tied to that change.",
    "Testing requirements must be evidence-based from the approved source task, report, or canonical execution plan.",
    "Never invent test modules, test files, package scripts, commands, or verification targets that are not supported by the approved source evidence.",
    "For IMPLEMENTATION work with no concrete verifier documented in approved source evidence, use git diff --check instead of inventing a command.",
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
    "===== CANONICAL EXECUTION PLAN =====",
    $executionPlanText,
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
    $execution = & $routerPath -Provider $Provider -ProjectPath $root -Prompt $prompt -Context $context -SchemaPath $schemaPath -OutputPath $outputPath -Model $Model -Role "engineering-manager" -Workload "analysis" -SemanticValidatorPath $semanticValidatorPath

    if (-not (Test-Path $outputPath)) {
        throw "Backlog provider did not produce structured output: $outputPath"
    }
}

$backlog = Get-Content $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
$backlog = Repair-MojibakeObject -Value $backlog

# ReuseExistingOutput bypasses provider routing. Revalidate all structured
# output here so fresh and reused paths enforce the same semantic contract.
& $semanticValidatorPath -JsonPath $outputPath | Out-Null

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

if ([string]$backlog.source_task_id -ne $SourceTaskId) {
    throw "Backlog source_task_id mismatch. Expected $SourceTaskId, got $($backlog.source_task_id)"
}

if (-not [string]::IsNullOrWhiteSpace($workRequestId) -and [string]$backlog.work_request_id -ne $workRequestId) {
    throw "Backlog work_request_id mismatch. Expected $workRequestId, got $($backlog.work_request_id)"
}

$sourceEvidence = @($context,$executionPlanText) -join [Environment]::NewLine
$authorizationKey = Resolve-ImplementationAuthorizationKey -Backlog $backlog -SourceEvidence $sourceEvidence
$backlog.implementation_authorization_key = $authorizationKey

$keys = @{}
foreach ($item in @($backlog.items)) {
    $key = [string]$item.key
    if ($keys.ContainsKey($key)) { throw "Duplicate backlog item key: $key" }
    $keys[$key] = $true
}

foreach ($item in @($backlog.items)) {
    $repairedDependencies = @()

    foreach ($dependencyValue in @($item.dependencies)) {
        $dependency = [string]$dependencyValue

        if ($keys.ContainsKey($dependency)) {
            if ($dependency -eq [string]$item.key) {
                throw "Backlog item $($item.key) cannot depend on itself."
            }

            $repairedDependencies += $dependency
            continue
        }

        if ($dependency -match '^AICO-[0-9]+$') {
            $upstreamTaskPath = Join-Path $root ("tasks\" + $dependency + ".md")

            if (-not (Test-Path $upstreamTaskPath -PathType Leaf)) {
                throw "Unknown dependency key '$dependency' referenced by item $($item.key)"
            }

            $upstreamTask = Get-Content $upstreamTaskPath -Raw -Encoding UTF8
            $upstreamStatus = Read-Field $upstreamTask "Status"
            $upstreamWorkRequestId = Read-Field $upstreamTask "Work request"

            if (
                $upstreamStatus -eq "DONE" -and
                -not [string]::IsNullOrWhiteSpace($workRequestId) -and
                $upstreamWorkRequestId -eq $workRequestId
            ) {
                Write-Host (
                    "Repaired satisfied upstream planning dependency for " +
                    [string]$item.key + ": removed " + $dependency
                ) -ForegroundColor Yellow
                continue
            }

            throw (
                "External AICO dependency '" + $dependency + "' referenced by item " +
                [string]$item.key +
                " is not a satisfied DONE task from work request " +
                $workRequestId +
                ". Current status: " + $upstreamStatus +
                "; work request: " + $upstreamWorkRequestId
            )
        }

        throw "Unknown dependency key '$dependency' referenced by item $($item.key)"
    }

    $item.dependencies = @($repairedDependencies | Select-Object -Unique)
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

} finally { Exit-TaskExecutionScope -Scope $sourceScope }
