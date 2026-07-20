param(
    [string]$DaemonStatePath = 'tod/out/training/autonomous-campaign/daemon/autonomous-training-daemon-state.json',
    [string]$OutputPath = 'shared_state/tod_autonomy_status.latest.json',
    [string]$PublicRouteHealthPath = 'shared_state/tod_public_route_health.latest.json',
    [string]$TrainingStatusPath = 'shared_state/tod_training_status.latest.json',
    [string]$DailyTaskName = 'TOD-AutonomousTraining-Daily',
    [string]$DaemonTaskName = 'TOD-AutonomousTraining-IdleDaemon',
    [string]$GuardTaskName = 'TOD-Autonomy-Guard',
    [string]$TodGotThis = '',
    [string]$TodDidThis = '',
    [string]$TodNextAction = '',
    [string]$MimNextAction = '',
    [string]$CurrentTodState = '',
    [string]$CurrentMimState = '',
    [string]$Confidence = 'inferred',
    [string[]]$Blockers = @(),
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-DirectoryIfMissing -PathValue $directory
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-SecondsAgo {
    param([string]$WhenUtc)

    if ([string]::IsNullOrWhiteSpace($WhenUtc)) {
        return $null
    }

    try {
        return [math]::Max(0, [int][math]::Round((((Get-Date).ToUniversalTime()) - ([datetime]::Parse($WhenUtc).ToUniversalTime())).TotalSeconds))
    }
    catch {
        return $null
    }
}

function Get-TaskSummary {
    param([Parameter(Mandatory = $true)][string]$TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $info = $task | Get-ScheduledTaskInfo
        return [pscustomobject]@{
            task_name = $TaskName
            exists = $true
            state = [string]$task.State
            last_run_time = if ($info.LastRunTime -is [datetime]) { $info.LastRunTime.ToUniversalTime().ToString('o') } else { '' }
            next_run_time = if ($info.NextRunTime -is [datetime]) { $info.NextRunTime.ToUniversalTime().ToString('o') } else { '' }
            last_task_result = if ($null -eq $info.LastTaskResult) { $null } else { [long]$info.LastTaskResult }
        }
    }
    catch {
        return [pscustomobject]@{
            task_name = $TaskName
            exists = $false
            state = 'missing'
            last_run_time = ''
            next_run_time = ''
            last_task_result = $null
        }
    }
}

function Get-TodState {
    param(
        [AllowNull()]$DaemonState,
        [AllowNull()]$TrainingStatus,
        [AllowNull()]$DailyTask,
        [AllowNull()]$GuardTask
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentTodState)) {
        return $CurrentTodState
    }

    if ($TrainingStatus -and $TrainingStatus.PSObject.Properties['active'] -and [bool]$TrainingStatus.active) {
        return 'training'
    }

    if ($TrainingStatus -and $TrainingStatus.PSObject.Properties['state']) {
        $trainingState = [string]$TrainingStatus.state
        if ($trainingState -match 'completed') {
            return 'waiting'
        }
    }

    if ($DaemonState -and $DaemonState.PSObject.Properties['last_status']) {
        $lastStatus = [string]$DaemonState.last_status
        if ($lastStatus -match 'simulation_fallback|training') {
            return 'training'
        }
        if ($lastStatus -match 'critical_recovery') {
            return 'reconciling'
        }
        if ($lastStatus -match 'awaiting_mim_reply') {
            return 'executing'
        }
        if ($lastStatus -match 'mim_replied_actionable') {
            return 'executing'
        }
    }

    if ($DailyTask -and $DailyTask.exists -and $DailyTask.state -eq 'Running') {
        return 'training'
    }
    if ($GuardTask -and $GuardTask.exists -and $GuardTask.state -eq 'Running') {
        return 'executing'
    }

    return 'waiting'
}

