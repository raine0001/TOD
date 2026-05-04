param(
    [string]$DailyTaskName = 'TOD-AutonomousTraining-Daily',
    [string]$DaemonTaskName = 'TOD-AutonomousTraining-IdleDaemon',
    [string]$GuardTaskName = 'TOD-Autonomy-Guard',
    [string]$DailyAt = '20:00',
    [string]$ConfigPath = 'tod/config/tod-config.json',
    [string]$CampaignRoot = 'tod/out/training/autonomous-campaign',
    [int]$TotalDays = 12,
    [int]$IdleThresholdMinutes = 0,
    [int]$MimWaitMinutes = 5,
    [int]$SimulationCooldownMinutes = 0,
    [int]$SolicitationCooldownMinutes = 60,
    [int]$LongIdleProfileThresholdMinutes = 30,
    [int]$GuardIntervalMinutes = 15,
    [switch]$VisibleWindow,
    [switch]$RunDaemonNow,
    [switch]$RunGuardNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dailyScript = Join-Path $PSScriptRoot 'Invoke-TODAutonomousTrainingCampaignDaily.ps1'
$daemonScript = Join-Path $PSScriptRoot 'Start-TODAutonomousTrainingDaemon.ps1'
$guardRegistrationScript = Join-Path $PSScriptRoot 'Register-TODAutonomyGuardTask.ps1'

if (-not (Test-Path -Path $dailyScript)) {
    throw 'Missing daily campaign script: ' + $dailyScript
}
if (-not (Test-Path -Path $daemonScript)) {
    throw 'Missing autonomous daemon script: ' + $daemonScript
}
if (-not (Test-Path -Path $guardRegistrationScript)) {
    throw 'Missing autonomy guard registration script: ' + $guardRegistrationScript
}
if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw 'ScheduledTasks module is unavailable on this host.'
}

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

$resolvedConfigPath = Resolve-RepoPath -PathValue $ConfigPath
$resolvedCampaignRoot = Resolve-RepoPath -PathValue $CampaignRoot
if (-not (Test-Path -Path $resolvedConfigPath)) {
    throw 'Config not found: ' + $resolvedConfigPath
}

$windowPrelude = if (-not $VisibleWindow) { '-WindowStyle Hidden ' } else { '' }
$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

$dailyArgs = @(
    $windowPrelude + '-NoProfile -ExecutionPolicy Bypass',
    '-File', ('"' + $dailyScript + '"'),
    '-ConfigPath', ('"' + $resolvedConfigPath + '"'),
    '-CampaignRoot', ('"' + $resolvedCampaignRoot + '"'),
    '-TotalDays', [string]$TotalDays,
    '-TaskName', ('"' + $DailyTaskName + '"'),
    '-AutoDisableTask',
    '-EmitJson'
) -join ' '

$daemonArgs = @(
    $windowPrelude + '-NoProfile -ExecutionPolicy Bypass',
    '-File', ('"' + $daemonScript + '"'),
    '-ConfigPath', ('"' + $resolvedConfigPath + '"'),
    '-CampaignRoot', ('"' + $resolvedCampaignRoot + '"'),
    '-IdleThresholdMinutes', [string]$IdleThresholdMinutes,
    '-MimWaitMinutes', [string]$MimWaitMinutes,
    '-SimulationCooldownMinutes', [string]$SimulationCooldownMinutes,
    '-SolicitationCooldownMinutes', [string]$SolicitationCooldownMinutes,
    '-LongIdleProfileThresholdMinutes', [string]$LongIdleProfileThresholdMinutes,
    '-IgnoreCampaignCompletion', 'true',
    '-StartupHealthCheck'
) -join ' '

$dailyAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $dailyArgs
$daemonAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $daemonArgs

$dailySettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 12)
$daemonSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0)

