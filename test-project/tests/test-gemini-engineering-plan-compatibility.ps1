param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$schemaPath = Join-Path $repoRoot 'schemas/engineering-plan-result.schema.json'
$schemaHash = (Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('aico-gemini-em-schema-'+[guid]::NewGuid().ToString('N'))
$savedKey = $env:GEMINI_API_KEY
$savedTestRoot = $env:AICO_GEMINI_EM_TEST_ROOT
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function New-Work([int]$Count=1,[int]$AreaCount=1,[int]$DependencyCount=0) {
    $items = @()
    for ($i=0; $i -lt $Count; $i++) {
        $dependencies = @()
        if ($i -eq $Count-1) { for ($d=0; $d -lt $DependencyCount; $d++) { $dependencies += ('work-'+$d) } }
        $areas = @(); for ($a=0; $a -lt $AreaCount; $a++) { $areas += ('src/module-'+$a+'.py') }
        $items += @{key=('work-'+$i);kind='IMPLEMENTATION';change=('Implement product module '+$i+' with acceptance behavior');owner='backend';areas=$areas;depends_on=$dependencies;verify='Run product acceptance checks'}
    }
    return ,$items
}
function New-Result([string]$Outcome='COMPLETED',[object[]]$Work=(New-Work)) {
    $result = @{outcome=$Outcome;summary='Concrete engineering plan';report_markdown='Implementation plan identifies product modules and verification.';executable_work=$Work;verification='Acceptance assertions recorded';decisions='Use product module implementation';blockers='NONE';recommended_next='Execute approved product work';completion_check=@{substantive_role_deliverable_produced=$true;missing_required_outputs=@();evidence='Detailed owner plan supplied'}}
    if ($Outcome -eq 'BLOCKED') {
        $result.blockers='CEO decision on deployment region is pending.'
        $result.completion_check.substantive_role_deliverable_produced=$false
        $result.execution_blocker=@{kind='external_decision';prerequisite='CEO must approve deployment region';evidence='WR-001 requests a CEO region decision before implementation';resolution_owner='ceo';role_can_resolve=$false;why_role_cannot_resolve='Engineering Manager cannot authorize this business jurisdiction decision'}
    }
    return $result
}
function Invoke-FakeResult([string]$Name,[object]$Payload) {
    [IO.File]::WriteAllText((Join-Path $tempRoot 'payload.json'),($Payload | ConvertTo-Json -Depth 30))
    $path = Join-Path $tempRoot ($Name+'.json')
    & (Join-Path $repoRoot 'scripts/providers/invoke-gemini.ps1') -Prompt 'Build the engineering implementation plan.' -Context 'Deterministic schema portability regression.' -SchemaPath $schemaPath -OutputPath $path | Out-Null
    return $path
}
function Assert-Canonical([string]$Path) { & (Join-Path $repoRoot 'scripts/validate-json-contract.ps1') -JsonPath $Path -SchemaPath $schemaPath }
function Assert-Semantics([string]$Path) { & (Join-Path $repoRoot 'scripts/validate-analysis-result-semantics.ps1') -JsonPath $Path }
function Assert-Rejected([string]$Name,[object]$Payload,[string]$Validator,[string]$Expected) {
    $path = Invoke-FakeResult $Name $Payload
    $failed = $false
    try { if ($Validator -eq 'canonical') { Assert-Canonical $path } else { Assert-Semantics $path } } catch { $failed = $_.Exception.Message -match $Expected }
    Assert-True $failed ($Name+' must be rejected by original '+$Validator+' validator for '+$Expected)
}
function Invoke-RestMethod {
    param($Method,$Uri,$Headers,$ContentType,$Body,$TimeoutSec)
    Add-Content -LiteralPath (Join-Path $env:AICO_GEMINI_EM_TEST_ROOT 'calls.txt') -Value 'CALL'
    $request = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
    $wire = $request.generationConfig.responseJsonSchema
    # Model the isolated provider failure: bounded object arrays reject registration.
    if ($null -ne $wire.properties.executable_work.PSObject.Properties['maxItems']) { throw 'HTTP 400 INVALID_ARGUMENT: bounded object array schema rejected' }
    [IO.File]::WriteAllText((Join-Path $env:AICO_GEMINI_EM_TEST_ROOT 'wire.json'),($wire | ConvertTo-Json -Depth 30))
    $payload = Get-Content -LiteralPath (Join-Path $env:AICO_GEMINI_EM_TEST_ROOT 'payload.json') -Raw -Encoding UTF8
    return [pscustomobject]@{candidates=@([pscustomobject]@{content=[pscustomobject]@{parts=@([pscustomobject]@{text=$payload})}})}
}
try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $env:GEMINI_API_KEY = 'deterministic-fake-no-network'
    $env:AICO_GEMINI_EM_TEST_ROOT = $tempRoot
    $path = Invoke-FakeResult 'completed' (New-Result)
    Assert-Canonical $path; Assert-Semantics $path
    $wire = Get-Content -LiteralPath (Join-Path $tempRoot 'wire.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $work = $wire.properties.executable_work
    Assert-True ($work.type -eq 'array' -and $work.minItems -eq 0) 'Object array type and minItems=0 must remain in transport.'
    Assert-True ($null -eq $work.PSObject.Properties['maxItems']) 'Only object array maxItems must be omitted.'
    $original = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    foreach ($name in @('key','kind','change','owner','areas','depends_on','verify')) {
        Assert-True ($null -ne $work.items.properties.PSObject.Properties[$name]) ('Full object array property missing: '+$name)
        Assert-True (@($work.items.required) -contains $name) ('Full object array required field missing: '+$name)
    }
    Assert-True ($work.items.additionalProperties -eq $false) 'Object array must remain closed.'
    foreach ($name in @('kind','owner')) {
        Assert-True ((@($work.items.properties.$name.enum) -join '|') -ceq (@($original.properties.executable_work.items.properties.$name.enum) -join '|')) ('Object array enum changed: '+$name)
    }
    Assert-True ($work.items.properties.areas.maxItems -eq 12 -and $work.items.properties.areas.minItems -eq 1) 'Scalar areas array bounds must remain.'
    Assert-True ($work.items.properties.depends_on.maxItems -eq 12) 'Scalar dependency bound must remain.'
    Assert-True ($wire.properties.completion_check.properties.missing_required_outputs.maxItems -eq 30) 'Scalar missing outputs bound must remain.'
    $path = Invoke-FakeResult 'blocked-empty' (New-Result 'BLOCKED' @())
    Assert-Canonical $path; Assert-Semantics $path
    Assert-Rejected 'completed-empty' (New-Result 'COMPLETED' @()) 'semantic' 'contains no executable_work'
    Assert-Rejected 'blocked-nonempty' (New-Result 'BLOCKED' (New-Work)) 'semantic' 'must not contain executable work'
    Assert-Rejected 'work-over-limit' (New-Result 'COMPLETED' (New-Work 21)) 'canonical' 'maxItems|at most|maximum'
    Assert-Rejected 'areas-over-limit' (New-Result 'COMPLETED' (New-Work 1 13)) 'canonical' 'maxItems|at most|maximum'
    Assert-Rejected 'dependencies-over-limit' (New-Result 'COMPLETED' (New-Work 20 1 13)) 'canonical' 'maxItems|at most|maximum'
    $path = Invoke-FakeResult 'boundary-20-12-12' (New-Result 'COMPLETED' (New-Work 20 12 12))
    Assert-Canonical $path; Assert-Semantics $path
    Assert-True ((Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash -ceq $schemaHash) 'Canonical EM schema must remain byte-identical.'
    Assert-True (@(Get-Content -LiteralPath (Join-Path $tempRoot 'calls.txt')).Count -eq 8) 'Each deterministic transport must be called exactly once, with no retry.'
    $zeroSchema = Join-Path $tempRoot 'zero.schema.json'
    $zeroValue = Join-Path $tempRoot 'zero.json'
    [IO.File]::WriteAllText($zeroSchema,'{"type":"array","maxItems":0,"items":{"type":"string"}}')
    [IO.File]::WriteAllText($zeroValue,'[]')
    & (Join-Path $repoRoot 'scripts/validate-json-contract.ps1') -JsonPath $zeroValue -SchemaPath $zeroSchema | Out-Null
    [IO.File]::WriteAllText($zeroValue,'["one"]')
    $zeroRejected = $false
    try { & (Join-Path $repoRoot 'scripts/validate-json-contract.ps1') -JsonPath $zeroValue -SchemaPath $zeroSchema | Out-Null }
    catch { $zeroRejected = $_.Exception.Message -match 'at most 0' }
    Assert-True $zeroRejected 'maxItems=0 must reject one item.'
    Write-Host 'PASS: Gemini EM object-array schema compatibility; canonical and semantic bounds retained; COMPLETED/BLOCKED and 20/12/12 boundary' -ForegroundColor Green
}
finally {
    $env:GEMINI_API_KEY = $savedKey
    $env:AICO_GEMINI_EM_TEST_ROOT = $savedTestRoot
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/')) + [IO.Path]::DirectorySeparatorChar
    Assert-True ($resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) 'Unsafe regression cleanup path.'
    if (Test-Path $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
}
