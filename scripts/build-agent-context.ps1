param(
    [string]$ProjectPath = ".",
    [Parameter(Mandatory = $true)]
    [string]$Id,
    [Parameter(Mandatory = $true)]
    [string]$Owner,
    [int]$MaxChars = 180000
)

$ErrorActionPreference = "Stop"

function Add-ContextFile {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$Root,
        [string]$RelativePath,
        [int]$Remaining
    )

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path $fullPath -PathType Leaf)) { return 0 }

    try {
        $content = Get-Content $fullPath -Raw -ErrorAction Stop
    }
    catch {
        return 0
    }

    if ($null -eq $content) { $content = "" }

    $header = [Environment]::NewLine + [Environment]::NewLine + "===== FILE: " + $RelativePath + " =====" + [Environment]::NewLine
    if ($header.Length -ge $Remaining) { return 0 }

    $allowed = $Remaining - $header.Length
    if ($allowed -le 0) { return 0 }

    if ($content.Length -gt $allowed) {
        $marker = [Environment]::NewLine + "[TRUNCATED BY AI COMPANY OS CONTEXT BUILDER]"
        $take = [Math]::Max(0, $allowed - $marker.Length)
        $content = $content.Substring(0, $take) + $marker
    }

    [void]$Builder.Append($header)
    [void]$Builder.Append($content)
    return ($header.Length + $content.Length)
}

function Get-RoleScore {
    param([string]$RelativePath,[string]$Role)

    $p = $RelativePath.ToLowerInvariant().Replace("/","\")
    $score = 10

    if ($p -match '(^|\\)(readme|agents)\.md$') { $score += 160 }
    if ($p -match '(^|\\)package\.json$') { $score += 180 }
    if ($p -match '(^|\\)(vite|vitest|playwright|tsconfig|eslint|vercel)[^\\]*\.(json|js|mjs|cjs|ts)$') { $score += 120 }
    if ($p -match '^docs\\') { $score += 45 }
    if ($p -match '^src\\') { $score += 55 }
    if ($p -match '^supabase\\') { $score += 70 }
    if ($p -match '^tests?\\') { $score += 55 }
    if ($p -match '^scripts\\') { $score += 35 }

    switch ($Role.ToLowerInvariant()) {
        "pm" {
            if ($p -match '^docs\\product\\|product|user|sale|sales|inventory|employee|dashboard|auth|checkout') { $score += 160 }
            if ($p -match '\.(html|md)$') { $score += 40 }
        }
        "cto" {
            if ($p -match '^src\\|^supabase\\|architecture|bridge|controller|service|runtime|migration|schema') { $score += 170 }
            if ($p -match '\.(ts|tsx|js|mjs|sql)$') { $score += 35 }
        }
        "qa" {
            if ($p -match '^tests?\\|spec|test|verify|playwright|vitest|quality|regression') { $score += 220 }
            if ($p -match '^scripts\\') { $score += 60 }
        }
        "security" {
            if ($p -match '^supabase\\|auth|security|rls|policy|migration|edge|function|tenant|permission|role|secret|\.env') { $score += 240 }
            if ($p -match '\.sql$') { $score += 80 }
        }
        "devops" {
            if ($p -match '^\.github\\|vercel|deploy|workflow|docker|service-worker|manifest|pwa|build|operations|ci|cd') { $score += 240 }
            if ($p -match '^scripts\\|package\.json$') { $score += 80 }
        }
        "engineering-manager" {
            if ($p -match '^docs\\engineering\\|architecture|plan|task|result|review|qa|security') { $score += 200 }
        }
    }

    return $score
}

$root = (Resolve-Path $ProjectPath).Path
$builder = New-Object System.Text.StringBuilder

[void]$builder.AppendLine("# AI Company OS Repository Context Pack")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("Task: $Id")
[void]$builder.AppendLine("Owner: $Owner")
[void]$builder.AppendLine("Project root: $root")
[void]$builder.AppendLine("Generated: " + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))
[void]$builder.AppendLine("")
[void]$builder.AppendLine("This context is a bounded snapshot. Do not claim to have inspected files that are not included below.")

$required = @(
    "AGENTS.md",
    ".codex\agents\$Owner.md",
    "tasks\$Id.md",
    "docs\engineering\dispatch\$Id.md",
    ".codex\state\company-state.md",
    ".codex\state\current-sprint.md",
    "docs\engineering\project-intake.md",
    "docs\product\product-intake.md",
    "docs\architecture\architecture-intake.md",
    "docs\operations\operations-intake.md",
    "README.md",
    "package.json"
)

$used = $builder.Length
$included = @{}

foreach ($relative in $required) {
    if ($used -ge $MaxChars) { break }
    $added = Add-ContextFile -Builder $builder -Root $root -RelativePath $relative -Remaining ($MaxChars - $used)
    if ($added -gt 0) {
        $included[$relative.ToLowerInvariant()] = $true
        $used += $added
    }
}

