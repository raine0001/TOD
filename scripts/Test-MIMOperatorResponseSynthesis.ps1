param(
    [string]$InputPath = '',
    [string]$Text = '',
    [string]$OutputPath = 'runtime/shared/MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json',
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return [System.IO.Path]::GetFullPath($PathValue) }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload
    )
    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Payload | ConvertTo-Json -Depth 16) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    return $json
}

$sourceText = [string]$Text
$resolvedInputPath = ''
if ([string]::IsNullOrWhiteSpace($sourceText) -and -not [string]::IsNullOrWhiteSpace($InputPath)) {
    $resolvedInputPath = Resolve-RepoPath -PathValue $InputPath
    if (Test-Path -LiteralPath $resolvedInputPath) {
        $sourceText = Get-Content -LiteralPath $resolvedInputPath -Raw
    }
}

$leakPatterns = [ordered]@{
    lifecycle_leakage = '(?i)\blifecycle state\b|\bdispatch_status\b|\bcompletion_status\b|\btask envelope\b'
    artifact_leakage = '(?i)\bruntime/shared\b|\.latest\.json\b|\bpacket_type\b|\brequest_id\b|\btask_id\b'
    stale_summary_leakage = '(?i)\bstale summary\b|\bwrapper\b|\bsource_artifact\b'
    low_relevance_prompt = '(?i)\bwhat would you like me to do\b'
}

$violations = @()
foreach ($entry in $leakPatterns.GetEnumerator()) {
    if ($sourceText -match [string]$entry.Value) {
        $violations += [pscustomobject]@{
            rule = [string]$entry.Key
            pattern = [string]$entry.Value
        }
    }
}

$sentences = @([regex]::Split($sourceText.Trim(), '(?<=[.!?])\s+') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$wordCount = if ([string]::IsNullOrWhiteSpace($sourceText)) { 0 } else { @($sourceText -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count }
if ($wordCount -gt 120) {
    $violations += [pscustomobject]@{ rule = 'too_long_for_default_voice_turn'; pattern = 'word_count_gt_120' }
}
if (@($sentences).Count -gt 4) {
    $violations += [pscustomobject]@{ rule = 'too_many_sentences_for_default_voice_turn'; pattern = 'sentence_count_gt_4' }
}

$payload = [ordered]@{
    packet_type = 'mim-operator-response-synthesis-enforcement-status-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'Test-MIMOperatorResponseSynthesis'
    input_path = $resolvedInputPath
    status = if (@($violations).Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($sourceText)) { 'passed' } elseif ([string]::IsNullOrWhiteSpace($sourceText)) { 'not_applicable' } else { 'blocked_with_evidence' }
    violations = @($violations)
    checks = [ordered]@{
        word_count = $wordCount
        sentence_count = @($sentences).Count
        artifact_leakage_blocked = (@($violations | Where-Object { [string]$_.rule -eq 'artifact_leakage' }).Count -eq 0)
        lifecycle_leakage_blocked = (@($violations | Where-Object { [string]$_.rule -eq 'lifecycle_leakage' }).Count -eq 0)
        concise_by_default = ($wordCount -le 120 -and @($sentences).Count -le 4)
    }
    operator_facing_policy = 'Give Dave the useful answer first, suppress lifecycle and artifact internals unless explicitly requested, and keep default voice turns short.'
}

$outputAbs = Resolve-RepoPath -PathValue $OutputPath
$jsonOut = Write-Utf8NoBomJson -PathValue $outputAbs -Payload $payload
if ($EmitJson) {
    $jsonOut | Write-Output
}
if ($payload.status -eq 'blocked_with_evidence') {
    exit 2
}
