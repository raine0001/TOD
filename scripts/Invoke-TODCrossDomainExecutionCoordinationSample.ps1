param(
    [switch]$RunSampleLoop,
    [string]$SampleLoopScriptPath = "scripts/Invoke-TODBusAdapterSampleLoop.ps1",
    [string]$PolicyPath = "tod/templates/bus/tod_cross_domain_execution_policy.json",
    [string]$SummaryPath = "shared_state/bus_execution_summaries.json",
    [string]$SummaryPointerPath = "shared_state/bus_execution_summaries.index.json",
    [string]$HandoffSamplePath = "shared_state/bus_execution_handoff_integration_sample.json",
    [string]$OutputPath = "shared_state/bus_cross_domain_execution_coordination_sample.json"
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
    $sampleLoopRaw = & $sampleLoopAbs -SourceDomain "mim"
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
$summaryEntry = @($summaryDoc.summaries | Where-Object {
        [string]$_.trace_id -eq $traceId -and [string]$_.execution_id -eq $executionId
    } | Select-Object -First 1)

$sample = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-cross-domain-execution-coordination-sample-v1"
    type = "tod_cross_domain_execution_coordination_sample"
    policy = [pscustomobject]@{
        path = $PolicyPath
        version = [string]$policy.version
        default_unknown_domain_decision = [string]$policy.default_decision_for_unknown_domain
        reason_codes = @($policy.reason_codes)
    }
    domains = [pscustomobject]@{
        allowed = @($policy.domains | Where-Object { @($_.allowed_actions).Count -gt 0 } | Select-Object -ExpandProperty domain)
        blocked = @($policy.domains | Where-Object { @($_.blocked_actions).Count -gt 0 } | Select-Object -ExpandProperty domain)
        dry_run_only = @($policy.domains | Where-Object { @($_.dry_run_only_actions).Count -gt 0 } | Select-Object -ExpandProperty domain)
    }
    bounded_execution_flow = [pscustomobject]@{
        source_domain = $sourceDomain
        trace_id = $traceId
        execution_id = $executionId
        request = if ($null -ne $sampleLoopObj) { @($sampleLoopObj.steps | Select-Object -First 1)[0] } else { $null }
        lifecycle = $handoffDoc.lifecycle
        summary_pointer = $pointerDoc
        summary_entry = if ($summaryEntry.Count -gt 0) { $summaryEntry[0] } else { $handoffDoc.execution_summary }
        handoff = $handoffDoc.handoff
    }
    boundary_assertion = [pscustomobject]@{
        tod_scope = "execution_runtime_only"
        mim_scope = "cognition_planning_meaning_governance"
        policy_enforced = $true
    }
}

$outDir = Split-Path -Parent $outAbs
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$sample | ConvertTo-Json -Depth 30 | Set-Content -Path $outAbs
$sample | ConvertTo-Json -Depth 30 | Write-Output
