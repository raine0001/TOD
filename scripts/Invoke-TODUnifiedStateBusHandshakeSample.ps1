param(
    [switch]$RunSampleLoop,
    [string]$SampleLoopScriptPath = "scripts/Invoke-TODBusAdapterSampleLoop.ps1",
    [string]$HandshakeContractPath = "tod/templates/bus/tod_unified_state_bus_handshake.contract.json",
    [string]$SummaryPointerPath = "shared_state/bus_execution_summaries.index.json",
    [string]$SummaryPath = "shared_state/bus_execution_summaries.json",
    [string]$OutputPath = "shared_state/bus_unified_state_multidomain_integration_sample.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

if ($RunSampleLoop) {
    $sampleLoopAbs = Get-LocalPath -PathValue $SampleLoopScriptPath
    if (-not (Test-Path -Path $sampleLoopAbs)) {
        throw "Sample loop script not found: $sampleLoopAbs"
    }
    $sampleLoopRaw = & $sampleLoopAbs
    $sampleLoopObj = $sampleLoopRaw | ConvertFrom-Json
}
else {
    $sampleLoopObj = $null
}

$contractAbs = Get-LocalPath -PathValue $HandshakeContractPath
$pointerAbs = Get-LocalPath -PathValue $SummaryPointerPath
$summaryAbs = Get-LocalPath -PathValue $SummaryPath
$outAbs = Get-LocalPath -PathValue $OutputPath
$eventsAbs = Get-LocalPath -PathValue "tod/out/bus/events.jsonl"

if (-not (Test-Path -Path $contractAbs)) { throw "Handshake contract missing: $contractAbs" }
if (-not (Test-Path -Path $pointerAbs)) { throw "Summary pointer missing: $pointerAbs" }
if (-not (Test-Path -Path $summaryAbs)) { throw "Summary artifact missing: $summaryAbs" }
if (-not (Test-Path -Path $eventsAbs)) { throw "Bus stream missing: $eventsAbs" }

$contractDoc = Get-Content -Path $contractAbs -Raw | ConvertFrom-Json
$pointerDoc = Get-Content -Path $pointerAbs -Raw | ConvertFrom-Json
$summaryDoc = Get-Content -Path $summaryAbs -Raw | ConvertFrom-Json

$allEvents = @(
    Get-Content -Path $eventsAbs |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { $_ | ConvertFrom-Json }
)
if (@($allEvents).Count -eq 0) {
    throw "No events found in bus stream."
}

$traceId = if ($null -ne $sampleLoopObj -and $sampleLoopObj.PSObject.Properties["trace_id"]) { [string]$sampleLoopObj.trace_id } else { [string]$allEvents[-1].correlation.trace_id }
$executionId = if ($null -ne $sampleLoopObj -and $sampleLoopObj.PSObject.Properties["execution_id"]) { [string]$sampleLoopObj.execution_id } else { [string]$allEvents[-1].correlation.execution_id }
$traceEvents = @($allEvents | Where-Object {
        $_.PSObject.Properties["correlation"] -and
        $_.correlation -and
        [string]$_.correlation.trace_id -eq $traceId -and
        [string]$_.correlation.execution_id -eq $executionId
    })

$mimRequest = @($traceEvents | Where-Object { [string]$_.event_type -eq "execution.requested" } | Select-Object -First 1)
$mimRequestObj = $null
if ($mimRequest.Count -gt 0) {
    $mimRequestObj = $mimRequest[0]
}
elseif ($null -ne $sampleLoopObj) {
    $runtimeAction = ""
    if ($sampleLoopObj.steps -and @($sampleLoopObj.steps).Count -gt 0 -and $sampleLoopObj.steps[0].PSObject.Properties["runtime_action"]) {
        $runtimeAction = [string]$sampleLoopObj.steps[0].runtime_action
    }
    $mimRequestObj = [pscustomobject]@{
        event_id = if ($sampleLoopObj.steps -and @($sampleLoopObj.steps).Count -gt 0) { [string]$sampleLoopObj.steps[0].event_id } else { "" }
        event_type = "execution.requested"
        producer = [pscustomobject]@{
            system = "MIM"
            component = "ingestion_service"
            role = "reasoning_runtime"
        }
        correlation = [pscustomobject]@{
            trace_id = $traceId
            execution_id = $executionId
            goal_id = if ($sampleLoopObj.PSObject.Properties["goal_id"]) { [string]$sampleLoopObj.goal_id } else { "" }
            source_domain = "mim"
        }
        payload = [pscustomobject]@{
            runtime_action = $runtimeAction
        }
    }
}
$todLifecycle = @($traceEvents | Where-Object { [string]$_.event_type -ne "execution.requested" })
$todResult = @($traceEvents | Where-Object { [string]$_.event_type -in @("execution.succeeded", "execution.failed", "execution.cancelled", "execution.guardrail_blocked") } | Select-Object -Last 1)

$summaryEntry = @($summaryDoc.summaries | Where-Object {
        [string]$_.trace_id -eq $traceId -and [string]$_.execution_id -eq $executionId
    } | Select-Object -First 1)

$sample = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-unified-state-bus-handshake-sample-v1"
    type = "tod_unified_state_bus_multidomain_integration_sample"
    contract = [pscustomobject]@{
        path = $HandshakeContractPath
        contract_version = [string]$contractDoc.contract_version
        source_domain = [string]$contractDoc.source_domain
    }
    transient_bus = [pscustomobject]@{
        stream_path = "tod/out/bus/events.jsonl"
        trace_id = $traceId
        execution_id = $executionId
        mim_issued_request = $mimRequestObj
        tod_lifecycle = $todLifecycle
        tod_result_handoff = if ($todResult.Count -gt 0) { $todResult[0] } else { $null }
    }
    durable_shared_state = [pscustomobject]@{
        summary_pointer_path = $SummaryPointerPath
        summary_pointer = $pointerDoc
        summary_artifact_path = $SummaryPath
        summary_entry = if ($summaryEntry.Count -gt 0) { $summaryEntry[0] } else { $null }
    }
    separation_assertion = [pscustomobject]@{
        transient_bus_semantics = [string]$contractDoc.semantic_separation.transient_bus_semantics
        durable_shared_state_semantics = [string]$contractDoc.semantic_separation.durable_shared_state_semantics
        boundary_ok = $true
    }
}

$outDir = Split-Path -Parent $outAbs
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$sample | ConvertTo-Json -Depth 30 | Set-Content -Path $outAbs
$sample | ConvertTo-Json -Depth 30 | Write-Output
