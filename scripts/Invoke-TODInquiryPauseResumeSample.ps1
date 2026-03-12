param(
    [string]$AdapterScriptPath = "scripts/Invoke-TODBusAdapter.ps1",
    [string]$OutputPath = "shared_state/bus_inquiry_pause_resume_sample.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

$adapterAbs = Get-LocalPath -PathValue $AdapterScriptPath
$outAbs = Get-LocalPath -PathValue $OutputPath
if (-not (Test-Path -Path $adapterAbs)) { throw "Adapter script not found: $adapterAbs" }

$id = [guid]::NewGuid().ToString("N")
$base = Join-Path $repoRoot ("tod/out/tests/inquiry-sample-" + $id)
$inbox = Join-Path $base "inbox"
$processed = Join-Path $base "processed"
New-Item -ItemType Directory -Path $inbox -Force | Out-Null
New-Item -ItemType Directory -Path $processed -Force | Out-Null

$paths = [pscustomobject]@{
    Stream = (Join-Path $base "events.jsonl")
    State = (Join-Path $base "adapter-state.json")
    ConsumerLog = (Join-Path $base "consumer-log.jsonl")
    CorrelationLog = (Join-Path $base "correlation-log.jsonl")
    Status = (Join-Path $base "bus-adapter-status.json")
    Summary = (Join-Path $base "bus-execution-summaries.json")
    SummaryIndex = (Join-Path $base "bus-execution-summaries.index.json")
    SummaryContract = (Join-Path $repoRoot "tod/templates/bus/tod_bus_execution_summary_handoff.schema.json")
    DomainPolicy = (Join-Path $repoRoot "tod/templates/bus/tod_cross_domain_execution_policy.json")
    Inbox = $inbox
    Processed = $processed
}

function Invoke-Adapter {
    param(
        [Parameter(Mandatory = $true)][string]$AdapterAction,
        [hashtable]$InputParams = @{}
    )

    $invokeMap = @{
        Action = $AdapterAction
        EventStreamPath = $paths.Stream
        InboundInboxPath = $paths.Inbox
        ProcessedInboxPath = $paths.Processed
        AdapterStatePath = $paths.State
        ConsumerLogPath = $paths.ConsumerLog
        CorrelationLogPath = $paths.CorrelationLog
        BusStatusPath = $paths.Status
        ExecutionSummaryPath = $paths.Summary
        ExecutionSummaryIndexPath = $paths.SummaryIndex
        ExecutionSummaryContractPath = $paths.SummaryContract
        ExecutionDomainPolicyPath = $paths.DomainPolicy
    }
    foreach ($k in $InputParams.Keys) {
        $invokeMap[$k] = $InputParams[$k]
    }

    $raw = & $adapterAbs @invokeMap
    return ($raw | ConvertFrom-Json)
}

$traceId = "trace-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8))
$executionId = "exec-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8))
$sourceDomain = "workspace.perception"
$sourceContext = "workspace/mainboard"

[pscustomobject]@{
    source = "tod-bus-adapter-v1"
    updated_at = ""
    processed_event_ids = @()
    accepted_execution_ids = @($executionId)
    paused_execution_ids = @()
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
        paused_pending_inquiry = 0
        resumed_after_inquiry = 0
        deferred_for_operator_clarification = 0
        cancelled_pending_inquiry_timeout = 0
    }
} | ConvertTo-Json -Depth 20 | Set-Content -Path $paths.State

$pauseEvent = @{
    event_id = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10))
    event_type = "execution.pause_requested"
    occurred_at = (Get-Date).ToUniversalTime().ToString("o")
    producer = @{ system = "MIM"; component = "inquiry"; role = "reasoning_runtime" }
    correlation = @{ trace_id = $traceId; execution_id = $executionId; source_domain = $sourceDomain; source_context = $sourceContext }
    payload = @{ note = "need clarification" }
} | ConvertTo-Json -Depth 12 -Compress

