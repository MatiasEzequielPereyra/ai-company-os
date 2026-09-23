param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("aico-e2e-code-change-" + [Guid]::NewGuid().ToString("N"))

try {
    foreach ($relative in @(
        "scripts",
        "tasks",
        "src",
        "schemas",
        ".codex\state",
        ".codex\runtime",
        "docs\engineering\results",
        "docs\engineering\reviews",
        "docs\engineering\qa",
        "docs\engineering\security",
        "docs\engineering\final-approvals"
    )) {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot $relative) | Out-Null
    }

    foreach ($name in @(
        "new-task.ps1",
        "update-task.ps1",
        "advance-task.ps1",
        "submit-task-result.ps1",
        "review-task.ps1",
        "qa-task.ps1",
        "security-task.ps1",
        "finalize-task.ps1",
        "sync-company-state.ps1",
        "write-operational-event.ps1",
        "validate-json-contract.ps1",
        "validate-artifacts.ps1"
    )) {
        Copy-Item (Join-Path $repoRoot ("scripts\" + $name)) (Join-Path $tempRoot ("scripts\" + $name)) -Force
    }

    foreach ($schema in @("task.schema.json","company-state.schema.json")) {
        Copy-Item (Join-Path $repoRoot ("schemas\" + $schema)) (Join-Path $tempRoot ("schemas\" + $schema)) -Force
    }
    Copy-Item (Join-Path $repoRoot ".codex\workflow-profiles.json") (Join-Path $tempRoot ".codex\workflow-profiles.json") -Force

    $sourcePath = Join-Path $tempRoot "src\calculator.ps1"
    $buggySource = @(
        'function Add-Numbers {',
        '    param([int]$A,[int]$B)',
        '    return $A - $B',
        '}'
    ) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText($sourcePath,$buggySource,(New-Object System.Text.UTF8Encoding($false)))

    $tasksPath = Join-Path $tempRoot "tasks"
    & (Join-Path $tempRoot "scripts\new-task.ps1") -Title "Fix calculator addition" -Owner backend -Priority P1 -WorkflowProfile standard -Objective "Make Add-Numbers return the sum of its two inputs." -TasksPath $tasksPath

    & (Join-Path $tempRoot "scripts\advance-task.ps1") -Id AICO-001 -Status READY -Actor "engineering-manager" -Reason "Fixture acceptance criteria are explicit." -TasksPath $tasksPath
    & (Join-Path $tempRoot "scripts\advance-task.ps1") -Id AICO-001 -Status ACTIVE -Actor "engineering-manager" -Reason "Implementation authorized for isolated fixture." -TasksPath $tasksPath

    $implementation = Get-Content $sourcePath -Raw -Encoding UTF8
    $implementation = $implementation.Replace('return $A - $B','return $A + $B')
    [System.IO.File]::WriteAllText($sourcePath,$implementation,(New-Object System.Text.UTF8Encoding($false)))

    . $sourcePath
    $actual = Add-Numbers 2 3
    if ($actual -ne 5) { throw "Real code verification failed. Expected 5, got $actual" }

    & (Join-Path $tempRoot "scripts\submit-task-result.ps1") -ProjectPath $tempRoot -Id AICO-001 -Outcome COMPLETED -Summary "Fixed calculator addition." -ChangedArtifacts "src/calculator.ps1" -Verification "Executed Add-Numbers 2 3 and received 5." -Decisions "NONE" -Blockers "NONE" -RecommendedNext "REVIEW"

    & (Join-Path $tempRoot "scripts\review-task.ps1") -ProjectPath $tempRoot -Id AICO-001 -Recommendation APPROVE -Reviewer "engineering-manager" -Findings "Implementation is scoped and verified." -Verification "Reviewed source diff and execution evidence."

    & (Join-Path $tempRoot "scripts\qa-task.ps1") -ProjectPath $tempRoot -Id AICO-001 -Outcome PASS -Evidence "Add-Numbers 2 3 returned 5." -Findings "Acceptance behavior verified."

    & (Join-Path $tempRoot "scripts\security-task.ps1") -ProjectPath $tempRoot -Id AICO-001 -Outcome NOT_APPLICABLE -Evidence "Pure arithmetic change with no security boundary." -Findings "No meaningful security surface."

    & (Join-Path $tempRoot "scripts\finalize-task.ps1") -ProjectPath $tempRoot -Id AICO-001 -Decision APPROVE -Verification "Objective satisfied; review and QA passed; security explicitly not applicable."

    $sprintPath = Join-Path $tempRoot ".codex\state\current-sprint.md"
    & (Join-Path $tempRoot "scripts\sync-company-state.ps1") -TasksPath $tasksPath -SprintPath $sprintPath

    & (Join-Path $tempRoot "scripts\validate-artifacts.ps1") -ProjectPath $tempRoot | Out-Null

    $task = Get-Content (Join-Path $tasksPath "AICO-001.md") -Raw -Encoding UTF8
    if ($task -notmatch '(?m)^Status:\s*DONE\r?$') { throw "E2E task did not reach DONE." }

    $statePath = Join-Path $tempRoot ".codex\state\company-state.json"
    if (-not (Test-Path $statePath)) { throw "Canonical company-state.json was not generated." }
    $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$state.done_count -ne 1) { throw "Expected one DONE task in company state." }

    foreach ($artifact in @(
        "docs\engineering\results\AICO-001-result-001.md",
        "docs\engineering\reviews\AICO-001-review-001.md",
        "docs\engineering\qa\AICO-001-qa.md",
        "docs\engineering\security\AICO-001-security.md",
        "docs\engineering\final-approvals\AICO-001-final.md"
    )) {
        if (-not (Test-Path (Join-Path $tempRoot $artifact))) { throw "Missing E2E artifact: $artifact" }
    }

    $metricsPath = Join-Path $tempRoot ".codex\runtime\metrics\events.jsonl"
    if (-not (Test-Path $metricsPath)) { throw "Lifecycle metrics were not recorded." }
    $transitionEvents = @(Get-Content $metricsPath -Encoding UTF8 | Where-Object { $_ -match '"event_type":"task_transition"' })
    if ($transitionEvents.Count -lt 6) { throw "Expected lifecycle transition telemetry, got $($transitionEvents.Count) events." }

    Write-Host "PASS: end-to-end real code change workflow test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
