$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$newWorkRequest = Join-Path $repo "scripts\new-work-request.ps1"
$orchestrate = Join-Path $repo "scripts\orchestrate.ps1"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "aico-auth-test-" + [guid]::NewGuid().ToString("N")
)

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Expected,
        [string]$Message
    )

    if (-not $Content.Contains($Expected)) {
        throw "$Message`nExpected: $Expected"
    }
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".codex\state") | Out-Null

    Write-Host "TEST 1: default remains NOT_INFERRED"

    & $newWorkRequest `
        -ProjectPath $tempRoot `
        -Objective "Analyze the repository only." `
        -Type RESEARCH `
        -Priority P2 `
        -RequestedBy test

    $wr1 = Get-Content `
        (Join-Path $tempRoot "docs\engineering\work-requests\WR-001.md") `
        -Raw

    Assert-Contains `
        $wr1 `
        "Implementation authorization: NOT_INFERRED" `
        "Default authorization must remain NOT_INFERRED."

    Assert-Contains `
        $wr1 `
        "Permitted scope: planning and task preparation for this objective." `
        "Default permitted scope changed unexpectedly."

    Write-Host "PASS: default remains safe" -ForegroundColor Green

    Write-Host "TEST 2: explicit authorization is accepted by new-work-request"

    & $newWorkRequest `
        -ProjectPath $tempRoot `
        -Objective "Create greeting.txt." `
        -Type FEATURE `
        -Priority P2 `
        -RequestedBy test `
        -ImplementationAuthorization EXPLICIT

    $wr2 = Get-Content `
        (Join-Path $tempRoot "docs\engineering\work-requests\WR-002.md") `
        -Raw

    Assert-Contains `
        $wr2 `
        "Implementation authorization: EXPLICIT" `
        "Explicit implementation authorization was not recorded."

    Assert-Contains `
        $wr2 `
        "Permitted scope: planning, task preparation, and implementation for this objective." `
        "Explicit implementation scope was not recorded."

    Write-Host "PASS: new-work-request explicit authorization" -ForegroundColor Green

    Write-Host "TEST 3: orchestrate exposes and propagates explicit authorization"

    $syntax = (Get-Command $orchestrate).Parameters

    if (-not $syntax.ContainsKey("ImplementationAuthorization")) {
        throw "orchestrate.ps1 does not expose -ImplementationAuthorization."
    }

    $orchestrateText = Get-Content $orchestrate -Raw

    if ($orchestrateText -notmatch '\-ImplementationAuthorization\s+\$ImplementationAuthorization') {
        throw "orchestrate.ps1 does not propagate ImplementationAuthorization to new-work-request.ps1."
    }

    Write-Host "PASS: orchestrator propagation" -ForegroundColor Green

    Write-Host ""
    Write-Host "ALL EXPLICIT AUTHORIZATION TESTS PASSED" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
    }
}
