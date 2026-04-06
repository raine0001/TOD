param(
    [switch]$AsJson,
    [string]$StatePath,
    [Nullable[int64]]$MaxStateReadBytes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerStagePath = Join-Path $repoRoot "tod/out/context-sync/listener"
$listenerJournalPath = Join-Path $listenerStagePath "TOD_LOOP_JOURNAL.latest.json"
$listenerResultPath = Join-Path $listenerStagePath "TOD_MIM_TASK_RESULT.latest.json"
$listenerRequestPath = Join-Path $listenerStagePath "MIM_TOD_TASK_REQUEST.latest.json"
$listenerCommandStatusPath = Join-Path $listenerStagePath "TOD_MIM_COMMAND_STATUS.latest.json"
$listenerStatePath = Join-Path $listenerStagePath "listener_state.json"
$coordinationEscalationPath = Join-Path $listenerStagePath "TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json"
$regressionStallStatePath = Join-Path $listenerStagePath "TOD_REGRESSION_STALL_STATE.latest.json"
$currentBuildStatePath = Join-Path $repoRoot "shared_state/current_build_state.json"
$recoveryWatchdogStatePath = Join-Path $repoRoot "shared_state/tod_recovery_watchdog.latest.json"
$statePath = if ([string]::IsNullOrWhiteSpace($StatePath)) {
    Join-Path $repoRoot "tod/data/state.json"
}
elseif ([System.IO.Path]::IsPathRooted($StatePath)) {
    [System.IO.Path]::GetFullPath($StatePath)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $StatePath))
}
$maxStateReadBytes = if ($null -ne $MaxStateReadBytes -and [int64]$MaxStateReadBytes -gt 0) { [int64]$MaxStateReadBytes } else { [int64]256MB }
$watchdogStaleSkewSeconds = 300

