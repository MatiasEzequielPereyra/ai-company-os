function Get-WritableScopeFingerprint {
    param([Parameter(Mandatory=$true)][string]$TaskContent)

    $scope = [ordered]@{}
    foreach ($key in @("ID", "Type", "Work kind", "Owner", "Work request")) {
        $matches = [regex]::Matches($TaskContent, "(?m)^" + [regex]::Escape($key) + ":\s*(.*)$")
        if ($matches.Count -ne 1) { throw "Writable authorization scope requires exactly one task field: $key" }
        $scope[$key] = $matches[0].Groups[1].Value.Trim()
    }

    foreach ($key in @("Objective", "Acceptance Criteria")) {
        $matches = [regex]::Matches($TaskContent, "(?ms)^## " + [regex]::Escape($key) + "\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)")
        if ($matches.Count -ne 1) { throw "Writable authorization scope requires exactly one task section: $key" }
        $scope[$key] = $matches[0].Groups[1].Value.Trim()
    }

    $json = $scope | ConvertTo-Json -Depth 8 -Compress
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-WritableReceiptSection {
    param([Parameter(Mandatory=$true)][string]$Content)

    $sections = [regex]::Matches($Content, "(?ms)^## Authorization Receipt\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)")
    if ($sections.Count -ne 1) { throw "Work Request must contain exactly one canonical Authorization Receipt section." }
    return $sections[0].Groups[1].Value.Trim()
}

function Get-WritableReceiptField {
    param([Parameter(Mandatory=$true)][string]$Receipt,[Parameter(Mandatory=$true)][string]$Key)

    $matches = [regex]::Matches($Receipt, "(?m)^" + [regex]::Escape($Key) + ":\s*(.*?)\s*$")
    if ($matches.Count -ne 1) { throw "Authorization receipt must contain exactly one '$Key' field." }
    $value = $matches[0].Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Authorization receipt field '$Key' cannot be empty." }
    return $value
}

function Assert-WritableAuthorizationReceipt {
    param(
        [Parameter(Mandatory=$true)][string]$TaskId,
        [Parameter(Mandatory=$true)][string]$TaskContent,
        [Parameter(Mandatory=$true)][string]$WorkRequestContent,
        [Parameter(Mandatory=$true)][string]$WorkRequestId,
        [Parameter(Mandatory=$true)][string]$Operation
    )

    $workRequestIdentity = [regex]::Matches($WorkRequestContent, "(?m)^ID:\s*(.*?)\s*$")
    if ($workRequestIdentity.Count -ne 1 -or $workRequestIdentity[0].Groups[1].Value.Trim() -cne $WorkRequestId) {
        throw "Authorization receipt Work Request identity does not match task $TaskId."
    }
    $taskType = [regex]::Matches($TaskContent, "(?m)^Type:\s*(.*?)\s*$")
    $requestType = [regex]::Matches($WorkRequestContent, "(?m)^Type:\s*(.*?)\s*$")
    if ($taskType.Count -ne 1 -or $requestType.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace($taskType[0].Groups[1].Value.Trim()) -or
        $taskType[0].Groups[1].Value.Trim() -cne $requestType[0].Groups[1].Value.Trim()) {
        throw "Authorization receipt task and Work Request types are missing, ambiguous or inconsistent."
    }

    $requester = [regex]::Matches($WorkRequestContent, "(?m)^Requested by:\s*(.*?)\s*$")
    if ($requester.Count -ne 1 -or [string]::IsNullOrWhiteSpace($requester[0].Groups[1].Value.Trim())) {
        throw "Authorization receipt requester is missing or ambiguous."
    }
    $createdMatches = [regex]::Matches($WorkRequestContent, "(?m)^Created:\s*(.*?)\s*$")
    $createdAt = [DateTimeOffset]::MinValue
    if ($createdMatches.Count -ne 1 -or -not [DateTimeOffset]::TryParseExact(
        $createdMatches[0].Groups[1].Value.Trim(),
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$createdAt
    ) -or $createdAt -gt [DateTimeOffset]::UtcNow) {
        throw "Authorization receipt date/reference is missing, ambiguous or invalid."
    }

    $receipt = Get-WritableReceiptSection -Content $WorkRequestContent
    $requestedAction = Get-WritableReceiptField -Receipt $receipt -Key "Requested action"
    $permittedScope = Get-WritableReceiptField -Receipt $receipt -Key "Permitted scope"
    $implementationAuthorization = Get-WritableReceiptField -Receipt $receipt -Key "Implementation authorization"
    $authorizedTask = Get-WritableReceiptField -Receipt $receipt -Key "Authorized task"
    $authorizedOperation = Get-WritableReceiptField -Receipt $receipt -Key "Authorized operation"
    $authorizedExecutionMode = Get-WritableReceiptField -Receipt $receipt -Key "Authorized execution mode"
    $authorizedProviderInvocation = Get-WritableReceiptField -Receipt $receipt -Key "Authorized provider invocation"
    $authorizedWriteScope = Get-WritableReceiptField -Receipt $receipt -Key "Authorized write scope"
    $authorizedScope = Get-WritableReceiptField -Receipt $receipt -Key "Authorized scope SHA-256"
    $expiresAt = Get-WritableReceiptField -Receipt $receipt -Key "Authorization expires (UTC)"
    $retainedRestrictions = Get-WritableReceiptField -Receipt $receipt -Key "Retained restrictions"

    if ($implementationAuthorization -cne "AUTHORIZED") {
        throw "Work Request does not explicitly authorize implementation."
    }
    if ($authorizedTask -cne $TaskId -or $authorizedOperation -cne $Operation) {
        throw "Authorization receipt belongs to another task or operation."
    }
    if ($authorizedExecutionMode -cne "WRITABLE" -or
        $authorizedProviderInvocation -cne "ALLOWED" -or
        $authorizedWriteScope -cne "TASK_WORKTREE_ONLY") {
        throw "Authorization receipt does not explicitly permit writable execution, provider invocation and task-worktree writes."
    }
    if ($permittedScope -cnotmatch '(?i)(^|[^A-Z0-9_])WRITABLE_IMPLEMENTATION([^A-Z0-9_]|$)') {
        throw "Authorization receipt does not permit WRITABLE_IMPLEMENTATION."
    }
    if ($permittedScope -match '(?i)\b(?:READ[- ]ONLY|DRY[- ]RUN|NO WRIT(?:E|ABLE)|NO IMPLEMENTATION)\b') {
        throw "Authorization receipt retains a scope restriction that prohibits writable implementation."
    }
    if ($requestedAction -notmatch [regex]::Escape($TaskId)) {
        throw "Authorization receipt requested action is not bound to task $TaskId."
    }
    if ($authorizedScope -notmatch '^[a-fA-F0-9]{64}$' -or
        $authorizedScope.ToLowerInvariant() -cne (Get-WritableScopeFingerprint -TaskContent $TaskContent)) {
        throw "Authorization receipt scope is invalid or stale for task $TaskId."
    }
    if ($retainedRestrictions -cne "NONE") {
        throw "Authorization receipt retains restrictions; writable execution requires the explicit NONE value."
    }

    $expiry = [DateTimeOffset]::MinValue
    $parsed = [DateTimeOffset]::TryParseExact(
        $expiresAt,
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$expiry
    )
    if (-not $parsed -or $expiry -le [DateTimeOffset]::UtcNow -or $expiry -le $createdAt) {
        throw "Authorization receipt is invalid or expired."
    }

    $receiptSha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $receiptFingerprint = ([System.BitConverter]::ToString(
            $receiptSha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($WorkRequestContent))
        )).Replace("-","").ToLowerInvariant()
    }
    finally { $receiptSha.Dispose() }

    return [PSCustomObject]@{
        TaskId = $TaskId
        Operation = $Operation
        ScopeFingerprint = $authorizedScope.ToLowerInvariant()
        ReceiptFingerprint = $receiptFingerprint
        ExpiresAt = $expiry
    }
}

