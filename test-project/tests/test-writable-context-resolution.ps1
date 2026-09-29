param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-writable-context-" + [Guid]::NewGuid().ToString("N"))

function Write-NoBom {
    param([string]$Path,[string]$Value)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    Write-NoBom (Join-Path $tempRoot "index.html") "<html><body>REQUIRED_INDEX_SENTINEL</body></html>"
    Write-NoBom (Join-Path $tempRoot "src\other.ts") "export const other = true;"
    Write-NoBom (Join-Path $tempRoot "app.js") ("A" * 131674)
    Write-NoBom (Join-Path $tempRoot ".env") "SECRET_VALUE=must-not-leak"

    & git -C $tempRoot init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git init failed for writable context fixture." }
    & git -C $tempRoot config user.email "aico-test@example.invalid"
    & git -C $tempRoot config user.name "AI Company OS Test"
    & git -C $tempRoot add .
    & git -C $tempRoot commit -m "fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fixture commit failed." }

    $resolver = Join-Path $repoRoot "scripts\resolve-writable-required-files.ps1"
    $builder = Join-Path $repoRoot "scripts\build-agent-context.ps1"
    $policy = Join-Path $repoRoot ".codex\writable-policy.json"

    $taskText = @(
        "## Objective",
        "",
        "Modify index.html to load the mandatory runtime modules.",
        "",
        "## Acceptance Criteria",
        "",
        "- Update index.html so the required runtime modules load before app.js."
    ) -join [Environment]::NewLine

    $dispatchText = @(
        "Implementation target: index.html",
        "Do not invent its current content."
    ) -join [Environment]::NewLine

    $required = @(& $resolver -ProjectPath $tempRoot -SourceText @($taskText,$dispatchText) -PolicyPath $policy)

    if ($required -notcontains "index.html") {
        throw "Required-file resolver did not resolve index.html from explicit task/dispatch references."
    }

    if ($required -contains "app.js") {
        throw "Required-file resolver incorrectly promoted contextual app.js to a mandatory full-file target."
    }

    $oversizedTargetBlocked = $false
    try {
        & $resolver -ProjectPath $tempRoot -SourceText @("Update app.js for this implementation.") -PolicyPath $policy | Out-Null
    }
    catch {
        if ($_.Exception.Message -match "exceeds policy size limit") {
            $oversizedTargetBlocked = $true
        }
        else {
            throw
        }
    }

    if (-not $oversizedTargetBlocked) {
        throw "Required-file resolver did not block an oversized direct writable target."
    }

    $context = & $builder -ProjectPath $tempRoot -Id "AICO-013" -Owner "frontend" -MaxChars 12000 -RequiredFiles $required

    if ($context -notmatch '===== FILE: index\.html =====') {
        throw "Writable context did not include index.html as a required file."
    }

    if ($context -notmatch 'REQUIRED_INDEX_SENTINEL') {
        throw "Writable context did not include the current index.html content."
    }

    $secretBlocked = $false
    try {
        & $resolver -ProjectPath $tempRoot -SourceText @("Update .env as part of this implementation.") -PolicyPath $policy | Out-Null
    }
    catch {
        if ($_.Exception.Message -match "secret-sensitive|prohibited by policy") {
            $secretBlocked = $true
        }
        else {
            throw
        }
    }

    if (-not $secretBlocked) {
        throw "Required-file resolver did not block an explicitly requested secret-sensitive file."
    }

    $negatedSecret = @(& $resolver -ProjectPath $tempRoot -SourceText @("Do not modify .env during this implementation.") -PolicyPath $policy)
    if ($negatedSecret.Count -ne 0) {
        throw "Required-file resolver treated a negated secret reference as required context."
    }

    $ambiguousRoot = Join-Path $tempRoot "ambiguous"
    Write-NoBom (Join-Path $ambiguousRoot "a\index.html") "A"
    Write-NoBom (Join-Path $ambiguousRoot "b\index.html") "B"

    & git -C $ambiguousRoot init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git init failed for ambiguous fixture." }
    & git -C $ambiguousRoot config user.email "aico-test@example.invalid"
    & git -C $ambiguousRoot config user.name "AI Company OS Test"
    & git -C $ambiguousRoot add .
    & git -C $ambiguousRoot commit -m "ambiguous fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ambiguous fixture commit failed." }

    $ambiguousBlocked = $false
    try {
        & $resolver -ProjectPath $ambiguousRoot -SourceText @("Modify index.html.") -PolicyPath $policy | Out-Null
    }
    catch {
        if ($_.Exception.Message -match "ambiguous") {
            $ambiguousBlocked = $true
        }
        else {
            throw
        }
    }

    if (-not $ambiguousBlocked) {
        throw "Required-file resolver guessed when an explicit basename was ambiguous."
    }

    Write-Host "PASS: writable required-file context resolution" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
