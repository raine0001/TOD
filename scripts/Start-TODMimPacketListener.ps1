param(
    [string]$EnvFile = ".env",
    [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared",
    [string]$StageDir = "tod/out/context-sync/listener",
    [string]$SyncScriptPath = "scripts/Invoke-TODSharedStateSync.ps1",
    [string]$TodScriptPath = "scripts/TOD.ps1",
    [string]$ValidatorScriptPath = "scripts/Invoke-TODMimListenerValidator.ps1",
    [int]$PollSeconds = 2,
    [int]$RegressionNoDeltaThreshold = 4,
    [int]$QuarantineFailCycleThreshold = 5,
    [int]$IdleWakeupSeconds = 120,
    [int]$IdleWakeupCooldownSeconds = 300,
    [switch]$RunOnce,
    [switch]$ProcessWithoutGoOrder,
    [switch]$PublishIntegrationStatus,
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$scriptVersion = "2026-03-15T21:58Z"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -Path $Path)) { return "" }

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace([string]$line)) { return "" }

    return ([string]($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "")).Trim()
}

function Resolve-SshHostAlias {
    param([Parameter(Mandatory = $true)][string]$RemoteHost)

    if ($RemoteHost -match "^\d{1,3}(?:\.\d{1,3}){3}$" -or $RemoteHost -match "\.") {
        return $RemoteHost
    }

    $sshConfigPath = Join-Path $HOME ".ssh/config"
    if (-not (Test-Path -Path $sshConfigPath)) {
        return $RemoteHost
    }

    $matchedHost = $false
    foreach ($rawLine in Get-Content -Path $sshConfigPath) {
        $line = [string]$rawLine
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith("#")) {
            continue
        }

        if ($trim -match "^(?i)Host\s+(.+)$") {
            $matchedHost = $false
            foreach ($token in @($matches[1] -split "\s+")) {
                if ([string]::Equals([string]$token, $RemoteHost, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchedHost = $true
                    break
                }
            }
            continue
        }

        if ($matchedHost -and $trim -match "^(?i)HostName\s+(.+)$") {
            return [string]$matches[1]
        }
    }

    return $RemoteHost
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) { return $null }
    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function New-ListenerState {
    param($ExistingState)

    return [pscustomobject]@{
        last_processed_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_processed_request_id"]) { [string]$ExistingState.last_processed_request_id } else { "" }
        last_processed_request_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_processed_request_signature"]) { [string]$ExistingState.last_processed_request_signature } else { "" }
        last_trigger_event_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_trigger_event_signature"]) { [string]$ExistingState.last_trigger_event_signature } else { "" }
        last_cycle_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_cycle_at"]) { [string]$ExistingState.last_cycle_at } else { "" }
        last_execution_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_execution_at"]) { [string]$ExistingState.last_execution_at } else { "" }
    }
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
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Get-RegressionSnapshot {
    param([Parameter(Mandatory = $true)][string]$CurrentBuildStatePath)

    $build = Read-JsonFileIfExists -PathValue $CurrentBuildStatePath
    if ($null -eq $build -or -not $build.PSObject.Properties["last_regression_result"]) {
        return [pscustomobject]@{
            available = $false
            passed = 0
            failed = 0
            total = 0
            generated_at = ""
            signature = ""
        }
    }

    $reg = $build.last_regression_result
    $passed = 0
    $failed = 0
    $total = 0
    try { $passed = [int]$reg.passed } catch { $passed = 0 }
    try { $failed = [int]$reg.failed } catch { $failed = 0 }
    try { $total = [int]$reg.total } catch { $total = 0 }
    $generatedAt = if ($reg.PSObject.Properties["generated_at"]) { [string]$reg.generated_at } else { "" }

    return [pscustomobject]@{
        available = $true
        passed = $passed
        failed = $failed
        total = $total
        generated_at = $generatedAt
        signature = ("{0}|{1}|{2}|{3}" -f $generatedAt, $passed, $failed, $total)
    }
}

function New-RegressionStallState {
    param($ExistingState)

    return [pscustomobject]@{
        last_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_signature"]) { [string]$ExistingState.last_signature } else { "" }
        last_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_request_id"]) { [string]$ExistingState.last_request_id } else { "" }
        unchanged_cycles = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["unchanged_cycles"]) { [int]$ExistingState.unchanged_cycles } else { 0 }
        last_update_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_update_at"]) { [string]$ExistingState.last_update_at } else { "" }
    }
}

function New-CoordinationEscalationState {
    param($ExistingState)

    return [pscustomobject]@{
        pending_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_request_id"]) { [string]$ExistingState.pending_request_id } else { "" }
        pending_since = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_since"]) { [string]$ExistingState.pending_since } else { "" }
        last_emit_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emit_at"]) { [string]$ExistingState.last_emit_at } else { "" }
        last_emitted_level = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emitted_level"]) { [int]$ExistingState.last_emitted_level } else { 0 }
        emit_count = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["emit_count"]) { [int]$ExistingState.emit_count } else { 0 }
        last_ack_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_request_id"]) { [string]$ExistingState.last_ack_request_id } else { "" }
        last_acknowledged_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_acknowledged_at"]) { [string]$ExistingState.last_acknowledged_at } else { "" }
        last_ack_generated_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_generated_at"]) { [string]$ExistingState.last_ack_generated_at } else { "" }
        last_ack_status = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_status"]) { [string]$ExistingState.last_ack_status } else { "" }
        last_ack_decision = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_decision"]) { [string]$ExistingState.last_ack_decision } else { "" }
        last_ack_reason = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_reason"]) { [string]$ExistingState.last_ack_reason } else { "" }
    }
}

function Clear-CoordinationEscalationState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$Reason = "",
        [string]$RequestId = ""
    )

    $State.pending_request_id = ""
    $State.pending_since = ""
    $State.last_emit_at = ""
    $State.last_emitted_level = 0
    $State.emit_count = 0
    if (-not [string]::IsNullOrWhiteSpace($RequestId)) {
        $State.last_ack_request_id = $RequestId
    }
    $State.last_acknowledged_at = (Get-Date).ToUniversalTime().ToString("o")
    $State.last_ack_status = "resolved"
    $State.last_ack_decision = "auto_resolved_regression_green"
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        $State.last_ack_reason = $Reason
    }
}

function Get-IdleSeconds {
    param([string]$Since)
    if ([string]::IsNullOrWhiteSpace($Since)) { return 99999 }
    [datetime]$dt = [datetime]::MinValue
    if ([datetime]::TryParse($Since, [ref]$dt)) {
        $utc = $dt.ToUniversalTime()
        return [int][math]::Floor(([DateTime]::UtcNow - $utc).TotalSeconds)
    }
    return 99999
}

function New-IdleWakeupState {
    param($ExistingState)
    return [pscustomobject]@{
        last_wakeup_at          = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_wakeup_at"])          { [string]$ExistingState.last_wakeup_at }          else { "" }
        last_wakeup_reason      = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_wakeup_reason"])      { [string]$ExistingState.last_wakeup_reason }      else { "" }
        last_self_task_id       = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_self_task_id"])       { [string]$ExistingState.last_self_task_id }       else { "" }
        last_objective_advanced = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_objective_advanced"]) { [string]$ExistingState.last_objective_advanced } else { "" }
        wakeup_count            = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["wakeup_count"])            { [int]$ExistingState.wakeup_count }                else { 0 }
    }
}

# Self-improvement task catalog — rotated through when MIM has no pending work.
$script:SelfImprovementTasks = @(
    [pscustomobject]@{ title = "Run full regression suite and document any new failures or flakiness";                    scope = "scripts/TOD.ps1, tod/tests";                                              criteria = "Regression report produced; any failures triaged and recorded in failure taxonomy." }
    [pscustomobject]@{ title = "Review engineering loop history and identify top-3 reliability gaps";                    scope = "scripts/Start-TODMimPacketListener.ps1, tod/data/state.json";             criteria = "Gap analysis written to journal; at least one concrete improvement task proposed." }
    [pscustomobject]@{ title = "Audit MIM-TOD packet protocol for latency, retry, and edge-case coverage";              scope = "scripts/Start-TODMimPacketListener.ps1, scripts/Push-SyntheticResult.ps1"; criteria = "Protocol audit complete; any gaps filed as follow-on tasks." }
    [pscustomobject]@{ title = "Verify quarantine, cadence-reset, and idle-wakeup improvements end-to-end";             scope = "scripts/Start-TODMimPacketListener.ps1, scripts/Start-TOD-UI.ps1";        criteria = "All three mechanisms exercised and pass a manual smoke check." }
    [pscustomobject]@{ title = "Review failure taxonomy and propose routing-confidence penalty updates";                 scope = "scripts/TOD.ps1, tod/config/tod-config.json";                               criteria = "Taxonomy reviewed; penalty update either applied or documented as future work." }
    [pscustomobject]@{ title = "Scan state.json for OOM risk and apply compaction if size exceeds 2 MiB";               scope = "tod/data/state.json, scripts/TOD.ps1";                                      criteria = "state.json size confirmed below 2 MiB or compacted; no data loss." }
)