function Read-JsonFileIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path)) {
        return $null
    }

    try {
        return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-ObjectiveIdFromRequestId {
    param([string]$RequestId)

    if ([string]::IsNullOrWhiteSpace($RequestId)) {
        return ""
    }

    $match = [regex]::Match([string]$RequestId, '^objective-(?<objective>\d+)-task-.+$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return ""
    }

    return [string]$match.Groups['objective'].Value
}

function Get-TaskRefInfo {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $match = [regex]::Match([string]$Value, '^objective-(?<objective>\d+)-task-(?<tail>.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    $ordinalMatch = [regex]::Match([string]$match.Groups['tail'].Value, '(?<task>\d+)(?!.*\d)')
    if (-not $ordinalMatch.Success) {
        return $null
    }

    return [pscustomobject]@{
        objective = [string]$match.Groups['objective'].Value
        task_number = [long]$ordinalMatch.Groups['task'].Value
        raw = [string]$Value
    }
}

function Convert-ToDateTimeOffsetOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    try {
        return [DateTimeOffset]::Parse([string]$Value)
    }
    catch {
        return $null
    }
}

function Get-IsoAgeSeconds {
    param([string]$Value)

    $parsed = Convert-ToDateTimeOffsetOrNull -Value $Value
    if ($null -eq $parsed) {
        return -1
    }

    return [int][Math]::Max(0, ([DateTimeOffset]::UtcNow - $parsed.ToUniversalTime()).TotalSeconds)
}

function Get-PercentileValue {
    param(
        [double[]]$Values,
        [double]$Percentile
    )

    if ($null -eq $Values -or $Values.Count -eq 0) {
        return 0.0
    }

    $sorted = @($Values | Sort-Object)
    $index = [int][math]::Floor(($Percentile / 100.0) * ([double]($sorted.Count - 1)))
    if ($index -lt 0) { $index = 0 }
    if ($index -ge $sorted.Count) { $index = $sorted.Count - 1 }
    return [math]::Round([double]$sorted[$index], 1)
}

function Get-TaskProgressWeight {
    param([string]$Status)

    $normalized = ([string]$Status).Trim().ToLowerInvariant()
    switch ($normalized) {
        'pass' { return 1.0 }
        'reviewed_pass' { return 1.0 }
        'done' { return 1.0 }
        'completed' { return 1.0 }
        'implemented' { return 0.75 }
        'in_progress' { return 0.5 }
        'active' { return 0.5 }
        'revise' { return 0.35 }
        'planned' { return 0.15 }
        'open' { return 0.1 }
        default { return 0.0 }
    }
}

function Get-ListenerActivity {
    $journal = Read-JsonFileIfExists -Path $listenerJournalPath
    $resultPacket = Read-JsonFileIfExists -Path $listenerResultPath
    $requestPacket = Read-JsonFileIfExists -Path $listenerRequestPath
    $commandStatusPacket = Read-JsonFileIfExists -Path $listenerCommandStatusPath

    $entries = @()
    if ($journal -and $journal.PSObject.Properties['entries']) {
        $entries = @($journal.entries)
    }
    elseif ($journal -is [System.Array]) {
        $entries = @($journal)
    }

    $bridgeCurrentTaskId = ""
    if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['bridge_runtime'] -and $commandStatusPacket.bridge_runtime -and $commandStatusPacket.bridge_runtime.PSObject.Properties['current_processing'] -and $commandStatusPacket.bridge_runtime.current_processing -and $commandStatusPacket.bridge_runtime.current_processing.PSObject.Properties['task_id']) {
        $bridgeCurrentTaskId = [string]$commandStatusPacket.bridge_runtime.current_processing.task_id
    }
    $bridgeCurrentRef = Get-TaskRefInfo -Value $bridgeCurrentTaskId

    $normalizedEntries = @()
    foreach ($entry in $entries) {
        $requestId = if ($entry.PSObject.Properties['request_id']) { [string]$entry.request_id } else { "" }
        $objectiveId = if ($entry.PSObject.Properties['objective_id']) { [string]$entry.objective_id } else { "" }
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            $objectiveId = Get-ObjectiveIdFromRequestId -RequestId $requestId
        }

        $entryExecutionStatus = if ($entry.PSObject.Properties['execution_status']) { [string]$entry.execution_status } else { 'unknown' }
        $entryRequestRef = Get-TaskRefInfo -Value $requestId
        if (
            $entryRequestRef -and
            $bridgeCurrentRef -and
            [string]::Equals([string]$entryRequestRef.objective, [string]$bridgeCurrentRef.objective, [System.StringComparison]::OrdinalIgnoreCase) -and
            [long]$entryRequestRef.task_number -lt [long]$bridgeCurrentRef.task_number -and
            @('stale_backfill_ignored', 'stale_request_ignored') -contains $entryExecutionStatus.Trim().ToLowerInvariant()
        ) {
            continue
        }

        $normalizedEntries += [pscustomobject]@{
            timestamp = if ($entry.PSObject.Properties['timestamp']) { [string]$entry.timestamp } else { "" }
            request_id = $requestId
            objective_id = $objectiveId
            execution_status = $entryExecutionStatus
        }
    }

    $requestExecutionStats = [ordered]@{}
    foreach ($entry in $normalizedEntries) {
        $objectiveId = [string]$entry.objective_id
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            continue
        }

        $requestKey = [string]$entry.request_id
        if ([string]::IsNullOrWhiteSpace($requestKey)) {
            $requestKey = ('__entry__|' + [string]$entry.timestamp + '|' + [guid]::NewGuid().ToString('N'))
        }

        $aggregateKey = "$objectiveId|$requestKey"
        $rawStatus = ([string]$entry.execution_status).Trim().ToLowerInvariant()
        $mappedStatus = switch ($rawStatus) {
            'succeeded' { 'completed' }
            'pass' { 'completed' }
            'reviewed_pass' { 'completed' }
            'done' { 'completed' }
            'completed' { 'completed' }
            'already_processed' { 'completed' }
            'in_progress' { 'in_progress' }
            'active' { 'in_progress' }
            'running' { 'in_progress' }
            'failed' { 'failed' }
            'contract_violation_rejected' { 'failed' }
            'quarantined' { 'failed' }
            'invalid_request' { 'failed' }
            default { '' }
        }
        if ([string]::IsNullOrWhiteSpace($mappedStatus)) {
            continue
        }

        if (-not $requestExecutionStats.Contains($aggregateKey)) {
            $requestExecutionStats[$aggregateKey] = [ordered]@{
                objective_id = $objectiveId
                request_id = [string]$entry.request_id
                execution_status = $mappedStatus
                raw_execution_status = [string]$entry.execution_status
                timestamp = [string]$entry.timestamp
            }
            continue
        }

        $aggregate = $requestExecutionStats[$aggregateKey]
        if ($rawStatus -ne 'already_processed') {
            $aggregate.execution_status = $mappedStatus
            $aggregate.raw_execution_status = [string]$entry.execution_status
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$aggregate.raw_execution_status)) {
            $aggregate.execution_status = $mappedStatus
            $aggregate.raw_execution_status = [string]$entry.execution_status
        }

        $aggregate.timestamp = [string]$entry.timestamp
    }

    $aggregatedEntries = @($requestExecutionStats.Values | ForEach-Object {
            [pscustomobject]@{
                objective_id = [string]$_.objective_id
                request_id = [string]$_.request_id
                execution_status = [string]$_.execution_status
                raw_execution_status = [string]$_.raw_execution_status
                timestamp = [string]$_.timestamp
            }
        })

    $objectiveStats = @{}
    foreach ($entry in $aggregatedEntries) {
        $statusKey = ([string]$entry.execution_status).Trim().ToLowerInvariant()
        if (@('completed', 'failed', 'in_progress') -notcontains $statusKey) {
            continue
        }

        $objectiveId = [string]$entry.objective_id
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            continue
        }

        if (-not $objectiveStats.ContainsKey($objectiveId)) {
            $objectiveStats[$objectiveId] = [ordered]@{
                total = 0
                completed = 0
                failed = 0
                in_progress = 0
                progress_units = 0.0
                last_request_id = ""
                last_execution_status = ""
                last_timestamp = ""
            }
        }

        $stats = $objectiveStats[$objectiveId]
        $stats.total = [int]$stats.total + 1
        $status = [string]$entry.execution_status
        if ($statusKey -eq 'completed') {
            $stats.completed = [int]$stats.completed + 1
        }
        elseif ($statusKey -eq 'failed') {
            $stats.failed = [int]$stats.failed + 1
        }
        elseif ($statusKey -eq 'in_progress') {
            $stats.in_progress = [int]$stats.in_progress + 1
        }

        $stats.progress_units = [double]$stats.progress_units + (Get-TaskProgressWeight -Status $status)
        $stats.last_request_id = [string]$entry.request_id
        $stats.last_execution_status = $status
        $stats.last_timestamp = [string]$entry.timestamp
    }

    $latest = if (@($normalizedEntries).Count -gt 0) { @($normalizedEntries)[-1] } else { $null }
    $effectiveLatest = $latest
    $effectiveLatestRef = $null
    foreach ($entry in $normalizedEntries) {
        $entryRef = Get-TaskRefInfo -Value ([string]$entry.request_id)
        if ($null -eq $entryRef) {
            continue
        }

        if ($null -eq $effectiveLatestRef -or [long]$entryRef.task_number -gt [long]$effectiveLatestRef.task_number) {
            $effectiveLatest = $entry
            $effectiveLatestRef = $entryRef
        }
    }
    if ($bridgeCurrentRef -and ($null -eq $effectiveLatestRef -or [long]$bridgeCurrentRef.task_number -gt [long]$effectiveLatestRef.task_number)) {
        $effectiveLatest = [pscustomobject]@{
            timestamp = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['generated_at']) { [string]$commandStatusPacket.generated_at } else { "" }
            request_id = [string]$bridgeCurrentTaskId
            objective_id = [string]$bridgeCurrentRef.objective
            execution_status = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['status']) { [string]$commandStatusPacket.status } else { "" }
        }
        $effectiveLatestRef = $bridgeCurrentRef
    }
    $commandStatusValue = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['status']) { ([string]$commandStatusPacket.status).Trim().ToLowerInvariant() } else { '' }
    $commandStatusGeneratedAt = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['generated_at']) { [string]$commandStatusPacket.generated_at } else { '' }
    $commandStatusTs = Convert-ToDateTimeOffsetOrNull -Value $commandStatusGeneratedAt
    $effectiveLatestTs = if ($effectiveLatest) { Convert-ToDateTimeOffsetOrNull -Value ([string]$effectiveLatest.timestamp) } else { $null }
    if (
        $bridgeCurrentRef -and
        $null -ne $commandStatusTs -and
        ($null -eq $effectiveLatestRef -or [long]$bridgeCurrentRef.task_number -ge [long]$effectiveLatestRef.task_number) -and
        ($null -eq $effectiveLatestTs -or $commandStatusTs -gt $effectiveLatestTs)
    ) {
        $effectiveLatest = [pscustomobject]@{
            timestamp = $commandStatusGeneratedAt
            request_id = [string]$bridgeCurrentTaskId
            objective_id = [string]$bridgeCurrentRef.objective
            execution_status = $commandStatusValue
        }
        $effectiveLatestRef = $bridgeCurrentRef
    }
    $recentEntries = @($normalizedEntries | Select-Object -Last 30)
    $resultRequestId = if ($null -ne $effectiveLatest) { [string]$effectiveLatest.request_id } elseif ($resultPacket -and $resultPacket.PSObject.Properties['request_id']) { [string]$resultPacket.request_id } else { "" }
    $resultRef = if ($null -ne $effectiveLatest) { Get-TaskRefInfo -Value ([string]$effectiveLatest.request_id) } else { Get-TaskRefInfo -Value $resultRequestId }
    $requestTaskId = if ($requestPacket -and $requestPacket.PSObject.Properties['task_id']) { [string]$requestPacket.task_id } else { "" }
    $requestRef = Get-TaskRefInfo -Value $requestTaskId
    $requestSyncRef = $requestRef
    if ([string]::Equals($commandStatusValue, 'stale_request_ignored', [System.StringComparison]::OrdinalIgnoreCase) -and $bridgeCurrentRef -and $requestSyncRef) {
        if ([string]::Equals([string]$bridgeCurrentRef.objective, [string]$requestSyncRef.objective, [System.StringComparison]::OrdinalIgnoreCase) -and [long]$requestSyncRef.task_number -lt [long]$bridgeCurrentRef.task_number) {
            $requestSyncRef = $bridgeCurrentRef
        }
    }
    $isMimAhead = $false
    $pendingCount = 0
    if ($requestSyncRef -and $resultRef) {
        if ([string]$requestSyncRef.objective -eq [string]$resultRef.objective -and [long]$requestSyncRef.task_number -gt [long]$resultRef.task_number) {
            $isMimAhead = $true
            $pendingCount = [long]$requestSyncRef.task_number - [long]$resultRef.task_number
        }
    }
    elseif ($requestSyncRef -and -not $resultRef) {
        $isMimAhead = $true
        $pendingCount = [long]$requestSyncRef.task_number
    }

    return [pscustomobject]@{
        entry_count = @($normalizedEntries).Count
        latest_objective_id = if ($effectiveLatest) { [string]$effectiveLatest.objective_id } else { "" }
        latest_request_id = if ($effectiveLatest) { [string]$effectiveLatest.request_id } else { "" }
        latest_execution_status = if ($effectiveLatest) { [string]$effectiveLatest.execution_status } else { "" }
        latest_timestamp = if ($effectiveLatest) { [string]$effectiveLatest.timestamp } else { "" }
        result_request_id = $resultRequestId
        result_generated_at = if ($resultPacket -and $resultPacket.PSObject.Properties['generated_at']) { [string]$resultPacket.generated_at } else { "" }
        request_task_id = $requestTaskId
        request_generated_at = if ($requestPacket -and $requestPacket.PSObject.Properties['generated_at']) { [string]$requestPacket.generated_at } else { "" }
        sync = [pscustomobject]@{
            is_mim_ahead = $isMimAhead
            pending_request_count = $pendingCount
            result_task_number = if ($resultRef) { [long]$resultRef.task_number } else { -1L }
            request_task_number = if ($requestSyncRef) { [long]$requestSyncRef.task_number } else { -1L }
        }
        recent_entries = @($recentEntries)
        objective_stats = [pscustomobject]$objectiveStats
    }
}

