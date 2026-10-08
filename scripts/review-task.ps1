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

    [string]$ProjectPath = ".",

    [object]$TaskExecutionLease,

    [string]$ResultPath,

    [object]$GroundingContext
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($Value)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$stream.Write($bytes,0,$bytes.Length)} finally {$stream.Dispose()}
}

function Assert-ReviewDestination {
    param([string]$Root,[string]$Path)
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\','/'))
    $current=[IO.Path]::GetFullPath($Path)
    if(-not $current.StartsWith($rootFull+[IO.Path]::DirectorySeparatorChar,(Get-ExecutionPathComparison))){throw 'REVIEW_DESTINATION_UNSAFE: path escapes project.'}
    while(-not [string]::Equals($current,$rootFull,(Get-ExecutionPathComparison))) {
        if(Test-Path -LiteralPath $current) {
            if((Get-Item -LiteralPath $current -Force).Attributes-band [IO.FileAttributes]::ReparsePoint){throw 'REVIEW_DESTINATION_UNSAFE: reparse point in destination ancestry.'}
        }
        $current=Split-Path $current -Parent
    }
}

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

$root=(Resolve-Path $ProjectPath).Path
. (Join-Path $PSScriptRoot 'task-execution-lock.ps1')
$reviewScope = Enter-TaskExecutionScope -ProjectPath $root -Id $Id -Operation 'REVIEW_INTAKE' -Lease $TaskExecutionLease
try {
# Scalar manual judgments are not usable Review v1 evidence. Validation and
# recording of complete grounded judgments is supplied by the v1 intake below.
if ([string]::IsNullOrWhiteSpace($ResultPath) -or $null -eq $GroundingContext) {
    throw 'REVIEW_GROUNDING_REQUIRED: complete review-grounding-v1 judgment and trusted engine snapshot context are required.'
}
. (Join-Path $PSScriptRoot 'review-grounding.ps1')
& (Join-Path $PSScriptRoot 'validate-json-contract.ps1') -JsonPath $ResultPath -SchemaPath (Join-Path $root 'schemas/review-result.schema.json') | Out-Null
$judgment = Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
$validation = Assert-ReviewGroundingResult -Result $judgment -Context $GroundingContext -CheckDrift
Assert-ReviewGroundingValidation -ProjectPath $root -Id $Id -Lease $reviewScope.Lease -Validation $validation -Recommendation ([string]$judgment.recommendation)
if ($Recommendation -cne [string]$judgment.recommendation) { throw 'REVIEW_RECOMMENDATION_MISMATCH' }
$Findings = [string]$judgment.findings
$Verification = [string]$judgment.verification
$manifest = Get-ReviewGroundingManifest -Context $GroundingContext
$findingLines=New-Object 'Collections.Generic.List[string]'
$findingLines.Add($Findings)
foreach($name in @('missing_required_outputs','deliverable_defects')) {
    if(@($judgment.$name).Count) {
        $findingLines.Add('');$findingLines.Add('### '+$name)
        foreach($item in $judgment.$name){$findingLines.Add('- '+[string]$item)}
    }
}
foreach($row in @($judgment.assessments|Where-Object{$_.status-ceq 'UNSATISFIED'})) {
    $declaration=@($manifest.obligations|Where-Object{$_.required_output_id-ceq $row.required_output_id})[0].declaration
    $findingLines.Add('');$findingLines.Add('### UNSATISFIED '+[string]$row.required_output_id)
    $findingLines.Add([string]$declaration);$findingLines.Add([string]$row.rationale)
}
$canonicalFindings=$findingLines.ToArray()-join [Environment]::NewLine
$tasksPath=Join-Path $root "tasks"
$taskPath=Join-Path $tasksPath ($Id + ".md")

if(-not(Test-Path $taskPath)){throw "Task not found: $taskPath"}

$taskContent=Get-Content $taskPath -Raw -Encoding UTF8
$status=Read-Field $taskContent "Status"
$owner=Read-Field $taskContent "Owner"

if($status -ne "REVIEW"){
    throw "Task $Id must be REVIEW to submit a review. Current status: $status"
}

$reviewDir=Join-Path $root "docs\engineering\reviews"
Assert-ReviewDestination -Root $root -Path $reviewDir
$updateScript=Join-Path $PSScriptRoot "update-task.ps1"
$advanceScript=Join-Path $PSScriptRoot "advance-task.ps1"
if(-not(Test-Path $updateScript)){throw "update-task.ps1 not found: $updateScript"}
if(-not(Test-Path $advanceScript)){throw "advance-task.ps1 not found: $advanceScript"}
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
    "Contract version: review-grounding-v1",
    ("Snapshot ID: " + $manifest.snapshot_id),
    ("Manifest SHA256: " + $manifest.manifest_digest),
    "",
    "## Findings",
    "",
    $canonicalFindings,
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

$auditPath = [IO.Path]::ChangeExtension($reviewPath,'grounding.json')
Assert-ReviewDestination -Root $root -Path $reviewPath
Assert-ReviewDestination -Root $root -Path $auditPath
if((Test-Path -LiteralPath $reviewPath) -or (Test-Path -LiteralPath $auditPath)){throw 'REVIEW_DESTINATION_COLLISION: existing Review history cannot be overwritten.'}
$audit = [ordered]@{ contract_version='review-grounding-v1'; manifest=$manifest; judgment=$judgment }
$auditText=$audit | ConvertTo-Json -Depth 40
Write-Utf8NoBom $reviewPath ($lines -join [Environment]::NewLine)
try {Write-Utf8NoBom $auditPath $auditText} catch {
    # Only this invocation's newly created Markdown is removed on a failed
    # sidecar publication; CreateNew never replaces historical artifacts.
    Assert-ReviewDestination -Root $root -Path $reviewPath
    Remove-Item -LiteralPath $reviewPath -Force
    throw
}
$receipt = New-ReviewIntakeReceipt -ProjectPath $root -Id $Id -Lease $reviewScope.Lease -ReviewPath $reviewPath -Recommendation $Recommendation -GroundingValidation $validation

$relativeReview="docs/engineering/reviews/" + (Split-Path $reviewPath -Leaf)
& $updateScript -Id $Id -Evidence ("Review recorded: " + $relativeReview) -Note ("Review recommendation: " + $Recommendation + ". " + $Findings) -TasksPath $tasksPath -TaskExecutionLease $reviewScope.Lease

if($Recommendation -eq "APPROVE"){
    & $advanceScript -Id $Id -Status QA -Actor $Reviewer -Reason "Independent review approved." -Evidence ("Review artifact: " + $relativeReview) -TasksPath $tasksPath -TaskExecutionLease $reviewScope.Lease -ReviewIntakeReceipt $receipt
}
else{
    & $advanceScript -Id $Id -Status READY -Actor $Reviewer -Reason ("Review requested changes. " + $Findings) -Evidence ("Review artifact: " + $relativeReview) -TasksPath $tasksPath -TaskExecutionLease $reviewScope.Lease -ReviewIntakeReceipt $receipt
}

Write-Host "Review recorded:" -ForegroundColor Green
Write-Host $reviewPath
Write-Host "Recommendation: $Recommendation"
} finally {
    Exit-TaskExecutionScope -Scope $reviewScope
}
