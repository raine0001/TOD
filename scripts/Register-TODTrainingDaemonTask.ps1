param(
    [string]$TaskName = "TOD-TrainingDaemon",
    [int]$IntervalSeconds = 300,
    [int]$IdleCadenceMinutes = 30,
    [int]$FullCadenceHours = 24,
    [int]$Top = 15,
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$daemonScript = Join-Path $PSScriptRoot "Start-TODTrainingDaemon.ps1"

if (-not (Test-Path -Path $daemonScript)) {
    throw "Missing daemon script: $daemonScript"
}

$effectiveConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    Join-Path $repoRoot "tod/config/tod-config.json"
}
else {
    if ([System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath } else { Join-Path $repoRoot $ConfigPath }
}

if (-not (Test-Path -Path $effectiveConfigPath)) {
    throw "Config not found: $effectiveConfigPath"
}

if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "ScheduledTasks module is unavailable on this host."
}

$argParts = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$daemonScript`"",
    "-IntervalSeconds", "$IntervalSeconds",
    "-IdleCadenceMinutes", "$IdleCadenceMinutes",
    "-FullCadenceHours", "$FullCadenceHours",
    "-Top", "$Top",
    "-ConfigPath", "`"$effectiveConfigPath`""
)
$actionArgs = ($argParts -join " ")

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0)

$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

$triggers = @()
$triggers += New-ScheduledTaskTrigger -AtLogOn -User $currentUser

$startupAdded = $false
try {
    $triggers += New-ScheduledTaskTrigger -AtStartup
    $startupAdded = $true
}
catch {
    $startupAdded = $false
}

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "TOD continuous training daemon (daily full + idle training)" -Force -ErrorAction Stop | Out-Null
}
catch {
    # Fallback for environments where startup trigger + interactive principal is not allowed.
    $triggers = @()
    $triggers += New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "TOD continuous training daemon (logon trigger)" -Force -ErrorAction Stop | Out-Null
        $startupAdded = $false
    }
    catch {
        $message = $_.Exception.Message
        $isAccessDenied = $message -match "Access is denied|0x80070005"
        [pscustomobject]@{
            ok = $false
            task_name = $TaskName
            user = $currentUser
            startup_trigger_enabled = $false
            requires_elevation = $isAccessDenied
            error = $message
        } | ConvertTo-Json -Depth 8 | Write-Output
        return
    }
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($null -eq $task) {
    [pscustomobject]@{
        ok = $false
        task_name = $TaskName
        user = $currentUser
        startup_trigger_enabled = $startupAdded
        requires_elevation = $false
        error = "Task registration did not produce a visible scheduled task."
    } | ConvertTo-Json -Depth 8 | Write-Output
    return
}

$result = [pscustomobject]@{
    ok = $true
    task_name = $TaskName
    user = $currentUser
    startup_trigger_enabled = $startupAdded
    state = [string]$task.State
    action = [pscustomobject]@{
        execute = "powershell.exe"
        arguments = $actionArgs
    }
}

$result | ConvertTo-Json -Depth 8 | Write-Output
