param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$required = @(
    "scripts\run-agent-task.ps1",
    "scripts\run-active-agents.ps1",
    "scripts\provider-router.ps1",
    "scripts\build-agent-context.ps1",
    "scripts\providers\invoke-codex.ps1",
    "scripts\providers\invoke-openrouter.ps1",
    "scripts\providers\invoke-gemini.ps1",
    "scripts\providers\invoke-ollama.ps1",
    "scripts\providers\invoke-deepseek.ps1",
    "scripts\providers\invoke-xai.ps1",
    "scripts\local-runtime\detect-hardware.ps1",
    "scripts\local-runtime\resolve-local-runtime.ps1",
    "scripts\local-runtime\benchmark-ollama.ps1",
    "scripts\local-runtime\initialize-local-runtime.ps1",
    "scripts\run-gate-agent.ps1",
    "scripts\run-pending-gates.ps1",
    "scripts\generate-engineering-backlog.ps1",
    "scripts\materialize-engineering-backlog.ps1",
    ".codex\provider-config.json",
    ".codex\local-runtime-config.json",
    "schemas\agent-result.schema.json",
    "schemas\review-result.schema.json",
    "schemas\qa-gate-result.schema.json",
    "schemas\security-gate-result.schema.json",
    "schemas\engineering-backlog.schema.json"
)

foreach ($relative in $required) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path $path)) {
        throw "Missing runtime component: $relative"
    }
}

$schemaPath = Join-Path $repoRoot "schemas\agent-result.schema.json"
$schema = Get-Content $schemaPath -Raw | ConvertFrom-Json

foreach ($field in @("outcome","summary","report_markdown","verification","decisions","blockers","recommended_next")) {
    if ($schema.required -notcontains $field) {
        throw "Runtime schema missing required field: $field"
    }
}

if ([string]$schema.properties.outcome.description -notmatch 'Use COMPLETED.*release blockers') {
    throw "Runtime schema must distinguish completed audits from product/release blockers"
}
if ([string]$schema.properties.blockers.description -notmatch 'Execution blockers') {
    throw "Runtime schema blockers field must mean execution blockers"
}

$configPath = Join-Path $repoRoot ".codex\provider-config.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

foreach ($providerName in @("Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok")) {
    if (@($config.auto_order) -notcontains $providerName) {
        throw "Provider config must include $providerName"
    }
}
if ([bool]$config.allow_paid_fallback -ne $false) { throw "Paid provider fallback must default to disabled" }
if ([string]$config.models.Ollama -ne "llama3.1:8b") { throw "Ollama must default to llama3.1:8b" }
if ([int]$config.ollama_context_max_chars -gt 25000) { throw "Ollama context pack must remain tightly bounded for local inference" }
if ([int]$config.ollama_gate_context_max_chars -gt 10000) { throw "Ollama gate base context must remain tightly bounded" }
if ([int]$config.ollama_gate_artifact_max_chars -gt 5000) { throw "Ollama gate artifact context must remain tightly bounded" }
if ([string]$config.models.OpenRouter -ne "openrouter/free") { throw "OpenRouter must default to openrouter/free" }
if ([string]$config.models.Gemini -ne "gemini-3.5-flash-lite") { throw "Gemini must default to gemini-3.5-flash-lite" }
if ([string]$config.models.DeepSeek -ne "deepseek-flash") { throw "DeepSeek must default to deepseek-flash" }
if ([string]$config.models.Grok -ne "grok-4.7") { throw "Grok must default to grok-4.7" }
if ([int]$config.context_max_chars -lt 300000) { throw "External provider context budget must be at least 300000 characters" }
if ([int]$config.gate_context_max_chars -lt 100000) { throw "Gate context budget must be explicitly configured" }

$pmInstructions = Get-Content (Join-Path $repoRoot ".codex\agents\pm.md") -Raw
if ($pmInstructions -notmatch 'Existing Project Context Fallback') {
    throw "PM instructions must support existing-project intake baselines"
}
if ($pmInstructions -notmatch 'product-intake\.md') {
    throw "PM existing-project fallback must recognize product-intake.md"
}

$runnerPath = Join-Path $repoRoot "scripts\run-agent-task.ps1"
$runner = Get-Content $runnerPath -Raw

