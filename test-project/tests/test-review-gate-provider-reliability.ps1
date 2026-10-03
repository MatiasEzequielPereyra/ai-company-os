param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "aico-review-gate-provider-reliability-" +
    [Guid]::NewGuid().ToString("N")
)

$savedOpenRouterKey = $env:OPENROUTER_API_KEY

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
        New-Item -ItemType Directory -Force `
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

    # Deliberately use the framework's real provider policy.
    Copy-Item `
        (Join-Path $repoRoot ".codex\provider-config.json") `
        (Join-Path $tempRoot ".codex\provider-config.json") `
        -Force

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
        '    Reason = "Deterministic Review gate P1 fixture."'
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
        'Add-Content -Path (Join-Path $fixtureRoot "provider-attempts.txt") -Value "Ollama" -Encoding UTF8'
        ''
        '[System.IO.File]::WriteAllText('
        '    (Join-Path $fixtureRoot "ollama-runtime.txt"),'
        '    ("sent_chars=" + $Context.Length + ";num_ctx=" + $NumCtx + ";num_predict=" + $NumPredict),'
        '    (New-Object System.Text.UTF8Encoding($false))'
        ')'
        ''
        'throw ('
        '    "Ollama structured completion was truncated. " +'
        '    "done_reason=length; " +'
        '    "prompt_eval_count=2403; " +'
        '    "eval_count=2048; " +'
        '    "num_predict=2048"'
        ')'
    ) -join [Environment]::NewLine

    Write-Utf8NoBom `
        (Join-Path $tempRoot "scripts\providers\invoke-ollama.ps1") `
        $ollamaAdapter

    $openRouterAdapter = @(
        'param('
        '    [string]$Prompt,'
        '    [string]$Context,'
        '    [string]$SchemaPath,'
        '    [string]$OutputPath,'
        '    [string]$Model,'
        '    [int]$TimeoutSeconds'
        ')'
        ''
        '$fixtureRoot = Split-Path -Parent $OutputPath'
        'Add-Content -Path (Join-Path $fixtureRoot "provider-attempts.txt") -Value "OpenRouter" -Encoding UTF8'
        ''
        '$payload = @{'
        '    recommendation = "APPROVE"'
        '    findings = "Deterministic Review fallback fixture."'
        '    verification = "Truncated Ollama was rejected and fallback completed."'
        '    missing_required_outputs = @()'
        '    deliverable_defects = @()'
        '} | ConvertTo-Json -Depth 10'
        ''
        '[System.IO.File]::WriteAllText('
        '    $OutputPath,'
        '    $payload,'
        '    (New-Object System.Text.UTF8Encoding($false))'
        ')'
        ''
        '[PSCustomObject]@{'
        '    Provider = "OpenRouter"'
        '    Model = $Model'
        '}'
    ) -join [Environment]::NewLine

    Write-Utf8NoBom `
        (Join-Path $tempRoot "scripts\providers\invoke-openrouter.ps1") `
        $openRouterAdapter

    $semanticCapture = @(
        'param('
        '    [Parameter(Mandatory = $true)]'
        '    [string]$JsonPath'
        ')'
        ''
        '$fixtureRoot = Split-Path -Parent $JsonPath'
        ''
        '[System.IO.File]::WriteAllText('
        '    (Join-Path $fixtureRoot "semantic-validation-invoked.txt"),'
        '    "invoked",'
        '    (New-Object System.Text.UTF8Encoding($false))'
        ')'
        ''
        '& (Join-Path $PSScriptRoot "validate-gate-result-semantics.ps1") -JsonPath $JsonPath | Out-Null'
    ) -join [Environment]::NewLine

    Write-Utf8NoBom `
        (Join-Path $tempRoot "scripts\validate-gate-semantic-capture.ps1") `
        $semanticCapture

    $env:OPENROUTER_API_KEY = "p1-review-gate-fixture"

    $context = "G" * 51021

    $routerArgs = @{
        Provider = "Auto"
        ProjectPath = $tempRoot
        Prompt = "Deterministic Review gate provider reliability fixture"
        Context = $context
        SchemaPath = Join-Path $tempRoot "schemas\review-result.schema.json"
        OutputPath = Join-Path $tempRoot "review-result.json"
        Role = "engineering-manager"
        Workload = "gate"
        SemanticValidatorPath = Join-Path $tempRoot "scripts\validate-gate-semantic-capture.ps1"
    }

    $result = & (
        Join-Path $tempRoot "scripts\provider-router.ps1"
    ) @routerArgs

    if ([string]$result.Provider -ne "OpenRouter") {
        throw (
            "Review Auto gate did not fall back to OpenRouter after " +
            "Ollama truncation. Actual provider: " +
            [string]$result.Provider
        )
    }

    $attemptsPath = Join-Path $tempRoot "provider-attempts.txt"

    if (-not (Test-Path $attemptsPath)) {
        throw "Provider attempt capture was not created."
    }

    $attempts = @(
        Get-Content $attemptsPath -Encoding UTF8 |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($attempts.Count -lt 2) {
        throw (
            "Expected Ollama truncation followed by another provider. " +
            "Attempts: " + ($attempts -join ", ")
        )
    }

    if ($attempts[0] -ne "Ollama") {
        throw (
            "Review Auto gate must remain local-first. First provider: " +
            $attempts[0]
        )
    }

    if ($attempts[1] -ne "OpenRouter") {
        throw (
            "Expected OpenRouter as next eligible provider. Attempts: " +
            ($attempts -join ", ")
        )
    }

    $runtimeCapture = Get-Content `
        (Join-Path $tempRoot "ollama-runtime.txt") `
        -Raw `
        -Encoding UTF8

    if ($runtimeCapture -notmatch 'sent_chars=7000') {
        throw (
            "Expected current Ollama gate candidate cap of 7000 chars. Actual: " +
            $runtimeCapture
        )
    }

    if ($runtimeCapture -notmatch 'num_ctx=16384') {
        throw (
            "Expected LOCAL_GPU_12GB num_ctx=16384. Actual: " +
            $runtimeCapture
        )
    }

    if ($runtimeCapture -notmatch 'num_predict=2048') {
        throw (
            "Expected LOCAL_GPU_12GB num_predict=2048. Actual: " +
            $runtimeCapture
        )
    }

    if (-not (
        Test-Path (
            Join-Path $tempRoot "semantic-validation-invoked.txt"
        )
    )) {
        throw "Review semantic validation was not executed."
    }

    & (
        Join-Path $tempRoot "scripts\validate-gate-result-semantics.ps1"
    ) `
        -JsonPath (Join-Path $tempRoot "review-result.json") |
        Out-Null

    Remove-Item $attemptsPath -Force -ErrorAction SilentlyContinue

    $explicitOutput = Join-Path $tempRoot "explicit-ollama-result.json"
    Remove-Item $explicitOutput -Force -ErrorAction SilentlyContinue

    $explicitArgs = $routerArgs.Clone()
    $explicitArgs["Provider"] = "Ollama"
    $explicitArgs["OutputPath"] = $explicitOutput

    $explicitError = $null

    try {
        & (
            Join-Path $tempRoot "scripts\provider-router.ps1"
        ) @explicitArgs | Out-Null
    }
    catch {
        $explicitError = $_
    }

    if ($null -eq $explicitError) {
        throw (
            "Explicit Ollama gate unexpectedly succeeded after " +
            "the deterministic truncated completion."
        )
    }

    $explicitMessage = [string]$explicitError.Exception.Message

    if ($explicitMessage -notmatch '(?i)Ollama.*truncat|truncat.*Ollama') {
        throw (
            "Explicit Ollama failure did not preserve truncation diagnostics. " +
            "Actual: " + $explicitMessage
        )
    }

    if (-not (Test-Path $attemptsPath)) {
        throw "Explicit Ollama provider attempt was not captured."
    }

    $explicitAttempts = @(
        Get-Content $attemptsPath -Encoding UTF8 |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if (
        $explicitAttempts.Count -ne 1 -or
        $explicitAttempts[0] -ne "Ollama"
    ) {
        throw (
            "Explicit Provider=Ollama must never fall back to cloud. " +
            "Attempts: " + ($explicitAttempts -join ", ")
        )
    }

    if (Test-Path $explicitOutput) {
        throw "Truncated explicit Ollama output must not be persisted."
    }

    Write-Host (
        "PASS: explicit Ollama rejects truncation without cloud fallback"
    ) -ForegroundColor Green

    Write-Host (
        "PASS: Review Auto rejects truncated Ollama and falls back " +
        "to valid semantically checked Review output"
    ) -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedOpenRouterKey

    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
