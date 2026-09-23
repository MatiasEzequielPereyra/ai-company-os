param(
    [string]$ProjectPath = ".",

    [ValidateSet("Auto","Codex","OpenRouter","Gemini")]
    [string]$Provider = "Auto",

    [string]$Model = ""
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param([string]$Content,[string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+)$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

$root = (Resolve-Path $ProjectPath).Path
$tasksPath = Join-Path $root "tasks"
$gateRunner = Join-Path $PSScriptRoot "run-gate-agent.ps1"

if (-not (Test-Path $gateRunner)) { throw "run-gate-agent.ps1 not found: $gateRunner" }

$phases = @(
    @{ Status = "REVIEW"; Gate = "Review" },
    @{ Status = "QA"; Gate = "QA" },
    @{ Status = "SECURITY"; Gate = "Security" }
)

foreach ($phase in $phases) {
    $ids = @(
        Get-ChildItem $tasksPath -Filter "AICO-*.md" -File |
            ForEach-Object {
                $content = Get-Content $_.FullName -Raw
                $id = Read-Field $content "ID"
                if ([string]::IsNullOrWhiteSpace($id)) { $id = $_.BaseName }
                $status = Read-Field $content "Status"

                if ($status -eq $phase.Status) {
                    if ($phase.Gate -eq "Security") {
                        $securityArtifact = Join-Path $root ("docs\engineering\security\" + $id + "-security.md")
                        if (Test-Path $securityArtifact) {
                            $securityContent = Get-Content $securityArtifact -Raw
                            $securityOutcome = Read-Field $securityContent "Outcome"
                            if ($securityOutcome -in @("PASS","NOT_APPLICABLE")) {
                                return
                            }
                        }
                    }

                    $id
                }
            } |
            Sort-Object
    )

    if ($ids.Count -eq 0) {
        Write-Host ("No " + $phase.Status + " tasks for " + $phase.Gate + " gate.") -ForegroundColor DarkGray
        continue
    }

    Write-Host ""
    Write-Host ($phase.Gate + " gate tasks: " + $ids.Count) -ForegroundColor Cyan

    foreach ($id in $ids) {
        & $gateRunner -ProjectPath $root -Id $id -Gate $phase.Gate -Provider $Provider -Model $Model
    }
}

Write-Host ""
Write-Host "Autonomous gate batch complete." -ForegroundColor Green
