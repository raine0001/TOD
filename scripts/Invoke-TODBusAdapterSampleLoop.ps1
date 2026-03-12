param(
    [string]$AdapterScriptPath = "scripts/Invoke-TODBusAdapter.ps1",
    [string]$OutputPath = "shared_state/bus_adapter_integration_sample.json",
    [string]$HandoffOutputPath = "shared_state/bus_execution_handoff_integration_sample.json"
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
$outputAbs = Get-LocalPath -PathValue $OutputPath
$handoffOutputAbs = Get-LocalPath -PathValue $HandoffOutputPath
if (-not (Test-Path -Path $adapterAbs)) { throw "Adapter script not found: $adapterAbs" }

$traceId = "trace-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8))
$executionId = "exec-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8))
$goalId = "MIMGOAL-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant())

$steps = @()

$requestedRaw = & $adapterAbs -Action "consume-event" -EventJson (@{
        event_id = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10))
        event_type = "execution.requested"
        occurred_at = (Get-Date).ToUniversalTime().ToString("o")
        producer = @{ system = "MIM"; component = "ingestion_service"; role = "reasoning_runtime" }
        correlation = @{ trace_id = $traceId; execution_id = $executionId; goal_id = $goalId; source_domain = "mim" }
    payload = @{ runtime_action = "get-engineering-loop-summary"; reliability_hints = @{ simulate_retry_once = $true; simulate_drift = $true } }
    } | ConvertTo-Json -Depth 10 -Compress)
$steps += ($requestedRaw | ConvertFrom-Json)

$summaryRaw = & $adapterAbs -Action "summarize-executions"
$summaryObj = $summaryRaw | ConvertFrom-Json
$summaryDoc = $null
$summaryPathResolved = ""
if (-not [string]::IsNullOrWhiteSpace([string]$summaryObj.summary_path)) {
    $summaryPathResolved = Get-LocalPath -PathValue ([string]$summaryObj.summary_path)
}
if (-not [string]::IsNullOrWhiteSpace($summaryPathResolved) -and (Test-Path -Path $summaryPathResolved)) {
    $summaryDoc = Get-Content -Path $summaryPathResolved -Raw | ConvertFrom-Json
}
$pointerObj = $null
$pointerPathResolved = ""
if (-not [string]::IsNullOrWhiteSpace([string]$summaryObj.discovery_pointer_path)) {
    $pointerPathResolved = Get-LocalPath -PathValue ([string]$summaryObj.discovery_pointer_path)
}
if (-not [string]::IsNullOrWhiteSpace($pointerPathResolved) -and (Test-Path -Path $pointerPathResolved)) {
    $pointerObj = Get-Content -Path $pointerPathResolved -Raw | ConvertFrom-Json
}

$streamPath = Get-LocalPath -PathValue "tod/out/bus/events.jsonl"
$traceEvents = @()
if (Test-Path -Path $streamPath) {
    $traceEvents = @(
        Get-Content -Path $streamPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_ | ConvertFrom-Json } |
        Where-Object {
            $_.PSObject.Properties["correlation"] -and
            $_.correlation -and
            $_.correlation.PSObject.Properties["trace_id"] -and
            ([string]$_.correlation.trace_id -eq $traceId)
        }
    )
}

$lifecycleStarted = @($traceEvents | Where-Object { [string]$_.event_type -eq "execution.started" })
$lifecycleRetryScheduled = @($traceEvents | Where-Object { [string]$_.event_type -eq "execution.retry_scheduled" })
$lifecycleRecovered = @($traceEvents | Where-Object { [string]$_.event_type -eq "execution.recovered" })
$lifecycleDriftDetected = @($traceEvents | Where-Object { [string]$_.event_type -eq "execution.drift_detected" })
$lifecycleFallbackApplied = @($traceEvents | Where-Object { [string]$_.event_type -eq "execution.fallback_applied" })
$lifecycleCancelled = @($traceEvents | Where-Object { [string]$_.event_type -eq "execution.cancelled" })
$lifecycleSucceeded = @($traceEvents | Where-Object { [string]$_.event_type -eq "execution.succeeded" })
$lifecycleFailed = @($traceEvents | Where-Object { [string]$_.event_type -eq "execution.failed" })

$result = [pscustomobject]@{
    ok = $true
    source = "tod-bus-adapter-sample-loop-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    trace_id = $traceId
    execution_id = $executionId
    goal_id = $goalId
    steps = @($steps)
    execution_summary = @($summaryDoc.summaries | Where-Object {
            [string]$_.trace_id -eq $traceId -and [string]$_.execution_id -eq $executionId
        } | Select-Object -First 1)
    execution_summary_artifact = [string]$summaryObj.summary_path
    execution_summary_handoff = [pscustomobject]@{
        generated_at = if ($null -ne $summaryDoc) { [string]$summaryDoc.generated_at } else { "" }
        summary_version = [string]$summaryObj.summary_version
        source = if ($null -ne $summaryDoc) { [string]$summaryDoc.source } else { [string]$summaryObj.source }
        ordering_notes = [string]$summaryObj.ordering_notes
        retention_notes = [string]$summaryObj.retention_notes
        discovery_pointer_path = [string]$summaryObj.discovery_pointer_path
        contract_path = [string]$summaryObj.contract_path
        pointer = $pointerObj
    }
    lifecycle = [pscustomobject]@{
        started = @($lifecycleStarted)
        retry_scheduled = @($lifecycleRetryScheduled)
        recovered = @($lifecycleRecovered)
        drift_detected = @($lifecycleDriftDetected)
        fallback_applied = @($lifecycleFallbackApplied)
        cancelled = @($lifecycleCancelled)
        succeeded = @($lifecycleSucceeded)
        failed = @($lifecycleFailed)
    }
    summary = [pscustomobject]@{
        consumed_requested = [bool](@($steps | Where-Object { [string]$_.action -eq "consume-event" -and [string]$_.status -eq "accepted_executed" }).Count -gt 0)
        published_started = [bool](@($lifecycleStarted).Count -gt 0)
        published_retry_scheduled = [bool](@($lifecycleRetryScheduled).Count -gt 0)
        published_recovered = [bool](@($lifecycleRecovered).Count -gt 0)
        published_drift_detected = [bool](@($lifecycleDriftDetected).Count -gt 0)
        published_fallback_applied = [bool](@($lifecycleFallbackApplied).Count -gt 0)
        published_cancelled = [bool](@($lifecycleCancelled).Count -gt 0)
        published_succeeded = [bool](@($lifecycleSucceeded).Count -gt 0)
        published_failed = [bool](@($lifecycleFailed).Count -gt 0)
    }
}

$outDir = Split-Path -Parent $outputAbs
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$handoffOutDir = Split-Path -Parent $handoffOutputAbs
if (-not [string]::IsNullOrWhiteSpace($handoffOutDir) -and -not (Test-Path -Path $handoffOutDir)) {
    New-Item -ItemType Directory -Path $handoffOutDir -Force | Out-Null
}

$result | ConvertTo-Json -Depth 20 | Set-Content -Path $outputAbs
$handoffArtifact = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-bus-adapter-sample-loop-v1"
    type = "tod_execution_summary_handoff_integration"
    trace_id = $traceId
    execution_id = $executionId
    lifecycle = $result.lifecycle
    execution_summary = $result.execution_summary
    handoff = $result.execution_summary_handoff
}
$handoffArtifact | ConvertTo-Json -Depth 20 | Set-Content -Path $handoffOutputAbs
$result | ConvertTo-Json -Depth 20 | Write-Output
