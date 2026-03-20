param(
    [string]$TaskName = "TOD-GitHubProjectSimulation-Daily",
    [string]$DailyAt = "09:15",
    [switch]$UseAssist,
    [switch]$RunNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$dailyScript = Join-Path $PSScriptRoot "Invoke-TODGitHubProjectSimulationDaily.ps1"
if (-not (Test-Path -Path $dailyScript)) {
    throw "Missing daily simulation script: $dailyScript"
}

if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "ScheduledTasks module is unavailable on this host."
}

$argParts = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$dailyScript`""
)
if ($UseAssist) { $argParts += "-UseAssist" }
$actionArgs = ($argParts -join " ")
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$timeValue = [DateTime]::ParseExact($DailyAt, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
$triggers = @(
    (New-ScheduledTaskTrigger -Daily -At $timeValue),
    (New-ScheduledTaskTrigger -AtLogOn -User $currentUser)
)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "TOD GitHub project simulation daily run" -Force | Out-Null

if ($RunNow) {
    try { Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch {}
}

$task = Get-ScheduledTask -TaskName $TaskName
[pscustomobject]@{
    ok = $true
    task_name = $TaskName
    state = [string]$task.State
    daily_at = $DailyAt
    run_now_requested = [bool]$RunNow
    action = [pscustomobject]@{
        execute = "powershell.exe"
        arguments = $actionArgs
    }
} | ConvertTo-Json -Depth 8 | Write-Output
