param(
    [string]$TaskName = "TOD-SelfHealth-Maintenance",
    [string[]]$DailyAt = @("08:00", "14:00", "20:00"),
    [ValidateSet("light", "standard", "deep")]
    [string]$Profile = "standard",
    [int]$FallbackWarningThresholdRuns = 6,
    [int]$FallbackWarningWindowHours = 48,
    [switch]$RestartUiOnFailure,
    [switch]$RefreshAgentMimReadiness,
    [switch]$IncludeLogonTrigger,
    [switch]$VisibleWindow,
    [switch]$RunNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$maintenanceScript = Join-Path $PSScriptRoot "Invoke-TODSelfHealthMaintenance.ps1"

if (-not (Test-Path -Path $maintenanceScript)) {
    throw "Missing maintenance script: $maintenanceScript"
}

if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "ScheduledTasks module is unavailable on this host."
}

$normalizedDailyTimes = @()
foreach ($timeText in @($DailyAt | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
    $normalizedDailyTimes += ([string]$timeText).Trim()
}
$normalizedDailyTimes = @($normalizedDailyTimes | Select-Object -Unique)

if (@($normalizedDailyTimes).Count -eq 0) {
    throw "Provide at least one daily trigger time in HH:mm format."
}

$argParts = @(
    if (-not $VisibleWindow) { '-WindowStyle'; 'Hidden' }
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$maintenanceScript`"",
    "-Profile", "$Profile",
    "-InvocationMode", "scheduled",
    "-FallbackWarningThresholdRuns", "$FallbackWarningThresholdRuns",
    "-FallbackWarningWindowHours", "$FallbackWarningWindowHours"
)

if ($RestartUiOnFailure) {
    $argParts += "-RestartUiOnFailure"
}
if ($RefreshAgentMimReadiness) {
    $argParts += "-RefreshAgentMimReadiness"
}

$actionArgs = ($argParts -join " ")
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

$triggers = @()
foreach ($timeText in $normalizedDailyTimes) {
    $timeValue = [DateTime]::ParseExact($timeText, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    $triggers += New-ScheduledTaskTrigger -Daily -At $timeValue
}
if ($IncludeLogonTrigger) {
    $triggers += New-ScheduledTaskTrigger -AtLogOn -User $currentUser
}

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "TOD scheduled self-health maintenance" -Force -ErrorAction Stop | Out-Null
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
    profile = $Profile
    fallback_warning_threshold_runs = $FallbackWarningThresholdRuns
    fallback_warning_window_hours = $FallbackWarningWindowHours
    daily_at = @($normalizedDailyTimes)
    include_logon_trigger = [bool]$IncludeLogonTrigger
    visible_window = [bool]$VisibleWindow
    run_now_requested = [bool]$RunNow
    action = [pscustomobject]@{
        execute = "powershell.exe"
        arguments = $actionArgs
    }
} | ConvertTo-Json -Depth 8 | Write-Output