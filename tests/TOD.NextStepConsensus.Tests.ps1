Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$newStepsScript = Join-Path $repoRoot 'scripts/New-TODCodexNextSteps.ps1'
$resolveConsensusScript = Join-Path $repoRoot 'scripts/Resolve-TODNextStepConsensus.ps1'
$policyScript = Join-Path $repoRoot 'scripts/Invoke-TODNextStepPolicy.ps1'

function New-TestArea {
    $id = [guid]::NewGuid().ToString('N')
    $base = Join-Path $repoRoot ("tod/out/tests/next-step-consensus-" + $id)
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    return $base
}

Describe 'TOD codex next-step artifacts' {
    It 'generates structured findings from recommendation fallback' {
        $base = New-TestArea
        $resultPath = Join-Path $base 'result.json'
        $outputPath = Join-Path $base 'tod_codex_next_steps.latest.json'

        [pscustomobject]@{
            task_id = '3422'
            summary = 'Completed bounded listener cleanup.'
            files_changed = @('scripts/Start-TODMimPacketListener.ps1')
            tests_run = @('listener smoke')
            test_results = @('pass')
            failures = @()
            recommendations = @('Run canonical-only validation pass', 'Retire remaining live aliases')
            needs_escalation = $false
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $resultPath

        $payload = (& $newStepsScript -TaskId '3422' -ObjectiveId '97' -ResultJsonPath $resultPath -ReviewDecision 'pass' -LoopDecision 'continue' -OutputPath $outputPath) | ConvertFrom-Json
        [bool]$payload.ok | Should Be $true
        [int]$payload.finding_count | Should Be 2
        (Test-Path -Path $outputPath) | Should Be $true

        $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json
        [string]$artifact.contract_version | Should Be 'tod-codex-next-steps-v1'
        [string]$artifact.findings[0].action_type | Should Be 'validate'
        [bool]$artifact.findings[0].needs_cross_system_consensus | Should Be $true
    }

    It 'resolves consensus with explicit MIM positions and prefers validation before dependent cleanup' {
        $base = New-TestArea
        $findingsPath = Join-Path $base 'tod_codex_next_steps.latest.json'
        $mimPath = Join-Path $base 'mim_positions.json'
        $consensusPath = Join-Path $base 'NEXT_STEP_CONSENSUS.latest.json'

        [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'test'
            contract_version = 'tod-codex-next-steps-v1'
            run_id = 'test-run-1'
            workspace = 'TOD'
            objective_id = '97'
            task_id = '3422'
            summary = 'Cleanup finished.'
            findings = @(
                [pscustomobject]@{
                    finding_id = '3422-finding-001'
                    type = 'validation_candidate'
                    description = 'Run canonical-only validation pass'
                    owner_workspace = 'TOD'
                    action_type = 'validate'
                    needs_remote_input = $true
                    needs_cross_system_consensus = $true
                    approval_required = $false
                    confidence = 0.84
                    risk = 'low'
                    blocking_dependencies = @()
                    recommended_executor = 'tod.local'
                    source = 'test'
                },
                [pscustomobject]@{
                    finding_id = '3422-finding-002'
                    type = 'cleanup_candidate'
                    description = 'Retire remaining live aliases'
                    owner_workspace = 'TOD'
                    action_type = 'cleanup'
                    needs_remote_input = $true
                    needs_cross_system_consensus = $true
                    approval_required = $false
                    confidence = 0.8
                    risk = 'medium'
                    blocking_dependencies = @('3422-finding-001')
                    recommended_executor = 'tod.local'
                    source = 'test'
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $findingsPath

        [pscustomobject]@{
            source = 'mim_fixture'
            summary = 'MIM sees no local blocker.'
            finding_positions = @(
                [pscustomobject]@{ finding_id = '3422-finding-001'; decision = 'approve'; reason = 'Low-risk validation.'; confidence = 0.88; local_blockers = @() },
                [pscustomobject]@{ finding_id = '3422-finding-002'; decision = 'approve'; reason = 'Cleanup can proceed after validation.'; confidence = 0.79; local_blockers = @() }
            )
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $mimPath

        $payload = (& $resolveConsensusScript -FindingsPath $findingsPath -MimPositionJsonPath $mimPath -OutputPath $consensusPath) | ConvertFrom-Json
        [bool]$payload.ok | Should Be $true
        [string]$payload.status | Should Be 'consensus_ready'

        $artifact = Get-Content -Path $consensusPath -Raw | ConvertFrom-Json
        [string]$artifact.consensus.selected_finding_id | Should Be '3422-finding-001'
        [string]$artifact.consensus.execution_policy.class | Should Be 'auto_execute'
        [bool]$artifact.consensus.execution_policy.applied | Should Be $false
        [string]$artifact.findings[1].consensus_status | Should Be 'approved'
    }

    It 'projects phase-one policy without auto-applying the selected next step' {
        $base = New-TestArea
        $consensusPath = Join-Path $base 'NEXT_STEP_CONSENSUS.latest.json'
        $policyPath = Join-Path $base 'NEXT_STEP_POLICY.latest.json'

        [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'test'
            contract_version = 'tod-next-step-consensus-v1'
            status = 'consensus_ready'
            consensus = [pscustomobject]@{
                selected_finding_id = 'f-1'
                action = 'Run canonical-only validation pass'
                execution_policy = [pscustomobject]@{
                    class = 'auto_execute'
                    applied = $false
                    applied_reason = 'phase1_recommendation_only'
                }
            }
            findings = @(
                [pscustomobject]@{
                    finding = [pscustomobject]@{ finding_id = 'f-1'; description = 'Run canonical-only validation pass' }
                }
            )
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $consensusPath

        $payload = (& $policyScript -ConsensusPath $consensusPath -OutputPath $policyPath) | ConvertFrom-Json
        [bool]$payload.ok | Should Be $true
        (Test-Path -Path $policyPath) | Should Be $true

        $policy = Get-Content -Path $policyPath -Raw | ConvertFrom-Json
        [string]$policy.status | Should Be 'consensus_ready'
        [bool]$policy.applied | Should Be $false
        [string]$policy.execution_policy.class | Should Be 'auto_execute'
        [string]$policy.applied_reason | Should Be 'phase1_recommendation_only'
    }

    It 'allows TOD to select the next step locally when parity is green' {
        $base = New-TestArea
        $findingsPath = Join-Path $base 'tod_codex_next_steps.latest.json'
        $parityPath = Join-Path $base 'tod-mim-execution-parity.latest.json'
        $consensusPath = Join-Path $base 'NEXT_STEP_CONSENSUS.latest.json'

        [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'test'
            contract_version = 'tod-codex-next-steps-v1'
            run_id = 'test-run-parity-green'
            workspace = 'TOD'
            objective_id = '99'
            task_id = 'objective-99-next-step'
            summary = 'Parity-green local selection path.'
            findings = @(
                [pscustomobject]@{
                    finding_id = '99-finding-001'
                    type = 'validation_candidate'
                    description = 'Proceed with bounded compound execution slice'
                    owner_workspace = 'TOD'
                    action_type = 'validate'
                    needs_remote_input = $true
                    needs_cross_system_consensus = $true
                    approval_required = $false
                    confidence = 0.91
                    risk = 'low'
                    blocking_dependencies = @()
                    recommended_executor = 'tod.local'
                    source = 'test'
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $findingsPath

        [pscustomobject]@{
            compatible = $true
            mismatch_count = 0
            warning_count = 0
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $parityPath

        $payload = (& $resolveConsensusScript -FindingsPath $findingsPath -ParityArtifactPath $parityPath -OutputPath $consensusPath -WaitSeconds 0 -PollMilliseconds 10) | ConvertFrom-Json
        [bool]$payload.ok | Should Be $true
        [string]$payload.status | Should Be 'consensus_ready'

        $artifact = Get-Content -Path $consensusPath -Raw | ConvertFrom-Json
        [string]$artifact.mim_position.decision | Should Be 'not_required'
        [string]$artifact.mim_position.source | Should Be 'tod_parity_green_local_authority'
        [string]$artifact.consensus.selected_finding_id | Should Be '99-finding-001'
    }

    It 'sends an explicit reminder on the open session when MIM does not answer in time' {
        $base = New-TestArea
        $findingsPath = Join-Path $base 'tod_codex_next_steps.latest.json'
        $dialogDir = Join-Path $base 'dialog'
        $consensusPath = Join-Path $base 'NEXT_STEP_CONSENSUS.latest.json'
        $parityPath = Join-Path $base 'missing-parity.json'

        [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'test'
            contract_version = 'tod-codex-next-steps-v1'
            run_id = 'test-run-timeout'
            workspace = 'TOD'
            objective_id = '98A'
            task_id = 'objective-98a-mim-next-step-adjudication'
            summary = 'Consensus request waiting on MIM.'
            findings = @(
                [pscustomobject]@{
                    finding_id = '98a-finding-001'
                    type = 'validation_candidate'
                    description = 'Check shared-state bridge health'
                    owner_workspace = 'TOD'
                    action_type = 'validate'
                    needs_remote_input = $true
                    needs_cross_system_consensus = $true
                    approval_required = $false
                    confidence = 0.86
                    risk = 'low'
                    blocking_dependencies = @()
                    recommended_executor = 'tod.local'
                    source = 'test'
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $findingsPath

        $payload = (& $resolveConsensusScript -FindingsPath $findingsPath -DialogDir $dialogDir -ParityArtifactPath $parityPath -OutputPath $consensusPath -WaitSeconds 0 -PollMilliseconds 10) | ConvertFrom-Json
        [bool]$payload.ok | Should Be $true
        [string]$payload.status | Should Be 'pending_mim'

        $sessionId = 'next-step-objective-98a-mim-next-step-adjudication-test-run-timeout'
        $sessionPath = Join-Path $dialogDir ('MIM_TOD_DIALOG.session-' + $sessionId + '.jsonl')
        (Test-Path -Path $sessionPath) | Should Be $true

        $messages = @(Get-Content -Path $sessionPath | ForEach-Object { $_ | ConvertFrom-Json })
        @($messages).Count | Should Be 2
        [string]$messages[0].message_type | Should Be 'handoff_request'
        [string]$messages[1].message_type | Should Be 'status_request'
        [string]$messages[1].intent | Should Be 'next_step_consensus_reminder'

        $artifact = Get-Content -Path $consensusPath -Raw | ConvertFrom-Json
        [string]$artifact.mim_position.source | Should Be 'dialog_timeout_reminder_sent'
        [bool]$artifact.mim_position.reminder.sent | Should Be $true
    }

    It 'reuses an existing open session and still sends a reminder instead of failing resend' {
        $base = New-TestArea
        $findingsPath = Join-Path $base 'tod_codex_next_steps.latest.json'
        $dialogDir = Join-Path $base 'dialog'
        $consensusPath = Join-Path $base 'NEXT_STEP_CONSENSUS.latest.json'
        $parityPath = Join-Path $base 'missing-parity.json'

        [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'test'
            contract_version = 'tod-codex-next-steps-v1'
            run_id = 'test-run-retry'
            workspace = 'TOD'
            objective_id = '98A'
            task_id = 'objective-98a-mim-next-step-adjudication'
            summary = 'Consensus request retry path.'
            findings = @(
                [pscustomobject]@{
                    finding_id = '98a-retry-finding-001'
                    type = 'validation_candidate'
                    description = 'Refresh shared bridge status'
                    owner_workspace = 'TOD'
                    action_type = 'refresh'
                    needs_remote_input = $true
                    needs_cross_system_consensus = $true
                    approval_required = $false
                    confidence = 0.82
                    risk = 'low'
                    blocking_dependencies = @()
                    recommended_executor = 'tod.local'
                    source = 'test'
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $findingsPath

        $null = (& $resolveConsensusScript -FindingsPath $findingsPath -DialogDir $dialogDir -ParityArtifactPath $parityPath -OutputPath $consensusPath -WaitSeconds 0 -PollMilliseconds 10) | ConvertFrom-Json
        $retryPayload = (& $resolveConsensusScript -FindingsPath $findingsPath -DialogDir $dialogDir -ParityArtifactPath $parityPath -OutputPath $consensusPath -WaitSeconds 0 -PollMilliseconds 10) | ConvertFrom-Json
        [bool]$retryPayload.ok | Should Be $true
        [string]$retryPayload.status | Should Be 'pending_mim'

        $sessionId = 'next-step-objective-98a-mim-next-step-adjudication-test-run-retry'
        $sessionPath = Join-Path $dialogDir ('MIM_TOD_DIALOG.session-' + $sessionId + '.jsonl')
        $messages = @(Get-Content -Path $sessionPath | ForEach-Object { $_ | ConvertFrom-Json })

        [string]$messages[2].message_type | Should Be 'status_request'
        [string]$messages[2].intent | Should Be 'next_step_consensus_reminder'

        $artifact = Get-Content -Path $consensusPath -Raw | ConvertFrom-Json
        [string]$artifact.mim_position.source | Should Be 'dialog_timeout_reminder_sent'
    }
}