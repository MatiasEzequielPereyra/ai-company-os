param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [Parameter(Mandatory = $true)]
    [ValidateSet("APPROVE","CHANGES_REQUIRED")]
    [string]$Recommendation,

    [Parameter(Mandatory = $true)]
    [string]$Reviewer,

    [string]$Findings = "NONE",

    [string]$Verification = "NOT_RUN",

    [string]$ProjectPath = "."
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

$root=(Resolve-Path $ProjectPath).Path
$tasksPath=Join-Path $root "tasks"
$taskPath=Join-Path $tasksPath ($Id + ".md")

if(-not(Test-Path $taskPath)){throw "Task not found: $taskPath"}

$taskContent=Get-Content $taskPath -Raw
$status=Read-Field $taskContent "Status"
$owner=Read-Field $taskContent "Owner"

if($status -ne "REVIEW"){
    throw "Task $Id must be REVIEW to submit a review. Current status: $status"
}

$reviewDir=Join-Path $root "docs\engineering\reviews"
if(-not(Test-Path $reviewDir)){New-Item -ItemType Directory -Force -Path $reviewDir|Out-Null}

$existing=@(Get-ChildItem $reviewDir -Filter ($Id + "-review-*.md") -File -ErrorAction SilentlyContinue | ForEach-Object {
    if($_.BaseName -match [regex]::Escape($Id) + '-review-(\d+)$'){[int]$Matches[1]}
})
$next=1
if($existing.Count -gt 0){$next=[int](($existing|Measure-Object -Maximum).Maximum)+1}
$sequence=$next.ToString().PadLeft(3,'0')
$now=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$reviewPath=Join-Path $reviewDir ($Id + "-review-" + $sequence + ".md")

$lines=@(
    "# Review - $Id",
    "",
    "Recorded: $now",
    "Task: $Id",
    "Task owner: $owner",
    "Reviewer: $Reviewer",
    "Recommendation: $Recommendation",
    "",
    "## Findings",
    "",
    $Findings,
    "",
    "## Verification",
    "",
    $Verification,
    "",
    "## Review Rules",
    "",
    "- Review is independent evidence for the REVIEW gate.",
    "- APPROVE does not imply QA, security or final approval.",
    "- CHANGES_REQUIRED returns the task to READY for corrective work."
)

Write-Utf8NoBom $reviewPath ($lines -join [Environment]::NewLine)

$updateScript=Join-Path $PSScriptRoot "update-task.ps1"
$advanceScript=Join-Path $PSScriptRoot "advance-task.ps1"
if(-not(Test-Path $updateScript)){throw "update-task.ps1 not found: $updateScript"}
if(-not(Test-Path $advanceScript)){throw "advance-task.ps1 not found: $advanceScript"}

$relativeReview="docs/engineering/reviews/" + (Split-Path $reviewPath -Leaf)
& $updateScript -Id $Id -Evidence ("Review recorded: " + $relativeReview) -Note ("Review recommendation: " + $Recommendation + ". " + $Findings) -TasksPath $tasksPath

if($Recommendation -eq "APPROVE"){
    & $advanceScript -Id $Id -Status QA -Actor $Reviewer -Reason "Independent review approved." -Evidence ("Review artifact: " + $relativeReview) -TasksPath $tasksPath
}
else{
    & $advanceScript -Id $Id -Status READY -Actor $Reviewer -Reason ("Review requested changes. " + $Findings) -Evidence ("Review artifact: " + $relativeReview) -TasksPath $tasksPath
}

Write-Host "Review recorded:" -ForegroundColor Green
Write-Host $reviewPath
Write-Host "Recommendation: $Recommendation"
