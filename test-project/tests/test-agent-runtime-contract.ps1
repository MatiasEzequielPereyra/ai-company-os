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
    ".codex\provider-config.json",
    "schemas\agent-result.schema.json"
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

$configPath = Join-Path $repoRoot ".codex\provider-config.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

if (@($config.auto_order) -notcontains "Codex") { throw "Provider config must include Codex" }
if (@($config.auto_order) -notcontains "OpenRouter") { throw "Provider config must include OpenRouter" }
if (@($config.auto_order) -notcontains "Gemini") { throw "Provider config must include Gemini" }
if ([string]$config.models.OpenRouter -ne "openrouter/free") { throw "OpenRouter must default to openrouter/free" }
if ([string]$config.models.Gemini -ne "gemini-3.5-flash-lite") { throw "Gemini must default to gemini-3.5-flash-lite" }
if ([int]$config.context_max_chars -lt 500000) { throw "External provider context budget must be at least 500000 characters" }

$pmInstructions = Get-Content (Join-Path $repoRoot ".codex\agents\pm.md") -Raw
if ($pmInstructions -notmatch 'Existing Project Context Fallback') {
    throw "PM instructions must support existing-project intake baselines"
}
if ($pmInstructions -notmatch 'product-intake\.md') {
    throw "PM existing-project fallback must recognize product-intake.md"
}

$runnerPath = Join-Path $repoRoot "scripts\run-agent-task.ps1"
$runner = Get-Content $runnerPath -Raw

if ($runner -notmatch 'ValidateSet\("Auto","Codex","OpenRouter","Gemini"\)') {
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

$parseTargets = @(
    "scripts\run-agent-task.ps1",
    "scripts\run-active-agents.ps1",
    "scripts\provider-router.ps1",
    "scripts\build-agent-context.ps1",
    "scripts\providers\invoke-codex.ps1",
    "scripts\providers\invoke-openrouter.ps1",
    "scripts\providers\invoke-gemini.ps1"
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

Write-Host "PASS: multi-provider agent runtime contract test" -ForegroundColor Green
