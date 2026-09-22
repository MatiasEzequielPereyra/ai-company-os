param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$required = @(
    "scripts\run-agent-task.ps1",
    "scripts\run-active-agents.ps1",
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

$runner = Get-Content (Join-Path $repoRoot "scripts\run-agent-task.ps1") -Raw
if ($runner -notmatch '"--sandbox","read-only"') {
    throw "Agent runner must use read-only sandbox for audit execution"
}
if ($runner -notmatch '"--output-schema"') {
    throw "Agent runner must require structured output"
}
if ($runner -notmatch 'submit-task-result\.ps1') {
    throw "Agent runner must feed the Result Intake Engine"
}


$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $repoRoot "scripts\run-agent-task.ps1"),
    [ref]$null,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw ("run-agent-task.ps1 has PowerShell parse errors: " + (($parseErrors | ForEach-Object { $_.Message }) -join "; "))
}

$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $repoRoot "scripts\run-active-agents.ps1"),
    [ref]$null,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw ("run-active-agents.ps1 has PowerShell parse errors: " + (($parseErrors | ForEach-Object { $_.Message }) -join "; "))
}

Write-Host "PASS: agent runtime contract test" -ForegroundColor Green
