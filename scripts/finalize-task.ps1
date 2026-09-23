param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][ValidateSet("APPROVE","REJECT")][string]$Decision,
    [Parameter(Mandatory = $true)][string]$Verification,
    [string]$ProjectPath = "."
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom { param([string]$Path,[string]$Value) [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false))) }
function Read-Field { param([string]$Content,[string]$Key) $p="(?m)^"+[regex]::Escape($Key)+":\s*(.+)$"; if($Content -match $p){return $Matches[1].Trim()}; return "" }

$root=(Resolve-Path $ProjectPath).Path
$tasksPath=Join-Path $root "tasks"
$taskPath=Join-Path $tasksPath ($Id+".md")
if(-not(Test-Path $taskPath)){throw "Task not found: $taskPath"}

$content=Get-Content $taskPath -Raw
$status=Read-Field $content "Status"
$profile=Read-Field $content "Workflow profile"
if([string]::IsNullOrWhiteSpace($profile)){$profile="standard"}
if($status -ne "SECURITY"){throw "Task $Id must be SECURITY for final approval. Current status: $status"}

$qaPath=Join-Path $root ("docs\engineering\qa\"+$Id+"-qa.md")
$securityPath=Join-Path $root ("docs\engineering\security\"+$Id+"-security.md")
if(-not(Test-Path $qaPath)){throw "QA artifact missing for $Id"}
if(-not(Test-Path $securityPath)){throw "Security artifact missing for $Id"}

$qa=Get-Content $qaPath -Raw
$sec=Get-Content $securityPath -Raw
$qaOutcome=Read-Field $qa "Outcome"
$secOutcome=Read-Field $sec "Outcome"

if($qaOutcome -ne "PASS"){throw "QA gate is not PASS for $Id"}
if($secOutcome -notin @("PASS","NOT_APPLICABLE")){throw "Security gate is not satisfied for $Id"}
if($profile -eq "high-assurance" -and $secOutcome -ne "PASS"){throw "High-assurance task $Id requires security PASS before final approval."}

$dir=Join-Path $root "docs\engineering\final-approvals"
if(-not(Test-Path $dir)){New-Item -ItemType Directory -Force -Path $dir|Out-Null}
$now=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$path=Join-Path $dir ($Id+"-final.md")

$lines=@(
"# Final Approval - $Id","",
"Recorded: $now",
"Approver: ceo",
"Decision: $Decision","",
"## Verification","",$Verification,"",
"## Gate Evidence","",
"- QA: $qaOutcome",
"- Security: $secOutcome","",
"## Rule","",
"- APPROVE confirms applicable gates and original task objective were verified.",
"- REJECT returns the task to READY for corrective work."
)
Write-Utf8NoBom $path ($lines -join [Environment]::NewLine)

$advance=Join-Path $PSScriptRoot "advance-task.ps1"
$relative="docs/engineering/final-approvals/"+(Split-Path $path -Leaf)

if($Decision -eq "APPROVE"){
    & $advance -Id $Id -Status DONE -Actor "ceo" -Reason "CEO final verification approved all applicable gates." -Evidence ("Final approval: "+$relative) -TasksPath $tasksPath

    $refresh=Join-Path $PSScriptRoot "refresh-dependencies.ps1"
    if(Test-Path $refresh){ & $refresh -ProjectPath $root }
}else{
    & $advance -Id $Id -Status READY -Actor "ceo" -Reason "CEO final verification rejected the task." -Evidence ("Final approval: "+$relative) -TasksPath $tasksPath
}

Write-Host "Final approval recorded: $Decision" -ForegroundColor Green
