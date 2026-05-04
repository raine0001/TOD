param(
    [ValidateSet("light", "standard", "deep")]
    [string]$Profile = "standard",
    [ValidateSet("manual", "scheduled")]
    [string]$InvocationMode = "manual",
    [string]$SharedStateDir = "shared_state",
    [string]$LightweightStateBusScriptPath = "scripts/Get-TODLightweightStateBus.ps1",
    [string]$SharedStateSyncScriptPath = "scripts/Invoke-TODSharedStateSync.ps1",
    [string]$RecoveryWatchdogScriptPath = "scripts/Start-TODRecoveryWatchdog.ps1",
    [string]$WatchdogDriftGuardScriptPath = "scripts/Invoke-TODWatchdogDriftGuard.ps1",
    [string]$PublicRouteHealthScriptPath = "scripts/Invoke-TODPublicRouteHealthCheck.ps1",
    [string]$ReadinessScriptPath = "scripts/Invoke-TODCodexReadinessDaily.ps1",
    [string]$LocalVerificationScriptPath = "scripts/Invoke-TODAgentMimLocalVerification.ps1",
    [string]$LocalVerificationQueuePath = "shared_state/agentmim/MIM_TOD_AGENT_TASK_QUEUE.latest.json",
    [string]$OutputPath = "shared_state/TOD_SELF_HEALTH_RUN.latest.json",
    [string]$LogPath = "shared_state/TOD_SELF_HEALTH_RUN.log.jsonl",
    [int]$FallbackWarningThresholdRuns = 6,
    [int]$FallbackWarningWindowHours = 48,
    [int]$FallbackWarningTailLines = 128,
    [switch]$RestartUiOnFailure,
    [switch]$RefreshAgentMimReadiness,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runnerId = "tod-self-health-maintenance-v1"

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Append-Utf8NoBomJsonLine {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $line = (($Payload | ConvertTo-Json -Depth $Depth -Compress) + "`n")
    [System.IO.File]::AppendAllText($PathValue, $line, $utf8NoBom)
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function ConvertTo-UtcDateTimeOrNull {
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    try {
        return ([DateTime]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime()
    }
    catch {
        return $null
    }
}

function Read-JsonLinesTail {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [int]$TailLines = 128
    )

    if (-not (Test-Path -Path $PathValue)) {
        return @()
    }

    try {
        $lines = @(Get-Content -Path $PathValue -Tail $TailLines -ErrorAction Stop)
    }
    catch {
        return @()
    }

    $entries = @()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace([string]$line)) {
            continue
        }

        try {
            $entries += ($line | ConvertFrom-Json)
        }
        catch {
        }
    }

    return @($entries)
}

function Test-IsExpectedBoundedFallbackEntry {
    param([AllowNull()]$Entry)

    if ($null -eq $Entry) {
        return $false
    }

    if ($Entry.PSObject.Properties['severity_reason'] -and [string]$Entry.severity_reason -eq 'expected_bounded_fallback') {
        return $true
    }

    if ($Entry.PSObject.Properties['postflight'] -and $Entry.postflight -and $Entry.postflight.PSObject.Properties['fallback_only_warning'] -and [bool]$Entry.postflight.fallback_only_warning) {
        return $true
    }

    return $false
}

function Get-MaintenanceHistorySummary {
    param(
        [Parameter(Mandatory = $true)][string]$LogPathValue,
        [Parameter(Mandatory = $true)][string]$CurrentInvocationMode,
        [Parameter(Mandatory = $true)][string]$CurrentSeverityReason,
        [int]$WindowHours = 48,
        [int]$ThresholdRuns = 6,
        [int]$TailLines = 128
    )

    $windowStart = (Get-Date).ToUniversalTime().AddHours(-1 * [Math]::Abs($WindowHours))
    $entries = @(Read-JsonLinesTail -PathValue $LogPathValue -TailLines $TailLines)
    $scheduledEntries = @()
    foreach ($entry in $entries) {
        $entryInvocationMode = if ($entry.PSObject.Properties['invocation_mode']) { [string]$entry.invocation_mode } else { '' }
        if ($entryInvocationMode -ne 'scheduled') {
            continue
        }

        $generatedAt = ConvertTo-UtcDateTimeOrNull -Value $(if ($entry.PSObject.Properties['generated_at']) { $entry.generated_at } else { $null })
        if ($null -eq $generatedAt -or $generatedAt -lt $windowStart) {
            continue
        }

        $scheduledEntries += [pscustomobject]@{
            generated_at = $generatedAt
            is_expected_bounded_fallback = (Test-IsExpectedBoundedFallbackEntry -Entry $entry)
        }
    }

    $orderedScheduledEntries = @($scheduledEntries | Sort-Object -Property generated_at)
    $scheduledFallbackRunCount = @($orderedScheduledEntries | Where-Object { [bool]$_.is_expected_bounded_fallback }).Count

    $consecutiveScheduledFallbackRuns = 0
    foreach ($entry in @($orderedScheduledEntries | Sort-Object -Property generated_at -Descending)) {
        if (-not [bool]$entry.is_expected_bounded_fallback) {
            break
        }
        $consecutiveScheduledFallbackRuns += 1
    }

    $currentIsExpectedBoundedFallback = ($CurrentInvocationMode -eq 'scheduled' -and $CurrentSeverityReason -eq 'expected_bounded_fallback')
    $scheduledFallbackRunCountIncludingCurrent = $scheduledFallbackRunCount + $(if ($currentIsExpectedBoundedFallback) { 1 } else { 0 })
    $consecutiveScheduledFallbackRunsIncludingCurrent = $(if ($currentIsExpectedBoundedFallback) { $consecutiveScheduledFallbackRuns + 1 } else { 0 })
    $thresholdExceeded = ($currentIsExpectedBoundedFallback -and $scheduledFallbackRunCountIncludingCurrent -ge $ThresholdRuns)

    return [pscustomobject]@{
        invocation_mode = $CurrentInvocationMode
        window_hours = [Math]::Abs($WindowHours)
        threshold_runs = $ThresholdRuns
        tail_lines = $TailLines
        scheduled_runs_considered = @($orderedScheduledEntries).Count
        scheduled_fallback_runs_in_window = $scheduledFallbackRunCount
        scheduled_fallback_runs_including_current = $scheduledFallbackRunCountIncludingCurrent
        consecutive_scheduled_fallback_runs = $consecutiveScheduledFallbackRuns
        consecutive_scheduled_fallback_runs_including_current = $consecutiveScheduledFallbackRunsIncludingCurrent
        threshold_exceeded = $thresholdExceeded
    }
}

