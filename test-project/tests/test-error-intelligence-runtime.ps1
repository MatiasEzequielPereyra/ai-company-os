$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'scripts'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('aico-error-runtime-' + [guid]::NewGuid().ToString('N'))
$variables = @('AICO_ERROR_INTELLIGENCE_ENABLED','AICO_ERROR_INTELLIGENCE_PYTHON','AICO_ERROR_INTELLIGENCE_MODULE_ROOT','AICO_ERROR_INTELLIGENCE_PATH','AICO_TEST_CAPTURE','PYTHONPATH')
$saved = @{}
foreach ($name in $variables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$assertions = 0
function Assert-True($condition, $message) { if (-not $condition) { throw $message }; $script:assertions++ }
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture 'company_os/error_intelligence') -Force | Out-Null
    $utf8 = New-Object Text.UTF8Encoding($false)
    foreach ($relative in @('company_os/__init__.py','company_os/error_intelligence/__init__.py')) { [IO.File]::WriteAllText((Join-Path $fixture $relative),'',$utf8) }
    $stub = @'
import json, os, sys
event = json.load(sys.stdin)
with open(os.environ['AICO_TEST_CAPTURE'], 'a', encoding='utf-8') as stream:
    stream.write(json.dumps({'event':event,'args':sys.argv}, ensure_ascii=False)+'\n')
if event.get('mode') == 'failure':
    sys.stderr.write('sensitive detail must not escape')
    sys.exit(1)
if event.get('mode') == 'unavailable':
    print(json.dumps({'status':'unavailable'}))
    sys.exit(0)
