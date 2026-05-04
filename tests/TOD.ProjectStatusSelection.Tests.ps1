Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiScript = Join-Path $repoRoot 'scripts/Start-TOD-UI.ps1'

function Import-UiFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($uiScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $uiScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $uiScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function Read-JsonFileIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path -PathType Leaf)) {
        return $null
    }

    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Get-IsoAgeSeconds {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return -1
    }

    try {
        $timestamp = [DateTime]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return [int][Math]::Floor(((Get-Date).ToUniversalTime() - $timestamp.ToUniversalTime()).TotalSeconds)
    }
    catch {
        return -1
    }
}

function Get-DialogSessionsPayload {
    param(
        [int]$Limit = 6,
        [string]$Actor = 'TOD'
    )

    return [pscustomobject]@{
        available = $true
        open_count = 0
        timed_out_count = 0
        closed_count = 0
        total_count = 0
        sessions = @()
    }
}

Describe 'TOD project status selection hardening' {
    BeforeAll {
        Import-UiFunction -Name 'Normalize-ObjectiveIdValue'
        Import-UiFunction -Name 'Get-ObjectiveNumericValue'
        Import-UiFunction -Name 'Resolve-ProjectSelectedObjectiveId'
        Import-UiFunction -Name 'Get-CommunicationHealth'
        Import-UiFunction -Name 'Get-TrainingStatusPayload'
        $script:nextStepConsensusPath = Join-Path $repoRoot 'shared_state/NEXT_STEP_CONSENSUS.latest.json'
        $script:nextStepPolicyPath = Join-Path $repoRoot 'shared_state/NEXT_STEP_POLICY.latest.json'
    }

    It 'reads the live training artifact for UI status rendering' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/project-status-training-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $script:trainingStatusPath = Join-Path $fixture 'tod_training_status.latest.json'

            [pscustomobject]@{
                source = 'tod-training-status-v1'
                run_id = 'run-123'
                state = 'running'
                state_label = 'TRAINING ACTIVE'
                active = $true
                percent_complete = 58
                phase = 'runtime_safe_subset'
                phase_detail = 'Running runtime-safe validation subset.'
                runtime_seconds = 901
                eta_seconds = 122
                latest_error = ''
                latest_resolution = 'Runtime-safe validation advanced.'
                recent_events = @()
                stages = @()
            } | ConvertTo-Json -Depth 12 | Set-Content -Path $script:trainingStatusPath

            $payload = Get-TrainingStatusPayload

            [bool]$payload.available | Should Be $true
            [bool]$payload.active | Should Be $true
            [int]$payload.percent_complete | Should Be 58
            [string]$payload.phase | Should Be 'runtime_safe_subset'
            [string]$payload.latest_resolution | Should Be 'Runtime-safe validation advanced.'
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 'prefers the canonical MIM objective when watchdog flags publication surface divergence' {
        $selectedObjectiveId = Resolve-ProjectSelectedObjectiveId -ExplicitObjectiveId '' -ListenerActivity ([pscustomobject]@{
                latest_objective_id = 'objective-115'
            }) -BridgeStatus ([pscustomobject]@{
                canonical_mim_objective_id = 'objective-122'
                task_request_objective_id = 'objective-115'
                objective_mismatch = $false
            }) -RecoveryWatchdog ([pscustomobject]@{
                last_issue = 'publication_surface_divergence'
            }) -NextActions $null -Objectives @()

        [string]$selectedObjectiveId | Should Be 'objective-122'
    }

    It 'treats publication surface divergence as active communication work rather than resolved comm health' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/project-status-selection-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $script:coordinationEscalationPath = Join-Path $fixture 'coordination.json'
            $script:listenerEmergencyRequestPath = Join-Path $fixture 'TOD_MIM_EMERGENCY_REQUEST.latest.json'
            $script:listenerEmergencyAckPath = Join-Path $fixture 'MIM_TOD_EMERGENCY_ACK.latest.json'
            $script:dialogDirPath = Join-Path $fixture 'dialog'
            $script:nextStepConsensusPath = Join-Path $fixture 'NEXT_STEP_CONSENSUS.latest.json'
            $script:nextStepPolicyPath = Join-Path $fixture 'NEXT_STEP_POLICY.latest.json'

            $health = Get-CommunicationHealth -ListenerActivity ([pscustomobject]@{
                    latest_request_id = 'objective-115-task-mim-arm-capture-frame-20260407033825'
                    latest_execution_status = 'completed'
                }) -BridgeStatus ([pscustomobject]@{
                    available = $true
                    status = 'warning'
                    canonical_mim_objective_id = 'objective-122'
                    task_request_objective_id = 'objective-115'
                    objective_mismatch = $false
                    objective_mismatch_detail = 'Canonical export shows objective 122 while live task-request publication remains objective 115.'
                }) -RecoveryWatchdog ([pscustomobject]@{
                    last_issue = 'publication_surface_divergence'
                })

            [string]$health.status | Should Be 'warning'
            [string]$health.pending_issue_code | Should Be 'publication_surface_divergence'
            [string]$health.coordination_status | Should Be 'publisher_realign_pending'
            [string]$health.coordination_decision | Should Be 'republish_live_task_request'
            [string]$health.summary | Should Match 'Canonical MIM objective objective-122 is ahead of the live task publication surface objective-115'
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 'treats a stale pending next-step consensus as a communication stall' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/project-status-next-step-stall-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $script:coordinationEscalationPath = Join-Path $fixture 'coordination.json'
            $script:listenerEmergencyRequestPath = Join-Path $fixture 'TOD_MIM_EMERGENCY_REQUEST.latest.json'
            $script:listenerEmergencyAckPath = Join-Path $fixture 'MIM_TOD_EMERGENCY_ACK.latest.json'
            $script:dialogDirPath = Join-Path $fixture 'dialog'
            $script:nextStepConsensusPath = Join-Path $fixture 'NEXT_STEP_CONSENSUS.latest.json'
            $script:nextStepPolicyPath = Join-Path $fixture 'NEXT_STEP_POLICY.latest.json'

            [pscustomobject]@{
                generated_at = (Get-Date).ToUniversalTime().AddMinutes(-8).ToString('o')
                status = 'pending_mim'
                mim_position = [pscustomobject]@{
                    decision = 'pending'
                    session_id = 'next-step-session-123'
                }
                consensus = [pscustomobject]@{
                    action = 'Run bounded validation pass'
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:nextStepConsensusPath

            [pscustomobject]@{
                continuation = [pscustomobject]@{
                    decision = 'await_tod_mim_consensus'
                    route = 'tod_mim_consensus_dialog'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $script:nextStepPolicyPath

            $health = Get-CommunicationHealth -ListenerActivity ([pscustomobject]@{
                    latest_request_id = 'objective-200-task-001'
                    latest_execution_status = 'completed'
                }) -BridgeStatus ([pscustomobject]@{
                    available = $true
                    status = 'ok'
                }) -RecoveryWatchdog ([pscustomobject]@{
                    last_issue = ''
                })

            [string]$health.status | Should Be 'warning'
            [string]$health.next_step_status | Should Be 'pending_mim'
            [string]$health.next_step_continuation_decision | Should Be 'await_tod_mim_consensus'
            [bool]$health.next_step_stalled | Should Be $true
            [string]$health.summary | Should Match 'Next-step consensus'
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 'treats a timed-out next-step consensus session as a frozen communication lane' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/project-status-next-step-freeze-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $script:coordinationEscalationPath = Join-Path $fixture 'coordination.json'
            $script:listenerEmergencyRequestPath = Join-Path $fixture 'TOD_MIM_EMERGENCY_REQUEST.latest.json'
            $script:listenerEmergencyAckPath = Join-Path $fixture 'MIM_TOD_EMERGENCY_ACK.latest.json'
            $script:dialogDirPath = Join-Path $fixture 'dialog'
            $script:nextStepConsensusPath = Join-Path $fixture 'NEXT_STEP_CONSENSUS.latest.json'
            $script:nextStepPolicyPath = Join-Path $fixture 'NEXT_STEP_POLICY.latest.json'
            New-Item -ItemType Directory -Path $script:dialogDirPath -Force | Out-Null

            [pscustomobject]@{
                generated_at = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o')
                status = 'pending_mim'
                mim_position = [pscustomobject]@{
                    decision = 'pending'
                    session_id = 'next-step-session-timeout'
                }
                consensus = [pscustomobject]@{
                    action = 'Run bounded validation pass'
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:nextStepConsensusPath

            [pscustomobject]@{
                continuation = [pscustomobject]@{
                    decision = 'await_tod_mim_consensus'
                    route = 'tod_mim_consensus_dialog'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $script:nextStepPolicyPath

            [pscustomobject]@{
                session_id = 'next-step-session-timeout'
                status = 'timed_out'
                updated_at = (Get-Date).ToUniversalTime().AddMinutes(-6).ToString('o')
                summary = 'MIM did not answer the next-step request in time.'
                message_type = 'status_request'
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $script:dialogDirPath 'MIM_TOD_DIALOG.session-next-step-session-timeout.latest.json')

            $health = Get-CommunicationHealth -ListenerActivity ([pscustomobject]@{
                    latest_request_id = 'objective-200-task-001'
                    latest_execution_status = 'completed'
                }) -BridgeStatus ([pscustomobject]@{
                    available = $true
                    status = 'ok'
                }) -RecoveryWatchdog ([pscustomobject]@{
                    last_issue = ''
                })

            [string]$health.status | Should Be 'critical'
            [string]$health.next_step_dialog_status | Should Be 'timed_out'
            [bool]$health.next_step_frozen | Should Be $true
            [string]$health.summary | Should Match 'timed out'
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 'does not freeze communication health when policy already moved stale consensus to provisional local execution' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/project-status-next-step-provisional-local-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $script:coordinationEscalationPath = Join-Path $fixture 'coordination.json'
            $script:listenerEmergencyRequestPath = Join-Path $fixture 'TOD_MIM_EMERGENCY_REQUEST.latest.json'
            $script:listenerEmergencyAckPath = Join-Path $fixture 'MIM_TOD_EMERGENCY_ACK.latest.json'
            $script:dialogDirPath = Join-Path $fixture 'dialog'
            $script:nextStepConsensusPath = Join-Path $fixture 'NEXT_STEP_CONSENSUS.latest.json'
            $script:nextStepPolicyPath = Join-Path $fixture 'NEXT_STEP_POLICY.latest.json'
            New-Item -ItemType Directory -Path $script:dialogDirPath -Force | Out-Null

            [pscustomobject]@{
                generated_at = (Get-Date).ToUniversalTime().AddDays(-15).ToString('o')
                status = 'pending_mim'
                mim_position = [pscustomobject]@{
                    decision = 'pending'
                    session_id = 'next-step-session-stale-provisional'
                }
                consensus = [pscustomobject]@{
                    action = 'Run canonical-only validation pass'
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:nextStepConsensusPath

            [pscustomobject]@{
                applied = $true
                provisional = $true
                continuation = [pscustomobject]@{
                    decision = 'proceed_with_local_decision'
                    route = 'tod_local_provisional_follow_through'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $script:nextStepPolicyPath

            [pscustomobject]@{
                session_id = 'next-step-session-stale-provisional'
                status = 'timed_out'
                updated_at = (Get-Date).ToUniversalTime().AddDays(-14).ToString('o')
                summary = 'MIM did not answer the next-step request in time.'
                message_type = 'status_request'
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $script:dialogDirPath 'MIM_TOD_DIALOG.session-next-step-session-stale-provisional.latest.json')

            $health = Get-CommunicationHealth -ListenerActivity ([pscustomobject]@{
                    latest_request_id = 'objective-200-task-001'
                    latest_execution_status = 'completed'
                }) -BridgeStatus ([pscustomobject]@{
                    available = $true
                    status = 'ok'
                }) -RecoveryWatchdog ([pscustomobject]@{
                    last_issue = ''
                })

            [string]$health.status | Should Be 'ok'
            [string]$health.next_step_status | Should Be 'pending_mim'
            [string]$health.next_step_continuation_decision | Should Be 'proceed_with_local_decision'
            [bool]$health.next_step_handled_locally | Should Be $true
            [bool]$health.next_step_stalled | Should Be $false
            [bool]$health.next_step_frozen | Should Be $false
            [string]$health.summary | Should Match 'currently clear'
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }
}
