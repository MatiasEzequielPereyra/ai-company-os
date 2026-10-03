param(
    [Parameter(Mandatory = $true)]
    [string]$JsonPath
)

$ErrorActionPreference = "Stop"
$result = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$check = $result.completion_check
if ($null -eq $check) { throw "Semantic contract: completion_check is required." }
foreach ($field in @('substantive_role_deliverable_produced', 'missing_required_outputs', 'evidence')) {
    if ($null -eq $check.PSObject.Properties[$field]) { throw "Semantic contract: completion_check.$field is required." }
}
if ($check.substantive_role_deliverable_produced -isnot [bool]) { throw "Semantic contract: completion self-check must be boolean." }
if ([string]::IsNullOrWhiteSpace([string]$check.evidence)) { throw "Semantic contract: completion evidence is required." }

if ($result.outcome -eq 'COMPLETED') {
    if (-not $check.substantive_role_deliverable_produced) {
        throw "Semantic contract: invalid COMPLETED result; substantive role-owned deliverable was not produced."
    }
    if (@($check.missing_required_outputs).Count -gt 0) {
        throw "Semantic contract: invalid COMPLETED result; required role outputs are missing."
    }
    if ($null -ne $result.execution_blocker) { throw "Semantic contract: COMPLETED must not declare an execution_blocker." }
    if ($null -ne $result.PSObject.Properties['executable_work']) {
        & (Join-Path $PSScriptRoot 'validate-engineering-plan-result.ps1') -JsonPath $JsonPath
    }
    return
}
if ($result.outcome -ne 'BLOCKED') { throw "Semantic contract: unsupported analysis outcome." }

$blocker = $result.execution_blocker
if ($null -eq $blocker) { throw "Semantic contract: BLOCKED requires structured execution_blocker evidence, not a pending role-owned output." }
foreach ($field in @('kind', 'prerequisite', 'evidence', 'resolution_owner', 'why_role_cannot_resolve', 'role_can_resolve')) {
    if ($null -eq $blocker.PSObject.Properties[$field]) { throw "Semantic contract: execution_blocker.$field is required." }
}
if ($blocker.kind -notin @('missing_evidence', 'access_denied', 'authorization_required', 'external_decision', 'unsatisfied_dependency')) {
    throw "Semantic contract: BLOCKED requires an external impediment; owned_output_pending is corrective work."
}
if ($blocker.role_can_resolve -isnot [bool] -or $blocker.role_can_resolve) {
    throw "Semantic contract: the assigned role can resolve this prerequisite; deliver its corrective work instead of BLOCKED."
}
foreach ($field in @('prerequisite', 'evidence', 'resolution_owner', 'why_role_cannot_resolve')) {
    $value = ([string]$blocker.$field).Trim()
    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^(?i:NONE|N/?A|UNKNOWN|TBD|-)$') {
        throw "Semantic contract: execution_blocker.$field must identify concrete evidence and responsibility."
    }
}
$blockers = ([string]$result.blockers).Trim()
if ([string]::IsNullOrWhiteSpace($blockers) -or $blockers -match '^(?i:NONE|N/?A|-)$') {
    throw "Semantic contract: BLOCKED requires an execution blocker summary."
}
if ($null -ne $result.PSObject.Properties['executable_work']) {
    & (Join-Path $PSScriptRoot 'validate-engineering-plan-result.ps1') -JsonPath $JsonPath
}
