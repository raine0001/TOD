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
$conversationReplyScript = Join-Path $PSScriptRoot "Invoke-TODConversationalReply.ps1"
$localExecutionEngineScript = Join-Path $PSScriptRoot "engines/LocalExecutionEngine.ps1"
$todChatDispatchBuildId = 'direct-chat-local-executor-v1'
$maxStateReadBytes = 256MB
$lightweightStateBusScript = Join-Path $PSScriptRoot "Get-TODLightweightStateBus.ps1"
$listenerStagePath = Join-Path $repoRoot "tod/out/context-sync/listener"
$contextSyncPath = Join-Path $repoRoot "tod/out/context-sync"
$contextSyncSshSharedPath = Join-Path $contextSyncPath "ssh-shared"
$listenerJournalPath = Join-Path $listenerStagePath "TOD_LOOP_JOURNAL.latest.json"
$listenerResultPath = Join-Path $listenerStagePath "TOD_MIM_TASK_RESULT.latest.json"
$listenerRequestPath = Join-Path $listenerStagePath "MIM_TOD_TASK_REQUEST.latest.json"
$mimExportCanonicalPath = Join-Path $contextSyncSshSharedPath "MIM_CONTEXT_EXPORT.latest.json"
$mimExportFallbackPath = Join-Path $contextSyncPath "MIM_CONTEXT_EXPORT.latest.json"
$mimHandshakeCanonicalPath = Join-Path $contextSyncSshSharedPath "MIM_TOD_HANDSHAKE_PACKET.latest.json"
$mimHandshakeFallbackPath = Join-Path $contextSyncPath "MIM_TOD_HANDSHAKE_PACKET.latest.json"
$listenerTriggerAckPath = Join-Path $listenerStagePath "TOD_TO_MIM_TRIGGER_ACK.latest.json"
$listenerPingResponsePath = Join-Path $listenerStagePath "TOD_TO_MIM_PING.latest.json"
$listenerStatePath = Join-Path $listenerStagePath "listener_state.json"
$coordinationEscalationPath = Join-Path $listenerStagePath "TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json"
$regressionStallStatePath = Join-Path $listenerStagePath "TOD_REGRESSION_STALL_STATE.latest.json"
$currentBuildStatePath = Join-Path $repoRoot "shared_state/current_build_state.json"
$integrationStatusPath = Join-Path $repoRoot "shared_state/integration_status.json"
$nextActionsPath = Join-Path $repoRoot "shared_state/next_actions.json"
$trainingStatusPath = Join-Path $repoRoot "shared_state/tod_training_status.latest.json"
$recoveryWatchdogStatePath = Join-Path $repoRoot "shared_state/tod_recovery_watchdog.latest.json"
$activityStreamPrimaryPath = Join-Path $repoRoot "runtime/shared/TOD_ACTIVITY_STREAM.latest.json"
$activityStreamMirrorPath = Join-Path $repoRoot "tmp_remote_mim/runtime/shared/TOD_ACTIVITY_STREAM.latest.json"
$directChatActivityStreamPath = Join-Path $repoRoot "shared_state/tod_direct_chat_activity_stream.latest.json"
$todActivityStreamBuildId = 'fresh-direct-chat-activity-v1'
$voiceAdapterConfigPath = Join-Path $repoRoot "tod/config/voice-adapter.json"
$voiceAdapterTelemetryPath = Join-Path $repoRoot "shared_state/voice_adapter_status.json"
$voiceAdapterInboxPath = Join-Path $repoRoot "tod/inbox/voice/events"
$voiceListenerPidPath = Join-Path $repoRoot "shared_state/voice_listener.pid"
$driveAccessRoots = @(
    [pscustomobject]@{ key = 'e_drive'; label = 'Local E Drive'; path = 'E:\' }
)
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
            $launchArgs = @(
                "--app=$Url",
                "--new-window",
                "--start-maximized"
            )
            Start-Process -FilePath $browserPath -ArgumentList $launchArgs | Out-Null
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

function Invoke-TodConversationReplyRequest {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Query,
        [string]$ObjectiveId = '',
        [string]$OperatorName = '',
        [string]$ConversationHistoryJson = '[]',
        [int]$WindowMinutes = 10
    )

    if ([string]::IsNullOrWhiteSpace($Query)) {
        throw 'query is required'
    }
    if (-not (Test-Path -Path $conversationReplyScript)) {
        throw "Missing conversation reply script: $conversationReplyScript"
    }

    $invokeArgList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $conversationReplyScript,
        '-Query', $Query,
        '-ConversationHistoryJson', $ConversationHistoryJson,
        '-WindowMinutes', [string]$WindowMinutes,
        '-AsJson'
    )

    if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
        $invokeArgList += @('-ObjectiveId', $ObjectiveId)
    }
    if (-not [string]::IsNullOrWhiteSpace($OperatorName)) {
        $invokeArgList += @('-OperatorName', $OperatorName)
    }

    $output = powershell @invokeArgList 2>&1
    $exitCode = $LASTEXITCODE
    $rawOutput = [string]($output | Out-String)
    if ($exitCode -ne 0) {
        throw ("TOD conversation request failed with exit code {0}. {1}" -f $exitCode, $rawOutput.Trim())
    }

    try {
        return ($rawOutput | ConvertFrom-Json)
    }
    catch {
        throw ("TOD conversation reply was not valid JSON. {0}" -f $rawOutput.Trim())
    }
}

function Write-JsonArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $json = $Payload | ConvertTo-Json -Depth $Depth
    Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Get-ActivityTimestampText {
    param($Value)

    $candidates = @()
    if ($null -ne $Value) {
        if ($Value.PSObject.Properties['stream_generated_at']) {
            $candidates += [string]$Value.stream_generated_at
        }
        if ($Value.PSObject.Properties['generated_at']) {
            $candidates += [string]$Value.generated_at
        }
        if ($Value.PSObject.Properties['latest_event'] -and $null -ne $Value.latest_event -and $Value.latest_event.PSObject.Properties['timestamp']) {
            $candidates += [string]$Value.latest_event.timestamp
        }
        if ($Value.PSObject.Properties['events'] -and $null -ne $Value.events) {
            $lastEvent = @($Value.events | Select-Object -Last 1)
            if (@($lastEvent).Count -gt 0 -and $lastEvent[0].PSObject.Properties['timestamp']) {
                $candidates += [string]$lastEvent[0].timestamp
            }
        }
    }

    foreach ($candidate in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return [string]$candidate
        }
    }

    return ''
}

function Get-ActivityTimestampTicks {
    param($Value)

    $timestampText = Get-ActivityTimestampText -Value $Value
    if ([string]::IsNullOrWhiteSpace($timestampText)) {
        return [int64]0
    }

    try {
        return ([datetime]::Parse($timestampText).ToUniversalTime().Ticks)
    }
    catch {
        return [int64]0
    }
}

function Get-FilteredActivityEvents {
    param(
        $Payload,
        [string]$ObjectiveId = '',
        [string]$TaskId = ''
    )

    if ($null -eq $Payload) {
        return @()
    }

    $events = if ($Payload.PSObject.Properties['events'] -and $null -ne $Payload.events) {
        @($Payload.events | Where-Object { $null -ne $_ })
    }
    elseif ($Payload.PSObject.Properties['latest_event'] -and $null -ne $Payload.latest_event) {
        @($Payload.latest_event)
    }
    else {
        @()
    }

    if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
        $events = @($events | Where-Object {
                $candidateObjectiveId = if ($_.PSObject.Properties['objective_id']) { [string]$_.objective_id } else { '' }
                [string]::Equals($candidateObjectiveId, $ObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)
            })
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $events = @($events | Where-Object {
                $candidateTaskId = if ($_.PSObject.Properties['task_id']) { [string]$_.task_id } else { '' }
                [string]::Equals($candidateTaskId, $TaskId, [System.StringComparison]::OrdinalIgnoreCase)
            })
    }

    return @($events)
}

