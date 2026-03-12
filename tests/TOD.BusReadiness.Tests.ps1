Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$schemaPath = Join-Path $repoRoot "tod/templates/bus/tod_execution_event_envelope.schema.json"
$samplesPath = Join-Path $repoRoot "tod/templates/bus/tod_execution_event_samples.json"
$summaryContractPath = Join-Path $repoRoot "tod/templates/bus/tod_bus_execution_summary_handoff.schema.json"
$handshakeContractPath = Join-Path $repoRoot "tod/templates/bus/tod_unified_state_bus_handshake.contract.json"
$docPath = Join-Path $repoRoot "docs/tod-unified-state-bus-execution-events-v1.md"

Describe "TOD Bus Readiness Artifacts" {
    It "contains required contract artifacts" {
        (Test-Path -Path $schemaPath) | Should Be $true
        (Test-Path -Path $samplesPath) | Should Be $true
        (Test-Path -Path $summaryContractPath) | Should Be $true
        (Test-Path -Path $handshakeContractPath) | Should Be $true
        (Test-Path -Path $docPath) | Should Be $true
    }

    It "samples satisfy required envelope fields" {
        $schema = Get-Content -Path $schemaPath -Raw | ConvertFrom-Json
        $samples = Get-Content -Path $samplesPath -Raw | ConvertFrom-Json

        @($samples).Count | Should Be 6

        foreach ($evt in @($samples)) {
            foreach ($field in @($schema.required_fields)) {
                (($evt.PSObject.Properties.Name) -contains [string]$field) | Should Be $true
            }
        }
    }

    It "samples use allowed event types and producer boundary" {
        $schema = Get-Content -Path $schemaPath -Raw | ConvertFrom-Json
        $samples = Get-Content -Path $samplesPath -Raw | ConvertFrom-Json

        foreach ($evt in @($samples)) {
            (@($schema.event_types) -contains [string]$evt.event_type) | Should Be $true
            [string]$evt.producer.system | Should Be "TOD"
            [string]$evt.producer.role | Should Be "execution_runtime"
        }
    }

    It "samples satisfy correlation and reason models" {
        $schema = Get-Content -Path $schemaPath -Raw | ConvertFrom-Json
        $samples = Get-Content -Path $samplesPath -Raw | ConvertFrom-Json

        foreach ($evt in @($samples)) {
            foreach ($field in @($schema.correlation_model.required_fields)) {
                (($evt.correlation.PSObject.Properties.Name) -contains [string]$field) | Should Be $true
            }

            @($evt.reasons).Count | Should BeGreaterThan 0
            foreach ($reason in @($evt.reasons)) {
                foreach ($field in @($schema.reason_model.required_fields)) {
                    (($reason.PSObject.Properties.Name) -contains [string]$field) | Should Be $true
                }

                (@($schema.severity_values) -contains [string]$reason.severity) | Should Be $true
                (@($schema.reason_categories) -contains [string]$reason.category) | Should Be $true
            }
        }
    }
}
