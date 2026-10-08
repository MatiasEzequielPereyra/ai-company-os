param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts/task-execution-lock.ps1')
. (Join-Path $repoRoot 'scripts/review-grounding.ps1')
. (Join-Path $repoRoot 'test-project/helpers/grounded-review-fixture.ps1')
$groundedFixture=$null
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "aico-gate-evidence-preservation-" +
    [Guid]::NewGuid().ToString("N")
)

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)

    [System.IO.File]::WriteAllText(
        $Path,
        $Value,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

try {
    foreach ($relative in @(
        "scripts",
        "scripts\providers",
        "scripts\local-runtime",
        "schemas",
        ".codex",
        ".codex\runtime"
    )) {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path (Join-Path $tempRoot $relative) |
            Out-Null
    }

    foreach ($name in @(
        "provider-router.ps1",
        "validate-json-contract.ps1",
        "validate-gate-result-semantics.ps1",
        "write-operational-event.ps1"
    )) {
        Copy-Item `
            (Join-Path $repoRoot ("scripts\" + $name)) `
            (Join-Path $tempRoot ("scripts\" + $name)) `
            -Force
    }

    Copy-Item `
        (Join-Path $repoRoot "schemas\review-result.schema.json") `
        (Join-Path $tempRoot "schemas\review-result.schema.json") `
        -Force

    $config = @{
        auto_order = @("Ollama")
        gate_auto_order = @("Ollama")
        allow_paid_fallback = $false
        models = @{
            Ollama = "qwen3:8b"
        }
        gate_context_max_chars = 180000
        ollama_gate_context_max_chars = 7000
        provider_timeout_seconds = @{
            Ollama = 30
        }
    } | ConvertTo-Json -Depth 20

    Write-Utf8NoBom `
        (Join-Path $tempRoot ".codex\provider-config.json") `
        $config

    Write-Utf8NoBom `
        (Join-Path $tempRoot ".codex\local-runtime-config.json") `
        "{}"

    $resolver = @(
        'param('
        '    [string]$ProjectPath,'
        '    [string]$Role,'
        '    [string]$Workload,'
        '    [string]$ModelOverride'
        ')'
        ''
        '[PSCustomObject]@{'
        '    Available = $true'
        '    Profile = "LOCAL_GPU_12GB"'
        '    CapabilityScore = 78'
        '    Model = "qwen3:8b"'
        '    NumCtx = 16384'
        '    NumPredict = 2048'
        '    ContextMaxChars = 50000'
        '    GateContextMaxChars = 16000'
        '    GateArtifactMaxChars = 7000'
        '    Reason = "Deterministic evidence-preservation fixture."'
        '}'
    ) -join [Environment]::NewLine

    Write-Utf8NoBom `
        (Join-Path $tempRoot "scripts\local-runtime\resolve-local-runtime.ps1") `
        $resolver

    $ollamaAdapter = @(
        'param('
        '    [string]$Prompt,'
        '    [string]$Context,'
        '    [string]$SchemaPath,'
        '    [string]$OutputPath,'
        '    [string]$Model,'
        '    [int]$NumCtx,'
        '    [int]$NumPredict,'
        '    [int]$TimeoutSeconds'
        ')'
        ''
        '$fixtureRoot = Split-Path -Parent $OutputPath'
        ''
        '[System.IO.File]::WriteAllText('
        '    (Join-Path $fixtureRoot "captured-gate-context.txt"),'
        '    $Context,'
        '    (New-Object System.Text.UTF8Encoding($false))'
        ')'
        ''
        '$payload = [IO.File]::ReadAllText((Join-Path $fixtureRoot "fixture-grounded-review.json"))'
        ''
        '[System.IO.File]::WriteAllText('
        '    $OutputPath,'
        '    $payload,'
        '    (New-Object System.Text.UTF8Encoding($false))'
        ')'
        ''
        '[PSCustomObject]@{'
        '    Provider = "Ollama"'
        '    Model = $Model'
        '}'
    ) -join [Environment]::NewLine

    Write-Utf8NoBom `
        (Join-Path $tempRoot "scripts\providers\invoke-ollama.ps1") `
        $ollamaAdapter

    # Mirror the real gate shape: large generic/base context first,
    # authoritative explicit gate evidence afterwards.
    $baseContext = @(
        "===== GENERIC PROJECT CONTEXT ====="
        ("B" * 43000)
    ) -join [Environment]::NewLine

    $canonicalTask = @(
        "===== CANONICAL TASK ====="
        "Repository-relative path: tasks/AICO-001.md"
        "SENTINEL_CANONICAL_TASK_7D31"
    ) -join [Environment]::NewLine

    $ownerRole = @(
        "===== ORIGINAL OWNER ROLE CONTRACT ====="
        "Repository-relative path: .codex/agents/backend.md"
        "SENTINEL_OWNER_ROLE_CONTRACT_5A82"
    ) -join [Environment]::NewLine

    $primaryReport = @(
        "===== PRIMARY AGENT REPORT ====="
        "Repository-relative path: docs/engineering/agent-reports/AICO-001.md"
        "SENTINEL_PRIMARY_AGENT_REPORT_C914"
    ) -join [Environment]::NewLine

    $latestResult = @(
        "===== LATEST TASK RESULT ====="
        "Repository-relative path: docs/engineering/results/AICO-001-result-001.md"
        "SENTINEL_LATEST_TASK_RESULT_E603"
    ) -join [Environment]::NewLine

    $context = @(
        $baseContext
        $canonicalTask
        $ownerRole
        $primaryReport
        $latestResult
    ) -join ([Environment]::NewLine + [Environment]::NewLine)

    if ($context.Length -lt 43000) {
        throw "Fixture context is unexpectedly small."
    }

    $outputPath = Join-Path $tempRoot "review-result.json"

    $groundedFixture=New-GroundedRouterFixture -Root $tempRoot
    $routerArgs = @{
        SemanticValidationContext=$groundedFixture.Context
        SemanticValidatorPath=Join-Path $tempRoot "scripts/validate-gate-result-semantics.ps1"
        Provider = "Auto"
        ProjectPath = $tempRoot
        Prompt = "Gate evidence preservation fixture"
        Context = $context
        SchemaPath = Join-Path $tempRoot "schemas\review-result.schema.json"
        OutputPath = $outputPath
        Role = "engineering-manager"
        Workload = "gate"
    }

    $result = & (
        Join-Path $tempRoot "scripts\provider-router.ps1"
    ) @routerArgs

    if ([string]$result.Provider -ne "Ollama") {
        throw "Expected deterministic Ollama gate candidate."
    }

    $capturePath = Join-Path $tempRoot "captured-gate-context.txt"

    if (-not (Test-Path $capturePath)) {
        throw "Gate context capture was not created."
    }

    $captured = Get-Content $capturePath -Raw -Encoding UTF8

    if ($captured.Length -gt 7000) {
        throw (
            "Ollama gate context exceeded configured cap. Actual: " +
            $captured.Length
        )
    }

    if ($captured.Length -lt 6000) {
        throw (
            "Gate evidence compaction underutilized provider context budget. " +
            "Expected at least 6000 of 7000 chars; Actual=" +
            $captured.Length
        )
    }

    $requiredSentinels = @(
        "SENTINEL_CANONICAL_TASK_7D31",
        "SENTINEL_OWNER_ROLE_CONTRACT_5A82",
        "SENTINEL_PRIMARY_AGENT_REPORT_C914",
        "SENTINEL_LATEST_TASK_RESULT_E603"
    )

    $missing = @(
        foreach ($sentinel in $requiredSentinels) {
            if ($captured -notmatch [regex]::Escape($sentinel)) {
                $sentinel
            }
        }
    )

    if ($missing.Count -gt 0) {
        throw (
            "Gate context dropped required evidence sentinels: " +
            ($missing -join ", ")
        )
    }

    Write-Host (
        "PASS: bounded Ollama gate context preserves authoritative evidence"
    ) -ForegroundColor Green
}
finally {
    if($null-ne $groundedFixture){Exit-TaskExecutionLock -Lock $groundedFixture.Lease}
    if (Test-Path $tempRoot) {
        Remove-Item `
            $tempRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
