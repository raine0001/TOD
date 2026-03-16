param(
    [switch]$RunSampleLoop,
    [string]$SampleLoopScriptPath = "scripts/Invoke-TODBusAdapterSampleLoop.ps1",
    [string]$PolicyPath = "tod/templates/bus/tod_cross_domain_execution_policy.json",
    [string]$SummaryPath = "shared_state/bus_execution_summaries.json",
    [string]$SummaryPointerPath = "shared_state/bus_execution_summaries.index.json",
    [string]$HandoffSamplePath = "shared_state/bus_execution_handoff_integration_sample.json",
    [string]$OutputPath = "shared_state/bus_perception_workspace_execution_sample.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

$sampleLoopAbs = Get-LocalPath -PathValue $SampleLoopScriptPath
$policyAbs = Get-LocalPath -PathValue $PolicyPath
$summaryAbs = Get-LocalPath -PathValue $SummaryPath
$summaryPointerAbs = Get-LocalPath -PathValue $SummaryPointerPath
$handoffAbs = Get-LocalPath -PathValue $HandoffSamplePath
$outAbs = Get-LocalPath -PathValue $OutputPath

if (-not (Test-Path -Path $sampleLoopAbs)) { throw "Sample loop script not found: $sampleLoopAbs" }
if (-not (Test-Path -Path $policyAbs)) { throw "Cross-domain execution policy not found: $policyAbs" }

if ($RunSampleLoop) {
    $sampleLoopRaw = & $sampleLoopAbs -SourceDomain "workspace.perception" -SourceContext "workspace/mainboard" -PerceptionState "clear" -PerceptionSafety "safe"
    $sampleLoopObj = $sampleLoopRaw | ConvertFrom-Json
}
else {
    if (-not (Test-Path -Path $handoffAbs)) { throw "Handoff sample not found: $handoffAbs" }
    $sampleLoopObj = $null
}

if (-not (Test-Path -Path $summaryAbs)) { throw "Summary artifact not found: $summaryAbs" }
if (-not (Test-Path -Path $summaryPointerAbs)) { throw "Summary pointer artifact not found: $summaryPointerAbs" }
if (-not (Test-Path -Path $handoffAbs)) { throw "Handoff sample not found: $handoffAbs" }

$policy = Get-Content -Path $policyAbs -Raw | ConvertFrom-Json
$summaryDoc = Get-Content -Path $summaryAbs -Raw | ConvertFrom-Json
$pointerDoc = Get-Content -Path $summaryPointerAbs -Raw | ConvertFrom-Json
$handoffDoc = Get-Content -Path $handoffAbs -Raw | ConvertFrom-Json

$traceId = if ($null -ne $sampleLoopObj -and $sampleLoopObj.PSObject.Properties["trace_id"]) { [string]$sampleLoopObj.trace_id } else { [string]$handoffDoc.trace_id }
$executionId = if ($null -ne $sampleLoopObj -and $sampleLoopObj.PSObject.Properties["execution_id"]) { [string]$sampleLoopObj.execution_id } else { [string]$handoffDoc.execution_id }
$sourceDomain = if ($null -ne $sampleLoopObj -and $sampleLoopObj.PSObject.Properties["source_domain"]) { [string]$sampleLoopObj.source_domain } else { [string]$handoffDoc.source_domain }
$sourceContext = if ($null -ne $sampleLoopObj -and $sampleLoopObj.PSObject.Properties["source_context"]) { [string]$sampleLoopObj.source_context } else { [string]$handoffDoc.source_context }
$summaryEntry = @($summaryDoc.summaries | Where-Object {
        [string]$_.trace_id -eq $traceId -and [string]$_.execution_id -eq $executionId
    } | Select-Object -First 1)

$lifecycleReasonCodes = @()
if ($null -ne $handoffDoc.lifecycle) {
    foreach ($eventList in @(
            @($handoffDoc.lifecycle.started),
            @($handoffDoc.lifecycle.retry_scheduled),
            @($handoffDoc.lifecycle.recovered),
            @($handoffDoc.lifecycle.drift_detected),
            @($handoffDoc.lifecycle.fallback_applied),
            @($handoffDoc.lifecycle.cancelled),
            @($handoffDoc.lifecycle.succeeded),
            @($handoffDoc.lifecycle.failed)
        )) {
        foreach ($evt in @($eventList)) {
            foreach ($r in @($evt.reasons)) {
                if ($r -and $r.PSObject.Properties["code"] -and -not [string]::IsNullOrWhiteSpace([string]$r.code)) {
                    $lifecycleReasonCodes += [string]$r.code
                }
            }
        }
    }
}

$sample = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-perception-workspace-execution-sample-v1"
    type = "tod_perception_workspace_execution_sample"
    policy = [pscustomobject]@{
        path = $PolicyPath
        version = [string]$policy.version
        reason_codes = @($policy.reason_codes)
    }
    bounded_execution_flow = [pscustomobject]@{
        source_domain = $sourceDomain
        source_context = $sourceContext
        trace_id = $traceId
        execution_id = $executionId
        request = if ($null -ne $sampleLoopObj -and $sampleLoopObj.steps -and @($sampleLoopObj.steps).Count -gt 0) { @($sampleLoopObj.steps | Select-Object -First 1)[0] } else { $null }
        lifecycle = $handoffDoc.lifecycle
        lifecycle_reason_codes = @($lifecycleReasonCodes | Select-Object -Unique)
        summary_pointer = $pointerDoc
        summary_entry = if ($summaryEntry.Count -gt 0) { $summaryEntry[0] } else { $handoffDoc.execution_summary }
        handoff = $handoffDoc.handoff
    }
    boundary_assertion = [pscustomobject]@{
        tod_scope = "execution_runtime_only"
        mim_scope = "perception_normalization_memory_spatial_meaning_planning_governance"
        policy_enforced = $true
    }
}

$outDir = Split-Path -Parent $outAbs
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$sample | ConvertTo-Json -Depth 30 | Set-Content -Path $outAbs
$sample | ConvertTo-Json -Depth 30 | Write-Output