function Get-RecoveryWatchdogStatus {
    $doc = Read-JsonFileIfExists -Path $recoveryWatchdogStatePath
    $watchdogItem = if (Test-Path -Path $recoveryWatchdogStatePath) { Get-Item -Path $recoveryWatchdogStatePath } else { $null }
    $listenerItem = if (Test-Path -Path $listenerStatePath) { Get-Item -Path $listenerStatePath } else { $null }
    $requestItem = if (Test-Path -Path $listenerRequestPath) { Get-Item -Path $listenerRequestPath } else { $null }
    $resultItem = if (Test-Path -Path $listenerResultPath) { Get-Item -Path $listenerResultPath } else { $null }
    $nowUtc = (Get-Date).ToUniversalTime()

    $watchdogMtimeUtc = if ($watchdogItem) { $watchdogItem.LastWriteTimeUtc } else { $null }
    $referenceCandidates = @()
    foreach ($candidate in @($listenerItem, $requestItem, $resultItem)) {
        if ($candidate) {
            $referenceCandidates += $candidate.LastWriteTimeUtc
        }
    }

    $referenceLatestUtc = $null
    if (@($referenceCandidates).Count -gt 0) {
        $referenceLatestUtc = @($referenceCandidates | Sort-Object | Select-Object -Last 1)[0]
    }

    $watchdogSkewSeconds = -1
    if ($watchdogMtimeUtc -and $referenceLatestUtc) {
        $watchdogSkewSeconds = [int][Math]::Floor(($referenceLatestUtc - $watchdogMtimeUtc).TotalSeconds)
    }

    $watchdogFileAgeSeconds = -1
    if ($watchdogMtimeUtc) {
        $watchdogFileAgeSeconds = [int][Math]::Floor(($nowUtc - $watchdogMtimeUtc).TotalSeconds)
    }

    $isStale = $false
    $staleReason = 'none'
    if ($watchdogSkewSeconds -ge $watchdogStaleSkewSeconds) {
        $isStale = $true
        $staleReason = 'watchdog_older_than_listener_truth'
    }

    if ($null -eq $doc) {
        return [pscustomobject]@{
            available = $false
            state = 'unknown'
            effective_state = 'unknown'
            stale = $false
            stale_reason = 'missing'
            task_state = 'idle'
            heartbeat_age_seconds = -1
            recovery_attempts = 0
            consecutive_freezes = 0
            file_age_seconds = $watchdogFileAgeSeconds
            watchdog_mtime_utc = if ($watchdogMtimeUtc) { $watchdogMtimeUtc.ToString('o') } else { '' }
            listener_reference_utc = if ($referenceLatestUtc) { $referenceLatestUtc.ToString('o') } else { '' }
            watchdog_skew_seconds = $watchdogSkewSeconds
        }
    }

    $state = if ($doc.PSObject.Properties['state']) { [string]$doc.state } else { 'unknown' }
    return [pscustomobject]@{
        available = $true
        state = $state
        effective_state = if ($isStale) { 'stale' } else { $state }
        stale = $isStale
        stale_reason = $staleReason
        task_state = if ($doc.PSObject.Properties['task_state']) { [string]$doc.task_state } else { 'idle' }
        heartbeat_age_seconds = if ($doc.PSObject.Properties['heartbeat_age_seconds']) { [int]$doc.heartbeat_age_seconds } else { -1 }
        recovery_attempts = if ($doc.PSObject.Properties['recovery_attempts']) { [int]$doc.recovery_attempts } else { 0 }
        consecutive_freezes = if ($doc.PSObject.Properties['consecutive_freezes']) { [int]$doc.consecutive_freezes } else { 0 }
        file_age_seconds = $watchdogFileAgeSeconds
        watchdog_mtime_utc = if ($watchdogMtimeUtc) { $watchdogMtimeUtc.ToString('o') } else { '' }
        listener_reference_utc = if ($referenceLatestUtc) { $referenceLatestUtc.ToString('o') } else { '' }
        watchdog_skew_seconds = $watchdogSkewSeconds
    }
}

