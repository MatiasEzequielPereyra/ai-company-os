# Invocation state is module-private. Repeated dot-sourcing preserves registered
# context and validation identities; callers receive handles or detached copies.
if (-not (Get-Module -Name AicoReviewGroundingV1)) {
    New-Module -Name AicoReviewGroundingV1 -ScriptBlock {
        param([string]$LockHelperPath)
        . $LockHelperPath
        $contexts = @{}
        $validations = @{}
        $pathComparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }

        function Get-ReviewHash([byte[]]$Bytes) {
            $sha = [Security.Cryptography.SHA256]::Create()
            try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
        }
        function Get-ReviewTextHash([string]$Text) { return Get-ReviewHash ([Text.Encoding]::UTF8.GetBytes($Text)) }
        function Get-ReviewNormalizedText {
            param([Parameter(Mandatory=$true)][AllowEmptyCollection()][byte[]]$Bytes)
            try { $text = (New-Object Text.UTF8Encoding($false,$true)).GetString($Bytes) } catch { throw 'REVIEW_GROUNDING_INVALID_UTF8: source must be strict UTF-8.' }
            if ($text.Length -and $text[0] -eq [char]0xfeff) { $text = $text.Substring(1) }
            return $text.Replace("`r`n","`n").Replace("`r","`n")
        }
        function Get-ReviewDeclarations {
            param([string]$Text,[ValidateSet('Output','Acceptance Criteria')][string]$Section,
                  [ValidateSet('role-output','task-acceptance')][string]$SourceKind,[string]$RelativePath,[switch]$AllowAbsent)
            $lines = $Text.Split([char]10)
            $selected = New-Object 'Collections.Generic.List[string]'
            $found = 0; $inside = $false; $fence = ''; $fenceLength = 0
            foreach ($line in $lines) {
                if ($fence) {
                    if ($line -match ('^ {0,3}'+[regex]::Escape($fence)+'{'+$fenceLength+',}[ \t]*$')) { $fence=''; $fenceLength=0 }
                    continue
                }
                if ($line -match '^ {0,3}(`{3,}|~{3,})(.*)$') { $fence=$Matches[1].Substring(0,1); $fenceLength=$Matches[1].Length; continue }
                if ($line -cmatch ('^## '+[regex]::Escape($Section)+'[ \t]*$')) {
                    $found++; $inside=$true; continue
                }
                if ($line -match '^#{1,2}[ \t]+') { $inside=$false }
                if ($inside) { $selected.Add($line) }
            }
            if ($fence) { throw 'OBLIGATION_SOURCE_MALFORMED: unclosed fenced code in declaration source.' }
            if ($found -gt 1) { throw "OBLIGATION_SOURCE_MALFORMED: duplicate $Section sections." }
            if (-not $found) { if ($AllowAbsent) { return }; throw "OBLIGATION_SOURCE_MALFORMED: missing $Section section." }
            $bodies = New-Object 'Collections.Generic.List[string]'
            foreach ($line in $selected) {
                if ($line -match '^[ \t]*$' -or $line -eq '---') { continue }
                if ($SourceKind -eq 'role-output' -and $line -cin @('Produce:','The normal output is:','Typical outputs include:')) { continue }
                if ($line -match '^[-*+] (.*)$') {
                    $body=$Matches[1]
                    if ($body -match '^\[( |x|X)\] (.*)$') { $body=$Matches[2] }
                    if ([string]::IsNullOrWhiteSpace($body) -or $body -match '^(?i:-|NONE|UNKNOWN|TBD|UNCONFIRMED)$') { throw 'OBLIGATION_SOURCE_MALFORMED: empty or placeholder declaration.' }
                    $bodies.Add($body); continue
                }
                if ($line -match '^ {2,}\S') {
                    if (-not $bodies.Count -or $line -match '^ {2,}(?:[-*+] |\d+[.)] )') { throw 'OBLIGATION_SOURCE_MALFORMED: orphan continuation or nested list.' }
                    $bodies[$bodies.Count-1] += "`n"+$line; continue
                }
                throw 'OBLIGATION_SOURCE_MALFORMED: unsupported declaration prose, ordered list or indentation.'
            }
            if (-not $bodies.Count) { throw "OBLIGATION_SOURCE_MALFORMED: empty $Section section." }
            $digest = Get-ReviewTextHash ($bodies -join "`n")
            for ($i=0; $i -lt $bodies.Count; $i++) {
                [pscustomobject][ordered]@{
                    required_output_id="v1/$SourceKind/$RelativePath/$digest/$($i+1)"
                    source_kind=$SourceKind; declaration_path=$RelativePath; section_sha256=$digest
                    bullet_order=$i+1; declaration=$bodies[$i]; conditional=$false
                }
            }
        }
        function Assert-ReviewSafePath([string]$Root,[string]$Path) {
            $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
            $full=[IO.Path]::GetFullPath($Path)
            if (-not $full.StartsWith($rootFull+[IO.Path]::DirectorySeparatorChar,$pathComparison)) { throw 'REVIEW_GROUNDING_UNSAFE_PATH: source escapes its namespace.' }
            $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
            while ($null -ne $item) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'REVIEW_GROUNDING_UNSAFE_PATH: reparse point in source ancestry.' }
                if ([string]::Equals($item.FullName,$rootFull,$pathComparison)) { break }
                $parent=Split-Path $item.FullName -Parent
                if (-not $parent) { throw 'REVIEW_GROUNDING_UNSAFE_PATH: source ancestry escaped namespace.' }
                $item=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
            }
        }
        function Read-ReviewSource([string]$Root,[string]$Path,[string]$RelativePath,[string]$Namespace,[string]$Kind,[byte[]]$CapturedRawBytes,[switch]$AllowMissing) {
            $relative=$RelativePath.Replace('\','/')
            if ([IO.Path]::IsPathRooted($relative) -or $relative.StartsWith('/') -or ($relative -split '/') -contains '..' -or ($relative -split '/') -contains '.' -or ($relative -split '/') -contains '' -or $relative -match '[:\r\n]') { throw 'REVIEW_GROUNDING_UNSAFE_PATH: noncanonical relative path.' }
            if ($relative -match '(?i)(^|/)(\.env[^/]*|[^/]*(?:secret|credential|private[-_]?key)[^/]*)(/|$)') { throw 'REVIEW_GROUNDING_UNSAFE_PATH: sensitive artifact name.' }
            $full=[IO.Path]::GetFullPath($Path)
            if (-not [string]::Equals($full,[IO.Path]::GetFullPath((Join-Path $Root $relative)),$pathComparison)) { throw 'REVIEW_GROUNDING_UNSAFE_PATH: path and namespace-relative identity disagree.' }
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                if (-not $AllowMissing) { throw "REVIEW_GROUNDING_SOURCE_MISSING: $relative" }
                return [pscustomobject][ordered]@{path=$full;root=$Root;relative_path=$relative;namespace=$Namespace;kind=$Kind;exists=$false;raw_sha256='';raw_bytes='';text='';normalized_sha256='';line_count=0}
            }
            Assert-ReviewSafePath $Root $full
            $stream=$null; $memory=$null
            try {
                if ($null -eq $CapturedRawBytes) {
                    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
                    if ($stream.Length -gt 5000000) { throw 'REVIEW_GROUNDING_LIMIT: source exceeds capture byte ceiling.' }
                    $memory=New-Object IO.MemoryStream
                    $stream.CopyTo($memory); $bytes=$memory.ToArray()
                } else { $bytes=[byte[]]$CapturedRawBytes.Clone() }
                $text=Get-ReviewNormalizedText -Bytes $bytes
                return [pscustomobject][ordered]@{
                    path=$full;root=$Root;relative_path=$relative;namespace=$Namespace;kind=$Kind;exists=$true
                    raw_sha256=(Get-ReviewHash $bytes);raw_bytes=[Convert]::ToBase64String($bytes)
                    text=$text;normalized_sha256=(Get-ReviewTextHash $text);line_count=$text.Split([char]10).Count
                }
            } finally { if($null-ne $memory){$memory.Dispose()};if($null-ne $stream){$stream.Dispose()} }
        }
        function Get-ReviewEntry([object]$Context) {
            $entries=@($contexts.Values | Where-Object {[object]::ReferenceEquals($_.Context,$Context)})
            if($entries.Count-ne 1){throw 'REVIEW_GROUNDING_UNTRUSTED_CONTEXT: no registered immutable invocation.'}
            $entry=$entries[0]
            Assert-TaskExecutionLease -ProjectPath $entry.Project -Id $entry.TaskId -Lease $entry.Lease -Operation GATE
            $manifest=$entry.ManifestJson|ConvertFrom-Json
            if($entry.ProcessId-ne $PID -or $Context.SnapshotId-cne $manifest.snapshot_id -or $Context.ManifestDigest-cne $entry.ManifestDigest -or (Get-ReviewTextHash $entry.ManifestJson)-cne $entry.ManifestDigest -or (Get-ReviewTextHash $entry.FrozenSourcesJson)-cne $entry.FrozenSourcesDigest){throw 'REVIEW_GROUNDING_UNTRUSTED_CONTEXT: registry or handle identity changed.'}
            return $entry
        }
        function Invoke-ReviewCandidateGit([string]$Root,[string[]]$Arguments) {
            $output=@(& git -c "safe.directory=$Root" -C $Root @Arguments 2>$null)
            if($LASTEXITCODE-ne 0){throw 'REVIEW_GROUNDING_CANDIDATE_IDENTITY: unable to verify registered Git candidate.'}
            return $output
        }
        function Assert-ReviewCandidateRegistration([string]$Project,[string]$TaskId,[object]$Identity,[string]$RelativePath) {
            $workspace=[IO.Path]::GetFullPath([string]$Identity.root).TrimEnd('\','/')
            if([string]::Equals($workspace,$Project.TrimEnd('\','/'),$pathComparison)){throw 'REVIEW_GROUNDING_CANDIDATE_IDENTITY: primary checkout is not a candidate.'}
            $evidence=Read-ReviewSource $Project (Join-Path $Project "docs/engineering/writable-evidence/$TaskId.md") "docs/engineering/writable-evidence/$TaskId.md" 'project' 'authorization' $null
            $worktree=[regex]::Match($evidence.text,'(?m)^Worktree:[ \t]*([^\n]+)$').Groups[1].Value.Trim()
            $branch='aico/'+$TaskId.ToLowerInvariant()
            if(-not $worktree -or -not [string]::Equals([IO.Path]::GetFullPath($worktree).TrimEnd('\','/'),$workspace,$pathComparison) -or $evidence.text-cnotmatch ('(?m)^Branch:[ \t]*'+[regex]::Escape($branch)+'[ \t]*$')){throw 'REVIEW_GROUNDING_CANDIDATE_IDENTITY: canonical candidate declaration mismatch.'}
            $records=@(Invoke-ReviewCandidateGit $Project @('worktree','list','--porcelain'))
            $registered=$false;$current=''
            foreach($line in $records){if($line-match '^worktree (.+)$'){$current=[IO.Path]::GetFullPath($Matches[1]).TrimEnd('\','/')};if($line-ceq "branch refs/heads/$branch" -and [string]::Equals($current,$workspace,$pathComparison)){$registered=$true}}
            $actualBranch=(@(Invoke-ReviewCandidateGit $workspace @('branch','--show-current'))-join '').Trim()
            $common=(@(Invoke-ReviewCandidateGit $workspace @('rev-parse','--git-common-dir'))-join '').Trim()
            $projectCommon=(@(Invoke-ReviewCandidateGit $Project @('rev-parse','--git-common-dir'))-join '').Trim()
            if(-not [IO.Path]::IsPathRooted($common)){$common=Join-Path $workspace $common};if(-not [IO.Path]::IsPathRooted($projectCommon)){$projectCommon=Join-Path $Project $projectCommon}
            if(-not $registered -or $actualBranch-cne $branch -or -not [string]::Equals([IO.Path]::GetFullPath($common).TrimEnd('\','/'),[IO.Path]::GetFullPath($projectCommon).TrimEnd('\','/'),$pathComparison) -or -not [string]::Equals([IO.Path]::GetFullPath($common).TrimEnd('\','/'),[IO.Path]::GetFullPath([string]$Identity.common_directory).TrimEnd('\','/'),$pathComparison)){throw 'REVIEW_GROUNDING_CANDIDATE_IDENTITY: live registration/common-directory mismatch.'}
            $inventory=@(@(Invoke-ReviewCandidateGit $workspace @('-c','core.quotePath=false','diff','--name-only','HEAD','--'))+@(Invoke-ReviewCandidateGit $workspace @('-c','core.quotePath=false','ls-files','--others','--exclude-standard'))|Sort-Object -Unique)
            if($inventory-cnotcontains $RelativePath){throw 'REVIEW_GROUNDING_CANDIDATE_IDENTITY: source is not in actual changed candidate inventory.'}
            $policySource=Read-ReviewSource $Project (Join-Path $Project '.codex/writable-policy.json') '.codex/writable-policy.json' 'project' 'authorization' $null
            $policy=$policySource.text|ConvertFrom-Json
            foreach($prefix in $policy.protected_path_prefixes){if($RelativePath.ToLowerInvariant()-eq ([string]$prefix).ToLowerInvariant() -or $RelativePath.ToLowerInvariant().StartsWith(([string]$prefix).ToLowerInvariant()+'/')){throw 'REVIEW_GROUNDING_UNSAFE_PATH: candidate policy protected source.'}}
            foreach($pattern in $policy.secret_name_patterns){if($RelativePath-match $pattern){throw 'REVIEW_GROUNDING_UNSAFE_PATH: candidate policy sensitive source.'}}
            if((Get-Item -LiteralPath (Join-Path $workspace $RelativePath)).Length-gt [long]$policy.max_file_bytes -or $inventory.Count-gt [int]$policy.max_changed_files){throw 'REVIEW_GROUNDING_LIMIT: candidate exceeds canonical policy.'}
        }
        function New-ReviewGroundingContext {
            param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$Id,
                  [Parameter(Mandatory=$true)][object]$Lease,[object[]]$PrimaryArtifacts=@(),
                  [string]$TaskPath='', [string]$RolePath='', [string]$DispatchPath='', [string]$ResultPath='',
                  [scriptblock]$CandidateIdentityVerifier,[string[]]$AdditionalSourcePaths=@())
            $root=[IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path)
            Assert-TaskExecutionLease -ProjectPath $root -Id $Id -Lease $Lease -Operation GATE
            if($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$'){throw 'REVIEW_GROUNDING_UNSAFE_PATH: task ID invalid.'}
            $taskRelative="tasks/$Id.md"
            if(-not $TaskPath){$TaskPath=Join-Path $root $taskRelative}
            $task=Read-ReviewSource $root $TaskPath $taskRelative 'project' 'requirements' $null
            $ownerMatch=[regex]::Match($task.text,'(?m)^Owner:[ \t]*([a-z][a-z_-]+)[ \t]*$')
            if(-not $ownerMatch.Success -or $task.text -cnotmatch ('(?m)^ID:[ \t]*'+[regex]::Escape($Id)+'[ \t]*$') -or $task.text-cnotmatch '(?m)^Status:[ \t]*REVIEW[ \t]*$'){throw 'REVIEW_GROUNDING_IDENTITY: canonical task identity or REVIEW status missing.'}
            $owner=$ownerMatch.Groups[1].Value; $roleRelative=".codex/agents/$owner.md"
            if(-not $RolePath){$RolePath=Join-Path $root $roleRelative}
            $role=Read-ReviewSource $root $RolePath $roleRelative 'project' 'requirements' $null
            $dispatchRelative="docs/engineering/dispatch/$Id.md"
            if(-not $DispatchPath){$DispatchPath=Join-Path $root $dispatchRelative}
            $dispatch=Read-ReviewSource $root $DispatchPath $dispatchRelative 'project' 'requirements' $null
            if($dispatch.exists -and ($dispatch.text -cnotmatch ('(?m)^Task:[ \t]*'+[regex]::Escape($Id)+'[ \t]*$') -or $dispatch.text -cnotmatch ('(?m)^Owner:[ \t]*'+[regex]::Escape($owner)+'[ \t]*$'))){throw 'REVIEW_GROUNDING_IDENTITY: dispatch task/owner mismatch.'}
            if(-not $ResultPath){$ResultPath=@(Get-ChildItem -LiteralPath (Join-Path $root 'docs/engineering/results') -Filter "$Id-result-*.md" -File | Sort-Object {if($_.BaseName-match '-result-(\d+)$'){[int]$Matches[1]}else{-1}} -Descending | Select-Object -First 1)[0].FullName}
            if(-not $ResultPath){throw 'REVIEW_GROUNDING_SOURCE_MISSING: latest owner result.'}
            $resultRelative='docs/engineering/results/'+(Split-Path $ResultPath -Leaf)
            if((Split-Path $ResultPath -Leaf)-notmatch ('^'+[regex]::Escape($Id)+'-result-\d+\.md$')){throw 'REVIEW_GROUNDING_IDENTITY: result belongs to another task.'}
            $result=Read-ReviewSource $root $ResultPath $resultRelative 'project' 'secondary' $null
            if($result.text-cnotmatch ('(?m)^Task:[ \t]*'+[regex]::Escape($Id)+'[ \t]*$') -or $result.text-cnotmatch ('(?m)^Owner:[ \t]*'+[regex]::Escape($owner)+'[ \t]*$')){throw 'REVIEW_GROUNDING_IDENTITY: result task/owner mismatch.'}
            $roleObligations=@(Get-ReviewDeclarations -Text $role.text -Section Output -SourceKind role-output -RelativePath $roleRelative -AllowAbsent)
            if($owner-cin @('pm','cto','engineering-manager') -and -not $roleObligations.Count){throw 'OBLIGATION_SOURCE_MALFORMED: shipped declaring role is missing Output.'}
            $taskObligations=@(Get-ReviewDeclarations -Text $task.text -Section 'Acceptance Criteria' -SourceKind task-acceptance -RelativePath $taskRelative)
            $scaffold=@('Objective is satisfied.','Required evidence is recorded.','Applicable quality gates are complete or explicitly marked NOT_APPLICABLE.','Role-owned deliverable is produced.','Open questions and blockers are explicit.','Evidence is recorded in this task.','Applicable downstream dependencies are ready.')
            if(-not $roleObligations.Count -and -not @($taskObligations | Where-Object {$_.declaration -cnotin $scaffold}).Count){throw 'OBLIGATION_SOURCE_NOT_CONCRETE: no role Output and only generic task scaffolds.'}
            $obligations=@($roleObligations)+@($taskObligations)
            if($obligations.Count-gt 64){throw 'REVIEW_GROUNDING_LIMIT: more than 64 obligations.'}
            foreach($obligation in $obligations){
                if($obligation.source_kind-ceq 'role-output' -and $obligation.declaration_path-ceq '.codex/agents/cto.md' -and $obligation.bullet_order-eq 7 -and $obligation.declaration-ceq 'ADR when necessary.' -and $obligation.section_sha256-ceq '06a29bd81a9409b71386fdfa27204a01dc10576f665e72fafa4c1620e5d69281'){$obligation.conditional=$true}
            }
            $reportRelative="docs/engineering/agent-reports/$Id.md"
            $implementation=$task.text -match '(?m)^Work kind:[ \t]*IMPLEMENTATION[ \t]*$'
            if($implementation -and -not $PrimaryArtifacts.Count){throw 'REVIEW_GROUNDING_AUTHORITY: implementation requires registered candidate inventory.'}
            if(-not $PrimaryArtifacts.Count){$PrimaryArtifacts=@([pscustomobject]@{Path=(Join-Path $root $reportRelative);RelativePath=$reportRelative;Namespace='project'})}
            if($PrimaryArtifacts.Count-gt 20){throw 'REVIEW_GROUNDING_LIMIT: more than 20 primary artifacts.'}
            $sources=@($task,$role,$dispatch,$result);$artifacts=@();$seen=@{}
            foreach($inputArtifact in $PrimaryArtifacts){
                $namespace=[string]$inputArtifact.Namespace
                $relative=([string]$inputArtifact.RelativePath).Replace('\','/')
                if($namespace -notin @('project','implementation-candidate')){throw 'REVIEW_GROUNDING_IDENTITY: unsupported primary namespace.'}
                $sourceRoot=$root
                if($namespace-eq 'project' -and $relative-cne $reportRelative){
                    $changed=[regex]::Match($result.text,'(?ms)^## Changed Artifacts[ \t]*\n(.*?)(?=^## |\z)').Groups[1].Value
                    if($relative-notmatch '^docs/(product|architecture|decisions|engineering/handoffs)/' -or -not $task.text.Contains($relative) -or -not $dispatch.text.Contains($relative) -or -not $changed.Contains($relative) -or $relative-match 'AICO-(\d+)' -and $Matches[0]-cne $Id){throw 'REVIEW_GROUNDING_AUTHORITY: additional output lacks canonical task/dispatch delivered-artifact registration.'}
                }
                if($namespace-eq 'implementation-candidate'){
                    if($null-eq $inputArtifact.CandidateIdentity -or $null-eq $CandidateIdentityVerifier){throw 'REVIEW_GROUNDING_AUTHORITY: implementation candidate identity/verifier required.'}
                    $sourceRoot=[string]$inputArtifact.CandidateIdentity.root
                    if(-not $sourceRoot){throw 'REVIEW_GROUNDING_IDENTITY: candidate workspace missing.'}
                    if(-not $implementation -or -not $inputArtifact.CandidateIdentity.registered -or $inputArtifact.CandidateIdentity.branch-cne ('aico/'+$Id.ToLowerInvariant()) -or [string]::IsNullOrWhiteSpace([string]$inputArtifact.CandidateIdentity.common_directory)){throw 'REVIEW_GROUNDING_AUTHORITY: candidate is not task-bound registered implementation.'}
                    Assert-ReviewCandidateRegistration $root $Id $inputArtifact.CandidateIdentity $relative
                }
                $key=$namespace+'/'+$relative
                if($seen.ContainsKey($key)){throw 'REVIEW_GROUNDING_IDENTITY: duplicate primary source.'};$seen[$key]=$true
                $source=Read-ReviewSource $sourceRoot ([string]$inputArtifact.Path) $relative $namespace 'primary' $inputArtifact.CapturedRawBytes
                if($null-ne $inputArtifact.CapturedRawBytes){$current=Read-ReviewSource $sourceRoot ([string]$inputArtifact.Path) $relative $namespace 'primary' $null;if($current.raw_sha256-cne $source.raw_sha256){throw 'REVIEW_GROUNDING_SOURCE_DRIFT: captured bytes differ from live preparation source.'}}
                if($namespace-eq 'project' -and ($source.text-cnotmatch ('(?m)^# Agent Report - '+[regex]::Escape($Id)+'[ \t]*$') -or $source.text-cnotmatch ('(?m)^Owner:[ \t]*'+[regex]::Escape($owner)+'[ \t]*$'))){throw 'REVIEW_GROUNDING_IDENTITY: primary report task/owner mismatch.'}
                $artifact=[pscustomobject][ordered]@{artifact_id=('primary-'+($artifacts.Count+1));authority_class='primary';task_id=$Id;namespace=$namespace;relative_path=$relative;raw_sha256=$source.raw_sha256;normalized_sha256=$source.normalized_sha256;line_count=$source.line_count;candidate_identity=$inputArtifact.CandidateIdentity}
                $source | Add-Member -NotePropertyName artifact_id -NotePropertyValue $artifact.artifact_id
                $sources+=$source;$artifacts+=$artifact
            }
            if($implementation){
                if(@($artifacts|Where-Object{$_.namespace-ne 'implementation-candidate'}).Count){throw 'REVIEW_GROUNDING_AUTHORITY: implementation positive proof must be candidate source.'}
                $summary=Read-ReviewSource $root (Join-Path $root $reportRelative) $reportRelative 'project' 'secondary-report' $null
                $sources+=$summary
            }
            foreach($additionalPath in $AdditionalSourcePaths){
                $full=[IO.Path]::GetFullPath($additionalPath)
                if(-not $full.StartsWith($root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,$pathComparison)){throw 'REVIEW_GROUNDING_UNSAFE_PATH: additional identity source outside project.'}
                $relative=$full.Substring($root.TrimEnd('\','/').Length+1).Replace('\','/')
                $sources+=Read-ReviewSource $root $full $relative 'project' 'authorization' $null
            }
            $candidateJson=''
            if($null-ne $CandidateIdentityVerifier){
                $candidateIdentity=& $CandidateIdentityVerifier
                $candidateJson=$candidateIdentity|ConvertTo-Json -Depth 60 -Compress
                foreach($artifact in @($artifacts|Where-Object{$_.namespace-eq 'implementation-candidate'})){
                    $registered=@($candidateIdentity.files|Where-Object{$_.path-ceq $artifact.relative_path -and -not $_.deleted -and $_.raw_sha256-ceq $artifact.raw_sha256})
                    if($registered.Count-ne 1 -or $candidateIdentity.branch-cne $artifact.candidate_identity.branch -or -not $candidateIdentity.registered -or -not [string]::Equals([string]$candidateIdentity.root,[string]$artifact.candidate_identity.root,$pathComparison)){throw 'REVIEW_GROUNDING_SOURCE_DRIFT: candidate capture no longer matches registered inventory.'}
                }
            }
            $candidateInventory=$null
            if($candidateJson){$candidateInventory=$candidateJson|ConvertFrom-Json}
            $manifest=[ordered]@{contract_version='review-grounding-v1';normalization='utf8-lf-v1';snapshot_id=('review-'+[guid]::NewGuid().ToString('N'));task_id=$Id;owner=$owner;obligations=$obligations;artifacts=$artifacts;candidate_inventory=$candidateInventory;source_identities=@($sources|ForEach-Object{[ordered]@{relative_path=$_.relative_path;namespace=$_.namespace;kind=$_.kind;exists=$_.exists;raw_sha256=$_.raw_sha256;normalized_sha256=$_.normalized_sha256}})}
            $manifestJson=$manifest|ConvertTo-Json -Depth 60 -Compress
            $digest=Get-ReviewTextHash $manifestJson
            $handle=[pscustomobject]@{SnapshotId=$manifest.snapshot_id;ManifestDigest=$digest}
            $sourcesJson=$sources|ConvertTo-Json -Depth 60 -Compress
            $contexts[$manifest.snapshot_id]=[pscustomobject]@{Context=$handle;Project=$root;TaskId=$Id;Lease=$Lease;ProcessId=$PID;ManifestJson=$manifestJson;ManifestDigest=$digest;FrozenSourcesJson=$sourcesJson;FrozenSourcesDigest=(Get-ReviewTextHash $sourcesJson);CandidateJson=$candidateJson;Verifier=$CandidateIdentityVerifier}
            return $handle
        }
        function Get-ReviewGroundingManifest {
            param([object]$Context)
            $entry=Get-ReviewEntry $Context
            $copy=$entry.ManifestJson|ConvertFrom-Json
            $copy|Add-Member -NotePropertyName manifest_digest -NotePropertyValue $entry.ManifestDigest
            return $copy
        }
        function Get-ReviewGroundingPrompt {
            param([object]$Context)
            $entry=Get-ReviewEntry $Context;$manifest=$entry.ManifestJson|ConvertFrom-Json;$sources=$entry.FrozenSourcesJson|ConvertFrom-Json
            $builder=New-Object Text.StringBuilder
            foreach($pair in @(@('requirements','tasks/','CANONICAL TASK'),@('requirements','docs/engineering/dispatch/','DISPATCH PACKET'),@('requirements','.codex/agents/','ORIGINAL OWNER ROLE CONTRACT'))){
                $source=@($sources|Where-Object{$_.kind-eq $pair[0]-and $_.relative_path.StartsWith($pair[1])})[0]
                [void]$builder.AppendLine("===== $($pair[2]) =====")
                [void]$builder.AppendLine('AUTHORITY: REQUIREMENTS/CONTEXT ONLY; NOT ELIGIBLE POSITIVE DELIVERY EVIDENCE.')
                [void]$builder.AppendLine($source.text)
            }
            [void]$builder.AppendLine('===== PRIMARY AGENT REPORT =====')
            foreach($summary in @($sources|Where-Object{$_.kind-eq 'secondary-report'})){
                [void]$builder.AppendLine('SECONDARY EXECUTION SUMMARY — IMPLEMENTATION DELIVERY PROOF IS REGISTERED CANDIDATE SOURCE BELOW.')
                [void]$builder.AppendLine($summary.text)
            }
            [void]$builder.AppendLine('ENGINE IMMUTABLE PRIMARY EVIDENCE. Line labels are outside source content; excerpt must omit labels.')
            foreach($source in @($sources|Where-Object{$_.kind-eq 'primary'})){
                [void]$builder.AppendLine("Artifact: $($source.artifact_id); namespace: $($source.namespace); relative path: $($source.relative_path)")
                $lines=$source.text.Split([char]10)
                for($i=0;$i-lt $lines.Count;$i++){[void]$builder.AppendLine("$($i+1)|$($lines[$i])")}
            }
            if($null-ne $manifest.candidate_inventory){
                [void]$builder.AppendLine('===== IMMUTABLE IMPLEMENTATION CANDIDATE INVENTORY =====')
                [void]$builder.AppendLine('Registration and deleted-path metadata are frozen context, not positive textual evidence. Deleted artifacts have no eligible citation ID.')
                foreach($file in $manifest.candidate_inventory.files){
                    [void]$builder.AppendLine("Repository-relative path: $($file.path)")
                    if($file.deleted){[void]$builder.AppendLine('Candidate operation: DELETE (absent from current worktree)')}
                    else{[void]$builder.AppendLine('Candidate operation: CURRENT SOURCE');[void]$builder.AppendLine("Raw SHA256: $($file.raw_sha256)")}
                }
            }
            [void]$builder.AppendLine('===== LATEST TASK RESULT =====')
            [void]$builder.AppendLine('SECONDARY SELF-ATTESTATION — NOT ELIGIBLE POSITIVE EVIDENCE.')
            [void]$builder.AppendLine(@($sources|Where-Object{$_.kind-eq 'secondary'})[0].text)
            [void]$builder.AppendLine('===== REVIEW GROUNDING CONTRACT =====')
            [void]$builder.AppendLine("Manifest digest: $($entry.ManifestDigest)")
            [void]$builder.AppendLine($entry.ManifestJson)
            [void]$builder.AppendLine('Assess every exact required_output_id once. SATISFIED requires exact primary line citations. NOT_APPLICABLE is allowed only for conditional=true and requires rationale, primary facts citing applicability, and conditional_authority equal to the exact required_output_id from the source declaration. UNSATISFIED missing-output judgments may have empty evidence. Genuine quotes establish provenance, not semantic sufficiency. Never trust result claims as delivered proof.')
            return $builder.ToString()
        }
        function Assert-ReviewDrift([object]$Entry) {
            $frozenSources=$Entry.FrozenSourcesJson|ConvertFrom-Json
            foreach($source in $frozenSources){
                try {
                    $live=Read-ReviewSource $source.root $source.path $source.relative_path $source.namespace $source.kind $null -AllowMissing
                    if($live.exists-ne $source.exists -or $live.raw_sha256-cne $source.raw_sha256){throw 'raw identity changed'}
                } catch { throw "REVIEW_GROUNDING_SOURCE_DRIFT: $($source.relative_path); fresh invocation required." }
            }
            $latest=@(Get-ChildItem -LiteralPath (Join-Path $Entry.Project 'docs/engineering/results') -Filter "$($Entry.TaskId)-result-*.md" -File|Sort-Object {if($_.BaseName-match '-result-(\d+)$'){[int]$Matches[1]}else{-1}} -Descending|Select-Object -First 1)[0]
            $captured=@($frozenSources|Where-Object{$_.kind-eq 'secondary'})[0]
            if($null-eq $latest -or -not [string]::Equals($latest.FullName,$captured.path,$pathComparison)){throw 'REVIEW_GROUNDING_SOURCE_DRIFT: latest result membership changed.'}
            try { if($null-ne $Entry.Verifier -and (& $Entry.Verifier|ConvertTo-Json -Depth 60 -Compress)-cne $Entry.CandidateJson){throw 'candidate identity changed'} } catch { throw 'REVIEW_GROUNDING_SOURCE_DRIFT: candidate registration identity unavailable or changed.' }
        }
        function Assert-ReviewGroundingResult {
            param([object]$Result,[object]$Context,[switch]$CheckDrift)
            $entry=Get-ReviewEntry $Context;$manifest=$entry.ManifestJson|ConvertFrom-Json;$sources=$entry.FrozenSourcesJson|ConvertFrom-Json
            if($Result.contract_version-cne 'review-grounding-v1' -or $Result.snapshot_id-cne $manifest.snapshot_id){throw 'REVIEW_GROUNDING_SNAPSHOT_MISMATCH: contract version or invocation ID differs.'}
            foreach($field in @('contract_version','snapshot_id','recommendation','findings','verification','missing_required_outputs','deliverable_defects','assessments')){if($null-eq $Result.PSObject.Properties[$field]){throw "REVIEW_GROUNDING_INVALID_ASSESSMENT: missing $field"}}
            foreach($field in @('missing_required_outputs','deliverable_defects')){foreach($value in @($Result.$field)){if($value-isnot [string] -or [string]::IsNullOrWhiteSpace($value)){throw 'REVIEW_GROUNDING_NEGATIVE_REQUIRED: missing/defect records must be concrete strings.'}}}
            $rows=@($Result.assessments)
            if($rows.Count-ne @($manifest.obligations).Count -or $rows.Count-gt 64){throw 'REVIEW_GROUNDING_COVERAGE: assessment set does not match frozen obligations.'}
            $seen=@{};$totalBytes=0;$unsatisfied=0
            foreach($row in $rows){
                $id=[string]$row.required_output_id
                if($seen.ContainsKey($id)){throw 'REVIEW_GROUNDING_COVERAGE: duplicate obligation.'};$seen[$id]=$true
                $expected=@($manifest.obligations|Where-Object{$_.required_output_id-ceq $id})
                if($expected.Count-ne 1){throw 'REVIEW_GROUNDING_COVERAGE: unknown obligation ID.'}
                if([string]::IsNullOrWhiteSpace([string]$row.rationale)){throw 'REVIEW_GROUNDING_INVALID_ASSESSMENT: rationale required.'}
                if($row.status-cnotin @('SATISFIED','UNSATISFIED','NOT_APPLICABLE')){throw 'REVIEW_GROUNDING_INVALID_ASSESSMENT: unsupported status.'}
                if($row.status-ceq 'UNSATISFIED'){$unsatisfied++}
                if($row.status-ceq 'NOT_APPLICABLE' -and -not $expected[0].conditional){throw 'REVIEW_GROUNDING_CONDITIONAL_UNAUTHORIZED: unconditional obligation cannot be waived.'}
                if($row.status-ceq 'NOT_APPLICABLE' -and $row.conditional_authority-cne $expected[0].required_output_id){throw 'REVIEW_GROUNDING_CONDITIONAL_UNAUTHORIZED: exact versioned source authority required.'}
                $citations=@($row.evidence)
                if($citations.Count-gt 3 -or ($row.status-cne 'UNSATISFIED'-and $citations.Count-eq 0)){throw 'REVIEW_GROUNDING_CITATION_REQUIRED: positive or conditional judgment needs primary evidence.'}
                foreach($citation in $citations){
                    $matches=@($sources|Where-Object{$_.kind-eq 'primary'-and $_.artifact_id-ceq $citation.artifact_id})
                    if($matches.Count-ne 1){throw 'REVIEW_GROUNDING_PRIMARY_AUTHORITY: citation does not name supplied primary evidence.'}
                    $source=$matches[0]
                    $actualNormalizedHash=Get-ReviewTextHash $source.text
                    $rawBytes=[Convert]::FromBase64String($source.raw_bytes)
                    $actualRawHash=Get-ReviewHash $rawBytes
                    if($actualNormalizedHash-cne $source.normalized_sha256 -or $actualRawHash-cne $source.raw_sha256 -or -not [string]::Equals((Get-ReviewNormalizedText -Bytes $rawBytes),$source.text,[StringComparison]::Ordinal)){throw 'REVIEW_GROUNDING_SNAPSHOT_MISMATCH: captured source identity invalid.'}
                    if($citation.start_line-isnot [int] -and $citation.start_line-isnot [long]){throw 'REVIEW_GROUNDING_LOCATOR: line must be integer.'}
                    if($citation.end_line-isnot [int] -and $citation.end_line-isnot [long]){throw 'REVIEW_GROUNDING_LOCATOR: line must be integer.'}
                    $start=[long]$citation.start_line;$end=[long]$citation.end_line
                    $bytes=[Text.Encoding]::UTF8.GetByteCount([string]$citation.excerpt);$totalBytes+=$bytes
                    if($start-lt 1 -or $end-lt $start -or $end-gt $source.line_count -or $end-$start+1-gt 16 -or $bytes-gt 2048 -or $totalBytes-gt 32768){throw 'REVIEW_GROUNDING_LOCATOR_LIMIT: citation bounds or excerpt limits exceeded.'}
                    $lines=$source.text.Split([char]10);$exact=$lines[($start-1)..($end-1)]-join "`n"
                    if(-not [string]::Equals($exact,[string]$citation.excerpt,[StringComparison]::Ordinal)){throw 'REVIEW_GROUNDING_EXCERPT_MISMATCH: quote differs at exact normalized line range.'}
                }
            }
            if($Result.recommendation-ceq 'APPROVE'){
                if($unsatisfied-gt 0 -or @($Result.missing_required_outputs).Count-gt 0 -or @($Result.deliverable_defects).Count-gt 0){throw 'REVIEW_GROUNDING_APPROVE_CONTRADICTION: obligations or defect arrays contradict approval.'}
            } elseif($Result.recommendation-ceq 'CHANGES_REQUIRED'){
                if(@($Result.missing_required_outputs).Count-eq 0-and @($Result.deliverable_defects).Count-eq 0){throw 'REVIEW_GROUNDING_NEGATIVE_REQUIRED: concrete missing output or deliverable defect required.'}
                if(@($Result.missing_required_outputs).Count-gt 0-and $unsatisfied-eq 0){throw 'REVIEW_GROUNDING_NEGATIVE_REQUIRED: missing output needs corresponding UNSATISFIED assessment.'}
            } else {throw 'REVIEW_GROUNDING_INVALID_ASSESSMENT: recommendation invalid.'}
            if($CheckDrift){Assert-ReviewDrift $entry}
            $token=[pscustomobject]@{ValidationId=[guid]::NewGuid().ToString('N')}
            $validations[$token.ValidationId]=[pscustomobject]@{Token=$token;Entry=$entry;Context=$Context;Result=$Result;Recommendation=[string]$Result.recommendation;ResultJson=($Result|ConvertTo-Json -Depth 60 -Compress);ResultDigest=(Get-ReviewTextHash ($Result|ConvertTo-Json -Depth 60 -Compress));DriftChecked=[bool]$CheckDrift;ProcessId=$PID}
            return $token
        }
        function Assert-ReviewGroundingValidation {
            param([string]$ProjectPath,[string]$Id,[object]$Lease,[object]$Validation,[string]$Recommendation)
            $records=@($validations.Values|Where-Object{[object]::ReferenceEquals($_.Token,$Validation)})
            if($records.Count-ne 1){throw 'REVIEW_GROUNDING_UNTRUSTED_VALIDATION: no registered grounded pre-intake judgment.'}
            $record=$records[0];$entry=Get-ReviewEntry $record.Context
            if(-not $record.DriftChecked -or $record.ProcessId-ne $PID -or $entry.TaskId-cne $Id -or -not [object]::ReferenceEquals($entry.Lease,$Lease) -or -not [string]::Equals($entry.Project,[IO.Path]::GetFullPath((Resolve-Path $ProjectPath).Path),$pathComparison)-or $record.Recommendation-cne $Recommendation -or (Get-ReviewTextHash $record.ResultJson)-cne $record.ResultDigest -or (Get-ReviewTextHash ($record.Result|ConvertTo-Json -Depth 60 -Compress))-cne $record.ResultDigest){throw 'REVIEW_GROUNDING_UNTRUSTED_VALIDATION: validation identity, result identity or final drift check missing.'}
        }
        Export-ModuleMember -Function Get-ReviewNormalizedText,Get-ReviewDeclarations,New-ReviewGroundingContext,Get-ReviewGroundingManifest,Get-ReviewGroundingPrompt,Assert-ReviewGroundingResult,Assert-ReviewGroundingValidation
    } -ArgumentList (Join-Path $PSScriptRoot 'task-execution-lock.ps1') | Import-Module -Global
}
