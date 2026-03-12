param(
    [ValidateSet("publish-event", "consume-event", "consume-inbox", "status", "summarize-executions")][string]$Action = "status",
    [string]$EventType,
    [string]$EventJson,
    [string]$EventFile,
    [string]$EventId,
    [string]$TraceId,
    [string]$ExecutionId,
    [string]$GoalId,
    [string]$PlanId,
    [string]$ActionId,
    [string]$SourceDomain,
    [string[]]$ArtifactPaths = @(),
    [string]$EventStreamPath = "tod/out/bus/events.jsonl",
    [string]$InboundInboxPath = "tod/inbox/bus/events",
    [string]$ProcessedInboxPath = "tod/out/bus/processed",
    [string]$AdapterStatePath = "tod/out/bus/adapter-state.json",
    [string]$ConsumerLogPath = "tod/out/bus/consumer-log.jsonl",
    [string]$CorrelationLogPath = "shared_state/bus_correlation_links.jsonl",
    [string]$SchemaPath = "tod/templates/bus/tod_bus_adapter_event.schema.json",
    [string]$BusStatusPath = "shared_state/bus_adapter_status.json",
    [string]$ExecutionSummaryPath = "shared_state/bus_execution_summaries.json",
    [string]$ExecutionSummaryIndexPath = "shared_state/bus_execution_summaries.index.json",
    [string]$ExecutionSummaryContractPath = "tod/templates/bus/tod_bus_execution_summary_handoff.schema.json",
    [string]$TodScriptPath = "scripts/TOD.ps1",
    [string]$TodConfigPath = "tod/config/tod-config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Ensure-ParentDir {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Get-RepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $baseFull = [System.IO.Path]::GetFullPath($repoRoot)
    $targetFull = [System.IO.Path]::GetFullPath($AbsolutePath)

    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull = $baseFull + [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())
    return $relativePath.Replace("\\", "/")
}

function Append-JsonLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Object
    )

    Ensure-ParentDir -FilePath $Path
    ($Object | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine | Add-Content -Path $Path
}

function Load-JsonIfExists {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -Path $Path)) { return $null }
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Get-AdapterState {
    param([Parameter(Mandatory = $true)][string]$StateFile)

    $state = Load-JsonIfExists -Path $StateFile
    if ($null -eq $state) {
        return [pscustomobject]@{
            source = "tod-bus-adapter-v1"
            updated_at = ""
            processed_event_ids = @()
            counters = [pscustomobject]@{
                inbound_accepted = 0
                inbound_rejected = 0
                inbound_ignored = 0
                inbound_duplicate = 0
                outbound_published = 0
                retries_scheduled = 0
                recoveries = 0
                drift_detected = 0
                fallback_applied = 0
                cancelled = 0
                guardrail_blocked = 0
                failed_runtime = 0
                successful_runtime = 0
            }
            accepted_execution_ids = @()
        }
    }

    if (-not $state.PSObject.Properties["processed_event_ids"] -or $null -eq $state.processed_event_ids) {
        $state | Add-Member -NotePropertyName processed_event_ids -NotePropertyValue @() -Force
    }
    if (-not $state.PSObject.Properties["counters"] -or $null -eq $state.counters) {
        $state | Add-Member -NotePropertyName counters -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $state.PSObject.Properties["accepted_execution_ids"] -or $null -eq $state.accepted_execution_ids) {
        $state | Add-Member -NotePropertyName accepted_execution_ids -NotePropertyValue @() -Force
    }

    foreach ($name in @(
            "inbound_accepted", "inbound_rejected", "inbound_ignored", "inbound_duplicate", "outbound_published",
            "retries_scheduled", "recoveries", "drift_detected", "fallback_applied", "cancelled",
            "guardrail_blocked", "failed_runtime", "successful_runtime"
        )) {
        if (-not $state.counters.PSObject.Properties[$name]) {
            $state.counters | Add-Member -NotePropertyName $name -NotePropertyValue 0 -Force
        }
    }

    return $state
}

function Save-AdapterState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$StateFile
    )

    $State.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    Ensure-ParentDir -FilePath $StateFile
    $State | ConvertTo-Json -Depth 20 | Set-Content -Path $StateFile
}

function Get-Schema {
    param([Parameter(Mandatory = $true)][string]$SchemaFile)
    $schema = Load-JsonIfExists -Path $SchemaFile
    if ($null -eq $schema) {
        throw "Schema file not found: $SchemaFile"
    }
    return $schema
}

function New-Reason {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][ValidateSet("info", "warning", "error", "critical")][string]$Severity,
        [Parameter(Mandatory = $true)][ValidateSet("execution", "guardrail", "retry", "drift", "recovery", "outcome")][string]$Category,
        [Parameter(Mandatory = $true)][string]$Message,
        $Evidence = $null
    )

    $reason = [ordered]@{
        code = $Code
        severity = $Severity
        category = $Category
        message = $Message
    }
    if ($null -ne $Evidence) {
        $reason["evidence"] = $Evidence
    }
    return [pscustomobject]$reason
}

