param(
    [string]$TaskName = 'TOD-Autonomy-Guard',
    [int]$IntervalMinutes = 15,
    [string]$DailyTaskName = 'TOD-AutonomousTraining-Daily',
    [string]$DaemonTaskName = 'TOD-AutonomousTraining-IdleDaemon',
    [string]$DailyAt = '20:00',
    [string]$ConfigPath = 'tod/config/tod-config.json',
    [string]$CampaignRoot = 'tod/out/training/autonomous-campaign',
    [int]$IdleThresholdMinutes = 0,
    [int]$MimWaitMinutes = 5,
    [int]$SimulationCooldownMinutes = 0,
    [int]$SolicitationCooldownMinutes = 60,
    [int]$LongIdleProfileThresholdMinutes = 30,
    [switch]$VisibleWindow,
    [switch]$RunNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$guardScript = Join-Path $PSScriptRoot 'Invoke-TODAutonomyGuard.ps1'

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

if (-not (Test-Path -Path $guardScript)) {
    throw 'Missing guard script: ' + $guardScript
}

$resolvedConfigPath = Resolve-RepoPath -PathValue $ConfigPath
$resolvedCampaignRoot = Resolve-RepoPath -PathValue $CampaignRoot
$windowPrelude = if (-not $VisibleWindow) { '-WindowStyle Hidden ' } else { '' }
$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

$guardArgs = @(
    $windowPrelude + '-NoProfile -ExecutionPolicy Bypass',
    '-File', ('"' + $guardScript + '"'),
    '-DailyTaskName', ('"' + $DailyTaskName + '"'),
    '-DaemonTaskName', ('"' + $DaemonTaskName + '"'),
    '-DailyAt', ('"' + $DailyAt + '"'),
    '-ConfigPath', ('"' + $resolvedConfigPath + '"'),
    '-CampaignRoot', ('"' + $resolvedCampaignRoot + '"'),
    '-IdleThresholdMinutes', [string]$IdleThresholdMinutes,
    '-MimWaitMinutes', [string]$MimWaitMinutes,
    '-SimulationCooldownMinutes', [string]$SimulationCooldownMinutes,
    '-SolicitationCooldownMinutes', [string]$SolicitationCooldownMinutes,
    '-LongIdleProfileThresholdMinutes', [string]$LongIdleProfileThresholdMinutes
) -join ' '

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $guardArgs
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'TOD autonomy guard to prevent idle stalls and missed training windows' -Force | Out-Null

if ($RunNow) {
    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
    catch {
    }
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
[pscustomobject]@{
    ok = ($null -ne $task)
    task_name = $TaskName
    state = if ($task) { [string]$task.State } else { 'missing' }
    interval_minutes = $IntervalMinutes
    arguments = $guardArgs
    run_now = [bool]$RunNow
} | ConvertTo-Json -Depth 10 | Write-Output
