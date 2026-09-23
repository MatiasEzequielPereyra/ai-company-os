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

$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))
    $hash = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
}
finally {
    $sha.Dispose()
}

$mutex = New-Object System.Threading.Mutex($false,("AICompanyOSMetrics_" + $hash.Substring(0,24)))
$acquired = $false
try {
    $acquired = $mutex.WaitOne(10000)
    if (-not $acquired) { throw "Timed out waiting for the operational metrics append lock." }
    [System.IO.File]::AppendAllText($path,$line + [Environment]::NewLine,(New-Object System.Text.UTF8Encoding($false)))
}
finally {
    if ($acquired) { $mutex.ReleaseMutex() | Out-Null }
    $mutex.Dispose()
}

return $path
