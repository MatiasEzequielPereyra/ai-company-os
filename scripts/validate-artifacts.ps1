param(
    [string]$ProjectPath = "."
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Read-Section {
    param([string]$Content,[string]$Section)
    $pattern = "(?ms)^## " + [regex]::Escape($Section) + "\s*\r?\n\s*\r?\n(.*?)(?=\r?\n\r?\n---|\r?\n\r?\n##|\z)"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Read-Dependencies {
    param([string]$Content)
    $section = Read-Section $Content "Dependencies"
    if ([string]::IsNullOrWhiteSpace($section) -or $section -eq "-") { return @() }
    return @(
        $section -split "\r?\n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match "^-\s+AICO-\d+$" } |
            ForEach-Object { $_ -replace "^-\s+", "" }
    )
}

$root = (Resolve-Path $ProjectPath).Path
$validator = Join-Path $PSScriptRoot "validate-json-contract.ps1"
$taskSchema = Join-Path $root "schemas\task.schema.json"
$companyStateSchema = Join-Path $root "schemas\company-state.schema.json"
$profilesPath = Join-Path $root ".codex\workflow-profiles.json"

foreach ($required in @($validator,$taskSchema,$profilesPath)) {
    if (-not (Test-Path $required -PathType Leaf)) { throw "Required validation artifact missing: $required" }
}

try { $profiles = Get-Content $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "Invalid workflow profile configuration: $($_.Exception.Message)" }

$profileNames = @($profiles.profiles.PSObject.Properties.Name)
if ($profileNames.Count -eq 0) { throw "No workflow profiles are configured." }
if ($profileNames -notcontains [string]$profiles.default_profile) { throw "default_profile does not reference a configured workflow profile." }

$tasksPath = Join-Path $root "tasks"
if (-not (Test-Path $tasksPath)) { throw "Tasks directory not found: $tasksPath" }

$tempDir = Join-Path $root ".codex\runtime\validation"
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Force -Path $tempDir | Out-Null }

$validated = 0
$ids = @{}
$records = @()
$expectedPhaseByStatus = @{
    BACKLOG = "PLANNING"
    READY = "PLANNING"
    ACTIVE = "IMPLEMENTATION"
    REVIEW = "CODE_REVIEW"
    QA = "QA"
    SECURITY = "SECURITY"
    DONE = "DONE"
    BLOCKED = "BLOCKED"
}

foreach ($file in Get-ChildItem $tasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $id = Read-Field $content "ID"
    if ([string]::IsNullOrWhiteSpace($id)) { $id = $file.BaseName }
    if ($id -ne $file.BaseName) { throw "Task ID $id does not match filename $($file.BaseName)." }

    if ($ids.ContainsKey($id)) { throw "Duplicate task ID: $id" }
    $ids[$id] = $true

    $title = if ($content -match "(?m)^#\s+(.+)$") { $Matches[1].Trim() } else { "" }
    if ($title -match ("^" + [regex]::Escape($id) + "\s+-\s+(.+)$")) { $title = $Matches[1].Trim() }

    $profile = Read-Field $content "Workflow profile"
    if ([string]::IsNullOrWhiteSpace($profile)) { $profile = [string]$profiles.default_profile }

    $normalized = [ordered]@{
        id = $id
        title = $title
        status = Read-Field $content "Status"
        priority = Read-Field $content "Priority"
        owner = Read-Field $content "Owner"
        created = Read-Field $content "Created"
        updated = Read-Field $content "Updated"
        workflow_phase = Read-Field $content "Workflow phase"
        workflow_profile = $profile
        objective = Read-Section $content "Objective"
        acceptance_criteria = Read-Section $content "Acceptance Criteria"
        dependencies = @(Read-Dependencies $content)
    }

    if (-not $expectedPhaseByStatus.ContainsKey([string]$normalized.status)) { throw "Unsupported task status in ${id}: $($normalized.status)" }
    $expectedPhase = [string]$expectedPhaseByStatus[[string]$normalized.status]
    if ([string]$normalized.workflow_phase -ne $expectedPhase) {
        throw "Task $id has Workflow phase $($normalized.workflow_phase) but status $($normalized.status) requires $expectedPhase."
    }
    if ([string]$normalized.acceptance_criteria -notmatch '(?m)^-\s+\[[ xX]\]') {
        throw "Task $id must contain checklist-based Acceptance Criteria."
    }

    $records += [PSCustomObject]$normalized

    $tempJson = Join-Path $tempDir ($id + ".normalized.json")
    [System.IO.File]::WriteAllText(
        $tempJson,
        ($normalized | ConvertTo-Json -Depth 10),
        (New-Object System.Text.UTF8Encoding($false))
    )

    & $validator -JsonPath $tempJson -SchemaPath $taskSchema | Out-Null
    $validated++
}

foreach ($record in $records) {
    foreach ($dependency in @($record.dependencies)) {
        if (-not $ids.ContainsKey([string]$dependency)) { throw "Task $($record.id) references missing dependency $dependency." }
    }
}

$companyStateJson = Join-Path $root ".codex\state\company-state.json"
if (Test-Path $companyStateJson) {
    if (-not (Test-Path $companyStateSchema)) { throw "Company state schema missing: $companyStateSchema" }
    & $validator -JsonPath $companyStateJson -SchemaPath $companyStateSchema | Out-Null
    $state = Get-Content $companyStateJson -Raw -Encoding UTF8 | ConvertFrom-Json

    $expectedActiveIds = @($records | Where-Object { $_.status -eq "ACTIVE" } | ForEach-Object { $_.id } | Sort-Object)
    $expectedBlockedIds = @($records | Where-Object { $_.status -eq "BLOCKED" } | ForEach-Object { $_.id } | Sort-Object)
    $expectedDoneCount = @($records | Where-Object { $_.status -eq "DONE" }).Count

    if ([int]$state.task_count -ne $records.Count) { throw "company-state task_count does not match authoritative tasks." }
    if ([int]$state.active_count -ne $expectedActiveIds.Count) { throw "company-state active_count does not match authoritative tasks." }
    if ([int]$state.blocked_count -ne $expectedBlockedIds.Count) { throw "company-state blocked_count does not match authoritative tasks." }
    if ([int]$state.done_count -ne $expectedDoneCount) { throw "company-state done_count does not match authoritative tasks." }

    $actualActiveIds = @($state.active_task_ids | ForEach-Object { [string]$_ } | Sort-Object)
    $actualBlockedIds = @($state.blocked_task_ids | ForEach-Object { [string]$_ } | Sort-Object)
    if (($actualActiveIds -join "|") -ne ($expectedActiveIds -join "|")) { throw "company-state active_task_ids do not match authoritative tasks." }
    if (($actualBlockedIds -join "|") -ne ($expectedBlockedIds -join "|")) { throw "company-state blocked_task_ids do not match authoritative tasks." }
}

Write-Host "PASS: canonical artifact validation" -ForegroundColor Green
Write-Host "Tasks validated: $validated"
Write-Host "Workflow profiles: $($profileNames -join ', ')"

[PSCustomObject]@{
    TasksValidated = $validated
    Profiles = $profileNames
    CompanyStateValidated = (Test-Path $companyStateJson)
}
