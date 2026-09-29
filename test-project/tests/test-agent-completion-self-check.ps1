param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-agent-completion-" + [Guid]::NewGuid().ToString("N"))

function Write-NoBom {
    param([string]$Path,[string]$Value)

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
    param([string]$Path,[string]$Key)

    if (-not (Test-Path $Path -PathType Leaf)) {
        return ""
    }

    $content = Get-Content $Path -Raw -Encoding UTF8
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"

    if ($content -match $pattern) {
        return $Matches[1].Trim()
    }

    return ""
}

try {
    foreach ($dir in @(
        "scripts",
        "schemas",
        "tasks",
        ".codex\agents",
        "docs\engineering\dispatch"
    )) {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path (Join-Path $tempRoot $dir) |
            Out-Null
    }

    Copy-Item `
        (Join-Path $repoRoot "scripts\run-agent-task.ps1") `
        (Join-Path $tempRoot "scripts\run-agent-task.ps1") `
        -Force

    Copy-Item `
        (Join-Path $repoRoot "schemas\agent-result.schema.json") `
        (Join-Path $tempRoot "schemas\agent-result.schema.json") `
        -Force

    $role = @(
        "# Chief Technology Officer",
        "",
        "## Output",
        "",
        "Produce:",
        "",
        "- Architecture proposal.",
        "- Technical implementation plan.",
        "- Component boundaries.",
        "- API/data contracts.",
        "- Risks.",
        "- Migration strategy."
    ) -join [Environment]::NewLine

    Write-NoBom `
        (Join-Path $tempRoot ".codex\agents\cto.md") `
        $role

    $task = @(
        "# AICO-002 - Agent completion fixture",
        "",
        "## Metadata",
        "",
        "ID: AICO-002",
        "Status: ACTIVE",
        "Priority: P1",
        "Owner: cto",
        "Workflow phase: IMPLEMENTATION",
        "Workflow profile: standard",
        "Work kind: PLANNING",
        "Work request: WR-001",
        "",
        "---",
        "",
        "## Objective",
        "",
        "Define technical architecture for WR-001.",
        "",
        "---",
        "",
        "## Requirements",
        "",
        "- Produce the CTO architecture deliverable.",
        "",
        "---",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] Architecture proposal is defined.",
        "- [ ] Technical implementation plan is defined.",
        "- [ ] Component boundaries are defined.",
        "- [ ] API/data contracts are defined.",
        "- [ ] Risks are documented.",
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
        "## Evidence",
        "",
        "-",
        "",
        "---",
        "",
        "## Transition Log",
        "",
        "- Fixture active.",
        "",
        "---",
        "",
        "## Notes",
        "",
        "-"
    ) -join [Environment]::NewLine

    $taskPath = Join-Path $tempRoot "tasks\AICO-002.md"
    Write-NoBom $taskPath $task

    $dispatch = @(
        "# Dispatch - AICO-002",
        "",
        "Task: AICO-002",
        "Owner: cto",
        "Work kind: PLANNING",
        "",
        "Produce the CTO architecture deliverable."
    ) -join [Environment]::NewLine

    Write-NoBom `
        (Join-Path $tempRoot "docs\engineering\dispatch\AICO-002.md") `
        $dispatch

    $contextBuilder = @(
        "param(",
        "    [string]`$ProjectPath,",
        "    [string]`$Id,",
        "    [string]`$Owner,",
        "    [int]`$MaxChars",
        ")",
        "",
        '"===== FIXTURE CONTEXT ====="',
        '"Task: " + $Id',
        '"Owner: " + $Owner'
    ) -join [Environment]::NewLine

    Write-NoBom `
        (Join-Path $tempRoot "scripts\build-agent-context.ps1") `
        $contextBuilder

    $fakeRouter = @(
        "param(",
        "    [string]`$Provider,",
        "    [string]`$ProjectPath,",
        "    [string]`$Prompt,",
        "    [string]`$Context,",
        "    [string]`$SchemaPath,",
        "    [string]`$OutputPath,",
        "    [string]`$Model,",
        "    [string]`$Role,",
        "    [string]`$Workload",
        ")",
        "",
        "`$payload = @{",
        '    outcome = "COMPLETED"',
        '    summary = "Reviewed the task requirements."',
        "    report_markdown = (`@(",
        '        "## Objective",',
        '        "",',
        '        "Define technical architecture.",',
        '        "",',
        '        "## Requirements",',
        '        "",',
        '        "Produce the CTO architecture deliverable.",',
        '        "",',
        '        "No substantive architecture proposal was produced."',
        "    ) -join [Environment]::NewLine)",
        '    verification = "Task metadata reviewed."',
        '    decisions = "NONE"',
        '    blockers = "NONE"',
        '    recommended_next = "Proceed."',
        "    completion_check = @{",
        "        substantive_role_deliverable_produced = `$false",
        "        missing_required_outputs = `@(",
        '            "Architecture proposal",',
        '            "Technical implementation plan",',
        '            "Component boundaries",',
        '            "API/data contracts",',
        '            "Risks",',
        '            "Migration strategy"',
        "        )",
        '        evidence = "The report only restates the task and does not contain the CTO-owned outputs."',
        "    }",
        "} | ConvertTo-Json -Depth 20",
        "",
        "[System.IO.File]::WriteAllText(",
        "    `$OutputPath,",
        "    `$payload,",
        "    (New-Object System.Text.UTF8Encoding(`$false))",
        ")",
        "",
        "[PSCustomObject]@{",
        '    Provider = "Fixture"',
        '    Model = "deterministic"',
        "}"
    ) -join [Environment]::NewLine

    Write-NoBom `
        (Join-Path $tempRoot "scripts\provider-router.ps1") `
        $fakeRouter

    Write-NoBom `
        (Join-Path $tempRoot "scripts\submit-task-result.ps1") `
        'throw "submit-task-result.ps1 must not run for an invalid COMPLETED result."'

    $rejected = $false
    $message = ""

    try {
        & (Join-Path $tempRoot "scripts\run-agent-task.ps1") `
            -Id "AICO-002" `
            -ProjectPath $tempRoot `
            -Provider OpenRouter
    }
    catch {
        $rejected = $true
        $message = $_.Exception.Message
    }

    if (-not $rejected) {
        throw "Invalid COMPLETED result was accepted."
    }

    if (
        $message -notmatch "(?i)substantive role-owned deliverable" -and
        $message -notmatch "(?i)required role outputs are missing"
    ) {
        throw (
            "Agent result was rejected for an unexpected reason: " +
            $message
        )
    }

    $status = Read-Field `
        -Path $taskPath `
        -Key "Status"

    if ($status -ne "ACTIVE") {
        throw "Rejected completion mutated task status. Actual: $status"
    }

    $reportPath = Join-Path `
        $tempRoot `
        "docs\engineering\agent-reports\AICO-002.md"

    if (Test-Path $reportPath) {
        throw "Invalid COMPLETED result created an agent report."
    }

    $resultsDir = Join-Path `
        $tempRoot `
        "docs\engineering\results"

    if (Test-Path $resultsDir) {
        $results = @(
            Get-ChildItem `
                $resultsDir `
                -File `
                -ErrorAction SilentlyContinue
        )

        if ($results.Count -gt 0) {
            throw "Invalid COMPLETED result created a task result artifact."
        }
    }

    Write-Host `
        "PASS: invalid COMPLETED role deliverable rejected before Result Intake" `
        -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item `
            $tempRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}