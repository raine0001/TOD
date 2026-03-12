param(
    [string]$StatePath = "tod/data/state.json",
    [string]$OutputPath = "shared_state/approval_reduction_summary.json",
    [string]$DevJournalPath = "shared_state/dev_journal.jsonl",
    [int]$Top = 15,
    [switch]$WriteOutputs,
    [switch]$AppendJournal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Convert-ToUtcDateOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try {
        return ([datetime]$Value).ToUniversalTime()
    }
    catch {
        return $null
    }
}

function Get-PendingApprovals {
    param([Parameter(Mandatory = $true)]$State)

    if (-not $State.PSObject.Properties["engineering_loop"] -or -not $State.engineering_loop) {
        return @()
    }
    if (-not $State.engineering_loop.PSObject.Properties["cycle_records"] -or $null -eq $State.engineering_loop.cycle_records) {
        return @()
    }

    return @($State.engineering_loop.cycle_records | Where-Object {
            ($_.PSObject.Properties["approval_pending"] -and [bool]$_.approval_pending) -or
            ($_.PSObject.Properties["approval_status"] -and ([string]$_.approval_status).ToLowerInvariant() -eq "pending_apply")
        })
}

$stateAbs = Get-LocalPath -PathValue $StatePath
if (-not (Test-Path -Path $stateAbs)) {
    throw "State file not found: $stateAbs"
}

$state = Get-Content -Path $stateAbs -Raw | ConvertFrom-Json
$pending = Get-PendingApprovals -State $state
$now = (Get-Date).ToUniversalTime()

$byKey = @{}
$promotable = @()
$nonLowValue = @()
$lowValue = @()

foreach ($item in $pending) {
    $objectiveId = if ($item.PSObject.Properties["objective_id"]) { [string]$item.objective_id } else { "" }
    $taskId = if ($item.PSObject.Properties["task_id"]) { [string]$item.task_id } else { "" }
    $status = if ($item.PSObject.Properties["approval_status"] -and -not [string]::IsNullOrWhiteSpace([string]$item.approval_status)) {
        ([string]$item.approval_status).ToLowerInvariant()
    }
    else {
        "pending_apply"
    }

    $score = $null
    if ($item.PSObject.Properties["score_snapshot"] -and $item.score_snapshot -and $item.score_snapshot.PSObject.Properties["overall"] -and $item.score_snapshot.overall -and $item.score_snapshot.overall.PSObject.Properties["score"] -and $null -ne $item.score_snapshot.overall.score) {
        $score = [double]$item.score_snapshot.overall.score
    }

    $band = if ($item.PSObject.Properties["maturity_band"]) { ([string]$item.maturity_band).ToLowerInvariant() } else { "" }
    $source = if ($item.PSObject.Properties["task_category"] -and -not [string]::IsNullOrWhiteSpace([string]$item.task_category)) {
        "task_category:{0}" -f [string]$item.task_category
    }
    elseif (-not [string]::IsNullOrWhiteSpace($objectiveId)) {
        "objective:{0}" -f $objectiveId
    }
    else {
        "engineering_loop"
    }

    $recordId = if ($item.PSObject.Properties["cycle_id"] -and -not [string]::IsNullOrWhiteSpace([string]$item.cycle_id)) {
        [string]$item.cycle_id
    }
    elseif ($item.PSObject.Properties["run_id"] -and -not [string]::IsNullOrWhiteSpace([string]$item.run_id)) {
        [string]$item.run_id
    }
    else {
        [guid]::NewGuid().ToString()
    }

    $createdAt = if ($item.PSObject.Properties["created_at"]) { Convert-ToUtcDateOrNull -Value ([string]$item.created_at) } else { $null }
    $updatedAt = if ($item.PSObject.Properties["updated_at"]) { Convert-ToUtcDateOrNull -Value ([string]$item.updated_at) } else { $null }
    $anchor = if ($null -ne $createdAt) { $createdAt } else { $updatedAt }
    $ageHours = if ($null -ne $anchor) { [math]::Round(($now - $anchor).TotalHours, 2) } else { $null }

    $isPromotable = ($band -in @("good", "strong") -and $null -ne $score -and $score -ge 0.65)
    $isLowValue = ($band -in @("early", "emerging") -or ($null -ne $score -and $score -lt 0.45))

    $row = [pscustomobject]@{
        id = $recordId
        objective_id = $objectiveId
        task_id = $taskId
        status = $status
        source = $source
        maturity_band = $band
        score = if ($null -ne $score) { [math]::Round($score, 4) } else { $null }
        age_hours = $ageHours
    }

    if ($isPromotable) {
        $promotable += $row
    }
    if ($isLowValue) {
        $lowValue += $row
    }
    else {
        $nonLowValue += $row
    }

    # Group near-duplicates by objective/task/status/band/score bucket.
    $scoreBucket = if ($null -eq $score) { "na" } else { [math]::Round([double]$score, 1).ToString("0.0") }
    $dupKey = "{0}|{1}|{2}|{3}|{4}" -f $objectiveId, $taskId, $status, $band, $scoreBucket
    if (-not $byKey.ContainsKey($dupKey)) {
        $byKey[$dupKey] = @()
    }
    $byKey[$dupKey] = @($byKey[$dupKey]) + @($row)
}

