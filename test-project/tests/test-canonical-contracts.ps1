param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$validator = Join-Path $repoRoot "scripts\validate-json-contract.ps1"
$schemaPath = Join-Path $repoRoot "schemas\agent-result.schema.json"
$profilesPath = Join-Path $repoRoot ".codex\workflow-profiles.json"

foreach ($path in @($validator,$schemaPath,$profilesPath)) {
    if (-not (Test-Path $path)) { throw "Missing contract artifact: $path" }
}

$tempRoot = Join-Path $env:TEMP ("aico-contract-" + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $valid = [ordered]@{
        outcome = "COMPLETED"
        summary = "Contract fixture"
        report_markdown = "# Report"
        verification = "Verified locally"
        decisions = "NONE"
        blockers = "NONE"
        recommended_next = "REVIEW"
    }
    $validPath = Join-Path $tempRoot "valid.json"
    [System.IO.File]::WriteAllText($validPath,($valid | ConvertTo-Json -Depth 10),(New-Object System.Text.UTF8Encoding($false)))
    & $validator -JsonPath $validPath -SchemaPath $schemaPath | Out-Null

    $invalid = [ordered]@{
        outcome = "COMPLETED"
        report_markdown = "# Missing summary"
        verification = "NONE"
        decisions = "NONE"
        blockers = "NONE"
        recommended_next = "REVIEW"
    }
    $invalidPath = Join-Path $tempRoot "invalid.json"
    [System.IO.File]::WriteAllText($invalidPath,($invalid | ConvertTo-Json -Depth 10),(New-Object System.Text.UTF8Encoding($false)))

    $rejected = $false
    try {
        & $validator -JsonPath $invalidPath -SchemaPath $schemaPath | Out-Null
    }
    catch {
        if ($_.Exception.Message -match "summary") { $rejected = $true } else { throw }
    }
    if (-not $rejected) { throw "Schema validator accepted a result missing required summary." }

    $profiles = Get-Content $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$profiles.default_profile -ne "standard") { throw "standard must remain the backward-compatible default profile." }
    foreach ($name in @("lightweight","standard","high-assurance")) {
        if ($null -eq $profiles.profiles.PSObject.Properties[$name]) { throw "Missing workflow profile: $name" }
    }

    $router = Get-Content (Join-Path $repoRoot "scripts\provider-router.ps1") -Raw -Encoding UTF8
    if ($router -notmatch "validate-json-contract\.ps1") { throw "Provider router must locally validate structured output." }
    if ($router -notmatch "provider_attempt") { throw "Provider router must emit provider attempt metrics." }

    $gemini = Get-Content (Join-Path $repoRoot "scripts\providers\invoke-gemini.ps1") -Raw -Encoding UTF8
    if ($gemini -notmatch "Test-TransientGeminiError") { throw "Gemini adapter must classify transient failures." }
    if ($gemini -notmatch "\$maxAttempts = 3") { throw "Gemini adapter must retry transient failures." }

    $parallel = Get-Content (Join-Path $repoRoot "scripts\run-active-agents.ps1") -Raw -Encoding UTF8
    if ($parallel -notmatch "Shared-workspace -Parallel execution is only allowed") { throw "Parallel runtime guard is missing." }

    $workspace = Get-Content (Join-Path $repoRoot "scripts\new-agent-workspace.ps1") -Raw -Encoding UTF8
    if ($workspace -notmatch "git -C \$root worktree add") { throw "Writable isolation must use Git worktrees." }

    Write-Host "PASS: canonical contracts and runtime safety test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
