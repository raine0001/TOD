param(
    [string]$TaskName = "TOD-MimListener",
    [int]$PollSeconds = 2,
    [int]$RegressionNoDeltaThreshold = 4,
    [switch]$PublishIntegrationStatus,
    [switch]$SystemStartup,
    [string]$EnvFile = ".env",
    [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared",
    [string]$StageDir = "tod/out/context-sync/listener"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerScript = Join-Path $PSScriptRoot "Start-TODMimPacketListener.ps1"

if (-not (Test-Path -Path $listenerScript)) {
    throw "Missing listener script: $listenerScript"
}

if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "ScheduledTasks module is unavailable on this host."
}

$argParts = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$listenerScript`"",
    "-PollSeconds", "$PollSeconds",
    "-RegressionNoDeltaThreshold", "$RegressionNoDeltaThreshold",
    "-EnvFile", "`"$EnvFile`"",
    "-RemoteRoot", "`"$RemoteRoot`"",
    "-StageDir", "`"$StageDir`""
)

if ($PublishIntegrationStatus) {
    $argParts += "-PublishIntegrationStatus"
}

$actionArgs = ($argParts -join " ")
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0)

$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$startupAdded = $false

if ($SystemStartup) {
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $triggers = @()
    $triggers += New-ScheduledTaskTrigger -AtStartup
    $startupAdded = $true
}
else {
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
    $triggers = @()
    $triggers += New-ScheduledTaskTrigger -AtLogOn -User $currentUser

    try {
        $triggers += New-ScheduledTaskTrigger -AtStartup
        $startupAdded = $true
    }
    catch {
        $startupAdded = $false
    }
}

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "TOD MIM packet listener (startup + logon)" -Force -ErrorAction Stop | Out-Null
}
catch {
    # Fallback for environments where startup trigger or SYSTEM registration is not allowed.
    $triggers = @()
    $triggers += New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "TOD MIM packet listener (logon trigger)" -Force -ErrorAction Stop | Out-Null
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
