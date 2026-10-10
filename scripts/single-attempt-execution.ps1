# Process-local capability registry. Persisted records are evidence, never authorization.
if (-not (Get-Module AicoSingleAttemptV1)) {
    $module = New-Module -Name AicoSingleAttemptV1 -ScriptBlock {
        $script:records = @{}
        function Test-SecretIdentifier($value) {
            foreach ($secret in @($env:CODEX_API_KEY,$env:OPENROUTER_API_KEY,$env:GEMINI_API_KEY,$env:DEEPSEEK_API_KEY,$env:XAI_API_KEY)) {
                if (-not [string]::IsNullOrWhiteSpace($secret) -and ([string]$value).Contains($secret)) { return $true }
            }
            return $false
        }
        function Save-Record($record) {
            $public = $record.Public
            [IO.File]::WriteAllText($record.Path,($public | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
        }
        function Get-Registered($Context) {
            if ($null -eq $Context -or -not $script:records.ContainsKey([string]$Context.Id) -or -not [object]::ReferenceEquals($script:records[[string]$Context.Id].Handle,$Context)) { throw 'SINGLE_ATTEMPT_CONTEXT_INVALID' }
            return $script:records[[string]$Context.Id]
        }
        function New-SingleAttemptExecution {
            param([string]$ProjectPath,[string]$Provider,[string]$Model)
            $root = (Resolve-Path -LiteralPath $ProjectPath).Path
            $directory = Join-Path $root '.codex/runtime/single-attempt-executions'
            $current = [IO.Path]::GetFullPath($directory)
            while ($current -ne $root) {
                if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'SINGLE_ATTEMPT_EVIDENCE_PATH_UNSAFE' }
                $parent = Split-Path $current -Parent
                if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) { throw 'SINGLE_ATTEMPT_EVIDENCE_PATH_UNSAFE' }
                $current = $parent
            }
            [IO.Directory]::CreateDirectory($directory) | Out-Null
            $id = [Guid]::NewGuid().ToString('N')
            $handle = [pscustomobject]@{ Id=$id }
            # Identity fields accept identifiers only; never arbitrary provider prose/URLs.
            $safeProvider = if (-not (Test-SecretIdentifier $Provider) -and $Provider -match '^[A-Za-z][A-Za-z0-9_-]{0,63}$') { $Provider } else { 'UNAVAILABLE' }
            $safeModel = if (-not (Test-SecretIdentifier $Model) -and $Model -match '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$') { $Model } else { 'UNAVAILABLE' }
            $public = [ordered]@{ contract_version='single-attempt-provider-execution-v1'; execution_id=$id; execution_mode='SingleAttempt'; provider=$safeProvider; model=$safeModel; attempts_started=0; result='PREFLIGHT'; validation_status='NOT_RUN'; error_category=$null; duration_ms=0; output_limit=$null; prompt_tokens=$null; completion_tokens=$null; total_tokens=$null; reasoning_tokens=$null; finish_reason=$null; metadata_source='provider_reported_when_available'; started_utc=[DateTime]::UtcNow.ToString('o') }
            $record = @{ Handle=$handle; Path=(Join-Path $directory ($id+'.json')); Public=$public; Clock=[Diagnostics.Stopwatch]::StartNew(); Provider=$Provider; Model=$Model; Completed=$false; Configured=$false; Endpoint=$null }
            $script:records[$id]=$record
            Save-Record $record
            return $handle
        }
        function Assert-SingleAttemptConfiguration {
            param([object]$Context,[string]$Provider,[string]$Model,[string]$ProviderEndpoint='')
            $record=Get-Registered $Context
            if ($record.Completed -or $record.Public.attempts_started -ne 0) { throw 'SINGLE_ATTEMPT_LIMIT_EXCEEDED' }
            if ((Test-SecretIdentifier $Provider) -or (Test-SecretIdentifier $Model) -or (Test-SecretIdentifier $ProviderEndpoint)) { throw 'SINGLE_ATTEMPT_IDENTITY_INVALID' }
            if ($record.Provider -cne $Provider -or $record.Model -cne $Model) { throw 'SINGLE_ATTEMPT_IDENTITY_MISMATCH' }
            if ($Provider -eq 'Auto' -or [string]::IsNullOrWhiteSpace($Model)) { throw 'SINGLE_ATTEMPT_EXPLICIT_IDENTITY_REQUIRED' }
            if ($Provider -notin @('OpenRouter','Gemini','Ollama','DeepSeek','Grok')) { throw 'SINGLE_ATTEMPT_ADAPTER_UNSUPPORTED' }
            if ($Model -notmatch '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$') { throw 'SINGLE_ATTEMPT_MODEL_INVALID' }
            if ($Provider -eq 'OpenRouter') {
                if ($Model -match '^(?i:openrouter/(free|auto)|.*:(online|nitro|floor))$') { throw 'SINGLE_ATTEMPT_DYNAMIC_MODEL_REJECTED' }
                if ($ProviderEndpoint -notmatch '^[A-Za-z0-9][A-Za-z0-9_./-]{0,127}$') { throw 'SINGLE_ATTEMPT_ENDPOINT_REQUIRED' }
                if ($record.Configured -and $record.Endpoint -cne $ProviderEndpoint) { throw 'SINGLE_ATTEMPT_ENDPOINT_MISMATCH' }
                $record.Endpoint=$ProviderEndpoint
                $record.Public['endpoint']=$ProviderEndpoint
            }
            $record.Configured=$true
            Save-Record $record
        }
        function Start-SingleAttemptProviderCall {
            param([object]$Context,[string]$Provider,[string]$Model)
            $record = Get-Registered $Context
            if (-not $record.Configured) { throw 'SINGLE_ATTEMPT_CONFIGURATION_NOT_VERIFIED' }
            if ($record.Completed -or $record.Public.attempts_started -ne 0) { throw 'SINGLE_ATTEMPT_LIMIT_EXCEEDED' }
            if ($Provider -cne $record.Provider -or $Model -cne $record.Model) { throw 'SINGLE_ATTEMPT_IDENTITY_MISMATCH' }
            $record.Public.attempts_started=1
            $record.Public.result='IN_FLIGHT'
            Save-Record $record
        }
        function Set-SingleAttemptProviderMetadata {
            param([object]$Context,[object]$Result)
            $record = Get-Registered $Context
            if ($record.Completed) { throw 'SINGLE_ATTEMPT_ALREADY_COMPLETED' }
            foreach ($pair in @(@('OutputLimit','output_limit'),@('PromptTokens','prompt_tokens'),@('CompletionTokens','completion_tokens'),@('TotalTokens','total_tokens'),@('ReasoningTokens','reasoning_tokens'))) {
                $value = $Result.($pair[0]); $parsed=0L
                if ($null -ne $value -and [long]::TryParse([string]$value,[ref]$parsed) -and $parsed -ge 0) { $record.Public[$pair[1]]=$parsed }
            }
            if (-not (Test-SecretIdentifier $Result.FinishReason) -and $null -ne $Result.FinishReason -and [string]$Result.FinishReason -match '^[A-Za-z0-9_-]{1,64}$') { $record.Public.finish_reason=[string]$Result.FinishReason }
            if (-not (Test-SecretIdentifier $Result.Model) -and $null -ne $Result.Model -and [string]$Result.Model -match '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$') { $record.Public['reported_model']=[string]$Result.Model }
            Save-Record $record
        }
        function Get-SingleAttemptStartedCount {
            param([object]$Context)
            $record=Get-Registered $Context
            return [int]$record.Public.attempts_started
        }
        function Complete-SingleAttemptExecution {
            param([object]$Context,[ValidateSet('VALID','INVALID','NOT_RUN')][string]$ValidationStatus,[string]$ErrorCategory='')
            $record = Get-Registered $Context
            if ($record.Completed -and $ValidationStatus -ne 'INVALID') { return }
            if ($ValidationStatus -eq 'VALID' -and $record.Public.attempts_started -ne 1) { throw 'SINGLE_ATTEMPT_CALL_UNVERIFIED' }
            $record.Completed=$true
            $record.Public.validation_status=$ValidationStatus
            $record.Public.result=if ($ValidationStatus -eq 'VALID') { 'VALIDATED' } else { 'FAILED' }
            $record.Public.error_category=if ($ErrorCategory -match '^[a-z_]{1,64}$') { $ErrorCategory } else { $record.Public.error_category }
            if ($ValidationStatus -eq 'INVALID' -and $null -eq $record.Public.error_category) {
                $record.Public.error_category=if ($record.Public.attempts_started -eq 0) { 'preflight' } else { 'local_validation' }
            }
            $record.Public.duration_ms=[long]$record.Clock.ElapsedMilliseconds
            Save-Record $record
        }
        Export-ModuleMember -Function Get-SingleAttemptStartedCount,Assert-SingleAttemptConfiguration,New-SingleAttemptExecution,Start-SingleAttemptProviderCall,Set-SingleAttemptProviderMetadata,Complete-SingleAttemptExecution
    }
    Import-Module $module -Global
}
