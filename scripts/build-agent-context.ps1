param(
    [string]$ProjectPath = ".",
    [Parameter(Mandatory = $true)]
    [string]$Id,
    [Parameter(Mandatory = $true)]
    [string]$Owner,
    [int]$MaxChars = 120000,
    [string[]]$RequiredFiles = @()
)

$ErrorActionPreference = "Stop"

function Add-ContextFile {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$Root,
        [string]$RelativePath,
        [int]$Remaining,
        [switch]$RequireComplete
    )

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path $fullPath -PathType Leaf)) { return 0 }

    try {
        $content = Get-Content $fullPath -Raw -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        return 0
    }

    if ($null -eq $content) { $content = "" }

    $header = [Environment]::NewLine + [Environment]::NewLine + "===== FILE: " + $RelativePath + " =====" + [Environment]::NewLine
    if ($header.Length -ge $Remaining) { return 0 }

    $available = $Remaining - $header.Length
    if ($available -le 0) { return 0 }

    if ($RequireComplete) {
        if ($content.Length -gt $available) {
            throw "Required context file cannot fit completely within the context budget: $RelativePath"
        }
    }
    else {
        $allowed = [Math]::Min($available,60000)
        if ($content.Length -gt $allowed) {
            $marker = [Environment]::NewLine + "[TRUNCATED BY AI COMPANY OS CONTEXT BUILDER]"
            $take = [Math]::Max(0, $allowed - $marker.Length)
            $content = $content.Substring(0,$take) + $marker
        }
    }

    [void]$Builder.Append($header)
    [void]$Builder.Append($content)
    return ($header.Length + $content.Length)
}

function Get-RoleScore {
    param(
        [string]$RelativePath,
        [string]$Role
    )

    $p = $RelativePath.ToLowerInvariant().Replace("/","\")
    $score = 10

    if ($p -match '(^|\\)(readme|agents)\.md$') { $score += 160 }
    if ($p -match '(^|\\)package\.json$') { $score += 180 }
    if ($p -match '(^|\\)(vite|vitest|playwright|tsconfig|eslint|vercel)[^\\]*\.(json|js|mjs|cjs|ts)$') { $score += 120 }

    if ($p -match '^docs\\') { $score += 45 }
    if ($p -match '^docs\\audit\\') { $score += 220 }
    if ($p -match '^docs\\plans\\') { $score += 120 }
    if ($p -match '^src\\') { $score += 55 }
    if ($p -match '^supabase\\') { $score += 70 }
    if ($p -match '^tests?\\') { $score += 55 }
    if ($p -match '^scripts\\') { $score += 35 }
    if ($p -match '^\.github\\workflows\\') { $score += 110 }

    switch ($Role.ToLowerInvariant()) {
        "pm" {
            if ($p -match '^docs\\product\\|product|user|sale|sales|inventory|employee|dashboard|auth|checkout') { $score += 160 }
            if ($p -match '^docs\\audit\\|^docs\\plans\\') { $score += 180 }
            if ($p -match '^src\\(auth|dashboard|products|sales|inventory|purchases|team|cash|offline|commercial)\\') { $score += 150 }
            if ($p -match '\.(html|md)$') { $score += 40 }
        }
        "cto" {
            if ($p -match '^src\\|^supabase\\|architecture|bridge|controller|service|runtime|migration|schema') { $score += 170 }
            if ($p -match '^docs\\audit\\|^docs\\plans\\') { $score += 130 }
            if ($p -match '\.(ts|tsx|js|mjs|sql)$') { $score += 35 }
        }
        "qa" {
            if ($p -match '^tests?\\|spec|test|verify|playwright|vitest|quality|regression') { $score += 220 }
            if ($p -match '^docs\\audit\\|^docs\\plans\\') { $score += 120 }
            if ($p -match '^scripts\\') { $score += 60 }
        }
        "security" {
            if ($p -match '^supabase\\|auth|security|rls|policy|migration|edge|function|tenant|permission|role') { $score += 240 }
            if ($p -match '^docs\\audit\\') { $score += 140 }
            if ($p -match '\.sql$') { $score += 80 }
        }
        "devops" {
            if ($p -match '^\.github\\|vercel|deploy|workflow|docker|service-worker|manifest|pwa|operations|ci|cd') { $score += 240 }
            if ($p -match '^docs\\audit\\|^docs\\plans\\') { $score += 110 }
            if ($p -match '^scripts\\|package\.json$') { $score += 80 }
        }
        "engineering-manager" {
            if ($p -match '^docs\\engineering\\|architecture|plan|task|result|review|qa|security') { $score += 200 }
        }
    }

    return $score
}

$root = (Resolve-Path $ProjectPath).Path

$managedFiles = @{}
$managedManifestPath = Join-Path $root ".codex\managed-files.json"

if (Test-Path $managedManifestPath -PathType Leaf) {
    try {
        $managedManifest = Get-Content $managedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

        foreach ($managedPath in @($managedManifest.managed_files)) {
            if ([string]::IsNullOrWhiteSpace([string]$managedPath)) { continue }

            $normalizedManaged = ([string]$managedPath).Trim().Replace("/","\").TrimStart(".","\").ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace($normalizedManaged)) {
                $managedFiles[$normalizedManaged] = $true
            }
        }
    }
    catch {
        throw "Invalid AI Company OS managed-files manifest: $managedManifestPath"
    }
}

$builder = New-Object System.Text.StringBuilder

[void]$builder.AppendLine("# AI Company OS Repository Context Pack")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("Task: $Id")
[void]$builder.AppendLine("Owner: $Owner")
[void]$builder.AppendLine("Generated: " + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))
[void]$builder.AppendLine("")
[void]$builder.AppendLine("This is a bounded repository snapshot. Do not claim to have inspected omitted files.")

