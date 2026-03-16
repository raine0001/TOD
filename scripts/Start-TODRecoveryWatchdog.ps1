param(
    [int]$CheckEverySeconds = 120,
    [int]$FreezeAfterMinutes = 5,
    [int]$AlertCooldownSeconds = 300,
    [switch]$RestartUiOnFailure,
    [switch]$RunOnce,
    [string]$EnvFile = ".env",
    [string]$ListenerScriptPath = "scripts/Start-TODMimPacketListener.ps1",
    [string]$UiScriptPath = "scripts/Start-TOD-UI.ps1",
    [int]$UiPort = 8844,
    [string]$StageDir = "tod/out/context-sync/listener",
    [string]$SharedStateDir = "shared_state"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$watchdogId = "tod-recovery-watchdog-v1"

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) { return $null }
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
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Add-JsonLine {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $line = (($Payload | ConvertTo-Json -Depth 20 -Compress) + "`n")
    [System.IO.File]::AppendAllText($PathValue, $line, $utf8NoBom)
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -Path $Path)) { return "" }

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace([string]$line)) { return "" }

    return ([string]($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "")).Trim()
}

function Test-ListenerRunning {
    param([Parameter(Mandatory = $true)][string]$ListenerScriptAbs)

    $procs = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and $_.CommandLine -match [regex]::Escape($ListenerScriptAbs)
    }
    return ([bool](@($procs).Count -gt 0))
}

function Stop-ScriptProcesses {
    param([Parameter(Mandatory = $true)][string]$ScriptAbs)

    $procs = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and $_.CommandLine -match [regex]::Escape($ScriptAbs)
    }

    foreach ($proc in $procs) {
        try {
            Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction Stop
        }
        catch {
        }
    }
}

function Start-BackgroundScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptAbs,
        [string[]]$ScriptArgs = @()
    )

    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptAbs) + @($ScriptArgs)
    $null = Start-Process -FilePath "powershell" -ArgumentList $argList -WindowStyle Hidden
}

function Test-UiHealthy {
    param([Parameter(Mandatory = $true)][int]$Port)

    try {
        $resp = Invoke-WebRequest -Uri ("http://localhost:{0}/api/project-status" -f $Port) -UseBasicParsing -TimeoutSec 8
        return ($resp.StatusCode -eq 200)
    }
    catch {
        return $false
    }
}

function Resolve-SshHostAlias {
    param([Parameter(Mandatory = $true)][string]$RemoteHost)

    if ($RemoteHost -match "^\d{1,3}(?:\.\d{1,3}){3}$" -or $RemoteHost -match "\.") {
        return $RemoteHost
    }

    $sshConfigPath = Join-Path $HOME ".ssh/config"
    if (-not (Test-Path -Path $sshConfigPath)) {
        return $RemoteHost
    }

    $matchedHost = $false
    foreach ($rawLine in Get-Content -Path $sshConfigPath) {
        $line = [string]$rawLine
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith("#")) { continue }

        if ($trim -match "^(?i)Host\s+(.+)$") {
            $matchedHost = $false
            foreach ($token in @($matches[1] -split "\s+")) {
                if ([string]::Equals([string]$token, $RemoteHost, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchedHost = $true
                    break
                }
            }
            continue
        }

        if ($matchedHost -and $trim -match "^(?i)HostName\s+(.+)$") {
            return [string]$matches[1]
        }
    }

    return $RemoteHost
}

function Get-AlertSignature {
    param(
        [string]$IssueCode,
        [string]$IssueDetail,
        [string]$RecoveryAction,
        [string]$RequestId,
        [string]$LastProcessedId
    )

    return ((@(
                [string]$IssueCode,
                [string]$IssueDetail,
                [string]$RecoveryAction,
                [string]$RequestId,
                [string]$LastProcessedId
            ) -join "|").ToLowerInvariant())
}