function Get-CadenceHealth {
    param(
        $ListenerActivity,
        $RecoveryWatchdog
    )

    if ($null -eq $ListenerActivity) {
        return [pscustomobject]@{
            available = $false
            severity = 'unknown'
            alerts = @('no_listener_activity')
            stream = [pscustomobject]@{ aligned = $false; task_delta = -1; loop_idle_sec = -1 }
            cadence = [pscustomobject]@{ sample_size = 0; avg_sec = 0; p50_sec = 0; p95_sec = 0; retry_rate = 0 }
            governance = [pscustomobject]@{ adjusted_severity = 'unknown'; noise_suppressed = $false; dominant_retry_reason = 'none' }
            thresholds = [pscustomobject]@{ warning_cycle_sec = 180; critical_cycle_sec = 300; warning_sync_delta = 1; critical_sync_delta = 3; warning_retry_rate = 0.6; warning_score = 70; critical_score = 40 }
        }
    }

    $warningCycleSec = 180
    $criticalCycleSec = 300
    $warningSyncDelta = 1
    $criticalSyncDelta = 3
    $warningRetryRate = 0.6
    $warningScore = 70
    $criticalScore = 40

    $recentEntries = @()
    if ($ListenerActivity.PSObject.Properties['recent_entries'] -and $ListenerActivity.recent_entries -is [System.Array]) {
        $recentEntries = @($ListenerActivity.recent_entries)
    }

    $entriesSorted = @($recentEntries | Sort-Object {
        $ts = Convert-ToDateTimeOffsetOrNull -Value ([string]$_.timestamp)
        if ($null -eq $ts) { [DateTimeOffset]::MinValue } else { $ts }
    })

    $intervals = New-Object System.Collections.Generic.List[double]
    $requestIds = @()
    $retryCount = 0
    $retryWeightTotal = 0.0
    $failureRetryCount = 0
    $noNewWorkRetryCount = 0
    $duplicateRetryCount = 0
    $waitingGoOrderRetryCount = 0
    $lastTs = $null
    foreach ($entry in $entriesSorted) {
        $requestId = if ($entry.PSObject.Properties['request_id']) { [string]$entry.request_id } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($requestId)) { $requestIds += $requestId }

        $retryReason = if ($entry.PSObject.Properties['retry_reason']) { ([string]$entry.retry_reason).Trim().ToLowerInvariant() } else { 'none' }
        $isCadenceNoise = $false
        if ($entry.PSObject.Properties['cadence_noise']) {
            try { $isCadenceNoise = [bool]$entry.cadence_noise } catch { $isCadenceNoise = $false }
        }
        if ($retryReason -ne 'none' -and -not $isCadenceNoise) {
            $retryCount += 1
        }

        $retryWeight = 0.0
        if ($entry.PSObject.Properties['retry_weight']) {
            try { $retryWeight = [double]$entry.retry_weight } catch { $retryWeight = 0.0 }
        }
        if (-not $isCadenceNoise) {
            $retryWeightTotal += $retryWeight

            switch ($retryReason) {
                'failure' { $failureRetryCount += 1 }
                'no_new_work' { $noNewWorkRetryCount += 1 }
                'duplicate_seen' { $duplicateRetryCount += 1 }
                'waiting_go_order' { $waitingGoOrderRetryCount += 1 }
            }
        }

        $ts = Convert-ToDateTimeOffsetOrNull -Value ([string]$entry.timestamp)
        if ($null -ne $ts -and $null -ne $lastTs) { $intervals.Add(($ts - $lastTs).TotalSeconds) }
        if ($null -ne $ts) { $lastTs = $ts }
    }

    $avgSec = if ($intervals.Count -gt 0) { [math]::Round((($intervals | Measure-Object -Average).Average), 1) } else { 0 }
    $smoothedAvgSec = 0.0
    if ($intervals.Count -gt 0) {
        $alpha = 0.35
        $smoothed = [double]$intervals[0]
        foreach ($interval in $intervals) {
            $smoothed = ($alpha * [double]$interval) + ((1 - $alpha) * $smoothed)
        }
        $smoothedAvgSec = [Math]::Round($smoothed, 1)
    }
    $p50Sec = Get-PercentileValue -Values ([double[]]$intervals.ToArray()) -Percentile 50
    $p95Sec = Get-PercentileValue -Values ([double[]]$intervals.ToArray()) -Percentile 95
    $stdDevSec = 0.0
    if ($intervals.Count -gt 1) {
        $varianceTotal = 0.0
        foreach ($interval in $intervals) {
            $varianceTotal += [Math]::Pow(([double]$interval - [double]$avgSec), 2)
        }
        $stdDevSec = [Math]::Round([Math]::Sqrt($varianceTotal / $intervals.Count), 1)
    }
    $uniqueRequestIds = @($requestIds | Sort-Object -Unique)
    $retryRate = if (@($entriesSorted).Count -gt 0) { [math]::Round(($retryCount / [double]@($entriesSorted).Count), 3) } else { 0 }
    $sampleSize = [Math]::Max(@($entriesSorted).Count, 1)
    $weightedRetryRatio = if (@($entriesSorted).Count -gt 0) { [Math]::Round(($retryWeightTotal / [double]@($entriesSorted).Count), 3) } else { 0 }
    $failureRetryRatio = [Math]::Round(($failureRetryCount / [double]$sampleSize), 3)
    $noNewWorkRetryRatio = [Math]::Round(($noNewWorkRetryCount / [double]$sampleSize), 3)
    $duplicateRetryRatio = [Math]::Round(($duplicateRetryCount / [double]$sampleSize), 3)
    $waitingGoOrderRetryRatio = [Math]::Round(($waitingGoOrderRetryCount / [double]$sampleSize), 3)

    $latestTs = Convert-ToDateTimeOffsetOrNull -Value ([string]$ListenerActivity.latest_timestamp)
    $loopIdleSec = -1
    if ($null -ne $latestTs) { $loopIdleSec = [math]::Round(([DateTimeOffset]::UtcNow - $latestTs).TotalSeconds, 1) }
    elseif ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['heartbeat_age_seconds']) { $loopIdleSec = [double]$RecoveryWatchdog.heartbeat_age_seconds }

    $syncTaskDelta = 0
    $sync = if ($ListenerActivity.PSObject.Properties['sync']) { $ListenerActivity.sync } else { $null }
    if ($sync) {
        $reqTask = if ($sync.PSObject.Properties['request_task_number']) { [long]$sync.request_task_number } else { -1L }
        $resTask = if ($sync.PSObject.Properties['result_task_number']) { [long]$sync.result_task_number } else { -1L }
        if ($reqTask -ge 0 -and $resTask -ge 0) { $syncTaskDelta = [math]::Abs($reqTask - $resTask) }
    }

    $alerts = New-Object System.Collections.Generic.List[string]
    $severity = 'ok'
    $dominantRetryReason = 'none'
    $retryBreakdown = [ordered]@{
        failure = $failureRetryCount
        no_new_work = $noNewWorkRetryCount
        duplicate_seen = $duplicateRetryCount
        waiting_go_order = $waitingGoOrderRetryCount
    }
    $dominantRetryCount = 0
    foreach ($retryKey in $retryBreakdown.Keys) {
        $retryKeyCount = [int]$retryBreakdown[$retryKey]
        if ($retryKeyCount -gt $dominantRetryCount) {
            $dominantRetryCount = $retryKeyCount
            $dominantRetryReason = [string]$retryKey
        }
    }
    $noiseOnlyCadence = ($failureRetryCount -eq 0) -and (($noNewWorkRetryCount + $duplicateRetryCount + $waitingGoOrderRetryCount) -gt 0)
    $timingVarianceRatio = if ($smoothedAvgSec -gt 0) { [Math]::Round(($stdDevSec / [Math]::Max([double]$smoothedAvgSec, 1.0)), 3) } else { 0 }

    if ($loopIdleSec -gt $criticalCycleSec) { $alerts.Add('loop_idle_gt_300s'); $severity = 'critical' }
    elseif ($loopIdleSec -gt $warningCycleSec) { $alerts.Add('loop_idle_gt_180s'); $severity = 'warning' }
    if ($syncTaskDelta -gt $criticalSyncDelta) { $alerts.Add('sync_delta_gt_3'); $severity = 'critical' }
    elseif ($syncTaskDelta -gt $warningSyncDelta -and $severity -ne 'critical') { $alerts.Add('sync_delta_gt_1'); $severity = 'warning' }

    if ($failureRetryRatio -gt 0.35) {
        $alerts.Add('failure_retry_ratio_gt_35pct')
        if ($severity -ne 'critical') { $severity = 'warning' }
    }
    elseif ($weightedRetryRatio -gt $warningRetryRate -and -not $noiseOnlyCadence -and $severity -eq 'ok') {
        $alerts.Add('weighted_retry_ratio_gt_60pct')
        $severity = 'warning'
    }

    $latencyPenalty = 0.0
    if ($loopIdleSec -gt $warningCycleSec) {
        $latencyPenalty = [Math]::Min(35.0, (($loopIdleSec - $warningCycleSec) / [Math]::Max(($criticalCycleSec - $warningCycleSec), 1)) * 35.0)
    }
    $variancePenalty = [Math]::Min(20.0, $timingVarianceRatio * 25.0)
    $retryPenaltyRaw = [Math]::Min(30.0, ($failureRetryRatio * 28.0) + ($duplicateRetryRatio * 10.0) + ($waitingGoOrderRetryRatio * 8.0) + ($noNewWorkRetryRatio * 4.0))
    $retryPenalty = if ($noiseOnlyCadence) { [Math]::Round($retryPenaltyRaw * 0.4, 1) } else { [Math]::Round($retryPenaltyRaw, 1) }
    $syncPenalty = [Math]::Min(25.0, [double]$syncTaskDelta * 8.0)
    $score = [Math]::Round([Math]::Max(0.0, 100.0 - $latencyPenalty - $variancePenalty - $retryPenalty - $syncPenalty), 1)
    $noiseSuppressed = ($noiseOnlyCadence -and ($retryPenaltyRaw -gt $retryPenalty))

    if ($score -le $criticalScore -and $severity -ne 'critical') {
        $severity = 'critical'
        $alerts.Add('cadence_score_lte_40')
    }
    elseif ($score -le $warningScore -and $severity -eq 'ok') {
        $severity = 'warning'
        $alerts.Add('cadence_score_lte_70')
    }

    $adjustedSeverity = $severity
    if ($noiseOnlyCadence -and $syncTaskDelta -le $warningSyncDelta -and $loopIdleSec -le $warningCycleSec) {
        if ($adjustedSeverity -eq 'critical') {
            $adjustedSeverity = 'warning'
        }
        elseif ($adjustedSeverity -eq 'warning' -and $score -gt $warningScore) {
            $adjustedSeverity = 'ok'
        }
    }

    if ($noiseSuppressed) { $alerts.Add('cadence_noise_suppressed') }
    if ($alerts.Count -eq 0) { $alerts.Add('none') }

    return [pscustomobject]@{
        available = $true
        severity = $severity
        alerts = @($alerts)
        stream = [pscustomobject]@{ aligned = ($syncTaskDelta -eq 0); task_delta = $syncTaskDelta; loop_idle_sec = $loopIdleSec }
        cadence = [pscustomobject]@{
            sample_size = $intervals.Count
            avg_sec = $avgSec
            smoothed_avg_sec = $smoothedAvgSec
            p50_sec = $p50Sec
            p95_sec = $p95Sec
            stddev_sec = $stdDevSec
            retry_rate = $retryRate
            weighted_retry_ratio = $weightedRetryRatio
            failure_retry_ratio = $failureRetryRatio
            no_new_work_retry_ratio = $noNewWorkRetryRatio
            duplicate_retry_ratio = $duplicateRetryRatio
            waiting_go_order_retry_ratio = $waitingGoOrderRetryRatio
            score = $score
        }
        governance = [pscustomobject]@{ adjusted_severity = $adjustedSeverity; noise_suppressed = $noiseSuppressed; dominant_retry_reason = $dominantRetryReason }
        thresholds = [pscustomobject]@{ warning_cycle_sec = $warningCycleSec; critical_cycle_sec = $criticalCycleSec; warning_sync_delta = $warningSyncDelta; critical_sync_delta = $criticalSyncDelta; warning_retry_rate = $warningRetryRate; warning_score = $warningScore; critical_score = $criticalScore }
    }
}

