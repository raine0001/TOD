param(
    [switch]$RunSampleLoop,
    [string]$SampleLoopScriptPath = "scripts/Invoke-TODBusAdapterSampleLoop.ps1",
    [string]$PointerPath = "shared_state/bus_execution_summaries.index.json",
    [string]$ContractPath = "tod/templates/bus/tod_bus_execution_summary_handoff.schema.json",
    [string]$OutputPath = "shared_state/mim_execution_summary_consumption_validation.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Test-HasProperties {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string[]]$PropertyNames
    )

    foreach ($name in $PropertyNames) {
        if (-not $Object.PSObject.Properties[$name]) {
            return $false
        }
    }
    return $true
}

if ($RunSampleLoop) {
    $sampleLoopAbs = Get-LocalPath -PathValue $SampleLoopScriptPath
    if (-not (Test-Path -Path $sampleLoopAbs)) {
        throw "Sample loop script not found: $sampleLoopAbs"
    }
    $null = & $sampleLoopAbs
}

$pointerAbs = Get-LocalPath -PathValue $PointerPath
$contractAbs = Get-LocalPath -PathValue $ContractPath
$outputAbs = Get-LocalPath -PathValue $OutputPath

if (-not (Test-Path -Path $pointerAbs)) {
    throw "Execution summary pointer not found: $pointerAbs"
}
if (-not (Test-Path -Path $contractAbs)) {
    throw "Execution summary handoff contract not found: $contractAbs"
}

$pointerDoc = Get-Content -Path $pointerAbs -Raw | ConvertFrom-Json
$contractDoc = Get-Content -Path $contractAbs -Raw | ConvertFrom-Json

$pointerRequired = @("generated_at", "summary_version", "source", "type", "latest_summary_path", "contract_path", "ordering_notes", "retention_notes")
$pointerAccepted = Test-HasProperties -Object $pointerDoc -PropertyNames $pointerRequired

$summaryPath = Get-LocalPath -PathValue ([string]$pointerDoc.latest_summary_path)
if (-not (Test-Path -Path $summaryPath)) {
    throw "Summary path from pointer not found: $summaryPath"
}
$summaryDoc = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json

$metadataAccepted = $true
if (-not (Test-HasProperties -Object $summaryDoc -PropertyNames @($contractDoc.required_metadata_fields))) {
    $metadataAccepted = $false
}
if ([string]$summaryDoc.summary_version -ne [string]$contractDoc.summary_version) {
    $metadataAccepted = $false
}
if ([string]$summaryDoc.type -ne [string]$contractDoc.type) {
    $metadataAccepted = $false
}

$entryAcceptance = @()
foreach ($entry in @($summaryDoc.summaries)) {
    $accepted = Test-HasProperties -Object $entry -PropertyNames @($contractDoc.required_summary_fields)
    $entryAcceptance += [pscustomobject]@{
        trace_id = [string]$entry.trace_id
        execution_id = [string]$entry.execution_id
        accepted = [bool]$accepted
    }
}

$allEntriesAccepted = [bool](@($entryAcceptance | Where-Object { -not $_.accepted }).Count -eq 0)

$signalCounts = [ordered]@{
    critical = 0
    warning = 0
    elevated = 0
    stable = 0
}
foreach ($entry in @($summaryDoc.summaries)) {
    $signal = [string]$entry.reliability_signal
    if ($signalCounts.Contains($signal)) {
        $signalCounts[$signal] = [int]$signalCounts[$signal] + 1
    }
}

$highAttention = @(
    @($summaryDoc.summaries) |
    Where-Object { [string]$_.recommended_attention -ne "none" } |
    ForEach-Object {
        [pscustomobject]@{
            trace_id = [string]$_.trace_id
            execution_id = [string]$_.execution_id
            reliability_signal = [string]$_.reliability_signal
            recommended_attention = [string]$_.recommended_attention
            final_outcome = [string]$_.final_outcome
        }
    }
)

$interpretation = [pscustomobject]@{
    source = "mim-summary-consumer-v1"
    ready_for_memory_update = [bool]($pointerAccepted -and $metadataAccepted -and $allEntriesAccepted)
    reliability_overview = [pscustomobject]@{
        summary_count = [int]@($summaryDoc.summaries).Count
        by_signal = [pscustomobject]$signalCounts
        high_attention_count = [int]@($highAttention).Count
    }
    high_attention = $highAttention
    update_payload = [pscustomobject]@{
        memory_key = "mim.tod.execution_reliability.latest"
        summary_version = [string]$summaryDoc.summary_version
        generated_at = [string]$summaryDoc.generated_at
        discovery_pointer_path = [string]$PointerPath
        latest_summary_path = [string]$pointerDoc.latest_summary_path
        contract_path = [string]$pointerDoc.contract_path
    }
}

$result = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-mim-execution-summary-consumption-validation-v1"
    mode = "simulated_mim_summary_consumer"
    pointer_read = [pscustomobject]@{
        path = [string]$PointerPath
        accepted = [bool]$pointerAccepted
        type = if ($pointerDoc.PSObject.Properties["type"]) { [string]$pointerDoc.type } else { "" }
    }
    summary_read = [pscustomobject]@{
        path = [string]$pointerDoc.latest_summary_path
        accepted = [bool](Test-Path -Path $summaryPath)
        summary_count = [int]@($summaryDoc.summaries).Count
    }
    metadata_accepted = [bool]$metadataAccepted
    summary_entries_accepted = [pscustomobject]@{
        all = [bool]$allEntriesAccepted
        entries = $entryAcceptance
    }
    mim_interpretation_payload = $interpretation
}

$outDir = Split-Path -Parent $outputAbs
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$result | ConvertTo-Json -Depth 20 | Set-Content -Path $outputAbs
$result | ConvertTo-Json -Depth 20 | Write-Output
