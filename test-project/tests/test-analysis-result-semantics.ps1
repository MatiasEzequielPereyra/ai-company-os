$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$validator = Join-Path $root 'scripts/validate-analysis-result-semantics.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('analysis-semantics-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $scratch | Out-Null
function Assert-Result($Result, [bool]$Accept, [string]$Name) {
    $path = Join-Path $scratch 'result.json'
    $Result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
    $accepted = $true
    try { & $validator -JsonPath $path } catch { $accepted = $false }
    if ($accepted -ne $Accept) { throw "Unexpected semantic validation: $Name (accepted=$accepted)." }
}
try {
    $result = @{ outcome='COMPLETED'; blockers='NONE'; completion_check=@{substantive_role_deliverable_produced=$true;missing_required_outputs=@();evidence='ADR proposal included in report'} }
    Assert-Result $result $true 'legacy completed'
    $result.completion_check.missing_required_outputs=@('ADR')
    Assert-Result $result $false 'incomplete completed'
    $result.outcome='BLOCKED'; $result.blockers='ADR pending'
    Assert-Result $result $false 'unstructured owned ADR'
    $result.execution_blocker=@{kind='owned_output_pending';prerequisite='ADR';evidence='review requires ADR';resolution_owner='cto';why_role_cannot_resolve='ADR still pending';role_can_resolve=$false}
    Assert-Result $result $false 'structured owned ADR'
    $result.execution_blocker=@{kind='external_decision';prerequisite='PM retention decision';evidence='DEC-012 unresolved in product decision log';resolution_owner='pm';why_role_cannot_resolve='Only PM is authorized to choose retention';role_can_resolve=$false}
    $result.blockers='DEC-012 requires PM decision'
    Assert-Result $result $true 'legitimate external blocker'
    $result.execution_blocker.role_can_resolve=$true
    Assert-Result $result $false 'resolvable prerequisite'
    $result.execution_blocker.role_can_resolve=$false
    $result.execution_blocker.evidence='NONE'
    Assert-Result $result $false 'missing concrete evidence'
    $result.execution_blocker.evidence='DEC-012 unresolved'; $result.blockers='NONE'
    Assert-Result $result $false 'contradictory blocker summary'
    $result.blockers='decision pending'; $result.execution_blocker.Remove('resolution_owner')
    Assert-Result $result $false 'missing escalation owner'
    $result.execution_blocker.resolution_owner='pm'
    $result.executable_work=@()
    Assert-Result $result $true 'blocked engineering plan without executable work'
    $result.executable_work=@(@{key='work'})
    Assert-Result $result $false 'blocked engineering plan with executable work'
    $result.Remove('execution_blocker'); $result.outcome='COMPLETED'; $result.blockers='NONE'
    $result.completion_check.missing_required_outputs=@(); $result.executable_work=@()
    Assert-Result $result $false 'completed engineering plan still needs executable work'
    Write-Output 'PASS: analysis result semantic contract (12 cases)'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
