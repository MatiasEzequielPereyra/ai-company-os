param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)

    $script:failures.Add($Message)
    Write-Host ("FAIL: " + $Message) -ForegroundColor Red
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        Add-Failure $Message
        return $false
    }

    Write-Host ("PASS: " + $Message) -ForegroundColor Green
    return $true
}

function Write-NoBom {
    param(
        [string]$Path,
        [string]$Value
    )

    $parent = Split-Path $Path -Parent

    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $Value,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Read-Field {
    param(
        [string]$Path,
        [string]$Key
    )

    if (-not (Test-Path $Path)) {
        return ""
    }

    $content = Get-Content $Path -Raw -Encoding UTF8
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"

    if ($content -match $pattern) {
        return $Matches[1].Trim()
    }

    return ""
}

function New-GateFixture {
    param(
        [string]$Status,
        [string]$Mode,
        [ValidateSet("shallow","complete")]
        [string]$ReportKind = "complete"
    )

    $root = Join-Path $env:TEMP (
        "aico-role-gate-" +
        $Mode +
        "-" +
        [Guid]::NewGuid().ToString("N")
    )

    foreach ($dir in @(
        "scripts",
        "schemas",
        "tasks",
        ".codex",
        ".codex\agents",
        "docs\engineering\dispatch",
        "docs\engineering\agent-reports",
        "docs\engineering\results",
        "docs\engineering\reviews",
        "docs\engineering\qa",
        "docs\engineering\security"
    )) {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path (Join-Path $root $dir) |
            Out-Null
    }

    foreach ($scriptName in @(
        "run-gate-agent.ps1",
        "validate-gate-result-semantics.ps1",
        "task-execution-lock.ps1",
        "review-task.ps1",
        "assert-bug-diagnostic-evidence.ps1",
        "qa-task.ps1",
        "security-task.ps1",
        "update-task.ps1",
        "advance-task.ps1"
    )) {
        Copy-Item `
            (Join-Path $repoRoot ("scripts\" + $scriptName)) `
            (Join-Path $root ("scripts\" + $scriptName)) `
            -Force
    }

    foreach ($schemaName in @(
        "review-result.schema.json",
        "qa-gate-result.schema.json",
        "security-gate-result.schema.json"
    )) {
        Copy-Item `
            (Join-Path $repoRoot ("schemas\" + $schemaName)) `
            (Join-Path $root ("schemas\" + $schemaName)) `
            -Force
    }

    Copy-Item `
        (Join-Path $repoRoot ".codex\agents\cto.md") `
        (Join-Path $root ".codex\agents\cto.md") `
        -Force

    foreach ($role in @(
        "engineering-manager",
        "qa",
        "security"
    )) {
        Write-NoBom `
            (Join-Path $root (".codex\agents\" + $role + ".md")) `
            ("# " + $role + [Environment]::NewLine + "Fixture role.")
    }

    $phase = switch ($Status) {
        "REVIEW"   { "CODE_REVIEW" }
        "QA"       { "QA" }
        "SECURITY" { "SECURITY" }
        default    { "PLANNING" }
    }

    $task = @(
        "# AICO-002 - CTO deliverable gate fixture",
        "",
        "## Metadata",
        "",
        "ID: AICO-002",
        "Status: $Status",
        "Priority: P1",
        "Owner: cto",
        "Workflow phase: $phase",
        "Workflow profile: standard",
        "Work kind: PLANNING",
        "Work request: WR-001",
        "",
        "---",
        "",
        "## Objective",
        "",
        "Define the technical architecture for WR-001.",
        "",
        "---",
        "",
        "## Context",
        "",
        "- CTO gate semantic validation fixture.",
        "",
        "---",
        "",
        "## Requirements",
        "",
        "- Produce the CTO role-owned technical architecture deliverable.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] Architecture proposal is defined.",
        "- [ ] Technical implementation plan is defined.",
        "- [ ] Component boundaries are defined.",
        "- [ ] API/data contracts are defined.",
        "- [ ] Technical risks are documented.",
        "- [ ] Migration strategy is documented.",
        "",
        "---",
        "",
        "## Dependencies",
        "",
        "-",
        "",
        "---",
        "",
        "## Testing Requirements",
        "",
        "- Validate the role-owned deliverable.",
        "",
        "---",
        "",
        "## Evidence",
        "",
        "- Result submitted: docs/engineering/results/AICO-002-result-001.md",
        "",
        "---",
        "",
        "## Handoff",
        "",
        "Next agent: engineering-manager",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "- Fixture prepared.",
        "",
        "---",
        "",
        "## Notes",
        "",
        "-"
    ) -join [Environment]::NewLine

    Write-NoBom `
        (Join-Path $root "tasks\AICO-002.md") `
        $task

    $dispatch = @(
        "# Dispatch - AICO-002",
        "",
        "Task: AICO-002",
        "Owner: cto",
        "Work kind: PLANNING",
        "",
        "Produce the technical architecture deliverable required by the CTO role."
    ) -join [Environment]::NewLine

    Write-NoBom `
        (Join-Path $root "docs\engineering\dispatch\AICO-002.md") `
        $dispatch

    if ($ReportKind -eq "shallow") {
        $report = @(
            "# Agent Report - AICO-002",
            "",
            "Owner: cto",
            "Outcome: COMPLETED",
            "",
            "## Objective",
            "",
            "Define the technical architecture for WR-001.",
            "",
            "## Requirements",
            "",
            "- Produce the CTO role-owned technical architecture deliverable.",
            "",
            "## Acceptance Criteria",
            "",
            "- Architecture should be defined.",
            "- Risks should be considered.",
            "",
            "The task metadata and requirements were reviewed."
        ) -join [Environment]::NewLine
    }
    else {
        $report = @(
            "# Agent Report - AICO-002",
            "",
            "Owner: cto",
            "Outcome: COMPLETED",
            "",
            "## Architecture Proposal",
            "",
            "Use the existing runtime control plane and preserve canonical task state.",
            "",
            "## Technical Implementation Plan",
            "",
            "Introduce the change behind the current orchestration boundary, add regression coverage, then migrate incrementally.",
            "",
            "## Component Boundaries",
            "",
            "- Task lifecycle remains owned by orchestration scripts.",
            "- Provider execution remains owned by the runtime adapter layer.",
            "- Gate validation remains independent from task execution.",
            "",
            "## API/Data Contracts",
            "",
            "- Task metadata remains canonical Markdown.",
            "- Structured provider output must conform to the repository schemas.",
            "- Repository-relative artifact identity remains canonical.",
            "",
            "## Risks",
            "",
            "- Schema drift between installed projects and runtime.",
            "- Gate false positives if role contracts are not supplied.",
            "",
            "## Migration Strategy",
            "",
            "Add backwards-compatible structured fields, validate them, update installers, then migrate existing projects.",
            "",
            "## ADR",
            "",
            "No ADR required for this fixture."
        ) -join [Environment]::NewLine
    }

    Write-NoBom `
        (Join-Path $root "docs\engineering\agent-reports\AICO-002.md") `
        $report

    $result = @(
        "# Task Result - AICO-002",
        "",
        "Task: AICO-002",
        "Owner: cto",
        "Outcome: COMPLETED",
        "",
        "## Changed Artifacts",
        "",
        "docs/engineering/agent-reports/AICO-002.md",
        "",
        "## Verification",
        "",
        "Role-owned artifact submitted."
    ) -join [Environment]::NewLine

    Write-NoBom `
        (Join-Path $root "docs\engineering\results\AICO-002-result-001.md") `
        $result

    $contextBuilderLines = @(
        'param(',
        '    [string]$ProjectPath,',
        '    [string]$Id,',
        '    [string]$Owner,',
        '    [int]$MaxChars',
        ')',
        '',
        '@"',
        '===== GENERIC REPOSITORY CONTEXT =====',
        'Task: $Id',
        'Gate owner: $Owner',
        '',
        'Generic context intentionally does not inject the original owner role contract.',
        '"@'
    )

    Write-NoBom `
        (Join-Path $root "scripts\build-agent-context.ps1") `
        ($contextBuilderLines -join [Environment]::NewLine)

    Write-NoBom `
        (Join-Path $root ".codex\fixture-mode.txt") `
        $Mode

    $routerLines = @(
        'param(',
        '    [string]$Provider,',
        '    [string]$ProjectPath,',
        '    [string]$Prompt,',
        '    [string]$Context,',
        '    [string]$SchemaPath,',
        '    [string]$OutputPath,',
        '    [string]$Model,',
        '    [string]$Role,',
        '    [string]$Workload,',
        '    [string]$SemanticValidatorPath',
        ')',
        '',
        'if ([string]::IsNullOrWhiteSpace($SemanticValidatorPath)) {',
        '    throw "Gate fixture router did not receive SemanticValidatorPath."',
        '}',
        'if (-not (Test-Path $SemanticValidatorPath -PathType Leaf)) {',
        '    throw "Gate fixture semantic validator does not exist."',
        '}',
        '',
        '$mode = (Get-Content (Join-Path $ProjectPath ".codex\fixture-mode.txt") -Raw).Trim()',
        '',
        '[System.IO.File]::WriteAllText(',
        '    (Join-Path $ProjectPath ".codex\captured-gate-context.txt"),',
        '    $Context,',
        '    (New-Object System.Text.UTF8Encoding($false))',
        ')',
        '',
        '[System.IO.File]::WriteAllText(',
        '    (Join-Path $ProjectPath ".codex\captured-gate-prompt.txt"),',
        '    $Prompt,',
        '    (New-Object System.Text.UTF8Encoding($false))',
        ')',
        '',
        '$payload = $null',
        '',
        'if ($mode -eq "semantic-review") {',
        '    $hasRoleContract = (',
        '        $Context -match [regex]::Escape("===== ORIGINAL OWNER ROLE CONTRACT =====") -and',
        '        $Context -match [regex]::Escape("Repository-relative path: .codex/agents/cto.md") -and',
        '        $Context -match [regex]::Escape("## Output") -and',
        '        $Context -match [regex]::Escape("Architecture proposal.") -and',
        '        $Context -match [regex]::Escape("Technical implementation plan.") -and',
        '        $Context -match [regex]::Escape("Component boundaries.") -and',
        '        $Context -match [regex]::Escape("API/data contracts.") -and',
        '        $Context -match [regex]::Escape("Migration strategy.")',
        '    )',
        '',
        '    $hasFullReport = (',
        '        $Context -match [regex]::Escape("## Architecture Proposal") -and',
        '        $Context -match [regex]::Escape("## Technical Implementation Plan") -and',
        '        $Context -match [regex]::Escape("## Component Boundaries") -and',
        '        $Context -match [regex]::Escape("## API/Data Contracts") -and',
        '        $Context -match [regex]::Escape("## Risks") -and',
        '        $Context -match [regex]::Escape("## Migration Strategy")',
        '    )',
        '',
        '    if ($hasRoleContract -and $hasFullReport) {',
        '        $payload = @{',
        '            recommendation = "APPROVE"',
        '            findings = "The CTO role-owned deliverable contains the required outputs."',
        '            verification = "Role contract and report outputs were compared."',
        '            missing_required_outputs = @()',
        '            deliverable_defects = @()',
        '        }',
        '    }',
        '    elseif ($hasRoleContract) {',
        '        $payload = @{',
        '            recommendation = "CHANGES_REQUIRED"',
        '            findings = "The report restates task metadata but does not produce the required CTO outputs."',
        '            verification = "The report was compared with the CTO Output contract."',
        '            missing_required_outputs = @(',
        '                "Architecture proposal",',
        '                "Technical implementation plan",',
        '                "Component boundaries",',
        '                "API/data contracts",',
        '                "Risks",',
        '                "Migration strategy"',
        '            )',
        '            deliverable_defects = @("Role-owned deliverable is materially incomplete.")',
        '        }',
        '    }',
        '    else {',
        '        # Reproduce the historical false positive when the original-owner',
        '        # contract is not supplied to the gate.',
        '        $payload = @{',
        '            recommendation = "APPROVE"',
        '            findings = "Report appears complete from task metadata alone."',
        '            verification = "Task metadata inspected."',
        '            missing_required_outputs = @()',
        '            deliverable_defects = @()',
        '        }',
        '    }',
        '}',
        'elseif ($mode -eq "review-invalid-changes") {',
        '    $payload = @{',
        '        recommendation = "CHANGES_REQUIRED"',
        '        findings = "No concrete defect identified."',
        '        verification = "Fixture."',
        '        missing_required_outputs = @()',
        '        deliverable_defects = @()',
        '    }',
        '}',
        'elseif ($mode -eq "qa-invalid-fail") {',
        '    $payload = @{',
        '        outcome = "FAIL"',
        '        evidence = "Fixture evidence."',
        '        findings = "No unsatisfied criterion identified."',
        '        criteria_assessment = @(',
        '            @{',
        '                criterion = "Role-owned deliverable is produced"',
        '                status = "SATISFIED"',
        '                evidence = "Report exists."',
        '            }',
        '        )',
        '    }',
        '}',
        'elseif ($mode -eq "security-invalid-fail") {',
        '    $payload = @{',
        '        outcome = "FAIL"',
        '        evidence = "Fixture evidence."',
        '        findings = "No concrete security defect of the deliverable was identified."',
        '        security_relevant = $true',
        '        deliverable_security_defects = @()',
        '    }',
        '}',
        'elseif ($mode -eq "security-not-applicable") {',
        '    $payload = @{',
        '        outcome = "NOT_APPLICABLE"',
        '        evidence = "Planning-only analysis with no additional security-relevant change."',
        '        findings = "No additional security verification is applicable to this planning deliverable."',
        '        security_relevant = $false',
        '        deliverable_security_defects = @()',
        '    }',
        '}',
        'elseif ($mode -eq "security-product-risk") {',
        '    $payload = @{',
        '        outcome = "FAIL"',
        '        evidence = "The report documents future product security work."',
        '        findings = "The underlying product has security issues that should be addressed in a future implementation task."',
        '        security_relevant = $false',
        '        deliverable_security_defects = @()',
        '    }',
        '}',
        'else {',
        '    throw "Unknown fixture mode: $mode"',
        '}',
        '',
        '$json = $payload | ConvertTo-Json -Depth 20',
        '',
        '[System.IO.File]::WriteAllText(',
        '    $OutputPath,',
        '    $json,',
        '    (New-Object System.Text.UTF8Encoding($false))',
        ')',
        '',
        '[PSCustomObject]@{',
        '    Provider = "Fixture"',
        '    Model = "deterministic"',
        '}'
    )

    Write-NoBom `
        (Join-Path $root "scripts\provider-router.ps1") `
        ($routerLines -join [Environment]::NewLine)

    return $root
}

function Invoke-GateFixture {
    param(
        [string]$Root,
        [ValidateSet("Review","QA","Security")]
        [string]$Gate
    )

    & (Join-Path $Root "scripts\run-gate-agent.ps1") `
        -Id "AICO-002" `
        -Gate $Gate `
        -ProjectPath $Root `
        -Provider OpenRouter
}

Write-Host ""
Write-Host "=== STATIC STRUCTURED CONTRACTS ===" -ForegroundColor Cyan

$gateRunner = Get-Content (Join-Path $repoRoot "scripts\run-gate-agent.ps1") -Raw -Encoding UTF8
[void](Assert-True ($gateRunner -match [regex]::Escape("validate-gate-result-semantics.ps1")) "Gate runner requires the semantic gate validator")
[void](Assert-True ($gateRunner -match "SemanticValidatorPath") "Gate runner routes semantic validation through provider routing")
[void](Assert-True ($gateRunner -match '& \$gateSemanticValidatorPath -JsonPath') "Gate runner revalidates semantic output before lifecycle mutation")

$reviewSchema = Get-Content `
    (Join-Path $repoRoot "schemas\review-result.schema.json") `
    -Raw |
    ConvertFrom-Json

$qaSchema = Get-Content `
    (Join-Path $repoRoot "schemas\qa-gate-result.schema.json") `
    -Raw |
    ConvertFrom-Json

$securitySchema = Get-Content `
    (Join-Path $repoRoot "schemas\security-gate-result.schema.json") `
    -Raw |
    ConvertFrom-Json

$agentSchema = Get-Content `
    (Join-Path $repoRoot "schemas\agent-result.schema.json") `
    -Raw |
    ConvertFrom-Json

[void](Assert-True `
    ($reviewSchema.required -contains "missing_required_outputs") `
    "Review schema requires missing_required_outputs")

[void](Assert-True `
    ($reviewSchema.required -contains "deliverable_defects") `
    "Review schema requires deliverable_defects")

[void](Assert-True `
    ($qaSchema.required -contains "criteria_assessment") `
    "QA schema requires criteria_assessment")

[void](Assert-True `
    ($securitySchema.required -contains "security_relevant") `
    "Security schema requires security_relevant")

[void](Assert-True `
    ($securitySchema.required -contains "deliverable_security_defects") `
    "Security schema requires deliverable_security_defects")

[void](Assert-True `
    ($agentSchema.required -contains "completion_check") `
    "Agent result schema requires completion_check")

Write-Host ""
Write-Host "=== AGENT COMPLETION SELF-CHECK CONTRACT ===" -ForegroundColor Cyan

$agentRunner = Get-Content `
    (Join-Path $repoRoot "scripts\run-agent-task.ps1") `
    -Raw `
    -Encoding UTF8

[void](Assert-True `
    ($agentRunner -match "completion_check") `
    "Agent runner consumes a structured completion self-check")

[void](Assert-True `
    ($agentRunner -match "substantive_role_deliverable_produced") `
    "Agent runner requires substantive role-owned delivery before COMPLETED")

[void](Assert-True `
    ($agentRunner -match "missing_required_outputs") `
    "Agent runner tracks missing role-required outputs")

[void](Assert-True `
    ($agentRunner -match "(?i)do not merely (restate|reformulate)") `
    "Agent prompt explicitly rejects task restatement as a deliverable")

$tempRoots = New-Object System.Collections.Generic.List[string]

try {
    Write-Host ""
    Write-Host "=== REVIEW: SHALLOW CTO REPORT ===" -ForegroundColor Cyan

    $shallowRoot = New-GateFixture `
        -Status REVIEW `
        -Mode "semantic-review" `
        -ReportKind shallow

    $tempRoots.Add($shallowRoot)

    try {
        Invoke-GateFixture -Root $shallowRoot -Gate Review

        $status = Read-Field `
            (Join-Path $shallowRoot "tasks\AICO-002.md") `
            "Status"

        [void](Assert-True `
            ($status -eq "READY") `
            "Shallow CTO metadata-only report cannot advance Review to QA")
    }
    catch {
        Add-Failure (
            "Shallow CTO Review fixture threw unexpectedly: " +
            $_.Exception.Message
        )
    }

    Write-Host ""
    Write-Host "=== REVIEW: COMPLETE CTO REPORT ===" -ForegroundColor Cyan

    $completeRoot = New-GateFixture `
        -Status REVIEW `
        -Mode "semantic-review" `
        -ReportKind complete

    $tempRoots.Add($completeRoot)

    try {
        Invoke-GateFixture -Root $completeRoot -Gate Review

        $status = Read-Field `
            (Join-Path $completeRoot "tasks\AICO-002.md") `
            "Status"

        [void](Assert-True `
            ($status -eq "QA") `
            "Complete CTO report may advance Review to QA")

        $capturedContext = Get-Content `
            (Join-Path $completeRoot ".codex\captured-gate-context.txt") `
            -Raw `
            -Encoding UTF8

        [void](Assert-True `
            ($capturedContext -match [regex]::Escape("===== ORIGINAL OWNER ROLE CONTRACT =====")) `
            "Gate context includes ORIGINAL OWNER ROLE CONTRACT")

        [void](Assert-True `
            ($capturedContext -match [regex]::Escape("Repository-relative path: .codex/agents/cto.md")) `
            "Original owner role contract uses canonical repository-relative path")

        [void](Assert-True `
            ($capturedContext -match [regex]::Escape("===== CANONICAL TASK =====")) `
            "Gate context explicitly includes canonical task")

        [void](Assert-True `
            ($capturedContext -match [regex]::Escape("===== DISPATCH PACKET =====")) `
            "Gate context explicitly includes dispatch packet")

        $capturedPrompt = Get-Content `
            (Join-Path $completeRoot ".codex\captured-gate-prompt.txt") `
            -Raw `
            -Encoding UTF8

        [void](Assert-True `
            ($capturedPrompt -match "(?i)repeating.*Objective.*Requirements") `
            "Gate prompt says task restatement is not role deliverable completion")

        [void](Assert-True `
            ($capturedPrompt -match "(?i)original owner.*role contract") `
            "Gate prompt requires comparison against original owner role contract")
    }
    catch {
        Add-Failure (
            "Complete CTO Review fixture threw unexpectedly: " +
            $_.Exception.Message
        )
    }

    Write-Host ""
    Write-Host "=== REVIEW: INVALID CHANGES_REQUIRED ===" -ForegroundColor Cyan

    $invalidReviewRoot = New-GateFixture `
        -Status REVIEW `
        -Mode "review-invalid-changes" `
        -ReportKind complete

    $tempRoots.Add($invalidReviewRoot)

    $reviewRejected = $false

    try {
        Invoke-GateFixture `
            -Root $invalidReviewRoot `
            -Gate Review
    }
    catch {
        $reviewRejected = $true
    }

    [void](Assert-True `
        $reviewRejected `
        "CHANGES_REQUIRED without concrete missing output or deliverable defect is rejected")

    Write-Host ""
    Write-Host "=== QA: INVALID FAIL ===" -ForegroundColor Cyan

    $invalidQaRoot = New-GateFixture `
        -Status QA `
        -Mode "qa-invalid-fail" `
        -ReportKind complete

    $tempRoots.Add($invalidQaRoot)

    $qaRejected = $false

    try {
        Invoke-GateFixture `
            -Root $invalidQaRoot `
            -Gate QA
    }
    catch {
        $qaRejected = $true
    }

    [void](Assert-True `
        $qaRejected `
        "QA FAIL without an UNSATISFIED criterion is rejected")

    Write-Host ""
    Write-Host "=== SECURITY: INVALID FAIL ===" -ForegroundColor Cyan

    $invalidSecurityRoot = New-GateFixture `
        -Status SECURITY `
        -Mode "security-invalid-fail" `
        -ReportKind complete

    $tempRoots.Add($invalidSecurityRoot)

    $securityRejected = $false

    try {
        Invoke-GateFixture `
            -Root $invalidSecurityRoot `
            -Gate Security
    }
    catch {
        $securityRejected = $true
    }

    [void](Assert-True `
        $securityRejected `
        "Security FAIL without deliverable_security_defects is rejected")

    Write-Host ""
    Write-Host "=== SECURITY: STANDARD PLANNING NOT_APPLICABLE ===" -ForegroundColor Cyan

    $naRoot = New-GateFixture `
        -Status SECURITY `
        -Mode "security-not-applicable" `
        -ReportKind complete

    $tempRoots.Add($naRoot)

    try {
        Invoke-GateFixture `
            -Root $naRoot `
            -Gate Security

        $securityArtifact = Join-Path `
            $naRoot `
            "docs\engineering\security\AICO-002-security.md"

        $outcome = Read-Field `
            $securityArtifact `
            "Outcome"

        [void](Assert-True `
            ($outcome -eq "NOT_APPLICABLE") `
            "Standard planning/analysis Security may return NOT_APPLICABLE when security_relevant=false")
    }
    catch {
        Add-Failure (
            "Valid planning Security NOT_APPLICABLE was rejected: " +
            $_.Exception.Message
        )
    }

    Write-Host ""
    Write-Host "=== SECURITY: PRODUCT FUTURE FINDINGS ARE NOT DELIVERABLE FAIL ===" -ForegroundColor Cyan

    $productRiskRoot = New-GateFixture `
        -Status SECURITY `
        -Mode "security-product-risk" `
        -ReportKind complete

    $tempRoots.Add($productRiskRoot)

    $productRiskRejected = $false

    try {
        Invoke-GateFixture `
            -Root $productRiskRoot `
            -Gate Security
    }
    catch {
        $productRiskRejected = $true
    }

    [void](Assert-True `
        $productRiskRejected `
        "Future product security findings cannot justify Security FAIL without a deliverable security defect")
}
finally {
    foreach ($tempRoot in $tempRoots) {
        if (Test-Path $tempRoot) {
            Remove-Item `
                $tempRoot `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "ROLE DELIVERABLE GATE REGRESSION SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host ("RED: " + $failures.Count + " failing checks") -ForegroundColor Yellow

    foreach ($failure in $failures) {
        Write-Host (" - " + $failure) -ForegroundColor Yellow
    }

    throw (
        "P0 role deliverable gate validation regressions are RED: " +
        $failures.Count
    )
}

Write-Host ""
Write-Host "PASS: role deliverable gate semantic regressions" -ForegroundColor Green
