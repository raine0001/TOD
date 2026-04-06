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
        [string]$RemoteBoundaryClassification = 'canonical_remote_surface',
        [string]$TaskAckStatus = 'accepted',
        [string]$HighWatermarkTaskId = '',
        [bool]$EmitResult = $true
    )

    $base = Join-Path $repoRoot ('tod/out/tests/bridge-smoke-' + [guid]::NewGuid().ToString('N'))
    $listener = Join-Path $base 'listener'
    $integrationPath = Join-Path $base 'integration_status.json'
    $outputPath = Join-Path $base 'bridge_smoke.json'
    $remoteProbePath = Join-Path $base 'remote_probe.json'
    $remoteBoundaryPath = Join-Path $base 'remote_boundary.json'
    $now = (Get-Date).ToUniversalTime()

    Write-JsonNoBom -PathValue (Join-Path $listener 'MIM_TOD_TASK_REQUEST.latest.json') -Payload ([pscustomobject]@{
        generated_at = $now.AddSeconds(-30).ToString('o')
        task_id = $RequestTaskId
        objective_id = $RequestObjective
        sequence = 381549
    })
    Write-JsonNoBom -PathValue (Join-Path $listener 'TOD_TO_MIM_TRIGGER_ACK.latest.json') -Payload ([pscustomobject]@{
        generated_at = $now.AddSeconds(-20).ToString('o')
        acknowledges = $RequestTaskId
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
            status = 'in_sync'
            tod_current_objective = ($ExpectedObjective -replace '^objective-', '')
            mim_objective_active = ($ExpectedObjective -replace '^objective-', '')
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
        sha256 = '2ef2574dd4dfc7889da67f98296f06ca2c38801e3bc046e870da371a03bde105'
        objective_id = $RequestObjective
        task_id = $RequestTaskId
        sequence = '381549'
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
        $fixture = New-BridgeSmokeFixture
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
}