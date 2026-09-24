param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Require-Text {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )

    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Required file missing: $Path"
    }

    $content = Get-Content $Path -Raw -Encoding UTF8

    if ($content -notmatch $Pattern) {
        throw $Message
    }
}

$writable = Join-Path $repoRoot "scripts\run-writable-agent.ps1"
$review = Join-Path $repoRoot "scripts\review-task.ps1"
$qa = Join-Path $repoRoot "scripts\qa-task.ps1"
$security = Join-Path $repoRoot "scripts\security-task.ps1"
$finalize = Join-Path $repoRoot "scripts\finalize-task.ps1"
$protocol = Join-Path $repoRoot ".codex\protocols\tui-runtime-integration.md"

Require-Text $writable 'status -notin @\("READY","ACTIVE"\)' "Writable runner must accept only canonical READY/ACTIVE entry states."
Require-Text $writable 'submit-task-result\.ps1' "Writable runner must use canonical Result Intake."
Require-Text $review 'ValidateSet\("APPROVE","CHANGES_REQUIRED"\)' "Review must expose APPROVE/CHANGES_REQUIRED."
Require-Text $review 'Status READY' "CHANGES_REQUIRED must return through canonical READY."
Require-Text $review 'Status QA' "Review approval must advance to QA."
Require-Text $qa 'ValidateSet\("PASS","FAIL"\)' "QA must expose PASS/FAIL."
Require-Text $qa 'Status SECURITY' "QA PASS must advance to SECURITY."
Require-Text $qa 'Status READY' "QA FAIL must return to READY."
Require-Text $security 'ValidateSet\("PASS","FAIL","NOT_APPLICABLE"\)' "Security gate outcomes changed unexpectedly."
Require-Text $security 'Status READY' "Security FAIL must return to READY."
Require-Text $finalize 'ValidateSet\("APPROVE","REJECT"\)' "Final approval must remain explicit."
Require-Text $finalize 'Status DONE' "Final APPROVE must canonically advance to DONE."
Require-Text $finalize 'Status READY' "Final REJECT must return to READY."
Require-Text $protocol 'CHANGES_REQUIRED.*READY' "TUI protocol must model review retry without inventing a task status."
Require-Text $protocol 'human/CEO authorization' "TUI protocol must preserve human final authorization."
Require-Text $protocol 'run-writable-agent\.ps1' "TUI protocol must delegate source implementation to writable runtime."

Write-Host "PASS: TUI/runtime canonical lifecycle integration contract" -ForegroundColor Green
