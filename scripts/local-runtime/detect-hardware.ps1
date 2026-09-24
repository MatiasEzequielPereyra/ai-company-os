param(
    [string]$FixturePath = "",
    [string]$OllamaBaseUrl = "",
    [switch]$SkipOllamaProbe
)

$ErrorActionPreference = "Stop"

function Get-Sha256Hex {
    param([string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
        $sha.Dispose()
    }
}

function Get-CapabilityProfile {
    param(
        [long]$RamBytes,
        [bool]$DiscreteGpu,
        [long]$VramBytes
    )

    $gb = 1GB
    $ramGb = if ($RamBytes -gt 0) { [double]$RamBytes / $gb } else { 0 }
    $vramGb = if ($VramBytes -gt 0) { [double]$VramBytes / $gb } else { 0 }

    if ($DiscreteGpu -and $vramGb -ge 15) { return "LOCAL_GPU_16GB_PLUS" }
    if ($DiscreteGpu -and $vramGb -ge 10) { return "LOCAL_GPU_12GB" }
    if ($DiscreteGpu -and $vramGb -ge 7) { return "LOCAL_GPU_8GB" }
    if ($DiscreteGpu -and $vramGb -ge 5) { return "LOCAL_GPU_6GB" }
    if ($ramGb -ge 28) { return "LOCAL_CPU_HIGH" }
    return "LOCAL_CPU_LOW"
}

if ([string]::IsNullOrWhiteSpace($OllamaBaseUrl)) {
    $OllamaBaseUrl = if ([string]::IsNullOrWhiteSpace($env:OLLAMA_BASE_URL)) {
        "http://localhost:11434"
    }
    else {
        $env:OLLAMA_BASE_URL.TrimEnd('/')
    }
}

$cpuName = ""
$logicalProcessors = [Environment]::ProcessorCount
$ramBytes = 0L
$gpuName = ""
$gpuVendor = ""
$vramBytes = 0L
$discreteGpu = $false
$ollamaReachable = $false
$models = @()

if (-not [string]::IsNullOrWhiteSpace($FixturePath)) {
    if (-not (Test-Path $FixturePath -PathType Leaf)) {
        throw "Hardware fixture not found: $FixturePath"
    }

    $fixture = Get-Content $FixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $cpuName = [string]$fixture.cpu_name
    if ($null -ne $fixture.logical_processors) { $logicalProcessors = [int]$fixture.logical_processors }
    if ($null -ne $fixture.ram_bytes) { $ramBytes = [long]$fixture.ram_bytes }
    $gpuName = [string]$fixture.gpu_name
    $gpuVendor = [string]$fixture.gpu_vendor
    if ($null -ne $fixture.gpu_vram_bytes) { $vramBytes = [long]$fixture.gpu_vram_bytes }
    if ($null -ne $fixture.gpu_discrete) { $discreteGpu = [bool]$fixture.gpu_discrete }
    if ($null -ne $fixture.ollama_reachable) { $ollamaReachable = [bool]$fixture.ollama_reachable }

    if ($null -ne $fixture.ollama_models) {
        $models = @($fixture.ollama_models | ForEach-Object {
            [PSCustomObject]@{
                name = [string]$_.name
                size = [long]$_.size
            }
        })
    }
}
else {
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        try {
            $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            $ramBytes = [long]$computer.TotalPhysicalMemory
        }
        catch {}

        try {
            $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
            $cpuName = [string]$cpu.Name
            if ($null -ne $cpu.NumberOfLogicalProcessors) {
                $logicalProcessors = [int]$cpu.NumberOfLogicalProcessors
            }
        }
        catch {}

        $nvidiaCommand = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if ($null -ne $nvidiaCommand) {
            try {
                $rows = @(& $nvidiaCommand.Source --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null)
                $best = $null
                foreach ($row in $rows) {
                    if ([string]::IsNullOrWhiteSpace([string]$row)) { continue }
                    $parts = ([string]$row).Split(",")
                    if ($parts.Count -lt 2) { continue }
                    $mb = 0
                    if (-not [int]::TryParse($parts[1].Trim(),[ref]$mb)) { continue }
                    if ($null -eq $best -or $mb -gt $best.MemoryMb) {
                        $best = [PSCustomObject]@{ Name = $parts[0].Trim(); MemoryMb = $mb }
                    }
                }

                if ($null -ne $best) {
                    $gpuName = [string]$best.Name
                    $gpuVendor = "NVIDIA"
                    $vramBytes = [long]$best.MemoryMb * 1MB
                    $discreteGpu = $true
                }
            }
            catch {}
        }

        if ([string]::IsNullOrWhiteSpace($gpuName)) {
            try {
                $controllers = @(Get-CimInstance Win32_VideoController -ErrorAction Stop)
                $preferred = $controllers |
                    Sort-Object @{ Expression = {
                        $name = [string]$_.Name
                        if ($name -match '(?i)NVIDIA|AMD|Radeon|Arc') { 1 } else { 0 }
                    }; Descending = $true }, @{ Expression = { [long]$_.AdapterRAM }; Descending = $true } |
                    Select-Object -First 1

                if ($null -ne $preferred) {
                    $gpuName = [string]$preferred.Name
                    if ($gpuName -match '(?i)NVIDIA') { $gpuVendor = "NVIDIA" }
                    elseif ($gpuName -match '(?i)AMD|Radeon') { $gpuVendor = "AMD" }
                    elseif ($gpuName -match '(?i)Intel') { $gpuVendor = "Intel" }
                    else { $gpuVendor = "Unknown" }

                    if ($null -ne $preferred.AdapterRAM) {
                        $vramBytes = [long]$preferred.AdapterRAM
                    }

                    $discreteGpu = $gpuName -match '(?i)NVIDIA|AMD|Radeon|Arc' -and $gpuName -notmatch '(?i)Intel.*UHD|Intel.*Iris'
                }
            }
            catch {}
        }
    }
    else {
        if (Test-Path "/proc/meminfo") {
            try {
                $memLine = Get-Content "/proc/meminfo" | Where-Object { $_ -match '^MemTotal:' } | Select-Object -First 1
                if ($memLine -match 'MemTotal:\s+(\d+)\s+kB') {
                    $ramBytes = [long]$Matches[1] * 1KB
                }
            }
            catch {}
        }

        if (Test-Path "/proc/cpuinfo") {
            try {
                $modelLine = Get-Content "/proc/cpuinfo" | Where-Object { $_ -match '^model name\s*:' } | Select-Object -First 1
                if ($modelLine -match ':\s*(.+)$') { $cpuName = $Matches[1].Trim() }
            }
            catch {}
        }

        $nvidiaCommand = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if ($null -ne $nvidiaCommand) {
            try {
                $row = @(& $nvidiaCommand.Source --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null) | Select-Object -First 1
                if (-not [string]::IsNullOrWhiteSpace([string]$row)) {
                    $parts = ([string]$row).Split(",")
                    $mb = 0
                    if ($parts.Count -ge 2 -and [int]::TryParse($parts[1].Trim(),[ref]$mb)) {
                        $gpuName = $parts[0].Trim()
                        $gpuVendor = "NVIDIA"
                        $vramBytes = [long]$mb * 1MB
                        $discreteGpu = $true
                    }
                }
            }
            catch {}
        }
    }

    if (-not $SkipOllamaProbe) {
        try {
            $tags = Invoke-RestMethod -Method Get -Uri ($OllamaBaseUrl.TrimEnd('/') + "/api/tags") -TimeoutSec 5
            $ollamaReachable = $true
            if ($null -ne $tags.models) {
                $models = @($tags.models | ForEach-Object {
                    [PSCustomObject]@{
                        name = [string]$_.name
                        size = [long]$_.size
                    }
                })
            }
        }
        catch {
            $ollamaReachable = $false
            $models = @()
        }
    }
}

