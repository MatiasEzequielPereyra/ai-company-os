param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [Parameter(Mandatory = $true)]
    [ValidateSet("BACKLOG", "READY", "ACTIVE", "REVIEW", "QA", "SECURITY", "DONE", "BLOCKED")]
    [string]$Status,

    [string]$Actor = "engineering-manager",
    [string]$Reason = "Status transition requested.",
    [string]$Evidence = "",
    [string]$TasksPath = "tasks"
)

$ErrorActionPreference = "Stop"

$validTransitions = @{
    "BACKLOG" = @("READY", "BLOCKED")
    "READY" = @("ACTIVE", "BACKLOG", "BLOCKED")
    "ACTIVE" = @("REVIEW", "BLOCKED")
    "REVIEW" = @("QA", "READY", "BLOCKED")
    "QA" = @("SECURITY", "DONE", "READY", "BLOCKED")
    "SECURITY" = @("DONE", "READY", "BLOCKED")
    "BLOCKED" = @("READY", "BACKLOG")
    "DONE" = @("BACKLOG", "BLOCKED")
}

function Replace-LineValue {
    param(
        [string]$Content,
        [string]$Key,
        [string]$Value
    )

    $escapedKey = [regex]::Escape($Key)
    $line = $Key + ": " + $Value

    if ($Content -match ("(?m)^" + $escapedKey + ":.*$")) {
        return [regex]::Replace($Content, ("(?m)^" + $escapedKey + ":.*$"), $line)
    }

    return $Content
}

function Append-SectionLine {
    param(
        [string]$Content,
        [string]$Section,
        [string]$Line
    )

    $pattern = "(?ms)(## " + [regex]::Escape($Section) + "\s*\n)(.*?)(\n---|\z)"

    if ($Content -match $pattern) {
        return [regex]::Replace($Content, $pattern, {
            param($match)

            $header = $match.Groups[1].Value
            $body = $match.Groups[2].Value.TrimEnd()
            $tail = $match.Groups[3].Value
            $nl = [Environment]::NewLine

            return $header + $body + $nl + "- " + $Line + $tail
        })
    }

    $nl = [Environment]::NewLine
    return $Content + $nl + $nl + "## " + $Section + $nl + $nl + "- " + $Line + $nl
}

function Read-Field {
    param(
        [string]$Content,
        [string]$Key
    )

    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"

    if ($Content -match $pattern) {
        return $Matches[1].Trim()
    }

    return ""
}

function Read-Section {
    param(
        [string]$Content,
        [string]$Section
    )

    $pattern = "(?ms)^## " + [regex]::Escape($Section) + "\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)"

    if ($Content -match $pattern) {
        return $Matches[1].Trim()
    }

    return ""
}

function Get-TaskDependencies {
    param([string]$Content)

    $section = Read-Section -Content $Content -Section "Dependencies"

    if ([string]::IsNullOrWhiteSpace($section)) {
        return @()
    }

    return @(
        $section -split '\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^-\s+AICO-\d+$' } |
            ForEach-Object { $_ -replace '^-\s+', '' }
    )
}

