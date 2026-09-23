param(
    [string]$ProjectPath = ".",
    [switch]$Parallel,
    [ValidateSet("Auto","Codex","OpenRouter","Gemini")]
    [string]$Provider = "Auto",
    [string]$Model = "",
    [ValidateSet("Auto","ChatGPT","ApiKey")]
    [string]$AuthMode = "Auto"
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

if ($PSBoundParameters.ContainsKey("AuthMode") -and -not $PSBoundParameters.ContainsKey("Provider")) {
    if ($AuthMode -eq "ChatGPT") {
        $Provider = "Codex"
    }
    elseif ($AuthMode -eq "ApiKey") {
        throw "Legacy -AuthMode ApiKey is disabled. Use -Provider OpenRouter or -Provider Gemini."
    }
}

$root = (Resolve-Path $ProjectPath).Path
$tasksPath = Join-Path $root "tasks"
$runner = Join-Path $PSScriptRoot "run-agent-task.ps1"
if (-not (Test-Path $runner)) { throw "run-agent-task.ps1 not found: $runner" }

$active = @()
Get-ChildItem $tasksPath -Filter "AICO-*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -Encoding UTF8
    $status = Read-Field $content "Status"
    if ($status -eq "ACTIVE") {
        $active += [PSCustomObject]@{
            ID = Read-Field $content "ID"
            Owner = Read-Field $content "Owner"
        }
    }
}

if ($active.Count -eq 0) {
    Write-Host "No ACTIVE tasks found." -ForegroundColor Yellow
    exit 0
}

Write-Host "ACTIVE agent tasks: $($active.Count)" -ForegroundColor Cyan
Write-Host "Provider mode: $Provider" -ForegroundColor DarkGray
$active | Sort-Object ID | Format-Table ID, Owner -AutoSize

if (-not $Parallel) {
    foreach ($task in ($active | Sort-Object ID)) {
        & $runner -ProjectPath $root -Id $task.ID -Provider $Provider -Model $Model
    }
}
else {
    $jobs = @()

    foreach ($task in ($active | Sort-Object ID)) {
        $id = $task.ID
        $jobs += Start-Job -Name $id -ArgumentList $runner,$root,$id,$Provider,$Model -ScriptBlock {
            param($runnerPath,$projectRoot,$taskId,$providerName,$modelName)
            & $runnerPath -ProjectPath $projectRoot -Id $taskId -Provider $providerName -Model $modelName
        }
    }

    Write-Host "Running $($jobs.Count) agents in parallel..." -ForegroundColor Cyan
    Wait-Job -Job $jobs | Out-Null

    $failed = @()
    foreach ($job in $jobs) {
        Receive-Job -Job $job
        if ($job.State -ne "Completed") { $failed += $job.Name }
    }
    Remove-Job -Job $jobs -Force

    if ($failed.Count -gt 0) {
        throw ("Agent jobs failed: " + ($failed -join ", "))
    }
}

Write-Host ""
Write-Host "Agent runtime batch complete." -ForegroundColor Green