function Test-MandatoryCorrelation {
    param(
        [Parameter(Mandatory = $true)]$Event,
        [Parameter(Mandatory = $true)]$Schema
    )

    if (-not $Event.PSObject.Properties["correlation"] -or $null -eq $Event.correlation) {
        return $false
    }

    foreach ($field in @($Schema.correlation_required_fields)) {
        if ($field -eq "event_id") {
            if (-not $Event.PSObject.Properties["event_id"] -or [string]::IsNullOrWhiteSpace([string]$Event.event_id)) { return $false }
        }
        else {
            if (-not $Event.correlation.PSObject.Properties[[string]$field] -or [string]::IsNullOrWhiteSpace([string]$Event.correlation.([string]$field))) { return $false }
        }
    }

    return $true
}

function New-CorrelationObject {
    $corr = [ordered]@{
        trace_id = $TraceId
        execution_id = $ExecutionId
    }
    if (-not [string]::IsNullOrWhiteSpace($GoalId)) { $corr.goal_id = $GoalId }
    if (-not [string]::IsNullOrWhiteSpace($PlanId)) { $corr.plan_id = $PlanId }
    if (-not [string]::IsNullOrWhiteSpace($ActionId)) { $corr.action_id = $ActionId }
    if (-not [string]::IsNullOrWhiteSpace($SourceDomain)) { $corr.source_domain = $SourceDomain }
    return [pscustomobject]$corr
}

function Get-ParsedEvent {
    param(
        [string]$RawJson,
        [string]$FilePath
    )

    try {
        if (-not [string]::IsNullOrWhiteSpace($RawJson)) {
            return ($RawJson | ConvertFrom-Json)
        }
        if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
            $resolved = Get-LocalPath -PathValue $FilePath
            return (Get-Content -Path $resolved -Raw | ConvertFrom-Json)
        }
        return $null
    }
    catch {
        return $null
    }
}

function Get-ExecutionIdFromEvent {
    param($Event)
    if ($null -eq $Event -or -not $Event.PSObject.Properties["correlation"] -or $null -eq $Event.correlation) { return "" }
    if (-not $Event.correlation.PSObject.Properties["execution_id"]) { return "" }
    return [string]$Event.correlation.execution_id
}

function Build-CorrelationFromEvent {
    param($Event)
    $corr = [ordered]@{
        trace_id = [string]$Event.correlation.trace_id
        execution_id = [string]$Event.correlation.execution_id
    }
    foreach ($name in @("goal_id", "plan_id", "action_id", "source_domain")) {
        if ($Event.correlation.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Event.correlation.$name)) {
            $corr[$name] = [string]$Event.correlation.$name
        }
    }
    return [pscustomobject]$corr
}

function Get-ReliabilitySignal {
    param(
        [Parameter(Mandatory = $true)][string]$FinalOutcome,
        [Parameter(Mandatory = $true)][int]$Retries,
        [Parameter(Mandatory = $true)][int]$Fallbacks,
        [Parameter(Mandatory = $true)][int]$DriftEvents,
        [Parameter(Mandatory = $true)][bool]$Recovered
    )

    if ($FinalOutcome -in @("failed", "cancelled", "guardrail_blocked")) {
        return "critical"
    }
    if ($DriftEvents -gt 0 -or $Fallbacks -gt 0) {
        return "warning"
    }
    if ($Retries -gt 0 -or $Recovered) {
        return "elevated"
    }
    return "stable"
}

function Get-RecommendedAttention {
    param([Parameter(Mandatory = $true)][string]$ReliabilitySignal)

    switch ($ReliabilitySignal) {
        "critical" { return "immediate_review" }
        "warning" { return "monitor_closely" }
        "elevated" { return "observe" }
        default { return "none" }
    }
}

