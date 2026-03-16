param(
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerStagePath = Join-Path $repoRoot "tod/out/context-sync/listener"
$listenerJournalPath = Join-Path $listenerStagePath "TOD_LOOP_JOURNAL.latest.json"
$listenerResultPath = Join-Path $listenerStagePath "TOD_MIM_TASK_RESULT.latest.json"
$listenerRequestPath = Join-Path $listenerStagePath "MIM_TOD_TASK_REQUEST.latest.json"
$coordinationEscalationPath = Join-Path $listenerStagePath "TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json"
$regressionStallStatePath = Join-Path $listenerStagePath "TOD_REGRESSION_STALL_STATE.latest.json"
$currentBuildStatePath = Join-Path $repoRoot "shared_state/current_build_state.json"
$recoveryWatchdogStatePath = Join-Path $repoRoot "shared_state/tod_recovery_watchdog.latest.json"
$statePath = Join-Path $repoRoot "tod/data/state.json"
$maxStateReadBytes = 256MB

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

    $match = [regex]::Match([string]$RequestId, '^objective-(?<objective>\d+)-task-\d+$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
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

    $match = [regex]::Match([string]$Value, '^objective-(?<objective>\d+)-task-(?<task>\d+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    return [pscustomobject]@{
        objective = [string]$match.Groups['objective'].Value
        task_number = [int]$match.Groups['task'].Value
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

function Get-ListenerActivity {
    $journal = Read-JsonFileIfExists -Path $listenerJournalPath
    $resultPacket = Read-JsonFileIfExists -Path $listenerResultPath
    $requestPacket = Read-JsonFileIfExists -Path $listenerRequestPath

    $entries = @()
    if ($journal -and $journal.PSObject.Properties['entries']) {
        $entries = @($journal.entries)
    }
    elseif ($journal -is [System.Array]) {
        $entries = @($journal)
    }

    $normalizedEntries = @()
    foreach ($entry in $entries) {
        $requestId = if ($entry.PSObject.Properties['request_id']) { [string]$entry.request_id } else { "" }
        $objectiveId = if ($entry.PSObject.Properties['objective_id']) { [string]$entry.objective_id } else { "" }
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            $objectiveId = Get-ObjectiveIdFromRequestId -RequestId $requestId
        }

        $executionStatus = if ($entry.PSObject.Properties['execution_status']) { [string]$entry.execution_status } else { "unknown" }
        $normalizedEntries += [pscustomobject]@{
            timestamp = if ($entry.PSObject.Properties['timestamp']) { [string]$entry.timestamp } else { "" }
            request_id = $requestId
            objective_id = $objectiveId
            execution_status = $executionStatus
        }
    }

    $objectiveStats = @{}
    foreach ($entry in $normalizedEntries) {
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
        switch ($status.Trim().ToLowerInvariant()) {
            'completed' { $stats.completed = [int]$stats.completed + 1; $stats.progress_units = [double]$stats.progress_units + 1.0 }
            'failed' { $stats.failed = [int]$stats.failed + 1; $stats.progress_units = [double]$stats.progress_units + 0.25 }
            'in_progress' { $stats.in_progress = [int]$stats.in_progress + 1; $stats.progress_units = [double]$stats.progress_units + 0.5 }
            default { $stats.progress_units = [double]$stats.progress_units + 0.1 }
        }

        $stats.last_request_id = [string]$entry.request_id
        $stats.last_execution_status = $status
        $stats.last_timestamp = [string]$entry.timestamp
    }

    $latest = if (@($normalizedEntries).Count -gt 0) { @($normalizedEntries)[-1] } else { $null }
    $recentEntries = @($normalizedEntries | Select-Object -Last 30)
    $resultRequestId = if ($resultPacket -and $resultPacket.PSObject.Properties['request_id']) { [string]$resultPacket.request_id } else { "" }
    $resultRef = Get-TaskRefInfo -Value $resultRequestId
    $requestTaskId = if ($requestPacket -and $requestPacket.PSObject.Properties['task_id']) { [string]$requestPacket.task_id } else { "" }
    $requestRef = Get-TaskRefInfo -Value $requestTaskId
    $isMimAhead = $false
    $pendingCount = 0
    if ($requestRef -and $resultRef) {
        if ([string]$requestRef.objective -eq [string]$resultRef.objective -and [int]$requestRef.task_number -gt [int]$resultRef.task_number) {
            $isMimAhead = $true
            $pendingCount = [int]$requestRef.task_number - [int]$resultRef.task_number
        }
    }
    elseif ($requestRef -and -not $resultRef) {
        $isMimAhead = $true
        $pendingCount = [int]$requestRef.task_number
    }

    return [pscustomobject]@{
        entry_count = @($normalizedEntries).Count
        latest_objective_id = if ($latest) { [string]$latest.objective_id } else { "" }
        latest_request_id = if ($latest) { [string]$latest.request_id } else { "" }
        latest_execution_status = if ($latest) { [string]$latest.execution_status } else { "" }
        latest_timestamp = if ($latest) { [string]$latest.timestamp } else { "" }
        result_request_id = $resultRequestId
        result_generated_at = if ($resultPacket -and $resultPacket.PSObject.Properties['generated_at']) { [string]$resultPacket.generated_at } else { "" }
        request_task_id = $requestTaskId
        request_generated_at = if ($requestPacket -and $requestPacket.PSObject.Properties['generated_at']) { [string]$requestPacket.generated_at } else { "" }
        sync = [pscustomobject]@{
            is_mim_ahead = $isMimAhead
            pending_request_count = $pendingCount
            result_task_number = if ($resultRef) { [int]$resultRef.task_number } else { -1 }
            request_task_number = if ($requestRef) { [int]$requestRef.task_number } else { -1 }
        }
        recent_entries = @($recentEntries)
        objective_stats = [pscustomobject]$objectiveStats
    }
}

function Get-RecoveryWatchdogStatus {
    $doc = Read-JsonFileIfExists -Path $recoveryWatchdogStatePath
    if ($null -eq $doc) {
        return [pscustomobject]@{
            available = $false
            state = 'unknown'
            task_state = 'idle'
            heartbeat_age_seconds = -1
            recovery_attempts = 0
            consecutive_freezes = 0
        }
    }

    return [pscustomobject]@{
        available = $true
        state = if ($doc.PSObject.Properties['state']) { [string]$doc.state } else { 'unknown' }
        task_state = if ($doc.PSObject.Properties['task_state']) { [string]$doc.task_state } else { 'idle' }
        heartbeat_age_seconds = if ($doc.PSObject.Properties['heartbeat_age_seconds']) { [int]$doc.heartbeat_age_seconds } else { -1 }
        recovery_attempts = if ($doc.PSObject.Properties['recovery_attempts']) { [int]$doc.recovery_attempts } else { 0 }
        consecutive_freezes = if ($doc.PSObject.Properties['consecutive_freezes']) { [int]$doc.consecutive_freezes } else { 0 }
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
        }
    }

    $warningCycleSec = 180
    $criticalCycleSec = 300
    $warningSyncDelta = 1
    $criticalSyncDelta = 3
    $warningRetryRate = 0.6

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
    $lastTs = $null
    foreach ($entry in $entriesSorted) {
        $requestId = if ($entry.PSObject.Properties['request_id']) { [string]$entry.request_id } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($requestId)) { $requestIds += $requestId }
        $ts = Convert-ToDateTimeOffsetOrNull -Value ([string]$entry.timestamp)
        if ($null -ne $ts -and $null -ne $lastTs) { $intervals.Add(($ts - $lastTs).TotalSeconds) }
        if ($null -ne $ts) { $lastTs = $ts }
    }

    $avgSec = if ($intervals.Count -gt 0) { [math]::Round((($intervals | Measure-Object -Average).Average), 1) } else { 0 }
    $p50Sec = Get-PercentileValue -Values ([double[]]$intervals.ToArray()) -Percentile 50
    $p95Sec = Get-PercentileValue -Values ([double[]]$intervals.ToArray()) -Percentile 95
    $uniqueRequestIds = @($requestIds | Sort-Object -Unique)
    $retryRate = if ($requestIds.Count -gt 0) { [math]::Round((($requestIds.Count - $uniqueRequestIds.Count) / [double]$requestIds.Count), 3) } else { 0 }

    $latestTs = Convert-ToDateTimeOffsetOrNull -Value ([string]$ListenerActivity.latest_timestamp)
    $loopIdleSec = -1
    if ($null -ne $latestTs) { $loopIdleSec = [math]::Round(([DateTimeOffset]::UtcNow - $latestTs).TotalSeconds, 1) }
    elseif ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['heartbeat_age_seconds']) { $loopIdleSec = [double]$RecoveryWatchdog.heartbeat_age_seconds }

    $syncTaskDelta = 0
    $sync = if ($ListenerActivity.PSObject.Properties['sync']) { $ListenerActivity.sync } else { $null }
    if ($sync) {
        $reqTask = if ($sync.PSObject.Properties['request_task_number']) { [int]$sync.request_task_number } else { -1 }
        $resTask = if ($sync.PSObject.Properties['result_task_number']) { [int]$sync.result_task_number } else { -1 }
        if ($reqTask -ge 0 -and $resTask -ge 0) { $syncTaskDelta = [math]::Abs($reqTask - $resTask) }
    }

    $alerts = New-Object System.Collections.Generic.List[string]
    $severity = 'ok'
    if ($loopIdleSec -gt $criticalCycleSec) { $alerts.Add('loop_idle_gt_300s'); $severity = 'critical' }
    elseif ($loopIdleSec -gt $warningCycleSec) { $alerts.Add('loop_idle_gt_180s'); $severity = 'warning' }
    if ($syncTaskDelta -gt $criticalSyncDelta) { $alerts.Add('sync_delta_gt_3'); $severity = 'critical' }
    elseif ($syncTaskDelta -gt $warningSyncDelta -and $severity -ne 'critical') { $alerts.Add('sync_delta_gt_1'); $severity = 'warning' }
    if ($retryRate -gt $warningRetryRate -and $severity -eq 'ok') { $alerts.Add('retry_rate_gt_60pct'); $severity = 'warning' }
    if ($alerts.Count -eq 0) { $alerts.Add('none') }

    return [pscustomobject]@{
        available = $true
        severity = $severity
        alerts = @($alerts)
        stream = [pscustomobject]@{ aligned = ($syncTaskDelta -eq 0); task_delta = $syncTaskDelta; loop_idle_sec = $loopIdleSec }
        cadence = [pscustomobject]@{ sample_size = $intervals.Count; avg_sec = $avgSec; p50_sec = $p50Sec; p95_sec = $p95Sec; retry_rate = $retryRate }
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
    if ($build -and $build.PSObject.Properties['last_regression_result'] -and $build.last_regression_result) {
        $regressionAvailable = $true
        try { $passed = [int]$build.last_regression_result.passed } catch { }
        try { $failed = [int]$build.last_regression_result.failed } catch { }
        try { $total = [int]$build.last_regression_result.total } catch { }
    }

    $pendingCoordination = $false
    if ($coordination) {
        $pendingCoordination = -not [string]::IsNullOrWhiteSpace([string]$coordination.pending_request_id)
    }

    $unchangedCycles = 0
    if ($stallState -and $stallState.PSObject.Properties['unchanged_cycles']) {
        try { $unchangedCycles = [int]$stallState.unchanged_cycles } catch { }
    }

    $loopIdleSec = if ($CadenceHealth -and $CadenceHealth.PSObject.Properties['stream']) { [double]$CadenceHealth.stream.loop_idle_sec } else { -1 }
    if ($loopIdleSec -lt 0 -and $RecoveryWatchdog) {
        $loopIdleSec = [double]$RecoveryWatchdog.heartbeat_age_seconds
    }

    $cadenceSeverity = if ($CadenceHealth -and $CadenceHealth.PSObject.Properties['severity']) { [string]$CadenceHealth.severity } else { 'unknown' }
    $status = 'unknown'
    $summary = 'Steady state unavailable'
    if ($regressionAvailable -and $failed -le 0 -and -not $pendingCoordination -and $unchangedCycles -eq 0) {
        if ([string]::Equals($cadenceSeverity, 'critical', [System.StringComparison]::OrdinalIgnoreCase) -or ($loopIdleSec -ge 300)) {
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
        passed = $passed
        failed = $failed
        total = $total
        pending_coordination = $pendingCoordination
        unchanged_cycles = $unchangedCycles
        loop_idle_sec = $loopIdleSec
        cadence_severity = $cadenceSeverity
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
    $alertState = if ($SteadyState -and $SteadyState.status -eq 'critical') { 'critical' } elseif ($SteadyState -and $SteadyState.status -eq 'warning') { 'warning' } elseif ($CadenceHealth -and $CadenceHealth.severity -eq 'critical') { 'critical' } elseif ($CadenceHealth -and $CadenceHealth.severity -eq 'warning') { 'warning' } else { 'ok' }
    $blocks = @()
    if ($SteadyState -and $SteadyState.pending_coordination) { $blocks += 'pending_coordination' }
    if ($SteadyState -and [int]$SteadyState.failed -gt 0) { $blocks += 'regression_failures' }
    if ($CadenceHealth -and $CadenceHealth.severity -eq 'critical') { $blocks += 'cadence_critical' }

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
if ([int]$steadyState.failed -gt 0) {
    $blocks += [pscustomobject]@{ code = 'regression_failures'; severity = 'critical'; summary = 'Regression failures remain in the latest build snapshot.' }
}
if ($cadenceHealth -and $cadenceHealth.severity -eq 'critical') {
    $blocks += [pscustomobject]@{ code = 'cadence_critical'; severity = 'warning'; summary = 'Listener cadence appears stale.' }
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