function Publish-RecoveryAlertToMim {
    param(
        [Parameter(Mandatory = $true)]$AlertPayload,
        [Parameter(Mandatory = $true)][string]$LocalPacketPath,
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared"
    )

    Write-JsonFile -PathValue $LocalPacketPath -Payload $AlertPayload

    try {
        if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
            return [pscustomobject]@{ uploaded = $false; reason = "posh_ssh_not_installed" }
        }

        $hostAlias = Get-DotEnvValue -Path $EnvPath -Name "MIM_SSH_HOST"
        if ([string]::IsNullOrWhiteSpace($hostAlias)) { $hostAlias = "mim" }
        $userName = Get-DotEnvValue -Path $EnvPath -Name "MIM_SSH_USER"
        if ([string]::IsNullOrWhiteSpace($userName)) { $userName = "testpilot" }
        $portText = Get-DotEnvValue -Path $EnvPath -Name "MIM_SSH_PORT"
        $password = Get-DotEnvValue -Path $EnvPath -Name "MIM_SSH_PASSWORD"
        if ([string]::IsNullOrWhiteSpace($password) -or $password -eq "CHANGE_ME") {
            return [pscustomobject]@{ uploaded = $false; reason = "ssh_password_not_set" }
        }

        $port = 22
        $parsed = 0
        if ([int]::TryParse([string]$portText, [ref]$parsed) -and $parsed -gt 0) {
            $port = $parsed
        }

        Import-Module Posh-SSH -ErrorAction Stop | Out-Null
        $resolvedHost = Resolve-SshHostAlias -RemoteHost $hostAlias
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)
        $sftp = New-SFTPSession -ComputerName $resolvedHost -Port $port -Credential $credential -AcceptKey -ConnectionTimeout 15000

        try {
            Set-SFTPItem -SessionId ([int]$sftp.SessionId) -Path $LocalPacketPath -Destination $RemoteRoot -Force -ErrorAction Stop | Out-Null
        }
        finally {
            Remove-SFTPSession -SessionId ([int]$sftp.SessionId) | Out-Null
        }

        return [pscustomobject]@{ uploaded = $true; reason = "ok" }
    }
    catch {
        return [pscustomobject]@{ uploaded = $false; reason = [string]$_.Exception.Message }
    }
}

$envAbs = Get-LocalPath -PathValue $EnvFile
$listenerAbs = Get-LocalPath -PathValue $ListenerScriptPath
$uiAbs = Get-LocalPath -PathValue $UiScriptPath
$stageAbs = Get-LocalPath -PathValue $StageDir
$sharedAbs = Get-LocalPath -PathValue $SharedStateDir

New-Item -ItemType Directory -Path $stageAbs -Force | Out-Null
New-Item -ItemType Directory -Path $sharedAbs -Force | Out-Null

$requestPath = Join-Path $stageAbs "MIM_TOD_TASK_REQUEST.latest.json"
$statePath = Join-Path $stageAbs "listener_state.json"
$journalPath = Join-Path $stageAbs "TOD_LOOP_JOURNAL.latest.json"
$watchdogStatePath = Join-Path $sharedAbs "tod_recovery_watchdog.latest.json"
$watchdogLogPath = Join-Path $sharedAbs "tod_recovery_watchdog.log.jsonl"
$selfHealOrderPath = Join-Path $sharedAbs "TOD_SELF_HEAL_ORDER.latest.json"
$alertPacketPath = Join-Path $stageAbs "TOD_MIM_RECOVERY_ALERT.latest.json"
$stallThresholdSeconds = [Math]::Max(30, [int]($FreezeAfterMinutes * 60))

Write-Host "[TOD-WATCHDOG] Started."

