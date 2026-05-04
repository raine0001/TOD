Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'
$configPath = Join-Path $repoRoot 'tod/config/tod-config.json'
$listenerDir = Join-Path $repoRoot 'tod/out/context-sync/listener'
$requestPath = Join-Path $listenerDir 'MIM_TOD_TASK_REQUEST.latest.json'
$ackPath = Join-Path $listenerDir 'TOD_MIM_TASK_ACK.latest.json'
$resultPath = Join-Path $listenerDir 'TOD_MIM_TASK_RESULT.latest.json'

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, (($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"), $utf8NoBom)
}

function Backup-BridgeLaneFiles {
    $paths = @($requestPath, $ackPath, $resultPath)
    $backups = @()
    foreach ($pathValue in $paths) {
        $backups += [pscustomobject]@{
            path = $pathValue
            exists = (Test-Path -Path $pathValue -PathType Leaf)
            content = if (Test-Path -Path $pathValue -PathType Leaf) { [string](Get-Content -Path $pathValue -Raw) } else { '' }
        }
    }
    return @($backups)
}

function Restore-BridgeLaneFiles {
    param([Parameter(Mandatory = $true)]$Backups)

    foreach ($backup in @($Backups)) {
        if ([bool]$backup.exists) {
            $dir = Split-Path -Parent ([string]$backup.path)
            if (-not (Test-Path -Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }

            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText([string]$backup.path, [string]$backup.content, $utf8NoBom)
        }
        elseif (Test-Path -Path ([string]$backup.path)) {
            Remove-Item -Path ([string]$backup.path) -Force
        }
    }
}

function New-BridgeRequestConfigFixture {
    $id = [guid]::NewGuid().ToString('N')
    $base = Join-Path $repoRoot ('tod/out/tests/bridge-request-' + $id)
    New-Item -ItemType Directory -Path $base -Force | Out-Null

    $artifactPath = Join-Path $base 'tod_operator_chat_sweep_artifact_smoke.latest.json'
    $historyPath = Join-Path $base 'tod_execution_readiness_history.latest.json'
    $fixtureConfigPath = Join-Path $base 'tod-config.json'

    $artifact = [pscustomobject]@{
        source = 'tod-operator-chat-sweep-artifact-smoke-v1'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        summary = [pscustomobject]@{
            total = 13
            passed = 13
            failed = 0
            passed_all = $true
            exit_code = 0
        }
    }
    Write-JsonNoBom -PathValue $artifactPath -Payload $artifact

    $cfg = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    $cfg.execution_engine.readiness_policy = [pscustomobject]@{
        enabled = $true
        signal_path = $artifactPath
        history_path = $historyPath
        history_max_entries = 20
        max_artifact_age_minutes = 30
        display_max_artifact_age_minutes = 10
        block_actions = @('run-task')
        degrade_actions = @('engineer-run')
        block_states = @('stale', 'invalid', 'unknown')
        degrade_states = @('degraded', 'stale', 'invalid', 'unknown')
        degrade_apply_plan = $true
    }
    $cfg | ConvertTo-Json -Depth 40 | Set-Content -Path $fixtureConfigPath

    return [pscustomobject]@{
        Base = $base
        ConfigPath = $fixtureConfigPath
    }
}

function Remove-TestFixturePath {
    param([string]$PathValue)

    if (-not [string]::IsNullOrWhiteSpace($PathValue) -and (Test-Path -Path $PathValue)) {
        Remove-Item -Path $PathValue -Recurse -Force
    }
}

function Invoke-TodActionJson {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [hashtable]$ExtraArgs = @{}
    )

    $invokeParams = @{ Action = $Action }
    foreach ($key in $ExtraArgs.Keys) {
        $invokeParams[$key] = $ExtraArgs[$key]
    }

    $raw = & $todScript @invokeParams
    return ($raw | ConvertFrom-Json)
}

Describe 'TOD bridge request execution lane' {
    It 'executes the live bridge request with run-bridge-request and does not use task registry lookup' {
        $fixture = New-BridgeRequestConfigFixture
        $backups = Backup-BridgeLaneFiles
        try {
            Write-JsonNoBom -PathValue $requestPath -Payload ([pscustomobject]@{
                request_id = 'objective-400-task-001'
                task_id = 'objective-400-task-001'
                objective_id = 'objective-400'
                target = 'TOD'
                tod_action = 'get-state-bus'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
            })

            $payload = Invoke-TodActionJson -Action 'run-bridge-request' -ExtraArgs @{ RequestId = 'objective-400-task-001'; ConfigPath = $fixture.ConfigPath }

            [string]$payload.request_id | Should Be 'objective-400-task-001'
            [string]$payload.execution_lane | Should Be 'bridge_request'
            [bool]$payload.validated_request_match | Should Be $true
            [bool]$payload.mim_task_lookup_used | Should Be $false
            [bool]$payload.local_task_resolution_used | Should Be $false
            [string]$payload.tod_action | Should Be 'get-state-bus'
            [bool]$payload.execution.ok | Should Be $true
            [string]$payload.execution.action | Should Be 'get-state-bus'
            [string]$payload.execution.execution_mode | Should Be 'direct_script_success'
        }
        finally {
            Restore-BridgeLaneFiles -Backups $backups
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'rejects bridge requests that try to enter the task registry lane' {
        $fixture = New-BridgeRequestConfigFixture
        $backups = Backup-BridgeLaneFiles
        try {
            Write-JsonNoBom -PathValue $requestPath -Payload ([pscustomobject]@{
                request_id = 'objective-401-task-001'
                task_id = 'objective-401-task-001'
                objective_id = 'objective-401'
                target = 'TOD'
                tod_action = 'run-task'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
            })

            { & $todScript -Action 'run-bridge-request' -RequestId 'objective-401-task-001' -ConfigPath $fixture.ConfigPath } | Should Throw 'not supported by run-bridge-request'
        }
        finally {
            Restore-BridgeLaneFiles -Backups $backups
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'accepts scan_pose as a supported bridge action instead of rejecting the lane outright' {
        $fixture = New-BridgeRequestConfigFixture
        $backups = Backup-BridgeLaneFiles
        try {
            Write-JsonNoBom -PathValue $requestPath -Payload ([pscustomobject]@{
                request_id = 'objective-401-task-002'
                task_id = 'objective-401-task-002'
                objective_id = 'objective-401'
                target = 'TOD'
                tod_action = 'scan_pose'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
            })

            $message = ''
            try {
                & $todScript -Action 'run-bridge-request' -RequestId 'objective-401-task-002' -ConfigPath $fixture.ConfigPath 2>&1 | Out-String | Out-Null
            }
            catch {
                $message = [string]$_.Exception.Message
            }

            $message | Should Not Match 'not supported by run-bridge-request'
        }
        finally {
            Restore-BridgeLaneFiles -Backups $backups
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'accepts capture_frame as a supported bridge action instead of rejecting the lane outright' {
        $fixture = New-BridgeRequestConfigFixture
        $backups = Backup-BridgeLaneFiles
        try {
            Write-JsonNoBom -PathValue $requestPath -Payload ([pscustomobject]@{
                request_id = 'objective-401-task-003'
                task_id = 'objective-401-task-003'
                objective_id = 'objective-401'
                target = 'TOD'
                tod_action = 'capture_frame'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
            })

            $message = ''
            try {
                & $todScript -Action 'run-bridge-request' -RequestId 'objective-401-task-003' -ConfigPath $fixture.ConfigPath 2>&1 | Out-String | Out-Null
            }
            catch {
                $message = [string]$_.Exception.Message
            }

            $message | Should Not Match 'not supported by run-bridge-request'
        }
        finally {
            Restore-BridgeLaneFiles -Backups $backups
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'resolves nested bridge metadata to the bounded capture_frame action' {
        $fixture = New-BridgeRequestConfigFixture
        $backups = Backup-BridgeLaneFiles
        try {
            Write-JsonNoBom -PathValue $requestPath -Payload ([pscustomobject]@{
                request_id = 'objective-401-task-004'
                task_id = 'objective-401-task-004'
                objective_id = 'objective-401'
                target = 'TOD'
                tod_action = 'run-bridge-request'
                action = 'capture_frame'
                tod_action_args = [pscustomobject]@{
                    Action = 'capture_frame'
                    RequestId = 'objective-401-task-004'
                }
                tod_bridge_request = [pscustomobject]@{
                    action = 'capture_frame'
                    request_id = 'objective-401-task-004'
                }
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
            })

            $message = ''
            try {
                & $todScript -Action 'run-bridge-request' -RequestId 'objective-401-task-004' -ConfigPath $fixture.ConfigPath 2>&1 | Out-String | Out-Null
            }
            catch {
                $message = [string]$_.Exception.Message
            }

            $message | Should Not Match "resolves to TOD action 'run-bridge-request'"
            $message | Should Not Match 'not supported by run-bridge-request'
        }
        finally {
            Restore-BridgeLaneFiles -Backups $backups
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'accepts bridge packets with case-colliding nested action keys' {
        $fixture = New-BridgeRequestConfigFixture
        $backups = Backup-BridgeLaneFiles
        try {
            $rawJson = @'
{
  "request_id": "objective-401-task-005",
  "task_id": "objective-401-task-005",
  "objective_id": "objective-401",
  "target": "TOD",
  "tod_action": "run-bridge-request",
  "action": "capture_frame",
  "tod_action_args": {
    "Action": "capture_frame",
    "RequestId": "objective-401-task-005"
  },
  "tod_bridge_request": {
    "Action": "capture_frame",
    "action": "capture_frame",
    "RequestId": "objective-401-task-005"
  },
  "generated_at": "2026-04-07T00:00:00Z"
}
'@
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($requestPath, ($rawJson -replace "`r`n", "`n"), $utf8NoBom)

            $message = ''
            try {
                & $todScript -Action 'run-bridge-request' -RequestId 'objective-401-task-005' -ConfigPath $fixture.ConfigPath 2>&1 | Out-String | Out-Null
            }
            catch {
                $message = [string]$_.Exception.Message
            }

            $message | Should Not Match 'not valid JSON'
            $message | Should Not Match "resolves to TOD action 'run-bridge-request'"
        }
        finally {
            Restore-BridgeLaneFiles -Backups $backups
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'directs bridge request ids away from run-task and toward run-bridge-request' {
        $fixture = New-BridgeRequestConfigFixture
        $backups = Backup-BridgeLaneFiles
        try {
            Write-JsonNoBom -PathValue $requestPath -Payload ([pscustomobject]@{
                request_id = 'objective-402-task-001'
                task_id = 'objective-402-task-001'
                objective_id = 'objective-402'
                target = 'TOD'
                tod_action = 'get-state-bus'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
            })

            { & $todScript -Action 'run-task' -TaskId 'objective-402-task-001' -ConfigPath $fixture.ConfigPath } | Should Throw 'run-bridge-request'
        }
        finally {
            Restore-BridgeLaneFiles -Backups $backups
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }
}