function Normalize-Severity {
    param([string]$Value)

    $normalized = ([string]$Value).Trim().ToLowerInvariant()
    switch ($normalized) {
        "info" { return "info" }
        "notice" { return "notice" }
        "healthy" { return "ok" }
        "stable" { return "ok" }
        "clear" { return "ok" }
        "pass" { return "ok" }
        "watch" { return "warning" }
        "degraded" { return "warning" }
        "fail" { return "critical" }
        "error" { return "critical" }
        default {
            if ($normalized -in @("ok", "info", "notice", "warning", "critical")) {
                return $normalized
            }
            return "unknown"
        }
    }
}

function Get-SeverityRank {
    param([string]$Value)

    switch (Normalize-Severity -Value $Value) {
        "ok" { return 0 }
        "info" { return 0 }
        "notice" { return 1 }
        "warning" { return 2 }
        "critical" { return 3 }
        default { return 2 }
    }
}

function Get-HighestSeverity {
    param([string[]]$Values)

    $maxRank = -1
    $winner = "unknown"
    foreach ($value in @($Values)) {
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            continue
        }

        $normalized = Normalize-Severity -Value ([string]$value)
        $rank = Get-SeverityRank -Value $normalized
        if ($rank -gt $maxRank) {
            $maxRank = $rank
            $winner = $normalized
        }
    }

    return $winner
}

function Get-OperationalSeverity {
    param(
        [string]$BaseSeverity,
        [bool]$FallbackOnlyWarning,
        [int]$WarningCount,
        [int]$BlockCount,
        [bool]$MimIsAhead,
        [string]$WatchdogState,
        [string]$LatestExecutionStatus
    )

    $normalizedBase = Normalize-Severity -Value $BaseSeverity
    if ($normalizedBase -eq 'critical') {
        return 'critical'
    }

    $watchdogHealthy = [string]::Equals([string]$WatchdogState, 'healthy', [System.StringComparison]::OrdinalIgnoreCase)
    $latestExecution = ([string]$LatestExecutionStatus).Trim().ToLowerInvariant()
    $fallbackRiskElevated = ($WarningCount -gt 1) -or ($BlockCount -gt 0) -or $MimIsAhead -or (-not $watchdogHealthy) -or ($latestExecution -eq 'failed')

    if ($FallbackOnlyWarning -and -not $fallbackRiskElevated) {
        return 'notice'
    }

    if ($normalizedBase -eq 'warning') {
        return 'warning'
    }

    if ($normalizedBase -eq 'ok') {
        return 'info'
    }

    if ($FallbackOnlyWarning) {
        return 'warning'
    }

    return 'warning'
}

function Convert-ToStringArray {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace([string]$Value)) {
            return @()
        }
        return @([string]$Value)
    }

    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return @([string]$Value)
}