function Invoke-IdleWakeupIfNeeded {
    param(
        [Parameter(Mandatory=$true)]$ListenerState,
        [Parameter(Mandatory=$true)]$IdleWakeupState,
        [Parameter(Mandatory=$true)][string]$IdleWakeupStatePath,
        [Parameter(Mandatory=$true)][string]$TodScript,
        [Parameter(Mandatory=$true)][string]$SyncScript,
        [Parameter(Mandatory=$true)][int]$IdleThreshold,
        [Parameter(Mandatory=$true)][int]$Cooldown,
        [switch]$RunOnce
    )

    if ($RunOnce) { return }

    # Gate 1: has it been idle long enough?
    $idleSec = Get-IdleSeconds -Since ([string]$ListenerState.last_execution_at)
    if ($idleSec -lt $IdleThreshold) { return }

    # Gate 2: cooldown since last wakeup action?
    $cooldownSec = Get-IdleSeconds -Since ([string]$IdleWakeupState.last_wakeup_at)
    if ($cooldownSec -lt $Cooldown) { return }

    Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Idle for {0}s (threshold={1}s). Running proactive wake-up." -f $idleSec, $IdleThreshold)

    # Refresh shared state before evaluating
    try { & $SyncScript 2>&1 | Out-Null } catch { }

    $nextActionsPath = Get-LocalPath -PathValue "shared_state/next_actions.json"
    $statePath       = Get-LocalPath -PathValue "tod/data/state.json"
    $nextActions     = Read-JsonFileIfExists -PathValue $nextActionsPath
    $state           = Read-JsonFileIfExists -PathValue $statePath

    $currentObjId = if ($nextActions -and $nextActions.PSObject.Properties["current_objective_in_progress"]) { [string]$nextActions.current_objective_in_progress } else { "" }
    $roadmap      = if ($nextActions -and $nextActions.PSObject.Properties["tod_catchup_roadmap"])           { @($nextActions.tod_catchup_roadmap) } else { @() }
    $wakeupReason = "idle_check"
    $actionTaken  = ""

    if ($null -ne $state) {
        $terminalStatuses = @("pass", "reviewed_pass", "completed", "closed", "cancelled")
        $currentTasks = @($state.tasks | Where-Object { [string]$_.objective_id -eq $currentObjId })
        $pendingTasks = @($currentTasks | Where-Object { [string]$_.status -notin $terminalStatuses })
        $openObjective = $state.objectives | Where-Object { [string]$_.status -eq "open" } | Select-Object -First 1

        if ($currentTasks.Count -gt 0 -and $pendingTasks.Count -eq 0) {
            # Current objective fully done — advance to next roadmap entry
            $wakeupReason  = "objective_complete_advance"
            $advanceTarget = $null
            foreach ($item in $roadmap) {
                $rid   = if ($item.PSObject.Properties["id"])     { [string]$item.id     } else { "" }
                $rstat = if ($item.PSObject.Properties["status"]) { [string]$item.status } else { "" }
                if ([string]::IsNullOrWhiteSpace($rid) -or $rstat -eq "completed") { continue }
                $alreadyExists = $null -ne ($state.objectives | Where-Object { [string]$_.title -like "*$rid*" -and [string]$_.status -ne "completed" })
                if (-not $alreadyExists) { $advanceTarget = $item; break }
            }

            if ($null -ne $advanceTarget) {
                $rtitle = if ($advanceTarget.PSObject.Properties["title"]) { [string]$advanceTarget.title } else { "Self-improvement" }
                $rid    = if ($advanceTarget.PSObject.Properties["id"])    { [string]$advanceTarget.id    } else { "SELF" }
                Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Advancing to roadmap item: {0} - {1}" -f $rid, $rtitle)
                try {
                    $newObjRaw = & $TodScript new-objective `
                        -Title "${rid}: ${rtitle}" `
                        -Description "Autonomous advance from idle wake-up. Previous objective complete. Roadmap: $rid." `
                        -SuccessCriteria "First task in new objective reaches reviewed_pass." 2>&1
                    $newObj   = ($newObjRaw -join "") | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $newObjId = if ($newObj -and $newObj.PSObject.Properties["id"]) { [string]$newObj.id } `
                                elseif ($newObj -and $newObj.PSObject.Properties["local"]) { [string]$newObj.local.id } `
                                else { "" }
                    if (-not [string]::IsNullOrWhiteSpace($newObjId)) {
                        $null = & $TodScript add-task `
                            -ObjectiveId $newObjId `
                            -Title "Initial scoping and planning for $rid" `
                            -Description "Decompose '$rtitle' into steps. Review existing code, identify gaps, plan implementation." `
                            -Scope "scripts/, tod/" `
                            -AcceptanceCriteria "Scoping complete; at least one follow-on implementation task added to this objective." 2>&1
                        $actionTaken = "created_objective_$newObjId"
                        $IdleWakeupState.last_objective_advanced = $rid
                        Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Created objective {0} and first task for {1}." -f $newObjId, $rid)
                    }
                } catch {
                    Write-Warning ("[TOD-LISTENER][IDLE-WAKEUP] Failed to create roadmap objective: {0}" -f $_.Exception.Message)
                }
            } else {
                $wakeupReason = "self_improve_roadmap_exhausted"
            }
        }

        # Self-improvement when no MIM work is pending
        if ([string]::IsNullOrWhiteSpace($actionTaken) -and $null -ne $openObjective) {
            $existingTitles = @($state.tasks | Where-Object { [string]$_.objective_id -eq [string]$openObjective.id } | ForEach-Object { [string]$_.title })
            $selfTask = $script:SelfImprovementTasks | Where-Object {
                $t = [string]$_.title
                -not ($existingTitles | Where-Object { [string]$_ -like "*$($t.Substring(0, [math]::Min(40, $t.Length)))*" })
            } | Select-Object -First 1

            if ($null -ne $selfTask -and -not [string]::IsNullOrWhiteSpace([string]$IdleWakeupState.last_self_task_id)) {
                $lastCreatedTitle = ($state.tasks | Where-Object { [string]$_.id -eq [string]$IdleWakeupState.last_self_task_id } | Select-Object -ExpandProperty title -First 1)
                if ([string]::Equals([string]$selfTask.title, $lastCreatedTitle, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $selfTask = $null
                }
            }

            if ($null -ne $selfTask) {
                $wakeupReason = "self_improve"
                Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] No pending MIM work. Creating self-improvement task: {0}" -f [string]$selfTask.title)
                try {
                    $taskRaw = & $TodScript add-task `
                        -ObjectiveId ([string]$openObjective.id) `
                        -Title ([string]$selfTask.title) `
                        -Description ("Autonomous self-improvement task created by idle wake-up after {0}s of inactivity." -f $idleSec) `
                        -Scope ([string]$selfTask.scope) `
                        -AcceptanceCriteria ([string]$selfTask.criteria) 2>&1
                    $newTask   = ($taskRaw -join "") | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $newTaskId = if ($newTask -and $newTask.PSObject.Properties["id"]) { [string]$newTask.id } else { "" }
                    if (-not [string]::IsNullOrWhiteSpace($newTaskId)) {
                        $IdleWakeupState.last_self_task_id = $newTaskId
                        $actionTaken = "created_self_task_$newTaskId"
                        Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Self-improvement task created: {0}" -f $newTaskId)
                    }
                } catch {
                    Write-Warning ("[TOD-LISTENER][IDLE-WAKEUP] Failed to create self-improvement task: {0}" -f $_.Exception.Message)
                }
            } else {
                $wakeupReason = "self_improve_no_candidates"
                Write-Host "[TOD-LISTENER][IDLE-WAKEUP] No eligible self-improvement tasks remaining. Waiting for MIM."
            }
        }
    }

    # Persist wakeup state and emit event file
    $IdleWakeupState.last_wakeup_at     = (Get-Date).ToUniversalTime().ToString("o")
    $IdleWakeupState.last_wakeup_reason = $wakeupReason
    $IdleWakeupState.wakeup_count       = [int]$IdleWakeupState.wakeup_count + 1
    Write-JsonFile -PathValue $IdleWakeupStatePath -Payload $IdleWakeupState

    $idleEventPath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($IdleWakeupStatePath), "TOD_IDLE_WAKEUP_EVENT.latest.json")
    Write-JsonFile -PathValue $idleEventPath -Payload ([pscustomobject]@{
        generated_at  = (Get-Date).ToUniversalTime().ToString("o")
        source        = "tod-idle-wakeup-v1"
        idle_sec      = $idleSec
        threshold_sec = $IdleThreshold
        reason        = $wakeupReason
        action_taken  = $actionTaken
        wakeup_count  = [int]$IdleWakeupState.wakeup_count
    })
}

function New-QuarantineState {
    param($ExistingState)

    return [pscustomobject]@{
        quarantined_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["quarantined_request_id"]) { [string]$ExistingState.quarantined_request_id } else { "" }
        quarantine_applied_at  = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["quarantine_applied_at"])  { [string]$ExistingState.quarantine_applied_at  } else { "" }
        fail_cycle_count       = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["fail_cycle_count"])       { [int]$ExistingState.fail_cycle_count           } else { 0 }
        last_fail_request_id   = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_fail_request_id"])   { [string]$ExistingState.last_fail_request_id    } else { "" }
    }
}

function Get-CoordinationPriority {
    param([Parameter(Mandatory = $true)][int]$EscalationLevel)

    switch ($EscalationLevel) {
        { $_ -le 1 } { return "P0" }
        2 { return "P0-ESC-1" }
        3 { return "P0-ESC-2" }
        default { return "P0-CRITICAL" }
    }
}

function Get-DateOrMinValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [datetime]::MinValue
    }

    try {
        return [datetime]::Parse([string]$Value).ToUniversalTime()
    }
    catch {
        return [datetime]::MinValue
    }
}

function Update-ListenerHeartbeat {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][string]$CycleStartedAt,
        [string]$RequestId = "",
        [string]$RequestSignature = "",
        [switch]$MarkProcessed
    )

    if ($MarkProcessed) {
        if (-not [string]::IsNullOrWhiteSpace($RequestId)) {
            $State.last_processed_request_id = $RequestId
        }
        if (-not [string]::IsNullOrWhiteSpace($RequestSignature)) {
            $State.last_processed_request_signature = $RequestSignature
        }
        $State.last_execution_at = (Get-Date).ToUniversalTime().ToString("o")
    }

    $State.last_cycle_at = $CycleStartedAt
    Write-JsonFile -PathValue $StatePath -Payload $State
}

function Get-RequestSignature {
    param([Parameter(Mandatory = $true)][string]$RequestPath)

    if (-not (Test-Path -Path $RequestPath)) {
        return ""
    }

    try {
        return [string](Get-FileHash -Path $RequestPath -Algorithm SHA256).Hash
    }
    catch {
        return ""
    }
}

function Get-RequestIdentifier {
    param($Request)

    if ($null -eq $Request) { return "" }

    foreach ($field in @("request_id", "task_id", "id", "correlation_id")) {
        if ($Request.PSObject.Properties[$field] -and -not [string]::IsNullOrWhiteSpace([string]$Request.$field)) {
            return [string]$Request.$field
        }
    }

    if ($Request.PSObject.Properties["generated_at"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.generated_at)) {
        return [string]$Request.generated_at
    }

    return ""
}

function Get-UtcNowString {
    return (Get-Date).ToUniversalTime().ToString("o")
}

function Sync-LocalObjectiveFromRequest {
    param([Parameter(Mandatory = $true)]$Request)

    $requestedObjective = Get-ExpectedObjectiveFromRequest -Request $Request
    if ([string]::IsNullOrWhiteSpace($requestedObjective)) {
        return [pscustomobject]@{
            changed = $false
            objective_id = ""
            reason = "request_objective_missing"
        }
    }

    $nextActionsPath = Get-LocalPath -PathValue "shared_state/next_actions.json"
    $nextActions = Read-JsonFileIfExists -PathValue $nextActionsPath
    $currentObjectiveInProgress = ""
    if ($nextActions -and $nextActions.PSObject.Properties["current_objective_in_progress"] -and -not [string]::IsNullOrWhiteSpace([string]$nextActions.current_objective_in_progress)) {
        $currentObjectiveInProgress = Get-ExpectedObjectiveFromRequest -Request ([pscustomobject]@{ objective_id = [string]$nextActions.current_objective_in_progress })
    }
    if (-not [string]::IsNullOrWhiteSpace($currentObjectiveInProgress) -and -not [string]::Equals($requestedObjective, $currentObjectiveInProgress, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            changed = $false
            objective_id = $requestedObjective
            reason = "objective_mismatch_ignored"
        }
    }

    $statePath = Get-LocalPath -PathValue "tod/data/state.json"
    $state = Read-JsonFileIfExists -PathValue $statePath
    if ($null -eq $state) {
        return [pscustomobject]@{
            changed = $false
            objective_id = $requestedObjective
            reason = "state_unavailable"
        }
    }

    if (-not $state.PSObject.Properties["objectives"]) {
        $state | Add-Member -NotePropertyName objectives -NotePropertyValue @() -Force
    }

    $objectives = @($state.objectives)
    $existing = @($objectives | Where-Object { [string]$_.id -eq $requestedObjective } | Select-Object -First 1)
    $updatedAt = Get-UtcNowString
    $changed = $false

    $title = if ($Request.PSObject.Properties["title"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.title)) {
        [string]$Request.title
    }
    else {
        "Objective $requestedObjective - MIM synchronized objective"
    }

    $description = if ($Request.PSObject.Properties["scope"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.scope)) {
        [string]$Request.scope
    }
    elseif ($Request.PSObject.Properties["description"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.description)) {
        [string]$Request.description
    }
    else {
        "Synchronized from MIM request $($Request.task_id)."
    }

    $constraints = @()
    if ($Request.PSObject.Properties["constraints"] -and $null -ne $Request.constraints) {
        $constraints = @($Request.constraints | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $successCriteria = @()
    if ($Request.PSObject.Properties["acceptance_criteria"] -and $null -ne $Request.acceptance_criteria) {
        $successCriteria = @($Request.acceptance_criteria | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if (@($existing).Count -eq 0) {
        $newObjective = [pscustomobject]@{
            id = $requestedObjective
            title = $title
            description = $description
            priority = if ($Request.PSObject.Properties["priority"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.priority)) { [string]$Request.priority } else { "high" }
            constraints = @($constraints)
            success_criteria = @($successCriteria)
            status = "open"
            created_at = $updatedAt
            updated_at = $updatedAt
        }
        $state.objectives = @($objectives) + @($newObjective)
        $changed = $true
    }
    else {
        $objective = $existing[0]
        if ($objective.PSObject.Properties["status"] -and [string]::Equals([string]$objective.status, "completed", [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                changed = $false
                objective_id = $requestedObjective
                reason = "objective_completed_ignored"
            }
        }
        if (-not [string]::Equals([string]$objective.title, $title, [System.StringComparison]::Ordinal)) {
            $objective.title = $title
            $changed = $true
        }
        if (-not [string]::Equals([string]$objective.description, $description, [System.StringComparison]::Ordinal)) {
            $objective.description = $description
            $changed = $true
        }
        if ($successCriteria.Count -gt 0) {
            $objective.success_criteria = @($successCriteria)
            $changed = $true
        }
        if ($constraints.Count -gt 0) {
            $objective.constraints = @($constraints)
            $changed = $true
        }
        if ($changed) {
            $objective.updated_at = $updatedAt
        }
    }

    if ($changed) {
        Write-JsonFile -PathValue $statePath -Payload $state -Depth 100
    }

    return [pscustomobject]@{
        changed = $changed
        objective_id = $requestedObjective
        reason = if ($changed) { "objective_upserted" } else { "already_current" }
    }
}

function New-SshConnections {
    param(
        [Parameter(Mandatory = $true)][string]$HostAlias,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password
    )

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        throw "Posh-SSH is not installed. Install-Module -Name Posh-SSH -Scope CurrentUser"
    }
    Import-Module Posh-SSH -ErrorAction Stop | Out-Null

    $resolvedHost = Resolve-SshHostAlias -RemoteHost $HostAlias
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($UserName, $securePassword)

    $sshSession = New-SSHSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000
    $sftpSession = New-SFTPSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000

    return [pscustomobject]@{
        host_alias = $HostAlias
        resolved_host = $resolvedHost
        ssh = $sshSession
        sftp = $sftpSession
    }
}

function Close-SshConnections {
    param($Connections)

    if ($null -eq $Connections) { return }

    try {
        if ($Connections.sftp) {
            Remove-SFTPSession -SessionId ([int]$Connections.sftp.SessionId) | Out-Null
        }
    }
    catch {
    }

    try {
        if ($Connections.ssh) {
            Remove-SSHSession -SessionId ([int]$Connections.ssh.SessionId) | Out-Null
        }
    }
    catch {
    }
}

function Download-RemoteFile {
    param(
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [switch]$Required
    )

    try {
        $destinationDir = Split-Path -Parent $LocalPath
        if (-not [string]::IsNullOrWhiteSpace($destinationDir) -and -not (Test-Path -Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }

        Get-SFTPItem -SessionId ([int]$Connections.sftp.SessionId) -Path $RemotePath -Destination $destinationDir -Force -ErrorAction Stop | Out-Null
        return (Test-Path -Path $LocalPath -PathType Leaf)
    }
    catch {
        if ($Required) {
            throw
        }
        return $false
    }
}

function Upload-LocalFile {
    param(
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemoteDir
    )

    Set-SFTPItem -SessionId ([int]$Connections.sftp.SessionId) -Path $LocalPath -Destination $RemoteDir -Force -ErrorAction Stop | Out-Null
}

function Write-RemoteFileFromText {
    param(
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $remoteDir = [string](Split-Path -Path $RemotePath -Parent)
    $remoteDir = $remoteDir -replace "\\", "/"
    $remoteName = [string](Split-Path -Path $RemotePath -Leaf)
    if ([string]::IsNullOrWhiteSpace($remoteDir) -or [string]::IsNullOrWhiteSpace($remoteName)) {
        throw "Invalid remote path: $RemotePath"
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "tod-mim-listener"
    if (-not (Test-Path -Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    $tempPath = Join-Path $tempDir $remoteName
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $normalizedContent = ([string]$Content) -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($tempPath, $normalizedContent, $utf8NoBom)
        Set-SFTPItem -SessionId ([int]$Connections.sftp.SessionId) -Path $tempPath -Destination $remoteDir -Force -ErrorAction Stop | Out-Null
    }
    finally {
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Publish-TriggerAck {
    param(
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$RequestId
    )

    $triggerAck = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        source = "shared-trigger-ack-v1"
        status = "acknowledged"
        acknowledges = $RequestId
    }
    Write-JsonFile -PathValue $LocalPath -Payload $triggerAck
    $triggerAckJson = Get-Content -Path $LocalPath -Raw
    Write-RemoteFileFromText -Connections $Connections -RemotePath $RemotePath -Content $triggerAckJson
}

function Invoke-RequestExecution {
    param(
        [Parameter(Mandatory = $true)][string]$TodScriptAbs,
        [Parameter(Mandatory = $true)]$Request
    )

    $action = "get-state-bus"
    if ($Request.PSObject.Properties["tod_action"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.tod_action)) {
        $action = [string]$Request.tod_action
    }
    elseif ($Request.PSObject.Properties["action"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.action)) {
        $action = [string]$Request.action
    }

    $top = 10
    if ($Request.PSObject.Properties["top"] -and $null -ne $Request.top) {
        try { $top = [int]$Request.top } catch { $top = 10 }
    }

    $startUtc = (Get-Date).ToUniversalTime().ToString("o")

    # For get-state-bus: always return lightweight; TOD state.json is too large
    # to deserialize safely in-process. Any action that would load the full state
    # file is blocked here to protect listener memory.
    if ([string]::Equals($action, "get-state-bus", [System.StringComparison]::OrdinalIgnoreCase)) {
        $endUtc = (Get-Date).ToUniversalTime().ToString("o")
        $sizeMiB = ""
        try {
            $sf = Get-Item -Path (Join-Path (Split-Path -Parent $PSScriptRoot) "tod/data/state.json") -ErrorAction Stop
            $sizeMiB = [math]::Round(($sf.Length / 1MB), 2)
        } catch {}
        return [pscustomobject]@{
            ok = $true
            action = $action
            execution_mode = "lightweight_guard"
            started_at = $startUtc
            completed_at = $endUtc
            output = ("get-state-bus: lightweight success (in-process state read bypassed{0})" -f $(if ($sizeMiB) { "; state.json={0} MiB" -f $sizeMiB } else { "" }))
            error = ""
        }
    }

    try {
        $raw = & $TodScriptAbs -Action $action -Top $top 2>&1
        $endUtc = (Get-Date).ToUniversalTime().ToString("o")

        return [pscustomobject]@{
            ok = $true
            action = $action
            execution_mode = "direct_script_success"
            started_at = $startUtc
            completed_at = $endUtc
            output = [string]($raw | Out-String)
            error = ""
        }
    }
    catch {
        $endUtc = (Get-Date).ToUniversalTime().ToString("o")
        return [pscustomobject]@{
            ok = $false
            action = $action
            execution_mode = "direct_script_exception"
            started_at = $startUtc
            completed_at = $endUtc
            output = ""
            error = [string]$_.Exception.Message
        }
    }
}

function Test-AlignmentEquivalent {
    param(
        [string]$Actual,
        [string]$Expected
    )

    $actualNorm = ([string]$Actual).Trim().ToLowerInvariant()
    $expectedNorm = ([string]$Expected).Trim().ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($expectedNorm)) {
        return $true
    }

    if ($actualNorm -eq $expectedNorm) {
        return $true
    }

    if ($expectedNorm -eq "aligned" -and @("aligned", "in_sync") -contains $actualNorm) {
        return $true
    }

    return $false
}

function Get-ExpectedObjectiveFromRequest {
    param($Request)

    if ($null -eq $Request) {
        return ""
    }

    if ($Request.PSObject.Properties["objective_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.objective_id)) {
        $objectiveText = ([string]$Request.objective_id).Trim()
        $numericObjective = [regex]::Match($objectiveText, '(?i)(?:^objective-(?<objective>\d+)$|^(?<objective>\d+)$)')
        if ($numericObjective.Success) {
            return [string]$numericObjective.Groups['objective'].Value
        }
        return $objectiveText
    }

    if ($Request.PSObject.Properties["task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.task_id)) {
        $match = [regex]::Match([string]$Request.task_id, '^objective-(?<objective>\d+)-task-\d+$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return [string]$match.Groups['objective'].Value
        }
    }

    return ""
}

function Get-ReviewGateResult {
    param(
        $IntegrationStatus,
        $GoOrder,
        $Request,
        [string]$RequestId
    )

    $expectedCompatible = $true
    $expectedAlignment = "aligned"
    $expectedObjective = Get-ExpectedObjectiveFromRequest -Request $Request
    $expectedTod = $expectedObjective
    $expectedMim = $expectedObjective

    if ($GoOrder -and $GoOrder.PSObject.Properties["success_gate"] -and $null -ne $GoOrder.success_gate) {
        $gate = $GoOrder.success_gate
        if ($gate.PSObject.Properties["compatible"]) { $expectedCompatible = [bool]$gate.compatible }
        if ($gate.PSObject.Properties["objective_alignment_status"]) { $expectedAlignment = [string]$gate.objective_alignment_status }
        if ($gate.PSObject.Properties["tod_current_objective"]) { $expectedTod = [string]$gate.tod_current_objective }
        if ($gate.PSObject.Properties["mim_objective_active"]) { $expectedMim = [string]$gate.mim_objective_active }
    }

    $actualCompatible = if ($IntegrationStatus) { [bool]$IntegrationStatus.compatible } else { $false }
    $actualAlignment = if ($IntegrationStatus) { [string]$IntegrationStatus.objective_alignment.status } else { "" }
    $actualTod = if ($IntegrationStatus) { [string]$IntegrationStatus.objective_alignment.tod_current_objective } else { "" }
    $actualMim = if ($IntegrationStatus) { [string]$IntegrationStatus.objective_alignment.mim_objective_active } else { "" }
    $refreshFailure = if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties["mim_refresh"] -and $IntegrationStatus.mim_refresh.PSObject.Properties["failure_reason"]) { [string]$IntegrationStatus.mim_refresh.failure_reason } else { "missing" }

    $checks = @(
        [pscustomobject]@{ name = "compatible"; expected = $expectedCompatible; actual = $actualCompatible; passed = ($actualCompatible -eq $expectedCompatible) },
        [pscustomobject]@{ name = "objective_alignment"; expected = $expectedAlignment; actual = $actualAlignment; passed = (Test-AlignmentEquivalent -Actual $actualAlignment -Expected $expectedAlignment) },
        [pscustomobject]@{ name = "tod_current_objective"; expected = $expectedTod; actual = $actualTod; passed = ([string]$actualTod -eq [string]$expectedTod) },
        [pscustomobject]@{ name = "mim_objective_active"; expected = $expectedMim; actual = $actualMim; passed = ([string]$actualMim -eq [string]$expectedMim) },
        [pscustomobject]@{ name = "mim_refresh_failure_reason_empty"; expected = ""; actual = $refreshFailure; passed = ([string]::IsNullOrWhiteSpace($refreshFailure)) }
    )

    $allPassed = (@($checks | Where-Object { -not [bool]$_.passed }).Count -eq 0)

    return [pscustomobject]@{
        request_id = $RequestId
        passed = $allPassed
        expected = [pscustomobject]@{
            compatible = $expectedCompatible
            objective_alignment_status = $expectedAlignment
            tod_current_objective = $expectedTod
            mim_objective_active = $expectedMim
            mim_refresh_failure_reason = ""
        }
        actual = [pscustomobject]@{
            compatible = $actualCompatible
            objective_alignment_status = $actualAlignment
            tod_current_objective = $actualTod
            mim_objective_active = $actualMim
            mim_refresh_failure_reason = $refreshFailure
        }
        checks = @($checks)
    }
}

function Invoke-OptionalValidator {
    param(
        [string]$ValidatorAbs,
        [string]$RequestId,
        [string]$RequestPath,
        [string]$GoOrderPath,
        [string]$ReviewDecisionPath,
        [string]$IntegrationStatusPath,
        [string]$ResultPath
    )

    if ([string]::IsNullOrWhiteSpace($ValidatorAbs)) {
        return [pscustomobject]@{
            attempted = $false
            passed = $true
            message = "validator_not_configured"
            output = ""
        }
    }

    if (-not (Test-Path -Path $ValidatorAbs)) {
        return [pscustomobject]@{
            attempted = $true
            passed = $false
            message = "validator_script_not_found"
            output = $ValidatorAbs
        }
    }

    try {
        # Run validator out-of-process so any large-file read or exception inside
        # it cannot take down the listener or corrupt the main result packet.
        $raw = powershell -NoProfile -ExecutionPolicy Bypass -File $ValidatorAbs -RequestId $RequestId -RequestPath $RequestPath -GoOrderPath $GoOrderPath -ReviewDecisionPath $ReviewDecisionPath -IntegrationStatusPath $IntegrationStatusPath -ResultPath $ResultPath 2>&1
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }
        if ($exitCode -ne 0) {
            return [pscustomobject]@{
                attempted = $true
                passed = $false
                message = "validator_failed"
                output = [string]($raw | Out-String)
            }
        }
        return [pscustomobject]@{
            attempted = $true
            passed = $true
            message = "validator_passed"
            output = [string]($raw | Out-String)
        }
    }
    catch {
        return [pscustomobject]@{
            attempted = $true
            passed = $false
            message = "validator_failed"
            output = [string]$_.Exception.Message
        }
    }
}

$envAbs = Get-LocalPath -PathValue $EnvFile
$syncScriptAbs = Get-LocalPath -PathValue $SyncScriptPath
$todScriptAbs = Get-LocalPath -PathValue $TodScriptPath
$validatorAbs = if ([string]::IsNullOrWhiteSpace($ValidatorScriptPath)) { "" } else { Get-LocalPath -PathValue $ValidatorScriptPath }
$stageAbs = Get-LocalPath -PathValue $StageDir
$listenerStatePath = Join-Path $stageAbs "listener_state.json"

if (-not (Test-Path -Path $syncScriptAbs)) { throw "Sync script not found: $syncScriptAbs" }
if (-not (Test-Path -Path $todScriptAbs)) { throw "TOD script not found: $todScriptAbs" }
if (-not (Test-Path -Path $envAbs)) { throw "Env file not found: $envAbs" }

New-Item -ItemType Directory -Path $stageAbs -Force | Out-Null

$hostAlias = Get-DotEnvValue -Path $envAbs -Name "MIM_SSH_HOST"
if ([string]::IsNullOrWhiteSpace($hostAlias)) { $hostAlias = "mim" }
$userName = Get-DotEnvValue -Path $envAbs -Name "MIM_SSH_USER"
if ([string]::IsNullOrWhiteSpace($userName)) { $userName = "testpilot" }
$portText = Get-DotEnvValue -Path $envAbs -Name "MIM_SSH_PORT"
$port = 22
if (-not [string]::IsNullOrWhiteSpace($portText)) {
    $parsed = 0
    if ([int]::TryParse($portText, [ref]$parsed) -and $parsed -gt 0) {
        $port = $parsed
    }
}
$password = Get-DotEnvValue -Path $envAbs -Name "MIM_SSH_PASSWORD"
if ([string]::IsNullOrWhiteSpace($password) -or $password -eq "CHANGE_ME") {
    throw "Set MIM_SSH_PASSWORD in $envAbs"
}

$publishStatus = $true
if ($PSBoundParameters.ContainsKey("PublishIntegrationStatus")) {
    $publishStatus = [bool]$PublishIntegrationStatus
}

$localRequestPath = Join-Path $stageAbs "MIM_TOD_TASK_REQUEST.latest.json"
$localGoOrderPath = Join-Path $stageAbs "MIM_TOD_GO_ORDER.latest.json"
$localReviewPath = Join-Path $stageAbs "MIM_TOD_REVIEW_DECISION.latest.json"
$localAckPath = Join-Path $stageAbs "TOD_MIM_TASK_ACK.latest.json"
$localResultPath = Join-Path $stageAbs "TOD_MIM_TASK_RESULT.latest.json"
$localJournalPath = Join-Path $stageAbs "TOD_LOOP_JOURNAL.latest.json"
$localRemoteStatusFile = Join-Path $stageAbs "TOD_INTEGRATION_STATUS.latest.json"
$localTriggerAckPath = Join-Path $stageAbs "TOD_TO_MIM_TRIGGER_ACK.latest.json"
$localRegressionStallPath = Join-Path $stageAbs "TOD_REGRESSION_STALL_STATE.latest.json"
$localStallAlertPath = Join-Path $stageAbs "TOD_MIM_STALL_ALERT.latest.json"
$localCoordinationRequestPath = Join-Path $stageAbs "TOD_MIM_COORDINATION_REQUEST.latest.json"
$localCoordinationAckPath = Join-Path $stageAbs "MIM_TOD_COORDINATION_ACK.latest.json"
$localCoordinationEscalationStatePath = Join-Path $stageAbs "TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json"
$localQuarantineStatePath = Join-Path $stageAbs "TOD_MIM_QUARANTINE_STATE.latest.json"
$localIdleWakeupStatePath  = Join-Path $stageAbs "TOD_IDLE_WAKEUP_STATE.latest.json"
$currentBuildStatePath = Get-LocalPath -PathValue "shared_state/current_build_state.json"

$remoteRequestPath = ("{0}/MIM_TOD_TASK_REQUEST.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteGoOrderPath = ("{0}/MIM_TOD_GO_ORDER.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteReviewPath = ("{0}/MIM_TOD_REVIEW_DECISION.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteAckPath = ("{0}/TOD_MIM_TASK_ACK.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteResultPath = ("{0}/TOD_MIM_TASK_RESULT.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteStatusPath = ("{0}/TOD_INTEGRATION_STATUS.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteJournalPath = ("{0}/TOD_LOOP_JOURNAL.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteTriggerAckPath = ("{0}/TOD_TO_MIM_TRIGGER_ACK.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteStallAlertPath = ("{0}/TOD_MIM_STALL_ALERT.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteCoordinationRequestPath = ("{0}/TOD_MIM_COORDINATION_REQUEST.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteCoordinationAckPath = ("{0}/MIM_TOD_COORDINATION_ACK.latest.json" -f $RemoteRoot.TrimEnd('/'))

$listenerState = New-ListenerState -ExistingState (Read-JsonFileIfExists -PathValue $listenerStatePath)
$regressionStallState = New-RegressionStallState -ExistingState (Read-JsonFileIfExists -PathValue $localRegressionStallPath)
$coordinationEscalationState = New-CoordinationEscalationState -ExistingState (Read-JsonFileIfExists -PathValue $localCoordinationEscalationStatePath)
$quarantineState = New-QuarantineState -ExistingState (Read-JsonFileIfExists -PathValue $localQuarantineStatePath)
$idleWakeupState  = New-IdleWakeupState  -ExistingState (Read-JsonFileIfExists -PathValue $localIdleWakeupStatePath)

Write-Host ("[TOD-LISTENER] Started. version={0} host={1} root={2} poll={3}s run_once={4}" -f $scriptVersion, $hostAlias, $RemoteRoot, $PollSeconds, [bool]$RunOnce)
$lastSkipLogId = ""

while ($true) {
    $cycleStartedAt = (Get-Date).ToUniversalTime().ToString("o")
    $connections = $null
    Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt

    try {
        $connections = New-SshConnections -HostAlias $hostAlias -UserName $userName -Port $port -Password $password

        $requestExists = Download-RemoteFile -Connections $connections -RemotePath $remoteRequestPath -LocalPath $localRequestPath
        $null = Download-RemoteFile -Connections $connections -RemotePath $remoteGoOrderPath -LocalPath $localGoOrderPath
        $null = Download-RemoteFile -Connections $connections -RemotePath $remoteReviewPath -LocalPath $localReviewPath
        $coordinationAckExists = Download-RemoteFile -Connections $connections -RemotePath $remoteCoordinationAckPath -LocalPath $localCoordinationAckPath
        if ($coordinationAckExists) {
            $coordinationAck = Read-JsonFileIfExists -PathValue $localCoordinationAckPath
            if ($null -ne $coordinationAck) {
                $acknowledged = $false
                $ackStatus = ""
                $ackDecision = ""
                $ackReason = ""
                $ackGeneratedAt = if ($coordinationAck.PSObject.Properties["generated_at"]) { [string]$coordinationAck.generated_at } else { "" }
                if ($coordinationAck.PSObject.Properties["acknowledged"]) {
                    $acknowledged = [bool]$coordinationAck.acknowledged
                }
                $ackRequestId = if ($coordinationAck.PSObject.Properties["request_id"]) { [string]$coordinationAck.request_id } else { "" }

                if ($coordinationAck.PSObject.Properties["decision"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.decision)) {
                    $ackDecision = [string]$coordinationAck.decision
                }
                if ($coordinationAck.PSObject.Properties["reason"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.reason)) {
                    $ackReason = [string]$coordinationAck.reason
                }

                if ($coordinationAck.PSObject.Properties["coordination"] -and $coordinationAck.coordination) {
                    if ($coordinationAck.coordination.PSObject.Properties["status"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.coordination.status)) {
                        $ackStatus = [string]$coordinationAck.coordination.status
                    }
                    if ([string]::IsNullOrWhiteSpace($ackDecision) -and $coordinationAck.coordination.PSObject.Properties["phase"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.coordination.phase)) {
                        $ackDecision = [string]$coordinationAck.coordination.phase
                    }
                    if ([string]::IsNullOrWhiteSpace($ackReason) -and $coordinationAck.coordination.PSObject.Properties["detail"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.coordination.detail)) {
                        $ackReason = [string]$coordinationAck.coordination.detail
                    }
                }

                if ([string]::IsNullOrWhiteSpace($ackRequestId) -and $coordinationAck.PSObject.Properties["task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.task_id)) {
                    $ackRequestId = [string]$coordinationAck.task_id
                }

                if (-not $acknowledged) {
                    if ([string]::Equals($ackStatus, "acknowledged", [System.StringComparison]::OrdinalIgnoreCase) -or
                        [string]::Equals($ackStatus, "accepted", [System.StringComparison]::OrdinalIgnoreCase) -or
                        [string]::Equals($ackDecision, "acknowledged", [System.StringComparison]::OrdinalIgnoreCase)) {
                        $acknowledged = $true
                    }
                }

                $coordinationEscalationState.last_ack_request_id = $ackRequestId
                $coordinationEscalationState.last_ack_generated_at = $ackGeneratedAt
                $coordinationEscalationState.last_ack_status = $ackStatus
                $coordinationEscalationState.last_ack_decision = $ackDecision
                $coordinationEscalationState.last_ack_reason = $ackReason

                $pendingRequestId = [string]$coordinationEscalationState.pending_request_id

                if ($acknowledged -and -not [string]::IsNullOrWhiteSpace($ackRequestId) -and
                    ([string]::IsNullOrWhiteSpace($pendingRequestId) -or [string]::Equals($ackRequestId, $pendingRequestId, [System.StringComparison]::OrdinalIgnoreCase))) {
                    $coordinationEscalationState.pending_request_id = ""
                    $coordinationEscalationState.pending_since = ""
                    $coordinationEscalationState.last_emit_at = ""
                    $coordinationEscalationState.last_emitted_level = 0
                    $coordinationEscalationState.emit_count = 0
                    $coordinationEscalationState.last_ack_request_id = $ackRequestId
                    $coordinationEscalationState.last_acknowledged_at = if ($coordinationAck.PSObject.Properties["acknowledged_at"]) { [string]$coordinationAck.acknowledged_at } else { (Get-Date).ToUniversalTime().ToString("o") }
                }

                Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState
            }
        }

        # Always auto-resolve stale stalled-regression coordination when regression is green,
        # even during polling cycles that skip task execution.
        $loopRegressionSnapshot = Get-RegressionSnapshot -CurrentBuildStatePath $currentBuildStatePath
        if ($loopRegressionSnapshot.available -and [int]$loopRegressionSnapshot.failed -le 0) {
            $hasPendingEscalation = (-not [string]::IsNullOrWhiteSpace([string]$coordinationEscalationState.pending_request_id)) -or ([int]$coordinationEscalationState.emit_count -gt 0)
            $hasStaleRequestArtifact = Test-Path -Path $localCoordinationRequestPath
            if ($hasPendingEscalation -or $hasStaleRequestArtifact) {
                $loopResolveReason = "Regression failures are zero; stale coordination escalation has been auto-resolved."
                Clear-CoordinationEscalationState -State $coordinationEscalationState -Reason $loopResolveReason
                Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState

                $loopCoordinationResolved = [pscustomobject]@{
                    generated_at = (Get-Date).ToUniversalTime().ToString("o")
                    source = "tod-mim-coordination-request-v1"
                    status = "resolved"
                    priority = "none"
                    escalation_level = 0
                    request_id = [string]$coordinationEscalationState.last_ack_request_id
                    objective_id = "objective-75"
                    issue_code = "stalled_regression_no_delta_resolved"
                    issue_summary = "Regression is green; prior stalled-regression escalation is closed automatically."
                    evidence = [pscustomobject]@{
                        failed = [int]$loopRegressionSnapshot.failed
                        total = [int]$loopRegressionSnapshot.total
                        regression_signature = [string]$loopRegressionSnapshot.signature
                    }
                    requested_action = "none"
                    resolution_reason = $loopResolveReason
                    resolved_at = (Get-Date).ToUniversalTime().ToString("o")
                }
                Write-JsonFile -PathValue $localCoordinationRequestPath -Payload $loopCoordinationResolved
                try {
                    $loopCoordinationResolvedJson = Get-Content -Path $localCoordinationRequestPath -Raw
                    Write-RemoteFileFromText -Connections $connections -RemotePath $remoteCoordinationRequestPath -Content $loopCoordinationResolvedJson
                }
                catch {
                    Write-Warning ("[TOD-LISTENER] Unable to publish loop-level resolved coordination status to remote: {0}" -f $_.Exception.Message)
                }
            }
        }

        if (-not $requestExists) {
            Write-Host "[TOD-LISTENER] No task request packet found."
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath -TodScript $todScriptAbs -SyncScript $syncScriptAbs -IdleThreshold $IdleWakeupSeconds -Cooldown $IdleWakeupCooldownSeconds -RunOnce:$RunOnce
            if ($RunOnce) { break }
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        $request = Read-JsonFileIfExists -PathValue $localRequestPath
        if ($null -eq $request) {
            Write-Host "[TOD-LISTENER] Request file exists but is not valid JSON."
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            if ($RunOnce) { break }
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        $requestId = Get-RequestIdentifier -Request $request
        if ([string]::IsNullOrWhiteSpace($requestId)) {
            $requestId = "REQ-" + ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())
        }

        $objectiveSync = Sync-LocalObjectiveFromRequest -Request $request
        if ([bool]$objectiveSync.changed) {
            Write-Host ("[TOD-LISTENER] Local objective synchronized to {0}." -f [string]$objectiveSync.objective_id)
        }

        $requestSignature = Get-RequestSignature -RequestPath $localRequestPath
        $goOrderSignature = Get-RequestSignature -RequestPath $localGoOrderPath
        $triggerEventSignature = ((@(
                    [string]$requestId,
                    [string]$requestSignature,
                    [string]$goOrderSignature
                ) -join "|").ToLowerInvariant())
        $lastTriggerEventSignature = if ($listenerState.PSObject.Properties["last_trigger_event_signature"]) { [string]$listenerState.last_trigger_event_signature } else { "" }

        $triggerEventChanged = -not [string]::Equals($triggerEventSignature, $lastTriggerEventSignature, [System.StringComparison]::OrdinalIgnoreCase)
        if ($triggerEventChanged) {
            Publish-TriggerAck -Connections $connections -LocalPath $localTriggerAckPath -RemotePath $remoteTriggerAckPath -RequestId $requestId
            $listenerState.last_trigger_event_signature = $triggerEventSignature
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
        }

        # Quarantine guard: if this request_id has been quarantined after repeated failures, skip execution entirely.
        if (-not [string]::IsNullOrWhiteSpace([string]$quarantineState.quarantined_request_id) -and
            [string]::Equals($requestId, [string]$quarantineState.quarantined_request_id, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ("[TOD-LISTENER] Request {0} is QUARANTINED after {1} consecutive fail cycles. Skipping." -f $requestId, [int]$quarantineState.fail_cycle_count)
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath -TodScript $todScriptAbs -SyncScript $syncScriptAbs -IdleThreshold $IdleWakeupSeconds -Cooldown $IdleWakeupCooldownSeconds -RunOnce:$RunOnce
            if ($RunOnce) { break }
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        $lastProcessedSignature = if ($listenerState.PSObject.Properties["last_processed_request_signature"]) { [string]$listenerState.last_processed_request_signature } else { "" }

        if ([string]::Equals($requestId, [string]$listenerState.last_processed_request_id, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::IsNullOrWhiteSpace($requestSignature) -and
            [string]::Equals($requestSignature, $lastProcessedSignature, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [bool]$objectiveSync.changed) {
            if (-not [string]::Equals($lastSkipLogId, $requestId, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host ("[TOD-LISTENER] Request {0} already processed. Skipping." -f $requestId)
                $lastSkipLogId = $requestId
            }
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath -TodScript $todScriptAbs -SyncScript $syncScriptAbs -IdleThreshold $IdleWakeupSeconds -Cooldown $IdleWakeupCooldownSeconds -RunOnce:$RunOnce
            if ($RunOnce) { break }
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        $lastSkipLogId = ""

        $goOrder = Read-JsonFileIfExists -PathValue $localGoOrderPath
        $reviewDecision = Read-JsonFileIfExists -PathValue $localReviewPath
        $goAllowed = $true
        if ($null -ne $goOrder -and -not $ProcessWithoutGoOrder) {
            if ($goOrder.PSObject.Properties["authorization"] -and -not [string]::IsNullOrWhiteSpace([string]$goOrder.authorization)) {
                $goAllowed = ([string]$goOrder.authorization).Trim().ToLowerInvariant() -eq "go"
            }
            elseif ($goOrder.PSObject.Properties["allow_execute"]) {
                $goAllowed = [bool]$goOrder.allow_execute
            }
            elseif ($goOrder.PSObject.Properties["go"]) {
                $goAllowed = [bool]$goOrder.go
            }
        }

        $ack = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            source = "tod-mim-task-ack-v1"
            request_id = $requestId
            status = if ($goAllowed) { "accepted" } else { "deferred_waiting_go_order" }
            objective = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
            task = if ($request.PSObject.Properties["task_id"]) { [string]$request.task_id } else { "" }
            note = if ($goAllowed) { "Request acknowledged and queued for execution." } else { "Request acknowledged; waiting for GO order." }
        }
        Write-JsonFile -PathValue $localAckPath -Payload $ack

        $ackJson = Get-Content -Path $localAckPath -Raw
        Write-RemoteFileFromText -Connections $connections -RemotePath $remoteAckPath -Content $ackJson

        if (-not $goAllowed) {
            Write-Host ("[TOD-LISTENER] Request {0} acknowledged; waiting for GO order." -f $requestId)
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            if ($RunOnce) { break }
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        Write-Host ("[TOD-LISTENER] Executing request {0}..." -f $requestId)
        $execution = Invoke-RequestExecution -TodScriptAbs $todScriptAbs -Request $request

        $syncError = ""
        try {
            # Run sync as a child process so any OOM inside it cannot crash the listener.
            $syncOut = powershell -NoProfile -ExecutionPolicy Bypass -File $syncScriptAbs -RefreshMimContextFromSsh -MimSshHost $hostAlias -MimSshSharedRoot $RemoteRoot -MimSshStagingRoot $StageDir 2>&1
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                $syncError = ("sync exited {0}" -f $LASTEXITCODE)
                Write-Warning ("[TOD-LISTENER] Shared-state sync exited {0}; continuing with latest available status." -f $LASTEXITCODE)
            }
        }
        catch {
            $syncError = [string]$_.Exception.Message
            Write-Warning ("[TOD-LISTENER] Shared-state sync failed; continuing with latest available status: {0}" -f $syncError)
        }

        if ($publishStatus) {
            Copy-Item -Path (Get-LocalPath -PathValue "shared_state/integration_status.json") -Destination $localRemoteStatusFile -Force
            Upload-LocalFile -Connections $connections -LocalPath $localRemoteStatusFile -RemoteDir $RemoteRoot
        }

        $integrationStatusPath = Get-LocalPath -PathValue "shared_state/integration_status.json"
        $integrationStatus = Read-JsonFileIfExists -PathValue $integrationStatusPath
        $reviewGate = Get-ReviewGateResult -IntegrationStatus $integrationStatus -GoOrder $goOrder -Request $request -RequestId $requestId

        # Snapshot per-cycle inputs so validator cannot drift to a newer packet.
        $validatorSuffix = ([guid]::NewGuid().ToString("N"))
        $validatorRequestPath = Join-Path $stageAbs ("MIM_TOD_TASK_REQUEST.validator.{0}.json" -f $validatorSuffix)
        $validatorGoOrderPath = Join-Path $stageAbs ("MIM_TOD_GO_ORDER.validator.{0}.json" -f $validatorSuffix)
        $validatorReviewPath = Join-Path $stageAbs ("MIM_TOD_REVIEW_DECISION.validator.{0}.json" -f $validatorSuffix)
        $validatorResultPath = Join-Path $stageAbs ("TOD_MIM_TASK_RESULT.validator.{0}.json" -f $validatorSuffix)
        Write-JsonFile -PathValue $validatorRequestPath -Payload $request
        if ($null -ne $goOrder) {
            Write-JsonFile -PathValue $validatorGoOrderPath -Payload $goOrder
        }
        if ($null -ne $reviewDecision) {
            Write-JsonFile -PathValue $validatorReviewPath -Payload $reviewDecision
        }

        $validatorResult = Invoke-OptionalValidator -ValidatorAbs $validatorAbs -RequestId $requestId -RequestPath $validatorRequestPath -GoOrderPath $validatorGoOrderPath -ReviewDecisionPath $validatorReviewPath -IntegrationStatusPath $integrationStatusPath -ResultPath $validatorResultPath

        $regressionSnapshot = Get-RegressionSnapshot -CurrentBuildStatePath $currentBuildStatePath
        if ($regressionSnapshot.available) {
            if ([int]$regressionSnapshot.failed -le 0) {
                $regressionStallState.unchanged_cycles = 0
            }
            else {
                $sameSignature = [string]::Equals([string]$regressionSnapshot.signature, [string]$regressionStallState.last_signature, [System.StringComparison]::OrdinalIgnoreCase)
                $sameRequest = [string]::Equals([string]$requestId, [string]$regressionStallState.last_request_id, [System.StringComparison]::OrdinalIgnoreCase)
                if ($sameSignature -and -not $sameRequest) {
                    $regressionStallState.unchanged_cycles = [int]$regressionStallState.unchanged_cycles + 1
                }
                else {
                    $regressionStallState.unchanged_cycles = 0
                }
            }

            $regressionStallState.last_signature = [string]$regressionSnapshot.signature
            $regressionStallState.last_request_id = [string]$requestId
            $regressionStallState.last_update_at = (Get-Date).ToUniversalTime().ToString("o")
            Write-JsonFile -PathValue $localRegressionStallPath -Payload $regressionStallState

            if ([int]$regressionSnapshot.failed -le 0) {
                $autoResolveReason = "Regression failures are zero; stale coordination escalation has been auto-resolved."

                if (-not [string]::IsNullOrWhiteSpace([string]$coordinationEscalationState.pending_request_id) -or
                    [int]$coordinationEscalationState.emit_count -gt 0 -or
                    (Test-Path -Path $localCoordinationRequestPath)) {
                    Clear-CoordinationEscalationState -State $coordinationEscalationState -Reason $autoResolveReason -RequestId $requestId
                    Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState

                    $coordinationResolved = [pscustomobject]@{
                        generated_at = (Get-Date).ToUniversalTime().ToString("o")
                        source = "tod-mim-coordination-request-v1"
                        status = "resolved"
                        priority = "none"
                        escalation_level = 0
                        request_id = [string]$requestId
                        objective_id = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
                        issue_code = "stalled_regression_no_delta_resolved"
                        issue_summary = "Regression is green; prior stalled-regression escalation is closed automatically."
                        evidence = [pscustomobject]@{
                            failed = [int]$regressionSnapshot.failed
                            total = [int]$regressionSnapshot.total
                            regression_signature = [string]$regressionSnapshot.signature
                        }
                        requested_action = "none"
                        resolution_reason = $autoResolveReason
                        resolved_at = (Get-Date).ToUniversalTime().ToString("o")
                    }
                    Write-JsonFile -PathValue $localCoordinationRequestPath -Payload $coordinationResolved
                    try {
                        $coordinationResolvedJson = Get-Content -Path $localCoordinationRequestPath -Raw
                        Write-RemoteFileFromText -Connections $connections -RemotePath $remoteCoordinationRequestPath -Content $coordinationResolvedJson
                    }
                    catch {
                        Write-Warning ("[TOD-LISTENER] Unable to publish resolved coordination status to remote: {0}" -f $_.Exception.Message)
                    }
                }
            }
        }

        $stalledByNoDelta = ($regressionSnapshot.available -and [int]$regressionSnapshot.failed -gt 0 -and [int]$regressionStallState.unchanged_cycles -ge [Math]::Max(1, [int]$RegressionNoDeltaThreshold))

        $resultPacket = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            source = "tod-mim-task-result-v1"
            listener_version = $scriptVersion
            request_id = $requestId
            status = if ($execution.ok -and [bool]$reviewGate.passed -and [bool]$validatorResult.passed) { "completed" } else { "failed" }
            action = [string]$execution.action
            execution_mode = if ($execution.PSObject.Properties["execution_mode"]) { [string]$execution.execution_mode } else { "unknown" }
            started_at = [string]$execution.started_at
            completed_at = [string]$execution.completed_at
            error = [string]$execution.error
            request_action_raw = if ($request.PSObject.Properties["action"] -and $null -ne $request.action) { [string]$request.action } else { "" }
            request_tod_action_raw = if ($request.PSObject.Properties["tod_action"] -and $null -ne $request.tod_action) { [string]$request.tod_action } else { "" }
            mim_review_decision = if ($reviewDecision -and $reviewDecision.PSObject.Properties["decision"]) { [string]$reviewDecision.decision } else { "" }
            review_gate = $reviewGate
            validator = $validatorResult
            integration = [pscustomobject]@{
                compatible = if ($integrationStatus) { [bool]$integrationStatus.compatible } else { $false }
                alignment_status = if ($integrationStatus) { [string]$integrationStatus.objective_alignment.status } else { "unknown" }
                tod_current_objective = if ($integrationStatus) { [string]$integrationStatus.objective_alignment.tod_current_objective } else { "" }
                mim_objective_active = if ($integrationStatus) { [string]$integrationStatus.objective_alignment.mim_objective_active } else { "" }
                mim_refresh_failure_reason = if ($integrationStatus -and $integrationStatus.PSObject.Properties["mim_refresh"] -and $integrationStatus.mim_refresh.PSObject.Properties["failure_reason"]) { [string]$integrationStatus.mim_refresh.failure_reason } else { "" }
            }
            output_preview = if ([string]::IsNullOrWhiteSpace([string]$execution.output)) { "" } else { ([string]$execution.output).Substring(0, [Math]::Min(1200, ([string]$execution.output).Length)) }
        }

        if ($regressionSnapshot.available) {
            $resultPacket | Add-Member -NotePropertyName regression_snapshot -NotePropertyValue $regressionSnapshot -Force
        }

        if ($stalledByNoDelta) {
            $stallMsg = ("stalled_regression_no_delta: regression snapshot unchanged for {0} consecutive cycles while failures remain ({1}/{2} failed)." -f [int]$regressionStallState.unchanged_cycles, [int]$regressionSnapshot.failed, [int]$regressionSnapshot.total)
            $resultPacket.status = "failed"
            $resultPacket.error = $stallMsg
            $resultPacket | Add-Member -NotePropertyName stall_guard -NotePropertyValue ([pscustomobject]@{
                issue_code = "stalled_regression_no_delta"
                unchanged_cycles = [int]$regressionStallState.unchanged_cycles
                threshold = [int]$RegressionNoDeltaThreshold
                remediation_hint = "Switch from get-state-bus loop to a remediation task that runs or fixes failing regression tests."
            }) -Force

            $stallAlert = [pscustomobject]@{
                generated_at = (Get-Date).ToUniversalTime().ToString("o")
                source = "tod-mim-stall-alert-v1"
                request_id = [string]$requestId
                objective_id = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
                issue_code = "stalled_regression_no_delta"
                issue_detail = $stallMsg
                unchanged_cycles = [int]$regressionStallState.unchanged_cycles
                threshold = [int]$RegressionNoDeltaThreshold
                regression_snapshot = $regressionSnapshot
                requested_action = "dispatch_remediation_task"
            }
            Write-JsonFile -PathValue $localStallAlertPath -Payload $stallAlert
            $stallAlertJson = Get-Content -Path $localStallAlertPath -Raw
            Write-RemoteFileFromText -Connections $connections -RemotePath $remoteStallAlertPath -Content $stallAlertJson

            $utcNow = (Get-Date).ToUniversalTime()
            if (-not [string]::Equals([string]$coordinationEscalationState.pending_request_id, [string]$requestId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $coordinationEscalationState.pending_request_id = [string]$requestId
                $coordinationEscalationState.pending_since = $utcNow.ToString("o")
                $coordinationEscalationState.last_emit_at = ""
                $coordinationEscalationState.last_emitted_level = 0
                $coordinationEscalationState.emit_count = 0
            }

            $pendingSinceUtc = Get-DateOrMinValue -Value ([string]$coordinationEscalationState.pending_since)
            if ($pendingSinceUtc -eq [datetime]::MinValue) {
                $pendingSinceUtc = $utcNow
                $coordinationEscalationState.pending_since = $pendingSinceUtc.ToString("o")
            }

            $elapsedMinutes = 0
            try {
                $elapsedMinutes = [int][math]::Floor((New-TimeSpan -Start $pendingSinceUtc -End $utcNow).TotalMinutes)
            }
            catch {
                $elapsedMinutes = 0
            }

            $targetEscalationLevel = [math]::Max(1, ([int][math]::Floor($elapsedMinutes / 5) + 1))
            $lastEmitUtc = Get-DateOrMinValue -Value ([string]$coordinationEscalationState.last_emit_at)
            $minutesSinceLastEmit = if ($lastEmitUtc -eq [datetime]::MinValue) { 9999 } else { [int][math]::Floor((New-TimeSpan -Start $lastEmitUtc -End $utcNow).TotalMinutes) }
            $shouldEmitCoordination = ($coordinationEscalationState.last_emitted_level -lt $targetEscalationLevel) -or ($minutesSinceLastEmit -ge 5)

            if ($shouldEmitCoordination) {
                $coordinationRequest = [pscustomobject]@{
                    generated_at = $utcNow.ToString("o")
                    source = "tod-mim-coordination-request-v1"
                    priority = Get-CoordinationPriority -EscalationLevel $targetEscalationLevel
                    escalation_level = [int]$targetEscalationLevel
                    request_id = [string]$requestId
                    objective_id = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
                    issue_code = "stalled_regression_no_delta"
                    issue_summary = "TOD requests immediate remediation dispatch because regression has stalled with no delta while failures remain."
                    evidence = [pscustomobject]@{
                        unchanged_cycles = [int]$regressionStallState.unchanged_cycles
                        failed = [int]$regressionSnapshot.failed
                        total = [int]$regressionSnapshot.total
                        regression_signature = [string]$regressionSnapshot.signature
                    }
                    requested_action = "dispatch_remediation_task"
                    required_ack = [pscustomobject]@{
                        ack_file = "MIM_TOD_COORDINATION_ACK.latest.json"
                        ack_fields = @("acknowledged", "acknowledged_at", "request_id", "decision", "reason", "target_dispatch_task_id")
                        timeout_seconds = 300
                    }
                }
                Write-JsonFile -PathValue $localCoordinationRequestPath -Payload $coordinationRequest
                $coordinationJson = Get-Content -Path $localCoordinationRequestPath -Raw
                Write-RemoteFileFromText -Connections $connections -RemotePath $remoteCoordinationRequestPath -Content $coordinationJson

                $coordinationEscalationState.last_emit_at = $utcNow.ToString("o")
                $coordinationEscalationState.last_emitted_level = [int]$targetEscalationLevel
                $coordinationEscalationState.emit_count = [int]$coordinationEscalationState.emit_count + 1
                Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState

                $resultPacket | Add-Member -NotePropertyName coordination_request -NotePropertyValue $coordinationRequest -Force
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($syncError)) {
            $resultPacket | Add-Member -NotePropertyName sync_warning -NotePropertyValue $syncError -Force
        }
        Write-JsonFile -PathValue $localResultPath -Payload $resultPacket

        $resultJson = Get-Content -Path $localResultPath -Raw
        Write-RemoteFileFromText -Connections $connections -RemotePath $remoteResultPath -Content $resultJson

        Remove-Item -Path $validatorRequestPath -ErrorAction SilentlyContinue
        Remove-Item -Path $validatorGoOrderPath -ErrorAction SilentlyContinue
        Remove-Item -Path $validatorReviewPath -ErrorAction SilentlyContinue

        Publish-TriggerAck -Connections $connections -LocalPath $localTriggerAckPath -RemotePath $remoteTriggerAckPath -RequestId $requestId

        Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt -RequestId $requestId -RequestSignature $requestSignature -MarkProcessed

        $journalExisting = Read-JsonFileIfExists -PathValue $localJournalPath
        $entries = @()
        if ($null -eq $journalExisting) {
            $entries = @()
        }
        elseif ($journalExisting -is [System.Array]) {
            $entries = @($journalExisting)
        }
        elseif ($journalExisting.PSObject.Properties["entries"]) {
            $entries = @($journalExisting.entries)
        }

        $entries += [pscustomobject]@{
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
            request_id = $requestId
            ack_status = [string]$ack.status
            execution_status = [string]$resultPacket.status
            action = [string]$resultPacket.action
            integration_alignment = if ($integrationStatus) { [string]$integrationStatus.objective_alignment.status } else { "unknown" }
            integration_compatible = if ($integrationStatus) { [bool]$integrationStatus.compatible } else { $false }
            review_gate_passed = [bool]$reviewGate.passed
            validator_passed = [bool]$validatorResult.passed
            regression_failed = if ($regressionSnapshot.available) { [int]$regressionSnapshot.failed } else { -1 }
            regression_signature = if ($regressionSnapshot.available) { [string]$regressionSnapshot.signature } else { "" }
            stalled_no_delta = [bool]$stalledByNoDelta
        }
        if (@($entries).Count -gt 200) {
            $entries = @($entries | Select-Object -Last 200)
        }

        $journal = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            source = "tod-loop-journal-v1"
            entries = @($entries)
        }
        Write-JsonFile -PathValue $localJournalPath -Payload $journal

        $journalJson = Get-Content -Path $localJournalPath -Raw
        Write-RemoteFileFromText -Connections $connections -RemotePath $remoteJournalPath -Content $journalJson

        # Quarantine fail-cycle tracking: increment counter on fail; apply quarantine after threshold; clear on success.
        if ([string]$resultPacket.status -eq "failed") {
            if ([string]::Equals($requestId, [string]$quarantineState.last_fail_request_id, [System.StringComparison]::OrdinalIgnoreCase)) {
                $quarantineState.fail_cycle_count = [int]$quarantineState.fail_cycle_count + 1
            } else {
                $quarantineState.last_fail_request_id = $requestId
                $quarantineState.fail_cycle_count = 1
            }
            if ([int]$quarantineState.fail_cycle_count -ge [int]$QuarantineFailCycleThreshold) {
                $quarantineState.quarantined_request_id = $requestId
                $quarantineState.quarantine_applied_at = (Get-Date).ToUniversalTime().ToString("o")
                Write-Host ("[TOD-LISTENER] QUARANTINE applied to request {0} after {1} consecutive fail cycles." -f $requestId, [int]$quarantineState.fail_cycle_count)
            }
        } else {
            if ([string]::Equals($requestId, [string]$quarantineState.quarantined_request_id, [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals($requestId, [string]$quarantineState.last_fail_request_id, [System.StringComparison]::OrdinalIgnoreCase)) {
                $quarantineState.quarantined_request_id = ""
                $quarantineState.quarantine_applied_at = ""
                $quarantineState.fail_cycle_count = 0
                $quarantineState.last_fail_request_id = ""
            }
        }
        Write-JsonFile -PathValue $localQuarantineStatePath -Payload $quarantineState

        Write-Host ("[TOD-LISTENER] Processed request {0} status={1}" -f $requestId, [string]$resultPacket.status)

        if ($RunOnce) { break }
    }
    catch {
        Write-Warning ("[TOD-LISTENER] Cycle error: {0}" -f [string]$_.Exception.Message)
        Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
        if ($FailOnError) {
            throw
        }
        if ($RunOnce) { break }
    }
    finally {
        Close-SshConnections -Connections $connections
    }

    Start-Sleep -Seconds $PollSeconds
}

Write-Host "[TOD-LISTENER] Stopped."
