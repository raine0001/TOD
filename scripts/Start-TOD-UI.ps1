param(
    [int]$Port = 8844,
    [switch]$OpenAppWindow,
    [switch]$NoAutoOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiRoot = Join-Path $repoRoot "ui"
$indexPath = Join-Path $uiRoot "index.html"
$todScript = Join-Path $PSScriptRoot "TOD.ps1"
$configPath = Join-Path $repoRoot "tod/config/tod-config.json"
$defaultLogPath = Join-Path $repoRoot "tod/out/mim-http.log"
$uiCrashLogPath = Join-Path $repoRoot "tod/out/tod-ui-crash.log"
$statePath = Join-Path $repoRoot "tod/data/state.json"
$maxStateReadBytes = 256MB
$lightweightStateBusScript = Join-Path $PSScriptRoot "Get-TODLightweightStateBus.ps1"
$listenerStagePath = Join-Path $repoRoot "tod/out/context-sync/listener"
$listenerJournalPath = Join-Path $listenerStagePath "TOD_LOOP_JOURNAL.latest.json"
$listenerResultPath = Join-Path $listenerStagePath "TOD_MIM_TASK_RESULT.latest.json"
$listenerRequestPath = Join-Path $listenerStagePath "MIM_TOD_TASK_REQUEST.latest.json"
$coordinationEscalationPath = Join-Path $listenerStagePath "TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json"
$regressionStallStatePath = Join-Path $listenerStagePath "TOD_REGRESSION_STALL_STATE.latest.json"
$currentBuildStatePath = Join-Path $repoRoot "shared_state/current_build_state.json"
$recoveryWatchdogStatePath = Join-Path $repoRoot "shared_state/tod_recovery_watchdog.latest.json"
$voiceAdapterConfigPath = Join-Path $repoRoot "tod/config/voice-adapter.json"
$voiceAdapterTelemetryPath = Join-Path $repoRoot "shared_state/voice_adapter_status.json"
$voiceAdapterInboxPath = Join-Path $repoRoot "tod/inbox/voice/events"
$voiceListenerPidPath = Join-Path $repoRoot "shared_state/voice_listener.pid"
$shareArtifacts = [ordered]@{
    "chatgpt_update_md" = [pscustomobject]@{ label = "ChatGPT Update (Markdown)"; path = (Join-Path $repoRoot "shared_state/chatgpt_update.md") }
    "chatgpt_update_json" = [pscustomobject]@{ label = "ChatGPT Update (JSON)"; path = (Join-Path $repoRoot "shared_state/chatgpt_update.json") }
    "shared_development_log_plan" = [pscustomobject]@{ label = "Shared Development Log Plan"; path = (Join-Path $repoRoot "shared_state/shared_development_log_plan.json") }
    "mim_context_export_latest_json" = [pscustomobject]@{ label = "MIM Context Export (Latest JSON)"; path = (Join-Path $repoRoot "tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.json") }
    "mim_context_export_latest_yaml" = [pscustomobject]@{ label = "MIM Context Export (Latest YAML)"; path = (Join-Path $repoRoot "tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.yaml") }
    "formal_pass_receipt_latest" = [pscustomobject]@{ label = "Formal Pass Receipt (Latest)"; path = (Join-Path $repoRoot "tod/out/context-sync/exports/TOD_FORMAL_PASS_RECEIPT.latest.json") }
}

if (-not (Test-Path -Path $indexPath)) {
    throw "UI file not found at $indexPath"
}
if (-not (Test-Path -Path $todScript)) {
    throw "TOD script not found at $todScript"
}

function Resolve-AppBrowserPath {
    $commandCandidates = @("msedge.exe", "chrome.exe")
    foreach ($cmdName in $commandCandidates) {
        try {
            $cmd = Get-Command -Name $cmdName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
                return [string]$cmd.Source
            }
        }
        catch {
        }
    }

    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Open-TodUiClient {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [bool]$AppMode
    )

    if ($NoAutoOpen) {
        Write-Host "Auto-open disabled. Browse to $Url"
        return
    }

    if ($AppMode) {
        $browserPath = Resolve-AppBrowserPath
        if ($null -ne $browserPath) {
            $args = @(
                "--app=$Url",
                "--new-window",
                "--start-maximized"
            )
            Start-Process -FilePath $browserPath -ArgumentList $args | Out-Null
            Write-Host "Opened TOD UI in app window: $Url"
            return
        }

        Write-Host "No app-capable Chromium browser found; opening regular browser window." -ForegroundColor Yellow
    }

    Start-Process $Url | Out-Null
    Write-Host "Opened TOD UI in browser: $Url"
}

$listener = $null
$activePort = $Port
$maxPortAttempts = 15
$started = $false

for ($i = 0; $i -lt $maxPortAttempts; $i++) {
    $candidatePort = $Port + $i
    $candidate = New-Object System.Net.HttpListener
    $candidate.Prefixes.Add("http://localhost:$candidatePort/")

    try {
        $candidate.Start()
        $listener = $candidate
        $activePort = $candidatePort
        $started = $true
        break
    }
    catch {
        $candidate.Close()
        if ($i -eq ($maxPortAttempts - 1)) {
            throw
        }
    }
}

if (-not $started -or $null -eq $listener) {
    throw "Failed to start TOD UI listener."
}

if ($activePort -ne $Port) {
    Write-Host "Requested port $Port was unavailable; using $activePort instead."
}

Write-Host "TOD UI running at http://localhost:$activePort/"
Write-Host "Press Ctrl+C to stop."

$uiUrl = "http://localhost:$activePort/"
Open-TodUiClient -Url $uiUrl -AppMode ([bool]$OpenAppWindow)

