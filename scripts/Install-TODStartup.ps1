param(
    [string]$TaskName = 'TOD-Elevated-Startup',
    [string]$WatchdogTaskName = 'TOD-Elevated-Watchdog',
    [string]$WorkspacePath = '',
    [string]$LauncherPath = '',
    [string]$ShortcutName = 'TOD Elevated',
    [int]$WatchdogIntervalMinutes = 5,
    [switch]$NoApply,
    [switch]$StartNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function New-ShortcutFile {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [string]$Description = ''
    )

    $directory = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $shortcut.Arguments = $Arguments
    }
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $shortcut.WorkingDirectory = $WorkingDirectory
    }
    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $shortcut.Description = $Description
    }
    $shortcut.Save()
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedWorkspacePath = if ([string]::IsNullOrWhiteSpace($WorkspacePath)) {
    Join-Path $repoRoot 'TOD.code-workspace'
} else {
    Resolve-RepoPath -PathValue $WorkspacePath
}
$resolvedLauncherPath = if ([string]::IsNullOrWhiteSpace($LauncherPath)) {
    Join-Path $repoRoot 'Start-TOD-Elevated.cmd'
} else {
    Resolve-RepoPath -PathValue $LauncherPath
}
$resolvedWatchdogScriptPath = Join-Path $repoRoot 'scripts\Ensure-TODRunning.ps1'

if (-not (Test-Path -LiteralPath $resolvedWorkspacePath)) {
    throw 'Workspace path not found: ' + $resolvedWorkspacePath
}
if (-not (Test-Path -LiteralPath $resolvedLauncherPath -PathType Leaf)) {
    throw 'Launcher path not found: ' + $resolvedLauncherPath
}
if (-not (Test-Path -LiteralPath $resolvedWatchdogScriptPath -PathType Leaf)) {
    throw 'Watchdog script not found: ' + $resolvedWatchdogScriptPath
}
if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw 'ScheduledTasks module is unavailable on this host.'
}

$desktopDir = [Environment]::GetFolderPath('Desktop')
$startupDir = [Environment]::GetFolderPath('Startup')
$desktopShortcutPath = Join-Path $desktopDir ($ShortcutName + '.lnk')
$startupShortcutPath = Join-Path $startupDir ($ShortcutName + '.lnk')

$launcherArguments = '"' + $resolvedWorkspacePath + '"'
$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$actionArgs = @(
    '-WindowStyle', 'Hidden',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"' + (Join-Path $repoRoot 'scripts\Start-TOD-Elevated.ps1') + '"'),
    '-WorkspacePath', ('"' + $resolvedWorkspacePath + '"')
) -join ' '

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $actionArgs
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0)
$triggers = @((New-ScheduledTaskTrigger -AtLogOn -User $currentUser))
try {
    $triggers += New-ScheduledTaskTrigger -AtStartup
}
catch {
}

$watchdogArgs = @(
    '-WindowStyle', 'Hidden',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"' + $resolvedWatchdogScriptPath + '"'),
    '-WorkspacePath', ('"' + $resolvedWorkspacePath + '"')
) -join ' '
$watchdogAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $watchdogArgs
$watchdogPrincipal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
$watchdogSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0)
$watchdogTrigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes $WatchdogIntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)

$plan = [ordered]@{
    task_name = $TaskName
    watchdog_task_name = $WatchdogTaskName
    workspace_path = $resolvedWorkspacePath
    launcher_path = $resolvedLauncherPath
    watchdog_script_path = $resolvedWatchdogScriptPath
    desktop_shortcut = $desktopShortcutPath
    startup_shortcut = $startupShortcutPath
    startup_trigger_enabled = ($triggers.Count -gt 1)
    watchdog_interval_minutes = $WatchdogIntervalMinutes
    user = $currentUser
    no_apply = [bool]$NoApply.IsPresent
}

if ($NoApply.IsPresent) {
    [pscustomobject]$plan | ConvertTo-Json -Depth 5
    return
}

New-ShortcutFile -ShortcutPath $desktopShortcutPath -TargetPath $resolvedLauncherPath -Arguments $launcherArguments -WorkingDirectory $repoRoot -Description 'Launch TOD elevated.'
New-ShortcutFile -ShortcutPath $startupShortcutPath -TargetPath $resolvedLauncherPath -Arguments $launcherArguments -WorkingDirectory $repoRoot -Description 'Launch TOD elevated at user startup.'

$registration = [ordered]@{
    ok = $false
    error = ''
    requires_elevation = $false
}
try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description 'Launch TOD elevated at logon and system startup.' -Force -ErrorAction Stop | Out-Null
    $registration.ok = $true
}
catch {
    $registration.error = [string]$_.Exception.Message
    $registration.requires_elevation = ($registration.error -match 'Access is denied|0x80070005')
}

$watchdogRegistration = [ordered]@{
    ok = $false
    error = ''
    requires_elevation = $false
}
try {
    Register-ScheduledTask -TaskName $WatchdogTaskName -Action $watchdogAction -Trigger $watchdogTrigger -Principal $watchdogPrincipal -Settings $watchdogSettings -Description 'Ensure TOD stays running and relaunch if the editor process exits.' -Force -ErrorAction Stop | Out-Null
    $watchdogRegistration.ok = $true
}
catch {
    $watchdogRegistration.error = [string]$_.Exception.Message
    $watchdogRegistration.requires_elevation = ($watchdogRegistration.error -match 'Access is denied|0x80070005')
}

if ($StartNow.IsPresent -and $registration.ok) {
    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($registration.error)) {
            $registration.error = 'Task registered but failed to start immediately: ' + [string]$_.Exception.Message
        }
    }
}

if ($StartNow.IsPresent -and $watchdogRegistration.ok) {
    try {
        Start-ScheduledTask -TaskName $WatchdogTaskName -ErrorAction Stop
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($watchdogRegistration.error)) {
            $watchdogRegistration.error = 'Watchdog task registered but failed to start immediately: ' + [string]$_.Exception.Message
        }
    }
}

$result = [ordered]@{
    plan = $plan
    desktop_shortcut_exists = (Test-Path -LiteralPath $desktopShortcutPath -PathType Leaf)
    startup_shortcut_exists = (Test-Path -LiteralPath $startupShortcutPath -PathType Leaf)
    scheduled_task = $registration
    watchdog_task = $watchdogRegistration
}

[pscustomobject]$result | ConvertTo-Json -Depth 6
