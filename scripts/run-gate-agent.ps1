param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Review","QA","Security")]
    [string]$Gate,

    [string]$ProjectPath = ".",

    [ValidateSet("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok")]
    [string]$Provider = "Auto",

    [string]$Model = ""
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Add-Artifact {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$Root,
        [string]$Path,
        [string]$Label,
        [int]$MaxChars = 60000
    )

    if (-not (Test-Path $Path -PathType Leaf)) { return }

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@("\","/"))
    $pathFull = [System.IO.Path]::GetFullPath((Resolve-Path $Path).Path)
    $rootPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar

    if (-not $pathFull.StartsWith($rootPrefix,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Explicit gate artifact is outside the project root: $pathFull"
    }

    $relativePath = $pathFull.Substring($rootPrefix.Length).Replace("\","/")

    $content = Get-Content $pathFull -Raw -Encoding UTF8
    if ($null -eq $content) { $content = "" }
    # Authoritative evidence is never clipped by a per-artifact quota.
    # The router enforces the complete envelope against each finite candidate budget.

    [void]$Builder.AppendLine("")
    [void]$Builder.AppendLine("")
    [void]$Builder.AppendLine("===== " + $Label + " =====")
    [void]$Builder.AppendLine("Repository-relative path: " + $relativePath)
    [void]$Builder.AppendLine("Evidence type: explicit gate artifact")
    [void]$Builder.AppendLine("")
    [void]$Builder.AppendLine($content)
}

function Invoke-CandidateGit {
    param([string[]]$Arguments)
    $savedPreference = $ErrorActionPreference
    $nativePreference = Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $savedNative = if ($null -ne $nativePreference) { $nativePreference.Value } else { $null }
    try {
        $ErrorActionPreference = "Continue"
        $PSNativeCommandUseErrorActionPreference = $false
        $lines = @(& git @Arguments 2>$null)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
        if ($null -ne $nativePreference) { $PSNativeCommandUseErrorActionPreference = $savedNative }
        else { Remove-Variable PSNativeCommandUseErrorActionPreference -Scope Local -ErrorAction SilentlyContinue }
    }
    if ($exitCode -ne 0) { throw "Unable to inspect authoritative implementation candidate with Git." }
    return $lines
}

function Add-ImplementationCandidate {
    param([System.Text.StringBuilder]$Builder,[string]$Root,[string]$TaskId,[string]$TaskContent,[string]$ReportContent)
    $evidencePath = Join-Path $Root ("docs\engineering\writable-evidence\" + $TaskId + ".md")
    $declared = $ReportContent -match ('(?i)writable-evidence[\\/]' + [regex]::Escape($TaskId) + '\.md')
    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf) -and -not $declared) { return }
    if ((Read-Field $TaskContent "Work kind") -cne "IMPLEMENTATION") { return }
    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) { throw "Declared writable implementation evidence is missing: $evidencePath" }
    $evidenceContent = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8
    $workspaceField = Read-Field $evidenceContent "Worktree"
    $branch = "aico/" + $TaskId.ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($workspaceField) -or -not [IO.Path]::IsPathRooted($workspaceField)) {
        throw "Writable implementation candidate evidence must contain an absolute worktree path."
    }
    $workspace = [IO.Path]::GetFullPath($workspaceField).TrimEnd('\','/')
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    if ([string]::Equals($workspace,$rootFull,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Writable implementation candidate cannot be the primary checkout."
    }
    if (-not (Test-Path -LiteralPath $workspace -PathType Container)) { throw "Writable implementation candidate worktree is missing: $workspace" }
    if ((Get-Item -LiteralPath $workspace -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Writable implementation candidate worktree cannot be a reparse point."
    }
    $registered = $false
    $recordPath = ""
    foreach ($line in @(Invoke-CandidateGit -Arguments @("-C",$Root,"worktree","list","--porcelain"))) {
        if ($line -match '^worktree (.+)$') { $recordPath = [IO.Path]::GetFullPath($Matches[1]).TrimEnd('\','/') }
        if ($line -ceq ("branch refs/heads/" + $branch) -and [string]::Equals($recordPath,$workspace,[StringComparison]::OrdinalIgnoreCase)) { $registered = $true }
    }
    # Registration metadata alone may survive a replaced worktree directory.
    # Both Git views must resolve to the same repository common directory.
    $rootCommon = (@(Invoke-CandidateGit -Arguments @("-C",$Root,"rev-parse","--git-common-dir")) -join '').Trim()
    $candidateCommon = (@(Invoke-CandidateGit -Arguments @("-C",$workspace,"rev-parse","--git-common-dir")) -join '').Trim()
    if ([string]::IsNullOrWhiteSpace($rootCommon) -or [string]::IsNullOrWhiteSpace($candidateCommon)) {
        throw "Writable implementation candidate repository identity is missing."
    }
    if (-not [IO.Path]::IsPathRooted($rootCommon)) { $rootCommon = Join-Path $Root $rootCommon }
    if (-not [IO.Path]::IsPathRooted($candidateCommon)) { $candidateCommon = Join-Path $workspace $candidateCommon }
    $rootCommon = [IO.Path]::GetFullPath($rootCommon).TrimEnd([char[]]@("\","/"))
    $candidateCommon = [IO.Path]::GetFullPath($candidateCommon).TrimEnd([char[]]@("\","/"))
    if (-not [string]::Equals($rootCommon,$candidateCommon,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Writable implementation candidate belongs to a different Git repository."
    }
    $actualBranch = (@(Invoke-CandidateGit -Arguments @("-C",$workspace,"branch","--show-current")) -join '').Trim()
    if (-not $registered -or $actualBranch -cne $branch -or (Read-Field $evidenceContent "Branch") -cne $branch) {
        throw "Writable implementation candidate branch/registration does not match the task."
    }
    $policyPath = Join-Path $Root '.codex\writable-policy.json'
    if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) { throw "Writable candidate policy is missing." }
    $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $tracked = @(Invoke-CandidateGit -Arguments @("-C",$workspace,"-c","core.quotePath=false","diff","--name-only","HEAD","--"))
    $untracked = @(Invoke-CandidateGit -Arguments @("-C",$workspace,"-c","core.quotePath=false","ls-files","--others","--exclude-standard"))
    $paths = @(@($tracked + $untracked) | Sort-Object -Unique)
    if ($paths.Count -eq 0) { throw "Writable implementation candidate has no changed source files." }
    if ($paths.Count -gt [int]$policy.max_changed_files) { throw "Writable implementation candidate exceeds policy file-count limit." }
    [void]$Builder.AppendLine('')
    [void]$Builder.AppendLine('===== WRITABLE IMPLEMENTATION CANDIDATE =====')
    [void]$Builder.AppendLine("Worktree: $workspace")
    [void]$Builder.AppendLine("Branch: $branch")
    [void]$Builder.AppendLine('Provenance: current registered task worktree state captured for this gate; hashes describe this capture, not an immutable owner snapshot.')
    [void]$Builder.AppendLine('Evidence type: authoritative actual implementation candidate; primary repository source is baseline comparison only.')
    $totalBytes = 0L
    foreach ($pathValue in $paths) {
        $relative = ([string]$pathValue).Replace('\','/')
        $segments = @($relative -split '/')
        if ([IO.Path]::IsPathRooted($relative) -or $segments -contains '..' -or $segments -contains '.' -or $segments -contains '' -or $relative -match '[\r\n]') { throw "Unsafe writable implementation candidate path: $relative" }
        $lower = $relative.ToLowerInvariant()
        foreach ($prefixValue in @($policy.protected_path_prefixes)) {
            $prefix = ([string]$prefixValue).Replace('\','/').TrimEnd('/').ToLowerInvariant()
            if ($lower -eq $prefix -or $lower.StartsWith($prefix + '/')) { throw "Protected writable implementation candidate path: $relative" }
        }
        foreach ($pattern in @($policy.secret_name_patterns)) {
            if ($lower -match [string]$pattern) { throw "Secret-sensitive writable implementation candidate path: $relative" }
        }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $workspace $relative))
        if (-not $fullPath.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw "Writable implementation candidate path escapes worktree." }
        $current = $fullPath
        while (-not [string]::Equals($current,$workspace,[StringComparison]::OrdinalIgnoreCase)) {
            if (Test-Path -LiteralPath $current) {
                if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Writable implementation candidate path traverses a reparse point: $relative" }
            }
            $current = Split-Path $current -Parent
        }
        [void]$Builder.AppendLine('')
        [void]$Builder.AppendLine("Repository-relative path: $relative")
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            [void]$Builder.AppendLine('Candidate operation: DELETE (absent from current worktree)')
            continue
        }
        $stream = [IO.File]::Open($fullPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $length = $stream.Length
            $totalBytes += $length
            if ($length -gt [long]$policy.max_file_bytes -or $totalBytes -gt [long]$policy.max_total_write_bytes) { throw "Writable implementation candidate exceeds policy source-size limit: $relative" }
            $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
            $stream.Position = 0
            $reader = New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true,1024,$true)
            try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        finally { $sha.Dispose(); $stream.Dispose() }
        [void]$Builder.AppendLine("SHA256: $hash")
        [void]$Builder.AppendLine("Bytes: $length")
        [void]$Builder.AppendLine('Candidate operation: CURRENT SOURCE')
        [void]$Builder.AppendLine('')
        [void]$Builder.AppendLine($content)
    }
}

function Get-ConcreteStrings {
    param([object]$Value)

    return @(
        @($Value) |
            ForEach-Object {
                if ($null -ne $_) { ([string]$_).Trim() }
            } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            }
    )
}

function Assert-StructuredFields {
    param(
        [object]$Result,
        [string[]]$Fields,
        [string]$Label
    )

    foreach ($field in $Fields) {
        if ($null -eq $Result.PSObject.Properties[$field]) {
            throw "$Label result missing field: $field"
        }
    }
}

$root = (Resolve-Path $ProjectPath).Path
$taskPath = Join-Path $root ("tasks\" + $Id + ".md")
if (-not (Test-Path $taskPath)) { throw "Task not found: $taskPath" }

$taskContent = Get-Content $taskPath -Raw -Encoding UTF8
$status = Read-Field $taskContent "Status"
$owner = Read-Field $taskContent "Owner"

$expectedStatus = switch ($Gate) {
    "Review" { "REVIEW" }
    "QA" { "QA" }
    "Security" { "SECURITY" }
}

if ($status -ne $expectedStatus) {
    throw "Task $Id must be $expectedStatus for $Gate gate. Current status: $status"
}

$lockHelperPath = Join-Path $PSScriptRoot "task-execution-lock.ps1"
if (-not (Test-Path $lockHelperPath -PathType Leaf)) {
    throw "Task execution lock helper not found: $lockHelperPath"
}
. $lockHelperPath
$taskExecutionLock = Enter-TaskExecutionLock -ProjectPath $root -Id $Id -Operation "GATE"

try {
$reviewerRole = switch ($Gate) {
    "Review" { "engineering-manager" }
    "QA" {
        if ($owner -eq "qa") { "engineering-manager" } else { "qa" }
    }
    "Security" {
        if ($owner -eq "security") { "engineering-manager" } else { "security" }
    }
}

$schemaName = switch ($Gate) {
    "Review" { "review-result.schema.json" }
    "QA" { "qa-gate-result.schema.json" }
    "Security" { "security-gate-result.schema.json" }
}

$dispatchPath = Join-Path $root ("docs\engineering\dispatch\" + $Id + ".md")
$originalOwnerRolePath = Join-Path $root (".codex\agents\" + $owner + ".md")

$schemaPath = Join-Path $root ("schemas\" + $schemaName)
$routerPath = Join-Path $PSScriptRoot "provider-router.ps1"
$gateSemanticValidatorPath = Join-Path $PSScriptRoot "validate-gate-result-semantics.ps1"
$diagnosticValidatorPath = Join-Path $PSScriptRoot "validate-diagnostic-evidence.ps1"
$contextBuilderPath = Join-Path $PSScriptRoot "build-agent-context.ps1"
$localResolverPath = Join-Path $PSScriptRoot "local-runtime\resolve-local-runtime.ps1"
$localRuntimeConfigPath = Join-Path $root ".codex\local-runtime-config.json"

if ([string]::IsNullOrWhiteSpace($owner)) {
    throw "Task $Id has no original Owner."
}

foreach ($required in @(
    $schemaPath,
    $routerPath,
    $gateSemanticValidatorPath,
    $contextBuilderPath,
    $dispatchPath,
    $originalOwnerRolePath
)) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Required gate component not found: $required"
    }
}

$localRuntime = $null
$localRuntimeConfigured = (
    (Test-Path $localResolverPath -PathType Leaf) -and
    (Test-Path $localRuntimeConfigPath -PathType Leaf)
)

if ($Provider -eq "Ollama" -and -not $localRuntimeConfigured) {
    throw "Ollama local runtime is not configured for this project. Run initialize-local-runtime.ps1 first."
}

if ($Provider -in @("Auto","Ollama") -and $localRuntimeConfigured) {
    $localArgs = @{
        ProjectPath = $root
        Role = $reviewerRole
        Workload = "gate"
    }

    if ($Provider -eq "Ollama" -and -not [string]::IsNullOrWhiteSpace($Model)) {
        $localArgs.ModelOverride = $Model
    }

    $localRuntime = & $localResolverPath @localArgs
    if ($Provider -eq "Ollama" -and -not [bool]$localRuntime.Available) {
        throw ("Ollama local runtime unavailable: " + [string]$localRuntime.Reason)
    }

    if ([bool]$localRuntime.Available) {
        Write-Host ("Local runtime: " + $localRuntime.Profile + " -> " + $localRuntime.Model) -ForegroundColor DarkGray
    }
}

$maxChars = 180000
$artifactMaxChars = 60000
$configPath = Join-Path $root ".codex\provider-config.json"
$providerConfig = $null
if (Test-Path $configPath) {
    try {
        $providerConfig = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $providerConfig.gate_context_max_chars) {
            $maxChars = [int]$providerConfig.gate_context_max_chars
        }

        # Provider-specific limits belong to the router. Construction preserves
        # authoritative artifacts in full for every candidate, including explicit Ollama.

    }
    catch {
        throw "Invalid provider configuration: $configPath"
    }
}

Write-Host "Building gate context for $Gate / $reviewerRole..." -ForegroundColor DarkGray
$baseContext = & $contextBuilderPath -ProjectPath $root -Id $Id -Owner $reviewerRole -MaxChars $maxChars

$evidence = New-Object System.Text.StringBuilder
[void]$evidence.Append($baseContext)

Add-Artifact `
    -Builder $evidence `
    -Root $root `
    -Path $taskPath `
    -Label "CANONICAL TASK" `
    -MaxChars $artifactMaxChars

Add-Artifact `
    -Builder $evidence `
    -Root $root `
    -Path $dispatchPath `
    -Label "DISPATCH PACKET" `
    -MaxChars $artifactMaxChars

Add-Artifact `
    -Builder $evidence `
    -Root $root `
    -Path $originalOwnerRolePath `
    -Label "ORIGINAL OWNER ROLE CONTRACT" `
    -MaxChars $artifactMaxChars

$reportPath = Join-Path $root ("docs\engineering\agent-reports\" + $Id + ".md")

if (-not (Test-Path $reportPath -PathType Leaf)) {
    throw "Primary agent report not found for gate validation: $reportPath"
}

Add-Artifact `
    -Builder $evidence `
    -Root $root `
    -Path $reportPath `
    -Label "PRIMARY AGENT REPORT" `
    -MaxChars $artifactMaxChars

$latestResult = Get-ChildItem (Join-Path $root "docs\engineering\results") -Filter ($Id + "-result-*.md") -File -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

if ($null -eq $latestResult) {
    throw "Latest task result not found for gate validation: $Id"
}

Add-Artifact `
    -Builder $evidence `
    -Root $root `
    -Path $latestResult.FullName `
    -Label "LATEST TASK RESULT" `
    -MaxChars $artifactMaxChars

$diagnosticPath = Join-Path $root ("docs\engineering\diagnostics\" + $Id + "-diagnostic-v1.json")
$taskType = (Read-Field $taskContent "Type").Trim().ToUpperInvariant()
$taskWorkKind = (Read-Field $taskContent "Work kind").Trim().ToUpperInvariant()
$isBugImplementation = ($taskType -eq "BUG" -and $taskWorkKind -eq "IMPLEMENTATION")

if (Test-Path -LiteralPath $diagnosticPath -PathType Leaf) {
    if (-not (Test-Path -LiteralPath $diagnosticValidatorPath -PathType Leaf)) {
        throw "Diagnostic evidence validator missing: $diagnosticValidatorPath"
    }
    & $diagnosticValidatorPath -JsonPath $diagnosticPath | Out-Null
    Add-Artifact -Builder $evidence -Root $root -Path $diagnosticPath -Label "DIAGNOSTIC EVIDENCE CONTRACT V1" -MaxChars $artifactMaxChars
}
elseif ($isBugImplementation) {
    [void]$evidence.AppendLine("===== DIAGNOSTIC EVIDENCE CONTRACT V1 =====")
    [void]$evidence.AppendLine("Repository-relative path: docs/engineering/diagnostics/$Id-diagnostic-v1.json")
    [void]$evidence.AppendLine("Evidence type: required BUG diagnostic artifact")
    [void]$evidence.AppendLine("MISSING: a BUG implementation cannot receive Review APPROVE or QA PASS without COMPLETE diagnostic evidence.")
    [void]$evidence.AppendLine("===== END DIAGNOSTIC EVIDENCE CONTRACT V1 =====")
    [void]$evidence.AppendLine()
}

if ($Gate -in @("QA","Security")) {
    $latestReview = Get-ChildItem (Join-Path $root "docs\engineering\reviews") -Filter ($Id + "-review-*.md") -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -ne $latestReview) {
        Add-Artifact -Builder $evidence -Root $root -Path $latestReview.FullName -Label "LATEST INDEPENDENT REVIEW" -MaxChars $artifactMaxChars
    }
}

if ($Gate -eq "Security") {
    $qaPath = Join-Path $root ("docs\engineering\qa\" + $Id + "-qa.md")
    Add-Artifact -Builder $evidence -Root $root -Path $qaPath -Label "QA GATE" -MaxChars $artifactMaxChars
}

Add-ImplementationCandidate -Builder $evidence -Root $root -TaskId $Id -TaskContent $taskContent -ReportContent (Get-Content $reportPath -Raw -Encoding UTF8)

$promptLines = @(
    "You are executing an independent AI Company OS quality gate.",
    "",
    "Gate: $Gate",
    "Task: $Id",
    "Original owner: $owner",
    "Independent gate role: $reviewerRole",
    "",
    "Evaluate the assigned task deliverable against its objective, acceptance criteria, evidence quality, internal consistency and role boundaries.",
    "This gate evaluates whether the DELIVERABLE is good enough to progress through the workflow.",
    "The ORIGINAL OWNER ROLE CONTRACT is authoritative for the role-owned outputs and responsibilities that the deliverable must actually produce.",
    "Compare the PRIMARY AGENT REPORT against the original owner role contract, especially its ## Output section and role Responsibilities, together with the canonical task and dispatch packet.",
    "Validate that every material role-required output was actually produced as substantive work.",
    "Repeating Objective / Requirements / Acceptance Criteria does not count as producing the role-owned deliverable.",
    "A report that only paraphrases task metadata, requirements or acceptance criteria is incomplete when the original role requires architecture, analysis, decisions, plans, contracts, risks or other substantive outputs.",
    "Review must return CHANGES_REQUIRED when a material role-required output is missing; QA cannot PASS a deliverable with missing required role outputs.",
    "Do not reject or fail merely because the underlying product has defects, P0/P1 findings, security issues, release blockers or failed product checks documented by the report.",
    "A strong audit report is allowed to conclude that the product is not production-ready.",
    "Reject/fail only when the report or task delivery itself is materially incomplete, unsupported, contradictory, outside role authority, or fails the assigned acceptance criteria.",
    "Do not invent repository evidence.",
    "Use only the supplied context and artifacts.",
    "When WRITABLE IMPLEMENTATION CANDIDATE is supplied, evaluate its full source as the authoritative actual implementation; primary repository source is only baseline comparison, never the candidate implementation.",
    "Explicit gate artifacts are authoritative supplied evidence when they include a Repository-relative path.",
    "An explicit gate artifact remains authoritative even when its path is intentionally excluded from the generic repository inventory.",
    "Do not infer that an explicit gate artifact is missing merely because it is absent from the generic repository inventory.",
    "Correlate result ChangedArtifacts references with the canonical Repository-relative path attached to explicit gate artifacts.",
    "When DIAGNOSTIC EVIDENCE CONTRACT V1 is supplied, treat runtime receipts and the frozen signal fingerprint as authoritative diagnostic execution evidence.",
    "For a BUG repair, Review must reject unsupported CONFIRMED causes, signal substitution, WORKAROUND mislabeled as REPAIR, or missing same-signal replay.",
    "For a BUG repair, QA must assess the originally broken behavior and cannot PASS when post_fix_replay is not FIXED_OBSERVED with the same frozen signal fingerprint.",
    "",
    "For Review: APPROVE requires missing_required_outputs=[] and deliverable_defects=[]. CHANGES_REQUIRED requires at least one concrete missing_required_output or deliverable_defect.",
    "For QA: assess concrete task/role criteria in criteria_assessment. PASS cannot contain an UNSATISFIED criterion. FAIL requires at least one concrete UNSATISFIED criterion.",
    "For Security: security_relevant describes whether this deliverable has an additional security-relevant aspect to verify.",
    "Security FAIL is valid only when security_relevant=true and deliverable_security_defects contains at least one concrete security defect OF THE DELIVERABLE.",
    "Future product vulnerabilities, product security findings, implementation risks or security work documented by an otherwise valid deliverable are not deliverable_security_defects by themselves.",
    "For a standard planning/analysis task with no additional security-relevant aspect, return NOT_APPLICABLE with security_relevant=false and deliverable_security_defects=[].",
    "Security PASS requires security_relevant=true and no deliverable_security_defects.",
    "",
    "Return only the structured JSON required by the supplied schema."
)

$prompt = $promptLines -join [Environment]::NewLine

$runtimeDir = Join-Path $root ".codex\runtime"
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
$outputPath = Join-Path $runtimeDir ($Id + "-" + $Gate.ToLowerInvariant() + "-gate.json")

Write-Host ("Gate context budget: generic=" + $maxChars + " chars; authoritative artifacts preserved in full for candidate budget validation") -ForegroundColor DarkGray
Write-Host "Running $Gate gate: $reviewerRole -> $Id" -ForegroundColor Cyan
$execution = & $routerPath -Provider $Provider -ProjectPath $root -Prompt $prompt -Context $evidence.ToString() -SchemaPath $schemaPath -OutputPath $outputPath -Model $Model -Role $reviewerRole -Workload "gate" -SemanticValidatorPath $gateSemanticValidatorPath

if (-not (Test-Path $outputPath)) {
    throw "Gate provider did not produce structured output: $outputPath"
}

$result = Get-Content $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Provider routing performs semantic retry/fallback. Revalidate once more before
# mutating lifecycle state so alternate/custom router implementations also fail closed.
& $gateSemanticValidatorPath -JsonPath $outputPath | Out-Null

switch ($Gate) {
    "Review" {
        Assert-StructuredFields `
            -Result $result `
            -Fields @(
                "recommendation",
                "findings",
                "verification",
                "missing_required_outputs",
                "deliverable_defects"
            ) `
            -Label "Review"

        $missingRequiredOutputs = @(
            Get-ConcreteStrings -Value $result.missing_required_outputs
        )

        $deliverableDefects = @(
            Get-ConcreteStrings -Value $result.deliverable_defects
        )

        if ([string]$result.recommendation -eq "APPROVE") {
            if (
                $missingRequiredOutputs.Count -gt 0 -or
                $deliverableDefects.Count -gt 0
            ) {
                throw (
                    "Invalid structured Review APPROVE: missing_required_outputs " +
                    "and deliverable_defects must both be empty."
                )
            }
        }
        elseif ([string]$result.recommendation -eq "CHANGES_REQUIRED") {
            if (
                $missingRequiredOutputs.Count -eq 0 -and
                $deliverableDefects.Count -eq 0
            ) {
                throw (
                    "Invalid structured Review CHANGES_REQUIRED: identify at " +
                    "least one concrete missing required output or deliverable defect."
                )
            }
        }
        else {
            throw "Invalid structured Review recommendation: $($result.recommendation)"
        }

        & (Join-Path $PSScriptRoot "review-task.ps1") `
            -ProjectPath $root `
            -Id $Id `
            -Recommendation $result.recommendation `
            -Reviewer ("ai-" + $reviewerRole) `
            -Findings $result.findings `
            -Verification $result.verification
    }

    "QA" {
        Assert-StructuredFields `
            -Result $result `
            -Fields @(
                "outcome",
                "evidence",
                "findings",
                "criteria_assessment"
            ) `
            -Label "QA"

        $criteria = @($result.criteria_assessment)

        if ($criteria.Count -eq 0) {
            throw "Invalid structured QA result: criteria_assessment cannot be empty."
        }

        foreach ($criterion in $criteria) {
            Assert-StructuredFields `
                -Result $criterion `
                -Fields @("criterion","status","evidence") `
                -Label "QA criterion"

            if ([string]::IsNullOrWhiteSpace([string]$criterion.criterion)) {
                throw "Invalid structured QA criterion: criterion text is required."
            }

            if ([string]::IsNullOrWhiteSpace([string]$criterion.evidence)) {
                throw "Invalid structured QA criterion: evidence is required."
            }

            if (
                [string]$criterion.status -notin @(
                    "SATISFIED",
                    "UNSATISFIED",
                    "NOT_APPLICABLE"
                )
            ) {
                throw "Invalid structured QA criterion status: $($criterion.status)"
            }
        }

        $unsatisfiedCriteria = @(
            $criteria |
                Where-Object {
                    [string]$_.status -eq "UNSATISFIED"
                }
        )

        if ([string]$result.outcome -eq "PASS") {
            if ($unsatisfiedCriteria.Count -gt 0) {
                throw (
                    "Invalid structured QA PASS: at least one criterion is UNSATISFIED."
                )
            }
        }
        elseif ([string]$result.outcome -eq "FAIL") {
            if ($unsatisfiedCriteria.Count -eq 0) {
                throw (
                    "Invalid structured QA FAIL: identify at least one concrete " +
                    "UNSATISFIED criterion."
                )
            }
        }
        else {
            throw "Invalid structured QA outcome: $($result.outcome)"
        }

        & (Join-Path $PSScriptRoot "qa-task.ps1") `
            -ProjectPath $root `
            -Id $Id `
            -Outcome $result.outcome `
            -Evidence $result.evidence `
            -Findings $result.findings
    }

    "Security" {
        Assert-StructuredFields `
            -Result $result `
            -Fields @(
                "outcome",
                "evidence",
                "findings",
                "security_relevant",
                "deliverable_security_defects"
            ) `
            -Label "Security"

        $securityRelevant = [bool]$result.security_relevant

        $deliverableSecurityDefects = @(
            Get-ConcreteStrings -Value $result.deliverable_security_defects
        )

        switch ([string]$result.outcome) {
            "PASS" {
                if (-not $securityRelevant) {
                    throw (
                        "Invalid structured Security PASS: security_relevant=false; " +
                        "use NOT_APPLICABLE when no meaningful security verification applies."
                    )
                }

                if ($deliverableSecurityDefects.Count -gt 0) {
                    throw (
                        "Invalid structured Security PASS: deliverable_security_defects " +
                        "must be empty."
                    )
                }
            }

            "FAIL" {
                if (-not $securityRelevant) {
                    throw (
                        "Invalid structured Security FAIL: security_relevant must be true."
                    )
                }

                if ($deliverableSecurityDefects.Count -eq 0) {
                    throw (
                        "Invalid structured Security FAIL: at least one concrete " +
                        "security defect of the deliverable is required."
                    )
                }
            }

            "NOT_APPLICABLE" {
                if ($securityRelevant) {
                    throw (
                        "Invalid structured Security NOT_APPLICABLE: " +
                        "security_relevant must be false."
                    )
                }

                if ($deliverableSecurityDefects.Count -gt 0) {
                    throw (
                        "Invalid structured Security NOT_APPLICABLE: " +
                        "deliverable_security_defects must be empty."
                    )
                }
            }

            default {
                throw "Invalid structured Security outcome: $($result.outcome)"
            }
        }

        & (Join-Path $PSScriptRoot "security-task.ps1") `
            -ProjectPath $root `
            -Id $Id `
            -Outcome $result.outcome `
            -Evidence $result.evidence `
            -Findings $result.findings
    }
}

Write-Host ""
Write-Host "$Gate gate completed for $Id" -ForegroundColor Green
Write-Host ("Provider: " + $execution.Provider)
Write-Host ("Model: " + $execution.Model)
}
finally {
    Exit-TaskExecutionLock -Lock $taskExecutionLock
}