if ($runner -notmatch 'ValidateSet\("Auto","Codex","OpenRouter","Gemini","Ollama","DeepSeek","Grok"\)') {
    throw "Agent runner must expose the full multi-provider selection"
}
if ($runner -notmatch '\$needsExternalContext = \(\$Provider -ne "Codex"\)') {
    throw "Agent runner must build bounded context for every non-Codex provider"
}
if ($runner -notmatch 'provider-router\.ps1') {
    throw "Agent runner must route through provider-router.ps1"
}
if ($runner -notmatch 'build-agent-context\.ps1') {
    throw "Agent runner must build repository context for external providers"
}
if ($runner -notmatch 'submit-task-result\.ps1') {
    throw "Agent runner must feed the Result Intake Engine"
}
if ($runner -notmatch 'COMPLETED means you completed the assigned audit') {
    throw "Agent runner must define audit completion semantics"
}
if ($runner -notmatch 'BLOCKED means you could not complete the assigned agent task itself') {
    throw "Agent runner must reserve BLOCKED for execution blockers"
}
$gateBatch = Get-Content (Join-Path $repoRoot "scripts\run-pending-gates.ps1") -Raw
if ($gateBatch -notmatch 'securityOutcome -in @\("PASS","NOT_APPLICABLE"\)') {
    throw "Pending gate runner must skip already satisfied security gates"
}

$codex = Get-Content (Join-Path $repoRoot "scripts\providers\invoke-codex.ps1") -Raw
if ($codex -notmatch '"--sandbox","read-only"') {
    throw "Codex adapter must use read-only sandbox"
}
if ($codex -notmatch '"--output-schema"') {
    throw "Codex adapter must require structured output"
}
if ($codex -notmatch '\$env:CODEX_API_KEY = \$null') {
    throw "Codex adapter must disable paid API-key auth to prevent accidental spend"
}

$openRouter = Get-Content (Join-Path $repoRoot "scripts\providers\invoke-openrouter.ps1") -Raw
if ($openRouter -notmatch 'https://openrouter\.ai/api/v1/chat/completions') {
    throw "OpenRouter adapter endpoint is missing"
}
if ($openRouter -notmatch 'OPENROUTER_API_KEY') {
    throw "OpenRouter adapter must use OPENROUTER_API_KEY"
}
if ($openRouter -notmatch 'json_schema') {
    throw "OpenRouter adapter must request structured JSON output"
}
if ($openRouter -notmatch 'Get-HttpErrorBody') {
    throw "OpenRouter adapter must surface HTTP error response bodies"
}
if ($openRouter -notmatch 'UTF8\.GetBytes') {
    throw "OpenRouter adapter must send explicitly encoded UTF-8 request bytes"
}
if ($openRouter -notmatch 'application/json; charset=utf-8') {
    throw "OpenRouter adapter must declare UTF-8 JSON content type"
}
if ($openRouter -notmatch 'ConvertFrom-Json') {
    throw "OpenRouter adapter must validate serialized JSON before transport"
}
if ($openRouter -notmatch 'Test-TransientOpenRouterError') {
    throw "OpenRouter adapter must classify transient failures"
}
if ($openRouter -notmatch '\$maxAttempts = 3') {
    throw "OpenRouter adapter must retry transient failures"
}
if ($openRouter -notmatch 'StatusCode -eq 429') {
    throw "OpenRouter adapter must retry rate-limit responses"
}
if ($openRouter -notmatch 'StatusCode -ge 500') {
    throw "OpenRouter adapter must retry server errors"
}

$gemini = Get-Content (Join-Path $repoRoot "scripts\providers\invoke-gemini.ps1") -Raw
if ($gemini -notmatch 'generativelanguage\.googleapis\.com') {
    throw "Gemini adapter endpoint is missing"
}
if ($gemini -notmatch 'GEMINI_API_KEY') {
    throw "Gemini adapter must use GEMINI_API_KEY"
}
if ($gemini -notmatch 'responseJsonSchema') {
    throw "Gemini adapter must request structured JSON output"
}

