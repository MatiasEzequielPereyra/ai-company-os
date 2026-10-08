param(
    [Parameter(Mandatory = $true)]
    [string]$JsonPath
)

$ErrorActionPreference = "Stop"

function Assert-Field {
    param([object]$Object,[string]$Name,[string]$Label)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "Diagnostic contract: $Label missing field: $Name"
    }
}

function Get-Strings {
    param([object]$Value)
    return @(
        @($Value) |
            ForEach-Object { if ($null -ne $_) { ([string]$_).Trim() } } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

if (-not (Test-Path -LiteralPath $JsonPath -PathType Leaf)) {
    throw "Diagnostic contract: evidence artifact not found: $JsonPath"
}

$evidence = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($field in @("schema_version","task_id","workflow","state","reproduction","receipts","attempts","regression","post_fix_replay")) {
    Assert-Field -Object $evidence -Name $field -Label "root"
}

if ([string]$evidence.schema_version -ne "1") {
    throw "Diagnostic contract: unsupported schema_version: $($evidence.schema_version)"
}
if ([string]$evidence.workflow -ne "BUG") {
    throw "Diagnostic contract: workflow must be BUG."
}

$reproduction = $evidence.reproduction
foreach ($field in @("kind","command","working_directory","broken_when","signal_fingerprint","pre_fix")) {
    Assert-Field -Object $reproduction -Name $field -Label "reproduction"
}
$fingerprint = ([string]$reproduction.signal_fingerprint).Trim()
if ($fingerprint -notmatch '^[a-f0-9]{64}$') {
    throw "Diagnostic contract: reproduction.signal_fingerprint must be a runtime SHA-256 hex digest."
}

$receiptsById = @{}
foreach ($receipt in @($evidence.receipts)) {
    foreach ($field in @("id","phase","source","command","exit_code","output_sha256","output_excerpt")) {
        Assert-Field -Object $receipt -Name $field -Label "receipt"
    }
    $id = ([string]$receipt.id).Trim()
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw "Diagnostic contract: receipt id is required."
    }
    if ($receiptsById.ContainsKey($id)) {
        throw "Diagnostic contract: duplicate receipt id: $id"
    }
    if ([string]$receipt.source -eq "RUNTIME") {
        if ($null -eq $receipt.exit_code) {
            throw "Diagnostic contract: runtime receipt requires exit_code: $id"
        }
        if ([string]$receipt.output_sha256 -notmatch '^[a-f0-9]{64}$') {
            throw "Diagnostic contract: runtime receipt requires SHA-256 output digest: $id"
        }
    }
    $receiptsById[$id] = $receipt
}

$preFix = $reproduction.pre_fix
foreach ($field in @("observation","receipt_ref")) {
    Assert-Field -Object $preFix -Name $field -Label "reproduction.pre_fix"
}
$preReceipt = ([string]$preFix.receipt_ref).Trim()
if (-not [string]::IsNullOrWhiteSpace($preReceipt) -and -not $receiptsById.ContainsKey($preReceipt)) {
    throw "Diagnostic contract: pre-fix receipt reference does not exist: $preReceipt"
}
if (-not [string]::IsNullOrWhiteSpace($preReceipt)) {
    $preReceiptValue = $receiptsById[$preReceipt]
    if ([string]$preReceiptValue.phase -ne "PRE_FIX") {
        throw "Diagnostic contract: pre-fix receipt must have PRE_FIX phase."
    }
    if ([string]$reproduction.kind -eq "COMMAND") {
        if ([string]$preReceiptValue.source -ne "RUNTIME") {
            throw "Diagnostic contract: command reproduction requires runtime pre-fix evidence."
        }
        if ([string]$preReceiptValue.command -cne [string]$reproduction.command) {
            throw "Diagnostic contract: pre-fix receipt command must match the frozen reproduction signal."
        }
        $preBroken = switch ([string]$reproduction.broken_when) {
            "EXIT_ZERO" { [int]$preReceiptValue.exit_code -eq 0 }
            "EXIT_NONZERO" { [int]$preReceiptValue.exit_code -ne 0 }
            default { $false }
        }
        $expectedPre = if ($preBroken) { "BROKEN_OBSERVED" } else { "NOT_REPRODUCED" }
        if ([string]$preFix.observation -ne $expectedPre) {
            throw "Diagnostic contract: pre-fix observation contradicts the runtime receipt."
        }
    }
}

$attemptIndexes = @{}
foreach ($attempt in @($evidence.attempts)) {
    foreach ($field in @("index","corrective","hypotheses","cause","resolution")) {
        Assert-Field -Object $attempt -Name $field -Label "attempt"
    }
    $attemptIndex = [int]$attempt.index
    if ($attemptIndex -lt 1 -or $attemptIndexes.ContainsKey($attemptIndex)) {
        throw "Diagnostic contract: attempt indexes must be unique positive integers."
    }
    $attemptIndexes[$attemptIndex] = $true

    $hypothesesById = @{}
    foreach ($hypothesis in @($attempt.hypotheses)) {
        foreach ($field in @("id","statement","prediction","falsifier","experiment_command","supported_when","result","receipt_ref")) {
            Assert-Field -Object $hypothesis -Name $field -Label "hypothesis"
        }
        foreach ($textField in @("statement","prediction","falsifier","experiment_command")) {
            if ([string]::IsNullOrWhiteSpace([string]$hypothesis.$textField)) {
                throw "Diagnostic contract: hypothesis.$textField must be concrete."
            }
        }
        $hypothesisId = ([string]$hypothesis.id).Trim()
        if ([string]::IsNullOrWhiteSpace($hypothesisId) -or $hypothesesById.ContainsKey($hypothesisId)) {
            throw "Diagnostic contract: hypothesis ids must be unique within an attempt."
        }
        $hypothesesById[$hypothesisId] = $hypothesis
        $receiptRef = ([string]$hypothesis.receipt_ref).Trim()
        if (-not $receiptsById.ContainsKey($receiptRef)) {
            throw "Diagnostic contract: hypothesis references missing receipt: $receiptRef"
        }
        if ([string]$hypothesis.experiment_command -ceq [string]$reproduction.command) {
            throw "Diagnostic contract: hypothesis experiment must discriminate the cause and cannot equal the frozen reproduction signal."
        }
        $hypothesisReceipt = $receiptsById[$receiptRef]
        if ([string]$hypothesisReceipt.phase -ne "HYPOTHESIS") {
            throw "Diagnostic contract: hypothesis receipt must have HYPOTHESIS phase: $receiptRef"
        }
        if ([string]$hypothesisReceipt.command -cne [string]$hypothesis.experiment_command) {
            throw "Diagnostic contract: hypothesis receipt command mismatch: $receiptRef"
        }
        $observedSupported = switch ([string]$hypothesis.supported_when) {
            "EXIT_ZERO" { [int]$hypothesisReceipt.exit_code -eq 0 }
            "EXIT_NONZERO" { [int]$hypothesisReceipt.exit_code -ne 0 }
            default { $false }
        }
        $expectedHypothesisResult = if ($observedSupported) { "SUPPORTED" } else { "FALSIFIED" }
        if ([string]$hypothesis.result -ne $expectedHypothesisResult) {
            throw "Diagnostic contract: hypothesis result contradicts its runtime receipt: $($hypothesis.id)"
        }
    }

    $cause = $attempt.cause
    foreach ($field in @("status","statement","hypothesis_refs","receipt_refs")) {
        Assert-Field -Object $cause -Name $field -Label "cause"
    }
    $causeHypotheses = @(Get-Strings -Value $cause.hypothesis_refs)
    $causeReceipts = @(Get-Strings -Value $cause.receipt_refs)
    foreach ($ref in $causeReceipts) {
        if (-not $receiptsById.ContainsKey($ref)) {
            throw "Diagnostic contract: cause references missing receipt: $ref"
        }
    }

    $expectedCauseReceipts = @(
        foreach ($hypothesisRef in $causeHypotheses) {
            if ($hypothesesById.ContainsKey($hypothesisRef)) {
                [string]$hypothesesById[$hypothesisRef].receipt_ref
            }
        }
    )
    foreach ($ref in $causeReceipts) {
        if ($expectedCauseReceipts -notcontains $ref) {
            throw "Diagnostic contract: cause receipt must belong to a referenced hypothesis: $ref"
        }
    }

    if ([string]$cause.status -eq "CONFIRMED") {
        if ($causeHypotheses.Count -lt 1 -or $causeReceipts.Count -lt 1) {
            throw "Diagnostic contract: CONFIRMED cause requires hypothesis and receipt evidence."
        }
        foreach ($ref in $causeHypotheses) {
            if (-not $hypothesesById.ContainsKey($ref)) {
                throw "Diagnostic contract: cause references unknown hypothesis: $ref"
            }
            if ([string]$hypothesesById[$ref].result -ne "SUPPORTED") {
                throw "Diagnostic contract: CONFIRMED cause may reference only SUPPORTED hypotheses: $ref"
            }
        }
    }

    $resolution = $attempt.resolution
    foreach ($field in @("classification","summary","residual_risk")) {
        Assert-Field -Object $resolution -Name $field -Label "resolution"
    }
    if ([string]$resolution.classification -eq "REPAIR" -and [string]$cause.status -ne "CONFIRMED") {
        throw "Diagnostic contract: REPAIR requires a CONFIRMED evidence-backed cause."
    }
    if (
        [string]$resolution.classification -eq "WORKAROUND" -and
        [string]::IsNullOrWhiteSpace([string]$resolution.residual_risk)
    ) {
        throw "Diagnostic contract: WORKAROUND requires explicit residual_risk."
    }
}

foreach ($ref in @(Get-Strings -Value $evidence.regression.receipt_refs)) {
    if (-not $receiptsById.ContainsKey($ref)) {
        throw "Diagnostic contract: regression references missing receipt: $ref"
    }
    if ([string]$receiptsById[$ref].phase -ne "REGRESSION") {
        throw "Diagnostic contract: regression receipt must have REGRESSION phase: $ref"
    }
}

$postFix = $evidence.post_fix_replay
foreach ($field in @("signal_fingerprint","observation","receipt_ref")) {
    Assert-Field -Object $postFix -Name $field -Label "post_fix_replay"
}
if ([string]$postFix.signal_fingerprint -ne $fingerprint) {
    throw "Diagnostic contract: post-fix replay must use the exact frozen reproduction signal fingerprint."
}
$postReceipt = ([string]$postFix.receipt_ref).Trim()
if (-not [string]::IsNullOrWhiteSpace($postReceipt) -and -not $receiptsById.ContainsKey($postReceipt)) {
    throw "Diagnostic contract: post-fix replay references missing receipt: $postReceipt"
}
if (-not [string]::IsNullOrWhiteSpace($postReceipt)) {
    $postReceiptValue = $receiptsById[$postReceipt]
    if ([string]$postReceiptValue.phase -ne "POST_FIX") {
        throw "Diagnostic contract: post-fix receipt must have POST_FIX phase."
    }
    if ([string]$reproduction.kind -eq "COMMAND") {
        if ([string]$postReceiptValue.source -ne "RUNTIME") {
            throw "Diagnostic contract: command reproduction requires runtime post-fix evidence."
        }
        if ([string]$postReceiptValue.command -cne [string]$reproduction.command) {
            throw "Diagnostic contract: post-fix receipt command must match the frozen reproduction signal."
        }
        $postBroken = switch ([string]$reproduction.broken_when) {
            "EXIT_ZERO" { [int]$postReceiptValue.exit_code -eq 0 }
            "EXIT_NONZERO" { [int]$postReceiptValue.exit_code -ne 0 }
            default { $false }
        }
        $expectedPost = if ($postBroken) { "BROKEN_OBSERVED" } else { "FIXED_OBSERVED" }
        if ([string]$postFix.observation -ne $expectedPost) {
            throw "Diagnostic contract: post-fix observation contradicts the runtime receipt."
        }
    }
}

switch ([string]$evidence.state) {
    "NOT_REPRODUCED" {
        if ([string]$preFix.observation -ne "NOT_REPRODUCED") {
            throw "Diagnostic contract: NOT_REPRODUCED state requires matching pre-fix observation."
        }
        if ([string]$postFix.observation -ne "NOT_RUN") {
            throw "Diagnostic contract: NOT_REPRODUCED cannot contain a post-fix replay."
        }
    }
    "PREFLIGHT" {
        if ([string]$preFix.observation -ne "BROKEN_OBSERVED") {
            throw "Diagnostic contract: PREFLIGHT requires observed broken behavior."
        }
        if ([string]$postFix.observation -ne "NOT_RUN") {
            throw "Diagnostic contract: PREFLIGHT cannot claim post-fix evidence."
        }
    }
    "FAILED_VERIFICATION" {
        if ([string]$preFix.observation -ne "BROKEN_OBSERVED") {
            throw "Diagnostic contract: FAILED_VERIFICATION requires observed broken behavior before the attempted change."
        }
        if ([string]$postFix.observation -ne "NOT_RUN") {
            throw "Diagnostic contract: FAILED_VERIFICATION cannot claim post-fix replay evidence."
        }
    }
    "FAILED_POST_FIX" {
        if ([string]$preFix.observation -ne "BROKEN_OBSERVED" -or [string]$postFix.observation -ne "BROKEN_OBSERVED") {
            throw "Diagnostic contract: FAILED_POST_FIX requires broken observations before and after the attempted change."
        }
    }
    "COMPLETE" {
        if ([string]$preFix.observation -ne "BROKEN_OBSERVED") {
            throw "Diagnostic contract: COMPLETE requires a broken pre-fix observation."
        }
        if ([string]$postFix.observation -ne "FIXED_OBSERVED") {
            throw "Diagnostic contract: COMPLETE requires the frozen signal to demonstrate the fix."
        }
        if (@($evidence.attempts).Count -lt 1) {
            throw "Diagnostic contract: COMPLETE requires at least one diagnostic attempt."
        }
    }
    default {
        throw "Diagnostic contract: invalid state: $($evidence.state)"
    }
}

Write-Output "PASS: diagnostic evidence contract"
