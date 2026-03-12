Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$handshakePath = Join-Path $repoRoot "tod/templates/bus/tod_unified_state_bus_handshake.contract.json"
$adapterSchemaPath = Join-Path $repoRoot "tod/templates/bus/tod_bus_adapter_event.schema.json"
$summaryContractPath = Join-Path $repoRoot "tod/templates/bus/tod_bus_execution_summary_handoff.schema.json"
$sampleScriptPath = Join-Path $repoRoot "scripts/Invoke-TODUnifiedStateBusHandshakeSample.ps1"
$sampleArtifactPath = Join-Path $repoRoot "shared_state/bus_unified_state_multidomain_integration_sample.json"

function Test-HandshakeCompatibility {
    param(
        [Parameter(Mandatory = $true)]$Handshake,
        [Parameter(Mandatory = $true)]$AdapterSchema,
        [Parameter(Mandatory = $true)]$SummaryContract
    )

    if ([string]$Handshake.source_domain -ne "tod") { return $false }
    if ([string]$Handshake.producer_metadata.system -ne "TOD") { return $false }
    if ([string]$Handshake.producer_metadata.role -ne "execution_runtime") { return $false }

    foreach ($evt in @($Handshake.supported_inbound_event_types)) {
        if (@($AdapterSchema.inbound_event_types) -notcontains [string]$evt) { return $false }
    }
    foreach ($evt in @($Handshake.supported_outbound_event_types)) {
        if (@($AdapterSchema.outbound_event_types) -notcontains [string]$evt) { return $false }
    }

    $requiredCorrelation = @("event_id", "trace_id", "execution_id")
    foreach ($f in $requiredCorrelation) {
        if (@($Handshake.correlation_requirements.required) -notcontains $f) { return $false }
    }

    if ([string]$Handshake.compatibility_expectations.compatible_summary_version -ne [string]$SummaryContract.summary_version) { return $false }
    return $true
}

Describe "TOD Unified State Bus Handshake" {
    It "handshake contract is present and compatible with adapter and summary contracts" {
        (Test-Path -Path $handshakePath) | Should Be $true
        (Test-Path -Path $adapterSchemaPath) | Should Be $true
        (Test-Path -Path $summaryContractPath) | Should Be $true

        $handshake = Get-Content -Path $handshakePath -Raw | ConvertFrom-Json
        $adapterSchema = Get-Content -Path $adapterSchemaPath -Raw | ConvertFrom-Json
        $summaryContract = Get-Content -Path $summaryContractPath -Raw | ConvertFrom-Json

        [bool](Test-HandshakeCompatibility -Handshake $handshake -AdapterSchema $adapterSchema -SummaryContract $summaryContract) | Should Be $true
        [string]$handshake.replay_duplicate_ordering_expectations.idempotency_key | Should Be "event_id"
        [string]$handshake.semantic_separation.transient_bus_semantics | Should Match "events.jsonl"
        [string]$handshake.semantic_separation.durable_shared_state_semantics | Should Match "shared_state"
    }

    It "incompatible handshake cases are rejected" {
        $adapterSchema = Get-Content -Path $adapterSchemaPath -Raw | ConvertFrom-Json
        $summaryContract = Get-Content -Path $summaryContractPath -Raw | ConvertFrom-Json
        $good = Get-Content -Path $handshakePath -Raw | ConvertFrom-Json

        $badDomain = ($good | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
        $badDomain.source_domain = "mim"
        [bool](Test-HandshakeCompatibility -Handshake $badDomain -AdapterSchema $adapterSchema -SummaryContract $summaryContract) | Should Be $false

        $badInbound = ($good | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
        $badInbound.supported_inbound_event_types = @($badInbound.supported_inbound_event_types) + @("planning.requested")
        [bool](Test-HandshakeCompatibility -Handshake $badInbound -AdapterSchema $adapterSchema -SummaryContract $summaryContract) | Should Be $false

        $badCorrelation = ($good | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
        $badCorrelation.correlation_requirements.required = @("event_id", "trace_id")
        [bool](Test-HandshakeCompatibility -Handshake $badCorrelation -AdapterSchema $adapterSchema -SummaryContract $summaryContract) | Should Be $false
    }

    It "multi-domain integration sample contains MIM request and TOD handoff" {
        (Test-Path -Path $sampleScriptPath) | Should Be $true
        $null = & $sampleScriptPath -RunSampleLoop

        (Test-Path -Path $sampleArtifactPath) | Should Be $true
        $sample = Get-Content -Path $sampleArtifactPath -Raw | ConvertFrom-Json

        [string]$sample.type | Should Be "tod_unified_state_bus_multidomain_integration_sample"
        [string]$sample.contract.source_domain | Should Be "tod"
        ($null -ne $sample.transient_bus.mim_issued_request) | Should Be $true
        [string]$sample.transient_bus.mim_issued_request.producer.system | Should Be "MIM"
        [string]$sample.transient_bus.mim_issued_request.event_type | Should Be "execution.requested"
        ($null -ne $sample.transient_bus.tod_result_handoff) | Should Be $true
        [string]$sample.durable_shared_state.summary_pointer.type | Should Be "bus_execution_summaries_pointer"
        ($null -ne $sample.durable_shared_state.summary_entry) | Should Be $true
        [bool]$sample.separation_assertion.boundary_ok | Should Be $true
    }
}