function Get-SteadyStateHealth {
    param(
        $ListenerActivity,
        $RecoveryWatchdog,
        $CadenceHealth,
        [string]$StateWarning
    )

    $build = Read-JsonFileIfExists -Path $currentBuildStatePath
    $coordination = Read-JsonFileIfExists -Path $coordinationEscalationPath
    $stallState = Read-JsonFileIfExists -Path $regressionStallStatePath

    $regressionAvailable = $false
    $passed = 0
    $failed = 0
    $total = 0
    $regressionGeneratedAt = ''
    if ($build -and $build.PSObject.Properties['last_regression_result'] -and $build.last_regression_result) {
        $regressionAvailable = $true
        try { $passed = [int]$build.last_regression_result.passed } catch { }
        try { $failed = [int]$build.last_regression_result.failed } catch { }
        try { $total = [int]$build.last_regression_result.total } catch { }
        if ($build.last_regression_result.PSObject.Properties['generated_at']) {
            $regressionGeneratedAt = [string]$build.last_regression_result.generated_at
        }
    }

    $pendingCoordination = $false
    $coordinationStatus = 'unknown'
    if ($coordination) {
        $pendingCoordination = -not [string]::IsNullOrWhiteSpace([string]$coordination.pending_request_id)
        if ($coordination.PSObject.Properties['last_ack_status']) {
            $coordinationStatus = [string]$coordination.last_ack_status
        }
    }

    $unchangedCycles = 0
    if ($stallState -and $stallState.PSObject.Properties['unchanged_cycles']) {
        try { $unchangedCycles = [int]$stallState.unchanged_cycles } catch { }
    }

    $loopIdleSec = if ($CadenceHealth -and $CadenceHealth.PSObject.Properties['stream']) { [double]$CadenceHealth.stream.loop_idle_sec } else { -1 }
    if ($loopIdleSec -lt 0 -and $RecoveryWatchdog) {
        $loopIdleSec = [double]$RecoveryWatchdog.heartbeat_age_seconds
    }

    $cadenceSeverity = if ($CadenceHealth -and $CadenceHealth.PSObject.Properties['governance'] -and $CadenceHealth.governance.PSObject.Properties['adjusted_severity']) { [string]$CadenceHealth.governance.adjusted_severity } elseif ($CadenceHealth -and $CadenceHealth.PSObject.Properties['severity']) { [string]$CadenceHealth.severity } else { 'unknown' }
    $listenerMode = 'listener_telemetry'
    $cadenceNoiseSuppressed = [bool]($CadenceHealth -and $CadenceHealth.PSObject.Properties['governance'] -and $CadenceHealth.governance.PSObject.Properties['noise_suppressed'] -and $CadenceHealth.governance.noise_suppressed)
    $regressionAgeSeconds = Get-IsoAgeSeconds -Value $regressionGeneratedAt
    $watchdogEffectiveState = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['effective_state'] -and -not [string]::IsNullOrWhiteSpace([string]$RecoveryWatchdog.effective_state)) { [string]$RecoveryWatchdog.effective_state } elseif ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['state']) { [string]$RecoveryWatchdog.state } else { 'unknown' }
    $watchdogHealthy = [string]::Equals($watchdogEffectiveState, 'healthy', [System.StringComparison]::OrdinalIgnoreCase)
    $bridgeStatus = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['bridge_smoke']) { $RecoveryWatchdog.bridge_smoke } else { $null }
    $bridgeHealthy = ($bridgeStatus -and $bridgeStatus.PSObject.Properties['passed'] -and [bool]$bridgeStatus.passed)
    $staleRegressionSuperseded = $regressionAvailable -and ($failed -gt 0) -and ($regressionAgeSeconds -ge 3600) -and $watchdogHealthy -and $bridgeHealthy -and [string]::Equals($cadenceSeverity, 'ok', [System.StringComparison]::OrdinalIgnoreCase)
    $status = 'unknown'
    $summary = 'Steady state unavailable'
    if ($regressionAvailable -and $failed -le 0 -and -not $pendingCoordination -and $unchangedCycles -eq 0) {
        if ($cadenceNoiseSuppressed -and [string]::Equals($cadenceSeverity, 'ok', [System.StringComparison]::OrdinalIgnoreCase)) {
            $status = 'ok'
            $summary = 'Regression is green; cadence noise is present but execution truth remains healthy.'
        }
        elseif ([string]::Equals($cadenceSeverity, 'critical', [System.StringComparison]::OrdinalIgnoreCase) -or ($loopIdleSec -ge 300)) {
            $status = 'warning'
            $summary = 'Regression is green, but live cadence looks stale.'
        }
        elseif ([string]::Equals($cadenceSeverity, 'warning', [System.StringComparison]::OrdinalIgnoreCase) -or ($loopIdleSec -ge 180)) {
            $status = 'warning'
            $summary = 'Regression is green and coordination is clear; cadence needs watching.'
        }
        else {
            $status = 'ok'
            $summary = 'Regression is green, coordination is clear, and listener cadence is healthy.'
        }
    }
    elseif ($staleRegressionSuperseded) {
        $status = 'ok'
        $summary = 'Historical regression failures are present, but the regression report is stale and current bridge, cadence, and watchdog telemetry are healthy.'
    }
    elseif ($regressionAvailable -and $failed -gt 0) {
        $status = 'critical'
        $summary = 'Regression failures remain; system is not in steady state.'
    }
    elseif ($pendingCoordination) {
        $status = 'warning'
        $summary = 'Coordination is still pending despite current listener activity.'
    }

    return [pscustomobject]@{
        available = ($regressionAvailable -or ($null -ne $CadenceHealth))
        status = $status
        summary = $summary
        regression_green = ($regressionAvailable -and $failed -le 0)
        regression_generated_at = $regressionGeneratedAt
        passed = $passed
        failed = $failed
        total = $total
        pending_coordination = $pendingCoordination
        coordination_status = $coordinationStatus
        unchanged_cycles = $unchangedCycles
        loop_idle_sec = $loopIdleSec
        cadence_severity = $cadenceSeverity
        listener_mode = $listenerMode
        regression_age_seconds = $regressionAgeSeconds
        regression_report_stale = $staleRegressionSuperseded
        source_warning = $StateWarning
    }
}

