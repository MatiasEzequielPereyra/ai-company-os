param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][ValidateSet("PASS","FAIL")][string]$Outcome,
    [Parameter(Mandatory = $true)][string]$Evidence,
    [string]$Findings = "NONE",
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
if($status -ne "QA"){throw "Task $Id must be QA. Current status: $status"}

$dir=Join-Path $root "docs\engineering\qa"
if(-not(Test-Path $dir)){New-Item -ItemType Directory -Force -Path $dir|Out-Null}
$now=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$path=Join-Path $dir ($Id+"-qa.md")

$lines=@(
"# QA Gate - $Id","",
"Recorded: $now",
"Outcome: $Outcome","",
"## Evidence","",$Evidence,"",
"## Findings","",$Findings,"",
"## Rule","",
"- PASS verifies QA acceptance only.",
"- FAIL returns the task to READY for corrective work."
)
Write-Utf8NoBom $path ($lines -join [Environment]::NewLine)

$advance=Join-Path $PSScriptRoot "advance-task.ps1"
$relative="docs/engineering/qa/"+(Split-Path $path -Leaf)
if($Outcome -eq "PASS"){
    & $advance -Id $Id -Status SECURITY -Actor "qa" -Reason "QA gate passed." -Evidence ("QA artifact: "+$relative) -TasksPath $tasksPath
}else{
    & $advance -Id $Id -Status READY -Actor "qa" -Reason ("QA gate failed. "+$Findings) -Evidence ("QA artifact: "+$relative) -TasksPath $tasksPath
}
Write-Host "QA gate recorded: $Outcome" -ForegroundColor Green
