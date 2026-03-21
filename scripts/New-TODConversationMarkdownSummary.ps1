param(
    [ValidateSet("auto", "pr", "nightly", "drift-lock-soak")]
    [string]$Kind = "auto",
    [string]$InputPath = "",
    [string]$OutputPath = "",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return "" }
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Get-ScenarioFamilies {
    param([string[]]$ScenarioIds)

    $families = @()
    foreach ($id in @($ScenarioIds)) {
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        switch -Regex ($id) {
            '^REL-|^CON-|^SAF-|^MEM-|^TASK-' { $families += 'replay-lock'; break }
            '^ENG-' { $families += 'engineering'; break }
            '^MESS-' { $families += 'messy'; break }
            '^BRG-' { $families += 'bridge'; break }
            '^OPR-' { $families += 'operator-friction'; break }
            default { $families += 'mixed' }
        }
    }

    return (@($families | Select-Object -Unique) -join ', ')
}

function Get-TopTagSummary {
    param($TagObjects)

    $items = @($TagObjects | ForEach-Object {
            if ($_.PSObject.Properties['tag']) {
                '{0} ({1})' -f [string]$_.tag, [int]$_.count
            }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if (@($items).Count -eq 0) { return 'none' }
    return ($items -join ', ')
}

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    switch ($Kind) {
        'pr' { $InputPath = 'shared_state/conversation_eval/conversation_score_report.pr.latest.json' }
        'nightly' { $InputPath = 'shared_state/conversation_eval/conversation_score_report.nightly.latest.json' }
        'drift-lock-soak' { $InputPath = 'shared_state/conversation_eval/drift_lock_soak/drift_lock_soak.latest.json' }
    }
}

$inputAbs = Resolve-LocalPath -PathValue $InputPath
if (-not (Test-Path -Path $inputAbs)) {
    throw "Input report not found: $inputAbs"
}

$doc = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
if ($Kind -eq 'auto') {
    switch ([string]$doc.source) {
        'tod-conversation-eval-pr-v1' { $Kind = 'pr' }
        'tod-conversation-eval-nightly-v1' { $Kind = 'nightly' }
        'tod-drift-lock-soak-v1' { $Kind = 'drift-lock-soak' }
        default { throw "Unable to infer markdown summary kind from source: $($doc.source)" }
    }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputAbs)
    $OutputPath = Join-Path ([System.IO.Path]::GetDirectoryName($inputAbs)) ($baseName + '.md')
}

$outputAbs = Resolve-LocalPath -PathValue $OutputPath
$lines = @('# TOD Conversation Report', '')

switch ($Kind) {
    'pr' {
        $promotionStatus = if ([bool]$doc.summary.gate_passed) { 'passed' } else { 'blocked' }
        $nextStep = if ([bool]$doc.summary.gate_passed) { 'Keep drift-lock clean and monitor nightly deltas.' } else { 'Replay the failing gate dimension before merge.' }
        $runId = if ($doc.PSObject.Properties['run_id']) { [string]$doc.run_id } else { 'n/a' }
        $topFailures = if ([bool]$doc.summary.drift_lock_passed) { 'none' } else { 'drift-lock failures present' }
        $driftLockStatus = if ([bool]$doc.summary.drift_lock_passed) { 'passed' } else { 'failed' }
        $lines += '- Run id: {0}' -f $runId
        $lines += '- Scenario family: smoke, expanded, replay-lock'
        $lines += '- Early/mid/late overall: n/a'
        $lines += '- Early/mid/late utility: n/a'
        $lines += '- Overall score: {0}' -f ([double]$doc.summary.overall_score)
        $lines += '- Developer utility: {0}' -f ([double]$doc.summary.developer_utility)
        $lines += '- Top failure tags: {0}' -f $topFailures
        $lines += '- Drift-lock status: {0}' -f $driftLockStatus
        $lines += '- Promotion status: {0}' -f $promotionStatus
        $lines += '- Recommended next step: {0}' -f $nextStep
    }
    'nightly' {
        $promotionStatus = if ($doc.summary.PSObject.Properties['delta_vs_baseline'] -and $null -ne $doc.summary.delta_vs_baseline -and [double]$doc.summary.delta_vs_baseline -ge 0) { 'stable_or_improving' } else { 'watch' }
        $nextStep = if ($promotionStatus -eq 'stable_or_improving') { 'Continue nightly monitoring and preserve the current baseline.' } else { 'Hold baseline changes and inspect the nightly delta.' }
        $runId = if ($doc.PSObject.Properties['run_id']) { [string]$doc.run_id } else { 'n/a' }
        $developerUtility = if ($doc.summary.PSObject.Properties['developer_utility']) { [double]$doc.summary.developer_utility } else { 'n/a' }
        $lines += '- Run id: {0}' -f $runId
        $lines += '- Scenario family: regression'
        $lines += '- Early/mid/late overall: n/a'
        $lines += '- Early/mid/late utility: n/a'
        $lines += '- Overall score: {0}' -f ([double]$doc.summary.overall_score)
        $lines += '- Developer utility: {0}' -f $developerUtility
        $lines += '- Top failure tags: n/a'
        $lines += '- Drift-lock status: n/a'
        $lines += '- Promotion status: {0}' -f $promotionStatus
        $lines += '- Recommended next step: {0}' -f $nextStep
    }
    'drift-lock-soak' {
        $families = Get-ScenarioFamilies -ScenarioIds @($doc.config.scenario_ids)
        $promotionStatus = if ([bool]$doc.summary.promotion_gates.promotion_gate_passed) { 'promotion_ready' } else { 'blocked' }
        $driftLockStatus = if ([bool]$doc.summary.promotion_gates.late_drift_lock_violations_bounded) { 'bounded' } else { 'violations exceeded bound' }
        $lines += '- Run id: {0}' -f [string]$doc.run_id
        $lines += '- Scenario family: {0}' -f $families
        $lines += '- Early/mid/late overall: {0} / {1} / {2}' -f $doc.summary.windows.early.avg_overall, $doc.summary.windows.mid.avg_overall, $doc.summary.windows.late.avg_overall
        $lines += '- Early/mid/late utility: {0} / {1} / {2}' -f $doc.summary.windows.early.avg_developer_utility, $doc.summary.windows.mid.avg_developer_utility, $doc.summary.windows.late.avg_developer_utility
        $lines += '- Top failure tags: {0}' -f (Get-TopTagSummary -TagObjects $doc.summary.top_failure_clusters)
        $lines += '- Drift-lock status: {0}' -f $driftLockStatus
        $lines += '- Promotion status: {0}' -f $promotionStatus
        $lines += '- Recommended next step: {0}' -f [string]$doc.summary.recommended_next_step
    }
}

$outDir = Split-Path -Parent $outputAbs
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$markdown = ($lines -join [Environment]::NewLine)
$markdown | Set-Content -Path $outputAbs

$result = [pscustomobject]@{
    kind = $Kind
    input_path = $inputAbs
    output_path = $outputAbs
}

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 6 | Write-Output
}
else {
    $result
}