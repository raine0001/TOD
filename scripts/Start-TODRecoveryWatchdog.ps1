param(
    [int]$CheckEverySeconds = 120,
    [int]$FreezeAfterMinutes = 5,
    [int]$AlertCooldownSeconds = 300,
    [switch]$RestartUiOnFailure,
    [switch]$RunOnce,
    [string]$EnvFile = ".env",
    [string]$ListenerScriptPath = "scripts/Start-TODMimPacketListener.ps1",
    [string]$ListenerStartupScriptPath = "scripts/Start-TODMimListenerStartup.ps1",
    [string]$BridgeSmokeScriptPath = "scripts/Invoke-TODMimBridgeSmoke.ps1",
    [string]$SharedStateSyncScriptPath = "scripts/Invoke-TODSharedStateSync.ps1",
    [string]$DialogScriptPath = "scripts/Invoke-TODMimDialog.ps1",
    [string]$UiScriptPath = "scripts/Start-TOD-UI.ps1",
    [int]$UiPort = 8844,
    [string]$StageDir = "tod/out/context-sync/listener",
    [string]$SharedStateDir = "shared_state",
    [switch]$PublishDialogRemote
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

function Get-SafeDialogSessionId {
    param([Parameter(Mandatory = $true)][string]$Seed)

    $safe = ([string]$Seed).Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = 'tod-watchdog'
    }

    return ($safe -replace '[^a-zA-Z0-9._-]', '_')
}

function Normalize-ObjectiveIdentity {
    param([string]$Value)

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    $match = [regex]::Match($text, '^(?i:objective-)?(?<id>.+)$')
    if ($match.Success) {
        return ([string]$match.Groups['id'].Value).Trim().ToLowerInvariant()
    }

    return $text.ToLowerInvariant()
}

