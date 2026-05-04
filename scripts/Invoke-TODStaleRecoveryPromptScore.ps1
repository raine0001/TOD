param(
    [string]$RunDir,
    [string]$CanonicalObjectiveId = '152',
    [int]$Top = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 25
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function Get-LatestRunDir {
    $baseDir = Join-Path $repoRoot 'tod/out/training'
    $dirs = Get-ChildItem -Path $baseDir -Directory -Filter 'stale-recovery-direct-*' | Sort-Object LastWriteTimeUtc -Descending
    if (@($dirs).Count -eq 0) {
        throw 'No stale recovery direct run directories were found.'
    }

    return $dirs[0].FullName
}

function Add-Reason {
    param(
        [System.Collections.Generic.List[string]]$Reasons,
        [string]$Reason
    )

    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        $Reasons.Add($Reason) | Out-Null
    }
}

function Get-SafeNestedValue {
    param(
        $InputObject,
        [string[]]$PropertyPath,
        $Default = ''
    )

    $current = $InputObject
    foreach ($segment in $PropertyPath) {
        if ($null -eq $current) {
            return $Default
        }

        $property = $current.PSObject.Properties[$segment]
        if ($null -eq $property) {
            return $Default
        }

        $current = $property.Value
    }

    return $current
}

function Get-ScoreCard {
    param(
        $Item,
        [string]$CanonicalObjectiveId
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    $score = 0
    $replyText = [string]$Item.reply_text
    $source = [string]$Item.source
    $providerDetail = [string]$Item.provider_status.detail
    $initiativeObjective = [string](Get-SafeNestedValue -InputObject $Item -PropertyPath @('raw_response', 'initiative', 'objective_id') -Default '')
    $activeTask = [string]$Item.active_task
    $nextAction = [string]$Item.next_action
    $canonicalObjective = [string](Get-SafeNestedValue -InputObject $Item -PropertyPath @('raw_response', 'canonical_context', 'objective_id') -Default '')

    if ([string]::Equals($source, 'bounded_fallback', [System.StringComparison]::OrdinalIgnoreCase)) {
        $score += 25
        Add-Reason -Reasons $reasons -Reason 'bounded_fallback_reply'
    }

    if ($providerDetail -match 'timed out') {
        $score += 20
        Add-Reason -Reasons $reasons -Reason 'provider_timeout'
    }

    if (([string]$initiativeObjective -eq '170') -or ($replyText -match 'objective 170|objective-170')) {
        $score += 35
        Add-Reason -Reasons $reasons -Reason 'stale_objective_170_reference'
    }

    if (-not [string]::IsNullOrWhiteSpace($canonicalObjective) -and $canonicalObjective -eq $CanonicalObjectiveId -and (([string]$initiativeObjective -eq '170') -or ($replyText -match 'objective 170|objective-170'))) {
        $score += 20
        Add-Reason -Reasons $reasons -Reason 'canonical_objective_mismatch'
    }

    if ($activeTask -match 'Refresh Governance Snapshot') {
        $score += 15
        Add-Reason -Reasons $reasons -Reason 'stale_active_task_refresh_governance_snapshot'
    }

    if ($nextAction -match 'Run canonical-only validation pass') {
        $score += 10
        Add-Reason -Reasons $reasons -Reason 'stale_next_action_canonical_validation_pass'
    }

    if ($replyText -match 'I know I am talking to Operator|I know I''m talking to Operator') {
        $score += 5
        Add-Reason -Reasons $reasons -Reason 'low_value_memory_repetition'
    }

    if ($replyText -notmatch 'next step|next action|bounded step|repair|artifact|blocker') {
        $score += 10
        Add-Reason -Reasons $reasons -Reason 'missing_actionable_recovery_language'
    }

    $severity = if ($score -ge 70) { 'critical' } elseif ($score -ge 45) { 'major' } elseif ($score -ge 25) { 'moderate' } else { 'minor' }

    return [pscustomobject]@{
        score = $score
        severity = $severity
        reasons = @($reasons)
    }
}

$resolvedRunDir = if ([string]::IsNullOrWhiteSpace($RunDir)) { Get-LatestRunDir } else { Resolve-RepoPath -PathValue $RunDir }
$itemsDir = Join-Path $resolvedRunDir 'items'
if (-not (Test-Path -Path $itemsDir -PathType Container)) {
    throw "Items directory not found: $itemsDir"
}

$items = @(Get-ChildItem -Path $itemsDir -Filter '*.json' | Sort-Object Name | ForEach-Object {
    Get-Content -Path $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
})

$scoredItems = @($items | ForEach-Object {
    $scoreCard = Get-ScoreCard -Item $_ -CanonicalObjectiveId $CanonicalObjectiveId
    [pscustomobject]@{
        id = [string]$_.id
        task_number = [int]$_.task_number
        title = [string]$_.title
        prompt = [string]$_.prompt
        source = [string]$_.source
        score = [int]$scoreCard.score
        severity = [string]$scoreCard.severity
        reasons = @($scoreCard.reasons)
        active_task = [string]$_.active_task
        next_action = [string]$_.next_action
        initiative_objective_id = [string](Get-SafeNestedValue -InputObject $_ -PropertyPath @('raw_response', 'initiative', 'objective_id') -Default '')
        canonical_objective_id = [string](Get-SafeNestedValue -InputObject $_ -PropertyPath @('raw_response', 'canonical_context', 'objective_id') -Default '')
        provider_detail = [string]$_.provider_status.detail
        reply_text = [string]$_.reply_text
    }
})

$ranked = @($scoredItems | Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = 'task_number'; Descending = $false })
$topRanked = @($ranked | Select-Object -First $Top)

