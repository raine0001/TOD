param(
    [string]$TaskName = "TOD-Watchdog-DriftGuard",
    [int]$CheckEveryMinutes = 15,
    [int]$StaleSkewSeconds = 300,
    [ValidateSet("light", "standard", "deep")]
    [string]$ResolutionProfile = "standard",
    [string[]]$ActiveWindows = @(),
    [switch]$RestartUiOnFailure,
    [switch]$TriggerMaintenanceOnUnresolved,
    [switch]$TriggerMaintenanceOnDetection,
    [switch]$IncludeLogonTrigger,
    [switch]$VisibleWindow,
    [switch]$RunNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$driftGuardScript = Join-Path $PSScriptRoot "Invoke-TODWatchdogDriftGuard.ps1"

if (-not (Test-Path -Path $driftGuardScript)) {
    throw "Missing drift-guard script: $driftGuardScript"
}

if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "ScheduledTasks module is unavailable on this host."
}

$intervalMinutes = [Math]::Max(1, [int]$CheckEveryMinutes)
$interval = New-TimeSpan -Minutes $intervalMinutes
$duration = New-TimeSpan -Days 3650

$argParts = @(
    if (-not $VisibleWindow) { '-WindowStyle'; 'Hidden' }
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$driftGuardScript`"",
    "-StaleSkewSeconds", "$StaleSkewSeconds",
    "-AutoCorrect",
    "-EmitJson",
    "-ResolutionProfile", "$ResolutionProfile"
)

if ($RestartUiOnFailure) {
    $argParts += "-RestartUiOnFailure"
}
if ($TriggerMaintenanceOnUnresolved) {
    $argParts += "-TriggerMaintenanceOnUnresolved"
}
if ($TriggerMaintenanceOnDetection) {
    $argParts += "-TriggerMaintenanceOnDetection"
}
foreach ($window in @($ActiveWindows)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$window)) {
        $argParts += "-ActiveWindows"
        $argParts += "`"$([string]$window)`""
    }
}

$actionArgs = ($argParts -join " ")
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)

$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

$triggers = @(
    (New-ScheduledTaskTrigger -Once -At ((Get-Date).ToUniversalTime().AddMinutes(1)) -RepetitionInterval $interval -RepetitionDuration $duration)
)
if ($IncludeLogonTrigger) {
    $triggers += New-ScheduledTaskTrigger -AtLogOn -User $currentUser
}

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "TOD watchdog drift alerts with auto-correction and optional resolution triggers" -Force -ErrorAction Stop | Out-Null
}
catch {
    $message = $_.Exception.Message
    $isAccessDenied = $message -match "Access is denied|0x80070005"
    [pscustomobject]@{
        ok = $false
        task_name = $TaskName
        user = $currentUser
        requires_elevation = $isAccessDenied
        error = $message
    } | ConvertTo-Json -Depth 8 | Write-Output
    return
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -eq $task) {
    [pscustomobject]@{
        ok = $false
        task_name = $TaskName
        user = $currentUser
        requires_elevation = $false
        error = "Task registration did not produce a visible scheduled task."
    } | ConvertTo-Json -Depth 8 | Write-Output
    return
}

if ($RunNow) {
    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
    catch {
    }
}

[pscustomobject]@{
    ok = $true
    task_name = $TaskName
    user = $currentUser
    state = [string]$task.State
    check_every_minutes = $intervalMinutes
    stale_skew_seconds = $StaleSkewSeconds
    resolution_profile = $ResolutionProfile
    active_windows = @($ActiveWindows)
    restart_ui_on_failure = [bool]$RestartUiOnFailure
    trigger_maintenance_on_unresolved = [bool]$TriggerMaintenanceOnUnresolved
    trigger_maintenance_on_detection = [bool]$TriggerMaintenanceOnDetection
    include_logon_trigger = [bool]$IncludeLogonTrigger
    visible_window = [bool]$VisibleWindow
    run_now_requested = [bool]$RunNow
    action = [pscustomobject]@{
        execute = "powershell.exe"
        arguments = $actionArgs
    }
} | ConvertTo-Json -Depth 8 | Write-Output
