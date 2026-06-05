param(
    [string]$DailyTaskName = 'TOD-AutonomousTraining-Daily',
    [string]$DaemonTaskName = 'TOD-AutonomousTraining-IdleDaemon',
    [string]$GuardTaskName = 'TOD-Autonomy-Guard',
    [string]$DailyAt = '20:00',
    [string]$ConfigPath = 'tod/config/tod-config.json',
    [string]$CampaignRoot = 'tod/out/training/autonomous-campaign',
    [int]$IdleThresholdMinutes = 0,
    [int]$MimWaitMinutes = 5,
    [int]$SimulationCooldownMinutes = 0,
    [int]$SolicitationCooldownMinutes = 60,
    [int]$LongIdleProfileThresholdMinutes = 30,
    [int]$DaemonStaleMinutes = 20,
    [string]$StatusOutputPath = 'shared_state/tod_autonomy_status.latest.json',
    [string]$StudioProjectsStateUrl = 'https://mim.mimtod.com/studio/api/projects/state',
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$daemonScript = Join-Path $PSScriptRoot 'Start-TODAutonomousTrainingDaemon.ps1'
$statusScript = Join-Path $PSScriptRoot 'Write-TODCompletionStatus.ps1'
$daemonStatePath = Join-Path $repoRoot 'tod/out/training/autonomous-campaign/daemon/autonomous-training-daemon-state.json'

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
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

function Get-ElapsedMinutes {
    param([string]$WhenUtc)

    if ([string]::IsNullOrWhiteSpace($WhenUtc)) {
        return [double]::PositiveInfinity
    }

    try {
        return (((Get-Date).ToUniversalTime()) - ([datetime]::Parse($WhenUtc).ToUniversalTime())).TotalMinutes
    }
    catch {
        return [double]::PositiveInfinity
    }
}

function Get-TaskInfoSafe {
    param([Parameter(Mandatory = $true)][string]$TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $info = $task | Get-ScheduledTaskInfo
        return [pscustomobject]@{
            exists = $true
            state = [string]$task.State
            last_run_time = if ($info.LastRunTime -is [datetime]) { $info.LastRunTime } else { $null }
            next_run_time = if ($info.NextRunTime -is [datetime]) { $info.NextRunTime } else { $null }
            last_task_result = if ($null -eq $info.LastTaskResult) { $null } else { [long]$info.LastTaskResult }
        }
    }
    catch {
        return [pscustomobject]@{
            exists = $false
            state = 'missing'
            last_run_time = $null
            next_run_time = $null
            last_task_result = $null
        }
    }
}

function Invoke-DaemonRunOnce {
    $result = & $daemonScript -ConfigPath $ConfigPath -CampaignRoot $CampaignRoot -IdleThresholdMinutes $IdleThresholdMinutes -MimWaitMinutes $MimWaitMinutes -SimulationCooldownMinutes $SimulationCooldownMinutes -SolicitationCooldownMinutes $SolicitationCooldownMinutes -LongIdleProfileThresholdMinutes $LongIdleProfileThresholdMinutes -RunOnce 2>&1 | Out-String
    return $result.Trim()
}

function Invoke-StudioProjectsStateRefresh {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $null
    }

    try {
        return Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 25 -ErrorAction Stop
    }
    catch {
        throw ("studio_projects_state_refresh_failed:" + [string]$_.Exception.Message)
    }
}

function Write-Status {
    param(
        [string]$TodDidThis,
        [string]$TodNextAction,
        [string]$TodState = '',
        [string]$MimState = '',
        [string[]]$Blockers = @()
    )

    $args = @{
        DaemonStatePath = $daemonStatePath
        OutputPath = $StatusOutputPath
        DailyTaskName = $DailyTaskName
        DaemonTaskName = $DaemonTaskName
        GuardTaskName = $GuardTaskName
        TodGotThis = 'TOD autonomy guard is responsible for keeping execution moving without waiting for a human.'
        TodDidThis = $TodDidThis
        TodNextAction = $TodNextAction
        MimNextAction = 'Provide direction when responsive; TOD continues without waiting.'
        Confidence = 'confirmed'
        Blockers = $Blockers
        EmitJson = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($TodState)) {
        $args.CurrentTodState = $TodState
    }
    if (-not [string]::IsNullOrWhiteSpace($MimState)) {
        $args.CurrentMimState = $MimState
    }

    return (& $statusScript @args | Out-String).Trim()
}

