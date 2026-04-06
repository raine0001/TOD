param(
    [int]$Port = 8844,
    [switch]$OpenAppWindow,
    [switch]$NoAutoOpen,
    [string]$AdvertiseHost = '',
    [switch]$LocalOnly,
    [switch]$AllowPortFallback
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiRoot = Join-Path $repoRoot "ui"
$indexPath = Join-Path $uiRoot "index.html"
$todScript = Join-Path $PSScriptRoot "TOD.ps1"
$configPath = Join-Path $repoRoot "tod/config/tod-config.json"
$defaultLogPath = Join-Path $repoRoot "tod/out/mim-http.log"
$uiCrashLogPath = Join-Path $repoRoot "tod/out/tod-ui-crash.log"
$uiStartupDiagnosticPath = Join-Path $repoRoot "tod/out/tod-ui-startup.latest.json"
$uiLanProxyScriptPath = Join-Path $PSScriptRoot "tod_ui_lan_proxy.py"
$statePath = Join-Path $repoRoot "tod/data/state.json"
$maxStateReadBytes = 256MB
$lightweightStateBusScript = Join-Path $PSScriptRoot "Get-TODLightweightStateBus.ps1"
$listenerStagePath = Join-Path $repoRoot "tod/out/context-sync/listener"
$contextSyncPath = Join-Path $repoRoot "tod/out/context-sync"
$contextSyncSshSharedPath = Join-Path $contextSyncPath "ssh-shared"
$listenerJournalPath = Join-Path $listenerStagePath "TOD_LOOP_JOURNAL.latest.json"
$listenerResultPath = Join-Path $listenerStagePath "TOD_MIM_TASK_RESULT.latest.json"
$listenerRequestPath = Join-Path $listenerStagePath "MIM_TOD_TASK_REQUEST.latest.json"
$listenerCommandStatusPath = Join-Path $listenerStagePath "TOD_MIM_COMMAND_STATUS.latest.json"
$mimExportCanonicalPath = Join-Path $contextSyncSshSharedPath "MIM_CONTEXT_EXPORT.latest.json"
$mimExportFallbackPath = Join-Path $contextSyncPath "MIM_CONTEXT_EXPORT.latest.json"
$mimHandshakeCanonicalPath = Join-Path $contextSyncSshSharedPath "MIM_TOD_HANDSHAKE_PACKET.latest.json"
$mimHandshakeFallbackPath = Join-Path $contextSyncPath "MIM_TOD_HANDSHAKE_PACKET.latest.json"
$listenerTriggerAckPath = Join-Path $listenerStagePath "TOD_TO_MIM_TRIGGER_ACK.latest.json"
$listenerPingResponsePath = Join-Path $listenerStagePath "TOD_TO_MIM_PING.latest.json"
$listenerStatePath = Join-Path $listenerStagePath "listener_state.json"
$coordinationEscalationPath = Join-Path $listenerStagePath "TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json"
$regressionStallStatePath = Join-Path $listenerStagePath "TOD_REGRESSION_STALL_STATE.latest.json"
$currentBuildStatePath = Join-Path $repoRoot "shared_state/current_build_state.json"
$sharedObjectivesPath = Join-Path $repoRoot "shared_state/objectives.json"
$nextActionsPath = Join-Path $repoRoot "shared_state/next_actions.json"
$recoveryWatchdogStatePath = Join-Path $repoRoot "shared_state/tod_recovery_watchdog.latest.json"
$selfHealthMaintenanceReportPath = Join-Path $repoRoot "shared_state/TOD_SELF_HEALTH_RUN.latest.json"
$operatorChatActionAuditLogPath = Join-Path $repoRoot "shared_state/tod_operator_chat_action_audit.log.jsonl"
$operatorChatActionAuditLatestPath = Join-Path $repoRoot "shared_state/tod_operator_chat_action_audit.latest.json"
$operatorChatReasoningLogPath = Join-Path $repoRoot "shared_state/tod_operator_chat_reasoning.log.jsonl"
$operatorChatReasoningLatestPath = Join-Path $repoRoot "shared_state/tod_operator_chat_reasoning.latest.json"
$operatorChatCommitmentLogPath = Join-Path $repoRoot "shared_state/tod_operator_chat_commitment.log.jsonl"
$operatorChatCommitmentLatestPath = Join-Path $repoRoot "shared_state/tod_operator_chat_commitment.latest.json"
$operatorChatFeedbackLogPath = Join-Path $repoRoot "shared_state/tod_operator_chat_feedback.log.jsonl"
$operatorChatFeedbackLatestPath = Join-Path $repoRoot "shared_state/tod_operator_chat_feedback.latest.json"
$dialogDirPath = Join-Path $repoRoot "shared_state/dialog"
$dialogSessionIndexPath = Join-Path $dialogDirPath "MIM_TOD_DIALOG.sessions.latest.json"
$dialogChannelPath = Join-Path $dialogDirPath "MIM_TOD_DIALOG.latest.jsonl"
$mimDialogScriptPath = Join-Path $PSScriptRoot "Invoke-TODMimDialog.ps1"
$operatorChatActionPreviewTtlMinutes = 10
$operatorChatActionPreviewRegistry = @{}
$operatorChatQueryCacheTtlSeconds = 120
$operatorChatMimReplyTimeoutSeconds = 4
$operatorChatMimReplyPollIntervalMilliseconds = 1000
$operatorChatMimRemoteConnectionTimeoutMilliseconds = 3000
$operatorChatQueryCache = @{}
$operatorChatParsedLogCache = @{}
$uiCrashLogDedupeWindowSeconds = 300
$uiCrashLogDedupeRegistry = @{}
$operatorChatValidationHarnessProfiles = @{
    'multi_objective_compare' = [pscustomobject]@{
        name = 'multi_objective_compare'
        label = 'bounded multi-objective compare'
        alternate_objective_id = 'validation-live-compare'
        alternate_title = 'Validation Live Compare Objective'
        alternate_status = 'warning'
        alternate_priority = 'validation'
        alternate_progress_percent = 63
        alternate_task_count = 8
        alternate_completed_equivalent = 5.0
        alternate_progress_source = 'validation_harness'
        listener_request_suffix = 'validation-live-compare'
        comparison_profile = 'full'
    }
    'compare_bridge' = [pscustomobject]@{
        name = 'compare_bridge'
        label = 'bounded bridge compare'
        alternate_objective_id = 'validation-compare-bridge'
        alternate_title = 'Validation Bridge Compare Objective'
        alternate_status = 'warning'
        alternate_priority = 'validation'
        alternate_progress_percent = 58
        alternate_task_count = 7
        alternate_completed_equivalent = 4.0
        alternate_progress_source = 'validation_harness'
        listener_request_suffix = 'validation-compare-bridge'
        comparison_profile = 'bridge'
    }
    'compare_cadence' = [pscustomobject]@{
        name = 'compare_cadence'
        label = 'bounded cadence compare'
        alternate_objective_id = 'validation-compare-cadence'
        alternate_title = 'Validation Cadence Compare Objective'
        alternate_status = 'warning'
        alternate_priority = 'validation'
        alternate_progress_percent = 61
        alternate_task_count = 7
        alternate_completed_equivalent = 4.5
        alternate_progress_source = 'validation_harness'
        listener_request_suffix = 'validation-compare-cadence'
        comparison_profile = 'cadence'
    }
    'compare_objective_status' = [pscustomobject]@{
        name = 'compare_objective_status'
        label = 'bounded objective-status compare'
        alternate_objective_id = 'validation-compare-objective'
        alternate_title = 'Validation Objective Status Compare Objective'
        alternate_status = 'warning'
        alternate_priority = 'validation'
        alternate_progress_percent = 49
        alternate_task_count = 6
        alternate_completed_equivalent = 3.0
        alternate_progress_source = 'validation_harness'
        listener_request_suffix = 'validation-compare-objective'
        comparison_profile = 'objective_status'
    }
}
$voiceAdapterConfigPath = Join-Path $repoRoot "tod/config/voice-adapter.json"
$voiceAdapterTelemetryPath = Join-Path $repoRoot "shared_state/voice_adapter_status.json"
$voiceAdapterInboxPath = Join-Path $repoRoot "tod/inbox/voice/events"
$voiceListenerPidPath = Join-Path $repoRoot "shared_state/voice_listener.pid"
$shareArtifacts = [ordered]@{
    "chatgpt_update_md" = [pscustomobject]@{ label = "ChatGPT Update (Markdown)"; path = (Join-Path $repoRoot "shared_state/chatgpt_update.md") }
    "chatgpt_update_json" = [pscustomobject]@{ label = "ChatGPT Update (JSON)"; path = (Join-Path $repoRoot "shared_state/chatgpt_update.json") }
    "shared_development_log_plan" = [pscustomobject]@{ label = "Shared Development Log Plan"; path = (Join-Path $repoRoot "shared_state/shared_development_log_plan.json") }
    "mim_context_export_latest_json" = [pscustomobject]@{ label = "MIM Context Export (Latest JSON)"; path = (Join-Path $repoRoot "tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.json") }
    "mim_context_export_latest_yaml" = [pscustomobject]@{ label = "MIM Context Export (Latest YAML)"; path = (Join-Path $repoRoot "tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.yaml") }
    "formal_pass_receipt_latest" = [pscustomobject]@{ label = "Formal Pass Receipt (Latest)"; path = (Join-Path $repoRoot "tod/out/context-sync/exports/TOD_FORMAL_PASS_RECEIPT.latest.json") }
}

if (-not (Test-Path -Path $indexPath)) {
    throw "UI file not found at $indexPath"
}
if (-not (Test-Path -Path $todScript)) {
    throw "TOD script not found at $todScript"
}

function Resolve-AppBrowserPath {
    $commandCandidates = @("msedge.exe", "chrome.exe")
    foreach ($cmdName in $commandCandidates) {
        try {
            $cmd = Get-Command -Name $cmdName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
                return [string]$cmd.Source
            }
        }
        catch {
        }
    }

    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Get-TodUiBaseUrl {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port
    )

    return ("http://{0}:{1}" -f $HostName.Trim(), $Port)
}

function Resolve-TodUiAdvertiseHost {
    param(
        [string]$ExplicitHost,
        [bool]$LocalOnlyMode
    )

    if ($LocalOnlyMode) {
        return 'localhost'
    }

    foreach ($candidate in @($ExplicitHost, $env:TOD_UI_HOST, $env:TOD_UI_ADVERTISE_HOST)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
            return [string]$candidate.Trim()
        }
    }

    try {
        $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
            $_.IPAddress -and
            $_.IPAddress -ne '127.0.0.1' -and
            $_.IPAddress -notlike '169.254.*'
        })

        $preferred = @($addresses | Where-Object {
            $_.IPAddress -like '192.168.*' -or
            [string]$_.InterfaceAlias -match 'Ethernet|Wi-Fi'
        } | Select-Object -First 1)
        if (@($preferred).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$preferred[0].IPAddress)) {
            return [string]$preferred[0].IPAddress
        }

        $fallback = @($addresses | Select-Object -First 1)
        if (@($fallback).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$fallback[0].IPAddress)) {
            return [string]$fallback[0].IPAddress
        }
    }
    catch {
    }

    return 'localhost'
}

function Get-TodUiListenHosts {
    param(
        [string]$AdvertiseHost,
        [bool]$LocalOnlyMode
    )

    $hosts = New-Object System.Collections.Generic.List[string]
    [void]$hosts.Add('localhost')
    if (-not $LocalOnlyMode -and -not [string]::IsNullOrWhiteSpace([string]$AdvertiseHost) -and -not [string]::Equals([string]$AdvertiseHost, 'localhost', [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$hosts.Add([string]$AdvertiseHost)
    }

    return @($hosts | Select-Object -Unique)
}

function Get-TodUiListenerPrefixes {
    param(
        [Parameter(Mandatory = $true)][string[]]$ListenHosts,
        [Parameter(Mandatory = $true)][int]$Port
    )

    $prefixes = foreach ($listenHost in @($ListenHosts | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$listenHost)) {
            "http://{0}:{1}/" -f [string]$listenHost, $Port
        }
    }

    return @($prefixes | Select-Object -Unique)
}

function Test-TodUiProjectStatusUrl {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [int]$TimeoutSeconds = 2
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri (([string]$BaseUrl).TrimEnd('/') + '/api/project-status') -TimeoutSec $TimeoutSeconds
        return ($response.StatusCode -eq 200)
    }
    catch {
        return $false
    }
}

function Get-TodUiPortOwnerInfo {
    param([Parameter(Mandatory = $true)][int]$Port)

    $connection = $null
    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    catch {
        $connection = $null
    }

    if ($null -eq $connection) {
        return [pscustomobject]@{
            port = $Port
            in_use = $false
            process_id = 0
            process_name = ''
            command_line = ''
            is_tod_ui_process = $false
            is_tod_ui_proxy_process = $false
        }
    }

    $processId = 0
    try { $processId = [int]$connection.OwningProcess } catch { $processId = 0 }
    $process = $null
    if ($processId -gt 0) {
        try {
            $process = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f $processId) -ErrorAction SilentlyContinue
        }
        catch {
            $process = $null
        }
    }

    $commandLine = if ($process -and $process.CommandLine) { [string]$process.CommandLine } else { '' }
    $processName = if ($process -and $process.Name) { [string]$process.Name } else { '' }

    return [pscustomobject]@{
        port = $Port
        in_use = $true
        process_id = $processId
        process_name = $processName
        command_line = $commandLine
        is_tod_ui_process = ($commandLine -like '*Start-TOD-UI.ps1*')
        is_tod_ui_proxy_process = ($commandLine -like '*tod_ui_lan_proxy.py*')
    }
}

function Get-TodUiProxyTargetPort {
    param($PortOwnerInfo)

    if ($null -eq $PortOwnerInfo -or -not $PortOwnerInfo.PSObject.Properties['command_line']) {
        return 0
    }

    $commandLine = [string]$PortOwnerInfo.command_line
    $match = [regex]::Match($commandLine, '--target-port\s+(\d+)')
    if ($match.Success) {
        return [int]$match.Groups[1].Value
    }

    return 0
}

function Test-TodUiPortFree {
    param([Parameter(Mandatory = $true)][int]$Port)

    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        return ($null -eq $connection)
    }
    catch {
        return $true
    }
}

function Find-TodUiInternalPort {
    param(
        [Parameter(Mandatory = $true)][int]$StartPort,
        [int]$MaxAttempts = 20
    )

    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        $candidate = $StartPort + $i
        if (Test-TodUiPortFree -Port $candidate) {
            return $candidate
        }
    }

    throw "Unable to find a free internal TOD UI listener port starting at $StartPort."
}

function Stop-TodUiProcessIfOwned {
    param([Parameter(Mandatory = $true)]$PortOwnerInfo)

    if (-not $PortOwnerInfo -or -not [bool]$PortOwnerInfo.in_use -or -not [bool]$PortOwnerInfo.is_tod_ui_process -or [int]$PortOwnerInfo.process_id -le 0) {
        return $false
    }

    try {
        Stop-Process -Id ([int]$PortOwnerInfo.process_id) -Force -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function New-TodUiStartupDiagnostic {
    param(
        [bool]$Ok,
        [string]$Status,
        [string]$Reason,
        [string]$Message,
        [int]$Port,
        [string[]]$ListenHosts,
        [string[]]$ListenerPrefixes,
        [string]$AdvertiseHost,
        [string]$AdvertiseUrl,
        $PortOwnerInfo,
        [string]$RecoveryAction = 'none',
        [string]$FailureDetail = ''
    )

    return [pscustomobject]@{
        ok = $Ok
        status = $Status
        reason = $Reason
        message = $Message
        port = $Port
        advertise_host = $AdvertiseHost
        advertise_url = $AdvertiseUrl
        listen_hosts = @($ListenHosts)
        listener_prefixes = @($ListenerPrefixes)
        recovery_action = $RecoveryAction
        failure_detail = $FailureDetail
        port_owner = if ($PortOwnerInfo) {
            [pscustomobject]@{
                in_use = [bool]$PortOwnerInfo.in_use
                process_id = if ($PortOwnerInfo.PSObject.Properties['process_id']) { [int]$PortOwnerInfo.process_id } else { 0 }
                process_name = if ($PortOwnerInfo.PSObject.Properties['process_name']) { [string]$PortOwnerInfo.process_name } else { '' }
                command_line = if ($PortOwnerInfo.PSObject.Properties['command_line']) { [string]$PortOwnerInfo.command_line } else { '' }
                is_tod_ui_process = if ($PortOwnerInfo.PSObject.Properties['is_tod_ui_process']) { [bool]$PortOwnerInfo.is_tod_ui_process } else { $false }
            }
        }
        else {
            $null
        }
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Write-TodUiStartupDiagnostic {
    param(
        [bool]$Ok,
        [string]$Status,
        [string]$Reason,
        [string]$Message,
        [int]$Port,
        [string[]]$ListenHosts,
        [string[]]$ListenerPrefixes,
        [string]$AdvertiseHost,
        [string]$AdvertiseUrl,
        $PortOwnerInfo,
        [string]$RecoveryAction = 'none',
        [string]$FailureDetail = ''
    )

    $doc = New-TodUiStartupDiagnostic -Ok:$Ok -Status $Status -Reason $Reason -Message $Message -Port $Port -ListenHosts $ListenHosts -ListenerPrefixes $ListenerPrefixes -AdvertiseHost $AdvertiseHost -AdvertiseUrl $AdvertiseUrl -PortOwnerInfo $PortOwnerInfo -RecoveryAction $RecoveryAction -FailureDetail $FailureDetail
    $directory = Split-Path -Parent $uiStartupDiagnosticPath
    if (-not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($uiStartupDiagnosticPath, (($doc | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"), $utf8NoBom)
    return $doc
}

function Wait-TodUiReady {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSeconds = 5
    )

    $deadline = (Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
    while ((Get-Date).ToUniversalTime() -lt $deadline) {
        try {
            $request = [System.Net.WebRequest]::Create($Url)
            $request.Method = "GET"
            $request.Timeout = 1000
            $request.ReadWriteTimeout = 1000
            $response = $request.GetResponse()
            try {
                return $true
            }
            finally {
                if ($response) {
                    $response.Close()
                }
            }
        }
        catch {
            Start-Sleep -Milliseconds 200
        }
    }

    return $false
}

function Resolve-TodUiProxyPythonPath {
    $venvPython = Join-Path $repoRoot '.venv/Scripts/python.exe'
    if (Test-Path -Path $venvPython) {
        return $venvPython
    }

    return 'python'
}

function Start-TodUiLanProxy {
    param(
        [Parameter(Mandatory = $true)][string]$ListenHost,
        [Parameter(Mandatory = $true)][int]$ListenPort,
        [Parameter(Mandatory = $true)][int]$TargetPort
    )

    if (-not (Test-Path -Path $uiLanProxyScriptPath)) {
        throw "TOD UI LAN proxy script not found at $uiLanProxyScriptPath"
    }

    $pythonPath = Resolve-TodUiProxyPythonPath
    $arguments = @(
        $uiLanProxyScriptPath,
        '--listen-host', $ListenHost,
        '--listen-port', [string]$ListenPort,
        '--target-host', '127.0.0.1',
        '--target-port', [string]$TargetPort
    )

    $process = Start-Process -FilePath $pythonPath -ArgumentList $arguments -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 1

    if ($process.HasExited) {
        try {
            if ($process -and -not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
        }
        throw ("TOD UI LAN proxy did not bind http://{0}:{1} within 10 seconds." -f $ListenHost, $ListenPort)
    }

    return $process
}

function Open-TodUiClient {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [bool]$AppMode
    )

    if ($NoAutoOpen) {
        Write-Host "Auto-open disabled. Browse to $Url"
        return
    }

    if (-not (Wait-TodUiReady -Url $Url)) {
        Write-UiCrashLogDeduped -Key "ui-not-ready-$Url" -Message "[AUTO-OPEN-DEFERRED] UI endpoint did not report ready before launch timeout: $Url" -WindowSeconds 60
        Write-Host "UI endpoint did not confirm readiness before launch timeout; opening anyway: $Url" -ForegroundColor Yellow
    }

    if ($AppMode) {
        $browserPath = Resolve-AppBrowserPath
        if ($null -ne $browserPath) {
            $launchArgs = @(
                "--app=$Url",
                "--new-window",
                "--start-maximized"
            )
            Start-Process -FilePath $browserPath -ArgumentList $launchArgs | Out-Null
            Write-Host "Opened TOD UI in app window: $Url"
            return
        }

        Write-Host "No app-capable Chromium browser found; opening regular browser window." -ForegroundColor Yellow
    }

    Start-Process $Url | Out-Null
    Write-Host "Opened TOD UI in browser: $Url"
}

$listener = $null
$activePort = $Port
$resolvedAdvertiseHost = Resolve-TodUiAdvertiseHost -ExplicitHost $AdvertiseHost -LocalOnlyMode ([bool]$LocalOnly)
$listenHosts = Get-TodUiListenHosts -AdvertiseHost $resolvedAdvertiseHost -LocalOnlyMode ([bool]$LocalOnly)
$bindingHosts = @('localhost')
$usePublicProxy = (-not [string]::Equals($resolvedAdvertiseHost, 'localhost', [System.StringComparison]::OrdinalIgnoreCase))
$candidatePorts = if ($AllowPortFallback) { @($Port..($Port + 14)) } else { @($Port) }
$activePrefixes = @()
$uiUrl = Get-TodUiBaseUrl -HostName $resolvedAdvertiseHost -Port $Port
$uiLanProxyProcess = $null
$activeListenerPort = $Port
$started = $false

foreach ($candidatePort in $candidatePorts) {
    $listenerPort = if ($usePublicProxy) { Find-TodUiInternalPort -StartPort ($candidatePort + 10000) } else { $candidatePort }
    $candidatePrefixes = Get-TodUiListenerPrefixes -ListenHosts $bindingHosts -Port $listenerPort
    $candidateUiUrl = Get-TodUiBaseUrl -HostName $resolvedAdvertiseHost -Port $candidatePort
    $healthyUrls = @($listenHosts | ForEach-Object {
        $baseUrl = Get-TodUiBaseUrl -HostName ([string]$_) -Port $candidatePort
        if (Test-TodUiProjectStatusUrl -BaseUrl $baseUrl -TimeoutSeconds 2) {
            $baseUrl
        }
    })
    $portOwner = Get-TodUiPortOwnerInfo -Port $candidatePort

    if (@($healthyUrls).Count -eq @($listenHosts).Count) {
        $null = Write-TodUiStartupDiagnostic -Ok:$true -Status 'already_running' -Reason 'healthy_existing_instance' -Message ('TOD UI already running at {0}' -f $candidateUiUrl) -Port $candidatePort -ListenHosts $listenHosts -ListenerPrefixes $candidatePrefixes -AdvertiseHost $resolvedAdvertiseHost -AdvertiseUrl $candidateUiUrl -PortOwnerInfo (Get-TodUiPortOwnerInfo -Port $candidatePort)
        Write-Host "TOD UI already running at $candidateUiUrl/"
        if (-not [string]::Equals($resolvedAdvertiseHost, 'localhost', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ("TOD UI loopback endpoint also available at {0}/" -f (Get-TodUiBaseUrl -HostName 'localhost' -Port $candidatePort))
        }
        Open-TodUiClient -Url $candidateUiUrl -AppMode ([bool]$OpenAppWindow)
        return
    }

    $proxyTargetPort = if ([bool]$portOwner.is_tod_ui_proxy_process) { Get-TodUiProxyTargetPort -PortOwnerInfo $portOwner } else { 0 }
    if ([bool]$portOwner.is_tod_ui_proxy_process -and $proxyTargetPort -gt 0 -and -not (Test-TodUiPortFree -Port $proxyTargetPort)) {
        $null = Write-TodUiStartupDiagnostic -Ok:$true -Status 'already_running' -Reason 'healthy_existing_proxy' -Message ('TOD UI already running at {0}' -f $candidateUiUrl) -Port $candidatePort -ListenHosts $listenHosts -ListenerPrefixes $candidatePrefixes -AdvertiseHost $resolvedAdvertiseHost -AdvertiseUrl $candidateUiUrl -PortOwnerInfo $portOwner
        Write-Host "TOD UI already running at $candidateUiUrl/"
        if (-not [string]::Equals($resolvedAdvertiseHost, 'localhost', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ("TOD UI loopback endpoint also available at {0}/" -f (Get-TodUiBaseUrl -HostName 'localhost' -Port $candidatePort))
        }
        Open-TodUiClient -Url $candidateUiUrl -AppMode ([bool]$OpenAppWindow)
        return
    }

    if ([bool]$portOwner.in_use) {
        $reclaimed = $false
        if ([bool]$portOwner.is_tod_ui_process) {
            $reclaimed = Stop-TodUiProcessIfOwned -PortOwnerInfo $portOwner
            if ($reclaimed) {
                Start-Sleep -Milliseconds 750
                $portOwner = Get-TodUiPortOwnerInfo -Port $candidatePort
            }
        }

        if ([bool]$portOwner.in_use) {
            if ($AllowPortFallback -and $candidatePort -ne @($candidatePorts)[-1]) {
                continue
            }

            $reason = if ($reclaimed) { 'stale_tod_ui_port_not_reclaimed' } else { 'port_in_use' }
            $message = if ($reclaimed) { "Requested UI port $candidatePort could not be reclaimed from a stale TOD UI process." } else { "Requested UI port $candidatePort is already in use." }
            $null = Write-TodUiStartupDiagnostic -Ok:$false -Status 'failed' -Reason $reason -Message $message -Port $candidatePort -ListenHosts $listenHosts -ListenerPrefixes $candidatePrefixes -AdvertiseHost $resolvedAdvertiseHost -AdvertiseUrl $candidateUiUrl -PortOwnerInfo $portOwner -RecoveryAction $(if ($AllowPortFallback) { 'try_next_port' } else { 'free_requested_port' })
            throw ("TOD UI startup failed ({0}): {1} See {2}" -f $reason, $message, $uiStartupDiagnosticPath)
        }
    }

    $candidate = New-Object System.Net.HttpListener
    foreach ($prefix in $candidatePrefixes) {
        [void]$candidate.Prefixes.Add($prefix)
    }

    try {
        $candidate.Start()
        $listener = $candidate
        $activePort = $candidatePort
        $activeListenerPort = $listenerPort
        $activePrefixes = $candidatePrefixes
        $uiUrl = $candidateUiUrl
        $started = $true
        break
    }
    catch {
        $candidate.Close()
        $detail = [string]$_.Exception.Message
        $reason = if ($detail -match 'Access is denied') { 'url_acl_denied' } elseif ($detail -match 'conflict|Cannot create a file when that file already exists|in use') { 'port_in_use' } else { 'listener_start_failed' }

        if ($AllowPortFallback -and $candidatePort -ne @($candidatePorts)[-1]) {
            continue
        }

        $null = Write-TodUiStartupDiagnostic -Ok:$false -Status 'failed' -Reason $reason -Message 'TOD UI listener could not bind to the requested startup prefixes.' -Port $candidatePort -ListenHosts $listenHosts -ListenerPrefixes $candidatePrefixes -AdvertiseHost $resolvedAdvertiseHost -AdvertiseUrl $candidateUiUrl -PortOwnerInfo (Get-TodUiPortOwnerInfo -Port $candidatePort) -RecoveryAction $(if ($reason -eq 'url_acl_denied') { 'grant_url_acl_or_use_localonly' } else { 'free_requested_port' }) -FailureDetail $detail
        throw ("TOD UI startup failed ({0}): {1} See {2}" -f $reason, $detail, $uiStartupDiagnosticPath)
    }
}

if (-not $started -or $null -eq $listener) {
    $null = Write-TodUiStartupDiagnostic -Ok:$false -Status 'failed' -Reason 'listener_not_started' -Message 'Failed to start TOD UI listener.' -Port $Port -ListenHosts $listenHosts -ListenerPrefixes (Get-TodUiListenerPrefixes -ListenHosts $listenHosts -Port $Port) -AdvertiseHost $resolvedAdvertiseHost -AdvertiseUrl (Get-TodUiBaseUrl -HostName $resolvedAdvertiseHost -Port $Port) -PortOwnerInfo (Get-TodUiPortOwnerInfo -Port $Port)
    throw "Failed to start TOD UI listener. See $uiStartupDiagnosticPath"
}

if ($activePort -ne $Port) {
    Write-Host "Requested port $Port was unavailable; using $activePort instead."
}

if ($usePublicProxy) {
    try {
        $uiLanProxyProcess = Start-TodUiLanProxy -ListenHost '0.0.0.0' -ListenPort $activePort -TargetPort $activeListenerPort
    }
    catch {
        try {
            if ($listener -and $listener.IsListening) {
                $listener.Stop()
            }
            if ($listener) {
                $listener.Close()
            }
        }
        catch {
        }

        $null = Write-TodUiStartupDiagnostic -Ok:$false -Status 'failed' -Reason 'lan_proxy_failed' -Message 'TOD UI localhost listener started, but the LAN proxy failed to publish the advertised URL.' -Port $activePort -ListenHosts $listenHosts -ListenerPrefixes $activePrefixes -AdvertiseHost $resolvedAdvertiseHost -AdvertiseUrl $uiUrl -PortOwnerInfo (Get-TodUiPortOwnerInfo -Port $activePort) -RecoveryAction 'check_bind_address_or_proxy_host' -FailureDetail ([string]$_.Exception.Message)
        throw ("TOD UI startup failed (lan_proxy_failed): {0} See {1}" -f $_.Exception.Message, $uiStartupDiagnosticPath)
    }
}

Write-Host "TOD UI running at $uiUrl/"
if ($usePublicProxy) {
    Write-Host ("TOD UI loopback endpoint also available at {0}/" -f (Get-TodUiBaseUrl -HostName 'localhost' -Port $activePort))
}
Write-Host "Press Ctrl+C to stop."

$null = Write-TodUiStartupDiagnostic -Ok:$true -Status $(if ($activePort -eq $Port) { 'started' } else { 'started_with_fallback' }) -Reason $(if ($activePort -eq $Port) { 'listener_started' } else { 'fallback_port_used' }) -Message ('TOD UI ready at {0}' -f $uiUrl) -Port $activePort -ListenHosts $listenHosts -ListenerPrefixes $activePrefixes -AdvertiseHost $resolvedAdvertiseHost -AdvertiseUrl $uiUrl -PortOwnerInfo (Get-TodUiPortOwnerInfo -Port $activePort) -RecoveryAction 'none'
Open-TodUiClient -Url $uiUrl -AppMode ([bool]$OpenAppWindow)

function Write-UiCrashLog {
    param([string]$Message)
    try {
        $line = "[{0}] {1}" -f (Get-Date).ToUniversalTime().ToString("o"), $Message
        Add-Content -Path $uiCrashLogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

function Write-UiCrashLogDeduped {
    param(
        [string]$Key,
        [string]$Message,
        [int]$WindowSeconds = 0
    )

    if ([string]::IsNullOrWhiteSpace([string]$Message)) {
        return
    }

    $resolvedKey = if ([string]::IsNullOrWhiteSpace([string]$Key)) { [string]$Message } else { [string]$Key }
    $resolvedWindowSeconds = if ($WindowSeconds -gt 0) { [int]$WindowSeconds } else { [int]$uiCrashLogDedupeWindowSeconds }
    $now = (Get-Date).ToUniversalTime()

    try {
        if ($uiCrashLogDedupeRegistry.ContainsKey($resolvedKey)) {
            $lastWrittenAt = $uiCrashLogDedupeRegistry[$resolvedKey]
            if ($lastWrittenAt -is [datetime] -and $lastWrittenAt.AddSeconds($resolvedWindowSeconds) -gt $now) {
                return
            }
        }
        $uiCrashLogDedupeRegistry[$resolvedKey] = $now
    }
    catch {
    }

    Write-UiCrashLog $Message
}

function Write-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
        $Response.StatusCode = $StatusCode
        $Response.ContentType = "application/json; charset=utf-8"
        $Response.ContentLength64 = $bytes.LongLength
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    catch {
        # Response may already be committed; avoid cascading failures in endpoint catch blocks.
        Write-UiCrashLog ("[WRITE-JSON-ERROR] " + $_.Exception.Message)
    }
    finally {
        try {
            if ($Response -and $Response.OutputStream) {
                $Response.OutputStream.Close()
            }
        }
        catch {
        }
        try {
            $Response.Close()
        }
        catch {
        }
    }
}

function Write-BytesResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,
        [Parameter(Mandatory = $true)]
        [string]$ContentType,
        [hashtable]$Headers = $null
    )

    try {
        $Response.StatusCode = $StatusCode
        $Response.ContentType = $ContentType
        if ($Headers) {
            foreach ($headerName in $Headers.Keys) {
                $Response.AddHeader([string]$headerName, [string]$Headers[$headerName])
            }
        }
        $Response.ContentLength64 = $Bytes.LongLength
        $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    }
    catch {
        Write-UiCrashLog ("[WRITE-BYTES-ERROR] " + $_.Exception.Message)
    }
    finally {
        try {
            if ($Response -and $Response.OutputStream) {
                $Response.OutputStream.Close()
            }
        }
        catch {
        }
        try {
            $Response.Close()
        }
        catch {
        }
    }
}

function Write-TextResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [string]$ContentType = "text/plain; charset=utf-8"
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    Write-BytesResponse -Response $Response -StatusCode $StatusCode -Bytes $bytes -ContentType $ContentType
}

function Test-ShouldUseLightweightStateBus {
    if (-not (Test-Path -Path $statePath)) {
        return $true
    }

    try {
        $item = Get-Item -Path $statePath -ErrorAction Stop
        return ([int64]$item.Length -gt [int64]$maxStateReadBytes)
    }
    catch {
        return $true
    }
}

function Invoke-LightweightUiAction {
    param(
        [Parameter(Mandatory = $true)][string]$Action
    )

    if (-not (Test-Path -Path $lightweightStateBusScript)) {
        throw "Missing lightweight state bus script: $lightweightStateBusScript"
    }

    $raw = & $lightweightStateBusScript -AsJson
    $payload = $raw | ConvertFrom-Json

    switch ($Action) {
        "get-state-bus" { return $payload }
        "get-reliability" { return $payload.reliability }
        "show-reliability-dashboard" { return $payload.reliability_dashboard }
        "show-failure-taxonomy" { return $payload.failure_taxonomy }
        "get-engineering-loop-summary" { return $payload.engineering_summary }
        "get-engineering-signal" { return $payload.engineering_signal }
        "get-engineering-loop-history" { return $payload.scorecard_history }
        default {
            throw "Unsupported lightweight action: $Action"
        }
    }
}

function Get-RecentLogLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [int]$Tail = 80
    )

    if (-not (Test-Path -Path $LogPath)) {
        return @()
    }

    $safeTail = if ($Tail -lt 1) { 1 } elseif ($Tail -gt 500) { 500 } else { $Tail }
    $content = ''
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        try {
            $stream = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
                try {
                    $content = $reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                }
            }
            finally {
                $stream.Dispose()
            }
            break
        }
        catch {
            if ($attempt -ge 5) {
                return @()
            }
            Start-Sleep -Milliseconds 40
        }
    }

    if ([string]::IsNullOrWhiteSpace($content)) {
        return @()
    }

    $lines = $content -split "`r?`n"
    if ($lines.Count -le $safeTail) {
        return @($lines)
    }

    return @($lines[($lines.Count - $safeTail)..($lines.Count - 1)])
}

function Get-RecentParsedLogEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [int]$Tail = 80
    )

    if (-not (Test-Path -Path $LogPath)) {
        return @()
    }

    $safeTail = if ($Tail -lt 1) { 1 } elseif ($Tail -gt 500) { 500 } else { $Tail }
    $file = Get-Item -Path $LogPath -ErrorAction SilentlyContinue
    $cacheKey = '{0}|{1}' -f $LogPath, $safeTail
    $cacheStamp = if ($file) { '{0}|{1}' -f $file.LastWriteTimeUtc.Ticks, $file.Length } else { '' }
    if ($operatorChatParsedLogCache.ContainsKey($cacheKey)) {
        $cached = $operatorChatParsedLogCache[$cacheKey]
        if ($cached -and [string]::Equals([string]$cached.stamp, $cacheStamp, [System.StringComparison]::Ordinal)) {
            return @($cached.entries)
        }
    }

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-RecentLogLines -LogPath $LogPath -Tail $safeTail)) {
        if ([string]::IsNullOrWhiteSpace([string]$line)) {
            continue
        }

        try {
            $entry = $line | ConvertFrom-Json
            if ($null -ne $entry) {
                [void]$entries.Add($entry)
            }
        }
        catch {
        }
    }

    $parsedEntries = @($entries.ToArray())
    $operatorChatParsedLogCache[$cacheKey] = [pscustomobject]@{
        stamp = $cacheStamp
        entries = $parsedEntries
    }
    return $parsedEntries
}

function Write-OperatorChatJsonArtifactEntry {
    param(
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][string]$LatestPath,
        [Parameter(Mandatory = $true)]$Entry
    )

    $directory = Split-Path -Parent $LogPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        [void][System.IO.Directory]::CreateDirectory($directory)
    }

    $json = $Entry | ConvertTo-Json -Depth 20 -Compress

    function Write-OperatorChatUtf8File {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Content,
            [switch]$Append
        )

        $targetDirectory = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($targetDirectory)) {
            [void][System.IO.Directory]::CreateDirectory($targetDirectory)
        }

        $encoding = New-Object System.Text.UTF8Encoding($false)
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            try {
                $mode = if ($Append) { [System.IO.FileMode]::Append } else { [System.IO.FileMode]::Create }
                $stream = [System.IO.File]::Open($Path, $mode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                try {
                    $writer = New-Object System.IO.StreamWriter($stream, $encoding)
                    try {
                        if ($Append) {
                            $writer.WriteLine($Content)
                        }
                        else {
                            $writer.Write($Content)
                        }
                        $writer.Flush()
                        $stream.Flush()
                    }
                    finally {
                        $writer.Dispose()
                    }
                }
                finally {
                    $stream.Dispose()
                }
                return
            }
            catch {
                if ($attempt -ge 5) {
                    throw
                }
                Start-Sleep -Milliseconds 40
            }
        }
    }

    Write-OperatorChatUtf8File -Path $LogPath -Content $json -Append
    Write-OperatorChatUtf8File -Path $LatestPath -Content ($Entry | ConvertTo-Json -Depth 20)

    foreach ($cacheKey in @($operatorChatParsedLogCache.Keys)) {
        if ([string]$cacheKey -like ("{0}|*" -f $LogPath)) {
            $operatorChatParsedLogCache.Remove($cacheKey)
        }
    }
}

function Get-OperatorChatCapabilities {
    return [pscustomobject]@{
        intents = @(
            'summarize_status',
            'explain_warning',
            'explain_bridge_status',
            'explain_cadence',
            'explain_maintenance',
            'suggest_next_action',
            'summarize_current_objective',
            'summarize_recent_changes'
        )
        safe_actions = @(
            [pscustomobject]@{ action = 'get-reliability'; label = 'Get Reliability'; mode = 'read_only'; governed = $true; confirmation_required = $true },
            [pscustomobject]@{ action = 'get-state-bus'; label = 'Refresh State Bus'; mode = 'read_only'; governed = $true; confirmation_required = $true },
            [pscustomobject]@{ action = 'get-engineering-loop-summary'; label = 'Engineering Loop Summary'; mode = 'read_only'; governed = $true; confirmation_required = $true },
            [pscustomobject]@{ action = 'get-engineering-signal'; label = 'Engineering Signal'; mode = 'read_only'; governed = $true; confirmation_required = $true },
            [pscustomobject]@{ action = 'show-reliability-dashboard'; label = 'Reliability Dashboard'; mode = 'read_only'; governed = $true; confirmation_required = $true },
            [pscustomobject]@{ action = 'refresh-share-links'; label = 'Refresh Share Links'; mode = 'ui_refresh_only'; governed = $true; confirmation_required = $true },
            [pscustomobject]@{ action = 'quick-refresh-reliability'; label = 'Quick Refresh Reliability'; mode = 'ui_refresh_only'; governed = $true; confirmation_required = $true },
            [pscustomobject]@{ action = 'refresh-project-status'; label = 'Refresh Status Snapshot'; mode = 'read_only'; governed = $true; confirmation_required = $true },
            [pscustomobject]@{ action = 'recheck-bridge-diagnostics'; label = 'Re-check Bridge Diagnostics'; mode = 'read_only'; governed = $true; confirmation_required = $true },
            [pscustomobject]@{ action = 'refresh-governance-snapshot'; label = 'Refresh Governance Snapshot'; mode = 'read_only'; governed = $true; confirmation_required = $true },
            [pscustomobject]@{ action = 'refresh-bridge-alignment-bundle'; label = 'Refresh Bridge Alignment Bundle'; mode = 'read_only'; governed = $true; confirmation_required = $true }
        )
    }
}

function Write-OperatorChatActionAuditEntry {
    param(
        [Parameter(Mandatory = $true)]$Entry
    )

    Write-OperatorChatJsonArtifactEntry -LogPath $operatorChatActionAuditLogPath -LatestPath $operatorChatActionAuditLatestPath -Entry $Entry
}

function Write-OperatorChatReasoningEntry {
    param(
        [Parameter(Mandatory = $true)]$Entry
    )

    Write-OperatorChatJsonArtifactEntry -LogPath $operatorChatReasoningLogPath -LatestPath $operatorChatReasoningLatestPath -Entry $Entry
}

function Write-OperatorChatCommitmentEntry {
    param(
        [Parameter(Mandatory = $true)]$Entry
    )

    Write-OperatorChatJsonArtifactEntry -LogPath $operatorChatCommitmentLogPath -LatestPath $operatorChatCommitmentLatestPath -Entry $Entry
    Clear-OperatorChatQueryCache
}

function Clear-OperatorChatQueryCache {
    foreach ($key in @($operatorChatQueryCache.Keys)) {
        $operatorChatQueryCache.Remove($key)
    }
}

function Clear-ExpiredOperatorChatActionPreviews {
    $now = (Get-Date).ToUniversalTime()
    foreach ($key in @($operatorChatActionPreviewRegistry.Keys)) {
        $entry = $operatorChatActionPreviewRegistry[$key]
        if ($null -eq $entry) {
            $operatorChatActionPreviewRegistry.Remove($key)
            continue
        }

        $expiresAt = $null
        if ($entry.PSObject.Properties['expires_at'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.expires_at)) {
            try {
                $expiresAt = [datetime]::Parse([string]$entry.expires_at).ToUniversalTime()
            }
            catch {
                $expiresAt = $null
            }
        }

        if ($null -ne $expiresAt -and $expiresAt -le $now) {
            $operatorChatActionPreviewRegistry.Remove($key)
        }
    }
}

function Get-OperatorChatQueryCacheKey {
    param(
        [string]$Query,
        [string]$Intent,
        [string]$ObjectiveId,
        [int]$WindowMinutes = 10,
        [string]$ValidationHarness = ''
    )

    $normalizedQuery = ([string]$Query).Trim().ToLowerInvariant()
    $normalizedIntent = ([string]$Intent).Trim().ToLowerInvariant()
    $normalizedObjectiveId = ([string]$ObjectiveId).Trim().ToLowerInvariant()
    $normalizedValidationHarness = ([string]$ValidationHarness).Trim().ToLowerInvariant()
    return ('{0}|{1}|{2}|{3}|{4}' -f $normalizedObjectiveId, $normalizedIntent, [int]$WindowMinutes, $normalizedValidationHarness, $normalizedQuery)
}

function Clear-ExpiredOperatorChatQueryCache {
    $now = (Get-Date).ToUniversalTime()
    foreach ($key in @($operatorChatQueryCache.Keys)) {
        $entry = $operatorChatQueryCache[$key]
        if ($null -eq $entry) {
            $operatorChatQueryCache.Remove($key)
            continue
        }

        $expiresAt = $null
        if ($entry.PSObject.Properties['expires_at'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.expires_at)) {
            try {
                $expiresAt = [datetime]::Parse([string]$entry.expires_at).ToUniversalTime()
            }
            catch {
                $expiresAt = $null
            }
        }

        if ($null -eq $expiresAt -or $expiresAt -le $now) {
            $operatorChatQueryCache.Remove($key)
        }
    }
}

function Register-OperatorChatQueryCacheEntry {
    param(
        [string]$Query,
        [string]$Intent,
        [string]$ObjectiveId,
        [int]$WindowMinutes = 10,
        [string]$ValidationHarness = '',
        $Result
    )

    if ($null -eq $Result) {
        return
    }

    Clear-ExpiredOperatorChatQueryCache
    $createdAt = (Get-Date).ToUniversalTime()
    $expiresAt = $createdAt.AddSeconds($operatorChatQueryCacheTtlSeconds)
    $entry = [pscustomobject]@{
        query = [string]$Query
        intent = [string]$Intent
        objective_id = [string]$ObjectiveId
        window_minutes = [int]$WindowMinutes
        validation_harness = [string]$ValidationHarness
        created_at = $createdAt.ToString('o')
        expires_at = $expiresAt.ToString('o')
        result = $Result
    }

    $primaryKey = Get-OperatorChatQueryCacheKey -Query $Query -Intent $Intent -ObjectiveId $ObjectiveId -WindowMinutes $WindowMinutes -ValidationHarness $ValidationHarness
    $operatorChatQueryCache[$primaryKey] = $entry
}

function Get-CachedOperatorChatQueryResult {
    param(
        [string]$Query,
        [string]$Intent,
        [string]$ObjectiveId,
        [int]$WindowMinutes = 10,
        [string]$ValidationHarness = ''
    )

    Clear-ExpiredOperatorChatQueryCache
    $key = Get-OperatorChatQueryCacheKey -Query $Query -Intent $Intent -ObjectiveId $ObjectiveId -WindowMinutes $WindowMinutes -ValidationHarness $ValidationHarness
    if ($operatorChatQueryCache.ContainsKey($key)) {
        $entry = $operatorChatQueryCache[$key]
        if ($null -ne $entry -and $entry.PSObject.Properties['result']) {
            return $entry.result
        }
    }

    if ([string]::IsNullOrWhiteSpace($ValidationHarness)) {
        $matchingEntries = @(
            $operatorChatQueryCache.Values | Where-Object {
                $entry = $_
                $null -ne $entry -and
                [string]::Equals([string]$entry.query, [string]$Query, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$entry.intent, [string]$Intent, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$entry.objective_id, [string]$ObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) -and
                [int]$entry.window_minutes -eq [int]$WindowMinutes
            }
        ) | Sort-Object {
            if ($_.PSObject.Properties['created_at']) {
                [datetime]::Parse([string]$_.created_at)
            }
            else {
                [datetime]::MinValue
            }
        } -Descending

        if (@($matchingEntries).Count -gt 0) {
            $fallbackEntry = $matchingEntries[0]
            if ($fallbackEntry -and $fallbackEntry.PSObject.Properties['result']) {
                return $fallbackEntry.result
            }
        }
    }

    return $null
}

function Register-OperatorChatActionPreview {
    param(
        [Parameter(Mandatory = $true)][string]$PreviewId,
        [Parameter(Mandatory = $true)][string]$Action,
        [string]$Label,
        [string]$Intent,
        [string]$ObjectiveId,
        [string]$Query,
        [string]$Mode,
        [string]$Actor,
        [string]$SuggestedReason,
        [string]$ReasoningBundleId,
        [string]$RemoteEndpoint,
        [string]$ProposalSource = '',
        [string]$ProposalId = '',
        [string]$ProposalObjectiveId = '',
        [string]$ProposalTitle = '',
        [string]$ProposalAcknowledgmentDisposition = '',
        [string]$ProposalClosureStatus = '',
        [string]$ProposalClosureDisposition = '',
        [string]$ProposalClosureSummary = ''
    )

    Clear-ExpiredOperatorChatActionPreviews
    $createdAt = (Get-Date).ToUniversalTime()
    $expiresAt = $createdAt.AddMinutes($operatorChatActionPreviewTtlMinutes)
    $entry = [pscustomobject]@{
        preview_id = [string]$PreviewId
        action = [string]$Action
        label = [string]$Label
        intent = [string]$Intent
        objective_id = [string]$ObjectiveId
        query = [string]$Query
        mode = [string]$Mode
        actor = [string]$Actor
        suggested_reason = [string]$SuggestedReason
        reasoning_bundle_id = [string]$ReasoningBundleId
        remote_endpoint = [string]$RemoteEndpoint
        proposal_source = [string]$ProposalSource
        proposal_id = [string]$ProposalId
        proposal_objective_id = [string]$ProposalObjectiveId
        proposal_title = [string]$ProposalTitle
        proposal_acknowledgment_disposition = [string]$ProposalAcknowledgmentDisposition
        proposal_closure_status = [string]$ProposalClosureStatus
        proposal_closure_disposition = [string]$ProposalClosureDisposition
        proposal_closure_summary = [string]$ProposalClosureSummary
        created_at = $createdAt.ToString('o')
        expires_at = $expiresAt.ToString('o')
        consumed = $false
        consumed_at = ''
    }
    $operatorChatActionPreviewRegistry[[string]$PreviewId] = $entry
    return $entry
}

function Test-OperatorChatActionPreviewConfirmation {
    param(
        [Parameter(Mandatory = $true)][string]$PreviewId,
        [string]$Action,
        [string]$Intent,
        [string]$ObjectiveId,
        [string]$Query,
        [string]$Mode,
        [string]$Actor
    )

    Clear-ExpiredOperatorChatActionPreviews
    if (-not $operatorChatActionPreviewRegistry.ContainsKey([string]$PreviewId)) {
        return [pscustomobject]@{
            valid = $false
            status = 'invalid_preview'
            reason = 'Preview ID was not found or expired. Request a new governed action preview.'
            preview = $null
        }
    }

    $entry = $operatorChatActionPreviewRegistry[[string]$PreviewId]
    if ($null -eq $entry) {
        return [pscustomobject]@{
            valid = $false
            status = 'invalid_preview'
            reason = 'Preview ID was not found or expired. Request a new governed action preview.'
            preview = $null
        }
    }

    if ([bool]$entry.consumed) {
        return [pscustomobject]@{
            valid = $false
            status = 'invalid_preview'
            reason = "Preview $PreviewId was already confirmed at $([string]$entry.consumed_at). Request a new governed action preview before retrying."
            preview = $entry
        }
    }

    $mismatchReasons = New-Object System.Collections.Generic.List[string]
    if (-not [string]::Equals([string]$entry.action, [string]$Action, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$mismatchReasons.Add('action does not match the original preview')
    }
    if (-not [string]::Equals([string]$entry.intent, [string]$Intent, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$mismatchReasons.Add('intent does not match the original preview')
    }
    if (-not [string]::Equals([string]$entry.objective_id, [string]$ObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$mismatchReasons.Add('objective scope does not match the original preview')
    }
    if (-not [string]::Equals([string]$entry.query, [string]$Query, [System.StringComparison]::Ordinal)) {
        [void]$mismatchReasons.Add('query does not match the original preview')
    }
    if (-not [string]::Equals([string]$entry.mode, [string]$Mode, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$mismatchReasons.Add('mode does not match the original preview')
    }
    if (-not [string]::Equals([string]$entry.actor, [string]$Actor, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$mismatchReasons.Add('operator does not match the original preview owner')
    }

    if ($mismatchReasons.Count -gt 0) {
        return [pscustomobject]@{
            valid = $false
            status = 'invalid_preview'
            reason = ('Preview validation failed because ' + (($mismatchReasons | Select-Object -Unique) -join '; ') + '.')
            preview = $entry
        }
    }

    return [pscustomobject]@{
        valid = $true
        status = 'ok'
        reason = ''
        preview = $entry
    }
}

function Mark-OperatorChatActionPreviewConsumed {
    param([Parameter(Mandatory = $true)][string]$PreviewId)

    if (-not $operatorChatActionPreviewRegistry.ContainsKey([string]$PreviewId)) {
        return $null
    }

    $entry = $operatorChatActionPreviewRegistry[[string]$PreviewId]
    if ($null -eq $entry) {
        return $null
    }

    $updated = [pscustomobject]@{
        preview_id = [string]$entry.preview_id
        action = [string]$entry.action
        label = [string]$entry.label
        intent = [string]$entry.intent
        objective_id = [string]$entry.objective_id
        query = [string]$entry.query
        mode = [string]$entry.mode
        actor = [string]$entry.actor
        suggested_reason = [string]$entry.suggested_reason
        reasoning_bundle_id = if ($entry.PSObject.Properties['reasoning_bundle_id']) { [string]$entry.reasoning_bundle_id } else { '' }
        remote_endpoint = [string]$entry.remote_endpoint
        proposal_source = if ($entry.PSObject.Properties['proposal_source']) { [string]$entry.proposal_source } else { '' }
        proposal_id = if ($entry.PSObject.Properties['proposal_id']) { [string]$entry.proposal_id } else { '' }
        proposal_objective_id = if ($entry.PSObject.Properties['proposal_objective_id']) { [string]$entry.proposal_objective_id } else { '' }
        proposal_title = if ($entry.PSObject.Properties['proposal_title']) { [string]$entry.proposal_title } else { '' }
        proposal_acknowledgment_disposition = if ($entry.PSObject.Properties['proposal_acknowledgment_disposition']) { [string]$entry.proposal_acknowledgment_disposition } else { '' }
        proposal_closure_status = if ($entry.PSObject.Properties['proposal_closure_status']) { [string]$entry.proposal_closure_status } else { '' }
        proposal_closure_disposition = if ($entry.PSObject.Properties['proposal_closure_disposition']) { [string]$entry.proposal_closure_disposition } else { '' }
        proposal_closure_summary = if ($entry.PSObject.Properties['proposal_closure_summary']) { [string]$entry.proposal_closure_summary } else { '' }
        created_at = [string]$entry.created_at
        expires_at = [string]$entry.expires_at
        consumed = $true
        consumed_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $operatorChatActionPreviewRegistry[[string]$PreviewId] = $updated
    return $updated
}

function Get-OperatorChatSuggestedActionMetadata {
    param(
        $OperatorResponse,
        [string]$Action,
        [string]$SuggestedReason,
        [string]$Mode
    )

    $items = if ($OperatorResponse -and $OperatorResponse.PSObject.Properties['response'] -and $OperatorResponse.response -and $OperatorResponse.response.PSObject.Properties['suggested_actions']) {
        @($OperatorResponse.response.suggested_actions)
    }
    else {
        @()
    }
    if (@($items).Count -eq 0) {
        return $null
    }

    $exact = @($items | Where-Object {
            [string]::Equals([string]$_.action, [string]$Action, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$_.reason, [string]$SuggestedReason, [System.StringComparison]::Ordinal) -and
            [string]::Equals([string]$_.mode, [string]$Mode, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
    if (@($exact).Count -gt 0) {
        return $exact[0]
    }

    $actionOnly = @($items | Where-Object {
            [string]::Equals([string]$_.action, [string]$Action, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
    if (@($actionOnly).Count -gt 0) {
        return $actionOnly[0]
    }

    return $null
}

function Get-OperatorChatActionAuditPayload {
    param(
        [int]$Limit = 8,
        [string]$AuditId = '',
        [string]$PreviewId = '',
        [string]$Action = '',
        [string]$ReasoningBundleId = '',
        [string]$OutcomeStatus = '',
        [string]$Phase = '',
        [string]$Search = ''
    )

    $safeLimit = if ($Limit -lt 1) { 1 } elseif ($Limit -gt 50) { 50 } else { $Limit }
    $entries = @()
    if (Test-Path -Path $operatorChatActionAuditLogPath) {
        $filterCount = @($AuditId, $PreviewId, $Action, $ReasoningBundleId, $OutcomeStatus, $Phase, $Search | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
        $tailMultiplier = if ($filterCount -gt 0) { 10 } else { 1 }
        $lines = Get-RecentLogLines -LogPath $operatorChatActionAuditLogPath -Tail ($safeLimit * $tailMultiplier)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace([string]$line)) {
                continue
            }

            try {
                $entry = $line | ConvertFrom-Json
                if (-not [string]::IsNullOrWhiteSpace($AuditId) -and -not [string]::Equals([string]$entry.audit_id, [string]$AuditId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($PreviewId) -and -not [string]::Equals([string]$entry.preview_id, [string]$PreviewId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($Action) -and -not [string]::Equals([string]$entry.action, [string]$Action, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($ReasoningBundleId) -and -not [string]::Equals([string]$entry.reasoning_bundle_id, [string]$ReasoningBundleId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($OutcomeStatus) -and -not [string]::Equals([string]$entry.outcome_status, [string]$OutcomeStatus, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($Phase) -and -not [string]::Equals([string]$entry.phase, [string]$Phase, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($Search)) {
                    $searchText = [string]$Search
                    $haystack = @(
                        [string]$entry.action,
                        [string]$entry.action_label,
                        [string]$entry.intent,
                        [string]$entry.query,
                        [string]$entry.objective_id,
                        [string]$entry.actor,
                        [string]$entry.outcome_status,
                        [string]$entry.outcome_summary,
                        [string]$entry.preview_id,
                        [string]$entry.audit_id,
                        [string]$entry.reasoning_bundle_id
                    ) -join ' '
                    if ($haystack -notmatch [regex]::Escape($searchText)) {
                        continue
                    }
                }
                $entries += @($entry)
            }
            catch {
            }
        }
    }

    $sorted = @($entries | Sort-Object timestamp_utc -Descending | Select-Object -First $safeLimit)
    $proposalLifecycle = $null
    if (@($sorted).Count -gt 0) {
        $latestEntry = $sorted[0]
        if ($latestEntry -and $latestEntry.PSObject.Properties['proposal_closure_status'] -and -not [string]::IsNullOrWhiteSpace([string]$latestEntry.proposal_closure_status)) {
            $proposalLifecycle = [pscustomobject]@{
                available = $true
                status = [string]$latestEntry.proposal_closure_status
                disposition = if ($latestEntry.PSObject.Properties['proposal_closure_disposition']) { [string]$latestEntry.proposal_closure_disposition } else { '' }
                summary = if ($latestEntry.PSObject.Properties['proposal_closure_summary']) { [string]$latestEntry.proposal_closure_summary } else { '' }
            }
        }
    }
    try {
        $lifecycleObjectiveId = if (@($sorted).Count -gt 0 -and $sorted[0].PSObject.Properties['objective_id']) { [string]$sorted[0].objective_id } else { '' }
        $auditProjectStatus = if ([string]::IsNullOrWhiteSpace($lifecycleObjectiveId)) { Get-ProjectStatusPayload } else { Get-ProjectStatusPayload -ObjectiveId $lifecycleObjectiveId }
        if ($null -eq $proposalLifecycle -and $auditProjectStatus -and $auditProjectStatus.PSObject.Properties['mim_proposal_closure']) {
            $proposalLifecycle = $auditProjectStatus.mim_proposal_closure
        }
    }
    catch {
        $proposalLifecycle = $null
    }
    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        count = @($sorted).Count
        latest_path = $operatorChatActionAuditLatestPath
        log_path = $operatorChatActionAuditLogPath
        filters = [pscustomobject]@{
            audit_id = [string]$AuditId
            preview_id = [string]$PreviewId
            action = [string]$Action
            reasoning_bundle_id = [string]$ReasoningBundleId
            outcome_status = [string]$OutcomeStatus
            phase = [string]$Phase
            search = [string]$Search
            limit = $safeLimit
        }
        proposal_lifecycle = $proposalLifecycle
        entries = @($sorted)
    }
}

function Get-OperatorChatCommitmentEvidenceSnapshot {
    param($ProjectStatus)

    if ($null -eq $ProjectStatus) {
        return $null
    }

    $statusSource = $ProjectStatus
    try {
        $statusSource = (($ProjectStatus | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
    }
    catch {
        $statusSource = $ProjectStatus
    }

    $marker = $null
    $steady = $null
    $cadence = $null
    $cadenceStream = $null
    $cadenceMetrics = $null
    $cadenceGovernance = $null
    $bridge = $null
    $maintenance = $null
    $watchdog = $null
    $listener = $null

    try {
        $markerProperty = $statusSource.PSObject.Properties.Match('marker') | Select-Object -First 1
        if ($markerProperty) {
            $marker = $markerProperty.Value
        }
    }
    catch {
    }

    try {
        $steadyProperty = $statusSource.PSObject.Properties.Match('steady_state') | Select-Object -First 1
        if ($steadyProperty) {
            $steady = $steadyProperty.Value
        }
    }
    catch {
    }

    try {
        $cadenceProperty = $statusSource.PSObject.Properties.Match('cadence_health') | Select-Object -First 1
        if ($cadenceProperty) {
            $cadence = $cadenceProperty.Value
        }
    }
    catch {
    }

    try {
        if ($cadence) {
            $cadenceStreamProperty = $cadence.PSObject.Properties.Match('stream') | Select-Object -First 1
            if ($cadenceStreamProperty) {
                $cadenceStream = $cadenceStreamProperty.Value
            }

            $cadenceMetricsProperty = $cadence.PSObject.Properties.Match('cadence') | Select-Object -First 1
            if ($cadenceMetricsProperty) {
                $cadenceMetrics = $cadenceMetricsProperty.Value
            }

            $cadenceGovernanceProperty = $cadence.PSObject.Properties.Match('governance') | Select-Object -First 1
            if ($cadenceGovernanceProperty) {
                $cadenceGovernance = $cadenceGovernanceProperty.Value
            }
        }
    }
    catch {
    }

    try {
        $bridgeProperty = $statusSource.PSObject.Properties.Match('bridge_status') | Select-Object -First 1
        if ($bridgeProperty) {
            $bridge = $bridgeProperty.Value
        }
    }
    catch {
    }

    try {
        $maintenanceProperty = $statusSource.PSObject.Properties.Match('self_health_maintenance') | Select-Object -First 1
        if ($maintenanceProperty) {
            $maintenance = $maintenanceProperty.Value
        }
    }
    catch {
    }

    try {
        $watchdogProperty = $statusSource.PSObject.Properties.Match('recovery_watchdog') | Select-Object -First 1
        if ($watchdogProperty) {
            $watchdog = $watchdogProperty.Value
        }
    }
    catch {
    }

    try {
        $listenerProperty = $statusSource.PSObject.Properties.Match('listener_activity') | Select-Object -First 1
        if ($listenerProperty) {
            $listener = $listenerProperty.Value
        }
    }
    catch {
    }

    return [pscustomobject]@{
        objective_id = if ($marker -and $marker.PSObject.Properties['objective_id']) { [string]$marker.objective_id } else { '' }
        objective_status = if ($marker -and $marker.PSObject.Properties['status']) { [string]$marker.status } else { '' }
        steady_status = if ($steady -and $steady.PSObject.Properties['status']) { [string]$steady.status } else { '' }
        cadence_severity = if ($cadence -and $cadence.PSObject.Properties['severity']) { [string]$cadence.severity } else { '' }
        cadence_adjusted_severity = if ($cadenceGovernance -and $cadenceGovernance.PSObject.Properties['adjusted_severity']) { [string]$cadenceGovernance.adjusted_severity } else { '' }
        cadence_loop_idle_seconds = if ($cadenceStream -and $cadenceStream.PSObject.Properties['loop_idle_sec']) { ConvertTo-OperatorChatEvidenceText -Value $cadenceStream.loop_idle_sec } else { '' }
        cadence_p95_seconds = if ($cadenceMetrics -and $cadenceMetrics.PSObject.Properties['p95_sec']) { ConvertTo-OperatorChatEvidenceText -Value $cadenceMetrics.p95_sec } else { '' }
        bridge_status = if ($bridge -and $bridge.PSObject.Properties['status']) { [string]$bridge.status } else { '' }
        bridge_objective_mismatch = if ($bridge -and $bridge.PSObject.Properties['objective_mismatch']) { ConvertTo-OperatorChatEvidenceText -Value $bridge.objective_mismatch } else { '' }
        bridge_canonical_objective = if ($bridge -and $bridge.PSObject.Properties['canonical_mim_objective_id']) { [string]$bridge.canonical_mim_objective_id } else { '' }
        bridge_task_objective = if ($bridge -and $bridge.PSObject.Properties['task_request_objective_id']) { [string]$bridge.task_request_objective_id } else { '' }
        maintenance_status = if ($maintenance -and $maintenance.PSObject.Properties['overall_status']) { [string]$maintenance.overall_status } else { '' }
        maintenance_severity = if ($maintenance -and $maintenance.PSObject.Properties['overall_severity']) { [string]$maintenance.overall_severity } else { '' }
        watchdog_state = if ($watchdog -and $watchdog.PSObject.Properties['state']) { [string]$watchdog.state } else { '' }
        listener_request_id = if ($listener -and $listener.PSObject.Properties['latest_request_id']) { [string]$listener.latest_request_id } else { '' }
    }
}

function Get-OperatorChatCommitmentEvidenceFingerprint {
    param($ProjectStatus)

    $snapshot = Get-OperatorChatCommitmentEvidenceSnapshot -ProjectStatus $ProjectStatus
    if ($null -eq $snapshot) {
        return ''
    }

    $parts = @(
        ('objective={0}' -f [string]$snapshot.objective_id),
        ('objective_status={0}' -f [string]$snapshot.objective_status),
        ('steady={0}' -f [string]$snapshot.steady_status),
        ('cadence={0}' -f [string]$snapshot.cadence_severity),
        ('cadence_adjusted={0}' -f [string]$snapshot.cadence_adjusted_severity),
        ('cadence_idle={0}' -f [string]$snapshot.cadence_loop_idle_seconds),
        ('cadence_p95={0}' -f [string]$snapshot.cadence_p95_seconds),
        ('bridge={0}' -f [string]$snapshot.bridge_status),
        ('bridge_mismatch={0}' -f [string]$snapshot.bridge_objective_mismatch),
        ('bridge_canonical={0}' -f [string]$snapshot.bridge_canonical_objective),
        ('bridge_task={0}' -f [string]$snapshot.bridge_task_objective),
        ('maintenance={0}' -f [string]$snapshot.maintenance_status),
        ('maintenance_severity={0}' -f [string]$snapshot.maintenance_severity),
        ('watchdog={0}' -f [string]$snapshot.watchdog_state),
        ('listener_request={0}' -f [string]$snapshot.listener_request_id)
    )

    return ($parts -join '|')
}

function Get-OperatorChatSnapshotFieldText {
    param(
        $Snapshot,
        [string]$FieldName
    )

    if ($null -eq $Snapshot -or [string]::IsNullOrWhiteSpace($FieldName) -or $null -eq $Snapshot.PSObject) {
        return ''
    }

    try {
        $property = $Snapshot.PSObject.Properties[$FieldName]
        if ($null -eq $property) {
            return ''
        }

        return [string]$property.Value
    }
    catch {
        return ''
    }
}

function Compare-OperatorChatCommitmentEvidenceSnapshots {
    param(
        $BaselineSnapshot,
        $CurrentSnapshot
    )

    if ($null -eq $BaselineSnapshot -or $null -eq $CurrentSnapshot) {
        return @()
    }

    $fieldLabels = [ordered]@{
        objective_id = 'Objective'
        objective_status = 'Objective Status'
        steady_status = 'Steady State'
        cadence_severity = 'Cadence Severity'
        cadence_adjusted_severity = 'Cadence Adjusted Severity'
        cadence_loop_idle_seconds = 'Loop Idle Seconds'
        cadence_p95_seconds = 'p95 Cycle Seconds'
        bridge_status = 'Bridge Health'
        bridge_objective_mismatch = 'Bridge Objective Mismatch'
        bridge_canonical_objective = 'Canonical MIM Objective'
        bridge_task_objective = 'Live Task Objective'
        maintenance_status = 'Maintenance Status'
        maintenance_severity = 'Maintenance Severity'
        watchdog_state = 'Watchdog State'
        listener_request_id = 'Latest Listener Request'
    }

    $deltas = New-Object System.Collections.Generic.List[object]
    foreach ($fieldEntry in $fieldLabels.GetEnumerator()) {
        $resolvedFieldName = [string]$fieldEntry.Key
        $label = [string]$fieldEntry.Value
        $before = Get-OperatorChatSnapshotFieldText -Snapshot $BaselineSnapshot -FieldName $resolvedFieldName
        $after = Get-OperatorChatSnapshotFieldText -Snapshot $CurrentSnapshot -FieldName $resolvedFieldName
        if ([string]::Equals($before, $after, [System.StringComparison]::Ordinal)) {
            continue
        }
        [void]$deltas.Add([pscustomobject]@{
            field = $resolvedFieldName
            label = $label
            before = $before
            after = $after
        })
    }

    return @($deltas.ToArray())
}

function Get-OperatorChatCommitmentHistoryProfile {
    param(
        [string]$ObjectiveId,
        [string]$Action,
        [int]$Limit = 12,
        [string]$Intent = ''
    )

    $normalizedObjectiveId = [string]$ObjectiveId
    $normalizedAction = [string]$Action
    if ([string]::IsNullOrWhiteSpace($normalizedAction)) {
        return [pscustomobject]@{
            objective_id = $normalizedObjectiveId
            action = $normalizedAction
            terminal_count = 0
            satisfied_count = 0
            abandoned_count = 0
            recent_terminal_state = ''
            recent_terminal_at = ''
            summary = ''
            outcome_bias = 'neutral'
            recent_fitness_score = 0
            ineffective_signal = $false
            ineffective_basis = ''
            same_intent_terminal_count = 0
            same_intent_satisfied_count = 0
            same_intent_abandoned_count = 0
            same_intent_summary = ''
        }
    }

    $entries = @()
    if (Test-Path -Path $operatorChatCommitmentLogPath) {
        $parsedEntries = Get-RecentParsedLogEntries -LogPath $operatorChatCommitmentLogPath -Tail ($Limit * 12)
        foreach ($entry in $parsedEntries) {
            if ($null -eq $entry) {
                continue
            }
            if (-not [string]::Equals([string]$entry.action, $normalizedAction, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace($normalizedObjectiveId) -and -not [string]::Equals([string]$entry.objective_id, $normalizedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $entries += @($entry)
        }
    }

    $terminalCandidates = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $entries) {
        if ($null -eq $entry) {
            continue
        }

        $state = if ($entry.PSObject.Properties['state']) { [string]$entry.state } else { '' }
        if (@('satisfied', 'abandoned') -contains $state) {
            [void]$terminalCandidates.Add($entry)
        }
    }

    $terminalEntries = @($terminalCandidates.ToArray() | Sort-Object timestamp_utc -Descending | Select-Object -First $Limit)
    $sameIntentEntriesList = New-Object System.Collections.Generic.List[object]
    $satisfiedCount = 0
    $abandonedCount = 0
    $sameIntentSatisfiedCount = 0
    $sameIntentAbandonedCount = 0
    foreach ($entry in $terminalEntries) {
        if ($null -eq $entry) {
            continue
        }

        $state = if ($entry.PSObject.Properties['state']) { [string]$entry.state } else { '' }
        $intentMatches = -not [string]::IsNullOrWhiteSpace($Intent) -and $entry.PSObject.Properties['intent'] -and [string]::Equals([string]$entry.intent, [string]$Intent, [System.StringComparison]::OrdinalIgnoreCase)
        if ([string]::Equals($state, 'satisfied', [System.StringComparison]::OrdinalIgnoreCase)) {
            $satisfiedCount++
            if ($intentMatches) {
                $sameIntentSatisfiedCount++
            }
        }
        elseif ([string]::Equals($state, 'abandoned', [System.StringComparison]::OrdinalIgnoreCase)) {
            $abandonedCount++
            if ($intentMatches) {
                $sameIntentAbandonedCount++
            }
        }

        if ($intentMatches) {
            [void]$sameIntentEntriesList.Add($entry)
        }
    }

    $sameIntentEntries = if ([string]::IsNullOrWhiteSpace($Intent)) { @() } else { @($sameIntentEntriesList.ToArray()) }
    $recentTerminal = if (@($terminalEntries).Count -gt 0) { $terminalEntries[0] } else { $null }
    $recentAbandonedStreak = 0
    foreach ($entry in $terminalEntries) {
        if ($null -eq $entry) {
            continue
        }

        $state = if ($entry.PSObject.Properties['state']) { [string]$entry.state } else { '' }
        if ([string]::Equals($state, 'abandoned', [System.StringComparison]::OrdinalIgnoreCase)) {
            $recentAbandonedStreak++
            continue
        }

        break
    }

    $sameIntentAbandonedStreak = 0
    foreach ($entry in $sameIntentEntries) {
        if ($null -eq $entry) {
            continue
        }

        $state = if ($entry.PSObject.Properties['state']) { [string]$entry.state } else { '' }
        if ([string]::Equals($state, 'abandoned', [System.StringComparison]::OrdinalIgnoreCase)) {
            $sameIntentAbandonedStreak++
            continue
        }

        break
    }
    $ineffectiveSignal = if ([string]::IsNullOrWhiteSpace($Intent)) {
        ($recentTerminal -and [string]::Equals([string]$recentTerminal.state, 'abandoned', [System.StringComparison]::OrdinalIgnoreCase) -and $recentAbandonedStreak -ge 2)
    }
    else {
        ($recentTerminal -and [string]::Equals([string]$recentTerminal.state, 'abandoned', [System.StringComparison]::OrdinalIgnoreCase) -and $sameIntentAbandonedStreak -ge 2)
    }
    $ineffectiveBasis = if ($ineffectiveSignal) {
        if ([string]::IsNullOrWhiteSpace($Intent)) {
            'Repeated abandoned terminal outcomes mark this action pattern ineffective until bounded evidence materially changes.'
        }
        else {
            'Repeated abandoned terminal outcomes for this intent mark this action pattern ineffective until bounded evidence materially changes.'
        }
    }
    else {
        ''
    }

    $fitnessScore = 0
    for ($index = 0; $index -lt @($terminalEntries).Count; $index++) {
        $entry = $terminalEntries[$index]
        $weight = switch ($index) {
            0 { 4 }
            1 { 3 }
            2 { 2 }
            default { 1 }
        }
        $stateScore = if ([string]::Equals([string]$entry.state, 'satisfied', [System.StringComparison]::OrdinalIgnoreCase)) { 3 } else { -4 }
        $intentMultiplier = if (-not [string]::IsNullOrWhiteSpace($Intent) -and [string]::Equals([string]$entry.intent, [string]$Intent, [System.StringComparison]::OrdinalIgnoreCase)) { 2 } else { 1 }
        $fitnessScore += ($weight * $stateScore * $intentMultiplier)
    }

    $outcomeBias = switch ($true) {
        ($fitnessScore -ge 12) { 'strong_positive'; break }
        ($fitnessScore -gt 0) { 'positive'; break }
        ($fitnessScore -le -12) { 'strong_negative'; break }
        ($fitnessScore -lt 0) { 'negative'; break }
        default { 'neutral' }
    }

    $summary = if ($recentTerminal) {
        if ($ineffectiveSignal) {
            '{0} satisfied / {1} abandoned in recent terminal history; latest repeated abandoned outcome marked this action pattern ineffective.' -f $satisfiedCount, $abandonedCount
        }
        else {
            '{0} satisfied / {1} abandoned in recent terminal history; latest terminal outcome was {2}.' -f $satisfiedCount, $abandonedCount, [string]$recentTerminal.state
        }
    }
    elseif (($satisfiedCount + $abandonedCount) -gt 0) {
        '{0} satisfied / {1} abandoned in recent terminal history.' -f $satisfiedCount, $abandonedCount
    }
    else {
        'No recent terminal commitment outcomes recorded for this action.'
    }

    $sameIntentSummary = if ([string]::IsNullOrWhiteSpace($Intent)) {
        ''
    }
    elseif (@($sameIntentEntries).Count -gt 0) {
        if ($ineffectiveSignal) {
            'Within intent {0}: {1} satisfied / {2} abandoned; the latest repeated abandoned outcome marked this action pattern ineffective.' -f [string]$Intent, $sameIntentSatisfiedCount, $sameIntentAbandonedCount
        }
        else {
            'Within intent {0}: {1} satisfied / {2} abandoned.' -f [string]$Intent, $sameIntentSatisfiedCount, $sameIntentAbandonedCount
        }
    }
    else {
        'No recent terminal outcomes recorded for intent {0}.' -f [string]$Intent
    }

    return [pscustomobject]@{
        objective_id = $normalizedObjectiveId
        action = $normalizedAction
        terminal_count = [int](@($terminalEntries).Count)
        satisfied_count = $satisfiedCount
        abandoned_count = $abandonedCount
        recent_terminal_state = if ($ineffectiveSignal) { 'ineffective' } elseif ($recentTerminal) { [string]$recentTerminal.state } else { '' }
        recent_terminal_at = if ($recentTerminal) { [string]$recentTerminal.timestamp_utc } else { '' }
        summary = $summary
        outcome_bias = $outcomeBias
        recent_fitness_score = [int]$fitnessScore
        ineffective_signal = [bool]$ineffectiveSignal
        ineffective_basis = [string]$ineffectiveBasis
        same_intent_terminal_count = [int](@($sameIntentEntries).Count)
        same_intent_satisfied_count = [int]$sameIntentSatisfiedCount
        same_intent_abandoned_count = [int]$sameIntentAbandonedCount
        same_intent_summary = $sameIntentSummary
    }
}

function Get-OperatorChatProposalOutcomeProfile {
    param(
        [string]$ObjectiveId,
        [string]$Action,
        [string]$Intent = '',
        [int]$Limit = 12
    )

    $normalizedObjectiveId = [string]$ObjectiveId
    $normalizedAction = [string]$Action
    if ([string]::IsNullOrWhiteSpace($normalizedAction)) {
        return [pscustomobject]@{
            objective_id = $normalizedObjectiveId
            action = $normalizedAction
            terminal_count = 0
            absorbed_satisfied_count = 0
            abandoned_count = 0
            same_intent_absorbed_satisfied_count = 0
            same_intent_abandoned_count = 0
            score = 0
            outcome_bias = 'neutral'
            summary = ''
            same_intent_summary = ''
        }
    }

    $entries = @()
    if (Test-Path -Path $operatorChatCommitmentLogPath) {
        $parsedEntries = Get-RecentParsedLogEntries -LogPath $operatorChatCommitmentLogPath -Tail ($Limit * 16)
        foreach ($entry in $parsedEntries) {
            if ($null -eq $entry) {
                continue
            }
            if (-not [string]::Equals([string]$entry.action, $normalizedAction, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace($normalizedObjectiveId) -and -not [string]::Equals([string]$entry.objective_id, $normalizedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if (-not [string]::Equals([string]$entry.proposal_source, 'mim', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if (@('satisfied', 'abandoned') -notcontains ([string]$entry.state)) {
                continue
            }
            $entries += @($entry)
        }
    }

    $terminalEntries = @($entries | Sort-Object timestamp_utc -Descending | Select-Object -First $Limit)
    $absorbedSatisfiedCount = [int](@($terminalEntries | Where-Object {
                [string]::Equals([string]$_.state, 'satisfied', [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.proposal_acknowledgment_disposition, 'absorbed', [System.StringComparison]::OrdinalIgnoreCase)
            }).Count)
    $abandonedCount = [int](@($terminalEntries | Where-Object { [string]::Equals([string]$_.state, 'abandoned', [System.StringComparison]::OrdinalIgnoreCase) }).Count)
    $sameIntentEntries = if ([string]::IsNullOrWhiteSpace($Intent)) {
        @()
    }
    else {
        @($terminalEntries | Where-Object { [string]::Equals([string]$_.intent, [string]$Intent, [System.StringComparison]::OrdinalIgnoreCase) })
    }
    $sameIntentAbsorbedSatisfiedCount = [int](@($sameIntentEntries | Where-Object {
                [string]::Equals([string]$_.state, 'satisfied', [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.proposal_acknowledgment_disposition, 'absorbed', [System.StringComparison]::OrdinalIgnoreCase)
            }).Count)
    $sameIntentAbandonedCount = [int](@($sameIntentEntries | Where-Object { [string]::Equals([string]$_.state, 'abandoned', [System.StringComparison]::OrdinalIgnoreCase) }).Count)

    $score = 0
    for ($index = 0; $index -lt @($terminalEntries).Count; $index++) {
        $entry = $terminalEntries[$index]
        $weight = switch ($index) {
            0 { 4 }
            1 { 3 }
            2 { 2 }
            default { 1 }
        }
        $isAbsorbedSatisfied = [string]::Equals([string]$entry.state, 'satisfied', [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$entry.proposal_acknowledgment_disposition, 'absorbed', [System.StringComparison]::OrdinalIgnoreCase)
        $stateScore = if ($isAbsorbedSatisfied) { 4 } elseif ([string]::Equals([string]$entry.state, 'satisfied', [System.StringComparison]::OrdinalIgnoreCase)) { 2 } else { -4 }
        $intentMultiplier = if (-not [string]::IsNullOrWhiteSpace($Intent) -and [string]::Equals([string]$entry.intent, [string]$Intent, [System.StringComparison]::OrdinalIgnoreCase)) { 2 } else { 1 }
        $score += ($weight * $stateScore * $intentMultiplier)
    }

    $outcomeBias = switch ($true) {
        ($score -ge 12) { 'strong_positive'; break }
        ($score -gt 0) { 'positive'; break }
        ($score -le -12) { 'strong_negative'; break }
        ($score -lt 0) { 'negative'; break }
        default { 'neutral' }
    }

    $summary = if (@($terminalEntries).Count -gt 0) {
        '{0} absorbed-and-satisfied / {1} abandoned proposal outcomes.' -f $absorbedSatisfiedCount, $abandonedCount
    }
    else {
        'No proposal-linked terminal outcomes recorded for this action yet.'
    }
    $sameIntentSummary = if ([string]::IsNullOrWhiteSpace($Intent)) {
        ''
    }
    elseif (@($sameIntentEntries).Count -gt 0) {
        'Within intent {0}: {1} absorbed-and-satisfied / {2} abandoned.' -f [string]$Intent, $sameIntentAbsorbedSatisfiedCount, $sameIntentAbandonedCount
    }
    else {
        'No proposal-linked terminal outcomes recorded for intent {0}.' -f [string]$Intent
    }

    return [pscustomobject]@{
        objective_id = $normalizedObjectiveId
        action = $normalizedAction
        terminal_count = [int](@($terminalEntries).Count)
        absorbed_satisfied_count = $absorbedSatisfiedCount
        abandoned_count = $abandonedCount
        same_intent_absorbed_satisfied_count = $sameIntentAbsorbedSatisfiedCount
        same_intent_abandoned_count = $sameIntentAbandonedCount
        score = [int]$score
        outcome_bias = $outcomeBias
        summary = $summary
        same_intent_summary = $sameIntentSummary
    }
}

function Get-OperatorChatComparisonObjectiveInfo {
    param(
        [string]$ObjectiveId = '',
        [switch]$AllowValidationFallback,
        [string]$ValidationHarness = ''
    )

    $statusPayload = if ([string]::IsNullOrWhiteSpace($ObjectiveId)) { Get-ProjectStatusPayload -ValidationHarness $ValidationHarness } else { Get-ProjectStatusPayload -ObjectiveId $ObjectiveId -ValidationHarness $ValidationHarness }
    $selectedObjectiveId = if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) { [string]$ObjectiveId } elseif ($statusPayload -and $statusPayload.PSObject.Properties['selected_objective_id']) { [string]$statusPayload.selected_objective_id } else { '' }
    $objectiveOptions = if ($statusPayload -and $statusPayload.PSObject.Properties['objective_options']) { @($statusPayload.objective_options) } else { @() }
    $alternateObjective = @($objectiveOptions | Where-Object {
            $candidateId = if ($null -ne $_ -and $_.PSObject.Properties['objective_id']) { [string]$_.objective_id } else { '' }
            -not [string]::IsNullOrWhiteSpace($candidateId) -and
            -not [string]::Equals($candidateId, $selectedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
    $alternateObjectiveId = if ($alternateObjective) { [string]$alternateObjective.objective_id } else { '' }

    if (-not [string]::IsNullOrWhiteSpace([string]$alternateObjectiveId)) {
        return [pscustomobject]@{
            ready = $true
            source = 'live_objective'
            label = 'live compare'
            objective_id = [string]$alternateObjectiveId
            validation_mode = ''
            summary = 'Trust-chain delta comparison can use live objective {0} as the bounded alternate posture.' -f [string]$alternateObjectiveId
        }
    }

    if ($AllowValidationFallback) {
        return [pscustomobject]@{
            ready = $true
            source = 'validation_only'
            label = 'validation only'
            objective_id = ''
            validation_mode = 'synthetic_drift'
            summary = 'Only one live objective is available, so trust-chain delta proving falls back to explicit validation-only synthetic drift.'
        }
    }

    return [pscustomobject]@{
        ready = $false
        source = 'none'
        label = 'no compare'
        objective_id = ''
        validation_mode = ''
        summary = 'No bounded alternate objective is currently available for live trust-chain delta comparison.'
    }
}

function Get-OperatorChatValidationHarnessProfile {
    param([string]$ValidationHarness = '')

    $harnessKey = if ([string]::IsNullOrWhiteSpace($ValidationHarness)) { '' } else { ([string]$ValidationHarness).Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($harnessKey)) {
        return $null
    }
    if ($operatorChatValidationHarnessProfiles.ContainsKey($harnessKey)) {
        return $operatorChatValidationHarnessProfiles[$harnessKey]
    }

    return $null
}

function Apply-OperatorChatComparisonProfileToStatus {
    param(
        $ProjectStatus,
        $ValidationHarnessProfile
    )

    if ($null -eq $ProjectStatus -or $null -eq $ValidationHarnessProfile) {
        return $ProjectStatus
    }

    $comparisonProfile = if ($ValidationHarnessProfile.PSObject.Properties['comparison_profile']) { [string]$ValidationHarnessProfile.comparison_profile } else { 'full' }
    $alternateObjectiveId = if ($ValidationHarnessProfile.PSObject.Properties['alternate_objective_id']) { [string]$ValidationHarnessProfile.alternate_objective_id } else { '' }

    if ($ProjectStatus.PSObject.Properties['listener_activity'] -and $ProjectStatus.listener_activity) {
        $existingRequestId = if ($ProjectStatus.listener_activity.PSObject.Properties['latest_request_id']) { [string]$ProjectStatus.listener_activity.latest_request_id } else { '' }
        $suffix = if ($ValidationHarnessProfile.PSObject.Properties['listener_request_suffix']) { [string]$ValidationHarnessProfile.listener_request_suffix } else { 'validation-compare' }
        $ProjectStatus.listener_activity.latest_request_id = if ([string]::IsNullOrWhiteSpace($existingRequestId)) { $suffix } else { '{0}|{1}' -f $existingRequestId, $suffix }
    }

    switch ($comparisonProfile) {
        'bridge' {
            if ($ProjectStatus.PSObject.Properties['bridge_status'] -and $ProjectStatus.bridge_status) {
                $ProjectStatus.bridge_status.status = 'warning'
                $ProjectStatus.bridge_status.objective_mismatch = $true
                $ProjectStatus.bridge_status.task_request_objective_id = if ([string]::IsNullOrWhiteSpace($alternateObjectiveId)) { 'validation-bridge-task' } else { $alternateObjectiveId }
                $ProjectStatus.bridge_status.summary = 'Bounded bridge comparison profile is forcing a mismatched live task objective for deterministic evidence comparison.'
            }
        }
        'cadence' {
            if ($ProjectStatus.PSObject.Properties['cadence_health'] -and $ProjectStatus.cadence_health) {
                $ProjectStatus.cadence_health.severity = 'warning'
                if ($ProjectStatus.cadence_health.PSObject.Properties['governance'] -and $ProjectStatus.cadence_health.governance) {
                    $ProjectStatus.cadence_health.governance.adjusted_severity = 'warning'
                }
                if ($ProjectStatus.cadence_health.PSObject.Properties['stream'] -and $ProjectStatus.cadence_health.stream) {
                    $ProjectStatus.cadence_health.stream.loop_idle_sec = 91.0
                }
                if ($ProjectStatus.cadence_health.PSObject.Properties['cadence'] -and $ProjectStatus.cadence_health.cadence) {
                    $ProjectStatus.cadence_health.cadence.p95_sec = 944
                }
            }
            if ($ProjectStatus.PSObject.Properties['steady_state'] -and $ProjectStatus.steady_state) {
                $ProjectStatus.steady_state.status = 'warning'
            }
        }
        'objective_status' {
            if ($ProjectStatus.PSObject.Properties['marker'] -and $ProjectStatus.marker) {
                $ProjectStatus.marker.status = 'warning'
                $ProjectStatus.marker.title = if ([string]::IsNullOrWhiteSpace($alternateObjectiveId)) { 'Validation Objective Status Compare Objective' } else { "Validation Objective $alternateObjectiveId" }
            }
        }
        default {
            if ($ProjectStatus.PSObject.Properties['marker'] -and $ProjectStatus.marker) {
                $ProjectStatus.marker.status = 'warning'
            }
            if ($ProjectStatus.PSObject.Properties['steady_state'] -and $ProjectStatus.steady_state) {
                $ProjectStatus.steady_state.status = 'warning'
            }
            if ($ProjectStatus.PSObject.Properties['cadence_health'] -and $ProjectStatus.cadence_health) {
                $ProjectStatus.cadence_health.severity = 'warning'
                if ($ProjectStatus.cadence_health.PSObject.Properties['governance'] -and $ProjectStatus.cadence_health.governance) {
                    $ProjectStatus.cadence_health.governance.adjusted_severity = 'warning'
                }
                if ($ProjectStatus.cadence_health.PSObject.Properties['stream'] -and $ProjectStatus.cadence_health.stream) {
                    $ProjectStatus.cadence_health.stream.loop_idle_sec = 91.0
                }
                if ($ProjectStatus.cadence_health.PSObject.Properties['cadence'] -and $ProjectStatus.cadence_health.cadence) {
                    $ProjectStatus.cadence_health.cadence.p95_sec = 944
                }
            }
            if ($ProjectStatus.PSObject.Properties['bridge_status'] -and $ProjectStatus.bridge_status) {
                $ProjectStatus.bridge_status.status = 'warning'
                $ProjectStatus.bridge_status.objective_mismatch = $true
                $ProjectStatus.bridge_status.task_request_objective_id = if ([string]::IsNullOrWhiteSpace($alternateObjectiveId)) { 'validation-live-compare' } else { $alternateObjectiveId }
                $ProjectStatus.bridge_status.summary = 'Bounded live-compare harness is presenting an alternate objective posture for deterministic trust-chain validation.'
            }
        }
    }

    if ($ProjectStatus.PSObject.Properties['self_health_maintenance'] -and $ProjectStatus.self_health_maintenance) {
        $ProjectStatus.self_health_maintenance.overall_status = 'healthy_with_fallback'
        $ProjectStatus.self_health_maintenance.overall_severity = 'warning'
        $ProjectStatus.self_health_maintenance.summary = 'Bounded live-compare harness is active for deterministic evidence delta proving.'
    }

    return $ProjectStatus
}

function Apply-OperatorChatValidationHarnessToStatus {
    param(
        $ProjectStatus,
        $ValidationHarnessProfile,
        [string]$RequestedObjectiveId = ''
    )

    if ($null -eq $ProjectStatus -or $null -eq $ValidationHarnessProfile) {
        return $ProjectStatus
    }

    try {
        $clone = (($ProjectStatus | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
    }
    catch {
        return $ProjectStatus
    }

    $alternateObjectiveId = [string]$ValidationHarnessProfile.alternate_objective_id
    if ([string]::IsNullOrWhiteSpace($alternateObjectiveId)) {
        return $clone
    }

    $objectiveOptions = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($clone.objective_options)) {
        if ($null -ne $item) {
            [void]$objectiveOptions.Add($item)
        }
    }

    $hasAlternate = @($objectiveOptions | Where-Object { [string]::Equals([string]$_.objective_id, $alternateObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if (-not $hasAlternate) {
        [void]$objectiveOptions.Add([pscustomobject]@{
                objective_id = $alternateObjectiveId
                title = [string]$ValidationHarnessProfile.alternate_title
                status = [string]$ValidationHarnessProfile.alternate_status
                priority = [string]$ValidationHarnessProfile.alternate_priority
            })
    }
    $clone.objective_options = @($objectiveOptions.ToArray())

    $selectedObjectiveId = if (-not [string]::IsNullOrWhiteSpace($RequestedObjectiveId)) { [string]$RequestedObjectiveId } elseif ($clone.PSObject.Properties['selected_objective_id']) { [string]$clone.selected_objective_id } else { '' }
    if ([string]::Equals($selectedObjectiveId, $alternateObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
        $clone.selected_objective_id = $alternateObjectiveId
        $alternateProgressPercent = [int]$ValidationHarnessProfile.alternate_progress_percent
        $alternateTaskCount = [int]$ValidationHarnessProfile.alternate_task_count
        $alternateCompletedEquivalent = [double]$ValidationHarnessProfile.alternate_completed_equivalent
        $updatedAt = (Get-Date).ToUniversalTime().ToString('o')

        $clone.marker = [pscustomobject]@{
            objective_id = $alternateObjectiveId
            remote_objective_id = $alternateObjectiveId
            title = [string]$ValidationHarnessProfile.alternate_title
            status = [string]$ValidationHarnessProfile.alternate_status
            priority = [string]$ValidationHarnessProfile.alternate_priority
            updated_at = $updatedAt
        }
        $clone.task_funnel = [pscustomobject]@{
            total = $alternateTaskCount
            by_status = [pscustomobject]@{
                completed = [int][math]::Floor($alternateCompletedEquivalent)
                in_progress = [math]::Max(0, ($alternateTaskCount - [int][math]::Floor($alternateCompletedEquivalent) - 1))
                failed = 1
            }
        }
        $clone.progress = [pscustomobject]@{
            percent = $alternateProgressPercent
            completed_equivalent = [math]::Round($alternateCompletedEquivalent, 2)
            task_count = $alternateTaskCount
            source = [string]$ValidationHarnessProfile.alternate_progress_source
            summary = "Objective ${alternateObjectiveId}: $alternateProgressPercent% (bounded live compare harness)"
        }

        $clone = Apply-OperatorChatComparisonProfileToStatus -ProjectStatus $clone -ValidationHarnessProfile $ValidationHarnessProfile
    }

    $clone | Add-Member -NotePropertyName validation_harness -NotePropertyValue ([pscustomobject]@{
            active = $true
            name = [string]$ValidationHarnessProfile.name
            label = [string]$ValidationHarnessProfile.label
            compare_objective_id = $alternateObjectiveId
            comparison_profile = if ($ValidationHarnessProfile.PSObject.Properties['comparison_profile']) { [string]$ValidationHarnessProfile.comparison_profile } else { 'full' }
        }) -Force

    return $clone
}

function New-OperatorChatValidationDriftProjectStatus {
    param(
        $ProjectStatus,
        [string]$DriftMode = 'synthetic_drift'
    )

    if ($null -eq $ProjectStatus) {
        return $null
    }

    try {
        $clone = (($ProjectStatus | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
    }
    catch {
        return $null
    }

    $normalizedMode = if ([string]::IsNullOrWhiteSpace($DriftMode)) { 'synthetic_drift' } else { ([string]$DriftMode).Trim().ToLowerInvariant() }
    switch ($normalizedMode) {
        'synthetic_drift' {
            if ($clone.PSObject.Properties['listener_activity'] -and $clone.listener_activity) {
                $existingRequestId = if ($clone.listener_activity.PSObject.Properties['latest_request_id']) { [string]$clone.listener_activity.latest_request_id } else { '' }
                $clone.listener_activity.latest_request_id = if ([string]::IsNullOrWhiteSpace($existingRequestId)) { 'validation-drift-request' } else { "$existingRequestId|validation-drift" }
            }
            elseif ($clone.PSObject.Properties['marker'] -and $clone.marker) {
                $existingStatus = if ($clone.marker.PSObject.Properties['status']) { [string]$clone.marker.status } else { '' }
                $clone.marker.status = if ([string]::IsNullOrWhiteSpace($existingStatus)) { 'validation-drift' } else { "$existingStatus-validation-drift" }
            }
        }
        default {
            return $null
        }
    }

    return $clone
}

function New-OperatorChatValidationDriftSnapshot {
    param(
        $BaselineSnapshot,
        [string]$DriftMode = 'synthetic_drift'
    )

    if ($null -eq $BaselineSnapshot) {
        return $null
    }

    try {
        $clone = (($BaselineSnapshot | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    }
    catch {
        return $null
    }

    $normalizedMode = if ([string]::IsNullOrWhiteSpace($DriftMode)) { 'synthetic_drift' } else { ([string]$DriftMode).Trim().ToLowerInvariant() }
    switch ($normalizedMode) {
        'synthetic_drift' {
            if ($clone.PSObject.Properties['listener_request_id']) {
                $existingRequestId = [string]$clone.listener_request_id
                $clone.listener_request_id = if ([string]::IsNullOrWhiteSpace($existingRequestId)) { 'validation-drift-request' } else { "$existingRequestId|validation-drift" }
            }
            elseif ($clone.PSObject.Properties['objective_status']) {
                $existingStatus = [string]$clone.objective_status
                $clone.objective_status = if ([string]::IsNullOrWhiteSpace($existingStatus)) { 'validation-drift' } else { "$existingStatus-validation-drift" }
            }
        }
        default {
            return $null
        }
    }

    return $clone
}

function Get-OperatorChatCommitmentEvidenceFingerprintFromSnapshot {
    param($Snapshot)

    if ($null -eq $Snapshot) {
        return ''
    }

    $parts = @(
        ('objective={0}' -f [string]$Snapshot.objective_id),
        ('objective_status={0}' -f [string]$Snapshot.objective_status),
        ('steady={0}' -f [string]$Snapshot.steady_status),
        ('cadence={0}' -f [string]$Snapshot.cadence_severity),
        ('cadence_adjusted={0}' -f [string]$Snapshot.cadence_adjusted_severity),
        ('cadence_idle={0}' -f [string]$Snapshot.cadence_loop_idle_seconds),
        ('cadence_p95={0}' -f [string]$Snapshot.cadence_p95_seconds),
        ('bridge={0}' -f [string]$Snapshot.bridge_status),
        ('bridge_mismatch={0}' -f [string]$Snapshot.bridge_objective_mismatch),
        ('bridge_canonical={0}' -f [string]$Snapshot.bridge_canonical_objective),
        ('bridge_task={0}' -f [string]$Snapshot.bridge_task_objective),
        ('maintenance={0}' -f [string]$Snapshot.maintenance_status),
        ('maintenance_severity={0}' -f [string]$Snapshot.maintenance_severity),
        ('watchdog={0}' -f [string]$Snapshot.watchdog_state),
        ('listener_request={0}' -f [string]$Snapshot.listener_request_id)
    )

    return ($parts -join '|')
}

function New-OperatorChatHarnessComparisonSnapshot {
    param(
        $BaselineSnapshot,
        $ValidationHarnessProfile,
        [string]$ComparisonObjectiveId = ''
    )

    if ($null -eq $BaselineSnapshot -or $null -eq $ValidationHarnessProfile) {
        return $null
    }

    $comparisonProfile = if ($ValidationHarnessProfile.PSObject.Properties['comparison_profile']) { [string]$ValidationHarnessProfile.comparison_profile } else { 'full' }
    $alternateObjectiveId = if ([string]::IsNullOrWhiteSpace($ComparisonObjectiveId)) {
        if ($ValidationHarnessProfile.PSObject.Properties['alternate_objective_id']) { [string]$ValidationHarnessProfile.alternate_objective_id } else { '' }
    }
    else {
        [string]$ComparisonObjectiveId
    }

    $objectiveId = if ([string]::IsNullOrWhiteSpace($alternateObjectiveId)) { [string]$BaselineSnapshot.objective_id } else { $alternateObjectiveId }
    $objectiveStatus = [string]$BaselineSnapshot.objective_status
    $steadyStatus = [string]$BaselineSnapshot.steady_status
    $cadenceSeverity = [string]$BaselineSnapshot.cadence_severity
    $cadenceAdjustedSeverity = [string]$BaselineSnapshot.cadence_adjusted_severity
    $cadenceLoopIdleSeconds = [string]$BaselineSnapshot.cadence_loop_idle_seconds
    $cadenceP95Seconds = [string]$BaselineSnapshot.cadence_p95_seconds
    $bridgeStatus = [string]$BaselineSnapshot.bridge_status
    $bridgeObjectiveMismatch = [string]$BaselineSnapshot.bridge_objective_mismatch
    $bridgeCanonicalObjective = [string]$BaselineSnapshot.bridge_canonical_objective
    $bridgeTaskObjective = [string]$BaselineSnapshot.bridge_task_objective
    $maintenanceStatus = [string]$BaselineSnapshot.maintenance_status
    $maintenanceSeverity = [string]$BaselineSnapshot.maintenance_severity
    $watchdogState = [string]$BaselineSnapshot.watchdog_state
    $listenerRequestId = [string]$BaselineSnapshot.listener_request_id

    switch ($comparisonProfile) {
        'bridge' {
            $bridgeStatus = 'warning'
            $bridgeObjectiveMismatch = 'true'
            if (-not [string]::IsNullOrWhiteSpace($alternateObjectiveId)) {
                $bridgeTaskObjective = $alternateObjectiveId
            }
            if ([string]::IsNullOrWhiteSpace($listenerRequestId)) {
                $listenerRequestId = if ([string]::IsNullOrWhiteSpace($alternateObjectiveId)) { 'validation-compare-bridge' } else { $alternateObjectiveId }
            }
        }
        'cadence' {
            $objectiveStatus = 'warning'
            $steadyStatus = 'warning'
            $cadenceSeverity = 'warning'
            $cadenceAdjustedSeverity = 'warning'
            $cadenceLoopIdleSeconds = '91'
            $cadenceP95Seconds = '944'
        }
        'objective_status' {
            $objectiveStatus = 'warning'
        }
        default {
            $objectiveStatus = 'warning'
            $steadyStatus = 'warning'
            $cadenceSeverity = 'warning'
            $cadenceAdjustedSeverity = 'warning'
            $cadenceLoopIdleSeconds = '91'
            $cadenceP95Seconds = '944'
            $bridgeStatus = 'warning'
            $bridgeObjectiveMismatch = 'true'
            if (-not [string]::IsNullOrWhiteSpace($alternateObjectiveId)) {
                $bridgeTaskObjective = $alternateObjectiveId
                $listenerRequestId = $alternateObjectiveId
            }
        }
    }

    return [pscustomobject]@{
        objective_id = $objectiveId
        objective_status = $objectiveStatus
        steady_status = $steadyStatus
        cadence_severity = $cadenceSeverity
        cadence_adjusted_severity = $cadenceAdjustedSeverity
        cadence_loop_idle_seconds = $cadenceLoopIdleSeconds
        cadence_p95_seconds = $cadenceP95Seconds
        bridge_status = $bridgeStatus
        bridge_objective_mismatch = $bridgeObjectiveMismatch
        bridge_canonical_objective = $bridgeCanonicalObjective
        bridge_task_objective = $bridgeTaskObjective
        maintenance_status = $maintenanceStatus
        maintenance_severity = $maintenanceSeverity
        watchdog_state = $watchdogState
        listener_request_id = $listenerRequestId
    }
}

function Repair-OperatorChatEvidenceLifecycleEntries {
    param(
        $Entries,
        $ProjectStatusOverrides = $null,
        [string]$ValidationHarness = ''
    )

    $repaired = New-Object System.Collections.Generic.List[object]
    $comparisonStatusCache = @{}
    $comparisonInfoCache = @{}
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) {
            continue
        }

        $merged = [ordered]@{}
        foreach ($property in $entry.PSObject.Properties) {
            $merged[$property.Name] = $property.Value
        }

        $releaseCondition = if ($entry.PSObject.Properties['release_condition']) { [string]$entry.release_condition } else { '' }
        $objectiveId = if ($entry.PSObject.Properties['objective_id']) { [string]$entry.objective_id } else { '' }
        if (-not [string]::Equals($releaseCondition, 'evidence_change', [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$repaired.Add([pscustomobject]$merged)
            continue
        }

        $currentStatus = $null
        $comparisonInfo = $null
        try {
            if ($ProjectStatusOverrides -is [hashtable] -and $ProjectStatusOverrides.ContainsKey($objectiveId)) {
                $currentStatus = $ProjectStatusOverrides[$objectiveId]
            }
            elseif (-not [string]::IsNullOrWhiteSpace($ValidationHarness)) {
                if (-not $comparisonInfoCache.ContainsKey($objectiveId)) {
                    try {
                        $comparisonInfoCache[$objectiveId] = Get-OperatorChatComparisonObjectiveInfo -ObjectiveId $objectiveId -AllowValidationFallback -ValidationHarness $ValidationHarness
                    }
                    catch {
                        $comparisonInfoCache[$objectiveId] = $null
                    }
                }
                $comparisonInfo = $comparisonInfoCache[$objectiveId]
                if (-not $comparisonStatusCache.ContainsKey($objectiveId)) {
                    try {
                        if ($comparisonInfo -and $comparisonInfo.ready -and [string]::Equals([string]$comparisonInfo.source, 'live_objective', [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace([string]$comparisonInfo.objective_id)) {
                            $comparisonStatusCache[$objectiveId] = Get-ProjectStatusPayload -ObjectiveId ([string]$comparisonInfo.objective_id) -ValidationHarness $ValidationHarness
                        }
                        else {
                            $comparisonStatusCache[$objectiveId] = $null
                        }
                    }
                    catch {
                        $comparisonStatusCache[$objectiveId] = $null
                    }
                }
                $currentStatus = $comparisonStatusCache[$objectiveId]
            }

            if ($null -eq $currentStatus -and -not [string]::IsNullOrWhiteSpace($objectiveId)) {
                try {
                    $currentStatus = Get-ProjectStatusPayload -ObjectiveId $objectiveId -ValidationHarness $ValidationHarness
                }
                catch {
                    $currentStatus = $null
                }
            }
        }
        catch {
            $currentStatus = $null
        }

        $baselineSnapshot = if ($entry.PSObject.Properties['baseline_evidence_snapshot']) { $entry.baseline_evidence_snapshot } elseif ($entry.PSObject.Properties['evidence_snapshot']) { $entry.evidence_snapshot } else { $null }
        $baselineFingerprint = if ($entry.PSObject.Properties['baseline_evidence_fingerprint']) { [string]$entry.baseline_evidence_fingerprint } elseif ($entry.PSObject.Properties['evidence_fingerprint']) { [string]$entry.evidence_fingerprint } else { '' }
        $currentSnapshot = if ($currentStatus) { Get-OperatorChatCommitmentEvidenceSnapshot -ProjectStatus $currentStatus } else { $null }
        if ($null -eq $currentSnapshot -and $comparisonInfo -and $comparisonInfo.ready -and [string]::Equals([string]$comparisonInfo.source, 'live_objective', [System.StringComparison]::OrdinalIgnoreCase) -and $validationHarnessProfile) {
            $currentSnapshot = New-OperatorChatHarnessComparisonSnapshot -BaselineSnapshot $baselineSnapshot -ValidationHarnessProfile $validationHarnessProfile -ComparisonObjectiveId ([string]$comparisonInfo.objective_id)
        }
        $currentFingerprint = if ($currentStatus) { Get-OperatorChatCommitmentEvidenceFingerprint -ProjectStatus $currentStatus } else { '' }
        if ([string]::IsNullOrWhiteSpace($currentFingerprint) -and $currentSnapshot) {
            $currentFingerprint = Get-OperatorChatCommitmentEvidenceFingerprintFromSnapshot -Snapshot $currentSnapshot
        }
        $evidenceDeltas = Compare-OperatorChatCommitmentEvidenceSnapshots -BaselineSnapshot $baselineSnapshot -CurrentSnapshot $currentSnapshot

        $merged['baseline_evidence_snapshot'] = $baselineSnapshot
        $merged['baseline_evidence_fingerprint'] = $baselineFingerprint
        $merged['current_evidence_snapshot'] = $currentSnapshot
        $merged['current_evidence_fingerprint'] = $currentFingerprint
        $merged['evidence_delta_count'] = [int](@($evidenceDeltas).Count)
        $merged['evidence_deltas'] = @($evidenceDeltas | Select-Object -First 8)

        if (-not [string]::IsNullOrWhiteSpace($baselineFingerprint) -and -not [string]::IsNullOrWhiteSpace($currentFingerprint) -and -not [string]::Equals($baselineFingerprint, $currentFingerprint, [System.StringComparison]::Ordinal)) {
            $merged['active'] = $false
            $merged['lifecycle_status'] = 'evidence_changed'
            $merged['revalidation_required'] = $true
            $merged['lifecycle_detail'] = if (@($evidenceDeltas).Count -gt 0) {
                'Live evidence changed since the commitment was recorded: {0}.' -f (@($evidenceDeltas | Select-Object -First 3 | ForEach-Object { [string]$_.label }) -join ', ')
            }
            else {
                'Live evidence changed since the commitment was recorded.'
            }
            $merged['escalation_reason'] = 'The evidence posture changed under the commitment, so refresh bounded evidence before recommitting or switching actions.'
            $merged['lifecycle_evaluator'] = 'repaired_dynamic_compare'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($currentFingerprint)) {
            $merged['lifecycle_evaluator'] = if ($comparisonInfo -and [string]::Equals([string]$comparisonInfo.source, 'live_objective', [System.StringComparison]::OrdinalIgnoreCase) -and $validationHarnessProfile) { 'harness_compare' } else { 'dynamic_compare' }
        }
        else {
            $merged['lifecycle_evaluator'] = if ($entry.PSObject.Properties['lifecycle_evaluator']) { [string]$entry.lifecycle_evaluator } else { 'fallback_static' }
        }

        [void]$repaired.Add([pscustomobject]$merged)
    }

    return @($repaired.ToArray())
}

function Repair-OperatorChatHarnessComparisonEntries {
    param(
        $Entries,
        [string]$ValidationHarness = ''
    )

    $validationHarnessProfile = if (-not [string]::IsNullOrWhiteSpace($ValidationHarness)) { Get-OperatorChatValidationHarnessProfile -ValidationHarness $ValidationHarness } else { $null }
    if ($null -eq $validationHarnessProfile) {
        return @($Entries)
    }

    $repaired = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) {
            continue
        }

        $merged = [ordered]@{}
        foreach ($property in $entry.PSObject.Properties) {
            $merged[$property.Name] = $property.Value
        }

        try {
            $releaseCondition = if ($entry.PSObject.Properties['release_condition']) { [string]$entry.release_condition } else { '' }
            $provenanceSource = if ($entry.PSObject.Properties['trust_chain_provenance_source']) { [string]$entry.trust_chain_provenance_source } else { '' }
            $currentSnapshot = if ($entry.PSObject.Properties['current_evidence_snapshot']) { $entry.current_evidence_snapshot } else { $null }
            if ([string]::Equals($releaseCondition, 'evidence_change', [System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($provenanceSource, 'live_objective', [System.StringComparison]::OrdinalIgnoreCase) -and $null -eq $currentSnapshot) {
                $baselineSnapshot = if ($entry.PSObject.Properties['baseline_evidence_snapshot']) { $entry.baseline_evidence_snapshot } elseif ($entry.PSObject.Properties['evidence_snapshot']) { $entry.evidence_snapshot } else { $null }
                $comparisonObjectiveId = if ($entry.PSObject.Properties['trust_chain_compare_objective_id']) { [string]$entry.trust_chain_compare_objective_id } else { '' }
                try {
                    $currentSnapshot = New-OperatorChatHarnessComparisonSnapshot -BaselineSnapshot $baselineSnapshot -ValidationHarnessProfile $validationHarnessProfile -ComparisonObjectiveId $comparisonObjectiveId
                }
                catch {
                    Write-UiCrashLog ('[HARNESS-COMPARE-SNAPSHOT] ' + $_.Exception.Message)
                    throw
                }
                try {
                    $currentFingerprint = Get-OperatorChatCommitmentEvidenceFingerprintFromSnapshot -Snapshot $currentSnapshot
                }
                catch {
                    Write-UiCrashLog ('[HARNESS-COMPARE-FINGERPRINT] ' + $_.Exception.Message)
                    throw
                }
                try {
                    $evidenceDeltas = Compare-OperatorChatCommitmentEvidenceSnapshots -BaselineSnapshot $baselineSnapshot -CurrentSnapshot $currentSnapshot
                }
                catch {
                    Write-UiCrashLog ('[HARNESS-COMPARE-DELTA] ' + $_.Exception.Message)
                    throw
                }

                $merged['current_evidence_snapshot'] = $currentSnapshot
                $merged['current_evidence_fingerprint'] = $currentFingerprint
                $merged['evidence_delta_count'] = [int](@($evidenceDeltas).Count)
                $merged['evidence_deltas'] = @($evidenceDeltas | Select-Object -First 8)
                if (@($evidenceDeltas).Count -gt 0) {
                    $merged['active'] = $false
                    $merged['lifecycle_status'] = 'evidence_changed'
                    $merged['revalidation_required'] = $true
                    $merged['lifecycle_detail'] = 'Bounded live compare harness changed the evidence posture, so the commitment now requires revalidation.'
                    $merged['escalation_reason'] = 'The bounded live compare harness changed the evidence posture, so refresh bounded evidence before recommitting.'
                }
                $merged['lifecycle_evaluator'] = 'harness_compare'
            }
        }
        catch {
            Write-UiCrashLog ('[HARNESS-COMPARE-REPAIR] ' + $_.Exception.Message)
        }

        [void]$repaired.Add([pscustomobject]$merged)
    }

    return @($repaired.ToArray())
}

function Write-OperatorChatFeedbackEntry {
    param($Entry)

    if ($null -eq $Entry) {
        return $null
    }

    Write-OperatorChatJsonArtifactEntry -LogPath $operatorChatFeedbackLogPath -LatestPath $operatorChatFeedbackLatestPath -Entry $Entry
    Clear-OperatorChatQueryCache
    return $Entry
}

function Get-OperatorChatFeedbackPayload {
    param(
        [int]$Limit = 12,
        [string]$ObjectiveId = '',
        [string]$Action = '',
        [string]$Intent = ''
    )

    $safeLimit = if ($Limit -lt 1) { 1 } elseif ($Limit -gt 100) { 100 } else { $Limit }
    $entries = @()
    if (Test-Path -Path $operatorChatFeedbackLogPath) {
        $tailMultiplier = if (@($ObjectiveId, $Action, $Intent | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) { 10 } else { 1 }
        $lines = Get-RecentLogLines -LogPath $operatorChatFeedbackLogPath -Tail ($safeLimit * $tailMultiplier)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace([string]$line)) {
                continue
            }
            try {
                $entry = $line | ConvertFrom-Json
                if (-not [string]::IsNullOrWhiteSpace($ObjectiveId) -and -not [string]::Equals([string]$entry.objective_id, [string]$ObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                if (-not [string]::IsNullOrWhiteSpace($Action) -and -not [string]::Equals([string]$entry.action, [string]$Action, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                if (-not [string]::IsNullOrWhiteSpace($Intent) -and -not [string]::Equals([string]$entry.intent, [string]$Intent, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $entries += @($entry)
            }
            catch {
            }
        }
    }

    $sorted = @($entries | Sort-Object timestamp_utc -Descending | Select-Object -First $safeLimit)
    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        count = @($sorted).Count
        latest_path = $operatorChatFeedbackLatestPath
        log_path = $operatorChatFeedbackLogPath
        entries = @($sorted)
    }
}

function Get-OperatorChatActionFeedbackProfile {
    param(
        [string]$ObjectiveId,
        [string]$Action,
        [string]$Intent = '',
        [int]$Limit = 12
    )

    $entries = @()
    if (Test-Path -Path $operatorChatFeedbackLogPath) {
        $parsedEntries = Get-RecentParsedLogEntries -LogPath $operatorChatFeedbackLogPath -Tail ($Limit * 10)
        foreach ($entry in $parsedEntries) {
            if ($null -eq $entry) {
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace($ObjectiveId) -and -not [string]::Equals([string]$entry.objective_id, [string]$ObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if (-not [string]::IsNullOrWhiteSpace($Action) -and -not [string]::Equals([string]$entry.action, [string]$Action, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $entries += @($entry)
        }
    }
    $entries = @($entries | Sort-Object timestamp_utc -Descending | Select-Object -First $Limit)
    $sameIntentEntries = if ([string]::IsNullOrWhiteSpace($Intent)) { @() } else { @($entries | Where-Object { [string]::Equals([string]$_.intent, [string]$Intent, [System.StringComparison]::OrdinalIgnoreCase) }) }
    $positiveCount = [int](@($entries | Where-Object { [string]::Equals([string]$_.polarity, 'positive', [System.StringComparison]::OrdinalIgnoreCase) }).Count)
    $negativeCount = [int](@($entries | Where-Object { [string]::Equals([string]$_.polarity, 'negative', [System.StringComparison]::OrdinalIgnoreCase) }).Count)
    $sameIntentPositive = [int](@($sameIntentEntries | Where-Object { [string]::Equals([string]$_.polarity, 'positive', [System.StringComparison]::OrdinalIgnoreCase) }).Count)
    $sameIntentNegative = [int](@($sameIntentEntries | Where-Object { [string]::Equals([string]$_.polarity, 'negative', [System.StringComparison]::OrdinalIgnoreCase) }).Count)
    $score = 0
    for ($index = 0; $index -lt @($entries).Count; $index++) {
        $entry = $entries[$index]
        $weight = switch ($index) {
            0 { 4 }
            1 { 3 }
            2 { 2 }
            default { 1 }
        }
        $polarityScore = if ([string]::Equals([string]$entry.polarity, 'positive', [System.StringComparison]::OrdinalIgnoreCase)) { 2 } else { -3 }
        $intentMultiplier = if (-not [string]::IsNullOrWhiteSpace($Intent) -and [string]::Equals([string]$entry.intent, [string]$Intent, [System.StringComparison]::OrdinalIgnoreCase)) { 2 } else { 1 }
        $score += ($weight * $polarityScore * $intentMultiplier)
    }

    $summary = if (($positiveCount + $negativeCount) -gt 0) {
        '{0} positive / {1} negative operator feedback ratings.' -f $positiveCount, $negativeCount
    }
    else {
        'No operator feedback ratings recorded for this action yet.'
    }
    $sameIntentSummary = if ([string]::IsNullOrWhiteSpace($Intent)) {
        ''
    }
    elseif (@($sameIntentEntries).Count -gt 0) {
        'Within intent {0}: {1} positive / {2} negative.' -f [string]$Intent, $sameIntentPositive, $sameIntentNegative
    }
    else {
        'No operator feedback ratings recorded for intent {0}.' -f [string]$Intent
    }

    return [pscustomobject]@{
        objective_id = [string]$ObjectiveId
        action = [string]$Action
        positive_count = $positiveCount
        negative_count = $negativeCount
        same_intent_positive_count = $sameIntentPositive
        same_intent_negative_count = $sameIntentNegative
        score = [int]$score
        summary = $summary
        same_intent_summary = $sameIntentSummary
    }
}

function Apply-OperatorChatValidationDriftToCommitmentEntries {
    param(
        $Entries,
        [string]$DriftMode = 'synthetic_drift'
    )

    $adjusted = @()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) {
            continue
        }

        $merged = [ordered]@{}
        foreach ($property in $entry.PSObject.Properties) {
            $merged[$property.Name] = $property.Value
        }

        if ([string]::Equals([string]$entry.state, 'until_evidence_change', [System.StringComparison]::OrdinalIgnoreCase)) {
            $baselineSnapshot = if ($entry.PSObject.Properties['baseline_evidence_snapshot']) { $entry.baseline_evidence_snapshot } elseif ($entry.PSObject.Properties['evidence_snapshot']) { $entry.evidence_snapshot } else { $null }
            $currentSnapshot = New-OperatorChatValidationDriftSnapshot -BaselineSnapshot $baselineSnapshot -DriftMode $DriftMode
            $driftField = ''
            $driftLabel = ''
            $before = ''
            $after = ''
            if ($baselineSnapshot -and $currentSnapshot) {
                $baselineListenerRequest = if ($baselineSnapshot.PSObject.Properties.Match('listener_request_id') | Select-Object -First 1) { [string]$baselineSnapshot.listener_request_id } else { '' }
                $currentListenerRequest = if ($currentSnapshot.PSObject.Properties.Match('listener_request_id') | Select-Object -First 1) { [string]$currentSnapshot.listener_request_id } else { '' }
                if (-not [string]::Equals($baselineListenerRequest, $currentListenerRequest, [System.StringComparison]::Ordinal)) {
                    $driftField = 'listener_request_id'
                    $driftLabel = 'Latest Listener Request'
                    $before = $baselineListenerRequest
                    $after = $currentListenerRequest
                }
                else {
                    $baselineObjectiveStatus = if ($baselineSnapshot.PSObject.Properties.Match('objective_status') | Select-Object -First 1) { [string]$baselineSnapshot.objective_status } else { '' }
                    $currentObjectiveStatus = if ($currentSnapshot.PSObject.Properties.Match('objective_status') | Select-Object -First 1) { [string]$currentSnapshot.objective_status } else { '' }
                    if (-not [string]::Equals($baselineObjectiveStatus, $currentObjectiveStatus, [System.StringComparison]::Ordinal)) {
                        $driftField = 'objective_status'
                        $driftLabel = 'Objective Status'
                        $before = $baselineObjectiveStatus
                        $after = $currentObjectiveStatus
                    }
                }
            }
            $evidenceDeltas = if (-not [string]::IsNullOrWhiteSpace($driftField)) {
                @([pscustomobject]@{
                        field = $driftField
                        label = $driftLabel
                        before = $before
                        after = $after
                    })
            }
            else {
                @()
            }
            if ($currentSnapshot -and @($evidenceDeltas).Count -gt 0) {
                $merged['active'] = $false
                $merged['lifecycle_status'] = 'evidence_changed'
                $merged['revalidation_required'] = $true
                $merged['lifecycle_detail'] = 'Validation-only synthetic drift changed the evidence posture so the evidence-bound commitment now requires revalidation.'
                $merged['escalation_reason'] = 'Validation-only synthetic drift invalidated the evidence-bound commitment; refresh bounded evidence before recommitting.'
                $merged['current_evidence_snapshot'] = $currentSnapshot
                $merged['current_evidence_fingerprint'] = Get-OperatorChatCommitmentEvidenceFingerprintFromSnapshot -Snapshot $currentSnapshot
                $merged['evidence_delta_count'] = [int](@($evidenceDeltas).Count)
                $merged['evidence_deltas'] = @($evidenceDeltas)
            }
        }

        $adjusted += ,([pscustomobject]$merged)
    }

    return @($adjusted)
}

function Resolve-OperatorChatCommitmentLifecycle {
    param(
        $Entry,
        $ProjectStatus
    )

    $normalizedState = if ($Entry) { ([string]$Entry.state).Trim().ToLowerInvariant() } else { '' }
    $releaseCondition = if ($Entry -and $Entry.PSObject.Properties['release_condition']) { [string]$Entry.release_condition } else { '' }
    if ([string]::IsNullOrWhiteSpace($releaseCondition)) {
        $releaseCondition = switch ($normalizedState) {
            'timeboxed' { 'timebox' }
            'until_evidence_change' { 'evidence_change' }
            default { 'manual_clear' }
        }
    }

    $now = (Get-Date).ToUniversalTime()
    $expiresAtText = if ($Entry -and $Entry.PSObject.Properties['expires_at']) { [string]$Entry.expires_at } else { '' }
    $expiresAtUtc = $null
    if (-not [string]::IsNullOrWhiteSpace($expiresAtText)) {
        try {
            $expiresAtUtc = [datetime]::Parse($expiresAtText).ToUniversalTime()
        }
        catch {
            $expiresAtUtc = $null
        }
    }

    $active = $false
    $lifecycleStatus = 'inactive'
    $revalidationRequired = $false
    $detail = ''
    $escalationReason = ''
    $isTerminal = $false
    $terminalState = ''
    $terminalDetail = ''
    $expiresInMinutes = $null
    $baselineFingerprint = if ($Entry -and $Entry.PSObject.Properties['evidence_fingerprint']) { [string]$Entry.evidence_fingerprint } else { '' }
    $baselineSnapshot = if ($Entry -and $Entry.PSObject.Properties['evidence_snapshot']) { $Entry.evidence_snapshot } else { $null }
    $currentSnapshot = if ($ProjectStatus) { Get-OperatorChatCommitmentEvidenceSnapshot -ProjectStatus $ProjectStatus } else { $null }
    $currentFingerprint = if ($ProjectStatus) { Get-OperatorChatCommitmentEvidenceFingerprint -ProjectStatus $ProjectStatus } else { '' }
    $evidenceDeltas = Compare-OperatorChatCommitmentEvidenceSnapshots -BaselineSnapshot $baselineSnapshot -CurrentSnapshot $currentSnapshot

    switch ($normalizedState) {
        'committed' {
            $active = $true
            $lifecycleStatus = 'active'
            $detail = 'Commitment remains active until the operator clears it.'
        }
        'timeboxed' {
            if ($null -eq $expiresAtUtc) {
                $active = $true
                $lifecycleStatus = 'active'
                $detail = 'Timeboxed commitment is active, but no expiry timestamp was retained.'
            }
            else {
                $remainingMinutes = [math]::Ceiling(($expiresAtUtc - $now).TotalMinutes)
                $expiresInMinutes = [int]$remainingMinutes
                if ($expiresAtUtc -le $now) {
                    $lifecycleStatus = 'expired'
                    $revalidationRequired = $true
                    $detail = 'Timeboxed commitment expired and should be revalidated before reuse.'
                    $escalationReason = 'The timeboxed commitment expired, so refresh bounded evidence before recommitting or switching actions.'
                }
                elseif ($remainingMinutes -le 5) {
                    $active = $true
                    $lifecycleStatus = 'expiring'
                    $revalidationRequired = $true
                    $detail = ('Timeboxed commitment expires in about {0} minute{1}.' -f [int]$remainingMinutes, $(if ([int]$remainingMinutes -eq 1) { '' } else { 's' }))
                    $escalationReason = 'The timeboxed commitment is expiring soon, so refresh status before renewing or changing action.'
                }
                else {
                    $active = $true
                    $lifecycleStatus = 'active'
                    $detail = ('Timeboxed commitment remains active for about {0} minute{1}.' -f [int]$remainingMinutes, $(if ([int]$remainingMinutes -eq 1) { '' } else { 's' }))
                }
            }
        }
        'until_evidence_change' {
            if ([string]::IsNullOrWhiteSpace($baselineFingerprint) -or [string]::IsNullOrWhiteSpace($currentFingerprint) -or [string]::Equals($baselineFingerprint, $currentFingerprint, [System.StringComparison]::Ordinal)) {
                $active = $true
                $lifecycleStatus = 'active'
                $detail = 'Commitment remains active until the live evidence posture changes materially.'
            }
            else {
                $lifecycleStatus = 'evidence_changed'
                $revalidationRequired = $true
                $detail = if (@($evidenceDeltas).Count -gt 0) {
                    'Live evidence changed since the commitment was recorded: {0}.' -f (@($evidenceDeltas | Select-Object -First 3 | ForEach-Object { [string]$_.label }) -join ', ')
                }
                else {
                    'Live evidence changed since the commitment was recorded.'
                }
                $escalationReason = 'The evidence posture changed under the commitment, so refresh bounded evidence before recommitting or switching actions.'
            }
        }
        'cleared' {
            $lifecycleStatus = 'cleared'
            $detail = 'Commitment was explicitly cleared by the operator.'
        }
        'satisfied' {
            $lifecycleStatus = 'satisfied'
            $detail = 'Commitment was completed and marked satisfied by the operator.'
            $isTerminal = $true
            $terminalState = 'satisfied'
            $terminalDetail = $detail
        }
        'abandoned' {
            $lifecycleStatus = 'abandoned'
            $detail = 'Commitment was explicitly abandoned by the operator.'
            $isTerminal = $true
            $terminalState = 'abandoned'
            $terminalDetail = $detail
        }
        default {
            $detail = 'Commitment state is unknown and should not suppress or steer action selection.'
        }
    }

    return [pscustomobject]@{
        active = $active
        lifecycle_status = $lifecycleStatus
        release_condition = $releaseCondition
        expires_at = if ($null -ne $expiresAtUtc) { $expiresAtUtc.ToString('o') } else { '' }
        expires_in_minutes = if ($null -ne $expiresInMinutes) { [int]$expiresInMinutes } else { $null }
        revalidation_required = $revalidationRequired
        is_terminal = $isTerminal
        terminal_state = $terminalState
        terminal_detail = $terminalDetail
        detail = $detail
        escalation_reason = $escalationReason
        baseline_evidence_fingerprint = $baselineFingerprint
        current_evidence_fingerprint = $currentFingerprint
        baseline_evidence_snapshot = $baselineSnapshot
        current_evidence_snapshot = $currentSnapshot
        evidence_delta_count = [int](@($evidenceDeltas).Count)
        evidence_deltas = @($evidenceDeltas | Select-Object -First 8)
    }
}

function Get-OperatorChatCommitmentResolutionKey {
    param($Entry)

    if ($null -eq $Entry) {
        return ''
    }

    $objectiveId = ''
    if ($Entry.PSObject.Properties['current_scope_selected_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.current_scope_selected_objective_id)) {
        $objectiveId = [string]$Entry.current_scope_selected_objective_id
    }
    elseif ($Entry.PSObject.Properties['scope_selected_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.scope_selected_objective_id)) {
        $objectiveId = [string]$Entry.scope_selected_objective_id
    }
    elseif ($Entry.PSObject.Properties['objective_id']) {
        $objectiveId = [string]$Entry.objective_id
    }

    $validationHarness = ''
    if ($Entry.PSObject.Properties['current_scope_validation_harness'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.current_scope_validation_harness)) {
        $validationHarness = [string]$Entry.current_scope_validation_harness
    }
    elseif ($Entry.PSObject.Properties['validation_harness']) {
        $validationHarness = [string]$Entry.validation_harness
    }

    return ('{0}|{1}' -f $objectiveId.Trim(), $validationHarness.Trim()).ToLowerInvariant()
}

function Resolve-OperatorChatCommitmentTerminalProjection {
    param(
        [object[]]$Entries
    )

    $resolved = New-Object System.Collections.Generic.List[object]
    $latestByResolution = @{}
    foreach ($entry in @($Entries | Sort-Object timestamp_utc -Descending)) {
        if ($null -eq $entry) {
            continue
        }

        $merged = [ordered]@{}
        foreach ($property in $entry.PSObject.Properties) {
            $merged[$property.Name] = $property.Value
        }

        $state = if ($entry.PSObject.Properties['state']) { ([string]$entry.state).Trim().ToLowerInvariant() } else { '' }
        $lifecycleStatus = if ($entry.PSObject.Properties['lifecycle_status']) { [string]$entry.lifecycle_status } else { '' }
        $isTerminal = if ($entry.PSObject.Properties['is_terminal']) { [bool]$entry.is_terminal } else { @('satisfied', 'abandoned', 'superseded', 'ineffective') -contains $lifecycleStatus }
        $terminalState = if ($entry.PSObject.Properties['terminal_state']) { [string]$entry.terminal_state } else { '' }
        $terminalDetail = if ($entry.PSObject.Properties['terminal_detail']) { [string]$entry.terminal_detail } else { '' }
        $terminalSuccessorCommitmentId = if ($entry.PSObject.Properties['terminal_successor_commitment_id']) { [string]$entry.terminal_successor_commitment_id } else { '' }
        $terminalHistory = if ($entry.PSObject.Properties['terminal_history']) { $entry.terminal_history } else { $null }
        $resolutionKey = Get-OperatorChatCommitmentResolutionKey -Entry $entry
        $newerEntry = if (-not [string]::IsNullOrWhiteSpace($resolutionKey) -and $latestByResolution.ContainsKey($resolutionKey)) { $latestByResolution[$resolutionKey] } else { $null }

        if (-not $isTerminal -and -not [string]::Equals($state, 'cleared', [System.StringComparison]::OrdinalIgnoreCase) -and $newerEntry) {
            $lifecycleStatus = 'superseded'
            $isTerminal = $true
            $terminalState = 'superseded'
            $terminalSuccessorCommitmentId = [string]$newerEntry.commitment_id
            $terminalDetail = if ([string]::Equals([string]$newerEntry.action, [string]$entry.action, [System.StringComparison]::OrdinalIgnoreCase)) {
                'A newer commitment decision for this action superseded this earlier commitment before it reached a terminal outcome.'
            }
            else {
                'A newer commitment decision for this objective superseded this earlier commitment before it reached a terminal outcome.'
            }
            $merged['active'] = $false
            $merged['revalidation_required'] = $false
            $merged['escalation_reason'] = ''
            $merged['lifecycle_detail'] = $terminalDetail
        }
        elseif ($isTerminal -and [string]::Equals($state, 'abandoned', [System.StringComparison]::OrdinalIgnoreCase) -and $terminalHistory -and $terminalHistory.PSObject.Properties['ineffective_signal'] -and [bool]$terminalHistory.ineffective_signal) {
            $recentTerminalAt = if ($terminalHistory.PSObject.Properties['recent_terminal_at']) { [string]$terminalHistory.recent_terminal_at } else { '' }
            $entryTimestamp = if ($entry.PSObject.Properties['timestamp_utc']) { [string]$entry.timestamp_utc } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($recentTerminalAt) -and [string]::Equals($entryTimestamp, $recentTerminalAt, [System.StringComparison]::OrdinalIgnoreCase)) {
                $lifecycleStatus = 'ineffective'
                $isTerminal = $true
                $terminalState = 'ineffective'
                $terminalDetail = if ($terminalHistory.PSObject.Properties['ineffective_basis'] -and -not [string]::IsNullOrWhiteSpace([string]$terminalHistory.ineffective_basis)) {
                    [string]$terminalHistory.ineffective_basis
                }
                else {
                    'Repeated abandoned terminal outcomes mark this action pattern ineffective until bounded evidence materially changes.'
                }
                $merged['active'] = $false
                $merged['revalidation_required'] = $false
                $merged['escalation_reason'] = ''
                $merged['lifecycle_detail'] = $terminalDetail
            }
        }

        $merged['lifecycle_status'] = $lifecycleStatus
        $merged['is_terminal'] = $isTerminal
        $merged['terminal_state'] = $terminalState
        $merged['terminal_detail'] = $terminalDetail
        $merged['terminal_successor_commitment_id'] = $terminalSuccessorCommitmentId
        [void]$resolved.Add([pscustomobject]$merged)

        if (-not [string]::IsNullOrWhiteSpace($resolutionKey) -and -not $latestByResolution.ContainsKey($resolutionKey)) {
            $latestByResolution[$resolutionKey] = [pscustomobject]@{
                commitment_id = if ($entry.PSObject.Properties['commitment_id']) { [string]$entry.commitment_id } else { '' }
                action = if ($entry.PSObject.Properties['action']) { [string]$entry.action } else { '' }
            }
        }
    }

    return @($resolved.ToArray())
}

function Get-OperatorChatCommitmentTerminalFollowup {
    param($Commitment)

    if ($null -eq $Commitment) {
        return $null
    }

    $terminalState = if ($Commitment.PSObject.Properties['terminal_state']) { [string]$Commitment.terminal_state } else { '' }
    if ([string]::IsNullOrWhiteSpace($terminalState) -and $Commitment.PSObject.Properties['lifecycle_status']) {
        $lifecycleStatus = [string]$Commitment.lifecycle_status
        if (@('satisfied', 'abandoned', 'superseded', 'ineffective') -contains $lifecycleStatus) {
            $terminalState = $lifecycleStatus
        }
    }
    if ([string]::IsNullOrWhiteSpace($terminalState)) {
        return $null
    }

    $actionLabel = if ($Commitment.PSObject.Properties['action_label'] -and -not [string]::IsNullOrWhiteSpace([string]$Commitment.action_label)) { [string]$Commitment.action_label } elseif ($Commitment.PSObject.Properties['action']) { [string]$Commitment.action } else { 'the prior commitment' }
    switch ($terminalState) {
        'satisfied' {
            return [pscustomobject]@{
                state = 'satisfied'
                action = 'refresh-governance-snapshot'
                label = 'Refresh Governance Snapshot'
                reason = "The last commitment for $actionLabel was satisfied. Refresh bounded evidence before choosing the next action."
                message = "The latest operator commitment for $actionLabel ended as satisfied, so TOD should refresh evidence before proposing the next move."
                flag = 'operator_commitment_terminal'
            }
        }
        'abandoned' {
            return [pscustomobject]@{
                state = 'abandoned'
                action = 'refresh-project-status'
                label = 'Refresh Status Snapshot'
                reason = "The last commitment for $actionLabel was abandoned. Re-read current status before switching actions."
                message = "The latest operator commitment for $actionLabel was abandoned, so TOD should re-ground on fresh evidence before pivoting."
                flag = 'operator_commitment_terminal'
            }
        }
        'superseded' {
            return [pscustomobject]@{
                state = 'superseded'
                action = 'refresh-project-status'
                label = 'Refresh Status Snapshot'
                reason = "A newer commitment decision superseded the last commitment for $actionLabel. Refresh status before recommitting or switching actions."
                message = "The latest non-active commitment for $actionLabel was superseded by a newer commitment decision, so TOD should refresh status before treating it as still live."
                flag = 'operator_commitment_superseded'
            }
        }
        'ineffective' {
            return [pscustomobject]@{
                state = 'ineffective'
                action = 'refresh-governance-snapshot'
                label = 'Refresh Governance Snapshot'
                reason = "Recent terminal outcomes suggest the last commitment for $actionLabel is ineffective. Refresh bounded evidence before retrying it."
                message = "The latest operator commitment for $actionLabel is now treated as ineffective, so TOD should refresh bounded evidence before retrying that action pattern."
                flag = 'operator_commitment_ineffective'
            }
        }
    }

    return $null
}

function Get-OperatorChatCommitmentScopeSnapshot {
    param(
        $ProjectStatus,
        [string]$ValidationHarness = ''
    )

    $resolvedHarness = [string]$ValidationHarness
    $resolvedHarnessLabel = ''
    if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['validation_harness'] -and $ProjectStatus.validation_harness) {
        if ([string]::IsNullOrWhiteSpace($resolvedHarness) -and $ProjectStatus.validation_harness.PSObject.Properties['name']) {
            $resolvedHarness = [string]$ProjectStatus.validation_harness.name
        }
        if ($ProjectStatus.validation_harness.PSObject.Properties['label']) {
            $resolvedHarnessLabel = [string]$ProjectStatus.validation_harness.label
        }
    }

    $mimProposal = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['mim_proposal']) { $ProjectStatus.mim_proposal } else { $null }
    $mimProposalConflict = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['mim_proposal_conflict']) { $ProjectStatus.mim_proposal_conflict } else { $null }
    $mimProposalArbitration = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['mim_proposal_arbitration']) { $ProjectStatus.mim_proposal_arbitration } else { $null }
    $mimProposalMergePolicy = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['mim_proposal_merge_policy']) { $ProjectStatus.mim_proposal_merge_policy } else { $null }
    $proposalObjectiveId = ''
    $proposalId = ''
    if ($mimProposal -and [bool]$mimProposal.available) {
        $proposalId = if ($mimProposal.PSObject.Properties['task_id']) { [string]$mimProposal.task_id } else { '' }
        $proposalObjectiveId = if ($mimProposal.PSObject.Properties['normalized_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$mimProposal.normalized_objective_id)) {
            [string]$mimProposal.normalized_objective_id
        }
        else {
            [string]$mimProposal.objective_id
        }
        $proposalObjectiveId = Normalize-ObjectiveIdValue -Value $proposalObjectiveId
    }

    return [pscustomobject]@{
        selected_objective_id = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['selected_objective_id']) { Normalize-ObjectiveIdValue -Value ([string]$ProjectStatus.selected_objective_id) } else { '' }
        validation_harness = $resolvedHarness
        validation_harness_label = $resolvedHarnessLabel
        scope_kind = if (-not [string]::IsNullOrWhiteSpace($proposalId) -or -not [string]::IsNullOrWhiteSpace($proposalObjectiveId)) { 'proposal_specific' } else { 'objective_wide' }
        proposal_id = $proposalId
        proposal_objective_id = $proposalObjectiveId
        proposal_conflict_status = if ($mimProposalConflict) { [string]$mimProposalConflict.status } else { '' }
        proposal_arbitration_winner = if ($mimProposalArbitration) { [string]$mimProposalArbitration.winner } else { '' }
        proposal_merge_policy_status = if ($mimProposalMergePolicy) { [string]$mimProposalMergePolicy.status } else { '' }
    }
}

function Get-OperatorChatCommitmentScopeKind {
    param(
        [string]$ProposalId = '',
        [string]$ProposalObjectiveId = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($ProposalId) -or -not [string]::IsNullOrWhiteSpace($ProposalObjectiveId)) {
        return 'proposal_specific'
    }

    return 'objective_wide'
}

function Resolve-OperatorChatCommitmentScope {
    param(
        $Entry,
        $ProjectStatus,
        [string]$ValidationHarness = ''
    )

    $currentScope = Get-OperatorChatCommitmentScopeSnapshot -ProjectStatus $ProjectStatus -ValidationHarness $ValidationHarness
    $entryObjectiveId = if ($Entry -and $Entry.PSObject.Properties['objective_id']) { Normalize-ObjectiveIdValue -Value ([string]$Entry.objective_id) } else { '' }
    $entryHarness = if ($Entry -and $Entry.PSObject.Properties['validation_harness']) { [string]$Entry.validation_harness } else { '' }
    $entryProposalId = if ($Entry -and $Entry.PSObject.Properties['scope_proposal_id']) { [string]$Entry.scope_proposal_id } else { '' }
    $entryProposalObjectiveId = if ($Entry -and $Entry.PSObject.Properties['scope_proposal_objective_id']) { Normalize-ObjectiveIdValue -Value ([string]$Entry.scope_proposal_objective_id) } else { '' }
    $entryMergePolicyStatus = if ($Entry -and $Entry.PSObject.Properties['scope_proposal_merge_policy_status']) { [string]$Entry.scope_proposal_merge_policy_status } else { '' }
    $entryScopeKind = Get-OperatorChatCommitmentScopeKind -ProposalId $entryProposalId -ProposalObjectiveId $entryProposalObjectiveId
    $currentScopeKind = if ($currentScope -and $currentScope.PSObject.Properties['scope_kind']) { [string]$currentScope.scope_kind } else { (Get-OperatorChatCommitmentScopeKind -ProposalId ([string]$currentScope.proposal_id) -ProposalObjectiveId ([string]$currentScope.proposal_objective_id)) }

    $status = 'in_scope'
    $inScope = $true
    $summary = 'Commitment remains in scope for the current objective and bounded evaluation posture.'
    $overlapStatus = 'exact'
    $conflictReason = ''
    $conflictResolution = 'active'
    $blocksActivation = $false
    $precedenceRank = if ([string]::Equals($entryScopeKind, 'proposal_specific', [System.StringComparison]::OrdinalIgnoreCase)) { 3 } else { 2 }
    $influenceSummary = if ([string]::Equals($entryScopeKind, 'proposal_specific', [System.StringComparison]::OrdinalIgnoreCase)) {
        'Proposal-specific commitment currently holds the narrowest valid scope and should steer active arbitration and recommit decisions.'
    }
    else {
        'Objective-wide commitment can steer active arbitration only while no narrower proposal-specific commitment takes precedence.'
    }

    if (-not [string]::IsNullOrWhiteSpace($entryObjectiveId) -and -not [string]::Equals($entryObjectiveId, [string]$currentScope.selected_objective_id, [System.StringComparison]::OrdinalIgnoreCase)) {
        $status = 'objective_shifted'
        $inScope = $false
        $summary = 'Commitment is out of scope because TOD is now centered on a different objective.'
        $overlapStatus = 'none'
        $conflictReason = 'objective_scope_precedence'
        $conflictResolution = 'block'
        $blocksActivation = $true
        $precedenceRank = 0
        $influenceSummary = 'Commitment is excluded from active arbitration because its objective scope no longer matches the live TOD objective.'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($entryHarness) -or -not [string]::IsNullOrWhiteSpace([string]$currentScope.validation_harness)) {
        if (-not [string]::Equals($entryHarness, [string]$currentScope.validation_harness, [System.StringComparison]::OrdinalIgnoreCase)) {
            $status = 'harness_shifted'
            $inScope = $false
            $summary = 'Commitment is out of scope because the active validation harness changed.'
            $overlapStatus = 'none'
            $conflictReason = 'validation_harness_precedence'
            $conflictResolution = 'block'
            $blocksActivation = $true
            $precedenceRank = 0
            $influenceSummary = 'Commitment is excluded from active arbitration because its bounded validation harness no longer matches the live compare posture.'
        }
    }

    if ($inScope) {
        $currentProposalId = [string]$currentScope.proposal_id
        $currentProposalObjectiveId = [string]$currentScope.proposal_objective_id
        $currentMergePolicyStatus = [string]$currentScope.proposal_merge_policy_status

        if ([string]::Equals($entryScopeKind, 'proposal_specific', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ([string]::IsNullOrWhiteSpace($currentProposalId) -and [string]::IsNullOrWhiteSpace($currentProposalObjectiveId)) {
                $status = 'proposal_context_missing'
                $inScope = $false
                $summary = 'Commitment is out of scope because it was recorded against a narrower proposal-specific scope that is no longer live.'
                $overlapStatus = 'none'
                $conflictReason = 'proposal_scope_missing'
                $conflictResolution = 'block'
                $blocksActivation = $true
                $precedenceRank = 0
                $influenceSummary = 'Proposal-specific commitment is excluded from active arbitration because no live proposal-specific scope is currently available.'
            }
            elseif (-not [string]::IsNullOrWhiteSpace($entryProposalId) -and -not [string]::IsNullOrWhiteSpace($currentProposalId) -and -not [string]::Equals($entryProposalId, $currentProposalId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $status = 'proposal_shifted'
                $inScope = $false
                $summary = 'Commitment is out of scope because the live MIM proposal identity changed.'
                $overlapStatus = 'none'
                $conflictReason = 'proposal_identity_precedence'
                $conflictResolution = 'block'
                $blocksActivation = $true
                $precedenceRank = 0
                $influenceSummary = 'Proposal-specific commitment is excluded from active arbitration because a different live proposal identity is now in scope.'
            }
            elseif (-not [string]::Equals($entryProposalObjectiveId, $currentProposalObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) -and
                -not [string]::Equals($entryMergePolicyStatus, 'merge_ready', [System.StringComparison]::OrdinalIgnoreCase)) {
                $status = 'proposal_shifted'
                $inScope = $false
                $summary = 'Commitment is out of scope because the live proposal objective shifted while merge policy is not merge_ready.'
                $overlapStatus = 'none'
                $conflictReason = 'proposal_objective_precedence'
                $conflictResolution = 'block'
                $blocksActivation = $true
                $precedenceRank = 0
                $influenceSummary = 'Proposal-specific commitment is excluded from active arbitration because the live proposal objective no longer matches its recorded scope.'
            }
            elseif (-not [string]::Equals($entryMergePolicyStatus, $currentMergePolicyStatus, [System.StringComparison]::OrdinalIgnoreCase) -and
                    -not [string]::Equals($currentMergePolicyStatus, 'merge_ready', [System.StringComparison]::OrdinalIgnoreCase)) {
                $status = 'proposal_shifted'
                $inScope = $false
                $summary = 'Commitment is out of scope because the live proposal merge posture changed.'
                $overlapStatus = 'none'
                $conflictReason = 'proposal_merge_posture_precedence'
                $conflictResolution = 'block'
                $blocksActivation = $true
                $precedenceRank = 0
                $influenceSummary = 'Proposal-specific commitment is excluded from active arbitration because the live proposal merge posture no longer matches its recorded scope.'
            }
            else {
                $status = 'proposal_nested_match'
                $summary = 'Commitment remains in exact proposal-specific scope under the current objective and proposal posture.'
                $overlapStatus = 'exact'
                $conflictReason = ''
                $conflictResolution = 'active'
                $blocksActivation = $false
                $precedenceRank = 3
                $influenceSummary = 'Proposal-specific commitment takes highest precedence for active arbitration and recommit decisions because it matches the live proposal identity.'
            }
        }
        elseif ([string]::Equals($currentScopeKind, 'proposal_specific', [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($entryObjectiveId, [string]$currentScope.selected_objective_id, [System.StringComparison]::OrdinalIgnoreCase)) {
            $status = 'objective_parent_scope'
            $summary = 'Commitment remains objective-wide and in scope, but it is downgraded beneath the active proposal-specific posture.'
            $overlapStatus = 'nested_parent'
            $conflictReason = 'proposal_specific_scope_takes_precedence'
            $conflictResolution = 'downgrade'
            $blocksActivation = $false
            $precedenceRank = 1
            $influenceSummary = 'Objective-wide commitment is retained as background context, but proposal-specific scope takes precedence for active arbitration and recommit decisions.'
        }
        else {
            $status = 'in_scope'
            $summary = 'Commitment remains objective-wide and in scope for the current objective.'
            $overlapStatus = 'exact'
            $conflictReason = ''
            $conflictResolution = 'active'
            $blocksActivation = $false
            $precedenceRank = 2
            $influenceSummary = 'Objective-wide commitment can steer active arbitration because no narrower live proposal-specific scope currently outranks it.'
        }
    }

    return [pscustomobject]@{
        in_scope = [bool]$inScope
        status = $status
        summary = $summary
        scope_kind = $entryScopeKind
        current_scope_kind = $currentScopeKind
        overlap_status = $overlapStatus
        conflict_reason = $conflictReason
        conflict_resolution = $conflictResolution
        blocks_activation = [bool]$blocksActivation
        precedence_rank = [int]$precedenceRank
        influence_summary = $influenceSummary
        current_scope = $currentScope
    }
}

function Get-OperatorChatReasoningPayload {
    param(
        [int]$Limit = 8,
        [string]$BundleId = ''
    )

    $safeLimit = if ($Limit -lt 1) { 1 } elseif ($Limit -gt 50) { 50 } else { $Limit }
    $entries = @()
    if (Test-Path -Path $operatorChatReasoningLogPath) {
        $tailMultiplier = if ([string]::IsNullOrWhiteSpace($BundleId)) { 1 } else { 10 }
        $lines = Get-RecentLogLines -LogPath $operatorChatReasoningLogPath -Tail ($safeLimit * $tailMultiplier)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace([string]$line)) {
                continue
            }

            try {
                $entry = $line | ConvertFrom-Json
                if (-not [string]::IsNullOrWhiteSpace($BundleId) -and -not [string]::Equals([string]$entry.reasoning_bundle_id, [string]$BundleId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                $entries += @($entry)
            }
            catch {
            }
        }
    }

    $sorted = @($entries | Sort-Object generated_at_utc -Descending | Select-Object -First $safeLimit)
    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        count = @($sorted).Count
        latest_path = $operatorChatReasoningLatestPath
        log_path = $operatorChatReasoningLogPath
        filters = [pscustomobject]@{
            bundle_id = [string]$BundleId
            limit = $safeLimit
        }
        entries = @($sorted)
    }
}

function Get-OperatorChatCommitmentPayload {
    param(
        [int]$Limit = 6,
        [string]$CommitmentId = '',
        [string]$PreviewId = '',
        [string]$ReasoningBundleId = '',
        [string]$ObjectiveId = '',
        [string]$State = '',
        $ProjectStatusOverrides = $null,
        [string]$ValidationHarness = '',
        [switch]$SkipLifecycleEvaluation
    )

    $safeLimit = if ($Limit -lt 1) { 1 } elseif ($Limit -gt 50) { 50 } else { $Limit }
    $entries = @()
    if (Test-Path -Path $operatorChatCommitmentLogPath) {
        $filterCount = @($CommitmentId, $PreviewId, $ReasoningBundleId, $ObjectiveId, $State | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
        $tailMultiplier = if ($filterCount -gt 0) { 10 } else { 1 }
        $lines = Get-RecentLogLines -LogPath $operatorChatCommitmentLogPath -Tail ($safeLimit * $tailMultiplier)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace([string]$line)) {
                continue
            }

            try {
                $entry = $line | ConvertFrom-Json
                if (-not [string]::IsNullOrWhiteSpace($CommitmentId) -and -not [string]::Equals([string]$entry.commitment_id, [string]$CommitmentId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($PreviewId) -and -not [string]::Equals([string]$entry.preview_id, [string]$PreviewId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($ReasoningBundleId) -and -not [string]::Equals([string]$entry.reasoning_bundle_id, [string]$ReasoningBundleId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($ObjectiveId) -and -not [string]::Equals([string]$entry.objective_id, [string]$ObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($State) -and -not [string]::Equals([string]$entry.state, [string]$State, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                $entries += @($entry)
            }
            catch {
            }
        }
    }

    $sorted = @($entries | Sort-Object timestamp_utc -Descending | Select-Object -First $safeLimit)
    if ($SkipLifecycleEvaluation) {
        $quickEntries = @()
        foreach ($entry in $sorted) {
            if ($null -eq $entry) {
                continue
            }

            $stateValue = if ($entry.PSObject.Properties['state']) { ([string]$entry.state).Trim().ToLowerInvariant() } else { '' }
            $isTerminal = @('satisfied', 'abandoned', 'superseded', 'ineffective') -contains $stateValue
            $active = @('committed', 'timeboxed', 'until_evidence_change') -contains $stateValue
            if ($stateValue -eq 'cleared') {
                $active = $false
            }

            $merged = [ordered]@{}
            foreach ($property in $entry.PSObject.Properties) {
                $merged[$property.Name] = $property.Value
            }
            $merged['active'] = [bool]$active
            $merged['lifecycle_status'] = if ($isTerminal -or $stateValue -eq 'cleared') { $stateValue } else { if ($active) { 'active' } else { 'inactive' } }
            $merged['is_terminal'] = [bool]$isTerminal
            $merged['revalidation_required'] = $false
            $merged['lifecycle_detail'] = ''
            $merged['escalation_reason'] = ''
            $merged['terminal_state'] = if ($isTerminal) { $stateValue } else { '' }
            $merged['terminal_detail'] = ''
            $merged['scope_status'] = 'in_scope'
            $merged['scope_summary'] = 'Fast-path scope evaluation defaults to objective-wide active scope.'
            $merged['scope_kind'] = 'objective_wide'
            $merged['current_scope_kind'] = 'objective_wide'
            $merged['scope_overlap_status'] = 'exact'
            $merged['scope_conflict_reason'] = ''
            $merged['scope_conflict_resolution'] = 'active'
            $merged['scope_influence_summary'] = 'Fast-path commitment scope is objective-wide unless full lifecycle evaluation is requested.'
            $merged['scope_in_scope'] = $true
            $merged['scope_blocks_activation'] = $false
            $merged['scope_precedence_rank'] = 1
            $quickEntries += ,([pscustomobject]$merged)
        }

        return [pscustomobject]@{
            ok = $true
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            count = @($quickEntries).Count
            latest_path = $operatorChatCommitmentLatestPath
            log_path = $operatorChatCommitmentLogPath
            filters = [pscustomobject]@{
                commitment_id = [string]$CommitmentId
                preview_id = [string]$PreviewId
                reasoning_bundle_id = [string]$ReasoningBundleId
                objective_id = [string]$ObjectiveId
                state = [string]$State
                limit = $safeLimit
                mode = 'skip_lifecycle_evaluation'
            }
            entries = @($quickEntries)
        }
    }

    $evaluatedEntries = New-Object System.Collections.Generic.List[object]
    $statusCache = @{}
    $historyCache = @{}
    $comparisonInfoCache = @{}
    foreach ($entry in $sorted) {
        $lifecycle = $null
        try {
            $entryObjectiveId = if ($entry -and $entry.PSObject.Properties['objective_id']) { [string]$entry.objective_id } else { '' }
            if (-not $statusCache.ContainsKey($entryObjectiveId)) {
                if ($ProjectStatusOverrides -and $ProjectStatusOverrides.ContainsKey($entryObjectiveId)) {
                    $statusCache[$entryObjectiveId] = $ProjectStatusOverrides[$entryObjectiveId]
                }
                else {
                    $statusCache[$entryObjectiveId] = if ([string]::IsNullOrWhiteSpace($entryObjectiveId)) { Get-ProjectStatusPayload -ValidationHarness $ValidationHarness } else { Get-ProjectStatusPayload -ObjectiveId $entryObjectiveId -ValidationHarness $ValidationHarness }
                }
            }
            $lifecycle = Resolve-OperatorChatCommitmentLifecycle -Entry $entry -ProjectStatus $statusCache[$entryObjectiveId]
        }
        catch {
            $fallbackState = if ($entry -and $entry.PSObject.Properties['state']) { ([string]$entry.state).Trim().ToLowerInvariant() } else { '' }
            $fallbackRelease = if ($entry -and $entry.PSObject.Properties['release_condition']) { [string]$entry.release_condition } else { '' }
            if ([string]::IsNullOrWhiteSpace($fallbackRelease)) {
                $fallbackRelease = switch ($fallbackState) {
                    'timeboxed' { 'timebox' }
                    'until_evidence_change' { 'evidence_change' }
                    'satisfied' { 'completed' }
                    'abandoned' { 'operator_abandoned' }
                    default { 'manual_clear' }
                }
            }
            $lifecycle = [pscustomobject]@{
                active = @('committed', 'timeboxed', 'until_evidence_change') -contains $fallbackState
                lifecycle_status = if (@('cleared', 'satisfied', 'abandoned') -contains $fallbackState) { $fallbackState } else { 'active' }
                release_condition = $fallbackRelease
                expires_at = if ($entry -and $entry.PSObject.Properties['expires_at']) { [string]$entry.expires_at } else { '' }
                expires_in_minutes = $null
                revalidation_required = $false
                is_terminal = @('satisfied', 'abandoned') -contains $fallbackState
                terminal_state = if (@('satisfied', 'abandoned') -contains $fallbackState) { $fallbackState } else { '' }
                terminal_detail = if (@('satisfied', 'abandoned') -contains $fallbackState) { 'Commitment lifecycle fell back to static evaluation after an operator terminal outcome was recorded.' } else { '' }
                detail = 'Commitment lifecycle fell back to static evaluation because dynamic evaluation failed.'
                escalation_reason = ''
                baseline_evidence_fingerprint = if ($entry -and $entry.PSObject.Properties['evidence_fingerprint']) { [string]$entry.evidence_fingerprint } else { '' }
                current_evidence_fingerprint = ''
                baseline_evidence_snapshot = if ($entry -and $entry.PSObject.Properties['evidence_snapshot']) { $entry.evidence_snapshot } else { $null }
                current_evidence_snapshot = $null
                evidence_delta_count = 0
                evidence_deltas = @()
            }
        }
        $merged = [ordered]@{}
        foreach ($property in $entry.PSObject.Properties) {
            $merged[$property.Name] = $property.Value
        }
        $merged['active'] = [bool]$lifecycle.active
        $merged['lifecycle_status'] = [string]$lifecycle.lifecycle_status
        $merged['release_condition'] = [string]$lifecycle.release_condition
        $merged['expires_at'] = [string]$lifecycle.expires_at
        $merged['expires_in_minutes'] = $lifecycle.expires_in_minutes
        $merged['revalidation_required'] = [bool]$lifecycle.revalidation_required
        $merged['is_terminal'] = [bool]$lifecycle.is_terminal
        $merged['terminal_state'] = [string]$lifecycle.terminal_state
        $merged['terminal_detail'] = [string]$lifecycle.terminal_detail
        $merged['terminal_successor_commitment_id'] = ''
        $merged['lifecycle_detail'] = [string]$lifecycle.detail
        $merged['escalation_reason'] = [string]$lifecycle.escalation_reason
        $merged['baseline_evidence_fingerprint'] = [string]$lifecycle.baseline_evidence_fingerprint
        $merged['current_evidence_fingerprint'] = [string]$lifecycle.current_evidence_fingerprint
        $merged['baseline_evidence_snapshot'] = $lifecycle.baseline_evidence_snapshot
        $merged['current_evidence_snapshot'] = $lifecycle.current_evidence_snapshot
        $merged['evidence_delta_count'] = [int]$lifecycle.evidence_delta_count
        $merged['evidence_deltas'] = @($lifecycle.evidence_deltas)
        $merged['lifecycle_evaluator'] = if ([string]::Equals([string]$lifecycle.release_condition, 'evidence_change', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($lifecycle.current_evidence_snapshot) { 'dynamic_compare' } else { 'fallback_static' }
        }
        else {
            'static_evaluation'
        }
        try {
            $historyKey = '{0}|{1}|{2}' -f [string]$entryObjectiveId, [string]$entry.action, [string]$entry.intent
            if (-not $historyCache.ContainsKey($historyKey)) {
                $historyCache[$historyKey] = Get-OperatorChatCommitmentHistoryProfile -ObjectiveId $entryObjectiveId -Action ([string]$entry.action) -Intent ([string]$entry.intent)
            }
            $merged['terminal_history'] = $historyCache[$historyKey]
        }
        catch {
            Write-UiCrashLogDeduped -Key 'COMMITMENT-HISTORY-FALLBACK' -Message ('[COMMITMENT-HISTORY-FALLBACK] ' + $_.Exception.Message)
            $merged['terminal_history'] = [pscustomobject]@{
                objective_id = [string]$entryObjectiveId
                action = [string]$entry.action
                terminal_count = 0
                satisfied_count = 0
                abandoned_count = 0
                recent_terminal_state = ''
                recent_terminal_at = ''
                summary = 'Commitment history unavailable; using static fallback.'
                outcome_bias = 'neutral'
                recent_fitness_score = 0
                ineffective_signal = $false
                ineffective_basis = ''
                same_intent_terminal_count = 0
                same_intent_satisfied_count = 0
                same_intent_abandoned_count = 0
                same_intent_summary = ''
            }
        }
        try {
            if ([string]::Equals([string]$merged['release_condition'], 'evidence_change', [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not $comparisonInfoCache.ContainsKey($entryObjectiveId)) {
                    $comparisonInfoCache[$entryObjectiveId] = Get-OperatorChatComparisonObjectiveInfo -ObjectiveId $entryObjectiveId -AllowValidationFallback -ValidationHarness $ValidationHarness
                }
                $comparisonInfo = $comparisonInfoCache[$entryObjectiveId]
                $merged['trust_chain_provenance_ready'] = [bool]$comparisonInfo.ready
                $merged['trust_chain_provenance_source'] = [string]$comparisonInfo.source
                $merged['trust_chain_provenance_label'] = [string]$comparisonInfo.label
                $merged['trust_chain_compare_objective_id'] = [string]$comparisonInfo.objective_id
                $merged['trust_chain_validation_mode'] = [string]$comparisonInfo.validation_mode
                $merged['trust_chain_provenance_summary'] = [string]$comparisonInfo.summary
            }
            else {
                $merged['trust_chain_provenance_ready'] = $false
                $merged['trust_chain_provenance_source'] = ''
                $merged['trust_chain_provenance_label'] = ''
                $merged['trust_chain_compare_objective_id'] = ''
                $merged['trust_chain_validation_mode'] = ''
                $merged['trust_chain_provenance_summary'] = ''
            }
        }
        catch {
            Write-UiCrashLog ('[COMMITMENT-PROVENANCE-FALLBACK] ' + $_.Exception.Message)
            $merged['trust_chain_provenance_ready'] = $false
            $merged['trust_chain_provenance_source'] = ''
            $merged['trust_chain_provenance_label'] = ''
            $merged['trust_chain_compare_objective_id'] = ''
            $merged['trust_chain_validation_mode'] = ''
            $merged['trust_chain_provenance_summary'] = ''
        }
        try {
            $scope = Resolve-OperatorChatCommitmentScope -Entry $entry -ProjectStatus $statusCache[$entryObjectiveId] -ValidationHarness $ValidationHarness
            $merged['scope_in_scope'] = [bool]$scope.in_scope
            $merged['scope_status'] = [string]$scope.status
            $merged['scope_summary'] = [string]$scope.summary
            $merged['scope_kind'] = [string]$scope.scope_kind
            $merged['current_scope_kind'] = [string]$scope.current_scope_kind
            $merged['scope_overlap_status'] = [string]$scope.overlap_status
            $merged['scope_conflict_reason'] = [string]$scope.conflict_reason
            $merged['scope_conflict_resolution'] = [string]$scope.conflict_resolution
            $merged['scope_blocks_activation'] = [bool]$scope.blocks_activation
            $merged['scope_precedence_rank'] = [int]$scope.precedence_rank
            $merged['scope_influence_summary'] = [string]$scope.influence_summary
            $merged['current_scope_selected_objective_id'] = if ($scope.current_scope) { [string]$scope.current_scope.selected_objective_id } else { '' }
            $merged['current_scope_validation_harness'] = if ($scope.current_scope) { [string]$scope.current_scope.validation_harness } else { '' }
            $merged['current_scope_kind'] = if ($scope.current_scope) { [string]$scope.current_scope.scope_kind } else { [string]$scope.current_scope_kind }
            $merged['current_scope_proposal_id'] = if ($scope.current_scope) { [string]$scope.current_scope.proposal_id } else { '' }
            $merged['current_scope_proposal_objective_id'] = if ($scope.current_scope) { [string]$scope.current_scope.proposal_objective_id } else { '' }
        }
        catch {
            Write-UiCrashLog ('[COMMITMENT-SCOPE-FALLBACK] ' + $_.Exception.Message)
            $currentScope = if ($statusCache.ContainsKey($entryObjectiveId)) { Get-OperatorChatCommitmentScopeSnapshot -ProjectStatus $statusCache[$entryObjectiveId] -ValidationHarness $ValidationHarness } else { $null }
            $scopeKind = if ($entry.PSObject.Properties['scope_kind']) { [string]$entry.scope_kind } else { 'objective_wide' }
            $currentScopeKind = if ($currentScope -and $currentScope.PSObject.Properties['scope_kind']) { [string]$currentScope.scope_kind } else { $scopeKind }
            $isProposalSpecific = [string]::Equals($scopeKind, 'proposal_specific', [System.StringComparison]::OrdinalIgnoreCase)
            $merged['scope_in_scope'] = $true
            $merged['scope_status'] = if ($isProposalSpecific) { 'proposal_nested_match' } else { 'in_scope' }
            $merged['scope_summary'] = if ($isProposalSpecific) { 'Commitment remains in exact proposal-specific scope under the current objective and proposal posture.' } else { 'Commitment remains objective-wide and in scope for the current objective.' }
            $merged['scope_kind'] = $scopeKind
            $merged['current_scope_kind'] = $currentScopeKind
            $merged['scope_overlap_status'] = 'exact'
            $merged['scope_conflict_reason'] = ''
            $merged['scope_conflict_resolution'] = 'active'
            $merged['scope_blocks_activation'] = $false
            $merged['scope_precedence_rank'] = if ($isProposalSpecific) { 3 } else { 2 }
            $merged['scope_influence_summary'] = if ($isProposalSpecific) { 'Proposal-specific commitment takes highest precedence for active arbitration and recommit decisions because it matches the live proposal identity.' } else { 'Objective-wide commitment can steer active arbitration because no narrower live proposal-specific scope currently outranks it.' }
            $merged['current_scope_selected_objective_id'] = if ($currentScope) { [string]$currentScope.selected_objective_id } else { [string]$entryObjectiveId }
            $merged['current_scope_validation_harness'] = if ($currentScope) { [string]$currentScope.validation_harness } else { '' }
            $merged['current_scope_kind'] = $currentScopeKind
            $merged['current_scope_proposal_id'] = if ($currentScope) { [string]$currentScope.proposal_id } else { if ($entry.PSObject.Properties['scope_proposal_id']) { [string]$entry.scope_proposal_id } else { '' } }
            $merged['current_scope_proposal_objective_id'] = if ($currentScope) { [string]$currentScope.proposal_objective_id } else { if ($entry.PSObject.Properties['scope_proposal_objective_id']) { [string]$entry.scope_proposal_objective_id } else { '' } }
        }
        [void]$evaluatedEntries.Add([pscustomobject]$merged)
    }

    try {
        $evaluatedArray = Repair-OperatorChatEvidenceLifecycleEntries -Entries @($evaluatedEntries.ToArray()) -ProjectStatusOverrides $ProjectStatusOverrides -ValidationHarness $ValidationHarness
    }
    catch {
        $evaluatedArray = @($evaluatedEntries.ToArray())
    }
    try {
        $evaluatedArray = Repair-OperatorChatHarnessComparisonEntries -Entries $evaluatedArray -ValidationHarness $ValidationHarness
    }
    catch {
        Write-UiCrashLog ('[HARNESS-COMPARE-POSTPASS] ' + $_.Exception.Message)
    }
    try {
        $evaluatedArray = Resolve-OperatorChatCommitmentTerminalProjection -Entries $evaluatedArray
    }
    catch {
        Write-UiCrashLog ('[COMMITMENT-TERMINAL-PROJECTION] ' + $_.Exception.Message)
    }
    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        count = $evaluatedEntries.Count
        latest_path = $operatorChatCommitmentLatestPath
        log_path = $operatorChatCommitmentLogPath
        filters = [pscustomobject]@{
            commitment_id = [string]$CommitmentId
            preview_id = [string]$PreviewId
            reasoning_bundle_id = [string]$ReasoningBundleId
            objective_id = [string]$ObjectiveId
            state = [string]$State
            limit = $safeLimit
        }
        entries = $evaluatedArray
    }
}

function Get-OperatorChatLatestCommitment {
    param(
        [string]$ObjectiveId = '',
        $ProjectStatus = $null,
        [string]$ValidationHarness = '',
        [switch]$IncludeInactive
    )

    $projectStatusOverrides = $null
    if ($ProjectStatus -and -not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
        $projectStatusOverrides = @{ ([string]$ObjectiveId) = $ProjectStatus }
    }
    $payload = Get-OperatorChatCommitmentPayload -Limit 8 -ObjectiveId $ObjectiveId -ProjectStatusOverrides $projectStatusOverrides -ValidationHarness $ValidationHarness -SkipLifecycleEvaluation
    $entries = @($payload.entries)
    if (@($entries).Count -eq 0) {
        return $null
    }

    $closedActions = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $bestActiveEntry = $null
    $bestActiveRank = -1
    $bestTerminalEntry = $null
    $fallbackEntry = $null
    foreach ($entry in $entries) {
        if ($null -eq $entry) {
            continue
        }
        $actionKey = [string]$entry.action
        if ([string]::IsNullOrWhiteSpace($actionKey)) {
            continue
        }
        $state = if ($entry.PSObject.Properties['state']) { [string]$entry.state } else { '' }
        $lifecycleStatus = if ($entry.PSObject.Properties['lifecycle_status']) { [string]$entry.lifecycle_status } else { '' }
        $isTerminal = if ($entry.PSObject.Properties['is_terminal']) { [bool]$entry.is_terminal } else { @('satisfied', 'abandoned', 'superseded', 'ineffective') -contains $lifecycleStatus }
        if ([string]::Equals($state, 'cleared', [System.StringComparison]::OrdinalIgnoreCase) -or $isTerminal) {
            if ($isTerminal -and $null -eq $bestTerminalEntry) {
                $bestTerminalEntry = $entry
            }
            [void]$closedActions.Add($actionKey)
            continue
        }
        if ($closedActions.Contains($actionKey)) {
            continue
        }
        $entryInScope = if ($entry.PSObject.Properties['scope_in_scope']) { [bool]$entry.scope_in_scope } else { $true }
        $blocksActivation = if ($entry.PSObject.Properties['scope_blocks_activation']) { [bool]$entry.scope_blocks_activation } else { (-not $entryInScope) }
        $precedenceRank = if ($entry.PSObject.Properties['scope_precedence_rank']) { [int]$entry.scope_precedence_rank } else { if ($entryInScope) { 1 } else { 0 } }
        if ([bool]$entry.active -and $entryInScope -and -not $blocksActivation) {
            if ($precedenceRank -gt $bestActiveRank) {
                $bestActiveEntry = $entry
                $bestActiveRank = $precedenceRank
            }
            continue
        }
        if ($IncludeInactive -and $null -eq $fallbackEntry -and ((@('expired', 'evidence_changed') -contains [string]$entry.lifecycle_status) -or (-not $entryInScope) -or $blocksActivation)) {
            $fallbackEntry = $entry
        }
    }

    if ($bestActiveEntry) {
        return $bestActiveEntry
    }

    if ($IncludeInactive -and $bestTerminalEntry) {
        return $bestTerminalEntry
    }

    if ($IncludeInactive -and $fallbackEntry) {
        return $fallbackEntry
    }

    return $null
}

function Get-OperatorChatCommitmentForPreview {
    param([string]$PreviewId)

    if ([string]::IsNullOrWhiteSpace($PreviewId)) {
        return $null
    }

    $payload = Get-OperatorChatCommitmentPayload -Limit 20 -PreviewId $PreviewId
    foreach ($entry in @($payload.entries)) {
        if ($null -eq $entry) {
            continue
        }
        if ([string]::Equals([string]$entry.preview_id, [string]$PreviewId, [System.StringComparison]::OrdinalIgnoreCase) -and [bool]$entry.active) {
            return $entry
        }
    }

    return $null
}

function Get-OperatorChatTrustChainPayload {
    param(
        [string]$AuditId = '',
        [string]$PreviewId = '',
        [string]$BundleId = '',
        [string]$CommitmentId = '',
        [string]$ComparisonObjectiveId = '',
        [string]$ValidationMode = '',
        [string]$ValidationHarness = ''
    )

    $validationHarnessProfile = if (-not [string]::IsNullOrWhiteSpace($ValidationHarness)) { Get-OperatorChatValidationHarnessProfile -ValidationHarness $ValidationHarness } else { $null }

    $auditPayload = if (-not [string]::IsNullOrWhiteSpace($AuditId)) {
        Get-OperatorChatActionAuditPayload -Limit 1 -AuditId $AuditId
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PreviewId)) {
        Get-OperatorChatActionAuditPayload -Limit 8 -PreviewId $PreviewId
    }
    elseif (-not [string]::IsNullOrWhiteSpace($BundleId)) {
        Get-OperatorChatActionAuditPayload -Limit 8 -ReasoningBundleId $BundleId
    }
    else {
        Get-OperatorChatActionAuditPayload -Limit 1
    }

    $auditEntry = if (@($auditPayload.entries).Count -gt 0) { $auditPayload.entries[0] } else { $null }
    $resolvedBundleId = if (-not [string]::IsNullOrWhiteSpace($BundleId)) { [string]$BundleId } elseif ($auditEntry) { [string]$auditEntry.reasoning_bundle_id } else { '' }
    $resolvedPreviewId = if (-not [string]::IsNullOrWhiteSpace($PreviewId)) { [string]$PreviewId } elseif ($auditEntry) { [string]$auditEntry.preview_id } else { '' }

    $reasoningPayload = if ([string]::IsNullOrWhiteSpace($resolvedBundleId)) {
        [pscustomobject]@{ ok = $true; count = 0; entries = @() }
    }
    else {
        Get-OperatorChatReasoningPayload -Limit 1 -BundleId $resolvedBundleId
    }
    $reasoningEntry = if (@($reasoningPayload.entries).Count -gt 0) { $reasoningPayload.entries[0] } else { $null }

    $commitmentEntries = @()
    $comparisonStatus = $null
    $comparisonApplied = $false
    $comparisonSource = ''
    $comparisonLabel = ''
    $comparisonSummary = ''
    $validationAdjustedEntries = @()
    $autoComparisonInfo = $null
    if (-not [string]::IsNullOrWhiteSpace($ComparisonObjectiveId)) {
        try {
            $comparisonStatus = Get-ProjectStatusPayload -ObjectiveId ([string]$ComparisonObjectiveId) -ValidationHarness $ValidationHarness
        }
        catch {
            $comparisonStatus = $null
        }
        if ($comparisonStatus) {
            $comparisonSource = 'live_objective'
            $comparisonLabel = 'live compare'
            $comparisonSummary = 'Commitment evidence was re-evaluated against a bounded comparison objective posture.'
        }
    }

    $commitmentPayload = if (-not [string]::IsNullOrWhiteSpace($CommitmentId)) {
        $basePayload = Get-OperatorChatCommitmentPayload -Limit 6 -CommitmentId $CommitmentId -ValidationHarness $ValidationHarness
        $firstCommitment = if (@($basePayload.entries).Count -gt 0) { $basePayload.entries[0] } else { $null }
        if (-not $comparisonStatus -and [string]::IsNullOrWhiteSpace($ValidationMode) -and $firstCommitment) {
            $comparisonObjectiveKey = if ($firstCommitment.PSObject.Properties['objective_id']) { [string]$firstCommitment.objective_id } else { '' }
            $autoComparisonInfo = Get-OperatorChatComparisonObjectiveInfo -ObjectiveId $comparisonObjectiveKey -ValidationHarness $ValidationHarness
            if ($autoComparisonInfo -and $autoComparisonInfo.ready -and [string]::Equals([string]$autoComparisonInfo.source, 'live_objective', [System.StringComparison]::OrdinalIgnoreCase)) {
                $ComparisonObjectiveId = [string]$autoComparisonInfo.objective_id
                try {
                    $comparisonStatus = Get-ProjectStatusPayload -ObjectiveId $ComparisonObjectiveId -ValidationHarness $ValidationHarness
                }
                catch {
                    $comparisonStatus = $null
                }
                if ($comparisonStatus) {
                    $comparisonSource = 'live_objective'
                    $comparisonLabel = 'live compare'
                    $comparisonSummary = [string]$autoComparisonInfo.summary
                }
            }
        }
        if ($comparisonStatus -and $firstCommitment) {
            $comparisonObjectiveKey = if ($firstCommitment.PSObject.Properties['objective_id']) { [string]$firstCommitment.objective_id } else { '' }
            $comparisonOverrides = @{}
            $comparisonOverrides[$comparisonObjectiveKey] = $comparisonStatus
            $comparisonApplied = $true
            Get-OperatorChatCommitmentPayload -Limit 6 -CommitmentId $CommitmentId -ProjectStatusOverrides $comparisonOverrides -ValidationHarness $ValidationHarness
        }
        elseif (-not [string]::IsNullOrWhiteSpace($ValidationMode) -and $firstCommitment) {
            $adjustedEntries = Apply-OperatorChatValidationDriftToCommitmentEntries -Entries @($basePayload.entries) -DriftMode $ValidationMode
            if (@($adjustedEntries).Count -gt 0) {
                $comparisonApplied = $true
                $comparisonSource = 'validation_only'
                $comparisonLabel = 'validation only'
                $comparisonSummary = 'Commitment evidence was re-evaluated against an explicit validation-only synthetic drift posture.'
                $validationAdjustedEntries = @($adjustedEntries)
                $basePayload
            }
            else {
                $basePayload
            }
        }
        else {
            $basePayload
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($resolvedPreviewId)) {
        Get-OperatorChatCommitmentPayload -Limit 6 -PreviewId $resolvedPreviewId -ValidationHarness $ValidationHarness
    }
    elseif (-not [string]::IsNullOrWhiteSpace($resolvedBundleId)) {
        Get-OperatorChatCommitmentPayload -Limit 6 -ReasoningBundleId $resolvedBundleId -ValidationHarness $ValidationHarness
    }
    else {
        [pscustomobject]@{ ok = $true; count = 0; entries = @() }
    }
    $commitmentEntries = if (@($validationAdjustedEntries).Count -gt 0) { @($validationAdjustedEntries) } else { @($commitmentPayload.entries) }
    if (@($commitmentEntries).Count -gt 0) {
        try {
            $commitmentEntries = Repair-OperatorChatEvidenceLifecycleEntries -Entries $commitmentEntries -ValidationHarness $ValidationHarness
        }
        catch {
        }
        try {
            $commitmentEntries = Repair-OperatorChatHarnessComparisonEntries -Entries $commitmentEntries -ValidationHarness $ValidationHarness
        }
        catch {
            Write-UiCrashLog ('[HARNESS-COMPARE-TRUST] ' + $_.Exception.Message)
        }
    }
    $proposalClosure = $null
    if ($auditEntry -and $auditEntry.PSObject.Properties['proposal_closure_status'] -and -not [string]::IsNullOrWhiteSpace([string]$auditEntry.proposal_closure_status)) {
        $proposalClosure = [pscustomobject]@{
            available = $true
            status = [string]$auditEntry.proposal_closure_status
            disposition = if ($auditEntry.PSObject.Properties['proposal_closure_disposition']) { [string]$auditEntry.proposal_closure_disposition } else { '' }
            summary = if ($auditEntry.PSObject.Properties['proposal_closure_summary']) { [string]$auditEntry.proposal_closure_summary } else { '' }
        }
    }
    elseif (@($commitmentEntries).Count -gt 0 -and $commitmentEntries[0].PSObject.Properties['proposal_closure_status'] -and -not [string]::IsNullOrWhiteSpace([string]$commitmentEntries[0].proposal_closure_status)) {
        $proposalClosure = [pscustomobject]@{
            available = $true
            status = [string]$commitmentEntries[0].proposal_closure_status
            disposition = if ($commitmentEntries[0].PSObject.Properties['proposal_closure_disposition']) { [string]$commitmentEntries[0].proposal_closure_disposition } else { '' }
            summary = if ($commitmentEntries[0].PSObject.Properties['proposal_closure_summary']) { [string]$commitmentEntries[0].proposal_closure_summary } else { '' }
        }
    }
    try {
        $trustObjectiveId = if ($auditEntry -and $auditEntry.PSObject.Properties['objective_id']) { [string]$auditEntry.objective_id } elseif (@($commitmentEntries).Count -gt 0 -and $commitmentEntries[0].PSObject.Properties['objective_id']) { [string]$commitmentEntries[0].objective_id } else { '' }
        $trustProjectStatus = if ([string]::IsNullOrWhiteSpace($trustObjectiveId)) { Get-ProjectStatusPayload -ValidationHarness $ValidationHarness } else { Get-ProjectStatusPayload -ObjectiveId $trustObjectiveId -ValidationHarness $ValidationHarness }
        if ($null -eq $proposalClosure -and $trustProjectStatus -and $trustProjectStatus.PSObject.Properties['mim_proposal_closure']) {
            $proposalClosure = $trustProjectStatus.mim_proposal_closure
        }
    }
    catch {
        $proposalClosure = $null
    }
    $activeCommitment = @($commitmentEntries | Where-Object { [bool]$_.active } | Select-Object -First 1)
    $hasEvidenceDeltas = @($commitmentEntries | Where-Object { [int]$_.evidence_delta_count -gt 0 }).Count -gt 0
    $chainStatus = if ($auditEntry -and $reasoningEntry -and [int](@($reasoningEntry.evidence).Count) -gt 0) { 'complete' } elseif ($auditEntry -or $reasoningEntry) { 'partial' } else { 'missing' }
    $summary = switch ($chainStatus) {
        'complete' {
            if ($hasEvidenceDeltas) {
                'Audit, reasoning, linked evidence, and commitment evidence deltas are available for this governed action.'
            }
            else {
                'Audit, reasoning, and linked evidence are available for this governed action.'
            }
        }
        'partial' { 'Trust chain is partial; at least one of audit, reasoning, or evidence is missing.' }
        default { 'Trust chain could not be resolved from the provided identifiers.' }
    }

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        chain_status = $chainStatus
        summary = $summary
        identifiers = [pscustomobject]@{
            audit_id = if ($auditEntry) { [string]$auditEntry.audit_id } else { [string]$AuditId }
            preview_id = $resolvedPreviewId
            reasoning_bundle_id = $resolvedBundleId
            commitment_id = if ($activeCommitment) { [string]$activeCommitment.commitment_id } elseif (-not [string]::IsNullOrWhiteSpace($CommitmentId)) { [string]$CommitmentId } else { '' }
            comparison_objective_id = [string]$ComparisonObjectiveId
            validation_mode = [string]$ValidationMode
        }
        audit = $auditEntry
        reasoning_bundle = $reasoningEntry
        commitments = @($commitmentEntries)
        evidence_count = if ($reasoningEntry) { [int](@($reasoningEntry.evidence).Count) } else { 0 }
        citation_count = if ($reasoningEntry) { [int](@($reasoningEntry.citations).Count) } else { 0 }
        comparison = [pscustomobject]@{
            applied = [bool]$comparisonApplied
            source = $comparisonSource
            label = $comparisonLabel
            objective_id = [string]$ComparisonObjectiveId
            validation_mode = [string]$ValidationMode
            validation_harness = [string]$ValidationHarness
            validation_harness_label = if ($validationHarnessProfile) { [string]$validationHarnessProfile.label } else { '' }
            summary = if ($comparisonApplied) { $comparisonSummary } elseif (-not [string]::IsNullOrWhiteSpace($ComparisonObjectiveId)) { 'Comparison objective was requested but could not be applied.' } elseif (-not [string]::IsNullOrWhiteSpace($ValidationMode)) { 'Validation drift was requested but could not be applied.' } else { '' }
        }
        proposal_closure = $proposalClosure
        evidence_delta_count = [int](@($commitmentEntries | ForEach-Object { if ($_.PSObject.Properties['evidence_delta_count']) { [int]$_.evidence_delta_count } else { 0 } } | Measure-Object -Sum).Sum)
    }
}

function Invoke-OperatorChatFeedbackRequest {
    param(
        [string]$Action,
        [string]$Intent,
        [string]$ObjectiveId,
        [string]$Polarity,
        [string]$Actor,
        [string]$Query,
        [string]$Note = ''
    )

    $normalizedPolarity = ([string]$Polarity).Trim().ToLowerInvariant()
    if (@('positive', 'negative') -notcontains $normalizedPolarity) {
        throw 'Feedback polarity must be positive or negative.'
    }
    if ([string]::IsNullOrWhiteSpace($Action)) {
        throw 'Feedback action is required.'
    }

    $entry = [pscustomobject]@{
        feedback_id = [guid]::NewGuid().ToString()
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        actor = if ([string]::IsNullOrWhiteSpace($Actor)) { 'operator' } else { [string]$Actor }
        action = [string]$Action
        intent = [string]$Intent
        objective_id = [string]$ObjectiveId
        polarity = $normalizedPolarity
        query = [string]$Query
        note = [string]$Note
    }
    $savedEntry = Write-OperatorChatFeedbackEntry -Entry $entry
    try {
        $feedbackProfile = Get-OperatorChatActionFeedbackProfile -ObjectiveId ([string]$ObjectiveId) -Action ([string]$Action) -Intent ([string]$Intent)
    }
    catch {
        Write-UiCrashLog ("[OPERATOR-CHAT-FEEDBACK-FALLBACK] " + $_.Exception.ToString())
        $feedbackProfile = [pscustomobject]@{
            objective_id = [string]$ObjectiveId
            action = [string]$Action
            positive_count = if ([string]::Equals($normalizedPolarity, 'positive', [System.StringComparison]::OrdinalIgnoreCase)) { 1 } else { 0 }
            negative_count = if ([string]::Equals($normalizedPolarity, 'negative', [System.StringComparison]::OrdinalIgnoreCase)) { 1 } else { 0 }
            same_intent_positive_count = if ([string]::Equals($normalizedPolarity, 'positive', [System.StringComparison]::OrdinalIgnoreCase)) { 1 } else { 0 }
            same_intent_negative_count = if ([string]::Equals($normalizedPolarity, 'negative', [System.StringComparison]::OrdinalIgnoreCase)) { 1 } else { 0 }
            score = if ([string]::Equals($normalizedPolarity, 'positive', [System.StringComparison]::OrdinalIgnoreCase)) { 2 } else { -3 }
            summary = 'Feedback aggregate fell back to the current submission because historical feedback aggregation was unavailable.'
            same_intent_summary = 'Feedback aggregate fell back to the current submission because historical feedback aggregation was unavailable.'
        }
    }
    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        summary = if ([string]::Equals($normalizedPolarity, 'positive', [System.StringComparison]::OrdinalIgnoreCase)) { 'Positive operator feedback recorded for the suggested action.' } else { 'Negative operator feedback recorded for the suggested action.' }
        feedback = $savedEntry
        aggregate = $feedbackProfile
    }
}

function New-OperatorChatReasoningBundle {
    param(
        [string]$ReasoningBundleId,
        [string]$Phase,
        [string]$Action,
        [string]$Intent,
        [string]$ObjectiveId,
        [string]$Query,
        [string]$Actor,
        [string]$PreviewId,
        [string]$ConfirmationReason,
        $Policy,
        $OperatorResponse
    )

    $bundleId = if ([string]::IsNullOrWhiteSpace($ReasoningBundleId)) { [guid]::NewGuid().ToString() } else { [string]$ReasoningBundleId }
    $response = if ($OperatorResponse) { $OperatorResponse.response } else { $null }
    return [pscustomobject]@{
        reasoning_bundle_id = $bundleId
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-operator-chat-governed-reasoning-v1'
        phase = [string]$Phase
        actor = [string]$Actor
        preview_id = [string]$PreviewId
        action = [string]$Action
        action_label = if ($Policy) { [string]$Policy.label } else { [string]$Action }
        action_mode = if ($Policy) { [string]$Policy.mode } else { '' }
        intent = [string]$Intent
        objective_id = [string]$ObjectiveId
        query = [string]$Query
        allowed = if ($Policy) { [bool]$Policy.allowed } else { $false }
        confirmation_required = if ($Policy) { [bool]$Policy.confirmation_required } else { $true }
        allow_reason = if ($Policy) { [string]$Policy.allow_reason } else { '' }
        blocked_reason = if ($Policy) { [string]$Policy.blocked_reason } else { '' }
        suggested_reason = if ($Policy) { [string]$Policy.suggested_reason } else { '' }
        remediation = if ($Policy) { [string]$Policy.remediation } else { '' }
        expected_impact = if ($Policy) { [string]$Policy.expected_impact } else { '' }
        confirmation_reason = [string]$ConfirmationReason
        operator_summary = if ($response) { [string]$response.summary } else { '' }
        recommended_next_step = if ($response) { [string]$response.recommended_next_step } else { '' }
        evidence = if ($response) { @($response.evidence) } else { @() }
        evidence_count = if ($response) { [int](@($response.evidence).Count) } else { 0 }
        citations = if ($response) { @($response.citations) } else { @() }
        evidence_flags = if ($response) { @($response.flags) } else { @() }
        limitations = if ($response) { @($response.limitations) } else { @() }
        alternative_actions = if ($Policy) { @($Policy.alternative_actions) } else { @() }
    }
}

function Invoke-OperatorChatCommitmentRequest {
    param(
        [string]$PreviewId,
        [string]$OperatorId,
        [string]$ObjectiveId,
        [string]$State = 'committed',
        [int]$DurationMinutes = 15,
        [string]$ValidationHarness = ''
    )

    $actor = if ([string]::IsNullOrWhiteSpace($OperatorId)) { 'local-operator' } else { [string]$OperatorId }
    $normalizedState = if ([string]::IsNullOrWhiteSpace($State)) { 'committed' } else { ([string]$State).Trim().ToLowerInvariant() }
    if (@('committed', 'timeboxed', 'until_evidence_change', 'cleared', 'satisfied', 'abandoned') -notcontains $normalizedState) {
        throw "Unsupported commitment state: $normalizedState"
    }

    $previewEntry = $null
    if (-not [string]::IsNullOrWhiteSpace($PreviewId) -and $operatorChatActionPreviewRegistry.ContainsKey([string]$PreviewId)) {
        $previewEntry = $operatorChatActionPreviewRegistry[[string]$PreviewId]
    }

    if ($null -eq $previewEntry -and -not [string]::IsNullOrWhiteSpace($PreviewId)) {
        $existingCommitmentPayload = Get-OperatorChatCommitmentPayload -Limit 6 -PreviewId $PreviewId -ValidationHarness $ValidationHarness
        $existingCommitment = @($existingCommitmentPayload.entries | Where-Object { -not [string]::Equals([string]$_.state, 'cleared', [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (-not $existingCommitment) {
            $existingCommitment = @($existingCommitmentPayload.entries | Select-Object -First 1)
        }
        if ($existingCommitment) {
            $previewEntry = [pscustomobject]@{
                preview_id = [string]$existingCommitment.preview_id
                reasoning_bundle_id = [string]$existingCommitment.reasoning_bundle_id
                objective_id = [string]$existingCommitment.objective_id
                intent = [string]$existingCommitment.intent
                query = [string]$existingCommitment.query
                action = [string]$existingCommitment.action
                label = [string]$existingCommitment.action_label
                mode = [string]$existingCommitment.action_mode
                suggested_reason = [string]$existingCommitment.suggested_reason
                proposal_source = if ($existingCommitment.PSObject.Properties['proposal_source']) { [string]$existingCommitment.proposal_source } else { '' }
                proposal_id = if ($existingCommitment.PSObject.Properties['proposal_id']) { [string]$existingCommitment.proposal_id } else { '' }
                proposal_objective_id = if ($existingCommitment.PSObject.Properties['proposal_objective_id']) { [string]$existingCommitment.proposal_objective_id } else { '' }
                proposal_title = if ($existingCommitment.PSObject.Properties['proposal_title']) { [string]$existingCommitment.proposal_title } else { '' }
                proposal_acknowledgment_disposition = if ($existingCommitment.PSObject.Properties['proposal_acknowledgment_disposition']) { [string]$existingCommitment.proposal_acknowledgment_disposition } else { '' }
            }
        }
    }

    if ($null -eq $previewEntry) {
        throw 'Preview ID was not found or expired. Request a new governed action preview before committing.'
    }

    $bundlePayload = Get-OperatorChatReasoningPayload -Limit 1 -BundleId ([string]$previewEntry.reasoning_bundle_id)
    $bundleEntry = if (@($bundlePayload.entries).Count -gt 0) { $bundlePayload.entries[0] } else { $null }
    $resolvedObjectiveId = if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) { [string]$ObjectiveId } else { [string]$previewEntry.objective_id }
    $projectStatus = if ([string]::IsNullOrWhiteSpace($resolvedObjectiveId)) { Get-ProjectStatusPayload -ValidationHarness $ValidationHarness } else { Get-ProjectStatusPayload -ObjectiveId $resolvedObjectiveId -ValidationHarness $ValidationHarness }
    $evidenceFingerprint = Get-OperatorChatCommitmentEvidenceFingerprint -ProjectStatus $projectStatus
    $evidenceSnapshot = Get-OperatorChatCommitmentEvidenceSnapshot -ProjectStatus $projectStatus
    $scopeSnapshot = Get-OperatorChatCommitmentScopeSnapshot -ProjectStatus $projectStatus -ValidationHarness $ValidationHarness
    $safeDurationMinutes = if ($DurationMinutes -lt 5) { 5 } elseif ($DurationMinutes -gt 120) { 120 } else { $DurationMinutes }
    $releaseCondition = switch ($normalizedState) {
        'timeboxed' { 'timebox' }
        'until_evidence_change' { 'evidence_change' }
        'satisfied' { 'completed' }
        'abandoned' { 'operator_abandoned' }
        default { 'manual_clear' }
    }
    $expiresAt = if ([string]::Equals($normalizedState, 'timeboxed', [System.StringComparison]::OrdinalIgnoreCase)) { (Get-Date).ToUniversalTime().AddMinutes($safeDurationMinutes).ToString('o') } else { '' }
    $summary = switch ($normalizedState) {
        'committed' { "Operator committed to $([string]$previewEntry.label) before execution." }
        'timeboxed' { "Operator committed to $([string]$previewEntry.label) for the next $safeDurationMinutes minutes before execution." }
        'until_evidence_change' { "Operator committed to $([string]$previewEntry.label) until the current evidence posture changes materially." }
        'satisfied' { "Operator marked the commitment for $([string]$previewEntry.label) as satisfied." }
        'abandoned' { "Operator abandoned the commitment for $([string]$previewEntry.label)." }
        default { "Operator cleared the active commitment for $([string]$previewEntry.label)." }
    }
    $entry = [pscustomobject]@{
        commitment_id = [guid]::NewGuid().ToString()
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        state = $normalizedState
        actor = $actor
        preview_id = [string]$previewEntry.preview_id
        reasoning_bundle_id = [string]$previewEntry.reasoning_bundle_id
        objective_id = $resolvedObjectiveId
        intent = [string]$previewEntry.intent
        query = [string]$previewEntry.query
        action = [string]$previewEntry.action
        action_label = [string]$previewEntry.label
        action_mode = [string]$previewEntry.mode
        suggested_reason = [string]$previewEntry.suggested_reason
        summary = $summary
        release_condition = $releaseCondition
        proposal_source = if ($previewEntry.PSObject.Properties['proposal_source']) { [string]$previewEntry.proposal_source } else { '' }
        proposal_id = if ($previewEntry.PSObject.Properties['proposal_id']) { [string]$previewEntry.proposal_id } else { '' }
        proposal_objective_id = if ($previewEntry.PSObject.Properties['proposal_objective_id']) { [string]$previewEntry.proposal_objective_id } else { '' }
        proposal_title = if ($previewEntry.PSObject.Properties['proposal_title']) { [string]$previewEntry.proposal_title } else { '' }
        proposal_acknowledgment_disposition = if ($previewEntry.PSObject.Properties['proposal_acknowledgment_disposition']) { [string]$previewEntry.proposal_acknowledgment_disposition } else { '' }
        proposal_closure_status = if ($previewEntry.PSObject.Properties['proposal_closure_status']) { [string]$previewEntry.proposal_closure_status } else { '' }
        proposal_closure_disposition = if ($previewEntry.PSObject.Properties['proposal_closure_disposition']) { [string]$previewEntry.proposal_closure_disposition } else { '' }
        proposal_closure_summary = if ($previewEntry.PSObject.Properties['proposal_closure_summary']) { [string]$previewEntry.proposal_closure_summary } else { '' }
        validation_harness = [string]$scopeSnapshot.validation_harness
        validation_harness_label = [string]$scopeSnapshot.validation_harness_label
        scope_kind = [string]$scopeSnapshot.scope_kind
        scope_selected_objective_id = [string]$scopeSnapshot.selected_objective_id
        scope_proposal_id = [string]$scopeSnapshot.proposal_id
        scope_proposal_objective_id = [string]$scopeSnapshot.proposal_objective_id
        scope_proposal_conflict_status = [string]$scopeSnapshot.proposal_conflict_status
        scope_proposal_arbitration_winner = [string]$scopeSnapshot.proposal_arbitration_winner
        scope_proposal_merge_policy_status = [string]$scopeSnapshot.proposal_merge_policy_status
        duration_minutes = if ([string]::Equals($normalizedState, 'timeboxed', [System.StringComparison]::OrdinalIgnoreCase)) { $safeDurationMinutes } else { $null }
        expires_at = $expiresAt
        evidence_fingerprint = $evidenceFingerprint
        evidence_snapshot = $evidenceSnapshot
        reasoning_summary = if ($bundleEntry) { [string]$bundleEntry.operator_summary } else { '' }
        evidence_citations = if ($bundleEntry) { @($bundleEntry.citations) } else { @() }
        evidence_flags = if ($bundleEntry) { @($bundleEntry.evidence_flags) } else { @() }
    }
    Write-OperatorChatCommitmentEntry -Entry $entry
    $payload = Get-OperatorChatCommitmentPayload -Limit 1 -CommitmentId ([string]$entry.commitment_id) -ValidationHarness $ValidationHarness
    $resolvedEntry = if (@($payload.entries).Count -gt 0) { $payload.entries[0] } else { $entry }
    return [pscustomobject]@{
        ok = $true
        summary = [string]$resolvedEntry.summary
        state = [string]$resolvedEntry.state
        commitment = $resolvedEntry
    }
}

function Get-OperatorChatGovernedActionPolicy {
    param(
        [string]$Action,
        [string]$Intent,
        [string]$SuggestedReason,
        [string]$Mode,
        $ProjectStatus
    )

    $normalizedAction = [string]$Action
    $label = $normalizedAction
    $expectedImpact = 'Run a bounded read-only operator action and return structured evidence.'
    $allowReason = ''
    $blockedReason = ''
    $remediation = ''
    $allowed = $false
    $confirmationRequired = $true

    switch ($normalizedAction) {
        'get-reliability' {
            $label = 'Get Reliability'
            $allowed = $true
            $allowReason = 'Reliability view is a read-only diagnostic path already exposed by the dashboard.'
            $expectedImpact = 'Refresh the reliability snapshot without mutating TOD state.'
        }
        'get-state-bus' {
            $label = 'Refresh State Bus'
            $allowed = $true
            $allowReason = 'State bus refresh is bounded to a read-only snapshot path.'
            $expectedImpact = 'Return the current shared state bus snapshot for operator review.'
        }
        'get-engineering-loop-summary' {
            $label = 'Engineering Loop Summary'
            $allowed = $true
            $allowReason = 'Engineering loop summary is a read-only diagnostic view sourced from the lightweight state bus.'
            $expectedImpact = 'Refresh the engineering loop summary so the operator can inspect score, maturity, thresholds, and penalties without mutating TOD state.'
        }
        'get-engineering-signal' {
            $label = 'Engineering Signal'
            $allowed = $true
            $allowReason = 'Engineering signal is a read-only diagnostic view already exposed through the dashboard and lightweight state bus.'
            $expectedImpact = 'Refresh the current engineering signal so the operator can inspect trend, maturity, and approval pressure without mutating TOD state.'
        }
        'show-reliability-dashboard' {
            $label = 'Reliability Dashboard'
            $allowed = $true
            $allowReason = 'Reliability dashboard is a read-only diagnostic surface with no side effects.'
            $expectedImpact = 'Return the reliability dashboard payload for operator review.'
        }
        'refresh-share-links' {
            $label = 'Refresh Share Links'
            $allowed = $true
            $allowReason = 'Share artifact refresh only re-reads configured artifact metadata.'
            $expectedImpact = 'Refresh the shared artifact availability snapshot and link metadata.'
        }
        'quick-refresh-reliability' {
            $label = 'Quick Refresh Reliability'
            $allowed = $true
            $allowReason = 'Quick refresh is implemented as a bounded read-only composite over status, artifacts, and reliability views.'
            $expectedImpact = 'Refresh the main operator reliability-facing snapshot bundle without executing TOD work.'
        }
        'refresh-project-status' {
            $label = 'Refresh Status Snapshot'
            $allowed = $true
            $allowReason = 'Project status snapshot is a read-only view already served by the dashboard.'
            $expectedImpact = 'Re-read the current project status payload for the scoped objective.'
        }
        'recheck-bridge-diagnostics' {
            $label = 'Re-check Bridge Diagnostics'
            $allowed = $true
            $allowReason = 'Bridge re-check reuses the existing read-only bridge explanation path.'
            $expectedImpact = 'Recompute the bridge explanation and return fresh alignment evidence.'
        }
        'refresh-governance-snapshot' {
            $label = 'Refresh Governance Snapshot'
            $allowed = $true
            $allowReason = 'Governance snapshot is a bounded composite over existing read-only status, artifact, and state-bus views.'
            $expectedImpact = 'Refresh a single governance-oriented evidence bundle for objective, cadence, bridge, maintenance, and artifact posture.'
        }
        'refresh-bridge-alignment-bundle' {
            $label = 'Refresh Bridge Alignment Bundle'
            $allowed = $true
            $allowReason = 'Bridge alignment bundle reuses the existing bridge explanation, state-bus snapshot, and artifact refresh paths without mutating TOD state.'
            $expectedImpact = 'Refresh bridge alignment evidence, state-bus posture, and share artifacts in one bounded operator step.'
        }
        'wait' {
            $label = 'No Action Needed'
            $blockedReason = 'This recommendation is observe-only. There is nothing to execute.'
            $remediation = 'Use one of the allowed read-only alternatives if you need fresher evidence, otherwise continue observing.'
        }
        default {
            $blockedReason = 'This action is outside the governed allowlist for Objective 86.'
            $remediation = 'Choose a governed read-only action from the suggested alternatives instead of constructing a new command.'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Mode) -and [string]::Equals([string]$Mode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)) {
        $allowed = $false
        $blockedReason = 'Observe-only recommendations must remain non-mutating and cannot enter the confirmation flow.'
        if ([string]::IsNullOrWhiteSpace($remediation)) {
            $remediation = 'Stay in observe mode unless one of the bounded alternatives is explicitly justified by the current evidence.'
        }
    }

    if ($allowed -and [string]::IsNullOrWhiteSpace($allowReason)) {
        $allowReason = 'This action is on the governed allowlist and uses an existing bounded control path.'
    }

    if (-not $allowed -and [string]::IsNullOrWhiteSpace($remediation)) {
        $remediation = 'Choose an allowed read-only action or continue observing the current state.'
    }

    $alternatives = @()
    if (-not $allowed) {
        $alternatives = Get-OperatorChatGovernedActionAlternatives -ProjectStatus $ProjectStatus -Intent $Intent -ExcludeAction $normalizedAction
    }

    return [pscustomobject]@{
        action = $normalizedAction
        label = $label
        allowed = $allowed
        confirmation_required = $confirmationRequired
        allow_reason = $allowReason
        blocked_reason = $blockedReason
        expected_impact = $expectedImpact
        suggested_reason = [string]$SuggestedReason
        remediation = [string]$remediation
        alternative_actions = @($alternatives)
        mode = [string]$Mode
        intent = [string]$Intent
    }
}

function Invoke-OperatorChatGovernedAction {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [string]$ObjectiveId,
        [string]$Intent,
        [string]$Query,
        [int]$WindowMinutes = 10,
        $ProjectStatus,
        [string]$ValidationHarness = ''
    )

    $resolvedObjectiveId = [string]$ObjectiveId
    $resolvedProjectStatus = if ($ProjectStatus) { $ProjectStatus } else { Get-ProjectStatusPayload -ObjectiveId $resolvedObjectiveId -ValidationHarness $ValidationHarness }

    switch ([string]$Action) {
        'get-reliability' {
            $payload = Invoke-LightweightUiAction -Action 'get-reliability'
            $alert = if ($payload -and $payload.PSObject.Properties['current_alert_state']) { [string]$payload.current_alert_state } else { 'unknown' }
            $drift = if ($payload -and $payload.PSObject.Properties['drift_warning_count']) { [string]$payload.drift_warning_count } else { '-' }
            return [pscustomobject]@{
                status = 'succeeded'
                summary = "Reliability snapshot refreshed. Alert state is $alert with drift warnings $drift."
                evidence = @(
                    (New-OperatorChatEvidence -Label 'Alert State' -Value $alert -Section 'recovery_watchdog' -Field 'state'),
                    (New-OperatorChatEvidence -Label 'Drift Warnings' -Value $drift -Section 'recovery_watchdog' -Field 'state')
                )
                result = $payload
            }
        }
        'get-state-bus' {
            $payload = Invoke-LightweightUiAction -Action 'get-state-bus'
            $mode = if ($payload -and $payload.PSObject.Properties['agent_state'] -and $payload.agent_state.PSObject.Properties['mode']) { [string]$payload.agent_state.mode } else { 'unknown' }
            $alert = if ($payload -and $payload.PSObject.Properties['reliability_state'] -and $payload.reliability_state.PSObject.Properties['current_alert_state']) { [string]$payload.reliability_state.current_alert_state } else { 'unknown' }
            return [pscustomobject]@{
                status = 'succeeded'
                summary = "State bus snapshot refreshed. Agent mode is $mode and alert state is $alert."
                evidence = @(
                    (New-OperatorChatEvidence -Label 'Agent Mode' -Value $mode -Section 'listener_activity' -Field 'summary'),
                    (New-OperatorChatEvidence -Label 'Alert State' -Value $alert -Section 'recovery_watchdog' -Field 'state')
                )
                result = $payload
            }
        }
        'get-engineering-loop-summary' {
            $payload = Invoke-LightweightUiAction -Action 'get-engineering-loop-summary'
            $status = if ($payload -and $payload.PSObject.Properties['current_engineering_loop_status']) { [string]$payload.current_engineering_loop_status } else { 'unknown' }
            $band = if ($payload -and $payload.PSObject.Properties['latest_maturity_band']) { [string]$payload.latest_maturity_band } else { 'unknown' }
            $trend = if ($payload -and $payload.PSObject.Properties['trend_direction']) { [string]$payload.trend_direction } else { 'unknown' }
            return [pscustomobject]@{
                status = 'succeeded'
                summary = "Engineering loop summary refreshed. Status is $status, maturity band is $band, and trend is $trend."
                evidence = @(
                    (New-OperatorChatEvidence -Label 'Loop Status' -Value $status -Section 'listener_activity' -Field 'summary'),
                    (New-OperatorChatEvidence -Label 'Maturity Band' -Value $band -Section 'listener_activity' -Field 'summary'),
                    (New-OperatorChatEvidence -Label 'Trend' -Value $trend -Section 'listener_activity' -Field 'summary')
                )
                result = $payload
            }
        }
        'get-engineering-signal' {
            $payload = Invoke-LightweightUiAction -Action 'get-engineering-signal'
            $status = if ($payload -and $payload.PSObject.Properties['current_engineering_loop_status']) { [string]$payload.current_engineering_loop_status } else { 'unknown' }
            $band = if ($payload -and $payload.PSObject.Properties['latest_maturity_band']) { [string]$payload.latest_maturity_band } else { 'unknown' }
            $pending = if ($payload -and $payload.PSObject.Properties['pending_approval_state'] -and $payload.pending_approval_state.PSObject.Properties['count']) { [string]$payload.pending_approval_state.count } else { '0' }
            return [pscustomobject]@{
                status = 'succeeded'
                summary = "Engineering signal refreshed. Loop status is $status, maturity band is $band, and pending approvals are $pending."
                evidence = @(
                    (New-OperatorChatEvidence -Label 'Loop Status' -Value $status -Section 'listener_activity' -Field 'summary'),
                    (New-OperatorChatEvidence -Label 'Maturity Band' -Value $band -Section 'listener_activity' -Field 'summary'),
                    (New-OperatorChatEvidence -Label 'Pending Approvals' -Value $pending -Section 'listener_activity' -Field 'summary')
                )
                result = $payload
            }
        }
        'show-reliability-dashboard' {
            $payload = Invoke-LightweightUiAction -Action 'show-reliability-dashboard'
            return [pscustomobject]@{
                status = 'succeeded'
                summary = 'Reliability dashboard payload refreshed.'
                evidence = @(
                    (New-OperatorChatEvidence -Label 'Dashboard' -Value 'refreshed' -Section 'recovery_watchdog' -Field 'state')
                )
                result = $payload
            }
        }
        'refresh-share-links' {
            $payload = Get-ShareArtifactsPayload -ActivePort $activePort -BaseUrl $uiUrl
            $artifacts = if ($payload -and $payload.PSObject.Properties['artifacts']) { @($payload.artifacts) } else { @() }
            $availableCount = @($artifacts | Where-Object { $_.exists -eq $true }).Count
            return [pscustomobject]@{
                status = 'succeeded'
                summary = "Share links refreshed. $availableCount of $(@($artifacts).Count) configured artifacts are currently available."
                evidence = @(
                    (New-OperatorChatEvidence -Label 'Available Artifacts' -Value "$availableCount/$(@($artifacts).Count)" -Section 'listener_activity' -Field 'summary')
                )
                result = $payload
            }
        }
        'refresh-project-status' {
            $payload = $resolvedProjectStatus
            $marker = if ($payload) { $payload.marker } else { $null }
            $bridge = if ($payload) { $payload.bridge_status } else { $null }
            return [pscustomobject]@{
                status = 'succeeded'
                summary = "Status snapshot refreshed for objective $([string]$(if ($marker) { $marker.objective_id } else { $resolvedObjectiveId })). Bridge is $([string]$(if ($bridge) { $bridge.status } else { 'unknown' }))."
                evidence = @(
                    (New-OperatorChatEvidence -Label 'Objective' -Value $(if ($marker) { $marker.objective_id } else { $resolvedObjectiveId }) -Section 'marker' -Field 'objective_id'),
                    (New-OperatorChatEvidence -Label 'Bridge Health' -Value $(if ($bridge) { $bridge.status } else { 'unknown' }) -Section 'bridge_status' -Field 'status')
                )
                result = $payload
            }
        }
        'recheck-bridge-diagnostics' {
            $payload = Invoke-OperatorChatQuery -Query $(if ([string]::IsNullOrWhiteSpace($Query)) { 'What is the current bridge mismatch?' } else { $Query }) -Intent 'explain_bridge_status' -ObjectiveId $resolvedObjectiveId -WindowMinutes $WindowMinutes -ValidationHarness $ValidationHarness
            return [pscustomobject]@{
                status = 'succeeded'
                summary = "Bridge diagnostics re-checked. $([string]$payload.response.summary)"
                evidence = @($payload.response.evidence)
                flags = @($payload.response.flags)
                citations = @($payload.response.citations)
                next = [string]$payload.response.recommended_next_step
                result = $payload
            }
        }
        'quick-refresh-reliability' {
            $statusPayload = $resolvedProjectStatus
            $sharePayload = Get-ShareArtifactsPayload -ActivePort $activePort -BaseUrl $uiUrl
            $reliabilityPayload = Invoke-LightweightUiAction -Action 'get-reliability'
            $marker = if ($statusPayload) { $statusPayload.marker } else { $null }
            $bridge = if ($statusPayload) { $statusPayload.bridge_status } else { $null }
            $alert = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties['current_alert_state']) { [string]$reliabilityPayload.current_alert_state } else { 'unknown' }
            $artifactCount = if ($sharePayload -and $sharePayload.PSObject.Properties['artifacts']) { @($sharePayload.artifacts).Count } else { 0 }
            return [pscustomobject]@{
                status = 'succeeded'
                summary = "Quick reliability refresh completed. Objective $([string]$(if ($marker) { $marker.objective_id } else { $resolvedObjectiveId })) is in scope, bridge is $([string]$(if ($bridge) { $bridge.status } else { 'unknown' })), and reliability alert state is $alert."
                evidence = @(
                    (New-OperatorChatEvidence -Label 'Objective' -Value $(if ($marker) { $marker.objective_id } else { $resolvedObjectiveId }) -Section 'marker' -Field 'objective_id'),
                    (New-OperatorChatEvidence -Label 'Bridge Health' -Value $(if ($bridge) { $bridge.status } else { 'unknown' }) -Section 'bridge_status' -Field 'status'),
                    (New-OperatorChatEvidence -Label 'Reliability Alert' -Value $alert -Section 'recovery_watchdog' -Field 'state'),
                    (New-OperatorChatEvidence -Label 'Artifacts Refreshed' -Value $artifactCount -Section 'listener_activity' -Field 'summary')
                )
                result = [pscustomobject]@{
                    project_status = $statusPayload
                    share_artifacts = $sharePayload
                    reliability = $reliabilityPayload
                }
            }
        }
        'refresh-governance-snapshot' {
            $statusPayload = $resolvedProjectStatus
            $sharePayload = Get-ShareArtifactsPayload -ActivePort $activePort -BaseUrl $uiUrl
            $stateBusPayload = Invoke-LightweightUiAction -Action 'get-state-bus'
            $marker = if ($statusPayload) { $statusPayload.marker } else { $null }
            $bridge = if ($statusPayload) { $statusPayload.bridge_status } else { $null }
            $cadence = if ($statusPayload) { $statusPayload.cadence_health } else { $null }
            $maintenance = if ($statusPayload) { $statusPayload.self_health_maintenance } else { $null }
            $agentMode = if ($stateBusPayload -and $stateBusPayload.PSObject.Properties['agent_state'] -and $stateBusPayload.agent_state.PSObject.Properties['mode']) { [string]$stateBusPayload.agent_state.mode } else { 'unknown' }
            $artifactCount = if ($sharePayload -and $sharePayload.PSObject.Properties['artifacts']) { @($sharePayload.artifacts | Where-Object { $_.exists -eq $true }).Count } else { 0 }
            return [pscustomobject]@{
                status = 'succeeded'
                summary = "Governance snapshot refreshed. Objective $([string]$(if ($marker) { $marker.objective_id } else { $resolvedObjectiveId })) is in scope, cadence is $([string]$(if ($cadence) { $cadence.severity } else { 'unknown' })), bridge is $([string]$(if ($bridge) { $bridge.status } else { 'unknown' })), and maintenance is $([string]$(if ($maintenance) { $maintenance.overall_status } else { 'unknown' }))."
                evidence = @(
                    (New-OperatorChatEvidence -Label 'Objective' -Value $(if ($marker) { $marker.objective_id } else { $resolvedObjectiveId }) -Section 'marker' -Field 'objective_id'),
                    (New-OperatorChatEvidence -Label 'Cadence Severity' -Value $(if ($cadence) { $cadence.severity } else { 'unknown' }) -Section 'cadence_health' -Field 'severity'),
                    (New-OperatorChatEvidence -Label 'Bridge Health' -Value $(if ($bridge) { $bridge.status } else { 'unknown' }) -Section 'bridge_status' -Field 'status'),
                    (New-OperatorChatEvidence -Label 'Maintenance Status' -Value $(if ($maintenance) { $maintenance.overall_status } else { 'unknown' }) -Section 'self_health_maintenance' -Field 'overall_status'),
                    (New-OperatorChatEvidence -Label 'Available Artifacts' -Value $artifactCount -Section 'listener_activity' -Field 'summary'),
                    (New-OperatorChatEvidence -Label 'Agent Mode' -Value $agentMode -Section 'listener_activity' -Field 'summary')
                )
                next = 'Use this governance bundle to decide whether a narrower bridge, cadence, or maintenance diagnostic is still needed.'
                result = [pscustomobject]@{
                    project_status = $statusPayload
                    share_artifacts = $sharePayload
                    state_bus = $stateBusPayload
                }
            }
        }
        'refresh-bridge-alignment-bundle' {
            $statusPayload = $resolvedProjectStatus
            $sharePayload = Get-ShareArtifactsPayload -ActivePort $activePort -BaseUrl $uiUrl
            $stateBusPayload = Invoke-LightweightUiAction -Action 'get-state-bus'
            $bridgePayload = Invoke-OperatorChatQuery -Query $(if ([string]::IsNullOrWhiteSpace($Query)) { 'What is the current bridge mismatch?' } else { $Query }) -Intent 'explain_bridge_status' -ObjectiveId $resolvedObjectiveId -WindowMinutes $WindowMinutes -ValidationHarness $ValidationHarness
            $artifactsAvailable = if ($sharePayload -and $sharePayload.PSObject.Properties['artifacts']) { @($sharePayload.artifacts | Where-Object { $_.exists -eq $true }).Count } else { 0 }
            $agentMode = if ($stateBusPayload -and $stateBusPayload.PSObject.Properties['agent_state'] -and $stateBusPayload.agent_state.PSObject.Properties['mode']) { [string]$stateBusPayload.agent_state.mode } else { 'unknown' }
            return [pscustomobject]@{
                status = 'succeeded'
                summary = "Bridge alignment bundle refreshed. $([string]$bridgePayload.response.summary)"
                evidence = @(
                    @($bridgePayload.response.evidence)
                    (New-OperatorChatEvidence -Label 'Available Artifacts' -Value $artifactsAvailable -Section 'listener_activity' -Field 'summary')
                    (New-OperatorChatEvidence -Label 'Agent Mode' -Value $agentMode -Section 'listener_activity' -Field 'summary')
                )
                flags = @($bridgePayload.response.flags)
                citations = @($bridgePayload.response.citations)
                next = 'Use the refreshed bridge evidence and state-bus posture before considering publisher-side intervention.'
                result = [pscustomobject]@{
                    bridge = $bridgePayload
                    share_artifacts = $sharePayload
                    state_bus = $stateBusPayload
                    project_status = $statusPayload
                }
            }
        }
        default {
            throw "Unsupported governed action: $Action"
        }
    }
}

function Get-OperatorChatExecutionReadinessGate {
    param(
        [Parameter(Mandatory = $true)][string]$ActionName,
        [string]$ConfigPath,
        [switch]$ApplyPlan,
        [switch]$GovernedConfirm
    )

    $payload = $null
    try {
        $resolvedConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $configPath } else { $ConfigPath }
        $raw = & $todScript -Action "get-execution-readiness" -ConfigPath $resolvedConfigPath -Top 1 2>&1
        $payload = $raw | ConvertFrom-Json
    }
    catch {
        $payload = $null
    }

    if ($null -eq $payload -or -not $payload.PSObject.Properties['readiness']) {
        return [pscustomobject]@{
            blocked = $true
            degraded = $false
            signal = $payload
            trace = [pscustomobject]@{
                status = 'unknown'
                source = 'readiness_unavailable'
                detail = 'Execution readiness payload is unavailable.'
                valid = $false
                execution_allowed = $false
                authoritative = $true
                freshness_state = 'unknown'
                signal_name = 'execution-readiness'
                evaluated_action = $ActionName
                policy_outcome = 'block'
                decision_path = @(
                    'signal:execution-readiness',
                    'status:unknown',
                    'source:readiness_unavailable',
                    "action:$ActionName",
                    'policy_outcome:block'
                )
            }
        }
    }

    $readiness = $payload.readiness
    $status = if ($readiness.PSObject.Properties['status']) { ([string]$readiness.status).ToLowerInvariant() } else { 'unknown' }
    $blockActions = if ($payload.PSObject.Properties['policy'] -and $payload.policy.PSObject.Properties['block_actions']) { @($payload.policy.block_actions | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @('run-task') }
    $degradeActions = if ($payload.PSObject.Properties['policy'] -and $payload.policy.PSObject.Properties['degrade_actions']) { @($payload.policy.degrade_actions | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @('engineer-run') }
    $blockStates = if ($payload.PSObject.Properties['policy'] -and $payload.policy.PSObject.Properties['block_states']) { @($payload.policy.block_states | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @('stale', 'invalid', 'unknown') }
    $degradeStates = if ($payload.PSObject.Properties['policy'] -and $payload.policy.PSObject.Properties['degrade_states']) { @($payload.policy.degrade_states | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @('degraded', 'stale', 'invalid', 'unknown') }
    $actionNameLower = ([string]$ActionName).ToLowerInvariant()
    $effectiveApplyPlan = [bool]$ApplyPlan

    $applyGovernedConfirmBlockPolicy = [bool]$GovernedConfirm
    $blocked = (((($blockActions -contains $actionNameLower) -or $applyGovernedConfirmBlockPolicy) -and ($blockStates -contains $status)))
    $degraded = (-not $blocked) -and (($degradeActions -contains $actionNameLower) -and ($degradeStates -contains $status))
    if ($degraded -and $effectiveApplyPlan -and $payload.PSObject.Properties['policy'] -and $payload.policy.PSObject.Properties['degrade_apply_plan'] -and [bool]$payload.policy.degrade_apply_plan) {
        $effectiveApplyPlan = $false
    }
    $policyOutcome = if ($blocked) { 'block' } elseif ($degraded) { 'degrade' } else { 'allow' }

    $decisionPath = @(
        'signal:execution-readiness',
        "status:$(if ($readiness.PSObject.Properties['status']) { [string]$readiness.status } else { 'unknown' })",
        "source:$(if ($readiness.PSObject.Properties['reason']) { [string]$readiness.reason } else { 'unknown' })",
        "action:$ActionName",
        "policy_outcome:$policyOutcome"
    )
    if (-not [string]::IsNullOrWhiteSpace($resolvedConfigPath)) {
        $decisionPath += "config_path:$resolvedConfigPath"
    }
    if ($ApplyPlan.IsPresent) {
        $decisionPath += 'apply_plan_requested:true'
        $decisionPath += "apply_plan_effective:$([bool]$effectiveApplyPlan)"
    }
    if ($GovernedConfirm.IsPresent) {
        $decisionPath += 'governed_confirm:true'
    }

    return [pscustomobject]@{
        blocked = $blocked
        degraded = $degraded
        effective_apply_plan = [bool]$effectiveApplyPlan
        signal = $payload
        trace = [pscustomobject]@{
            status = if ($readiness.PSObject.Properties['status']) { [string]$readiness.status } else { 'unknown' }
            source = if ($readiness.PSObject.Properties['reason']) { [string]$readiness.reason } else { 'unknown' }
            detail = if ($readiness.PSObject.Properties['detail']) { [string]$readiness.detail } else { '' }
            valid = if ($readiness.PSObject.Properties['valid']) { [bool]$readiness.valid } else { $false }
            execution_allowed = if ($readiness.PSObject.Properties['execution_allowed']) { [bool]$readiness.execution_allowed } else { $false }
            authoritative = if ($readiness.PSObject.Properties['authoritative']) { [bool]$readiness.authoritative } else { $true }
            freshness_state = if ($readiness.PSObject.Properties['freshness_state']) { [string]$readiness.freshness_state } else { 'unknown' }
            signal_name = if ($payload.PSObject.Properties['signal_name']) { [string]$payload.signal_name } else { 'execution-readiness' }
            evaluated_action = $ActionName
            policy_outcome = $policyOutcome
            config_path = $resolvedConfigPath
            effective_apply_plan = [bool]$effectiveApplyPlan
            decision_path = @($decisionPath)
        }
    }
}

function Invoke-OperatorChatActionRequest {
    param(
        [string]$Phase,
        [string]$Action,
        [string]$Intent,
        [string]$ObjectiveId,
        [string]$Query,
        [int]$WindowMinutes,
        [string]$OperatorId,
        [string]$SuggestedReason,
        [string]$Mode,
        [string]$PreviewId,
        [string]$ConfigPath,
        [string]$RemoteEndpoint,
        [string]$ValidationHarness = ''
    )

    $normalizedPhase = if ([string]::IsNullOrWhiteSpace($Phase)) { 'preview' } else { ([string]$Phase).Trim().ToLowerInvariant() }
    $resolvedObjectiveId = [string]$ObjectiveId
    $resolvedIntent = Resolve-OperatorChatIntent -Query $Query -Intent $Intent
    $actor = if ([string]::IsNullOrWhiteSpace($OperatorId)) { 'local-operator' } else { [string]$OperatorId }
    $resolvedPreviewId = if ([string]::IsNullOrWhiteSpace($PreviewId)) { [guid]::NewGuid().ToString() } else { [string]$PreviewId }
    $operatorResponse = Get-CachedOperatorChatQueryResult -Query $Query -Intent $resolvedIntent -ObjectiveId $resolvedObjectiveId -WindowMinutes $WindowMinutes -ValidationHarness $ValidationHarness
    $resolvedValidationHarness = if (-not [string]::IsNullOrWhiteSpace($ValidationHarness)) {
        [string]$ValidationHarness
    }
    elseif ($operatorResponse -and $operatorResponse.PSObject.Properties['validation_harness'] -and $operatorResponse.validation_harness -and $operatorResponse.validation_harness.PSObject.Properties['name']) {
        [string]$operatorResponse.validation_harness.name
    }
    else {
        ''
    }
    if ([string]::IsNullOrWhiteSpace($resolvedValidationHarness) -and -not [string]::IsNullOrWhiteSpace($resolvedObjectiveId)) {
        $recentCommitmentPayload = Get-OperatorChatCommitmentPayload -Limit 6 -ObjectiveId $resolvedObjectiveId
        $recentHarnessEntry = @($recentCommitmentPayload.entries | Where-Object {
                $_ -and
                $_.PSObject.Properties['validation_harness'] -and
                -not [string]::IsNullOrWhiteSpace([string]$_.validation_harness)
            } | Select-Object -First 1)
        if (@($recentHarnessEntry).Count -gt 0) {
            $resolvedValidationHarness = [string]$recentHarnessEntry[0].validation_harness
        }
    }
    $projectStatus = Get-ProjectStatusPayload -ObjectiveId $resolvedObjectiveId -ValidationHarness $resolvedValidationHarness
    if ($null -eq $operatorResponse) {
        $operatorResponse = Invoke-OperatorChatQuery -Query $Query -Intent $resolvedIntent -ObjectiveId $resolvedObjectiveId -WindowMinutes $WindowMinutes -ValidationHarness $resolvedValidationHarness
    }
    $policy = Get-OperatorChatGovernedActionPolicy -Action $Action -Intent $resolvedIntent -SuggestedReason $SuggestedReason -Mode $Mode -ProjectStatus $projectStatus
    $matchedSuggestedAction = Get-OperatorChatSuggestedActionMetadata -OperatorResponse $operatorResponse -Action $policy.action -SuggestedReason $policy.suggested_reason -Mode $policy.mode
    if ($null -eq $matchedSuggestedAction) {
        $operatorResponse = Invoke-OperatorChatQuery -Query $Query -Intent $resolvedIntent -ObjectiveId $resolvedObjectiveId -WindowMinutes $WindowMinutes -ValidationHarness $resolvedValidationHarness
        $matchedSuggestedAction = Get-OperatorChatSuggestedActionMetadata -OperatorResponse $operatorResponse -Action $policy.action -SuggestedReason $policy.suggested_reason -Mode $policy.mode
    }
    $confirmationReason = 'Confirmation is required because even bounded operator actions should be explicit, inspectable, replay-resistant, and auditable.'
    $reasoningBundle = $null
    $reasoningBundleId = ''

    if ([string]::Equals($normalizedPhase, 'preview', [System.StringComparison]::OrdinalIgnoreCase)) {
        $reasoningBundle = New-OperatorChatReasoningBundle -Phase 'preview' -Action $policy.action -Intent $resolvedIntent -ObjectiveId $resolvedObjectiveId -Query $Query -Actor $actor -PreviewId $resolvedPreviewId -ConfirmationReason $confirmationReason -Policy $policy -OperatorResponse $operatorResponse
        Write-OperatorChatReasoningEntry -Entry $reasoningBundle
        $reasoningBundleId = [string]$reasoningBundle.reasoning_bundle_id
    }
    elseif (-not [string]::IsNullOrWhiteSpace($resolvedPreviewId) -and $operatorChatActionPreviewRegistry.ContainsKey([string]$resolvedPreviewId)) {
        $previewEntry = $operatorChatActionPreviewRegistry[[string]$resolvedPreviewId]
        if ($previewEntry -and $previewEntry.PSObject.Properties['reasoning_bundle_id']) {
            $reasoningBundleId = [string]$previewEntry.reasoning_bundle_id
        }
    }

    if ([string]::IsNullOrWhiteSpace($reasoningBundleId)) {
        $reasoningBundle = New-OperatorChatReasoningBundle -Phase $normalizedPhase -Action $policy.action -Intent $resolvedIntent -ObjectiveId $resolvedObjectiveId -Query $Query -Actor $actor -PreviewId $resolvedPreviewId -ConfirmationReason $confirmationReason -Policy $policy -OperatorResponse $operatorResponse
        Write-OperatorChatReasoningEntry -Entry $reasoningBundle
        $reasoningBundleId = [string]$reasoningBundle.reasoning_bundle_id
    }

    $baseAudit = [ordered]@{
        audit_id = [guid]::NewGuid().ToString()
        preview_id = $resolvedPreviewId
        reasoning_bundle_id = $reasoningBundleId
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        phase = $normalizedPhase
        actor = $actor
        remote_endpoint = [string]$RemoteEndpoint
        intent = [string]$resolvedIntent
        query = [string]$Query
        objective_id = [string]$resolvedObjectiveId
        action = [string]$policy.action
        action_label = [string]$policy.label
        action_mode = [string]$policy.mode
        allowed = [bool]$policy.allowed
        confirmation_required = [bool]$policy.confirmation_required
        allow_reason = [string]$policy.allow_reason
        blocked_reason = [string]$policy.blocked_reason
        suggested_reason = [string]$policy.suggested_reason
        evidence_flags = @($operatorResponse.response.flags)
        evidence_citations = @($operatorResponse.response.citations)
        proposal_source = if ($matchedSuggestedAction -and $matchedSuggestedAction.PSObject.Properties['proposal_source']) { [string]$matchedSuggestedAction.proposal_source } else { '' }
        proposal_id = if ($matchedSuggestedAction -and $matchedSuggestedAction.PSObject.Properties['proposal_id']) { [string]$matchedSuggestedAction.proposal_id } else { '' }
        proposal_objective_id = if ($matchedSuggestedAction -and $matchedSuggestedAction.PSObject.Properties['proposal_objective_id']) { [string]$matchedSuggestedAction.proposal_objective_id } else { '' }
        proposal_title = if ($matchedSuggestedAction -and $matchedSuggestedAction.PSObject.Properties['proposal_title']) { [string]$matchedSuggestedAction.proposal_title } else { '' }
        proposal_acknowledgment_disposition = if ($matchedSuggestedAction -and $matchedSuggestedAction.PSObject.Properties['proposal_acknowledgment_disposition']) { [string]$matchedSuggestedAction.proposal_acknowledgment_disposition } else { '' }
        proposal_closure_status = if ($matchedSuggestedAction -and $matchedSuggestedAction.PSObject.Properties['proposal_closure_status']) { [string]$matchedSuggestedAction.proposal_closure_status } else { '' }
        proposal_closure_disposition = if ($matchedSuggestedAction -and $matchedSuggestedAction.PSObject.Properties['proposal_closure_disposition']) { [string]$matchedSuggestedAction.proposal_closure_disposition } else { '' }
        proposal_closure_summary = if ($matchedSuggestedAction -and $matchedSuggestedAction.PSObject.Properties['proposal_closure_summary']) { [string]$matchedSuggestedAction.proposal_closure_summary } else { '' }
    }

    if (@('preview', 'confirm') -notcontains $normalizedPhase) {
        $auditEntry = [pscustomobject]($baseAudit + [ordered]@{
            outcome_status = 'invalid_request'
            outcome_summary = "Unsupported operator-chat-action phase '$normalizedPhase'."
        })
        Write-OperatorChatActionAuditEntry -Entry $auditEntry

        return [pscustomobject]@{
            ok = $true
            phase = $normalizedPhase
            action_status = 'invalid_request'
            action = [string]$policy.action
            action_label = [string]$policy.label
            summary = "Unsupported operator-chat-action phase '$normalizedPhase'."
            evidence = @($operatorResponse.response.evidence)
            flags = @(@($operatorResponse.response.flags) + @('action_blocked'))
            limitations = @($operatorResponse.response.limitations)
            citations = @($operatorResponse.response.citations)
            alternative_actions = @(Get-OperatorChatGovernedActionAlternatives -ProjectStatus $projectStatus -Intent $resolvedIntent -ExcludeAction $policy.action)
            recommended_next_step = 'Use preview or confirm, and request a fresh preview before attempting confirmation.'
            audit = $auditEntry
        }
    }

    if ([string]::Equals($normalizedPhase, 'preview', [System.StringComparison]::OrdinalIgnoreCase)) {
        $previewRecord = $null
        if ($policy.allowed) {
            $previewRecord = Register-OperatorChatActionPreview -PreviewId $resolvedPreviewId -Action $policy.action -Label $policy.label -Intent $resolvedIntent -ObjectiveId $resolvedObjectiveId -Query $Query -Mode $policy.mode -Actor $actor -SuggestedReason $policy.suggested_reason -ReasoningBundleId $reasoningBundleId -RemoteEndpoint $RemoteEndpoint -ProposalSource ([string]$baseAudit.proposal_source) -ProposalId ([string]$baseAudit.proposal_id) -ProposalObjectiveId ([string]$baseAudit.proposal_objective_id) -ProposalTitle ([string]$baseAudit.proposal_title) -ProposalAcknowledgmentDisposition ([string]$baseAudit.proposal_acknowledgment_disposition) -ProposalClosureStatus ([string]$baseAudit.proposal_closure_status) -ProposalClosureDisposition ([string]$baseAudit.proposal_closure_disposition) -ProposalClosureSummary ([string]$baseAudit.proposal_closure_summary)
        }

        $auditEntry = [pscustomobject]($baseAudit + [ordered]@{
            preview_expires_at = if ($previewRecord) { [string]$previewRecord.expires_at } else { '' }
            outcome_status = if ($policy.allowed) { 'previewed' } else { 'blocked' }
            outcome_summary = if ($policy.allowed) { "Previewed governed action $([string]$policy.label)." } else { [string]$policy.blocked_reason }
        })
        Write-OperatorChatActionAuditEntry -Entry $auditEntry

        $previewFlags = New-Object System.Collections.Generic.List[string]
        foreach ($flag in @($operatorResponse.response.flags)) {
            [void]$previewFlags.Add([string]$flag)
        }
        if (-not $policy.allowed) {
            [void]$previewFlags.Add('action_blocked')
        }

        return [pscustomobject]@{
            ok = $true
            preview_id = $resolvedPreviewId
            preview_expires_at = if ($previewRecord) { [string]$previewRecord.expires_at } else { '' }
            phase = 'preview'
            action = [string]$policy.action
            action_label = [string]$policy.label
            allowed = [bool]$policy.allowed
            blocked = -not [bool]$policy.allowed
            confirmation_required = [bool]$policy.confirmation_required
            policy_reason = if ($policy.allowed) { [string]$policy.allow_reason } else { [string]$policy.blocked_reason }
            policy_remediation = [string]$policy.remediation
            confirmation_reason = $confirmationReason
            expected_impact = [string]$policy.expected_impact
            suggested_reason = [string]$policy.suggested_reason
            reasoning_bundle = $reasoningBundle
            evidence = @($operatorResponse.response.evidence)
            flags = @($previewFlags | Select-Object -Unique)
            limitations = @($operatorResponse.response.limitations)
            citations = @($operatorResponse.response.citations)
            alternative_actions = @($policy.alternative_actions)
            audit = $auditEntry
        }
    }

    $baseAudit.reasoning_bundle_id = $reasoningBundleId

    if ([string]::IsNullOrWhiteSpace($resolvedPreviewId)) {
        $auditEntry = [pscustomobject]($baseAudit + [ordered]@{
            outcome_status = 'invalid_preview'
            outcome_summary = 'preview_id is required for confirmation.'
        })
        Write-OperatorChatActionAuditEntry -Entry $auditEntry

        return [pscustomobject]@{
            ok = $true
            phase = 'confirm'
            action_status = 'invalid_preview'
            action = [string]$policy.action
            action_label = [string]$policy.label
            summary = 'preview_id is required for confirmation.'
            evidence = @($operatorResponse.response.evidence)
            flags = @(@($operatorResponse.response.flags) + @('action_blocked'))
            limitations = @($operatorResponse.response.limitations)
            citations = @($operatorResponse.response.citations)
            alternative_actions = @(Get-OperatorChatGovernedActionAlternatives -ProjectStatus $projectStatus -Intent $resolvedIntent -ExcludeAction $policy.action)
            recommended_next_step = 'Request a new governed action preview and confirm only that exact preview.'
            audit = $auditEntry
        }
    }

    $previewValidation = Test-OperatorChatActionPreviewConfirmation -PreviewId $resolvedPreviewId -Action $Action -Intent $resolvedIntent -ObjectiveId $resolvedObjectiveId -Query $Query -Mode $Mode -Actor $actor
    if (-not $previewValidation.valid) {
        $auditEntry = [pscustomobject]($baseAudit + [ordered]@{
            outcome_status = [string]$previewValidation.status
            outcome_summary = [string]$previewValidation.reason
        })
        Write-OperatorChatActionAuditEntry -Entry $auditEntry

        return [pscustomobject]@{
            ok = $true
            phase = 'confirm'
            action_status = [string]$previewValidation.status
            action = [string]$policy.action
            action_label = [string]$policy.label
            summary = [string]$previewValidation.reason
            evidence = @($operatorResponse.response.evidence)
            flags = @(@($operatorResponse.response.flags) + @('action_blocked'))
            limitations = @($operatorResponse.response.limitations)
            citations = @($operatorResponse.response.citations)
            alternative_actions = @(Get-OperatorChatGovernedActionAlternatives -ProjectStatus $projectStatus -Intent $resolvedIntent -ExcludeAction $policy.action)
            recommended_next_step = 'Request a fresh governed action preview and confirm that exact request only once.'
            audit = $auditEntry
        }
    }

    if (-not $policy.allowed) {
        $auditEntry = [pscustomobject]($baseAudit + [ordered]@{
            outcome_status = 'blocked'
            outcome_summary = [string]$policy.blocked_reason
        })
        Write-OperatorChatActionAuditEntry -Entry $auditEntry

        return [pscustomobject]@{
            ok = $true
            phase = 'confirm'
            action_status = 'blocked'
            action = [string]$policy.action
            action_label = [string]$policy.label
            summary = [string]$policy.blocked_reason
            evidence = @($operatorResponse.response.evidence)
            flags = @(@($operatorResponse.response.flags) + @('action_blocked'))
            limitations = @($operatorResponse.response.limitations)
            citations = @($operatorResponse.response.citations)
            alternative_actions = @($policy.alternative_actions)
            recommended_next_step = [string]$policy.remediation
            audit = $auditEntry
        }
    }

    $executionActionName = if ([string]::IsNullOrWhiteSpace([string]$policy.action)) { 'run-task' } else { [string]$policy.action }
    $executionReadinessGate = Get-OperatorChatExecutionReadinessGate -ActionName $executionActionName -ConfigPath $ConfigPath -GovernedConfirm
    if ($executionReadinessGate.blocked) {
        $auditEntry = [pscustomobject]($baseAudit + [ordered]@{
            execution_readiness_status = if ($executionReadinessGate.trace.PSObject.Properties['status']) { [string]$executionReadinessGate.trace.status } else { 'unknown' }
            execution_readiness_source = if ($executionReadinessGate.trace.PSObject.Properties['source']) { [string]$executionReadinessGate.trace.source } else { 'unknown' }
            execution_readiness_policy_outcome = if ($executionReadinessGate.trace.PSObject.Properties['policy_outcome']) { [string]$executionReadinessGate.trace.policy_outcome } else { 'block' }
            execution_readiness_config_path = if ($executionReadinessGate.trace.PSObject.Properties['config_path']) { [string]$executionReadinessGate.trace.config_path } else { '' }
            outcome_status = 'blocked'
            outcome_summary = 'Execution blocked by the authoritative certification gate.'
        })
        Write-OperatorChatActionAuditEntry -Entry $auditEntry

        return [pscustomobject]@{
            ok = $true
            phase = 'confirm'
            action_status = 'blocked'
            action = [string]$policy.action
            action_label = [string]$policy.label
            summary = 'Execution blocked by the authoritative certification gate.'
            evidence = @($operatorResponse.response.evidence)
            flags = @(@($operatorResponse.response.flags) + @('execution_readiness_blocked') | Select-Object -Unique)
            limitations = @($operatorResponse.response.limitations)
            citations = @($operatorResponse.response.citations)
            alternative_actions = @($policy.alternative_actions)
            recommended_next_step = 'Run .\scripts\Test-TODOperatorChatSweepArtifact.ps1 and restore a current passing certification artifact before confirming governed actions.'
            execution_readiness = $executionReadinessGate.trace
            audit = $auditEntry
        }
    }

    $commitment = Get-OperatorChatCommitmentForPreview -PreviewId $resolvedPreviewId

    [void](Mark-OperatorChatActionPreviewConsumed -PreviewId $resolvedPreviewId)

    try {
        $execution = Invoke-OperatorChatGovernedAction -Action $policy.action -ObjectiveId $resolvedObjectiveId -Intent $resolvedIntent -Query $Query -WindowMinutes $WindowMinutes -ProjectStatus $projectStatus -ValidationHarness $resolvedValidationHarness
        $executionFlags = New-Object System.Collections.Generic.List[string]
        foreach ($flag in @($operatorResponse.response.flags)) {
            [void]$executionFlags.Add([string]$flag)
        }
        if ($execution.PSObject.Properties['flags']) {
            foreach ($flag in @($execution.flags)) {
                [void]$executionFlags.Add([string]$flag)
            }
        }

        $executionCitations = if ($execution.PSObject.Properties['citations']) { @($execution.citations) } else { @($operatorResponse.response.citations) }
        $executionEvidence = if ($execution.PSObject.Properties['evidence']) { @($execution.evidence) } else { @($operatorResponse.response.evidence) }
        $nextStep = if ($execution.PSObject.Properties['next']) { [string]$execution.next } else { 'Use the refreshed evidence to decide whether another bounded action is needed.' }

        $auditEntry = [pscustomobject]($baseAudit + [ordered]@{
            commitment_id = if ($commitment) { [string]$commitment.commitment_id } else { '' }
            outcome_status = [string]$execution.status
            outcome_summary = [string]$execution.summary
        })
        Write-OperatorChatActionAuditEntry -Entry $auditEntry

        return [pscustomobject]@{
            ok = $true
            phase = 'confirm'
            action_status = [string]$execution.status
            action = [string]$policy.action
            action_label = [string]$policy.label
            reasoning_bundle = if ($reasoningBundle) { $reasoningBundle } else { (Get-OperatorChatReasoningPayload -Limit 1 -BundleId $reasoningBundleId).entries[0] }
            summary = [string]$execution.summary
            execution_readiness = $executionReadinessGate.trace
            evidence = @($executionEvidence)
            flags = @($executionFlags | Select-Object -Unique)
            limitations = @($operatorResponse.response.limitations)
            citations = @($executionCitations)
            alternative_actions = @()
            recommended_next_step = $nextStep
            result = $execution.result
            commitment = $commitment
            audit = $auditEntry
        }
    }
    catch {
        $auditEntry = [pscustomobject]($baseAudit + [ordered]@{
            commitment_id = if ($commitment) { [string]$commitment.commitment_id } else { '' }
            outcome_status = 'failed'
            outcome_summary = [string]$_.Exception.Message
        })
        Write-OperatorChatActionAuditEntry -Entry $auditEntry

        return [pscustomobject]@{
            ok = $true
            phase = 'confirm'
            action_status = 'failed'
            action = [string]$policy.action
            action_label = [string]$policy.label
            reasoning_bundle = if ($reasoningBundle) { $reasoningBundle } else { (Get-OperatorChatReasoningPayload -Limit 1 -BundleId $reasoningBundleId).entries[0] }
            summary = [string]$_.Exception.Message
            evidence = @($operatorResponse.response.evidence)
            flags = @($operatorResponse.response.flags)
            limitations = @($operatorResponse.response.limitations)
            citations = @($operatorResponse.response.citations)
            alternative_actions = @(Get-OperatorChatGovernedActionAlternatives -ProjectStatus $projectStatus -Intent $resolvedIntent -ExcludeAction $policy.action)
            recommended_next_step = 'Inspect the action audit trail and request a fresh preview before retrying any bounded alternative.'
            commitment = $commitment
            audit = $auditEntry
        }
    }
}

function Resolve-OperatorChatIntent {
    param(
        [string]$Query,
        [string]$Intent
    )

    $allowed = @(
        'summarize_status',
        'explain_warning',
        'explain_bridge_status',
        'explain_cadence',
        'explain_maintenance',
        'suggest_next_action',
        'summarize_current_objective',
        'summarize_recent_changes'
    )

    if (-not [string]::IsNullOrWhiteSpace($Intent) -and ($allowed -contains $Intent)) {
        return $Intent
    }

    $q = [string]$Query
    if ([string]::IsNullOrWhiteSpace($q)) {
        return 'summarize_status'
    }

    $normalized = $q.Trim().ToLowerInvariant()

    if ($normalized -match 'what did .* just work on|what was .* just working on|what did tod do|what just happened|what changed|last\s+\d+\s+minute|recent changes|since the last successful completion|last task you worked on|last task|what have you been working on') {
        return 'summarize_recent_changes'
    }
    if ($normalized -match 'what are you currently working on|currently working on|current task|what are you working on|what is tod working on') {
        return 'summarize_current_objective'
    }
    if ($normalized -match 'what should i do next|action should i run next|run next|next action|resync|restart|just patience|just wait|what now') {
        return 'suggest_next_action'
    }
    if ($normalized -match 'healthy_with_fallback|maintenance|fallback') {
        return 'explain_maintenance'
    }
    if ($normalized -match 'cadence|retry|idle|critical|p95|loop idle') {
        return 'explain_cadence'
    }
    if ($normalized -match 'bridge|mim ahead|ahead of tod|mismatch|ack|shared path') {
        return 'explain_bridge_status'
    }
    if ($normalized -match 'blocking progress|why .*warning|explain warning|warning exists|blocked') {
        return 'explain_warning'
    }
    if ($normalized -match 'objective\s+\d+|current objective|what is objective') {
        return 'summarize_current_objective'
    }

    return 'summarize_status'
}

function Get-OperatorChatObjectiveIdFromQuery {
    param([string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) {
        return ''
    }

    $match = [regex]::Match([string]$Query, 'objective\s+(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return [string]$match.Groups[1].Value
    }

    return ''
}

function ConvertTo-OperatorChatEvidenceText {
    param([object]$Value)

    if ($null -eq $Value) {
        return '-'
    }

    if ($Value -is [bool]) {
        return $Value.ToString().ToLowerInvariant()
    }

    return [string]$Value
}

function New-OperatorChatEvidence {
    param(
        [string]$Label,
        [object]$Value,
        [string]$Section,
        [string]$Field
    )

    return [pscustomobject]@{
        label = $Label
        value = ConvertTo-OperatorChatEvidenceText -Value $Value
        section = $Section
        field = $Field
    }
}

function New-OperatorChatAction {
    param(
        [string]$Action,
        [string]$Label,
        [string]$Reason,
        [string]$Mode = 'read_only',
        [string]$ProposalSource = '',
        [string]$ProposalId = '',
        [string]$ProposalObjectiveId = '',
        [string]$ProposalPriority = '',
        [string]$ProposalTitle = '',
        [string]$ProposalSummary = '',
        [string]$ProposalConflictStatus = '',
        [bool]$ProposalConflictDetected = $false,
        [string]$ProposalConflictSummary = '',
        [string]$ProposalArbitrationStatus = '',
        [string]$ProposalArbitrationWinner = '',
        [string]$ProposalArbitrationSummary = '',
        [string]$ProposalMergePolicyStatus = '',
        [string]$ProposalMergePolicyMode = '',
        [string]$ProposalMergePolicySummary = '',
        [string]$ProposalAcknowledgmentStatus = '',
        [string]$ProposalAcknowledgmentDisposition = '',
        [string]$ProposalAcknowledgmentSummary = '',
        [string]$ProposalClosureStatus = '',
        [string]$ProposalClosureDisposition = '',
        [string]$ProposalClosureSummary = ''
    )

    return [pscustomobject]@{
        action = $Action
        label = $Label
        reason = $Reason
        mode = $Mode
        proposal_source = $ProposalSource
        proposal_id = $ProposalId
        proposal_objective_id = $ProposalObjectiveId
        proposal_priority = $ProposalPriority
        proposal_title = $ProposalTitle
        proposal_summary = $ProposalSummary
        proposal_conflict_status = $ProposalConflictStatus
        proposal_conflict_detected = [bool]$ProposalConflictDetected
        proposal_conflict_summary = $ProposalConflictSummary
        proposal_arbitration_status = $ProposalArbitrationStatus
        proposal_arbitration_winner = $ProposalArbitrationWinner
        proposal_arbitration_summary = $ProposalArbitrationSummary
        proposal_merge_policy_status = $ProposalMergePolicyStatus
        proposal_merge_policy_mode = $ProposalMergePolicyMode
        proposal_merge_policy_summary = $ProposalMergePolicySummary
        proposal_acknowledgment_status = $ProposalAcknowledgmentStatus
        proposal_acknowledgment_disposition = $ProposalAcknowledgmentDisposition
        proposal_acknowledgment_summary = $ProposalAcknowledgmentSummary
        proposal_closure_status = $ProposalClosureStatus
        proposal_closure_disposition = $ProposalClosureDisposition
        proposal_closure_summary = $ProposalClosureSummary
    }
}

function Get-OperatorChatCitationForSection {
    param(
        [string]$Section,
        [string]$Field
    )

    $normalizedSection = [string]$Section
    switch ($normalizedSection) {
        'marker' {
            return [pscustomobject]@{ section = $normalizedSection; field = $Field; card_id = 'projectMarkerCard'; card_label = 'Current Project Marker' }
        }
        'progress' {
            return [pscustomobject]@{ section = $normalizedSection; field = $Field; card_id = 'projectMarkerCard'; card_label = 'Current Project Marker' }
        }
        'steady_state' {
            return [pscustomobject]@{ section = $normalizedSection; field = $Field; card_id = 'projectMarkerCard'; card_label = 'Current Project Marker' }
        }
        'cadence_health' {
            return [pscustomobject]@{ section = $normalizedSection; field = $Field; card_id = 'projectMarkerCard'; card_label = 'Current Project Marker' }
        }
        'bridge_status' {
            return [pscustomobject]@{ section = $normalizedSection; field = $Field; card_id = 'bridgeStatusCard'; card_label = 'Bridge Status' }
        }
        'self_health_maintenance' {
            return [pscustomobject]@{ section = $normalizedSection; field = $Field; card_id = 'maintenanceStatusCard'; card_label = 'Maintenance Status' }
        }
        'recovery_watchdog' {
            return [pscustomobject]@{ section = $normalizedSection; field = $Field; card_id = 'actionWorkspaceCard'; card_label = 'Action Workspace' }
        }
        'listener_activity' {
            return [pscustomobject]@{ section = $normalizedSection; field = $Field; card_id = 'actionWorkspaceCard'; card_label = 'Action Workspace' }
        }
        'mim_proposal' {
            return [pscustomobject]@{ section = $normalizedSection; field = $Field; card_id = 'actionWorkspaceCard'; card_label = 'Action Workspace' }
        }
        default {
            return [pscustomobject]@{ section = $normalizedSection; field = $Field; card_id = 'operatorChatCard'; card_label = 'TOD Operator Chat' }
        }
    }
}

function Get-OperatorChatRecentChangesMode {
    param([string]$Query)

    $normalized = [string]$Query
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return 'window'
    }

    if ($normalized.Trim().ToLowerInvariant() -match 'since the last successful completion|last successful completion') {
        return 'last_successful_completion'
    }

    return 'window'
}

function Get-OperatorChatLastSuccessfulCompletionTime {
    param($ListenerActivity)

    $entries = @()
    if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['recent_entries']) {
        $entries = @($ListenerActivity.recent_entries)
    }

    $latestCompleted = $null
    foreach ($entry in $entries) {
        $status = if ($entry.PSObject.Properties['execution_status']) { [string]$entry.execution_status } else { '' }
        if (-not [string]::Equals($status, 'completed', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $timestamp = if ($entry.PSObject.Properties['timestamp']) { [string]$entry.timestamp } else { '' }
        $dt = Convert-ToDateTimeOffsetOrNull -Value $timestamp
        if ($null -eq $dt) {
            continue
        }

        if ($null -eq $latestCompleted -or $dt.UtcDateTime -gt $latestCompleted.UtcDateTime) {
            $latestCompleted = $dt
        }
    }

    return $latestCompleted
}

function Get-OperatorChatRecentChanges {
    param(
        $ListenerActivity,
        $BridgeStatus,
        $Maintenance,
        [string]$Query,
        [int]$WindowMinutes = 10
    )

    $window = if ($WindowMinutes -lt 1) { 1 } elseif ($WindowMinutes -gt 180) { 180 } else { $WindowMinutes }
    $mode = Get-OperatorChatRecentChangesMode -Query $Query
    $baselineTimestamp = $null
    $baselineLabel = "last $window minutes"
    if ([string]::Equals($mode, 'last_successful_completion', [System.StringComparison]::OrdinalIgnoreCase)) {
        $baselineTimestamp = Get-OperatorChatLastSuccessfulCompletionTime -ListenerActivity $ListenerActivity
        if ($null -ne $baselineTimestamp) {
            $baselineLabel = 'since the last successful completion'
        }
        else {
            $baselineTimestamp = [DateTimeOffset]::UtcNow.AddMinutes(-$window)
            $baselineLabel = "last $window minutes (no recent successful completion found)"
        }
    }
    else {
        $baselineTimestamp = [DateTimeOffset]::UtcNow.AddMinutes(-$window)
    }

    $baselineTimestampText = if ($null -ne $baselineTimestamp) { $baselineTimestamp.ToString('o') } else { '' }
    $changes = @()

    $entries = @()
    if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['recent_entries']) {
        $entries = @($ListenerActivity.recent_entries)
    }

    foreach ($entry in $entries) {
        $timestamp = if ($entry.PSObject.Properties['timestamp']) { [string]$entry.timestamp } else { '' }
        $dt = Convert-ToDateTimeOffsetOrNull -Value $timestamp
        if ($null -eq $dt -or ($null -ne $baselineTimestamp -and $dt.UtcDateTime -lt $baselineTimestamp.UtcDateTime)) {
            continue
        }
        if ([string]::Equals($mode, 'last_successful_completion', [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$entry.execution_status, 'completed', [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($dt.ToString('o'), $baselineTimestampText, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $requestId = if ($entry.PSObject.Properties['request_id']) { [string]$entry.request_id } else { '' }
        $status = if ($entry.PSObject.Properties['execution_status']) { [string]$entry.execution_status } else { 'unknown' }
        $cycle = if ($entry.PSObject.Properties['cycle_classification']) { [string]$entry.cycle_classification } else { '' }
        $changes += [pscustomobject]@{
            timestamp = $dt.ToString('o')
            summary = if ([string]::IsNullOrWhiteSpace($requestId)) { "Listener recorded $status activity." } else { "$requestId -> $status" }
            detail = if ([string]::IsNullOrWhiteSpace($cycle)) { '' } else { "cycle=$cycle" }
            source = 'listener_activity'
        }
    }

    if ($BridgeStatus -and $BridgeStatus.available -and $BridgeStatus.trigger_ack -and $BridgeStatus.trigger_ack.generated_at) {
        $dt = Convert-ToDateTimeOffsetOrNull -Value ([string]$BridgeStatus.trigger_ack.generated_at)
        if ($null -ne $dt -and ($null -eq $baselineTimestamp -or $dt.UtcDateTime -ge $baselineTimestamp.UtcDateTime)) {
            $changes += [pscustomobject]@{
                timestamp = $dt.ToString('o')
                summary = 'Bridge trigger ACK refreshed.'
                detail = "seq=$([string]$BridgeStatus.latest_ack_sequence) | type=$([string]$BridgeStatus.latest_trigger_type)"
                source = 'bridge_status'
            }
        }
    }

    if ($Maintenance -and $Maintenance.available -and $Maintenance.generated_at) {
        $dt = Convert-ToDateTimeOffsetOrNull -Value ([string]$Maintenance.generated_at)
        if ($null -ne $dt -and ($null -eq $baselineTimestamp -or $dt.UtcDateTime -ge $baselineTimestamp.UtcDateTime)) {
            $changes += [pscustomobject]@{
                timestamp = $dt.ToString('o')
                summary = 'Self-health maintenance report refreshed.'
                detail = "$([string]$Maintenance.overall_status) / $([string]$Maintenance.overall_severity)"
                source = 'self_health_maintenance'
            }
        }
    }

    return [pscustomobject]@{
        mode = $mode
        baseline_label = $baselineLabel
        baseline_timestamp = if ($null -ne $baselineTimestamp) { $baselineTimestamp.ToString('o') } else { '' }
        changes = @($changes | Sort-Object timestamp -Descending | Select-Object -First 8)
    }
}

function Get-OperatorChatProjectStatus {
    param(
        [string]$ObjectiveId,
        [string]$Intent,
        [string]$ValidationHarness = ''
    )

    $listenerOnlyIntents = @(
        'summarize_recent_changes',
        'summarize_current_objective'
    )

    if ($listenerOnlyIntents -contains [string]$Intent) {
        $validationHarnessProfile = Get-OperatorChatValidationHarnessProfile -ValidationHarness $ValidationHarness
        $listenerActivity = Get-ListenerActivity
        $recoveryWatchdog = Get-RecoveryWatchdogStatus
        $cadenceHealth = Get-CadenceHealth -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog
        $voiceAdapterStatus = Get-VoiceAdapterStatus
        $mimProposal = Get-MimProposalFromListenerRequest
        $listenerOnlyPayload = Get-ProjectStatusFromListenerOnly -ObjectiveId $ObjectiveId -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog -CadenceHealth $cadenceHealth -VoiceAdapterStatus $voiceAdapterStatus -StateWarning 'operator chat listener-only fast path' -MimProposal $mimProposal
        if ($validationHarnessProfile) {
            return Apply-OperatorChatValidationHarnessToStatus -ProjectStatus $listenerOnlyPayload -ValidationHarnessProfile $validationHarnessProfile -RequestedObjectiveId $ObjectiveId
        }
        return $listenerOnlyPayload
    }

    return Get-ProjectStatusPayload -ObjectiveId $ObjectiveId -ValidationHarness $ValidationHarness
}

function Get-OperatorChatRecommendedActions {
    param(
        $ProjectStatus,
        [string]$Intent,
        $ActiveCommitment = $null,
        $RecentCommitment = $null,
        [string]$ValidationHarness = ''
    )

    $actions = @()
    $cadence = if ($ProjectStatus) { $ProjectStatus.cadence_health } else { $null }
    $bridge = if ($ProjectStatus) { $ProjectStatus.bridge_status } else { $null }
    $maintenance = if ($ProjectStatus) { $ProjectStatus.self_health_maintenance } else { $null }
    $steady = if ($ProjectStatus) { $ProjectStatus.steady_state } else { $null }
    $listener = if ($ProjectStatus) { $ProjectStatus.listener_activity } else { $null }
    $mimProposal = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['mim_proposal']) { $ProjectStatus.mim_proposal } else { $null }
    $mimProposalConflict = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['mim_proposal_conflict']) { $ProjectStatus.mim_proposal_conflict } else { $null }
    $mimProposalArbitration = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['mim_proposal_arbitration']) { $ProjectStatus.mim_proposal_arbitration } else { $null }
    $mimProposalMergePolicy = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['mim_proposal_merge_policy']) { $ProjectStatus.mim_proposal_merge_policy } else { $null }
    $mimProposalAcknowledgment = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['mim_proposal_acknowledgment']) { $ProjectStatus.mim_proposal_acknowledgment } else { $null }
    $mimProposalClosure = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['mim_proposal_closure']) { $ProjectStatus.mim_proposal_closure } else { $null }
    $watchdog = if ($ProjectStatus) { $ProjectStatus.recovery_watchdog } else { $null }
    $commitmentObjectiveId = if ($ProjectStatus -and $ProjectStatus.marker) { [string]$ProjectStatus.marker.objective_id } else { '' }
    $resolvedActiveCommitment = $ActiveCommitment
    $resolvedRecentCommitment = $RecentCommitment
    if ($null -eq $resolvedRecentCommitment) {
        $resolvedRecentCommitment = $resolvedActiveCommitment
    }
    if ($null -eq $resolvedRecentCommitment) {
        try {
            $resolvedRecentCommitment = Get-OperatorChatLatestCommitment -ObjectiveId $commitmentObjectiveId -ProjectStatus $ProjectStatus -ValidationHarness $ValidationHarness -IncludeInactive
            if ($null -eq $resolvedActiveCommitment -and $resolvedRecentCommitment -and $resolvedRecentCommitment.PSObject.Properties['active'] -and [bool]$resolvedRecentCommitment.active) {
                $resolvedActiveCommitment = $resolvedRecentCommitment
            }
        }
        catch {
            Write-UiCrashLog ("[RECOMMENDED-ACTIONS-COMMITMENT-FALLBACK] " + $_.Exception.ToString())
        }
    }

    if ($mimProposal -and [bool]$mimProposal.available) {
        $proposalObjectiveId = if ([string]::IsNullOrWhiteSpace([string]$mimProposal.normalized_objective_id)) { [string]$mimProposal.objective_id } else { [string]$mimProposal.normalized_objective_id }
        $proposalTitle = if ([string]::IsNullOrWhiteSpace([string]$mimProposal.title)) { 'the live MIM proposal' } else { [string]$mimProposal.title }
        $proposalSummary = if ([string]::IsNullOrWhiteSpace([string]$mimProposal.scope)) { [string]$mimProposal.notes } else { [string]$mimProposal.scope }
        $proposalConflictStatus = if ($mimProposalConflict) { [string]$mimProposalConflict.status } else { '' }
        $proposalConflictDetected = [bool]($mimProposalConflict -and $mimProposalConflict.PSObject.Properties['conflict_detected'] -and $mimProposalConflict.conflict_detected)
        $proposalConflictSummary = if ($mimProposalConflict) { [string]$mimProposalConflict.summary } else { '' }
        $proposalArbitrationStatus = if ($mimProposalArbitration) { [string]$mimProposalArbitration.status } else { '' }
        $proposalArbitrationWinner = if ($mimProposalArbitration) { [string]$mimProposalArbitration.winner } else { '' }
        $proposalArbitrationSummary = if ($mimProposalArbitration) { [string]$mimProposalArbitration.summary } else { '' }
        $proposalMergePolicyStatus = if ($mimProposalMergePolicy) { [string]$mimProposalMergePolicy.status } else { '' }
        $proposalMergePolicyMode = if ($mimProposalMergePolicy) { [string]$mimProposalMergePolicy.mode } else { '' }
        $proposalMergePolicySummary = if ($mimProposalMergePolicy) { [string]$mimProposalMergePolicy.summary } else { '' }
        $proposalAcknowledgmentStatus = if ($mimProposalAcknowledgment) { [string]$mimProposalAcknowledgment.status } else { '' }
        $proposalAcknowledgmentDisposition = if ($mimProposalAcknowledgment) { [string]$mimProposalAcknowledgment.disposition } else { '' }
        $proposalAcknowledgmentSummary = if ($mimProposalAcknowledgment) { [string]$mimProposalAcknowledgment.summary } else { '' }
        $proposalClosureStatus = if ($mimProposalClosure) { [string]$mimProposalClosure.status } else { '' }
        $proposalClosureDisposition = if ($mimProposalClosure) { [string]$mimProposalClosure.disposition } else { '' }
        $proposalClosureSummary = if ($mimProposalClosure) { [string]$mimProposalClosure.summary } else { '' }
        $proposalReason = if ($proposalConflictDetected) {
            "MIM proposed $proposalTitle, but TOD sees a proposal conflict: $proposalConflictSummary"
        }
        elseif ($mimProposalArbitration -and [string]::Equals([string]$mimProposalArbitration.winner, 'shared', [System.StringComparison]::OrdinalIgnoreCase)) {
            "MIM proposed $proposalTitle, and current arbitration treats it as aligned bounded context: $proposalArbitrationSummary $proposalMergePolicySummary"
        }
        elseif ([string]::IsNullOrWhiteSpace($proposalObjectiveId)) {
            "MIM proposed $proposalTitle, so start with a bounded status refresh before TOD commits to the request posture."
        }
        else {
            "MIM proposed $proposalTitle for objective $proposalObjectiveId, so start with a bounded status refresh before TOD commits to the request posture."
        }

        if ($proposalConflictDetected -and $bridge -and $bridge.available) {
            $actions += New-OperatorChatAction -Action 'refresh-bridge-alignment-bundle' -Label 'Refresh Bridge Alignment Bundle' -Reason 'A live MIM proposal conflict is present, so refresh bridge alignment evidence before confirming TOD and MIM are pointed at the same work.' -ProposalSource 'mim' -ProposalId ([string]$mimProposal.task_id) -ProposalObjectiveId $proposalObjectiveId -ProposalPriority ([string]$mimProposal.priority) -ProposalTitle ([string]$mimProposal.title) -ProposalSummary $proposalSummary -ProposalConflictStatus $proposalConflictStatus -ProposalConflictDetected $proposalConflictDetected -ProposalConflictSummary $proposalConflictSummary -ProposalArbitrationStatus $proposalArbitrationStatus -ProposalArbitrationWinner $proposalArbitrationWinner -ProposalArbitrationSummary $proposalArbitrationSummary -ProposalMergePolicyStatus $proposalMergePolicyStatus -ProposalMergePolicyMode $proposalMergePolicyMode -ProposalMergePolicySummary $proposalMergePolicySummary -ProposalAcknowledgmentStatus $proposalAcknowledgmentStatus -ProposalAcknowledgmentDisposition $proposalAcknowledgmentDisposition -ProposalAcknowledgmentSummary $proposalAcknowledgmentSummary -ProposalClosureStatus $proposalClosureStatus -ProposalClosureDisposition $proposalClosureDisposition -ProposalClosureSummary $proposalClosureSummary
        }
        $actions += New-OperatorChatAction -Action 'refresh-project-status' -Label 'Refresh Status Snapshot' -Reason $proposalReason -ProposalSource 'mim' -ProposalId ([string]$mimProposal.task_id) -ProposalObjectiveId $proposalObjectiveId -ProposalPriority ([string]$mimProposal.priority) -ProposalTitle ([string]$mimProposal.title) -ProposalSummary $proposalSummary -ProposalConflictStatus $proposalConflictStatus -ProposalConflictDetected $proposalConflictDetected -ProposalConflictSummary $proposalConflictSummary -ProposalArbitrationStatus $proposalArbitrationStatus -ProposalArbitrationWinner $proposalArbitrationWinner -ProposalArbitrationSummary $proposalArbitrationSummary -ProposalMergePolicyStatus $proposalMergePolicyStatus -ProposalMergePolicyMode $proposalMergePolicyMode -ProposalMergePolicySummary $proposalMergePolicySummary -ProposalAcknowledgmentStatus $proposalAcknowledgmentStatus -ProposalAcknowledgmentDisposition $proposalAcknowledgmentDisposition -ProposalAcknowledgmentSummary $proposalAcknowledgmentSummary -ProposalClosureStatus $proposalClosureStatus -ProposalClosureDisposition $proposalClosureDisposition -ProposalClosureSummary $proposalClosureSummary
        $actions += New-OperatorChatAction -Action 'get-state-bus' -Label 'Refresh State Bus' -Reason 'A live MIM proposal is in scope, so inspect shared-state posture before treating it as aligned work.' -ProposalSource 'mim' -ProposalId ([string]$mimProposal.task_id) -ProposalObjectiveId $proposalObjectiveId -ProposalPriority ([string]$mimProposal.priority) -ProposalTitle ([string]$mimProposal.title) -ProposalSummary $proposalSummary -ProposalConflictStatus $proposalConflictStatus -ProposalConflictDetected $proposalConflictDetected -ProposalConflictSummary $proposalConflictSummary -ProposalArbitrationStatus $proposalArbitrationStatus -ProposalArbitrationWinner $proposalArbitrationWinner -ProposalArbitrationSummary $proposalArbitrationSummary -ProposalMergePolicyStatus $proposalMergePolicyStatus -ProposalMergePolicyMode $proposalMergePolicyMode -ProposalMergePolicySummary $proposalMergePolicySummary -ProposalAcknowledgmentStatus $proposalAcknowledgmentStatus -ProposalAcknowledgmentDisposition $proposalAcknowledgmentDisposition -ProposalAcknowledgmentSummary $proposalAcknowledgmentSummary -ProposalClosureStatus $proposalClosureStatus -ProposalClosureDisposition $proposalClosureDisposition -ProposalClosureSummary $proposalClosureSummary
        if (-not $proposalConflictDetected -and $bridge -and $bridge.available) {
            $actions += New-OperatorChatAction -Action 'refresh-bridge-alignment-bundle' -Label 'Refresh Bridge Alignment Bundle' -Reason 'A live MIM proposal is in scope, so refresh bridge alignment evidence before confirming TOD and MIM are pointed at the same work.' -ProposalSource 'mim' -ProposalId ([string]$mimProposal.task_id) -ProposalObjectiveId $proposalObjectiveId -ProposalPriority ([string]$mimProposal.priority) -ProposalTitle ([string]$mimProposal.title) -ProposalSummary $proposalSummary -ProposalConflictStatus $proposalConflictStatus -ProposalConflictDetected $proposalConflictDetected -ProposalConflictSummary $proposalConflictSummary -ProposalArbitrationStatus $proposalArbitrationStatus -ProposalArbitrationWinner $proposalArbitrationWinner -ProposalArbitrationSummary $proposalArbitrationSummary -ProposalMergePolicyStatus $proposalMergePolicyStatus -ProposalMergePolicyMode $proposalMergePolicyMode -ProposalMergePolicySummary $proposalMergePolicySummary -ProposalAcknowledgmentStatus $proposalAcknowledgmentStatus -ProposalAcknowledgmentDisposition $proposalAcknowledgmentDisposition -ProposalAcknowledgmentSummary $proposalAcknowledgmentSummary -ProposalClosureStatus $proposalClosureStatus -ProposalClosureDisposition $proposalClosureDisposition -ProposalClosureSummary $proposalClosureSummary
        }
    }

    if ($bridge -and $bridge.available -and [bool]$bridge.objective_mismatch) {
        $actions += New-OperatorChatAction -Action 'refresh-bridge-alignment-bundle' -Label 'Refresh Bridge Alignment Bundle' -Reason 'Bridge mismatch is present, so start with a bounded bundle that refreshes bridge evidence, state bus posture, and share artifacts together.'
        $actions += New-OperatorChatAction -Action 'refresh-share-links' -Label 'Refresh Share Links' -Mode 'ui_refresh_only' -Reason 'Bridge mismatch is present, so refresh the shared artifact links before deciding whether the live publisher needs intervention.'
        $actions += New-OperatorChatAction -Action 'get-state-bus' -Label 'Refresh State Bus' -Reason 'State bus refresh gives a read-only alignment snapshot for MIM vs TOD before any restart decision.'
    }

    if ($cadence -and $cadence.available -and [string]::Equals([string]$cadence.severity, 'critical', [System.StringComparison]::OrdinalIgnoreCase)) {
        $actions += New-OperatorChatAction -Action 'get-reliability' -Label 'Get Reliability' -Reason 'Cadence is critical, so pull the reliability view before choosing recovery or restart.'
        $actions += New-OperatorChatAction -Action 'get-engineering-loop-summary' -Label 'Engineering Loop Summary' -Reason 'Cadence is critical, so confirm whether engineering-loop thresholds or penalties are also contributing before escalating.'
        $actions += New-OperatorChatAction -Action 'refresh-governance-snapshot' -Label 'Refresh Governance Snapshot' -Reason 'A governance snapshot shows whether cadence is isolated or part of a broader bridge or maintenance posture issue.'
    }
    elseif ($cadence -and $cadence.available -and [string]::Equals([string]$cadence.severity, 'warning', [System.StringComparison]::OrdinalIgnoreCase)) {
        $actions += New-OperatorChatAction -Action 'quick-refresh-reliability' -Label 'Quick Refresh Reliability' -Mode 'ui_refresh_only' -Reason 'Cadence warning often clears with fresh telemetry; a safe refresh is the cheapest next check.'
        $actions += New-OperatorChatAction -Action 'get-engineering-signal' -Label 'Engineering Signal' -Reason 'Engineering signal adds trend and approval-pressure context before you treat cadence warning as an infrastructure problem.'
        $actions += New-OperatorChatAction -Action 'refresh-governance-snapshot' -Label 'Refresh Governance Snapshot' -Reason 'If cadence remains warning after a quick refresh, use a governance snapshot to check bridge and maintenance context.'
    }

    if ($maintenance -and $maintenance.available -and [string]::Equals([string]$maintenance.overall_status, 'healthy_with_fallback', [System.StringComparison]::OrdinalIgnoreCase)) {
        $actions += New-OperatorChatAction -Action 'get-state-bus' -Label 'Refresh State Bus' -Reason 'Maintenance is healthy_with_fallback, so a state-bus snapshot is the right read-only check before escalating.'
        $actions += New-OperatorChatAction -Action 'refresh-governance-snapshot' -Label 'Refresh Governance Snapshot' -Reason 'Governance snapshot confirms whether fallback remains bounded or is stacking with bridge or cadence pressure.'
        $actions += New-OperatorChatAction -Action 'get-engineering-signal' -Label 'Engineering Signal' -Reason 'Engineering signal provides trend context so maintenance fallback does not get misread as a broader delivery regression.'
    }

    if ($watchdog -and $watchdog.available -and -not [string]::Equals([string]$watchdog.state, 'healthy', [System.StringComparison]::OrdinalIgnoreCase)) {
        $actions += New-OperatorChatAction -Action 'get-reliability' -Label 'Get Reliability' -Reason 'Watchdog is not healthy, so reliability detail is the next truthful diagnostic step.'
    }

    if (@($actions).Count -eq 0) {
        if ($steady -and $steady.available -and [string]::Equals([string]$steady.status, 'ok', [System.StringComparison]::OrdinalIgnoreCase) -and $listener -and $listener.sync -and -not [bool]$listener.sync.is_mim_ahead) {
            $actions += New-OperatorChatAction -Action 'wait' -Label 'No Action Needed' -Mode 'observe_only' -Reason 'Current signals are healthy or bounded; patience is more justified than churn.'
        }
        else {
            $actions += New-OperatorChatAction -Action 'refresh-governance-snapshot' -Label 'Refresh Governance Snapshot' -Reason 'When the situation is ambiguous, refresh the bounded governance bundle before narrowing into a single subsystem.'
            $actions += New-OperatorChatAction -Action 'quick-refresh-reliability' -Label 'Quick Refresh Reliability' -Mode 'ui_refresh_only' -Reason 'When the situation is ambiguous, a fresh read-only telemetry pass is still the lowest-risk narrow check.'
        }
    }

    $unique = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($item in $actions) {
        $key = "{0}|{1}" -f [string]$item.action, [string]$item.reason
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$unique.Add($item)
        }
    }
    try {
        $historyProfiles = @{}
        $proposalOutcomeProfiles = @{}
        $scored = New-Object System.Collections.Generic.List[object]
        foreach ($item in $unique) {
            $historyKey = '{0}|{1}' -f [string]$commitmentObjectiveId, [string]$item.action
            if (-not $historyProfiles.ContainsKey($historyKey)) {
                $historyProfiles[$historyKey] = Get-OperatorChatCommitmentHistoryProfile -ObjectiveId $commitmentObjectiveId -Action ([string]$item.action) -Intent $Intent
            }
            $historyProfile = $historyProfiles[$historyKey]
            $historyScore = [int]$historyProfile.recent_fitness_score
            $ineffectivePenalty = if ($historyProfile.PSObject.Properties['ineffective_signal'] -and [bool]$historyProfile.ineffective_signal) { -6 } else { 0 }
            $feedbackProfile = Get-OperatorChatActionFeedbackProfile -ObjectiveId $commitmentObjectiveId -Action ([string]$item.action) -Intent $Intent
            $feedbackScore = [int]$feedbackProfile.score
            if (-not $proposalOutcomeProfiles.ContainsKey($historyKey)) {
                $proposalOutcomeProfiles[$historyKey] = Get-OperatorChatProposalOutcomeProfile -ObjectiveId $commitmentObjectiveId -Action ([string]$item.action) -Intent $Intent
            }
            $proposalOutcomeProfile = $proposalOutcomeProfiles[$historyKey]
            $proposalOutcomeScore = [int]$proposalOutcomeProfile.score
            $proposalArbitrationBias = 0
            $itemProposalSource = if ($item.PSObject.Properties['proposal_source']) { [string]$item.proposal_source } else { '' }
            if ($mimProposalArbitration -and [bool]$mimProposalArbitration.available) {
                if ([string]::Equals($itemProposalSource, 'mim', [System.StringComparison]::OrdinalIgnoreCase)) {
                    switch ([string]$mimProposalArbitration.winner) {
                        'shared' { $proposalArbitrationBias = 2 }
                        'tod' { $proposalArbitrationBias = -2 }
                        default { $proposalArbitrationBias = 0 }
                    }
                }
                elseif ([string]::Equals([string]$mimProposalArbitration.winner, 'tod', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $proposalArbitrationBias = 1
                }
            }
            $score = $historyScore + $feedbackScore + $proposalOutcomeScore + $proposalArbitrationBias + $ineffectivePenalty
            $reasonPrefix = ''
            if ($historyProfile.PSObject.Properties['ineffective_signal'] -and [bool]$historyProfile.ineffective_signal) {
                $reasonPrefix = 'Recent repeated abandoned outcomes mark this action pattern ineffective until bounded evidence materially changes. '
            }
            elseif ([string]::Equals([string]$historyProfile.outcome_bias, 'strong_positive', [System.StringComparison]::OrdinalIgnoreCase)) {
                $reasonPrefix = 'Repeated satisfied outcomes strongly support this action for the current decision pattern. '
            }
            elseif ([string]::Equals([string]$historyProfile.outcome_bias, 'positive', [System.StringComparison]::OrdinalIgnoreCase)) {
                $reasonPrefix = 'Recent satisfied outcomes support this action. '
            }
            elseif ([string]::Equals([string]$historyProfile.outcome_bias, 'strong_negative', [System.StringComparison]::OrdinalIgnoreCase)) {
                $reasonPrefix = 'Repeated abandoned outcomes make this action a poor fit until materially different evidence appears. '
            }
            elseif ([string]::Equals([string]$historyProfile.outcome_bias, 'negative', [System.StringComparison]::OrdinalIgnoreCase)) {
                $reasonPrefix = 'Recent abandoned outcomes make this action a weaker next choice until fresh evidence justifies it. '
            }
            if ($feedbackProfile.positive_count -gt 0 -or $feedbackProfile.negative_count -gt 0) {
                if ($feedbackProfile.score -gt 0) {
                    $reasonPrefix = 'Operator feedback is currently supportive of this action. ' + $reasonPrefix
                }
                elseif ($feedbackProfile.score -lt 0) {
                    $reasonPrefix = 'Recent operator feedback is skeptical of this action, so TOD is lowering its rank unless evidence clearly supports it. ' + $reasonPrefix
                }
            }
            if ([string]::Equals([string]$proposalOutcomeProfile.outcome_bias, 'strong_positive', [System.StringComparison]::OrdinalIgnoreCase)) {
                $reasonPrefix = 'Repeated absorbed-and-satisfied proposal outcomes strongly support this action. ' + $reasonPrefix
            }
            elseif ([string]::Equals([string]$proposalOutcomeProfile.outcome_bias, 'positive', [System.StringComparison]::OrdinalIgnoreCase)) {
                $reasonPrefix = 'Recent absorbed-and-satisfied proposal outcomes support this action. ' + $reasonPrefix
            }
            elseif ([string]::Equals([string]$proposalOutcomeProfile.outcome_bias, 'strong_negative', [System.StringComparison]::OrdinalIgnoreCase)) {
                $reasonPrefix = 'Repeated abandoned proposal outcomes make this action a poor fit unless the proposal posture materially changes. ' + $reasonPrefix
            }
            elseif ([string]::Equals([string]$proposalOutcomeProfile.outcome_bias, 'negative', [System.StringComparison]::OrdinalIgnoreCase)) {
                $reasonPrefix = 'Recent abandoned proposal outcomes weaken this action until fresh evidence justifies it again. ' + $reasonPrefix
            }

            $mergedAction = [ordered]@{}
            foreach ($property in $item.PSObject.Properties) {
                $mergedAction[$property.Name] = $property.Value
            }
            if (-not [string]::IsNullOrWhiteSpace($reasonPrefix)) {
                $mergedAction['reason'] = '{0}{1}' -f $reasonPrefix, [string]$item.reason
            }
            $mergedAction['history_summary'] = [string]$historyProfile.summary
            $mergedAction['history_same_intent_summary'] = [string]$historyProfile.same_intent_summary
            $mergedAction['history_outcome_bias'] = [string]$historyProfile.outcome_bias
            $mergedAction['history_satisfied_count'] = [int]$historyProfile.satisfied_count
            $mergedAction['history_abandoned_count'] = [int]$historyProfile.abandoned_count
            $mergedAction['history_ineffective_signal'] = if ($historyProfile.PSObject.Properties['ineffective_signal']) { [bool]$historyProfile.ineffective_signal } else { $false }
            $mergedAction['history_ineffective_basis'] = if ($historyProfile.PSObject.Properties['ineffective_basis']) { [string]$historyProfile.ineffective_basis } else { '' }
            $mergedAction['history_same_intent_satisfied_count'] = [int]$historyProfile.same_intent_satisfied_count
            $mergedAction['history_same_intent_abandoned_count'] = [int]$historyProfile.same_intent_abandoned_count
            $mergedAction['history_score'] = [int]$historyScore
            $mergedAction['ineffective_penalty'] = [int]$ineffectivePenalty
            $mergedAction['feedback_score'] = [int]$feedbackScore
            $mergedAction['proposal_outcome_score'] = [int]$proposalOutcomeScore
            $mergedAction['proposal_outcome_bias'] = [string]$proposalOutcomeProfile.outcome_bias
            $mergedAction['proposal_outcome_summary'] = [string]$proposalOutcomeProfile.summary
            $mergedAction['proposal_outcome_same_intent_summary'] = [string]$proposalOutcomeProfile.same_intent_summary
            $mergedAction['proposal_outcome_absorbed_satisfied_count'] = [int]$proposalOutcomeProfile.absorbed_satisfied_count
            $mergedAction['proposal_outcome_abandoned_count'] = [int]$proposalOutcomeProfile.abandoned_count
            $mergedAction['feedback_positive_count'] = [int]$feedbackProfile.positive_count
            $mergedAction['feedback_negative_count'] = [int]$feedbackProfile.negative_count
            $mergedAction['feedback_same_intent_positive_count'] = [int]$feedbackProfile.same_intent_positive_count
            $mergedAction['feedback_same_intent_negative_count'] = [int]$feedbackProfile.same_intent_negative_count
            $mergedAction['feedback_summary'] = [string]$feedbackProfile.summary
            $mergedAction['feedback_same_intent_summary'] = [string]$feedbackProfile.same_intent_summary
            $mergedAction['proposal_arbitration_bias'] = [int]$proposalArbitrationBias
            $mergedAction['combined_score'] = [int]$score
            $mergedAction['ranking_explanation'] = if ($mimProposalArbitration -and [bool]$mimProposalArbitration.available) { 'Ranked by terminal commitment outcomes, proposal closure outcomes, operator feedback, and the current bounded MIM vs TOD arbitration posture.' } else { 'Ranked by terminal commitment outcomes, proposal closure outcomes, and operator feedback for the same action and intent.' }
            $mergedAction['ranking_source'] = 'history_feedback_proposal'
            [void]$scored.Add([pscustomobject]$mergedAction)
        }
        $unique = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($scored | Sort-Object -Property @(@{ Expression = 'combined_score'; Descending = $true }, @{ Expression = 'history_score'; Descending = $true }, @{ Expression = 'label'; Descending = $false }))) {
            [void]$unique.Add($item)
        }
    }
    catch {
        Write-UiCrashLogDeduped -Key 'RECOMMENDED-ACTIONS-SCORING-FALLBACK' -Message ("[RECOMMENDED-ACTIONS-SCORING-FALLBACK] " + $_.Exception.ToString())
    }

    $terminalFollowupCommitment = $resolvedRecentCommitment
    try {
        $recentCommitmentPayload = Get-OperatorChatCommitmentPayload -Limit 12 -ObjectiveId $commitmentObjectiveId -ValidationHarness $ValidationHarness
        $recentIneffectiveCommitment = @($recentCommitmentPayload.entries | Where-Object {
                $_ -and
                $_.PSObject.Properties['terminal_state'] -and
                [string]::Equals([string]$_.terminal_state, 'ineffective', [System.StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1)
        if (@($recentIneffectiveCommitment).Count -gt 0) {
            $useIneffectiveCommitment = $true
            if ($resolvedActiveCommitment -and $resolvedActiveCommitment.PSObject.Properties['timestamp_utc'] -and $recentIneffectiveCommitment[0].PSObject.Properties['timestamp_utc']) {
                try {
                    $activeTimestamp = [datetime]::Parse([string]$resolvedActiveCommitment.timestamp_utc)
                    $ineffectiveTimestamp = [datetime]::Parse([string]$recentIneffectiveCommitment[0].timestamp_utc)
                    $useIneffectiveCommitment = $ineffectiveTimestamp -ge $activeTimestamp
                }
                catch {
                }
            }
            if ($useIneffectiveCommitment) {
                $terminalFollowupCommitment = $recentIneffectiveCommitment[0]
            }
        }
    }
    catch {
    }

    $terminalFollowup = if ($terminalFollowupCommitment) { Get-OperatorChatCommitmentTerminalFollowup -Commitment $terminalFollowupCommitment } else { $null }
    $preferTerminalFollowup = $terminalFollowup -and [string]::Equals([string]$terminalFollowup.state, 'ineffective', [System.StringComparison]::OrdinalIgnoreCase)

    if ($resolvedActiveCommitment -and -not [string]::IsNullOrWhiteSpace([string]$resolvedActiveCommitment.action) -and -not $preferTerminalFollowup) {
        $committedAction = [string]$resolvedActiveCommitment.action
        $filtered = New-Object System.Collections.Generic.List[object]
        foreach ($item in $unique) {
            if ([string]::Equals([string]$item.action, $committedAction, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            [void]$filtered.Add($item)
        }
        $unique = $filtered
        $reason = if ([string]::IsNullOrWhiteSpace([string]$resolvedActiveCommitment.reasoning_summary)) { 'An active operator commitment is already in place for this objective.' } else { [string]$resolvedActiveCommitment.reasoning_summary }
        $lifecycleNote = switch ([string]$resolvedActiveCommitment.lifecycle_status) {
            'expiring' { if ($null -ne $resolvedActiveCommitment.expires_in_minutes) { " The commitment expires in about $([int]$resolvedActiveCommitment.expires_in_minutes) minute$(if ([int]$resolvedActiveCommitment.expires_in_minutes -eq 1) { '' } else { 's' })." } else { ' The commitment is expiring soon.' } }
            default { '' }
        }
        $unique.Insert(0, (New-OperatorChatAction -Action $committedAction -Label ("Continue Commitment: {0}" -f [string]$resolvedActiveCommitment.action_label) -Reason ("Operator already committed to this action. {0}{1}" -f $reason, $lifecycleNote) -Mode 'observe_only'))
        if ([bool]$resolvedActiveCommitment.revalidation_required -and -not [string]::IsNullOrWhiteSpace([string]$resolvedActiveCommitment.escalation_reason)) {
            $revalidationAction = New-OperatorChatAction -Action 'refresh-project-status' -Label 'Refresh Status Snapshot' -Reason ([string]$resolvedActiveCommitment.escalation_reason)
            $unique.Insert([Math]::Min(1, $unique.Count), $revalidationAction)
        }
    }
    else {
        if ($terminalFollowup) {
            if ([string]::Equals([string]$terminalFollowup.state, 'satisfied', [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace([string]$terminalFollowup.action)) {
                try {
                    $followupHistory = Get-OperatorChatCommitmentHistoryProfile -ObjectiveId $commitmentObjectiveId -Action ([string]$terminalFollowup.action) -Intent $Intent
                    if ($followupHistory -and $followupHistory.PSObject.Properties['ineffective_signal'] -and [bool]$followupHistory.ineffective_signal) {
                        $terminalFollowup = $null
                    }
                }
                catch {
                }
            }
        }
        if ($terminalFollowup) {
            $followupAction = New-OperatorChatAction -Action ([string]$terminalFollowup.action) -Label ([string]$terminalFollowup.label) -Reason ([string]$terminalFollowup.reason)
            if ([string]::Equals([string]$terminalFollowup.state, 'ineffective', [System.StringComparison]::OrdinalIgnoreCase)) {
                $followupMerged = [ordered]@{}
                foreach ($property in $followupAction.PSObject.Properties) {
                    $followupMerged[$property.Name] = $property.Value
                }
                $followupMerged['history_ineffective_signal'] = $true
                $followupMerged['history_ineffective_basis'] = [string]$terminalFollowup.reason
                $followupMerged['ineffective_penalty'] = 0
                $followupMerged['history_summary'] = 'Recent repeated abandoned outcomes marked the previous action pattern ineffective.'
                $followupMerged['history_same_intent_summary'] = 'Recent repeated abandoned outcomes marked the previous action pattern ineffective.'
                $followupMerged['ranking_explanation'] = 'Governance refresh is favored because recent repeated abandoned outcomes marked the prior action pattern ineffective.'
                $followupAction = [pscustomobject]$followupMerged
            }
            $unique.Insert(0, $followupAction)
        }
        elseif ($resolvedRecentCommitment -and @('expired', 'evidence_changed') -contains [string]$resolvedRecentCommitment.lifecycle_status) {
        $revalidationAction = if ([string]::Equals([string]$resolvedRecentCommitment.lifecycle_status, 'evidence_changed', [System.StringComparison]::OrdinalIgnoreCase)) {
            New-OperatorChatAction -Action 'refresh-governance-snapshot' -Label 'Refresh Governance Snapshot' -Reason ("A previous commitment for {0} is no longer valid because live evidence changed. Revalidate before recommitting or switching actions." -f [string]$resolvedRecentCommitment.action_label)
        }
        else {
            New-OperatorChatAction -Action 'refresh-project-status' -Label 'Refresh Status Snapshot' -Reason ("A previous commitment for {0} expired. Refresh status before recommitting or switching actions." -f [string]$resolvedRecentCommitment.action_label)
        }
        $unique.Insert(0, $revalidationAction)
        }
    }

    $final = New-Object System.Collections.Generic.List[object]
    $finalSeen = @{}
    foreach ($item in $unique) {
        $key = [string]$item.action
        if ($finalSeen.ContainsKey($key)) {
            $existingIndex = [int]$finalSeen[$key]
            $existingItem = $final[$existingIndex]
            $existingProposalSource = if ($existingItem -and $existingItem.PSObject.Properties['proposal_source']) { [string]$existingItem.proposal_source } else { '' }
            $currentProposalSource = if ($item -and $item.PSObject.Properties['proposal_source']) { [string]$item.proposal_source } else { '' }
            $existingConflictStatus = if ($existingItem -and $existingItem.PSObject.Properties['proposal_conflict_status']) { [string]$existingItem.proposal_conflict_status } else { '' }
            $currentConflictStatus = if ($item -and $item.PSObject.Properties['proposal_conflict_status']) { [string]$item.proposal_conflict_status } else { '' }
            if (([string]::IsNullOrWhiteSpace($existingProposalSource) -and -not [string]::IsNullOrWhiteSpace($currentProposalSource)) -or
                ([string]::IsNullOrWhiteSpace($existingConflictStatus) -and -not [string]::IsNullOrWhiteSpace($currentConflictStatus))) {
                $final[$existingIndex] = $item
            }
            continue
        }
        $finalSeen[$key] = $final.Count
        [void]$final.Add($item)
    }
    return @($final | Select-Object -First 3)
}

function Get-OperatorChatGovernedActionAlternatives {
    param(
        $ProjectStatus,
        [string]$Intent,
        [string]$ExcludeAction = ''
    )

    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-OperatorChatRecommendedActions -ProjectStatus $ProjectStatus -Intent $Intent)) {
        if ($null -eq $item) {
            continue
        }
        if ([string]::Equals([string]$item.action, [string]$ExcludeAction, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if ([string]::Equals([string]$item.mode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        [void]$actions.Add($item)
    }

    foreach ($fallback in @(
            (New-OperatorChatAction -Action 'refresh-project-status' -Label 'Refresh Status Snapshot' -Reason 'Re-read the bounded status payload before choosing another action.'),
            (New-OperatorChatAction -Action 'refresh-governance-snapshot' -Label 'Refresh Governance Snapshot' -Reason 'Use the governance bundle when you need a broader bounded evidence refresh.'),
            (New-OperatorChatAction -Action 'get-state-bus' -Label 'Refresh State Bus' -Reason 'State bus refresh is the default read-only alignment check.')
        )) {
        if ([string]::Equals([string]$fallback.action, [string]$ExcludeAction, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        [void]$actions.Add($fallback)
    }

    $unique = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($item in $actions) {
        $key = [string]$item.action
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$unique.Add($item)
        }
    }

    return @($unique | Select-Object -First 3)
}

function Invoke-OperatorChatMimDialogCommand {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Arguments
    )

    if (-not (Test-Path -Path $mimDialogScriptPath)) {
        throw "MIM dialog script not found at $mimDialogScriptPath"
    }

    try {
        $invokeParams = @{}
        foreach ($key in @($Arguments.Keys)) {
            $invokeParams[[string]$key] = $Arguments[$key]
        }
        if (-not $invokeParams.ContainsKey('RemoteConnectionTimeoutMilliseconds')) {
            $invokeParams['RemoteConnectionTimeoutMilliseconds'] = $operatorChatMimRemoteConnectionTimeoutMilliseconds
        }
        $invokeParams['EmitJson'] = $true
        $raw = (& $mimDialogScriptPath @invokeParams 2>&1 | Out-String)
    }
    catch {
        throw $_.Exception
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw 'MIM dialog command returned no payload.'
    }

    try {
        return ($raw | ConvertFrom-Json)
    }
    catch {
        throw ("Unable to parse MIM dialog payload: {0}" -f $_.Exception.Message)
    }
}

function New-OperatorChatMimSessionId {
    param(
        [string]$Intent,
        [string]$ObjectiveId
    )

    $intentToken = if ([string]::IsNullOrWhiteSpace($Intent)) { 'status' } else { ([string]$Intent -replace '[^a-zA-Z0-9._-]', '-').Trim('-').ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($intentToken)) {
        $intentToken = 'status'
    }
    $objectiveToken = if ([string]::IsNullOrWhiteSpace($ObjectiveId)) { 'unscoped' } else { ([string]$ObjectiveId -replace '[^a-zA-Z0-9._-]', '-').Trim('-').ToLowerInvariant() }
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    $nonce = ([guid]::NewGuid().ToString('N')).Substring(0, 8)
    return ("tod-operator-chat-{0}-{1}-{2}-{3}" -f $intentToken, $objectiveToken, $stamp, $nonce)
}

function ConvertTo-OperatorChatSuggestedActionArray {
    param([AllowNull()]$Value)

    $items = @()
    foreach ($entry in @($Value)) {
        if ($null -eq $entry) {
            continue
        }

        if ($entry -is [string]) {
            continue
        }

        $actionName = if ($entry.PSObject.Properties['action']) { [string]$entry.action } else { '' }
        if ([string]::IsNullOrWhiteSpace($actionName)) {
            continue
        }

        $items += [pscustomobject]@{
            action = $actionName
            label = if ($entry.PSObject.Properties['label']) { [string]$entry.label } else { '' }
            reason = if ($entry.PSObject.Properties['reason']) { [string]$entry.reason } else { '' }
            mode = if ($entry.PSObject.Properties['mode']) { [string]$entry.mode } else { 'read_only' }
        }
    }

    return @($items)
}

function ConvertTo-OperatorChatCitationArray {
    param([AllowNull()]$Value)

    $items = @()
    foreach ($entry in @($Value)) {
        if ($null -eq $entry) {
            continue
        }

        $section = if ($entry.PSObject.Properties['section']) { [string]$entry.section } else { '' }
        $field = if ($entry.PSObject.Properties['field']) { [string]$entry.field } else { '' }
        if ([string]::IsNullOrWhiteSpace($section) -or [string]::IsNullOrWhiteSpace($field)) {
            continue
        }

        $items += [pscustomobject]@{
            section = $section
            field = $field
        }
    }

    return @($items)
}

function Get-OperatorChatMimPrimaryResult {
    param(
        [string]$Query,
        [string]$ResolvedIntent,
        [string]$ResolvedObjectiveId,
        [int]$WindowMinutes,
        [AllowNull()]$ProjectStatus,
        [AllowNull()]$Marker,
        [AllowNull()]$Progress,
        [AllowNull()]$Listener,
        [AllowNull()]$Bridge,
        [AllowNull()]$Maintenance,
        [AllowNull()]$Cadence,
        [AllowNull()]$Steady,
        [AllowNull()]$Watchdog,
        [string]$ValidationHarness
    )

    if (-not (Test-Path -Path $mimDialogScriptPath)) {
        return [pscustomobject]@{
            ok = $false
            error = 'mim_dialog_script_missing'
            detail = "MIM dialog script not found at $mimDialogScriptPath"
        }
    }

    $sessionId = New-OperatorChatMimSessionId -Intent $ResolvedIntent -ObjectiveId $ResolvedObjectiveId
    $taskId = if ($Listener -and $Listener.PSObject.Properties['latest_request_id']) { [string]$Listener.latest_request_id } else { '' }
    $requestSummary = if ([string]::IsNullOrWhiteSpace($Query)) {
        "TOD operator chat needs MIM-owned guidance for $ResolvedIntent."
    }
    else {
        "TOD operator chat asks MIM: $Query"
    }

    $requestPayload = [ordered]@{
        request_kind = 'operator_chat'
        primary_source = 'MIM'
        instruction = 'MIM is the primary source for updates, continued development, natural next steps, tasks, and bounded operational guidance. Reply on this session with a concise status-owned answer for TOD to render.'
        query = [string]$Query
        intent = [string]$ResolvedIntent
        objective_id = [string]$ResolvedObjectiveId
        window_minutes = [int]$WindowMinutes
        validation_harness = [string]$ValidationHarness
        project_status = [ordered]@{
            objective_id = if ($Marker -and $Marker.PSObject.Properties['objective_id']) { [string]$Marker.objective_id } else { [string]$ResolvedObjectiveId }
            objective_status = if ($Marker -and $Marker.PSObject.Properties['status']) { [string]$Marker.status } else { 'unknown' }
            progress_summary = if ($Progress -and $Progress.PSObject.Properties['summary']) { [string]$Progress.summary } else { '' }
            latest_request_id = if ($Listener -and $Listener.PSObject.Properties['latest_request_id']) { [string]$Listener.latest_request_id } else { '' }
            latest_execution_status = if ($Listener -and $Listener.PSObject.Properties['latest_execution_status']) { [string]$Listener.latest_execution_status } else { '' }
            bridge_status = if ($Bridge -and $Bridge.PSObject.Properties['status']) { [string]$Bridge.status } else { 'unknown' }
            bridge_summary = if ($Bridge -and $Bridge.PSObject.Properties['summary']) { [string]$Bridge.summary } else { '' }
            cadence_severity = if ($Cadence -and $Cadence.PSObject.Properties['severity']) { [string]$Cadence.severity } else { 'unknown' }
            steady_state = if ($Steady -and $Steady.PSObject.Properties['status']) { [string]$Steady.status } else { 'unknown' }
            maintenance_status = if ($Maintenance -and $Maintenance.PSObject.Properties['overall_status']) { [string]$Maintenance.overall_status } else { 'unknown' }
            maintenance_severity = if ($Maintenance -and $Maintenance.PSObject.Properties['overall_severity']) { [string]$Maintenance.overall_severity } else { 'unknown' }
            watchdog_state = if ($Watchdog -and $Watchdog.PSObject.Properties['state']) { [string]$Watchdog.state } else { 'unknown' }
        }
        requested_fields = @('summary', 'recommended_next_step', 'updates', 'continued_development', 'natural_next_steps', 'tasks', 'confidence', 'limitations', 'flags')
    }

    $sendResult = $null
    try {
        $sendResult = Invoke-OperatorChatMimDialogCommand -Arguments @{
            Action = 'send'
            SessionId = $sessionId
            Actor = 'TOD'
            PeerActor = 'MIM'
            MessageType = 'status_request'
            Intent = $ResolvedIntent
            TaskId = $taskId
            Summary = $requestSummary
            PayloadJson = ($requestPayload | ConvertTo-Json -Depth 14 -Compress)
            PublishRemote = $true
            RequiresReply = $true
        }
    }
    catch {
        return [pscustomobject]@{
            ok = $false
            error = 'mim_dialog_send_failed'
            detail = [string]$_.Exception.Message
            session_id = $sessionId
        }
    }

    $sendRemoteStatus = if ($sendResult -and $sendResult.PSObject.Properties['remote'] -and $sendResult.remote -and $sendResult.remote.PSObject.Properties['status']) { [string]$sendResult.remote.status } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($sendRemoteStatus) -and -not [string]::Equals($sendRemoteStatus, 'uploaded', [System.StringComparison]::OrdinalIgnoreCase)) {
        $sendRemoteError = if ($sendResult.remote.PSObject.Properties['error']) { [string]$sendResult.remote.error } else { '' }
        $sendRemoteDetail = if (-not [string]::IsNullOrWhiteSpace($sendRemoteError)) {
            "MIM primary-source handoff could not publish remotely ({0}: {1})." -f $sendRemoteStatus, $sendRemoteError
        }
        else {
            "MIM primary-source handoff could not publish remotely ({0})." -f $sendRemoteStatus
        }
        return [pscustomobject]@{
            ok = $false
            error = 'mim_dialog_remote_unavailable'
            detail = $sendRemoteDetail
            session_id = $sessionId
        }
    }

    $deadline = (Get-Date).ToUniversalTime().AddSeconds($operatorChatMimReplyTimeoutSeconds)
    $replyMessage = $null
    $lastSessionState = $null
    $pollCount = 0

    while ((Get-Date).ToUniversalTime() -lt $deadline) {
        try {
            $refreshFromRemote = ($pollCount -eq 0) -or ((Get-Date).ToUniversalTime().AddMilliseconds($operatorChatMimReplyPollIntervalMilliseconds) -ge $deadline)
            $sessionDoc = Invoke-OperatorChatMimDialogCommand -Arguments @{
                Action = 'read-session'
                SessionId = $sessionId
                RefreshFromRemote = $refreshFromRemote
                Tail = 12
            }
        }
        catch {
            return [pscustomobject]@{
                ok = $false
                error = 'mim_dialog_read_failed'
                detail = [string]$_.Exception.Message
                session_id = $sessionId
            }
        }

        $lastSessionState = if ($sessionDoc.PSObject.Properties['session_state']) { $sessionDoc.session_state } else { $null }
    $sessionRemoteStatus = if ($sessionDoc.PSObject.Properties['remote'] -and $sessionDoc.remote -and $sessionDoc.remote.PSObject.Properties['status']) { [string]$sessionDoc.remote.status } else { '' }
        $matchingReplyMessages = @($sessionDoc.messages | Where-Object {
                $_ -and
                $_.PSObject.Properties['from'] -and
                $_.PSObject.Properties['to'] -and
                [string]::Equals([string]$_.from, 'MIM', [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.to, 'TOD', [System.StringComparison]::OrdinalIgnoreCase) -and
                $_.PSObject.Properties['message_type'] -and
                @('status_reply', 'diagnostic_reply', 'handoff_response', 'resolution_notice') -contains [string]$_.message_type
            })

        if (@($matchingReplyMessages).Count -gt 0) {
            $replyMessage = @($matchingReplyMessages)[-1]
            break
        }

        if (@('remote_not_configured', 'refresh_failed') -contains $sessionRemoteStatus) {
            $sessionRemoteError = if ($sessionDoc.remote.PSObject.Properties['error']) { [string]$sessionDoc.remote.error } else { '' }
            $sessionRemoteDetail = if (-not [string]::IsNullOrWhiteSpace($sessionRemoteError)) {
                "MIM primary-source reply refresh became unavailable ({0}: {1})." -f $sessionRemoteStatus, $sessionRemoteError
            }
            else {
                "MIM primary-source reply refresh became unavailable ({0})." -f $sessionRemoteStatus
            }
            return [pscustomobject]@{
                ok = $false
                error = 'mim_dialog_remote_unavailable'
                detail = $sessionRemoteDetail
                session_id = $sessionId
                session_state = $lastSessionState
            }
        }

        $pollCount++
        Start-Sleep -Milliseconds $operatorChatMimReplyPollIntervalMilliseconds
    }

    if ($null -eq $replyMessage) {
        return [pscustomobject]@{
            ok = $false
            error = 'mim_dialog_timeout'
            detail = "MIM did not reply within $operatorChatMimReplyTimeoutSeconds seconds."
            session_id = $sessionId
            session_state = $lastSessionState
        }
    }

    $replyPayload = if ($replyMessage.PSObject.Properties['payload']) { $replyMessage.payload } else { $null }
    $summary = if ($replyPayload -and $replyPayload.PSObject.Properties['summary'] -and -not [string]::IsNullOrWhiteSpace([string]$replyPayload.summary)) {
        [string]$replyPayload.summary
    }
    elseif ($replyMessage -and $replyMessage.PSObject.Properties['summary'] -and -not [string]::IsNullOrWhiteSpace([string]$replyMessage.summary)) {
        [string]$replyMessage.summary
    }
    else {
        'MIM replied without summary text.'
    }
    $recommendedNextStep = if ($replyPayload -and $replyPayload.PSObject.Properties['recommended_next_step'] -and -not [string]::IsNullOrWhiteSpace([string]$replyPayload.recommended_next_step)) {
        [string]$replyPayload.recommended_next_step
    }
    elseif ($replyPayload -and $replyPayload.PSObject.Properties['natural_next_steps'] -and @($replyPayload.natural_next_steps).Count -gt 0) {
        [string]@($replyPayload.natural_next_steps)[0]
    }
    elseif ($replyPayload -and $replyPayload.PSObject.Properties['tasks'] -and @($replyPayload.tasks).Count -gt 0) {
        [string]@($replyPayload.tasks)[0]
    }
    else {
        'Continue with the MIM-provided guidance on this dialog session and refresh bounded TOD evidence after each material change.'
    }

    $evidence = New-Object System.Collections.Generic.List[object]
    [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Session' -Value $sessionId -Section 'dialog' -Field 'session_id'))
    [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Reply Type' -Value $(if ($replyMessage.PSObject.Properties['message_type']) { [string]$replyMessage.message_type } else { 'status_reply' }) -Section 'dialog' -Field 'message_type'))
    [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Reply Intent' -Value $(if ($replyMessage.PSObject.Properties['intent']) { [string]$replyMessage.intent } else { $ResolvedIntent }) -Section 'dialog' -Field 'intent'))

    foreach ($update in @($(if ($replyPayload -and $replyPayload.PSObject.Properties['updates']) { @($replyPayload.updates) } else { @() }) | Select-Object -First 3)) {
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Update' -Value $update -Section 'dialog' -Field 'updates'))
    }
    foreach ($task in @($(if ($replyPayload -and $replyPayload.PSObject.Properties['tasks']) { @($replyPayload.tasks) } else { @() }) | Select-Object -First 3)) {
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Task' -Value $task -Section 'dialog' -Field 'tasks'))
    }
    foreach ($developmentItem in @($(if ($replyPayload -and $replyPayload.PSObject.Properties['continued_development']) { @($replyPayload.continued_development) } else { @() }) | Select-Object -First 2)) {
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'Continued Development' -Value $developmentItem -Section 'dialog' -Field 'continued_development'))
    }

    $limitations = @()
    if ($replyPayload -and $replyPayload.PSObject.Properties['limitations']) {
        $limitations = @(Convert-ToStringArray -Value $replyPayload.limitations)
    }

    $result = [pscustomobject]@{
        ok = $true
        query = [string]$Query
        intent = $ResolvedIntent
        objective_id = if ($Marker -and $Marker.PSObject.Properties['objective_id']) { [string]$Marker.objective_id } else { [string]$ResolvedObjectiveId }
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        validation_harness = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties['validation_harness']) { $ProjectStatus.validation_harness } else { $null }
        source = 'mim_dialog'
        source_label = 'MIM via TOD'
        dialog_session_id = $sessionId
        dialog_message_type = if ($replyMessage.PSObject.Properties['message_type']) { [string]$replyMessage.message_type } else { 'status_reply' }
        capabilities = Get-OperatorChatCapabilities
        response = [pscustomobject]@{
            summary = $summary
            evidence = @($evidence | Select-Object -First 8)
            recommended_next_step = $recommendedNextStep
            suggested_actions = @(ConvertTo-OperatorChatSuggestedActionArray -Value $(if ($replyPayload -and $replyPayload.PSObject.Properties['suggested_actions']) { $replyPayload.suggested_actions } else { @() }))
            confidence = if ($replyPayload -and $replyPayload.PSObject.Properties['confidence']) { [string]$replyPayload.confidence } else { 'medium' }
            flags = @(@('mim_primary_response') + @(Convert-ToStringArray -Value $(if ($replyPayload -and $replyPayload.PSObject.Properties['flags']) { $replyPayload.flags } else { @() })) | Select-Object -Unique)
            limitations = @($limitations)
            citations = @(ConvertTo-OperatorChatCitationArray -Value $(if ($replyPayload -and $replyPayload.PSObject.Properties['citations']) { $replyPayload.citations } else { @() }))
        }
    }

    return [pscustomobject]@{
        ok = $true
        result = $result
        session_id = $sessionId
    }
}

function Invoke-OperatorChatQuery {
    param(
        [string]$Query,
        [string]$Intent,
        [string]$ObjectiveId,
        [int]$WindowMinutes = 10,
        [string]$ValidationHarness = ''
    )

    $resolvedObjectiveId = if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) { [string]$ObjectiveId } else { Get-OperatorChatObjectiveIdFromQuery -Query $Query }
    $resolvedIntent = Resolve-OperatorChatIntent -Query $Query -Intent $Intent
    $projectStatus = Get-OperatorChatProjectStatus -ObjectiveId $resolvedObjectiveId -Intent $resolvedIntent -ValidationHarness $ValidationHarness
    $marker = if ($projectStatus) { $projectStatus.marker } else { $null }
    $progress = if ($projectStatus) { $projectStatus.progress } else { $null }
    $listener = if ($projectStatus) { $projectStatus.listener_activity } else { $null }
    $bridge = if ($projectStatus) { $projectStatus.bridge_status } else { $null }
    $maintenance = if ($projectStatus) { $projectStatus.self_health_maintenance } else { $null }
    $cadence = if ($projectStatus) { $projectStatus.cadence_health } else { $null }
    $steady = if ($projectStatus) { $projectStatus.steady_state } else { $null }
    $watchdog = if ($projectStatus) { $projectStatus.recovery_watchdog } else { $null }
    $mimProposal = if ($projectStatus -and $projectStatus.PSObject.Properties['mim_proposal']) { $projectStatus.mim_proposal } else { $null }
    $mimProposalConflict = if ($projectStatus -and $projectStatus.PSObject.Properties['mim_proposal_conflict']) { $projectStatus.mim_proposal_conflict } else { $null }
    $mimProposalArbitration = if ($projectStatus -and $projectStatus.PSObject.Properties['mim_proposal_arbitration']) { $projectStatus.mim_proposal_arbitration } else { $null }
    $mimProposalMergePolicy = if ($projectStatus -and $projectStatus.PSObject.Properties['mim_proposal_merge_policy']) { $projectStatus.mim_proposal_merge_policy } else { $null }
    $mimProposalClosure = if ($projectStatus -and $projectStatus.PSObject.Properties['mim_proposal_closure']) { $projectStatus.mim_proposal_closure } else { $null }
    $evidence = New-Object System.Collections.Generic.List[object]
    $limitations = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]
    $suggestedActions = @()
    $summary = ''
    $nextStep = ''
    $confidence = 'medium'
    $resolvedValidationHarness = if ($projectStatus -and $projectStatus.PSObject.Properties['validation_harness'] -and $projectStatus.validation_harness -and $projectStatus.validation_harness.PSObject.Properties['name']) { [string]$projectStatus.validation_harness.name } else { '' }
    $commitmentContext = $null
    $commitmentContextEnabled = $false
    if ($commitmentContextEnabled) {
        try {
            $commitmentContext = Get-OperatorChatLatestCommitment -ObjectiveId $resolvedObjectiveId -ProjectStatus $projectStatus -ValidationHarness $resolvedValidationHarness -IncludeInactive
        }
        catch {
            Write-UiCrashLog ("[OPERATOR-CHAT-COMMITMENT-FALLBACK] " + $_.Exception.ToString())
        }
    }
    $activeCommitment = if ($commitmentContext -and $commitmentContext.PSObject.Properties['active'] -and [bool]$commitmentContext.active) { $commitmentContext } else { $null }

    if ($projectStatus -and $projectStatus.data_sources -and [string]::Equals([string]$projectStatus.data_sources.project_status_mode, 'listener_telemetry_fallback', [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$limitations.Add('Dashboard is operating in listener_telemetry_fallback mode because full state.json is too large or unavailable.')
        [void]$flags.Add('listener_telemetry_fallback')
    }

    if ([string]::IsNullOrWhiteSpace($resolvedValidationHarness)) {
        $mimPrimaryAttempt = Get-OperatorChatMimPrimaryResult -Query $Query -ResolvedIntent $resolvedIntent -ResolvedObjectiveId $resolvedObjectiveId -WindowMinutes $WindowMinutes -ProjectStatus $projectStatus -Marker $marker -Progress $progress -Listener $listener -Bridge $bridge -Maintenance $maintenance -Cadence $cadence -Steady $steady -Watchdog $watchdog -ValidationHarness $resolvedValidationHarness
        if ($mimPrimaryAttempt -and $mimPrimaryAttempt.PSObject.Properties['ok'] -and [bool]$mimPrimaryAttempt.ok -and $mimPrimaryAttempt.PSObject.Properties['result']) {
            Register-OperatorChatQueryCacheEntry -Query $Query -Intent $resolvedIntent -ObjectiveId $resolvedObjectiveId -WindowMinutes $WindowMinutes -ValidationHarness $resolvedValidationHarness -Result $mimPrimaryAttempt.result
            return $mimPrimaryAttempt.result
        }
        if ($mimPrimaryAttempt -and $mimPrimaryAttempt.PSObject.Properties['detail'] -and -not [string]::IsNullOrWhiteSpace([string]$mimPrimaryAttempt.detail)) {
            [void]$limitations.Add(("MIM primary-source path unavailable; TOD used bounded local fallback. {0}" -f [string]$mimPrimaryAttempt.detail))
            [void]$flags.Add('mim_primary_fallback')
        }
        elseif ($mimPrimaryAttempt -and $mimPrimaryAttempt.PSObject.Properties['error']) {
            [void]$limitations.Add('MIM primary-source path unavailable; TOD used bounded local fallback.')
            [void]$flags.Add('mim_primary_fallback')
        }
    }

    if ($activeCommitment) {
        $commitmentMessage = switch ([string]$activeCommitment.state) {
            'timeboxed' { if ($null -ne $activeCommitment.expires_in_minutes) { "Active timeboxed operator commitment: $([string]$activeCommitment.action_label). TOD will honor it first, but it expires in about $([int]$activeCommitment.expires_in_minutes) minute$(if ([int]$activeCommitment.expires_in_minutes -eq 1) { '' } else { 's' })." } else { "Active timeboxed operator commitment: $([string]$activeCommitment.action_label). TOD will honor it before switching actions." } }
            'until_evidence_change' { "Active evidence-bound operator commitment: $([string]$activeCommitment.action_label). TOD will honor it unless live evidence changes materially." }
            default { "Active operator commitment: $([string]$activeCommitment.action_label). TOD will bias recommendations toward honoring or explicitly clearing that commitment before switching actions." }
        }
        [void]$limitations.Add($commitmentMessage)
        [void]$flags.Add('active_operator_commitment')
        if ([string]::Equals([string]$activeCommitment.lifecycle_status, 'expiring', [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$flags.Add('operator_commitment_expiring')
        }
    }
    elseif ($commitmentContext -and [bool]$commitmentContext.revalidation_required) {
        [void]$limitations.Add(("Latest operator commitment for {0} now requires revalidation. {1}" -f [string]$commitmentContext.action_label, [string]$commitmentContext.lifecycle_detail))
        [void]$flags.Add('operator_commitment_revalidation')
    }
    elseif ($commitmentContext) {
        $terminalFollowup = Get-OperatorChatCommitmentTerminalFollowup -Commitment $commitmentContext
        if ($terminalFollowup) {
            [void]$limitations.Add([string]$terminalFollowup.message)
            [void]$flags.Add('operator_commitment_terminal')
            if (-not [string]::Equals([string]$terminalFollowup.flag, 'operator_commitment_terminal', [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$flags.Add([string]$terminalFollowup.flag)
            }
        }
    }

    switch ($resolvedIntent) {
        'explain_cadence' {
            $severity = if ($cadence -and $cadence.available) { [string]$cadence.severity } else { 'unknown' }
            $adjustedSeverity = if ($cadence -and $cadence.governance -and $cadence.governance.PSObject.Properties['adjusted_severity']) { [string]$cadence.governance.adjusted_severity } else { $severity }
            $idle = if ($cadence -and $cadence.stream) { $cadence.stream.loop_idle_sec } else { $null }
            $p95 = if ($cadence -and $cadence.cadence) { $cadence.cadence.p95_sec } else { $null }
            $retryRate = if ($cadence -and $cadence.cadence) { [math]::Round((([double]$cadence.cadence.retry_rate) * 100), 0) } else { $null }
            $governanceDetail = if ($adjustedSeverity -ne $severity) { "; governance currently treats it as $adjustedSeverity after noise suppression" } else { '' }
            $summary = if ($cadence -and $cadence.available) {
                "Cadence is $severity because loop idle, retry rate, and cycle latency are outside the healthy band$governanceDetail."
            } else {
                'Cadence telemetry is unavailable, so the console cannot explain the current cadence posture yet.'
            }
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Cadence Severity' -Value $severity -Section 'cadence_health' -Field 'severity'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Governance Severity' -Value $adjustedSeverity -Section 'cadence_health' -Field 'governance.adjusted_severity'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Loop Idle Seconds' -Value $idle -Section 'cadence_health' -Field 'stream.loop_idle_sec'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'p95 Cycle Seconds' -Value $p95 -Section 'cadence_health' -Field 'cadence.p95_sec'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Retry Rate' -Value $(if ($null -ne $retryRate) { "$retryRate%" } else { '-' }) -Section 'cadence_health' -Field 'cadence.retry_rate'))
            $nextStep = 'If cadence stays warning or critical after a safe telemetry refresh, compare reliability with watchdog state before considering any restart.'
            $confidence = if ($cadence -and $cadence.available) { 'high' } else { 'low' }
            if ($activeCommitment) {
                $summary = "{0} Active operator commitment remains the first-order constraint: {1}." -f $summary, [string]$activeCommitment.action_label
                $nextStep = if ([bool]$activeCommitment.revalidation_required) {
                    'Refresh bounded status first because the commitment now requires revalidation before any cadence-driven pivot.'
                }
                else {
                    'Honor the active operator commitment first; only pivot on cadence if fresh evidence invalidates that commitment.'
                }
            }
            elseif ($commitmentContext -and [string]::Equals([string]$commitmentContext.lifecycle_status, 'evidence_changed', [System.StringComparison]::OrdinalIgnoreCase)) {
                $summary = "{0} A recent evidence-bound commitment is no longer valid because the evidence posture changed." -f $summary
                $nextStep = 'Refresh governance snapshot before following cadence pressure because the prior commitment evidence changed underneath TOD.'
            }
        }
        'explain_bridge_status' {
            $summary = if ($bridge -and $bridge.available) {
                if ([bool]$bridge.objective_mismatch -and -not [string]::IsNullOrWhiteSpace([string]$bridge.objective_mismatch_detail)) {
                    "{0} Observe first with read-only refreshes before publisher intervention. {1}" -f [string]$bridge.summary, [string]$bridge.objective_mismatch_detail
                }
                elseif ([bool]$bridge.objective_mismatch) {
                    "{0} Observe first with read-only refreshes before publisher intervention." -f [string]$bridge.summary
                }
                else {
                    [string]$bridge.summary
                }
            } else {
                'Bridge status is unavailable, so the console cannot currently explain MIM/TOD alignment.'
            }
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Bridge Health' -Value $(if ($bridge) { $bridge.status } else { 'unknown' }) -Section 'bridge_status' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Canonical MIM Objective' -Value $(if ($bridge) { $bridge.canonical_mim_objective_id } else { '' }) -Section 'bridge_status' -Field 'canonical_mim_objective_id'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Live Task Objective' -Value $(if ($bridge) { $bridge.task_request_objective_id } else { '' }) -Section 'bridge_status' -Field 'task_request_objective_id'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Objective Mismatch' -Value $(if ($bridge) { $bridge.objective_mismatch } else { $null }) -Section 'bridge_status' -Field 'objective_mismatch'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Mismatch Detail' -Value $(if ($bridge) { $bridge.objective_mismatch_detail } else { '' }) -Section 'bridge_status' -Field 'objective_mismatch_detail'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Bridge Status Reason' -Value $(if ($bridge) { $bridge.status_reason } else { '' }) -Section 'bridge_status' -Field 'status_reason'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Listener Heartbeat Age' -Value $(if ($bridge) { $bridge.listener_cycle_age_seconds } else { $null }) -Section 'bridge_status' -Field 'listener_cycle_age_seconds'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Listener Freshness State' -Value $(if ($bridge) { $bridge.listener_freshness_state } else { '' }) -Section 'bridge_status' -Field 'listener_freshness_state'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Listener Freshness Threshold' -Value $(if ($bridge) { $bridge.listener_fresh_threshold_seconds } else { $null }) -Section 'bridge_status' -Field 'listener_fresh_threshold_seconds'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Bridge Sequence State' -Value $(if ($bridge) { $bridge.sequence_state } else { '' }) -Section 'bridge_status' -Field 'sequence_state'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Bridge Artifact Completeness' -Value $(if ($bridge) { $bridge.artifact_completeness } else { '' }) -Section 'bridge_status' -Field 'artifact_completeness'))
            if ($bridge -and $bridge.available -and [bool]$bridge.objective_mismatch) {
                [void]$flags.Add('observe_before_act')
                $nextStep = 'Observe first: refresh share links and state bus, then only consider publisher intervention if the mismatch persists.'
            }
            else {
                $nextStep = 'Use the bridge explanation together with a read-only state-bus or share-link refresh before deciding on publisher intervention.'
            }
            $confidence = if ($bridge -and $bridge.available) { 'high' } else { 'low' }
        }
        'explain_maintenance' {
            $summary = if ($maintenance -and $maintenance.available) {
                $maintenanceStatus = if ($maintenance.PSObject.Properties['overall_status']) { [string]$maintenance.overall_status } else { 'unknown' }
                $maintenanceSeverity = if ($maintenance.PSObject.Properties['overall_severity']) { [string]$maintenance.overall_severity } else { 'unknown' }
                $maintenanceReason = if ($maintenance.PSObject.Properties['severity_reason']) { [string]$maintenance.severity_reason } else { 'unknown reason' }
                $maintenancePostflight = if ($maintenance.PSObject.Properties['postflight']) { $maintenance.postflight } else { $null }
                $maintenanceSummary = "Maintenance is $maintenanceStatus with operational severity $maintenanceSeverity because $maintenanceReason."
                $blockCount = if ($maintenancePostflight -and $maintenancePostflight.PSObject.Properties['block_count']) { [int]$maintenancePostflight.block_count } else { 0 }
                $watchdogSuffix = ''
                if ($watchdog -and -not [string]::IsNullOrWhiteSpace([string]$watchdog.state) -and -not [string]::Equals([string]$watchdog.state, 'healthy', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $watchdogSummary = if ($watchdog.PSObject.Properties['last_issue_detail'] -and -not [string]::IsNullOrWhiteSpace([string]$watchdog.last_issue_detail)) {
                        [string]$watchdog.last_issue_detail
                    }
                    elseif ($watchdog.PSObject.Properties['last_issue'] -and -not [string]::IsNullOrWhiteSpace([string]$watchdog.last_issue)) {
                        [string]$watchdog.last_issue
                    }
                    else {
                        'watchdog is not healthy'
                    }
                    $watchdogSuffix = " Recovery watchdog is $([string]$watchdog.state): $watchdogSummary."
                }
                $blockSuffix = if ($blockCount -gt 0) {
                    " Active blockers remaining: $blockCount."
                } else {
                    ''
                }
                "$maintenanceSummary$blockSuffix$watchdogSuffix"
            } else {
                'Maintenance report is unavailable, so the console cannot explain the current fallback posture.'
            }
            $maintenancePostflight = if ($maintenance -and $maintenance.PSObject.Properties['postflight']) { $maintenance.postflight } else { $null }
            $maintenanceHistory = if ($maintenance -and $maintenance.PSObject.Properties['history']) { $maintenance.history } else { $null }
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Maintenance Status' -Value $(if ($maintenance -and $maintenance.PSObject.Properties['overall_status']) { $maintenance.overall_status } else { 'unknown' }) -Section 'self_health_maintenance' -Field 'overall_status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Operational Severity' -Value $(if ($maintenance -and $maintenance.PSObject.Properties['overall_severity']) { $maintenance.overall_severity } else { 'unknown' }) -Section 'self_health_maintenance' -Field 'overall_severity'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Source Severity' -Value $(if ($maintenance -and $maintenance.PSObject.Properties['source_severity']) { $maintenance.source_severity } else { 'unknown' }) -Section 'self_health_maintenance' -Field 'source_severity'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Reason' -Value $(if ($maintenance -and $maintenance.PSObject.Properties['severity_reason']) { $maintenance.severity_reason } else { 'unknown' }) -Section 'self_health_maintenance' -Field 'severity_reason'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Block Count' -Value $(if ($maintenancePostflight -and $maintenancePostflight.PSObject.Properties['block_count']) { $maintenancePostflight.block_count } else { $null }) -Section 'self_health_maintenance' -Field 'postflight.block_count'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Invocation Mode' -Value $(if ($maintenance -and $maintenance.PSObject.Properties['invocation_mode']) { $maintenance.invocation_mode } else { 'unknown' }) -Section 'self_health_maintenance' -Field 'invocation_mode'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Scheduled Fallback Count' -Value $(if ($maintenanceHistory) { "{0}/{1}" -f $maintenanceHistory.scheduled_fallback_runs_including_current, $maintenanceHistory.threshold_runs } else { '-' }) -Section 'self_health_maintenance' -Field 'history.scheduled_fallback_runs_including_current'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Threshold Window' -Value $(if ($maintenanceHistory) { "{0}h" -f $maintenanceHistory.window_hours } else { '-' }) -Section 'self_health_maintenance' -Field 'history.window_hours'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Last Report' -Value $(if ($maintenance -and $maintenance.PSObject.Properties['generated_at']) { $maintenance.generated_at } else { '' }) -Section 'self_health_maintenance' -Field 'generated_at'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Watchdog State' -Value $(if ($watchdog -and $watchdog.PSObject.Properties['state']) { $watchdog.state } else { 'unknown' }) -Section 'recovery_watchdog' -Field 'state'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Watchdog Issue' -Value $(if ($watchdog -and $watchdog.PSObject.Properties['last_issue_detail']) { $watchdog.last_issue_detail } else { '' }) -Section 'recovery_watchdog' -Field 'last_issue_detail'))
            $nextStep = 'If fallback remains bounded and below threshold, observe or refresh state bus; escalation is justified only when the persistence threshold or other health signals worsen.'
            $confidence = if ($maintenance -and $maintenance.available) { 'high' } else { 'low' }
        }
        'suggest_next_action' {
            try {
                $suggestedActions = Get-OperatorChatRecommendedActions -ProjectStatus $projectStatus -Intent $resolvedIntent -ActiveCommitment $activeCommitment -RecentCommitment $commitmentContext -ValidationHarness $resolvedValidationHarness
            }
            catch {
                Write-UiCrashLog ("[SUGGEST-NEXT-ACTION-ERROR] " + $_.Exception.ToString())
                throw
            }
            $firstAction = if (@($suggestedActions).Count -gt 0) { $suggestedActions[0] } else { $null }
            if ($firstAction -and $firstAction.PSObject.Properties['history_ineffective_signal'] -and [bool]$firstAction.history_ineffective_signal) {
                [void]$flags.Add('operator_commitment_terminal')
                [void]$flags.Add('operator_commitment_ineffective')
                if ($firstAction.PSObject.Properties['history_ineffective_basis'] -and -not [string]::IsNullOrWhiteSpace([string]$firstAction.history_ineffective_basis)) {
                    [void]$limitations.Add([string]$firstAction.history_ineffective_basis)
                }
            }
            $summary = if ($firstAction) {
                "The next bounded step is $([string]$firstAction.label) because $([string]$firstAction.reason)"
            } else {
                'No strong next action recommendation is available from current telemetry.'
            }
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Steady State' -Value $(if ($steady) { $steady.status } else { 'unknown' }) -Section 'steady_state' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Watchdog State' -Value $(if ($watchdog) { $watchdog.state } else { 'unknown' }) -Section 'recovery_watchdog' -Field 'state'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Bridge Health' -Value $(if ($bridge) { $bridge.status } else { 'unknown' }) -Section 'bridge_status' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Cadence Severity' -Value $(if ($cadence) { $cadence.severity } else { 'unknown' }) -Section 'cadence_health' -Field 'severity'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Maintenance Status' -Value $(if ($maintenance) { $maintenance.overall_status } else { 'unknown' }) -Section 'self_health_maintenance' -Field 'overall_status'))
            $nextStep = if ($firstAction) { [string]$firstAction.label } else { 'Observe current state and refresh telemetry if it becomes stale.' }
            $confidence = 'medium'
        }
        'summarize_current_objective' {
            $summary = if ($marker) {
                "Objective $([string]$marker.objective_id) is currently $([string]$marker.status). $([string]$progress.summary)"
            } else {
                'No current objective marker is available.'
            }
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Objective' -Value $(if ($marker) { $marker.objective_id } else { '' }) -Section 'marker' -Field 'objective_id'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Objective Status' -Value $(if ($marker) { $marker.status } else { 'unknown' }) -Section 'marker' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Objective Title' -Value $(if ($marker) { $marker.title } else { '' }) -Section 'marker' -Field 'title'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Progress' -Value $(if ($progress) { "$([string]$progress.percent)%" } else { '-' }) -Section 'progress' -Field 'percent'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Latest Request' -Value $(if ($listener) { $listener.latest_request_id } else { '' }) -Section 'listener_activity' -Field 'latest_request_id'))
            $nextStep = 'Use the objective summary to decide whether you need explanation of cadence, bridge status, or warning posture next.'
            $confidence = if ($marker) { 'high' } else { 'low' }
        }
        'summarize_recent_changes' {
            $recentChangeSet = Get-OperatorChatRecentChanges -ListenerActivity $listener -BridgeStatus $bridge -Maintenance $maintenance -Query $Query -WindowMinutes $WindowMinutes
            $changes = if ($recentChangeSet -and $recentChangeSet.PSObject.Properties['changes']) { @($recentChangeSet.changes) } else { @() }
            $baselineLabel = if ($recentChangeSet -and $recentChangeSet.PSObject.Properties['baseline_label']) { [string]$recentChangeSet.baseline_label } else { "last $WindowMinutes minutes" }
            $usedCompletionFallback = $baselineLabel -like '*no recent successful completion found*'
            if (@($changes).Count -gt 0) {
                $summary = "The main changes $baselineLabel were the latest listener events plus any fresh bridge ACK or maintenance report updates."
                foreach ($change in $changes) {
                    $text = if ([string]::IsNullOrWhiteSpace([string]$change.detail)) { [string]$change.summary } else { "{0} ({1})" -f [string]$change.summary, [string]$change.detail }
                    [void]$evidence.Add((New-OperatorChatEvidence -Label ([string]$change.source) -Value $text -Section ([string]$change.source) -Field 'summary'))
                }
                $confidence = 'medium'
            } else {
                $summary = "No material listener, bridge, or maintenance changes were recorded $baselineLabel."
                $confidence = 'low'
                [void]$limitations.Add('Recent change detection only covers listener entries, bridge ACK freshness, and maintenance report updates surfaced by the UI.')
            }
            if ($usedCompletionFallback) {
                [void]$limitations.Add('No recent successful completion was found in scoped listener history, so the answer fell back to a bounded recent-time window.')
                [void]$flags.Add('recent_completion_baseline_fallback')
            }
            $nextStep = 'If you expected movement but recent changes are empty, refresh telemetry and check whether the listener is stale or idle.'
        }
        'explain_warning' {
            if ($bridge -and $bridge.available -and [string]::Equals([string]$bridge.status, 'warning', [System.StringComparison]::OrdinalIgnoreCase)) {
                $summary = "The most concrete warning source is bridge status: $([string]$bridge.summary)"
            }
            elseif ($cadence -and $cadence.available -and -not [string]::Equals([string]$cadence.severity, 'ok', [System.StringComparison]::OrdinalIgnoreCase)) {
                $summary = "The active warning source is cadence: severity is $([string]$cadence.severity), so TOD is moving slower or less cleanly than the healthy band."
            }
            elseif ($steady -and $steady.available -and -not [string]::Equals([string]$steady.status, 'ok', [System.StringComparison]::OrdinalIgnoreCase)) {
                $summary = "The warning posture is coming from steady-state health: $([string]$steady.summary)"
            }
            elseif ($maintenance -and $maintenance.available -and -not [string]::Equals([string]$maintenance.overall_severity, 'info', [System.StringComparison]::OrdinalIgnoreCase)) {
                $summary = "Maintenance is contributing to the warning posture because it is $([string]$maintenance.overall_status) with severity $([string]$maintenance.overall_severity)."
            }
            else {
                $summary = 'There is no single dominant warning signal in the current snapshot; the console is seeing either healthy or bounded fallback conditions.'
            }
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Bridge Health' -Value $(if ($bridge) { $bridge.status } else { 'unknown' }) -Section 'bridge_status' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Cadence Severity' -Value $(if ($cadence) { $cadence.severity } else { 'unknown' }) -Section 'cadence_health' -Field 'severity'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Steady State' -Value $(if ($steady) { $steady.status } else { 'unknown' }) -Section 'steady_state' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Maintenance Severity' -Value $(if ($maintenance) { $maintenance.overall_severity } else { 'unknown' }) -Section 'self_health_maintenance' -Field 'overall_severity'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Watchdog State' -Value $(if ($watchdog) { $watchdog.state } else { 'unknown' }) -Section 'recovery_watchdog' -Field 'state'))
            $nextStep = 'Follow the strongest concrete warning source first; bridge mismatch beats generic cadence concern, and failed reliability beats both.'
            $confidence = 'medium'
            if ($activeCommitment) {
                $summary = "{0} An active operator commitment to {1} currently outranks opportunistic switching." -f $summary, [string]$activeCommitment.action_label
                $nextStep = if ([bool]$activeCommitment.revalidation_required) {
                    'Refresh bounded status first because the active commitment now requires revalidation before acting on the warning.'
                }
                else {
                    'Honor or explicitly clear the active commitment before switching to a different warning response.'
                }
            }
            elseif ($commitmentContext -and [bool]$commitmentContext.revalidation_required) {
                $summary = "{0} The last operator commitment also needs revalidation before TOD should pivot." -f $summary
                $nextStep = 'Revalidate the last commitment with a bounded refresh before you switch warning-handling actions.'
            }
        }
        default {
            $summary = "TOD is currently $([string]$steady.status) in steady-state terms, cadence is $([string]$cadence.severity), bridge is $([string]$bridge.status), and maintenance is $([string]$maintenance.overall_status)."
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Objective' -Value $(if ($marker) { $marker.objective_id } else { '' }) -Section 'marker' -Field 'objective_id'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Objective Status' -Value $(if ($marker) { $marker.status } else { 'unknown' }) -Section 'marker' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Steady State' -Value $(if ($steady) { $steady.status } else { 'unknown' }) -Section 'steady_state' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Cadence Severity' -Value $(if ($cadence) { $cadence.severity } else { 'unknown' }) -Section 'cadence_health' -Field 'severity'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Bridge Health' -Value $(if ($bridge) { $bridge.status } else { 'unknown' }) -Section 'bridge_status' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Maintenance Status' -Value $(if ($maintenance) { $maintenance.overall_status } else { 'unknown' }) -Section 'self_health_maintenance' -Field 'overall_status'))
            $nextStep = 'Ask for a specific explanation if you need bridge, cadence, maintenance, or recent-change detail.'
            $confidence = 'medium'
        }
    }

    if ($mimProposal -and [bool]$mimProposal.available) {
        $proposalObjectiveId = if ([string]::IsNullOrWhiteSpace([string]$mimProposal.normalized_objective_id)) { [string]$mimProposal.objective_id } else { [string]$mimProposal.normalized_objective_id }
        [void]$flags.Add('mim_proposal_ingested')
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Task' -Value ([string]$mimProposal.task_id) -Section 'mim_proposal' -Field 'task_id'))
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Title' -Value ([string]$mimProposal.title) -Section 'mim_proposal' -Field 'title'))
        if (-not [string]::IsNullOrWhiteSpace($proposalObjectiveId)) {
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Objective' -Value $proposalObjectiveId -Section 'mim_proposal' -Field 'objective_id'))
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$mimProposal.priority)) {
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Priority' -Value ([string]$mimProposal.priority) -Section 'mim_proposal' -Field 'priority'))
        }
        if ($mimProposalConflict -and [bool]$mimProposalConflict.available) {
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Conflict Status' -Value ([string]$mimProposalConflict.status) -Section 'mim_proposal_conflict' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Conflict Summary' -Value ([string]$mimProposalConflict.summary) -Section 'mim_proposal_conflict' -Field 'summary'))
            if ([bool]$mimProposalConflict.conflict_detected) {
                [void]$flags.Add('mim_proposal_conflict_detected')
            }
        }
        if ($mimProposalArbitration -and [bool]$mimProposalArbitration.available) {
            [void]$flags.Add('mim_proposal_arbitrated')
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Arbitration Status' -Value ([string]$mimProposalArbitration.status) -Section 'mim_proposal_arbitration' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Arbitration Winner' -Value ([string]$mimProposalArbitration.winner) -Section 'mim_proposal_arbitration' -Field 'winner'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Arbitration Summary' -Value ([string]$mimProposalArbitration.summary) -Section 'mim_proposal_arbitration' -Field 'summary'))
            if ([string]::Equals([string]$mimProposalArbitration.winner, 'tod', [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$flags.Add('mim_proposal_tod_priority')
            }
            elseif ([string]::Equals([string]$mimProposalArbitration.winner, 'shared', [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$flags.Add('mim_proposal_shared_priority')
            }
        }
        if ($mimProposalMergePolicy -and [bool]$mimProposalMergePolicy.available) {
            [void]$flags.Add('mim_proposal_merge_policy_available')
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Merge Policy Status' -Value ([string]$mimProposalMergePolicy.status) -Section 'mim_proposal_merge_policy' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Merge Policy Mode' -Value ([string]$mimProposalMergePolicy.mode) -Section 'mim_proposal_merge_policy' -Field 'mode'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Merge Policy Summary' -Value ([string]$mimProposalMergePolicy.summary) -Section 'mim_proposal_merge_policy' -Field 'summary'))
            if ([string]::Equals([string]$mimProposalMergePolicy.status, 'merge_ready', [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$flags.Add('mim_proposal_merge_ready')
            }
            elseif ([string]::Equals([string]$mimProposalMergePolicy.status, 'merge_deferred', [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$flags.Add('mim_proposal_merge_deferred')
            }
        }
        if ($projectStatus -and $projectStatus.PSObject.Properties['mim_proposal_acknowledgment'] -and $projectStatus.mim_proposal_acknowledgment -and [bool]$projectStatus.mim_proposal_acknowledgment.available) {
            $mimProposalAcknowledgment = $projectStatus.mim_proposal_acknowledgment
            [void]$flags.Add('mim_proposal_acknowledged')
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Acknowledgment Status' -Value ([string]$mimProposalAcknowledgment.status) -Section 'mim_proposal_acknowledgment' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Acknowledgment Disposition' -Value ([string]$mimProposalAcknowledgment.disposition) -Section 'mim_proposal_acknowledgment' -Field 'disposition'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Acknowledgment Summary' -Value ([string]$mimProposalAcknowledgment.summary) -Section 'mim_proposal_acknowledgment' -Field 'summary'))
            if ([string]::Equals([string]$mimProposalAcknowledgment.disposition, 'absorbed', [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$flags.Add('mim_proposal_absorbed')
            }
            elseif ([string]::Equals([string]$mimProposalAcknowledgment.disposition, 'deferred', [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$flags.Add('mim_proposal_ack_deferred')
            }
            elseif ([string]::Equals([string]$mimProposalAcknowledgment.disposition, 'rejected', [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$flags.Add('mim_proposal_rejected')
            }
        }
        if ($mimProposalClosure -and [bool]$mimProposalClosure.available) {
            [void]$flags.Add('mim_proposal_closure_available')
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Closure Status' -Value ([string]$mimProposalClosure.status) -Section 'mim_proposal_closure' -Field 'status'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Closure Disposition' -Value ([string]$mimProposalClosure.disposition) -Section 'mim_proposal_closure' -Field 'disposition'))
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'MIM Proposal Closure Summary' -Value ([string]$mimProposalClosure.summary) -Section 'mim_proposal_closure' -Field 'summary'))
            switch ([string]$mimProposalClosure.disposition) {
                'open' { [void]$flags.Add('mim_proposal_open') }
                'fulfilled' { [void]$flags.Add('mim_proposal_fulfilled') }
                'abandoned' { [void]$flags.Add('mim_proposal_abandoned') }
                'superseded' { [void]$flags.Add('mim_proposal_superseded') }
                'withdrawn' { [void]$flags.Add('mim_proposal_withdrawn') }
            }
        }
        if ($resolvedIntent -in @('summarize_status', 'summarize_current_objective', 'suggest_next_action')) {
            $proposalSummary = if ([string]::IsNullOrWhiteSpace([string]$mimProposal.scope)) { [string]$mimProposal.notes } else { [string]$mimProposal.scope }
            $useCompactProposalSummary = (
                $resolvedIntent -in @('summarize_status', 'summarize_current_objective') -and
                $mimProposalClosure -and [bool]$mimProposalClosure.available -and
                [string]::Equals([string]$mimProposalClosure.disposition, 'fulfilled', [System.StringComparison]::OrdinalIgnoreCase) -and
                $mimProposalArbitration -and [bool]$mimProposalArbitration.available -and
                [string]::Equals([string]$mimProposalArbitration.winner, 'shared', [System.StringComparison]::OrdinalIgnoreCase)
            )
            $proposalSentence = if ($useCompactProposalSummary) {
                if ([string]::IsNullOrWhiteSpace($proposalObjectiveId)) {
                    ' Bounded MIM context remains aligned and fulfilled; unattended cadence stays under strict suite checkpoints.'
                }
                else {
                    ' Bounded MIM context for objective {0} remains aligned around {1}; the linked proposal is fulfilled and unattended cadence stays under strict suite checkpoints.' -f $proposalObjectiveId, ([string]$mimProposal.title)
                }
            }
            elseif ([string]::IsNullOrWhiteSpace($proposalObjectiveId)) {
                " MIM also has a live proposal in scope: $([string]$mimProposal.title)."
            }
            else {
                ' MIM also has a live proposal in scope for objective {0}: {1}.' -f $proposalObjectiveId, ([string]$mimProposal.title)
            }
            if (-not $useCompactProposalSummary) {
                if ($mimProposalConflict -and [bool]$mimProposalConflict.available -and [bool]$mimProposalConflict.conflict_detected) {
                    $proposalSentence = "$proposalSentence Conflict detected: $([string]$mimProposalConflict.summary)"
                }
                if ($mimProposalArbitration -and [bool]$mimProposalArbitration.available) {
                    $proposalSentence = "$proposalSentence Arbitration: $([string]$mimProposalArbitration.summary)"
                }
                if ($mimProposalMergePolicy -and [bool]$mimProposalMergePolicy.available) {
                    $proposalSentence = "$proposalSentence Merge policy: $([string]$mimProposalMergePolicy.summary)"
                }
                if ($mimProposalClosure -and [bool]$mimProposalClosure.available) {
                    $proposalSentence = "$proposalSentence Closure: $([string]$mimProposalClosure.summary)"
                }
                if (-not [string]::IsNullOrWhiteSpace($proposalSummary)) {
                    $proposalSentence = "$proposalSentence $proposalSummary"
                }
            }
            $summary = "$summary$proposalSentence"
            $nextStep = if (
                $mimProposalArbitration -and [bool]$mimProposalArbitration.available -and [string]::Equals([string]$mimProposalArbitration.winner, 'shared', [System.StringComparison]::OrdinalIgnoreCase) -and
                $mimProposalMergePolicy -and [bool]$mimProposalMergePolicy.available -and [string]::Equals([string]$mimProposalMergePolicy.status, 'merge_ready', [System.StringComparison]::OrdinalIgnoreCase) -and
                $mimProposalClosure -and [bool]$mimProposalClosure.available -and [string]::Equals([string]$mimProposalClosure.status, 'open', [System.StringComparison]::OrdinalIgnoreCase)
            ) {
                'Use MIM-TOD bounded context to determine implementation, then refresh bounded status before confirming or recommitting.'
            }
            elseif ($mimProposalClosure -and [bool]$mimProposalClosure.available -and -not [string]::IsNullOrWhiteSpace([string]$mimProposalClosure.recommended_action)) {
                [string]$mimProposalClosure.recommended_action
            }
            elseif ($mimProposalMergePolicy -and [bool]$mimProposalMergePolicy.available -and -not [string]::IsNullOrWhiteSpace([string]$mimProposalMergePolicy.recommended_action)) {
                [string]$mimProposalMergePolicy.recommended_action
            }
            elseif ($mimProposalArbitration -and [bool]$mimProposalArbitration.available -and -not [string]::IsNullOrWhiteSpace([string]$mimProposalArbitration.recommended_action)) {
                [string]$mimProposalArbitration.recommended_action
            }
            elseif ($mimProposalConflict -and [bool]$mimProposalConflict.available -and [bool]$mimProposalConflict.conflict_detected) {
                'Resolve the bounded proposal conflict with bridge alignment and state-bus evidence before confirming or recommitting.'
            }
            else {
                'Review bounded status, state-bus, and bridge evidence against the live MIM proposal before confirming or recommitting.'
            }
        }
    }

    if (@($suggestedActions).Count -eq 0) {
        $suggestedActions = Get-OperatorChatRecommendedActions -ProjectStatus $projectStatus -Intent $resolvedIntent -ActiveCommitment $activeCommitment -RecentCommitment $commitmentContext -ValidationHarness $resolvedValidationHarness
    }
    if ($commitmentContext) {
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'Committed Action' -Value ([string]$commitmentContext.action_label) -Section 'operator_commitment' -Field 'action_label'))
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'Commitment State' -Value ([string]$commitmentContext.state) -Section 'operator_commitment' -Field 'state'))
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'Commitment Lifecycle' -Value ([string]$commitmentContext.lifecycle_status) -Section 'operator_commitment' -Field 'lifecycle_status'))
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'Commitment Release' -Value ([string]$commitmentContext.release_condition) -Section 'operator_commitment' -Field 'release_condition'))
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'Commitment Scope Status' -Value ([string]$commitmentContext.scope_status) -Section 'operator_commitment' -Field 'scope_status'))
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'Commitment Scope Kind' -Value ([string]$commitmentContext.scope_kind) -Section 'operator_commitment' -Field 'scope_kind'))
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'Commitment Scope Resolution' -Value ([string]$commitmentContext.scope_conflict_resolution) -Section 'operator_commitment' -Field 'scope_conflict_resolution'))
        [void]$evidence.Add((New-OperatorChatEvidence -Label 'Commitment Scope Influence' -Value ([string]$commitmentContext.scope_influence_summary) -Section 'operator_commitment' -Field 'scope_influence_summary'))
        if ($commitmentContext.PSObject.Properties['scope_conflict_reason'] -and -not [string]::IsNullOrWhiteSpace([string]$commitmentContext.scope_conflict_reason)) {
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Commitment Scope Conflict' -Value ([string]$commitmentContext.scope_conflict_reason) -Section 'operator_commitment' -Field 'scope_conflict_reason'))
        }
        if ($commitmentContext.expires_at) {
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Commitment Expires' -Value ([string]$commitmentContext.expires_at) -Section 'operator_commitment' -Field 'expires_at'))
        }
        if ([int]$commitmentContext.evidence_delta_count -gt 0) {
            [void]$evidence.Add((New-OperatorChatEvidence -Label 'Commitment Evidence Delta Count' -Value ([int]$commitmentContext.evidence_delta_count) -Section 'operator_commitment' -Field 'evidence_delta_count'))
        }
        if ($commitmentContext.PSObject.Properties['scope_conflict_resolution'] -and [string]::Equals([string]$commitmentContext.scope_conflict_resolution, 'downgrade', [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$flags.Add('operator_commitment_scope_downgraded')
        }
        if ($commitmentContext.PSObject.Properties['scope_blocks_activation'] -and [bool]$commitmentContext.scope_blocks_activation) {
            [void]$flags.Add('operator_commitment_scope_blocked')
        }
        if ($commitmentContext.PSObject.Properties['scope_in_scope'] -and -not [bool]$commitmentContext.scope_in_scope) {
            [void]$limitations.Add([string]$commitmentContext.scope_summary)
            [void]$flags.Add('operator_commitment_scope_shifted')
        }
    }
    $citationIndex = @{}
    $citations = foreach ($item in $evidence) {
        $section = [string]$item.section
        $field = [string]$item.field
        $citationKey = '{0}::{1}' -f $section, $field
        if ($citationIndex.ContainsKey($citationKey)) {
            continue
        }

        $citationIndex[$citationKey] = $true
        [pscustomobject]@{
            section = $section
            field = $field
        }
    }

    $result = [pscustomobject]@{
        ok = $true
        query = [string]$Query
        intent = $resolvedIntent
        objective_id = if ($marker) { [string]$marker.objective_id } else { [string]$resolvedObjectiveId }
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        validation_harness = if ($projectStatus -and $projectStatus.PSObject.Properties['validation_harness']) { $projectStatus.validation_harness } else { $null }
        capabilities = Get-OperatorChatCapabilities
        response = [pscustomobject]@{
            summary = $summary
            evidence = @($evidence | Select-Object -First 8)
            recommended_next_step = $nextStep
            suggested_actions = @($suggestedActions)
            confidence = $confidence
            flags = @($flags | Select-Object -Unique)
            limitations = @($limitations)
            citations = @($citations)
        }
    }

    Register-OperatorChatQueryCacheEntry -Query $Query -Intent $resolvedIntent -ObjectiveId $resolvedObjectiveId -WindowMinutes $WindowMinutes -ValidationHarness $resolvedValidationHarness -Result $result
    return $result
}

function Get-MimeTypeForPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        ".json" { return "application/json; charset=utf-8" }
        ".yaml" { return "application/x-yaml; charset=utf-8" }
        ".yml" { return "application/x-yaml; charset=utf-8" }
        ".md" { return "text/markdown; charset=utf-8" }
        ".txt" { return "text/plain; charset=utf-8" }
        default { return "application/octet-stream" }
    }
}

function Get-ShareArtifactsPayload {
    param(
        [int]$ActivePort,
        [string]$BaseUrl
    )

    $items = @()
    foreach ($entry in $shareArtifacts.GetEnumerator()) {
        $key = [string]$entry.Key
        $spec = $entry.Value
        $fullPath = [string]$spec.path
        $exists = Test-Path -Path $fullPath
        $item = [ordered]@{
            key = $key
            label = [string]$spec.label
            path = $fullPath
            exists = $exists
            download_url = "/api/share-download?key=$([uri]::EscapeDataString($key))"
            preview_url = "/api/share-open?key=$([uri]::EscapeDataString($key))"
            file_uri = "file:///" + ($fullPath -replace "\\", "/")
        }

        if ($exists) {
            $file = Get-Item -Path $fullPath
            $item.last_write_time_utc = $file.LastWriteTimeUtc.ToString("o")
            $item.length = [int64]$file.Length
        }

        $items += [pscustomobject]$item
    }

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        base_url = if (-not [string]::IsNullOrWhiteSpace([string]$BaseUrl)) { [string]$BaseUrl } else { (Get-TodUiBaseUrl -HostName 'localhost' -Port $ActivePort) }
        artifacts = @($items)
    }
}

function Get-TaskProgressWeight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    $normalized = $Status.Trim().ToLowerInvariant()
    switch ($normalized) {
        "pass" { return 1.0 }
        "reviewed_pass" { return 1.0 }
        "done" { return 1.0 }
        "completed" { return 1.0 }
        "implemented" { return 0.75 }
        "in_progress" { return 0.5 }
        "active" { return 0.5 }
        "revise" { return 0.35 }
        "planned" { return 0.15 }
        "open" { return 0.1 }
        default { return 0.0 }
    }
}

function Convert-ListenerExecutionStatusToProgressStatus {
    param([string]$Status)

    $normalized = ([string]$Status).Trim().ToLowerInvariant()
    switch ($normalized) {
        'succeeded' { return 'completed' }
        'pass' { return 'completed' }
        'reviewed_pass' { return 'completed' }
        'done' { return 'completed' }
        'completed' { return 'completed' }
        'already_processed' { return 'completed' }
        'in_progress' { return 'in_progress' }
        'active' { return 'in_progress' }
        'running' { return 'in_progress' }
        'failed' { return 'failed' }
        'contract_violation_rejected' { return 'failed' }
        'quarantined' { return 'failed' }
        'invalid_request' { return 'failed' }
        default { return '' }
    }
}

function Read-JsonFileIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path)) {
        return $null
    }

    try {
        $text = Read-TextFileIfExists -Path $Path
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }
        return ($text | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Read-TextFileIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path)) {
        return $null
    }

    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Read-JsonLinesFileIfExists {
    param(
        [string]$Path,
        [int]$Tail = 40
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path)) {
        return @()
    }

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-RecentLogLines -LogPath $Path -Tail $Tail)) {
        if ([string]::IsNullOrWhiteSpace([string]$line)) {
            continue
        }

        try {
            $entry = $line | ConvertFrom-Json
            if ($null -ne $entry) {
                [void]$entries.Add($entry)
            }
        }
        catch {
        }
    }

    return @($entries.ToArray())
}

function Get-DialogSessionsPayload {
    param(
        [int]$Limit = 8,
        [string]$Actor = 'TOD'
    )

    $safeLimit = if ($Limit -lt 1) { 1 } elseif ($Limit -gt 30) { 30 } else { $Limit }
    $actorName = if ([string]::IsNullOrWhiteSpace($Actor)) { 'TOD' } else { [string]$Actor.Trim().ToUpperInvariant() }
    $indexDoc = Read-JsonFileIfExists -Path $dialogSessionIndexPath
    $sessions = @()

    if ($indexDoc -and $indexDoc.PSObject.Properties['sessions']) {
        $sessions = @($indexDoc.sessions)
    }
    elseif (Test-Path -Path $dialogDirPath) {
        $states = Get-ChildItem -Path $dialogDirPath -Filter 'MIM_TOD_DIALOG.session-*.latest.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending
        foreach ($stateFile in @($states)) {
            $state = Read-JsonFileIfExists -Path $stateFile.FullName
            if ($null -ne $state) {
                $sessions += $state
            }
        }
    }

    $sortedSessions = @($sessions | Sort-Object {
        if ($_.PSObject.Properties['updated_at']) { [string]$_.updated_at } else { '' }
    } -Descending)

    $openCount = 0
    $timedOutCount = 0
    $closedCount = 0
    foreach ($session in @($sortedSessions)) {
        $status = if ($session.PSObject.Properties['status']) { [string]$session.status } else { '' }
        switch -Regex ($status) {
            'awaiting_reply' { $openCount++ }
            'timed_out' { $timedOutCount++ }
            'closed' { $closedCount++ }
        }
    }

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        actor = $actorName
        available = (Test-Path -Path $dialogDirPath)
        channel_path = $dialogChannelPath
        session_index_path = $dialogSessionIndexPath
        open_count = $openCount
        timed_out_count = $timedOutCount
        closed_count = $closedCount
        total_count = @($sortedSessions).Count
        sessions = @($sortedSessions | Select-Object -First $safeLimit)
    }
}

function Get-DialogSessionPayload {
    param(
        [Parameter(Mandatory = $true)][string]$SessionId,
        [int]$Tail = 12
    )

    $trimmedSessionId = [string]$SessionId.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedSessionId)) {
        throw 'session_id is required.'
    }

    $safeSessionId = $trimmedSessionId -replace '[^a-zA-Z0-9._-]', '_'
    $sessionLogPath = Join-Path $dialogDirPath ("MIM_TOD_DIALOG.session-{0}.jsonl" -f $safeSessionId)
    $sessionStatePath = Join-Path $dialogDirPath ("MIM_TOD_DIALOG.session-{0}.latest.json" -f $safeSessionId)
    $sessionState = Read-JsonFileIfExists -Path $sessionStatePath
    $messages = Read-JsonLinesFileIfExists -Path $sessionLogPath -Tail $Tail

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        session_id = $trimmedSessionId
        session_state = $sessionState
        message_count = @($messages).Count
        messages = @($messages)
        session_path = $sessionLogPath
    }
}

function Get-ObjectiveIdFromRequestId {
    param([string]$RequestId)

    if ([string]::IsNullOrWhiteSpace($RequestId)) {
        return ""
    }

    $match = [regex]::Match([string]$RequestId, '^objective-(?<objective>\d+)-task-.+$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return ""
    }

    return [string]$match.Groups['objective'].Value
}

function Normalize-ObjectiveIdValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $trimmed = [string]$Value.Trim()
    $objectiveMatch = [regex]::Match($trimmed, '^objective-(?<objective>\d+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($objectiveMatch.Success) {
        return [string]$objectiveMatch.Groups['objective'].Value
    }

    return $trimmed
}

function Get-ObjectiveNumericValue {
    param([string]$Value)

    $normalized = Normalize-ObjectiveIdValue -Value $Value
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return -1
    }

    $parsed = 0
    if ([int]::TryParse($normalized, [ref]$parsed)) {
        return $parsed
    }

    return -1
}

function Get-CanonicalMimObjective {
    $candidates = @(
        [pscustomobject]@{
            path = $mimExportCanonicalPath
            source = "ssh_shared_export"
            fields = @("objective_active", "objective_in_flight", "current_next_objective")
        },
        [pscustomobject]@{
            path = $mimExportFallbackPath
            source = "local_export"
            fields = @("objective_active", "objective_in_flight", "current_next_objective")
        },
        [pscustomobject]@{
            path = $mimHandshakeCanonicalPath
            source = "ssh_shared_handshake"
            fields = @("objective_active", "current_next_objective")
        },
        [pscustomobject]@{
            path = $mimHandshakeFallbackPath
            source = "local_handshake"
            fields = @("objective_active", "current_next_objective")
        }
    )

    foreach ($candidate in $candidates) {
        $doc = Read-JsonFileIfExists -Path ([string]$candidate.path)
        if ($null -eq $doc) {
            continue
        }

        foreach ($field in @($candidate.fields)) {
            if (-not $doc.PSObject.Properties[$field]) {
                continue
            }

            $normalized = Normalize-ObjectiveIdValue -Value ([string]$doc.$field)
            if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                return [pscustomobject]@{
                    available = $true
                    objective_id = $normalized
                    field = [string]$field
                    source = [string]$candidate.source
                    path = [string]$candidate.path
                }
            }
        }
    }

    return [pscustomobject]@{
        available = $false
        objective_id = ""
        field = ""
        source = ""
        path = ""
    }
}

function Resolve-ProjectSelectedObjectiveId {
    param(
        [string]$ExplicitObjectiveId,
        [AllowNull()]$ListenerActivity,
        [AllowNull()]$BridgeStatus,
        [AllowNull()]$NextActions,
        [AllowNull()]$Objectives
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitObjectiveId)) {
        return [string]$ExplicitObjectiveId
    }

    $listenerObjectiveId = ""
    if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['latest_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$ListenerActivity.latest_objective_id)) {
        $listenerObjectiveId = [string]$ListenerActivity.latest_objective_id
    }

    $bridgeCanonicalObjectiveId = ""
    if ($BridgeStatus -and $BridgeStatus.PSObject.Properties['canonical_mim_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$BridgeStatus.canonical_mim_objective_id)) {
        $bridgeCanonicalObjectiveId = [string]$BridgeStatus.canonical_mim_objective_id
    }

    $bridgeTaskRequestObjectiveId = ""
    if ($BridgeStatus -and $BridgeStatus.PSObject.Properties['task_request_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$BridgeStatus.task_request_objective_id)) {
        $bridgeTaskRequestObjectiveId = [string]$BridgeStatus.task_request_objective_id
    }

    $nextActionsObjectiveId = ""
    if ($NextActions -and $NextActions.PSObject.Properties['current_objective_in_progress'] -and -not [string]::IsNullOrWhiteSpace([string]$NextActions.current_objective_in_progress)) {
        $nextActionsObjectiveId = [string]$NextActions.current_objective_in_progress
    }

    $listenerObjectiveNumber = Get-ObjectiveNumericValue -Value $listenerObjectiveId
    $bridgeCanonicalObjectiveNumber = Get-ObjectiveNumericValue -Value $bridgeCanonicalObjectiveId
    $bridgeTaskRequestObjectiveNumber = Get-ObjectiveNumericValue -Value $bridgeTaskRequestObjectiveId
    if ($BridgeStatus -and $BridgeStatus.PSObject.Properties['objective_mismatch'] -and [bool]$BridgeStatus.objective_mismatch) {
        if ($bridgeCanonicalObjectiveNumber -ge 0 -and $bridgeTaskRequestObjectiveNumber -ge 0) {
            if ($bridgeCanonicalObjectiveNumber -gt $bridgeTaskRequestObjectiveNumber) {
                return $bridgeCanonicalObjectiveId
            }

            if ($bridgeTaskRequestObjectiveNumber -gt $bridgeCanonicalObjectiveNumber -and -not [string]::IsNullOrWhiteSpace($bridgeTaskRequestObjectiveId)) {
                return $bridgeTaskRequestObjectiveId
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($bridgeTaskRequestObjectiveId)) {
            return $bridgeTaskRequestObjectiveId
        }
    }

    if ($bridgeTaskRequestObjectiveNumber -ge 0 -and $bridgeCanonicalObjectiveNumber -ge 0 -and $bridgeTaskRequestObjectiveNumber -gt $bridgeCanonicalObjectiveNumber) {
        if ([string]::Equals($listenerObjectiveId, $bridgeTaskRequestObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) -or $listenerObjectiveNumber -eq $bridgeTaskRequestObjectiveNumber) {
            return $bridgeTaskRequestObjectiveId
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($listenerObjectiveId) -and -not [string]::IsNullOrWhiteSpace($bridgeCanonicalObjectiveId)) {
        if ([string]::Equals($listenerObjectiveId, $bridgeCanonicalObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $listenerObjectiveId
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($nextActionsObjectiveId) -and -not [string]::IsNullOrWhiteSpace($bridgeCanonicalObjectiveId)) {
        if ([string]::Equals($nextActionsObjectiveId, $bridgeCanonicalObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $nextActionsObjectiveId
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($listenerObjectiveId)) {
        return $listenerObjectiveId
    }

    if (-not [string]::IsNullOrWhiteSpace($bridgeCanonicalObjectiveId)) {
        return $bridgeCanonicalObjectiveId
    }

    if (-not [string]::IsNullOrWhiteSpace($nextActionsObjectiveId)) {
        return $nextActionsObjectiveId
    }

    if ($Objectives) {
        $latestObjective = @($Objectives | Sort-Object created_at -Descending | Select-Object -First 1)
        if (@($latestObjective).Count -gt 0 -and $latestObjective[0] -and $latestObjective[0].PSObject.Properties['id']) {
            return [string]$latestObjective[0].id
        }
    }

    return ""
}

function Get-TaskRefInfo {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $match = [regex]::Match([string]$Value, '^objective-(?<objective>\d+)-task-(?<tail>.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    $ordinalMatch = [regex]::Match([string]$match.Groups['tail'].Value, '(?<task>\d+)(?!.*\d)')
    if (-not $ordinalMatch.Success) {
        return $null
    }

    return [pscustomobject]@{
        objective = [string]$match.Groups['objective'].Value
        task_number = [long]$ordinalMatch.Groups['task'].Value
        raw = [string]$Value
    }
}

function Convert-ToDateTimeOffsetOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    try {
        return [DateTimeOffset]::Parse([string]$Value)
    }
    catch {
        return $null
    }
}

function Get-PercentileValue {
    param(
        [double[]]$Values,
        [double]$Percentile
    )

    if ($null -eq $Values -or $Values.Count -eq 0) {
        return 0.0
    }

    $sorted = @($Values | Sort-Object)
    $index = [int][math]::Floor(($Percentile / 100.0) * ([double]($sorted.Count - 1)))
    if ($index -lt 0) {
        $index = 0
    }
    if ($index -ge $sorted.Count) {
        $index = $sorted.Count - 1
    }

    return [math]::Round([double]$sorted[$index], 1)
}

function Get-CadenceHealth {
    param(
        $ListenerActivity,
        $RecoveryWatchdog
    )

    if ($null -eq $ListenerActivity) {
        return [pscustomobject]@{
            available = $false
            severity = "unknown"
            alerts = @("no_listener_activity")
            stream = [pscustomobject]@{
                aligned = $false
                task_delta = -1
                loop_idle_sec = -1
            }
            cadence = [pscustomobject]@{
                sample_size = 0
                avg_sec = 0
                smoothed_avg_sec = 0
                p50_sec = 0
                p95_sec = 0
                stddev_sec = 0
                retry_rate = 0
                weighted_retry_ratio = 0
                failure_retry_ratio = 0
                no_new_work_retry_ratio = 0
                duplicate_retry_ratio = 0
                waiting_go_order_retry_ratio = 0
                score = 0
            }
            governance = [pscustomobject]@{
                adjusted_severity = "unknown"
                noise_suppressed = $false
                dominant_retry_reason = "none"
            }
            thresholds = [pscustomobject]@{
                warning_cycle_sec = 180
                critical_cycle_sec = 300
                warning_sync_delta = 1
                critical_sync_delta = 3
                warning_retry_rate = 0.6
                warning_score = 70
                critical_score = 40
            }
        }
    }

    $warningCycleSec = 180
    $criticalCycleSec = 300
    $warningSyncDelta = 1
    $criticalSyncDelta = 3
    $warningRetryRate = 0.6
    $warningScore = 70
    $criticalScore = 40

    $recentEntries = @()
    if ($ListenerActivity.PSObject.Properties['recent_entries']) {
        $recentEntries = @($ListenerActivity.recent_entries)
    }

    $entriesSorted = @($recentEntries | Sort-Object {
            $ts = Convert-ToDateTimeOffsetOrNull -Value ([string]$_.timestamp)
            if ($null -eq $ts) { [DateTimeOffset]::MinValue } else { $ts }
        })

    $intervals = New-Object System.Collections.Generic.List[double]
    $requestIds = @()
    $retryCount = 0
    $retryWeightTotal = 0.0
    $failureRetryCount = 0
    $noNewWorkRetryCount = 0
    $duplicateRetryCount = 0
    $waitingGoOrderRetryCount = 0
    $lastTs = $null
    foreach ($entry in $entriesSorted) {
        $requestId = if ($entry.PSObject.Properties['request_id']) { [string]$entry.request_id } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($requestId)) {
            $requestIds += $requestId
        }

        $retryReason = if ($entry.PSObject.Properties['retry_reason']) { ([string]$entry.retry_reason).Trim().ToLowerInvariant() } else { "none" }
        $isCadenceNoise = $false
        if ($entry.PSObject.Properties['cadence_noise']) {
            try { $isCadenceNoise = [bool]$entry.cadence_noise } catch { $isCadenceNoise = $false }
        }
        if ($retryReason -ne 'none' -and -not $isCadenceNoise) {
            $retryCount += 1
        }
        $retryWeight = 0.0
        if ($entry.PSObject.Properties['retry_weight']) {
            try { $retryWeight = [double]$entry.retry_weight } catch { $retryWeight = 0.0 }
        }
        if (-not $isCadenceNoise) {
            $retryWeightTotal += $retryWeight
            switch ($retryReason) {
                'failure' { $failureRetryCount += 1 }
                'no_new_work' { $noNewWorkRetryCount += 1 }
                'duplicate_seen' { $duplicateRetryCount += 1 }
                'waiting_go_order' { $waitingGoOrderRetryCount += 1 }
            }
        }

        $timestampValue = ""
        if ($entry.PSObject.Properties['timestamp']) {
            $timestampValue = [string]$entry.timestamp
        }
        $ts = Convert-ToDateTimeOffsetOrNull -Value $timestampValue
        if ($null -ne $ts -and $null -ne $lastTs) {
            $intervals.Add(($ts - $lastTs).TotalSeconds)
        }
        if ($null -ne $ts) {
            $lastTs = $ts
        }
    }

    $avgSec = if ($intervals.Count -gt 0) { [math]::Round((($intervals | Measure-Object -Average).Average), 1) } else { 0 }
    $smoothedAvgSec = 0.0
    if ($intervals.Count -gt 0) {
        $alpha = 0.35
        $smoothed = [double]$intervals[0]
        foreach ($interval in $intervals) {
            $smoothed = ($alpha * [double]$interval) + ((1 - $alpha) * $smoothed)
        }
        $smoothedAvgSec = [Math]::Round($smoothed, 1)
    }
    $p50Sec = Get-PercentileValue -Values ([double[]]$intervals.ToArray()) -Percentile 50
    $p95Sec = Get-PercentileValue -Values ([double[]]$intervals.ToArray()) -Percentile 95
    $stdDevSec = 0.0
    if ($intervals.Count -gt 1) {
        $varianceTotal = 0.0
        foreach ($interval in $intervals) {
            $varianceTotal += [Math]::Pow(([double]$interval - [double]$avgSec), 2)
        }
        $stdDevSec = [Math]::Round([Math]::Sqrt($varianceTotal / $intervals.Count), 1)
    }

    $sampleSize = [Math]::Max(@($entriesSorted).Count, 1)
    $retryRate = if (@($entriesSorted).Count -gt 0) {
        [math]::Round(($retryCount / [double]@($entriesSorted).Count), 3)
    }
    else {
        0
    }
    $weightedRetryRatio = if (@($entriesSorted).Count -gt 0) { [Math]::Round(($retryWeightTotal / [double]@($entriesSorted).Count), 3) } else { 0 }
    $failureRetryRatio = [Math]::Round(($failureRetryCount / [double]$sampleSize), 3)
    $noNewWorkRetryRatio = [Math]::Round(($noNewWorkRetryCount / [double]$sampleSize), 3)
    $duplicateRetryRatio = [Math]::Round(($duplicateRetryCount / [double]$sampleSize), 3)
    $waitingGoOrderRetryRatio = [Math]::Round(($waitingGoOrderRetryCount / [double]$sampleSize), 3)

    $latestTimestamp = if ($ListenerActivity.PSObject.Properties['latest_timestamp']) { [string]$ListenerActivity.latest_timestamp } else { "" }
    $latestTs = Convert-ToDateTimeOffsetOrNull -Value $latestTimestamp
    $loopIdleSec = -1
    if ($null -ne $latestTs) {
        $loopIdleSec = [math]::Round(([DateTimeOffset]::UtcNow - $latestTs).TotalSeconds, 1)
    }
    elseif ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['heartbeat_age_seconds']) {
        $loopIdleSec = [double]([int]$RecoveryWatchdog.heartbeat_age_seconds)
    }

    $syncTaskDelta = 0L
    $sync = if ($ListenerActivity.PSObject.Properties['sync']) { $ListenerActivity.sync } else { $null }
    if ($sync -and $sync.PSObject.Properties['request_task_number'] -and $sync.PSObject.Properties['result_task_number']) {
        $reqTask = [long]$sync.request_task_number
        $resTask = [long]$sync.result_task_number
        if ($reqTask -ge 0 -and $resTask -ge 0) {
            $syncTaskDelta = [math]::Abs($reqTask - $resTask)
        }
    }

    $alerts = New-Object System.Collections.Generic.List[string]
    $severity = "ok"
    $dominantRetryReason = "none"
    $retryBreakdown = [ordered]@{
        failure = $failureRetryCount
        no_new_work = $noNewWorkRetryCount
        duplicate_seen = $duplicateRetryCount
        waiting_go_order = $waitingGoOrderRetryCount
    }
    $dominantRetryCount = 0
    foreach ($retryKey in $retryBreakdown.Keys) {
        $retryKeyCount = [int]$retryBreakdown[$retryKey]
        if ($retryKeyCount -gt $dominantRetryCount) {
            $dominantRetryCount = $retryKeyCount
            $dominantRetryReason = [string]$retryKey
        }
    }
    $noiseOnlyCadence = ($failureRetryCount -eq 0) -and (($noNewWorkRetryCount + $duplicateRetryCount + $waitingGoOrderRetryCount) -gt 0)
    $timingVarianceRatio = if ($smoothedAvgSec -gt 0) { [Math]::Round(($stdDevSec / [Math]::Max([double]$smoothedAvgSec, 1.0)), 3) } else { 0 }

    if ($loopIdleSec -gt $criticalCycleSec) {
        $alerts.Add("loop_idle_gt_${criticalCycleSec}s")
        $severity = "critical"
    }
    elseif ($loopIdleSec -gt $warningCycleSec) {
        $alerts.Add("loop_idle_gt_${warningCycleSec}s")
        if ($severity -ne "critical") {
            $severity = "warning"
        }
    }

    if ($syncTaskDelta -gt $criticalSyncDelta) {
        $alerts.Add("sync_delta_gt_${criticalSyncDelta}")
        $severity = "critical"
    }
    elseif ($syncTaskDelta -gt $warningSyncDelta) {
        $alerts.Add("sync_delta_gt_${warningSyncDelta}")
        if ($severity -ne "critical") {
            $severity = "warning"
        }
    }

    if ($failureRetryRatio -gt 0.35) {
        $alerts.Add("failure_retry_ratio_gt_35pct")
        if ($severity -ne "critical") {
            $severity = "warning"
        }
    }
    elseif ($weightedRetryRatio -gt $warningRetryRate -and -not $noiseOnlyCadence) {
        $alerts.Add("weighted_retry_ratio_gt_60pct")
        if ($severity -eq "ok") {
            $severity = "warning"
        }
    }

    $latencyPenalty = 0.0
    if ($loopIdleSec -gt $warningCycleSec) {
        $latencyPenalty = [Math]::Min(35.0, (($loopIdleSec - $warningCycleSec) / [Math]::Max(($criticalCycleSec - $warningCycleSec), 1)) * 35.0)
    }
    $variancePenalty = [Math]::Min(20.0, $timingVarianceRatio * 25.0)
    $retryPenaltyRaw = [Math]::Min(30.0, ($failureRetryRatio * 28.0) + ($duplicateRetryRatio * 10.0) + ($waitingGoOrderRetryRatio * 8.0) + ($noNewWorkRetryRatio * 4.0))
    $retryPenalty = if ($noiseOnlyCadence) { [Math]::Round($retryPenaltyRaw * 0.4, 1) } else { [Math]::Round($retryPenaltyRaw, 1) }
    $syncPenalty = [Math]::Min(25.0, [double]$syncTaskDelta * 8.0)
    $score = [Math]::Round([Math]::Max(0.0, 100.0 - $latencyPenalty - $variancePenalty - $retryPenalty - $syncPenalty), 1)
    $noiseSuppressed = ($noiseOnlyCadence -and ($retryPenaltyRaw -gt $retryPenalty))

    if ($score -le $criticalScore -and $severity -ne 'critical') {
        $severity = 'critical'
        $alerts.Add("cadence_score_lte_${criticalScore}")
    }
    elseif ($score -le $warningScore -and $severity -eq 'ok') {
        $severity = 'warning'
        $alerts.Add("cadence_score_lte_${warningScore}")
    }

    $adjustedSeverity = $severity
    if ($noiseOnlyCadence -and $syncTaskDelta -le $warningSyncDelta -and $loopIdleSec -le $warningCycleSec) {
        if ($adjustedSeverity -eq 'critical') {
            $adjustedSeverity = 'warning'
        }
        elseif ($adjustedSeverity -eq 'warning' -and $score -gt $warningScore) {
            $adjustedSeverity = 'ok'
        }
    }

    if ($noiseSuppressed) {
        $alerts.Add('cadence_noise_suppressed')
    }

    if ($alerts.Count -eq 0) {
        $alerts.Add("none")
    }

    return [pscustomobject]@{
        available = $true
        severity = $severity
        alerts = @($alerts)
        stream = [pscustomobject]@{
            aligned = ($syncTaskDelta -eq 0)
            task_delta = $syncTaskDelta
            loop_idle_sec = $loopIdleSec
        }
        cadence = [pscustomobject]@{
            sample_size = $intervals.Count
            avg_sec = $avgSec
            smoothed_avg_sec = $smoothedAvgSec
            p50_sec = $p50Sec
            p95_sec = $p95Sec
            stddev_sec = $stdDevSec
            retry_rate = $retryRate
            weighted_retry_ratio = $weightedRetryRatio
            failure_retry_ratio = $failureRetryRatio
            no_new_work_retry_ratio = $noNewWorkRetryRatio
            duplicate_retry_ratio = $duplicateRetryRatio
            waiting_go_order_retry_ratio = $waitingGoOrderRetryRatio
            score = $score
        }
        governance = [pscustomobject]@{
            adjusted_severity = $adjustedSeverity
            noise_suppressed = $noiseSuppressed
            dominant_retry_reason = $dominantRetryReason
        }
        thresholds = [pscustomobject]@{
            warning_cycle_sec = $warningCycleSec
            critical_cycle_sec = $criticalCycleSec
            warning_sync_delta = $warningSyncDelta
            critical_sync_delta = $criticalSyncDelta
            warning_retry_rate = $warningRetryRate
            warning_score = $warningScore
            critical_score = $criticalScore
        }
    }
}

function Get-VoiceAdapterStatus {
    $cfg = Read-JsonFileIfExists -Path $voiceAdapterConfigPath
    if ($null -eq $cfg) {
        return [pscustomobject]@{
            available         = $false
            enabled           = $false
            mode              = "dry_run"
            allow_microphone  = $false
            allow_camera      = $false
            require_push_to_talk = $true
            wake_phrase       = "tod"
            microphone_active = $false
            camera_active     = $false
            last_event_id     = ""
            last_intent       = ""
            last_transcript   = ""
            queued_events     = 0
            error             = "voice-adapter.json not found"
        }
    }

    $telemetry = Read-JsonFileIfExists -Path $voiceAdapterTelemetryPath

    $queuedEvents = 0
    if (Test-Path -Path $voiceAdapterInboxPath) {
        $queuedEvents = @(Get-ChildItem -Path $voiceAdapterInboxPath -Filter "voice-*.json" -ErrorAction SilentlyContinue).Count
    }

    $micActive = $false
    if (Test-Path -Path $voiceListenerPidPath) {
        try {
            $listenerPid = [int](Get-Content -Path $voiceListenerPidPath -Raw -ErrorAction SilentlyContinue).Trim()
            $micActive = ($null -ne (Get-Process -Id $listenerPid -ErrorAction SilentlyContinue))
        } catch { }
    }

    return [pscustomobject]@{
        available         = $true
        enabled           = [bool]$cfg.enabled
        mode              = if ($cfg.PSObject.Properties["mode"]) { [string]$cfg.mode } else { "dry_run" }
        allow_microphone  = [bool]$cfg.allow_microphone
        allow_camera      = [bool]$cfg.allow_camera
        require_push_to_talk = if ($cfg.PSObject.Properties["require_push_to_talk"]) { [bool]$cfg.require_push_to_talk } else { $true }
        wake_phrase       = if ($cfg.PSObject.Properties["wake_phrase"]) { [string]$cfg.wake_phrase } else { "tod" }
        microphone_active = $micActive
        camera_active     = $false
        last_event_id     = if ($telemetry -and $telemetry.PSObject.Properties["last_event_id"]) { [string]$telemetry.last_event_id } else { "" }
        last_intent       = if ($telemetry -and $telemetry.PSObject.Properties["last_intent"]) { [string]$telemetry.last_intent } else { "" }
        last_transcript   = if ($telemetry -and $telemetry.PSObject.Properties["last_transcript"]) { [string]$telemetry.last_transcript } else { "" }
        queued_events     = $queuedEvents
        error             = ""
    }
}

function Get-ListenerActivity {
    $journal = Read-JsonFileIfExists -Path $listenerJournalPath
    $resultPacket = Read-JsonFileIfExists -Path $listenerResultPath
    $requestPacket = Read-JsonFileIfExists -Path $listenerRequestPath
    $commandStatusPacket = Read-JsonFileIfExists -Path $listenerCommandStatusPath
    $listenerState = Read-JsonFileIfExists -Path $listenerStatePath

    $entries = @()
    if ($journal -and $journal.PSObject.Properties['entries']) {
        $entries = @($journal.entries)
    }
    elseif ($journal -is [System.Array]) {
        $entries = @($journal)
    }

    $normalizedEntries = @()
    foreach ($entry in $entries) {
        $requestId = if ($entry.PSObject.Properties['request_id']) { [string]$entry.request_id } else { "" }
        $objectiveId = if ($entry.PSObject.Properties['objective_id']) { [string]$entry.objective_id } else { "" }
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            $objectiveId = Get-ObjectiveIdFromRequestId -RequestId $requestId
        }

        $executionStatus = if ($entry.PSObject.Properties['execution_status']) { [string]$entry.execution_status } else { "unknown" }
        $normalizedEntries += [pscustomobject]@{
            timestamp = if ($entry.PSObject.Properties['timestamp']) { [string]$entry.timestamp } else { "" }
            request_id = $requestId
            objective_id = $objectiveId
            execution_status = $executionStatus
            cycle_classification = if ($entry.PSObject.Properties['cycle_classification']) { [string]$entry.cycle_classification } else { "" }
            retry_reason = if ($entry.PSObject.Properties['retry_reason']) { [string]$entry.retry_reason } else { "none" }
            cadence_noise = if ($entry.PSObject.Properties['cadence_noise']) { [bool]$entry.cadence_noise } else { $false }
            retry_weight = if ($entry.PSObject.Properties['retry_weight']) { [double]$entry.retry_weight } else { 0.0 }
            planned_sleep_seconds = if ($entry.PSObject.Properties['planned_sleep_seconds']) { [int]$entry.planned_sleep_seconds } else { 0 }
            minimum_cycle_seconds = if ($entry.PSObject.Properties['minimum_cycle_seconds']) { [int]$entry.minimum_cycle_seconds } else { 0 }
            backoff_seconds = if ($entry.PSObject.Properties['backoff_seconds']) { [int]$entry.backoff_seconds } else { 0 }
            retry_streak = if ($entry.PSObject.Properties['retry_streak']) { [int]$entry.retry_streak } else { 0 }
            review_gate_passed = if ($entry.PSObject.Properties['review_gate_passed']) { [bool]$entry.review_gate_passed } else { $null }
            validator_passed = if ($entry.PSObject.Properties['validator_passed']) { [bool]$entry.validator_passed } else { $null }
            integration_compatible = if ($entry.PSObject.Properties['integration_compatible']) { [bool]$entry.integration_compatible } else { $null }
        }
    }

    $requestExecutionStats = [ordered]@{}
    foreach ($entry in $normalizedEntries) {
        $objectiveId = [string]$entry.objective_id
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            continue
        }

        $requestKey = [string]$entry.request_id
        if ([string]::IsNullOrWhiteSpace($requestKey)) {
            $requestKey = ('__entry__|' + [string]$entry.timestamp + '|' + [guid]::NewGuid().ToString('N'))
        }

        $aggregateKey = "$objectiveId|$requestKey"
        $mappedStatus = Convert-ListenerExecutionStatusToProgressStatus -Status ([string]$entry.execution_status)
        if ([string]::IsNullOrWhiteSpace($mappedStatus)) {
            continue
        }

        if (-not $requestExecutionStats.Contains($aggregateKey)) {
            $requestExecutionStats[$aggregateKey] = [ordered]@{
                objective_id = $objectiveId
                request_id = [string]$entry.request_id
                execution_status = $mappedStatus
                raw_execution_status = [string]$entry.execution_status
                timestamp = [string]$entry.timestamp
                review_gate_passed = $entry.review_gate_passed
                validator_passed = $entry.validator_passed
                integration_compatible = $entry.integration_compatible
            }
            continue
        }

        $aggregate = $requestExecutionStats[$aggregateKey]
        $rawStatusKey = ([string]$entry.execution_status).Trim().ToLowerInvariant()
        if ($rawStatusKey -ne 'already_processed') {
            $aggregate.execution_status = $mappedStatus
            $aggregate.raw_execution_status = [string]$entry.execution_status
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$aggregate.raw_execution_status)) {
            $aggregate.execution_status = $mappedStatus
            $aggregate.raw_execution_status = [string]$entry.execution_status
        }

        $aggregate.timestamp = [string]$entry.timestamp
        $aggregate.review_gate_passed = $entry.review_gate_passed
        $aggregate.validator_passed = $entry.validator_passed
        $aggregate.integration_compatible = $entry.integration_compatible
    }

    $aggregatedEntries = @($requestExecutionStats.Values | ForEach-Object {
            [pscustomobject]@{
                objective_id = [string]$_.objective_id
                request_id = [string]$_.request_id
                execution_status = [string]$_.execution_status
                raw_execution_status = [string]$_.raw_execution_status
                timestamp = [string]$_.timestamp
                review_gate_passed = $_.review_gate_passed
                validator_passed = $_.validator_passed
                integration_compatible = $_.integration_compatible
            }
        })

    $objectiveStats = @{}
    foreach ($entry in $aggregatedEntries) {
        $statusKey = ([string]$entry.execution_status).Trim().ToLowerInvariant()
        if (@('completed', 'failed', 'in_progress') -notcontains $statusKey) {
            continue
        }

        $objectiveId = [string]$entry.objective_id
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            continue
        }

        if (-not $objectiveStats.ContainsKey($objectiveId)) {
            $objectiveStats[$objectiveId] = [ordered]@{
                total = 0
                completed = 0
                failed = 0
                in_progress = 0
                progress_units = 0.0
                last_request_id = ""
                last_execution_status = ""
                last_timestamp = ""
            }
        }

        $stats = $objectiveStats[$objectiveId]
        $stats.total = [int]$stats.total + 1
        $status = [string]$entry.execution_status
        if ($statusKey -eq 'completed') {
            $stats.completed = [int]$stats.completed + 1
        }
        elseif ($statusKey -eq 'failed') {
            $stats.failed = [int]$stats.failed + 1
        }
        elseif ($statusKey -eq 'in_progress') {
            $stats.in_progress = [int]$stats.in_progress + 1
        }

        $stats.progress_units = [double]$stats.progress_units + (Get-TaskProgressWeight -Status $status)
        $stats.last_request_id = [string]$entry.request_id
        $stats.last_execution_status = $status
        $stats.last_timestamp = [string]$entry.timestamp
    }

    $latest = if (@($normalizedEntries).Count -gt 0) { @($normalizedEntries)[-1] } else { $null }
    $latestExecution = if (@($aggregatedEntries | Where-Object { @('completed', 'failed', 'in_progress') -contains ([string]$_.execution_status).Trim().ToLowerInvariant() }).Count -gt 0) { @($aggregatedEntries | Where-Object { @('completed', 'failed', 'in_progress') -contains ([string]$_.execution_status).Trim().ToLowerInvariant() } | Sort-Object timestamp)[-1] } else { $latest }
    $effectiveLatestExecution = $latestExecution
    $effectiveLatestRef = if ($latestExecution) { Get-TaskRefInfo -Value ([string]$latestExecution.request_id) } else { $null }
    foreach ($entry in $normalizedEntries) {
        $entryRef = Get-TaskRefInfo -Value ([string]$entry.request_id)
        if ($null -eq $entryRef) {
            continue
        }

        if ($null -eq $effectiveLatestRef -or [long]$entryRef.task_number -gt [long]$effectiveLatestRef.task_number) {
            $effectiveLatestExecution = $entry
            $effectiveLatestRef = $entryRef
        }
    }
    $bridgeCurrentTaskId = ""
    if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['bridge_runtime'] -and $commandStatusPacket.bridge_runtime -and $commandStatusPacket.bridge_runtime.PSObject.Properties['current_processing'] -and $commandStatusPacket.bridge_runtime.current_processing -and $commandStatusPacket.bridge_runtime.current_processing.PSObject.Properties['task_id']) {
        $bridgeCurrentTaskId = [string]$commandStatusPacket.bridge_runtime.current_processing.task_id
    }
    $bridgeCurrentRef = Get-TaskRefInfo -Value $bridgeCurrentTaskId
    if ($bridgeCurrentRef -and ($null -eq $effectiveLatestRef -or [long]$bridgeCurrentRef.task_number -gt [long]$effectiveLatestRef.task_number)) {
        $effectiveLatestExecution = [pscustomobject]@{
            timestamp = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['generated_at']) { [string]$commandStatusPacket.generated_at } else { "" }
            request_id = [string]$bridgeCurrentTaskId
            objective_id = [string]$bridgeCurrentRef.objective
            execution_status = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['status']) { [string]$commandStatusPacket.status } else { "" }
            cycle_classification = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['status']) { [string]$commandStatusPacket.status } else { "" }
            retry_reason = if ($listenerState -and $listenerState.PSObject.Properties['last_retry_reason']) { [string]$listenerState.last_retry_reason } else { "none" }
            review_gate_passed = $null
            validator_passed = $null
            integration_compatible = $null
        }
        $effectiveLatestRef = $bridgeCurrentRef
    }
    # Use the authoritative current_objective_in_progress from next_actions.json as the filter key
    # so that cadence metrics reset immediately on objective rollover without waiting for a new journal entry.
    $nextActions = Read-JsonFileIfExists -Path $nextActionsPath
    $resultRequestId = if ($effectiveLatestExecution) { [string]$effectiveLatestExecution.request_id } elseif ($resultPacket -and $resultPacket.PSObject.Properties['request_id']) { [string]$resultPacket.request_id } else { "" }
    $resultObjectiveId = Get-ObjectiveIdFromRequestId -RequestId $resultRequestId
    $resultRef = if ($effectiveLatestExecution) { Get-TaskRefInfo -Value ([string]$effectiveLatestExecution.request_id) } else { Get-TaskRefInfo -Value $resultRequestId }
    $requestTaskId = if ($requestPacket -and $requestPacket.PSObject.Properties['task_id']) { [string]$requestPacket.task_id } else { "" }
    $requestRef = Get-TaskRefInfo -Value $requestTaskId
    $requestSyncRef = $requestRef
    $commandStatusValue = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['status']) { ([string]$commandStatusPacket.status).Trim().ToLowerInvariant() } else { '' }
    $staleGuard = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['stale_guard']) { $commandStatusPacket.stale_guard } elseif ($listenerState -and $listenerState.PSObject.Properties['last_stale_guard']) { $listenerState.last_stale_guard } else { $null }
    if ([string]::Equals($commandStatusValue, 'stale_request_ignored', [System.StringComparison]::OrdinalIgnoreCase) -and $bridgeCurrentRef -and $requestSyncRef) {
        if ([string]::Equals([string]$bridgeCurrentRef.objective, [string]$requestSyncRef.objective, [System.StringComparison]::OrdinalIgnoreCase) -and [long]$requestSyncRef.task_number -lt [long]$bridgeCurrentRef.task_number) {
            $requestSyncRef = $bridgeCurrentRef
        }
    }
    $nextActionsObjectiveId = if ($nextActions -and $nextActions.PSObject.Properties['current_objective_in_progress'] -and -not [string]::IsNullOrWhiteSpace([string]$nextActions.current_objective_in_progress)) { [string]$nextActions.current_objective_in_progress } else { "" }
    $requestObjectiveId = if ($requestRef) { [string]$requestRef.objective } else { "" }
    $activeObjectiveId = ""
    if (-not [string]::IsNullOrWhiteSpace($requestObjectiveId) -and -not [string]::IsNullOrWhiteSpace($nextActionsObjectiveId) -and -not [string]::Equals($requestObjectiveId, $nextActionsObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
        $requestObjectiveNumber = Get-ObjectiveNumericValue -Value $requestObjectiveId
        $nextActionsObjectiveNumber = Get-ObjectiveNumericValue -Value $nextActionsObjectiveId
        $resultObjectiveNumber = Get-ObjectiveNumericValue -Value $resultObjectiveId
        if (($requestObjectiveNumber -ge 0 -and $nextActionsObjectiveNumber -ge 0 -and $requestObjectiveNumber -gt $nextActionsObjectiveNumber) -or
            ($requestObjectiveNumber -ge 0 -and $resultObjectiveNumber -ge 0 -and $requestObjectiveNumber -ge $resultObjectiveNumber)) {
            $activeObjectiveId = $requestObjectiveId
        }
    }
    if ([string]::IsNullOrWhiteSpace($activeObjectiveId)) {
        if (-not [string]::IsNullOrWhiteSpace($nextActionsObjectiveId)) {
            $activeObjectiveId = $nextActionsObjectiveId
        }
        elseif ($latest) {
            $activeObjectiveId = [string]$latest.objective_id
        }
    }
    # Scope recent_entries to the current objective so stale history from prior objectives
    # does not contaminate cadence health metrics (retry_rate, intervals) after an objective rollover.
    $recentEntries = if (-not [string]::IsNullOrWhiteSpace($activeObjectiveId)) {
        @($normalizedEntries | Where-Object { ([string]$_.objective_id -eq $activeObjectiveId) -or [string]::IsNullOrWhiteSpace([string]$_.objective_id) } | Select-Object -Last 30)
    } else {
        @($normalizedEntries | Select-Object -Last 30)
    }
    $isMimAhead = $false
    $pendingCount = 0

    if ($requestSyncRef -and $resultRef) {
        if ([string]$requestSyncRef.objective -eq [string]$resultRef.objective -and [long]$requestSyncRef.task_number -gt [long]$resultRef.task_number) {
            $isMimAhead = $true
            $pendingCount = [long]$requestSyncRef.task_number - [long]$resultRef.task_number
        }
    }
    elseif ($requestSyncRef -and -not $resultRef) {
        $isMimAhead = $true
        $pendingCount = [long]$requestSyncRef.task_number
    }

    $latestRequestId = if ($effectiveLatestExecution) { [string]$effectiveLatestExecution.request_id } else { "" }
    $latestCycleClassification = if ($latest) { [string]$latest.cycle_classification } else { "" }
    $latestUsesDuplicateTelemetry =
        [string]::Equals($latestCycleClassification, 'duplicate_seen', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($commandStatusValue, 'already_processed', [System.StringComparison]::OrdinalIgnoreCase)
    $latestMatchesResultPacket =
        -not [string]::IsNullOrWhiteSpace($latestRequestId) -and
        -not [string]::IsNullOrWhiteSpace($resultRequestId) -and
        [string]::Equals($latestRequestId, $resultRequestId, [System.StringComparison]::OrdinalIgnoreCase)
    $preferResultPacketForLatestChecks = $latestUsesDuplicateTelemetry -and $latestMatchesResultPacket
    $latestReviewGatePassed = if ($preferResultPacketForLatestChecks -and $resultPacket -and $resultPacket.PSObject.Properties['review_gate'] -and $resultPacket.review_gate.PSObject.Properties['passed']) { [bool]$resultPacket.review_gate.passed } elseif ($latestExecution -and $null -ne $latestExecution.review_gate_passed) { $latestExecution.review_gate_passed } elseif ($resultPacket -and $resultPacket.PSObject.Properties['review_gate'] -and $resultPacket.review_gate.PSObject.Properties['passed']) { [bool]$resultPacket.review_gate.passed } else { $null }
    $latestValidatorPassed = if ($preferResultPacketForLatestChecks -and $resultPacket -and $resultPacket.PSObject.Properties['validator'] -and $resultPacket.validator.PSObject.Properties['passed']) { [bool]$resultPacket.validator.passed } elseif ($latestExecution -and $null -ne $latestExecution.validator_passed) { $latestExecution.validator_passed } elseif ($resultPacket -and $resultPacket.PSObject.Properties['validator'] -and $resultPacket.validator.PSObject.Properties['passed']) { [bool]$resultPacket.validator.passed } else { $null }
    $latestIntegrationCompatible = if ($preferResultPacketForLatestChecks -and $resultPacket -and $resultPacket.PSObject.Properties['integration'] -and $resultPacket.integration.PSObject.Properties['compatible']) { [bool]$resultPacket.integration.compatible } elseif ($latestExecution -and $null -ne $latestExecution.integration_compatible) { $latestExecution.integration_compatible } elseif ($resultPacket -and $resultPacket.PSObject.Properties['integration'] -and $resultPacket.integration.PSObject.Properties['compatible']) { [bool]$resultPacket.integration.compatible } else { $null }

    return [pscustomobject]@{
        entry_count = @($normalizedEntries).Count
        latest_objective_id = if ($effectiveLatestExecution) { [string]$effectiveLatestExecution.objective_id } else { "" }
        latest_request_id = $latestRequestId
        latest_execution_status = if ($effectiveLatestExecution) { [string]$effectiveLatestExecution.execution_status } else { "" }
        latest_timestamp = if ($latest) { [string]$latest.timestamp } else { "" }
        latest_cycle_classification = $latestCycleClassification
        latest_retry_reason = if ($latest) { [string]$latest.retry_reason } else { "none" }
        latest_review_gate_passed = $latestReviewGatePassed
        latest_validator_passed = $latestValidatorPassed
        latest_integration_compatible = $latestIntegrationCompatible
        result_request_id = $resultRequestId
        result_objective_id = $resultObjectiveId
        result_status = if ($resultPacket -and $resultPacket.PSObject.Properties['status']) { [string]$resultPacket.status } else { "" }
        result_generated_at = if ($resultPacket -and $resultPacket.PSObject.Properties['generated_at']) { [string]$resultPacket.generated_at } else { "" }
        result_review_gate_passed = if ($resultPacket -and $resultPacket.PSObject.Properties['review_gate'] -and $resultPacket.review_gate.PSObject.Properties['passed']) { [bool]$resultPacket.review_gate.passed } else { $null }
        result_review_gate_expected_alignment = if ($resultPacket -and $resultPacket.PSObject.Properties['review_gate'] -and $resultPacket.review_gate.PSObject.Properties['expected'] -and $resultPacket.review_gate.expected.PSObject.Properties['objective_alignment_status']) { [string]$resultPacket.review_gate.expected.objective_alignment_status } else { "" }
        result_review_gate_actual_alignment = if ($resultPacket -and $resultPacket.PSObject.Properties['review_gate'] -and $resultPacket.review_gate.PSObject.Properties['actual'] -and $resultPacket.review_gate.actual.PSObject.Properties['objective_alignment_status']) { [string]$resultPacket.review_gate.actual.objective_alignment_status } else { "" }
        result_validator_passed = if ($resultPacket -and $resultPacket.PSObject.Properties['validator'] -and $resultPacket.validator.PSObject.Properties['passed']) { [bool]$resultPacket.validator.passed } else { $null }
        result_validator_message = if ($resultPacket -and $resultPacket.PSObject.Properties['validator'] -and $resultPacket.validator.PSObject.Properties['message']) { [string]$resultPacket.validator.message } else { "" }
        result_validator_output = if ($resultPacket -and $resultPacket.PSObject.Properties['validator'] -and $resultPacket.validator.PSObject.Properties['output']) { [string]$resultPacket.validator.output } else { "" }
        result_integration_alignment_status = if ($resultPacket -and $resultPacket.PSObject.Properties['integration'] -and $resultPacket.integration.PSObject.Properties['alignment_status']) { [string]$resultPacket.integration.alignment_status } else { "" }
        result_tod_current_objective = if ($resultPacket -and $resultPacket.PSObject.Properties['integration'] -and $resultPacket.integration.PSObject.Properties['tod_current_objective']) { [string]$resultPacket.integration.tod_current_objective } else { "" }
        result_mim_objective_active = if ($resultPacket -and $resultPacket.PSObject.Properties['integration'] -and $resultPacket.integration.PSObject.Properties['mim_objective_active']) { [string]$resultPacket.integration.mim_objective_active } else { "" }
        request_task_id = $requestTaskId
        request_objective_id = if ($requestRef) { [string]$requestRef.objective } else { "" }
        request_generated_at = if ($requestPacket -and $requestPacket.PSObject.Properties['generated_at']) { [string]$requestPacket.generated_at } else { "" }
        command_status = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['status']) { [string]$commandStatusPacket.status } else { "" }
        command_status_detail = if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['detail']) { [string]$commandStatusPacket.detail } else { "" }
        stale_guard = $staleGuard
        sync = [pscustomobject]@{
            is_mim_ahead = $isMimAhead
            pending_request_count = $pendingCount
            result_request_id = $resultRequestId
            request_task_id = $requestTaskId
            result_task_number = if ($resultRef) { [long]$resultRef.task_number } else { -1L }
            request_task_number = if ($requestSyncRef) { [long]$requestSyncRef.task_number } else { -1L }
        }
        cadence_runtime = [pscustomobject]@{
            retry_streak = if ($listenerState -and $listenerState.PSObject.Properties['cadence_retry_streak']) { [int]$listenerState.cadence_retry_streak } else { 0 }
            backoff_seconds = if ($listenerState -and $listenerState.PSObject.Properties['cadence_backoff_seconds']) { [int]$listenerState.cadence_backoff_seconds } else { 0 }
            minimum_cycle_seconds = if ($listenerState -and $listenerState.PSObject.Properties['cadence_minimum_cycle_seconds']) { [int]$listenerState.cadence_minimum_cycle_seconds } else { 0 }
            planned_sleep_seconds = if ($listenerState -and $listenerState.PSObject.Properties['cadence_planned_sleep_seconds']) { [int]$listenerState.cadence_planned_sleep_seconds } else { 0 }
            last_success_at = if ($listenerState -and $listenerState.PSObject.Properties['cadence_last_success_at']) { [string]$listenerState.cadence_last_success_at } else { "" }
        }
        recent_entries = @($recentEntries)
        objective_stats = [pscustomobject]$objectiveStats
    }
}

function Get-IsoAgeSeconds {
    param([string]$Value)

    $dt = Convert-ToDateTimeOffsetOrNull -Value $Value
    if ($null -eq $dt) {
        return -1
    }

    return [math]::Round(([DateTimeOffset]::UtcNow - $dt).TotalSeconds, 1)
}

function Get-BridgeStatus {
    $triggerAck = Read-JsonFileIfExists -Path $listenerTriggerAckPath
    $pingResponse = Read-JsonFileIfExists -Path $listenerPingResponsePath
    $commandStatusPacket = Read-JsonFileIfExists -Path $listenerCommandStatusPath
    $listenerState = Read-JsonFileIfExists -Path $listenerStatePath

    $available = ($null -ne $triggerAck) -or ($null -ne $pingResponse) -or ($null -ne $listenerState)
    if (-not $available) {
        return [pscustomobject]@{
            available = $false
            status = "unknown"
            summary = "Bridge artifacts unavailable."
        }
    }

    $pollSeconds = 0
    $sharedPathKind = ""
    $currentTaskId = ""
    $currentCorrelationId = ""
    $consumerHost = ""
    $consumerService = ""
    $triggerType = ""
    $triggeredArtifact = ""
    $triggerSequence = 0
    $ackSequence = 0
    $pingAckSequence = 0
    $ackObservedAt = ""
    $pingObservedAt = ""
    $lastCycleAt = if ($listenerState -and $listenerState.PSObject.Properties['last_cycle_at']) { [string]$listenerState.last_cycle_at } else { "" }
    $listenerCycleAgeSeconds = Get-IsoAgeSeconds -Value $lastCycleAt
    $listenerPlannedSleepSeconds = if ($listenerState -and $listenerState.PSObject.Properties['cadence_planned_sleep_seconds']) {
        try { [int]$listenerState.cadence_planned_sleep_seconds } catch { 0 }
    }
    else {
        0
    }
    $missingArtifacts = New-Object System.Collections.Generic.List[string]

    if ($triggerAck) {
        if ($triggerAck.PSObject.Properties['current_task_id']) { $currentTaskId = [string]$triggerAck.current_task_id }
        if ($triggerAck.PSObject.Properties['current_correlation_id']) { $currentCorrelationId = [string]$triggerAck.current_correlation_id }
        if ($triggerAck.PSObject.Properties['consumer_host']) { $consumerHost = [string]$triggerAck.consumer_host }
        if ($triggerAck.PSObject.Properties['consumer_service']) { $consumerService = [string]$triggerAck.consumer_service }
        if ($triggerAck.PSObject.Properties['trigger_type']) { $triggerType = [string]$triggerAck.trigger_type }
        if ($triggerAck.PSObject.Properties['triggered_artifact']) { $triggeredArtifact = [string]$triggerAck.triggered_artifact }
        if ($triggerAck.PSObject.Properties['acknowledged_trigger_sequence']) { try { $triggerSequence = [long]$triggerAck.acknowledged_trigger_sequence } catch { $triggerSequence = 0 } }
        if ($triggerAck.PSObject.Properties['ack_sequence']) { try { $ackSequence = [long]$triggerAck.ack_sequence } catch { $ackSequence = 0 } }
        if ($triggerAck.PSObject.Properties['observed_at']) { $ackObservedAt = [string]$triggerAck.observed_at }
        if ($triggerAck.PSObject.Properties['bridge_runtime'] -and $triggerAck.bridge_runtime.PSObject.Properties['listener']) {
            $listenerRuntime = $triggerAck.bridge_runtime.listener
            if ($listenerRuntime.PSObject.Properties['poll_interval_seconds']) { try { $pollSeconds = [int]$listenerRuntime.poll_interval_seconds } catch { $pollSeconds = 0 } }
            if ($listenerRuntime.PSObject.Properties['shared_path_kind']) { $sharedPathKind = [string]$listenerRuntime.shared_path_kind }
        }
    }
    else {
        [void]$missingArtifacts.Add('trigger_ack')
    }

    if ($pingResponse) {
        if ([string]::IsNullOrWhiteSpace($currentTaskId) -and $pingResponse.PSObject.Properties['current_task_id']) { $currentTaskId = [string]$pingResponse.current_task_id }
        if ([string]::IsNullOrWhiteSpace($currentCorrelationId) -and $pingResponse.PSObject.Properties['current_correlation_id']) { $currentCorrelationId = [string]$pingResponse.current_correlation_id }
        if ([string]::IsNullOrWhiteSpace($consumerHost) -and $pingResponse.PSObject.Properties['consumer_host']) { $consumerHost = [string]$pingResponse.consumer_host }
        if ([string]::IsNullOrWhiteSpace($consumerService) -and $pingResponse.PSObject.Properties['consumer_service']) { $consumerService = [string]$pingResponse.consumer_service }
        if ([string]::IsNullOrWhiteSpace($triggerType) -and $pingResponse.PSObject.Properties['response_to']) { $triggerType = [string]$pingResponse.response_to }
        if ([string]::IsNullOrWhiteSpace($triggeredArtifact) -and $pingResponse.PSObject.Properties['response_to_artifact']) { $triggeredArtifact = [string]$pingResponse.response_to_artifact }
        if ($pingResponse.PSObject.Properties['ack_sequence']) { try { $pingAckSequence = [long]$pingResponse.ack_sequence } catch { $pingAckSequence = 0 } }
        if ($triggerSequence -le 0 -and $pingResponse.PSObject.Properties['acknowledged_trigger_sequence']) { try { $triggerSequence = [long]$pingResponse.acknowledged_trigger_sequence } catch { $triggerSequence = 0 } }
        if ($pingResponse.PSObject.Properties['observed_at']) { $pingObservedAt = [string]$pingResponse.observed_at }
        if ($pollSeconds -le 0 -and $pingResponse.PSObject.Properties['bridge_runtime'] -and $pingResponse.bridge_runtime.PSObject.Properties['listener']) {
            $listenerRuntime = $pingResponse.bridge_runtime.listener
            if ($listenerRuntime.PSObject.Properties['poll_interval_seconds']) { try { $pollSeconds = [int]$listenerRuntime.poll_interval_seconds } catch { $pollSeconds = 0 } }
            if ([string]::IsNullOrWhiteSpace($sharedPathKind) -and $listenerRuntime.PSObject.Properties['shared_path_kind']) { $sharedPathKind = [string]$listenerRuntime.shared_path_kind }
        }
    }
    else {
        [void]$missingArtifacts.Add('ping_response')
    }

    if (-not $listenerState) {
        [void]$missingArtifacts.Add('listener_state')
    }

    if ($commandStatusPacket -and $commandStatusPacket.PSObject.Properties['bridge_runtime'] -and $commandStatusPacket.bridge_runtime -and $commandStatusPacket.bridge_runtime.PSObject.Properties['current_processing'] -and $commandStatusPacket.bridge_runtime.current_processing) {
        if ([string]::IsNullOrWhiteSpace($currentTaskId) -and $commandStatusPacket.bridge_runtime.current_processing.PSObject.Properties['task_id']) {
            $currentTaskId = [string]$commandStatusPacket.bridge_runtime.current_processing.task_id
        }
        elseif ($commandStatusPacket.bridge_runtime.current_processing.PSObject.Properties['task_id']) {
            $commandCurrentTaskId = [string]$commandStatusPacket.bridge_runtime.current_processing.task_id
            $commandTaskRef = Get-TaskRefInfo -Value $commandCurrentTaskId
            $currentTaskRef = Get-TaskRefInfo -Value $currentTaskId
            if ($commandTaskRef -and ($null -eq $currentTaskRef -or [long]$commandTaskRef.task_number -gt [long]$currentTaskRef.task_number)) {
                $currentTaskId = $commandCurrentTaskId
            }
        }

        if ([string]::IsNullOrWhiteSpace($currentCorrelationId) -and $commandStatusPacket.bridge_runtime.current_processing.PSObject.Properties['correlation_id']) {
            $currentCorrelationId = [string]$commandStatusPacket.bridge_runtime.current_processing.correlation_id
        }
    }

    if ([string]::IsNullOrWhiteSpace($currentTaskId) -and $listenerState -and $listenerState.PSObject.Properties['last_processed_request_id']) {
        $currentTaskId = [string]$listenerState.last_processed_request_id
    }

    if ([string]::IsNullOrWhiteSpace($currentTaskId) -and $listenerState -and $listenerState.PSObject.Properties['high_watermark_request_id']) {
        $currentTaskId = [string]$listenerState.high_watermark_request_id
    }

    $taskObjectiveId = Get-ObjectiveIdFromRequestId -RequestId $currentTaskId
    $canonicalMimObjective = Get-CanonicalMimObjective
    $canonicalObjectiveId = if ($canonicalMimObjective) { [string]$canonicalMimObjective.objective_id } else { "" }
    $objectiveMismatch = $false
    $objectiveMismatchDetail = ""
    if ($canonicalMimObjective -and [bool]$canonicalMimObjective.available -and -not [string]::IsNullOrWhiteSpace($canonicalObjectiveId) -and -not [string]::IsNullOrWhiteSpace($taskObjectiveId)) {
        if (-not [string]::Equals($canonicalObjectiveId, $taskObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $objectiveMismatch = $true
            $objectiveMismatchDetail = "canonical_objective={0}; live_task_objective={1}; source={2}" -f $canonicalObjectiveId, $taskObjectiveId, [string]$canonicalMimObjective.source
        }
    }

    $listenerFreshThreshold = if ($pollSeconds -gt 0) {
        [math]::Max(15, [math]::Max(($pollSeconds * 6), ($listenerPlannedSleepSeconds + 5)))
    }
    else {
        [math]::Max(30, ($listenerPlannedSleepSeconds + 5))
    }
    $listenerFresh = ($listenerCycleAgeSeconds -ge 0) -and ($listenerCycleAgeSeconds -le $listenerFreshThreshold)
    $sequenceAware = ($ackSequence -gt 0) -and ($triggerSequence -gt 0)
    $ackObservedAgeSeconds = Get-IsoAgeSeconds -Value $ackObservedAt
    $pingObservedAgeSeconds = Get-IsoAgeSeconds -Value $pingObservedAt
    $recentObservedBridgePacket = (($ackObservedAgeSeconds -ge 0) -and ($ackObservedAgeSeconds -le $listenerFreshThreshold)) -or (($pingObservedAgeSeconds -ge 0) -and ($pingObservedAgeSeconds -le $listenerFreshThreshold))
    $listenerFreshnessState = if ($listenerFresh) {
        'fresh'
    }
    elseif ($listenerCycleAgeSeconds -lt 0) {
        'unknown'
    }
    elseif ($recentObservedBridgePacket) {
        'startup_lag'
    }
    else {
        'stale'
    }
    $sequenceState = if ($sequenceAware) {
        'sequence_aware'
    }
    elseif (($ackSequence -gt 0) -or ($triggerSequence -gt 0) -or ($pingAckSequence -gt 0)) {
        'partial'
    }
    else {
        'missing'
    }
    $artifactCompleteness = if ($missingArtifacts.Count -eq 0) { 'complete' } else { 'partial' }

    $status = "ok"
    $statusReason = 'healthy'
    if ($objectiveMismatch) {
        $status = 'warning'
        $statusReason = 'objective_mismatch'
    }
    elseif ($listenerFreshnessState -eq 'stale') {
        $status = 'warning'
        $statusReason = 'listener_stale'
    }
    elseif ($listenerFreshnessState -eq 'startup_lag') {
        $status = 'warning'
        $statusReason = 'listener_startup_lag'
    }
    elseif ($sequenceState -ne 'sequence_aware') {
        $status = 'warning'
        $statusReason = 'sequence_incomplete'
    }
    elseif ($artifactCompleteness -ne 'complete') {
        $status = 'warning'
        $statusReason = 'artifact_incomplete'
    }

    $summary = if ($objectiveMismatch) {
        "Bridge packets are live, but objective routing is stale: canonical MIM export targets objective $canonicalObjectiveId while live task requests are objective $taskObjectiveId. Restart the live publisher to realign task packets."
    }
    elseif ($status -eq "ok") {
        "Bridge packets are live, sequence-aware, and listener heartbeat is fresh."
    }
    elseif ($listenerFreshnessState -eq 'startup_lag') {
        "Bridge packets are arriving, but listener heartbeat publication is still catching up after startup or recycle."
    }
    elseif ($listenerFreshnessState -eq 'stale') {
        "Bridge artifacts exist, but listener heartbeat looks stale."
    }
    elseif ($sequenceState -ne 'sequence_aware') {
        "Bridge artifacts are present, but sequence metadata is still incomplete."
    }
    else {
        "Bridge artifacts are present, but some live bridge fields are still incomplete."
    }

    return [pscustomobject]@{
        available = $true
        status = $status
        status_reason = $statusReason
        summary = $summary
        shared_path_kind = $sharedPathKind
        poll_interval_seconds = $pollSeconds
        current_task_id = $currentTaskId
        current_correlation_id = $currentCorrelationId
        latest_trigger_type = $triggerType
        latest_triggered_artifact = $triggeredArtifact
        latest_trigger_sequence = $triggerSequence
        latest_ack_sequence = $ackSequence
        latest_ping_ack_sequence = $pingAckSequence
        consumer_host = $consumerHost
        consumer_service = $consumerService
        listener_cycle_age_seconds = $listenerCycleAgeSeconds
        listener_fresh_threshold_seconds = $listenerFreshThreshold
        listener_fresh = $listenerFresh
        listener_freshness_state = $listenerFreshnessState
        trigger_ack_age_seconds = $ackObservedAgeSeconds
        ping_response_age_seconds = $pingObservedAgeSeconds
        sequence_state = $sequenceState
        artifact_completeness = $artifactCompleteness
        missing_artifacts = @($missingArtifacts)
        canonical_mim_objective_id = $canonicalObjectiveId
        canonical_mim_objective_source = if ($canonicalMimObjective) { [string]$canonicalMimObjective.source } else { "" }
        canonical_mim_objective_path = if ($canonicalMimObjective) { [string]$canonicalMimObjective.path } else { "" }
        task_request_objective_id = $taskObjectiveId
        objective_mismatch = $objectiveMismatch
        objective_mismatch_detail = $objectiveMismatchDetail
        trigger_ack = [pscustomobject]@{
            generated_at = if ($triggerAck -and $triggerAck.PSObject.Properties['generated_at']) { [string]$triggerAck.generated_at } else { "" }
            observed_at = $ackObservedAt
        }
        ping_response = [pscustomobject]@{
            generated_at = if ($pingResponse -and $pingResponse.PSObject.Properties['generated_at']) { [string]$pingResponse.generated_at } else { "" }
            observed_at = $pingObservedAt
        }
        listener = [pscustomobject]@{
            last_cycle_at = $lastCycleAt
            last_execution_at = if ($listenerState -and $listenerState.PSObject.Properties['last_execution_at']) { [string]$listenerState.last_execution_at } else { "" }
            last_outbound_sequence = if ($listenerState -and $listenerState.PSObject.Properties['last_outbound_sequence']) { [long]$listenerState.last_outbound_sequence } else { 0 }
        }
    }
}

function Get-RecoveryWatchdogStatus {
    $doc = Read-JsonFileIfExists -Path $recoveryWatchdogStatePath
    $watchdogItem = if (Test-Path -Path $recoveryWatchdogStatePath) { Get-Item -Path $recoveryWatchdogStatePath } else { $null }
    $listenerItem = if (Test-Path -Path $listenerStatePath) { Get-Item -Path $listenerStatePath } else { $null }
    $requestItem = if (Test-Path -Path $listenerRequestPath) { Get-Item -Path $listenerRequestPath } else { $null }
    $resultItem = if (Test-Path -Path $listenerResultPath) { Get-Item -Path $listenerResultPath } else { $null }
    $nowUtc = (Get-Date).ToUniversalTime()

    $watchdogMtimeUtc = if ($watchdogItem) { $watchdogItem.LastWriteTimeUtc } else { $null }
    $referenceCandidates = @()
    foreach ($candidate in @($listenerItem, $requestItem, $resultItem)) {
        if ($candidate) {
            $referenceCandidates += $candidate.LastWriteTimeUtc
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

    $watchdogFileAgeSeconds = -1
    if ($watchdogMtimeUtc) {
        $watchdogFileAgeSeconds = [int][Math]::Floor(($nowUtc - $watchdogMtimeUtc).TotalSeconds)
    }

    $isStale = $false
    $staleReason = 'none'
    if ($watchdogSkewSeconds -ge 300) {
        $isStale = $true
        $staleReason = 'watchdog_older_than_listener_truth'
    }

    if ($null -eq $doc) {
        return [pscustomobject]@{
            available = $false
            state = "unknown"
            effective_state = "unknown"
            stale = $false
            stale_reason = "missing"
            bridge_smoke = $null
            task_state = "idle"
            progress_classification = "no_progress_but_heartbeats_present"
            last_check_at = ""
            last_issue = ""
            last_recovery_action = ""
            last_recovery_ok = $null
            last_task_heartbeat = ""
            heartbeat_age_seconds = -1
            stall_threshold_seconds = -1
            recovery_attempts = 0
            consecutive_freezes = 0
            last_recovery_time = ""
            file_age_seconds = $watchdogFileAgeSeconds
            watchdog_mtime_utc = if ($watchdogMtimeUtc) { $watchdogMtimeUtc.ToString('o') } else { '' }
            listener_reference_utc = if ($referenceLatestUtc) { $referenceLatestUtc.ToString('o') } else { '' }
            watchdog_skew_seconds = $watchdogSkewSeconds
        }
    }

    $state = if ($doc.PSObject.Properties["state"]) { [string]$doc.state } else { "unknown" }
    return [pscustomobject]@{
        available = $true
        state = $state
        effective_state = if ($isStale) { 'stale' } else { $state }
        stale = $isStale
        stale_reason = $staleReason
        bridge_smoke = if ($doc.PSObject.Properties['bridge_smoke']) { $doc.bridge_smoke } else { $null }
        task_state = if ($doc.PSObject.Properties["task_state"]) { [string]$doc.task_state } else { "idle" }
        progress_classification = if ($doc.PSObject.Properties["progress_classification"]) { [string]$doc.progress_classification } else { "no_progress_but_heartbeats_present" }
        last_check_at = if ($doc.PSObject.Properties["last_check_at"]) { [string]$doc.last_check_at } else { "" }
        last_issue = if ($doc.PSObject.Properties["last_issue"]) { [string]$doc.last_issue } else { "" }
        last_recovery_action = if ($doc.PSObject.Properties["last_recovery_action"]) { [string]$doc.last_recovery_action } else { "" }
        last_recovery_ok = if ($doc.PSObject.Properties["last_recovery_ok"]) { $doc.last_recovery_ok } else { $null }
        last_task_heartbeat = if ($doc.PSObject.Properties["last_task_heartbeat"]) { [string]$doc.last_task_heartbeat } else { "" }
        heartbeat_age_seconds = if ($doc.PSObject.Properties["heartbeat_age_seconds"]) { [int]$doc.heartbeat_age_seconds } else { -1 }
        stall_threshold_seconds = if ($doc.PSObject.Properties["stall_threshold_seconds"]) { [int]$doc.stall_threshold_seconds } else { -1 }
        recovery_attempts = if ($doc.PSObject.Properties["recovery_attempts"]) { [int]$doc.recovery_attempts } else { 0 }
        consecutive_freezes = if ($doc.PSObject.Properties["consecutive_freezes"]) { [int]$doc.consecutive_freezes } else { 0 }
        last_recovery_time = if ($doc.PSObject.Properties["last_recovery_time"]) { [string]$doc.last_recovery_time } else { "" }
        file_age_seconds = $watchdogFileAgeSeconds
        watchdog_mtime_utc = if ($watchdogMtimeUtc) { $watchdogMtimeUtc.ToString('o') } else { '' }
        listener_reference_utc = if ($referenceLatestUtc) { $referenceLatestUtc.ToString('o') } else { '' }
        watchdog_skew_seconds = $watchdogSkewSeconds
    }
}

function Get-SelfHealthMaintenanceStatus {
    $doc = Read-JsonFileIfExists -Path $selfHealthMaintenanceReportPath
    if ($null -eq $doc) {
        return [pscustomobject]@{
            available = $false
            path = $selfHealthMaintenanceReportPath
            overall_status = "unknown"
            overall_severity = "unknown"
            source_severity = "unknown"
            severity_reason = "report_unavailable"
            invocation_mode = "unknown"
            summary = "Self-health maintenance report unavailable."
            generated_at = ""
            generated_age_seconds = -1
            duration_seconds = -1
            stale = $false
            stale_reason = 'missing'
            source_overall_status = 'unknown'
            source_overall_severity = 'unknown'
            source_summary = 'Self-health maintenance report unavailable.'
            recommendation = ""
            history = [pscustomobject]@{
                scheduled_runs_considered = 0
                scheduled_fallback_runs_including_current = 0
                threshold_runs = 0
                window_hours = 0
                threshold_exceeded = $false
            }
        }
    }

    $history = if ($doc.PSObject.Properties['history'] -and $doc.history) { $doc.history } else { $null }
    $recommendations = if ($doc.PSObject.Properties['recommendations']) { @($doc.recommendations) } else { @() }
    $generatedAt = if ($doc.PSObject.Properties['generated_at']) { [string]$doc.generated_at } else { "" }
    $generatedAgeSeconds = Get-IsoAgeSeconds -Value $generatedAt
    $sourceOverallStatus = if ($doc.PSObject.Properties['overall_status']) { [string]$doc.overall_status } else { "unknown" }
    $sourceOverallSeverity = if ($doc.PSObject.Properties['overall_severity']) { [string]$doc.overall_severity } else { "unknown" }
    $sourceSummary = if ($doc.PSObject.Properties['summary']) { [string]$doc.summary } else { "" }
    $sourceSeverityReason = if ($doc.PSObject.Properties['severity_reason']) { [string]$doc.severity_reason } else { "unknown" }
    $liveWatchdog = Get-RecoveryWatchdogStatus
    $watchdogEffectiveState = if ($liveWatchdog -and $liveWatchdog.PSObject.Properties['effective_state'] -and -not [string]::IsNullOrWhiteSpace([string]$liveWatchdog.effective_state)) {
        [string]$liveWatchdog.effective_state
    }
    elseif ($liveWatchdog -and $liveWatchdog.PSObject.Properties['state']) {
        [string]$liveWatchdog.state
    }
    else {
        'unknown'
    }
    $watchdogHealthy = [string]::Equals($watchdogEffectiveState, 'healthy', [System.StringComparison]::OrdinalIgnoreCase)
    $reportStale = ($generatedAgeSeconds -ge 1800)
    $supersededByLiveWatchdog = $reportStale -and $watchdogHealthy
    $effectiveOverallStatus = if ($supersededByLiveWatchdog) { 'healthy' } else { $sourceOverallStatus }
    $effectiveOverallSeverity = if ($supersededByLiveWatchdog) { 'info' } else { $sourceOverallSeverity }
    $effectiveSeverityReason = if ($supersededByLiveWatchdog) { 'stale_report_superseded_by_live_watchdog' } else { $sourceSeverityReason }
    $effectiveSummary = if ($supersededByLiveWatchdog) {
        'Latest maintenance report is stale relative to the live watchdog state; current recovery telemetry is healthy.'
    }
    else {
        $sourceSummary
    }

    return [pscustomobject]@{
        available = $true
        path = $selfHealthMaintenanceReportPath
        overall_status = $effectiveOverallStatus
        overall_severity = $effectiveOverallSeverity
        source_severity = if ($doc.PSObject.Properties['source_severity']) { [string]$doc.source_severity } else { "unknown" }
        severity_reason = $effectiveSeverityReason
        invocation_mode = if ($doc.PSObject.Properties['invocation_mode']) { [string]$doc.invocation_mode } else { "unknown" }
        summary = $effectiveSummary
        generated_at = $generatedAt
        generated_age_seconds = $generatedAgeSeconds
        duration_seconds = if ($doc.PSObject.Properties['duration_seconds']) { [double]$doc.duration_seconds } else { -1 }
        stale = $supersededByLiveWatchdog
        stale_reason = if ($supersededByLiveWatchdog) { 'superseded_by_live_watchdog' } elseif ($reportStale) { 'aged_report' } else { 'none' }
        source_overall_status = $sourceOverallStatus
        source_overall_severity = $sourceOverallSeverity
        source_summary = $sourceSummary
        recommendation = if (@($recommendations).Count -gt 0) { [string]$recommendations[0] } else { "" }
        history = [pscustomobject]@{
            scheduled_runs_considered = if ($history -and $history.PSObject.Properties['scheduled_runs_considered']) { [int]$history.scheduled_runs_considered } else { 0 }
            scheduled_fallback_runs_including_current = if ($history -and $history.PSObject.Properties['scheduled_fallback_runs_including_current']) { [int]$history.scheduled_fallback_runs_including_current } else { 0 }
            threshold_runs = if ($history -and $history.PSObject.Properties['threshold_runs']) { [int]$history.threshold_runs } else { 0 }
            window_hours = if ($history -and $history.PSObject.Properties['window_hours']) { [int]$history.window_hours } else { 0 }
            threshold_exceeded = if ($history -and $history.PSObject.Properties['threshold_exceeded']) { [bool]$history.threshold_exceeded } else { $false }
        }
    }
}

function Get-SteadyStateHealth {
    param(
        $ListenerActivity,
        $RecoveryWatchdog,
        $CadenceHealth,
        [string]$StateWarning,
        [bool]$UsingListenerOnly
    )

    $build = Read-JsonFileIfExists -Path $currentBuildStatePath
    $coordination = Read-JsonFileIfExists -Path $coordinationEscalationPath
    $stallState = Read-JsonFileIfExists -Path $regressionStallStatePath

    $regressionAvailable = $false
    $passed = 0
    $failed = 0
    $total = 0
    $regressionGeneratedAt = ""
    if ($build -and $build.PSObject.Properties['last_regression_result'] -and $build.last_regression_result) {
        $regressionAvailable = $true
        try { $passed = [int]$build.last_regression_result.passed } catch { $passed = 0 }
        try { $failed = [int]$build.last_regression_result.failed } catch { $failed = 0 }
        try { $total = [int]$build.last_regression_result.total } catch { $total = 0 }
        $regressionGeneratedAt = if ($build.last_regression_result.PSObject.Properties['generated_at']) { [string]$build.last_regression_result.generated_at } else { "" }
    }

    $pendingCoordination = $false
    $coordinationStatus = "unknown"
    if ($coordination) {
        $pendingCoordination = -not [string]::IsNullOrWhiteSpace([string]$coordination.pending_request_id)
        if ($coordination.PSObject.Properties['last_ack_status']) {
            $coordinationStatus = [string]$coordination.last_ack_status
        }
    }

    $unchangedCycles = 0
    if ($stallState -and $stallState.PSObject.Properties['unchanged_cycles']) {
        try { $unchangedCycles = [int]$stallState.unchanged_cycles } catch { $unchangedCycles = 0 }
    }

    $loopIdleSec = -1
    if ($CadenceHealth -and $CadenceHealth.PSObject.Properties['stream'] -and $CadenceHealth.stream.PSObject.Properties['loop_idle_sec']) {
        try { $loopIdleSec = [double]$CadenceHealth.stream.loop_idle_sec } catch { $loopIdleSec = -1 }
    }
    if ($loopIdleSec -lt 0 -and $RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['heartbeat_age_seconds']) {
        try { $loopIdleSec = [double]$RecoveryWatchdog.heartbeat_age_seconds } catch { $loopIdleSec = -1 }
    }

    $cadenceSeverity = if ($CadenceHealth -and $CadenceHealth.PSObject.Properties['governance'] -and $CadenceHealth.governance.PSObject.Properties['adjusted_severity']) { [string]$CadenceHealth.governance.adjusted_severity } elseif ($CadenceHealth -and $CadenceHealth.PSObject.Properties['severity']) { [string]$CadenceHealth.severity } else { "unknown" }
    $listenerMode = if ($UsingListenerOnly) { "listener_telemetry" } else { "state_plus_listener" }
    $cadenceNoiseSuppressed = [bool]($CadenceHealth -and $CadenceHealth.PSObject.Properties['governance'] -and $CadenceHealth.governance.PSObject.Properties['noise_suppressed'] -and $CadenceHealth.governance.noise_suppressed)
    $regressionAgeSeconds = Get-IsoAgeSeconds -Value $regressionGeneratedAt
    $watchdogEffectiveState = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['effective_state'] -and -not [string]::IsNullOrWhiteSpace([string]$RecoveryWatchdog.effective_state)) { [string]$RecoveryWatchdog.effective_state } elseif ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['state']) { [string]$RecoveryWatchdog.state } else { 'unknown' }
    $watchdogHealthy = [string]::Equals($watchdogEffectiveState, 'healthy', [System.StringComparison]::OrdinalIgnoreCase)
    $bridgeStatus = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties['bridge_smoke']) { $RecoveryWatchdog.bridge_smoke } else { $null }
    $bridgeHealthy = $false
    if ($bridgeStatus -and $bridgeStatus.PSObject.Properties['passed']) {
        $bridgeHealthy = [bool]$bridgeStatus.passed
    }
    elseif ($bridgeStatus -and $bridgeStatus.PSObject.Properties['available'] -and $bridgeStatus.PSObject.Properties['status']) {
        $bridgeHealthy = ([bool]$bridgeStatus.available -and [string]::Equals([string]$bridgeStatus.status, 'ok', [System.StringComparison]::OrdinalIgnoreCase))
    }
    else {
        $bridgeStatus = Get-BridgeStatus
        $bridgeHealthy = ($bridgeStatus -and [bool]$bridgeStatus.available -and [string]::Equals([string]$bridgeStatus.status, 'ok', [System.StringComparison]::OrdinalIgnoreCase))
    }
    $staleRegressionSuperseded = $regressionAvailable -and ($failed -gt 0) -and ($regressionAgeSeconds -ge 3600) -and $watchdogHealthy -and $bridgeHealthy -and [string]::Equals($cadenceSeverity, 'ok', [System.StringComparison]::OrdinalIgnoreCase)

    $status = "unknown"
    $summary = "Steady state unavailable"
    if ($regressionAvailable -and $failed -le 0 -and -not $pendingCoordination -and $unchangedCycles -eq 0) {
        if ($cadenceNoiseSuppressed -and [string]::Equals($cadenceSeverity, 'ok', [System.StringComparison]::OrdinalIgnoreCase)) {
            $status = "ok"
            $summary = "Regression is green; cadence noise is present but execution truth remains healthy."
        }
        elseif ([string]::Equals($cadenceSeverity, 'critical', [System.StringComparison]::OrdinalIgnoreCase) -or ($loopIdleSec -ge 300)) {
            $status = "warning"
            $summary = "Regression is green, but live cadence looks stale."
        }
        elseif ([string]::Equals($cadenceSeverity, 'warning', [System.StringComparison]::OrdinalIgnoreCase) -or ($loopIdleSec -ge 180)) {
            $status = "warning"
            $summary = "Regression is green and coordination is clear; cadence needs watching."
        }
        else {
            $status = "ok"
            $summary = "Regression is green, coordination is clear, and listener cadence is healthy."
        }
    }
    elseif ($staleRegressionSuperseded) {
        $status = 'ok'
        $summary = 'Historical regression failures are present, but the regression report is stale and current bridge, cadence, and watchdog telemetry are healthy.'
    }
    elseif ($regressionAvailable -and $failed -gt 0) {
        $status = "critical"
        $summary = "Regression failures remain; system is not in steady state."
    }
    elseif ($pendingCoordination) {
        $status = "warning"
        $summary = "Coordination is still pending despite current listener activity."
    }

    return [pscustomobject]@{
        available = ($regressionAvailable -or $null -ne $CadenceHealth)
        status = $status
        summary = $summary
        regression_green = ($regressionAvailable -and $failed -le 0)
        regression_generated_at = $regressionGeneratedAt
        passed = $passed
        failed = $failed
        total = $total
        pending_coordination = $pendingCoordination
        coordination_status = $coordinationStatus
        unchanged_cycles = $unchangedCycles
        loop_idle_sec = $loopIdleSec
        cadence_severity = $cadenceSeverity
        listener_mode = $listenerMode
        regression_age_seconds = $regressionAgeSeconds
        regression_report_stale = $staleRegressionSuperseded
        source_warning = $StateWarning
    }
}

function Get-ProjectDataSources {
    param(
        [bool]$UsingListenerOnly,
        [string]$StateWarning,
        $ListenerActivity
    )

    return [pscustomobject]@{
        project_status_mode = if ($UsingListenerOnly) { "listener_telemetry_fallback" } else { "state_plus_listener" }
        listener_journal_available = [bool]($ListenerActivity -and [int]$ListenerActivity.entry_count -gt 0)
        current_build_state_available = [bool](Test-Path -Path $currentBuildStatePath)
        coordination_state_available = [bool](Test-Path -Path $coordinationEscalationPath)
        state_warning = $StateWarning
    }
}

function Get-MimProposalFromListenerRequest {
    $requestPacket = Read-JsonFileIfExists -Path $listenerRequestPath
    if ($null -eq $requestPacket) {
        return [pscustomobject]@{
            available = $false
            source = 'mim_listener_task_request'
            suppressed = $false
            suppression_reason = ''
        }
    }

    $taskId = if ($requestPacket.PSObject.Properties['task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$requestPacket.task_id)) { [string]$requestPacket.task_id } elseif ($requestPacket.PSObject.Properties['request_id']) { [string]$requestPacket.request_id } else { '' }
    $objectiveId = if ($requestPacket.PSObject.Properties['objective_id']) { [string]$requestPacket.objective_id } else { '' }
    $generatedAt = if ($requestPacket.PSObject.Properties['generated_at']) { [string]$requestPacket.generated_at } else { '' }
    $normalizedObjectiveId = ''
    $commandStatusPacket = Read-JsonFileIfExists -Path $listenerCommandStatusPath
    $effectiveTaskId = ''
    $commandStatus = ''

    if (-not [string]::IsNullOrWhiteSpace($taskId)) {
        $requestRef = Get-TaskRefInfo -Value $taskId
        if ($requestRef) {
            $normalizedObjectiveId = [string]$requestRef.objective
        }
    }

    if ([string]::IsNullOrWhiteSpace($normalizedObjectiveId) -and -not [string]::IsNullOrWhiteSpace($objectiveId)) {
        $objectiveMatch = [regex]::Match($objectiveId, 'objective-(?<objective>\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($objectiveMatch.Success) {
            $normalizedObjectiveId = [string]$objectiveMatch.Groups['objective'].Value
        }
        else {
            $normalizedObjectiveId = $objectiveId
        }
    }

    if ($commandStatusPacket) {
        if ($commandStatusPacket.PSObject.Properties['status']) {
            $commandStatus = [string]$commandStatusPacket.status
        }
        if ($commandStatusPacket.PSObject.Properties['bridge_runtime'] -and $commandStatusPacket.bridge_runtime -and $commandStatusPacket.bridge_runtime.PSObject.Properties['current_processing'] -and $commandStatusPacket.bridge_runtime.current_processing -and $commandStatusPacket.bridge_runtime.current_processing.PSObject.Properties['task_id']) {
            $effectiveTaskId = [string]$commandStatusPacket.bridge_runtime.current_processing.task_id
        }
    }

    $requestRef = Get-TaskRefInfo -Value $taskId
    $effectiveTaskRef = Get-TaskRefInfo -Value $effectiveTaskId
    $staleBackfillSuperseded = $false
    if (
        $requestRef -and
        $effectiveTaskRef -and
        [string]::Equals([string]$requestRef.objective, [string]$effectiveTaskRef.objective, [System.StringComparison]::OrdinalIgnoreCase) -and
        ([long]$effectiveTaskRef.task_number -gt [long]$requestRef.task_number) -and
        @('stale_request_ignored', 'stale_backfill_ignored') -contains $commandStatus
    ) {
        $staleBackfillSuperseded = $true
    }

    $acceptanceCriteria = @()
    if ($requestPacket.PSObject.Properties['acceptance_criteria']) {
        $acceptanceCriteria = @($requestPacket.acceptance_criteria | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $constraints = @()
    if ($requestPacket.PSObject.Properties['constraints']) {
        $constraints = @($requestPacket.constraints | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ($staleBackfillSuperseded) {
        return [pscustomobject]@{
            available = $false
            source = 'mim_listener_task_request'
            suppressed = $true
            suppression_reason = 'stale_backfill_superseded'
            task_id = $taskId
            effective_task_id = $effectiveTaskId
            objective_id = $objectiveId
            normalized_objective_id = $normalizedObjectiveId
            generated_at = $generatedAt
            correlation_id = if ($requestPacket.PSObject.Properties['correlation_id']) { [string]$requestPacket.correlation_id } else { '' }
            title = if ($requestPacket.PSObject.Properties['title'] -and -not [string]::IsNullOrWhiteSpace([string]$requestPacket.title)) { [string]$requestPacket.title } elseif ($requestPacket.PSObject.Properties['project_question'] -and -not [string]::IsNullOrWhiteSpace([string]$requestPacket.project_question)) { [string]$requestPacket.project_question } else { '' }
            scope = if ($requestPacket.PSObject.Properties['scope']) { [string]$requestPacket.scope } else { '' }
            priority = if ($requestPacket.PSObject.Properties['priority']) { [string]$requestPacket.priority } else { '' }
            notes = if ($requestPacket.PSObject.Properties['notes']) { [string]$requestPacket.notes } else { '' }
            source_service = if ($requestPacket.PSObject.Properties['source_service']) { [string]$requestPacket.source_service } else { '' }
            source_instance_id = if ($requestPacket.PSObject.Properties['source_instance_id']) { [string]$requestPacket.source_instance_id } else { '' }
            acceptance_criteria = @($acceptanceCriteria)
            acceptance_criteria_count = @($acceptanceCriteria).Count
            constraints = @($constraints)
            constraints_count = @($constraints).Count
        }
    }

    return [pscustomobject]@{
        available = $true
        source = 'mim_listener_task_request'
        suppressed = $false
        suppression_reason = ''
        task_id = $taskId
        effective_task_id = $effectiveTaskId
        objective_id = $objectiveId
        normalized_objective_id = $normalizedObjectiveId
        generated_at = $generatedAt
        correlation_id = if ($requestPacket.PSObject.Properties['correlation_id']) { [string]$requestPacket.correlation_id } else { '' }
        title = if ($requestPacket.PSObject.Properties['title'] -and -not [string]::IsNullOrWhiteSpace([string]$requestPacket.title)) { [string]$requestPacket.title } elseif ($requestPacket.PSObject.Properties['project_question'] -and -not [string]::IsNullOrWhiteSpace([string]$requestPacket.project_question)) { [string]$requestPacket.project_question } else { '' }
        scope = if ($requestPacket.PSObject.Properties['scope']) { [string]$requestPacket.scope } else { '' }
        priority = if ($requestPacket.PSObject.Properties['priority']) { [string]$requestPacket.priority } else { '' }
        notes = if ($requestPacket.PSObject.Properties['notes']) { [string]$requestPacket.notes } else { '' }
        source_service = if ($requestPacket.PSObject.Properties['source_service']) { [string]$requestPacket.source_service } else { '' }
        source_instance_id = if ($requestPacket.PSObject.Properties['source_instance_id']) { [string]$requestPacket.source_instance_id } else { '' }
        acceptance_criteria = @($acceptanceCriteria)
        acceptance_criteria_count = @($acceptanceCriteria).Count
        constraints = @($constraints)
        constraints_count = @($constraints).Count
    }
}

function Get-MimProposalConflict {
    param(
        $MimProposal,
        [string]$SelectedObjectiveId,
        $BridgeStatus
    )

    if ($null -eq $MimProposal -or -not [bool]$MimProposal.available) {
        return [pscustomobject]@{
            available = $false
            status = 'none'
            conflict_detected = $false
            summary = 'No live MIM proposal is available.'
            proposal_objective_id = ''
            selected_objective_id = Normalize-ObjectiveIdValue -Value $SelectedObjectiveId
            canonical_mim_objective_id = if ($BridgeStatus -and $BridgeStatus.PSObject.Properties['canonical_mim_objective_id']) { Normalize-ObjectiveIdValue -Value ([string]$BridgeStatus.canonical_mim_objective_id) } else { '' }
            live_task_objective_id = if ($BridgeStatus -and $BridgeStatus.PSObject.Properties['task_request_objective_id']) { Normalize-ObjectiveIdValue -Value ([string]$BridgeStatus.task_request_objective_id) } else { '' }
            recommended_action = ''
        }
    }

    $proposalObjectiveId = Normalize-ObjectiveIdValue -Value $(if ($MimProposal.PSObject.Properties['normalized_objective_id']) { [string]$MimProposal.normalized_objective_id } else { [string]$MimProposal.objective_id })
    $selectedNormalizedObjectiveId = Normalize-ObjectiveIdValue -Value $SelectedObjectiveId
    $canonicalObjectiveId = if ($BridgeStatus -and $BridgeStatus.PSObject.Properties['canonical_mim_objective_id']) { Normalize-ObjectiveIdValue -Value ([string]$BridgeStatus.canonical_mim_objective_id) } else { '' }
    $liveTaskObjectiveId = if ($BridgeStatus -and $BridgeStatus.PSObject.Properties['task_request_objective_id']) { Normalize-ObjectiveIdValue -Value ([string]$BridgeStatus.task_request_objective_id) } else { '' }

    $status = 'aligned'
    $conflictDetected = $false
    $summary = 'The live MIM proposal is aligned with the current TOD objective posture.'
    $recommendedAction = 'refresh-project-status'

    if ([string]::IsNullOrWhiteSpace($proposalObjectiveId)) {
        $status = 'insufficient_scope'
        $summary = 'The live MIM proposal is available, but its objective scope is incomplete.'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($selectedNormalizedObjectiveId) -and -not [string]::Equals($proposalObjectiveId, $selectedNormalizedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
        $status = 'objective_scope_mismatch'
        $conflictDetected = $true
        $recommendedAction = 'refresh-bridge-alignment-bundle'
        $summary = 'The live MIM proposal targets objective {0}, but TOD is currently centered on objective {1}.' -f $proposalObjectiveId, $selectedNormalizedObjectiveId
    }
    elseif ($BridgeStatus -and $BridgeStatus.PSObject.Properties['objective_mismatch'] -and [bool]$BridgeStatus.objective_mismatch) {
        $status = 'bridge_alignment_mismatch'
        $conflictDetected = $true
        $recommendedAction = 'refresh-bridge-alignment-bundle'
        if (-not [string]::IsNullOrWhiteSpace([string]$BridgeStatus.objective_mismatch_detail)) {
            $summary = 'The live MIM proposal is in scope, but bridge alignment is still warning: {0}.' -f [string]$BridgeStatus.objective_mismatch_detail
        }
        else {
            $summary = 'The live MIM proposal is in scope, but bridge alignment still shows an objective mismatch.'
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($canonicalObjectiveId) -and -not [string]::Equals($proposalObjectiveId, $canonicalObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
        $status = 'canonical_export_mismatch'
        $conflictDetected = $true
        $recommendedAction = 'refresh-bridge-alignment-bundle'
        $summary = 'The live MIM proposal targets objective {0}, but the canonical MIM export still reports objective {1}.' -f $proposalObjectiveId, $canonicalObjectiveId
    }

    return [pscustomobject]@{
        available = $true
        status = $status
        conflict_detected = [bool]$conflictDetected
        summary = $summary
        proposal_objective_id = $proposalObjectiveId
        selected_objective_id = $selectedNormalizedObjectiveId
        canonical_mim_objective_id = $canonicalObjectiveId
        live_task_objective_id = $liveTaskObjectiveId
        recommended_action = $recommendedAction
    }
}

function Get-MimProposalArbitration {
    param(
        $MimProposal,
        $MimProposalConflict
    )

    if ($null -eq $MimProposal -or -not [bool]$MimProposal.available) {
        return [pscustomobject]@{
            available = $false
            status = 'none'
            winner = 'none'
            summary = 'No live MIM proposal is available for arbitration.'
            recommended_posture = 'none'
            recommended_action = ''
            confidence = 'low'
            mim_score = 0
            tod_score = 0
        }
    }

    $proposalTitle = if ([string]::IsNullOrWhiteSpace([string]$MimProposal.title)) { 'the live MIM proposal' } else { [string]$MimProposal.title }
    $recommendedAction = if ($MimProposalConflict -and $MimProposalConflict.PSObject.Properties['recommended_action']) { [string]$MimProposalConflict.recommended_action } else { 'refresh-project-status' }

    if ($null -eq $MimProposalConflict -or -not [bool]$MimProposalConflict.available) {
        return [pscustomobject]@{
            available = $true
            status = 'observe_first'
            winner = 'observe'
            summary = 'A live MIM proposal is present, but conflict posture is unavailable, so TOD should refresh bounded evidence before arbitration.'
            recommended_posture = 'observe_first'
            recommended_action = 'refresh-project-status'
            confidence = 'low'
            mim_score = 1
            tod_score = 1
        }
    }

    if ([string]::Equals([string]$MimProposalConflict.status, 'insufficient_scope', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            available = $true
            status = 'revalidate_scope_first'
            winner = 'tod'
            summary = "TOD keeps priority because $proposalTitle does not expose enough objective scope to arbitrate safely."
            recommended_posture = 'hold_mim_switch'
            recommended_action = 'refresh-project-status'
            confidence = 'low'
            mim_score = 0
            tod_score = 3
        }
    }

    if ([bool]$MimProposalConflict.conflict_detected) {
        return [pscustomobject]@{
            available = $true
            status = 'revalidate_tod_priority'
            winner = 'tod'
            summary = "TOD keeps priority until bounded evidence resolves the proposal conflict. $([string]$MimProposalConflict.summary)"
            recommended_posture = 'hold_mim_switch'
            recommended_action = if ([string]::IsNullOrWhiteSpace($recommendedAction)) { 'refresh-bridge-alignment-bundle' } else { $recommendedAction }
            confidence = if ([string]::Equals([string]$MimProposalConflict.status, 'bridge_alignment_mismatch', [System.StringComparison]::OrdinalIgnoreCase)) { 'medium' } else { 'high' }
            mim_score = 1
            tod_score = 5
        }
    }

    return [pscustomobject]@{
        available = $true
        status = 'proceed_with_mim_context'
        winner = 'shared'
        summary = "TOD and MIM are aligned enough to use $proposalTitle as bounded context for the next refresh and decision."
        recommended_posture = 'aligned_refresh_then_commit'
        recommended_action = if ([string]::IsNullOrWhiteSpace($recommendedAction)) { 'refresh-project-status' } else { $recommendedAction }
        confidence = 'high'
        mim_score = 4
        tod_score = 4
    }
}

function Get-MimProposalMergePolicy {
    param(
        $MimProposal,
        $MimProposalConflict,
        $MimProposalArbitration
    )

    if ($null -eq $MimProposal -or -not [bool]$MimProposal.available) {
        return [pscustomobject]@{
            available = $false
            status = 'none'
            mode = 'none'
            summary = 'No live MIM proposal is available for merge policy.'
            recommended_action = ''
        }
    }

    if ($null -eq $MimProposalArbitration -or -not [bool]$MimProposalArbitration.available) {
        return [pscustomobject]@{
            available = $true
            status = 'observe_first'
            mode = 'defer'
            summary = 'Merge policy is deferred until arbitration posture is available.'
            recommended_action = 'refresh-project-status'
        }
    }

    if ([string]::Equals([string]$MimProposalArbitration.winner, 'shared', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            available = $true
            status = 'merge_ready'
            mode = 'context'
            summary = 'Use MIM-TOD bounded context to determine implementation for the current TOD objective rather than creating a separate competing lane.'
            recommended_action = if ($MimProposalArbitration.PSObject.Properties['recommended_action']) { [string]$MimProposalArbitration.recommended_action } else { 'refresh-project-status' }
        }
    }

    $deferredSummary = if ($MimProposalConflict -and $MimProposalConflict.PSObject.Properties['summary']) { [string]$MimProposalConflict.summary } else { [string]$MimProposalArbitration.summary }
    return [pscustomobject]@{
        available = $true
        status = 'merge_deferred'
        mode = 'separate'
        summary = "Keep the live MIM proposal separate until bounded revalidation resolves the current posture. $deferredSummary"
        recommended_action = if ($MimProposalArbitration.PSObject.Properties['recommended_action']) { [string]$MimProposalArbitration.recommended_action } else { 'refresh-bridge-alignment-bundle' }
    }
}

function Get-MimProposalAcknowledgment {
    param(
        $MimProposal,
        $MimProposalConflict,
        $MimProposalArbitration,
        $MimProposalMergePolicy
    )

    if ($null -eq $MimProposal -or -not [bool]$MimProposal.available) {
        return [pscustomobject]@{
            available = $false
            status = 'none'
            disposition = 'none'
            summary = 'No live MIM proposal is available for acknowledgment.'
            recommended_action = ''
        }
    }

    if ($null -eq $MimProposalMergePolicy -or -not [bool]$MimProposalMergePolicy.available) {
        return [pscustomobject]@{
            available = $true
            status = 'pending_review'
            disposition = 'pending'
            summary = 'TOD has not acknowledged the live MIM proposal yet because merge policy is not available.'
            recommended_action = 'refresh-project-status'
        }
    }

    if ([string]::Equals([string]$MimProposalMergePolicy.status, 'merge_ready', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            available = $true
            status = 'acknowledged_context'
            disposition = 'absorbed'
            summary = 'TOD acknowledges the live MIM proposal and currently absorbs it as bounded context for the active objective.'
            recommended_action = if ($MimProposalMergePolicy.PSObject.Properties['recommended_action']) { [string]$MimProposalMergePolicy.recommended_action } else { 'refresh-project-status' }
        }
    }

    $conflictStatus = if ($MimProposalConflict -and $MimProposalConflict.PSObject.Properties['status']) { [string]$MimProposalConflict.status } else { '' }
    if (@('canonical_export_mismatch', 'insufficient_scope') -contains $conflictStatus) {
        return [pscustomobject]@{
            available = $true
            status = 'rejected'
            disposition = 'rejected'
            summary = 'TOD currently rejects the live MIM proposal as active context because bounded proposal posture still fails scope or canonical-alignment checks.'
            recommended_action = if ($MimProposalMergePolicy.PSObject.Properties['recommended_action']) { [string]$MimProposalMergePolicy.recommended_action } else { 'refresh-bridge-alignment-bundle' }
        }
    }

    return [pscustomobject]@{
        available = $true
        status = 'deferred'
        disposition = 'deferred'
        summary = 'TOD acknowledges the live MIM proposal but keeps it separate until bounded revalidation resolves the current posture.'
        recommended_action = if ($MimProposalMergePolicy.PSObject.Properties['recommended_action']) { [string]$MimProposalMergePolicy.recommended_action } else { 'refresh-bridge-alignment-bundle' }
    }
}

function Get-MimProposalActivityTrail {
    param([int]$Limit = 80)

    $records = New-Object System.Collections.Generic.List[object]
    if (Test-Path -Path $operatorChatActionAuditLogPath) {
        $lines = Get-RecentLogLines -LogPath $operatorChatActionAuditLogPath -Tail ($Limit * 10)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace([string]$line)) {
                continue
            }

            try {
                $entry = $line | ConvertFrom-Json
                $proposalId = if ($entry.PSObject.Properties['proposal_id']) { [string]$entry.proposal_id } else { '' }
                $proposalSource = if ($entry.PSObject.Properties['proposal_source']) { [string]$entry.proposal_source } else { '' }
                if ([string]::IsNullOrWhiteSpace($proposalId) -or -not [string]::Equals($proposalSource, 'mim', [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                [void]$records.Add([pscustomobject]@{
                        timestamp_utc = if ($entry.PSObject.Properties['timestamp_utc']) { [string]$entry.timestamp_utc } else { '' }
                        source_type = 'audit'
                        proposal_id = $proposalId
                        proposal_objective_id = if ($entry.PSObject.Properties['proposal_objective_id']) { Normalize-ObjectiveIdValue -Value ([string]$entry.proposal_objective_id) } else { '' }
                        proposal_title = if ($entry.PSObject.Properties['proposal_title']) { [string]$entry.proposal_title } else { '' }
                        action = if ($entry.PSObject.Properties['action']) { [string]$entry.action } else { '' }
                        status = if ($entry.PSObject.Properties['outcome_status']) { [string]$entry.outcome_status } else { '' }
                    })
            }
            catch {
            }
        }
    }

    if (Test-Path -Path $operatorChatCommitmentLogPath) {
        $lines = Get-RecentLogLines -LogPath $operatorChatCommitmentLogPath -Tail ($Limit * 10)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace([string]$line)) {
                continue
            }

            try {
                $entry = $line | ConvertFrom-Json
                $proposalId = if ($entry.PSObject.Properties['proposal_id']) { [string]$entry.proposal_id } else { '' }
                $proposalSource = if ($entry.PSObject.Properties['proposal_source']) { [string]$entry.proposal_source } else { '' }
                if ([string]::IsNullOrWhiteSpace($proposalId) -or -not [string]::Equals($proposalSource, 'mim', [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                [void]$records.Add([pscustomobject]@{
                        timestamp_utc = if ($entry.PSObject.Properties['timestamp_utc']) { [string]$entry.timestamp_utc } else { '' }
                        source_type = 'commitment'
                        proposal_id = $proposalId
                        proposal_objective_id = if ($entry.PSObject.Properties['proposal_objective_id']) { Normalize-ObjectiveIdValue -Value ([string]$entry.proposal_objective_id) } else { '' }
                        proposal_title = if ($entry.PSObject.Properties['proposal_title']) { [string]$entry.proposal_title } else { '' }
                        action = if ($entry.PSObject.Properties['action']) { [string]$entry.action } else { '' }
                        status = if ($entry.PSObject.Properties['state']) { [string]$entry.state } else { '' }
                    })
            }
            catch {
            }
        }
    }

    return @($records | Sort-Object timestamp_utc -Descending | Select-Object -First $Limit)
}

function Get-MimProposalClosure {
    param(
        $MimProposal,
        $MimProposalAcknowledgment
    )

    if ($MimProposal -and $MimProposal.PSObject.Properties['suppressed'] -and [bool]$MimProposal.suppressed) {
        return [pscustomobject]@{
            available = $false
            status = 'none'
            disposition = 'none'
            summary = 'Raw MIM proposal telemetry is a stale backfill superseded by the effective live bridge task.'
            recommended_action = 'refresh-project-status'
            proposal_id = if ($MimProposal.PSObject.Properties['task_id']) { [string]$MimProposal.task_id } else { '' }
            proposal_objective_id = if ($MimProposal.PSObject.Properties['normalized_objective_id']) { [string]$MimProposal.normalized_objective_id } else { '' }
            journal = @()
            latest_terminal_state = ''
            latest_terminal_at = ''
        }
    }

    $currentProposalId = if ($MimProposal -and [bool]$MimProposal.available -and $MimProposal.PSObject.Properties['task_id']) { [string]$MimProposal.task_id } else { '' }
    $currentProposalTitle = if ($MimProposal -and [bool]$MimProposal.available -and $MimProposal.PSObject.Properties['title']) { [string]$MimProposal.title } else { '' }
    $currentProposalObjectiveId = if ($MimProposal -and [bool]$MimProposal.available) {
        $rawObjectiveId = if ($MimProposal.PSObject.Properties['normalized_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$MimProposal.normalized_objective_id)) { [string]$MimProposal.normalized_objective_id } else { [string]$MimProposal.objective_id }
        Normalize-ObjectiveIdValue -Value $rawObjectiveId
    }
    else {
        ''
    }
    $activity = @(Get-MimProposalActivityTrail -Limit 120)
    $groupMap = @{}
    foreach ($record in $activity) {
        $proposalId = [string]$record.proposal_id
        if ([string]::IsNullOrWhiteSpace($proposalId)) {
            continue
        }
        if (-not $groupMap.ContainsKey($proposalId)) {
            $groupMap[$proposalId] = New-Object System.Collections.Generic.List[object]
        }
        [void]$groupMap[$proposalId].Add($record)
    }

    $groups = New-Object System.Collections.Generic.List[object]
    foreach ($proposalId in @($groupMap.Keys)) {
        $records = @($groupMap[$proposalId].ToArray() | Sort-Object timestamp_utc -Descending)
        if (@($records).Count -eq 0) {
            continue
        }
        $latest = $records[0]
        $latestTerminal = @($records | Where-Object {
                [string]::Equals([string]$_.source_type, 'commitment', [System.StringComparison]::OrdinalIgnoreCase) -and @('satisfied', 'abandoned') -contains ([string]$_.status)
            } | Select-Object -First 1)
        [void]$groups.Add([pscustomobject]@{
                proposal_id = $proposalId
                proposal_objective_id = [string]$latest.proposal_objective_id
                proposal_title = [string]$latest.proposal_title
                latest_record = $latest
                latest_terminal = if (@($latestTerminal).Count -gt 0) { $latestTerminal[0] } else { $null }
            })
    }

    $sortedGroups = @($groups.ToArray() | Sort-Object { [string]$_.latest_record.timestamp_utc } -Descending)
    $journal = New-Object System.Collections.Generic.List[object]
    foreach ($group in $sortedGroups) {
        $live = -not [string]::IsNullOrWhiteSpace($currentProposalId) -and [string]::Equals([string]$group.proposal_id, $currentProposalId, [System.StringComparison]::OrdinalIgnoreCase)
        $laterSameObjective = @($sortedGroups | Where-Object {
                -not [string]::Equals([string]$_.proposal_id, [string]$group.proposal_id, [System.StringComparison]::OrdinalIgnoreCase) -and
                -not [string]::IsNullOrWhiteSpace([string]$group.proposal_objective_id) -and
                [string]::Equals([string]$_.proposal_objective_id, [string]$group.proposal_objective_id, [System.StringComparison]::OrdinalIgnoreCase) -and
                ([string]$_.latest_record.timestamp_utc) -gt ([string]$group.latest_record.timestamp_utc)
            } | Select-Object -First 1)

        $status = 'open'
        $summary = 'The proposal is still active and has not reached a terminal outcome yet.'
        if ($group.latest_terminal) {
            if ([string]::Equals([string]$group.latest_terminal.status, 'satisfied', [System.StringComparison]::OrdinalIgnoreCase)) {
                $status = 'fulfilled'
                $summary = 'The proposal reached a satisfied commitment outcome and is now treated as fulfilled.'
            }
            elseif ($live) {
                $status = 'open'
                $summary = 'The live proposal remains open; the latest proposal-linked commitment was abandoned and should be treated as historical context, not proposal closure.'
            }
            else {
                $status = 'abandoned'
                $summary = 'The latest proposal-linked commitment was abandoned.'
            }
        }
        elseif (-not $live) {
            if (@($laterSameObjective).Count -gt 0) {
                $status = 'superseded'
                $summary = 'A newer proposal for the same objective appeared before this proposal reached a terminal outcome.'
            }
            else {
                $status = 'withdrawn'
                $summary = 'The proposal is no longer live and no terminal commitment outcome was recorded.'
            }
        }

        [void]$journal.Add([pscustomobject]@{
                proposal_id = [string]$group.proposal_id
                proposal_objective_id = [string]$group.proposal_objective_id
                proposal_title = [string]$group.proposal_title
                live = [bool]$live
                status = $status
                disposition = $status
                summary = $summary
                latest_event_at = [string]$group.latest_record.timestamp_utc
                latest_event_type = [string]$group.latest_record.source_type
                latest_event_status = [string]$group.latest_record.status
                latest_terminal_state = if ($group.latest_terminal) { [string]$group.latest_terminal.status } else { '' }
                latest_action = [string]$group.latest_record.action
            })
    }

    if (-not [string]::IsNullOrWhiteSpace($currentProposalId) -and @($journal | Where-Object { [string]::Equals([string]$_.proposal_id, $currentProposalId, [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
        [void]$journal.Insert(0, [pscustomobject]@{
                proposal_id = $currentProposalId
                proposal_objective_id = $currentProposalObjectiveId
                proposal_title = $currentProposalTitle
                live = $true
                status = 'open'
                disposition = 'open'
                summary = if ($MimProposalAcknowledgment -and $MimProposalAcknowledgment.PSObject.Properties['summary']) { 'The live proposal remains open. ' + [string]$MimProposalAcknowledgment.summary } else { 'The live proposal remains open and has not reached a terminal outcome yet.' }
                latest_event_at = ''
                latest_event_type = 'live'
                latest_event_status = 'open'
                latest_terminal_state = ''
                latest_action = ''
            })
    }

    $journalEntries = @($journal.ToArray() | Sort-Object latest_event_at -Descending | Select-Object -First 6)
    if ([string]::IsNullOrWhiteSpace($currentProposalId) -and @($journalEntries).Count -eq 0) {
        return [pscustomobject]@{
            available = $false
            status = 'none'
            disposition = 'none'
            summary = 'No live or recent MIM proposal closure history is available.'
            recommended_action = ''
            proposal_id = ''
            proposal_objective_id = ''
            journal = @()
        }
    }

    $currentEntry = if (-not [string]::IsNullOrWhiteSpace($currentProposalId)) {
        @($journalEntries | Where-Object { [string]::Equals([string]$_.proposal_id, $currentProposalId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    }
    else {
        @()
    }
    $selectedEntry = if (@($currentEntry).Count -gt 0) { $currentEntry[0] } elseif (@($journalEntries).Count -gt 0) { $journalEntries[0] } else { $null }

    return [pscustomobject]@{
        available = $true
        status = if ($selectedEntry) { [string]$selectedEntry.status } else { 'none' }
        disposition = if ($selectedEntry) { [string]$selectedEntry.disposition } else { 'none' }
        summary = if ($selectedEntry) { [string]$selectedEntry.summary } else { 'No MIM proposal closure history is available.' }
        recommended_action = switch ([string]$(if ($selectedEntry) { $selectedEntry.status } else { 'none' })) {
            'fulfilled' { 'refresh-governance-snapshot' }
            'abandoned' { 'refresh-project-status' }
            'superseded' { 'refresh-project-status' }
            'withdrawn' { 'refresh-project-status' }
            default { if ($MimProposalAcknowledgment -and $MimProposalAcknowledgment.PSObject.Properties['recommended_action']) { [string]$MimProposalAcknowledgment.recommended_action } else { 'refresh-project-status' } }
        }
        proposal_id = if ($selectedEntry) { [string]$selectedEntry.proposal_id } else { $currentProposalId }
        proposal_objective_id = if ($selectedEntry) { [string]$selectedEntry.proposal_objective_id } else { $currentProposalObjectiveId }
        journal = @($journalEntries)
        latest_terminal_state = if ($selectedEntry) { [string]$selectedEntry.latest_terminal_state } else { '' }
        latest_terminal_at = if ($selectedEntry) { [string]$selectedEntry.latest_event_at } else { '' }
    }
}

function Get-ProjectStatusFromListenerOnly {
    param(
        [string]$ObjectiveId,
        $ListenerActivity,
        $RecoveryWatchdog,
        $CadenceHealth,
        $VoiceAdapterStatus,
        [string]$StateWarning,
        $MimProposal
    )

    $nextActions = Read-JsonFileIfExists -Path $nextActionsPath
    $bridgeStatus = Get-BridgeStatus
    $selfHealthMaintenance = Get-SelfHealthMaintenanceStatus

    $latestListenerObjectiveId = if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['latest_objective_id']) { [string]$ListenerActivity.latest_objective_id } else { '' }
    $latestListenerStatus = if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['latest_execution_status']) { [string]$ListenerActivity.latest_execution_status } else { '' }
    $latestListenerTimestamp = if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['latest_timestamp']) { [string]$ListenerActivity.latest_timestamp } else { '' }

    $objectiveOptions = @()
    $objectiveStatsMap = @{}
    if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['objective_stats']) {
        foreach ($prop in $ListenerActivity.objective_stats.PSObject.Properties) {
            $listenerObjectiveId = [string]$prop.Name
            if ([string]::IsNullOrWhiteSpace($listenerObjectiveId)) {
                continue
            }

            $stats = $prop.Value
            $objectiveStatsMap[$listenerObjectiveId] = $stats
            $objectiveOptions += [pscustomobject]@{
                objective_id = $listenerObjectiveId
                title = "Listener Objective $listenerObjectiveId"
                status = if ($stats.last_execution_status) { [string]$stats.last_execution_status } else { "listener" }
                priority = "listener"
            }
        }
    }

    $selectedObjectiveId = Resolve-ProjectSelectedObjectiveId -ExplicitObjectiveId $ObjectiveId -ListenerActivity $ListenerActivity -BridgeStatus $bridgeStatus -NextActions $nextActions -Objectives $null
    if ([string]::IsNullOrWhiteSpace($selectedObjectiveId) -and @($objectiveOptions).Count -gt 0) {
        $selectedObjectiveId = [string]$objectiveOptions[0].objective_id
    }

    if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId) -and -not $objectiveStatsMap.ContainsKey($selectedObjectiveId)) {
        $objectiveOptions += [pscustomobject]@{
            objective_id = $selectedObjectiveId
            title = "Listener Objective $selectedObjectiveId"
            status = if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['result_objective_id'] -and [string]::Equals([string]$ListenerActivity.result_objective_id, $selectedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace([string]$ListenerActivity.result_status)) { [string]$ListenerActivity.result_status } else { "listener" }
            priority = "listener"
        }
    }

    $selectedStats = $null
    if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId) -and $objectiveStatsMap.ContainsKey($selectedObjectiveId)) {
        $selectedStats = $objectiveStatsMap[$selectedObjectiveId]
    }

    $taskCount = 0
    $progressUnits = 0.0
    $percent = 0
    $statusBreakdown = @{}

    if ($selectedStats) {
        $taskCount = [int]$selectedStats.total
        $progressUnits = [double]$selectedStats.progress_units
        if ($taskCount -gt 0) {
            $percent = [int][math]::Round(($progressUnits / [double]$taskCount) * 100)
        }
        $statusBreakdown = @{
            completed = [int]$selectedStats.completed
            failed = [int]$selectedStats.failed
            in_progress = [int]$selectedStats.in_progress
        }
    }

    $selectedObjectiveStatus = ''
    if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId) -and
        -not [string]::IsNullOrWhiteSpace($latestListenerObjectiveId) -and
        [string]::Equals($selectedObjectiveId, $latestListenerObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::IsNullOrWhiteSpace($latestListenerStatus)) {
        $selectedObjectiveStatus = $latestListenerStatus
    }
    elseif ($selectedStats -and $selectedStats.last_execution_status) {
        $selectedObjectiveStatus = [string]$selectedStats.last_execution_status
    }
    elseif ($ListenerActivity -and $ListenerActivity.PSObject.Properties['result_objective_id'] -and [string]::Equals([string]$ListenerActivity.result_objective_id, $selectedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace([string]$ListenerActivity.result_status)) {
        $selectedObjectiveStatus = [string]$ListenerActivity.result_status
    }

    $selectedObjectiveStatusNormalized = ([string]$selectedObjectiveStatus).Trim().ToLowerInvariant()
    $listenerPendingRequestCount = if ($ListenerActivity -and $ListenerActivity.PSObject.Properties['sync'] -and $ListenerActivity.sync -and $ListenerActivity.sync.PSObject.Properties['pending_request_count']) { [int]$ListenerActivity.sync.pending_request_count } else { 0 }
    if (
        ($taskCount -gt 0) -and
        ($listenerPendingRequestCount -le 0) -and
        (@('completed', 'succeeded', 'done', 'pass') -contains $selectedObjectiveStatusNormalized)
    ) {
        $taskCount = 1
        $progressUnits = 1.0
        $percent = 100
        $statusBreakdown = @{ completed = 1 }
    }

    $selectedObjectiveUpdatedAt = ''
    if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId) -and
        -not [string]::IsNullOrWhiteSpace($latestListenerObjectiveId) -and
        [string]::Equals($selectedObjectiveId, $latestListenerObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::IsNullOrWhiteSpace($latestListenerTimestamp)) {
        $selectedObjectiveUpdatedAt = $latestListenerTimestamp
    }
    elseif ($selectedStats -and $selectedStats.last_timestamp) {
        $selectedObjectiveUpdatedAt = [string]$selectedStats.last_timestamp
    }

    $marker = $null
    if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId)) {
        $marker = [pscustomobject]@{
            objective_id = $selectedObjectiveId
            remote_objective_id = $selectedObjectiveId
            title = "Listener Objective $selectedObjectiveId"
            status = if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveStatus)) { $selectedObjectiveStatus } else { "listener" }
            priority = "listener"
            updated_at = $selectedObjectiveUpdatedAt
        }
    }

    $engineeringSignal = [pscustomobject]@{
        available = $false
        error = "Engineering signal skipped in listener-only mode to keep dashboard refresh responsive."
    }

    $mimProposalConflict = Get-MimProposalConflict -MimProposal $MimProposal -SelectedObjectiveId $selectedObjectiveId -BridgeStatus $bridgeStatus
    $mimProposalArbitration = Get-MimProposalArbitration -MimProposal $MimProposal -MimProposalConflict $mimProposalConflict
    $mimProposalMergePolicy = Get-MimProposalMergePolicy -MimProposal $MimProposal -MimProposalConflict $mimProposalConflict -MimProposalArbitration $mimProposalArbitration
    $mimProposalAcknowledgment = Get-MimProposalAcknowledgment -MimProposal $MimProposal -MimProposalConflict $mimProposalConflict -MimProposalArbitration $mimProposalArbitration -MimProposalMergePolicy $mimProposalMergePolicy
    $mimProposalClosure = Get-MimProposalClosure -MimProposal $MimProposal -MimProposalAcknowledgment $mimProposalAcknowledgment

    $steadyState = Get-SteadyStateHealth -ListenerActivity $ListenerActivity -RecoveryWatchdog $RecoveryWatchdog -CadenceHealth $CadenceHealth -StateWarning $StateWarning -UsingListenerOnly $true
    $dataSources = Get-ProjectDataSources -UsingListenerOnly $true -StateWarning $StateWarning -ListenerActivity $ListenerActivity

    return [pscustomobject]@{
        ok = $true
        objective_options = @($objectiveOptions)
        selected_objective_id = $selectedObjectiveId
        marker = $marker
        task_funnel = [pscustomobject]@{
            total = $taskCount
            by_status = [pscustomobject]$statusBreakdown
        }
        progress = [pscustomobject]@{
            percent = $percent
            completed_equivalent = [math]::Round($progressUnits, 2)
            task_count = $taskCount
            source = if ($percent -eq 100 -and $taskCount -eq 1 -and @('completed', 'succeeded', 'done', 'pass') -contains $selectedObjectiveStatusNormalized) { "objective_status" } else { "listener_journal" }
            summary = if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId) -and $taskCount -gt 0 -and $percent -eq 100 -and @('completed', 'succeeded', 'done', 'pass') -contains $selectedObjectiveStatusNormalized) { "Objective ${selectedObjectiveId}: 100% (listener terminal status)" } elseif (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId) -and $taskCount -gt 0) { "Objective ${selectedObjectiveId}: $percent% (listener journal)" } elseif (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId)) { "Objective ${selectedObjectiveId}: awaiting listener journal convergence" } else { "Awaiting listener telemetry..." }
        }
        listener_activity = $ListenerActivity
        recovery_watchdog = $RecoveryWatchdog
        task_state = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["task_state"]) { [string]$RecoveryWatchdog.task_state } else { "idle" }
        task_state_model = [pscustomobject]@{
            current = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["task_state"]) { [string]$RecoveryWatchdog.task_state } else { "idle" }
            progress_classification = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["progress_classification"]) { [string]$RecoveryWatchdog.progress_classification } else { "no_progress_but_heartbeats_present" }
            heartbeat_age_seconds = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["heartbeat_age_seconds"]) { [int]$RecoveryWatchdog.heartbeat_age_seconds } else { -1 }
            stall_threshold_seconds = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["stall_threshold_seconds"]) { [int]$RecoveryWatchdog.stall_threshold_seconds } else { -1 }
            recovery_attempts = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["recovery_attempts"]) { [int]$RecoveryWatchdog.recovery_attempts } else { 0 }
            consecutive_freezes = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["consecutive_freezes"]) { [int]$RecoveryWatchdog.consecutive_freezes } else { 0 }
            last_recovery_time = if ($RecoveryWatchdog -and $RecoveryWatchdog.PSObject.Properties["last_recovery_time"]) { [string]$RecoveryWatchdog.last_recovery_time } else { "" }
        }
        engineering_signal = $engineeringSignal
        bridge_status = $bridgeStatus
        self_health_maintenance = $selfHealthMaintenance
        cadence_health = $CadenceHealth
        steady_state = $steadyState
        data_sources = $dataSources
        voice_adapter = $VoiceAdapterStatus
        mim_proposal = $MimProposal
        mim_proposal_conflict = $mimProposalConflict
        mim_proposal_arbitration = $mimProposalArbitration
        mim_proposal_merge_policy = $mimProposalMergePolicy
        mim_proposal_acknowledgment = $mimProposalAcknowledgment
        mim_proposal_closure = $mimProposalClosure
        warnings = if ([string]::IsNullOrWhiteSpace($StateWarning)) { @() } else { @($StateWarning) }
    }
}

function Get-SharedObjectiveProgressSnapshot {
    param([string]$ObjectiveId)

    $normalizedObjectiveId = Normalize-ObjectiveIdValue -Value $ObjectiveId
    if ([string]::IsNullOrWhiteSpace($normalizedObjectiveId)) {
        return $null
    }

    $ledger = Read-JsonFileIfExists -Path $sharedObjectivesPath
    if ($null -eq $ledger -or -not $ledger.PSObject.Properties['objectives']) {
        return $null
    }

    foreach ($entry in @($ledger.objectives)) {
        $entryObjectiveId = ''
        if ($entry.PSObject.Properties['objective_id']) {
            $entryObjectiveId = Normalize-ObjectiveIdValue -Value ([string]$entry.objective_id)
        }
        elseif ($entry.PSObject.Properties['id']) {
            $entryObjectiveId = Normalize-ObjectiveIdValue -Value ([string]$entry.id)
        }

        if (-not [string]::Equals($entryObjectiveId, $normalizedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($entry.PSObject.Properties['progress_snapshot'] -and $entry.progress_snapshot -and $entry.progress_snapshot.PSObject.Properties['available'] -and [bool]$entry.progress_snapshot.available) {
            return $entry.progress_snapshot
        }
    }

    return $null
}

function Get-ProjectStatusPayload {
    param(
        [string]$ObjectiveId,
        [string]$ValidationHarness = ''
    )

    $validationHarnessProfile = Get-OperatorChatValidationHarnessProfile -ValidationHarness $ValidationHarness

    $listenerActivity = Get-ListenerActivity
    $recoveryWatchdog = Get-RecoveryWatchdogStatus
    $selfHealthMaintenance = Get-SelfHealthMaintenanceStatus
    $cadenceHealth = Get-CadenceHealth -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog
    $voiceAdapterStatus = Get-VoiceAdapterStatus
    $bridgeStatus = Get-BridgeStatus
    $mimProposal = Get-MimProposalFromListenerRequest

    $state = $null
    $stateReadWarning = ""
    if (-not (Test-Path -Path $statePath)) {
        $stateReadWarning = "state.json not found; using listener telemetry"
    }
    else {
        try {
            $stateFile = Get-Item -Path $statePath -ErrorAction Stop
            if ($stateFile.Length -gt $maxStateReadBytes) {
                $stateMiB = [math]::Round(($stateFile.Length / 1MB), 2)
                $stateReadWarning = "state.json too large (${stateMiB} MiB); using listener telemetry"
            }
            else {
                $rawState = Read-TextFileIfExists -Path $statePath
                if ([string]::IsNullOrWhiteSpace($rawState)) {
                    $stateReadWarning = "state.json unavailable for UI telemetry: read returned empty content"
                }
                else {
                    $state = $rawState | ConvertFrom-Json
                }
            }
        }
        catch {
            $stateReadWarning = "state.json unavailable for UI telemetry: $([string]$_.Exception.Message)"
        }
    }

    if ($null -eq $state) {
        $listenerOnlyPayload = Get-ProjectStatusFromListenerOnly -ObjectiveId $ObjectiveId -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog -CadenceHealth $cadenceHealth -VoiceAdapterStatus $voiceAdapterStatus -StateWarning $stateReadWarning -MimProposal $mimProposal
        if ($validationHarnessProfile) {
            return Apply-OperatorChatValidationHarnessToStatus -ProjectStatus $listenerOnlyPayload -ValidationHarnessProfile $validationHarnessProfile -RequestedObjectiveId $ObjectiveId
        }
        return $listenerOnlyPayload
    }

    $objectives = @($state.objectives)
    $tasks = @($state.tasks)

    $objectiveOptions = @($objectives | Sort-Object created_at -Descending | ForEach-Object {
            [pscustomobject]@{
                objective_id = [string]$_.id
                title = [string]$_.title
                status = [string]$_.status
                priority = [string]$_.priority
            }
        })

    $knownObjectiveIds = @{}
    foreach ($item in $objectiveOptions) {
        $knownObjectiveIds[[string]$item.objective_id] = $true
    }

    if ($listenerActivity -and $listenerActivity.PSObject.Properties['objective_stats']) {
        $listenerObjectiveStats = $listenerActivity.objective_stats.PSObject.Properties
        foreach ($prop in $listenerObjectiveStats) {
            $listenerObjectiveId = [string]$prop.Name
            if ([string]::IsNullOrWhiteSpace($listenerObjectiveId)) {
                continue
            }
            if (-not $knownObjectiveIds.ContainsKey($listenerObjectiveId)) {
                $stats = $prop.Value
                $objectiveOptions += [pscustomobject]@{
                    objective_id = $listenerObjectiveId
                    title = "Listener Objective $listenerObjectiveId"
                    status = if ($stats.last_execution_status) { [string]$stats.last_execution_status } else { "listener" }
                    priority = "listener"
                }
                $knownObjectiveIds[$listenerObjectiveId] = $true
            }
        }
    }

    if (@($objectiveOptions).Count -eq 0) {
        $emptyPayload = [pscustomobject]@{
            ok = $true
            marker = $null
            objective_options = @()
            selected_objective_id = ""
            task_funnel = [pscustomobject]@{ total = 0; by_status = @{} }
            progress = [pscustomobject]@{
                percent = 0
                completed_equivalent = 0
                task_count = 0
                summary = "No objectives yet"
            }
        }
        if ($validationHarnessProfile) {
            return Apply-OperatorChatValidationHarnessToStatus -ProjectStatus $emptyPayload -ValidationHarnessProfile $validationHarnessProfile -RequestedObjectiveId $ObjectiveId
        }
        return $emptyPayload
    }

    $nextActions = $null
    if (Test-Path -Path $nextActionsPath) {
        try {
            $nextActionsRaw = Read-TextFileIfExists -Path $nextActionsPath
            if (-not [string]::IsNullOrWhiteSpace($nextActionsRaw)) {
                $nextActions = $nextActionsRaw | ConvertFrom-Json
            }
        }
        catch {
            $nextActions = $null
        }
    }

    $marker = $null
    $selectedObjectiveId = Resolve-ProjectSelectedObjectiveId -ExplicitObjectiveId $ObjectiveId -ListenerActivity $listenerActivity -BridgeStatus $bridgeStatus -NextActions $nextActions -Objectives $objectives

    if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId)) {
        $selected = @($objectives | Where-Object { [string]$_.id -eq [string]$selectedObjectiveId } | Select-Object -First 1)
        if (@($selected).Count -gt 0) {
            $marker = $selected[0]
        }
    }

    if ($null -eq $marker) {
        $marker = @($objectives | Sort-Object created_at -Descending | Select-Object -First 1)[0]
    }

    $objectiveId = if (-not [string]::IsNullOrWhiteSpace($selectedObjectiveId)) { $selectedObjectiveId } else { [string]$marker.id }

    if ([string]::IsNullOrWhiteSpace([string]$marker.id) -or ([string]$marker.id -ne $objectiveId -and -not @($objectives | Where-Object { [string]$_.id -eq $objectiveId }).Count)) {
        $listenerObjective = $null
        if ($listenerActivity -and $listenerActivity.PSObject.Properties['objective_stats']) {
            $listenerObjective = $listenerActivity.objective_stats.PSObject.Properties[$objectiveId]
        }

        $marker = [pscustomobject]@{
            id = $objectiveId
            remote_objective_id = $objectiveId
            title = "Listener Objective $objectiveId"
            status = if ($listenerObjective -and $listenerObjective.Value.last_execution_status) { [string]$listenerObjective.Value.last_execution_status } else { "listener" }
            priority = "listener"
            updated_at = if ($listenerObjective -and $listenerObjective.Value.last_timestamp) { [string]$listenerObjective.Value.last_timestamp } else { "" }
        }
    }

    $stateObjectiveTasks = @($tasks | Where-Object { [string]$_.objective_id -eq $objectiveId })
    $bridgeRuntimeTasks = @($stateObjectiveTasks | Where-Object {
            (($_.PSObject.Properties['task_category']) -and [string]::Equals([string]$_.task_category, 'bridge_runtime', [System.StringComparison]::OrdinalIgnoreCase)) -or
            (($_.PSObject.Properties['source']) -and [string]::Equals([string]$_.source, 'bridge_runtime_sync', [System.StringComparison]::OrdinalIgnoreCase))
        })
    $objectiveTasks = @($stateObjectiveTasks | Where-Object {
            -not (((($_.PSObject.Properties['task_category']) -and [string]::Equals([string]$_.task_category, 'bridge_runtime', [System.StringComparison]::OrdinalIgnoreCase)) -or
            (($_.PSObject.Properties['source']) -and [string]::Equals([string]$_.source, 'bridge_runtime_sync', [System.StringComparison]::OrdinalIgnoreCase))))
        })
    $taskCount = @($objectiveTasks).Count
    $stateTaskCount = $taskCount

    $statusBreakdown = @{}
    foreach ($task in $objectiveTasks) {
        $statusValue = if ($task.PSObject.Properties["status"]) { [string]$task.status } else { "unknown" }
        $key = if ([string]::IsNullOrWhiteSpace($statusValue)) { "unknown" } else { $statusValue.Trim().ToLowerInvariant() }
        if (-not $statusBreakdown.ContainsKey($key)) {
            $statusBreakdown[$key] = 0
        }
        $statusBreakdown[$key] = [int]$statusBreakdown[$key] + 1
    }

    $bridgeRuntimeStatusBreakdown = @{}
    foreach ($task in $bridgeRuntimeTasks) {
        $statusValue = if ($task.PSObject.Properties["status"]) { [string]$task.status } else { "unknown" }
        $key = if ([string]::IsNullOrWhiteSpace($statusValue)) { "unknown" } else { $statusValue.Trim().ToLowerInvariant() }
        if (-not $bridgeRuntimeStatusBreakdown.ContainsKey($key)) {
            $bridgeRuntimeStatusBreakdown[$key] = 0
        }
        $bridgeRuntimeStatusBreakdown[$key] = [int]$bridgeRuntimeStatusBreakdown[$key] + 1
    }

    $progressUnits = 0.0
    foreach ($task in $objectiveTasks) {
        $statusValue = if ($task.PSObject.Properties["status"]) { [string]$task.status } else { "" }
        $progressUnits += (Get-TaskProgressWeight -Status $statusValue)
    }

    $listenerStats = $null
    if ($listenerActivity -and $listenerActivity.PSObject.Properties['objective_stats']) {
        $listenerStats = $listenerActivity.objective_stats.PSObject.Properties[$objectiveId]
    }

    $listenerTaskCount = 0
    $listenerProgressUnits = 0.0
    if ($listenerStats) {
        $listenerTaskCount = [int]$listenerStats.Value.total
        $listenerProgressUnits = [double]$listenerStats.Value.progress_units
    }

    $sharedObjectiveProgress = Get-SharedObjectiveProgressSnapshot -ObjectiveId $objectiveId
    $sharedTaskCount = 0
    $sharedProgressUnits = 0.0
    $sharedStatusBreakdown = @{}
    if ($sharedObjectiveProgress) {
        if ($sharedObjectiveProgress.PSObject.Properties['task_count']) {
            $sharedTaskCount = [int]$sharedObjectiveProgress.task_count
        }
        if ($sharedObjectiveProgress.PSObject.Properties['completed_equivalent']) {
            $sharedProgressUnits = [double]$sharedObjectiveProgress.completed_equivalent
        }
        if ($sharedObjectiveProgress.PSObject.Properties['by_status'] -and $sharedObjectiveProgress.by_status) {
            foreach ($prop in $sharedObjectiveProgress.by_status.PSObject.Properties) {
                $sharedStatusBreakdown[[string]$prop.Name] = [int]$prop.Value
            }
        }
    }

    $preferSharedObjectiveLedger = ($sharedTaskCount -gt 0) -and (
        ($taskCount -le 0) -or
        ($sharedTaskCount -gt $taskCount) -or
        (($sharedTaskCount -eq $taskCount) -and ($sharedProgressUnits -gt $progressUnits))
    )

    $progressSource = "tasks"
    $percent = if ($taskCount -gt 0 -and -not $preferSharedObjectiveLedger) {
        [int][math]::Round(($progressUnits / [double]$taskCount) * 100)
    }
    elseif ($sharedTaskCount -gt 0) {
        $progressSource = "shared_objective_ledger"
        $progressUnits = $sharedProgressUnits
        $taskCount = $sharedTaskCount
        $statusBreakdown = $sharedStatusBreakdown
        [int][math]::Round(($sharedProgressUnits / [double]$sharedTaskCount) * 100)
    }
    elseif ($listenerTaskCount -gt 0) {
        $progressSource = "listener_journal"
        $progressUnits = $listenerProgressUnits
        $taskCount = $listenerTaskCount
        [int][math]::Round(($listenerProgressUnits / [double]$listenerTaskCount) * 100)
    }
    else {
        $progressSource = "objective_status"
        [int][math]::Round((Get-TaskProgressWeight -Status ([string]$marker.status)) * 100)
    }

    if ($preferSharedObjectiveLedger -and $sharedTaskCount -gt 0 -and $taskCount -eq $sharedTaskCount) {
        $progressSource = "shared_objective_ledger"
        if ($sharedStatusBreakdown.Count -gt 0) {
            $statusBreakdown = $sharedStatusBreakdown
        }
        $progressUnits = $sharedProgressUnits
    }
    elseif ($progressSource -eq "listener_journal" -and $stateTaskCount -eq 0 -and -not [string]::IsNullOrWhiteSpace($objectiveId)) {
        $progressSource = "state_plus_listener"
    }

    $markerStatusNormalized = ([string]$marker.status).Trim().ToLowerInvariant()
    $listenerLatestExecutionNormalized = if ($listenerActivity -and $listenerActivity.PSObject.Properties['latest_execution_status']) { ([string]$listenerActivity.latest_execution_status).Trim().ToLowerInvariant() } else { '' }
    $listenerPendingRequestCount = if ($listenerActivity -and $listenerActivity.PSObject.Properties['sync'] -and $listenerActivity.sync -and $listenerActivity.sync.PSObject.Properties['pending_request_count']) { [int]$listenerActivity.sync.pending_request_count } else { 0 }
    if (
        ($progressSource -eq 'listener_journal' -or $progressSource -eq 'state_plus_listener') -and
        ($stateTaskCount -le 0) -and
        ($listenerPendingRequestCount -le 0) -and
        (@('completed', 'succeeded', 'done', 'pass') -contains $markerStatusNormalized) -and
        (@('completed', 'succeeded') -contains $listenerLatestExecutionNormalized)
    ) {
        $progressSource = 'objective_status'
        $taskCount = 1
        $progressUnits = 1.0
        $statusBreakdown = @{ completed = 1 }
        $percent = 100
    }

    $progressSummary = if ($taskCount -gt 0) {
        if ($progressSource -eq "listener_journal") {
            "Objective ${objectiveId}: $percent% (listener journal)"
        }
        elseif ($progressSource -eq "shared_objective_ledger") {
            "Objective ${objectiveId}: $percent% (shared objective ledger)"
        }
        elseif ($progressSource -eq "state_plus_listener") {
            "Objective ${objectiveId}: $percent% (state marker plus listener task journal)"
        }
        else {
            "Objective ${objectiveId}: $percent%"
        }
    }
    else {
        "Objective ${objectiveId}: $percent% (status-based; no tasks yet)"
    }

    $engineeringSignal = $null
    if (-not [string]::IsNullOrWhiteSpace($stateReadWarning)) {
        $engineeringSignal = [pscustomobject]@{
            available = $false
            error = "Engineering signal skipped while using listener telemetry only."
        }
    }
    else {
        try {
            $signalRaw = & $todScript -Action "get-engineering-signal" -ConfigPath $configPath -Top 10
            $engineeringSignal = $signalRaw | ConvertFrom-Json
        }
        catch {
            $engineeringSignal = [pscustomobject]@{
                available = $false
                error = $_.Exception.Message
            }
        }
    }

    $steadyState = Get-SteadyStateHealth -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog -CadenceHealth $cadenceHealth -StateWarning $stateReadWarning -UsingListenerOnly ([string]::IsNullOrWhiteSpace($stateReadWarning) -eq $false)
    $dataSources = Get-ProjectDataSources -UsingListenerOnly ([string]::IsNullOrWhiteSpace($stateReadWarning) -eq $false) -StateWarning $stateReadWarning -ListenerActivity $listenerActivity
    $mimProposalConflict = Get-MimProposalConflict -MimProposal $mimProposal -SelectedObjectiveId $objectiveId -BridgeStatus $bridgeStatus
    $mimProposalArbitration = Get-MimProposalArbitration -MimProposal $mimProposal -MimProposalConflict $mimProposalConflict
    $mimProposalMergePolicy = Get-MimProposalMergePolicy -MimProposal $mimProposal -MimProposalConflict $mimProposalConflict -MimProposalArbitration $mimProposalArbitration
    $mimProposalAcknowledgment = Get-MimProposalAcknowledgment -MimProposal $mimProposal -MimProposalConflict $mimProposalConflict -MimProposalArbitration $mimProposalArbitration -MimProposalMergePolicy $mimProposalMergePolicy
    $mimProposalClosure = Get-MimProposalClosure -MimProposal $mimProposal -MimProposalAcknowledgment $mimProposalAcknowledgment

    $payload = [pscustomobject]@{
        ok = $true
        objective_options = @($objectiveOptions)
        selected_objective_id = $objectiveId
        marker = [pscustomobject]@{
            objective_id = $objectiveId
            remote_objective_id = if ($marker.PSObject.Properties["remote_objective_id"]) { [string]$marker.remote_objective_id } else { "" }
            title = [string]$marker.title
            status = [string]$marker.status
            priority = [string]$marker.priority
            updated_at = if ($marker.PSObject.Properties["updated_at"]) { [string]$marker.updated_at } else { "" }
        }
        task_funnel = [pscustomobject]@{
            total = $taskCount
            by_status = [pscustomobject]$statusBreakdown
            state_canonical_total = $stateTaskCount
            state_total = @($stateObjectiveTasks).Count
            bridge_runtime = [pscustomobject]@{
                total = @($bridgeRuntimeTasks).Count
                by_status = [pscustomobject]$bridgeRuntimeStatusBreakdown
            }
        }
        progress = [pscustomobject]@{
            percent = $percent
            completed_equivalent = [math]::Round($progressUnits, 2)
            task_count = $taskCount
            source = $progressSource
            summary = $progressSummary
        }
        listener_activity = $listenerActivity
        recovery_watchdog = $recoveryWatchdog
        task_state = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["task_state"]) { [string]$recoveryWatchdog.task_state } else { "idle" }
        task_state_model = [pscustomobject]@{
            current = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["task_state"]) { [string]$recoveryWatchdog.task_state } else { "idle" }
            progress_classification = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["progress_classification"]) { [string]$recoveryWatchdog.progress_classification } else { "no_progress_but_heartbeats_present" }
            heartbeat_age_seconds = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["heartbeat_age_seconds"]) { [int]$recoveryWatchdog.heartbeat_age_seconds } else { -1 }
            stall_threshold_seconds = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["stall_threshold_seconds"]) { [int]$recoveryWatchdog.stall_threshold_seconds } else { -1 }
            recovery_attempts = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["recovery_attempts"]) { [int]$recoveryWatchdog.recovery_attempts } else { 0 }
            consecutive_freezes = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["consecutive_freezes"]) { [int]$recoveryWatchdog.consecutive_freezes } else { 0 }
            last_recovery_time = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["last_recovery_time"]) { [string]$recoveryWatchdog.last_recovery_time } else { "" }
        }
        engineering_signal = $engineeringSignal
        bridge_status = $bridgeStatus
        self_health_maintenance = $selfHealthMaintenance
        cadence_health = $cadenceHealth
        steady_state = $steadyState
        data_sources = $dataSources
        voice_adapter = $voiceAdapterStatus
        mim_proposal = $mimProposal
        mim_proposal_conflict = $mimProposalConflict
        mim_proposal_arbitration = $mimProposalArbitration
        mim_proposal_merge_policy = $mimProposalMergePolicy
        mim_proposal_acknowledgment = $mimProposalAcknowledgment
        mim_proposal_closure = $mimProposalClosure
    }

    if ($validationHarnessProfile) {
        return Apply-OperatorChatValidationHarnessToStatus -ProjectStatus $payload -ValidationHarnessProfile $validationHarnessProfile -RequestedObjectiveId $ObjectiveId
    }

    return $payload
}

function Get-TaskStatePayload {
    $recoveryWatchdog = Get-RecoveryWatchdogStatus
    $listenerActivity = Get-ListenerActivity

    return [pscustomobject]@{
        ok = $true
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        current_state = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["task_state"]) { [string]$recoveryWatchdog.task_state } else { "idle" }
        watchdog_state = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["state"]) { [string]$recoveryWatchdog.state } else { "unknown" }
        progress_classification = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["progress_classification"]) { [string]$recoveryWatchdog.progress_classification } else { "no_progress_but_heartbeats_present" }
        last_task_heartbeat = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["last_task_heartbeat"]) { [string]$recoveryWatchdog.last_task_heartbeat } else { "" }
        heartbeat_age_seconds = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["heartbeat_age_seconds"]) { [int]$recoveryWatchdog.heartbeat_age_seconds } else { -1 }
        stall_threshold_seconds = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["stall_threshold_seconds"]) { [int]$recoveryWatchdog.stall_threshold_seconds } else { -1 }
        recovery_attempts = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["recovery_attempts"]) { [int]$recoveryWatchdog.recovery_attempts } else { 0 }
        consecutive_freezes = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["consecutive_freezes"]) { [int]$recoveryWatchdog.consecutive_freezes } else { 0 }
        last_recovery_time = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["last_recovery_time"]) { [string]$recoveryWatchdog.last_recovery_time } else { "" }
        last_issue = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["last_issue"]) { [string]$recoveryWatchdog.last_issue } else { "" }
        last_recovery_action = if ($recoveryWatchdog -and $recoveryWatchdog.PSObject.Properties["last_recovery_action"]) { [string]$recoveryWatchdog.last_recovery_action } else { "" }
        latest_request_id = if ($listenerActivity -and $listenerActivity.PSObject.Properties["latest_request_id"]) { [string]$listenerActivity.latest_request_id } else { "" }
        latest_execution_status = if ($listenerActivity -and $listenerActivity.PSObject.Properties["latest_execution_status"]) { [string]$listenerActivity.latest_execution_status } else { "" }
    }
}

Write-UiCrashLog ("UI server started on public port {0}, internal listener port {1}, advertise host {2}" -f $activePort, $activeListenerPort, $resolvedAdvertiseHost)

try {
    while ($listener.IsListening) {
        $context = $null
        try {
            $context = $listener.GetContext()
        }
        catch [System.Net.HttpListenerException] {
            # Listener was stopped (Ctrl+C or shutdown) - exit cleanly
            break
        }
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.AbsolutePath

        try {

        if ($request.HttpMethod -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
            $html = Get-Content -Path $indexPath -Raw
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                Write-BytesResponse -Response $response -StatusCode 200 -Bytes $bytes -ContentType "text/html; charset=utf-8"
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/run") {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $bodyRaw = $reader.ReadToEnd()
                $payload = if ([string]::IsNullOrWhiteSpace($bodyRaw)) { @{} } else { $bodyRaw | ConvertFrom-Json }

                $action = [string]$payload.action
                if ([string]::IsNullOrWhiteSpace($action)) {
                    throw "action is required"
                }

                $invokeParams = @{
                    Action = $action
                }

                if ($payload.PSObject.Properties["top"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.top)) {
                    $invokeParams.Top = [int]$payload.top
                }
                if ($payload.PSObject.Properties["category"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.category)) {
                    $invokeParams.Category = [string]$payload.category
                }
                if ($payload.PSObject.Properties["engine"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.engine)) {
                    $invokeParams.Engine = [string]$payload.engine
                }
                if ($payload.PSObject.Properties["configPath"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.configPath)) {
                    $invokeParams.ConfigPath = [string]$payload.configPath
                }
                if ($payload.PSObject.Properties["taskId"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.taskId)) {
                    $invokeParams.TaskId = [string]$payload.taskId
                }
                if ($payload.PSObject.Properties["requestId"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.requestId)) {
                    $invokeParams.RequestId = [string]$payload.requestId
                }
                if ($payload.PSObject.Properties["statePath"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.statePath)) {
                    $invokeParams.StatePath = [string]$payload.statePath
                }
                if ($payload.PSObject.Properties["objectiveId"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.objectiveId)) {
                    $invokeParams.ObjectiveId = [string]$payload.objectiveId
                }
                if ($payload.PSObject.Properties["applyPlan"] -and [bool]$payload.applyPlan) {
                    $invokeParams.ApplyPlan = $true
                }
                if ($payload.PSObject.Properties["allowContractDrift"] -and [bool]$payload.allowContractDrift) {
                    $invokeParams.AllowContractDrift = $true
                }

                if ([string]::Equals($action, 'run-task', [System.StringComparison]::OrdinalIgnoreCase)) {
                    if (-not $invokeParams.ContainsKey('TaskId') -or [string]::IsNullOrWhiteSpace([string]$invokeParams.TaskId)) {
                        throw 'run-task requires taskId.'
                    }
                    if ($invokeParams.ContainsKey('RequestId') -and -not [string]::IsNullOrWhiteSpace([string]$invokeParams.RequestId)) {
                        throw 'run-task does not accept requestId. Use action=run-bridge-request with requestId for live bridge requests.'
                    }
                }
                elseif ([string]::Equals($action, 'run-bridge-request', [System.StringComparison]::OrdinalIgnoreCase)) {
                    if (-not $invokeParams.ContainsKey('RequestId') -or [string]::IsNullOrWhiteSpace([string]$invokeParams.RequestId)) {
                        throw 'run-bridge-request requires requestId.'
                    }
                    if ($invokeParams.ContainsKey('TaskId') -and -not [string]::IsNullOrWhiteSpace([string]$invokeParams.TaskId)) {
                        throw 'run-bridge-request does not accept taskId. Use requestId only for the bridge lane.'
                    }
                }
                elseif ($invokeParams.ContainsKey('RequestId') -and -not [string]::IsNullOrWhiteSpace([string]$invokeParams.RequestId)) {
                    throw ("Action '{0}' does not accept requestId. requestId is reserved for run-bridge-request." -f $action)
                }

                $lightweightActions = @(
                    "get-state-bus",
                    "get-reliability",
                    "show-reliability-dashboard",
                    "show-failure-taxonomy",
                    "get-engineering-loop-summary",
                    "get-engineering-signal",
                    "get-engineering-loop-history"
                )

                $canUseLightweight = ($lightweightActions -contains $action)
                if ($canUseLightweight -and (Test-ShouldUseLightweightStateBus)) {
                    $lightweightResult = Invoke-LightweightUiAction -Action $action
                    $result = [pscustomobject]@{
                        ok = $true
                        result = $lightweightResult
                    }
                    Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 22)
                    continue
                }

                $applyPlanRequested = ($invokeParams.ContainsKey('ApplyPlan') -and [bool]$invokeParams.ApplyPlan)
                $gateConfigPath = if ($invokeParams.ContainsKey('ConfigPath')) { [string]$invokeParams.ConfigPath } else { '' }
                $executionReadinessGate = Get-OperatorChatExecutionReadinessGate -ActionName $action -ConfigPath $gateConfigPath -ApplyPlan:$applyPlanRequested

                if ([bool]$executionReadinessGate.blocked) {
                    $blockedPayload = [pscustomobject]@{
                        task_id = if ($invokeParams.ContainsKey('TaskId')) { [string]$invokeParams.TaskId } else { '' }
                        decision = 'blocked'
                        blocked = $true
                        execution_readiness = $executionReadinessGate.trace
                        execution_trace = [pscustomobject]@{
                            action = $action
                            execution_readiness = $executionReadinessGate.trace
                        }
                        message = "$action blocked by execution-readiness policy before child invocation."
                    }
                    $result = [pscustomobject]@{
                        ok = $true
                        result = $blockedPayload
                    }
                    Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 22)
                    continue
                }

                if ([bool]$executionReadinessGate.degraded -and [string]::Equals($action, 'engineer-run', [System.StringComparison]::OrdinalIgnoreCase) -and $applyPlanRequested -and -not [bool]$executionReadinessGate.effective_apply_plan) {
                    $degradedPayload = [pscustomobject]@{
                        execution_readiness = $executionReadinessGate.signal.readiness
                        execution_readiness_degraded = $true
                        apply_plan_effective = $false
                        execution_trace = [pscustomobject]@{
                            action = $action
                            execution_readiness = $executionReadinessGate.trace
                        }
                        phases = [pscustomobject]@{
                            implement = [pscustomobject]@{
                                status = 'planned_only'
                                apply_requested = $false
                            }
                        }
                    }
                    $result = [pscustomobject]@{
                        ok = $true
                        result = $degradedPayload
                    }
                    Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 22)
                    continue
                }

                # Run TOD action as child process to isolate OOM and other fatal errors
                $invokeArgList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $todScript)
                foreach ($k in $invokeParams.Keys) {
                    if ($invokeParams[$k] -is [bool]) {
                        if ([bool]$invokeParams[$k]) {
                            $invokeArgList += "-$k"
                        }
                        continue
                    }
                    $invokeArgList += "-$k"
                    $invokeArgList += [string]$invokeParams[$k]
                }
                $output = powershell @invokeArgList 2>&1
                $exitCode = $LASTEXITCODE
                $parsed = $null
                try {
                    $parsed = $output | Out-String | ConvertFrom-Json
                }
                catch {
                    $parsed = [pscustomobject]@{ raw = [string]($output | Out-String) }
                }

                $rawOutputText = [string]($output | Out-String)
                $isOutOfMemory = ($rawOutputText -match 'OutOfMemoryException')
                if ($canUseLightweight -and $isOutOfMemory) {
                    $lightweightResult = Invoke-LightweightUiAction -Action $action
                    $parsed = $lightweightResult
                    $exitCode = 0
                }

                if ($exitCode -ne 0 -and $null -eq $parsed.error) {
                    $parsed | Add-Member -NotePropertyName exit_code -NotePropertyValue $exitCode -Force
                }

                $result = [pscustomobject]@{
                    ok = $true
                    result = $parsed
                }
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 22)
            }
            catch {
                Write-UiCrashLog ("[OPERATOR-CHAT-ERROR] " + ($_ | Out-String))
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/operator-chat") {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $bodyRaw = $reader.ReadToEnd()
                $payload = if ([string]::IsNullOrWhiteSpace($bodyRaw)) { @{} } else { $bodyRaw | ConvertFrom-Json }

                $query = if ($payload.PSObject.Properties['query']) { [string]$payload.query } else { '' }
                $intent = if ($payload.PSObject.Properties['intent']) { [string]$payload.intent } else { '' }
                $objectiveId = if ($payload.PSObject.Properties['objective_id']) { [string]$payload.objective_id } else { '' }
                $windowMinutes = if ($payload.PSObject.Properties['window_minutes']) { [int]$payload.window_minutes } else { 10 }
                $validationHarness = if ($payload.PSObject.Properties['validation_harness']) { [string]$payload.validation_harness } else { '' }

                $result = Invoke-OperatorChatQuery -Query $query -Intent $intent -ObjectiveId $objectiveId -WindowMinutes $windowMinutes -ValidationHarness $validationHarness
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 18)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/operator-chat-action") {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $bodyRaw = $reader.ReadToEnd()
                $payload = if ([string]::IsNullOrWhiteSpace($bodyRaw)) { @{} } else { $bodyRaw | ConvertFrom-Json }

                $phase = if ($payload.PSObject.Properties['phase']) { [string]$payload.phase } else { 'preview' }
                $action = if ($payload.PSObject.Properties['action']) { [string]$payload.action } else { '' }
                $intent = if ($payload.PSObject.Properties['intent']) { [string]$payload.intent } else { '' }
                $objectiveId = if ($payload.PSObject.Properties['objective_id']) { [string]$payload.objective_id } else { '' }
                $query = if ($payload.PSObject.Properties['query']) { [string]$payload.query } else { '' }
                $windowMinutes = if ($payload.PSObject.Properties['window_minutes']) { [int]$payload.window_minutes } else { 10 }
                $operatorId = if ($payload.PSObject.Properties['operator_id']) { [string]$payload.operator_id } else { 'local-operator' }
                $suggestedReason = if ($payload.PSObject.Properties['suggested_reason']) { [string]$payload.suggested_reason } else { '' }
                $mode = if ($payload.PSObject.Properties['mode']) { [string]$payload.mode } else { '' }
                $previewId = if ($payload.PSObject.Properties['preview_id']) { [string]$payload.preview_id } else { '' }
                $configPathOverride = if ($payload.PSObject.Properties['configPath']) { [string]$payload.configPath } else { '' }
                $validationHarness = if ($payload.PSObject.Properties['validation_harness']) { [string]$payload.validation_harness } else { '' }
                $remoteEndpoint = if ($request.RemoteEndPoint) { [string]$request.RemoteEndPoint } else { '' }

                if ([string]::IsNullOrWhiteSpace($action)) {
                    throw 'action is required'
                }

                $result = Invoke-OperatorChatActionRequest -Phase $phase -Action $action -Intent $intent -ObjectiveId $objectiveId -Query $query -WindowMinutes $windowMinutes -OperatorId $operatorId -SuggestedReason $suggestedReason -Mode $mode -PreviewId $previewId -ConfigPath $configPathOverride -RemoteEndpoint $remoteEndpoint -ValidationHarness $validationHarness
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 20)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/operator-chat-commitment") {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $bodyRaw = $reader.ReadToEnd()
                $payload = if ([string]::IsNullOrWhiteSpace($bodyRaw)) { @{} } else { $bodyRaw | ConvertFrom-Json }

                $previewId = if ($payload.PSObject.Properties['preview_id']) { [string]$payload.preview_id } else { '' }
                $operatorId = if ($payload.PSObject.Properties['operator_id']) { [string]$payload.operator_id } else { 'local-operator' }
                $objectiveId = if ($payload.PSObject.Properties['objective_id']) { [string]$payload.objective_id } else { '' }
                $state = if ($payload.PSObject.Properties['state']) { [string]$payload.state } else { 'committed' }
                $durationMinutes = if ($payload.PSObject.Properties['duration_minutes']) { [int]$payload.duration_minutes } else { 15 }
                $validationHarness = if ($payload.PSObject.Properties['validation_harness']) { [string]$payload.validation_harness } else { '' }

                $result = Invoke-OperatorChatCommitmentRequest -PreviewId $previewId -OperatorId $operatorId -ObjectiveId $objectiveId -State $state -DurationMinutes $durationMinutes -ValidationHarness $validationHarness
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 20)
            }
            catch {
                Write-UiCrashLog ("[OPERATOR-CHAT-COMMITMENT-ERROR] " + $_.Exception.ToString())
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/operator-chat-feedback") {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $bodyRaw = $reader.ReadToEnd()
                $payload = if ([string]::IsNullOrWhiteSpace($bodyRaw)) { @{} } else { $bodyRaw | ConvertFrom-Json }

                $action = if ($payload.PSObject.Properties['action']) { [string]$payload.action } else { '' }
                $intent = if ($payload.PSObject.Properties['intent']) { [string]$payload.intent } else { '' }
                $objectiveId = if ($payload.PSObject.Properties['objective_id']) { [string]$payload.objective_id } else { '' }
                $polarity = if ($payload.PSObject.Properties['polarity']) { [string]$payload.polarity } else { '' }
                $operatorId = if ($payload.PSObject.Properties['operator_id']) { [string]$payload.operator_id } else { 'local-operator' }
                $query = if ($payload.PSObject.Properties['query']) { [string]$payload.query } else { '' }
                $note = if ($payload.PSObject.Properties['note']) { [string]$payload.note } else { '' }

                $result = Invoke-OperatorChatFeedbackRequest -Action $action -Intent $intent -ObjectiveId $objectiveId -Polarity $polarity -Actor $operatorId -Query $query -Note $note
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 16)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/operator-chat-action-audit") {
            try {
                $limitRaw = [string]$request.QueryString["limit"]
                $auditId = [string]$request.QueryString["audit_id"]
                $previewId = [string]$request.QueryString["preview_id"]
                $limit = 8
                if (-not [string]::IsNullOrWhiteSpace($limitRaw)) {
                    $parsedLimit = 0
                    if ([int]::TryParse($limitRaw, [ref]$parsedLimit)) {
                        $limit = $parsedLimit
                    }
                }
                        $action = [string]$request.QueryString["action"]
                        $reasoningBundleId = [string]$request.QueryString["reasoning_bundle_id"]
                        $outcomeStatus = [string]$request.QueryString["outcome_status"]
                        $phase = [string]$request.QueryString["phase"]
                        $search = [string]$request.QueryString["search"]

                        $payload = Get-OperatorChatActionAuditPayload -Limit $limit -AuditId $auditId -PreviewId $previewId -Action $action -ReasoningBundleId $reasoningBundleId -OutcomeStatus $outcomeStatus -Phase $phase -Search $search
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 20)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/operator-chat-action-reasoning") {
            try {
                $limitRaw = [string]$request.QueryString["limit"]
                $bundleId = [string]$request.QueryString["bundle_id"]
                $limit = 6
                if (-not [string]::IsNullOrWhiteSpace($limitRaw)) {
                    $parsedLimit = 0
                    if ([int]::TryParse($limitRaw, [ref]$parsedLimit)) {
                        $limit = $parsedLimit
                    }
                }

                $payload = Get-OperatorChatReasoningPayload -Limit $limit -BundleId $bundleId
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 20)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/operator-chat-feedback") {
            try {
                $limitRaw = [string]$request.QueryString["limit"]
                $objectiveId = [string]$request.QueryString["objective_id"]
                $action = [string]$request.QueryString["action"]
                $intent = [string]$request.QueryString["intent"]
                $limit = 12
                if (-not [string]::IsNullOrWhiteSpace($limitRaw)) {
                    $parsedLimit = 0
                    if ([int]::TryParse($limitRaw, [ref]$parsedLimit)) {
                        $limit = $parsedLimit
                    }
                }

                $payload = Get-OperatorChatFeedbackPayload -Limit $limit -ObjectiveId $objectiveId -Action $action -Intent $intent
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 20)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/operator-chat-commitments") {
            try {
                $limitRaw = [string]$request.QueryString["limit"]
                $commitmentId = [string]$request.QueryString["commitment_id"]
                $previewId = [string]$request.QueryString["preview_id"]
                $reasoningBundleId = [string]$request.QueryString["reasoning_bundle_id"]
                $objectiveId = [string]$request.QueryString["objective_id"]
                $state = [string]$request.QueryString["state"]
                $validationHarness = [string]$request.QueryString["validation_harness"]
                $limit = 6
                if (-not [string]::IsNullOrWhiteSpace($limitRaw)) {
                    $parsedLimit = 0
                    if ([int]::TryParse($limitRaw, [ref]$parsedLimit)) {
                        $limit = $parsedLimit
                    }
                }

                $payload = Get-OperatorChatCommitmentPayload -Limit $limit -CommitmentId $commitmentId -PreviewId $previewId -ReasoningBundleId $reasoningBundleId -ObjectiveId $objectiveId -State $state -ValidationHarness $validationHarness
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 20)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/operator-chat-action-trust-chain") {
            try {
                $auditId = [string]$request.QueryString["audit_id"]
                $previewId = [string]$request.QueryString["preview_id"]
                $bundleId = [string]$request.QueryString["bundle_id"]
                $commitmentId = [string]$request.QueryString["commitment_id"]
                $comparisonObjectiveId = [string]$request.QueryString["comparison_objective_id"]
                $validationMode = [string]$request.QueryString["validation_mode"]
                $validationHarness = [string]$request.QueryString["validation_harness"]

                $payload = Get-OperatorChatTrustChainPayload -AuditId $auditId -PreviewId $previewId -BundleId $bundleId -CommitmentId $commitmentId -ComparisonObjectiveId $comparisonObjectiveId -ValidationMode $validationMode -ValidationHarness $validationHarness
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 20)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/logs") {
            try {
                $tailRaw = [string]$request.QueryString["tail"]
                $tail = 80
                if (-not [string]::IsNullOrWhiteSpace($tailRaw)) {
                    $parsedTail = 0
                    if ([int]::TryParse($tailRaw, [ref]$parsedTail)) {
                        $tail = $parsedTail
                    }
                }

                $lines = Get-RecentLogLines -LogPath $defaultLogPath -Tail $tail
                $entries = @()
                foreach ($line in $lines) {
                    if ([string]::IsNullOrWhiteSpace($line)) {
                        continue
                    }

                    try {
                        $entries += @($line | ConvertFrom-Json)
                    }
                    catch {
                        $entries += @([pscustomobject]@{ raw = [string]$line })
                    }
                }

                $payload = [pscustomobject]@{
                    ok = $true
                    log_path = $defaultLogPath
                    count = @($entries).Count
                    entries = @($entries)
                }
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 20)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/project-status") {
            try {
                $objectiveId = [string]$request.QueryString["objective_id"]
                $validationHarness = [string]$request.QueryString["validation_harness"]
                $payload = Get-ProjectStatusPayload -ObjectiveId $objectiveId -ValidationHarness $validationHarness
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 12)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/task-state") {
            try {
                $payload = Get-TaskStatePayload
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 8)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/share-artifacts") {
            try {
                $payload = Get-ShareArtifactsPayload -ActivePort $activePort -BaseUrl $uiUrl
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 8)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/dialog-sessions") {
            try {
                $limitText = [string]$request.QueryString["limit"]
                $limit = 8
                if (-not [string]::IsNullOrWhiteSpace($limitText)) {
                    [void][int]::TryParse($limitText, [ref]$limit)
                }
                $actor = [string]$request.QueryString["actor"]
                $payload = Get-DialogSessionsPayload -Limit $limit -Actor $actor
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 12)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/dialog-session") {
            try {
                $sessionIdValue = [string]$request.QueryString["session_id"]
                $tailText = [string]$request.QueryString["tail"]
                $tail = 12
                if (-not [string]::IsNullOrWhiteSpace($tailText)) {
                    [void][int]::TryParse($tailText, [ref]$tail)
                }
                $payload = Get-DialogSessionPayload -SessionId $sessionIdValue -Tail $tail
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 14)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/share-download") {
            try {
                $key = [string]$request.QueryString["key"]
                if ([string]::IsNullOrWhiteSpace($key) -or -not $shareArtifacts.Contains($key)) {
                    Write-TextResponse -Response $response -StatusCode 404 -Text "Unknown artifact key"
                    continue
                }

                $artifactPath = [string]$shareArtifacts[$key].path
                if (-not (Test-Path -Path $artifactPath)) {
                    Write-TextResponse -Response $response -StatusCode 404 -Text "Artifact not found"
                    continue
                }

                $fileInfo = Get-Item -Path $artifactPath
                $bytes = [System.IO.File]::ReadAllBytes($artifactPath)
                Write-BytesResponse -Response $response -StatusCode 200 -Bytes $bytes -ContentType (Get-MimeTypeForPath -Path $artifactPath) -Headers @{ "Content-Disposition" = ('attachment; filename="{0}"' -f $fileInfo.Name) }
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/share-open") {
            try {
                $key = [string]$request.QueryString["key"]
                if ([string]::IsNullOrWhiteSpace($key) -or -not $shareArtifacts.Contains($key)) {
                    Write-TextResponse -Response $response -StatusCode 404 -Text "Unknown artifact key"
                    continue
                }

                $artifactPath = [string]$shareArtifacts[$key].path
                if (-not (Test-Path -Path $artifactPath)) {
                    Write-TextResponse -Response $response -StatusCode 404 -Text "Artifact not found"
                    continue
                }

                $bytes = [System.IO.File]::ReadAllBytes($artifactPath)
                Write-BytesResponse -Response $response -StatusCode 200 -Bytes $bytes -ContentType (Get-MimeTypeForPath -Path $artifactPath)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        Write-TextResponse -Response $response -StatusCode 404 -Text "Not found"

        } catch {
            # Per-request outer safety net — log and try to return 500 so server keeps running
            $reqErr = "[REQUEST ERROR] $($request.HttpMethod) $path : $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber)"
            Write-UiCrashLog $reqErr
            Write-Warning $reqErr
            try {
                if ($null -ne $response) {
                    try {
                        $response.Abort()
                    }
                    catch {
                        try {
                            $response.Close()
                        }
                        catch {
                        }
                    }
                }
            } catch {}
        }
    }
}
finally {
    if ($uiLanProxyProcess) {
        try {
            if (-not $uiLanProxyProcess.HasExited) {
                Stop-Process -Id $uiLanProxyProcess.Id -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
        }
    }
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
