param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("aico-p1-planning-e2e-" + [Guid]::NewGuid().ToString("N"))
$savedOpenRouterKey = $env:OPENROUTER_API_KEY
$savedGeminiKey = $env:GEMINI_API_KEY

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $Value,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Write-Utf8NoBom (Join-Path $tempRoot "src\app.py") @'
def current_behavior():
    return "baseline"
'@

    & (Join-Path $repoRoot "scripts\install-existing-project.ps1") -TargetProject $tempRoot | Out-Null

    Remove-Item (Join-Path $tempRoot ".codex\local-runtime-config.json") -Force -ErrorAction SilentlyContinue

    $config = @{
        auto_order = @("OpenRouter","Gemini")
        writable_auto_order = @("Ollama")
        allow_paid_fallback = $false
        models = @{
            OpenRouter = "fixture/openrouter"
            Gemini = "fixture/gemini"
        }
        analysis_context_max_chars = 120000
        analysis_context_max_chars_by_role = @{
            "engineering-manager" = 120000
        }
        analysis_auto_order_by_role = @{
            "engineering-manager" = @("OpenRouter","Gemini")
        }
        analysis_models_by_role = @{
            "engineering-manager" = @{
                OpenRouter = "fixture/openrouter"
                Gemini = "fixture/gemini"
            }
        }
        provider_timeout_seconds = @{
            OpenRouter = 30
            Gemini = 30
        }
    } | ConvertTo-Json -Depth 20

    Write-Utf8NoBom (Join-Path $tempRoot ".codex\provider-config.json") $config

    $taskId = "AICO-P1-PLAN-03"
    Write-Utf8NoBom (Join-Path $tempRoot ("tasks\" + $taskId + ".md")) @"
# $taskId - Prepare engineering execution plan

## Metadata

ID: $taskId

Status: ACTIVE

Priority: P1

Owner: engineering-manager

Created: 2026-09-30T00:00:00Z

Updated: 2026-09-30T00:00:00Z

Workflow phase: PLANNING

Work request: WR-P1-03

---

## Objective

Prepare engineering execution plan for WR-P1-03 against the real fixture source tree.

---

## Context

- Fresh deterministic provider/planning integration fixture.
- Do not modify production code during planning.

---

## Requirements

- Produce executable engineering work against src/app.py.
- Include at least one real IMPLEMENTATION item.
- Use only repository evidence.

---

## Acceptance Criteria

- [ ] Engineering plan passes JSON Schema validation.
- [ ] Engineering plan passes semantic validation.
- [ ] Canonical execution-plan JSON is written.
- [ ] Task advances from ACTIVE to REVIEW.

---

## Dependencies

-

---

## Testing Requirements

- Verify the generated execution plan and task transition.

---

## Evidence

- src/app.py

---

## Handoff

Next agent: engineering-manager

---

## Transition Log

- 2026-09-30T00:00:00Z - SYSTEM - CREATED - Focused provider/planning E2E fixture.
"@

    Write-Utf8NoBom (Join-Path $tempRoot ("docs\engineering\dispatch\" + $taskId + ".md")) @"
# Dispatch Packet - $taskId

Task: $taskId
Owner: engineering-manager
Work request: WR-P1-03
Objective: Produce a concrete execution plan grounded in src/app.py.
"@

    $openRouterAdapter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [int]$TimeoutSeconds
)

[System.IO.File]::WriteAllText(
    (Join-Path (Split-Path -Parent $OutputPath) "p1-e2e-openrouter-attempted.txt"),
    [string]$Context.Length,
    (New-Object System.Text.UTF8Encoding($false))
)

throw "OpenRouter structured completion was truncated before completion. finish_reason: length; max_tokens: 12000."
'@
    Write-Utf8NoBom (Join-Path $tempRoot "scripts\providers\invoke-openrouter.ps1") $openRouterAdapter

    $geminiAdapter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [int]$TimeoutSeconds
)

[System.IO.File]::WriteAllText(
    (Join-Path (Split-Path -Parent $OutputPath) "p1-e2e-gemini-attempted.txt"),
    [string]$Context.Length,
    (New-Object System.Text.UTF8Encoding($false))
)

$reportText = "## Execution strategy" + [Environment]::NewLine + [Environment]::NewLine + "The fixture exposes a single product source area at src/app.py. Implement the requested behavior there and verify it with focused automated coverage before broader validation."

$payload = @{
    outcome = "COMPLETED"
    summary = "Concrete engineering execution plan produced from the fresh fixture."
    report_markdown = $reportText
    executable_work = @(
        @{
            key = "impl-app-behavior"
            kind = "IMPLEMENTATION"
            change = "Implement the planned product behavior in src/app.py while preserving the existing callable contract."
            owner = "backend"
            areas = @("src/app.py")
            depends_on = @()
            verify = "Run focused Python tests that exercise current_behavior and the new behavior."
        },
        @{
            key = "validate-app-behavior"
            kind = "VALIDATION"
            change = "Add and run focused regression coverage for the implemented src/app.py behavior."
            owner = "qa"
            areas = @("tests","src/app.py")
            depends_on = @("impl-app-behavior")
            verify = "Run the focused regression test and the supported Python suite."
        }
    )
    verification = "Schema and semantic validation must pass before persistence."
    decisions = "Keep implementation scoped to the real fixture source area."
    blockers = "NONE"
    recommended_next = "Review the canonical execution plan before implementation authorization."
    completion_check = @{
        substantive_role_deliverable_produced = $true
        missing_required_outputs = @()
        evidence = "The result contains concrete implementation and validation work grounded in src/app.py."
    }
} | ConvertTo-Json -Depth 30 -Compress

[System.IO.File]::WriteAllText(
    $OutputPath,
    $payload,
    (New-Object System.Text.UTF8Encoding($false))
)

[PSCustomObject]@{
    Provider = "Gemini"
    Model = $Model
}
'@
    Write-Utf8NoBom (Join-Path $tempRoot "scripts\providers\invoke-gemini.ps1") $geminiAdapter

    $env:OPENROUTER_API_KEY = "p1-e2e-openrouter-fixture"
    $env:GEMINI_API_KEY = "p1-e2e-gemini-fixture"

    $runArgs = @{
        Id = $taskId
        ProjectPath = $tempRoot
        Provider = "Auto"
    }
    & (Join-Path $tempRoot "scripts\run-agent-task.ps1") @runArgs | Out-Null

    $runtimeDir = Join-Path $tempRoot ".codex\runtime"
    if (-not (Test-Path (Join-Path $runtimeDir "p1-e2e-openrouter-attempted.txt"))) {
        throw "Focused E2E did not attempt OpenRouter first."
    }
    if (-not (Test-Path (Join-Path $runtimeDir "p1-e2e-gemini-attempted.txt"))) {
        throw "Focused E2E did not fall back to Gemini."
    }

    $planPath = Join-Path $tempRoot ("docs\engineering\plans\" + $taskId + "-execution-plan.json")
    if (-not (Test-Path $planPath -PathType Leaf)) {
        throw "Focused E2E did not materialize the canonical Engineering Manager execution plan."
    }

    $plan = Get-Content $planPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if ([string]$plan.provider -ne "Gemini") {
        throw "Focused E2E canonical plan recorded the wrong provider: $($plan.provider)"
    }
    if (@($plan.executable_work).Count -lt 1) {
        throw "Focused E2E canonical plan contains no executable work."
    }
    if (@($plan.executable_work | Where-Object { $_.kind -eq "IMPLEMENTATION" }).Count -lt 1) {
        throw "Focused E2E canonical plan contains no real IMPLEMENTATION item."
    }

    $taskPath = Join-Path $tempRoot ("tasks\" + $taskId + ".md")
    $task = Get-Content $taskPath -Raw -Encoding UTF8
    if ((Read-Field -Content $task -Key "Status") -ne "REVIEW") {
        throw "Focused E2E task did not advance from ACTIVE to REVIEW."
    }

    $reportPath = Join-Path $tempRoot ("docs\engineering\agent-reports\" + $taskId + ".md")
    if (-not (Test-Path $reportPath -PathType Leaf)) {
        throw "Focused E2E did not persist the Engineering Manager report."
    }

    $report = Get-Content $reportPath -Raw -Encoding UTF8
    if ($report -notmatch 'Canonical plan:\s+docs/engineering/plans/') {
        throw "Focused E2E report does not reference the canonical execution plan."
    }

    $resultFiles = @(Get-ChildItem (Join-Path $tempRoot "docs\engineering\results") -Filter ($taskId + "-result-*.md") -File)
    if ($resultFiles.Count -ne 1) {
        throw "Focused E2E expected exactly one authoritative task result. Actual: $($resultFiles.Count)"
    }

    Write-Host "PASS: fresh Engineering Manager provider/planning focused E2E" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedOpenRouterKey
    $env:GEMINI_API_KEY = $savedGeminiKey

    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