function Write-UiCrashLog {
    param([string]$Message)
    try {
        $line = "[{0}] {1}" -f (Get-Date).ToUniversalTime().ToString("o"), $Message
        Add-Content -Path $uiCrashLogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

function Write-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
        $Response.StatusCode = $StatusCode
        $Response.ContentType = "application/json; charset=utf-8"
        $Response.ContentLength64 = $bytes.LongLength
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    catch {
        # Response may already be committed; avoid cascading failures in endpoint catch blocks.
        Write-UiCrashLog ("[WRITE-JSON-ERROR] " + $_.Exception.Message)
    }
    finally {
        try {
            if ($Response -and $Response.OutputStream) {
                $Response.OutputStream.Close()
            }
        }
        catch {
        }
        try {
            $Response.Close()
        }
        catch {
        }
    }
}

function Test-ShouldUseLightweightStateBus {
    if (-not (Test-Path -Path $statePath)) {
        return $true
    }

    try {
        $item = Get-Item -Path $statePath -ErrorAction Stop
        return ([int64]$item.Length -gt [int64]$maxStateReadBytes)
    }
    catch {
        return $true
    }
}

function Invoke-LightweightUiAction {
    param(
        [Parameter(Mandatory = $true)][string]$Action
    )

    if (-not (Test-Path -Path $lightweightStateBusScript)) {
        throw "Missing lightweight state bus script: $lightweightStateBusScript"
    }

    $raw = & $lightweightStateBusScript -AsJson
    $payload = $raw | ConvertFrom-Json

    switch ($Action) {
        "get-state-bus" { return $payload }
        "get-reliability" { return $payload.reliability }
        "show-reliability-dashboard" { return $payload.reliability_dashboard }
        "show-failure-taxonomy" { return $payload.failure_taxonomy }
        "get-engineering-loop-summary" { return $payload.engineering_summary }
        "get-engineering-signal" { return $payload.engineering_signal }
        "get-engineering-loop-history" { return $payload.scorecard_history }
        default {
            throw "Unsupported lightweight action: $Action"
        }
    }
}

function Get-RecentLogLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [int]$Tail = 80
    )

    if (-not (Test-Path -Path $LogPath)) {
        return @()
    }

    $safeTail = if ($Tail -lt 1) { 1 } elseif ($Tail -gt 500) { 500 } else { $Tail }
    return @(Get-Content -Path $LogPath -Tail $safeTail -ErrorAction SilentlyContinue)
}

function Get-MimeTypeForPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        ".json" { return "application/json; charset=utf-8" }
        ".yaml" { return "application/x-yaml; charset=utf-8" }
        ".yml" { return "application/x-yaml; charset=utf-8" }
        ".md" { return "text/markdown; charset=utf-8" }
        ".txt" { return "text/plain; charset=utf-8" }
        default { return "application/octet-stream" }
    }
}

function Get-ShareArtifactsPayload {
    param([int]$ActivePort)

    $items = @()
    foreach ($entry in $shareArtifacts.GetEnumerator()) {
        $key = [string]$entry.Key
        $spec = $entry.Value
        $fullPath = [string]$spec.path
        $exists = Test-Path -Path $fullPath
        $item = [ordered]@{
            key = $key
            label = [string]$spec.label
            path = $fullPath
            exists = $exists
            download_url = "/api/share-download?key=$([uri]::EscapeDataString($key))"
            preview_url = "/api/share-open?key=$([uri]::EscapeDataString($key))"
            file_uri = "file:///" + ($fullPath -replace "\\", "/")
        }

        if ($exists) {
            $file = Get-Item -Path $fullPath
            $item.last_write_time_utc = $file.LastWriteTimeUtc.ToString("o")
            $item.length = [int64]$file.Length
        }

        $items += [pscustomobject]$item
    }

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        base_url = "http://localhost:$ActivePort"
        artifacts = @($items)
    }
}

function Get-TaskProgressWeight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    $normalized = $Status.Trim().ToLowerInvariant()
    switch ($normalized) {
        "pass" { return 1.0 }
        "reviewed_pass" { return 1.0 }
        "done" { return 1.0 }
        "completed" { return 1.0 }
        "implemented" { return 0.75 }
        "in_progress" { return 0.5 }
        "active" { return 0.5 }
        "revise" { return 0.35 }
        "planned" { return 0.15 }
        "open" { return 0.1 }
        default { return 0.0 }
    }
}

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
    if ($index -lt 0) {
        $index = 0
    }
    if ($index -ge $sorted.Count) {
        $index = $sorted.Count - 1
    }

    return [math]::Round([double]$sorted[$index], 1)
}

function Get-CadenceHealth {
    param(
        $ListenerActivity,
        $RecoveryWatchdog
    )

    if ($null -eq $ListenerActivity) {
        return [pscustomobject]@{
            available = $false
            severity = "unknown"
            alerts = @("no_listener_activity")
            stream = [pscustomobject]@{
                aligned = $false
                task_delta = -1
                loop_idle_sec = -1
            }
            cadence = [pscustomobject]@{
                sample_size = 0
                avg_sec = 0
                p50_sec = 0
                p95_sec = 0
                retry_rate = 0
            }
            thresholds = [pscustomobject]@{
                warning_cycle_sec = 180
                critical_cycle_sec = 300
                warning_sync_delta = 1
                critical_sync_delta = 3
                warning_retry_rate = 0.6
            }
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
        $requestId = if ($entry.PSObject.Properties['request_id']) { [string]$entry.request_id } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($requestId)) {
            $requestIds += $requestId
        }

        $timestampValue = ""
        if ($entry.PSObject.Properties['timestamp']) {
            $timestampValue = [string]$entry.timestamp
        }
        $ts = Convert-ToDateTimeOffsetOrNull -Value $timestampValue
        if ($null -ne $ts -and $null -ne $lastTs) {
            $intervals.Add(($ts - $lastTs).TotalSeconds)
        }
        if ($null -ne $ts) {
            $lastTs = $ts
        }
    }

    $avgSec = if ($intervals.Count -gt 0) { [math]::Round((($intervals | Measure-Object -Average).Average), 1) } else { 0 }
    $p50Sec = Get-PercentileValue -Values ([double[]]$intervals.ToArray()) -Percentile 50
    $p95Sec = Get-PercentileValue -Values ([double[]]$intervals.ToArray()) -Percentile 95

    $uniqueRequestIds = @($requestIds | Sort-Object -Unique)
    $retryRate = if ($requestIds.Count -gt 0) {
        [math]::Round((($requestIds.Count - $uniqueRequestIds.Count) / [double]$requestIds.Count), 3)
    }
    else {
        0
    }

    $latestTimestamp = if ($ListenerActivity.PSObject.Properties['latest_timestamp']) { [string]$ListenerActivity.latest_timestamp } else { "" }
    $latestTs = Convert-ToDateTimeOffsetOrNull -Value $latestTimestamp
    $loopIdleSec = -1
    if ($null -ne $latestTs) {
        $loopIdleSec = [math]::Round(([DateTimeOffset]::UtcNow - $latestTs).TotalSeconds, 1)
    }
    elseif ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['heartbeat_age_seconds']) {
        $loopIdleSec = [double]([int]$RecoveryWatchdog.heartbeat_age_seconds)
    }

    $syncTaskDelta = 0
    $sync = if ($ListenerActivity.PSObject.Properties['sync']) { $ListenerActivity.sync } else { $null }
    if ($sync -and $sync.PSObject.Properties['request_task_number'] -and $sync.PSObject.Properties['result_task_number']) {
        $reqTask = [int]$sync.request_task_number
        $resTask = [int]$sync.result_task_number
        if ($reqTask -ge 0 -and $resTask -ge 0) {
            $syncTaskDelta = [math]::Abs($reqTask - $resTask)
        }
    }

    $alerts = New-Object System.Collections.Generic.List[string]
    $severity = "ok"

    if ($loopIdleSec -gt $criticalCycleSec) {
        $alerts.Add("loop_idle_gt_${criticalCycleSec}s")
        $severity = "critical"
    }
    elseif ($loopIdleSec -gt $warningCycleSec) {
        $alerts.Add("loop_idle_gt_${warningCycleSec}s")
        if ($severity -ne "critical") {
            $severity = "warning"
        }
    }

    if ($syncTaskDelta -gt $criticalSyncDelta) {
        $alerts.Add("sync_delta_gt_${criticalSyncDelta}")
        $severity = "critical"
    }
    elseif ($syncTaskDelta -gt $warningSyncDelta) {
        $alerts.Add("sync_delta_gt_${warningSyncDelta}")
        if ($severity -ne "critical") {
            $severity = "warning"
        }
    }

    if ($retryRate -gt $warningRetryRate) {
        $alerts.Add("retry_rate_gt_60pct")
        if ($severity -eq "ok") {
            $severity = "warning"
        }
    }

    if ($alerts.Count -eq 0) {
        $alerts.Add("none")
    }

    return [pscustomobject]@{
        available = $true
        severity = $severity
        alerts = @($alerts)
        stream = [pscustomobject]@{
            aligned = ($syncTaskDelta -eq 0)
            task_delta = $syncTaskDelta
            loop_idle_sec = $loopIdleSec
        }
        cadence = [pscustomobject]@{
            sample_size = $intervals.Count
            avg_sec = $avgSec
            p50_sec = $p50Sec
            p95_sec = $p95Sec
            retry_rate = $retryRate
        }
        thresholds = [pscustomobject]@{
            warning_cycle_sec = $warningCycleSec
            critical_cycle_sec = $criticalCycleSec
            warning_sync_delta = $warningSyncDelta
            critical_sync_delta = $criticalSyncDelta
            warning_retry_rate = $warningRetryRate
        }
    }
}