$dailyTime = [DateTime]::ParseExact($DailyAt, 'HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
$dailyTriggers = @((New-ScheduledTaskTrigger -Daily -At $dailyTime))
$daemonTriggers = @((New-ScheduledTaskTrigger -AtLogOn -User $currentUser))
try {
    $daemonTriggers += New-ScheduledTaskTrigger -AtStartup
}
catch {
}

$dailyRegistration = [pscustomobject]@{
    ok = $false
    requires_elevation = $false
    error = ''
}
try {
    Register-ScheduledTask -TaskName $DailyTaskName -Action $dailyAction -Trigger $dailyTriggers -Principal $principal -Settings $dailySettings -Description 'TOD 12-day autonomous daily training campaign' -Force -ErrorAction Stop | Out-Null
    $dailyRegistration.ok = $true
}
catch {
    $dailyRegistration.error = [string]$_.Exception.Message
    $dailyRegistration.requires_elevation = ($dailyRegistration.error -match 'Access is denied|0x80070005')
}

$daemonRegistration = [pscustomobject]@{
    ok = $false
    startup_trigger_enabled = ($daemonTriggers.Count -gt 1)
    requires_elevation = $false
    error = ''
}
try {
    Register-ScheduledTask -TaskName $DaemonTaskName -Action $daemonAction -Trigger $daemonTriggers -Principal $principal -Settings $daemonSettings -Description 'TOD autonomous idle daemon with MIM-first solicitation and simulation fallback' -Force -ErrorAction Stop | Out-Null
    $daemonRegistration.ok = $true
}
catch {
    $daemonRegistration.error = [string]$_.Exception.Message
    $daemonRegistration.requires_elevation = ($daemonRegistration.error -match 'Access is denied|0x80070005')

    try {
        $daemonFallbackTriggers = @((New-ScheduledTaskTrigger -AtLogOn -User $currentUser))
        Register-ScheduledTask -TaskName $DaemonTaskName -Action $daemonAction -Trigger $daemonFallbackTriggers -Principal $principal -Settings $daemonSettings -Description 'TOD autonomous idle daemon with MIM-first solicitation and simulation fallback' -Force -ErrorAction Stop | Out-Null
        $daemonRegistration.ok = $true
        $daemonRegistration.startup_trigger_enabled = $false
        $daemonRegistration.requires_elevation = $false
        $daemonRegistration.error = ''
    }
    catch {
        $daemonRegistration.error = [string]$_.Exception.Message
        $daemonRegistration.requires_elevation = ($daemonRegistration.error -match 'Access is denied|0x80070005')
    }
}

if ($RunDaemonNow) {
    try {
        Start-ScheduledTask -TaskName $DaemonTaskName -ErrorAction SilentlyContinue
    }
    catch {
    }
}

$guardRegistration = [pscustomobject]@{
    ok = $false
    error = ''
}
try {
    $guardArgs = @{
        TaskName = $GuardTaskName
        IntervalMinutes = $GuardIntervalMinutes
        DailyTaskName = $DailyTaskName
        DaemonTaskName = $DaemonTaskName
        DailyAt = $DailyAt
        ConfigPath = $resolvedConfigPath
        CampaignRoot = $resolvedCampaignRoot
        IdleThresholdMinutes = $IdleThresholdMinutes
        MimWaitMinutes = $MimWaitMinutes
        SimulationCooldownMinutes = $SimulationCooldownMinutes
        SolicitationCooldownMinutes = $SolicitationCooldownMinutes
        LongIdleProfileThresholdMinutes = $LongIdleProfileThresholdMinutes
    }
    if ($VisibleWindow.IsPresent) {
        $guardArgs.VisibleWindow = $true
    }
    if ($RunGuardNow.IsPresent) {
        $guardArgs.RunNow = $true
    }

    $guardRaw = & $guardRegistrationScript @guardArgs
    $guardExitCode = $null
    if (Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue) {
        $guardExitCode = $LASTEXITCODE
    }
    if ($guardExitCode -is [int] -and [int]$guardExitCode -ne 0) {
        throw ('guard registration returned exit code ' + [int]$LASTEXITCODE)
    }
    $guardRegistration.ok = $true
}
catch {
    $guardRegistration.error = [string]$_.Exception.Message
}

$dailyTask = Get-ScheduledTask -TaskName $DailyTaskName -ErrorAction SilentlyContinue
$daemonTask = Get-ScheduledTask -TaskName $DaemonTaskName -ErrorAction SilentlyContinue
$guardTask = Get-ScheduledTask -TaskName $GuardTaskName -ErrorAction SilentlyContinue

[pscustomobject]@{
    ok = [bool]$dailyRegistration.ok -and [bool]$daemonRegistration.ok
    user = $currentUser
    daily_task = [pscustomobject]@{
        task_name = $DailyTaskName
        state = if ($dailyTask) { [string]$dailyTask.State } else { 'missing' }
        daily_at = $DailyAt
        registration_ok = [bool]$dailyRegistration.ok
        requires_elevation = [bool]$dailyRegistration.requires_elevation
        error = [string]$dailyRegistration.error
        arguments = $dailyArgs
    }
    daemon_task = [pscustomobject]@{
        task_name = $DaemonTaskName
        state = if ($daemonTask) { [string]$daemonTask.State } else { 'missing' }
        idle_threshold_minutes = $IdleThresholdMinutes
        mim_wait_minutes = $MimWaitMinutes
        simulation_cooldown_minutes = $SimulationCooldownMinutes
        solicitation_cooldown_minutes = $SolicitationCooldownMinutes
        long_idle_profile_threshold_minutes = $LongIdleProfileThresholdMinutes
        run_daemon_now = [bool]$RunDaemonNow
        registration_ok = [bool]$daemonRegistration.ok
        startup_trigger_enabled = [bool]$daemonRegistration.startup_trigger_enabled
        requires_elevation = [bool]$daemonRegistration.requires_elevation
        error = [string]$daemonRegistration.error
        arguments = $daemonArgs
    }
    guard_task = [pscustomobject]@{
        task_name = $GuardTaskName
        state = if ($guardTask) { [string]$guardTask.State } else { 'missing' }
        interval_minutes = $GuardIntervalMinutes
        run_guard_now = [bool]$RunGuardNow
        registration_ok = [bool]$guardRegistration.ok
        error = [string]$guardRegistration.error
    }
    campaign_root = $resolvedCampaignRoot
    total_days = $TotalDays
} | ConvertTo-Json -Depth 10 | Write-Output