$ollama = Get-Content (Join-Path $repoRoot "scripts\providers\invoke-ollama.ps1") -Raw
foreach ($adapterName in @("invoke-openrouter.ps1","invoke-gemini.ps1","invoke-ollama.ps1","invoke-deepseek.ps1","invoke-xai.ps1")) {
    $adapterText = Get-Content (Join-Path $repoRoot ("scripts\providers\" + $adapterName)) -Raw
    if ($adapterText -notmatch '\[AllowEmptyString\(\)\]\[string\]\$Context') {
        throw "$adapterName must accept an empty context payload for direct provider smoke tests"
    }
}
if ($ollama -notmatch 'localhost:11434') { throw "Ollama adapter must default to the local Ollama endpoint" }
if ($ollama -notmatch 'OLLAMA_BASE_URL') { throw "Ollama adapter must support a configurable local endpoint" }
if ($ollama -notmatch 'format = \$schema') { throw "Ollama adapter must pass the requested JSON schema to format" }
if ($ollama -notmatch 'Test-TransientOllamaError') { throw "Ollama adapter must classify transient failures" }
if ($ollama -notmatch '\[int\]\$NumCtx = 8192') { throw "Ollama adapter must expose an adaptive context parameter" }
if ($ollama -notmatch '\[int\]\$NumPredict = 1024') { throw "Ollama adapter must expose an adaptive generation parameter" }
if ($ollama -notmatch 'num_ctx = \$NumCtx') { throw "Ollama adapter must apply the resolved context budget" }
if ($ollama -notmatch 'num_predict = \$NumPredict') { throw "Ollama adapter must apply the resolved generation budget" }
if ($ollama -notmatch 'OLLAMA_TIMEOUT_SEC') { throw "Ollama adapter must support a configurable timeout" }

$deepSeek = Get-Content (Join-Path $repoRoot "scripts\providers\invoke-deepseek.ps1") -Raw
if ($deepSeek -notmatch 'https://api\.deepseek\.com/chat/completions') { throw "DeepSeek adapter endpoint is missing" }
if ($deepSeek -notmatch 'DEEPSEEK_API_KEY') { throw "DeepSeek adapter must use DEEPSEEK_API_KEY" }
if ($deepSeek -notmatch 'json_object') { throw "DeepSeek adapter must request JSON output" }
if ($deepSeek -notmatch 'Test-TransientDeepSeekError') { throw "DeepSeek adapter must classify transient failures" }

$xai = Get-Content (Join-Path $repoRoot "scripts\providers\invoke-xai.ps1") -Raw
if ($xai -notmatch 'https://api\.x\.ai/v1/chat/completions') { throw "xAI adapter endpoint is missing" }
if ($xai -notmatch 'XAI_API_KEY') { throw "xAI adapter must use XAI_API_KEY" }
if ($xai -notmatch 'json_schema') { throw "xAI adapter must request schema-constrained structured output" }
if ($xai -notmatch 'Test-TransientXaiError') { throw "xAI adapter must classify transient failures" }

$router = Get-Content (Join-Path $repoRoot "scripts\provider-router.ps1") -Raw
if ($router -notmatch 'allow_paid_fallback') { throw "Provider router must guard paid automatic fallbacks" }
if ($router -notmatch 'DeepSeek.*Grok') { throw "Provider router must know the paid provider set" }
if ($router -notmatch 'resolve-local-runtime\.ps1') { throw "Provider router must use the hardware-aware local runtime resolver" }
if ($router -notmatch 'HardwareProfile') { throw "Provider router must surface the selected local hardware profile" }
if ($router -notmatch 'NumCtx') { throw "Provider router must pass adaptive Ollama inference budgets" }

$localConfig = Get-Content (Join-Path $repoRoot ".codex\local-runtime-config.json") -Raw | ConvertFrom-Json
foreach ($profileName in @("LOCAL_CPU_LOW","LOCAL_CPU_HIGH","LOCAL_GPU_6GB","LOCAL_GPU_8GB","LOCAL_GPU_12GB","LOCAL_GPU_16GB_PLUS")) {
    if ($null -eq $localConfig.profiles.PSObject.Properties[$profileName]) {
        throw "Local runtime config missing profile: $profileName"
    }
}
if ([int]$localConfig.profiles.LOCAL_GPU_12GB.num_ctx -le [int]$localConfig.profiles.LOCAL_CPU_LOW.num_ctx) {
    throw "12 GB GPU profile must expose more context than low-CPU profile"
}


$contextBuilder = Get-Content (Join-Path $repoRoot "scripts\build-agent-context.ps1") -Raw
if ($contextBuilder -notmatch '\.env') { throw "Context builder must explicitly exclude environment files" }
if (-not $contextBuilder.Contains("private[-_]?key")) { throw "Context builder must exclude private-key files" }

$parseTargets = @(
    "scripts\run-agent-task.ps1",
    "scripts\run-active-agents.ps1",
    "scripts\provider-router.ps1",
    "scripts\build-agent-context.ps1",
    "scripts\providers\invoke-codex.ps1",
    "scripts\providers\invoke-openrouter.ps1",
    "scripts\providers\invoke-gemini.ps1",
    "scripts\providers\invoke-ollama.ps1",
    "scripts\providers\invoke-deepseek.ps1",
    "scripts\providers\invoke-xai.ps1",
    "scripts\local-runtime\detect-hardware.ps1",
    "scripts\local-runtime\resolve-local-runtime.ps1",
    "scripts\local-runtime\benchmark-ollama.ps1",
    "scripts\local-runtime\initialize-local-runtime.ps1",
    "scripts\run-gate-agent.ps1",
    "scripts\run-pending-gates.ps1",
    "scripts\generate-engineering-backlog.ps1",
    "scripts\materialize-engineering-backlog.ps1"
)

foreach ($relative in $parseTargets) {
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repoRoot $relative),
        [ref]$null,
        [ref]$parseErrors
    )

    if ($parseErrors.Count -gt 0) {
        throw ($relative + " has PowerShell parse errors: " + (($parseErrors | ForEach-Object { $_.Message }) -join "; "))
    }
}