function Get-VoiceAdapterStatus {
    $cfg = Read-JsonFileIfExists -Path $voiceAdapterConfigPath
    if ($null -eq $cfg) {
        return [pscustomobject]@{
            available         = $false
            enabled           = $false
            mode              = "dry_run"
            allow_microphone  = $false
            allow_camera      = $false
            require_push_to_talk = $true
            wake_phrase       = "tod"
            microphone_active = $false
            camera_active     = $false
            last_event_id     = ""
            last_intent       = ""
            last_transcript   = ""
            queued_events     = 0
            error             = "voice-adapter.json not found"
        }
    }

    $telemetry = Read-JsonFileIfExists -Path $voiceAdapterTelemetryPath

    $queuedEvents = 0
    if (Test-Path -Path $voiceAdapterInboxPath) {
        $queuedEvents = @(Get-ChildItem -Path $voiceAdapterInboxPath -Filter "voice-*.json" -ErrorAction SilentlyContinue).Count
    }

    $micActive = $false
    if (Test-Path -Path $voiceListenerPidPath) {
        try {
            $listenerPid = [int](Get-Content -Path $voiceListenerPidPath -Raw -ErrorAction SilentlyContinue).Trim()
            $micActive = ($null -ne (Get-Process -Id $listenerPid -ErrorAction SilentlyContinue))
        } catch { }
    }

    return [pscustomobject]@{
        available         = $true
        enabled           = [bool]$cfg.enabled
        mode              = if ($cfg.PSObject.Properties["mode"]) { [string]$cfg.mode } else { "dry_run" }
        allow_microphone  = [bool]$cfg.allow_microphone
        allow_camera      = [bool]$cfg.allow_camera
        require_push_to_talk = if ($cfg.PSObject.Properties["require_push_to_talk"]) { [bool]$cfg.require_push_to_talk } else { $true }
        wake_phrase       = if ($cfg.PSObject.Properties["wake_phrase"]) { [string]$cfg.wake_phrase } else { "tod" }
        microphone_active = $micActive
        camera_active     = $false
        last_event_id     = if ($telemetry -and $telemetry.PSObject.Properties["last_event_id"]) { [string]$telemetry.last_event_id } else { "" }
        last_intent       = if ($telemetry -and $telemetry.PSObject.Properties["last_intent"]) { [string]$telemetry.last_intent } else { "" }
        last_transcript   = if ($telemetry -and $telemetry.PSObject.Properties["last_transcript"]) { [string]$telemetry.last_transcript } else { "" }
        queued_events     = $queuedEvents
        error             = ""
    }
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
            review_gate_passed = if ($entry.PSObject.Properties['review_gate_passed']) { [bool]$entry.review_gate_passed } else { $null }
            validator_passed = if ($entry.PSObject.Properties['validator_passed']) { [bool]$entry.validator_passed } else { $null }
            integration_compatible = if ($entry.PSObject.Properties['integration_compatible']) { [bool]$entry.integration_compatible } else { $null }
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
        $statusKey = $status.Trim().ToLowerInvariant()
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
    $recentEntries = @($normalizedEntries | Select-Object -Last 30)
    $resultRequestId = if ($resultPacket -and $resultPacket.PSObject.Properties['request_id']) { [string]$resultPacket.request_id } else { "" }
    $resultObjectiveId = Get-ObjectiveIdFromRequestId -RequestId $resultRequestId
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
        latest_review_gate_passed = if ($latest) { $latest.review_gate_passed } else { $null }
        latest_validator_passed = if ($latest) { $latest.validator_passed } else { $null }
        latest_integration_compatible = if ($latest) { $latest.integration_compatible } else { $null }
        result_request_id = $resultRequestId
        result_objective_id = $resultObjectiveId
        result_status = if ($resultPacket -and $resultPacket.PSObject.Properties['status']) { [string]$resultPacket.status } else { "" }
        result_generated_at = if ($resultPacket -and $resultPacket.PSObject.Properties['generated_at']) { [string]$resultPacket.generated_at } else { "" }
        request_task_id = $requestTaskId
        request_objective_id = if ($requestRef) { [string]$requestRef.objective } else { "" }
        request_generated_at = if ($requestPacket -and $requestPacket.PSObject.Properties['generated_at']) { [string]$requestPacket.generated_at } else { "" }
        sync = [pscustomobject]@{
            is_mim_ahead = $isMimAhead
            pending_request_count = $pendingCount
            result_request_id = $resultRequestId
            request_task_id = $requestTaskId
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
            state = "unknown"
            task_state = "idle"
            progress_classification = "no_progress_but_heartbeats_present"
            last_check_at = ""
            last_issue = ""
            last_recovery_action = ""
            last_recovery_ok = $null
            last_task_heartbeat = ""
            heartbeat_age_seconds = -1
            stall_threshold_seconds = -1
            recovery_attempts = 0
            consecutive_freezes = 0
            last_recovery_time = ""
        }
    }

    return [pscustomobject]@{
        available = $true
        state = if ($doc.PSObject.Properties["state"]) { [string]$doc.state } else { "unknown" }
        task_state = if ($doc.PSObject.Properties["task_state"]) { [string]$doc.task_state } else { "idle" }
        progress_classification = if ($doc.PSObject.Properties["progress_classification"]) { [string]$doc.progress_classification } else { "no_progress_but_heartbeats_present" }
        last_check_at = if ($doc.PSObject.Properties["last_check_at"]) { [string]$doc.last_check_at } else { "" }
        last_issue = if ($doc.PSObject.Properties["last_issue"]) { [string]$doc.last_issue } else { "" }
        last_recovery_action = if ($doc.PSObject.Properties["last_recovery_action"]) { [string]$doc.last_recovery_action } else { "" }
        last_recovery_ok = if ($doc.PSObject.Properties["last_recovery_ok"]) { $doc.last_recovery_ok } else { $null }
        last_task_heartbeat = if ($doc.PSObject.Properties["last_task_heartbeat"]) { [string]$doc.last_task_heartbeat } else { "" }
        heartbeat_age_seconds = if ($doc.PSObject.Properties["heartbeat_age_seconds"]) { [int]$doc.heartbeat_age_seconds } else { -1 }
        stall_threshold_seconds = if ($doc.PSObject.Properties["stall_threshold_seconds"]) { [int]$doc.stall_threshold_seconds } else { -1 }
        recovery_attempts = if ($doc.PSObject.Properties["recovery_attempts"]) { [int]$doc.recovery_attempts } else { 0 }
        consecutive_freezes = if ($doc.PSObject.Properties["consecutive_freezes"]) { [int]$doc.consecutive_freezes } else { 0 }
        last_recovery_time = if ($doc.PSObject.Properties["last_recovery_time"]) { [string]$doc.last_recovery_time } else { "" }
    }
}