while ($true) {
    $nowUtc = (Get-Date).ToUniversalTime()
    $issueCode = ""
    $issueDetail = ""
    $recoveryAction = "none"
    $recoveryOk = $null
    $taskState = "idle"
    $progressClassification = "no_progress_but_heartbeats_present"

    $previousState = Read-JsonFileIfExists -PathValue $watchdogStatePath
    $recoveryAttempts = 0
    $consecutiveFreezes = 0
    $lastRecoveryTime = ""
    $lastAlertSignature = ""
    $lastAlertPublishedAt = ""
    if ($previousState) {
        if ($previousState.PSObject.Properties["recovery_attempts"]) {
            try { $recoveryAttempts = [int]$previousState.recovery_attempts } catch { $recoveryAttempts = 0 }
        }
        if ($previousState.PSObject.Properties["consecutive_freezes"]) {
            try { $consecutiveFreezes = [int]$previousState.consecutive_freezes } catch { $consecutiveFreezes = 0 }
        }
        if ($previousState.PSObject.Properties["last_recovery_time"]) {
            $lastRecoveryTime = [string]$previousState.last_recovery_time
        }
        if ($previousState.PSObject.Properties["last_alert_signature"]) {
            $lastAlertSignature = [string]$previousState.last_alert_signature
        }
        if ($previousState.PSObject.Properties["last_alert_published_at"]) {
            $lastAlertPublishedAt = [string]$previousState.last_alert_published_at
        }
    }

    $listenerRunning = Test-ListenerRunning -ListenerScriptAbs $listenerAbs
    $uiHealthy = Test-UiHealthy -Port $UiPort

    $request = Read-JsonFileIfExists -PathValue $requestPath
    $listenerState = Read-JsonFileIfExists -PathValue $statePath
    $journal = Read-JsonFileIfExists -PathValue $journalPath

    $requestId = ""
    if ($request -and $request.PSObject.Properties["task_id"]) {
        $requestId = [string]$request.task_id
    }

    $lastProcessedId = ""
    if ($listenerState -and $listenerState.PSObject.Properties["last_processed_request_id"]) {
        $lastProcessedId = [string]$listenerState.last_processed_request_id
    }

    $lastCycleAt = $null
    if ($listenerState -and $listenerState.PSObject.Properties["last_cycle_at"] -and -not [string]::IsNullOrWhiteSpace([string]$listenerState.last_cycle_at)) {
        try { $lastCycleAt = [datetime][string]$listenerState.last_cycle_at } catch { $lastCycleAt = $null }
    }

    $lastJournalAt = $null
    $lastJournalStatus = ""
    if ($journal -and $journal.PSObject.Properties["entries"]) {
        $entries = @($journal.entries)
        if (@($entries).Count -gt 0) {
            $last = @($entries | Select-Object -Last 1)[0]
            if ($last.PSObject.Properties["timestamp"] -and -not [string]::IsNullOrWhiteSpace([string]$last.timestamp)) {
                try { $lastJournalAt = [datetime][string]$last.timestamp } catch { $lastJournalAt = $null }
            }
            if ($last.PSObject.Properties["execution_status"]) {
                $lastJournalStatus = [string]$last.execution_status
            }
        }
    }

    $lastTaskHeartbeatAt = $null
    if ($null -ne $lastCycleAt -and $null -ne $lastJournalAt) {
        if ($lastCycleAt.ToUniversalTime() -ge $lastJournalAt.ToUniversalTime()) {
            $lastTaskHeartbeatAt = $lastCycleAt.ToUniversalTime()
        }
        else {
            $lastTaskHeartbeatAt = $lastJournalAt.ToUniversalTime()
        }
    }
    elseif ($null -ne $lastCycleAt) {
        $lastTaskHeartbeatAt = $lastCycleAt.ToUniversalTime()
    }
    elseif ($null -ne $lastJournalAt) {
        $lastTaskHeartbeatAt = $lastJournalAt.ToUniversalTime()
    }

    $heartbeatAgeSeconds = -1
    if ($null -ne $lastTaskHeartbeatAt) {
        $heartbeatAgeSeconds = [int][Math]::Max(0, [Math]::Floor(($nowUtc - $lastTaskHeartbeatAt).TotalSeconds))
    }

    $hasPendingRequest = -not [string]::IsNullOrWhiteSpace($requestId) -and (
        [string]::IsNullOrWhiteSpace($lastProcessedId) -or
        -not [string]::Equals($requestId, $lastProcessedId, [System.StringComparison]::OrdinalIgnoreCase)
    )
    $heartbeatFresh = ($heartbeatAgeSeconds -ge 0 -and $heartbeatAgeSeconds -lt $stallThresholdSeconds)

    if ($hasPendingRequest -and $heartbeatFresh -and [string]::Equals($lastJournalStatus, "in_progress", [System.StringComparison]::OrdinalIgnoreCase)) {
        $progressClassification = "active_progress"
        $taskState = "running"
    }
    elseif ($hasPendingRequest -and $heartbeatFresh) {
        $progressClassification = "no_progress_but_heartbeats_present"
        $taskState = "running"
    }
    elseif ($hasPendingRequest -and -not $heartbeatFresh) {
        $progressClassification = "no_heartbeats_no_progress"
        $taskState = "stalled"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($requestId)) {
        $progressClassification = if ($heartbeatFresh) { "no_progress_but_heartbeats_present" } else { "no_heartbeats_no_progress" }
        $taskState = "waiting"
    }
    else {
        $progressClassification = if ($heartbeatFresh) { "no_progress_but_heartbeats_present" } else { "no_heartbeats_no_progress" }
        $taskState = "idle"
    }

    if (-not $listenerRunning) {
        $issueCode = "listener_not_running"
        $issueDetail = "Listener process is not active."
    }
    elseif (-not [string]::IsNullOrWhiteSpace($requestId) -and -not [string]::IsNullOrWhiteSpace($lastProcessedId) -and -not [string]::Equals($requestId, $lastProcessedId, [System.StringComparison]::OrdinalIgnoreCase)) {
        $isStaleCycle = $false
        if ($null -eq $lastCycleAt) {
            $isStaleCycle = $true
        }
        else {
            $minsSinceCycle = ($nowUtc - $lastCycleAt.ToUniversalTime()).TotalMinutes
            $isStaleCycle = ($minsSinceCycle -ge $FreezeAfterMinutes)
        }

        if ($isStaleCycle) {
            $issueCode = "listener_stalled_pending_request"
            $issueDetail = "Pending request was not processed within freeze threshold."
        }
    }
    elseif (-not $uiHealthy) {
        $issueCode = "ui_unhealthy"
        $issueDetail = "UI project-status endpoint is not healthy."
    }

    if (-not [string]::IsNullOrWhiteSpace($issueCode)) {
        $taskState = "recovering"
        $progressClassification = "no_heartbeats_recovery_in_progress"
        $recoveryAttempts = [int]$recoveryAttempts + 1
        $consecutiveFreezes = [int]$consecutiveFreezes + 1
        $lastRecoveryTime = $nowUtc.ToString("o")

        $recoveryAction = "restart_listener"
        Stop-ScriptProcesses -ScriptAbs $listenerAbs
        Start-BackgroundScript -ScriptAbs $listenerAbs -ScriptArgs @("-PollSeconds", "2")

        if ($issueCode -eq "ui_unhealthy" -or ($RestartUiOnFailure -and -not $uiHealthy)) {
            $recoveryAction = "restart_listener_and_ui"
            Stop-ScriptProcesses -ScriptAbs $uiAbs
            Start-BackgroundScript -ScriptAbs $uiAbs -ScriptArgs @("-Port", [string]$UiPort, "-NoAutoOpen")
        }

        Start-Sleep -Seconds 4
        $listenerRecovered = Test-ListenerRunning -ListenerScriptAbs $listenerAbs
        $uiRecovered = Test-UiHealthy -Port $UiPort
        $recoveryOk = ($listenerRecovered -and $uiRecovered)
        $taskState = if ($recoveryOk) { "recovered" } else { "failed" }

        $selfHealOrder = [pscustomobject]@{
            generated_at = $nowUtc.ToString("o")
            source = $watchdogId
            issue_code = $issueCode
            issue_detail = $issueDetail
            task_state = $taskState
            progress_classification = $progressClassification
            recovery_attempts = $recoveryAttempts
            consecutive_freezes = $consecutiveFreezes
            requested_actions = @(
                "restart_listener",
                "restart_ui_if_needed",
                "run_health_test",
                "resume_processing"
            )
            verification = [pscustomobject]@{
                listener_running = $listenerRecovered
                ui_healthy = $uiRecovered
                passed = $recoveryOk
            }
            status = if ($recoveryOk) { "completed" } else { "failed" }
        }
        Write-JsonFile -PathValue $selfHealOrderPath -Payload $selfHealOrder

        $alertPayload = [pscustomobject]@{
            generated_at = $nowUtc.ToString("o")
            packet_type = "tod-mim-recovery-alert-v1"
            source = $watchdogId
            issue_code = $issueCode
            issue_detail = $issueDetail
            recovery_action = $recoveryAction
            recovery_ok = $recoveryOk
            task_state = $taskState
            progress_classification = $progressClassification
            ui_port = $UiPort
            request_id = $requestId
            listener_last_processed_request_id = $lastProcessedId
            listener_last_cycle_at = if ($null -ne $lastCycleAt) { $lastCycleAt.ToUniversalTime().ToString("o") } else { "" }
            last_task_heartbeat = if ($null -ne $lastTaskHeartbeatAt) { $lastTaskHeartbeatAt.ToString("o") } else { "" }
            heartbeat_age_seconds = $heartbeatAgeSeconds
            stall_threshold_seconds = $stallThresholdSeconds
            recovery_attempts = $recoveryAttempts
            consecutive_freezes = $consecutiveFreezes
            last_recovery_time = $lastRecoveryTime
            journal_last_status = $lastJournalStatus
            journal_last_timestamp = if ($null -ne $lastJournalAt) { $lastJournalAt.ToUniversalTime().ToString("o") } else { "" }
            self_heal_order_path = $selfHealOrderPath
        }

        $alertSignature = Get-AlertSignature -IssueCode $issueCode -IssueDetail $issueDetail -RecoveryAction $recoveryAction -RequestId $requestId -LastProcessedId $lastProcessedId
        $alertPublished = $false
        $alertPublishReason = "cooldown_skipped"
        $shouldPublishAlert = $true
        if (-not [string]::IsNullOrWhiteSpace($lastAlertPublishedAt) -and [string]::Equals($alertSignature, $lastAlertSignature, [System.StringComparison]::OrdinalIgnoreCase)) {
            try {
                $lastAlertPublishedAtUtc = ([datetime]$lastAlertPublishedAt).ToUniversalTime()
                $secondsSinceAlert = ($nowUtc - $lastAlertPublishedAtUtc).TotalSeconds
                if ($secondsSinceAlert -lt $AlertCooldownSeconds) {
                    $shouldPublishAlert = $false
                    $alertPublishReason = "cooldown_active"
                }
            }
            catch {
            }
        }

        if ($shouldPublishAlert) {
            $publishResult = Publish-RecoveryAlertToMim -AlertPayload $alertPayload -LocalPacketPath $alertPacketPath -EnvPath $envAbs
            $alertPublished = [bool]$publishResult.uploaded
            $alertPublishReason = [string]$publishResult.reason
            if ($alertPublished) {
                $lastAlertSignature = $alertSignature
                $lastAlertPublishedAt = $nowUtc.ToString("o")
            }
        }

        $logEntry = [pscustomobject]@{
            timestamp = $nowUtc.ToString("o")
            source = $watchdogId
            state = if ($recoveryOk) { "recovered" } else { "error" }
            issue_code = $issueCode
            issue_detail = $issueDetail
            action = $recoveryAction
            recovery_ok = $recoveryOk
            task_state = $taskState
            progress_classification = $progressClassification
            last_task_heartbeat = if ($null -ne $lastTaskHeartbeatAt) { $lastTaskHeartbeatAt.ToString("o") } else { "" }
            heartbeat_age_seconds = $heartbeatAgeSeconds
            stall_threshold_seconds = $stallThresholdSeconds
            recovery_attempts = $recoveryAttempts
            consecutive_freezes = $consecutiveFreezes
            last_recovery_time = $lastRecoveryTime
            publish_uploaded = $alertPublished
            publish_reason = $alertPublishReason
            request_id = $requestId
            last_processed_request_id = $lastProcessedId
        }
        Add-JsonLine -PathValue $watchdogLogPath -Payload $logEntry

        $stateDoc = [pscustomobject]@{
            generated_at = $nowUtc.ToString("o")
            source = $watchdogId
            state = if ($recoveryOk) { "recovered" } else { "error" }
            task_state = $taskState
            progress_classification = $progressClassification
            last_check_at = $nowUtc.ToString("o")
            last_issue = $issueCode
            last_issue_detail = $issueDetail
            last_recovery_action = $recoveryAction
            last_recovery_ok = $recoveryOk
            last_task_heartbeat = if ($null -ne $lastTaskHeartbeatAt) { $lastTaskHeartbeatAt.ToString("o") } else { "" }
            heartbeat_age_seconds = $heartbeatAgeSeconds
            stall_threshold_seconds = $stallThresholdSeconds
            recovery_attempts = $recoveryAttempts
            consecutive_freezes = $consecutiveFreezes
            last_recovery_time = $lastRecoveryTime
            last_alert_signature = $lastAlertSignature
            last_alert_published_at = $lastAlertPublishedAt
            listener_running = $listenerRecovered
            ui_healthy = $uiRecovered
            request_id = $requestId
            last_processed_request_id = $lastProcessedId
        }
        Write-JsonFile -PathValue $watchdogStatePath -Payload $stateDoc

        Write-Warning ("[TOD-WATCHDOG] issue={0} action={1} recovered={2}" -f $issueCode, $recoveryAction, [string]$recoveryOk)
    }
    else {
        $consecutiveFreezes = 0
        $stateDoc = [pscustomobject]@{
            generated_at = $nowUtc.ToString("o")
            source = $watchdogId
            state = "healthy"
            task_state = $taskState
            progress_classification = $progressClassification
            last_check_at = $nowUtc.ToString("o")
            last_issue = ""
            last_issue_detail = ""
            last_recovery_action = "none"
            last_recovery_ok = $null
            last_task_heartbeat = if ($null -ne $lastTaskHeartbeatAt) { $lastTaskHeartbeatAt.ToString("o") } else { "" }
            heartbeat_age_seconds = $heartbeatAgeSeconds
            stall_threshold_seconds = $stallThresholdSeconds
            recovery_attempts = $recoveryAttempts
            consecutive_freezes = $consecutiveFreezes
            last_recovery_time = $lastRecoveryTime
            last_alert_signature = $lastAlertSignature
            last_alert_published_at = $lastAlertPublishedAt
            listener_running = $listenerRunning
            ui_healthy = $uiHealthy
            request_id = $requestId
            last_processed_request_id = $lastProcessedId
        }
        Write-JsonFile -PathValue $watchdogStatePath -Payload $stateDoc
    }

    if ($RunOnce) { break }
    Start-Sleep -Seconds $CheckEverySeconds
}

Write-Host "[TOD-WATCHDOG] Stopped."
