param(
    [string]$ProjectPath = ".",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Read-Section {
    param([string]$Content,[string]$Section)
    $pattern = "(?ms)^## " + [regex]::Escape($Section) + "\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

$root=(Resolve-Path $ProjectPath).Path
$tasksPath=Join-Path $root "tasks"
$dispatchDir=Join-Path $root "docs\engineering\dispatch"

if(-not(Test-Path $tasksPath)){throw "Tasks directory not found: $tasksPath"}
if(-not(Test-Path $dispatchDir)){New-Item -ItemType Directory -Force -Path $dispatchDir|Out-Null}

$ready=@()

Get-ChildItem $tasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $content=Get-Content $_.FullName -Raw -Encoding UTF8
    $status=Read-Field $content "Status"
    if($status -eq "READY"){
        $ready += [PSCustomObject]@{
            File=$_.FullName
            Content=$content
            ID=Read-Field $content "ID"
            Owner=Read-Field $content "Owner"
            Priority=Read-Field $content "Priority"
            WorkRequest=Read-Field $content "Work request"
            Objective=Read-Section $content "Objective"
            Context=Read-Section $content "Context"
            Acceptance=Read-Section $content "Acceptance Criteria"
            Dependencies=Read-Section $content "Dependencies"
            Testing=Read-Section $content "Testing Requirements"
        }
    }
}

if($ready.Count -eq 0){
    Write-Host "No READY tasks found." -ForegroundColor Yellow
    exit 0
}

$now=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$generated=@()

foreach($task in ($ready|Sort-Object ID)){
    $packetPath=Join-Path $dispatchDir ($task.ID + ".md")
    $agentInstructions=".codex/agents/" + $task.Owner + ".md"
    if($task.Owner -eq "engineering-manager"){
        $agentInstructions=".codex/agents/engineering-manager.md"
    }

    $lines=@(
        "# Execution Request - $($task.ID)",
        "",
        "Generated: $now",
        "Status: PREPARED",
        "",
        "## Assignment",
        "",
        "Task: $($task.ID)",
        "Owner: $($task.Owner)",
        "Priority: $($task.Priority)",
        "Work request: $($task.WorkRequest)",
        "",
        "## Objective",
        "",
        $task.Objective,
        "",
        "## Context",
        "",
        $task.Context,
        "",
        "## Expected Output",
        "",
        "- Complete the role-owned deliverable described by the task.",
        "- Record evidence, blockers and unresolved questions.",
        "- Return changed artifacts and verification results.",
        "",
        "## Acceptance Criteria",
        "",
        $task.Acceptance,
        "",
        "## Dependencies",
        "",
        $task.Dependencies,
        "",
        "## Testing Requirements",
        "",
        $task.Testing,
        "",
        "## Required Context",
        "",
        "- AGENTS.md",
        "- $agentInstructions",
        "- tasks/$($task.ID).md",
        "- .codex/state/company-state.md",
        "- .codex/state/current-sprint.md",
        "- docs/engineering/project-intake.md",
        "- docs/product/product-intake.md",
        "- docs/architecture/architecture-intake.md",
        "- docs/operations/operations-intake.md",
        "",
        "## Execution Restrictions",
        "",
        "- Stay within the task objective and role authority.",
        "- Do not invent product requirements or architecture decisions.",
        "- Do not bypass unresolved blockers or dependencies.",
        "- Do not declare completion without evidence.",
        "- READY status alone is not implementation authorization.",
        "",
        "## Result Contract",
        "",
        "Return:",
        "1. Work completed.",
        "2. Files or documents changed.",
        "3. Verification performed.",
        "4. Decisions made within role authority.",
        "5. Blockers or unresolved questions.",
        "6. Recommended next lifecycle transition."
    )

    Write-Utf8NoBom $packetPath ($lines -join [Environment]::NewLine)
    $generated += $task.ID
}

Write-Host "Execution packets prepared:" -ForegroundColor Green
$generated|ForEach-Object{Write-Host $_}

if($Apply){
    $advance=Join-Path $PSScriptRoot "advance-task.ps1"
    if(-not(Test-Path $advance)){throw "advance-task.ps1 not found: $advance"}

    foreach($task in ($ready|Sort-Object ID)){
        & $advance -Id $task.ID -Status ACTIVE -Actor "engineering-manager" -Reason "Execution packet prepared and dispatch explicitly applied." -Evidence ("Execution request: docs/engineering/dispatch/" + $task.ID + ".md") -TasksPath $tasksPath
    }

    Write-Host ""
    Write-Host "Dispatch applied: $($ready.Count) task(s) moved to ACTIVE." -ForegroundColor Green
}
else{
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply to activate prepared READY tasks." -ForegroundColor Cyan
}
