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
    if ($content.Length -gt $MaxChars) {
        $content = $content.Substring(0,$MaxChars) + [Environment]::NewLine + "[TRUNCATED]"
    }

    [void]$Builder.AppendLine("")
    [void]$Builder.AppendLine("")
    [void]$Builder.AppendLine("===== " + $Label + " =====")
    [void]$Builder.AppendLine("Repository-relative path: " + $relativePath)
    [void]$Builder.AppendLine("Evidence type: explicit gate artifact")
    [void]$Builder.AppendLine("")
    [void]$Builder.AppendLine($content)
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
$contextBuilderPath = Join-Path $PSScriptRoot "build-agent-context.ps1"
$localResolverPath = Join-Path $PSScriptRoot "local-runtime\resolve-local-runtime.ps1"
$localRuntimeConfigPath = Join-Path $root ".codex\local-runtime-config.json"

if ([string]::IsNullOrWhiteSpace($owner)) {
    throw "Task $Id has no original Owner."
}

foreach ($required in @(
    $schemaPath,
    $routerPath,
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

        if ($null -ne $localRuntime -and [bool]$localRuntime.Available) {
            $maxChars = [Math]::Min($maxChars,[int]$localRuntime.GateContextMaxChars)
            $artifactMaxChars = [Math]::Min($artifactMaxChars,[int]$localRuntime.GateArtifactMaxChars)
        }
        elseif ($Provider -eq "Ollama") {
            if ($null -ne $providerConfig.ollama_gate_context_max_chars) {
                $maxChars = [Math]::Min($maxChars,[int]$providerConfig.ollama_gate_context_max_chars)
            }
            if ($null -ne $providerConfig.ollama_gate_artifact_max_chars) {
                $artifactMaxChars = [int]$providerConfig.ollama_gate_artifact_max_chars
            }
        }
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
    "Explicit gate artifacts are authoritative supplied evidence when they include a Repository-relative path.",
    "An explicit gate artifact remains authoritative even when its path is intentionally excluded from the generic repository inventory.",
    "Do not infer that an explicit gate artifact is missing merely because it is absent from the generic repository inventory.",
    "Correlate result ChangedArtifacts references with the canonical Repository-relative path attached to explicit gate artifacts.",
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

Write-Host ("Gate context budget: base=" + $maxChars + " chars, artifact=" + $artifactMaxChars + " chars") -ForegroundColor DarkGray
Write-Host "Running $Gate gate: $reviewerRole -> $Id" -ForegroundColor Cyan
$execution = & $routerPath -Provider $Provider -ProjectPath $root -Prompt $prompt -Context $evidence.ToString() -SchemaPath $schemaPath -OutputPath $outputPath -Model $Model -Role $reviewerRole -Workload "gate"

if (-not (Test-Path $outputPath)) {
    throw "Gate provider did not produce structured output: $outputPath"
}

$result = Get-Content $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json

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
