Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerScript = Join-Path $repoRoot 'scripts/Start-TODMimPacketListener.ps1'

function Import-ListenerFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($listenerScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $listenerScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $listenerScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, (($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"), $utf8NoBom)
}

function New-MockTodScript {
    param([Parameter(Mandatory = $true)][string]$LogPath)

    $scriptPath = Join-Path $repoRoot ('tod/out/tests/mock-idle-wakeup-tod-' + [guid]::NewGuid().ToString('N') + '.ps1')
    $escapedLogPath = $LogPath.Replace("'", "''")
    $scriptContent = @'
param(
    [string]$Action,
    [string]$ObjectiveId,
    [string]$TaskId,
    [string]$Title,
    [string]$Description,
    [string]$Scope,
    [string]$AcceptanceCriteria,
    [string]$SuccessCriteria,
    [int]$Top = 0
)

Add-Content -Path '__LOG_PATH__' -Value ("{0}|{1}|{2}|{3}" -f $Action, $ObjectiveId, $TaskId, $Top)

switch ($Action) {
    'engineer-run' {
        @{
            run_id = 'ENGRUN-TEST'
            focus = @{
                objective_id = $ObjectiveId
                task_id = $TaskId
            }
        } | ConvertTo-Json -Depth 6
        break
    }
    'new-objective' {
        @{ id = 'objective-999' } | ConvertTo-Json -Depth 4
        break
    }
    'add-task' {
        @{ id = 'task-999' } | ConvertTo-Json -Depth 4
        break
    }
    default {
        throw ("Unexpected action: {0}" -f $Action)
    }
}
'@
    $scriptContent = $scriptContent.Replace('__LOG_PATH__', $escapedLogPath)

    $dir = Split-Path -Parent $scriptPath
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($scriptPath, ($scriptContent -replace "`r`n", "`n"), $utf8NoBom)
    return $scriptPath
}

Describe 'TOD packet listener idle wake-up' {
    BeforeAll {
        Import-ListenerFunction -Name 'New-ListenerState'
        $script:IdleAdvancementObjectiveTitle = 'TOD Autonomous Advancement Loop'
        $script:SelfImprovementTasks = @(
            [pscustomobject]@{ title = 'Improve listener reliability and retry discipline'; scope = 'scripts/Start-TODMimPacketListener.ps1, tests/TOD.PacketListener*.Tests.ps1'; criteria = 'One concrete reliability improvement is implemented or a bounded follow-on task is added with evidence.'; category = 'improve' }
            [pscustomobject]@{ title = 'Learn from recent engineer runs and summarize failure patterns'; scope = 'tod/data/state.json, scripts/TOD-Engineer.ps1, shared_state'; criteria = 'A short failure-pattern summary is produced and at least one mitigation task is added or updated.'; category = 'learn' }
            [pscustomobject]@{ title = 'Explore next-stage TOD autonomy opportunities while MIM is quiet'; scope = 'docs, scripts, shared_state'; criteria = 'At least three candidate advancement directions are identified and one is converted into a bounded task.'; category = 'explore' }
            [pscustomobject]@{ title = 'Run full regression suite and document any new failures or flakiness'; scope = 'scripts/TOD.ps1, tod/tests'; criteria = 'Regression report produced; any failures triaged and recorded in failure taxonomy.'; category = 'improve' }
            [pscustomobject]@{ title = 'Audit MIM-TOD packet protocol for latency, retry, and edge-case coverage'; scope = 'scripts/Start-TODMimPacketListener.ps1, scripts/Push-SyntheticResult.ps1'; criteria = 'Protocol audit complete; any gaps filed as follow-on tasks.'; category = 'learn' }
            [pscustomobject]@{ title = 'Scan state.json for OOM risk and apply compaction if size exceeds 2 MiB'; scope = 'tod/data/state.json, scripts/TOD.ps1'; criteria = 'state.json size confirmed below 2 MiB or compacted; no data loss.'; category = 'improve' }
        )
        Import-ListenerFunction -Name 'New-IdleWakeupState'
        Import-ListenerFunction -Name 'Set-ListenerReadinessSnapshot'
        Import-ListenerFunction -Name 'Clear-BlockedRecoveryState'
        Import-ListenerFunction -Name 'Save-BlockedRecoveryState'
        Import-ListenerFunction -Name 'Invoke-BlockedRecoveryContinuationIfNeeded'
        Import-ListenerFunction -Name 'Get-IdleWakeupPreferredTask'
        Import-ListenerFunction -Name 'Get-IdleWakeupCandidateTask'
        Import-ListenerFunction -Name 'Get-IdleAdvancementObjective'
        Import-ListenerFunction -Name 'Get-NextSelfImprovementTaskTemplate'
        Import-ListenerFunction -Name 'Ensure-IdleAdvancementObjective'
        Import-ListenerFunction -Name 'Invoke-IdleWakeupIfNeeded'
    }

    BeforeEach {
        function global:Get-IdleSeconds {
            param([string]$Since)
            return 999
        }

        function global:Invoke-ExecutionReadinessRefresh {
            param([string]$ReadinessScriptAbs, [string]$Reason)
            return [pscustomobject]@{
                ok = $true
                reason = 'refreshed'
                detail = $ReadinessScriptAbs
                payload = $null
            }
        }

        function global:Invoke-SharedStateSyncRefresh {
            param([string]$SyncScriptAbs, [string]$HostAlias, [string]$RemoteRoot, [string]$SyncStageRoot, [string]$ListenerRequestPath, [string]$Reason)
            return ''
        }

        function global:Get-LocalPath {
            param([string]$PathValue)

            switch ($PathValue) {
                'shared_state/next_actions.json' { return $script:NextActionsPath }
                'tod/data/state.json' { return $script:StatePath }
                default { return $PathValue }
            }
        }

        function global:Read-JsonFileIfExists {
            param([string]$PathValue)
            if (-not (Test-Path -Path $PathValue)) {
                return $null
            }

            return (Get-Content -Path $PathValue -Raw) | ConvertFrom-Json
        }

        function global:Write-JsonFile {
            param(
                [string]$PathValue,
                $Payload,
                [int]$Depth = 20
            )

            $dir = Split-Path -Parent $PathValue
            if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }

            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($PathValue, (($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"), $utf8NoBom)
        }
    }

    It 'resumes a pending task instead of creating self-improvement work' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/idle-wakeup-' + [guid]::NewGuid().ToString('N'))
        $script:NextActionsPath = Join-Path $fixture 'next_actions.json'
        $script:StatePath = Join-Path $fixture 'state.json'
        $idleWakeupStatePath = Join-Path $fixture 'TOD_IDLE_WAKEUP_STATE.latest.json'
        $mockLogPath = Join-Path $fixture 'mock-tod.log'
        $mockTodScript = $null

        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null

            Write-JsonFile -PathValue $script:NextActionsPath -Payload ([pscustomobject]@{
                current_objective_in_progress = '152'
                tod_catchup_roadmap = @()
            })

            Write-JsonFile -PathValue $script:StatePath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{
                        id = '152'
                        title = 'Objective 152'
                        status = 'open'
                        created_at = '2026-04-08T00:00:00Z'
                        updated_at = '2026-04-08T00:00:00Z'
                    }
                )
                tasks = @(
                    [pscustomobject]@{
                        id = 'task-152-a'
                        objective_id = '152'
                        title = 'Resume pending work'
                        status = 'planned'
                        created_at = '2026-04-08T00:00:00Z'
                        updated_at = '2026-04-08T00:05:00Z'
                    }
                )
            })

            $mockTodScript = New-MockTodScript -LogPath $mockLogPath
            $listenerState = [pscustomobject]@{
                last_execution_at = '2026-04-08T00:00:00Z'
            }
            $idleWakeupState = New-IdleWakeupState -ExistingState $null

            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $idleWakeupStatePath -TodScript $mockTodScript -SyncScript 'sync.ps1' -ReadinessScript 'readiness.ps1' -HostAlias 'mim' -RemoteRoot '/remote' -SyncStageRoot 'stage' -IdleThreshold 120 -Cooldown 300

            $logLines = @()
            if (Test-Path -Path $mockLogPath) {
                $logLines = @(Get-Content -Path $mockLogPath)
            }

            @($logLines | Where-Object { $_ -like 'engineer-run|152|task-152-a|5' }).Count | Should Be 1
            @($logLines | Where-Object { $_ -like 'add-task*' }).Count | Should Be 0
            [string]$idleWakeupState.last_engineer_run_signature | Should Match '152\|task-152-a\|planned\|2026-04-08T00:05:00Z'
            ([string]::IsNullOrWhiteSpace([string]$idleWakeupState.last_readiness_refresh_at)) | Should Be $false
            ([string]$listenerState.last_execution_at) | Should Not Be '2026-04-08T00:00:00Z'

            $idleEventPath = Join-Path $fixture 'TOD_IDLE_WAKEUP_EVENT.latest.json'
            (Test-Path -Path $idleEventPath) | Should Be $true
            $idleEvent = (Get-Content -Path $idleEventPath -Raw) | ConvertFrom-Json
            [string]$idleEvent.reason | Should Be 'resume_pending_task'
            [string]$idleEvent.action_taken | Should Be 'engineer_run_task-152-a'
            [bool]$idleEvent.readiness_refresh.ok | Should Be $true
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($mockTodScript) -and (Test-Path -Path $mockTodScript)) {
                Remove-Item -Path $mockTodScript -Force
            }
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 'creates an autonomous advancement objective and self-improvement task when idle with no pending work' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/idle-wakeup-' + [guid]::NewGuid().ToString('N'))
        $script:NextActionsPath = Join-Path $fixture 'next_actions.json'
        $script:StatePath = Join-Path $fixture 'state.json'
        $idleWakeupStatePath = Join-Path $fixture 'TOD_IDLE_WAKEUP_STATE.latest.json'
        $mockLogPath = Join-Path $fixture 'mock-tod.log'
        $mockTodScript = $null

        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null

            Write-JsonFile -PathValue $script:NextActionsPath -Payload ([pscustomobject]@{
                current_objective_in_progress = '152'
                tod_catchup_roadmap = @()
            })

            Write-JsonFile -PathValue $script:StatePath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{
                        id = '152'
                        title = 'Objective 152'
                        status = 'completed'
                        created_at = '2026-04-08T00:00:00Z'
                        updated_at = '2026-04-08T00:10:00Z'
                    }
                )
                tasks = @(
                    [pscustomobject]@{
                        id = 'task-152-a'
                        objective_id = '152'
                        title = 'Completed bounded work'
                        status = 'completed'
                        created_at = '2026-04-08T00:00:00Z'
                        updated_at = '2026-04-08T00:05:00Z'
                    }
                )
            })

            $mockTodScript = New-MockTodScript -LogPath $mockLogPath
            $listenerState = [pscustomobject]@{
                last_execution_at = '2026-04-08T00:00:00Z'
            }
            $idleWakeupState = New-IdleWakeupState -ExistingState $null

            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $idleWakeupStatePath -TodScript $mockTodScript -SyncScript 'sync.ps1' -ReadinessScript 'readiness.ps1' -HostAlias 'mim' -RemoteRoot '/remote' -SyncStageRoot 'stage' -IdleThreshold 120 -Cooldown 300

            $logLines = @()
            if (Test-Path -Path $mockLogPath) {
                $logLines = @(Get-Content -Path $mockLogPath)
            }

            @($logLines | Where-Object { $_ -like 'new-objective|||*' }).Count | Should Be 1
            @($logLines | Where-Object { $_ -like 'add-task|objective-999||0' }).Count | Should Be 1
            [int]$idleWakeupState.last_self_task_catalog_index | Should Be 0

            $idleEventPath = Join-Path $fixture 'TOD_IDLE_WAKEUP_EVENT.latest.json'
            $idleEvent = (Get-Content -Path $idleEventPath -Raw) | ConvertFrom-Json
            [string]$idleEvent.reason | Should Be 'self_improve'
            [string]$idleEvent.action_taken | Should Be 'created_self_task_task-999'
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($mockTodScript) -and (Test-Path -Path $mockTodScript)) {
                Remove-Item -Path $mockTodScript -Force
            }
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 're-pings engineer-run on the same pending task after the idle reping interval' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/idle-wakeup-' + [guid]::NewGuid().ToString('N'))
        $script:NextActionsPath = Join-Path $fixture 'next_actions.json'
        $script:StatePath = Join-Path $fixture 'state.json'
        $idleWakeupStatePath = Join-Path $fixture 'TOD_IDLE_WAKEUP_STATE.latest.json'
        $mockLogPath = Join-Path $fixture 'mock-tod.log'
        $mockTodScript = $null

        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null

            Write-JsonFile -PathValue $script:NextActionsPath -Payload ([pscustomobject]@{
                current_objective_in_progress = '170'
                tod_catchup_roadmap = @()
            })

            Write-JsonFile -PathValue $script:StatePath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{
                        id = '170'
                        title = 'TOD Autonomous Advancement Loop'
                        status = 'open'
                        created_at = '2026-04-08T00:00:00Z'
                        updated_at = '2026-04-08T00:00:00Z'
                    }
                )
                tasks = @(
                    [pscustomobject]@{
                        id = 'task-170-a'
                        objective_id = '170'
                        title = 'Improve listener reliability and retry discipline'
                        status = 'planned'
                        created_at = '2026-04-08T00:00:00Z'
                        updated_at = '2026-04-08T00:05:00Z'
                    }
                )
            })

            $mockTodScript = New-MockTodScript -LogPath $mockLogPath
            $listenerState = [pscustomobject]@{
                last_execution_at = '2026-04-08T00:00:00Z'
            }
            $idleWakeupState = New-IdleWakeupState -ExistingState ([pscustomobject]@{
                last_engineer_run_signature = '170|task-170-a|planned|2026-04-08T00:05:00Z'
                last_engineer_run_at = '2026-04-08T00:00:00Z'
            })

            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $idleWakeupStatePath -TodScript $mockTodScript -SyncScript 'sync.ps1' -ReadinessScript 'readiness.ps1' -HostAlias 'mim' -RemoteRoot '/remote' -SyncStageRoot 'stage' -IdleThreshold 120 -Cooldown 300

            $logLines = @()
            if (Test-Path -Path $mockLogPath) {
                $logLines = @(Get-Content -Path $mockLogPath)
            }

            @($logLines | Where-Object { $_ -like 'engineer-run|170|task-170-a|5' }).Count | Should Be 1

            $idleEventPath = Join-Path $fixture 'TOD_IDLE_WAKEUP_EVENT.latest.json'
            $idleEvent = (Get-Content -Path $idleEventPath -Raw) | ConvertFrom-Json
            [string]$idleEvent.reason | Should Be 'resume_pending_task_reping'
            [string]$idleEvent.action_taken | Should Be 'engineer_run_task-170-a'
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($mockTodScript) -and (Test-Path -Path $mockTodScript)) {
                Remove-Item -Path $mockTodScript -Force
            }
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 'resumes a previously blocked task once when readiness recovers' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/blocked-recovery-' + [guid]::NewGuid().ToString('N'))
        $listenerStatePath = Join-Path $fixture 'listener_state.json'
        $idleWakeupStatePath = Join-Path $fixture 'TOD_IDLE_WAKEUP_STATE.latest.json'
        $mockLogPath = Join-Path $fixture 'mock-tod.log'
        $mockTodScript = $null

        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null

            function global:Get-ExecutionReadinessTrace {
                param([string]$TodScriptAbs, [string]$Action)
                return [pscustomobject]@{
                    status = 'valid'
                    source = 'health_probe'
                    detail = 'recovered'
                    valid = $true
                    execution_allowed = $true
                    authoritative = $true
                    freshness_state = 'fresh'
                    signal_name = 'execution-readiness'
                    evaluated_action = $Action
                    policy_outcome = 'allow'
                }
            }

            $mockTodScript = New-MockTodScript -LogPath $mockLogPath
            $listenerState = New-ListenerState -ExistingState $null
            $idleWakeupState = New-IdleWakeupState -ExistingState $null
            Save-BlockedRecoveryState -ListenerState $listenerState -RequestId 'req-152' -RequestSignature 'sig-152' -TaskId 'task-152-a' -ObjectiveId '152' -CorrelationId 'corr-152' -Action 'run-bridge-request' -ReasonCode 'execution_readiness_blocked' -Summary 'Execution readiness is blocking the requested action.' -ReadinessTrace ([pscustomobject]@{
                status = 'stale'
                source = 'cache'
                detail = 'stale'
                valid = $false
                execution_allowed = $false
                policy_outcome = 'block'
            })
            Write-JsonFile -PathValue $listenerStatePath -Payload $listenerState

            $resumeResult = Invoke-BlockedRecoveryContinuationIfNeeded -ListenerState $listenerState -ListenerStatePath $listenerStatePath -TodScript $mockTodScript -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $idleWakeupStatePath
            [bool]$resumeResult.resumed | Should Be $true
            [bool]$listenerState.blocked_resume_retry_attempted | Should Be $true

            $logLines = @()
            if (Test-Path -Path $mockLogPath) {
                $logLines = @(Get-Content -Path $mockLogPath)
            }
            @($logLines | Where-Object { $_ -like 'engineer-run|152|task-152-a|5' }).Count | Should Be 1

            $eventPath = Join-Path $fixture 'TOD_BLOCKED_RECOVERY_EVENT.latest.json'
            (Test-Path -Path $eventPath) | Should Be $true
            $event = (Get-Content -Path $eventPath -Raw) | ConvertFrom-Json
            [string]$event.status | Should Be 'resumed'
            [string]$event.recovery_transition | Should Be 'blocked_to_valid'

            $secondResult = Invoke-BlockedRecoveryContinuationIfNeeded -ListenerState $listenerState -ListenerStatePath $listenerStatePath -TodScript $mockTodScript -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $idleWakeupStatePath
            [bool]$secondResult.resumed | Should Be $false
            [string]$secondResult.reason | Should Be 'retry_already_attempted'

            $logLines = @(Get-Content -Path $mockLogPath)
            @($logLines | Where-Object { $_ -like 'engineer-run|152|task-152-a|5' }).Count | Should Be 1
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($mockTodScript) -and (Test-Path -Path $mockTodScript)) {
                Remove-Item -Path $mockTodScript -Force
            }
            if (Test-Path -Path Function:\Get-ExecutionReadinessTrace) {
                Remove-Item -Path Function:\Get-ExecutionReadinessTrace -Force
            }
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }
}