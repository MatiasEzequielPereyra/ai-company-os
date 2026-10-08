param(
    [Parameter(Mandatory = $true)]
    [string]$JsonPath,
    [object]$GroundingContext
)

$ErrorActionPreference = "Stop"

function Get-ConcreteStrings {
    param([object]$Value)
    return @(
        @($Value) |
            ForEach-Object {
                if ($null -ne $_) { ([string]$_).Trim() }
            } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            }
    )
}

function Assert-StructuredFields {
    param(
        [object]$Result,
        [string[]]$Fields,
        [string]$Label
    )
    foreach ($field in $Fields) {
        if ($null -eq $Result.PSObject.Properties[$field]) {
            throw "Semantic contract: $Label result missing field: $field"
        }
    }
}

if (-not (Test-Path $JsonPath -PathType Leaf)) {
    throw "Semantic contract: gate result not found: $JsonPath"
}

$result = Get-Content $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($null -ne $result.PSObject.Properties["recommendation"]) {
    if ($null -eq $GroundingContext) { throw 'REVIEW_GROUNDING_UNTRUSTED_CONTEXT: Review requires engine-owned invocation context.' }
    . (Join-Path $PSScriptRoot 'review-grounding.ps1')
    Assert-StructuredFields -Result $result -Fields @("recommendation","findings","verification","missing_required_outputs","deliverable_defects") -Label "Review"
    $missingRequiredOutputs = @(Get-ConcreteStrings -Value $result.missing_required_outputs)
    $deliverableDefects = @(Get-ConcreteStrings -Value $result.deliverable_defects)

    switch ([string]$result.recommendation) {
        "APPROVE" {
            if ($missingRequiredOutputs.Count -gt 0 -or $deliverableDefects.Count -gt 0) {
                throw "Semantic contract: invalid Review APPROVE; missing_required_outputs and deliverable_defects must both be empty."
            }
        }
        "CHANGES_REQUIRED" {
            if ($missingRequiredOutputs.Count -eq 0 -and $deliverableDefects.Count -eq 0) {
                throw "Semantic contract: invalid Review CHANGES_REQUIRED; at least one concrete missing required output or deliverable defect is required."
            }
        }
        default {
            throw "Semantic contract: invalid Review recommendation: $($result.recommendation)"
        }
    }
    Assert-ReviewGroundingResult -Result $result -Context $GroundingContext | Out-Null
    Write-Output "PASS: Review gate semantic validation"
    return
}

if ($null -ne $result.PSObject.Properties["criteria_assessment"]) {
    Assert-StructuredFields -Result $result -Fields @("outcome","evidence","findings","criteria_assessment") -Label "QA"
    $criteria = @($result.criteria_assessment)
    if ($criteria.Count -eq 0) {
        throw "Semantic contract: invalid QA result; criteria_assessment cannot be empty."
    }
    foreach ($criterion in $criteria) {
        Assert-StructuredFields -Result $criterion -Fields @("criterion","status","evidence") -Label "QA criterion"
        if ([string]::IsNullOrWhiteSpace([string]$criterion.criterion)) {
            throw "Semantic contract: invalid QA criterion; criterion text is required."
        }
        if ([string]::IsNullOrWhiteSpace([string]$criterion.evidence)) {
            throw "Semantic contract: invalid QA criterion; evidence is required."
        }
        if ([string]$criterion.status -notin @("SATISFIED","UNSATISFIED","NOT_APPLICABLE")) {
            throw "Semantic contract: invalid QA criterion status: $($criterion.status)"
        }
    }
    $unsatisfiedCriteria = @($criteria | Where-Object { [string]$_.status -eq "UNSATISFIED" })
    switch ([string]$result.outcome) {
        "PASS" {
            if ($unsatisfiedCriteria.Count -gt 0) {
                throw "Semantic contract: invalid QA PASS; at least one criterion is UNSATISFIED."
            }
        }
        "FAIL" {
            if ($unsatisfiedCriteria.Count -eq 0) {
                throw "Semantic contract: invalid QA FAIL; at least one concrete UNSATISFIED criterion is required."
            }
        }
        default {
            throw "Semantic contract: invalid QA outcome: $($result.outcome)"
        }
    }
    Write-Output "PASS: QA gate semantic validation"
    return
}

if ($null -ne $result.PSObject.Properties["security_relevant"]) {
    Assert-StructuredFields -Result $result -Fields @("outcome","evidence","findings","security_relevant","deliverable_security_defects") -Label "Security"
    $securityRelevant = [bool]$result.security_relevant
    $deliverableSecurityDefects = @(Get-ConcreteStrings -Value $result.deliverable_security_defects)
    switch ([string]$result.outcome) {
        "PASS" {
            if (-not $securityRelevant) {
                throw "Semantic contract: invalid Security PASS; security_relevant must be true. Use NOT_APPLICABLE when no meaningful security verification applies."
            }
            if ($deliverableSecurityDefects.Count -gt 0) {
                throw "Semantic contract: invalid Security PASS; deliverable_security_defects must be empty."
            }
        }
        "FAIL" {
            if (-not $securityRelevant) {
                throw "Semantic contract: invalid Security FAIL; security_relevant must be true."
            }
            if ($deliverableSecurityDefects.Count -eq 0) {
                throw "Semantic contract: invalid Security FAIL; at least one concrete security defect of the deliverable is required."
            }
        }
        "NOT_APPLICABLE" {
            if ($securityRelevant) {
                throw "Semantic contract: invalid Security NOT_APPLICABLE; security_relevant must be false."
            }
            if ($deliverableSecurityDefects.Count -gt 0) {
                throw "Semantic contract: invalid Security NOT_APPLICABLE; deliverable_security_defects must be empty."
            }
        }
        default {
            throw "Semantic contract: invalid Security outcome: $($result.outcome)"
        }
    }
    Write-Output "PASS: Security gate semantic validation"
    return
}

throw "Semantic contract: gate result type could not be determined from structured fields."