function Test-IsFallbackOnlyWarning {
    param(
        [string[]]$Warnings,
        [int]$BlockCount,
        [string]$WatchdogState,
        [bool]$MimIsAhead,
        [string]$AlertState,
        [string]$CadenceSeverity,
        [string]$SteadyState,
        [string]$LatestExecutionStatus
    )

    $warningList = @(Convert-ToStringArray -Value $Warnings)
    if (@($warningList).Count -eq 0) {
        return $false
    }

    $allWarningsAreFallback = @($warningList | Where-Object { $_ -notmatch 'state\.json too large|listener telemetry|using listener telemetry' }).Count -eq 0
    if (-not $allWarningsAreFallback) {
        return $false
    }

    if ($BlockCount -gt 0 -or $MimIsAhead) {
        return $false
    }

    if ((Normalize-Severity -Value $AlertState) -eq 'critical' -or (Normalize-Severity -Value $CadenceSeverity) -eq 'critical' -or (Normalize-Severity -Value $SteadyState) -eq 'critical') {
        return $false
    }

    if (-not [string]::Equals([string]$WatchdogState, 'healthy', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $latestExecution = ([string]$LatestExecutionStatus).Trim().ToLowerInvariant()
    if ($latestExecution -eq 'failed') {
        return $false
    }

    return $true
}

function New-ActionRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [bool]$Attempted = $false,
        [bool]$Ok = $false,
        [string]$Summary = "",
        [string]$Artifact = "",
        [AllowNull()]$Details = $null,
        [int]$DurationMs = 0
    )

    return [pscustomobject]@{
        name = $Name
        attempted = [bool]$Attempted
        ok = [bool]$Ok
        summary = [string]$Summary
        artifact = [string]$Artifact
        duration_ms = [int]$DurationMs
        details = $Details
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $started = Get-Date
    try {
        $result = & $Action
        $durationMs = [int][Math]::Round(((Get-Date) - $started).TotalMilliseconds)
        return [pscustomobject]@{
            ok = $true
            duration_ms = $durationMs
            result = $result
            error = ""
            name = $Name
        }
    }
    catch {
        $durationMs = [int][Math]::Round(((Get-Date) - $started).TotalMilliseconds)
        return [pscustomobject]@{
            ok = $false
            duration_ms = $durationMs
            result = $null
            error = [string]$_.Exception.Message
            name = $Name
        }
    }
}

function Get-StateBusSnapshot {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)

    $raw = & $ScriptPath -AsJson
    if ($raw -is [System.Array]) {
        $raw = ($raw -join "`n")
    }

    return ($raw | ConvertFrom-Json)
}