function Test-PublicationSurfaceRecoveryNeeded {
    param(
        [AllowNull()]$BridgeSmoke = $null,
        [AllowEmptyCollection()][string[]]$BridgeFailureModes = @(),
        [bool]$LocalTerminalRequestFinished = $false
    )

    if ($null -eq $BridgeSmoke -or [bool]$BridgeSmoke.passed) {
        return $false
    }

    $failureModes = @(
        $BridgeFailureModes |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $hasPublicationIssue = @(
        'publication_surface_divergence',
        'stale_remote_request_identity',
        'canonical_request_mismatch'
    ) | Where-Object { $failureModes -contains $_ } | Select-Object -First 1

    if ($null -eq $hasPublicationIssue) {
        return $false
    }

    if (-not $LocalTerminalRequestFinished) {
        # If the remote surface was recently written by the TOD UI (operator-issued objective), trust it.
        $earlyCanonicalRequest = if ($BridgeSmoke.PSObject.Properties['canonical_request']) { $BridgeSmoke.canonical_request } else { $null }
        $earlyRemoteSurface = if ($earlyCanonicalRequest -and $earlyCanonicalRequest.PSObject.Properties['remote_surface']) { $earlyCanonicalRequest.remote_surface } else { $null }
        $earlySourceService = if ($earlyRemoteSurface -and $earlyRemoteSurface.PSObject.Properties['source_service']) { [string]$earlyRemoteSurface.source_service } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($earlySourceService) -and $earlySourceService -match '^tod-ui') {
            $earlyGeneratedAt = if ($earlyRemoteSurface -and $earlyRemoteSurface.PSObject.Properties['generated_at']) { [string]$earlyRemoteSurface.generated_at } else { '' }
            $earlyAgeMinutes = [double]::MaxValue
            if (-not [string]::IsNullOrWhiteSpace($earlyGeneratedAt)) {
                $parsedDt = [datetime]::MinValue
                if ([datetime]::TryParse($earlyGeneratedAt, [ref]$parsedDt)) {
                    $earlyAgeMinutes = ([datetime]::UtcNow - $parsedDt.ToUniversalTime()).TotalMinutes
                }
            }
            if ($earlyAgeMinutes -le 20.0) {
                return $false
            }
        }
        return $true
    }

    $canonicalRequest = if ($BridgeSmoke.PSObject.Properties['canonical_request']) { $BridgeSmoke.canonical_request } else { $null }
    $remoteSurface = if ($canonicalRequest -and $canonicalRequest.PSObject.Properties['remote_surface']) { $canonicalRequest.remote_surface } else { $null }
    $localBridge = if ($BridgeSmoke.PSObject.Properties['local_bridge']) { $BridgeSmoke.local_bridge } else { $null }
    $expectedObjectiveId = if ($canonicalRequest -and $canonicalRequest.PSObject.Properties['expected_objective_id']) { Normalize-ObjectiveIdentity -Value ([string]$canonicalRequest.expected_objective_id) } else { '' }
    $remoteObjectiveId = if ($remoteSurface -and $remoteSurface.PSObject.Properties['objective_id']) { Normalize-ObjectiveIdentity -Value ([string]$remoteSurface.objective_id) } else { '' }
    $remoteRequestId = if ($remoteSurface -and $remoteSurface.PSObject.Properties['request_id']) { [string]$remoteSurface.request_id } elseif ($remoteSurface -and $remoteSurface.PSObject.Properties['task_id']) { [string]$remoteSurface.task_id } else { '' }
    $localRequestId = if ($localBridge -and $localBridge.PSObject.Properties['request_id']) { [string]$localBridge.request_id } else { '' }

    if (-not [string]::IsNullOrWhiteSpace($expectedObjectiveId) -and -not [string]::IsNullOrWhiteSpace($remoteObjectiveId) -and -not [string]::Equals($expectedObjectiveId, $remoteObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
        # If the divergence is because the TOD UI recently issued a new objective, defer to that authority.
        $remoteSourceService = if ($remoteSurface -and $remoteSurface.PSObject.Properties['source_service']) { [string]$remoteSurface.source_service } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($remoteSourceService) -and $remoteSourceService -match '^tod-ui') {
            $remoteGeneratedAt = if ($remoteSurface -and $remoteSurface.PSObject.Properties['generated_at']) { [string]$remoteSurface.generated_at } else { '' }
            $uiWriteAgeMinutes = [double]::MaxValue
            if (-not [string]::IsNullOrWhiteSpace($remoteGeneratedAt)) {
                $parsedDt = [datetime]::MinValue
                if ([datetime]::TryParse($remoteGeneratedAt, [ref]$parsedDt)) {
                    $uiWriteAgeMinutes = ([datetime]::UtcNow - $parsedDt.ToUniversalTime()).TotalMinutes
                }
            }
            if ($uiWriteAgeMinutes -le 20.0) {
                return $false
            }
        }
        return $true
    }

    if (-not [string]::IsNullOrWhiteSpace($remoteRequestId) -and -not [string]::IsNullOrWhiteSpace($localRequestId) -and -not [string]::Equals($remoteRequestId, $localRequestId, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    # A terminal local request does not clear a stale remote publication boundary.
    return $true
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

function Invoke-DialogNotice {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptAbs,
        [Parameter(Mandatory = $true)][ValidateSet('send', 'close-session')][string]$Action,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$MessageType,
        [Parameter(Mandatory = $true)][string]$Intent,
        [Parameter(Mandatory = $true)][string]$Summary,
        [Parameter(Mandatory = $true)]$Payload,
        [string]$TaskId = '',
        [string]$CorrelationId = '',
        [string]$EnvPath = '',
        [switch]$PublishRemote
    )

    if (-not (Test-Path -Path $ScriptAbs)) {
        return [pscustomobject]@{
            ok = $false
            status = 'dialog_script_missing'
        }
    }

    try {
        $payloadJson = $Payload | ConvertTo-Json -Depth 12 -Compress
        $args = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $ScriptAbs,
            '-Action', $Action,
            '-SessionId', $SessionId,
            '-Actor', 'TOD',
            '-PeerActor', 'MIM',
            '-MessageType', $MessageType,
            '-Intent', $Intent,
            '-Summary', $Summary,
            '-PayloadJson', $payloadJson,
            '-TaskId', $TaskId,
            '-CorrelationId', $CorrelationId,
            '-EmitJson'
        )
        if (-not [string]::IsNullOrWhiteSpace($EnvPath) -and (Test-Path -Path $EnvPath)) {
            $args += @('-DotEnvPath', $EnvPath)
        }
        if ($PublishRemote) {
            $args += '-PublishRemote'
        }

        $null = & powershell.exe @args
        return [pscustomobject]@{
            ok = $true
            status = 'sent'
        }
    }
    catch {
        return [pscustomobject]@{
            ok = $false
            status = 'send_failed'
            error = [string]$_.Exception.Message
        }
    }
}

function Get-ScriptHostProcesses {
    param([Parameter(Mandatory = $true)][string[]]$ScriptPaths)

    $normalizedPaths = @(
        $ScriptPaths |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object {
                try {
                    [System.IO.Path]::GetFullPath([string]$_)
                }
                catch {
                    [string]$_
                }
            } |
            Select-Object -Unique
    )

    if (@($normalizedPaths).Count -eq 0) {
        return @()
    }

    $scriptMatchers = @(
        $normalizedPaths |
            ForEach-Object {
                $fullPath = [string]$_
                $leafName = ""
                try {
                    $leafName = [System.IO.Path]::GetFileName($fullPath)
                }
                catch {
                    $leafName = $fullPath
                }

                [pscustomobject]@{
                    full_path = $fullPath
                    leaf_name = $leafName
                }
            }
    )

    return @(
        Get-CimInstance Win32_Process | Where-Object {
            $commandLine = [string]$_.CommandLine
            if ([string]::IsNullOrWhiteSpace($commandLine)) {
                return $false
            }

            foreach ($matcher in $scriptMatchers) {
                if (-not [string]::IsNullOrWhiteSpace([string]$matcher.full_path) -and $commandLine -match [regex]::Escape([string]$matcher.full_path)) {
                    return $true
                }

                if (-not [string]::IsNullOrWhiteSpace([string]$matcher.leaf_name) -and $commandLine -match ("(?i){0}" -f [regex]::Escape([string]$matcher.leaf_name))) {
                    return $true
                }
            }

            return $false
        }
    )
}

function Test-ListenerRunning {
    param(
        [Parameter(Mandatory = $true)][string]$ListenerScriptAbs,
        [string]$ListenerStartupScriptAbs = ""
    )

    $scriptHosts = @($ListenerScriptAbs)
    if (-not [string]::IsNullOrWhiteSpace($ListenerStartupScriptAbs)) {
        $scriptHosts += $ListenerStartupScriptAbs
    }

    $procs = Get-ScriptHostProcesses -ScriptPaths $scriptHosts
    return ([bool](@($procs).Count -gt 0))
}

function Stop-ScriptProcesses {
    param([Parameter(Mandatory = $true)][string[]]$ScriptAbs)

    $procs = Get-ScriptHostProcesses -ScriptPaths $ScriptAbs

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

function Invoke-BridgeSmokeCheck {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptAbs,
        [Parameter(Mandatory = $true)][string]$StageDirValue,
        [Parameter(Mandatory = $true)][string]$IntegrationStatusPathValue,
        [Parameter(Mandatory = $true)][string]$OutputPathValue
    )

    if (-not (Test-Path -Path $ScriptAbs)) {
        return [pscustomobject]@{
            available = $false
            passed = $false
            status = "unavailable"
            failure_modes = @("bridge_smoke_script_missing")
            error = "bridge_smoke_script_missing"
        }
    }

    $invokeError = ""
    try {
        & $ScriptAbs -ListenerStageDir $StageDirValue -IntegrationStatusPath $IntegrationStatusPathValue -OutputPath $OutputPathValue | Out-Null
    }
    catch {
        $invokeError = [string]$_.Exception.Message
    }

    $doc = Read-JsonFileIfExists -PathValue $OutputPathValue
    if ($null -eq $doc) {
        return [pscustomobject]@{
            available = $true
            passed = $false
            status = "error"
            failure_modes = @("bridge_smoke_output_missing")
            error = if ([string]::IsNullOrWhiteSpace($invokeError)) { "bridge_smoke_output_missing" } else { $invokeError }
        }
    }

    $doc | Add-Member -NotePropertyName available -NotePropertyValue $true -Force
    if (-not $doc.PSObject.Properties['error']) {
        $doc | Add-Member -NotePropertyName error -NotePropertyValue $invokeError -Force
    }
    elseif (-not [string]::IsNullOrWhiteSpace($invokeError)) {
        $doc.error = $invokeError
    }

    return $doc
}

function Get-RecoveryGuidance {
    param(
        [string]$IssueCode,
        [AllowEmptyCollection()][string[]]$BridgeFailureModes = @()
    )

    $guidance = New-Object System.Collections.Generic.List[string]

    switch ($IssueCode) {
        "listener_not_running" {
            $guidance.Add("Restart the TOD listener host and verify a fresh ACK or result artifact appears before escalating.")
        }
        "listener_stalled_pending_request" {
            $guidance.Add("Treat this as a real local bridge stall only when ACK, result, and listener-cycle freshness all stop moving.")
            $guidance.Add("Restart the listener, then verify the latest request id matches both ACK and result before escalating.")
        }
        "bridge_remote_publish_unverified" {
            $guidance.Add("Do not restart the listener first; republish TOD shared state to MIM and verify remote mirror plus consumer execution.")
            $guidance.Add("Escalate only if remote publish stays unverified after a fresh shared-state sync.")
        }
        "bridge_objective_misaligned" {
            $guidance.Add("Refresh MIM context and shared-state sync to re-establish canonical objective alignment before restarting runtime processes.")
        }
        "publication_surface_divergence" {
            $guidance.Add("Treat the remote SSH/SFTP canonical request as the live boundary and do not restart the listener just because the boundary is stale.")
            $guidance.Add("Capture remote request fingerprints before and after controlled MIM publishes, then repair or retarget the publication surface only with evidence.")
        }
        "ui_unhealthy" {
            $guidance.Add("Recover the UI host only after bridge health is confirmed so a UI outage is not misread as a listener freeze.")
        }
    }

    if (@($BridgeFailureModes).Count -eq 0) {
        return @($guidance | Select-Object -Unique)
    }

    foreach ($failureMode in @($BridgeFailureModes)) {
        switch ([string]$failureMode) {
            "listener_contract_stalled" {
                $guidance.Add("Local bridge mutation is stale; confirm listener_state, ACK, and result timestamps stop advancing before declaring the bridge frozen.")
            }
            "remote_publish_not_verified" {
                $guidance.Add("Local listener work is healthy; the failure domain is remote delivery or consumer execution, not trigger processing.")
            }
            "objective_alignment_not_in_sync" {
                $guidance.Add("Current live request and canonical objective disagree; refresh shared-state evidence rather than recycling the listener blindly.")
            }
            "publication_surface_divergence" {
                $guidance.Add("The active failure domain is the remote publication surface; hold listener logic fixed until the remote boundary evidence changes.")
            }
            "stale_remote_request_identity" {
                $guidance.Add("The remote canonical request identity is stale relative to the expected live objective; capture and compare fingerprints instead of rewriting the request from TOD.")
            }
            "canonical_request_mismatch" {
                $guidance.Add("Local listener mirror and remote canonical request differ; verify which boundary TOD is actually consuming before restarting anything.")
            }
        }
    }

    return @($guidance | Select-Object -Unique)
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

function Get-DateOrMinValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [datetime]::MinValue
    }

    try {
        return [datetime]::Parse([string]$Value).ToUniversalTime()
    }
    catch {
        return [datetime]::MinValue
    }
}

