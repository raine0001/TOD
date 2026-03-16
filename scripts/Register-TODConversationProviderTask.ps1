param(
    [string]$TaskName = 'TOD-ConversationProvider',
    [string]$ConfigPath = 'tod/config/llama-runtime.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serverScript = Join-Path $PSScriptRoot 'Start-TODLlamaCppServer.ps1'
if (-not (Test-Path -Path $serverScript)) {
    throw "Missing conversation provider script: $serverScript"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$effectiveConfigPath = if ([System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath } else { Join-Path $repoRoot $ConfigPath }
if (-not (Test-Path -Path $effectiveConfigPath)) {
    throw "Config not found: $effectiveConfigPath"
}

if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw 'ScheduledTasks module is unavailable on this host.'
}

$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$actionArgs = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$serverScript`" -ConfigPath `"$effectiveConfigPath`" -Launch"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $actionArgs
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'TOD local conversation provider (llama.cpp)' -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop

[pscustomobject]@{
    ok = $true
    task_name = $TaskName
    user = $currentUser
    state = [string]$task.State
    action = [pscustomobject]@{
        execute = 'powershell.exe'
        arguments = $actionArgs
    }
} | ConvertTo-Json -Depth 8 | Write-Output