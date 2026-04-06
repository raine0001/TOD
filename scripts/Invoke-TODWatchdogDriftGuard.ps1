param(
    [string]$SharedStateDir = "shared_state",
    [string]$ListenerStageDir = "tod/out/context-sync/listener",
    [string]$RecoveryWatchdogScriptPath = "scripts/Start-TODRecoveryWatchdog.ps1",
    [string]$SelfHealthMaintenanceScriptPath = "scripts/Invoke-TODSelfHealthMaintenance.ps1",
    [ValidateSet("light", "standard", "deep")]
    [string]$ResolutionProfile = "standard",
    [string[]]$ActiveWindows = @(),
    [int]$StaleSkewSeconds = 300,
    [switch]$AutoCorrect,
    [switch]$TriggerMaintenanceOnDetection,
    [switch]$TriggerMaintenanceOnUnresolved,
    [switch]$RestartUiOnFailure,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$guardId = "tod-watchdog-drift-guard-v1"

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
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

function Write-Utf8NoBomJson {
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
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Append-Utf8NoBomJsonLine {
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
    $line = (($Payload | ConvertTo-Json -Depth $Depth -Compress) + "`n")
    [System.IO.File]::AppendAllText($PathValue, $line, $utf8NoBom)
}

function Get-ItemUtcOrNull {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $null
    }

    return (Get-Item -Path $PathValue).LastWriteTimeUtc
}

function Test-InActiveWindow {
    param(
        [datetime]$NowLocal,
        [string[]]$Windows
    )

    if ($null -eq $Windows -or @($Windows).Count -eq 0) {
        return [pscustomobject]@{
            active = $true
            matched_window = "always"
        }
    }

    $currentMinute = ($NowLocal.Hour * 60) + $NowLocal.Minute
    foreach ($window in @($Windows)) {
        $text = ([string]$window).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $parts = $text -split "-"
        if (@($parts).Count -ne 2) {
            continue
        }

        $start = [datetime]::MinValue
        $end = [datetime]::MinValue
        $okStart = [datetime]::TryParseExact($parts[0].Trim(), "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$start)
        $okEnd = [datetime]::TryParseExact($parts[1].Trim(), "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$end)
        if (-not ($okStart -and $okEnd)) {
            continue
        }

        $startMinute = ($start.Hour * 60) + $start.Minute
        $endMinute = ($end.Hour * 60) + $end.Minute
        $inWindow = $false

        if ($startMinute -le $endMinute) {
            $inWindow = ($currentMinute -ge $startMinute -and $currentMinute -lt $endMinute)
        }
        else {
            $inWindow = ($currentMinute -ge $startMinute -or $currentMinute -lt $endMinute)
        }

        if ($inWindow) {
            return [pscustomobject]@{
                active = $true
                matched_window = $text
            }
        }
    }

    return [pscustomobject]@{
        active = $false
        matched_window = ""
    }
}

$sharedStateAbs = Resolve-LocalPath -PathValue $SharedStateDir
$listenerStageAbs = Resolve-LocalPath -PathValue $ListenerStageDir
$watchdogScriptAbs = Resolve-LocalPath -PathValue $RecoveryWatchdogScriptPath
$selfHealthScriptAbs = Resolve-LocalPath -PathValue $SelfHealthMaintenanceScriptPath

if (-not (Test-Path -Path $sharedStateAbs)) {
    New-Item -ItemType Directory -Path $sharedStateAbs -Force | Out-Null
}

$watchdogStatePath = Join-Path $sharedStateAbs "tod_recovery_watchdog.latest.json"
$guardLatestPath = Join-Path $sharedStateAbs "tod_watchdog_drift_guard.latest.json"
$guardLogPath = Join-Path $sharedStateAbs "tod_watchdog_drift_guard.log.jsonl"

$listenerStatePath = Join-Path $listenerStageAbs "listener_state.json"
$requestPath = Join-Path $listenerStageAbs "MIM_TOD_TASK_REQUEST.latest.json"
$resultPath = Join-Path $listenerStageAbs "TOD_MIM_TASK_RESULT.latest.json"

$nowUtc = (Get-Date).ToUniversalTime()
$nowLocal = Get-Date
$windowEval = Test-InActiveWindow -NowLocal $nowLocal -Windows $ActiveWindows
$watchdogDoc = Read-JsonFileIfExists -PathValue $watchdogStatePath
$watchdogState = if ($watchdogDoc -and $watchdogDoc.PSObject.Properties['state']) { [string]$watchdogDoc.state } else { "unknown" }

$watchdogMtimeUtc = Get-ItemUtcOrNull -PathValue $watchdogStatePath
$listenerMtimeUtc = Get-ItemUtcOrNull -PathValue $listenerStatePath
$requestMtimeUtc = Get-ItemUtcOrNull -PathValue $requestPath
$resultMtimeUtc = Get-ItemUtcOrNull -PathValue $resultPath

$referenceCandidates = @()
foreach ($candidate in @($listenerMtimeUtc, $requestMtimeUtc, $resultMtimeUtc)) {
    if ($candidate) {
        $referenceCandidates += $candidate
    }
}

$referenceLatestUtc = $null
if (@($referenceCandidates).Count -gt 0) {
    $referenceLatestUtc = @($referenceCandidates | Sort-Object | Select-Object -Last 1)[0]
}

$watchdogSkewSeconds = -1
if ($watchdogMtimeUtc -and $referenceLatestUtc) {
    $watchdogSkewSeconds = [int][Math]::Floor(($referenceLatestUtc - $watchdogMtimeUtc).TotalSeconds)
}

$watchdogAgeSeconds = -1
if ($watchdogMtimeUtc) {
    $watchdogAgeSeconds = [int][Math]::Floor(($nowUtc - $watchdogMtimeUtc).TotalSeconds)
}

$detected = $false
$reasonCodes = New-Object System.Collections.Generic.List[string]
if (-not $watchdogMtimeUtc) {
    $detected = $true
    $reasonCodes.Add("watchdog_state_missing") | Out-Null
}
if ($watchdogSkewSeconds -ge [Math]::Max(1, $StaleSkewSeconds)) {
    $detected = $true
    $reasonCodes.Add("watchdog_older_than_listener_truth") | Out-Null
}

$actionAttempted = $false
$actionSucceeded = $false
$actionMessage = "no_correction_needed"
$postWatchdogState = $watchdogState

$resolutionAttempted = $false
$resolutionSucceeded = $false
$resolutionMessage = "no_resolution_triggered"
$resolutionStatus = "not_run"

if ($windowEval.active -and $detected -and $AutoCorrect) {
    if (-not (Test-Path -Path $watchdogScriptAbs)) {
        $actionAttempted = $true
        $actionSucceeded = $false
        $actionMessage = "watchdog_script_missing"
    }
    else {
        $actionAttempted = $true
        try {
            $watchdogArgs = @{ RunOnce = $true }
            if ($RestartUiOnFailure) {
                $watchdogArgs.RestartUiOnFailure = $true
            }

            & $watchdogScriptAbs @watchdogArgs | Out-Null
            $postDoc = Read-JsonFileIfExists -PathValue $watchdogStatePath
            $postWatchdogState = if ($postDoc -and $postDoc.PSObject.Properties['state']) { [string]$postDoc.state } else { "unknown" }
            $actionSucceeded = ($postWatchdogState -ne "unknown")
            $actionMessage = if ($actionSucceeded) { "watchdog_run_once_completed" } else { "watchdog_run_once_no_state" }
        }
        catch {
            $actionSucceeded = $false
            $actionMessage = [string]$_.Exception.Message
        }
    }
}

$shouldTriggerResolution = $false
if ($windowEval.active -and $detected -and $TriggerMaintenanceOnDetection) {
    $shouldTriggerResolution = $true
}
elseif ($windowEval.active -and $detected -and $TriggerMaintenanceOnUnresolved -and -not $actionSucceeded) {
    $shouldTriggerResolution = $true
}

if ($shouldTriggerResolution) {
    $resolutionAttempted = $true
    if (-not (Test-Path -Path $selfHealthScriptAbs)) {
        $resolutionSucceeded = $false
        $resolutionMessage = "self_health_script_missing"
        $resolutionStatus = "failed"
    }
    else {
        try {
            $maintenanceArgs = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $selfHealthScriptAbs,
                "-Profile", $ResolutionProfile,
                "-InvocationMode", "manual",
                "-EmitJson"
            )
            if ($RestartUiOnFailure) {
                $maintenanceArgs += "-RestartUiOnFailure"
            }

            $maintenanceOutput = & powershell.exe @maintenanceArgs | Out-String
            $maintenanceDoc = $null
            try {
                $maintenanceDoc = ($maintenanceOutput | ConvertFrom-Json)
            }
            catch {
                $maintenanceDoc = $null
            }

            if ($maintenanceDoc -and $maintenanceDoc.PSObject.Properties['overall_status']) {
                $resolutionStatus = [string]$maintenanceDoc.overall_status
                $resolutionSucceeded = -not [string]::Equals($resolutionStatus, "needs_attention", [System.StringComparison]::OrdinalIgnoreCase)
                $resolutionMessage = if ($maintenanceDoc.PSObject.Properties['summary']) { [string]$maintenanceDoc.summary } else { "maintenance_completed" }
            }
            else {
                $resolutionSucceeded = $false
                $resolutionStatus = "failed"
                $resolutionMessage = "maintenance_output_unreadable"
            }
        }
        catch {
            $resolutionSucceeded = $false
            $resolutionStatus = "failed"
            $resolutionMessage = [string]$_.Exception.Message
        }
    }
}

if (-not $detected) {
    if ($windowEval.active) {
        $reasonCodes.Add("none") | Out-Null
    }
    else {
        $reasonCodes.Add("outside_active_window") | Out-Null
    }
}

$result = [pscustomobject]@{
    generated_at = $nowUtc.ToString("o")
    source = $guardId
    detected = $detected
    threshold_seconds = [Math]::Max(1, $StaleSkewSeconds)
    reasons = @($reasonCodes)
    window_gate = [pscustomobject]@{
        active = [bool]$windowEval.active
        matched_window = [string]$windowEval.matched_window
        now_local = $nowLocal.ToString("yyyy-MM-ddTHH:mm:ss")
        configured_windows = @($ActiveWindows)
    }
    metrics = [pscustomobject]@{
        watchdog_state = $watchdogState
        watchdog_mtime_utc = if ($watchdogMtimeUtc) { $watchdogMtimeUtc.ToString("o") } else { "" }
        listener_reference_utc = if ($referenceLatestUtc) { $referenceLatestUtc.ToString("o") } else { "" }
        watchdog_age_seconds = $watchdogAgeSeconds
        watchdog_skew_seconds = $watchdogSkewSeconds
        listener_state_mtime_utc = if ($listenerMtimeUtc) { $listenerMtimeUtc.ToString("o") } else { "" }
        request_mtime_utc = if ($requestMtimeUtc) { $requestMtimeUtc.ToString("o") } else { "" }
        result_mtime_utc = if ($resultMtimeUtc) { $resultMtimeUtc.ToString("o") } else { "" }
    }
    correction = [pscustomobject]@{
        attempted = $actionAttempted
        succeeded = $actionSucceeded
        message = $actionMessage
        post_watchdog_state = $postWatchdogState
    }
    resolution_trigger = [pscustomobject]@{
        attempted = $resolutionAttempted
        succeeded = $resolutionSucceeded
        status = $resolutionStatus
        message = $resolutionMessage
        mode = if ($TriggerMaintenanceOnDetection) { "on_detection" } elseif ($TriggerMaintenanceOnUnresolved) { "on_unresolved" } else { "disabled" }
        profile = $ResolutionProfile
    }
}

Write-Utf8NoBomJson -PathValue $guardLatestPath -Payload $result
Append-Utf8NoBomJsonLine -PathValue $guardLogPath -Payload $result

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 20
}
else {
    $result
}