$profile = Get-CapabilityProfile -RamBytes $ramBytes -DiscreteGpu $discreteGpu -VramBytes $vramBytes

$ramScore = [Math]::Min(20.0,([double]$ramBytes / 32GB) * 20.0)
$cpuScore = [Math]::Min(15.0,([double]$logicalProcessors / 16.0) * 15.0)
$gpuScore = 0.0
if ($discreteGpu) {
    $gpuScore = [Math]::Min(40.0,([double]$vramBytes / 16GB) * 40.0)
}
elseif ($vramBytes -gt 0) {
    $gpuScore = [Math]::Min(5.0,([double]$vramBytes / 4GB) * 5.0)
}
$ollamaScore = if ($ollamaReachable) { 10.0 } else { 0.0 }
$fitModelCount = @($models | Where-Object { [long]$_.size -le 10500000000 }).Count
$modelScore = [Math]::Min(15.0,[double]$fitModelCount * 7.5)
$capabilityScore = [int][Math]::Round([Math]::Min(100.0,$ramScore + $cpuScore + $gpuScore + $ollamaScore + $modelScore))

$fingerprintSource = @(
    $cpuName,
    [string]$logicalProcessors,
    [string]$ramBytes,
    $gpuName,
    $gpuVendor,
    [string]$vramBytes,
    [string]$discreteGpu
) -join "|"

[PSCustomObject]@{
    schema_version = 1
    generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    hardware_fingerprint = Get-Sha256Hex -Value $fingerprintSource
    profile = $profile
    capability_score = $capabilityScore
    cpu = [PSCustomObject]@{
        name = $cpuName
        logical_processors = $logicalProcessors
    }
    memory = [PSCustomObject]@{
        total_bytes = $ramBytes
        total_gb = [math]::Round(($ramBytes / 1GB),2)
    }
    gpu = [PSCustomObject]@{
        name = $gpuName
        vendor = $gpuVendor
        discrete = $discreteGpu
        vram_bytes = $vramBytes
        vram_gb = [math]::Round(($vramBytes / 1GB),2)
    }
    ollama = [PSCustomObject]@{
        reachable = $ollamaReachable
        base_url = $OllamaBaseUrl.TrimEnd('/')
        models = @($models)
    }
}
