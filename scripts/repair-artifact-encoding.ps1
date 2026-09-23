param(
    [string]$ProjectPath = ".",

    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Get-MojibakeScore {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return 0 }

    $score = 0
    foreach ($pattern in @("Ã","Â","â","ð","ƒ","€","™","œ","ž")) {
        $score += ([regex]::Matches($Value,[regex]::Escape($pattern))).Count
    }

    $score += 100 * ([regex]::Matches($Value,[regex]::Escape([char]0xFFFD))).Count
    return $score
}

function Repair-MojibakeText {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return $Value }

    $current = $Value
    $strict1252 = [System.Text.Encoding]::GetEncoding(
        1252,
        [System.Text.EncoderFallback]::ExceptionFallback,
        [System.Text.DecoderFallback]::ExceptionFallback
    )
    $utf8 = New-Object System.Text.UTF8Encoding($false,$true)

    for ($i = 0; $i -lt 4; $i++) {
        $currentScore = Get-MojibakeScore $current
        if ($currentScore -eq 0) { break }

        try {
            $byteList = New-Object "System.Collections.Generic.List[byte]"

            foreach ($character in $current.ToCharArray()) {
                $codePoint = [int][char]$character

                if ($codePoint -le 255) {
                    $byteList.Add([byte]$codePoint)
                    continue
                }

                $encodedCharacter = $strict1252.GetBytes([string]$character)
                if ($encodedCharacter.Length -ne 1) {
                    throw "Character cannot be represented as a single legacy byte."
                }

                $byteList.Add($encodedCharacter[0])
            }

            $candidate = $utf8.GetString($byteList.ToArray())
        }
        catch {
            break
        }

        $candidateScore = Get-MojibakeScore $candidate
        if ($candidateScore -ge $currentScore) { break }

        $current = $candidate
    }

    return $current
}

function Repair-ArtifactContent {
    param([string]$Content)

    return [regex]::Replace(
        $Content,
        '[^\r\n]+',
        {
            param($match)
            return (Repair-MojibakeText -Value $match.Value)
        }
    )
}

$root = (Resolve-Path $ProjectPath).Path

$artifactRoots = @(
    "tasks",
    "docs\engineering",
    ".codex\state"
)

$files = @()

foreach ($relativeRoot in $artifactRoots) {
    $path = Join-Path $root $relativeRoot
    if (-not (Test-Path $path)) { continue }

    $files += Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in @(".md",".json",".txt") }
}

$files = @($files | Sort-Object FullName -Unique)
$changed = @()

foreach ($file in $files) {
    $original = Get-Content $file.FullName -Raw -Encoding UTF8
    if ($null -eq $original) { $original = "" }

    $repaired = Repair-ArtifactContent -Content $original

    if ($repaired -eq $original) { continue }

    $beforeScore = Get-MojibakeScore $original
    $afterScore = Get-MojibakeScore $repaired

    if ($afterScore -ge $beforeScore) { continue }

    $relative = $file.FullName.Substring($root.Length).TrimStart("\")
    $changed += [PSCustomObject]@{
        File = $relative
        BeforeScore = $beforeScore
        AfterScore = $afterScore
    }

    if ($Apply) {
        [System.IO.File]::WriteAllText(
            $file.FullName,
            $repaired,
            (New-Object System.Text.UTF8Encoding($false))
        )
    }
}

if ($changed.Count -eq 0) {
    Write-Host "No repairable mojibake found in AI Company OS artifacts." -ForegroundColor Green
    return
}

$changed | Format-Table File,BeforeScore,AfterScore -AutoSize
Write-Host ""

if ($Apply) {
    Write-Host ("Repaired artifact files: " + $changed.Count) -ForegroundColor Green
}
else {
    Write-Host ("Repairable artifact files: " + $changed.Count) -ForegroundColor Yellow
    Write-Host "Dry run only. Re-run with -Apply to write changes." -ForegroundColor Yellow
}
