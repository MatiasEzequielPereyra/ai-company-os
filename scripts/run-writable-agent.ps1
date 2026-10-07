param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [string]$ProjectPath = ".",

    [string]$WorkspacePath = "",

    [ValidateSet("Auto","Ollama","OpenRouter","Gemini")]
    [string]$Provider = "Auto",

    [string]$Model = ""
)

$ErrorActionPreference = "Stop"

function Get-AicoTempPath {
    if ($env:OS -eq "Windows_NT") {
        $localAppData = [Environment]::GetFolderPath(
            [Environment+SpecialFolder]::LocalApplicationData
        )

        if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
            $candidate = Join-Path $localAppData "Temp"

            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $candidate | Out-Null
            }

            return (Get-Item -LiteralPath $candidate).FullName
        }
    }

    foreach ($candidate in @(
        $env:TEMP,
        $env:TMP,
        [System.IO.Path]::GetTempPath()
    )) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $candidate | Out-Null
            }

            return (Get-Item -LiteralPath $candidate).FullName
        }
        catch {
            continue
        }
    }

    throw "Unable to resolve a writable temporary directory."
}

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

function Invoke-GitOutput {
    param([string[]]$Arguments,[string]$FailureMessage)

    # Git read commands may emit LF/CRLF warnings while exiting zero.
    # Keep stdout only and restore strict preferences before checking failure.
    $savedErrorActionPreference = $ErrorActionPreference
    $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $savedNativePreference = if ($null -ne $nativePreference) { $nativePreference.Value } else { $null }
    try {
        $ErrorActionPreference = "Continue"
        $PSNativeCommandUseErrorActionPreference = $false
        $output = @(& git @Arguments 2>$null)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
        if ($null -ne $nativePreference) { $PSNativeCommandUseErrorActionPreference = $savedNativePreference }
        else { Remove-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Local -ErrorAction SilentlyContinue }
    }
    if ($exitCode -ne 0) { throw $FailureMessage }
    return $output
}