print(json.dumps({'incident_id':'inc_test','occurrence_count':2,'verified_solution_available':True}))
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'company_os/error_intelligence/runtime.py'),$stub,$utf8)
    $env:AICO_ERROR_INTELLIGENCE_MODULE_ROOT = $fixture
    if (-not $env:AICO_ERROR_INTELLIGENCE_PYTHON) { $env:AICO_ERROR_INTELLIGENCE_PYTHON = (Get-Command python -CommandType Application).Source }
    $env:AICO_TEST_CAPTURE = Join-Path $fixture 'captured.jsonl'
    $env:AICO_ERROR_INTELLIGENCE_ENABLED = '0'
    & (Join-Path $scripts 'error-intelligence.ps1') -ProjectPath $fixture -Event @{event_type='runtime_failure'}
    Assert-True (-not (Test-Path $env:AICO_TEST_CAPTURE)) 'Disabled observer invoked Python'
    $env:AICO_ERROR_INTELLIGENCE_ENABLED = '1'
    & (Join-Path $scripts 'error-intelligence.ps1') -ProjectPath $fixture -Event @{event_type='provider_attempt_finished';success=$true}
    Assert-True (-not (Test-Path $env:AICO_TEST_CAPTURE)) 'Successful provider event invoked Python'
    $prior = $env:PYTHONPATH
    $unicodeMarker = 'espa' + [char]0x00f1 + 'ol ' + [char]0x65e5 + [char]0x672c + [char]0x8a9e
    $output = @(& (Join-Path $scripts 'error-intelligence.ps1') -ProjectPath $fixture -Event @{event_type='runtime_failure';component='agent-runner';task_id='AICO-001';marker=$unicodeMarker})
    Assert-True ($output.Count -eq 0) 'Observer polluted success output'
    Assert-True ($env:PYTHONPATH -eq $prior) 'Observer failed to restore PYTHONPATH'
    $captured = Get-Content -LiteralPath $env:AICO_TEST_CAPTURE -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($captured.event.marker -eq $unicodeMarker) 'UTF-8 stdin damaged event'
    Assert-True ($captured.args[-1] -eq $fixture) 'Project argument damaged'
    & (Join-Path $scripts 'error-intelligence.ps1') -ProjectPath $fixture -Event @{event_type='task_transition';from_status='REVIEW';to_status='READY'}
    Assert-True (@(Get-Content $env:AICO_TEST_CAPTURE).Count -eq 2) 'Rejected gate transition was not captured'
    $path = & (Join-Path $scripts 'write-operational-event.ps1') -ProjectPath $fixture -Event @{event_type='runtime_failure';mode='failure'}
    Assert-True (Test-Path -LiteralPath $path) 'Capture failure broke metrics write'
    Assert-True ((Get-Content -LiteralPath $path -Raw) -match 'runtime_failure') 'Capture failure lost metrics event'
    $messages = @(& (Join-Path $scripts 'error-intelligence.ps1') -ProjectPath $fixture -Event @{event_type='runtime_failure';mode='unavailable'} 6>&1)
    Assert-True (($messages | Out-String) -match 'ERROR_INTELLIGENCE_CAPTURE_UNAVAILABLE') 'Unavailable storage was silent'
    Assert-True (($messages | Out-String) -notmatch 'sensitive detail') 'Observer exposed raw exception details'
    $env:AICO_ERROR_INTELLIGENCE_MODULE_ROOT = Join-Path (Split-Path $scripts -Parent) 'src'
    $env:AICO_ERROR_INTELLIGENCE_PATH = $fixture
    $messages = @(& (Join-Path $scripts 'error-intelligence.ps1') -ProjectPath $fixture -Event @{event_type='runtime_failure';component='agent-runner';error_category='runtime'} 6>&1)
    Assert-True (($messages | Out-String) -match 'ERROR_INTELLIGENCE_CAPTURE_UNAVAILABLE') 'Actual invalid storage path was silent'
    $env:AICO_ERROR_INTELLIGENCE_PATH = Join-Path $fixture 'actual.sqlite3'
    $env:AICO_ERROR_INTELLIGENCE_MODULE_ROOT = ''
    $actualEvent = @{event_type='provider_attempt_finished';provider='OpenRouter';success=$false;error_category='timeout';task_id='AICO-002'}
    $messages = @(& (Join-Path $scripts 'write-operational-event.ps1') -ProjectPath $fixture -Event $actualEvent 6>&1)
    Assert-True (Test-Path $env:AICO_ERROR_INTELLIGENCE_PATH) 'Actual observer did not create explicit SQLite store'
    Assert-True (($messages | Out-String) -match 'occurrences=1') 'Actual observer did not capture first incident'
    $messages = @(& (Join-Path $scripts 'write-operational-event.ps1') -ProjectPath $fixture -Event $actualEvent 6>&1)
    Assert-True (($messages | Out-String) -match 'occurrences=2') 'Actual repeated observation did not increment occurrence count'
    $messages = @(& (Join-Path $scripts 'write-operational-event.ps1') -ProjectPath $fixture -Event @{event_type='provider_failed';provider='OpenRouter';error_category='timeout'} 6>&1)
    Assert-True (($messages | Out-String) -notmatch 'incident=') 'Failure alias double captured incident'
    $env:AICO_ERROR_INTELLIGENCE_ENABLED = '0'
    $messages = @(& (Join-Path $scripts 'write-operational-event.ps1') -ProjectPath $fixture -Event $actualEvent 6>&1)
    Assert-True (($messages | Out-String) -notmatch 'incident=') 'Actual observer ignored opt out'
    $env:AICO_ERROR_INTELLIGENCE_ENABLED = '1'
    $messages = @(& (Join-Path $scripts 'write-operational-event.ps1') -ProjectPath $fixture -Event $actualEvent 6>&1)
    Assert-True (($messages | Out-String) -match 'occurrences=3') 'Alias or opted-out event modified store'
    Assert-True ($env:PYTHONPATH -eq $prior) 'Actual module discovery changed caller PYTHONPATH'
    . (Join-Path $scripts 'task-execution-lock.ps1')
    $lock = Enter-TaskExecutionLock -ProjectPath $fixture -Id 'AICO-002' -Operation 'GATE'
    try {
        $metricsPath = Join-Path $fixture '.codex/runtime/metrics/events.jsonl'
        $metricsHash = (Get-FileHash -LiteralPath $metricsPath -Algorithm SHA256).Hash
        $realPython = $env:AICO_ERROR_INTELLIGENCE_PYTHON
        foreach ($runner in @('run-agent-task.ps1','run-writable-agent.ps1')) {
            foreach ($python in @($realPython,(Join-Path $fixture 'missing-python.exe'))) {
                $env:AICO_ERROR_INTELLIGENCE_PYTHON = $python
                $failure = ''
                try { & (Join-Path $scripts $runner) -ProjectPath $fixture -Id 'AICO-002' | Out-Null }
                catch { $failure = $_.Exception.Message }
                Assert-True ($failure -match 'already has an AI Company OS execution in progress') 'Observer masked original contested lease rejection'
                Assert-True ((Get-FileHash -LiteralPath $metricsPath -Algorithm SHA256).Hash -eq $metricsHash) 'Lease rejection mutated project metrics'
            }
        }
        $env:AICO_ERROR_INTELLIGENCE_PYTHON = $realPython
    }
    finally { Exit-TaskExecutionLock -Lock $lock }
    $env:AICO_ERROR_INTELLIGENCE_MODULE_ROOT = $fixture
    $env:AICO_ERROR_INTELLIGENCE_PYTHON = Join-Path $fixture 'missing-python.exe'
    $output = @(& (Join-Path $scripts 'error-intelligence.ps1') -ProjectPath $fixture -Event @{event_type='runtime_failure'})
    Assert-True ($output.Count -eq 0) 'Unavailable interpreter polluted success output'
    Assert-True ($env:PYTHONPATH -eq $prior) 'Failed observer did not restore PYTHONPATH'
    Write-Host "Error Intelligence runtime: $assertions assertions PASS"
}
finally {
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
}
