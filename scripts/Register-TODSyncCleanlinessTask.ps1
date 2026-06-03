param(
    [string]$TaskName = 'TOD-SyncCleanliness',
    [int]$IntervalMinutes = 15,
    [switch]$StartNow
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'Invoke-TODSyncCleanliness.ps1'

if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw 'ScheduledTasks module is unavailable on this host.'
}

$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$args = @(
    '-WindowStyle', 'Hidden',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"' + $scriptPath + '"'),
    '-RepoRoot', ('"' + $repoRoot + '"'),
    '-CleanGeneratedRuntime'
) -join ' '

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Keep TOD repo sync cleanliness healthy by suppressing generated runtime-state churn and reporting real dirty work.' -Force | Out-Null

if ($StartNow.IsPresent) {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    ok = $true
    task_name = $TaskName
    interval_minutes = $IntervalMinutes
    action = 'powershell.exe'
    arguments = $args
}