$tempRoot = Join-Path $env:TEMP ("aico-runtime-contract-" + [Guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".codex\agents") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".codex\state") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "tasks") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\engineering\dispatch") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\product") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\architecture") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs\operations") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "src") | Out-Null

    Set-Content (Join-Path $tempRoot "AGENTS.md") "runtime contract fixture"
    Set-Content (Join-Path $tempRoot ".codex\agents\pm.md") "PM fixture"
    Set-Content (Join-Path $tempRoot "tasks\AICO-TEST.md") "ID: AICO-TEST"
    Set-Content (Join-Path $tempRoot "docs\engineering\dispatch\AICO-TEST.md") "dispatch fixture"
    Set-Content (Join-Path $tempRoot "docs\engineering\project-intake.md") "engineering intake"
    Set-Content (Join-Path $tempRoot "docs\product\product-intake.md") "product intake"
    Set-Content (Join-Path $tempRoot "docs\architecture\architecture-intake.md") "architecture intake"
    Set-Content (Join-Path $tempRoot "docs\operations\operations-intake.md") "operations intake"
    Set-Content (Join-Path $tempRoot "src\product-controller.ts") "export const product = true;"
    Set-Content (Join-Path $tempRoot ".env") "SUPER_SECRET_VALUE=must-not-leak"

    $context = & (Join-Path $repoRoot "scripts\build-agent-context.ps1") -ProjectPath $tempRoot -Id "AICO-TEST" -Owner "pm" -MaxChars 20000

    if ($context -notmatch 'src\\product-controller\.ts') {
        throw "Context builder did not include relevant source evidence"
    }
    if ($context.Length -gt 20000) {
        throw "Context builder exceeded requested MaxChars"
    }
    if ($context -match 'must-not-leak') {
        throw "Context builder leaked .env content"
    }
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}



$engineeringSchema = Get-Content (Join-Path $repoRoot "schemas\engineering-backlog.schema.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($engineeringSchema.required) -notcontains "implementation_authorization_key") {
    throw "Engineering backlog schema must require implementation_authorization_key"
}

$materializerScript = Get-Content (Join-Path $repoRoot "scripts\materialize-engineering-backlog.ps1") -Raw -Encoding UTF8
if ($materializerScript -notmatch 'dependency cycle') {
    throw "Engineering backlog materializer must reject dependency cycles"
}
if ($materializerScript -notmatch 'Test-DependsOnKey') {
    throw "Engineering backlog materializer must enforce authorization dependency reachability"
}

Write-Host "PASS: multi-provider agent runtime contract test" -ForegroundColor Green