$resolvedDaemonStatePath = Resolve-RepoPath -PathValue $daemonStatePath
$dailyTask = Get-TaskInfoSafe -TaskName $DailyTaskName
$daemonTask = Get-TaskInfoSafe -TaskName $DaemonTaskName
$now = Get-Date
$dailyTime = [DateTime]::ParseExact($DailyAt, 'HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
$scheduledToday = Get-Date -Hour $dailyTime.Hour -Minute $dailyTime.Minute -Second 0

$actionTaken = 'guard_check_only'
$todState = 'executing'
$blockers = @()
$projectState = $null
$projectCounts = $null

if ($now -ge $scheduledToday) {
    $ranToday = $false
    if ($dailyTask.exists -and $dailyTask.last_run_time) {
        $ranToday = ($dailyTask.last_run_time.Date -eq $now.Date)
    }

    if (-not $ranToday) {
        try {
            Start-ScheduledTask -TaskName $DailyTaskName -ErrorAction Stop
            $actionTaken = 'started_missed_daily_training'
            $todState = 'training'
        }
        catch {
            $blockers += ('failed_to_start_daily_training:' + [string]$_.Exception.Message)
        }
    }
}

$daemonState = Read-JsonFileIfExists -PathValue $resolvedDaemonStatePath
$daemonAgeMinutes = if ($daemonState) { Get-ElapsedMinutes -WhenUtc ([string]$daemonState.updated_at_utc) } else { [double]::PositiveInfinity }
if ($daemonAgeMinutes -ge $DaemonStaleMinutes) {
    try {
        $null = Invoke-DaemonRunOnce
        if ($actionTaken -eq 'guard_check_only') {
            $actionTaken = 'ran_daemon_reconciliation'
        }
    }
    catch {
        $blockers += ('failed_to_run_daemon_once:' + [string]$_.Exception.Message)
    }
}

try {
    $projectState = Invoke-StudioProjectsStateRefresh -Url $StudioProjectsStateUrl
    if ($projectState -and $projectState.PSObject.Properties['counts']) {
        $projectCounts = $projectState.counts
        $staleCount = if ($projectCounts.PSObject.Properties['stale']) { [int]$projectCounts.stale } else { 0 }
        $needsReviewCount = if ($projectCounts.PSObject.Properties['needs_review']) { [int]$projectCounts.needs_review } else { 0 }
        if (($staleCount + $needsReviewCount) -gt 0 -and $actionTaken -eq 'guard_check_only') {
            $actionTaken = 'refreshed_studio_project_stale_recovery'
        }
    }
}
catch {
    $blockers += [string]$_.Exception.Message
}

$todNextAction = 'Keep the daemon fresh, start scheduled training when due, refresh Studio project stale recovery, and continue under the no-stall rule.'
if ($projectCounts) {
    $staleCount = if ($projectCounts.PSObject.Properties['stale']) { [int]$projectCounts.stale } else { 0 }
    $needsReviewCount = if ($projectCounts.PSObject.Properties['needs_review']) { [int]$projectCounts.needs_review } else { 0 }
    $autoActions = if ($projectState -and $projectState.PSObject.Properties['auto_intervention_count']) { [int]$projectState.auto_intervention_count } else { 0 }
    $todNextAction = "Studio project guard refreshed: stale=$staleCount, needs_review=$needsReviewCount, auto_actions=$autoActions. Resolve stale rows by executing, blocking with evidence, splitting, archiving, or escalating."
}

$statusJson = Write-Status -TodDidThis $actionTaken -TodNextAction $todNextAction -TodState $todState -MimState 'unknown' -Blockers $blockers

if ($EmitJson) {
    $statusJson
}