function Build-ExecutionSummaries {
    $events = @()
    if (Test-Path -Path $eventStreamAbs) {
        $events = @(
            Get-Content -Path $eventStreamAbs |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                try { $_ | ConvertFrom-Json }
                catch { $null }
            } |
            Where-Object {
                $null -ne $_ -and
                $_.PSObject.Properties["correlation"] -and
                $_.correlation -and
                $_.correlation.PSObject.Properties["trace_id"] -and
                $_.correlation.PSObject.Properties["execution_id"] -and
                -not [string]::IsNullOrWhiteSpace([string]$_.correlation.trace_id) -and
                -not [string]::IsNullOrWhiteSpace([string]$_.correlation.execution_id)
            }
        )
    }

    $correlationLinks = @()
    if (Test-Path -Path $correlationLogAbs) {
        $correlationLinks = @(
            Get-Content -Path $correlationLogAbs |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                try { $_ | ConvertFrom-Json }
                catch { $null }
            } |
            Where-Object {
                $null -ne $_ -and
                $_.PSObject.Properties["trace_id"] -and
                $_.PSObject.Properties["execution_id"] -and
                $_.PSObject.Properties["artifact_path"]
            }
        )
    }

    $groups = @{}
    foreach ($evt in $events) {
        $key = "{0}|{1}" -f ([string]$evt.correlation.trace_id), ([string]$evt.correlation.execution_id)
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = @()
        }
        $groups[$key] += $evt
    }

    $summaries = @()
    foreach ($key in $groups.Keys) {
        $groupEvents = @($groups[$key] | Sort-Object -Property occurred_at)
        if (@($groupEvents).Count -eq 0) { continue }

        $first = $groupEvents[0]
        $traceIdValue = [string]$first.correlation.trace_id
        $executionIdValue = [string]$first.correlation.execution_id

        $retries = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.retry_scheduled" }).Count
        $fallbacks = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.fallback_applied" }).Count
        $recovered = [bool](@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.recovered" }).Count -gt 0)
        $driftEvents = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.drift_detected" }).Count
        $cancelled = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.cancelled" }).Count
        $guardrailBlocks = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.guardrail_blocked" }).Count

        $finalOutcome = "in_progress"
        if (@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.cancelled" }).Count -gt 0) {
            $finalOutcome = "cancelled"
        }
        elseif (@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.guardrail_blocked" }).Count -gt 0) {
            $finalOutcome = "guardrail_blocked"
        }
        elseif (@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.failed" }).Count -gt 0) {
            $finalOutcome = "failed"
        }
        elseif (@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.succeeded" }).Count -gt 0) {
            $finalOutcome = "succeeded"
        }

        $reliabilitySignal = Get-ReliabilitySignal -FinalOutcome $finalOutcome -Retries $retries -Fallbacks $fallbacks -DriftEvents $driftEvents -Recovered $recovered
        $recommendedAttention = Get-RecommendedAttention -ReliabilitySignal $reliabilitySignal

        $artifactFromEvents = @(
            $groupEvents |
            ForEach-Object {
                if ($_.PSObject.Properties["artifact_links"] -and $_.artifact_links) { @($_.artifact_links) } else { @() }
            }
        )
        $artifactFromCorrelationLog = @(
            $correlationLinks |
            Where-Object { [string]$_.trace_id -eq $traceIdValue -and [string]$_.execution_id -eq $executionIdValue } |
            ForEach-Object { [string]$_.artifact_path }
        )
        $artifactLinks = @($artifactFromEvents + $artifactFromCorrelationLog | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)

        $summaries += [pscustomobject]@{
            trace_id = $traceIdValue
            execution_id = $executionIdValue
            final_outcome = $finalOutcome
            retries = $retries
            fallbacks = $fallbacks
            recovered = $recovered
            drift_events = $driftEvents
            cancelled = $cancelled
            guardrail_blocks = $guardrailBlocks
            reliability_signal = $reliabilitySignal
            recommended_attention = $recommendedAttention
            event_count = [int]@($groupEvents).Count
            artifact_links = $artifactLinks
            last_event_at = [string]$groupEvents[-1].occurred_at
        }
    }

    return @(
        $summaries | Sort-Object -Property @(
            @{ Expression = { [string]$_.last_event_at }; Descending = $true },
            @{ Expression = { [string]$_.trace_id }; Descending = $false },
            @{ Expression = { [string]$_.execution_id }; Descending = $false }
        )
    )
}

function Publish-EventInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)]$Correlation,
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)]$Reasons,
        [string[]]$Artifacts = @()
    )

    if (@($schema.outbound_event_types) -notcontains $Type) {
        throw "Unsupported outbound event type: $Type"
    }

    $event = [pscustomobject]@{
        event_id = $Id
        event_type = $Type
        occurred_at = (Get-Date).ToUniversalTime().ToString("o")
        producer = [pscustomobject]@{
            system = "TOD"
            component = "bus_adapter"
            role = "execution_runtime"
        }
        correlation = $Correlation
        reasons = @($Reasons)
        payload = $Payload
    }

    if (@($Artifacts).Count -gt 0) {
        $event | Add-Member -NotePropertyName artifact_links -NotePropertyValue @($Artifacts) -Force
    }

    if (-not (Test-MandatoryCorrelation -Event $event -Schema $schema)) {
        throw "publish-event failed mandatory correlation validation"
    }

    Append-JsonLine -Path $eventStreamAbs -Object $event

    foreach ($artifactPath in @($Artifacts)) {
        if (-not [string]::IsNullOrWhiteSpace($artifactPath)) {
            Append-JsonLine -Path $correlationLogAbs -Object ([pscustomobject]@{
                    linked_at = (Get-Date).ToUniversalTime().ToString("o")
                    event_id = $event.event_id
                    trace_id = [string]$event.correlation.trace_id
                    execution_id = [string]$event.correlation.execution_id
                    artifact_path = [string]$artifactPath
                })
        }
    }

    $state.counters.outbound_published = [int]$state.counters.outbound_published + 1
    Save-AdapterState -State $state -StateFile $stateAbs
    return $event
}