function Get-SteadyStateHealth {
    param(
        $ListenerActivity,
        $RecoveryWatchdog,
        $CadenceHealth,
        [string]$StateWarning,
        [bool]$UsingListenerOnly
    )

    $build = Read-JsonFileIfExists -Path $currentBuildStatePath
    $coordination = Read-JsonFileIfExists -Path $coordinationEscalationPath
    $stallState = Read-JsonFileIfExists -Path $regressionStallStatePath

    $regressionAvailable = $false
    $passed = 0
    $failed = 0
    $total = 0
    $regressionGeneratedAt = ""
    if ($build -and $build.PSObject.Properties['last_regression_result'] -and $build.last_regression_result) {
        $regressionAvailable = $true
        try { $passed = [int]$build.last_regression_result.passed } catch { $passed = 0 }
        try { $failed = [int]$build.last_regression_result.failed } catch { $failed = 0 }
        try { $total = [int]$build.last_regression_result.total } catch { $total = 0 }
        $regressionGeneratedAt = if ($build.last_regression_result.PSObject.Properties['generated_at']) { [string]$build.last_regression_result.generated_at } else { "" }
    }

    $pendingCoordination = $false
    $coordinationStatus = "unknown"
    if ($coordination) {
        $pendingCoordination = -not [string]::IsNullOrWhiteSpace([string]$coordination.pending_request_id)
        if ($coordination.PSObject.Properties['last_ack_status']) {
            $coordinationStatus = [string]$coordination.last_ack_status
        }
    }

    $unchangedCycles = 0
    if ($stallState -and $stallState.PSObject.Properties['unchanged_cycles']) {
        try { $unchangedCycles = [int]$stallState.unchanged_cycles } catch { $unchangedCycles = 0 }
    }

    $loopIdleSec = -1
    if ($CadenceHealth -and $CadenceHealth.PSObject.Properties['stream'] -and $CadenceHealth.stream.PSObject.Properties['loop_idle_sec']) {
        try { $loopIdleSec = [double]$CadenceHealth.stream.loop_idle_sec } catch { $loopIdleSec = -1 }
    }
    if ($loopIdleSec -lt 0 -and $RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['heartbeat_age_seconds']) {
        try { $loopIdleSec = [double]$RecoveryWatchdog.heartbeat_age_seconds } catch { $loopIdleSec = -1 }
    }

    $cadenceSeverity = if ($CadenceHealth -and $CadenceHealth.PSObject.Properties['severity']) { [string]$CadenceHealth.severity } else { "unknown" }
    $listenerMode = if ($UsingListenerOnly) { "listener_telemetry" } else { "state_plus_listener" }

    $status = "unknown"
    $summary = "Steady state unavailable"
    if ($regressionAvailable -and $failed -le 0 -and -not $pendingCoordination -and $unchangedCycles -eq 0) {
        if ([string]::Equals($cadenceSeverity, 'critical', [System.StringComparison]::OrdinalIgnoreCase) -or ($loopIdleSec -ge 300)) {
            $status = "warning"
            $summary = "Regression is green, but live cadence looks stale."
        }
        elseif ([string]::Equals($cadenceSeverity, 'warning', [System.StringComparison]::OrdinalIgnoreCase) -or ($loopIdleSec -ge 180)) {
            $status = "warning"
            $summary = "Regression is green and coordination is clear; cadence needs watching."
        }
        else {
            $status = "ok"
            $summary = "Regression is green, coordination is clear, and listener cadence is healthy."
        }
    }
    elseif ($regressionAvailable -and $failed -gt 0) {
        $status = "critical"
        $summary = "Regression failures remain; system is not in steady state."
    }
    elseif ($pendingCoordination) {
        $status = "warning"
        $summary = "Coordination is still pending despite current listener activity."
    }

    return [pscustomobject]@{
        available = ($regressionAvailable -or $null -ne $CadenceHealth)
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
        source_warning = $StateWarning
    }
}

