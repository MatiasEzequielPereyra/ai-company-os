param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$required = @(
    "scripts\run-agent-task.ps1",
    "scripts\run-active-agents.ps1",
    "scripts\run-writable-agent.ps1",
    "scripts\provider-router.ps1",
    "scripts\build-agent-context.ps1",
    "scripts\resolve-writable-required-files.ps1",
    "scripts\providers\invoke-codex.ps1",
    "scripts\providers\invoke-openrouter.ps1",
    "scripts\providers\invoke-gemini.ps1",
    "scripts\providers\invoke-ollama.ps1",
    "scripts\providers\invoke-deepseek.ps1",
    "scripts\providers\invoke-xai.ps1",
    "scripts\local-runtime\detect-hardware.ps1",
    "scripts\local-runtime\resolve-local-runtime.ps1",
    "scripts\local-runtime\initialize-local-runtime.ps1",
    "scripts\local-runtime\benchmark-ollama.ps1",
    "scripts\run-gate-agent.ps1",
    "scripts\run-pending-gates.ps1",
    "scripts\generate-engineering-backlog.ps1",
    "scripts\materialize-engineering-backlog.ps1",
    ".codex\provider-config.json",
    "schemas\agent-result.schema.json",
    "schemas\writable-change-set.schema.json",
    ".codex\writable-policy.json",
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

$maxLengths = @{
    summary = 1000
    report_markdown = 12000
    verification = 2500
    decisions = 2500
    blockers = 2000
    recommended_next = 2000
}
foreach ($field in $maxLengths.Keys) {
    $actual = [int]$schema.properties.$field.maxLength
    if ($actual -lt 1 -or $actual -gt [int]$maxLengths[$field]) {
        throw "Runtime schema must bound $field output. Actual maxLength=$actual"
    }
}

$configPath = Join-Path $repoRoot ".codex\provider-config.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

if (@($config.auto_order) -notcontains "Codex") { throw "Provider config must include Codex" }
if (@($config.auto_order) -notcontains "OpenRouter") { throw "Provider config must include OpenRouter" }
if (@($config.auto_order) -notcontains "Gemini") { throw "Provider config must include Gemini" }
if (@($config.auto_order) -notcontains "Ollama") { throw "Provider config must include Ollama" }
if (@($config.auto_order) -notcontains "DeepSeek") { throw "Provider config must include DeepSeek" }
if (@($config.auto_order) -notcontains "Grok") { throw "Provider config must include Grok" }
if ([bool]$config.allow_paid_fallback) { throw "Paid analysis fallback must be disabled by default" }
if ([string]$config.models.OpenRouter -ne "openrouter/free") { throw "OpenRouter must default to openrouter/free" }
if ([string]$config.models.Gemini -ne "gemini-3.5-flash-lite") { throw "Gemini must default to gemini-3.5-flash-lite" }
if (@($config.writable_auto_order) -join "," -ne "OpenRouter,Gemini") { throw "Writable Auto must be limited to OpenRouter then Gemini" }
if ([string]$config.writable_models.OpenRouter -ne "qwen/qwen3.8-27b:free") { throw "Writable OpenRouter must default to the pinned free structured coding model" }
if ([string]$config.writable_models.Gemini -ne "gemini-3.5-flash-lite") { throw "Writable Gemini must default to gemini-3.5-flash-lite" }
if ([int]$config.writable_context_max_chars -gt 160000 -or [int]$config.writable_context_max_chars -lt 60000) { throw "Writable context budget must remain bounded for free-tier execution" }
if ($null -eq $config.analysis_context_max_chars) { throw "Analysis context budget must be explicitly configured" }
if ([int]$config.analysis_context_max_chars -gt 160000 -or [int]$config.analysis_context_max_chars -lt 60000) {
    throw "Analysis context budget must remain bounded and useful"
}
if ($null -eq $config.analysis_context_max_chars_by_role) {
    throw "Analysis context must support role-specific budgets"
}
$pmBudget = [int]$config.analysis_context_max_chars_by_role.pm
if ($pmBudget -lt 20000 -or $pmBudget -gt 100000) {
    throw "PM analysis context budget must be substantially below the historical 320000-character budget"
}
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
    throw "Agent runner must expose multi-provider selection"
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
if ($runner -notmatch 'analysis_context_max_chars_by_role') {
    throw "Agent runner must honor role-specific analysis context budgets"
}
if ($runner -notmatch 'analysis_context_max_chars') {
    throw "Agent runner must honor the global analysis context budget"
}
if ($runner -notmatch 'structured result concise|Keep the structured result concise') {
    throw "Agent runner must instruct schema-critical analysis results to stay concise"
}
$writableRunner = Get-Content (Join-Path $repoRoot "scripts\run-writable-agent.ps1") -Raw
if ($writableRunner -notmatch 'ValidateSet\("Auto","OpenRouter","Gemini"\)') {
    throw "Writable runner must expose only Auto/OpenRouter/Gemini provider selection"
}
if ($writableRunner -notmatch 'refuses to use the primary checkout') {
    throw "Writable runner must reject the primary checkout as a writable workspace"
}
if ($writableRunner -notmatch 'writable-change-set\.schema\.json') {
    throw "Writable runner must require the writable structured change contract"
}
if ($writableRunner -notmatch 'writable-policy\.json') {
    throw "Writable runner must enforce the writable policy"
}
if ($writableRunner -match 'Invoke-Expression') {
    throw "Writable runner must never execute model-provided PowerShell through Invoke-Expression"
}
if ($writableRunner -notmatch 'protected control-plane path') {
    throw "Writable runner must reject protected control-plane paths"
}
if ($writableRunner -notmatch 'symlink/junction/reparse point') {
    throw "Writable runner must block reparse-point escapes"
}
if ($writableRunner -notmatch 'submit-task-result\.ps1') {
    throw "Writable runner must reuse the canonical Result Intake Engine"
}
if ($writableRunner -notmatch 'resolve-writable-required-files\.ps1') {
    throw "Writable runner must resolve explicit task/dispatch file requirements before provider execution"
}
if ($writableRunner -notmatch '-RequiredFiles') {
    throw "Writable runner must pass resolved required files into the context builder"
}

$writableSchema = Get-Content (Join-Path $repoRoot "schemas\writable-change-set.schema.json") -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($field in @("outcome","summary","report_markdown","changes","verification_commands","verification","decisions","blockers","recommended_next")) {
    if (@($writableSchema.required) -notcontains $field) {
        throw "Writable change-set schema missing required field: $field"
    }
}

$writablePolicy = Get-Content (Join-Path $repoRoot ".codex\writable-policy.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($writablePolicy.free_provider_models.OpenRouter) -notcontains "qwen/qwen3.8-27b:free") {
    throw "Writable policy must allow the pinned free structured coding model"
}
if (@($writablePolicy.protected_path_prefixes) -notcontains ".git") {
    throw "Writable policy must protect .git"
}
if (@($writablePolicy.secret_name_patterns).Count -lt 1) {
    throw "Writable policy must define secret-path rejection patterns"
}
if ([int]$writablePolicy.required_context_max_files -lt 1) {
    throw "Writable policy must bound explicit required context file count"
}
if ([long]$writablePolicy.required_context_max_total_bytes -lt 1) {
    throw "Writable policy must bound explicit required context total size"
}

$gateRunner = Get-Content (Join-Path $repoRoot "scripts\run-gate-agent.ps1") -Raw
if ($gateRunner -notmatch 'Repository-relative path') {
    throw "Gate runner must attach canonical repository-relative identity to explicit artifacts"
}
if ($gateRunner -notmatch 'Explicit gate artifacts are authoritative') {
    throw "Gate prompt must treat explicit gate artifacts as authoritative supplied evidence"
}
if ($gateRunner -notmatch 'generic repository inventory') {
    throw "Gate prompt must distinguish explicit artifact evidence from the generic inventory"
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
if ($openRouter -notmatch 'require_parameters') {
    throw "OpenRouter adapter must require providers that honor requested structured-output parameters"
}
if ($openRouter -notmatch 'empty/null structured content') {
    throw "OpenRouter adapter must reject empty/null structured responses with diagnostics"
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
if ($openRouter -notmatch 'finish_reason') {
    throw "OpenRouter adapter must inspect completion finish_reason"
}
if ($openRouter -notmatch 'length') {
    throw "OpenRouter adapter must explicitly reject length-truncated structured completions"
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

$contextBuilder = Get-Content (Join-Path $repoRoot "scripts\build-agent-context.ps1") -Raw
if ($contextBuilder -notmatch '\.env') { throw "Context builder must explicitly exclude environment files" }
if (-not $contextBuilder.Contains("private[-_]?key")) { throw "Context builder must exclude private-key files" }
if ($contextBuilder -notmatch 'RequiredFiles') { throw "Context builder must support prioritized required files" }
if ($contextBuilder -notmatch 'RequireComplete') { throw "Required context files must not be silently truncated" }
if ($contextBuilder -notmatch 'managed-files\.json') { throw "Context builder must load the managed runtime manifest" }
if ($contextBuilder -notmatch 'managed_files') { throw "Context builder must exclude manifest-owned runtime paths from generic context" }

$requiredResolver = Get-Content (Join-Path $repoRoot "scripts\resolve-writable-required-files.ps1") -Raw
if ($requiredResolver -notmatch 'ambiguous') { throw "Required-file resolver must reject ambiguous basenames" }
if ($requiredResolver -notmatch 'secret-sensitive') { throw "Required-file resolver must reject secret-sensitive required files" }
if ($requiredResolver -notmatch 'reparse point') { throw "Required-file resolver must reject reparse-point escapes" }

$parseTargets = @(
    "scripts\run-agent-task.ps1",
    "scripts\run-active-agents.ps1",
    "scripts\run-writable-agent.ps1",
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
    "scripts\local-runtime\initialize-local-runtime.ps1",
    "scripts\local-runtime\benchmark-ollama.ps1",
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