$regressionCandidates = @($topRanked | ForEach-Object {
    [pscustomobject]@{
        id = [string]$_.id
        task_number = [int]$_.task_number
        title = [string]$_.title
        severity = [string]$_.severity
        score = [int]$_.score
        reasons = @($_.reasons)
        suggested_test_name = ('rejects-stale-recovery-pattern-{0:d3}' -f [int]$_.task_number)
        prompt = [string]$_.prompt
        expected_contract = @(
            'must anchor to canonical objective 152 when available',
            'must avoid stale objective 170 language',
            'must produce one actionable next step',
            'must preserve blocker specificity when degraded'
        )
    }
})

$summary = [pscustomobject]@{
    ok = $true
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-stale-recovery-score-v1'
    run_dir = $resolvedRunDir
    item_count = @($items).Count
    critical_count = @($ranked | Where-Object { $_.severity -eq 'critical' }).Count
    major_count = @($ranked | Where-Object { $_.severity -eq 'major' }).Count
    moderate_count = @($ranked | Where-Object { $_.severity -eq 'moderate' }).Count
    minor_count = @($ranked | Where-Object { $_.severity -eq 'minor' }).Count
    top_candidates = @($regressionCandidates)
}

$scorePath = Join-Path $resolvedRunDir 'scorecard.json'
$regressionPath = Join-Path $resolvedRunDir 'regression_candidates.json'
$reportPath = Join-Path $resolvedRunDir 'scorecard.md'

Write-JsonNoBom -PathValue $scorePath -Payload $summary -Depth 25
Write-JsonNoBom -PathValue $regressionPath -Payload $regressionCandidates -Depth 25

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# TOD Stale Recovery Scorecard') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('Generated at: {0}' -f $summary.generated_at)) | Out-Null
$lines.Add(('Run dir: {0}' -f $resolvedRunDir)) | Out-Null
$lines.Add(('Critical: {0} | Major: {1} | Moderate: {2} | Minor: {3}' -f $summary.critical_count, $summary.major_count, $summary.moderate_count, $summary.minor_count)) | Out-Null
$lines.Add('') | Out-Null

foreach ($candidate in $regressionCandidates) {
    $lines.Add(('## {0}. {1}' -f [int]$candidate.task_number, [string]$candidate.title)) | Out-Null
    $lines.Add(('Severity: {0} | Score: {1}' -f [string]$candidate.severity, [int]$candidate.score)) | Out-Null
    $lines.Add(('Reasons: {0}' -f ((@($candidate.reasons) -join ', ')))) | Out-Null
    $lines.Add(('Suggested test: {0}' -f [string]$candidate.suggested_test_name)) | Out-Null
    $lines.Add('') | Out-Null
}

[System.IO.File]::WriteAllLines($reportPath, $lines, (New-Object System.Text.UTF8Encoding($false)))

$summary | ConvertTo-Json -Depth 25