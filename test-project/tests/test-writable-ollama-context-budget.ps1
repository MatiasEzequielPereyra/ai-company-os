param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase ("aico-writable-budget-" + [Guid]::NewGuid().ToString("N"))
$savedKey = $env:OPENROUTER_API_KEY

function Write-Fixture {
    param([string]$Relative,[string]$Text)
    [System.IO.File]::WriteAllText((Join-Path $tempRoot $Relative),$Text,(New-Object System.Text.UTF8Encoding($false)))
}

try {
    foreach ($dir in @("scripts","scripts/providers","scripts/local-runtime",".codex","schemas")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $dir) | Out-Null
    }
    foreach ($name in @("provider-router.ps1","validate-json-contract.ps1","write-operational-event.ps1")) {
        Copy-Item (Join-Path $repoRoot "scripts/$name") (Join-Path $tempRoot "scripts/$name")
    }
    Copy-Item (Join-Path $repoRoot "schemas/agent-result.schema.json") (Join-Path $tempRoot "schemas/agent-result.schema.json")
    Write-Fixture ".codex/local-runtime-config.json" "{}"
    $config = @{
        writable_context_max_chars = 30000
        ollama_context_max_chars = 25000
        models = @{ OpenRouter = "fixture/free" }
        allow_paid_fallback = $false
    }
    Write-Fixture ".codex/provider-config.json" ($config | ConvertTo-Json -Depth 10)
    Write-Fixture "scripts/local-runtime/resolve-local-runtime.ps1" @'
param([string]$ProjectPath,[string]$Role,[string]$Workload,[string]$ModelOverride)
if ($Role -ne "backend" -or $Workload -ne "writable") { throw "Wrong writable resolver role/workload" }
Get-Content (Join-Path $ProjectPath ".codex/runtime-fixture.json") -Raw | ConvertFrom-Json
'@
    $adapter = @'
param([string]$Prompt,[string]$Context,[string]$SchemaPath,[string]$OutputPath,[string]$Model,[int]$NumCtx,[int]$NumPredict,[int]$TimeoutSeconds)
[System.IO.File]::WriteAllText(($OutputPath + ".length"),[string]$Context.Length)
$payload = @{
    outcome = "COMPLETED"; summary = "Fixture"; report_markdown = "# Fixture"
    verification = "Fixture"; decisions = "NONE"; blockers = "NONE"; recommended_next = "REVIEW"
    completion_check = @{ substantive_role_deliverable_produced = $true; missing_required_outputs = @(); evidence = "Fixture" }
} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutputPath,$payload)
[PSCustomObject]@{ Provider = "Fixture"; Model = $Model }
'@
    Write-Fixture "scripts/providers/invoke-ollama.ps1" $adapter
    Write-Fixture "scripts/providers/invoke-openrouter.ps1" $adapter
    $router = Join-Path $tempRoot "scripts/provider-router.ps1"
    $output = Join-Path $tempRoot "result.json"
    $args = @{
        Provider = "Ollama"; ProjectPath = $tempRoot; Prompt = "Fixture"
        Context = ("x" * 50000); Role = "backend"; Workload = "writable"
        SchemaPath = (Join-Path $tempRoot "schemas/agent-result.schema.json"); OutputPath = $output
    }
    $runtime = @{
        Available = $true; ContextMaxChars = 15000; Model = "fixture/local"
        Profile = "LOCAL_CPU_LOW"; NumCtx = 4096; NumPredict = 1024
    }
    foreach ($case in @(
        @{ Hardware = 15000; Writable = 30000; Input = 50000; Expected = 15000 },
        @{ Hardware = 60000; Writable = 20000; Input = 50000; Expected = 20000 },
        @{ Hardware = 60000; Writable = 30000; Input = 50000; Expected = 25000 },
        @{ Hardware = 15000; Writable = 30000; Input = 9000; Expected = 9000 },
        @{ Hardware = 20; Writable = 30000; Input = 9000; Expected = 20 }
    )) {
        $runtime.ContextMaxChars = $case.Hardware
        $config.writable_context_max_chars = $case.Writable
        Write-Fixture ".codex/provider-config.json" ($config | ConvertTo-Json -Depth 10)
        Write-Fixture ".codex/runtime-fixture.json" ($runtime | ConvertTo-Json)
        $args.Context = "x" * $case.Input
        & $router @args | Out-Null
        $length = [int](Get-Content ($output + ".length") -Raw)
        if ($length -ne $case.Expected) { throw "Wrong effective writable context: $length != $($case.Expected)" }
        Remove-Item -LiteralPath ($output + ".length")
    }
    foreach ($invalid in @(
        @{ Available = $false; ContextMaxChars = 15000; Reason = "Unavailable fixture" },
        @{ Available = $true; ContextMaxChars = "invalid" },
        @{ Available = $true; ContextMaxChars = 0 },
        @{ Available = $true }
    )) {
        Write-Fixture ".codex/runtime-fixture.json" ($invalid | ConvertTo-Json)
        $failed = $false
        try { & $router @args | Out-Null } catch { $failed = $true }
        if (-not $failed -or (Test-Path ($output + ".length"))) { throw "Invalid runtime must fail before adapter invocation" }
    }
    Write-Fixture "scripts/local-runtime/resolve-local-runtime.ps1" 'param([string]$ProjectPath,[string]$Role,[string]$Workload,[string]$ModelOverride); throw "Fixture resolver failure"'
    $failed = $false
    try { & $router @args | Out-Null } catch { $failed = $true }
    if (-not $failed -or (Test-Path ($output + ".length"))) { throw "Resolver failure must fail before adapter invocation" }

    $env:OPENROUTER_API_KEY = "obviously-fake-writable-fixture"
    $args.Provider = "OpenRouter"
    $args.Context = "x" * 50000
    & $router @args | Out-Null
    if ([int](Get-Content ($output + ".length") -Raw) -ne 50000) { throw "Non-Ollama writable context must remain unchanged" }

    foreach ($forbidden in @("DeepSeek","Grok")) {
        $failed = $false
        try { & (Join-Path $repoRoot "scripts/run-writable-agent.ps1") -Id "FIXTURE" -Provider $forbidden | Out-Null }
        catch [System.Management.Automation.ParameterBindingException] { $failed = $true }
        if (-not $failed) { throw "$forbidden must be rejected by writable provider binding" }
    }
    Write-Host "PASS: writable Ollama context budget (5 limits, 5 invalid runtimes, cloud isolation, 2 forbidden providers)" -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedKey
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    if (-not $resolved.StartsWith($tempBase,[System.StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike "aico-writable-budget-*") {
        throw "Refusing unsafe fixture cleanup"
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
