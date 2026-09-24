param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [string[]]$SourceText,

    [Parameter(Mandatory = $true)]
    [string]$PolicyPath
)

$ErrorActionPreference = "Stop"

function Test-MatchesAnyPattern {
    param([string]$Value,[object[]]$Patterns)

    foreach ($pattern in @($Patterns)) {
        if ($Value -match [string]$pattern) { return $true }
    }

    return $false
}

function Assert-ReadableRequiredPath {
    param(
        [string]$Root,
        [string]$RelativePath,
        [object]$Policy
    )

    $normalized = $RelativePath.Replace("\","/").TrimStart("/")
    $lower = $normalized.ToLowerInvariant()

    foreach ($prefixValue in @($Policy.protected_path_prefixes)) {
        $prefix = ([string]$prefixValue).Trim().Replace("\","/").TrimEnd("/").ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }

        if ($lower -eq $prefix -or $lower.StartsWith($prefix + "/")) {
            throw "Required writable context file is prohibited by policy: $normalized"
        }
    }

    if (Test-MatchesAnyPattern -Value $lower -Patterns @($Policy.secret_name_patterns)) {
        throw "Required writable context file is secret-sensitive and prohibited by policy: $normalized"
    }

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@("\","/"))
    $targetFull = [System.IO.Path]::GetFullPath((Join-Path $rootFull ($normalized.Replace("/","\"))))
    $prefixFull = $rootFull + [System.IO.Path]::DirectorySeparatorChar

    if (-not $targetFull.StartsWith($prefixFull,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Required writable context file escapes the isolated worktree: $normalized"
    }

    $current = $targetFull

    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $currentFull = [System.IO.Path]::GetFullPath($current).TrimEnd([char[]]@("\","/"))

        if ([string]::Equals($currentFull,$rootFull,[System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        if (Test-Path $currentFull) {
            $item = Get-Item $currentFull -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Required writable context file traverses a symlink/junction/reparse point: $normalized"
            }
        }

        $parent = Split-Path $currentFull -Parent
        if ($parent -eq $currentFull) { break }
        $current = $parent
    }

    if (-not (Test-Path $targetFull -PathType Leaf)) {
        throw "Required writable context file disappeared before it could be read: $normalized"
    }

    $fileInfo = Get-Item $targetFull -Force
    $maxBytes = if ($null -ne $Policy.required_context_max_file_bytes) {
        [long]$Policy.required_context_max_file_bytes
    }
    else {
        90000
    }

    if ([long]$fileInfo.Length -gt $maxBytes) {
        throw "Required writable context file exceeds policy size limit: $normalized ($($fileInfo.Length) bytes > $maxBytes bytes)"
    }

    return [PSCustomObject]@{
        Relative = $normalized
        FullPath = $targetFull
        Length = [long]$fileInfo.Length
    }
}

$root = (Resolve-Path $ProjectPath).Path
if (-not (Test-Path $PolicyPath -PathType Leaf)) {
    throw "Writable policy not found: $PolicyPath"
}

$policy = Get-Content $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$maxFiles = if ($null -ne $policy.required_context_max_files) {
    [int]$policy.required_context_max_files
}
else {
    8
}
$maxTotalBytes = if ($null -ne $policy.required_context_max_total_bytes) {
    [long]$policy.required_context_max_total_bytes
}
else {
    100000
}

$combined = (@($SourceText) -join [Environment]::NewLine)
if ([string]::IsNullOrWhiteSpace($combined)) {
    return
}

$negativeRequirementPattern = '(?i)\b(do not|don''t|never|must not|should not|without|exclude|excluded|prohibit|prohibited|no modificar|no tocar|no incluir|no leer)\b'
$scanLines = @(
    $combined -split '\r?\n' |
        Where-Object { $_ -notmatch $negativeRequirementPattern }
)
$scanText = $scanLines -join [Environment]::NewLine

$inventory = @(
    foreach ($relativeName in @(Get-ChildItem $root -File -Recurse -Force -Name -ErrorAction SilentlyContinue)) {
        $relative = ([string]$relativeName).Replace("\","/")
        $lower = $relative.ToLowerInvariant().Replace("/","\")

        if ($lower -match '(^|\\)(node_modules|\.git|dist|dist-refactor-modular|build|coverage|\.next|vendor)(\\|$)') {
            continue
        }

        [PSCustomObject]@{
            Relative = $relative
            Name = (Split-Path $relative -Leaf)
            FullPath = (Join-Path $root ($relative.Replace("/","\")))
        }
    }
)

$byRelative = @{}
$byName = @{}

foreach ($entry in $inventory) {
    $byRelative[$entry.Relative.ToLowerInvariant()] = $entry

    $nameKey = $entry.Name.ToLowerInvariant()
    if (-not $byName.ContainsKey($nameKey)) {
        $byName[$nameKey] = @()
    }
    $byName[$nameKey] = @($byName[$nameKey]) + @($entry)
}

$candidates = New-Object System.Collections.Generic.List[string]

$pathPattern = '(?i)(?<![A-Za-z0-9_.-])((?:[A-Za-z0-9_.-]+[\\/])*[A-Za-z0-9_.-]+\.(?:html?|css|scss|js|jsx|ts|tsx|mjs|cjs|json|md|txt|toml|ya?ml|sql|ps1|sh|py|go|rs|java|cs|xml|pem|key|p12|pfx))(?![A-Za-z0-9_.-])'
foreach ($match in [regex]::Matches($scanText,$pathPattern)) {
    $value = $match.Groups[1].Value.Trim().Replace("\","/")
    if (-not [string]::IsNullOrWhiteSpace($value) -and -not $candidates.Contains($value)) {
        [void]$candidates.Add($value)
    }
}

$specialPattern = '(?i)(?<![A-Za-z0-9_.-])((?:[A-Za-z0-9_.-]+[\\/])*(?:\.env(?:\.[A-Za-z0-9_.-]+)?|Dockerfile|\.npmrc))(?![A-Za-z0-9_.-])'
foreach ($match in [regex]::Matches($scanText,$specialPattern)) {
    $value = $match.Groups[1].Value.Trim().Replace("\","/")
    if (-not [string]::IsNullOrWhiteSpace($value) -and -not $candidates.Contains($value)) {
        [void]$candidates.Add($value)
    }
}

$resolved = New-Object System.Collections.Generic.List[object]
$seen = @{}
$totalBytes = 0L

foreach ($candidate in $candidates) {
    $candidateKey = $candidate.ToLowerInvariant()
    $entry = $null

    if ($candidate.Contains("/")) {
        if ($byRelative.ContainsKey($candidateKey)) {
            $entry = $byRelative[$candidateKey]
        }
    }
    else {
        if ($byName.ContainsKey($candidateKey)) {
            $matches = @($byName[$candidateKey])

            if ($matches.Count -gt 1) {
                $paths = ($matches | ForEach-Object { $_.Relative }) -join ", "
                throw "Required writable context filename is ambiguous: $candidate -> $paths"
            }

            if ($matches.Count -eq 1) {
                $entry = $matches[0]
            }
        }
    }

    if ($null -eq $entry) {
        continue
    }

    $safe = Assert-ReadableRequiredPath -Root $root -RelativePath $entry.Relative -Policy $policy
    $key = $safe.Relative.ToLowerInvariant()

    if ($seen.ContainsKey($key)) {
        continue
    }

    $seen[$key] = $true
    $totalBytes += [long]$safe.Length

    if ($resolved.Count + 1 -gt $maxFiles) {
        throw "Required writable context exceeds policy file-count limit: $maxFiles"
    }

    if ($totalBytes -gt $maxTotalBytes) {
        throw "Required writable context exceeds policy total-size limit: $totalBytes bytes > $maxTotalBytes bytes"
    }

    [void]$resolved.Add($safe)
}

foreach ($entry in $resolved) {
    Write-Output $entry.Relative
}
