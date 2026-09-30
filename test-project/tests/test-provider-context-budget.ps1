param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-provider-context-p1-" + [Guid]::NewGuid().ToString("N"))
$savedOpenRouterKey = $env:OPENROUTER_API_KEY
$savedDeepSeekKey = $env:DEEPSEEK_API_KEY
$savedXaiKey = $env:XAI_API_KEY

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

try {
    foreach ($relative in @("scripts","scripts\providers","scripts\local-runtime","schemas",".codex",".codex\runtime")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $relative) | Out-Null
    }

    foreach ($name in @("provider-router.ps1","validate-json-contract.ps1","write-operational-event.ps1")) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $tempRoot ("scripts\" + $name)) -Force
    }
    Copy-Item (Join-Path $repoRoot "schemas\agent-result.schema.json") (Join-Path $tempRoot "schemas\agent-result.schema.json") -Force

    $config = @{
        auto_order = @("Ollama")
        allow_paid_fallback = $false
        models = @{
            Ollama = "qwen3:8b"
            OpenRouter = "fixture/openrouter"
            DeepSeek = "fixture/deepseek"
            Grok = "fixture/grok"
        }
        analysis_context_max_chars = 120000
        analysis_context_max_chars_by_role = @{
            "engineering-manager" = 120000
        }
        analysis_auto_order_by_role = @{
            "engineering-manager" = @("OpenRouter","Ollama","DeepSeek","Grok")
        }
        ollama_context_max_chars = 20000
        provider_timeout_seconds = @{
            OpenRouter = 30
            Ollama = 30
            DeepSeek = 30
            Grok = 30
        }
    } | ConvertTo-Json -Depth 20

    Write-Utf8NoBom (Join-Path $tempRoot ".codex\provider-config.json") $config
    Write-Utf8NoBom (Join-Path $tempRoot ".codex\local-runtime-config.json") "{}"

    $resolver = @'
param(
    [string]$ProjectPath,
    [string]$Role,
    [string]$Workload,
    [string]$ModelOverride
)

[PSCustomObject]@{
    Available = $true
    Profile = "LOCAL_GPU_12GB"
    CapabilityScore = 78
    Model = "qwen3:8b"
    NumCtx = 16384
    NumPredict = 2048
    ContextMaxChars = 50000
    GateContextMaxChars = 16000
    GateArtifactMaxChars = 7000
    Reason = "P1 deterministic fixture."
}
'@
    Write-Utf8NoBom (Join-Path $tempRoot "scripts\local-runtime\resolve-local-runtime.ps1") $resolver

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
    (Join-Path (Split-Path -Parent $OutputPath) "openrouter-context-length.txt"),
    [string]$Context.Length,
    (New-Object System.Text.UTF8Encoding($false))
)
throw "fixture OpenRouter failure before Ollama fallback"
'@
    Write-Utf8NoBom (Join-Path $tempRoot "scripts\providers\invoke-openrouter.ps1") $openRouterAdapter

    $ollamaAdapter = @'
param(
    [string]$Prompt,
    [string]$Context,
    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$Model,
    [int]$NumCtx,
    [int]$NumPredict,
    [int]$TimeoutSeconds
)

[System.IO.File]::WriteAllText(
    (Join-Path (Split-Path -Parent $OutputPath) "ollama-context-length.txt"),
    [string]$Context.Length,
    (New-Object System.Text.UTF8Encoding($false))
)

$payload = @{
    outcome = "COMPLETED"
    summary = "Ollama fallback accepted bounded context"
    report_markdown = "# Context budget fixture"
    verification = "Fixture"
    decisions = "NONE"
    blockers = "NONE"
    recommended_next = "REVIEW"
    completion_check = @{
        substantive_role_deliverable_produced = $true
        missing_required_outputs = @()
        evidence = "The fallback provider returned valid structured output."
    }
} | ConvertTo-Json -Depth 20 -Compress

[System.IO.File]::WriteAllText(
    $OutputPath,
    $payload,
    (New-Object System.Text.UTF8Encoding($false))
)

[PSCustomObject]@{
    Provider = "Ollama"
    Model = $Model
}
'@
    Write-Utf8NoBom (Join-Path $tempRoot "scripts\providers\invoke-ollama.ps1") $ollamaAdapter

    $deepSeekAdapter = @'
param([string]$Prompt,[string]$Context,[string]$SchemaPath,[string]$OutputPath,[string]$Model,[int]$TimeoutSeconds)
[System.IO.File]::WriteAllText(
    (Join-Path (Split-Path -Parent $OutputPath) "deepseek-invoked.txt"),
    "invoked",
    (New-Object System.Text.UTF8Encoding($false))
)
throw "DeepSeek must not be invoked when paid fallback is disabled."
'@
    Write-Utf8NoBom (Join-Path $tempRoot "scripts\providers\invoke-deepseek.ps1") $deepSeekAdapter

    $xaiAdapter = @'
param([string]$Prompt,[string]$Context,[string]$SchemaPath,[string]$OutputPath,[string]$Model,[int]$TimeoutSeconds)
[System.IO.File]::WriteAllText(
    (Join-Path (Split-Path -Parent $OutputPath) "grok-invoked.txt"),
    "invoked",
    (New-Object System.Text.UTF8Encoding($false))
)
throw "Grok must not be invoked when paid fallback is disabled."
'@
    Write-Utf8NoBom (Join-Path $tempRoot "scripts\providers\invoke-xai.ps1") $xaiAdapter

    $env:OPENROUTER_API_KEY = "p1-openrouter-fixture"
    $env:DEEPSEEK_API_KEY = "p1-deepseek-fixture"
    $env:XAI_API_KEY = "p1-xai-fixture"

    $routerArgs = @{
        Provider = "Auto"
        ProjectPath = $tempRoot
        Prompt = "P1 context budget fixture"
        Context = ("x" * 43595)
        SchemaPath = (Join-Path $tempRoot "schemas\agent-result.schema.json")
        OutputPath = (Join-Path $tempRoot "result.json")
        Role = "engineering-manager"
        Workload = "analysis"
    }

    $result = & (Join-Path $tempRoot "scripts\provider-router.ps1") @routerArgs

    if ([string]$result.Provider -ne "Ollama") {
        throw "Expected fallback to Ollama after the deterministic OpenRouter failure."
    }

    $openRouterLength = [int](Get-Content (Join-Path $tempRoot "openrouter-context-length.txt") -Raw -Encoding UTF8)
    $ollamaLength = [int](Get-Content (Join-Path $tempRoot "ollama-context-length.txt") -Raw -Encoding UTF8)

    if ($openRouterLength -ne 43595) {
        throw "Cloud provider must retain the role-bounded context. Actual: $openRouterLength"
    }

    if ($ollamaLength -ne 20000) {
        throw "Effective Ollama context must be min(role, provider, hardware)=20000. Actual: $ollamaLength"
    }

    foreach ($marker in @("deepseek-invoked.txt","grok-invoked.txt")) {
        if (Test-Path (Join-Path $tempRoot $marker)) {
            throw "Paid provider was invoked despite allow_paid_fallback=false: $marker"
        }
    }

    Write-Host "PASS: provider-specific context budget and fallback contract" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedOpenRouterKey
    $env:DEEPSEEK_API_KEY = $savedDeepSeekKey
    $env:XAI_API_KEY = $savedXaiKey
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