$required = @(
    "AGENTS.md",
    "docs\PROJECT-BRIEF.md",
    "docs\product\product-context.md",
    "docs\architecture\architecture-context.md",
    "docs\engineering\engineering-context.md",
    "docs\operations\operations-context.md",
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

$included = @{}
$used = $builder.Length

foreach ($relative in @($RequiredFiles)) {
    if ([string]::IsNullOrWhiteSpace($relative)) { continue }
    if ($used -ge $MaxChars) {
        throw "Required context files exhausted the configured context budget."
    }

    $key = $relative.ToLowerInvariant().Replace("/","\")
    if ($included.ContainsKey($key)) { continue }

    $added = Add-ContextFile -Builder $builder -Root $root -RelativePath $relative -Remaining ($MaxChars - $used) -RequireComplete
    if ($added -le 0) {
        throw "Required context file was resolved but could not be included: $relative"
    }

    $included[$key] = $true
    $used += $added
}

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

$allFiles = @(
    foreach ($relativeName in @(Get-ChildItem $root -File -Recurse -Force -Name -ErrorAction SilentlyContinue)) {
        $relative = ([string]$relativeName).Replace("/","\")
        $fullPath = Join-Path $root $relative

        try {
            $fileInfo = Get-Item $fullPath -Force -ErrorAction Stop
        }
        catch {
            continue
        }

        $lower = $relative.ToLowerInvariant()
        $name = $fileInfo.Name.ToLowerInvariant()
        $ext = $fileInfo.Extension.ToLowerInvariant()
        $allowed = $false

        if ($lower -match '(^|\\)(node_modules|\.git|dist|dist-refactor-modular|build|coverage|\.next|vendor)(\\|$)') {
            $allowed = $false
        }
        elseif ($managedFiles.ContainsKey($lower)) {
            $allowed = $false
        }
        elseif ($lower -match '^\.codex\\runtime\\|^docs\\engineering\\agent-reports\\') {
            $allowed = $false
        }
        elseif ($name -like ".env*") {
            $allowed = $false
        }
        elseif ($name -match 'secret|credential|private[-_]?key|service[-_]?account') {
            $allowed = $false
        }
        elseif ($name -in @("package-lock.json","pnpm-lock.yaml","yarn.lock")) {
            $allowed = $false
        }
        elseif ($ext -in @(".pem",".key",".p12",".pfx",".crt",".cer")) {
            $allowed = $false
        }
        elseif ($fileInfo.Length -gt 500000) {
            $allowed = $false
        }
        elseif ($allowedExtensions -contains $ext) {
            $allowed = $true
        }
        elseif ($fileInfo.Name -in @("Dockerfile",".gitignore",".npmrc")) {
            $allowed = $true
        }

        if ($allowed) {
            [PSCustomObject]@{
                Relative = $relative
                Score = Get-RoleScore -RelativePath $relative -Role $Owner
            }
        }
    }
)

$inventoryReserve = [Math]::Min(30000,[Math]::Max(2000,[int]($MaxChars * 0.15)))
$contentBudget = [Math]::Max(0,$MaxChars - $inventoryReserve)
$used = $builder.Length

foreach ($entry in ($allFiles | Sort-Object @{Expression="Score";Descending=$true}, @{Expression="Relative";Descending=$false})) {
    if ($used -ge $contentBudget) { break }

    $key = $entry.Relative.ToLowerInvariant()
    if ($included.ContainsKey($key)) { continue }

    $added = Add-ContextFile -Builder $builder -Root $root -RelativePath $entry.Relative -Remaining ($contentBudget - $used)
    if ($added -gt 0) {
        $included[$key] = $true
        $used += $added
    }
}

[void]$builder.AppendLine("")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("===== REPOSITORY INVENTORY =====")

foreach ($entry in ($allFiles | Sort-Object Relative | Select-Object -First 1600)) {
    $line = $entry.Relative
    if (($builder.Length + $line.Length + 2) -ge $MaxChars) { break }
    [void]$builder.AppendLine($line)
}

if ($builder.Length -gt $MaxChars) {
    return $builder.ToString().Substring(0,$MaxChars)
}

$builder.ToString()