function New-ActivityStreamCandidatePayload {
    param(
        $Payload,
        [string]$SourcePath = '',
        [string]$ObjectiveId = '',
        [string]$TaskId = '',
        [int]$Limit = 60
    )

    if ($null -eq $Payload) {
        return $null
    }

    $events = Get-FilteredActivityEvents -Payload $Payload -ObjectiveId $ObjectiveId -TaskId $TaskId
    if (@($events).Count -eq 0 -and (-not [string]::IsNullOrWhiteSpace($ObjectiveId) -or -not [string]::IsNullOrWhiteSpace($TaskId))) {
        return $null
    }
    if (@($events).Count -eq 0) {
        $events = Get-FilteredActivityEvents -Payload $Payload
    }
    if (@($events).Count -eq 0) {
        return $null
    }

    $safeLimit = if ($Limit -lt 1) { 1 } elseif ($Limit -gt 200) { 200 } else { $Limit }
    if (@($events).Count -gt $safeLimit) {
        $events = @($events | Select-Object -Last $safeLimit)
    }

    $latestEvent = @($events | Select-Object -Last 1)
    $latestEvent = if (@($latestEvent).Count -gt 0) { $latestEvent[0] } else { $null }
    $streamGeneratedAt = Get-ActivityTimestampText -Value $Payload

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source_path = $SourcePath
        stream_generated_at = $streamGeneratedAt
        tod_activity_stream_build_id = $todActivityStreamBuildId
        objective_id = if ($latestEvent -and $latestEvent.PSObject.Properties['objective_id']) { [string]$latestEvent.objective_id } elseif ($Payload.PSObject.Properties['objective_id']) { [string]$Payload.objective_id } else { '' }
        task_id = if ($latestEvent -and $latestEvent.PSObject.Properties['task_id']) { [string]$latestEvent.task_id } elseif ($Payload.PSObject.Properties['task_id']) { [string]$Payload.task_id } else { '' }
        title = if ($latestEvent -and $latestEvent.PSObject.Properties['title']) { [string]$latestEvent.title } elseif ($Payload.PSObject.Properties['title']) { [string]$Payload.title } else { '' }
        summary = if ($Payload.PSObject.Properties['summary']) { [string]$Payload.summary } elseif ($latestEvent -and $latestEvent.PSObject.Properties['message']) { [string]$latestEvent.message } else { '' }
        status = if ($latestEvent -and $latestEvent.PSObject.Properties['status']) { [string]$latestEvent.status } elseif ($Payload.PSObject.Properties['status']) { [string]$Payload.status } else { 'idle' }
        event = if ($latestEvent -and $latestEvent.PSObject.Properties['event_type']) { [string]$latestEvent.event_type } elseif ($Payload.PSObject.Properties['event']) { [string]$Payload.event } else { '' }
        phase = if ($latestEvent -and $latestEvent.PSObject.Properties['step']) { [string]$latestEvent.step } elseif ($Payload.PSObject.Properties['phase']) { [string]$Payload.phase } else { '' }
        latest_event = $latestEvent
        count = @($events).Count
        events = @($events)
    }
}