function Publish-PacketToMim {
    param(
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$LocalPacketPath,
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared"
    )

    Write-JsonFile -PathValue $LocalPacketPath -Payload $Payload

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

function Publish-RecoveryAlertToMim {
    param(
        [Parameter(Mandatory = $true)]$AlertPayload,
        [Parameter(Mandatory = $true)][string]$LocalPacketPath,
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared"
    )

    return Publish-PacketToMim -Payload $AlertPayload -LocalPacketPath $LocalPacketPath -EnvPath $EnvPath -RemoteRoot $RemoteRoot
}

function New-PublicationSurfaceCoordinationRequest {
    param(
        [Parameter(Mandatory = $true)][string]$IssueCode,
        [Parameter(Mandatory = $true)][string]$IssueDetail,
        [Parameter(Mandatory = $true)][string]$AlertSignature,
        [string]$RequestId = '',
        [string[]]$BridgeFailureModes = @(),
        [AllowNull()]$BridgeSmoke = $null
    )

    $generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    $canonicalRequest = if ($BridgeSmoke -and $BridgeSmoke.PSObject.Properties['canonical_request']) { $BridgeSmoke.canonical_request } else { $null }
    $localBridge = if ($BridgeSmoke -and $BridgeSmoke.PSObject.Properties['local_bridge']) { $BridgeSmoke.local_bridge } else { $null }
    $remoteBoundary = if ($BridgeSmoke -and $BridgeSmoke.PSObject.Properties['remote_boundary']) { $BridgeSmoke.remote_boundary } else { $null }
    $expectedObjectiveId = if ($canonicalRequest -and $canonicalRequest.PSObject.Properties['expected_objective_id']) { [string]$canonicalRequest.expected_objective_id } else { '' }
    $remoteSurface = if ($canonicalRequest -and $canonicalRequest.PSObject.Properties['remote_surface']) { $canonicalRequest.remote_surface } else { $null }
    $remoteObjectiveId = if ($remoteSurface -and $remoteSurface.PSObject.Properties['objective_id']) { [string]$remoteSurface.objective_id } else { '' }
    $remoteTaskId = if ($remoteSurface -and $remoteSurface.PSObject.Properties['task_id']) { [string]$remoteSurface.task_id } else { '' }
    $localRequestId = if ($localBridge -and $localBridge.PSObject.Properties['request_id']) { [string]$localBridge.request_id } else { '' }
    $coordinationRequestId = if (-not [string]::IsNullOrWhiteSpace($RequestId)) {
        ('coordination-{0}-{1}' -f $RequestId, $IssueCode)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($expectedObjectiveId)) {
        ('coordination-{0}-{1}' -f $expectedObjectiveId, $IssueCode)
    }
    else {
        ('coordination-{0}' -f $IssueCode)
    }

    return [pscustomobject]@{
        generated_at = $generatedAt
        source = 'tod-mim-coordination-request-v1'
        priority = 'high'
        escalation_level = 1
        request_id = $coordinationRequestId
        objective_id = $expectedObjectiveId
        task_id = $RequestId
        correlation_id = $AlertSignature
        issue_code = $IssueCode
        issue_summary = $IssueDetail
        requested_action = 'Republish the live task-request surface from the canonical MIM objective, or acknowledge why the canonical export should remain ahead of live publication.'
        required_ack = [pscustomobject]@{
            ack_file = 'MIM_TOD_COORDINATION_ACK.latest.json'
            ack_fields = @('acknowledged', 'acknowledged_at', 'request_id', 'decision', 'reason', 'target_dispatch_task_id')
            timeout_seconds = 60
        }
        evidence = [pscustomobject]@{
            canonical_expected_objective_id = $expectedObjectiveId
            stale_live_task_request_objective_id = $remoteObjectiveId
            stale_live_task_request_id = $remoteTaskId
            local_listener_request_id = $localRequestId
            bridge_classification = if ($BridgeSmoke -and $BridgeSmoke.PSObject.Properties['classification']) { [string]$BridgeSmoke.classification } else { '' }
            bridge_failure_modes = @($BridgeFailureModes)
            remote_boundary = $remoteBoundary
        }
    }
}

function New-PublicationSurfaceEmergencyRequest {
    param(
        [Parameter(Mandatory = $true)][string]$IssueCode,
        [Parameter(Mandatory = $true)][string]$IssueDetail,
        [Parameter(Mandatory = $true)][string]$ParentRequestId,
        [Parameter(Mandatory = $true)][int]$ElapsedIssueSeconds,
        [AllowNull()]$BridgeSmoke = $null,
        [string]$CoordinationRequestId = ''
    )

    $canonicalRequest = if ($BridgeSmoke -and $BridgeSmoke.PSObject.Properties['canonical_request']) { $BridgeSmoke.canonical_request } else { $null }
    $remoteSurface = if ($canonicalRequest -and $canonicalRequest.PSObject.Properties['remote_surface']) { $canonicalRequest.remote_surface } else { $null }
    $expectedObjectiveId = if ($canonicalRequest -and $canonicalRequest.PSObject.Properties['expected_objective_id']) { [string]$canonicalRequest.expected_objective_id } else { '' }
    $remoteObjectiveId = if ($remoteSurface -and $remoteSurface.PSObject.Properties['objective_id']) { [string]$remoteSurface.objective_id } else { '' }
    $remoteTaskId = if ($remoteSurface -and $remoteSurface.PSObject.Properties['task_id']) { [string]$remoteSurface.task_id } else { '' }

    return [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-mim-emergency-request-v1'
        status = 'active'
        priority = 'critical'
        escalation_level = 4
        request_id = ('tod-watchdog-emergency-{0}-{1}' -f $ParentRequestId, $IssueCode)
        parent_request_id = $CoordinationRequestId
        objective_id = $expectedObjectiveId
        task_id = $ParentRequestId
        issue_code = $IssueCode + '_emergency'
        issue_summary = $IssueDetail
        emergency_reason = ('Watchdog has observed {0} for {1}s without the live publication surface recovering.' -f $IssueCode, [int]$ElapsedIssueSeconds)
        requested_action = 'Reply immediately on MIM_TOD_EMERGENCY_ACK.latest.json, republish or explicitly reject the stale live publication surface, and explain the next update if the canonical surface must remain ahead temporarily.'
        required_ack = [pscustomobject]@{
            ack_file = 'MIM_TOD_EMERGENCY_ACK.latest.json'
            ack_fields = @('acknowledged', 'acknowledged_at', 'request_id', 'decision', 'reason', 'next_update_at')
            timeout_seconds = 15
        }
        evidence = [pscustomobject]@{
            canonical_expected_objective_id = $expectedObjectiveId
            stale_live_task_request_objective_id = $remoteObjectiveId
            stale_live_task_request_id = $remoteTaskId
            bridge_classification = if ($BridgeSmoke -and $BridgeSmoke.PSObject.Properties['classification']) { [string]$BridgeSmoke.classification } else { '' }
            coordination_request_id = $CoordinationRequestId
            elapsed_issue_seconds = [int]$ElapsedIssueSeconds
        }
    }
}

function Publish-CoordinationRequestToMim {
    param(
        [Parameter(Mandatory = $true)]$CoordinationRequest,
        [Parameter(Mandatory = $true)][string]$LocalPacketPath,
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared"
    )

    return Publish-PacketToMim -Payload $CoordinationRequest -LocalPacketPath $LocalPacketPath -EnvPath $EnvPath -RemoteRoot $RemoteRoot
}

function Publish-EmergencyRequestToMim {
    param(
        [Parameter(Mandatory = $true)]$EmergencyRequest,
        [Parameter(Mandatory = $true)][string]$LocalPacketPath,
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared"
    )

    return Publish-PacketToMim -Payload $EmergencyRequest -LocalPacketPath $LocalPacketPath -EnvPath $EnvPath -RemoteRoot $RemoteRoot
}

function Publish-ResolvedEmergencyToMim {
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [Parameter(Mandatory = $true)][string]$IssueCode,
        [Parameter(Mandatory = $true)][string]$LocalPacketPath,
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [string]$ObjectiveId = '',
        [string]$ResolutionReason = '',
        [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared"
    )

    $payload = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-mim-emergency-request-v1'
        status = 'resolved'
        priority = 'none'
        escalation_level = 0
        request_id = $RequestId
        objective_id = $ObjectiveId
        issue_code = ('{0}_emergency_resolved' -f $IssueCode)
        issue_summary = ('TOD cleared the prior emergency request for {0}.' -f $IssueCode)
        requested_action = 'none'
        resolution_reason = $ResolutionReason
        resolved_at = (Get-Date).ToUniversalTime().ToString('o')
    }

    return Publish-PacketToMim -Payload $payload -LocalPacketPath $LocalPacketPath -EnvPath $EnvPath -RemoteRoot $RemoteRoot
}

