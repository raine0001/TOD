[CmdletBinding()]
param([string]$TaskName = 'TOD-Managed-SSH-Connectivity')

$ErrorActionPreference = 'Stop'
$syncScript = Join-Path $PSScriptRoot 'Sync-TODManagedSshConnectivity.ps1'
if (-not (Test-Path -LiteralPath $syncScript)) { throw "Missing sync script: $syncScript" }
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $syncScript)
$atLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$recurring = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes 15)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($atLogon,$recurring) -Settings $settings -Description 'TOD-owned SSH authority synchronization and key-access proof for TODBOX and MIMBOX.' -Force | Out-Null
Get-ScheduledTask -TaskName $TaskName | Select-Object TaskName,State