function Get-StateWarning {
    if (-not (Test-Path -Path $statePath)) {
        return 'state.json not found; using listener telemetry'
    }

    try {
        $item = Get-Item -Path $statePath -ErrorAction Stop
        if ([int64]$item.Length -gt [int64]$maxStateReadBytes) {
            $stateMiB = [math]::Round(([double]$item.Length / 1MB), 2)
            return "state.json too large (${stateMiB} MiB); using listener telemetry"
        }
    }
    catch {
        return 'state.json unavailable; using listener telemetry'
    }

    return ''
}

function Get-TrainingSystemPosture {
    param(
        $ListenerActivity,
        $SteadyState,
        $CadenceHealth
    )

    $pendingCount = if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['sync']) { [int]$ListenerActivity.sync.pending_request_count } else { 0 }
    $latestStatus = if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['latest_execution_status']) { [string]$ListenerActivity.latest_execution_status } else { 'unknown' }
    $loopIdleSec = if ($CadenceHealth -and $CadenceHealth.PSObject.Properties['stream']) { [double]$CadenceHealth.stream.loop_idle_sec } else { -1 }
    $activeExecutions = 0
    if ($latestStatus -eq 'in_progress') {
        $activeExecutions = 1
    }
    elseif ($pendingCount -gt 0) {
        $activeExecutions = 1
    }
    elseif ($loopIdleSec -ge 0 -and $loopIdleSec -lt 90 -and $latestStatus -ne 'completed') {
        $activeExecutions = 1
    }

    $agentState = if ($activeExecutions -gt 0 -or ($SteadyState -and $SteadyState.pending_coordination)) { 'busy' } elseif ($SteadyState -and $SteadyState.status -eq 'critical') { 'degraded' } else { 'idle' }
    $cadenceAdjustedSeverity = if ($CadenceHealth -and $CadenceHealth.PSObject.Properties['governance'] -and $CadenceHealth.governance.PSObject.Properties['adjusted_severity']) { [string]$CadenceHealth.governance.adjusted_severity } elseif ($CadenceHealth -and $CadenceHealth.PSObject.Properties['severity']) { [string]$CadenceHealth.severity } else { 'unknown' }
    $alertState = if ($SteadyState -and $SteadyState.status -eq 'critical') { 'critical' } elseif ($SteadyState -and $SteadyState.status -eq 'warning') { 'warning' } elseif ($CadenceHealth -and $cadenceAdjustedSeverity -eq 'critical') { 'critical' } elseif ($CadenceHealth -and $cadenceAdjustedSeverity -eq 'warning') { 'warning' } else { 'ok' }
    $blocks = @()
    if ($SteadyState -and $SteadyState.pending_coordination) { $blocks += 'pending_coordination' }
    if ($SteadyState -and [int]$SteadyState.failed -gt 0 -and -not [bool]$SteadyState.regression_report_stale) { $blocks += 'regression_failures' }
    if ($CadenceHealth -and $cadenceAdjustedSeverity -eq 'critical') { $blocks += 'cadence_critical' }

    return [pscustomobject]@{
        agent_state = $agentState
        current_alert_state = $alertState
        active_goal_count = if ($activeExecutions -gt 0 -or $pendingCount -gt 0) { 1 } else { 0 }
        active_execution_count = $activeExecutions
        pending_confirmations = if ($SteadyState -and $SteadyState.pending_coordination) { 1 } else { 0 }
        blocked_items = @($blocks).Count
        registered_capabilities = 0
        current_executor_health = if ($alertState -eq 'critical') { 'degraded' } elseif ($alertState -eq 'warning') { 'watch' } else { 'healthy' }
        summary = if ($activeExecutions -gt 0) { 'Listener telemetry indicates active execution is in progress.' } elseif ($pendingCount -gt 0) { 'MIM is ahead of TOD and work is queued.' } else { 'Listener telemetry indicates TOD is between task handoffs.' }
    }
}

