param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-analysis-context-" + [Guid]::NewGuid().ToString("N"))

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    Write-Utf8NoBom (Join-Path $tempRoot "sample.txt") "CLIENT_SAMPLE_EVIDENCE"

    & (Join-Path $repoRoot "scripts\install-existing-project.ps1") -TargetProject $tempRoot | Out-Null

    $manifestPath = Join-Path $tempRoot ".codex\managed-files.json"
    if (-not (Test-Path $manifestPath)) {
        throw "Installed project must contain .codex/managed-files.json"
    }

    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $managed = @($manifest.managed_files | ForEach-Object { ([string]$_).Replace("\","/") })

    foreach ($requiredManaged in @(
        "scripts/build-agent-context.ps1",
        "scripts/run-agent-task.ps1",
        "schemas/agent-result.schema.json",
        ".codex/agents/pm.md"
    )) {
        if ($managed -notcontains $requiredManaged) {
            throw "Managed manifest missing installed runtime file: $requiredManaged"
        }
    }

    Write-Utf8NoBom (Join-Path $tempRoot "docs\PROJECT-BRIEF.md") "CLIENT_PROJECT_BRIEF"
    Write-Utf8NoBom (Join-Path $tempRoot "tasks\AICO-CTX.md") @"
# AICO-CTX
ID: AICO-CTX
Status: ACTIVE
Owner: pm
"@
    Write-Utf8NoBom (Join-Path $tempRoot "docs\engineering\dispatch\AICO-CTX.md") "CLIENT_DISPATCH_EVIDENCE"

    Write-Utf8NoBom (Join-Path $tempRoot "scripts\client-build.ps1") "CLIENT_SCRIPT_EVIDENCE"
    Write-Utf8NoBom (Join-Path $tempRoot "schemas\client-domain.schema.json") '{"client":"CLIENT_SCHEMA_EVIDENCE"}'

    $managedBloat = "MANAGED_RUNTIME_BLOAT_" + ("X" * 24000)
    foreach ($relative in @(
        "scripts\advance-task.ps1",
        "scripts\build-agent-context.ps1",
        "scripts\dispatch-ready-tasks.ps1"
    )) {
        Write-Utf8NoBom (Join-Path $tempRoot $relative) $managedBloat
    }

    $builder = Join-Path $repoRoot "scripts\build-agent-context.ps1"
    $context = & $builder -ProjectPath $tempRoot -Id "AICO-CTX" -Owner "pm" -MaxChars 50000

    if ($context -notmatch 'CLIENT_SAMPLE_EVIDENCE') {
        throw "PM context lost client sample evidence because managed runtime consumed the generic budget"
    }
    if ($context -notmatch 'CLIENT_SCRIPT_EVIDENCE') {
        throw "Client-owned scripts must remain eligible for generic repository context"
    }
    if ($context -match 'MANAGED_RUNTIME_BLOAT') {
        throw "Managed AI Company OS runtime leaked into generic repository context"
    }
    if ($context -match 'scripts\\advance-task\.ps1|scripts\\build-agent-context\.ps1') {
        throw "Managed AI Company OS paths leaked into generic repository inventory"
    }
    if ($context -notmatch 'CLIENT_PROJECT_BRIEF') {
        throw "Canonical PROJECT-BRIEF must remain included even when managed files are filtered"
    }
    if ($context -notmatch 'CLIENT_DISPATCH_EVIDENCE') {
        throw "Canonical dispatch context must remain included"
    }
    if ($context.Length -gt 50000) {
        throw "Analysis context exceeded requested MaxChars"
    }

    $requiredBody = ("R" * 12000) + "REQUIRED_FILE_END"
    Write-Utf8NoBom (Join-Path $tempRoot "src\required.ts") $requiredBody

    $requiredContext = & $builder -ProjectPath $tempRoot -Id "AICO-CTX" -Owner "pm" -MaxChars 18000 -RequiredFiles @("src\required.ts")
    if ($requiredContext -notmatch 'REQUIRED_FILE_END') {
        throw "Explicit RequiredFiles must be included completely"
    }

    $tooLargeBody = ("Z" * 15000) + "TOO_LARGE_END"
    Write-Utf8NoBom (Join-Path $tempRoot "src\too-large.ts") $tooLargeBody

    $requiredFailed = $false
    try {
        $null = & $builder -ProjectPath $tempRoot -Id "AICO-CTX" -Owner "pm" -MaxChars 10000 -RequiredFiles @("src\too-large.ts")
    }
    catch {
        $requiredFailed = $true
        if ($_.Exception.Message -notmatch 'cannot fit completely|exhausted the configured context budget') {
            throw
        }
    }

    if (-not $requiredFailed) {
        throw "Oversized explicit RequiredFiles must fail instead of being silently truncated"
    }

    Write-Host "PASS: managed analysis context budget regression" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}