function Write-StatusArtifact {
    param(
        [string]$LastAction = "",
        [string]$LastStatus = "",
        [string]$LastEventId = ""
    )

    $streamExists = Test-Path -Path $eventStreamAbs
    $streamCount = 0
    if ($streamExists) {
        $streamCount = @((Get-Content -Path $eventStreamAbs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })).Count
    }

    $statusObj = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        source = "tod-bus-adapter-v1"
        type = "bus_adapter_status"
        last_action = $LastAction
        last_status = $LastStatus
        last_event_id = $LastEventId
        counters = $state.counters
        accepted_execution_ids_count = [int]@($state.accepted_execution_ids).Count
        stream_event_count = [int]$streamCount
        schema = [string]$schema.schema_name
        inbound_event_types = @($schema.inbound_event_types)
        outbound_event_types = @($schema.outbound_event_types)
        lifecycle_feedback = [pscustomobject]@{
            retries_scheduled = [int]$state.counters.retries_scheduled
            recoveries = [int]$state.counters.recoveries
            drift_detected = [int]$state.counters.drift_detected
            fallback_applied = [int]$state.counters.fallback_applied
            cancelled = [int]$state.counters.cancelled
            guardrail_blocked = [int]$state.counters.guardrail_blocked
            failed_runtime = [int]$state.counters.failed_runtime
            successful_runtime = [int]$state.counters.successful_runtime
        }
    }

    Ensure-ParentDir -FilePath $busStatusAbs
    $statusObj | ConvertTo-Json -Depth 20 | Set-Content -Path $busStatusAbs
}

$eventStreamAbs = Get-LocalPath -PathValue $EventStreamPath
$inboxAbs = Get-LocalPath -PathValue $InboundInboxPath
$processedAbs = Get-LocalPath -PathValue $ProcessedInboxPath
$stateAbs = Get-LocalPath -PathValue $AdapterStatePath
$consumerLogAbs = Get-LocalPath -PathValue $ConsumerLogPath
$correlationLogAbs = Get-LocalPath -PathValue $CorrelationLogPath
$schemaAbs = Get-LocalPath -PathValue $SchemaPath
$busStatusAbs = Get-LocalPath -PathValue $BusStatusPath
$executionSummaryAbs = Get-LocalPath -PathValue $ExecutionSummaryPath
$executionSummaryIndexAbs = Get-LocalPath -PathValue $ExecutionSummaryIndexPath
$executionSummaryContractAbs = Get-LocalPath -PathValue $ExecutionSummaryContractPath
$todScriptAbs = Get-LocalPath -PathValue $TodScriptPath
$todConfigAbs = Get-LocalPath -PathValue $TodConfigPath

$schema = Get-Schema -SchemaFile $schemaAbs
$state = Get-AdapterState -StateFile $stateAbs

