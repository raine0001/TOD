Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$bridgeSmokeScript = Join-Path $repoRoot 'scripts/Invoke-TODMimBridgeSmoke.ps1'

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 12
    )

    $dir = Split-Path -Parent $PathValue
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function New-BridgeSmokeFixture {
    param(
        [string]$ExpectedObjective = 'objective-97',
        [string]$RequestObjective = 'objective-75',
        [string]$RequestTaskId = 'objective-75-task-3422',
        [string]$FormalProgramTaskId = '',
        [string]$RemoteBoundaryClassification = 'canonical_remote_surface',
        [string]$TaskAckStatus = 'accepted',
        [string]$HighWatermarkTaskId = '',
        [bool]$EmitResult = $true,
        [string]$LatestCompletedObjective = '',
        [string]$TriggerAckAcknowledges = '',
        [AllowNull()]$LocalSequence = '381549',
        [AllowNull()]$RemoteSequence = '381549',
        [string]$RemoteSha256 = '',
        [string]$ObjectiveAlignmentStatus = 'in_sync'
    )

    $base = Join-Path $repoRoot ('tod/out/tests/bridge-smoke-' + [guid]::NewGuid().ToString('N'))
    $listener = Join-Path $base 'listener'
    $integrationPath = Join-Path $base 'integration_status.json'
    $outputPath = Join-Path $base 'bridge_smoke.json'
    $remoteProbePath = Join-Path $base 'remote_probe.json'
    $remoteBoundaryPath = Join-Path $base 'remote_boundary.json'
    $now = (Get-Date).ToUniversalTime()

    $requestPath = Join-Path $listener 'MIM_TOD_TASK_REQUEST.latest.json'
    Write-JsonNoBom -PathValue $requestPath -Payload ([pscustomobject]@{
        generated_at = $now.AddSeconds(-30).ToString('o')
        task_id = $RequestTaskId
        objective_id = $RequestObjective
        sequence = $LocalSequence
    })
    $requestSha = (Get-FileHash -Path $requestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-JsonNoBom -PathValue (Join-Path $listener 'TOD_TO_MIM_TRIGGER_ACK.latest.json') -Payload ([pscustomobject]@{
        generated_at = $now.AddSeconds(-20).ToString('o')
        acknowledges = if ([string]::IsNullOrWhiteSpace($TriggerAckAcknowledges)) { $RequestTaskId } else { $TriggerAckAcknowledges }
        acknowledged_trigger_sequence = 11
    })
    Write-JsonNoBom -PathValue (Join-Path $listener 'TOD_MIM_TASK_ACK.latest.json') -Payload ([pscustomobject]@{
        generated_at = $now.AddSeconds(-12).ToString('o')
        request_id = $RequestTaskId
        task_id = $RequestTaskId
        status = $TaskAckStatus
        bridge_runtime = [pscustomobject]@{
            current_processing = [pscustomobject]@{
                task_id = if ([string]::IsNullOrWhiteSpace($HighWatermarkTaskId)) { $RequestTaskId } else { $HighWatermarkTaskId }
            }
        }
    })
    if ($EmitResult) {
        Write-JsonNoBom -PathValue (Join-Path $listener 'TOD_MIM_TASK_RESULT.latest.json') -Payload ([pscustomobject]@{
            generated_at = $now.AddSeconds(-10).ToString('o')
            task_id = $RequestTaskId
            status = 'completed'
            review_gate = [pscustomobject]@{ passed = $true }
        })
    }
    Write-JsonNoBom -PathValue (Join-Path $listener 'listener_state.json') -Payload ([pscustomobject]@{
        last_cycle_at = $now.AddSeconds(-5).ToString('o')
        high_watermark_request_id = if ([string]::IsNullOrWhiteSpace($HighWatermarkTaskId)) { $RequestTaskId } else { $HighWatermarkTaskId }
    })
    Write-JsonNoBom -PathValue $integrationPath -Payload ([pscustomobject]@{
        objective_alignment = [pscustomobject]@{
            status = $ObjectiveAlignmentStatus
            tod_current_objective = ($ExpectedObjective -replace '^objective-', '')
            mim_objective_active = ($ExpectedObjective -replace '^objective-', '')
        }
        mim_handshake = [pscustomobject]@{
            latest_completed_objective = if ([string]::IsNullOrWhiteSpace($LatestCompletedObjective)) { ($RequestObjective -replace '^objective-', '') } else { ($LatestCompletedObjective -replace '^objective-', '') }
            source_of_truth = [pscustomobject]@{
                formal_program_truth = [pscustomobject]@{
                    task_id = if ([string]::IsNullOrWhiteSpace($FormalProgramTaskId)) { '' } else { $FormalProgramTaskId }
                }
            }
        }
        tod_status_publish = [pscustomobject]@{
            status = 'uploaded'
            mim_mirror_status = 'mirrored'
            remote_access_status = 'full_access_granted'
            consumer_status = 'executed'
        }
    })
    Write-JsonNoBom -PathValue $remoteProbePath -Payload ([pscustomobject]@{
        available = $true
        hostname = 'raspberrypi'
        whoami = 'testpilot'
        absolute_path = '/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json'
        realpath = '/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json'
        inode = '649265'
        mtime = $now.AddSeconds(-30).ToString('o')
        size = 875
        sha256 = if ([string]::IsNullOrWhiteSpace($RemoteSha256)) { $requestSha } else { $RemoteSha256 }
        objective_id = $RequestObjective
        task_id = $RequestTaskId
        sequence = $RemoteSequence
    })
    Write-JsonNoBom -PathValue $remoteBoundaryPath -Payload ([pscustomobject]@{
        available = $true
        remote_boundary = [pscustomobject]@{
            classification = $RemoteBoundaryClassification
            recommendation = if ($RemoteBoundaryClassification -eq 'noncanonical_remote_surface') { 'repair_current_boundary' } else { 'keep_current_boundary' }
            reason = if ($RemoteBoundaryClassification -eq 'noncanonical_remote_surface') { 'remote_runtime_tree_has_no_visible_repo_checkout_or_active_publisher' } else { 'none' }
        }
    })

    return [pscustomobject]@{
        Base = $base
        Listener = $listener
        Integration = $integrationPath
        Output = $outputPath
        RemoteProbe = $remoteProbePath
        RemoteBoundary = $remoteBoundaryPath
    }
}

function Remove-TestFixturePath {
    param([string]$PathValue)

    if (-not [string]::IsNullOrWhiteSpace($PathValue) -and (Test-Path -Path $PathValue)) {
        Remove-Item -Path $PathValue -Recurse -Force
    }
}

Describe 'TOD bridge smoke' {
    It 'classifies stale remote canonical request as publication surface divergence' {
        $fixture = New-BridgeSmokeFixture -LatestCompletedObjective 'objective-74'
        try {
            try {
                & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary | Out-Null
            }
            catch {
            }

            $doc = Get-Content -Path $fixture.Output -Raw | ConvertFrom-Json
            [bool]$doc.passed | Should Be $false
            [string]$doc.classification | Should Be 'publication_surface_divergence'
            [string]$doc.failure_reason | Should Be 'publication_surface_divergence'
            (@($doc.failure_modes) -contains 'publication_surface_divergence') | Should Be $true
            (@($doc.failure_modes) -contains 'stale_remote_request_identity') | Should Be $true
            (@($doc.failure_modes) -contains 'listener_contract_stalled') | Should Be $false
            [string]$doc.canonical_request.expected_objective_id | Should Be 'objective-97'
            [string]$doc.canonical_request.remote_surface.objective_id | Should Be 'objective-75'
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'passes when remote canonical request matches expected objective and local listener state is healthy' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-75' -RequestObjective 'objective-75'
        try {
            $raw = & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.passed | Should Be $true
            [string]$doc.classification | Should Be 'pass'
            @($doc.failure_modes).Count | Should Be 0
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'passes when a live non-formal chat objective supersedes stale numeric objective alignment' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-3458' -RequestObjective 'wat-shuld-happen-befor-we-add-anothr-featre' -RequestTaskId 'wat-shuld-happen-befor-we-add-anothr-featre-mim-request-f140a49c-replan-1'
        try {
            $raw = & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.passed | Should Be $true
            [string]$doc.classification | Should Be 'pass'
            [string]$doc.canonical_request.expected_objective_id | Should Be 'wat-shuld-happen-befor-we-add-anothr-featre'
            [string]$doc.canonical_request.expected_task_id | Should Be 'wat-shuld-happen-befor-we-add-anothr-featre-mim-request-f140a49c-replan-1'
            @($doc.failure_modes).Count | Should Be 0
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'does not treat blank and null optional sequence metadata as canonical divergence' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-3458' -RequestObjective 'wat-shuld-happen-befor-we-add-anothr-featre' -RequestTaskId 'wat-shuld-happen-befor-we-add-anothr-featre-mim-request-f140a49c-replan-1' -LocalSequence '' -RemoteSequence $null
        try {
            $raw = & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.passed | Should Be $true
            [string]$doc.classification | Should Be 'pass'
            [bool]$doc.canonical_request.canonical_request_mismatch | Should Be $false
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'does not treat matching request identity with different mirror payload hash as canonical divergence' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-3458' -RequestObjective 'wat-shuld-happen-befor-we-add-anothr-featre' -RequestTaskId 'wat-shuld-happen-befor-we-add-anothr-featre-mim-request-f140a49c-replan-1' -LocalSequence '' -RemoteSequence $null -RemoteSha256 '446347d289531f1fa590a3d76e60efa9e5bfbc7f563e801c615cc3163ef54f4f'
        try {
            $raw = & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.passed | Should Be $true
            [bool]$doc.canonical_request.canonical_request_mismatch | Should Be $false
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'passes while a fresh accepted request is still in flight before a matching result exists' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-3458' -RequestObjective 'wat-shuld-happen-befor-we-add-anothr-featre' -RequestTaskId 'wat-shuld-happen-befor-we-add-anothr-featre-mim-request-f140a49c-replan-1' -EmitResult $false
        try {
            $raw = & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.passed | Should Be $true
            [bool]$doc.local_bridge.request_in_flight_healthy | Should Be $true
            (@($doc.failure_modes) -contains 'listener_contract_stalled') | Should Be $false
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'passes while a fresh request is awaiting listener ack before the freshness window expires' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-3458' -RequestObjective 'wat-shuld-happen-befor-we-add-anothr-featre' -RequestTaskId 'wat-shuld-happen-befor-we-add-anothr-featre-mim-request-cd582c45-replan-1' -EmitResult $false -TriggerAckAcknowledges 'wat-shuld-happen-befor-we-add-anothr-featre-mim-request-previous-replan-1'
        try {
            $raw = & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.passed | Should Be $true
            [bool]$doc.local_bridge.request_awaiting_ack_healthy | Should Be $true
            (@($doc.failure_modes) -contains 'listener_contract_stalled') | Should Be $false
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'treats matching TOD and MIM objective values as aligned when the status text lags' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-3458' -RequestObjective 'wat-shuld-happen-befor-we-add-anothr-featre' -RequestTaskId 'wat-shuld-happen-befor-we-add-anothr-featre-mim-request-f140a49c-replan-1' -ObjectiveAlignmentStatus 'mismatch'
        try {
            $raw = & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.passed | Should Be $true
            [bool]$doc.objective_alignment.in_sync | Should Be $true
            (@($doc.failure_modes) -contains 'objective_alignment_not_in_sync') | Should Be $false
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'fails when the remote request task id diverges from formal program truth even if the objective matches' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-216' -RequestObjective 'objective-216' -RequestTaskId 'objective-216-task-008' -FormalProgramTaskId '1721'
        try {
            try {
                & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary | Out-Null
            }
            catch {
            }

            $doc = Get-Content -Path $fixture.Output -Raw | ConvertFrom-Json
            [bool]$doc.passed | Should Be $false
            [string]$doc.classification | Should Be 'publication_surface_divergence'
            [string]$doc.failure_reason | Should Be 'publication_surface_divergence'
            (@($doc.failure_modes) -contains 'publication_surface_divergence') | Should Be $true
            (@($doc.failure_modes) -contains 'stale_remote_request_identity') | Should Be $true
            [string]$doc.canonical_request.expected_objective_id | Should Be 'objective-216'
            [string]$doc.canonical_request.expected_task_id | Should Be 'objective-216-task-1721'
            [string]$doc.canonical_request.remote_surface.task_id | Should Be 'objective-216-task-008'
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'passes when a stale backfill request is closed by a fresh stale_ignored task ACK' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-97' -RequestObjective 'objective-97' -RequestTaskId 'objective-97-task-207752' -HighWatermarkTaskId 'objective-97-task-1775172258' -TaskAckStatus 'stale_ignored' -EmitResult $false
        try {
            $raw = & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.passed | Should Be $true
            [string]$doc.classification | Should Be 'pass'
            [bool]$doc.local_bridge.stale_terminal_ack_healthy | Should Be $true
            [string]$doc.local_bridge.task_ack_status | Should Be 'stale_ignored'
            (@($doc.failure_modes) -contains 'listener_contract_stalled') | Should Be $false
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'fails when the remote boundary stays noncanonical even if the canonical request identity matches' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-97' -RequestObjective 'objective-97' -RequestTaskId 'objective-97-task-3422' -RemoteBoundaryClassification 'noncanonical_remote_surface'
        try {
            try {
                & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary | Out-Null
            }
            catch {
            }

            $doc = Get-Content -Path $fixture.Output -Raw | ConvertFrom-Json
            [bool]$doc.passed | Should Be $false
            [string]$doc.classification | Should Be 'noncanonical_remote_surface'
            [string]$doc.failure_reason | Should Be 'noncanonical_remote_surface'
            (@($doc.failure_modes) -contains 'noncanonical_remote_surface') | Should Be $true
            [bool]$doc.canonical_request.publication_surface_divergence | Should Be $false
            [bool]$doc.canonical_request.noncanonical_remote_surface | Should Be $true
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'passes when the stale remote request only reflects the latest completed objective residue' {
        $fixture = New-BridgeSmokeFixture -ExpectedObjective 'objective-170' -RequestObjective 'objective-152' -RequestTaskId 'objective-152-task-mim-arm-safe-home-20260408160030' -LatestCompletedObjective 'objective-152' -TriggerAckAcknowledges 'coordination-objective-152-task-mim-arm-safe-home-20260408160030-publication_surface_divergence'
        try {
            $raw = & $bridgeSmokeScript -ListenerStageDir $fixture.Listener -IntegrationStatusPath $fixture.Integration -OutputPath $fixture.Output -RemoteProbeJsonPath $fixture.RemoteProbe -RemoteBoundaryDiagnosticJsonPath $fixture.RemoteBoundary
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.passed | Should Be $true
            [string]$doc.classification | Should Be 'pass'
            (@($doc.failure_modes) -contains 'publication_surface_divergence') | Should Be $false
            [bool]$doc.canonical_request.completed_objective_residue | Should Be $true
            [bool]$doc.local_bridge.completed_objective_residue | Should Be $true
            [bool]$doc.local_bridge.healthy | Should Be $true
            [string]$doc.canonical_request.latest_completed_objective_id | Should Be 'objective-152'
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }
}
