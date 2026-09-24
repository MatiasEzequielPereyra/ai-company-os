param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [string]$ProjectPath = ".",

    [string]$WorkspacePath = "",

    [ValidateSet("Auto","OpenRouter","Gemini")]
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

function Read-Section {
    param([string]$Content,[string]$Section)
    $pattern = "(?ms)^## " + [regex]::Escape($Section) + "\s*\r?\n\s*\r?\n(.+?)(?:\r?\n\r?\n---|\r?\n\r?\n##|\z)"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}


function Write-Utf8NoBom {
    param([string]$Path,[string]$Value)
    [System.IO.File]::WriteAllText($Path,$Value,(New-Object System.Text.UTF8Encoding($false)))
}

function Get-ConfiguredModel {
    param([object]$Config,[string]$ProviderName,[string]$CollectionName)

    if ($null -eq $Config) { return "" }
    $collection = $Config.PSObject.Properties[$CollectionName]
    if ($null -eq $collection -or $null -eq $collection.Value) { return "" }

    $property = $collection.Value.PSObject.Properties[$ProviderName]
    if ($null -eq $property) { return "" }

    return [string]$property.Value
}

function Get-ChangedPaths {
    param([string]$Workspace)

    $paths = @()

    $tracked = @(& git -C $Workspace diff --name-only -- 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "git diff --name-only failed in writable workspace." }

    $untracked = @(& git -C $Workspace ls-files --others --exclude-standard 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "git ls-files --others failed in writable workspace." }

    foreach ($path in @($tracked + $untracked)) {
        $value = ([string]$path).Trim().Replace("\","/")
        if (-not [string]::IsNullOrWhiteSpace($value) -and $paths -notcontains $value) {
            $paths += $value
        }
    }

    return @($paths | Sort-Object)
}

function Test-LatestReviewRequiresChanges {
    param([string]$Root,[string]$TaskId)

    $reviewsDir = Join-Path $Root "docs\engineering\reviews"
    if (-not (Test-Path $reviewsDir)) { return $false }

    $latest = Get-ChildItem $reviewsDir -Filter ($TaskId + "-review-*.md") -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if ($null -eq $latest) { return $false }

    $content = Get-Content $latest.FullName -Raw -Encoding UTF8
    return ((Read-Field -Content $content -Key "Recommendation") -eq "CHANGES_REQUIRED")
}

function Test-MatchesAnyPattern {
    param([string]$Value,[object[]]$Patterns)

    foreach ($pattern in @($Patterns)) {
        if ($Value -match [string]$pattern) { return $true }
    }

    return $false
}

function Assert-NoReparseEscape {
    param(
        [string]$Workspace,
        [string]$TargetPath
    )

    $workspaceFull = [System.IO.Path]::GetFullPath($Workspace).TrimEnd([char[]]@("\","/"))
    $current = Split-Path $TargetPath -Parent

    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $currentFull = [System.IO.Path]::GetFullPath($current).TrimEnd([char[]]@("\","/"))

        if ([string]::Equals($currentFull,$workspaceFull,[System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        if (-not $currentFull.StartsWith($workspaceFull + [System.IO.Path]::DirectorySeparatorChar,[System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Writable path parent escaped the task worktree."
        }

        if (Test-Path $currentFull) {
            $item = Get-Item $currentFull -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Writable change path traverses a symlink/junction/reparse point: $currentFull"
            }
        }

        $parent = Split-Path $currentFull -Parent
        if ($parent -eq $currentFull) { break }
        $current = $parent
    }

    if (Test-Path $TargetPath) {
        $targetItem = Get-Item $TargetPath -Force
        if (($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Writable change target is a symlink/junction/reparse point: $TargetPath"
        }
    }
}

function Resolve-SafeChangePath {
    param(
        [string]$Workspace,
        [string]$RelativePath,
        [object]$Policy
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw "Writable change path cannot be empty."
    }

    $candidate = $RelativePath.Trim().Replace("\","/")

    if ([System.IO.Path]::IsPathRooted($candidate)) {
        throw "Writable change path must be repository-relative: $RelativePath"
    }

    $segments = @($candidate -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($segments.Count -eq 0) {
        throw "Writable change path is invalid: $RelativePath"
    }

    if ($segments -contains "..") {
        throw "Writable change path cannot contain '..': $RelativePath"
    }

    if ($segments -contains ".") {
        throw "Writable change path cannot contain '.' segments: $RelativePath"
    }

    $normalized = ($segments -join "/")
    $lower = $normalized.ToLowerInvariant()

    foreach ($prefixValue in @($Policy.protected_path_prefixes)) {
        $prefix = ([string]$prefixValue).Trim().Replace("\","/").TrimEnd("/").ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }

        if ($lower -eq $prefix -or $lower.StartsWith($prefix + "/")) {
            throw "Writable change path targets a protected control-plane path: $normalized"
        }
    }

    if (Test-MatchesAnyPattern -Value $lower -Patterns @($Policy.secret_name_patterns)) {
        throw "Writable change path looks secret-sensitive and is prohibited: $normalized"
    }

    $workspaceFull = [System.IO.Path]::GetFullPath($Workspace).TrimEnd([char[]]@("\","/"))
    $targetFull = [System.IO.Path]::GetFullPath((Join-Path $workspaceFull ($normalized.Replace("/","\"))))
    $prefixFull = $workspaceFull + [System.IO.Path]::DirectorySeparatorChar

    if (-not $targetFull.StartsWith($prefixFull,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Writable change path escapes the task worktree: $normalized"
    }

    Assert-NoReparseEscape -Workspace $workspaceFull -TargetPath $targetFull

    return [PSCustomObject]@{
        Relative = $normalized
        FullPath = $targetFull
    }
}

function Assert-SafeArgument {
    param([string]$Argument)

    if ([string]::IsNullOrWhiteSpace($Argument)) { return }

    if ($Argument -match '[\r\n]') {
        throw "Verification arguments cannot contain newlines."
    }

    if ($Argument -match '(?i)[A-Z]:[\\/]') {
        throw "Verification command contains an absolute Windows path."
    }

    if ($Argument.StartsWith("/") -and -not $Argument.StartsWith("--")) {
        throw "Verification command contains an absolute path."
    }

    $normalized = $Argument.Replace("\","/")
    if (@($normalized -split "/") -contains "..") {
        throw "Verification command contains path traversal."
    }
}

function Get-SafeCommand {
    param(
        [string]$Command,
        [object]$Policy
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw "Verification command cannot be empty."
    }

    if ($Command -match '[\r\n]') {
        throw "Verification command must be a single line."
    }

    $allowed = $false
    foreach ($pattern in @($Policy.verification_command_patterns)) {
        if ($Command -match [string]$pattern) {
            $allowed = $true
            break
        }
    }

    if (-not $allowed) {
        throw "Verification command is not allowed by writable policy: $Command"
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Command,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if (@($parseErrors).Count -gt 0) {
        throw "Verification command has PowerShell parse errors: $Command"
    }

    $statements = @($ast.EndBlock.Statements)
    if ($statements.Count -ne 1 -or $statements[0] -isnot [System.Management.Automation.Language.PipelineAst]) {
        throw "Verification command must contain exactly one simple command."
    }

    $pipeline = $statements[0]
    if (@($pipeline.PipelineElements).Count -ne 1) {
        throw "Verification pipelines are prohibited."
    }

    $commandAst = $pipeline.PipelineElements[0]
    if ($commandAst -isnot [System.Management.Automation.Language.CommandAst]) {
        throw "Verification command must be a direct executable invocation."
    }

    if (@($commandAst.Redirections).Count -gt 0) {
        throw "Verification redirections are prohibited."
    }

    $parts = @()
    foreach ($element in @($commandAst.CommandElements)) {
        if ($element -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
            throw "Verification command may contain only literal executable/arguments."
        }

        $parts += [string]$element.Value
    }

    if ($parts.Count -lt 1) {
        throw "Verification command has no executable."
    }

    foreach ($argument in @($parts | Select-Object -Skip 1)) {
        Assert-SafeArgument -Argument $argument
    }

    return [PSCustomObject]@{
        Executable = $parts[0]
        Arguments = @($parts | Select-Object -Skip 1)
        Display = $Command
    }
}

function Invoke-VerificationCommand {
    param(
        [object]$SafeCommand,
        [string]$Workspace
    )

    $resolved = Get-Command $SafeCommand.Executable -ErrorAction SilentlyContinue
    if ($null -eq $resolved) {
        throw "Verification executable is not available: $($SafeCommand.Executable)"
    }

    Push-Location $Workspace
    try {
        $lines = New-Object System.Collections.Generic.List[string]
        & $SafeCommand.Executable @($SafeCommand.Arguments) 2>&1 | ForEach-Object {
            $line = $_.ToString()
            [void]$lines.Add($line)
            Write-Host $line
        }

        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }

        $output = ($lines.ToArray() -join [Environment]::NewLine)
        if ($output.Length -gt 30000) {
            $output = $output.Substring(0,30000) + [Environment]::NewLine + "[TRUNCATED]"
        }

        if ($exitCode -ne 0) {
            throw ("Verification command failed with exit code " + $exitCode + ": " + $SafeCommand.Display)
        }

        return $output
    }
    finally {
        Pop-Location
    }
}

function Restore-PlannedFiles {
    param([hashtable]$Backups)

    foreach ($entry in $Backups.GetEnumerator()) {
        $state = $entry.Value

        if ($state.Existed) {
            $parent = Split-Path $state.Path -Parent
            if (-not (Test-Path $parent)) {
                New-Item -ItemType Directory -Force -Path $parent | Out-Null
            }
            [System.IO.File]::WriteAllBytes($state.Path,$state.Bytes)
        }
        elseif (Test-Path $state.Path) {
            Remove-Item $state.Path -Force -ErrorAction SilentlyContinue
        }
    }
}

$root = (Resolve-Path $ProjectPath).Path
$tasksPath = Join-Path $root "tasks"
$taskPath = Join-Path $tasksPath ($Id + ".md")

if (-not (Test-Path (Join-Path $root ".git"))) {
    throw "Writable execution requires a Git repository."
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required for writable execution."
}

if (-not (Test-Path $taskPath)) {
    throw "Task not found: $taskPath"
}

$task = Get-Content $taskPath -Raw -Encoding UTF8
$status = Read-Field -Content $task -Key "Status"
$owner = Read-Field -Content $task -Key "Owner"

if ($status -notin @("READY","ACTIVE")) {
    throw "Task $Id must be READY or ACTIVE for writable execution. Current status: $status"
}

if ([string]::IsNullOrWhiteSpace($owner)) {
    throw "Task $Id has no owner."
}

if ([string]::IsNullOrWhiteSpace($WorkspacePath)) {
    $workspaceRoot = Join-Path (Split-Path -Parent $root) ((Split-Path $root -Leaf) + "-worktrees")
    $WorkspacePath = Join-Path $workspaceRoot $Id
}

if (-not (Test-Path $WorkspacePath)) {
    throw "Task worktree not found: $WorkspacePath. Create it with scripts/new-agent-workspace.ps1 first."
}

$workspace = (Resolve-Path $WorkspacePath).Path

if ([string]::Equals(
    [System.IO.Path]::GetFullPath($workspace).TrimEnd([char[]]@("\","/")),
    [System.IO.Path]::GetFullPath($root).TrimEnd([char[]]@("\","/")),
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Writable execution refuses to use the primary checkout as its workspace."
}

$registered = $false
$workspaceFull = [System.IO.Path]::GetFullPath($workspace).TrimEnd([char[]]@("\","/"))
$worktreeLines = @(& git -C $root worktree list --porcelain 2>$null)
if ($LASTEXITCODE -ne 0) { throw "git worktree list failed." }

foreach ($line in $worktreeLines) {
    if (-not $line.StartsWith("worktree ")) { continue }
    $candidate = [System.IO.Path]::GetFullPath($line.Substring(9).Trim()).TrimEnd([char[]]@("\","/"))

    if ([string]::Equals($candidate,$workspaceFull,[System.StringComparison]::OrdinalIgnoreCase)) {
        $registered = $true
        break
    }
}

if (-not $registered) {
    throw "Workspace is not a registered Git worktree of the project: $workspace"
}

$expectedBranch = "aico/" + $Id.ToLowerInvariant()
$currentBranch = ([string](& git -C $workspace branch --show-current)).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve writable worktree branch." }

if ($currentBranch -ne $expectedBranch) {
    throw "Writable workspace branch mismatch. Expected '$expectedBranch', found '$currentBranch'."
}

$corrective = Test-LatestReviewRequiresChanges -Root $root -TaskId $Id
$baselineChanged = @(Get-ChangedPaths -Workspace $workspace)

if ($baselineChanged.Count -gt 0 -and -not $corrective) {
    throw ("Writable worktree must be clean for a fresh implementation. Existing changes: " + ($baselineChanged -join ", "))
}

if ($status -eq "READY") {
    $advance = Join-Path $PSScriptRoot "advance-task.ps1"
    if (-not (Test-Path $advance)) { throw "advance-task.ps1 not found: $advance" }

    & $advance -Id $Id -Status ACTIVE -Actor $owner -Reason "Writable implementation execution started in isolated task worktree." -Evidence ("Worktree: " + $workspace) -TasksPath $tasksPath

    $task = Get-Content $taskPath -Raw -Encoding UTF8
    $status = Read-Field -Content $task -Key "Status"
}

if ($status -ne "ACTIVE") {
    throw "Task $Id could not be activated for writable execution."
}

$dispatchPath = Join-Path $root ("docs\engineering\dispatch\" + $Id + ".md")
$rolePath = Join-Path $root (".codex\agents\" + $owner + ".md")
$schemaPath = Join-Path $root "schemas\writable-change-set.schema.json"
$policyPath = Join-Path $root ".codex\writable-policy.json"
$routerPath = Join-Path $PSScriptRoot "provider-router.ps1"
$contextBuilderPath = Join-Path $PSScriptRoot "build-agent-context.ps1"
$requiredResolverPath = Join-Path $PSScriptRoot "resolve-writable-required-files.ps1"
$submitPath = Join-Path $PSScriptRoot "submit-task-result.ps1"

foreach ($required in @($dispatchPath,$rolePath,$schemaPath,$policyPath,$routerPath,$contextBuilderPath,$requiredResolverPath,$submitPath)) {
    if (-not (Test-Path $required)) {
        throw "Required writable runtime component not found: $required"
    }
}

$policy = Get-Content $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$configPath = Join-Path $root ".codex\provider-config.json"
$config = $null

if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$taskText = Get-Content $taskPath -Raw -Encoding UTF8
$dispatchText = Get-Content $dispatchPath -Raw -Encoding UTF8
$roleText = Get-Content $rolePath -Raw -Encoding UTF8

$maxChars = 120000
if ($null -ne $config -and $null -ne $config.writable_context_max_chars) {
    $maxChars = [int]$config.writable_context_max_chars
}
elseif ($null -ne $config -and $null -ne $config.context_max_chars) {
    $maxChars = [Math]::Min([int]$config.context_max_chars,120000)
}

$requiredSourceText = @(
    (Read-Section -Content $taskText -Section "Objective"),
    (Read-Section -Content $taskText -Section "Context"),
    (Read-Section -Content $taskText -Section "Requirements"),
    (Read-Section -Content $taskText -Section "Acceptance Criteria"),
    (Read-Section -Content $taskText -Section "Testing Requirements"),
    (Read-Section -Content $dispatchText -Section "Objective"),
    (Read-Section -Content $dispatchText -Section "Context"),
    (Read-Section -Content $dispatchText -Section "Expected Output"),
    (Read-Section -Content $dispatchText -Section "Acceptance Criteria"),
    (Read-Section -Content $dispatchText -Section "Testing Requirements")
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$requiredFiles = @(& $requiredResolverPath -ProjectPath $workspace -SourceText $requiredSourceText -PolicyPath $policyPath)

if ($requiredFiles.Count -gt 0) {
    Write-Host ("Writable required files: " + ($requiredFiles -join ", ")) -ForegroundColor DarkGray
}
else {
    Write-Host "Writable required files: none resolved from task/dispatch." -ForegroundColor DarkGray
}

Write-Host "Building writable repository context from isolated worktree..." -ForegroundColor DarkGray
$context = & $contextBuilderPath -ProjectPath $workspace -Id $Id -Owner $owner -MaxChars $maxChars -RequiredFiles $requiredFiles

$prompt = @(
    "You are executing an AUTHORIZED IMPLEMENTATION task for AI Company OS.",
    "",
    "Task: $Id",
    "Role: $owner",
    "Writable worktree branch: $currentBranch",
    "",
    "You do NOT have shell or filesystem access.",
    "Use only the supplied task, dispatch, role instructions and repository context.",
    "Return a structured change set only.",
    "",
    "Each WRITE operation must contain the COMPLETE desired UTF-8 text content of that file.",
    "DELETE is allowed only when the task explicitly requires removing that file.",
    "Use repository-relative paths only.",
    "Never target absolute paths, '..', .git, .env, credentials, private keys, service accounts or lifecycle/control-plane artifacts.",
    "Do not propose merge, push, deploy, rebase, git reset, package publication or secret access.",
    "",
    "Verification commands are suggestions only. They are never executed unless the local writable policy explicitly allows them.",
    "Prefer deterministic repository-local verification such as tests, lint, typecheck, build, or dedicated verify scripts.",
    "",
    "Outcome semantics:",
    "- COMPLETED means you produced a complete implementation change set ready for local application and verification.",
    "- BLOCKED means implementation cannot be safely produced from the supplied evidence. BLOCKED must return no changes and no verification commands.",
    "",
    "TASK FILE:",
    $taskText,
    "",
    "DISPATCH PACKET:",
    $dispatchText,
    "",
    "ROLE INSTRUCTIONS:",
    $roleText,
    "",
    "Return only JSON matching the supplied writable change-set schema."
) -join [Environment]::NewLine

$tempRoot = Join-Path $env:TEMP "ai-company-os-writable"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$outputPath = Join-Path $tempRoot ($Id + "-" + [Guid]::NewGuid().ToString("N") + ".json")

$primaryStatusBefore = (@(& git -C $root status --porcelain --untracked-files=no 2>$null) -join [Environment]::NewLine)
if ($LASTEXITCODE -ne 0) { throw "Unable to snapshot primary checkout status." }

$execution = $null
$result = $null

try {
    if ($Provider -eq "Auto") {
        $order = @("OpenRouter","Gemini")

        if ($null -ne $config -and $null -ne $config.writable_auto_order -and @($config.writable_auto_order).Count -gt 0) {
            $order = @($config.writable_auto_order | ForEach-Object { [string]$_ })
        }

        $providerErrors = @()

        foreach ($candidate in $order) {
            if ($candidate -notin @("OpenRouter","Gemini")) { continue }

            if ($candidate -eq "OpenRouter" -and [string]::IsNullOrWhiteSpace($env:OPENROUTER_API_KEY)) {
                $providerErrors += "OpenRouter: OPENROUTER_API_KEY not configured"
                continue
            }

            if ($candidate -eq "Gemini" -and [string]::IsNullOrWhiteSpace($env:GEMINI_API_KEY)) {
                $providerErrors += "Gemini: GEMINI_API_KEY not configured"
                continue
            }

            $candidateModel = Get-ConfiguredModel -Config $config -ProviderName $candidate -CollectionName "writable_models"
            if ([string]::IsNullOrWhiteSpace($candidateModel)) {
                $candidateModel = Get-ConfiguredModel -Config $config -ProviderName $candidate -CollectionName "models"
            }

            $freeModelsProperty = $policy.free_provider_models.PSObject.Properties[$candidate]
            $freeModels = @()
            if ($null -ne $freeModelsProperty) {
                $freeModels = @($freeModelsProperty.Value | ForEach-Object { [string]$_ })
            }

            if ([string]::IsNullOrWhiteSpace($candidateModel) -or $freeModels -notcontains $candidateModel) {
                $providerErrors += ($candidate + ": no free writable model is configured")
                continue
            }

            try {
                $execution = & $routerPath -Provider $candidate -ProjectPath $root -Prompt $prompt -Context $context -SchemaPath $schemaPath -OutputPath $outputPath -Model $candidateModel
                break
            }
            catch {
                $providerErrors += ($candidate + ": " + $_.Exception.Message)
            }
        }

        if ($null -eq $execution) {
            throw ("No free writable provider succeeded. " + ($providerErrors -join " | "))
        }
    }
    else {
        $selectedModel = $Model
        if ([string]::IsNullOrWhiteSpace($selectedModel)) {
            $selectedModel = Get-ConfiguredModel -Config $config -ProviderName $Provider -CollectionName "writable_models"
        }
        if ([string]::IsNullOrWhiteSpace($selectedModel)) {
            $selectedModel = Get-ConfiguredModel -Config $config -ProviderName $Provider -CollectionName "models"
        }

        $execution = & $routerPath -Provider $Provider -ProjectPath $root -Prompt $prompt -Context $context -SchemaPath $schemaPath -OutputPath $outputPath -Model $selectedModel
    }

    if (-not (Test-Path $outputPath)) {
        throw "Writable provider did not produce structured output."
    }

    $result = Get-Content $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
finally {
    if (Test-Path $outputPath) {
        Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
    }
}

if ($null -eq $result) {
    throw "Writable provider produced no usable result."
}

$changes = @($result.changes)
$verificationCommands = @($result.verification_commands)

if ($result.outcome -eq "BLOCKED") {
    if ($changes.Count -gt 0 -or $verificationCommands.Count -gt 0) {
        throw "BLOCKED writable result must not contain changes or verification commands."
    }

    $evidenceDir = Join-Path $root "docs\engineering\writable-evidence"
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
    $evidencePath = Join-Path $evidenceDir ($Id + ".md")
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $blockedReport = @(
        "# Writable Execution Evidence - $Id",
        "",
        "Generated: $now",
        "Outcome: BLOCKED",
        "Provider: $($execution.Provider)",
        "Model: $($execution.Model)",
        "Worktree: $workspace",
        "Branch: $currentBranch",
        "",
        "## Summary",
        "",
        [string]$result.summary,
        "",
        "## Report",
        "",
        [string]$result.report_markdown,
        "",
        "## Blockers",
        "",
        [string]$result.blockers
    ) -join [Environment]::NewLine

    Write-Utf8NoBom -Path $evidencePath -Value $blockedReport

    & $submitPath -ProjectPath $root -Id $Id -Outcome BLOCKED -Summary ([string]$result.summary) -ChangedArtifacts ("docs/engineering/writable-evidence/" + (Split-Path $evidencePath -Leaf)) -Verification ([string]$result.verification) -Decisions ([string]$result.decisions) -Blockers ([string]$result.blockers) -RecommendedNext ([string]$result.recommended_next)
    return
}

if ($result.outcome -ne "COMPLETED") {
    throw "Unsupported writable outcome: $($result.outcome)"
}

if ($changes.Count -lt 1) {
    throw "COMPLETED writable result must contain at least one change."
}

if ($verificationCommands.Count -lt 1) {
    throw "COMPLETED writable result must contain at least one verification command."
}

if ($changes.Count -gt [int]$policy.max_changed_files) {
    throw "Writable change set exceeds max_changed_files policy."
}

if ($verificationCommands.Count -gt [int]$policy.max_verification_commands) {
    throw "Writable change set exceeds max_verification_commands policy."
}

$planned = @{}
$backups = @{}
$totalWriteBytes = 0
$effectiveChanges = 0

try {
    foreach ($change in $changes) {
        $safe = Resolve-SafeChangePath -Workspace $workspace -RelativePath ([string]$change.path) -Policy $policy
        $key = $safe.Relative.ToLowerInvariant()

        if ($planned.ContainsKey($key)) {
            throw "Writable change set contains duplicate path: $($safe.Relative)"
        }

        $planned[$key] = $safe.Relative

        $existed = Test-Path $safe.FullPath -PathType Leaf
        $bytes = $null
        if ($existed) {
            $bytes = [System.IO.File]::ReadAllBytes($safe.FullPath)
        }

        $backups[$key] = [PSCustomObject]@{
            Path = $safe.FullPath
            Existed = $existed
            Bytes = $bytes
        }

        $operation = ([string]$change.operation).ToUpperInvariant()

        if ($operation -eq "WRITE") {
            $contentValue = [string]$change.content
            $writeBytes = [System.Text.Encoding]::UTF8.GetByteCount($contentValue)

            if ($writeBytes -gt [int]$policy.max_file_bytes) {
                throw "Writable file exceeds max_file_bytes policy: $($safe.Relative)"
            }

            $totalWriteBytes += $writeBytes
            if ($totalWriteBytes -gt [int]$policy.max_total_write_bytes) {
                throw "Writable change set exceeds max_total_write_bytes policy."
            }

            $same = $false
            if ($existed) {
                $existingText = [System.IO.File]::ReadAllText($safe.FullPath,[System.Text.Encoding]::UTF8)
                $same = ($existingText -ceq $contentValue)
            }

            $parent = Split-Path $safe.FullPath -Parent
            if (-not (Test-Path $parent)) {
                New-Item -ItemType Directory -Force -Path $parent | Out-Null
            }

            Write-Utf8NoBom -Path $safe.FullPath -Value $contentValue
            if (-not $same) { $effectiveChanges++ }
        }
        elseif ($operation -eq "DELETE") {
            if (-not $existed) {
                throw "Writable DELETE target does not exist as a file: $($safe.Relative)"
            }

            Remove-Item $safe.FullPath -Force
            $effectiveChanges++
        }
        else {
            throw "Unsupported writable operation: $operation"
        }
    }

    if ($effectiveChanges -lt 1) {
        throw "Writable provider proposed no effective file changes."
    }

    & git -C $workspace diff --check
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed after applying writable change set."
    }

    $verificationLog = New-Object System.Collections.Generic.List[string]

    foreach ($commandText in $verificationCommands) {
        $safeCommand = Get-SafeCommand -Command ([string]$commandText) -Policy $policy
        Write-Host ""
        Write-Host ("Verification: " + $safeCommand.Display) -ForegroundColor Cyan
        $commandOutput = Invoke-VerificationCommand -SafeCommand $safeCommand -Workspace $workspace

        [void]$verificationLog.Add(
            ("$ " + $safeCommand.Display + [Environment]::NewLine + $commandOutput).Trim()
        )
    }

    $changedAfter = @(Get-ChangedPaths -Workspace $workspace)
    $allowedChanged = @{}

    foreach ($path in $baselineChanged) {
        $allowedChanged[$path.ToLowerInvariant()] = $true
    }
    foreach ($path in $planned.Values) {
        $allowedChanged[$path.ToLowerInvariant()] = $true
    }

    foreach ($path in $changedAfter) {
        if (-not $allowedChanged.ContainsKey($path.ToLowerInvariant())) {
            throw "Verification introduced an unapproved repository change: $path"
        }
    }

    $primaryStatusAfter = (@(& git -C $root status --porcelain --untracked-files=no 2>$null) -join [Environment]::NewLine)
    if ($LASTEXITCODE -ne 0) { throw "Unable to verify primary checkout status." }

    if ($primaryStatusAfter -cne $primaryStatusBefore) {
        throw "Primary checkout changed during writable source execution. Refusing to submit the result."
    }

    $diffLines = @(& git -C $workspace diff --no-ext-diff -- 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Unable to obtain writable git diff." }

    $diffText = $diffLines -join [Environment]::NewLine
    $diffHash = ""
    if (-not [string]::IsNullOrWhiteSpace($diffText)) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($diffText))
            $diffHash = ([System.BitConverter]::ToString($hashBytes)).Replace("-","").ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }

    $evidenceDir = Join-Path $root "docs\engineering\writable-evidence"
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
    $evidencePath = Join-Path $evidenceDir ($Id + ".md")
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $verificationText = $verificationLog.ToArray() -join ([Environment]::NewLine + [Environment]::NewLine)

    $evidence = @(
        "# Writable Execution Evidence - $Id",
        "",
        "Generated: $now",
        "Outcome: COMPLETED",
        "Provider: $($execution.Provider)",
        "Model: $($execution.Model)",
        "Worktree: $workspace",
        "Branch: $currentBranch",
        "Corrective run: $corrective",
        "Git diff SHA256: $diffHash",
        "",
        "## Summary",
        "",
        [string]$result.summary,
        "",
        "## Changed Paths",
        "",
        (($changedAfter | ForEach-Object { "- " + $_ }) -join [Environment]::NewLine),
        "",
        "## Verification",
        "",
        $verificationText,
        "",
        "## Agent Verification Notes",
        "",
        [string]$result.verification,
        "",
        "## Agent Report",
        "",
        [string]$result.report_markdown,
        "",
        "## Decisions",
        "",
        [string]$result.decisions,
        "",
        "## Runtime Guarantees",
        "",
        "- Source writes were restricted to the registered task worktree.",
        "- The primary checkout source state was unchanged during application and verification.",
        "- No merge, push, deploy, rebase or automatic commit was performed.",
        "- Verification commands passed the local writable policy before execution."
    ) -join [Environment]::NewLine

    Write-Utf8NoBom -Path $evidencePath -Value $evidence

    $changedArtifacts = (($changedAfter + @("docs/engineering/writable-evidence/" + (Split-Path $evidencePath -Leaf))) -join "; ")
    $verificationSummary = "git diff --check PASS. " + (($verificationCommands | ForEach-Object { $_ + " PASS" }) -join "; ")

    & $submitPath -ProjectPath $root -Id $Id -Outcome COMPLETED -Summary ([string]$result.summary) -ChangedArtifacts $changedArtifacts -Verification $verificationSummary -Decisions ([string]$result.decisions) -Blockers "NONE" -RecommendedNext "REVIEW"

    Write-Host ""
    Write-Host "Writable implementation completed safely." -ForegroundColor Green
    Write-Host "Task: $Id"
    Write-Host "Worktree: $workspace"
    Write-Host "Branch: $currentBranch"
    Write-Host "Evidence: $evidencePath"
    Write-Host "The worktree changes remain uncommitted for independent review." -ForegroundColor DarkYellow
}
catch {
    Restore-PlannedFiles -Backups $backups
    throw
}