function Assert-WritableDependencies {
    param([Parameter(Mandatory=$true)][string]$TasksPath,[Parameter(Mandatory=$true)][string]$TaskContent,[Parameter(Mandatory=$true)][string]$TaskId)

    $sections = [regex]::Matches($TaskContent, "(?ms)^## Dependencies\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)")
    if ($sections.Count -ne 1) { throw "Task $TaskId must contain exactly one canonical Dependencies section." }

    $seen = @{}
    foreach ($line in @($sections[0].Groups[1].Value -split '\r?\n')) {
        $value = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq "-") { continue }
        if ($value -notmatch '^[-*]\s+(AICO-\d+)\s*$') { throw "Task $TaskId has an invalid dependency declaration: $value" }
        $dependencyId = $Matches[1]
        if ($seen.ContainsKey($dependencyId)) { throw "Task $TaskId has an ambiguous duplicate dependency: $dependencyId" }
        $seen[$dependencyId] = $true

        $dependencyPath = Join-Path $TasksPath ($dependencyId + ".md")
        if (-not (Test-Path -LiteralPath $dependencyPath -PathType Leaf)) { throw "Task $TaskId dependency is missing: $dependencyId" }
        $dependencyContent = Get-Content -LiteralPath $dependencyPath -Raw -Encoding UTF8
        $idMatches = [regex]::Matches($dependencyContent, "(?m)^ID:\s*(.*?)\s*$")
        $statusMatches = [regex]::Matches($dependencyContent, "(?m)^Status:\s*(.*?)\s*$")
        if ($idMatches.Count -ne 1 -or $idMatches[0].Groups[1].Value.Trim() -cne $dependencyId -or
            $statusMatches.Count -ne 1 -or $statusMatches[0].Groups[1].Value.Trim() -cne "DONE") {
            throw "Task $TaskId dependency is not authoritatively DONE: $dependencyId"
        }
    }
}