$listenerActivity = Get-ListenerActivity
$recoveryWatchdog = Get-RecoveryWatchdogStatus
$cadenceHealth = Get-CadenceHealth -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog
$stateWarning = Get-StateWarning
$steadyState = Get-SteadyStateHealth -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog -CadenceHealth $cadenceHealth -StateWarning $stateWarning
$systemPosture = Get-TrainingSystemPosture -ListenerActivity $listenerActivity -SteadyState $steadyState -CadenceHealth $cadenceHealth

$blocks = @()
if ($steadyState.pending_coordination) {
    $blocks += [pscustomobject]@{ code = 'pending_coordination'; severity = 'warning'; summary = 'Coordination is still pending.' }
}
if ([int]$steadyState.failed -gt 0 -and -not [bool]$steadyState.regression_report_stale) {
    $blocks += [pscustomobject]@{ code = 'regression_failures'; severity = 'critical'; summary = 'Regression failures remain in the latest build snapshot.' }
}
if ($cadenceHealth -and $cadenceHealth.PSObject.Properties['governance'] -and $cadenceHealth.governance.PSObject.Properties['adjusted_severity'] -and $cadenceHealth.governance.adjusted_severity -eq 'critical') {
    $blocks += [pscustomobject]@{ code = 'cadence_critical'; severity = 'warning'; summary = 'Listener cadence appears stale.' }
}
if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties['stale'] -and [bool]$recoveryWatchdog.stale) {
    $blocks += [pscustomobject]@{ code = 'watchdog_state_stale'; severity = 'warning'; summary = 'Watchdog state is older than listener/request/result telemetry; treat watchdog state as non-authoritative until refreshed.' }
}

