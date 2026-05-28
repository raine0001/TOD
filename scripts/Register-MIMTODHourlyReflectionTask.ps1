param(
    [string]$TaskName = 'MIM-TOD-HourlyReflection',
    [int]$IntervalMinutes = 60,
    [switch]$RunNow,
    [switch]$VisibleWindow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'Invoke-MIMTODHourlyReflection.ps1'

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing script: $scriptPath"
}
if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw 'ScheduledTasks module is unavailable on this host.'
}

$windowPrelude = if ($VisibleWindow) { '' } else { '-WindowStyle Hidden ' }
$args = @(
    $windowPrelude + '-NoProfile -ExecutionPolicy Bypass',
    '-File', ('"' + $scriptPath + '"')
) -join ' '

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args -WorkingDirectory $repoRoot
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Hourly MIM/TOD reflection: health, blockers, follow-on objectives, and next action summary.' -Force | Out-Null

if ($RunNow) {
    Start-ScheduledTask -TaskName $TaskName
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
[pscustomobject]@{
    ok = [bool]$task
    task_name = $TaskName
    state = if ($task) { [string]$task.State } else { 'missing' }
    interval_minutes = $IntervalMinutes
    run_now = [bool]$RunNow
    script_path = $scriptPath
} | ConvertTo-Json -Depth 5