$allowedExtensions = @(
    ".md",".txt",".json",".toml",".yml",".yaml",
    ".ts",".tsx",".js",".jsx",".mjs",".cjs",
    ".html",".css",".scss",".sql",".ps1",".sh"
)

$allFiles = Get-ChildItem $root -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $relative = $_.FullName.Substring($root.Length).TrimStart("\")
    $lower = $relative.ToLowerInvariant()

    if ($lower -match '(^|\\)(node_modules|\.git|dist|dist-refactor-modular|build|coverage|\.next|vendor)(\\|$)') { return $false }
    if ($lower -match '^\.codex\\runtime\\|^docs\\engineering\\agent-reports\\') { return $false }
    if ($lower -match '(^|\\)\.env($|\.)|secret|credential|private[-_]?key|service[-_]?account') { return $false }
    if ($lower -match '(^|\\)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock)
    if ($allowedExtensions -contains $ext) { return $true }
    if ($_.Name -in @("Dockerfile",".gitignore",".npmrc")) { return $true }
    return $false
} | ForEach-Object {
    $relative = $_.FullName.Substring($root.Length).TrimStart("\")
    [PSCustomObject]@{
        FullName = $_.FullName
        Relative = $relative
        Score = Get-RoleScore -RelativePath $relative -Role $Owner
    }
}

[void]$builder.AppendLine("")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("===== REPOSITORY INVENTORY =====")

foreach ($entry in ($allFiles | Sort-Object Relative | Select-Object -First 1200)) {
    $line = $entry.Relative
    if (($builder.Length + $line.Length + 2) -ge $MaxChars) { break }
    [void]$builder.AppendLine($line)
}

$used = $builder.Length

foreach ($entry in ($allFiles | Sort-Object @{Expression="Score";Descending=$true}, @{Expression="Relative";Descending=$false})) {
    if ($used -ge $MaxChars) { break }

    $key = $entry.Relative.ToLowerInvariant()
    if ($included.ContainsKey($key)) { continue }

    $added = Add-ContextFile -Builder $builder -Root $root -RelativePath $entry.Relative -Remaining ($MaxChars - $used)
    if ($added -gt 0) {
        $included[$key] = $true
        $used += $added
    }
}

$builder.ToString()
) { return $false }
    if ($lower -match '\.(pem|key|p12|pfx|crt|cer)
    if ($allowedExtensions -contains $ext) { return $true }
    if ($_.Name -in @("Dockerfile",".gitignore",".npmrc")) { return $true }
    return $false
} | ForEach-Object {
    $relative = $_.FullName.Substring($root.Length).TrimStart("\")
    [PSCustomObject]@{
        FullName = $_.FullName
        Relative = $relative
        Score = Get-RoleScore -RelativePath $relative -Role $Owner
    }
}

[void]$builder.AppendLine("")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("===== REPOSITORY INVENTORY =====")

foreach ($entry in ($allFiles | Sort-Object Relative | Select-Object -First 1200)) {
    $line = $entry.Relative
    if (($builder.Length + $line.Length + 2) -ge $MaxChars) { break }
    [void]$builder.AppendLine($line)
}

$used = $builder.Length

foreach ($entry in ($allFiles | Sort-Object @{Expression="Score";Descending=$true}, @{Expression="Relative";Descending=$false})) {
    if ($used -ge $MaxChars) { break }

    $key = $entry.Relative.ToLowerInvariant()
    if ($included.ContainsKey($key)) { continue }

    $added = Add-ContextFile -Builder $builder -Root $root -RelativePath $entry.Relative -Remaining ($MaxChars - $used)
    if ($added -gt 0) {
        $included[$key] = $true
        $used += $added
    }
}

$builder.ToString()
) { return $false }

    $ext = $_.Extension.ToLowerInvariant()
    if ($allowedExtensions -contains $ext) { return $true }
    if ($_.Name -in @("Dockerfile",".gitignore",".npmrc")) { return $true }
    return $false
} | ForEach-Object {
    $relative = $_.FullName.Substring($root.Length).TrimStart("\")
    [PSCustomObject]@{
        FullName = $_.FullName
        Relative = $relative
        Score = Get-RoleScore -RelativePath $relative -Role $Owner
    }
}

[void]$builder.AppendLine("")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("===== REPOSITORY INVENTORY =====")

foreach ($entry in ($allFiles | Sort-Object Relative | Select-Object -First 1200)) {
    $line = $entry.Relative
    if (($builder.Length + $line.Length + 2) -ge $MaxChars) { break }
    [void]$builder.AppendLine($line)
}

$used = $builder.Length

foreach ($entry in ($allFiles | Sort-Object @{Expression="Score";Descending=$true}, @{Expression="Relative";Descending=$false})) {
    if ($used -ge $MaxChars) { break }

    $key = $entry.Relative.ToLowerInvariant()
    if ($included.ContainsKey($key)) { continue }

    $added = Add-ContextFile -Builder $builder -Root $root -RelativePath $entry.Relative -Remaining ($MaxChars - $used)
    if ($added -gt 0) {
        $included[$key] = $true
        $used += $added
    }
}

$builder.ToString()
