param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [Parameter(Mandatory = $true)]
    [ValidateSet("COMPLETED","BLOCKED")]
    [string]$Outcome,

    [Parameter(Mandatory = $true)]
    [string]$Summary,

    [string]$ChangedArtifacts = "NONE",

    [string]$Verification = "NOT_RUN",

    [string]$Decisions = "NONE",

    [string]$Blockers = "NONE",

    [string]$RecommendedNext = "REVIEW",

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

$taskContent=Get-Content $taskPath -Raw -Encoding UTF8
$status=Read-Field $taskContent "Status"
$owner=Read-Field $taskContent "Owner"
$workRequest=Read-Field $taskContent "Work request"

if($status -ne "ACTIVE"){
    throw "Task $Id must be ACTIVE to submit a result. Current status: $status"
}

$resultsDir=Join-Path $root "docs\engineering\results"
if(-not(Test-Path $resultsDir)){New-Item -ItemType Directory -Force -Path $resultsDir|Out-Null}

$existing=@(Get-ChildItem $resultsDir -Filter ($Id + "-result-*.md") -File -ErrorAction SilentlyContinue | ForEach-Object {
    if($_.BaseName -match [regex]::Escape($Id) + '-result-(\d+)$'){[int]$Matches[1]}
})
$next=1
if($existing.Count -gt 0){$next=[int](($existing|Measure-Object -Maximum).Maximum)+1}
$sequence=$next.ToString().PadLeft(3,'0')
$now=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$resultPath=Join-Path $resultsDir ($Id + "-result-" + $sequence + ".md")

$lines=@(
    "# Task Result - $Id",
    "",
    "Recorded: $now",
    "Task: $Id",
    "Owner: $owner",
    "Work request: $workRequest",
    "Outcome: $Outcome",
    "",
    "## Summary",
    "",
    $Summary,
    "",
    "## Changed Artifacts",
    "",
    $ChangedArtifacts,
    "",
    "## Verification",
    "",
    $Verification,
    "",
    "## Decisions",
    "",
    $Decisions,
    "",
    "## Blockers",
    "",
    $Blockers,
    "",
    "## Recommended Next",
    "",
    $RecommendedNext,
    "",
    "## Result Rules",
    "",
    "- This result records the assigned owner's delivery.",
    "- It does not replace independent review, QA, security or CEO approval.",
    "- BLOCKED is reserved for an execution blocker that prevented the assigned owner from completing the task.",
    "- Product defects, release blockers, failed validations and audit findings may be severe while the task outcome remains COMPLETED."
)

Write-Utf8NoBom $resultPath ($lines -join [Environment]::NewLine)

$updateScript=Join-Path $PSScriptRoot "update-task.ps1"
$advanceScript=Join-Path $PSScriptRoot "advance-task.ps1"

if(-not(Test-Path $updateScript)){throw "update-task.ps1 not found: $updateScript"}
if(-not(Test-Path $advanceScript)){throw "advance-task.ps1 not found: $advanceScript"}

$relativeResult="docs/engineering/results/" + (Split-Path $resultPath -Leaf)
& $updateScript -Id $Id -Evidence ("Result submitted: " + $relativeResult) -Note ("Owner outcome: " + $Outcome + ". " + $Summary) -TasksPath $tasksPath

if($Outcome -eq "BLOCKED"){
    & $advanceScript -Id $Id -Status BLOCKED -Actor $owner -Reason ("Owner reported blocker. " + $Blockers) -Evidence ("Result artifact: " + $relativeResult) -TasksPath $tasksPath
}
else{
    & $advanceScript -Id $Id -Status REVIEW -Actor $owner -Reason "Owner submitted completed work for independent review." -Evidence ("Result artifact: " + $relativeResult) -TasksPath $tasksPath
}

Write-Host "Task result recorded:" -ForegroundColor Green
Write-Host $resultPath
Write-Host "Outcome: $Outcome"
