param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][ValidateSet("PASS","FAIL","NOT_APPLICABLE")][string]$Outcome,
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

$content=Get-Content $taskPath -Raw -Encoding UTF8
$status=Read-Field $content "Status"
if($status -ne "SECURITY"){throw "Task $Id must be SECURITY. Current status: $status"}

$profile=Read-Field $content "Workflow profile"
if([string]::IsNullOrWhiteSpace($profile)){$profile="standard"}

if($profile -eq "high-assurance" -and $Outcome -eq "NOT_APPLICABLE"){
    throw "High-assurance tasks require an explicit security PASS or FAIL; NOT_APPLICABLE is not allowed."
}

$dir=Join-Path $root "docs\engineering\security"
if(-not(Test-Path $dir)){New-Item -ItemType Directory -Force -Path $dir|Out-Null}
$now=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$path=Join-Path $dir ($Id+"-security.md")

$lines=@(
"# Security Gate - $Id","",
"Recorded: $now",
"Workflow profile: $profile",
"Outcome: $Outcome","",
"## Evidence","",$Evidence,"",
"## Findings","",$Findings,"",
"## Rule","",
"- PASS or an allowed NOT_APPLICABLE satisfies the security gate only.",
"- high-assurance tasks require an explicit PASS or FAIL.",
"- Final DONE still requires CEO verification.",
"- FAIL returns the task to READY."
)
Write-Utf8NoBom $path ($lines -join [Environment]::NewLine)

$update=Join-Path $PSScriptRoot "update-task.ps1"
$advance=Join-Path $PSScriptRoot "advance-task.ps1"
$relative="docs/engineering/security/"+(Split-Path $path -Leaf)

& $update -Id $Id -Evidence ("Security artifact: "+$relative+"; Outcome="+$Outcome) -TasksPath $tasksPath

if($Outcome -eq "FAIL"){
    & $advance -Id $Id -Status READY -Actor "security" -Reason ("Security gate failed. "+$Findings) -Evidence ("Security artifact: "+$relative) -TasksPath $tasksPath
}

Write-Host "Security gate recorded: $Outcome" -ForegroundColor Green
