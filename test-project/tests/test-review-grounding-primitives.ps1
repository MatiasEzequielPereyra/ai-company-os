param([string]$ProjectPath = '')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repo 'scripts/task-execution-lock.ps1')
. (Join-Path $repo 'scripts/review-grounding.ps1')
$script:checks=0
function Check([bool]$Condition,[string]$Name) { if(-not $Condition){throw "Assertion failed: $Name"};$script:checks++ }
function Reject([scriptblock]$Action,[string]$Reason) {
    $caught='';try { & $Action | Out-Null } catch {$caught=$_.Exception.Message}
    Check ($caught -match [regex]::Escape($Reason)) "expected $Reason; got $caught"
}
function Parse([string]$Text) { @(Get-ReviewDeclarations -Text $Text -Section 'Acceptance Criteria' -SourceKind task-acceptance -RelativePath 'tasks/AICO-001.md') }
$utf8=New-Object Text.UTF8Encoding($false,$true)
$text="first`t  `ncombining e$([char]0x301) $([char]::ConvertFromUtf32(0x1f680))`n"
foreach($variant in @($text,$text.Replace("`n","`r`n"),$text.Replace("`n","`r"))) {
    Check ([string]::Equals((Get-ReviewNormalizedText -Bytes $utf8.GetBytes($variant)),$text,[StringComparison]::Ordinal)) 'LF/CRLF/lone CR normalize without other edits'
}
$bom=[byte[]](@(239,187,191)+@($utf8.GetBytes($text)))
Check ([string]::Equals((Get-ReviewNormalizedText -Bytes $bom),$text,[StringComparison]::Ordinal)) 'initial BOM removed'
Check ((Get-ReviewNormalizedText -Bytes $utf8.GetBytes($text)).Split([char]10).Count -eq 3) 'trailing LF retains empty final line'
Reject {Get-ReviewNormalizedText -Bytes ([byte[]](0xc3,0x28))} 'REVIEW_GROUNDING_INVALID_UTF8'
$a=Parse "# Task`n## Acceptance Criteria`n- [ ] Same  text.`n* [x] Same  text.`n+ Third.`n  literal continuation`t `n## Requirements`n- Context only."
Check ($a.Count -eq 3) 'three declarations only in chosen section'
Check ($a[0].declaration -ceq 'Same  text.') 'literal spacing preserved'
Check ($a[2].declaration -ceq "Third.`n  literal continuation`t ") 'continuation whitespace preserved'
Check ($a[0].required_output_id -cne $a[1].required_output_id) 'duplicate text retains distinct ordinal IDs'
$b=Parse "## Acceptance Criteria`n+ [X] Same  text.`n- Same  text.`n* Third.`n  literal continuation`t "
Check ($a[0].required_output_id -ceq $b[0].required_output_id) 'checkbox/list-marker representation excluded from section identity'
$reordered=Parse "## Acceptance Criteria`n- Third.`n- Same  text."
Check ($reordered[0].section_sha256 -cne $a[0].section_sha256) 'order changes declaration identity'
$fenced=@(Parse "~~~text`n## Acceptance Criteria`n- forged`n~~~`n## Acceptance Criteria`n- Real.")
Check ($fenced.Count -eq 1 -and $fenced[0].declaration -ceq 'Real.') 'fenced headings cannot create declarations'
foreach($bad in @(
"## Acceptance Criteria`n- Real.`n## Acceptance Criteria`n- Duplicate.",
"## Acceptance Criteria`n- Real.`n  - Nested.",
"## Acceptance Criteria`n1. Ordered.",
"## Acceptance Criteria`n  Orphan.",
"## Acceptance Criteria`n- TBD",
"## Acceptance Criteria`nUnexpected prose.",
"## Acceptance Criteria`n",
"## Acceptance Criteria`n- Real.`n~~~text`nunclosed",
"## acceptance criteria`n- Wrong case."
)) {Reject {Parse $bad} 'OBLIGATION_SOURCE_MALFORMED'}
Check (@(Get-ReviewDeclarations -Text '# No outputs' -Section Output -SourceKind role-output -RelativePath '.codex/agents/qa.md' -AllowAbsent).Count -eq 0) 'absent role Output creates zero obligations'
foreach($framing in @('Produce:','The normal output is:','Typical outputs include:')) {
    Check (@(Get-ReviewDeclarations -Text "## Output`n$framing`n- Concrete output." -Section Output -SourceKind role-output -RelativePath '.codex/agents/pm.md').Count -eq 1) 'shipped framing accepted without extra obligation'
}
$ctoText=Get-ReviewNormalizedText -Bytes ([IO.File]::ReadAllBytes((Join-Path $repo '.codex/agents/cto.md')))
$cto=@(Get-ReviewDeclarations -Text $ctoText -Section Output -SourceKind role-output -RelativePath '.codex/agents/cto.md')
Check ($cto.Count -eq 7) 'CTO seven exact outputs'
Check ($cto[1].declaration -ceq 'Technical implementation plan.') 'CTO ordinal two preserves implementation plan'
Check ($cto[6].declaration -ceq 'ADR when necessary.') 'CTO conditional declaration literal'
Write-Host "PASS review-grounding-primitives: $script:checks assertions"
