param(
    [string]$TaskName = "TOD-VoiceListener"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$voiceScript = Join-Path $PSScriptRoot "Start-TODVoiceListener.ps1"
if (-not (Test-Path -Path $voiceScript)) {
    throw "Missing voice listener script: $voiceScript"
}

if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "ScheduledTasks module is unavailable on this host."
}

$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$actionArgs = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$voiceScript`""
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "TOD voice listener (logon trigger)" -Force | Out-Null

try {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}
catch {
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop

[pscustomobject]@{
    ok = $true
    task_name = $TaskName
    user = $currentUser
    state = [string]$task.State
    action = [pscustomobject]@{
        execute = "powershell.exe"
        arguments = $actionArgs
    }
} | ConvertTo-Json -Depth 8 | Write-Output