function Publish-ResolvedCoordinationToMim {
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [Parameter(Mandatory = $true)][string]$IssueCode,
        [Parameter(Mandatory = $true)][string]$LocalPacketPath,
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [string]$ObjectiveId = '',
        [string]$ResolutionReason = '',
        [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared"
    )

    $payload = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-mim-coordination-request-v1'
        status = 'resolved'
        priority = 'none'
        escalation_level = 0
        request_id = $RequestId
        objective_id = $ObjectiveId
        issue_code = ('{0}_resolved' -f $IssueCode)
        issue_summary = ('TOD cleared prior coordination request for {0}.' -f $IssueCode)
        requested_action = 'none'
        resolution_reason = $ResolutionReason
        resolved_at = (Get-Date).ToUniversalTime().ToString('o')
    }

    return Publish-PacketToMim -Payload $payload -LocalPacketPath $LocalPacketPath -EnvPath $EnvPath -RemoteRoot $RemoteRoot
}

function Convert-ToObjectiveLabel {
    param([string]$ObjectiveId)

    $normalized = Normalize-ObjectiveIdentity -Value $ObjectiveId
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return ''
    }

    return ('objective-{0}' -f $normalized)
}

function Get-CanonicalTaskIdForSelfHeal {
    param(
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [AllowNull()]$BridgeSmoke = $null
    )

    $objectiveLabel = Convert-ToObjectiveLabel -ObjectiveId $ObjectiveId
    if ([string]::IsNullOrWhiteSpace($objectiveLabel)) {
        return ''
    }

    $sharedTruthPath = Join-Path $repoRoot 'runtime/shared/TOD_MIM_SHARED_TRUTH.latest.json'
    $sharedTruth = Read-JsonFileIfExists -PathValue $sharedTruthPath
    if ($sharedTruth) {
        $sharedTruthObjective = if ($sharedTruth.PSObject.Properties['objective_id']) {
            Convert-ToObjectiveLabel -ObjectiveId ([string]$sharedTruth.objective_id)
        }
        else {
            ''
        }
        $sharedTruthTaskId = if ($sharedTruth.PSObject.Properties['task_id']) {
            [string]$sharedTruth.task_id
        }
        elseif ($sharedTruth.PSObject.Properties['request_id']) {
            [string]$sharedTruth.request_id
        }
        else {
            ''
        }
        if (-not [string]::IsNullOrWhiteSpace($sharedTruthTaskId) -and [string]::Equals($sharedTruthObjective, $objectiveLabel, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $sharedTruthTaskId
        }
    }

    if ($BridgeSmoke -and $BridgeSmoke.PSObject.Properties['canonical_request'] -and $BridgeSmoke.canonical_request) {
        $canonicalRequest = $BridgeSmoke.canonical_request
        $candidateTaskId = if ($canonicalRequest.PSObject.Properties['expected_task_id']) {
            [string]$canonicalRequest.expected_task_id
        }
        elseif ($canonicalRequest.PSObject.Properties['task_id']) {
            [string]$canonicalRequest.task_id
        }
        elseif ($canonicalRequest.PSObject.Properties['request_id']) {
            [string]$canonicalRequest.request_id
        }
        else {
            ''
        }
        if (-not [string]::IsNullOrWhiteSpace($candidateTaskId)) {
            return $candidateTaskId
        }
    }

    return ''
}

function Get-CanonicalObjectiveForSelfHeal {
    param(
        [AllowNull()]$IntegrationStatus = $null,
        [AllowNull()]$BridgeSmoke = $null
    )

    if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties['objective_authority_reset'] -and $IntegrationStatus.objective_authority_reset) {
        $authorityReset = $IntegrationStatus.objective_authority_reset
        if ([bool]$authorityReset.active -and $authorityReset.PSObject.Properties['authoritative_current_objective']) {
            $authorityObjective = Convert-ToObjectiveLabel -ObjectiveId ([string]$authorityReset.authoritative_current_objective)
            if (-not [string]::IsNullOrWhiteSpace($authorityObjective)) {
                return $authorityObjective
            }
        }
    }

    if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties['mim_status'] -and $IntegrationStatus.mim_status -and $IntegrationStatus.mim_status.PSObject.Properties['objective_active']) {
        $mimObjective = Convert-ToObjectiveLabel -ObjectiveId ([string]$IntegrationStatus.mim_status.objective_active)
        if (-not [string]::IsNullOrWhiteSpace($mimObjective)) {
            return $mimObjective
        }
    }

    if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties['mim_handshake'] -and $IntegrationStatus.mim_handshake) {
        $handshake = $IntegrationStatus.mim_handshake
        if ($handshake.PSObject.Properties['current_next_objective']) {
            $nextObjective = Convert-ToObjectiveLabel -ObjectiveId ([string]$handshake.current_next_objective)
            if (-not [string]::IsNullOrWhiteSpace($nextObjective)) {
                return $nextObjective
            }
        }
        if ($handshake.PSObject.Properties['objective_active']) {
            $activeObjective = Convert-ToObjectiveLabel -ObjectiveId ([string]$handshake.objective_active)
            if (-not [string]::IsNullOrWhiteSpace($activeObjective)) {
                return $activeObjective
            }
        }
    }

    if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties['objective_alignment'] -and $IntegrationStatus.objective_alignment -and $IntegrationStatus.objective_alignment.PSObject.Properties['tod_current_objective']) {
        $todObjective = Convert-ToObjectiveLabel -ObjectiveId ([string]$IntegrationStatus.objective_alignment.tod_current_objective)
        if (-not [string]::IsNullOrWhiteSpace($todObjective)) {
            return $todObjective
        }
    }

    if ($BridgeSmoke -and $BridgeSmoke.PSObject.Properties['canonical_request'] -and $BridgeSmoke.canonical_request -and $BridgeSmoke.canonical_request.PSObject.Properties['expected_objective_id']) {
        $expectedObjective = Convert-ToObjectiveLabel -ObjectiveId ([string]$BridgeSmoke.canonical_request.expected_objective_id)
        if (-not [string]::IsNullOrWhiteSpace($expectedObjective)) {
            return $expectedObjective
        }
    }

    return ''
}

