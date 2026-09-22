param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$initScript = Join-Path $repoRoot "scripts\initialize-project.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("aico-intake-" + [guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "src") | Out-Null

    $packageJson = @'
{
  "name": "aico-intake-fixture",
  "version": "1.0.0",
  "scripts": {
    "dev": "vite",
    "test": "echo test",
    "build": "vite build"
  },
  "dependencies": {
    "react": "1.0.0",
    "@supabase/supabase-js": "1.0.0"
  },
  "devDependencies": {
    "vite": "1.0.0"
  }
}
'@

    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "package.json"),
        $packageJson,
        (New-Object System.Text.UTF8Encoding($false))
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot "package-lock.json"),
        "{}",
        (New-Object System.Text.UTF8Encoding($false))
    )

    & $initScript -ProjectPath $tempRoot

    $intake = Join-Path $tempRoot "docs\engineering\project-intake.md"
    if (-not (Test-Path $intake)) { throw "project-intake.md was not generated" }

    $content = Get-Content $intake -Raw
    foreach ($expected in @("JavaScript/TypeScript", "React", "Vite", "Supabase", "npm", "src")) {
        if ($content -notmatch [regex]::Escape($expected)) {
            throw "Expected intake value not found: $expected"
        }
    }

    Write-Host "PASS: project intake smoke test" -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}