function Update-DirectChatActivityStream {
    param($ReplyPayload)

    if ($null -eq $ReplyPayload -or -not $ReplyPayload.PSObject.Properties['command_dispatch']) {
        return $null
    }

    $commandDispatch = $ReplyPayload.command_dispatch
    if ($null -eq $commandDispatch -or -not [bool]$commandDispatch.created -or [string]::IsNullOrWhiteSpace([string]$commandDispatch.task_id)) {
        return $null
    }

    $dispatchPayload = if ($commandDispatch.PSObject.Properties['payload']) { $commandDispatch.payload } else { $null }
    $generatedAt = if ($ReplyPayload.PSObject.Properties['generated_at'] -and -not [string]::IsNullOrWhiteSpace([string]$ReplyPayload.generated_at)) {
        [string]$ReplyPayload.generated_at
    }
    else {
        (Get-Date).ToUniversalTime().ToString('o')
    }

    $taskId = [string]$commandDispatch.task_id
    $objectiveId = [string]$commandDispatch.objective_id
    $requestId = if ($commandDispatch.PSObject.Properties['request_id']) { [string]$commandDispatch.request_id } else { '' }
    $correlationId = if ($commandDispatch.PSObject.Properties['correlation_id']) { [string]$commandDispatch.correlation_id } else { '' }
    $title = if ($commandDispatch.PSObject.Properties['title']) { [string]$commandDispatch.title } else { '' }
    $taskCategory = if ($commandDispatch.PSObject.Properties['task_category']) { [string]$commandDispatch.task_category } else { '' }
    $runTask = if ($dispatchPayload -and $dispatchPayload.PSObject.Properties['run_task']) { $dispatchPayload.run_task } else { $null }
    $executorClassification = if ($dispatchPayload -and $dispatchPayload.PSObject.Properties['executor_classification']) { $dispatchPayload.executor_classification } else { $null }
    $runTaskDecision = if ($runTask -and $runTask.PSObject.Properties['decision']) { [string]$runTask.decision } else { '' }
    $runTaskSummary = if ($runTask -and $runTask.PSObject.Properties['summary']) { [string]$runTask.summary } else { '' }
    $engineInvocation = if ($runTask -and $runTask.PSObject.Properties['engine_invocation']) { $runTask.engine_invocation } else { $null }
    $engineResult = if ($engineInvocation -and $engineInvocation.PSObject.Properties['result']) { $engineInvocation.result } else { $null }
    $filesChanged = if ($engineResult -and $engineResult.PSObject.Properties['files_changed'] -and $null -ne $engineResult.files_changed) {
        @($engineResult.files_changed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    }
    else {
        @()
    }
    $noChangeRequired = $false
    if ($engineResult -and $engineResult.PSObject.Properties['no_change_required'] -and $null -ne $engineResult.no_change_required) {
        $noChangeRequired = [bool]$engineResult.no_change_required
    }
    $reportedEventTypes = if ($dispatchPayload -and $dispatchPayload.PSObject.Properties['activity_event_types']) { @($dispatchPayload.activity_event_types | ForEach-Object { [string]$_ }) } else { @() }
    $isLocalExecution = ($reportedEventTypes -contains 'local_executor_invoked') -or ($reportedEventTypes -contains 'local_executor_completed') -or ([string]$commandDispatch.detail -match '(?i)executor\s+local')

    $eventList = New-Object System.Collections.Generic.List[object]
    $eventList.Add([pscustomobject]@{
            timestamp = $generatedAt
            event_type = 'chat_task_created'
            objective_id = $objectiveId
            task_id = $taskId
            request_id = $requestId
            correlation_id = $correlationId
            title = $title
            step = 'task_dispatch'
            status = 'completed'
            message = 'Direct TOD conversation created and dispatched a bounded chat task.'
            details = [pscustomobject]@{
                task_category = $taskCategory
                request_artifact_path = if ($commandDispatch.PSObject.Properties['request_artifact_path']) { [string]$commandDispatch.request_artifact_path } else { '' }
            }
            source = 'tod.ui.direct_chat'
            surface = 'tod-conversation'
        })

    if ($null -ne $executorClassification) {
        $eventList.Add([pscustomobject]@{
                timestamp = $generatedAt
                event_type = 'executor_classified'
                objective_id = $objectiveId
                task_id = $taskId
                request_id = $requestId
                correlation_id = $correlationId
                title = $title
                step = 'task_dispatch'
                status = 'completed'
                message = ('Direct TOD conversation classified the bounded task for executor {0}.' -f [string]$executorClassification.selected_executor)
                details = [pscustomobject]@{
                    task_category = $taskCategory
                    selected_executor = if ($executorClassification.PSObject.Properties['selected_executor']) { [string]$executorClassification.selected_executor } else { '' }
                    classification_reason = if ($executorClassification.PSObject.Properties['classification_reason']) { [string]$executorClassification.classification_reason } else { '' }
                    local_supported = if ($executorClassification.PSObject.Properties['local_supported']) { [bool]$executorClassification.local_supported } else { $false }
                    codex_allowed = if ($executorClassification.PSObject.Properties['codex_allowed']) { [bool]$executorClassification.codex_allowed } else { $false }
                }
                source = 'tod.ui.direct_chat'
                surface = 'tod-conversation'
            })
    }

    if ($isLocalExecution) {
        $eventList.Add([pscustomobject]@{
                timestamp = $generatedAt
                event_type = 'local_executor_invoked'
                objective_id = $objectiveId
                task_id = $taskId
                request_id = $requestId
                correlation_id = $correlationId
                title = $title
                step = 'engine_invocation'
                status = 'started'
                message = 'Direct TOD conversation invoked the local execution engine for the bounded task.'
                details = [pscustomobject]@{
                    task_category = $taskCategory
                    run_task_summary = $runTaskSummary
                }
                source = 'tod.ui.direct_chat'
                surface = 'tod-conversation'
            })
    }

    $localExecutionCompleted = ($reportedEventTypes -contains 'local_executor_completed') -or [string]::Equals($runTaskDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)
    $terminalReviewDecision = ([string]$runTaskDecision).Trim()
    $validationFailed = (-not [string]::IsNullOrWhiteSpace($terminalReviewDecision)) -and (-not [string]::Equals($terminalReviewDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase))

    if ($localExecutionCompleted) {
        $eventList.Add([pscustomobject]@{
                timestamp = $generatedAt
                event_type = 'local_executor_completed'
                objective_id = $objectiveId
                task_id = $taskId
                request_id = $requestId
                correlation_id = $correlationId
                title = $title
                step = 'engine_invocation'
                status = 'completed'
                message = if ($noChangeRequired) { 'Local execution completed for the direct chat task without applying a new change.' } else { 'Local execution completed for the direct chat task.' }
                details = [pscustomobject]@{
                    run_task_summary = $runTaskSummary
                    no_change_required = $noChangeRequired
                    files_changed = @($filesChanged)
                }
                source = 'tod.ui.direct_chat'
                surface = 'tod-conversation'
            })
    }

    if ([string]::Equals($terminalReviewDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) {
        $eventList.Add([pscustomobject]@{
                timestamp = $generatedAt
                event_type = 'validation_passed'
                objective_id = $objectiveId
                task_id = $taskId
                request_id = $requestId
                correlation_id = $correlationId
                title = $title
                step = 'validator'
                status = 'completed'
                message = 'Direct chat execution passed validation.'
                details = [pscustomobject]@{ review_decision = 'pass' }
                source = 'tod.ui.direct_chat'
                surface = 'tod-conversation'
            })
    }
    elseif ($validationFailed) {
        $eventList.Add([pscustomobject]@{
                timestamp = $generatedAt
                event_type = 'validation_failed'
                objective_id = $objectiveId
                task_id = $taskId
                request_id = $requestId
                correlation_id = $correlationId
                title = $title
                step = 'validator'
                status = 'blocked'
                message = if ([string]::IsNullOrWhiteSpace($runTaskSummary)) { 'Direct chat execution finished with a non-passing review decision.' } else { $runTaskSummary }
                details = [pscustomobject]@{ review_decision = $terminalReviewDecision }
                source = 'tod.ui.direct_chat'
                surface = 'tod-conversation'
            })
    }

    if (-not [string]::IsNullOrWhiteSpace($terminalReviewDecision)) {
        $eventList.Add([pscustomobject]@{
                timestamp = $generatedAt
                event_type = 'result_published'
                objective_id = $objectiveId
                task_id = $taskId
                request_id = $requestId
                correlation_id = $correlationId
                title = $title
                step = 'result_publisher'
                status = if ([string]::Equals($terminalReviewDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) { 'completed' } else { 'blocked' }
                message = 'Direct chat execution published bounded result artifacts.'
                details = [pscustomobject]@{
                    review_decision = $terminalReviewDecision
                    no_change_required = $noChangeRequired
                    files_changed = @($filesChanged)
                }
                source = 'tod.ui.direct_chat'
                surface = 'tod-conversation'
            })
    }

    if (($reportedEventTypes -contains 'blocked') -or ($reportedEventTypes -contains 'blocked_missing_local_executor_result') -or [string]::Equals($runTaskDecision, 'blocked', [System.StringComparison]::OrdinalIgnoreCase)) {
        $eventList.Add([pscustomobject]@{
                timestamp = $generatedAt
                event_type = 'blocked'
                objective_id = $objectiveId
                task_id = $taskId
                request_id = $requestId
                correlation_id = $correlationId
                title = $title
                step = 'engine_invocation'
                status = 'blocked'
                message = if ([string]::IsNullOrWhiteSpace($runTaskSummary)) { 'Direct chat execution is blocked and needs replay or repair.' } else { $runTaskSummary }
                details = [pscustomobject]@{ decision = $runTaskDecision }
                source = 'tod.ui.direct_chat'
                surface = 'tod-conversation'
            })
    }

    $existingPayload = Read-JsonFileIfExists -Path $directChatActivityStreamPath
    $existingEvents = if ($existingPayload -and $existingPayload.PSObject.Properties['events'] -and $null -ne $existingPayload.events) {
        @($existingPayload.events | Where-Object { $null -ne $_ })
    }
    else {
        @()
    }

    $combinedEvents = @($existingEvents + @($eventList.ToArray()))
    $combinedEvents = @($combinedEvents | Sort-Object -Property @{ Expression = {
                if ($_.PSObject.Properties['timestamp']) { [string]$_.timestamp } else { '' }
            } }, @{ Expression = {
                if ($_.PSObject.Properties['event_type']) { [string]$_.event_type } else { '' }
            } } -Unique)

    $latestEvent = @($combinedEvents | Select-Object -Last 1)
    $latestEvent = if (@($latestEvent).Count -gt 0) { $latestEvent[0] } else { $null }
    $directPayload = [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        stream_generated_at = if ($latestEvent -and $latestEvent.PSObject.Properties['timestamp']) { [string]$latestEvent.timestamp } else { $generatedAt }
        tod_activity_stream_build_id = $todActivityStreamBuildId
        source_path = $directChatActivityStreamPath
        objective_id = $objectiveId
        task_id = $taskId
        title = $title
        summary = 'Fresh direct-chat execution events captured from /api/tod-conversation.'
        status = if ($latestEvent -and $latestEvent.PSObject.Properties['status']) { [string]$latestEvent.status } else { 'active' }
        event = if ($latestEvent -and $latestEvent.PSObject.Properties['event_type']) { [string]$latestEvent.event_type } else { '' }
        phase = if ($latestEvent -and $latestEvent.PSObject.Properties['step']) { [string]$latestEvent.step } else { 'task_dispatch' }
        latest_event = $latestEvent
        count = @($combinedEvents).Count
        events = @($combinedEvents | Select-Object -Last 200)
    }

    Write-JsonArtifact -Path $directChatActivityStreamPath -Payload $directPayload -Depth 20
    return $directPayload
}

function Finalize-TodConversationReplyPayload {
    param($ReplyPayload)

    if ($null -eq $ReplyPayload) {
        return $null
    }

    $freshActivityPayload = Update-DirectChatActivityStream -ReplyPayload $ReplyPayload
    $replyTaskId = if ($ReplyPayload.PSObject.Properties['command_dispatch'] -and $ReplyPayload.command_dispatch -and $ReplyPayload.command_dispatch.PSObject.Properties['task_id']) {
        [string]$ReplyPayload.command_dispatch.task_id
    }
    else {
        ''
    }

    $scopedActivityPayload = $null
    if (-not [string]::IsNullOrWhiteSpace($replyTaskId) -and $freshActivityPayload -and [string]::Equals([string]$freshActivityPayload.task_id, $replyTaskId, [System.StringComparison]::OrdinalIgnoreCase)) {
        $scopedActivityPayload = New-ActivityStreamCandidatePayload -Payload $freshActivityPayload -SourcePath $directChatActivityStreamPath -TaskId $replyTaskId -Limit 20
    }
    elseif (-not [string]::IsNullOrWhiteSpace($replyTaskId)) {
        $scopedActivityPayload = Get-ActivityStreamPayload -TaskId $replyTaskId -Limit 20
    }

    if ($ReplyPayload.PSObject.Properties['tod_activity_stream_build_id']) {
        $ReplyPayload.tod_activity_stream_build_id = $todActivityStreamBuildId
    }
    else {
        Add-Member -InputObject $ReplyPayload -NotePropertyName 'tod_activity_stream_build_id' -NotePropertyValue $todActivityStreamBuildId -Force
    }

    if ($null -ne $scopedActivityPayload) {
        Add-Member -InputObject $ReplyPayload -NotePropertyName 'activity_stream' -NotePropertyValue $scopedActivityPayload -Force
    }
    elseif ($null -ne $freshActivityPayload) {
        Add-Member -InputObject $ReplyPayload -NotePropertyName 'activity_stream' -NotePropertyValue $freshActivityPayload -Force
    }

    return $ReplyPayload
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

function Get-DriveAccessRootsPayload {
    param([int]$ActivePort)

    $items = @()
    foreach ($root in @($driveAccessRoots)) {
        $fullPath = [System.IO.Path]::GetFullPath([string]$root.path)
        $exists = Test-Path -LiteralPath $fullPath
        $items += [pscustomobject]@{
            key = [string]$root.key
            label = [string]$root.label
            path = $fullPath
            exists = $exists
            list_url = "/api/drive-access-list?path=$([uri]::EscapeDataString($fullPath))"
            download_url = "/api/drive-access-download?path=$([uri]::EscapeDataString($fullPath))"
        }
    }

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        base_url = "http://localhost:$ActivePort"
        roots = @($items)
    }
}

function Test-DriveAccessPathAllowed {
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath
    )

    $fullCandidate = [System.IO.Path]::GetFullPath($CandidatePath)
    foreach ($root in @($driveAccessRoots)) {
        $fullRoot = [System.IO.Path]::GetFullPath([string]$root.path)
        if ([string]::Equals($fullCandidate, $fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        $normalizedRootPrefix = if ($fullRoot.EndsWith('\')) { $fullRoot } else { ($fullRoot + '\') }
        if ($fullCandidate.StartsWith($normalizedRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Resolve-DriveAccessPath {
    param(
        [string]$RequestedPath,
        [switch]$AllowFile
    )

    $candidate = $RequestedPath
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = [string]$driveAccessRoots[0].path
    }

    $fullPath = [System.IO.Path]::GetFullPath($candidate)
    if (-not (Test-DriveAccessPathAllowed -CandidatePath $fullPath)) {
        throw 'Requested path is outside the allowed drive-access roots.'
    }

    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw 'Requested path was not found.'
    }

    $item = Get-Item -LiteralPath $fullPath -Force
    if (-not $AllowFile -and -not $item.PSIsContainer) {
        throw 'Requested path is not a directory.'
    }

    return $item
}

function Get-DriveAccessListingPayload {
    param(
        [string]$RequestedPath,
        [int]$ActivePort
    )

    $directory = Resolve-DriveAccessPath -RequestedPath $RequestedPath
    $entries = @()
    foreach ($child in @(Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue |
            Sort-Object -Property @(
                @{ Expression = { $_.PSIsContainer }; Descending = $true },
                @{ Expression = { $_.Name }; Descending = $false }
            ) |
            Select-Object -First 300)) {
        $entries += [pscustomobject]@{
            name = [string]$child.Name
            full_path = [string]$child.FullName
            kind = if ($child.PSIsContainer) { 'directory' } else { 'file' }
            size = if ($child.PSIsContainer) { $null } else { [int64]$child.Length }
            last_write_time_utc = $child.LastWriteTimeUtc.ToString('o')
            list_url = if ($child.PSIsContainer) { "/api/drive-access-list?path=$([uri]::EscapeDataString([string]$child.FullName))" } else { '' }
            download_url = "/api/drive-access-download?path=$([uri]::EscapeDataString([string]$child.FullName))"
        }
    }

    $parentPath = ''
    if ($null -ne $directory.Parent) {
        $candidateParentPath = [string]$directory.Parent.FullName
        if (-not [string]::IsNullOrWhiteSpace($candidateParentPath)) {
            try {
                if (Test-DriveAccessPathAllowed -CandidatePath $candidateParentPath) {
                    $parentPath = $candidateParentPath
                }
            }
            catch {
                $parentPath = ''
            }
        }
    }

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        base_url = "http://localhost:$ActivePort"
        requested_path = [string]$directory.FullName
        parent_path = $parentPath
        entries = @($entries)
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

function Get-StateActivityFallbackPayload {
    param(
        [string]$ObjectiveId = '',
        [string]$TaskId = ''
    )

    if (-not (Test-Path -Path $statePath)) {
        return $null
    }

    try {
        $stateFile = Get-Item -Path $statePath -ErrorAction Stop
        if ($stateFile.Length -gt $maxStateReadBytes) {
            return $null
        }

        $state = Read-JsonFileIfExists -Path $statePath
        if ($null -eq $state -or -not $state.PSObject.Properties['tasks']) {
            return $null
        }

        $tasks = @($state.tasks | Where-Object { $null -ne $_ })
        if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
            $tasks = @($tasks | Where-Object {
                    $candidateObjectiveId = if ($_.PSObject.Properties['objective_id']) { [string]$_.objective_id } else { '' }
                    [string]::Equals($candidateObjectiveId, $ObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)
                })
        }
        if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
            $tasks = @($tasks | Where-Object {
                    $candidateTaskId = if ($_.PSObject.Properties['id']) { [string]$_.id } else { '' }
                    $candidateRemoteTaskId = if ($_.PSObject.Properties['remote_task_id']) { [string]$_.remote_task_id } else { '' }
                    [string]::Equals($candidateTaskId, $TaskId, [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($candidateRemoteTaskId, $TaskId, [System.StringComparison]::OrdinalIgnoreCase)
                })
        }

        if (@($tasks).Count -eq 0) {
            return $null
        }

        $latestTask = @($tasks | Sort-Object -Property @{ Expression = {
                        if ($_.PSObject.Properties['updated_at'] -and -not [string]::IsNullOrWhiteSpace([string]$_.updated_at)) { [string]$_.updated_at }
                        elseif ($_.PSObject.Properties['created_at'] -and -not [string]::IsNullOrWhiteSpace([string]$_.created_at)) { [string]$_.created_at }
                        else { '' }
                    } } -Descending | Select-Object -First 1)
        if (@($latestTask).Count -eq 0) {
            return $null
        }

        $task = $latestTask[0]
        $taskIdValue = if ($task.PSObject.Properties['id']) { [string]$task.id } else { '' }
        $objectiveIdValue = if ($task.PSObject.Properties['objective_id']) { [string]$task.objective_id } else { '' }
        $createdAt = if ($task.PSObject.Properties['created_at'] -and -not [string]::IsNullOrWhiteSpace([string]$task.created_at)) { [string]$task.created_at } else { $stateFile.LastWriteTimeUtc.ToString('o') }
        $updatedAt = if ($task.PSObject.Properties['updated_at'] -and -not [string]::IsNullOrWhiteSpace([string]$task.updated_at)) { [string]$task.updated_at } else { $createdAt }
        $taskTitle = if ($task.PSObject.Properties['title']) { [string]$task.title } else { '' }
        $taskStatus = if ($task.PSObject.Properties['status']) { [string]$task.status } else { 'active' }
        $assignedExecutor = if ($task.PSObject.Properties['assigned_executor']) { [string]$task.assigned_executor } else { '' }
        $scope = if ($task.PSObject.Properties['scope']) { [string]$task.scope } else { '' }
        $taskCategory = if ($task.PSObject.Properties['task_category']) { [string]$task.task_category } else { '' }
        $taskSource = if ($task.PSObject.Properties['source']) { [string]$task.source } else { 'state_task_fallback' }
        $events = New-Object System.Collections.Generic.List[object]
        $events.Add([pscustomobject]@{
                timestamp = $createdAt
                event_type = 'chat_task_dispatch_started'
                objective_id = $objectiveIdValue
                task_id = $taskIdValue
                title = $taskTitle
                step = 'task_dispatch'
                status = 'completed'
                message = 'Recovered direct-chat task dispatch from tod/data/state.json.'
                details = [pscustomobject]@{
                    assigned_executor = $assignedExecutor
                    task_category = $taskCategory
                    source = $taskSource
                }
                source = 'tod.ui.state_fallback'
                surface = 'tod-state'
            })

        if ([string]::Equals($assignedExecutor, 'local', [System.StringComparison]::OrdinalIgnoreCase)) {
            $events.Add([pscustomobject]@{
                    timestamp = $createdAt
                    event_type = 'local_executor_invoked'
                    objective_id = $objectiveIdValue
                    task_id = $taskIdValue
                    title = $taskTitle
                    step = 'engine_invocation'
                    status = 'completed'
                    message = 'Recovered LocalExecutionEngine invocation from persisted task state.'
                    details = [pscustomobject]@{
                        assigned_executor = $assignedExecutor
                        task_category = $taskCategory
                    }
                    source = 'tod.ui.state_fallback'
                    surface = 'tod-state'
                })

            $completionEventType = if ($taskStatus -in @('pass', 'reviewed_pass', 'done', 'completed', 'implemented')) { 'local_executor_completed' } else { 'blocked_missing_local_executor_result' }
            $completionStatus = if ($completionEventType -eq 'local_executor_completed') { 'completed' } else { 'blocked' }
            $completionMessage = if ($completionEventType -eq 'local_executor_completed') { 'Recovered LocalExecutionEngine completion from persisted task state.' } else { 'Recovered a blocked local execution outcome from persisted task state.' }
            $events.Add([pscustomobject]@{
                    timestamp = $updatedAt
                    event_type = $completionEventType
                    objective_id = $objectiveIdValue
                    task_id = $taskIdValue
                    title = $taskTitle
                    step = 'engine_invocation'
                    status = $completionStatus
                    message = $completionMessage
                    details = [pscustomobject]@{
                        assigned_executor = $assignedExecutor
                        task_status = $taskStatus
                        task_category = $taskCategory
                        scope = $scope
                    }
                    source = 'tod.ui.state_fallback'
                    surface = 'tod-state'
                })
        }

        $eventArray = @($events.ToArray())
        $latestEvent = @($eventArray | Select-Object -Last 1)
        $latestEvent = if (@($latestEvent).Count -gt 0) { $latestEvent[0] } else { $null }
        return [pscustomobject]@{
            ok = $true
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source_path = $statePath
            stream_generated_at = $updatedAt
            objective_id = $objectiveIdValue
            task_id = $taskIdValue
            title = $taskTitle
            summary = ('Recovered fresh activity from tod/data/state.json for task ' + $taskIdValue + '.')
            status = if ($latestEvent) { [string]$latestEvent.status } else { 'active' }
            event = if ($latestEvent) { [string]$latestEvent.event_type } else { '' }
            phase = if ($latestEvent) { [string]$latestEvent.step } else { 'task_dispatch' }
            latest_event = $latestEvent
            count = @($eventArray).Count
            events = @($eventArray)
        }
    }
    catch {
        return $null
    }
}

function Get-TrainingStatusPayload {
    $status = Read-JsonFileIfExists -Path $trainingStatusPath
    if ($null -eq $status) {
        return [pscustomobject]@{
            available = $false
            state = 'idle'
            state_label = 'TRAINING IDLE'
            active = $false
            started_at = ''
            updated_at = ''
            runtime_seconds = 0
            percent_complete = 0
            phase = ''
            phase_label = ''
            phase_detail = ''
            eta_seconds = $null
            expected_completion_utc = ''
            summary = 'No active training status was published.'
            latest_error = ''
            latest_error_at = ''
            latest_resolution = ''
            latest_resolution_at = ''
            warnings = @()
            errors = @()
            resolutions = @()
            recent_events = @()
            stages = @()
        }
    }

    $startedAt = if ($status.PSObject.Properties['started_at']) { [string]$status.started_at } else { '' }
    $updatedAt = if ($status.PSObject.Properties['updated_at']) { [string]$status.updated_at } else { '' }
    $isActive = if ($status.PSObject.Properties['active']) { [bool]$status.active } else { $false }
    $runtimeSeconds = if ($status.PSObject.Properties['runtime_seconds']) { [int]$status.runtime_seconds } else { 0 }
    if ($isActive -and -not [string]::IsNullOrWhiteSpace($startedAt)) {
        try {
            $startedAtUtc = [datetime]::Parse($startedAt).ToUniversalTime()
            $liveRuntimeSeconds = [int][Math]::Max(0, [Math]::Floor(((Get-Date).ToUniversalTime() - $startedAtUtc).TotalSeconds))
            if ($liveRuntimeSeconds -gt $runtimeSeconds) {
                $runtimeSeconds = $liveRuntimeSeconds
            }
        }
        catch {
        }
    }

    return [pscustomobject]@{
        available = $true
        source = if ($status.PSObject.Properties['source']) { [string]$status.source } else { 'tod-training-status-v1' }
        run_id = if ($status.PSObject.Properties['run_id']) { [string]$status.run_id } else { '' }
        state = if ($status.PSObject.Properties['state']) { [string]$status.state } else { 'unknown' }
        state_label = if ($status.PSObject.Properties['state_label']) { [string]$status.state_label } else { 'TRAINING UNKNOWN' }
        active = $isActive
        started_at = $startedAt
        updated_at = $updatedAt
        runtime_seconds = $runtimeSeconds
        percent_complete = if ($status.PSObject.Properties['percent_complete']) { [int]$status.percent_complete } else { 0 }
        completed_steps = if ($status.PSObject.Properties['completed_steps']) { [int]$status.completed_steps } else { 0 }
        failed_steps = if ($status.PSObject.Properties['failed_steps']) { [int]$status.failed_steps } else { 0 }
        total_steps = if ($status.PSObject.Properties['total_steps']) { [int]$status.total_steps } else { 0 }
        phase = if ($status.PSObject.Properties['phase']) { [string]$status.phase } else { '' }
        phase_label = if ($status.PSObject.Properties['phase_label']) { [string]$status.phase_label } else { '' }
        phase_detail = if ($status.PSObject.Properties['phase_detail']) { [string]$status.phase_detail } else { '' }
        current_step = if ($status.PSObject.Properties['current_step']) { [string]$status.current_step } else { '' }
        eta_seconds = if ($status.PSObject.Properties['eta_seconds']) { $status.eta_seconds } else { $null }
        expected_completion_utc = if ($status.PSObject.Properties['expected_completion_utc']) { [string]$status.expected_completion_utc } else { '' }
        summary = if ($status.PSObject.Properties['summary']) { [string]$status.summary } else { '' }
        latest_error = if ($status.PSObject.Properties['latest_error']) { [string]$status.latest_error } else { '' }
        latest_error_at = if ($status.PSObject.Properties['latest_error_at']) { [string]$status.latest_error_at } else { '' }
        latest_resolution = if ($status.PSObject.Properties['latest_resolution']) { [string]$status.latest_resolution } else { '' }
        latest_resolution_at = if ($status.PSObject.Properties['latest_resolution_at']) { [string]$status.latest_resolution_at } else { '' }
        warnings = if ($status.PSObject.Properties['warnings']) { @($status.warnings) } else { @() }
        errors = if ($status.PSObject.Properties['errors']) { @($status.errors) } else { @() }
        resolutions = if ($status.PSObject.Properties['resolutions']) { @($status.resolutions) } else { @() }
        recent_events = if ($status.PSObject.Properties['recent_events']) { @($status.recent_events) } else { @() }
        stages = if ($status.PSObject.Properties['stages']) { @($status.stages) } else { @() }
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

function Normalize-ObjectiveIdValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $trimmed = [string]$Value.Trim()
    $objectiveMatch = [regex]::Match($trimmed, '^objective-(?<objective>\d+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($objectiveMatch.Success) {
        return [string]$objectiveMatch.Groups['objective'].Value
    }

    return $trimmed
}

function Get-CanonicalMimObjective {
    $integrationStatus = Read-JsonFileIfExists -Path $integrationStatusPath
    if ($integrationStatus) {
        $alignment = if ($integrationStatus.PSObject.Properties['objective_alignment']) { $integrationStatus.objective_alignment } else { $null }
        if ($alignment -and $alignment.PSObject.Properties['mim_objective_active']) {
            $normalizedAlignmentObjective = Normalize-ObjectiveIdValue -Value ([string]$alignment.mim_objective_active)
            if (-not [string]::IsNullOrWhiteSpace($normalizedAlignmentObjective)) {
                return [pscustomobject]@{
                    available = $true
                    objective_id = $normalizedAlignmentObjective
                    field = 'objective_alignment.mim_objective_active'
                    source = 'integration_status'
                    path = $integrationStatusPath
                }
            }
        }

        $authorityReset = if ($integrationStatus.PSObject.Properties['objective_authority_reset']) { $integrationStatus.objective_authority_reset } else { $null }
        if ($authorityReset -and [bool]$authorityReset.active -and $authorityReset.PSObject.Properties['authoritative_current_objective']) {
            $normalizedAuthorityObjective = Normalize-ObjectiveIdValue -Value ([string]$authorityReset.authoritative_current_objective)
            if (-not [string]::IsNullOrWhiteSpace($normalizedAuthorityObjective)) {
                return [pscustomobject]@{
                    available = $true
                    objective_id = $normalizedAuthorityObjective
                    field = 'objective_authority_reset.authoritative_current_objective'
                    source = 'integration_status_authority_reset'
                    path = $integrationStatusPath
                }
            }
        }
    }

    $candidates = @(
        [pscustomobject]@{
            path = $mimExportCanonicalPath
            source = "ssh_shared_export"
            fields = @("objective_active", "objective_in_flight", "current_next_objective")
        },
        [pscustomobject]@{
            path = $mimExportFallbackPath
            source = "local_export"
            fields = @("objective_active", "objective_in_flight", "current_next_objective")
        },
        [pscustomobject]@{
            path = $mimHandshakeCanonicalPath
            source = "ssh_shared_handshake"
            fields = @("objective_active", "current_next_objective")
        },
        [pscustomobject]@{
            path = $mimHandshakeFallbackPath
            source = "local_handshake"
            fields = @("objective_active", "current_next_objective")
        }
    )

    foreach ($candidate in $candidates) {
        $doc = Read-JsonFileIfExists -Path ([string]$candidate.path)
        if ($null -eq $doc) {
            continue
        }

        foreach ($field in @($candidate.fields)) {
            if (-not $doc.PSObject.Properties[$field]) {
                continue
            }

            $normalized = Normalize-ObjectiveIdValue -Value ([string]$doc.$field)
            if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                return [pscustomobject]@{
                    available = $true
                    objective_id = $normalized
                    field = [string]$field
                    source = [string]$candidate.source
                    path = [string]$candidate.path
                }
            }
        }
    }

    return [pscustomobject]@{
        available = $false
        objective_id = ""
        field = ""
        source = ""
        path = ""
    }
}

function Resolve-ProjectSelectedObjectiveId {
    param(
        [string]$ExplicitObjectiveId,
        [AllowNull()]$ListenerActivity,
        [AllowNull()]$BridgeStatus,
        [AllowNull()]$NextActions,
        [AllowNull()]$Objectives
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitObjectiveId)) {
        return [string]$ExplicitObjectiveId
    }

    $listenerObjectiveId = ""
    if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['latest_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$ListenerActivity.latest_objective_id)) {
        $listenerObjectiveId = [string]$ListenerActivity.latest_objective_id
    }

    $bridgeCanonicalObjectiveId = ""
    if ($BridgeStatus -and $BridgeStatus.PSObject.Properties['canonical_mim_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$BridgeStatus.canonical_mim_objective_id)) {
        $bridgeCanonicalObjectiveId = [string]$BridgeStatus.canonical_mim_objective_id
    }

    $nextActionsObjectiveId = ""
    if ($NextActions -and $NextActions.PSObject.Properties['current_objective_in_progress'] -and -not [string]::IsNullOrWhiteSpace([string]$NextActions.current_objective_in_progress)) {
        $nextActionsObjectiveId = [string]$NextActions.current_objective_in_progress
    }

    if (-not [string]::IsNullOrWhiteSpace($listenerObjectiveId) -and -not [string]::IsNullOrWhiteSpace($bridgeCanonicalObjectiveId)) {
        if ([string]::Equals($listenerObjectiveId, $bridgeCanonicalObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $listenerObjectiveId
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($nextActionsObjectiveId) -and -not [string]::IsNullOrWhiteSpace($bridgeCanonicalObjectiveId)) {
        if ([string]::Equals($nextActionsObjectiveId, $bridgeCanonicalObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $nextActionsObjectiveId
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($listenerObjectiveId)) {
        return $listenerObjectiveId
    }

    if (-not [string]::IsNullOrWhiteSpace($bridgeCanonicalObjectiveId)) {
        return $bridgeCanonicalObjectiveId
    }

    if (-not [string]::IsNullOrWhiteSpace($nextActionsObjectiveId)) {
        return $nextActionsObjectiveId
    }

    if ($Objectives) {
        $latestObjective = @($Objectives | Sort-Object created_at -Descending | Select-Object -First 1)
        if (@($latestObjective).Count -gt 0 -and $latestObjective[0] -and $latestObjective[0].PSObject.Properties['id']) {
            return [string]$latestObjective[0].id
        }
    }

    return ""
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
    # Use the authoritative current_objective_in_progress from next_actions.json as the filter key
    # so that cadence metrics reset immediately on objective rollover without waiting for a new journal entry.
    $nextActions = Read-JsonFileIfExists -Path $nextActionsPath
    $activeObjectiveId = if ($nextActions -and $nextActions.PSObject.Properties['current_objective_in_progress'] -and -not [string]::IsNullOrWhiteSpace([string]$nextActions.current_objective_in_progress)) {
        [string]$nextActions.current_objective_in_progress
    } elseif ($latest) {
        [string]$latest.objective_id
    } else { "" }
    # Scope recent_entries to the current objective so stale history from prior objectives
    # does not contaminate cadence health metrics (retry_rate, intervals) after an objective rollover.
    $recentEntries = if (-not [string]::IsNullOrWhiteSpace($activeObjectiveId)) {
        @($normalizedEntries | Where-Object { [string]$_.objective_id -eq $activeObjectiveId } | Select-Object -Last 30)
    } else {
        @($normalizedEntries | Select-Object -Last 30)
    }
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

function Get-IsoAgeSeconds {
    param([string]$Value)

    $dt = Convert-ToDateTimeOffsetOrNull -Value $Value
    if ($null -eq $dt) {
        return -1
    }

    return [math]::Round(([DateTimeOffset]::UtcNow - $dt).TotalSeconds, 1)
}

function Get-BridgeStatus {
    $triggerAck = Read-JsonFileIfExists -Path $listenerTriggerAckPath
    $pingResponse = Read-JsonFileIfExists -Path $listenerPingResponsePath
    $listenerState = Read-JsonFileIfExists -Path $listenerStatePath

    $available = ($null -ne $triggerAck) -or ($null -ne $pingResponse) -or ($null -ne $listenerState)
    if (-not $available) {
        return [pscustomobject]@{
            available = $false
            status = "unknown"
            summary = "Bridge artifacts unavailable."
        }
    }

    $pollSeconds = 0
    $sharedPathKind = ""
    $currentTaskId = ""
    $currentCorrelationId = ""
    $consumerHost = ""
    $consumerService = ""
    $triggerType = ""
    $triggeredArtifact = ""
    $triggerSequence = 0
    $ackSequence = 0
    $pingAckSequence = 0
    $ackObservedAt = ""
    $pingObservedAt = ""
    $lastCycleAt = if ($listenerState -and $listenerState.PSObject.Properties['last_cycle_at']) { [string]$listenerState.last_cycle_at } else { "" }
    $listenerCycleAgeSeconds = Get-IsoAgeSeconds -Value $lastCycleAt

    if ($triggerAck) {
        if ($triggerAck.PSObject.Properties['current_task_id']) { $currentTaskId = [string]$triggerAck.current_task_id }
        if ($triggerAck.PSObject.Properties['current_correlation_id']) { $currentCorrelationId = [string]$triggerAck.current_correlation_id }
        if ($triggerAck.PSObject.Properties['consumer_host']) { $consumerHost = [string]$triggerAck.consumer_host }
        if ($triggerAck.PSObject.Properties['consumer_service']) { $consumerService = [string]$triggerAck.consumer_service }
        if ($triggerAck.PSObject.Properties['trigger_type']) { $triggerType = [string]$triggerAck.trigger_type }
        if ($triggerAck.PSObject.Properties['triggered_artifact']) { $triggeredArtifact = [string]$triggerAck.triggered_artifact }
        if ($triggerAck.PSObject.Properties['acknowledged_trigger_sequence']) { try { $triggerSequence = [long]$triggerAck.acknowledged_trigger_sequence } catch { $triggerSequence = 0 } }
        if ($triggerAck.PSObject.Properties['ack_sequence']) { try { $ackSequence = [long]$triggerAck.ack_sequence } catch { $ackSequence = 0 } }
        if ($triggerAck.PSObject.Properties['observed_at']) { $ackObservedAt = [string]$triggerAck.observed_at }
        if ($triggerAck.PSObject.Properties['bridge_runtime'] -and $triggerAck.bridge_runtime.PSObject.Properties['listener']) {
            $listenerRuntime = $triggerAck.bridge_runtime.listener
            if ($listenerRuntime.PSObject.Properties['poll_interval_seconds']) { try { $pollSeconds = [int]$listenerRuntime.poll_interval_seconds } catch { $pollSeconds = 0 } }
            if ($listenerRuntime.PSObject.Properties['shared_path_kind']) { $sharedPathKind = [string]$listenerRuntime.shared_path_kind }
        }
    }

    if ($pingResponse) {
        if ([string]::IsNullOrWhiteSpace($currentTaskId) -and $pingResponse.PSObject.Properties['current_task_id']) { $currentTaskId = [string]$pingResponse.current_task_id }
        if ([string]::IsNullOrWhiteSpace($currentCorrelationId) -and $pingResponse.PSObject.Properties['current_correlation_id']) { $currentCorrelationId = [string]$pingResponse.current_correlation_id }
        if ([string]::IsNullOrWhiteSpace($consumerHost) -and $pingResponse.PSObject.Properties['consumer_host']) { $consumerHost = [string]$pingResponse.consumer_host }
        if ([string]::IsNullOrWhiteSpace($consumerService) -and $pingResponse.PSObject.Properties['consumer_service']) { $consumerService = [string]$pingResponse.consumer_service }
        if ([string]::IsNullOrWhiteSpace($triggerType) -and $pingResponse.PSObject.Properties['response_to']) { $triggerType = [string]$pingResponse.response_to }
        if ([string]::IsNullOrWhiteSpace($triggeredArtifact) -and $pingResponse.PSObject.Properties['response_to_artifact']) { $triggeredArtifact = [string]$pingResponse.response_to_artifact }
        if ($pingResponse.PSObject.Properties['ack_sequence']) { try { $pingAckSequence = [long]$pingResponse.ack_sequence } catch { $pingAckSequence = 0 } }
        if ($triggerSequence -le 0 -and $pingResponse.PSObject.Properties['acknowledged_trigger_sequence']) { try { $triggerSequence = [long]$pingResponse.acknowledged_trigger_sequence } catch { $triggerSequence = 0 } }
        if ($pingResponse.PSObject.Properties['observed_at']) { $pingObservedAt = [string]$pingResponse.observed_at }
        if ($pollSeconds -le 0 -and $pingResponse.PSObject.Properties['bridge_runtime'] -and $pingResponse.bridge_runtime.PSObject.Properties['listener']) {
            $listenerRuntime = $pingResponse.bridge_runtime.listener
            if ($listenerRuntime.PSObject.Properties['poll_interval_seconds']) { try { $pollSeconds = [int]$listenerRuntime.poll_interval_seconds } catch { $pollSeconds = 0 } }
            if ([string]::IsNullOrWhiteSpace($sharedPathKind) -and $listenerRuntime.PSObject.Properties['shared_path_kind']) { $sharedPathKind = [string]$listenerRuntime.shared_path_kind }
        }
    }

    if ([string]::IsNullOrWhiteSpace($currentTaskId) -and $listenerState -and $listenerState.PSObject.Properties['last_processed_request_id']) {
        $currentTaskId = [string]$listenerState.last_processed_request_id
    }

    $taskObjectiveId = Get-ObjectiveIdFromRequestId -RequestId $currentTaskId
    $canonicalMimObjective = Get-CanonicalMimObjective
    $canonicalObjectiveId = if ($canonicalMimObjective) { [string]$canonicalMimObjective.objective_id } else { "" }
    $objectiveMismatch = $false
    $objectiveMismatchDetail = ""
    if ($canonicalMimObjective -and [bool]$canonicalMimObjective.available -and -not [string]::IsNullOrWhiteSpace($canonicalObjectiveId) -and -not [string]::IsNullOrWhiteSpace($taskObjectiveId)) {
        if (-not [string]::Equals($canonicalObjectiveId, $taskObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $objectiveMismatch = $true
            $objectiveMismatchDetail = "canonical_objective={0}; live_task_objective={1}; source={2}" -f $canonicalObjectiveId, $taskObjectiveId, [string]$canonicalMimObjective.source
        }
    }

    $listenerFreshThreshold = if ($pollSeconds -gt 0) { [math]::Max(15, ($pollSeconds * 6)) } else { 30 }
    $listenerFresh = ($listenerCycleAgeSeconds -ge 0) -and ($listenerCycleAgeSeconds -le $listenerFreshThreshold)
    $sequenceAware = ($ackSequence -gt 0) -and ($triggerSequence -gt 0)

    $status = "ok"
    if (-not $triggerAck -or -not $pingResponse -or -not $listenerState) {
        $status = "warning"
    }
    if (-not $listenerFresh) {
        $status = "warning"
    }
    if (-not $sequenceAware) {
        $status = "warning"
    }
    if ($objectiveMismatch) {
        $status = "warning"
    }

    $summary = if ($objectiveMismatch) {
        "Bridge packets are live, but objective routing is stale: canonical MIM export targets objective $canonicalObjectiveId while live task requests are objective $taskObjectiveId. Restart the live publisher to realign task packets."
    }
    elseif ($status -eq "ok") {
        "Bridge packets are live, sequence-aware, and listener heartbeat is fresh."
    }
    elseif (-not $listenerFresh) {
        "Bridge artifacts exist, but listener heartbeat looks stale."
    }
    else {
        "Bridge artifacts are present, but some live bridge fields are still incomplete."
    }

    return [pscustomobject]@{
        available = $true
        status = $status
        summary = $summary
        shared_path_kind = $sharedPathKind
        poll_interval_seconds = $pollSeconds
        current_task_id = $currentTaskId
        current_correlation_id = $currentCorrelationId
        latest_trigger_type = $triggerType
        latest_triggered_artifact = $triggeredArtifact
        latest_trigger_sequence = $triggerSequence
        latest_ack_sequence = $ackSequence
        latest_ping_ack_sequence = $pingAckSequence
        consumer_host = $consumerHost
        consumer_service = $consumerService
        listener_cycle_age_seconds = $listenerCycleAgeSeconds
        listener_fresh = $listenerFresh
        canonical_mim_objective_id = $canonicalObjectiveId
        canonical_mim_objective_source = if ($canonicalMimObjective) { [string]$canonicalMimObjective.source } else { "" }
        canonical_mim_objective_path = if ($canonicalMimObjective) { [string]$canonicalMimObjective.path } else { "" }
        task_request_objective_id = $taskObjectiveId
        objective_mismatch = $objectiveMismatch
        objective_mismatch_detail = $objectiveMismatchDetail
        trigger_ack = [pscustomobject]@{
            generated_at = if ($triggerAck -and $triggerAck.PSObject.Properties['generated_at']) { [string]$triggerAck.generated_at } else { "" }
            observed_at = $ackObservedAt
        }
        ping_response = [pscustomobject]@{
            generated_at = if ($pingResponse -and $pingResponse.PSObject.Properties['generated_at']) { [string]$pingResponse.generated_at } else { "" }
            observed_at = $pingObservedAt
        }
        listener = [pscustomobject]@{
            last_cycle_at = $lastCycleAt
            last_execution_at = if ($listenerState -and $listenerState.PSObject.Properties['last_execution_at']) { [string]$listenerState.last_execution_at } else { "" }
            last_outbound_sequence = if ($listenerState -and $listenerState.PSObject.Properties['last_outbound_sequence']) { [long]$listenerState.last_outbound_sequence } else { 0 }
        }
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

function Test-IsTerminalExecutionStatus {
    param([string]$Status)

    if ([string]::IsNullOrWhiteSpace($Status)) {
        return $false
    }

    $normalized = ([string]$Status).Trim().ToLowerInvariant()
    return @('completed', 'succeeded', 'already_processed', 'stale_request_ignored', 'stale_backfill_ignored') -contains $normalized
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
        training_status_available = [bool](Test-Path -Path $trainingStatusPath)
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

    $trainingStatus = Get-TrainingStatusPayload
    $steadyState = Get-SteadyStateHealth -ListenerActivity $ListenerActivity -RecoveryWatchdog $RecoveryWatchdog -CadenceHealth $CadenceHealth -StateWarning $StateWarning -UsingListenerOnly $true
    $dataSources = Get-ProjectDataSources -UsingListenerOnly $true -StateWarning $StateWarning -ListenerActivity $ListenerActivity
    $bridgeStatus = Get-BridgeStatus

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
        bridge_status = $bridgeStatus
        cadence_health = $CadenceHealth
        steady_state = $steadyState
        training_status = $trainingStatus
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
    $bridgeStatus = Get-BridgeStatus
    $trainingStatus = Get-TrainingStatusPayload

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

    $nextActions = $null
    if (Test-Path -Path $nextActionsPath) {
        try {
            $nextActionsRaw = Get-Content -Path $nextActionsPath -Raw -ErrorAction Stop
            $nextActions = $nextActionsRaw | ConvertFrom-Json
        }
        catch {
            $nextActions = $null
        }
    }

    $marker = $null
    $selectedObjectiveId = Resolve-ProjectSelectedObjectiveId -ExplicitObjectiveId $ObjectiveId -ListenerActivity $listenerActivity -BridgeStatus $bridgeStatus -NextActions $nextActions -Objectives $objectives

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
        bridge_status = $bridgeStatus
        cadence_health = $cadenceHealth
        steady_state = $steadyState
        training_status = $trainingStatus
        data_sources = $dataSources
        voice_adapter = $voiceAdapterStatus
    }
}

function Get-TaskStatePayload {
    $recoveryWatchdog = Get-RecoveryWatchdogStatus
    $listenerActivity = Get-ListenerActivity
    $trainingStatus = Get-TrainingStatusPayload
    $latestExecutionStatus = if ($listenerActivity -and $listenerActivity.PSObject.Properties["latest_execution_status"]) { [string]$listenerActivity.latest_execution_status } else { '' }
    $latestRequestId = if ($listenerActivity -and $listenerActivity.PSObject.Properties["latest_request_id"]) { [string]$listenerActivity.latest_request_id } else { '' }
    $resultRequestId = if ($listenerActivity -and $listenerActivity.PSObject.Properties["result_request_id"]) { [string]$listenerActivity.result_request_id } else { '' }
    $resultStatus = if ($listenerActivity -and $listenerActivity.PSObject.Properties["result_status"]) { [string]$listenerActivity.result_status } else { '' }
    $matchedTerminalResult =
        (Test-IsTerminalExecutionStatus -Status $latestExecutionStatus) -and
        (Test-IsTerminalExecutionStatus -Status $resultStatus) -and
        -not [string]::IsNullOrWhiteSpace($latestRequestId) -and
        [string]::Equals($latestRequestId, $resultRequestId, [System.StringComparison]::OrdinalIgnoreCase)
    $currentState = if ($trainingStatus.available -and [bool]$trainingStatus.active) {
        'training'
    }
    elseif ($matchedTerminalResult) {
        'completed'
    }
    elseif ([string]::Equals($latestExecutionStatus, 'in_progress', [System.StringComparison]::OrdinalIgnoreCase)) {
        'executing'
    }
    elseif ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["task_state"]) {
        [string]$recoveryWatchdog.task_state
    }
    else {
        'idle'
    }

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        tod_chat_dispatch_build_id = $todChatDispatchBuildId
        live_source_paths = [pscustomobject]@{
            repo_root = $repoRoot
            ui_host_script = $PSCommandPath
            conversational_reply_script = $conversationReplyScript
            tod_script = $todScript
            local_execution_engine_script = $localExecutionEngineScript
        }
        current_state = $currentState
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
        latest_request_id = $latestRequestId
        latest_execution_status = $latestExecutionStatus
        training_status = $trainingStatus
    }
}

function Get-ActivityStreamPayload {
    param(
        [string]$ObjectiveId = '',
        [string]$TaskId = '',
        [int]$Limit = 60
    )

    $safeLimit = if ($Limit -lt 1) { 1 } elseif ($Limit -gt 200) { 200 } else { $Limit }
    $candidates = New-Object System.Collections.Generic.List[object]
    $directChatPayload = Read-JsonFileIfExists -Path $directChatActivityStreamPath
    $directCandidate = New-ActivityStreamCandidatePayload -Payload $directChatPayload -SourcePath $directChatActivityStreamPath -ObjectiveId $ObjectiveId -TaskId $TaskId -Limit $safeLimit
    if ($null -ne $directCandidate) {
        [void]$candidates.Add($directCandidate)
    }

    foreach ($candidatePath in @($activityStreamPrimaryPath, $activityStreamMirrorPath)) {
        $candidatePayload = Read-JsonFileIfExists -Path $candidatePath
        $candidate = New-ActivityStreamCandidatePayload -Payload $candidatePayload -SourcePath $candidatePath -ObjectiveId $ObjectiveId -TaskId $TaskId -Limit $safeLimit
        if ($null -ne $candidate) {
            [void]$candidates.Add($candidate)
        }
    }

    $stateFallbackPayload = Get-StateActivityFallbackPayload -ObjectiveId $ObjectiveId -TaskId $TaskId
    $stateCandidate = New-ActivityStreamCandidatePayload -Payload $stateFallbackPayload -SourcePath $statePath -ObjectiveId $ObjectiveId -TaskId $TaskId -Limit $safeLimit
    if ($null -ne $stateCandidate) {
        [void]$candidates.Add($stateCandidate)
    }

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{
            ok = $true
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source_path = ''
            stream_generated_at = ''
            tod_activity_stream_build_id = $todActivityStreamBuildId
            objective_id = ''
            task_id = ''
            title = ''
            summary = 'No TOD activity stream has been published yet.'
            status = 'idle'
            event = ''
            phase = ''
            latest_event = $null
            count = 0
            events = @()
        }
    }

    $preferDirectChatForScopedTask = -not [string]::IsNullOrWhiteSpace($TaskId)
    $selectedCandidate = @($candidates | Sort-Object -Property @(
            @{ Expression = {
                    if ($preferDirectChatForScopedTask -and [string]::Equals([string]$_.source_path, $directChatActivityStreamPath, [System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$_.task_id, $TaskId, [System.StringComparison]::OrdinalIgnoreCase)) { 1 } else { 0 }
                }; Descending = $true },
            @{ Expression = { Get-ActivityTimestampTicks -Value $_ }; Descending = $true },
            @{ Expression = { if ([string]::Equals([string]$_.source_path, $directChatActivityStreamPath, [System.StringComparison]::OrdinalIgnoreCase)) { 1 } else { 0 } }; Descending = $true }
        ) | Select-Object -First 1)
    return $selectedCandidate[0]
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

        if ($request.HttpMethod -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html" -or $path -eq "/tod" -or $path -eq "/tod/")) {
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
                if ($payload.PSObject.Properties["taskId"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.taskId)) {
                    $invokeParams.TaskId = [string]$payload.taskId
                }
                if ($payload.PSObject.Properties["requestId"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.requestId)) {
                    $invokeParams.RequestId = [string]$payload.requestId
                }
                if ($payload.PSObject.Properties["objectiveId"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.objectiveId)) {
                    $invokeParams.ObjectiveId = [string]$payload.objectiveId
                }
                if ($payload.PSObject.Properties["statePath"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.statePath)) {
                    $invokeParams.StatePath = [string]$payload.statePath
                }
                if ($payload.PSObject.Properties["configPath"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.configPath)) {
                    $invokeParams.ConfigPath = [string]$payload.configPath
                }
                if ($payload.PSObject.Properties["packagePath"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.packagePath)) {
                    $invokeParams.PackagePath = [string]$payload.packagePath
                }
                if ($payload.PSObject.Properties["content"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.content)) {
                    $invokeParams.Content = [string]$payload.content
                }
                if ($payload.PSObject.Properties["applyPlan"] -and $null -ne $payload.applyPlan) {
                    $invokeParams.ApplyPlan = [bool]$payload.applyPlan
                }
                if ($payload.PSObject.Properties["append"] -and $null -ne $payload.append) {
                    $invokeParams.Append = [bool]$payload.append
                }
                if ($payload.PSObject.Properties["dangerousApproved"] -and $null -ne $payload.dangerousApproved) {
                    $invokeParams.DangerousApproved = [bool]$payload.dangerousApproved
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

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/activity-stream") {
            try {
                $objectiveId = [string]$request.QueryString["objective_id"]
                $taskId = [string]$request.QueryString["task_id"]
                $limitRaw = [string]$request.QueryString["limit"]
                $limit = 60
                if (-not [string]::IsNullOrWhiteSpace($limitRaw)) {
                    $parsedLimit = 0
                    if ([int]::TryParse($limitRaw, [ref]$parsedLimit)) {
                        $limit = $parsedLimit
                    }
                }

                $payload = Get-ActivityStreamPayload -ObjectiveId $objectiveId -TaskId $taskId -Limit $limit
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 16)
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

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/tod-conversation") {
            try {
                $encoding = if ($request.ContentEncoding) { $request.ContentEncoding } else { [System.Text.Encoding]::UTF8 }
                $reader = New-Object System.IO.StreamReader($request.InputStream, $encoding)
                $bodyRaw = $reader.ReadToEnd()
                $payload = if ([string]::IsNullOrWhiteSpace($bodyRaw)) { @{} } else { $bodyRaw | ConvertFrom-Json }

                $query = if ($payload.PSObject.Properties['query']) { [string]$payload.query } else { '' }
                $objectiveId = if ($payload.PSObject.Properties['objective_id']) { [string]$payload.objective_id } else { '' }
                $operatorName = if ($payload.PSObject.Properties['operator_name']) { [string]$payload.operator_name } else { '' }
                $conversationHistoryJson = if ($payload.PSObject.Properties['conversation_history_json'] -and -not [string]::IsNullOrWhiteSpace([string]$payload.conversation_history_json)) { [string]$payload.conversation_history_json } else { '[]' }
                $windowMinutes = 10
                if ($payload.PSObject.Properties['window_minutes']) {
                    try { $windowMinutes = [int]$payload.window_minutes } catch { $windowMinutes = 10 }
                }

                $replyPayload = Invoke-TodConversationReplyRequest -Query $query -ObjectiveId $objectiveId -OperatorName $operatorName -ConversationHistoryJson $conversationHistoryJson -WindowMinutes $windowMinutes
                $replyPayload = Finalize-TodConversationReplyPayload -ReplyPayload $replyPayload
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($replyPayload | ConvertTo-Json -Depth 20)
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

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/drive-access-roots") {
            try {
                $payload = Get-DriveAccessRootsPayload -ActivePort $activePort
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 8)
            }
            catch {
                $errorPayload = [pscustomobject]@{ ok = $false; error = $_.Exception.Message }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/drive-access-list") {
            try {
                $requestedPath = [string]$request.QueryString['path']
                $payload = Get-DriveAccessListingPayload -RequestedPath $requestedPath -ActivePort $activePort
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 12)
            }
            catch {
                $errorPayload = [pscustomobject]@{ ok = $false; error = $_.Exception.Message }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/drive-access-download") {
            try {
                $requestedPath = [string]$request.QueryString['path']
                $target = Resolve-DriveAccessPath -RequestedPath $requestedPath -AllowFile
                if ($target.PSIsContainer) {
                    $errorPayload = [pscustomobject]@{ ok = $false; error = 'Requested path is a directory. Use /api/drive-access-list instead.' }
                    Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
                    continue
                }

                $bytes = [System.IO.File]::ReadAllBytes([string]$target.FullName)
                $response.StatusCode = 200
                $response.ContentType = Get-MimeTypeForPath -Path ([string]$target.FullName)
                $response.AddHeader('Content-Disposition', "attachment; filename=`"$($target.Name)`"")
                $response.ContentLength64 = $bytes.LongLength
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                $response.Close()
            }
            catch {
                $errorPayload = [pscustomobject]@{ ok = $false; error = $_.Exception.Message }
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