function Get-ChangedPaths {
    param([string]$Workspace)

    $paths = @()
    $tracked = @(Invoke-GitOutput -Arguments @("-C",$Workspace,"diff","--name-only","--") -FailureMessage "git diff --name-only failed in writable workspace.")
    $untracked = @(Invoke-GitOutput -Arguments @("-C",$Workspace,"ls-files","--others","--exclude-standard") -FailureMessage "git ls-files --others failed in writable workspace.")

    foreach ($path in @($tracked + $untracked)) {
        $value = ([string]$path).Trim().Replace("\","/")
        if (-not [string]::IsNullOrWhiteSpace($value) -and $paths -notcontains $value) {
            $paths += $value
        }
    }

    return @($paths | Sort-Object)
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

function Get-CorrectiveSourceEvidence {
    param([string]$Workspace,[string]$ProjectRoot,[string[]]$Paths,[object]$Policy)

    $sourcePaths = @($Paths | Sort-Object -Unique)
    $requiredContextMaxFiles = if ($null -ne $Policy.required_context_max_files) { [int]$Policy.required_context_max_files } else { 8 }
    $requiredContextMaxTotalBytes = if ($null -ne $Policy.required_context_max_total_bytes) { [long]$Policy.required_context_max_total_bytes } else { 100000L }
    $captureFileLimit = [int]$Policy.max_changed_files + $requiredContextMaxFiles
    # Corrective evidence contains both the current candidate and the primary
    # comparison view. Do not reuse the write-set ceiling as if those reads were
    # new writes; derive a bounded capture ceiling from both existing policies.
    $captureBytesLimit = 2L * ([long]$Policy.max_total_write_bytes + $requiredContextMaxTotalBytes)
    if ($sourcePaths.Count -gt $captureFileLimit) {
        throw "Corrective source inventory exceeds combined writable/required context file-count limit: $captureFileLimit"
    }
    $builder = New-Object Text.StringBuilder
    [void]$builder.AppendLine("===== BEGIN CORRECTIVE IMPLEMENTATION SOURCE =====")
    [void]$builder.AppendLine("Provenance: current file captures; hashes identify these bytes, not an immutable owner snapshot.")
    [void]$builder.AppendLine("CANDIDATE SOURCE is the current isolated task worktree. PRIMARY PROJECT COMPARISON is the current primary project source, provided for comparison only; it is not the candidate or a claimed immutable Git baseline.")
    $totalBytes = [long]0
    foreach ($relative in $sourcePaths) {
        if ($relative -match '[\r\n]') { throw "Corrective source path contains a newline." }
        foreach ($capture in @(
            [pscustomobject]@{ Root=$Workspace; Label='CANDIDATE SOURCE' },
            [pscustomobject]@{ Root=$ProjectRoot; Label='PRIMARY PROJECT COMPARISON' }
        )) {
            $safe = Resolve-SafeChangePath -Workspace $capture.Root -RelativePath $relative -Policy $Policy
            [void]$builder.AppendLine("===== $($capture.Label): $($safe.Relative) =====")
            if (-not (Test-Path -LiteralPath $safe.FullPath)) {
                [void]$builder.AppendLine("ABSENT IN THIS CAPTURE (missing or deleted); no file content supplied.")
                continue
            }
            if (-not (Test-Path -LiteralPath $safe.FullPath -PathType Leaf)) {
                throw "Corrective source path is not a regular file: $($safe.Relative)"
            }
            $stream = $null
            $memory = $null
            $sha = $null
            try {
                $stream = [IO.File]::Open($safe.FullPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
                if ($stream.Length -gt [long]$Policy.max_file_bytes) {
                    throw "Corrective source exceeds max_file_bytes policy: $($safe.Relative)"
                }
                if ($totalBytes + $stream.Length -gt $captureBytesLimit) {
                    throw "Corrective source inventory exceeds combined writable/required context capture limit."
                }
                $memory = New-Object IO.MemoryStream
                $stream.CopyTo($memory)
                $bytes = $memory.ToArray()
                $totalBytes += $bytes.LongLength
                $sha = [Security.Cryptography.SHA256]::Create()
                $digest = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
                $utf8 = New-Object Text.UTF8Encoding($false,$true)
                $text = $utf8.GetString($bytes)
                [void]$builder.AppendLine("SHA256: $digest; Bytes: $($bytes.LongLength)")
                [void]$builder.AppendLine($text)
            } finally {
                if ($null -ne $sha) { $sha.Dispose() }
                if ($null -ne $memory) { $memory.Dispose() }
                if ($null -ne $stream) { $stream.Dispose() }
            }
        }
    }
    [void]$builder.AppendLine("===== END CORRECTIVE IMPLEMENTATION SOURCE =====")
    return $builder.ToString()
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
        # PowerShell parses native flags such as -B and -m as parameters.
        # Admit only standalone literal flags; attached arguments/expressions
        # still fail the same literal-command contract.
        if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
            $null -eq $element.Argument -and
            $element.Extent.Text -cmatch '^--?[A-Za-z][A-Za-z0-9_-]*$') {
            $parts += [string]$element.Extent.Text
            continue
        }
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
        # Native stderr may contain warnings even when the command succeeds.
        # Capture under native-friendly preferences, then restore strict handling
        # before formatting/logging. Verification still depends on the exit code.
        $savedErrorActionPreference = $ErrorActionPreference
        $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
        $savedNativePreference = if ($null -ne $nativePreference) { $nativePreference.Value } else { $null }
        try {
            $ErrorActionPreference = "Continue"
            $PSNativeCommandUseErrorActionPreference = $false
            $capturedOutput = @(& $SafeCommand.Executable @($SafeCommand.Arguments) 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedErrorActionPreference
            if ($null -ne $nativePreference) {
                $PSNativeCommandUseErrorActionPreference = $savedNativePreference
            }
            else {
                Remove-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Local -ErrorAction SilentlyContinue
            }
        }

        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $capturedOutput) {
            $line = $entry.ToString()
            [void]$lines.Add($line)
            Write-Host $line
        }

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

function Get-Sha256Hex {
    param([string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Invoke-DiagnosticCommand {
    param(
        [object]$SafeCommand,
        [string]$Workspace
    )

    $resolved = Get-Command $SafeCommand.Executable -ErrorAction SilentlyContinue
    if ($null -eq $resolved) {
        throw "Diagnostic executable is not available: $($SafeCommand.Executable)"
    }

    Push-Location $Workspace
    try {
        $savedErrorActionPreference = $ErrorActionPreference
        $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
        $savedNativePreference = if ($null -ne $nativePreference) { $nativePreference.Value } else { $null }

        try {
            $ErrorActionPreference = "Continue"
            $PSNativeCommandUseErrorActionPreference = $false
            $capturedOutput = @(& $SafeCommand.Executable @($SafeCommand.Arguments) 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedErrorActionPreference
            if ($null -ne $nativePreference) {
                $PSNativeCommandUseErrorActionPreference = $savedNativePreference
            }
            else {
                Remove-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Local -ErrorAction SilentlyContinue
            }
        }

        if ($null -eq $exitCode) { $exitCode = 0 }

        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $capturedOutput) {
            $line = $entry.ToString()
            [void]$lines.Add($line)
            Write-Host $line
        }

        $output = $lines.ToArray() -join [Environment]::NewLine
        if ($output.Length -gt 30000) {
            $output = $output.Substring(0,30000) + [Environment]::NewLine + "[TRUNCATED]"
        }

        return [PSCustomObject]@{
            ExitCode = [int]$exitCode
            Output = $output
            OutputSha256 = Get-Sha256Hex -Value $output
        }
    }
    finally {
        Pop-Location
    }
}

function Test-DiagnosticExitCondition {
    param(
        [int]$ExitCode,
        [string]$Condition
    )

    switch ($Condition) {
        "EXIT_ZERO" { return ($ExitCode -eq 0) }
        "EXIT_NONZERO" { return ($ExitCode -ne 0) }
        default { throw "Unsupported diagnostic exit condition: $Condition" }
    }
}

function New-DiagnosticReceipt {
    param(
        [string]$Id,
        [string]$Phase,
        [string]$Command,
        [object]$CommandResult
    )

    $excerpt = [string]$CommandResult.Output
    if ($excerpt.Length -gt 4000) {
        $excerpt = $excerpt.Substring(0,4000) + [Environment]::NewLine + "[TRUNCATED]"
    }

    return [ordered]@{
        id = $Id
        phase = $Phase
        source = "RUNTIME"
        command = $Command
        exit_code = [int]$CommandResult.ExitCode
        output_sha256 = [string]$CommandResult.OutputSha256
        output_excerpt = $excerpt
    }
}

function Save-DiagnosticArtifact {
    param(
        [string]$Path,
        [object]$Artifact
    )

    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    Write-Utf8NoBom -Path $Path -Value ($Artifact | ConvertTo-Json -Depth 100)
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
$workKind = Read-Field -Content $task -Key "Work kind"
$taskType = (Read-Field -Content $task -Key "Type").Trim().ToUpperInvariant()
$workRequestId = (Read-Field -Content $task -Key "Work request").Trim()
$workRequestType = ""

if (-not [string]::IsNullOrWhiteSpace($workRequestId)) {
    $workRequestPath = Join-Path $root ("docs\engineering\work-requests\" + $workRequestId + ".md")
    if (Test-Path -LiteralPath $workRequestPath -PathType Leaf) {
        $workRequestContent = Get-Content -LiteralPath $workRequestPath -Raw -Encoding UTF8
        $workRequestType = (Read-Field -Content $workRequestContent -Key "Type").Trim().ToUpperInvariant()
    }
}

if (
    -not [string]::IsNullOrWhiteSpace($taskType) -and
    -not [string]::IsNullOrWhiteSpace($workRequestType) -and
    $taskType -cne $workRequestType
) {
    throw "Task/work-request type mismatch for $Id. Task=$taskType WorkRequest=$workRequestType"
}

if ([string]::IsNullOrWhiteSpace($taskType)) {
    $taskType = $workRequestType
}

$isBugTask = ($taskType -ceq "BUG")

if ($workKind -cne "IMPLEMENTATION") {
    $displayWorkKind = if ([string]::IsNullOrWhiteSpace($workKind)) { "<missing>" } else { $workKind }
    throw "writable execution requires Work kind IMPLEMENTATION. Current Work kind: $displayWorkKind"
}

if ($status -notin @("READY","ACTIVE")) {
    throw "Task $Id must be READY or ACTIVE for writable execution. Current status: $status"
}

if ([string]::IsNullOrWhiteSpace($owner)) {
    throw "Task $Id has no owner."
}

$lockHelperPath = Join-Path $PSScriptRoot "task-execution-lock.ps1"
if (-not (Test-Path $lockHelperPath -PathType Leaf)) {
    throw "Task execution lock helper not found: $lockHelperPath"
}
. $lockHelperPath
$taskExecutionLock = Enter-TaskExecutionLock -ProjectPath $root -Id $Id -Operation "WRITABLE"

try {

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
$worktreeLines = @(Invoke-GitOutput -Arguments @("-C",$root,"worktree","list","--porcelain") -FailureMessage "git worktree list failed.")

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

# Resolve pending corrective evidence from the canonical primary-root lifecycle,
# never from the older control-plane snapshot in the task worktree.
$correctiveBuilderPath = Join-Path $PSScriptRoot "build-corrective-analysis-context.ps1"
if (-not (Test-Path -LiteralPath $correctiveBuilderPath -PathType Leaf)) {
    throw "Corrective context builder not found: $correctiveBuilderPath"
}
$correctiveContext = [string](& $correctiveBuilderPath -ProjectPath $root -Id $Id -Owner $owner)
$corrective = -not [string]::IsNullOrWhiteSpace($correctiveContext)
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
$defaultSchemaPath = Join-Path $root "schemas\writable-change-set.schema.json"
$bugSchemaPath = Join-Path $root "schemas\writable-bug-change-set.schema.json"
$diagnosticEvidenceSchemaPath = Join-Path $root "schemas\diagnostic-evidence.schema.json"
$diagnosticValidatorPath = Join-Path $PSScriptRoot "validate-diagnostic-evidence.ps1"
$schemaPath = if ($isBugTask) { $bugSchemaPath } else { $defaultSchemaPath }
$policyPath = Join-Path $root ".codex\writable-policy.json"
$routerPath = Join-Path $PSScriptRoot "provider-router.ps1"
$contextBuilderPath = Join-Path $PSScriptRoot "build-agent-context.ps1"
$requiredResolverPath = Join-Path $PSScriptRoot "resolve-writable-required-files.ps1"
$submitPath = Join-Path $PSScriptRoot "submit-task-result.ps1"

$requiredRuntimeComponents = @(
    $dispatchPath,
    $rolePath,
    $schemaPath,
    $policyPath,
    $routerPath,
    $contextBuilderPath,
    $requiredResolverPath,
    $submitPath
)
if ($isBugTask) {
    $requiredRuntimeComponents += @($diagnosticEvidenceSchemaPath,$diagnosticValidatorPath)
}

foreach ($required in $requiredRuntimeComponents) {
    if (-not (Test-Path $required)) {
        throw "Required writable runtime component not found: $required"
    }
}

$policy = Get-Content $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$verificationPolicyLines = @(
    @($policy.verification_command_patterns) |
    ForEach-Object { "- " + [string]$_ }
)
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

if ($corrective) {
    # Findings alone cannot support a code repair. Keep the exact required and
    # already changed product source in the same protected provider envelope.
    $correctiveSourcePaths = @(@($requiredFiles) + @($baselineChanged) | Sort-Object -Unique)
    $correctiveSource = Get-CorrectiveSourceEvidence -Workspace $workspace -ProjectRoot $root -Paths $correctiveSourcePaths -Policy $policy
    $correctiveContext += [Environment]::NewLine + $correctiveSource
}

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
    "Do not invent test modules, test files, package scripts, commands, or verification targets that are not evidenced by the supplied task, dispatch, or repository context.",
    "If no project-specific verifier is evidenced, use git diff --check rather than inventing one.",
    "",
    "Exact local verification-command allowlist patterns:",
    ($verificationPolicyLines -join [Environment]::NewLine),
    "",
    $(if ($isBugTask) {
        @(
            "BUG Diagnostic Evidence Contract v1 is mandatory for COMPLETED implementation.",
            "Populate diagnostic_plan with exactly one command-based reproduction signal, falsifiable hypotheses, evidence-bound cause status, and REPAIR or WORKAROUND classification.",
            "The reproduction command and every hypothesis experiment command are untrusted suggestions: they must match the local verification-command policy and the runtime executes them before any source mutation.",
            "Do not claim that you executed commands and do not invent receipt ids, hashes, signal fingerprints, or observations; the runtime creates those.",
            "Use cause.status=CONFIRMED only when the listed hypothesis experiments are expected to support the cause. REPAIR requires CONFIRMED cause.",
            "WORKAROUND must state residual_risk explicitly.",
            "Do not invent a reproduction test or command that is not evidenced by the task, dispatch, repository context, or existing test/tooling surface.",
            "Automated writable v1 supports COMMAND reproduction only. Manual/procedure evidence cannot authorize automated source mutation."
        ) -join [Environment]::NewLine
    } else { "" }),
    "",
    "Outcome semantics:",
    "- COMPLETED means you produced a complete implementation change set ready for local application and verification.",
    "- For an authoritative corrective retry with an existing implementation candidate, report-only correction may return changes=[] and real verification commands. Express the corrected owner handoff in report_markdown; never WRITE or DELETE agent reports, writable evidence, dispatch packets, work requests, plans or other control-plane files in the source worktree.",
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

$tempRoot = Join-Path (Get-AicoTempPath) "ai-company-os-writable"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$outputPath = Join-Path $tempRoot ($Id + "-" + [Guid]::NewGuid().ToString("N") + ".json")

$primaryStatusBefore = (@(Invoke-GitOutput -Arguments @("-C",$root,"status","--porcelain","--untracked-files=no") -FailureMessage "Unable to snapshot primary checkout status.") -join [Environment]::NewLine)

$execution = $null
$result = $null

try {
    if ($Provider -eq "Auto") {
        $order = @("Ollama")

        if ($null -ne $config -and $null -ne $config.writable_auto_order -and @($config.writable_auto_order).Count -gt 0) {
            $order = @($config.writable_auto_order | ForEach-Object { [string]$_ })
        }

        $providerErrors = @()

        foreach ($candidate in $order) {
            if ($candidate -notin @("Ollama","OpenRouter","Gemini")) { continue }

            if ($candidate -eq "OpenRouter" -and [string]::IsNullOrWhiteSpace($env:OPENROUTER_API_KEY)) {
                $providerErrors += "OpenRouter: OPENROUTER_API_KEY not configured"
                continue
            }

            if ($candidate -eq "Gemini" -and [string]::IsNullOrWhiteSpace($env:GEMINI_API_KEY)) {
                $providerErrors += "Gemini: GEMINI_API_KEY not configured"
                continue
            }

            $candidateModel = ""

            if ($candidate -ne "Ollama") {
                $candidateModel = Get-ConfiguredModel -Config $config -ProviderName $candidate -CollectionName "writable_models"

                if ([string]::IsNullOrWhiteSpace($candidateModel)) {
                    $candidateModel = Get-ConfiguredModel -Config $config -ProviderName $candidate -CollectionName "models"
                }

                $freeModelsProperty = $policy.free_provider_models.PSObject.Properties[$candidate]
                $freeModels = @()

                if ($null -ne $freeModelsProperty) {
                    $freeModels = @(
                        $freeModelsProperty.Value |
                        ForEach-Object { [string]$_ }
                    )
                }

                if (
                    [string]::IsNullOrWhiteSpace($candidateModel) -or
                    $freeModels -notcontains $candidateModel
                ) {
                    $providerErrors += (
                        $candidate +
                        ": no free writable model is configured"
                    )
                    continue
                }
            }
            try {
                $execution = & $routerPath -Provider $candidate -ProjectPath $root -Prompt $prompt -Context $context -SchemaPath $schemaPath -OutputPath $outputPath -Model $candidateModel -Role $owner -Workload "writable" -CorrectiveContext $correctiveContext
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

        $execution = & $routerPath -Provider $Provider -ProjectPath $root -Prompt $prompt -Context $context -SchemaPath $schemaPath -OutputPath $outputPath -Model $selectedModel -Role $owner -Workload "writable" -CorrectiveContext $correctiveContext
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

$diagnosticPath = Join-Path $root ("docs\engineering\diagnostics\" + $Id + "-diagnostic-v1.json")
$diagnosticRelative = "docs/engineering/diagnostics/" + $Id + "-diagnostic-v1.json"
$diagnosticArtifact = $null
$safeReproductionCommand = $null
$signalFingerprint = ""
$diagnosticAttemptIndex = 0

if ($isBugTask -and [string]$result.outcome -eq "COMPLETED") {
    if ($null -eq $result.PSObject.Properties["diagnostic_plan"] -or $null -eq $result.diagnostic_plan) {
        throw "BUG COMPLETED writable result requires diagnostic_plan."
    }

    $plan = $result.diagnostic_plan
    foreach ($field in @("reproduction_signal","hypotheses","cause","resolution")) {
        if ($null -eq $plan.PSObject.Properties[$field]) {
            throw "BUG diagnostic_plan missing field: $field"
        }
    }

    $signal = $plan.reproduction_signal
    foreach ($field in @("kind","command","working_directory","broken_when")) {
        if ($null -eq $signal.PSObject.Properties[$field]) {
            throw "BUG reproduction_signal missing field: $field"
        }
    }

    if ([string]$signal.kind -ne "COMMAND") {
        throw "Automated writable BUG execution supports COMMAND reproduction only."
    }
    if ([string]$signal.working_directory -ne ".") {
        throw "BUG reproduction signal working_directory must be repository root '.'."
    }

    $safeReproductionCommand = Get-SafeCommand -Command ([string]$signal.command) -Policy $policy
    $signalFingerprint = Get-Sha256Hex -Value (
        "COMMAND" + [Environment]::NewLine +
        "." + [Environment]::NewLine +
        [string]$safeReproductionCommand.Display + [Environment]::NewLine +
        [string]$signal.broken_when
    )

    $priorReceipts = @()
    $priorAttempts = @()
    $preFixObservation = ""
    $preFixReceiptRef = ""

    if (Test-Path -LiteralPath $diagnosticPath -PathType Leaf) {
        & $diagnosticValidatorPath -JsonPath $diagnosticPath | Out-Null
        $existingDiagnostic = Get-Content -LiteralPath $diagnosticPath -Raw -Encoding UTF8 | ConvertFrom-Json

        if ([string]$existingDiagnostic.task_id -ne $Id) {
            throw "Existing diagnostic artifact belongs to another task."
        }
        if ([string]$existingDiagnostic.reproduction.signal_fingerprint -ne $signalFingerprint) {
            throw "BUG reproduction signal substitution refused. Corrective work must preserve the frozen signal fingerprint."
        }

        $priorReceipts = @($existingDiagnostic.receipts)
        $priorAttempts = @($existingDiagnostic.attempts)
        $preFixObservation = [string]$existingDiagnostic.reproduction.pre_fix.observation
        $preFixReceiptRef = [string]$existingDiagnostic.reproduction.pre_fix.receipt_ref
    }

    $receiptSerial = $priorReceipts.Count

    if ($preFixObservation -ne "BROKEN_OBSERVED") {
        Write-Host ""
        Write-Host ("Diagnostic reproduction: " + $safeReproductionCommand.Display) -ForegroundColor Cyan
        $preFixResult = Invoke-DiagnosticCommand -SafeCommand $safeReproductionCommand -Workspace $workspace
        $receiptSerial++
        $preFixReceiptRef = "pre-fix-" + $receiptSerial.ToString("000")
        $preFixReceipt = New-DiagnosticReceipt -Id $preFixReceiptRef -Phase "PRE_FIX" -Command $safeReproductionCommand.Display -CommandResult $preFixResult
        $priorReceipts = @($priorReceipts) + @($preFixReceipt)

        $brokenObserved = Test-DiagnosticExitCondition -ExitCode $preFixResult.ExitCode -Condition ([string]$signal.broken_when)
        $preFixObservation = if ($brokenObserved) { "BROKEN_OBSERVED" } else { "NOT_REPRODUCED" }

        if (-not $brokenObserved) {
            $diagnosticArtifact = [ordered]@{
                schema_version = "1"
                task_id = $Id
                workflow = "BUG"
                state = "NOT_REPRODUCED"
                reproduction = [ordered]@{
                    kind = "COMMAND"
                    command = [string]$safeReproductionCommand.Display
                    working_directory = "."
                    broken_when = [string]$signal.broken_when
                    signal_fingerprint = $signalFingerprint
                    pre_fix = [ordered]@{
                        observation = "NOT_REPRODUCED"
                        receipt_ref = $preFixReceiptRef
                    }
                }
                receipts = @($priorReceipts)
                attempts = @($priorAttempts)
                regression = [ordered]@{ receipt_refs = @() }
                post_fix_replay = [ordered]@{
                    signal_fingerprint = $signalFingerprint
                    observation = "NOT_RUN"
                    receipt_ref = ""
                }
            }
            Save-DiagnosticArtifact -Path $diagnosticPath -Artifact $diagnosticArtifact
            & $diagnosticValidatorPath -JsonPath $diagnosticPath | Out-Null
            throw "BUG reproduction signal did not observe the broken state. Source mutation refused."
        }
    }

    $existingIndexes = @($priorAttempts | ForEach-Object { [int]$_.index })
    $diagnosticAttemptIndex = if ($existingIndexes.Count -gt 0) {
        [int](($existingIndexes | Measure-Object -Maximum).Maximum) + 1
    }
    else {
        1
    }

    $hypothesisIds = @{}
    $hypothesisEvidence = @()

    foreach ($hypothesis in @($plan.hypotheses)) {
        foreach ($field in @("id","statement","prediction","falsifier","experiment_command","supported_when")) {
            if ($null -eq $hypothesis.PSObject.Properties[$field]) {
                throw "BUG hypothesis missing field: $field"
            }
        }

        $hypothesisId = ([string]$hypothesis.id).Trim()
        if ([string]::IsNullOrWhiteSpace($hypothesisId) -or $hypothesisId -notmatch '^[A-Za-z0-9._-]+$') {
            throw "BUG hypothesis id is invalid: $hypothesisId"
        }
        if ($hypothesisIds.ContainsKey($hypothesisId)) {
            throw "BUG diagnostic_plan contains duplicate hypothesis id: $hypothesisId"
        }
        $hypothesisIds[$hypothesisId] = $true

        foreach ($field in @("statement","prediction","falsifier","experiment_command")) {
            if ([string]::IsNullOrWhiteSpace([string]$hypothesis.$field)) {
                throw "BUG hypothesis.$field must be concrete."
            }
        }

        $safeExperiment = Get-SafeCommand -Command ([string]$hypothesis.experiment_command) -Policy $policy
        Write-Host ""
        Write-Host ("Diagnostic hypothesis " + $hypothesisId + ": " + $safeExperiment.Display) -ForegroundColor Cyan
        $experimentResult = Invoke-DiagnosticCommand -SafeCommand $safeExperiment -Workspace $workspace
        $receiptSerial++
        $receiptId = "attempt-" + $diagnosticAttemptIndex + "-" + $hypothesisId + "-" + $receiptSerial.ToString("000")
        $receipt = New-DiagnosticReceipt -Id $receiptId -Phase "HYPOTHESIS" -Command $safeExperiment.Display -CommandResult $experimentResult
        $priorReceipts = @($priorReceipts) + @($receipt)

        $supported = Test-DiagnosticExitCondition -ExitCode $experimentResult.ExitCode -Condition ([string]$hypothesis.supported_when)
        $hypothesisEvidence += [ordered]@{
            id = $hypothesisId
            statement = [string]$hypothesis.statement
            prediction = [string]$hypothesis.prediction
            falsifier = [string]$hypothesis.falsifier
            experiment_command = [string]$safeExperiment.Display
            supported_when = [string]$hypothesis.supported_when
            result = if ($supported) { "SUPPORTED" } else { "FALSIFIED" }
            receipt_ref = $receiptId
        }
    }

    if ($hypothesisEvidence.Count -lt 1) {
        throw "BUG diagnostic_plan requires at least one falsifiable hypothesis."
    }

    $cause = $plan.cause
    foreach ($field in @("status","statement","hypothesis_refs")) {
        if ($null -eq $cause.PSObject.Properties[$field]) {
            throw "BUG cause missing field: $field"
        }
    }

    $causeRefs = @($cause.hypothesis_refs | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    $causeReceiptRefs = @()

    foreach ($causeRef in $causeRefs) {
        $matched = @($hypothesisEvidence | Where-Object { [string]$_.id -eq $causeRef })
        if ($matched.Count -ne 1) {
            throw "BUG cause references unknown hypothesis: $causeRef"
        }
        if ([string]$cause.status -eq "CONFIRMED" -and [string]$matched[0].result -ne "SUPPORTED") {
            throw "BUG CONFIRMED cause references a hypothesis that the runtime falsified: $causeRef"
        }
        $causeReceiptRefs += [string]$matched[0].receipt_ref
    }

    if ([string]$cause.status -eq "CONFIRMED") {
        if ($causeRefs.Count -lt 1 -or $causeReceiptRefs.Count -lt 1) {
            throw "BUG CONFIRMED cause requires supported hypothesis evidence."
        }
    }
    elseif ([string]$cause.status -ne "UNCONFIRMED") {
        throw "BUG cause.status must be CONFIRMED or UNCONFIRMED."
    }

    $resolution = $plan.resolution
    foreach ($field in @("classification","summary","residual_risk")) {
        if ($null -eq $resolution.PSObject.Properties[$field]) {
            throw "BUG resolution missing field: $field"
        }
    }

    if ([string]$resolution.classification -eq "REPAIR") {
        if ([string]$cause.status -ne "CONFIRMED") {
            throw "BUG REPAIR requires a CONFIRMED evidence-backed cause."
        }
    }
    elseif ([string]$resolution.classification -eq "WORKAROUND") {
        if ([string]::IsNullOrWhiteSpace([string]$resolution.residual_risk)) {
            throw "BUG WORKAROUND requires explicit residual_risk."
        }
    }
    else {
        throw "BUG resolution.classification must be REPAIR or WORKAROUND."
    }

    $attempt = [ordered]@{
        index = $diagnosticAttemptIndex
        corrective = [bool]($corrective -or $priorAttempts.Count -gt 0)
        hypotheses = @($hypothesisEvidence)
        cause = [ordered]@{
            status = [string]$cause.status
            statement = [string]$cause.statement
            hypothesis_refs = @($causeRefs)
            receipt_refs = @($causeReceiptRefs)
        }
        resolution = [ordered]@{
            classification = [string]$resolution.classification
            summary = [string]$resolution.summary
            residual_risk = [string]$resolution.residual_risk
        }
    }

    $diagnosticArtifact = [ordered]@{
        schema_version = "1"
        task_id = $Id
        workflow = "BUG"
        state = "PREFLIGHT"
        reproduction = [ordered]@{
            kind = "COMMAND"
            command = [string]$safeReproductionCommand.Display
            working_directory = "."
            broken_when = [string]$signal.broken_when
            signal_fingerprint = $signalFingerprint
            pre_fix = [ordered]@{
                observation = "BROKEN_OBSERVED"
                receipt_ref = $preFixReceiptRef
            }
        }
        receipts = @($priorReceipts)
        attempts = @($priorAttempts) + @($attempt)
        regression = [ordered]@{ receipt_refs = @() }
        post_fix_replay = [ordered]@{
            signal_fingerprint = $signalFingerprint
            observation = "NOT_RUN"
            receipt_ref = ""
        }
    }

    Save-DiagnosticArtifact -Path $diagnosticPath -Artifact $diagnosticArtifact
    & $diagnosticValidatorPath -JsonPath $diagnosticPath | Out-Null
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

# The existing candidate was already captured through the safe-path/source
# guards before provider invocation. An authoritative corrective retry may
# repair only its role-owned report without fabricating a source operation.
$reportOnlyCorrective = ($corrective -and $baselineChanged.Count -gt 0 -and $changes.Count -eq 0)
if ($changes.Count -lt 1 -and -not $reportOnlyCorrective) {
    throw "COMPLETED writable result must contain at least one change unless correcting a report for an existing safe implementation candidate."
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

$safeVerificationCommands = @()
foreach ($commandText in $verificationCommands) {
    $safeVerificationCommands += Get-SafeCommand -Command ([string]$commandText) -Policy $policy
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

    if ($effectiveChanges -lt 1 -and -not $reportOnlyCorrective) {
        throw "Writable provider proposed no effective file changes."
    }

    & git -C $workspace diff --check
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed after applying writable change set."
    }

    $verificationLog = New-Object System.Collections.Generic.List[string]
    $verificationIndex = 0

    foreach ($safeCommand in $safeVerificationCommands) {
        $verificationIndex++
        Write-Host ""
        Write-Host ("Verification: " + $safeCommand.Display) -ForegroundColor Cyan

        if ($isBugTask -and $null -ne $diagnosticArtifact) {
            $verificationResult = Invoke-DiagnosticCommand -SafeCommand $safeCommand -Workspace $workspace
            $commandOutput = [string]$verificationResult.Output

            [void]$verificationLog.Add(
                ("$ " + $safeCommand.Display + [Environment]::NewLine + $commandOutput).Trim()
            )

            $verificationReceiptId = "attempt-" + $diagnosticAttemptIndex + "-regression-" + $verificationIndex.ToString("000")
            $verificationReceipt = New-DiagnosticReceipt -Id $verificationReceiptId -Phase "REGRESSION" -Command $safeCommand.Display -CommandResult $verificationResult
            $diagnosticArtifact.receipts = @($diagnosticArtifact.receipts) + @($verificationReceipt)
            $diagnosticArtifact.regression.receipt_refs = @($diagnosticArtifact.regression.receipt_refs) + @($verificationReceiptId)

            if ([int]$verificationResult.ExitCode -ne 0) {
                $diagnosticArtifact.state = "FAILED_VERIFICATION"
                Save-DiagnosticArtifact -Path $diagnosticPath -Artifact $diagnosticArtifact
                & $diagnosticValidatorPath -JsonPath $diagnosticPath | Out-Null
                throw ("Verification command failed with exit code " + $verificationResult.ExitCode + ": " + $safeCommand.Display)
            }
        }
        else {
            $commandOutput = Invoke-VerificationCommand -SafeCommand $safeCommand -Workspace $workspace
            [void]$verificationLog.Add(
                ("$ " + $safeCommand.Display + [Environment]::NewLine + $commandOutput).Trim()
            )
        }
    }

    if ($isBugTask -and $null -ne $diagnosticArtifact) {
        Write-Host ""
        Write-Host ("Post-fix reproduction replay: " + $safeReproductionCommand.Display) -ForegroundColor Cyan
        $postFixResult = Invoke-DiagnosticCommand -SafeCommand $safeReproductionCommand -Workspace $workspace
        $postFixReceiptId = "attempt-" + $diagnosticAttemptIndex + "-post-fix"
        $postFixReceipt = New-DiagnosticReceipt -Id $postFixReceiptId -Phase "POST_FIX" -Command $safeReproductionCommand.Display -CommandResult $postFixResult
        $diagnosticArtifact.receipts = @($diagnosticArtifact.receipts) + @($postFixReceipt)

        $stillBroken = Test-DiagnosticExitCondition -ExitCode $postFixResult.ExitCode -Condition ([string]$diagnosticArtifact.reproduction.broken_when)
        $diagnosticArtifact.post_fix_replay = [ordered]@{
            signal_fingerprint = $signalFingerprint
            observation = if ($stillBroken) { "BROKEN_OBSERVED" } else { "FIXED_OBSERVED" }
            receipt_ref = $postFixReceiptId
        }
        $diagnosticArtifact.state = if ($stillBroken) { "FAILED_POST_FIX" } else { "COMPLETE" }

        Save-DiagnosticArtifact -Path $diagnosticPath -Artifact $diagnosticArtifact
        & $diagnosticValidatorPath -JsonPath $diagnosticPath | Out-Null

        if ($stillBroken) {
            throw "BUG post-fix replay still reproduces the original defect. Source changes will be restored."
        }
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

    $primaryStatusAfter = (@(Invoke-GitOutput -Arguments @("-C",$root,"status","--porcelain","--untracked-files=no") -FailureMessage "Unable to verify primary checkout status.") -join [Environment]::NewLine)

    if ($primaryStatusAfter -cne $primaryStatusBefore) {
        throw "Primary checkout changed during writable source execution. Refusing to submit the result."
    }

    $diffLines = @(Invoke-GitOutput -Arguments @("-C",$workspace,"diff","--no-ext-diff","--") -FailureMessage "Unable to obtain writable git diff.")

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
        "## Diagnostic Evidence",
        "",
        $(if ($isBugTask -and (Test-Path -LiteralPath $diagnosticPath -PathType Leaf)) { $diagnosticRelative } else { "NOT_APPLICABLE" }),
        "",
        "## Runtime Guarantees",
        "",
        "- Source writes were restricted to the registered task worktree.",
        "- The primary checkout source state was unchanged during application and verification.",
        "- No merge, push, deploy, rebase or automatic commit was performed.",
        "- Verification commands passed the local writable policy before execution."
    ) -join [Environment]::NewLine

    Write-Utf8NoBom -Path $evidencePath -Value $evidence

    # Publish the canonical primary agent report expected by independent gates.
    # Writable evidence remains the implementation/runtime evidence artifact;
    # this report is the role-owned deliverable that Review / QA / Security inspect.
    $reportDir = Join-Path $root "docs\engineering\agent-reports"
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

    $reportPath = Join-Path $reportDir ($Id + ".md")

    $primaryReport = @(
        "# Agent Report - $Id",
        "",
        "Generated: $now",
        "Owner: $owner",
        "Outcome: COMPLETED",
        "Work kind: IMPLEMENTATION",
        "Provider: $($execution.Provider)",
        "Model: $($execution.Model)",
        "",
        "## Summary",
        "",
        [string]$result.summary,
        "",
        "## Role-Owned Deliverable",
        "",
        [string]$result.report_markdown,
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
        "## Decisions",
        "",
        [string]$result.decisions,
        "",
        "## Writable Evidence",
        "",
        ("docs/engineering/writable-evidence/" + (Split-Path $evidencePath -Leaf)),
        "",
        "## Diagnostic Evidence",
        "",
        $(if ($isBugTask -and (Test-Path -LiteralPath $diagnosticPath -PathType Leaf)) { $diagnosticRelative } else { "NOT_APPLICABLE" })
    ) -join [Environment]::NewLine

    Write-Utf8NoBom -Path $reportPath -Value $primaryReport

    $controlArtifacts = @(
        ("docs/engineering/writable-evidence/" + (Split-Path $evidencePath -Leaf)),
        ("docs/engineering/agent-reports/" + (Split-Path $reportPath -Leaf))
    )
    if ($isBugTask -and (Test-Path -LiteralPath $diagnosticPath -PathType Leaf)) {
        $controlArtifacts += $diagnosticRelative
    }

    $changedArtifacts = (($changedAfter + $controlArtifacts) -join "; ")

    $verificationSummary = "git diff --check PASS. " + (($verificationCommands | ForEach-Object { $_ + " PASS" }) -join "; ")
    if ($isBugTask -and $null -ne $diagnosticArtifact -and [string]$diagnosticArtifact.state -eq "COMPLETE") {
        $verificationSummary += ". Diagnostic same-signal replay PASS: " + $signalFingerprint
    }

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
}
finally {
    Exit-TaskExecutionLock -Lock $taskExecutionLock
}
) {
            throw "BUG hypothesis id is invalid: $hypothesisId"
        }
        if ($hypothesisIds.ContainsKey($hypothesisId)) {
            throw "BUG diagnostic_plan contains duplicate hypothesis id: $hypothesisId"
        }
        $hypothesisIds[$hypothesisId] = $true

        foreach ($field in @("statement","prediction","falsifier","experiment_command")) {
            if ([string]::IsNullOrWhiteSpace([string]$hypothesis.$field)) {
                throw "BUG hypothesis.$field must be concrete."
            }
        }

        $safeExperiment = Get-SafeCommand -Command ([string]$hypothesis.experiment_command) -Policy $policy
        Write-Host ""
        Write-Host ("Diagnostic hypothesis " + $hypothesisId + ": " + $safeExperiment.Display) -ForegroundColor Cyan
        $experimentResult = Invoke-DiagnosticCommand -SafeCommand $safeExperiment -Workspace $workspace
        $receiptSerial++
        $receiptId = "attempt-" + $diagnosticAttemptIndex + "-" + $hypothesisId + "-" + $receiptSerial.ToString("000")
        $receipt = New-DiagnosticReceipt -Id $receiptId -Phase "HYPOTHESIS" -Command $safeExperiment.Display -CommandResult $experimentResult
        $priorReceipts = @($priorReceipts) + @($receipt)

        $supported = Test-DiagnosticExitCondition -ExitCode $experimentResult.ExitCode -Condition ([string]$hypothesis.supported_when)
        $hypothesisEvidence += [ordered]@{
            id = $hypothesisId
            statement = [string]$hypothesis.statement
            prediction = [string]$hypothesis.prediction
            falsifier = [string]$hypothesis.falsifier
            experiment_command = [string]$safeExperiment.Display
            supported_when = [string]$hypothesis.supported_when
            result = if ($supported) { "SUPPORTED" } else { "FALSIFIED" }
            receipt_ref = $receiptId
        }
    }

    if ($hypothesisEvidence.Count -lt 1) {
        throw "BUG diagnostic_plan requires at least one falsifiable hypothesis."
    }

    $cause = $plan.cause
    foreach ($field in @("status","statement","hypothesis_refs")) {
        if ($null -eq $cause.PSObject.Properties[$field]) {
            throw "BUG cause missing field: $field"
        }
    }

    $causeRefs = @($cause.hypothesis_refs | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    $causeReceiptRefs = @()

    foreach ($causeRef in $causeRefs) {
        $matched = @($hypothesisEvidence | Where-Object { [string]$_.id -eq $causeRef })
        if ($matched.Count -ne 1) {
            throw "BUG cause references unknown hypothesis: $causeRef"
        }
        if ([string]$cause.status -eq "CONFIRMED" -and [string]$matched[0].result -ne "SUPPORTED") {
            throw "BUG CONFIRMED cause references a hypothesis that the runtime falsified: $causeRef"
        }
        $causeReceiptRefs += [string]$matched[0].receipt_ref
    }

    if ([string]$cause.status -eq "CONFIRMED") {
        if ($causeRefs.Count -lt 1 -or $causeReceiptRefs.Count -lt 1) {
            throw "BUG CONFIRMED cause requires supported hypothesis evidence."
        }
    }
    elseif ([string]$cause.status -ne "UNCONFIRMED") {
        throw "BUG cause.status must be CONFIRMED or UNCONFIRMED."
    }

    $resolution = $plan.resolution
    foreach ($field in @("classification","summary","residual_risk")) {
        if ($null -eq $resolution.PSObject.Properties[$field]) {
            throw "BUG resolution missing field: $field"
        }
    }

    if ([string]$resolution.classification -eq "REPAIR") {
        if ([string]$cause.status -ne "CONFIRMED") {
            throw "BUG REPAIR requires a CONFIRMED evidence-backed cause."
        }
    }
    elseif ([string]$resolution.classification -eq "WORKAROUND") {
        if ([string]::IsNullOrWhiteSpace([string]$resolution.residual_risk)) {
            throw "BUG WORKAROUND requires explicit residual_risk."
        }
    }
    else {
        throw "BUG resolution.classification must be REPAIR or WORKAROUND."
    }

    $attempt = [ordered]@{
        index = $diagnosticAttemptIndex
        corrective = [bool]($corrective -or $priorAttempts.Count -gt 0)
        hypotheses = @($hypothesisEvidence)
        cause = [ordered]@{
            status = [string]$cause.status
            statement = [string]$cause.statement
            hypothesis_refs = @($causeRefs)
            receipt_refs = @($causeReceiptRefs)
        }
        resolution = [ordered]@{
            classification = [string]$resolution.classification
            summary = [string]$resolution.summary
            residual_risk = [string]$resolution.residual_risk
        }
    }

    $diagnosticArtifact = [ordered]@{
        schema_version = "1"
        task_id = $Id
        workflow = "BUG"
        state = "PREFLIGHT"
        reproduction = [ordered]@{
            kind = "COMMAND"
            command = [string]$safeReproductionCommand.Display
            working_directory = "."
            broken_when = [string]$signal.broken_when
            signal_fingerprint = $signalFingerprint
            pre_fix = [ordered]@{
                observation = "BROKEN_OBSERVED"
                receipt_ref = $preFixReceiptRef
            }
        }
        receipts = @($priorReceipts)
        attempts = @($priorAttempts) + @($attempt)
        regression = [ordered]@{ receipt_refs = @() }
        post_fix_replay = [ordered]@{
            signal_fingerprint = $signalFingerprint
            observation = "NOT_RUN"
            receipt_ref = ""
        }
    }

    Save-DiagnosticArtifact -Path $diagnosticPath -Artifact $diagnosticArtifact
    & $diagnosticValidatorPath -JsonPath $diagnosticPath | Out-Null
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

# The existing candidate was already captured through the safe-path/source
# guards before provider invocation. An authoritative corrective retry may
# repair only its role-owned report without fabricating a source operation.
$reportOnlyCorrective = ($corrective -and $baselineChanged.Count -gt 0 -and $changes.Count -eq 0)
if ($changes.Count -lt 1 -and -not $reportOnlyCorrective) {
    throw "COMPLETED writable result must contain at least one change unless correcting a report for an existing safe implementation candidate."
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

$safeVerificationCommands = @()
foreach ($commandText in $verificationCommands) {
    $safeVerificationCommands += Get-SafeCommand -Command ([string]$commandText) -Policy $policy
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

    if ($effectiveChanges -lt 1 -and -not $reportOnlyCorrective) {
        throw "Writable provider proposed no effective file changes."
    }

    & git -C $workspace diff --check
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed after applying writable change set."
    }

    $verificationLog = New-Object System.Collections.Generic.List[string]

    foreach ($safeCommand in $safeVerificationCommands) {
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

    $primaryStatusAfter = (@(Invoke-GitOutput -Arguments @("-C",$root,"status","--porcelain","--untracked-files=no") -FailureMessage "Unable to verify primary checkout status.") -join [Environment]::NewLine)

    if ($primaryStatusAfter -cne $primaryStatusBefore) {
        throw "Primary checkout changed during writable source execution. Refusing to submit the result."
    }

    $diffLines = @(Invoke-GitOutput -Arguments @("-C",$workspace,"diff","--no-ext-diff","--") -FailureMessage "Unable to obtain writable git diff.")

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

    # Publish the canonical primary agent report expected by independent gates.
    # Writable evidence remains the implementation/runtime evidence artifact;
    # this report is the role-owned deliverable that Review / QA / Security inspect.
    $reportDir = Join-Path $root "docs\engineering\agent-reports"
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

    $reportPath = Join-Path $reportDir ($Id + ".md")

    $primaryReport = @(
        "# Agent Report - $Id",
        "",
        "Generated: $now",
        "Owner: $owner",
        "Outcome: COMPLETED",
        "Work kind: IMPLEMENTATION",
        "Provider: $($execution.Provider)",
        "Model: $($execution.Model)",
        "",
        "## Summary",
        "",
        [string]$result.summary,
        "",
        "## Role-Owned Deliverable",
        "",
        [string]$result.report_markdown,
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
        "## Decisions",
        "",
        [string]$result.decisions,
        "",
        "## Writable Evidence",
        "",
        ("docs/engineering/writable-evidence/" + (Split-Path $evidencePath -Leaf))
    ) -join [Environment]::NewLine

    Write-Utf8NoBom -Path $reportPath -Value $primaryReport

    $changedArtifacts = (
        (
            $changedAfter +
            @(
                ("docs/engineering/writable-evidence/" + (Split-Path $evidencePath -Leaf)),
                ("docs/engineering/agent-reports/" + (Split-Path $reportPath -Leaf))
            )
        ) -join "; "
    )

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
}
finally {
    Exit-TaskExecutionLock -Lock $taskExecutionLock
}