function New-CanonicalRepublishTaskRequest {
    param(
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [string]$TaskId = '',
        [string]$CorrelationId = ''
    )

    $objectiveLabel = Convert-ToObjectiveLabel -ObjectiveId $ObjectiveId
    if ([string]::IsNullOrWhiteSpace($objectiveLabel)) {
        throw 'canonical_objective_missing'
    }

    $normalizedObjective = Normalize-ObjectiveIdentity -Value $objectiveLabel
    $sequence = [int64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $resolvedTaskId = ([string]$TaskId).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTaskId)) {
        $resolvedTaskId = ('objective-{0}-task-{1}' -f $normalizedObjective, $sequence)
    }
    $resolvedCorrelationId = ([string]$CorrelationId).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedCorrelationId)) {
        $resolvedCorrelationId = $resolvedTaskId
    }
    $generatedAt = (Get-Date).ToUniversalTime().ToString('o')

    return [pscustomobject]@{
        generated_at = $generatedAt
        emitted_at = $generatedAt
        request_id = $resolvedTaskId
        task_id = $resolvedTaskId
        objective_id = $objectiveLabel
        correlation_id = $resolvedCorrelationId
        sequence = $sequence
        source_service = 'tod_watchdog_autorepair'
        canonical_lane_source = 'shared_truth'
        source_instance_id = $env:COMPUTERNAME
    }
}

