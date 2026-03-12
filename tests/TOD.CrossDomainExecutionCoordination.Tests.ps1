Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$policyPath = Join-Path $repoRoot "tod/templates/bus/tod_cross_domain_execution_policy.json"
$sampleScriptPath = Join-Path $repoRoot "scripts/Invoke-TODCrossDomainExecutionCoordinationSample.ps1"
$sampleArtifactPath = Join-Path $repoRoot "shared_state/bus_cross_domain_execution_coordination_sample.json"

Describe "TOD Cross-Domain Execution Coordination" {
    It "policy artifact exists with required reason codes" {
        (Test-Path -Path $policyPath) | Should Be $true
        $policy = Get-Content -Path $policyPath -Raw | ConvertFrom-Json

        [string]$policy.schema_name | Should Be "tod_cross_domain_execution_policy_v1"
        [string]$policy.default_decision_for_unknown_domain | Should Be "ignore"
        @($policy.reason_codes) -contains "domain_policy_allowed" | Should Be $true
        @($policy.reason_codes) -contains "domain_policy_blocked" | Should Be $true
        @($policy.reason_codes) -contains "domain_policy_deferred" | Should Be $true
        @($policy.reason_codes) -contains "domain_policy_dry_run_only" | Should Be $true
        @($policy.reason_codes) -contains "request_unsupported_domain_ignored" | Should Be $true
    }

    It "bounded multi-domain sample includes domain-tagged handoff" {
        (Test-Path -Path $sampleScriptPath) | Should Be $true
        $null = & $sampleScriptPath -RunSampleLoop

        (Test-Path -Path $sampleArtifactPath) | Should Be $true
        $sample = Get-Content -Path $sampleArtifactPath -Raw | ConvertFrom-Json

        [string]$sample.type | Should Be "tod_cross_domain_execution_coordination_sample"
        [string]$sample.bounded_execution_flow.source_domain | Should Be "mim"
        ($null -ne $sample.bounded_execution_flow.request) | Should Be $true
        [string]$sample.bounded_execution_flow.request.source_domain | Should Be "mim"
        ($null -ne $sample.bounded_execution_flow.summary_entry) | Should Be $true
        [string]$sample.bounded_execution_flow.summary_entry.source_domain | Should Be "mim"
        [bool]$sample.boundary_assertion.policy_enforced | Should Be $true
    }
}
