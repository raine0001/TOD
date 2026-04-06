param(
    [string]$TaskName = "TOD-CatchupGateWatcher",
    [int]$CheckEverySeconds = 30,
    [int]$WriterLeaseSeconds = 600,
    [string]$WriterId = "tod-catchup-gate-watcher"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$watcherScript = Join-Path $PSScriptRoot "Start-TODCatchupGateWatcher.ps1"

if (-not (Test-Path -Path $watcherScript)) {
    throw "Missing watcher script: $watcherScript"
}

if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "ScheduledTasks module is unavailable on this host."
}

$argParts = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$watcherScript`"",
    "-CheckEverySeconds", "$CheckEverySeconds",
    "-WriterLeaseSeconds", "$WriterLeaseSeconds",
    "-WriterId", "`"$WriterId`""
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
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "TOD catch-up gate watcher (single writer)" -Force -ErrorAction Stop | Out-Null
}
catch {
    $triggers = @()
    $triggers += New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "TOD catch-up gate watcher (logon trigger)" -Force -ErrorAction Stop | Out-Null
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

try {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}
catch {
}

[pscustomobject]@{
    ok = $true
    task_name = $TaskName
    user = $currentUser
    startup_trigger_enabled = $startupAdded
    state = [string]$task.State
    action = [pscustomobject]@{
        execute = "powershell.exe"
        arguments = $actionArgs
    }
} | ConvertTo-Json -Depth 8 | Write-Output