function Get-EffectiveBlockers {
    param(
        [string[]]$ExplicitBlockers = @(),
        [AllowNull()]$PublicRouteHealth = $null
    )

    $allBlockers = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($ExplicitBlockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        $allBlockers.Add([string]$entry)
    }

    if ($PublicRouteHealth -and $PublicRouteHealth.PSObject.Properties['blockers']) {
        foreach ($entry in @($PublicRouteHealth.blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
            $allBlockers.Add([string]$entry)
        }
    }

    return @($allBlockers.ToArray() | Select-Object -Unique)
}

function Get-MimState {
    param([AllowNull()]$DaemonState)

    if (-not [string]::IsNullOrWhiteSpace($CurrentMimState)) {
        return $CurrentMimState
    }

    if ($DaemonState -and $DaemonState.PSObject.Properties['pending_mim_session_id'] -and -not [string]::IsNullOrWhiteSpace([string]$DaemonState.pending_mim_session_id)) {
        return 'waiting'
    }

    return 'unknown'
}

$resolvedDaemonStatePath = Resolve-RepoPath -PathValue $DaemonStatePath
$resolvedOutputPath = Resolve-RepoPath -PathValue $OutputPath
$resolvedPublicRouteHealthPath = Resolve-RepoPath -PathValue $PublicRouteHealthPath
$resolvedTrainingStatusPath = Resolve-RepoPath -PathValue $TrainingStatusPath

$daemonState = Read-JsonFileIfExists -PathValue $resolvedDaemonStatePath
$publicRouteHealth = Read-JsonFileIfExists -PathValue $resolvedPublicRouteHealthPath
$trainingStatus = Read-JsonFileIfExists -PathValue $resolvedTrainingStatusPath
$dailyTask = Get-TaskSummary -TaskName $DailyTaskName
$daemonTask = Get-TaskSummary -TaskName $DaemonTaskName
$guardTask = Get-TaskSummary -TaskName $GuardTaskName

$lastMimRequestAt = if ($daemonState -and $daemonState.PSObject.Properties['pending_mim_requested_at_utc']) { [string]$daemonState.pending_mim_requested_at_utc } else { "" }
$lastMimRequestSeconds = if ($daemonState -and -not [string]::IsNullOrWhiteSpace($lastMimRequestAt)) { Get-SecondsAgo -WhenUtc $lastMimRequestAt } else { $null }
$lastTodActionSeconds = if ($daemonState) { Get-SecondsAgo -WhenUtc ([string]$daemonState.updated_at_utc) } else { $null }

$payload = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-completion-status-v1'
    tod_got_this = if (-not [string]::IsNullOrWhiteSpace($TodGotThis)) { $TodGotThis } elseif ($daemonState) { 'Autonomy guard and daemon state are active in the repo.' } else { 'Autonomy state is not yet initialized.' }
    tod_did_this = if (-not [string]::IsNullOrWhiteSpace($TodDidThis)) { $TodDidThis } elseif ($daemonState -and $daemonState.PSObject.Properties['last_status']) { 'Latest daemon status: ' + [string]$daemonState.last_status } else { 'No daemon action has been recorded yet.' }
    tod_next_action = if (-not [string]::IsNullOrWhiteSpace($TodNextAction)) { $TodNextAction } else { 'Continue under the no-stall rule and start training if no higher-priority MIM work exists.' }
    mim_next_action = if (-not [string]::IsNullOrWhiteSpace($MimNextAction)) { $MimNextAction } else { 'Provide direction when responsive; TOD continues without waiting.' }
    current_tod_state = Get-TodState -DaemonState $daemonState -TrainingStatus $trainingStatus -DailyTask $dailyTask -GuardTask $guardTask
    current_mim_state = Get-MimState -DaemonState $daemonState
    last_mim_request_sent_seconds_ago = $lastMimRequestSeconds
    last_tod_action_observed_seconds_ago = $lastTodActionSeconds
    confidence = $Confidence
    blockers = @(Get-EffectiveBlockers -ExplicitBlockers $Blockers -PublicRouteHealth $publicRouteHealth)
    daemon_state_path = $resolvedDaemonStatePath
    daemon_state = $daemonState
    training_status_path = $resolvedTrainingStatusPath
    training_status = $trainingStatus
    public_route_health_path = $resolvedPublicRouteHealthPath
    public_route_health = $publicRouteHealth
    scheduled_tasks = [pscustomobject]@{
        daily = $dailyTask
        daemon = $daemonTask
        guard = $guardTask
    }
}

Write-Utf8NoBomJson -PathValue $resolvedOutputPath -Payload $payload -Depth 20

if ($EmitJson) {
    $payload | ConvertTo-Json -Depth 20
}
