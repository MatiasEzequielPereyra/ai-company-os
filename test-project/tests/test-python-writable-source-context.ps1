param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase ('aico-python-writable-source-'+[guid]::NewGuid().ToString('N'))
$savedKey = $env:OPENROUTER_API_KEY
function Write-Fixture([string]$Relative,[string]$Text) {
    $path = Join-Path $tempRoot $Relative
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path,$Text,(New-Object Text.UTF8Encoding($false)))
}
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $main = "# Existing TaskCLI source`nfrom argparse import ArgumentParser`ndef main():`n    print('EMPTY_LIST_BASELINE_EXACT')`n"
    $test = "# Existing TaskCLI test`ndef test_empty_list():`n    assert 'PYTHON_BASELINE_TEST_EXACT'`n"
    Write-Fixture 'src/taskcli/__main__.py' $main
    Write-Fixture 'tests/test_cli.py' $test
    Write-Fixture 'guide.md' 'Reference guide describes an example.'
    Write-Fixture 'example.py' '# Reference example must not become a write target.'
    Write-Fixture '.env' 'SECRET_PYTHON_CONTEXT_MUST_NOT_LEAK'
    Write-Fixture 'vendor/ignored.py' 'VENDOR_PYTHON_MUST_NOT_LEAK'
    & git -C $tempRoot init | Out-Null
    & git -C $tempRoot config user.email 'aico-test@example.invalid'
    & git -C $tempRoot config user.name 'AI Company OS Test'
    & git -C $tempRoot add .
    & git -C $tempRoot commit -m 'Python baseline fixture' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not prepare isolated Python baseline fixture.' }
    $task = 'Create src/taskcli/storage.py implementing JSON persistence via TASKCLI_DATA_FILE. Update src/taskcli/__main__.py to support add, complete and remove commands.'
    $dispatch = 'Create storage.py for JSON persistence and update __main__.py for command integration.'
    $resolver = Join-Path $repoRoot 'scripts/resolve-writable-required-files.ps1'
    $builder = Join-Path $repoRoot 'scripts/build-agent-context.ps1'
    $required = @(& $resolver -ProjectPath $tempRoot -SourceText @($task,$dispatch) -PolicyPath (Join-Path $repoRoot '.codex/writable-policy.json'))
    Assert-True ($required -contains 'src/taskcli/__main__.py') 'Compound Create/Update request must resolve later existing Python target.'
    Assert-True ($required -notcontains 'src/taskcli/storage.py') 'New storage target has no current source to include.'
    Assert-True (-not (Test-Path (Join-Path $tempRoot 'src/taskcli/storage.py'))) 'Resolution must not create a new implementation target.'
    $referenceTargets = @(& $resolver -ProjectPath $tempRoot -SourceText @('Update src/taskcli/__main__.py using guide.md that describes how to modify example.py.') -PolicyPath (Join-Path $repoRoot '.codex/writable-policy.json'))
    Assert-True ($referenceTargets -contains 'src/taskcli/__main__.py') 'Positive update target must remain required.'
    Assert-True ($referenceTargets -notcontains 'guide.md' -and $referenceTargets -notcontains 'example.py') 'Narrative reference actions must not become mandatory write targets.'
    $general = & $builder -ProjectPath $tempRoot -Id 'AICO-007' -Owner 'backend' -MaxChars 30000
    Assert-True ($general.Contains($main)) 'General context must include existing Python product source verbatim.'
    Assert-True ($general.Contains($test)) 'General context must include existing Python baseline tests verbatim.'
    Assert-True (-not $general.Contains('SECRET_PYTHON_CONTEXT_MUST_NOT_LEAK')) 'Python support must preserve secret exclusion.'
    Assert-True (-not $general.Contains('VENDOR_PYTHON_MUST_NOT_LEAK')) 'Python support must preserve vendor exclusion.'
    $context = & $builder -ProjectPath $tempRoot -Id 'AICO-007' -Owner 'backend' -MaxChars 30000 -RequiredFiles $required
    Assert-True ($context.Contains($main)) 'Writable constructor must include exact current compound-request target.'
    foreach ($name in @('provider-router.ps1','validate-json-contract.ps1','write-operational-event.ps1')) {
        Write-Fixture ('scripts/'+$name) (Get-Content (Join-Path $repoRoot ('scripts/'+$name)) -Raw)
    }
    Write-Fixture 'schemas/agent-result.schema.json' (Get-Content (Join-Path $repoRoot 'schemas/agent-result.schema.json') -Raw)
    Write-Fixture '.codex/provider-config.json' '{"writable_context_max_chars":30000,"models":{"OpenRouter":"fake"}}'
    Write-Fixture 'scripts/providers/invoke-openrouter.ps1' @'
param([string]$Prompt,[string]$Context,[string]$SchemaPath,[string]$OutputPath,[string]$Model,[int]$TimeoutSeconds)
[IO.File]::WriteAllText(($OutputPath+'.context'),$Context)
$result = @{outcome='COMPLETED';summary='Fake capture';report_markdown='Fake capture only';verification='Fake';decisions='NONE';blockers='NONE';recommended_next='REVIEW';completion_check=@{substantive_role_deliverable_produced=$true;missing_required_outputs=@();evidence='Fake'}}
[IO.File]::WriteAllText($OutputPath,($result | ConvertTo-Json -Depth 10))
[pscustomobject]@{Provider='OpenRouter';Model=$Model}
'@
    $env:OPENROUTER_API_KEY = 'obviously-fake-no-network'
    $output = Join-Path $tempRoot 'captured-result.json'
    & (Join-Path $tempRoot 'scripts/provider-router.ps1') -Provider 'OpenRouter' -ProjectPath $tempRoot -Prompt $task -Context $context -SchemaPath (Join-Path $tempRoot 'schemas/agent-result.schema.json') -OutputPath $output -Role 'backend' -Workload 'writable' | Out-Null
    $captured = Get-Content ($output+'.context') -Raw
    Assert-True ($captured.Contains($main) -and $captured.Contains($test)) 'Fake writable provider must receive exact current Python source and baseline tests.'
    Assert-True ($captured.Length -le 30000) 'Adequate configured context budget must remain respected.'
    Write-Host 'PASS: compound Python Create/Update resolves existing target; generic and writable provider context preserve exact baseline source/tests' -ForegroundColor Green
}
finally {
    $env:OPENROUTER_API_KEY = $savedKey
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    if (-not $resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'aico-python-writable-source-*') { throw 'Unsafe test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