function Get-ProjectDataSources {
    param(
        [bool]$UsingListenerOnly,
        [string]$StateWarning,
        $ListenerActivity
    )

    return [pscustomobject]@{
        project_status_mode = if ($UsingListenerOnly) { "listener_telemetry_fallback" } else { "state_plus_listener" }
        listener_journal_available = [bool]($ListenerActivity -and [int]$ListenerActivity.entry_count -gt 0)
        current_build_state_available = [bool](Test-Path -Path $currentBuildStatePath)
        coordination_state_available = [bool](Test-Path -Path $coordinationEscalationPath)
        state_warning = $StateWarning
    }
}

function Get-ProjectStatusFromListenerOnly {
    param(
        [string]$ObjectiveId,
        $ListenerActivity,
        $RecoveryWatchdog,
        $CadenceHealth,
        $VoiceAdapterStatus,
        [string]$StateWarning
    )

    $objectiveOptions = @()
    $objectiveStatsMap = @{}
    if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['objective_stats']) {
        foreach ($prop in $ListenerActivity.objective_stats.PSObject.Properties) {
            $listenerObjectiveId = [string]$prop.Name
            if ([string]::IsNullOrWhiteSpace($listenerObjectiveId)) {
                continue
            }

            $stats = $prop.Value
            $objectiveStatsMap[$listenerObjectiveId] = $stats
            $objectiveOptions += [pscustomobject]@{
                objective_id = $listenerObjectiveId
                title = "Listener Objective $listenerObjectiveId"
                status = if ($stats.last_execution_status) { [string]$stats.last_execution_status } else { "listener" }
                priority = "listener"
            }
        }
    }

    $selectedObjectiveId = ""
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
        $selectedObjectiveId = [string]$ObjectiveId
    }
    elseif ($ListenerActivity -and -not [string]::IsNullOrWhiteSpace([string]$ListenerActivity.latest_objective_id)) {
        $selectedObjectiveId = [string]$ListenerActivity.latest_objective_id
    }
    elseif (@($objectiveOptions).Count -gt 0) {
        $selectedObjectiveId = [string]$objectiveOptions[0].objective_id
    }

    $selectedStats = $null
    if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId) -and $objectiveStatsMap.ContainsKey($selectedObjectiveId)) {
        $selectedStats = $objectiveStatsMap[$selectedObjectiveId]
    }

    $taskCount = 0
    $progressUnits = 0.0
    $percent = 0
    $statusBreakdown = @{}

    if ($selectedStats) {
        $taskCount = [int]$selectedStats.total
        $progressUnits = [double]$selectedStats.progress_units
        if ($taskCount -gt 0) {
            $percent = [int][math]::Round(($progressUnits / [double]$taskCount) * 100)
        }
        $statusBreakdown = @{
            completed = [int]$selectedStats.completed
            failed = [int]$selectedStats.failed
            in_progress = [int]$selectedStats.in_progress
        }
    }

    $marker = $null
    if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId)) {
        $marker = [pscustomobject]@{
            objective_id = $selectedObjectiveId
            remote_objective_id = $selectedObjectiveId
            title = "Listener Objective $selectedObjectiveId"
            status = if ($selectedStats -and $selectedStats.last_execution_status) { [string]$selectedStats.last_execution_status } else { "listener" }
            priority = "listener"
            updated_at = if ($selectedStats -and $selectedStats.last_timestamp) { [string]$selectedStats.last_timestamp } else { "" }
        }
    }

    $engineeringSignal = [pscustomobject]@{
        available = $false
        error = "Engineering signal skipped in listener-only mode to keep dashboard refresh responsive."
    }

    $steadyState = Get-SteadyStateHealth -ListenerActivity $ListenerActivity -RecoveryWatchdog $RecoveryWatchdog -CadenceHealth $CadenceHealth -StateWarning $StateWarning -UsingListenerOnly $true
    $dataSources = Get-ProjectDataSources -UsingListenerOnly $true -StateWarning $StateWarning -ListenerActivity $ListenerActivity

    return [pscustomobject]@{
        ok = $true
        objective_options = @($objectiveOptions)
        selected_objective_id = $selectedObjectiveId
        marker = $marker
        task_funnel = [pscustomobject]@{
            total = $taskCount
            by_status = [pscustomobject]$statusBreakdown
        }
        progress = [pscustomobject]@{
            percent = $percent
            completed_equivalent = [math]::Round($progressUnits, 2)
            task_count = $taskCount
            source = "listener_journal"
            summary = if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId)) { "Objective ${selectedObjectiveId}: $percent% (listener journal)" } else { "Awaiting listener telemetry..." }
        }
        listener_activity = $ListenerActivity
        recovery_watchdog = $RecoveryWatchdog
        task_state = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["task_state"]) { [string]$RecoveryWatchdog.task_state } else { "idle" }
        task_state_model = [pscustomobject]@{
            current = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["task_state"]) { [string]$RecoveryWatchdog.task_state } else { "idle" }
            progress_classification = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["progress_classification"]) { [string]$RecoveryWatchdog.progress_classification } else { "no_progress_but_heartbeats_present" }
            heartbeat_age_seconds = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["heartbeat_age_seconds"]) { [int]$RecoveryWatchdog.heartbeat_age_seconds } else { -1 }
            stall_threshold_seconds = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["stall_threshold_seconds"]) { [int]$RecoveryWatchdog.stall_threshold_seconds } else { -1 }
            recovery_attempts = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["recovery_attempts"]) { [int]$RecoveryWatchdog.recovery_attempts } else { 0 }
            consecutive_freezes = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["consecutive_freezes"]) { [int]$RecoveryWatchdog.consecutive_freezes } else { 0 }
            last_recovery_time = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["last_recovery_time"]) { [string]$RecoveryWatchdog.last_recovery_time } else { "" }
        }
        engineering_signal = $engineeringSignal
        cadence_health = $CadenceHealth
        steady_state = $steadyState
        data_sources = $dataSources
        voice_adapter = $VoiceAdapterStatus
        warnings = if ([string]::IsNullOrWhiteSpace($StateWarning)) { @() } else { @($StateWarning) }
    }
}

