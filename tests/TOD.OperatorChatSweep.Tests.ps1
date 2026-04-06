Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sweepScript = Join-Path $repoRoot 'scripts/Invoke-TODOperatorChatSweep.ps1'
$baseUrl = 'http://localhost:8844'
$executionReadinessArtifactPath = Join-Path $repoRoot 'shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json'

function Test-TodUiReachable {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/project-status" -TimeoutSec 5
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Get-TodExecutionReadinessArtifactBackup {
    if (-not (Test-Path -Path $executionReadinessArtifactPath -PathType Leaf)) {
        return $null
    }

    return [System.IO.File]::ReadAllText($executionReadinessArtifactPath)
}

function Restore-TodExecutionReadinessArtifact {
    param([AllowNull()][string]$Content)

    if ($null -eq $Content) {
        if (Test-Path -Path $executionReadinessArtifactPath -PathType Leaf) {
            Remove-Item -Path $executionReadinessArtifactPath -Force
        }
        return
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($executionReadinessArtifactPath, $Content, $utf8NoBom)
}

function Set-TodExecutionReadinessArtifactScenario {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('valid', 'stale')][string]$Scenario
    )

    $artifact = Get-Content -Path $executionReadinessArtifactPath -Raw | ConvertFrom-Json
    switch ($Scenario) {
        'valid' {
            $generatedAt = (Get-Date).ToUniversalTime().ToString('o')
            $artifact.generated_at = $generatedAt
            if ($artifact.PSObject.Properties['artifact_generated_at']) {
                $artifact.artifact_generated_at = $generatedAt
            }
            if (-not $artifact.PSObject.Properties['summary'] -or $null -eq $artifact.summary) {
                $artifact | Add-Member -NotePropertyName summary -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $artifact.summary.passed_all = $true
            $artifact.summary.exit_code = 0
        }
        'stale' {
            $generatedAt = (Get-Date).ToUniversalTime().AddMinutes(-45).ToString('o')
            $artifact.generated_at = $generatedAt
            if ($artifact.PSObject.Properties['artifact_generated_at']) {
                $artifact.artifact_generated_at = $generatedAt
            }
            if (-not $artifact.PSObject.Properties['summary'] -or $null -eq $artifact.summary) {
                $artifact | Add-Member -NotePropertyName summary -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $artifact.summary.passed_all = $true
            $artifact.summary.exit_code = 0
        }
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($executionReadinessArtifactPath, ($artifact | ConvertTo-Json -Depth 20), $utf8NoBom)
}

function Invoke-TodSweepSnapshot {
    $fixtureId = [guid]::NewGuid().ToString('N')
    $artifactDir = Join-Path $repoRoot ("tod/out/tests/operator-chat-sweep-ambient-" + $fixtureId)
    $rawArtifactPath = Join-Path $artifactDir 'raw.json'
    $summaryArtifactPath = Join-Path $artifactDir 'ineffective-summary.json'

    $null = & $sweepScript -Port 8844 -ValidationHarness 'multi_objective_compare' -RawArtifactPath $rawArtifactPath -IneffectiveSummaryPath $summaryArtifactPath

    $rawPayload = Get-Content -Path $rawArtifactPath -Raw | ConvertFrom-Json
    $summaryPayload = Get-Content -Path $summaryArtifactPath -Raw | ConvertFrom-Json

    return [pscustomobject]@{
        raw = [pscustomobject]@{
            stable_contract = $rawPayload.stable_contract
            commitment = $rawPayload.governed_actions.commitment
            trust_chain = $rawPayload.governed_actions.trust_chain
        }
        summary = $summaryPayload
    }
}

function Convert-ToNormalizedTodSweepSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    return [pscustomobject]@{
        raw = [pscustomobject]@{
            stable_contract = [pscustomobject]@{
                build_ok = [bool]$Snapshot.raw.stable_contract.build_ok
                operator_chat_queries_ok = [bool]$Snapshot.raw.stable_contract.operator_chat_queries_ok
                governed_actions_ok = [bool]$Snapshot.raw.stable_contract.governed_actions_ok
                audit_ok = [bool]$Snapshot.raw.stable_contract.audit_ok
                reasoning_ok = [bool]$Snapshot.raw.stable_contract.reasoning_ok
                commitments_ok = [bool]$Snapshot.raw.stable_contract.commitments_ok
                ineffective_smoke_ok = [bool]$Snapshot.raw.stable_contract.ineffective_smoke_ok
                feedback_ok = [bool]$Snapshot.raw.stable_contract.feedback_ok
                bridge_diagnostics_ok = [bool]$Snapshot.raw.stable_contract.bridge_diagnostics_ok
                bridge_explain_ok = [bool]$Snapshot.raw.stable_contract.bridge_explain_ok
            }
            commitment = [pscustomobject]@{
                ok = [bool]$Snapshot.raw.commitment.ok
                state = [string]$Snapshot.raw.commitment.state
                timeboxed_ok = [bool]$Snapshot.raw.commitment.timeboxed_ok
                timeboxed_state = [string]$Snapshot.raw.commitment.timeboxed_state
                timeboxed_has_expiry = [bool]$Snapshot.raw.commitment.timeboxed_has_expiry
                evidence_bound_ok = [bool]$Snapshot.raw.commitment.evidence_bound_ok
                evidence_bound_state = [string]$Snapshot.raw.commitment.evidence_bound_state
                evidence_bound_release = [string]$Snapshot.raw.commitment.evidence_bound_release
                evidence_bound_snapshot = [bool]$Snapshot.raw.commitment.evidence_bound_snapshot
                satisfied_ok = [bool]$Snapshot.raw.commitment.satisfied_ok
                satisfied_state = [string]$Snapshot.raw.commitment.satisfied_state
                satisfied_lifecycle = [string]$Snapshot.raw.commitment.satisfied_lifecycle
                abandoned_ok = [bool]$Snapshot.raw.commitment.abandoned_ok
                abandoned_state = [string]$Snapshot.raw.commitment.abandoned_state
                abandoned_lifecycle = [string]$Snapshot.raw.commitment.abandoned_lifecycle
                ineffective_cycle_one_preview_ok = [bool]$Snapshot.raw.commitment.ineffective_cycle_one_preview_ok
                ineffective_cycle_one_committed_ok = [bool]$Snapshot.raw.commitment.ineffective_cycle_one_committed_ok
                ineffective_cycle_one_abandoned_ok = [bool]$Snapshot.raw.commitment.ineffective_cycle_one_abandoned_ok
                ineffective_cycle_two_preview_ok = [bool]$Snapshot.raw.commitment.ineffective_cycle_two_preview_ok
                ineffective_cycle_two_committed_ok = [bool]$Snapshot.raw.commitment.ineffective_cycle_two_committed_ok
                ineffective_cycle_two_abandoned_ok = [bool]$Snapshot.raw.commitment.ineffective_cycle_two_abandoned_ok
                ineffective_probe_action = [string]$Snapshot.raw.commitment.ineffective_probe_action
                ineffective_projection_seen = [bool]$Snapshot.raw.commitment.ineffective_projection_seen
                ineffective_terminal_state = [string]$Snapshot.raw.commitment.ineffective_terminal_state
                ineffective_lifecycle_status = [string]$Snapshot.raw.commitment.ineffective_lifecycle_status
                ineffective_signal_seen = [bool]$Snapshot.raw.commitment.ineffective_signal_seen
                ineffective_followup_action = [string]$Snapshot.raw.commitment.ineffective_followup_action
                ineffective_followup_reason = [string]$Snapshot.raw.commitment.ineffective_followup_reason
                ineffective_followup_history_signal = [bool]$Snapshot.raw.commitment.ineffective_followup_history_signal
                list_ok = [bool]$Snapshot.raw.commitment.list_ok
                list_count = [int]$Snapshot.raw.commitment.list_count
                list_states = [string]$Snapshot.raw.commitment.list_states
                evidence_commitment_provenance_source = [string]$Snapshot.raw.commitment.evidence_commitment_provenance_source
                evidence_commitment_fitness_field = [bool]$Snapshot.raw.commitment.evidence_commitment_fitness_field
            }
            trust_chain = [pscustomobject]@{
                ok = [bool]$Snapshot.raw.trust_chain.ok
                chain_status = [string]$Snapshot.raw.trust_chain.chain_status
                evidence_count = [int]$Snapshot.raw.trust_chain.evidence_count
                commitment_count = [int]$Snapshot.raw.trust_chain.commitment_count
                evidence_delta_count = [int]$Snapshot.raw.trust_chain.evidence_delta_count
                evidence_commitment_ok = [bool]$Snapshot.raw.trust_chain.evidence_commitment_ok
                evidence_commitment_chain_status = [string]$Snapshot.raw.trust_chain.evidence_commitment_chain_status
                evidence_commitment_delta_field = [bool]$Snapshot.raw.trust_chain.evidence_commitment_delta_field
                evidence_commitment_comparison_applied = [bool]$Snapshot.raw.trust_chain.evidence_commitment_comparison_applied
                evidence_commitment_comparison_source = [string]$Snapshot.raw.trust_chain.evidence_commitment_comparison_source
                evidence_commitment_comparison_objective = [string]$Snapshot.raw.trust_chain.evidence_commitment_comparison_objective
                evidence_commitment_delta_positive = [bool]$Snapshot.raw.trust_chain.evidence_commitment_delta_positive
                evidence_commitment_snapshot_field = [bool]$Snapshot.raw.trust_chain.evidence_commitment_snapshot_field
                ineffective_commitment_ok = [bool]$Snapshot.raw.trust_chain.ineffective_commitment_ok
                ineffective_commitment_chain_status = [string]$Snapshot.raw.trust_chain.ineffective_commitment_chain_status
                ineffective_commitment_terminal_state = [string]$Snapshot.raw.trust_chain.ineffective_commitment_terminal_state
                ineffective_commitment_lifecycle_status = [string]$Snapshot.raw.trust_chain.ineffective_commitment_lifecycle_status
            }
        }
        summary = $Snapshot.summary
    }
}

Describe 'Operator chat sweep artifacts' {
    It 'writes raw and ineffective summary artifacts with stable ineffective smoke fields' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $fixtureId = [guid]::NewGuid().ToString('N')
        $artifactDir = Join-Path $repoRoot ("tod/out/tests/operator-chat-sweep-" + $fixtureId)
        $rawArtifactPath = Join-Path $artifactDir 'raw.json'
        $summaryArtifactPath = Join-Path $artifactDir 'ineffective-summary.json'

        $null = & $sweepScript -Port 8844 -ValidationHarness 'multi_objective_compare' -RawArtifactPath $rawArtifactPath -IneffectiveSummaryPath $summaryArtifactPath

        (Test-Path -Path $rawArtifactPath) | Should Be $true
        (Test-Path -Path $summaryArtifactPath) | Should Be $true

        $rawPayload = Get-Content -Path $rawArtifactPath -Raw | ConvertFrom-Json
        $summaryPayload = Get-Content -Path $summaryArtifactPath -Raw | ConvertFrom-Json

        $rawPayload.stable_contract | Should Not BeNullOrEmpty
        [bool]$rawPayload.stable_contract.ineffective_smoke_ok | Should Be $true
        [bool]($rawPayload.stable_contract.operator_chat_queries_ok -and $rawPayload.stable_contract.governed_actions_ok -and $rawPayload.stable_contract.audit_ok -and $rawPayload.stable_contract.reasoning_ok -and $rawPayload.stable_contract.commitments_ok) | Should Be $true
        [string]$rawPayload.governed_actions.commitment.ineffective_terminal_state | Should Be 'ineffective'
        [string]$rawPayload.governed_actions.commitment.ineffective_lifecycle_status | Should Be 'ineffective'
        [bool]$rawPayload.governed_actions.commitment.ineffective_signal_seen | Should Be $true
        [string]$rawPayload.governed_actions.commitment.ineffective_followup_action | Should Be 'refresh-governance-snapshot'
        [bool]$rawPayload.governed_actions.commitment.ineffective_followup_history_signal | Should Be $true
        [string]$rawPayload.governed_actions.trust_chain.ineffective_commitment_terminal_state | Should Be 'ineffective'

        [bool]$summaryPayload.ineffective_smoke_ok | Should Be $true
        [bool]$summaryPayload.stable_contract_ok | Should Be $true
        [string]$summaryPayload.ineffective_terminal_state | Should Be 'ineffective'
        [string]$summaryPayload.ineffective_lifecycle_status | Should Be 'ineffective'
        [bool]$summaryPayload.ineffective_signal_seen | Should Be $true
        [string]$summaryPayload.ineffective_followup_action | Should Be 'refresh-governance-snapshot'
        [bool]$summaryPayload.ineffective_followup_history_signal | Should Be $true
        [string]$summaryPayload.ineffective_commitment_terminal_state | Should Be 'ineffective'
    }

    It 'produces the same normalized sweep result under ambient valid and stale host readiness states' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        if (-not (Test-Path -Path $executionReadinessArtifactPath -PathType Leaf)) {
            return
        }

        $artifactBackup = Get-TodExecutionReadinessArtifactBackup
        try {
            Set-TodExecutionReadinessArtifactScenario -Scenario 'valid'
            $baseline = Convert-ToNormalizedTodSweepSnapshot -Snapshot (Invoke-TodSweepSnapshot)

            Set-TodExecutionReadinessArtifactScenario -Scenario 'stale'
            $stale = Convert-ToNormalizedTodSweepSnapshot -Snapshot (Invoke-TodSweepSnapshot)

            (($baseline.raw | ConvertTo-Json -Depth 20 -Compress)) | Should Be (($stale.raw | ConvertTo-Json -Depth 20 -Compress))
            (($baseline.summary | ConvertTo-Json -Depth 20 -Compress)) | Should Be (($stale.summary | ConvertTo-Json -Depth 20 -Compress))
        }
        finally {
            Restore-TodExecutionReadinessArtifact -Content $artifactBackup
        }
    }
}