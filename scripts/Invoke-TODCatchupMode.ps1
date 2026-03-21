param(
    [switch]$Pause,
    [switch]$Resume,
    [string]$TaskName = "TOD-MimListener",
    [string]$AlignObjectiveId = "75",
    [bool]$RunApprovalReductionPass = $true,
    [string]$OutputPath = "shared_state/tod_catchup_mode.latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Pause -and $Resume) {
    throw "Use either -Pause or -Resume, not both."
}
if (-not $Pause -and -not $Resume) {
    $Pause = $true
}

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth)
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Get-LightweightStateBus {
    $scriptPath = Get-LocalPath -PathValue "scripts/Get-TODLightweightStateBus.ps1"
    try {
        $raw = & $scriptPath -AsJson 2>$null
        if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Stop-ListenerProcesses {
    $stopped = @()
    $errors = @()

    $procs = @(Get-CimInstance Win32_Process | Where-Object {
            $_.CommandLine -and $_.CommandLine -like "*Start-TODMimPacketListener.ps1*"
        })

    foreach ($p in $procs) {
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            $stopped += [pscustomobject]@{ pid = [int]$p.ProcessId; ok = $true }
        }
        catch {
            $errors += [pscustomobject]@{ pid = [int]$p.ProcessId; ok = $false; error = [string]$_.Exception.Message }
        }
    }

    return [pscustomobject]@{
        found = [int]@($procs).Count
        stopped = @($stopped)
        errors = @($errors)
    }
}

function Disable-ListenerTask {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ exists = $false; changed = $false; message = "ScheduledTasks module unavailable" }
    }

    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return [pscustomobject]@{ exists = $false; changed = $false; message = "Task not found" }
    }

    $changed = $false
    try {
        Stop-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    }
    catch {
    }

    try {
        Disable-ScheduledTask -TaskName $Name -ErrorAction Stop | Out-Null
        $changed = $true
    }
    catch {
        return [pscustomobject]@{ exists = $true; changed = $false; message = [string]$_.Exception.Message }
    }

    return [pscustomobject]@{ exists = $true; changed = $changed; message = "Task disabled" }
}

function Resume-ListenerTask {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ exists = $false; changed = $false; message = "ScheduledTasks module unavailable" }
    }

    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return [pscustomobject]@{ exists = $false; changed = $false; message = "Task not found" }
    }

    try {
        Enable-ScheduledTask -TaskName $Name -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        return [pscustomobject]@{ exists = $true; changed = $true; message = "Task enabled and started" }
    }
    catch {
        return [pscustomobject]@{ exists = $true; changed = $false; message = [string]$_.Exception.Message }
    }
}

function Set-AlignmentObjective {
    param([Parameter(Mandatory = $true)][string]$ObjectiveId)

    $nextActionsPath = Get-LocalPath -PathValue "shared_state/next_actions.json"
    $nextActions = Read-JsonFileIfExists -PathValue $nextActionsPath
    if ($null -eq $nextActions) {
        $nextActions = [pscustomobject]@{}
    }

    $nextActions | Add-Member -NotePropertyName current_objective_in_progress -NotePropertyValue ([string]$ObjectiveId) -Force
    $nextActions | Add-Member -NotePropertyName catchup_mode -NotePropertyValue ([pscustomobject]@{
            enabled = $true
            objective_id = [string]$ObjectiveId
            set_at = (Get-Date).ToUniversalTime().ToString("o")
            source = "Invoke-TODCatchupMode"
        }) -Force

    Write-JsonFile -PathValue $nextActionsPath -Payload $nextActions

    return [pscustomobject]@{
        path = $nextActionsPath
        current_objective_in_progress = [string]$ObjectiveId
    }
}

function Invoke-ApprovalReduction {
    $scriptPath = Get-LocalPath -PathValue "scripts/Invoke-TODApprovalReductionPass.ps1"
    if (-not (Test-Path -Path $scriptPath)) {
        return [pscustomobject]@{ ok = $false; message = "Invoke-TODApprovalReductionPass.ps1 not found" }
    }

    try {
        $raw = & $scriptPath -WriteOutputs -AppendJournal
        $obj = $null
        try { $obj = $raw | ConvertFrom-Json } catch { }
        if ($obj) {
            return [pscustomobject]@{ ok = $true; totals = $obj.totals; output = "shared_state/approval_reduction_summary.json" }
        }

        return [pscustomobject]@{ ok = $true; message = "Approval reduction pass completed" }
    }
    catch {
        return [pscustomobject]@{ ok = $false; message = [string]$_.Exception.Message }
    }
}

$outputAbs = Get-LocalPath -PathValue $OutputPath
$before = Get-LightweightStateBus

$result = [ordered]@{
    ok = $true
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-catchup-mode-v1"
    mode = if ($Pause) { "pause" } else { "resume" }
    before = $before
    actions = [ordered]@{}
}

if ($Pause) {
    $result.actions.listener_processes = Stop-ListenerProcesses
    $result.actions.listener_task = Disable-ListenerTask -Name $TaskName

    $syncScript = Get-LocalPath -PathValue "scripts/Invoke-TODSharedStateSync.ps1"
    if (Test-Path -Path $syncScript) {
        try { & $syncScript 2>&1 | Out-Null } catch { }
    }

    $result.actions.objective_alignment = Set-AlignmentObjective -ObjectiveId $AlignObjectiveId

    if ($RunApprovalReductionPass) {
        $result.actions.approval_reduction = Invoke-ApprovalReduction
    }
    else {
        $result.actions.approval_reduction = [pscustomobject]@{ ok = $true; skipped = $true }
    }
}
else {
    $result.actions.listener_task = Resume-ListenerTask -Name $TaskName
}

$after = Get-LightweightStateBus
$result.after = $after

Write-JsonFile -PathValue $outputAbs -Payload ([pscustomobject]$result)

([pscustomobject]$result) | ConvertTo-Json -Depth 20 | Write-Output
