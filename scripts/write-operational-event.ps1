param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][hashtable]$Event
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path $ProjectPath).Path
$metricsDir = Join-Path $root ".codex\runtime\metrics"
if (-not (Test-Path $metricsDir)) { New-Item -ItemType Directory -Force -Path $metricsDir | Out-Null }

$payload = @{}
foreach ($key in $Event.Keys) { $payload[$key] = $Event[$key] }

$payload["schema_version"] = 1
if (-not $payload.ContainsKey("timestamp")) {
    $payload["timestamp"] = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

$line = $payload | ConvertTo-Json -Depth 10 -Compress
$path = Join-Path $metricsDir "events.jsonl"
[System.IO.File]::AppendAllText($path,$line + [Environment]::NewLine,(New-Object System.Text.UTF8Encoding($false)))

return $path