function Get-ProjectStatusPayload {
    param([string]$ObjectiveId)

    $listenerActivity = Get-ListenerActivity
    $recoveryWatchdog = Get-RecoveryWatchdogStatus
    $cadenceHealth = Get-CadenceHealth -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog
    $voiceAdapterStatus = Get-VoiceAdapterStatus

    $state = $null
    $stateReadWarning = ""
    if (-not (Test-Path -Path $statePath)) {
        $stateReadWarning = "state.json not found; using listener telemetry"
    }
    else {
        try {
            $stateFile = Get-Item -Path $statePath -ErrorAction Stop
            if ($stateFile.Length -gt $maxStateReadBytes) {
                $stateMiB = [math]::Round(($stateFile.Length / 1MB), 2)
                $stateReadWarning = "state.json too large (${stateMiB} MiB); using listener telemetry"
            }
            else {
                $rawState = Get-Content -Path $statePath -Raw
                $state = $rawState | ConvertFrom-Json
            }
        }
        catch {
            $stateReadWarning = "state.json unavailable for UI telemetry: $([string]$_.Exception.Message)"
        }
    }

    if ($null -eq $state) {
        return Get-ProjectStatusFromListenerOnly -ObjectiveId $ObjectiveId -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog -CadenceHealth $cadenceHealth -VoiceAdapterStatus $voiceAdapterStatus -StateWarning $stateReadWarning
    }

    $objectives = @($state.objectives)
    $tasks = @($state.tasks)

    $objectiveOptions = @($objectives | Sort-Object created_at -Descending | ForEach-Object {
            [pscustomobject]@{
                objective_id = [string]$_.id
                title = [string]$_.title
                status = [string]$_.status
                priority = [string]$_.priority
            }
        })

    $knownObjectiveIds = @{}
    foreach ($item in $objectiveOptions) {
        $knownObjectiveIds[[string]$item.objective_id] = $true
    }

    if ($listenerActivity -and $listenerActivity.PSObject.Properties['objective_stats']) {
        $listenerObjectiveStats = $listenerActivity.objective_stats.PSObject.Properties
        foreach ($prop in $listenerObjectiveStats) {
            $listenerObjectiveId = [string]$prop.Name
            if ([string]::IsNullOrWhiteSpace($listenerObjectiveId)) {
                continue
            }
            if (-not $knownObjectiveIds.ContainsKey($listenerObjectiveId)) {
                $stats = $prop.Value
                $objectiveOptions += [pscustomobject]@{
                    objective_id = $listenerObjectiveId
                    title = "Listener Objective $listenerObjectiveId"
                    status = if ($stats.last_execution_status) { [string]$stats.last_execution_status } else { "listener" }
                    priority = "listener"
                }
                $knownObjectiveIds[$listenerObjectiveId] = $true
            }
        }
    }

    if (@($objectiveOptions).Count -eq 0) {
        return [pscustomobject]@{
            ok = $true
            marker = $null
            objective_options = @()
            selected_objective_id = ""
            task_funnel = [pscustomobject]@{ total = 0; by_status = @{} }
            progress = [pscustomobject]@{
                percent = 0
                completed_equivalent = 0
                task_count = 0
                summary = "No objectives yet"
            }
        }
    }

    $marker = $null
    $selectedObjectiveId = ""
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
        $selectedObjectiveId = [string]$ObjectiveId
    }
    elseif ($listenerActivity -and -not [string]::IsNullOrWhiteSpace([string]$listenerActivity.latest_objective_id)) {
        $selectedObjectiveId = [string]$listenerActivity.latest_objective_id
    }

    if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId)) {
        $selected = @($objectives | Where-Object { [string]$_.id -eq [string]$selectedObjectiveId } | Select-Object -First 1)
        if (@($selected).Count -gt 0) {
            $marker = $selected[0]
        }
    }

    if ($null -eq $marker) {
        $marker = @($objectives | Sort-Object created_at -Descending | Select-Object -First 1)[0]
    }

    $objectiveId = if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId)) { $selectedObjectiveId } else { [string]$marker.id }

    if ([string]::IsNullOrWhiteSpace([string]$marker.id) -or ([string]$marker.id -ne $objectiveId -and -not @($objectives | Where-Object { [string]$_.id -eq $objectiveId }).Count)) {
        $listenerObjective = $null
        if ($listenerActivity -and $listenerActivity.PSObject.Properties['objective_stats']) {
            $listenerObjective = $listenerActivity.objective_stats.PSObject.Properties[$objectiveId]
        }

        $marker = [pscustomobject]@{
            id = $objectiveId
            remote_objective_id = $objectiveId
            title = "Listener Objective $objectiveId"
            status = if ($listenerObjective -and $listenerObjective.Value.last_execution_status) { [string]$listenerObjective.Value.last_execution_status } else { "listener" }
            priority = "listener"
            updated_at = if ($listenerObjective -and $listenerObjective.Value.last_timestamp) { [string]$listenerObjective.Value.last_timestamp } else { "" }
        }
    }

    $objectiveTasks = @($tasks | Where-Object { [string]$_.objective_id -eq $objectiveId })
    $taskCount = @($objectiveTasks).Count

    $statusBreakdown = @{}
    foreach ($task in $objectiveTasks) {
        $statusValue = if ($task.PSObject.Properties["status"]) { [string]$task.status } else { "unknown" }
        $key = if ([string]::IsNullOrWhiteSpace($statusValue)) { "unknown" } else { $statusValue.Trim().ToLowerInvariant() }
        if (-not $statusBreakdown.ContainsKey($key)) {
            $statusBreakdown[$key] = 0
        }
        $statusBreakdown[$key] = [int]$statusBreakdown[$key] + 1
    }

    $progressUnits = 0.0
    foreach ($task in $objectiveTasks) {
        $statusValue = if ($task.PSObject.Properties["status"]) { [string]$task.status } else { "" }
        $progressUnits += (Get-TaskProgressWeight -Status $statusValue)
    }

    $listenerStats = $null
    if ($listenerActivity -and $listenerActivity.PSObject.Properties['objective_stats']) {
        $listenerStats = $listenerActivity.objective_stats.PSObject.Properties[$objectiveId]
    }

    $listenerTaskCount = 0
    $listenerProgressUnits = 0.0
    if ($listenerStats) {
        $listenerTaskCount = [int]$listenerStats.Value.total
        $listenerProgressUnits = [double]$listenerStats.Value.progress_units
    }

    $progressSource = "tasks"
    $percent = if ($taskCount -gt 0) {
        [int][math]::Round(($progressUnits / [double]$taskCount) * 100)
    }
    elseif ($listenerTaskCount -gt 0) {
        $progressSource = "listener_journal"
        $progressUnits = $listenerProgressUnits
        $taskCount = $listenerTaskCount
        [int][math]::Round(($listenerProgressUnits / [double]$listenerTaskCount) * 100)
    }
    else {
        $progressSource = "objective_status"
        [int][math]::Round((Get-TaskProgressWeight -Status ([string]$marker.status)) * 100)
    }

    $progressSummary = if ($taskCount -gt 0) {
        if ($progressSource -eq "listener_journal") {
            "Objective ${objectiveId}: $percent% (listener journal)"
        }
        else {
            "Objective ${objectiveId}: $percent%"
        }
    }
    else {
        "Objective ${objectiveId}: $percent% (status-based; no tasks yet)"
    }

    $engineeringSignal = $null
    if (-not [string]::IsNullOrWhiteSpace($stateReadWarning)) {
        $engineeringSignal = [pscustomobject]@{
            available = $false
            error = "Engineering signal skipped while using listener telemetry only."
        }
    }
    else {
        try {
            $signalRaw = & $todScript -Action "get-engineering-signal" -ConfigPath $configPath -Top 10
            $engineeringSignal = $signalRaw | ConvertFrom-Json
        }
        catch {
            $engineeringSignal = [pscustomobject]@{
                available = $false
                error = $_.Exception.Message
            }
        }
    }

    $steadyState = Get-SteadyStateHealth -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog -CadenceHealth $cadenceHealth -StateWarning $stateReadWarning -UsingListenerOnly ([string]::IsNullOrWhiteSpace($stateReadWarning) -eq $false)
    $dataSources = Get-ProjectDataSources -UsingListenerOnly ([string]::IsNullOrWhiteSpace($stateReadWarning) -eq $false) -StateWarning $stateReadWarning -ListenerActivity $listenerActivity

    return [pscustomobject]@{
        ok = $true
        objective_options = @($objectiveOptions)
        selected_objective_id = $objectiveId
        marker = [pscustomobject]@{
            objective_id = $objectiveId
            remote_objective_id = if ($marker.PSObject.Properties["remote_objective_id"]) { [string]$marker.remote_objective_id } else { "" }
            title = [string]$marker.title
            status = [string]$marker.status
            priority = [string]$marker.priority
            updated_at = if ($marker.PSObject.Properties["updated_at"]) { [string]$marker.updated_at } else { "" }
        }
        task_funnel = [pscustomobject]@{
            total = $taskCount
            by_status = [pscustomobject]$statusBreakdown
        }
        progress = [pscustomobject]@{
            percent = $percent
            completed_equivalent = [math]::Round($progressUnits, 2)
            task_count = $taskCount
            source = $progressSource
            summary = $progressSummary
        }
        listener_activity = $listenerActivity
        recovery_watchdog = $recoveryWatchdog
        task_state = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["task_state"]) { [string]$recoveryWatchdog.task_state } else { "idle" }
        task_state_model = [pscustomobject]@{
            current = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["task_state"]) { [string]$recoveryWatchdog.task_state } else { "idle" }
            progress_classification = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["progress_classification"]) { [string]$recoveryWatchdog.progress_classification } else { "no_progress_but_heartbeats_present" }
            heartbeat_age_seconds = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["heartbeat_age_seconds"]) { [int]$recoveryWatchdog.heartbeat_age_seconds } else { -1 }
            stall_threshold_seconds = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["stall_threshold_seconds"]) { [int]$recoveryWatchdog.stall_threshold_seconds } else { -1 }
            recovery_attempts = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["recovery_attempts"]) { [int]$recoveryWatchdog.recovery_attempts } else { 0 }
            consecutive_freezes = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["consecutive_freezes"]) { [int]$recoveryWatchdog.consecutive_freezes } else { 0 }
            last_recovery_time = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["last_recovery_time"]) { [string]$recoveryWatchdog.last_recovery_time } else { "" }
        }
        engineering_signal = $engineeringSignal
        cadence_health = $cadenceHealth
        steady_state = $steadyState
        data_sources = $dataSources
        voice_adapter = $voiceAdapterStatus
    }
}