function Invoke-PublicationSurfaceSelfHeal {
    param(
        [AllowNull()]$BridgeSmoke = $null,
        [Parameter(Mandatory = $true)][string]$IntegrationStatusPath,
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [Parameter(Mandatory = $true)][string]$LocalRepairPacketPath,
        [string]$RemoteRoot = '/home/testpilot/mim/runtime/shared'
    )

    $integrationStatus = Read-JsonFileIfExists -PathValue $IntegrationStatusPath
    $canonicalObjective = Get-CanonicalObjectiveForSelfHeal -IntegrationStatus $integrationStatus -BridgeSmoke $BridgeSmoke
    if ([string]::IsNullOrWhiteSpace($canonicalObjective)) {
        return [pscustomobject]@{
            attempted = $false
            repaired = $false
            method = 'none'
            canonical_objective = ''
            request_id = ''
            reason = 'canonical_objective_missing'
            remote_host = ''
        }
    }

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        return [pscustomobject]@{
            attempted = $false
            repaired = $false
            method = 'none'
            canonical_objective = $canonicalObjective
            request_id = ''
            reason = 'posh_ssh_not_installed'
            remote_host = ''
        }
    }

    $hostAlias = Get-DotEnvValue -Path $EnvPath -Name 'MIM_SSH_HOST'
    if ([string]::IsNullOrWhiteSpace($hostAlias)) { $hostAlias = 'mim' }
    $userName = Get-DotEnvValue -Path $EnvPath -Name 'MIM_SSH_USER'
    if ([string]::IsNullOrWhiteSpace($userName)) { $userName = 'testpilot' }
    $portText = Get-DotEnvValue -Path $EnvPath -Name 'MIM_SSH_PORT'
    $password = Get-DotEnvValue -Path $EnvPath -Name 'MIM_SSH_PASSWORD'
    if ([string]::IsNullOrWhiteSpace($password) -or $password -eq 'CHANGE_ME') {
        return [pscustomobject]@{
            attempted = $false
            repaired = $false
            method = 'none'
            canonical_objective = $canonicalObjective
            request_id = ''
            reason = 'ssh_password_not_set'
            remote_host = $hostAlias
        }
    }

    $port = 22
    $parsedPort = 0
    if ([int]::TryParse([string]$portText, [ref]$parsedPort) -and $parsedPort -gt 0) {
        $port = $parsedPort
    }

    $normalizedObjective = Normalize-ObjectiveIdentity -Value $canonicalObjective
    $canonicalTaskId = Get-CanonicalTaskIdForSelfHeal -ObjectiveId $canonicalObjective -BridgeSmoke $BridgeSmoke
    $requestPayload = New-CanonicalRepublishTaskRequest -ObjectiveId $canonicalObjective -TaskId $canonicalTaskId -CorrelationId $(if (-not [string]::IsNullOrWhiteSpace($canonicalTaskId)) { $canonicalTaskId } else { 'watchdog-publication-surface-self-heal' })
    $requestId = [string]$requestPayload.request_id
    $remoteRequestPath = ((Join-Path $RemoteRoot 'MIM_TOD_TASK_REQUEST.latest.json') -replace '[\\/]+', '/')

    try {
        Import-Module Posh-SSH -ErrorAction Stop | Out-Null
        $resolvedHost = Resolve-SshHostAlias -RemoteHost $hostAlias
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)
        $session = New-SSHSession -ComputerName $resolvedHost -Port $port -Credential $credential -AcceptKey -ConnectionTimeout 15000
        $sftpSession = New-SFTPSession -ComputerName $resolvedHost -Port $port -Credential $credential -AcceptKey -ConnectionTimeout 15000

        try {
            $remoteCommand = @"
bash -lc 'if [ -x /home/testpilot/mim/scripts/continuous_task_dispatch.sh ]; then cd /home/testpilot/mim && ALLOW_LOCAL_ONLY_CANONICAL_WRITE=1 OBJECTIVE_ID=$normalizedObjective COUNT=1 ./scripts/continuous_task_dispatch.sh; printf "\\n__TOD_EXIT__0\\n"; else printf "\\n__TOD_EXIT__127\\n"; fi'
"@
            $commandResult = Invoke-SSHCommand -SessionId ([int]$session.SessionId) -Command $remoteCommand -TimeOut 120
            $commandOutput = [string]($commandResult.Output | Out-String)
            if ($commandOutput -match '__TOD_EXIT__0') {
                $verifyCommand = @"
bash -lc 'cat "$remoteRequestPath" 2>/dev/null || true'
"@
                $verifyResult = Invoke-SSHCommand -SessionId ([int]$session.SessionId) -Command $verifyCommand -TimeOut 30
                $verifyOutput = [string]($verifyResult.Output | Out-String)
                $remoteRequest = $null
                if (-not [string]::IsNullOrWhiteSpace($verifyOutput)) {
                    try {
                        $remoteRequest = ($verifyOutput | ConvertFrom-Json)
                    }
                    catch {
                        $remoteRequest = $null
                    }
                }

                $remoteObjective = if ($null -ne $remoteRequest -and $remoteRequest.PSObject.Properties['objective_id']) {
                    Convert-ToObjectiveLabel -ObjectiveId ([string]$remoteRequest.objective_id)
                }
                else {
                    ''
                }
                $remoteTaskId = if ($null -ne $remoteRequest -and $remoteRequest.PSObject.Properties['task_id']) {
                    [string]$remoteRequest.task_id
                }
                elseif ($null -ne $remoteRequest -and $remoteRequest.PSObject.Properties['request_id']) {
                    [string]$remoteRequest.request_id
                }
                else {
                    ''
                }

                if ([string]::Equals($remoteObjective, $canonicalObjective, [System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($remoteTaskId, $requestId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return [pscustomobject]@{
                        attempted = $true
                        repaired = $true
                        method = 'remote_dispatch_script'
                        canonical_objective = $canonicalObjective
                        request_id = $remoteTaskId
                        reason = 'ok'
                        remote_host = $resolvedHost
                    }
                }
            }

            $packetDir = Split-Path -Parent $LocalRepairPacketPath
            if (-not (Test-Path -Path $packetDir)) {
                New-Item -ItemType Directory -Path $packetDir -Force | Out-Null
            }
            Write-JsonFile -PathValue $LocalRepairPacketPath -Payload $requestPayload
            Set-SFTPItem -SessionId ([int]$sftpSession.SessionId) -Path $LocalRepairPacketPath -Destination $RemoteRoot -Force -ErrorAction Stop | Out-Null

            return [pscustomobject]@{
                attempted = $true
                repaired = $true
                method = 'sftp_direct_request_republish'
                canonical_objective = $canonicalObjective
                request_id = $requestId
                reason = 'ok'
                remote_host = $resolvedHost
            }
        }
        finally {
            if ($null -ne $sftpSession) {
                Remove-SFTPSession -SessionId ([int]$sftpSession.SessionId) | Out-Null
            }
            Remove-SSHSession -SessionId ([int]$session.SessionId) | Out-Null
        }
    }
    catch {
        return [pscustomobject]@{
            attempted = $true
            repaired = $false
            method = 'failed'
            canonical_objective = $canonicalObjective
            request_id = $requestId
            reason = [string]$_.Exception.Message
            remote_host = $hostAlias
        }
    }
}

$envAbs = Get-LocalPath -PathValue $EnvFile
$listenerAbs = Get-LocalPath -PathValue $ListenerScriptPath
$listenerStartupAbs = Get-LocalPath -PathValue $ListenerStartupScriptPath
$bridgeSmokeAbs = Get-LocalPath -PathValue $BridgeSmokeScriptPath
$sharedStateSyncAbs = Get-LocalPath -PathValue $SharedStateSyncScriptPath
$dialogScriptAbs = Get-LocalPath -PathValue $DialogScriptPath
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
$bridgeSmokeOutputPath = Join-Path $sharedAbs "TOD_MIM_BRIDGE_SMOKE.latest.json"
$integrationStatusPath = Join-Path $sharedAbs "integration_status.json"
$alertPacketPath = Join-Path $stageAbs "TOD_MIM_RECOVERY_ALERT.latest.json"
$coordinationRequestPath = Join-Path $stageAbs "TOD_MIM_COORDINATION_REQUEST.latest.json"
$emergencyRequestPath = Join-Path $stageAbs "TOD_MIM_EMERGENCY_REQUEST.latest.json"
$publicationRepairPacketPath = Join-Path $sharedAbs "watchdog-repair/MIM_TOD_TASK_REQUEST.latest.json"
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
    $lastDialogSessionId = ""
    $lastCoordinationRequestId = ""
    $lastIssueStartedAt = ""
    $lastEmergencyRequestId = ""
    $lastEmergencyPublishedAt = ""
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
        if ($previousState.PSObject.Properties["last_dialog_session_id"]) {
            $lastDialogSessionId = [string]$previousState.last_dialog_session_id
        }
        if ($previousState.PSObject.Properties["last_coordination_request_id"]) {
            $lastCoordinationRequestId = [string]$previousState.last_coordination_request_id
        }
        if ($previousState.PSObject.Properties["last_issue_started_at"]) {
            $lastIssueStartedAt = [string]$previousState.last_issue_started_at
        }
        if ($previousState.PSObject.Properties["last_emergency_request_id"]) {
            $lastEmergencyRequestId = [string]$previousState.last_emergency_request_id
        }
        if ($previousState.PSObject.Properties["last_emergency_published_at"]) {
            $lastEmergencyPublishedAt = [string]$previousState.last_emergency_published_at
        }
    }

    $listenerRunning = Test-ListenerRunning -ListenerScriptAbs $listenerAbs -ListenerStartupScriptAbs $listenerStartupAbs
    $uiHealthy = Test-UiHealthy -Port $UiPort

    $request = Read-JsonFileIfExists -PathValue $requestPath
    $listenerState = Read-JsonFileIfExists -PathValue $statePath
    $journal = Read-JsonFileIfExists -PathValue $journalPath
    $bridgeSmoke = Invoke-BridgeSmokeCheck -ScriptAbs $bridgeSmokeAbs -StageDirValue $StageDir -IntegrationStatusPathValue $integrationStatusPath -OutputPathValue $bridgeSmokeOutputPath
    $bridgeFailureModes = @()
    if ($bridgeSmoke -and $bridgeSmoke.PSObject.Properties['failure_modes'] -and $null -ne $bridgeSmoke.failure_modes) {
        $bridgeFailureModes = @($bridgeSmoke.failure_modes | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $requestId = ""
    if ($request -and $request.PSObject.Properties["task_id"]) {
        $requestId = [string]$request.task_id
    }
    elseif ($request -and $request.PSObject.Properties["request_id"]) {
        $requestId = [string]$request.request_id
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
    $listenerLastResultStatus = if ($listenerState -and $listenerState.PSObject.Properties['last_result_status']) { ([string]$listenerState.last_result_status).Trim().ToLowerInvariant() } else { '' }
    $localTerminalRequestFinished =
        (-not $hasPendingRequest) -and
        (-not [string]::IsNullOrWhiteSpace($requestId)) -and
        (-not [string]::IsNullOrWhiteSpace($lastProcessedId)) -and
        [string]::Equals($requestId, $lastProcessedId, [System.StringComparison]::OrdinalIgnoreCase) -and (
            @('completed', 'already_processed', 'succeeded', 'failed') -contains $lastJournalStatus -or
            @('completed', 'succeeded', 'failed') -contains $listenerLastResultStatus
        )
    $localTerminalRequestFailed =
        $localTerminalRequestFinished -and (
            @('failed') -contains $lastJournalStatus -or
            @('failed') -contains $listenerLastResultStatus
        )

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
    elseif ($localTerminalRequestFinished) {
        $progressClassification = "no_progress_but_heartbeats_present"
        $taskState = if ($localTerminalRequestFailed) { "failed" } else { "completed" }
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
    elseif ((-not [bool]$bridgeSmoke.passed) -and (@($bridgeFailureModes) -contains "remote_publish_not_verified")) {
        $issueCode = "bridge_remote_publish_unverified"
        $issueDetail = "Listener-stage artifacts are current, but remote publish verification failed."
    }
    elseif ((-not [bool]$bridgeSmoke.passed) -and (@($bridgeFailureModes) -contains "objective_alignment_not_in_sync")) {
        $issueCode = "bridge_objective_misaligned"
        $issueDetail = "Live objective alignment is not in sync across TOD and MIM."
    }
    elseif (Test-PublicationSurfaceRecoveryNeeded -BridgeSmoke $bridgeSmoke -BridgeFailureModes @($bridgeFailureModes) -LocalTerminalRequestFinished:$localTerminalRequestFinished) {
        $issueCode = "publication_surface_divergence"
        $issueDetail = "Remote canonical request surface diverges from the expected live publication boundary."
    }
    elseif ((-not [bool]$bridgeSmoke.passed) -and (@($bridgeFailureModes) -contains "listener_contract_stalled")) {
        $issueCode = "listener_stalled_pending_request"
        $issueDetail = "Bridge smoke detected stale local listener/ACK/result mutation."
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
        $operatorGuidance = @(Get-RecoveryGuidance -IssueCode $issueCode -BridgeFailureModes $bridgeFailureModes)

        $recoveryAction = "restart_listener"
        $publicationRepairResult = $null
        if ($issueCode -eq "bridge_remote_publish_unverified" -or $issueCode -eq "bridge_objective_misaligned") {
            $recoveryAction = "refresh_shared_state_sync"
            if (Test-Path -Path $sharedStateSyncAbs) {
                try {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sharedStateSyncAbs -RefreshMimContextFromSsh -PublishTodStatusToMimArm | Out-Null
                }
                catch {
                }
            }
        }
        elseif ($issueCode -eq "publication_surface_divergence") {
            $recoveryAction = "republish_authoritative_request"
            $publicationRepairResult = Invoke-PublicationSurfaceSelfHeal -BridgeSmoke $bridgeSmoke -IntegrationStatusPath $integrationStatusPath -EnvPath $envAbs -LocalRepairPacketPath $publicationRepairPacketPath
            if ([bool]$publicationRepairResult.repaired -and (Test-Path -Path $sharedStateSyncAbs)) {
                try {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sharedStateSyncAbs -RefreshMimContextFromSsh -PublishTodStatusToMimArm | Out-Null
                }
                catch {
                }
            }
            elseif (-not [bool]$publicationRepairResult.attempted) {
                $recoveryAction = "observe_publication_boundary"
            }
        }
        else {
            Stop-ScriptProcesses -ScriptAbs @($listenerAbs, $listenerStartupAbs)
            Start-BackgroundScript -ScriptAbs $listenerAbs -ScriptArgs @("-PollSeconds", "2")
        }

        if ($issueCode -eq "ui_unhealthy" -or ($RestartUiOnFailure -and -not $uiHealthy)) {
            $recoveryAction = "restart_listener_and_ui"
            Stop-ScriptProcesses -ScriptAbs $uiAbs
            Start-BackgroundScript -ScriptAbs $uiAbs -ScriptArgs @("-Port", [string]$UiPort, "-NoAutoOpen")
        }

        Start-Sleep -Seconds 4
        $listenerRecovered = Test-ListenerRunning -ListenerScriptAbs $listenerAbs -ListenerStartupScriptAbs $listenerStartupAbs
        $uiRecovered = Test-UiHealthy -Port $UiPort
        $bridgeSmokeAfter = Invoke-BridgeSmokeCheck -ScriptAbs $bridgeSmokeAbs -StageDirValue $StageDir -IntegrationStatusPathValue $integrationStatusPath -OutputPathValue $bridgeSmokeOutputPath
        $recoveryOk = ($listenerRecovered -and $uiRecovered -and [bool]$bridgeSmokeAfter.passed)
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
            operator_guidance = @($operatorGuidance)
            bridge_failure_modes = @($bridgeFailureModes)
            requested_actions = @(
                "restart_listener",
                "restart_ui_if_needed",
                "run_health_test",
                "resume_processing"
            )
            verification = [pscustomobject]@{
                listener_running = $listenerRecovered
                ui_healthy = $uiRecovered
                bridge_smoke_passed = [bool]$bridgeSmokeAfter.passed
                passed = $recoveryOk
            }
            publication_surface_self_heal = $publicationRepairResult
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
            bridge_smoke = $bridgeSmokeAfter
            bridge_failure_modes = @($bridgeFailureModes)
            operator_guidance = @($operatorGuidance)
            self_heal_order_path = $selfHealOrderPath
            publication_surface_self_heal = $publicationRepairResult
        }

        $alertSignature = Get-AlertSignature -IssueCode $issueCode -IssueDetail $issueDetail -RecoveryAction $recoveryAction -RequestId $requestId -LastProcessedId $lastProcessedId
        $alertPublished = $false
        $alertPublishReason = "cooldown_skipped"
        $coordinationPublished = $false
        $coordinationPublishReason = 'not_attempted'
        $emergencyPublished = $false
        $emergencyPublishReason = 'not_attempted'
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

        if ([string]::Equals([string]$previousState.last_issue, $issueCode, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($lastIssueStartedAt)) {
            $issueStartedAt = $lastIssueStartedAt
        }
        else {
            $issueStartedAt = $nowUtc.ToString('o')
        }
        $issueStartedUtc = Get-DateOrMinValue -Value $issueStartedAt
        $elapsedIssueSeconds = if ($issueStartedUtc -eq [datetime]::MinValue) { 0 } else { [int][math]::Floor((New-TimeSpan -Start $issueStartedUtc -End $nowUtc).TotalSeconds) }

        if ($shouldPublishAlert) {
            $publishResult = Publish-RecoveryAlertToMim -AlertPayload $alertPayload -LocalPacketPath $alertPacketPath -EnvPath $envAbs
            $alertPublished = [bool]$publishResult.uploaded
            $alertPublishReason = [string]$publishResult.reason
            if ($alertPublished) {
                $lastAlertSignature = $alertSignature
                $lastAlertPublishedAt = $nowUtc.ToString("o")
            }

            if ($issueCode -eq 'publication_surface_divergence') {
                $coordinationRequest = New-PublicationSurfaceCoordinationRequest -IssueCode $issueCode -IssueDetail $issueDetail -AlertSignature $alertSignature -RequestId $requestId -BridgeFailureModes @($bridgeFailureModes) -BridgeSmoke $bridgeSmoke
                $coordinationPublishResult = Publish-CoordinationRequestToMim -CoordinationRequest $coordinationRequest -LocalPacketPath $coordinationRequestPath -EnvPath $envAbs
                $coordinationPublished = [bool]$coordinationPublishResult.uploaded
                $coordinationPublishReason = [string]$coordinationPublishResult.reason
                if ($coordinationPublished) {
                    $lastCoordinationRequestId = [string]$coordinationRequest.request_id
                }
            }
        }

        if ($issueCode -eq 'publication_surface_divergence' -and $elapsedIssueSeconds -ge 120) {
            $lastEmergencyPublishUtc = Get-DateOrMinValue -Value $lastEmergencyPublishedAt
            $secondsSinceEmergencyPublish = if ($lastEmergencyPublishUtc -eq [datetime]::MinValue) { 999999 } else { [int][math]::Floor((New-TimeSpan -Start $lastEmergencyPublishUtc -End $nowUtc).TotalSeconds) }
            if ($secondsSinceEmergencyPublish -ge 120) {
                $emergencyRequest = New-PublicationSurfaceEmergencyRequest -IssueCode $issueCode -IssueDetail $issueDetail -ParentRequestId $requestId -ElapsedIssueSeconds $elapsedIssueSeconds -BridgeSmoke $bridgeSmoke -CoordinationRequestId $lastCoordinationRequestId
                $emergencyPublishResult = Publish-EmergencyRequestToMim -EmergencyRequest $emergencyRequest -LocalPacketPath $emergencyRequestPath -EnvPath $envAbs
                $emergencyPublished = [bool]$emergencyPublishResult.uploaded
                $emergencyPublishReason = [string]$emergencyPublishResult.reason
                if ($emergencyPublished) {
                    $lastEmergencyRequestId = [string]$emergencyRequest.request_id
                    $lastEmergencyPublishedAt = $nowUtc.ToString('o')
                }
            }
            else {
                $emergencyPublishReason = 'cooldown_active'
            }
        }

        $dialogSeed = ''
        if (-not [string]::IsNullOrWhiteSpace($requestId)) {
            $dialogSeed = "tod-watchdog-$requestId"
        }
        elseif (-not [string]::IsNullOrWhiteSpace($lastProcessedId)) {
            $dialogSeed = "tod-watchdog-$lastProcessedId"
        }
        else {
            $dialogSeed = "tod-watchdog-$issueCode"
        }
        $dialogSessionId = Get-SafeDialogSessionId -Seed $dialogSeed
        $dialogNoticeResult = $null
        if ($shouldPublishAlert) {
            $dialogPayload = [pscustomobject]@{
                source = $watchdogId
                issue_code = $issueCode
                issue_detail = $issueDetail
                recovery_action = $recoveryAction
                recovery_ok = $recoveryOk
                request_id = $requestId
                last_processed_request_id = $lastProcessedId
                heartbeat_age_seconds = $heartbeatAgeSeconds
                stall_threshold_seconds = $stallThresholdSeconds
                bridge_failure_modes = @($bridgeFailureModes)
                operator_guidance = @($operatorGuidance)
                ui_port = $UiPort
            }
            $dialogNoticeResult = Invoke-DialogNotice -ScriptAbs $dialogScriptAbs -Action 'send' -SessionId $dialogSessionId -MessageType 'blocker_notice' -Intent 'watchdog_issue_detected' -Summary ("Watchdog detected {0}: {1}" -f $issueCode, $issueDetail) -Payload $dialogPayload -TaskId $requestId -CorrelationId $alertSignature -EnvPath $envAbs -PublishRemote:$PublishDialogRemote
            if ($dialogNoticeResult.ok) {
                $lastDialogSessionId = $dialogSessionId
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
            dialog_status = if ($null -ne $dialogNoticeResult) { [string]$dialogNoticeResult.status } else { "not_attempted" }
            coordination_request_id = $lastCoordinationRequestId
            coordination_publish_uploaded = $coordinationPublished
            coordination_publish_reason = $coordinationPublishReason
            emergency_request_id = $lastEmergencyRequestId
            emergency_publish_uploaded = $emergencyPublished
            emergency_publish_reason = $emergencyPublishReason
            bridge_smoke_passed = [bool]$bridgeSmokeAfter.passed
            bridge_failure_modes = @($bridgeFailureModes)
            request_id = $requestId
            last_processed_request_id = $lastProcessedId
            publication_surface_self_heal = $publicationRepairResult
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
            last_dialog_session_id = $lastDialogSessionId
            last_coordination_request_id = $lastCoordinationRequestId
            last_issue_started_at = $issueStartedAt
            last_emergency_request_id = $lastEmergencyRequestId
            last_emergency_published_at = $lastEmergencyPublishedAt
            listener_running = $listenerRecovered
            ui_healthy = $uiRecovered
            bridge_smoke = $bridgeSmokeAfter
            operator_guidance = @($operatorGuidance)
            request_id = $requestId
            last_processed_request_id = $lastProcessedId
            publication_surface_self_heal = $publicationRepairResult
        }
        Write-JsonFile -PathValue $watchdogStatePath -Payload $stateDoc

        Write-Warning ("[TOD-WATCHDOG] issue={0} action={1} recovered={2}" -f $issueCode, $recoveryAction, [string]$recoveryOk)
    }
    else {
        $consecutiveFreezes = 0
        if ($previousState -and $previousState.PSObject.Properties['last_issue'] -and -not [string]::IsNullOrWhiteSpace([string]$previousState.last_issue)) {
            $resolutionSessionId = ''
            if (-not [string]::IsNullOrWhiteSpace($lastDialogSessionId)) {
                $resolutionSessionId = $lastDialogSessionId
            }
            elseif (-not [string]::IsNullOrWhiteSpace($requestId)) {
                $resolutionSessionId = Get-SafeDialogSessionId -Seed ("tod-watchdog-$requestId")
            }
            else {
                $resolutionSessionId = Get-SafeDialogSessionId -Seed ("tod-watchdog-{0}" -f [string]$previousState.last_issue)
            }
            $resolutionPayload = [pscustomobject]@{
                source = $watchdogId
                cleared_issue = [string]$previousState.last_issue
                cleared_issue_detail = if ($previousState.PSObject.Properties['last_issue_detail']) { [string]$previousState.last_issue_detail } else { '' }
                request_id = $requestId
                last_processed_request_id = $lastProcessedId
                listener_running = $listenerRunning
                ui_healthy = $uiHealthy
                bridge_smoke_passed = [bool]$bridgeSmoke.passed
            }
            $null = Invoke-DialogNotice -ScriptAbs $dialogScriptAbs -Action 'close-session' -SessionId $resolutionSessionId -MessageType 'resolution_notice' -Intent 'watchdog_issue_cleared' -Summary ("Watchdog cleared {0}; listener, UI, and bridge checks are healthy again." -f [string]$previousState.last_issue) -Payload $resolutionPayload -TaskId $requestId -CorrelationId $lastAlertSignature -EnvPath $envAbs -PublishRemote:$PublishDialogRemote
            $lastDialogSessionId = ''

            if ([string]::Equals([string]$previousState.last_issue, 'publication_surface_divergence', [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($lastCoordinationRequestId)) {
                $resolvedObjectiveId = ''
                if ($bridgeSmoke -and $bridgeSmoke.PSObject.Properties['canonical_request'] -and $bridgeSmoke.canonical_request -and $bridgeSmoke.canonical_request.PSObject.Properties['expected_objective_id']) {
                    $resolvedObjectiveId = [string]$bridgeSmoke.canonical_request.expected_objective_id
                }
                $null = Publish-ResolvedCoordinationToMim -RequestId $lastCoordinationRequestId -IssueCode 'publication_surface_divergence' -LocalPacketPath $coordinationRequestPath -EnvPath $envAbs -ObjectiveId $resolvedObjectiveId -ResolutionReason 'Watchdog now sees listener, UI, and bridge health restored with no publication-surface divergence.'
                $lastCoordinationRequestId = ''
                if (-not [string]::IsNullOrWhiteSpace($lastEmergencyRequestId)) {
                    $null = Publish-ResolvedEmergencyToMim -RequestId $lastEmergencyRequestId -IssueCode 'publication_surface_divergence' -LocalPacketPath $emergencyRequestPath -EnvPath $envAbs -ObjectiveId $resolvedObjectiveId -ResolutionReason 'Watchdog no longer sees publication-surface divergence, so the emergency lane can stand down.'
                    $lastEmergencyRequestId = ''
                    $lastEmergencyPublishedAt = ''
                }
            }
        }

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
            last_dialog_session_id = $lastDialogSessionId
            last_coordination_request_id = $lastCoordinationRequestId
            last_issue_started_at = ''
            last_emergency_request_id = $lastEmergencyRequestId
            last_emergency_published_at = $lastEmergencyPublishedAt
            listener_running = $listenerRunning
            ui_healthy = $uiHealthy
            bridge_smoke = $bridgeSmoke
            operator_guidance = @()
            request_id = $requestId
            last_processed_request_id = $lastProcessedId
        }
        Write-JsonFile -PathValue $watchdogStatePath -Payload $stateDoc
    }

    if ($RunOnce) { break }
    Start-Sleep -Seconds $CheckEverySeconds
}

Write-Host "[TOD-WATCHDOG] Stopped."
