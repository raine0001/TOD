Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sampleLoopScript = Join-Path $repoRoot "scripts/Invoke-TODBusAdapterSampleLoop.ps1"
$validatorScript = Join-Path $repoRoot "scripts/Invoke-TODMIMExecutionSummaryConsumptionValidation.ps1"

Describe "TOD MIM Execution Summary Consumption" {
    It "validates pointer and summary handoff consumption" {
        (Test-Path -Path $sampleLoopScript) | Should Be $true
        (Test-Path -Path $validatorScript) | Should Be $true

        $null = & $sampleLoopScript
        $raw = & $validatorScript
        $result = $raw | ConvertFrom-Json

        [string]$result.pointer_read.path | Should Be "shared_state/bus_execution_summaries.index.json"
        [bool]$result.pointer_read.accepted | Should Be $true
        [bool]$result.summary_read.accepted | Should Be $true
        [bool]$result.metadata_accepted | Should Be $true
        [bool]$result.summary_entries_accepted.all | Should Be $true
        [bool]$result.mim_interpretation_payload.ready_for_memory_update | Should Be $true
        [string]$result.mim_interpretation_payload.update_payload.memory_key | Should Be "mim.tod.execution_reliability.latest"
        [string]$result.mim_interpretation_payload.update_payload.discovery_pointer_path | Should Be "shared_state/bus_execution_summaries.index.json"
        [string]$result.mim_interpretation_payload.update_payload.latest_summary_path | Should Be "shared_state/bus_execution_summaries.json"
        [int]$result.summary_read.summary_count | Should BeGreaterThan 0
    }
}