function Get-TaskStatePayload {
    $recoveryWatchdog = Get-RecoveryWatchdogStatus
    $listenerActivity = Get-ListenerActivity

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        current_state = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["task_state"]) { [string]$recoveryWatchdog.task_state } else { "idle" }
        watchdog_state = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["state"]) { [string]$recoveryWatchdog.state } else { "unknown" }
        progress_classification = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["progress_classification"]) { [string]$recoveryWatchdog.progress_classification } else { "no_progress_but_heartbeats_present" }
        last_task_heartbeat = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["last_task_heartbeat"]) { [string]$recoveryWatchdog.last_task_heartbeat } else { "" }
        heartbeat_age_seconds = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["heartbeat_age_seconds"]) { [int]$recoveryWatchdog.heartbeat_age_seconds } else { -1 }
        stall_threshold_seconds = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["stall_threshold_seconds"]) { [int]$recoveryWatchdog.stall_threshold_seconds } else { -1 }
        recovery_attempts = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["recovery_attempts"]) { [int]$recoveryWatchdog.recovery_attempts } else { 0 }
        consecutive_freezes = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["consecutive_freezes"]) { [int]$recoveryWatchdog.consecutive_freezes } else { 0 }
        last_recovery_time = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["last_recovery_time"]) { [string]$recoveryWatchdog.last_recovery_time } else { "" }
        last_issue = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["last_issue"]) { [string]$recoveryWatchdog.last_issue } else { "" }
        last_recovery_action = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["last_recovery_action"]) { [string]$recoveryWatchdog.last_recovery_action } else { "" }
        latest_request_id = if ($listenerActivity -and $listenerActivity.PSObject.Properties["latest_request_id"]) { [string]$listenerActivity.latest_request_id } else { "" }
        latest_execution_status = if ($listenerActivity -and $listenerActivity.PSObject.Properties["latest_execution_status"]) { [string]$listenerActivity.latest_execution_status } else { "" }
    }
}

Write-UiCrashLog "UI server started on port $activePort"