switch ($Action) {
    "publish-event" {
        if ([string]::IsNullOrWhiteSpace($EventType)) {
            throw "-EventType is required for publish-event"
        }
        if (@($schema.outbound_event_types) -notcontains $EventType) {
            throw "Unsupported outbound event type: $EventType"
        }
        if ([string]::IsNullOrWhiteSpace($EventId) -or [string]::IsNullOrWhiteSpace($TraceId) -or [string]::IsNullOrWhiteSpace($ExecutionId)) {
            throw "publish-event requires -EventId, -TraceId, and -ExecutionId"
        }

        $payloadObject = [pscustomobject]@{}
        if (-not [string]::IsNullOrWhiteSpace($EventJson)) {
            try {
                $payloadObject = $EventJson | ConvertFrom-Json
            }
            catch {
                throw "publish-event received malformed -EventJson payload"
            }
        }

        $reason = New-Reason -Code "execution_started" -Severity "info" -Category "execution" -Message "Outbound execution event published."
        $event = Publish-EventInternal -Type $EventType -Id $EventId -Correlation (New-CorrelationObject) -Payload $payloadObject -Reasons @($reason) -Artifacts @($ArtifactPaths)
        Write-StatusArtifact -LastAction "publish-event" -LastStatus "published" -LastEventId ([string]$EventId)

        [pscustomobject]@{
            ok = $true
            action = "publish-event"
            status = "published"
            event = $event
            stream_path = $eventStreamAbs
        } | ConvertTo-Json -Depth 20 | Write-Output
        break
    }

    "consume-event" {
        $event = Get-ParsedEvent -RawJson $EventJson -FilePath $EventFile
        if ($null -eq $event) {
            $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
            Save-AdapterState -State $state -StateFile $stateAbs
            Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                    logged_at = (Get-Date).ToUniversalTime().ToString("o")
                    status = "rejected_malformed"
                    reason = "request_malformed"
                    input_file = if ([string]::IsNullOrWhiteSpace($EventFile)) { "" } else { $EventFile }
                })
            Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_malformed"
            [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_malformed" } | ConvertTo-Json -Depth 10 | Write-Output
            break
        }

        if (-not (Test-MandatoryCorrelation -Event $event -Schema $schema)) {
            $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
            Save-AdapterState -State $state -StateFile $stateAbs
            Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                    logged_at = (Get-Date).ToUniversalTime().ToString("o")
                    status = "rejected_malformed"
                    reason = "request_malformed"
                    event_id = if ($event.PSObject.Properties["event_id"]) { [string]$event.event_id } else { "" }
                })
            Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_malformed" -LastEventId (if ($event.PSObject.Properties["event_id"]) { [string]$event.event_id } else { "" })
            [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_malformed" } | ConvertTo-Json -Depth 10 | Write-Output
            break
        }

        $eventIdValue = [string]$event.event_id
        if (@($state.processed_event_ids) -contains $eventIdValue) {
            $state.counters.inbound_duplicate = [int]$state.counters.inbound_duplicate + 1
            Save-AdapterState -State $state -StateFile $stateAbs
            Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                    logged_at = (Get-Date).ToUniversalTime().ToString("o")
                    status = "duplicate_ignored"
                    reason = "request_duplicate_ignored"
                    event_id = $eventIdValue
                    event_type = [string]$event.event_type
                })
            Write-StatusArtifact -LastAction "consume-event" -LastStatus "duplicate_ignored" -LastEventId $eventIdValue
            [pscustomobject]@{ ok = $true; action = "consume-event"; status = "duplicate_ignored"; event_id = $eventIdValue } | ConvertTo-Json -Depth 10 | Write-Output
            break
        }

        $inboundType = [string]$event.event_type
        if (@($schema.inbound_event_types) -contains $inboundType) {
            $executionIdValue = Get-ExecutionIdFromEvent -Event $event

            if ($inboundType -eq "execution.cancel_requested") {
                if (@($state.accepted_execution_ids) -notcontains $executionIdValue) {
                    $state.counters.inbound_ignored = [int]$state.counters.inbound_ignored + 1
                    Save-AdapterState -State $state -StateFile $stateAbs
                    Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                            logged_at = (Get-Date).ToUniversalTime().ToString("o")
                            status = "ignored_out_of_order"
                            reason = "request_out_of_order_ignored"
                            event_id = $eventIdValue
                            event_type = $inboundType
                            execution_id = $executionIdValue
                        })
                    Write-StatusArtifact -LastAction "consume-event" -LastStatus "ignored_out_of_order" -LastEventId $eventIdValue
                    [pscustomobject]@{ ok = $true; action = "consume-event"; status = "ignored_out_of_order"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                    break
                }

                $corrCancelled = Build-CorrelationFromEvent -Event $event
                $cancelEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $cancelReason = New-Reason -Code "execution_cancelled" -Severity "warning" -Category "execution" -Message "Cancellation request accepted for active execution." -Evidence ([pscustomobject]@{ execution_id = $executionIdValue })
                $null = Publish-EventInternal -Type "execution.cancelled" -Id $cancelEventId -Correlation $corrCancelled -Payload ([pscustomobject]@{ state = "cancelled"; cause = "cancel_requested" }) -Reasons @($cancelReason) -Artifacts @()

                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.accepted_execution_ids = @($state.accepted_execution_ids | Where-Object { [string]$_ -ne $executionIdValue })
                $state.counters.inbound_accepted = [int]$state.counters.inbound_accepted + 1
                $state.counters.cancelled = [int]$state.counters.cancelled + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "accepted_cancelled"
                        reason = "request_validated"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        trace_id = [string]$event.correlation.trace_id
                        execution_id = $executionIdValue
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "accepted_cancelled" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = "accepted_cancelled"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            if ($inboundType -eq "execution.priority_changed") {
                if (@($state.accepted_execution_ids) -notcontains $executionIdValue) {
                    $state.counters.inbound_ignored = [int]$state.counters.inbound_ignored + 1
                    Save-AdapterState -State $state -StateFile $stateAbs
                    Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                            logged_at = (Get-Date).ToUniversalTime().ToString("o")
                            status = "ignored_out_of_order"
                            reason = "request_out_of_order_ignored"
                            event_id = $eventIdValue
                            event_type = $inboundType
                            execution_id = $executionIdValue
                        })
                    Write-StatusArtifact -LastAction "consume-event" -LastStatus "ignored_out_of_order" -LastEventId $eventIdValue
                    [pscustomobject]@{ ok = $true; action = "consume-event"; status = "ignored_out_of_order"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                    break
                }

                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.counters.inbound_accepted = [int]$state.counters.inbound_accepted + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "accepted_control_signal"
                        reason = "request_validated"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        trace_id = [string]$event.correlation.trace_id
                        execution_id = $executionIdValue
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "accepted_control_signal" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = "accepted_control_signal"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            $runtimeAction = ""
            if ($event.PSObject.Properties["payload"] -and $event.payload -and $event.payload.PSObject.Properties["runtime_action"]) {
                $runtimeAction = [string]$event.payload.runtime_action
            }

            if ([string]::IsNullOrWhiteSpace($runtimeAction)) {
                $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "rejected_malformed"
                        reason = "request_malformed"
                        event_id = $eventIdValue
                        event_type = $inboundType
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_malformed" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_malformed"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            if (@($schema.runtime_allowed_actions) -notcontains $runtimeAction) {
                $corr = Build-CorrelationFromEvent -Event $event
                $blockedReason = New-Reason -Code "guardrail_action_not_allowed" -Severity "warning" -Category "guardrail" -Message "Requested runtime action is not allowed by bus adapter guardrail." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction })
                $blockedId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $null = Publish-EventInternal -Type "execution.guardrail_blocked" -Id $blockedId -Correlation $corr -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; decision = "blocked" }) -Reasons @($blockedReason) -Artifacts @()

                $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
                $state.counters.guardrail_blocked = [int]$state.counters.guardrail_blocked + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "rejected_guardrail"
                        reason = "guardrail_action_not_allowed"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        runtime_action = $runtimeAction
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_guardrail" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_guardrail"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
            if (@($state.accepted_execution_ids) -notcontains $executionIdValue) {
                $state.accepted_execution_ids = @($state.accepted_execution_ids) + @($executionIdValue)
            }
            $state.counters.inbound_accepted = [int]$state.counters.inbound_accepted + 1
            Save-AdapterState -State $state -StateFile $stateAbs

            Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                    logged_at = (Get-Date).ToUniversalTime().ToString("o")
                    status = "accepted"
                    reason = "request_validated"
                    event_id = $eventIdValue
                    event_type = $inboundType
                    trace_id = [string]$event.correlation.trace_id
                    execution_id = $executionIdValue
                    runtime_action = $runtimeAction
                })

            $corrAccepted = Build-CorrelationFromEvent -Event $event
            $startEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
            $startReason = New-Reason -Code "execution_started" -Severity "info" -Category "execution" -Message "Execution requested event accepted and runtime action started." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction })
            $null = Publish-EventInternal -Type "execution.started" -Id $startEventId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; state = "started" }) -Reasons @($startReason) -Artifacts @()

            $runtimeOk = $false
            $runtimeSummary = [pscustomobject]@{ runtime_action = $runtimeAction }
            $runtimeError = ""
            $simulateRetryOnce = $false
            $simulateDrift = $false
            if ($event.PSObject.Properties["payload"] -and $event.payload) {
                if ($event.payload.PSObject.Properties["simulate_retry_once"]) {
                    $simulateRetryOnce = [bool]$event.payload.simulate_retry_once
                }
                if ($event.payload.PSObject.Properties["simulate_drift"]) {
                    $simulateDrift = [bool]$event.payload.simulate_drift
                }
                if ($event.payload.PSObject.Properties["reliability_hints"] -and $event.payload.reliability_hints) {
                    if ($event.payload.reliability_hints.PSObject.Properties["simulate_retry_once"]) {
                        $simulateRetryOnce = [bool]$event.payload.reliability_hints.simulate_retry_once
                    }
                    if ($event.payload.reliability_hints.PSObject.Properties["simulate_drift"]) {
                        $simulateDrift = [bool]$event.payload.reliability_hints.simulate_drift
                    }
                }
            }

            $attempt = 0
            $maxAttempts = if ($simulateRetryOnce) { 2 } else { 1 }
            while (($attempt -lt $maxAttempts) -and (-not $runtimeOk)) {
                $attempt = $attempt + 1
                try {
                    if ($simulateRetryOnce -and $attempt -eq 1) {
                        throw "Simulated transient failure before bounded retry"
                    }

                    if (-not (Test-Path -Path $todScriptAbs)) { throw "TOD runtime script not found" }
                    if (-not (Test-Path -Path $todConfigAbs)) { throw "TOD runtime config not found" }

                    $runtimeRaw = & $todScriptAbs -Action $runtimeAction -ConfigPath $todConfigAbs -Top 10
                    $runtimePayload = $runtimeRaw | ConvertFrom-Json
                    $runtimeOk = $true
                    if ($runtimePayload -and $runtimePayload.PSObject.Properties["path"]) {
                        $runtimeSummary | Add-Member -NotePropertyName path -NotePropertyValue ([string]$runtimePayload.path) -Force
                    }
                    if ($runtimePayload -and $runtimePayload.PSObject.Properties["status"]) {
                        $runtimeSummary | Add-Member -NotePropertyName status -NotePropertyValue ([string]$runtimePayload.status) -Force
                    }
                    if ($runtimePayload -and $runtimePayload.PSObject.Properties["generated_at"]) {
                        $runtimeSummary | Add-Member -NotePropertyName generated_at -NotePropertyValue ([string]$runtimePayload.generated_at) -Force
                    }
                }
                catch {
                    $runtimeOk = $false
                    $runtimeError = [string]$_.Exception.Message

                    if ($attempt -lt $maxAttempts) {
                        $retryId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                        $retryReason = New-Reason -Code "retry_scheduled" -Severity "warning" -Category "retry" -Message "Transient runtime failure encountered; bounded retry scheduled." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; attempt = $attempt; next_attempt = ($attempt + 1) })
                        $null = Publish-EventInternal -Type "execution.retry_scheduled" -Id $retryId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; current_attempt = $attempt; next_attempt = ($attempt + 1) }) -Reasons @($retryReason) -Artifacts @()
                        $state.counters.retries_scheduled = [int]$state.counters.retries_scheduled + 1
                        Save-AdapterState -State $state -StateFile $stateAbs
                    }
                }
            }

            if ($runtimeOk -and $attempt -gt 1) {
                $fallbackId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $fallbackReason = New-Reason -Code "fallback_applied" -Severity "warning" -Category "recovery" -Message "Fallback path applied via bounded retry execution." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; attempts = $attempt })
                $null = Publish-EventInternal -Type "execution.fallback_applied" -Id $fallbackId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; strategy = "bounded_retry"; attempts = $attempt }) -Reasons @($fallbackReason) -Artifacts @()

                $recoverId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $recoverReason = New-Reason -Code "recovery_completed" -Severity "info" -Category "recovery" -Message "Execution recovered after bounded retry." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; attempts = $attempt })
                $null = Publish-EventInternal -Type "execution.recovered" -Id $recoverId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; attempts = $attempt; state = "recovered" }) -Reasons @($recoverReason) -Artifacts @()

                $state.counters.fallback_applied = [int]$state.counters.fallback_applied + 1
                $state.counters.recoveries = [int]$state.counters.recoveries + 1
                Save-AdapterState -State $state -StateFile $stateAbs
            }

            $runtimeStatus = ""
            if ($runtimeSummary.PSObject.Properties["status"]) {
                $runtimeStatus = [string]$runtimeSummary.status
            }
            if ($runtimeOk -and ($simulateDrift -or ($runtimeStatus -in @("warning", "critical", "warming", "degraded")))) {
                $driftId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $driftReason = New-Reason -Code "drift_detected" -Severity "warning" -Category "drift" -Message "Runtime drift signal observed during bounded execution." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; status = $runtimeStatus })
                $null = Publish-EventInternal -Type "execution.drift_detected" -Id $driftId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; drift_state = "warning"; status = $runtimeStatus }) -Reasons @($driftReason) -Artifacts @()
                $state.counters.drift_detected = [int]$state.counters.drift_detected + 1
                Save-AdapterState -State $state -StateFile $stateAbs
            }

            if ($runtimeOk) {
                $successEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $successReason = New-Reason -Code "execution_succeeded" -Severity "info" -Category "outcome" -Message "Requested runtime action completed successfully." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction })
                $artifactLinks = @("shared_state/next_actions.json", "shared_state/review_artifacts_index.json")
                $null = Publish-EventInternal -Type "execution.succeeded" -Id $successEventId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; result = $runtimeSummary }) -Reasons @($successReason) -Artifacts $artifactLinks

                $state.accepted_execution_ids = @($state.accepted_execution_ids | Where-Object { [string]$_ -ne $executionIdValue })
                $state.counters.successful_runtime = [int]$state.counters.successful_runtime + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "accepted_executed" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = "accepted_executed"; event_id = $eventIdValue; event_type = $inboundType; runtime_action = $runtimeAction } | ConvertTo-Json -Depth 12 | Write-Output
                break
            }

            $failedEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
            $failedReason = New-Reason -Code "execution_failed" -Severity "error" -Category "execution" -Message "Requested runtime action failed." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; error = $runtimeError })
            $null = Publish-EventInternal -Type "execution.failed" -Id $failedEventId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; error = $runtimeError }) -Reasons @($failedReason) -Artifacts @()

            $state.accepted_execution_ids = @($state.accepted_execution_ids | Where-Object { [string]$_ -ne $executionIdValue })
            $state.counters.failed_runtime = [int]$state.counters.failed_runtime + 1
            Save-AdapterState -State $state -StateFile $stateAbs
            Write-StatusArtifact -LastAction "consume-event" -LastStatus "accepted_failed" -LastEventId $eventIdValue
            [pscustomobject]@{ ok = $false; action = "consume-event"; status = "accepted_failed"; event_id = $eventIdValue; event_type = $inboundType; runtime_action = $runtimeAction; error = $runtimeError } | ConvertTo-Json -Depth 12 | Write-Output
            break
        }

        $state.counters.inbound_ignored = [int]$state.counters.inbound_ignored + 1
        Save-AdapterState -State $state -StateFile $stateAbs
        Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                logged_at = (Get-Date).ToUniversalTime().ToString("o")
                status = "ignored_unknown"
                reason = "request_unknown_type_ignored"
                event_id = $eventIdValue
                event_type = $inboundType
            })
        Write-StatusArtifact -LastAction "consume-event" -LastStatus "ignored_unknown" -LastEventId $eventIdValue
        [pscustomobject]@{ ok = $true; action = "consume-event"; status = "ignored_unknown"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
        break
    }

    "consume-inbox" {
        if (-not (Test-Path -Path $inboxAbs)) {
            [pscustomobject]@{ ok = $true; action = "consume-inbox"; status = "no_inbox"; inbox_path = $inboxAbs; consumed = 0 } | ConvertTo-Json -Depth 10 | Write-Output
            break
        }

        if (-not (Test-Path -Path $processedAbs)) {
            New-Item -ItemType Directory -Path $processedAbs -Force | Out-Null
        }

        $files = @(Get-ChildItem -Path $inboxAbs -Filter "*.json" -File | Sort-Object LastWriteTimeUtc)
        $results = @()
        foreach ($file in $files) {
            $consumeRaw = & $PSCommandPath -Action "consume-event" -EventFile $file.FullName -EventStreamPath $EventStreamPath -InboundInboxPath $InboundInboxPath -ProcessedInboxPath $ProcessedInboxPath -AdapterStatePath $AdapterStatePath -ConsumerLogPath $ConsumerLogPath -CorrelationLogPath $CorrelationLogPath -SchemaPath $SchemaPath -BusStatusPath $BusStatusPath -TodScriptPath $TodScriptPath -TodConfigPath $TodConfigPath
            $consumeObj = $consumeRaw | ConvertFrom-Json
            $results += $consumeObj

            $dest = Join-Path $processedAbs $file.Name
            Move-Item -Path $file.FullName -Destination $dest -Force
        }

        [pscustomobject]@{
            ok = $true
            action = "consume-inbox"
            status = "processed"
            consumed = @($results).Count
            accepted = [int]@($results | Where-Object { [string]$_.status -in @("accepted", "accepted_executed", "accepted_control_signal", "accepted_cancelled") }).Count
            ignored = [int]@($results | Where-Object { [string]$_.status -eq "ignored_unknown" }).Count
            rejected = [int]@($results | Where-Object { [string]$_.status -eq "rejected_malformed" }).Count
            duplicate = [int]@($results | Where-Object { [string]$_.status -eq "duplicate_ignored" }).Count
        } | ConvertTo-Json -Depth 12 | Write-Output
        Write-StatusArtifact -LastAction "consume-inbox" -LastStatus "processed"
        break
    }

    "status" {
        $statusObj = [pscustomobject]@{
            ok = $true
            action = "status"
            source = "tod-bus-adapter-v1"
            schema = $schema.schema_name
            outbound_event_types = @($schema.outbound_event_types)
            inbound_event_types = @($schema.inbound_event_types)
            state = $state
            paths = [pscustomobject]@{
                stream = $eventStreamAbs
                inbox = $inboxAbs
                processed = $processedAbs
                state = $stateAbs
                consumer_log = $consumerLogAbs
                correlation_log = $correlationLogAbs
                schema = $schemaAbs
                execution_summary = $executionSummaryAbs
                execution_summary_index = $executionSummaryIndexAbs
                execution_summary_contract = $executionSummaryContractAbs
            }
        }

        $statusObj | ConvertTo-Json -Depth 20 | Write-Output
        Write-StatusArtifact -LastAction "status" -LastStatus "ok"
        break
    }

    "summarize-executions" {
        $summaries = Build-ExecutionSummaries
        $summaryVersion = "1.0.0"
        $orderingNotes = "Summaries are sorted by last_event_at descending; ties are ordered by trace_id then execution_id ascending."
        $retentionNotes = "Artifact is regenerated and overwritten per summarize-executions run; long-term history remains in the bus event stream."
        $summaryPathRelative = Get-RepoRelativePath -AbsolutePath $executionSummaryAbs
        $summaryIndexPathRelative = Get-RepoRelativePath -AbsolutePath $executionSummaryIndexAbs
        $summaryContractPathRelative = Get-RepoRelativePath -AbsolutePath $executionSummaryContractAbs

        $summaryObj = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            summary_version = $summaryVersion
            source = "tod-bus-adapter-v1"
            type = "bus_execution_summaries"
            ordering_notes = $orderingNotes
            retention_notes = $retentionNotes
            discovery_pointer_path = $summaryIndexPathRelative
            contract_path = $summaryContractPathRelative
            summary_count = [int]@($summaries).Count
            summaries = @($summaries)
        }

        $pointerObj = [pscustomobject]@{
            generated_at = $summaryObj.generated_at
            summary_version = $summaryVersion
            source = "tod-bus-adapter-v1"
            type = "bus_execution_summaries_pointer"
            latest_summary_path = $summaryPathRelative
            contract_path = $summaryContractPathRelative
            ordering_notes = $orderingNotes
            retention_notes = $retentionNotes
        }

        Ensure-ParentDir -FilePath $executionSummaryAbs
        $summaryObj | ConvertTo-Json -Depth 20 | Set-Content -Path $executionSummaryAbs
        Ensure-ParentDir -FilePath $executionSummaryIndexAbs
        $pointerObj | ConvertTo-Json -Depth 20 | Set-Content -Path $executionSummaryIndexAbs
        Write-StatusArtifact -LastAction "summarize-executions" -LastStatus "ok"

        [pscustomobject]@{
            ok = $true
            action = "summarize-executions"
            status = "ok"
            summary_path = $summaryPathRelative
            summary_version = $summaryVersion
            ordering_notes = $orderingNotes
            retention_notes = $retentionNotes
            discovery_pointer_path = $summaryIndexPathRelative
            contract_path = $summaryContractPathRelative
            summary_count = [int]@($summaries).Count
            summaries = @($summaries)
        } | ConvertTo-Json -Depth 20 | Write-Output
        break
    }
}