function Get-LatestArtifact {
    param(
        [string]$Directory,
        [string]$Filter
    )

    if (-not (Test-Path $Directory)) {
        return $null
    }

    return Get-ChildItem $Directory -Filter $Filter -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Assert-DependenciesDone {
    param(
        [string]$Content,
        [string]$TasksPath,
        [string]$TaskId
    )

    foreach ($dependency in @(Get-TaskDependencies -Content $Content)) {
        $dependencyPath = Join-Path $TasksPath ($dependency + ".md")

        if (-not (Test-Path $dependencyPath)) {
            throw ("Transition guard: dependency not found for {0}: {1}" -f $TaskId, $dependency)
        }

        $dependencyContent = Get-Content $dependencyPath -Raw -Encoding UTF8
        $dependencyStatus = Read-Field -Content $dependencyContent -Key "Status"

        if ($dependencyStatus -ne "DONE") {
            throw ("Transition guard: dependency {0} must be DONE before {1} can advance. Current status: {2}" -f $dependency, $TaskId, $dependencyStatus)
        }
    }
}

function Assert-PreparedForReady {
    param(
        [string]$Content,
        [string]$TaskId
    )

    $owner = Read-Field -Content $Content -Key "Owner"
    $objective = Read-Section -Content $Content -Section "Objective"
    $acceptance = Read-Section -Content $Content -Section "Acceptance Criteria"

    if ([string]::IsNullOrWhiteSpace($owner)) {
        throw ("Transition guard: {0} is missing Owner." -f $TaskId)
    }

    if ([string]::IsNullOrWhiteSpace($objective) -or $objective -eq "-") {
        throw ("Transition guard: {0} is missing Objective." -f $TaskId)
    }


    if ([string]::IsNullOrWhiteSpace($acceptance) -or $acceptance -eq "-") {
        throw ("Transition guard: {0} is missing Acceptance Criteria." -f $TaskId)
    }
}

function Assert-ArtifactField {
    param(
        [string]$Path,
        [string]$Field,
        [string[]]$AllowedValues,
        [string]$Description
    )

    if (-not (Test-Path $Path)) {
        throw ("Transition guard: required {0} artifact is missing: {1}" -f $Description, $Path)
    }

    $artifactContent = Get-Content $Path -Raw -Encoding UTF8
    $value = Read-Field -Content $artifactContent -Key $Field

    if ($AllowedValues -notcontains $value) {
        throw ("Transition guard: {0} {1} must be one of [{2}]. Current value: {3}" -f $Description, $Field, ($AllowedValues -join ", "), $value)
    }
}

$scriptProjectRoot = Split-Path -Parent $PSScriptRoot

if ([System.IO.Path]::IsPathRooted($TasksPath)) {
    $resolvedTasksPath = (Resolve-Path $TasksPath).Path
    $projectRoot = Split-Path -Parent $resolvedTasksPath
}
else {
    $projectRoot = $scriptProjectRoot
    $resolvedTasksPath = Join-Path $projectRoot $TasksPath
}

$filePath = Join-Path $resolvedTasksPath ($Id + ".md")

if (-not (Test-Path $filePath)) {
    throw "Task not found: $filePath"
}

$content = Get-Content -Path $filePath -Raw -Encoding UTF8
$currentStatus = Read-Field -Content $content -Key "Status"

if ([string]::IsNullOrWhiteSpace($currentStatus)) {
    $currentStatus = "UNKNOWN"
}

if (-not $validTransitions.ContainsKey($currentStatus)) {
    throw "Invalid current status '$currentStatus' in $filePath"
}

if ($validTransitions[$currentStatus] -notcontains $Status) {
    throw "Invalid transition: $currentStatus -> $Status. Allowed: $($validTransitions[$currentStatus] -join ', ')"
}

# Central transition guards. Every lifecycle script ultimately calls this file,
# so direct status changes cannot bypass dependency or gate evidence.
if ($Status -in @("READY", "ACTIVE")) {
    Assert-PreparedForReady -Content $content -TaskId $Id
    Assert-DependenciesDone -Content $content -TasksPath $resolvedTasksPath -TaskId $Id
}

if ($Status -eq "ACTIVE") {
    $dispatchPath = Join-Path $projectRoot ("docs\engineering\dispatch\" + $Id + ".md")

    if (-not (Test-Path $dispatchPath)) {
        throw ("Transition guard: {0} cannot become ACTIVE without a prepared dispatch packet: {1}" -f $Id, $dispatchPath)
    }
}

if ($Status -eq "REVIEW") {
    $resultDir = Join-Path $projectRoot "docs\engineering\results"
    $latestResult = Get-LatestArtifact -Directory $resultDir -Filter ($Id + "-result-*.md")

    if ($null -eq $latestResult) {
        throw ("Transition guard: {0} cannot enter REVIEW without a task result artifact." -f $Id)
    }

    Assert-ArtifactField -Path $latestResult.FullName -Field "Outcome" -AllowedValues @("COMPLETED") -Description "task result"
}

if ($Status -eq "QA") {
    $reviewDir = Join-Path $projectRoot "docs\engineering\reviews"
    $latestReview = Get-LatestArtifact -Directory $reviewDir -Filter ($Id + "-review-*.md")

    if ($null -eq $latestReview) {
        throw ("Transition guard: {0} cannot enter QA without a review artifact." -f $Id)
    }

    Assert-ArtifactField -Path $latestReview.FullName -Field "Recommendation" -AllowedValues @("APPROVE") -Description "review"
}

if ($Status -eq "SECURITY") {
    $qaPath = Join-Path $projectRoot ("docs\engineering\qa\" + $Id + "-qa.md")
    Assert-ArtifactField -Path $qaPath -Field "Outcome" -AllowedValues @("PASS") -Description "QA"
}

if ($Status -eq "DONE") {
    $qaPath = Join-Path $projectRoot ("docs\engineering\qa\" + $Id + "-qa.md")
    $securityPath = Join-Path $projectRoot ("docs\engineering\security\" + $Id + "-security.md")
    $finalPath = Join-Path $projectRoot ("docs\engineering\final-approvals\" + $Id + "-final.md")

    Assert-ArtifactField -Path $qaPath -Field "Outcome" -AllowedValues @("PASS") -Description "QA"
    Assert-ArtifactField -Path $securityPath -Field "Outcome" -AllowedValues @("PASS", "NOT_APPLICABLE") -Description "security"
    Assert-ArtifactField -Path $finalPath -Field "Decision" -AllowedValues @("APPROVE") -Description "final approval"
}

if ($Status -eq "READY") {
    if ($currentStatus -eq "REVIEW") {
        $reviewDir = Join-Path $projectRoot "docs\engineering\reviews"
        $latestReview = Get-LatestArtifact -Directory $reviewDir -Filter ($Id + "-review-*.md")

        if ($null -eq $latestReview) {
            throw "Transition guard: REVIEW -> READY requires a review artifact."
        }

        Assert-ArtifactField -Path $latestReview.FullName -Field "Recommendation" -AllowedValues @("CHANGES_REQUIRED") -Description "review"
    }
    elseif ($currentStatus -eq "QA") {
        $qaPath = Join-Path $projectRoot ("docs\engineering\qa\" + $Id + "-qa.md")
        Assert-ArtifactField -Path $qaPath -Field "Outcome" -AllowedValues @("FAIL") -Description "QA"
    }
    elseif ($currentStatus -eq "SECURITY") {
        $securityPath = Join-Path $projectRoot ("docs\engineering\security\" + $Id + "-security.md")
        $finalPath = Join-Path $projectRoot ("docs\engineering\final-approvals\" + $Id + "-final.md")

        if (Test-Path $finalPath) {
            Assert-ArtifactField -Path $finalPath -Field "Decision" -AllowedValues @("REJECT") -Description "final approval"
        }
        else {
            Assert-ArtifactField -Path $securityPath -Field "Outcome" -AllowedValues @("FAIL") -Description "security"
        }
    }
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$content = Replace-LineValue -Content $content -Key "Status" -Value $Status
$content = Replace-LineValue -Content $content -Key "Updated" -Value $now

if ($Status -eq "ACTIVE") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "IMPLEMENTATION"
}
elseif ($Status -eq "REVIEW") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "CODE_REVIEW"
}
elseif ($Status -eq "QA") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "QA"
}
elseif ($Status -eq "SECURITY") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "SECURITY"
}
elseif ($Status -eq "DONE") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "DONE"
}
elseif ($Status -eq "BLOCKED") {
    $content = Replace-LineValue -Content $content -Key "Workflow phase" -Value "BLOCKED"
}

$logLine = $now + " - " + $Actor + " - " + $currentStatus + " -> " + $Status + " - " + $Reason
$content = Append-SectionLine -Content $content -Section "Transition Log" -Line $logLine

if (-not [string]::IsNullOrWhiteSpace($Evidence)) {
    $evidenceLine = $now + " - " + $Evidence
    $content = Append-SectionLine -Content $content -Section "Evidence" -Line $evidenceLine
}

[System.IO.File]::WriteAllText(
    $filePath,
    $content,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Task advanced:" -ForegroundColor Green
Write-Host ($Id + ": " + $currentStatus + " -> " + $Status)