try {
    while ($listener.IsListening) {
        $context = $null
        try {
            $context = $listener.GetContext()
        }
        catch [System.Net.HttpListenerException] {
            # Listener was stopped (Ctrl+C or shutdown) - exit cleanly
            break
        }
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.AbsolutePath

        try {

        if ($request.HttpMethod -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
            $html = Get-Content -Path $indexPath -Raw
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
            $response.StatusCode = 200
            $response.ContentType = "text/html; charset=utf-8"
            $response.ContentLength64 = $bytes.LongLength
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/run") {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $bodyRaw = $reader.ReadToEnd()
                $payload = if ([string]::IsNullOrWhiteSpace($bodyRaw)) { @{} } else { $bodyRaw | ConvertFrom-Json }

                $action = [string]$payload.action
                if ([string]::IsNullOrWhiteSpace($action)) {
                    throw "action is required"
                }

                $invokeParams = @{
                    Action = $action
                }

                if ($payload.PSObject.Properties["top"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.top)) {
                    $invokeParams.Top = [int]$payload.top
                }
                if ($payload.PSObject.Properties["category"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.category)) {
                    $invokeParams.Category = [string]$payload.category
                }
                if ($payload.PSObject.Properties["engine"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.engine)) {
                    $invokeParams.Engine = [string]$payload.engine
                }
                if ($payload.PSObject.Properties["configPath"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.configPath)) {
                    $invokeParams.ConfigPath = [string]$payload.configPath
                }

                $lightweightActions = @(
                    "get-state-bus",
                    "get-reliability",
                    "show-reliability-dashboard",
                    "show-failure-taxonomy",
                    "get-engineering-loop-summary",
                    "get-engineering-signal",
                    "get-engineering-loop-history"
                )

                $canUseLightweight = ($lightweightActions -contains $action)
                if ($canUseLightweight -and (Test-ShouldUseLightweightStateBus)) {
                    $lightweightResult = Invoke-LightweightUiAction -Action $action
                    $result = [pscustomobject]@{
                        ok = $true
                        result = $lightweightResult
                    }
                    Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 22)
                    continue
                }

                # Run TOD action as child process to isolate OOM and other fatal errors
                $invokeArgList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $todScript)
                foreach ($k in $invokeParams.Keys) {
                    $invokeArgList += "-$k"
                    $invokeArgList += [string]$invokeParams[$k]
                }
                $output = powershell @invokeArgList 2>&1
                $exitCode = $LASTEXITCODE
                $parsed = $null
                try {
                    $parsed = $output | Out-String | ConvertFrom-Json
                }
                catch {
                    $parsed = [pscustomobject]@{ raw = [string]($output | Out-String) }
                }

                $rawOutputText = [string]($output | Out-String)
                $isOutOfMemory = ($rawOutputText -match 'OutOfMemoryException')
                if ($canUseLightweight -and $isOutOfMemory) {
                    $lightweightResult = Invoke-LightweightUiAction -Action $action
                    $parsed = $lightweightResult
                    $exitCode = 0
                }

                if ($exitCode -ne 0 -and $null -eq $parsed.error) {
                    $parsed | Add-Member -NotePropertyName exit_code -NotePropertyValue $exitCode -Force
                }

                $result = [pscustomobject]@{
                    ok = $true
                    result = $parsed
                }
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 22)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/logs") {
            try {
                $tailRaw = [string]$request.QueryString["tail"]
                $tail = 80
                if (-not [string]::IsNullOrWhiteSpace($tailRaw)) {
                    $parsedTail = 0
                    if ([int]::TryParse($tailRaw, [ref]$parsedTail)) {
                        $tail = $parsedTail
                    }
                }

                $lines = Get-RecentLogLines -LogPath $defaultLogPath -Tail $tail
                $entries = @()
                foreach ($line in $lines) {
                    if ([string]::IsNullOrWhiteSpace($line)) {
                        continue
                    }

                    try {
                        $entries += @($line | ConvertFrom-Json)
                    }
                    catch {
                        $entries += @([pscustomobject]@{ raw = [string]$line })
                    }
                }

                $payload = [pscustomobject]@{
                    ok = $true
                    log_path = $defaultLogPath
                    count = @($entries).Count
                    entries = @($entries)
                }
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 20)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/project-status") {
            try {
                $objectiveId = [string]$request.QueryString["objective_id"]
                $payload = Get-ProjectStatusPayload -ObjectiveId $objectiveId
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 12)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/task-state") {
            try {
                $payload = Get-TaskStatePayload
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 8)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/share-artifacts") {
            try {
                $payload = Get-ShareArtifactsPayload -ActivePort $activePort
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 8)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/share-download") {
            try {
                $key = [string]$request.QueryString["key"]
                if ([string]::IsNullOrWhiteSpace($key) -or -not $shareArtifacts.Contains($key)) {
                    $response.StatusCode = 404
                    $response.ContentType = "text/plain; charset=utf-8"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Unknown artifact key")
                    $response.ContentLength64 = $bytes.LongLength
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $response.Close()
                    continue
                }

                $artifactPath = [string]$shareArtifacts[$key].path
                if (-not (Test-Path -Path $artifactPath)) {
                    $response.StatusCode = 404
                    $response.ContentType = "text/plain; charset=utf-8"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Artifact not found")
                    $response.ContentLength64 = $bytes.LongLength
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $response.Close()
                    continue
                }

                $fileInfo = Get-Item -Path $artifactPath
                $bytes = [System.IO.File]::ReadAllBytes($artifactPath)
                $response.StatusCode = 200
                $response.ContentType = Get-MimeTypeForPath -Path $artifactPath
                $response.AddHeader("Content-Disposition", "attachment; filename=`"$($fileInfo.Name)`"")
                $response.ContentLength64 = $bytes.LongLength
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                $response.Close()
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/share-open") {
            try {
                $key = [string]$request.QueryString["key"]
                if ([string]::IsNullOrWhiteSpace($key) -or -not $shareArtifacts.Contains($key)) {
                    $response.StatusCode = 404
                    $response.ContentType = "text/plain; charset=utf-8"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Unknown artifact key")
                    $response.ContentLength64 = $bytes.LongLength
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $response.Close()
                    continue
                }

                $artifactPath = [string]$shareArtifacts[$key].path
                if (-not (Test-Path -Path $artifactPath)) {
                    $response.StatusCode = 404
                    $response.ContentType = "text/plain; charset=utf-8"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Artifact not found")
                    $response.ContentLength64 = $bytes.LongLength
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $response.Close()
                    continue
                }

                $bytes = [System.IO.File]::ReadAllBytes($artifactPath)
                $response.StatusCode = 200
                $response.ContentType = Get-MimeTypeForPath -Path $artifactPath
                $response.ContentLength64 = $bytes.LongLength
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                $response.Close()
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        $response.StatusCode = 404
        $response.ContentType = "text/plain; charset=utf-8"
        $notFound = [System.Text.Encoding]::UTF8.GetBytes("Not found")
        $response.ContentLength64 = $notFound.LongLength
        $response.OutputStream.Write($notFound, 0, $notFound.Length)
        $response.Close()

        } catch {
            # Per-request outer safety net — log and try to return 500 so server keeps running
            $reqErr = "[REQUEST ERROR] $($request.HttpMethod) $path : $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber)"
            Write-UiCrashLog $reqErr
            Write-Warning $reqErr
            try {
                if ($null -ne $response) {
                    try {
                        $response.Abort()
                    }
                    catch {
                        try {
                            $response.Close()
                        }
                        catch {
                        }
                    }
                }
            } catch {}
        }
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
