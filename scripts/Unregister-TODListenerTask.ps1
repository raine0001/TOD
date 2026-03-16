param(
    [string]$TaskName = "TOD-MimListener"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command -Name Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "ScheduledTasks module is unavailable on this host."
}

$exists = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -eq $exists) {
    [pscustomobject]@{
        ok = $true
        removed = $false
        task_name = $TaskName
        message = "Task not found"
    } | ConvertTo-Json -Depth 5 | Write-Output
    return
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

[pscustomobject]@{
    ok = $true
    removed = $true
    task_name = $TaskName
} | ConvertTo-Json -Depth 5 | Write-Output
