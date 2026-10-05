param()
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('aico-codex-schema-'+[Guid]::NewGuid().ToString('N'))
$savedPath=$env:PATH
$savedTemp=$env:TEMP
function Write-Fixture([string]$Path,[string]$Text){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)|Out-Null;[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Cleanup {
    Assert (@(Get-ChildItem (Join-Path $tempRoot 'runtime') -File -Recurse -ErrorAction SilentlyContinue).Count -eq 0) 'Codex temporary schema/prompt/runner leaked.'
}
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot 'runtime')|Out-Null
    $env:TEMP=Join-Path $tempRoot 'runtime'
    $bin=Join-Path $tempRoot 'fake bin'
    Write-Fixture (Join-Path $bin 'codex.ps1') @'
$ErrorActionPreference='Stop'
function Check-Strict($Node){
 if($Node.type -eq 'object'){
  if($Node.additionalProperties -ne $false){throw 'Object is not closed'}
  $names=@($Node.properties.PSObject.Properties.Name|Sort-Object)
  $required=@($Node.required|Sort-Object)
  if(($names -join ',') -ne ($required -join ',')){throw 'Strict object required does not equal properties'}
 }
 foreach($property in $Node.PSObject.Properties){
  if($property.Name -eq 'properties'){foreach($child in $property.Value.PSObject.Properties){Check-Strict $child.Value}}
  elseif($property.Name -in @('items','additionalProperties') -and $property.Value -is [PSCustomObject]){Check-Strict $property.Value}
  elseif($property.Name -in @('anyOf','oneOf','allOf')){foreach($child in $property.Value){Check-Strict $child}}
 }
}
$schemaPath=$args[[array]::IndexOf($args,'--output-schema')+1]
$outputPath=$args[[array]::IndexOf($args,'-o')+1]
$schema=Get-Content $schemaPath -Raw|ConvertFrom-Json
if($schema.type -ne 'object'){throw 'Strict root must be object'}
Check-Strict $schema
$nullable=@($schema.properties.execution_blocker.anyOf|Where-Object type -eq 'null')
if($nullable.Count -ne 1){throw 'Optional execution blocker must be nullable'}
Add-Content (Join-Path (Get-Location).Path 'fake-schema-calls.log') 'STRICT_SCHEMA_PASS'
$mode=(Get-Content (Join-Path (Get-Location).Path 'mode.txt') -Raw).Trim()
if($mode -eq 'timeout'){Start-Sleep -Seconds 15;exit 0}
if($mode -eq 'error'){exit 7}
Copy-Item (Join-Path (Get-Location).Path 'payload.json') $outputPath
exit 0
'@
    $env:PATH=$bin+[IO.Path]::PathSeparator+$savedPath
    $hashes=@{}
    foreach($schemaName in @('agent-result','engineering-plan-result')) {
        $canonical=Join-Path $repoRoot "schemas/$schemaName.schema.json"
        $hashes[$canonical]=(Get-FileHash $canonical).Hash
        $modes=@('completed-null','blocked-valid','completed-blocker','blocked-null','blocked-missing','blocked-owned','required-null')
        if($schemaName -eq 'engineering-plan-result'){$modes+=@('completed-empty','blocked-nonempty')}
        foreach($mode in $modes) {
            $payload=@{outcome='COMPLETED';summary='Architecture';report_markdown='Complete architecture contracts migration and ADR';verification='Fake check';decisions='Proposal';blockers='NONE';recommended_next='REVIEW';completion_check=@{substantive_role_deliverable_produced=$true;missing_required_outputs=@();evidence='Role deliverable complete'};execution_blocker=$null}
            if($schemaName -eq 'engineering-plan-result'){$payload.executable_work=@(@{key='implement-api';kind='IMPLEMENTATION';change='Implement API request validation in src/api.py';owner='backend';areas=@('src/api.py');depends_on=@();verify='Run API request validation tests'})}
            $blocker=@{kind='external_decision';prerequisite='PM retention decision';evidence='DEC-012 unresolved';resolution_owner='pm';why_role_cannot_resolve='PM must authorize retention policy';role_can_resolve=$false}
            if($mode -like 'blocked-*'){$payload.outcome='BLOCKED';$payload.blockers='PM retention decision';$payload.completion_check.substantive_role_deliverable_produced=$false;$payload.completion_check.missing_required_outputs=@('Retention contract');if($schemaName -eq 'engineering-plan-result'){$payload.executable_work=@()}}
            if($mode -in @('blocked-valid','completed-blocker','blocked-owned','blocked-nonempty')){$payload.execution_blocker=$blocker}
            if($mode -eq 'completed-empty'){$payload.executable_work=@()}
            if($mode -eq 'blocked-nonempty'){$payload.executable_work=@(@{key='implement-api';kind='IMPLEMENTATION';change='Implement API validation';owner='backend';areas=@('src/api.py');depends_on=@();verify='Run validation tests'})}
            if($mode -eq 'blocked-owned'){$payload.execution_blocker.role_can_resolve=$true}
            if($mode -eq 'blocked-missing'){$payload.Remove('execution_blocker')}
            if($mode -eq 'required-null'){$payload.summary=$null}
            Write-Fixture (Join-Path $tempRoot 'payload.json') ($payload|ConvertTo-Json -Depth 20)
            Write-Fixture (Join-Path $tempRoot 'mode.txt') $mode
            $output=Join-Path $tempRoot 'output.json'
            $rejected=$false
            $stage='adapter'
            try {
                & (Join-Path $repoRoot 'scripts/providers/invoke-codex.ps1') -ProjectPath $tempRoot -Prompt 'Fake strict schema portability check' -SchemaPath $canonical -OutputPath $output -TimeoutSeconds 30 |Out-Null
                $stage='canonical'
                & (Join-Path $repoRoot 'scripts/validate-json-contract.ps1') -JsonPath $output -SchemaPath $canonical |Out-Null
                $stage='semantic'
                & (Join-Path $repoRoot 'scripts/validate-analysis-result-semantics.ps1') -JsonPath $output |Out-Null
            } catch {
                $rejected=$true
                if($mode -in @('completed-null','blocked-valid')){Write-Host $_.Exception.Message}
                $expected=@{
                    'completed-blocker'='COMPLETED must not declare an execution_blocker'
                    'blocked-null'='BLOCKED requires structured execution_blocker evidence'
                    'blocked-missing'='BLOCKED requires structured execution_blocker evidence'
                    'blocked-owned'='assigned role can resolve this prerequisite'
                    'required-null'='\$\.summary must be a string'
                    'completed-empty'='no executable_work items'
                    'blocked-nonempty'='must not contain executable work'
                }
                if($expected.ContainsKey($mode)){
                    $expectedStage=if($mode -eq 'required-null'){'adapter'}else{'semantic'}
                    Assert ($stage -eq $expectedStage) "$schemaName $mode failed at $stage instead of $expectedStage."
                    Assert ($_.Exception.Message -match $expected[$mode]) "$schemaName $mode failed for an unexpected reason: $($_.Exception.Message)"
                }
            }
            $valid=$mode -in @('completed-null','blocked-valid')
            Assert ($rejected -ne $valid) "$schemaName $mode validity differed from canonical contracts."
            if($valid){$result=Get-Content $output -Raw|ConvertFrom-Json;if($mode -eq 'completed-null'){Assert ($null -eq $result.PSObject.Properties['execution_blocker']) 'Introduced optional null was not omitted.'}else{Assert ($result.execution_blocker.prerequisite -eq 'PM retention decision') 'Real blocker was erased.'}}
            Assert-Cleanup
        }
    }
    foreach($mode in @('error','timeout')) {
        Write-Fixture (Join-Path $tempRoot 'mode.txt') $mode
        $rejected=$false
        try {& (Join-Path $repoRoot 'scripts/providers/invoke-codex.ps1') -ProjectPath $tempRoot -Prompt 'Failure cleanup check' -SchemaPath (Join-Path $repoRoot 'schemas/agent-result.schema.json') -OutputPath (Join-Path $tempRoot 'output.json') -TimeoutSeconds $(if($mode -eq 'timeout'){1}else{30})|Out-Null}catch{
            $rejected=$true
            $expectedFailure=if($mode -eq 'timeout'){'Codex execution timed out after 1 seconds'}else{'Codex exec failed with exit code 7'}
            Assert ($_.Exception.Message -match [regex]::Escape($expectedFailure)) "$mode failed unexpectedly: $($_.Exception.Message)"
        }
        Assert $rejected "$mode did not fail."
        Assert (-not (Test-Path (Join-Path $tempRoot 'output.json'))) "$mode left failed output behind."
        Assert-Cleanup
    }
    # Optional members nested inside required objects use the same reversible mapping.
    $nestedSchema=Get-Content (Join-Path $repoRoot 'schemas/agent-result.schema.json') -Raw|ConvertFrom-Json
    $nestedSchema.properties.completion_check.properties|Add-Member -NotePropertyName optional_note -NotePropertyValue ([PSCustomObject]@{type='string'})
    $nestedSchemaPath=Join-Path $tempRoot 'nested-optional.schema.json'
    Write-Fixture $nestedSchemaPath ($nestedSchema|ConvertTo-Json -Depth 30)
    $nestedPayload=@{outcome='COMPLETED';summary='Architecture';report_markdown='Complete architecture';verification='Fake';decisions='Proposal';blockers='NONE';recommended_next='REVIEW';execution_blocker=$null;completion_check=@{substantive_role_deliverable_produced=$true;missing_required_outputs=@();evidence='Complete';optional_note=$null}}
    Write-Fixture (Join-Path $tempRoot 'payload.json') ($nestedPayload|ConvertTo-Json -Depth 15)
    Write-Fixture (Join-Path $tempRoot 'mode.txt') 'nested-null'
    & (Join-Path $repoRoot 'scripts/providers/invoke-codex.ps1') -ProjectPath $tempRoot -Prompt 'Nested nullable optional' -SchemaPath $nestedSchemaPath -OutputPath (Join-Path $tempRoot 'output.json') -TimeoutSeconds 30|Out-Null
    $nestedResult=Get-Content (Join-Path $tempRoot 'output.json') -Raw|ConvertFrom-Json
    Assert ($null -eq $nestedResult.completion_check.PSObject.Properties['optional_note']) 'Nested introduced optional null was not omitted.'
    Assert ($nestedResult.completion_check.evidence -eq 'Complete') 'Required nested evidence was changed.'
    Assert-Cleanup
    Write-Fixture (Join-Path $tempRoot 'bad-schema.json') '{ invalid json'
    $callsBeforePreparationFailure=@(Get-Content (Join-Path $tempRoot 'fake-schema-calls.log')).Count
    $rejected=$false
    try {& (Join-Path $repoRoot 'scripts/providers/invoke-codex.ps1') -ProjectPath $tempRoot -Prompt 'Preparation failure' -SchemaPath (Join-Path $tempRoot 'bad-schema.json') -OutputPath (Join-Path $tempRoot 'output.json')|Out-Null}catch{$rejected=$true}
    Assert $rejected 'Invalid schema preparation was accepted.'
    Assert (@(Get-Content (Join-Path $tempRoot 'fake-schema-calls.log')).Count -eq $callsBeforePreparationFailure) 'Malformed schema reached the CLI.'
    Assert-Cleanup
    foreach($path in $hashes.Keys){Assert ((Get-FileHash $path).Hash -eq $hashes[$path]) 'Canonical schema changed.'}
    Assert (@(Get-Content (Join-Path $tempRoot 'fake-schema-calls.log')).Count -ge 19) 'Fake strict CLI did not inspect every output schema.'
    Write-Host 'PASS: Codex strict schemas, nullable optionals, generic/EM semantics and cleanup (20 cases).' -ForegroundColor Green
}
finally {
    $env:PATH=$savedPath;$env:TEMP=$savedTemp
    $resolved=[IO.Path]::GetFullPath($tempRoot)
    Assert ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) 'Unsafe test cleanup path.'
    if(Test-Path $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