function Get-HealthSnapshotSummary {
    param([AllowNull()]$StateBus)

    if ($null -eq $StateBus) {
        return [pscustomobject]@{
            severity = "critical"
            cadence_severity = "unknown"
            steady_state = "unknown"
            alert_state = "unknown"
            latest_objective_id = ""
            latest_request_id = ""
            latest_execution_status = ""
            block_count = 0
            warning_count = 0
            watchdog_state = "unknown"
            heartbeat_age_seconds = -1
            pending_request_count = -1
            mim_is_ahead = $false
            warnings = @()
            warning_classification = "state_bus_unavailable"
            fallback_only_warning = $false
            operational_severity = "critical"
            severity_reason = "state_bus_unavailable"
            summary = "State bus snapshot unavailable."
        }
    }

    $alertState = if ($StateBus.PSObject.Properties['system_posture'] -and $StateBus.system_posture.PSObject.Properties['current_alert_state']) {
        [string]$StateBus.system_posture.current_alert_state
    }
    else {
        "unknown"
    }

    $cadenceSeverity = if ($StateBus.PSObject.Properties['cadence_health'] -and $StateBus.cadence_health.PSObject.Properties['governance'] -and $StateBus.cadence_health.governance.PSObject.Properties['adjusted_severity']) {
        [string]$StateBus.cadence_health.governance.adjusted_severity
    }
    elseif ($StateBus.PSObject.Properties['cadence_health'] -and $StateBus.cadence_health.PSObject.Properties['severity']) {
        [string]$StateBus.cadence_health.severity
    }
    else {
        "unknown"
    }

    $steadyState = if ($StateBus.PSObject.Properties['steady_state'] -and $StateBus.steady_state.PSObject.Properties['status']) {
        [string]$StateBus.steady_state.status
    }
    else {
        "unknown"
    }

    $severity = Get-HighestSeverity -Values @($alertState, $cadenceSeverity, $steadyState)
    $listener = if ($StateBus.PSObject.Properties['listener_activity']) { $StateBus.listener_activity } else { $null }
    $watchdog = if ($StateBus.PSObject.Properties['recovery_watchdog']) { $StateBus.recovery_watchdog } else { $null }
    $sync = if ($listener -and $listener.PSObject.Properties['sync']) { $listener.sync } else { $null }
    $blockCount = if ($StateBus.PSObject.Properties['blocks']) { @($StateBus.blocks).Count } else { 0 }
    $warningMessages = if ($StateBus.PSObject.Properties['warnings']) { @(Convert-ToStringArray -Value $StateBus.warnings) } else { @() }
    $warningCount = @($warningMessages).Count
    $watchdogState = if ($watchdog) { [string]$watchdog.state } else { "unknown" }
    $latestExecutionStatus = if ($listener) { [string]$listener.latest_execution_status } else { "" }
    $mimIsAhead = if ($sync -and $sync.PSObject.Properties['is_mim_ahead']) { [bool]$sync.is_mim_ahead } else { $false }
    $fallbackOnlyWarning = Test-IsFallbackOnlyWarning -Warnings $warningMessages -BlockCount $blockCount -WatchdogState $watchdogState -MimIsAhead $mimIsAhead -AlertState $alertState -CadenceSeverity $cadenceSeverity -SteadyState $steadyState -LatestExecutionStatus $latestExecutionStatus
    $warningClassification = if ($fallbackOnlyWarning) { 'state_size_fallback_only' } elseif ($warningCount -gt 0) { 'runtime_warning' } else { 'none' }
    $operationalSeverity = Get-OperationalSeverity -BaseSeverity $severity -FallbackOnlyWarning $fallbackOnlyWarning -WarningCount $warningCount -BlockCount $blockCount -MimIsAhead $mimIsAhead -WatchdogState $watchdogState -LatestExecutionStatus $latestExecutionStatus
    $severityReason = if ($fallbackOnlyWarning -and $operationalSeverity -eq 'notice') {
        'expected_bounded_fallback'
    }
    elseif ($warningClassification -eq 'state_bus_unavailable') {
        'state_bus_unavailable'
    }
    elseif ($operationalSeverity -eq 'critical') {
        'active_critical_condition'
    }
    elseif ($operationalSeverity -eq 'warning') {
        'active_warning_condition'
    }
    else {
        'nominal'
    }
    $summaryParts = @()

    $summaryParts += ("severity={0}" -f $operationalSeverity)
    if ($operationalSeverity -ne $severity) {
        $summaryParts += ("source_severity={0}" -f $severity)
    }
    if ($listener -and $listener.PSObject.Properties['latest_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$listener.latest_objective_id)) {
        $summaryParts += ("objective={0}" -f [string]$listener.latest_objective_id)
    }
    if ($listener -and $listener.PSObject.Properties['latest_execution_status'] -and -not [string]::IsNullOrWhiteSpace([string]$listener.latest_execution_status)) {
        $summaryParts += ("latest_execution={0}" -f [string]$listener.latest_execution_status)
    }
    if ($sync -and $sync.PSObject.Properties['is_mim_ahead'] -and [bool]$sync.is_mim_ahead) {
        $summaryParts += ("mim_ahead_by={0}" -f [int]$sync.pending_request_count)
    }
    if ($blockCount -gt 0) {
        $summaryParts += ("blocks={0}" -f $blockCount)
    }

    return [pscustomobject]@{
        severity = $severity
        operational_severity = $operationalSeverity
        cadence_severity = Normalize-Severity -Value $cadenceSeverity
        steady_state = Normalize-Severity -Value $steadyState
        alert_state = Normalize-Severity -Value $alertState
        latest_objective_id = if ($listener) { [string]$listener.latest_objective_id } else { "" }
        latest_request_id = if ($listener) { [string]$listener.latest_request_id } else { "" }
        latest_execution_status = $latestExecutionStatus
        block_count = $blockCount
        warning_count = $warningCount
        watchdog_state = $watchdogState
        heartbeat_age_seconds = if ($watchdog -and $watchdog.PSObject.Properties['heartbeat_age_seconds']) { [int]$watchdog.heartbeat_age_seconds } else { -1 }
        pending_request_count = if ($sync -and $sync.PSObject.Properties['pending_request_count']) { [int]$sync.pending_request_count } else { -1 }
        mim_is_ahead = if ($sync -and $sync.PSObject.Properties['is_mim_ahead']) { [bool]$sync.is_mim_ahead } else { $false }
        warnings = @($warningMessages)
        warning_classification = $warningClassification
        fallback_only_warning = $fallbackOnlyWarning
        severity_reason = $severityReason
        summary = ($summaryParts -join "; ")
    }
}

$sharedStateAbs = Resolve-LocalPath -PathValue $SharedStateDir
$outputAbs = Resolve-LocalPath -PathValue $OutputPath
$logAbs = Resolve-LocalPath -PathValue $LogPath
$stateBusAbs = Resolve-LocalPath -PathValue $LightweightStateBusScriptPath
$syncAbs = Resolve-LocalPath -PathValue $SharedStateSyncScriptPath
$watchdogAbs = Resolve-LocalPath -PathValue $RecoveryWatchdogScriptPath
$driftGuardAbs = Resolve-LocalPath -PathValue $WatchdogDriftGuardScriptPath
$publicRouteHealthAbs = Resolve-LocalPath -PathValue $PublicRouteHealthScriptPath
$readinessAbs = Resolve-LocalPath -PathValue $ReadinessScriptPath
$localVerificationAbs = Resolve-LocalPath -PathValue $LocalVerificationScriptPath
$localVerificationQueueAbs = Resolve-LocalPath -PathValue $LocalVerificationQueuePath

foreach ($required in @($stateBusAbs, $syncAbs, $watchdogAbs, $driftGuardAbs)) {
    if (-not (Test-Path -Path $required)) {
        throw "Required script not found: $required"
    }
}

if (-not (Test-Path -Path $sharedStateAbs)) {
    New-Item -ItemType Directory -Path $sharedStateAbs -Force | Out-Null
}

$actions = New-Object System.Collections.Generic.List[object]
$startedAt = (Get-Date).ToUniversalTime()

$shouldRunDriftGuard = ($Profile -ne "light")
if ($shouldRunDriftGuard) {
    $driftGuardStep = Invoke-Step -Name "watchdog_drift_guard" -Action {
        & $driftGuardAbs -AutoCorrect -RestartUiOnFailure:$RestartUiOnFailure -EmitJson | ConvertFrom-Json
    }

    $driftSummary = if ($driftGuardStep.ok -and $driftGuardStep.result) {
        $detected = [bool]$driftGuardStep.result.detected
        $correction = if ($driftGuardStep.result.PSObject.Properties['correction']) { $driftGuardStep.result.correction } else { $null }
        if (-not $detected) {
            "Watchdog drift guard found no stale watchdog mismatch."
        }
        elseif ($correction -and [bool]$correction.succeeded) {
            "Watchdog drift guard detected stale watchdog telemetry and completed one-shot correction."
        }
        else {
            "Watchdog drift guard detected stale watchdog telemetry; correction did not complete cleanly."
        }
    }
    else {
        $driftGuardStep.error
    }

    $actions.Add((New-ActionRecord -Name "watchdog_drift_guard" -Attempted $true -Ok $driftGuardStep.ok -Summary $driftSummary -Artifact (Join-Path $sharedStateAbs "tod_watchdog_drift_guard.latest.json") -Details $(if ($driftGuardStep.ok) { $driftGuardStep.result } else { [pscustomobject]@{ error = $driftGuardStep.error } }) -DurationMs $driftGuardStep.duration_ms))
}
else {
    $actions.Add((New-ActionRecord -Name "watchdog_drift_guard" -Attempted $false -Ok $true -Summary "Skipped in light profile." -Artifact (Join-Path $sharedStateAbs "tod_watchdog_drift_guard.latest.json")))
}

$preflightStep = Invoke-Step -Name "preflight_snapshot" -Action {
    Get-StateBusSnapshot -ScriptPath $stateBusAbs
}

$preflightBus = if ($preflightStep.ok) { $preflightStep.result } else { $null }
$preflightSummary = Get-HealthSnapshotSummary -StateBus $preflightBus
$actions.Add((New-ActionRecord -Name "preflight_snapshot" -Attempted $true -Ok $preflightStep.ok -Summary $(if ($preflightStep.ok) { $preflightSummary.summary } else { $preflightStep.error }) -Details $(if ($preflightStep.ok) { $preflightSummary } else { [pscustomobject]@{ error = $preflightStep.error } }) -DurationMs $preflightStep.duration_ms))

$shouldRefreshSharedState = ($Profile -ne "light")
$shouldRunWatchdog = ($Profile -ne "light")
$shouldRunReadiness = ($Profile -eq "deep")
$shouldRunLocalVerification = ($Profile -eq "deep") -or ((Get-SeverityRank -Value $preflightSummary.severity) -ge 1)

if ($shouldRefreshSharedState) {
    $syncStep = Invoke-Step -Name "shared_state_refresh" -Action {
        $syncArgs = @{ RefreshMimContextFromSsh = $true; PublishTodStatusToMimArm = $true }
        if ($RefreshAgentMimReadiness -or $Profile -eq "deep") {
            $syncArgs.RefreshAgentMimReadiness = $true
        }

        & $syncAbs @syncArgs
    }

    $syncDetails = if ($syncStep.ok -and $null -ne $syncStep.result) {
        $integrationStatusPath = if ($syncStep.result.PSObject.Properties['files'] -and $syncStep.result.files.PSObject.Properties['integration_status'] -and -not [string]::IsNullOrWhiteSpace([string]$syncStep.result.files.integration_status)) {
            [string]$syncStep.result.files.integration_status
        }
        else {
            [string](Join-Path $sharedStateAbs 'integration_status.json')
        }

        $integrationStatusDoc = Read-JsonFileIfExists -PathValue $integrationStatusPath
        [pscustomobject]@{
            integration_status_path = $integrationStatusPath
            compatible = if ($integrationStatusDoc -and $integrationStatusDoc.PSObject.Properties['compatible']) { [bool]$integrationStatusDoc.compatible } else { $false }
            compatibility_reason = if ($integrationStatusDoc -and $integrationStatusDoc.PSObject.Properties['compatibility_reason']) { [string]$integrationStatusDoc.compatibility_reason } else { '' }
            objective_alignment = if ($integrationStatusDoc -and $integrationStatusDoc.PSObject.Properties['objective_alignment']) { $integrationStatusDoc.objective_alignment } else { $null }
            mim_refresh = if ($integrationStatusDoc -and $integrationStatusDoc.PSObject.Properties['mim_refresh']) { $integrationStatusDoc.mim_refresh } else { $null }
            mim_status = if ($integrationStatusDoc -and $integrationStatusDoc.PSObject.Properties['mim_status']) { $integrationStatusDoc.mim_status } else { $null }
            live_task_request = if ($integrationStatusDoc -and $integrationStatusDoc.PSObject.Properties['live_task_request']) { $integrationStatusDoc.live_task_request } else { $null }
        }
    }
    else {
        [pscustomobject]@{ error = $syncStep.error }
    }

    $syncSummary = if ($syncStep.ok -and $syncDetails.objective_alignment -and $syncDetails.compatible) {
        $alignment = [string]$syncDetails.objective_alignment.status
        $todObjective = if ($syncDetails.objective_alignment.PSObject.Properties['tod_current_objective']) { [string]$syncDetails.objective_alignment.tod_current_objective } else { '' }
        $mimObjective = if ($syncDetails.objective_alignment.PSObject.Properties['mim_objective_active']) { [string]$syncDetails.objective_alignment.mim_objective_active } else { '' }
        "Shared-state sync refreshed canonical MIM context; compatibility is $([string]$syncDetails.compatibility_reason) and objective alignment is $alignment (TOD=$todObjective, MIM=$mimObjective)."
    }
    elseif ($syncStep.ok) {
        $missingParts = @()
        if (-not $syncDetails.compatible) {
            $missingParts += 'compatibility=false'
        }
        if (-not $syncDetails.objective_alignment) {
            $missingParts += 'objective_alignment=missing'
        }
        if (-not $syncDetails.mim_refresh) {
            $missingParts += 'mim_refresh=missing'
        }
        if (@($missingParts).Count -eq 0) {
            $missingParts += 'integration_status_unreadable'
        }
        "Shared-state sync completed, but follow-up review is still needed: $($missingParts -join ', ')."
    }
    else {
        $syncStep.error
    }

    $actions.Add((New-ActionRecord -Name "shared_state_refresh" -Attempted $true -Ok $syncStep.ok -Summary $syncSummary -Details $syncDetails -DurationMs $syncStep.duration_ms))
}
else {
    $actions.Add((New-ActionRecord -Name "shared_state_refresh" -Attempted $false -Ok $true -Summary "Skipped in light profile."))
}

if ($shouldRunWatchdog) {
    $watchdogStep = Invoke-Step -Name "watchdog_run_once" -Action {
        $watchdogArgs = @{ RunOnce = $true }
        if ($RestartUiOnFailure) {
            $watchdogArgs.RestartUiOnFailure = $true
        }

        & $watchdogAbs @watchdogArgs
        $watchdogStatePath = Join-Path $sharedStateAbs "tod_recovery_watchdog.latest.json"
        if (Test-Path -Path $watchdogStatePath) {
            return (Get-Content -Path $watchdogStatePath -Raw | ConvertFrom-Json)
        }

        return $null
    }

    $watchdogSummary = if ($watchdogStep.ok -and $watchdogStep.result) {
        "Watchdog one-shot completed; current state is $([string]$watchdogStep.result.state)."
    }
    elseif ($watchdogStep.ok) {
        "Watchdog one-shot completed."
    }
    else {
        $watchdogStep.error
    }

    $actions.Add((New-ActionRecord -Name "watchdog_run_once" -Attempted $true -Ok $watchdogStep.ok -Summary $watchdogSummary -Artifact (Join-Path $sharedStateAbs "tod_recovery_watchdog.latest.json") -Details $(if ($watchdogStep.ok) { $watchdogStep.result } else { [pscustomobject]@{ error = $watchdogStep.error } }) -DurationMs $watchdogStep.duration_ms))
}
else {
    $actions.Add((New-ActionRecord -Name "watchdog_run_once" -Attempted $false -Ok $true -Summary "Skipped in light profile."))
}

$postflightStep = Invoke-Step -Name "postflight_snapshot" -Action {
    Get-StateBusSnapshot -ScriptPath $stateBusAbs
}

$postflightBus = if ($postflightStep.ok) { $postflightStep.result } else { $null }
$postflightSummary = Get-HealthSnapshotSummary -StateBus $postflightBus
$actions.Add((New-ActionRecord -Name "postflight_snapshot" -Attempted $true -Ok $postflightStep.ok -Summary $(if ($postflightStep.ok) { $postflightSummary.summary } else { $postflightStep.error }) -Details $(if ($postflightStep.ok) { $postflightSummary } else { [pscustomobject]@{ error = $postflightStep.error } }) -DurationMs $postflightStep.duration_ms))

$publicRouteHealthStep = if (Test-Path -Path $publicRouteHealthAbs) {
    Invoke-Step -Name "public_route_health" -Action {
        & $publicRouteHealthAbs -EmitJson | ConvertFrom-Json
    }
}
else {
    [pscustomobject]@{
        ok = $true
        duration_ms = 0
        result = $null
        error = ""
        name = "public_route_health"
    }
}

$publicRouteHealthSummary = if ($publicRouteHealthStep.ok -and $publicRouteHealthStep.result) {
    [string]$publicRouteHealthStep.result.summary
}
elseif ($publicRouteHealthStep.ok) {
    "Skipped because the public route health script was not present."
}
else {
    $publicRouteHealthStep.error
}

$actions.Add((New-ActionRecord -Name "public_route_health" -Attempted $(Test-Path -Path $publicRouteHealthAbs) -Ok $publicRouteHealthStep.ok -Summary $publicRouteHealthSummary -Artifact (Join-Path $sharedStateAbs "tod_public_route_health.latest.json") -Details $(if ($publicRouteHealthStep.ok) { $publicRouteHealthStep.result } else { [pscustomobject]@{ error = $publicRouteHealthStep.error } }) -DurationMs $publicRouteHealthStep.duration_ms))

if ($shouldRunLocalVerification -and (Test-Path -Path $localVerificationAbs) -and (Test-Path -Path $localVerificationQueueAbs)) {
    $localVerificationStep = Invoke-Step -Name "local_verification" -Action {
        & $localVerificationAbs -TaskQueuePath $localVerificationQueueAbs -EmitJson | ConvertFrom-Json
    }

    $localVerificationSummary = if ($localVerificationStep.ok -and $localVerificationStep.result) {
        $strictReady = if ($localVerificationStep.result.summary.PSObject.Properties['strict_live_update_ready']) { [bool]$localVerificationStep.result.summary.strict_live_update_ready } else { $false }
        if ($strictReady) {
            "Local verification passed strict gate."
        }
        else {
            "Local verification found gaps in local readiness."
        }
    }
    else {
        $localVerificationStep.error
    }

    $actions.Add((New-ActionRecord -Name "local_verification" -Attempted $true -Ok $localVerificationStep.ok -Summary $localVerificationSummary -Artifact $(if ($localVerificationStep.ok -and $localVerificationStep.result) { [string]$localVerificationQueueAbs } else { "" }) -Details $(if ($localVerificationStep.ok) { $localVerificationStep.result.summary } else { [pscustomobject]@{ error = $localVerificationStep.error } }) -DurationMs $localVerificationStep.duration_ms))
}
elseif ($shouldRunLocalVerification) {
    $actions.Add((New-ActionRecord -Name "local_verification" -Attempted $false -Ok $true -Summary "Skipped because the local verification queue was not present." -Artifact $localVerificationQueueAbs))
}
else {
    $actions.Add((New-ActionRecord -Name "local_verification" -Attempted $false -Ok $true -Summary "Not required for the current profile and health state."))
}

if ($shouldRunReadiness -and (Test-Path -Path $readinessAbs)) {
    $readinessStep = Invoke-Step -Name "codex_readiness" -Action {
        & $readinessAbs -EmitJson | ConvertFrom-Json
    }

    $readinessSummary = if ($readinessStep.ok -and $readinessStep.result) {
        if ([bool]$readinessStep.result.summary.gate_passed) {
            "Codex readiness daily gate passed."
        }
        else {
            "Codex readiness daily gate failed."
        }
    }
    else {
        $readinessStep.error
    }

    $readinessArtifact = ""
    if ($readinessStep.ok -and $readinessStep.result) {
        if ($readinessStep.result.PSObject.Properties['artifact'] -and -not [string]::IsNullOrWhiteSpace([string]$readinessStep.result.artifact)) {
            $readinessArtifact = [string]$readinessStep.result.artifact
        }
        elseif ($readinessStep.result.PSObject.Properties['artifacts'] -and $readinessStep.result.artifacts.PSObject.Properties['latest_path']) {
            $readinessArtifact = [string]$readinessStep.result.artifacts.latest_path
        }
    }

    $actions.Add((New-ActionRecord -Name "codex_readiness" -Attempted $true -Ok $readinessStep.ok -Summary $readinessSummary -Artifact $readinessArtifact -Details $(if ($readinessStep.ok) { $readinessStep.result } else { [pscustomobject]@{ error = $readinessStep.error } }) -DurationMs $readinessStep.duration_ms))
}
elseif ($shouldRunReadiness) {
    $actions.Add((New-ActionRecord -Name "codex_readiness" -Attempted $false -Ok $true -Summary "Skipped because the readiness script was not present." -Artifact $readinessAbs))
}
else {
    $actions.Add((New-ActionRecord -Name "codex_readiness" -Attempted $false -Ok $true -Summary "Reserved for deep maintenance runs."))
}

$completedAt = (Get-Date).ToUniversalTime()
$historySummary = Get-MaintenanceHistorySummary -LogPathValue $logAbs -CurrentInvocationMode $InvocationMode -CurrentSeverityReason ([string]$postflightSummary.severity_reason) -WindowHours $FallbackWarningWindowHours -ThresholdRuns $FallbackWarningThresholdRuns -TailLines $FallbackWarningTailLines
$overallSeverity = [string]$postflightSummary.operational_severity
$sourceSeverity = [string]$postflightSummary.severity
$overallSeverityReason = [string]$postflightSummary.severity_reason
$publicRouteBlockers = @()
if ($publicRouteHealthStep.ok -and $publicRouteHealthStep.result -and $publicRouteHealthStep.result.PSObject.Properties['blockers']) {
    $publicRouteBlockers = @($publicRouteHealthStep.result.blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

if (@($publicRouteBlockers).Count -gt 0 -and (Get-SeverityRank -Value $overallSeverity) -lt 2) {
    $overallSeverity = 'warning'
    $overallSeverityReason = 'public_tod_route_divergence'
}

if ([bool]$historySummary.threshold_exceeded -and $overallSeverity -eq 'notice') {
    $overallSeverity = 'warning'
    $overallSeverityReason = 'fallback_persistence_threshold_exceeded'
}
$overallStatus = if ((Get-SeverityRank -Value $overallSeverity) -ge 3) {
    "needs_attention"
}
elseif ([bool]$postflightSummary.fallback_only_warning) {
    "healthy_with_fallback"
}
elseif ((Get-SeverityRank -Value $overallSeverity) -ge 2) {
    "warning"
}
else {
    "healthy"
}

$failedActions = @($actions | Where-Object { [bool]$_.attempted -and -not [bool]$_.ok })
$recommendations = @()
if ($overallStatus -eq "needs_attention") {
    $recommendations += "Inspect shared_state/tod_recovery_watchdog.latest.json and the listener artifacts for repeated freeze or alignment failures."
}
if ($postflightSummary.mim_is_ahead) {
    $recommendations += "MIM still appears ahead of TOD; verify upstream canonical export freshness and request publication."
}
if (@($publicRouteBlockers).Count -gt 0) {
    $recommendations += "Public /tod is not serving the expected full UI or is exposing inconsistent canonical state; monitor shared_state/tod_public_route_health.latest.json and treat the route definition itself as external until it becomes repo-managed."
}
if (@($failedActions).Count -gt 0) {
    $recommendations += "One or more maintenance steps failed; review the action log in shared_state/TOD_SELF_HEALTH_RUN.log.jsonl."
}
if ($overallStatus -eq "healthy_with_fallback") {
    if ($overallSeverity -eq 'warning' -and $overallSeverityReason -eq 'fallback_persistence_threshold_exceeded') {
        $recommendations += ("TOD remains operationally healthy, but fallback has persisted across {0} scheduled maintenance runs inside the last {1} hours; treat it as warning-level until the full-state path is restored or fallback becomes a first-class operating mode." -f [int]$historySummary.scheduled_fallback_runs_including_current, [int]$historySummary.window_hours)
    }
    else {
        $recommendations += "TOD is operationally healthy and maintenance is non-failing, but large state.json keeps the system on listener-telemetry fallback; only escalate if fallback scope grows, evidence quality drops, or adjacent health signals degrade."
    }
}
elseif ($overallStatus -eq "warning") {
    $recommendations += "Residual warnings remain; if they persist across scheduled runs, inspect cadence health or run the deep maintenance profile."
}
if (@($recommendations).Count -eq 0) {
    $recommendations += "No immediate follow-up is required from this maintenance pass."
}

$reportSummary = "TOD self-health maintenance completed, but unresolved critical issues remain."
if ($overallStatus -eq "healthy") {
    $reportSummary = "TOD self-health maintenance completed without detecting unresolved degradation."
}
elseif ($overallStatus -eq "healthy_with_fallback") {
    if ($overallSeverity -eq 'warning' -and $overallSeverityReason -eq 'fallback_persistence_threshold_exceeded') {
        $reportSummary = "TOD self-health maintenance completed successfully, but bounded fallback has persisted across repeated scheduled runs and now merits warning-level attention."
    }
    else {
        $reportSummary = "TOD self-health maintenance completed successfully; bounded oversized-state fallback is active, but no failing or degraded condition was detected."
    }
}
elseif ($overallStatus -eq "warning") {
    $reportSummary = "TOD self-health maintenance completed, but residual warnings remain."
}

$reportMap = [ordered]@{
    generated_at = $completedAt.ToString("o")
    source = $runnerId
    profile = $Profile
    invocation_mode = $InvocationMode
    started_at = $startedAt.ToString("o")
    completed_at = $completedAt.ToString("o")
    duration_seconds = [Math]::Round(($completedAt - $startedAt).TotalSeconds, 1)
    overall_status = $overallStatus
    overall_severity = $overallSeverity
    source_severity = $sourceSeverity
    severity_reason = $overallSeverityReason
    summary = $reportSummary
    preflight = $preflightSummary
    postflight = $postflightSummary
    history = $historySummary
    recommendations = @($recommendations)
    actions = @($actions.ToArray())
}

$report = New-Object PSObject -Property $reportMap

Write-Utf8NoBomJson -PathValue $outputAbs -Payload $report
Append-Utf8NoBomJsonLine -PathValue $logAbs -Payload $report

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 20 | Write-Output
}
else {
    $report
}