$duplicateGroups = @()
foreach ($entry in $byKey.GetEnumerator()) {
    $group = @($entry.Value)
    if (@($group).Count -gt 1) {
        $duplicateGroups += [pscustomobject]@{
            signature = [string]$entry.Key
            count = [int]@($group).Count
            ids = @($group | ForEach-Object { [string]$_.id })
            objective_id = [string]$group[0].objective_id
            task_id = [string]$group[0].task_id
            status = [string]$group[0].status
            maturity_band = [string]$group[0].maturity_band
            score = $group[0].score
        }
    }
}

$duplicateGroups = @($duplicateGroups | Sort-Object -Property count -Descending)
$promotableQueue = @($promotable | Sort-Object @{ Expression = { if ($null -eq $_.score) { 0.0 } else { [double]$_.score } }; Descending = $true }, @{ Expression = { if ($null -eq $_.age_hours) { 0.0 } else { [double]$_.age_hours } }; Descending = $true })
$lowValueQueue = @($lowValue | Sort-Object @{ Expression = { if ($null -eq $_.score) { 0.0 } else { [double]$_.score } }; Descending = $false }, @{ Expression = { if ($null -eq $_.age_hours) { 0.0 } else { [double]$_.age_hours } }; Descending = $true })

$duplicateSuppressionCandidates = @()
foreach ($group in $duplicateGroups) {
    $matchingRows = @($lowValueQueue | Where-Object { @($group.ids) -contains [string]$_.id })
    if (@($matchingRows).Count -gt 1) {
        $canonical = @($matchingRows | Sort-Object @{ Expression = { if ($null -eq $_.score) { 0.0 } else { [double]$_.score } }; Descending = $true }, @{ Expression = { if ($null -eq $_.age_hours) { 0.0 } else { [double]$_.age_hours } }; Descending = $false } | Select-Object -First 1)
        $toSuppress = @($matchingRows | Where-Object { [string]$_.id -ne [string]$canonical[0].id })
        if (@($toSuppress).Count -gt 0) {
            $duplicateSuppressionCandidates += [pscustomobject]@{
                group_signature = [string]$group.signature
                canonical_id = [string]$canonical[0].id
                suppress_ids = @($toSuppress | ForEach-Object { [string]$_.id })
                objective_id = [string]$group.objective_id
                task_id = [string]$group.task_id
                count = [int]@($toSuppress).Count
            }
        }
    }
}

$result = [pscustomobject]@{
    ok = $true
    generated_at = $now.ToString("o")
    source = "tod-approval-reduction-pass-v1"
    policy = [pscustomobject]@{
        mode = "analyze_only"
        preserve_non_low_value = $true
        suppression_rule = "only low-value duplicate groups are suppression candidates"
        promotion_rule = "promotable queue sorted by score desc then age desc"
    }
    totals = [pscustomobject]@{
        pending = [int]@($pending).Count
        promotable = [int]@($promotableQueue).Count
        low_value = [int]@($lowValueQueue).Count
        non_low_value = [int]@($nonLowValue).Count
        duplicate_groups = [int]@($duplicateGroups).Count
        duplicate_suppression_candidates = [int]@($duplicateSuppressionCandidates).Count
    }
    queues = [pscustomobject]@{
        promotable_first = @($promotableQueue | Select-Object -First $Top)
        low_value_review = @($lowValueQueue | Select-Object -First $Top)
        duplicate_groups = @($duplicateGroups | Select-Object -First $Top)
        duplicate_suppression_candidates = @($duplicateSuppressionCandidates | Select-Object -First $Top)
    }
    audit = [pscustomobject]@{
        preserved_non_low_value_count = [int]@($nonLowValue).Count
        non_low_value_sample = @($nonLowValue | Select-Object -First ([math]::Min(10, $Top)))
    }
    recommended_next_steps = @(
        "Apply promotable approvals first in descending score order.",
        "Review low-value queue and suppress only duplicate candidates.",
        "Keep all non-low-value pending approvals untouched unless explicitly reviewed."
    )
}

if ($WriteOutputs) {
    $outAbs = Get-LocalPath -PathValue $OutputPath
    $outDir = Split-Path -Parent $outAbs
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 20 | Set-Content -Path $outAbs

    if ($AppendJournal) {
        $journalAbs = Get-LocalPath -PathValue $DevJournalPath
        $journalDir = Split-Path -Parent $journalAbs
        if (-not [string]::IsNullOrWhiteSpace($journalDir) -and -not (Test-Path -Path $journalDir)) {
            New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        }

        $entry = [pscustomobject]@{
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
            machine = $env:COMPUTERNAME
            repo = "TOD"
            action = "approval_reduction_pass"
            summary = "Analyzed pending approvals and generated promotable/low-value/duplicate queues."
            reduction_summary_path = $outAbs
            totals = $result.totals
        }
        ($entry | ConvertTo-Json -Depth 12) + [Environment]::NewLine | Add-Content -Path $journalAbs
    }
}

$result | ConvertTo-Json -Depth 20 | Write-Output