$clarificationEvent = @{
    event_id = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10))
    event_type = "execution.clarification_received"
    occurred_at = (Get-Date).ToUniversalTime().AddSeconds(15).ToString("o")
    producer = @{ system = "MIM"; component = "inquiry"; role = "reasoning_runtime" }
    correlation = @{ trace_id = $traceId; execution_id = $executionId; source_domain = $sourceDomain; source_context = $sourceContext }
    payload = @{ clarification = "use latest bounded review" }
} | ConvertTo-Json -Depth 12 -Compress

$resumeEvent = @{
    event_id = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10))
    event_type = "execution.resume_requested"
    occurred_at = (Get-Date).ToUniversalTime().AddSeconds(30).ToString("o")
    producer = @{ system = "MIM"; component = "inquiry"; role = "reasoning_runtime" }
    correlation = @{ trace_id = $traceId; execution_id = $executionId; source_domain = $sourceDomain; source_context = $sourceContext }
    payload = @{ inquiry_resolved = $true }
} | ConvertTo-Json -Depth 12 -Compress

$steps = @()
$steps += Invoke-Adapter -AdapterAction "consume-event" -InputParams @{ EventJson = $pauseEvent }
$steps += Invoke-Adapter -AdapterAction "consume-event" -InputParams @{ EventJson = $clarificationEvent }
$steps += Invoke-Adapter -AdapterAction "consume-event" -InputParams @{ EventJson = $resumeEvent }
$summaryResult = Invoke-Adapter -AdapterAction "summarize-executions"

$events = @()
if (Test-Path -Path $paths.Stream) {
    $events = @(
        Get-Content -Path $paths.Stream |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_ | ConvertFrom-Json } |
        Where-Object {
            $_.PSObject.Properties["correlation"] -and
            $_.correlation -and
            [string]$_.correlation.trace_id -eq $traceId -and
            [string]$_.correlation.execution_id -eq $executionId
        }
    )
}

$paused = @($events | Where-Object { [string]$_.event_type -eq "execution.paused_pending_inquiry" })
$deferred = @($events | Where-Object { [string]$_.event_type -eq "execution.deferred_for_operator_clarification" })
$resumed = @($events | Where-Object { [string]$_.event_type -eq "execution.resumed_after_inquiry" })
$timeoutCancelled = @($events | Where-Object { [string]$_.event_type -eq "execution.cancelled_pending_inquiry_timeout" })
$summaryEntry = @($summaryResult.summaries | Where-Object { [string]$_.trace_id -eq $traceId -and [string]$_.execution_id -eq $executionId } | Select-Object -First 1)

$artifact = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-inquiry-pause-resume-sample-v1"
    type = "tod_inquiry_pause_resume_sample"
    context = [pscustomobject]@{
        trace_id = $traceId
        execution_id = $executionId
        source_domain = $sourceDomain
        source_context = $sourceContext
    }
    steps = @($steps)
    lifecycle = [pscustomobject]@{
        paused_pending_inquiry = @($paused)
        deferred_for_operator_clarification = @($deferred)
        resumed_after_inquiry = @($resumed)
        cancelled_pending_inquiry_timeout = @($timeoutCancelled)
    }
    handoff = [pscustomobject]@{
        summary_path = [string]$summaryResult.summary_path
        discovery_pointer_path = [string]$summaryResult.discovery_pointer_path
        contract_path = [string]$summaryResult.contract_path
        summary_entry = if ($summaryEntry.Count -gt 0) { $summaryEntry[0] } else { $null }
    }
    summary = [pscustomobject]@{
        pause_resume_flow_ok = [bool](@($paused).Count -gt 0 -and @($resumed).Count -gt 0)
        deferred_seen = [bool](@($deferred).Count -gt 0)
        timeout_cancel_seen = [bool](@($timeoutCancelled).Count -gt 0)
    }
}

$outDir = Split-Path -Parent $outAbs
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$artifact | ConvertTo-Json -Depth 30 | Set-Content -Path $outAbs
$artifact | ConvertTo-Json -Depth 30 | Write-Output