$reliability = [pscustomobject]@{
    source = 'listener_telemetry_fallback'
    current_alert_state = if ($systemPosture) { [string]$systemPosture.current_alert_state } else { 'unknown' }
    current_executor_health = if ($systemPosture) { [string]$systemPosture.current_executor_health } else { 'unknown' }
    recovery_attempts = if ($recoveryWatchdog) { [int]$recoveryWatchdog.recovery_attempts } else { 0 }
    consecutive_freezes = if ($recoveryWatchdog) { [int]$recoveryWatchdog.consecutive_freezes } else { 0 }
    alerts = if ($cadenceHealth) { @($cadenceHealth.alerts) } else { @() }
}

$reliabilityDashboard = [pscustomobject]@{
    source = 'listener_telemetry_fallback'
    retry_trend = [pscustomobject]@{
        retry_rate = if ($cadenceHealth) { [double]$cadenceHealth.cadence.retry_rate } else { 0 }
        sample_size = if ($cadenceHealth) { [int]$cadenceHealth.cadence.sample_size } else { 0 }
    }
    drift_warnings = @($blocks | ForEach-Object { [string]$_.summary })
    loop_idle_sec = if ($steadyState) { [double]$steadyState.loop_idle_sec } else { -1 }
    cadence_severity = if ($cadenceHealth) { [string]$cadenceHealth.severity } else { 'unknown' }
}

$failureTaxonomy = [pscustomobject]@{
    source = 'listener_telemetry_fallback'
    groups = @(
        [pscustomobject]@{
            name = 'listener-derived'
            items = @($blocks | ForEach-Object {
                [pscustomobject]@{
                    code = [string]$_.code
                    severity = [string]$_.severity
                    summary = [string]$_.summary
                }
            })
        }
    )
}

$selectedObjectiveStats = $null
if ($listenerActivity -and $listenerActivity.PSObject.Properties['objective_stats']) {
    $latestObjectiveId = [string]$listenerActivity.latest_objective_id
    if (-not [string]::IsNullOrWhiteSpace($latestObjectiveId) -and $listenerActivity.objective_stats.PSObject.Properties[$latestObjectiveId]) {
        $selectedObjectiveStats = $listenerActivity.objective_stats.PSObject.Properties[$latestObjectiveId].Value
    }
}

$derivedLatestScore = 0.0
if ($selectedObjectiveStats -and [int]$selectedObjectiveStats.total -gt 0) {
    $derivedLatestScore = [math]::Round(([double]$selectedObjectiveStats.progress_units / [double]$selectedObjectiveStats.total), 2)
}

$engineeringSummary = [pscustomobject]@{
    source = 'listener_telemetry_fallback'
    latest_score = $derivedLatestScore
    latest_request_id = if ($listenerActivity) { [string]$listenerActivity.latest_request_id } else { '' }
    latest_execution_status = if ($listenerActivity) { [string]$listenerActivity.latest_execution_status } else { '' }
    latest_objective_id = if ($listenerActivity) { [string]$listenerActivity.latest_objective_id } else { '' }
    cadence_severity = if ($cadenceHealth) { [string]$cadenceHealth.severity } else { 'unknown' }
}

$engineeringSignal = [pscustomobject]@{
    source = 'listener_telemetry_fallback'
    pending_approval_state = if ($steadyState -and $steadyState.pending_coordination) { 'pending' } else { 'clear' }
    stop_reason = if ($blocks.Count -gt 0) { [string]$blocks[0].code } else { '' }
    trend_direction = if ($cadenceHealth -and $cadenceHealth.severity -eq 'critical') { 'declining' } elseif ($cadenceHealth -and $cadenceHealth.severity -eq 'warning') { 'flat' } else { 'improving' }
    phase_snapshot = [pscustomobject]@{
        latest_execution_status = if ($listenerActivity) { [string]$listenerActivity.latest_execution_status } else { '' }
        loop_idle_sec = if ($steadyState) { [double]$steadyState.loop_idle_sec } else { -1 }
    }
}

$scorecardHistory = [pscustomobject]@{
    source = 'listener_telemetry_fallback'
    items = @($listenerActivity.recent_entries | ForEach-Object {
        [pscustomobject]@{
            timestamp = [string]$_.timestamp
            request_id = [string]$_.request_id
            status = [string]$_.execution_status
        }
    })
    paging = [pscustomobject]@{
        page = 1
        page_size = @($listenerActivity.recent_entries).Count
        total_items = @($listenerActivity.recent_entries).Count
    }
}

$payload = [pscustomobject]@{
    ok = $true
    source = 'tod-lightweight-state-bus-v1'
    mode = 'listener_telemetry_fallback'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    warnings = @($stateWarning | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    blocks = @($blocks)
    system_posture = $systemPosture
    engineering_loop_state = [pscustomobject]@{
        latest_objective_id = if ($listenerActivity) { [string]$listenerActivity.latest_objective_id } else { '' }
        latest_request_id = if ($listenerActivity) { [string]$listenerActivity.latest_request_id } else { '' }
        latest_execution_status = if ($listenerActivity) { [string]$listenerActivity.latest_execution_status } else { '' }
        cadence_severity = if ($cadenceHealth) { [string]$cadenceHealth.severity } else { 'unknown' }
        steady_state = if ($steadyState) { [string]$steadyState.status } else { 'unknown' }
        source_warning = $stateWarning
    }
    listener_activity = $listenerActivity
    recovery_watchdog = $recoveryWatchdog
    cadence_health = $cadenceHealth
    steady_state = $steadyState
    reliability = $reliability
    reliability_dashboard = $reliabilityDashboard
    failure_taxonomy = $failureTaxonomy
    engineering_summary = $engineeringSummary
    engineering_signal = $engineeringSignal
    scorecard_history = $scorecardHistory
}

if ($AsJson) {
    $payload | ConvertTo-Json -Depth 20
}
else {
    $payload
}