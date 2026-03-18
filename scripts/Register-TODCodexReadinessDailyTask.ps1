param(
    [string]$TaskName = "TOD-CodexReadiness-Daily",
    [string]$DailyAt = "09:00",
    [ValidateSet("review", "debug", "fixes", "plan", "operator")]
    [string]$Mode = "review",
    [switch]$RunNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$dailyScript = Join-Path $PSScriptRoot "Invoke-TODCodexReadinessDaily.ps1"

if (-not (Test-Path -Path $dailyScript)) {
    throw "Missing daily script: $dailyScript"
}

if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "ScheduledTasks module is unavailable on this host."
}

$argParts = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$dailyScript`"",
    "-Mode", "$Mode"
)
$actionArgs = ($argParts -join " ")
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

$timeValue = [DateTime]::ParseExact($DailyAt, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
$triggers = @()
$triggers += New-ScheduledTaskTrigger -Daily -At $timeValue
$triggers += New-ScheduledTaskTrigger -AtLogOn -User $currentUser

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "TOD codex-readiness daily run" -Force -ErrorAction Stop | Out-Null
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
    daily_at = $DailyAt
    run_now_requested = [bool]$RunNow
    action = [pscustomobject]@{
        execute = "powershell.exe"
        arguments = $actionArgs
    }
} | ConvertTo-Json -Depth 8 | Write-Output
