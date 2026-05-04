param(
    [int]$Port = 8844,
    [switch]$AllowPortFallback,
    [string]$CloudflaredPath = '',
    [string]$CloudflaredDownloadUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe',
    [string]$OutputRoot = '',
    [int]$UiStartupTimeoutSeconds = 120,
    [int]$TunnelStartupTimeoutSeconds = 90,
    [int]$RemoteProbeGraceSeconds = 60,
    [int]$RemoteProbePollSeconds = 5,
    [int]$ProbeTimeoutSeconds = 10,
    [int]$HealthIntervalSeconds = 30,
    [switch]$NoWait,
    [switch]$NoInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot 'tod/config/mim-remote-access-shell.json'
$uiScriptPath = Join-Path $PSScriptRoot 'Start-TOD-UI.ps1'
$uiStartupDiagnosticPath = Join-Path $repoRoot 'tod/out/tod-ui-startup.latest.json'
$uiIndexPath = Join-Path $repoRoot 'ui/index.html'
$defaultOutputRoot = Join-Path $repoRoot 'tod/out/remote-access/mim-shell'
$defaultCloudflaredPath = Join-Path $repoRoot 'tools/cloudflared/cloudflared.exe'

function Ensure-Directory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Directory path cannot be empty.'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return ($raw | ConvertFrom-Json)
}

function Write-JsonFile {
    param(
        [string]$Path,
        [Parameter(ValueFromPipeline = $true)]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Value
    )

    [System.IO.File]::WriteAllText($Path, $Value, [System.Text.UTF8Encoding]::new($false))
}

function Resolve-OutputRoot {
    $configuredRoot = $null
    $config = Read-JsonFile -Path $configPath
    if ($config -and $config.artifacts_root) {
        $configuredRoot = [string]$config.artifacts_root
    }

    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($configuredRoot)) {
            if ([System.IO.Path]::IsPathRooted($configuredRoot)) {
                return (Ensure-Directory -Path $configuredRoot)
            }

            return (Ensure-Directory -Path (Join-Path $repoRoot $configuredRoot))
        }

        return (Ensure-Directory -Path $defaultOutputRoot)
    }

    if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
        return (Ensure-Directory -Path $OutputRoot)
    }

    return (Ensure-Directory -Path (Join-Path $repoRoot $OutputRoot))
}

function Get-ConfiguredValue {
    param(
        [object]$Config,
        [string[]]$Path,
        $Fallback
    )

    $node = $Config
    foreach ($segment in $Path) {
        if ($null -eq $node) {
            return $Fallback
        }

        $prop = $node.PSObject.Properties[$segment]
        if ($null -eq $prop) {
            return $Fallback
        }

        $node = $prop.Value
    }

    if ($null -eq $node -or ($node -is [string] -and [string]::IsNullOrWhiteSpace([string]$node))) {
        return $Fallback
    }

    return $node
}

function Wait-ProjectStatusProbe {
    param(
        [string]$BaseUrl,
        [int]$ProbeTimeoutSeconds,
        [int]$GraceSeconds,
        [int]$PollSeconds
    )

    $lastProbe = $null
    $deadline = (Get-Date).AddSeconds($GraceSeconds)
    do {
        $lastProbe = Get-ProjectStatusProbe -BaseUrl $BaseUrl -TimeoutSeconds $ProbeTimeoutSeconds
        if ($lastProbe.ok) {
            return $lastProbe
        }

        if ((Get-Date) -ge $deadline) {
            return $lastProbe
        }

        Start-Sleep -Seconds $PollSeconds
    } while ($true)
}

function Wait-MimCommandProbe {
    param(
        [string]$BaseUrl,
        [string]$ObjectiveId,
        [int]$ProbeTimeoutSeconds,
        [int]$GraceSeconds,
        [int]$PollSeconds
    )

    $lastProbe = $null
    $deadline = (Get-Date).AddSeconds($GraceSeconds)
    do {
        $lastProbe = Invoke-MimCommandProbe -BaseUrl $BaseUrl -ObjectiveId $ObjectiveId -TimeoutSeconds $ProbeTimeoutSeconds
        if ($lastProbe.ok) {
            return $lastProbe
        }

        if ((Get-Date) -ge $deadline) {
            return $lastProbe
        }

        Start-Sleep -Seconds $PollSeconds
    } while ($true)
}

function New-FailedStatusProbe {
    param(
        [string]$BaseUrl,
        [string]$ErrorMessage
    )

    return [pscustomobject]@{
        ok = $false
        base_url = $BaseUrl
        selected_objective_id = ''
        overall_health = ''
        communication = ''
        marker = ''
        raw = $null
        error = $ErrorMessage
    }
}

function New-FailedInteractionProbe {
    param(
        [string]$BaseUrl,
        [string]$ErrorMessage
    )

    return [pscustomobject]@{
        ok = $false
        base_url = $BaseUrl

        session_id = ''
        summary = ''
        error = $ErrorMessage
    }
}

function New-FailedDriveAccessProbe {
    param(
        [string]$BaseUrl,
        [string]$RequestedPath,
        [string]$ErrorMessage
    )

    return [pscustomobject]@{
        ok = $false
        base_url = $BaseUrl
        requested_path = $RequestedPath
        entry_count = 0
        error = $ErrorMessage
    }
}

function Resolve-CloudflaredPath {
    param(
        [string]$ExplicitPath,
        [string]$DownloadUrl,
        [switch]$SkipInstall
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) {
            throw ("cloudflared not found at {0}" -f $ExplicitPath)
        }

        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $command = Get-Command -Name cloudflared -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    if (Test-Path -LiteralPath $defaultCloudflaredPath) {
        return (Resolve-Path -LiteralPath $defaultCloudflaredPath).Path
    }

    if ($SkipInstall) {
        throw 'cloudflared is not installed and -NoInstall was specified.'
    }

    $installRoot = Split-Path -Parent $defaultCloudflaredPath
    Ensure-Directory -Path $installRoot | Out-Null
    $downloadTarget = Join-Path $installRoot 'cloudflared.download.exe'
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadTarget -UseBasicParsing
    Move-Item -LiteralPath $downloadTarget -Destination $defaultCloudflaredPath -Force
    return (Resolve-Path -LiteralPath $defaultCloudflaredPath).Path
}

function Find-CloudflareTunnelUrl {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $match = [regex]::Match($Text, 'https://[a-z0-9-]+\.trycloudflare\.com', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return $match.Value
    }

    return $null
}

function Get-MobileReadinessEvidence {
    param([string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    return [pscustomobject]@{
        viewport_meta = [bool]([regex]::IsMatch($raw, '<meta\s+name="viewport"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
        responsive_breakpoints = [bool]([regex]::IsMatch($raw, '@media\s*\(', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
        mim_command_panel = [bool]([regex]::IsMatch($raw, '/api/tod-conversation', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
    }
}

function Get-ProjectStatusProbe {
    param(
        [string]$BaseUrl,
        [int]$TimeoutSeconds
    )

    try {
        $data = Invoke-RestMethod -Uri (($BaseUrl.TrimEnd('/')) + '/api/project-status') -TimeoutSec $TimeoutSeconds
        $steadyState = $data.PSObject.Properties['steady_state']
        $communicationHealth = $data.PSObject.Properties['communication_health']
        $communication = $data.PSObject.Properties['communication']
        $markerProperty = $data.PSObject.Properties['marker']
        $markerValue = if ($markerProperty) { $markerProperty.Value } else { $null }
        return [pscustomobject]@{
            ok = $true
            base_url = $BaseUrl
            selected_objective_id = [string]$data.selected_objective_id
            overall_health = if ($steadyState -and $steadyState.Value) { [string]$steadyState.Value.status } else { '' }
            communication = if ($communicationHealth -and $communicationHealth.Value) { [string]$communicationHealth.Value.status } elseif ($communication -and $communication.Value) { [string]$communication.Value.status } else { '' }
            marker = if ($markerValue) {
                if ($markerValue.PSObject.Properties['label']) {
                    [string]$markerValue.label
                } elseif ($markerValue.PSObject.Properties['title']) {
                    [string]$markerValue.title
                } elseif ($markerValue.PSObject.Properties['objective_id']) {
                    [string]$markerValue.objective_id
                } else {
                    ''
                }
            } else { '' }
            raw = $data
        }
    } catch {
        return [pscustomobject]@{
            ok = $false
            base_url = $BaseUrl
            error = [string]$_.Exception.Message
        }
    }
}

function Invoke-MimCommandProbe {
    param(
        [string]$BaseUrl,
        [string]$ObjectiveId,
        [int]$TimeoutSeconds
    )

    $body = @{
        query = 'Summarize the current operating state for remote access validation.'
        objective_id = [string]$ObjectiveId
        operator_name = 'MIM Remote Access Validation'
        conversation_history = @()
        window_minutes = 10
    } | ConvertTo-Json -Depth 8

    try {
        $data = Invoke-RestMethod -Uri (($BaseUrl.TrimEnd('/')) + '/api/tod-conversation') -Method Post -ContentType 'application/json' -Body $body -TimeoutSec $TimeoutSeconds
        $summary = if ($data.PSObject.Properties['reply_text']) { [string]$data.reply_text } else { '' }
        return [pscustomobject]@{
            ok = [bool]$data.ok
            base_url = $BaseUrl
            session_id = if ($data.PSObject.Properties['conversation_id']) { [string]$data.conversation_id } else { '' }
            summary = $summary
            error = ''
        }
    } catch {
        return [pscustomobject]@{
            ok = $false
            base_url = $BaseUrl
            session_id = ''
            summary = ''
            error = [string]$_.Exception.Message
        }
    }
}

function Invoke-DriveAccessProbe {
    param(
        [string]$BaseUrl,
        [string]$RequestedPath,
        [int]$TimeoutSeconds
    )

    try {
        $encodedPath = [uri]::EscapeDataString($RequestedPath)
        $data = Invoke-RestMethod -Uri (($BaseUrl.TrimEnd('/')) + '/api/drive-access-list?path=' + $encodedPath) -TimeoutSec $TimeoutSeconds
        return [pscustomobject]@{
            ok = [bool]$data.ok
            base_url = $BaseUrl
            requested_path = if ($data.PSObject.Properties['requested_path']) { [string]$data.requested_path } else { $RequestedPath }
            entry_count = @($data.entries).Count
            error = ''
        }
    } catch {
        return [pscustomobject]@{
            ok = $false
            base_url = $BaseUrl
            requested_path = $RequestedPath
            entry_count = 0
            error = [string]$_.Exception.Message
        }
    }
}

function Stop-TrackedProcess {
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) {
        return
    }

    try {
        if (-not $Process.HasExited) {
            $taskKill = Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID', $Process.Id.ToString(), '/T', '/F') -WindowStyle Hidden -Wait -PassThru -ErrorAction SilentlyContinue
            if ($taskKill -and $taskKill.ExitCode -eq 0) {
                return
            }

            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {
    }
}

function Find-TodUiAdvertiseUrl {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $match = [regex]::Match($Text, 'http://localhost:\d+/', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return $match.Value.TrimEnd('/')
    }

    return $null
}

function Start-TodUiChild {
    param(
        [int]$RequestedPort,
        [switch]$FallbackAllowed,
        [int]$TimeoutSeconds,
        [string]$StdOutPath,
        [string]$StdErrPath
    )

    $argumentList = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $uiScriptPath,
        '-LocalOnly',
        '-NoAutoOpen',
        '-Port',
        $RequestedPort.ToString()
    )
    if ($FallbackAllowed) {
        $argumentList += '-AllowPortFallback'
    }

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath -WindowStyle Hidden -PassThru
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $stdout = if (Test-Path -LiteralPath $StdOutPath) { Get-Content -LiteralPath $StdOutPath -Raw -ErrorAction SilentlyContinue } else { '' }
        $advertiseUrl = Find-TodUiAdvertiseUrl -Text $stdout
        if (-not [string]::IsNullOrWhiteSpace($advertiseUrl)) {
            $probe = Get-ProjectStatusProbe -BaseUrl $advertiseUrl -TimeoutSeconds 5
            if ($probe.ok) {
                return [pscustomobject]@{
                    process = $process
                    advertise_url = $advertiseUrl
                    port = [int]([uri]$advertiseUrl).Port
                    diagnostic = $null
                }
            }
        }
        Start-Sleep -Milliseconds 500
    }

    Stop-TrackedProcess -Process $process
    throw 'Timed out waiting for the local-only TOD UI to start.'
}

function Start-CloudflareQuickTunnel {
    param(
        [string]$ExecutablePath,
        [string]$LocalUrl,
        [string]$HomeRoot,
        [int]$TimeoutSeconds,
        [string]$StdOutPath,
        [string]$StdErrPath
    )

    $isolatedProfile = Ensure-Directory -Path $HomeRoot
    $quotedExe = $ExecutablePath.Replace("'", "''")
    $quotedUrl = $LocalUrl.Replace("'", "''")
    $quotedProfile = $isolatedProfile.Replace("'", "''")
    $command = @(
        "`$env:USERPROFILE = '$quotedProfile'",
        "`$env:HOME = '$quotedProfile'",
        "& '$quotedExe' tunnel --url '$quotedUrl' --no-autoupdate"
    ) -join '; '

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command) -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath -WindowStyle Hidden -PassThru
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $stdout = if (Test-Path -LiteralPath $StdOutPath) { Get-Content -LiteralPath $StdOutPath -Raw -ErrorAction SilentlyContinue } else { '' }
        $stderr = if (Test-Path -LiteralPath $StdErrPath) { Get-Content -LiteralPath $StdErrPath -Raw -ErrorAction SilentlyContinue } else { '' }
        $publicUrl = Find-CloudflareTunnelUrl -Text ($stdout + [Environment]::NewLine + $stderr)
        if (-not [string]::IsNullOrWhiteSpace($publicUrl)) {
            return [pscustomobject]@{
                process = $process
                public_url = $publicUrl
            }
        }
        Start-Sleep -Milliseconds 500
    }

    Stop-TrackedProcess -Process $process
    throw 'Timed out waiting for cloudflared to publish a TryCloudflare URL.'
}

function New-RemoteAccessReport {
    param(
        [string]$Status,
        [string]$Message,
        [string]$LocalUrl,
        [string]$PublicUrl,
        [string]$CloudflaredExe,
        [System.Diagnostics.Process]$UiProcess,
        [System.Diagnostics.Process]$TunnelProcess,
        $LocalStatus,
        $LocalInteraction,
        $LocalDriveAccess,
        $RemoteStatus,
        $RemoteInteraction,
        $RemoteDriveAccess,
        $MobileEvidence,
        [string]$StdOutLog,
        [string]$StdErrLog,
        [string]$UiStdOutLog,
        [string]$UiStdErrLog
    )

    return [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        status = $Status
        message = $Message
        local_url = $LocalUrl
        public_url = $PublicUrl
        cloudflared_path = $CloudflaredExe
        ui_process_id = if ($UiProcess) { $UiProcess.Id } else { 0 }
        tunnel_process_id = if ($TunnelProcess) { $TunnelProcess.Id } else { 0 }
        local_project_status = $LocalStatus
        local_interaction = $LocalInteraction
        local_drive_access = $LocalDriveAccess
        remote_project_status = $RemoteStatus
        remote_interaction = $RemoteInteraction
        remote_drive_access = $RemoteDriveAccess
        drive_access = [pscustomobject]@{
            roots_url = if ([string]::IsNullOrWhiteSpace($PublicUrl)) { '' } else { ($PublicUrl.TrimEnd('/') + '/api/drive-access-roots') }
            default_root = 'E:\'
        }
        mobile_readiness = $MobileEvidence
        logs = [pscustomobject]@{
            cloudflared_stdout = $StdOutLog
            cloudflared_stderr = $StdErrLog
            ui_stdout = $UiStdOutLog
            ui_stderr = $UiStdErrLog
        }
    }
}

function Write-RemoteAccessArtifacts {
    param(
        $Report,
        [System.Diagnostics.Process]$UiProcess,
        [System.Diagnostics.Process]$TunnelProcess,
        [string]$StatusPath,
        [string]$SummaryPath,
        [string]$PidPath
    )

    $Report | Write-JsonFile -Path $StatusPath
    $summary = @(
        '# TOD MIM Remote Access Shell',
        '',
        ('Status: {0}' -f $Report.status),
        ('Message: {0}' -f $Report.message),
        ('Local URL: {0}' -f $Report.local_url),
        ('Public URL: {0}' -f $Report.public_url),
        ('Local interaction OK: {0}' -f $(if ($Report.local_interaction) { $Report.local_interaction.ok } else { $false })),
        ('Local drive access OK: {0}' -f $(if ($Report.local_drive_access) { $Report.local_drive_access.ok } else { $false })),
        ('Remote interaction OK: {0}' -f $(if ($Report.remote_interaction) { $Report.remote_interaction.ok } else { $false })),
        ('Remote drive access OK: {0}' -f $(if ($Report.remote_drive_access) { $Report.remote_drive_access.ok } else { $false })),
        ('Drive roots URL: {0}' -f $(if ($Report.drive_access) { $Report.drive_access.roots_url } else { '' })),
        ('Mobile viewport present: {0}' -f $Report.mobile_readiness.viewport_meta),
        ('Responsive breakpoints present: {0}' -f $Report.mobile_readiness.responsive_breakpoints),
        ('Generated at: {0}' -f $Report.generated_at)
    ) -join [Environment]::NewLine
    Write-TextFile -Path $SummaryPath -Value ($summary + [Environment]::NewLine)
    ([pscustomobject]@{
        ui_process_id = if ($UiProcess) { $UiProcess.Id } else { 0 }
        tunnel_process_id = if ($TunnelProcess) { $TunnelProcess.Id } else { 0 }
        local_url = $Report.local_url
        public_url = $Report.public_url
        status_path = $StatusPath
        summary_path = $SummaryPath
    }) | Write-JsonFile -Path $PidPath
}

function Restart-TodUiChild {
    param(
        [System.Diagnostics.Process]$ExistingProcess,
        [int]$RequestedPort,
        [switch]$FallbackAllowed,
        [int]$TimeoutSeconds,
        [string]$StdOutPath,
        [string]$StdErrPath
    )

    Stop-TrackedProcess -Process $ExistingProcess
    return Start-TodUiChild -RequestedPort $RequestedPort -FallbackAllowed:$FallbackAllowed -TimeoutSeconds $TimeoutSeconds -StdOutPath $StdOutPath -StdErrPath $StdErrPath
}

function Restart-CloudflareQuickTunnel {
    param(
        [System.Diagnostics.Process]$ExistingProcess,
        [string]$ExecutablePath,
        [string]$LocalUrl,
        [string]$HomeRoot,
        [int]$TimeoutSeconds,
        [string]$StdOutPath,
        [string]$StdErrPath
    )

    Stop-TrackedProcess -Process $ExistingProcess
    return Start-CloudflareQuickTunnel -ExecutablePath $ExecutablePath -LocalUrl $LocalUrl -HomeRoot $HomeRoot -TimeoutSeconds $TimeoutSeconds -StdOutPath $StdOutPath -StdErrPath $StdErrPath
}

$config = Read-JsonFile -Path $configPath
$Port = [int](Get-ConfiguredValue -Config $config -Path @('ui', 'port') -Fallback $Port)
$UiStartupTimeoutSeconds = [int](Get-ConfiguredValue -Config $config -Path @('ui', 'startup_timeout_seconds') -Fallback $UiStartupTimeoutSeconds)
$ProbeTimeoutSeconds = [int](Get-ConfiguredValue -Config $config -Path @('ui', 'probe_timeout_seconds') -Fallback $ProbeTimeoutSeconds)
$HealthIntervalSeconds = [int](Get-ConfiguredValue -Config $config -Path @('health', 'loop_interval_seconds') -Fallback $HealthIntervalSeconds)
$TunnelStartupTimeoutSeconds = [int](Get-ConfiguredValue -Config $config -Path @('tunnel', 'startup_timeout_seconds') -Fallback $TunnelStartupTimeoutSeconds)
$RemoteProbeGraceSeconds = [int](Get-ConfiguredValue -Config $config -Path @('tunnel', 'remote_probe_grace_seconds') -Fallback $RemoteProbeGraceSeconds)
$RemoteProbePollSeconds = [int](Get-ConfiguredValue -Config $config -Path @('tunnel', 'remote_probe_poll_seconds') -Fallback $RemoteProbePollSeconds)
$AllowPortFallback = $AllowPortFallback -or [bool](Get-ConfiguredValue -Config $config -Path @('ui', 'allow_port_fallback') -Fallback $false)
$CloudflaredDownloadUrl = [string](Get-ConfiguredValue -Config $config -Path @('tunnel', 'download_url') -Fallback $CloudflaredDownloadUrl)

$resolvedOutputRoot = Resolve-OutputRoot
$cloudflaredHomeRoot = Ensure-Directory -Path (Join-Path $resolvedOutputRoot 'cloudflared-home')
$logsRoot = Ensure-Directory -Path (Join-Path $resolvedOutputRoot 'logs')
$statusPath = Join-Path $resolvedOutputRoot 'mim-remote-access-shell.latest.json'
$summaryPath = Join-Path $resolvedOutputRoot 'mim-remote-access-shell.latest.md'
$pidPath = Join-Path $resolvedOutputRoot 'mim-remote-access-shell.pid.json'
$cloudflaredStdOutPath = Join-Path $logsRoot 'cloudflared.stdout.log'
$cloudflaredStdErrPath = Join-Path $logsRoot 'cloudflared.stderr.log'
$uiStdOutPath = Join-Path $logsRoot 'tod-ui.stdout.log'
$uiStdErrPath = Join-Path $logsRoot 'tod-ui.stderr.log'
$driveAccessProbePath = 'E:\'

$cloudflaredExe = ''
$mobileEvidence = $null
$cloudflaredExe = Resolve-CloudflaredPath -ExplicitPath $CloudflaredPath -DownloadUrl $CloudflaredDownloadUrl -SkipInstall:$NoInstall
$mobileEvidence = Get-MobileReadinessEvidence -Path $uiIndexPath

$uiChild = $null
$tunnelChild = $null

try {
    $uiChild = Start-TodUiChild -RequestedPort $Port -FallbackAllowed:$AllowPortFallback -TimeoutSeconds $UiStartupTimeoutSeconds -StdOutPath $uiStdOutPath -StdErrPath $uiStdErrPath
    $localUrl = [string]$uiChild.advertise_url

    $localStatus = Get-ProjectStatusProbe -BaseUrl $localUrl -TimeoutSeconds $ProbeTimeoutSeconds
    if (-not $localStatus.ok) {
        throw ("Local project-status probe failed: {0}" -f $localStatus.error)
    }

    $localInteraction = Invoke-MimCommandProbe -BaseUrl $localUrl -ObjectiveId $localStatus.selected_objective_id -TimeoutSeconds $ProbeTimeoutSeconds

    $localDriveAccess = Invoke-DriveAccessProbe -BaseUrl $localUrl -RequestedPath $driveAccessProbePath -TimeoutSeconds $ProbeTimeoutSeconds
    if (-not $localDriveAccess.ok) {
        throw ("Local /api/drive-access-list probe failed: {0}" -f $localDriveAccess.error)
    }

    $publicUrl = ''
    $startupIssue = ''
    $remoteStatus = New-FailedStatusProbe -BaseUrl '' -ErrorMessage 'Remote tunnel not started yet.'
    $remoteInteraction = New-FailedInteractionProbe -BaseUrl '' -ErrorMessage 'Remote tunnel not started yet.'
    $remoteDriveAccess = New-FailedDriveAccessProbe -BaseUrl '' -RequestedPath $driveAccessProbePath -ErrorMessage 'Remote tunnel not started yet.'
    try {
        $tunnelChild = Start-CloudflareQuickTunnel -ExecutablePath $cloudflaredExe -LocalUrl $localUrl -HomeRoot $cloudflaredHomeRoot -TimeoutSeconds $TunnelStartupTimeoutSeconds -StdOutPath $cloudflaredStdOutPath -StdErrPath $cloudflaredStdErrPath
        $publicUrl = [string]$tunnelChild.public_url
        $remoteStatus = Wait-ProjectStatusProbe -BaseUrl $publicUrl -ProbeTimeoutSeconds $ProbeTimeoutSeconds -GraceSeconds $RemoteProbeGraceSeconds -PollSeconds $RemoteProbePollSeconds
        if ($remoteStatus.ok) {
            $remoteInteraction = Wait-MimCommandProbe -BaseUrl $publicUrl -ObjectiveId $localStatus.selected_objective_id -ProbeTimeoutSeconds $ProbeTimeoutSeconds -GraceSeconds $RemoteProbeGraceSeconds -PollSeconds $RemoteProbePollSeconds
            $remoteDriveAccess = Invoke-DriveAccessProbe -BaseUrl $publicUrl -RequestedPath $driveAccessProbePath -TimeoutSeconds $ProbeTimeoutSeconds
        } else {
            $remoteInteraction = New-FailedInteractionProbe -BaseUrl $publicUrl -ErrorMessage 'Remote project-status probe was unavailable during startup.'
            $remoteDriveAccess = New-FailedDriveAccessProbe -BaseUrl $publicUrl -RequestedPath $driveAccessProbePath -ErrorMessage 'Remote project-status probe was unavailable during startup.'
        }

        if (-not $remoteStatus.ok) {
            $startupIssue = "Remote project-status probe failed: $($remoteStatus.error)"
        } elseif (-not $remoteDriveAccess.ok) {
            $startupIssue = "Remote /api/drive-access-list probe failed: $($remoteDriveAccess.error)"
        }
    } catch {
        $startupIssue = [string]$_.Exception.Message
        $remoteStatus = New-FailedStatusProbe -BaseUrl $publicUrl -ErrorMessage $startupIssue
        $remoteInteraction = New-FailedInteractionProbe -BaseUrl $publicUrl -ErrorMessage $startupIssue
        $remoteDriveAccess = New-FailedDriveAccessProbe -BaseUrl $publicUrl -RequestedPath $driveAccessProbePath -ErrorMessage $startupIssue
        $tunnelChild = $null
    }

    $report = New-RemoteAccessReport -Status $(if ([string]::IsNullOrWhiteSpace($startupIssue)) { 'healthy' } else { 'degraded' }) -Message $(if ([string]::IsNullOrWhiteSpace($startupIssue)) { 'Remote access shell is active over a Cloudflare quick tunnel with read-only E drive access.' } else { 'Remote access shell bootstrapped with retry pending: ' + $startupIssue }) -LocalUrl $localUrl -PublicUrl $publicUrl -CloudflaredExe $cloudflaredExe -UiProcess $uiChild.process -TunnelProcess $(if ($tunnelChild) { $tunnelChild.process } else { $null }) -LocalStatus $localStatus -LocalInteraction $localInteraction -LocalDriveAccess $localDriveAccess -RemoteStatus $remoteStatus -RemoteInteraction $remoteInteraction -RemoteDriveAccess $remoteDriveAccess -MobileEvidence $mobileEvidence -StdOutLog $cloudflaredStdOutPath -StdErrLog $cloudflaredStdErrPath -UiStdOutLog $uiStdOutPath -UiStdErrLog $uiStdErrPath
    Write-RemoteAccessArtifacts -Report $report -UiProcess $uiChild.process -TunnelProcess $(if ($tunnelChild) { $tunnelChild.process } else { $null }) -StatusPath $statusPath -SummaryPath $summaryPath -PidPath $pidPath

    if ($NoWait) {
        return
    }

    while ($true) {
        $restartReasons = @()

        if ($uiChild.process.HasExited) {
            $restartReasons += 'ui_process_exited'
            $uiChild = Restart-TodUiChild -ExistingProcess $uiChild.process -RequestedPort $Port -FallbackAllowed:$AllowPortFallback -TimeoutSeconds $UiStartupTimeoutSeconds -StdOutPath $uiStdOutPath -StdErrPath $uiStdErrPath
            $localUrl = [string]$uiChild.advertise_url
        }

        $localStatus = Get-ProjectStatusProbe -BaseUrl $localUrl -TimeoutSeconds $ProbeTimeoutSeconds
        if (-not $localStatus.ok) {
            $restartReasons += 'local_project_status_failed'
            $uiChild = Restart-TodUiChild -ExistingProcess $uiChild.process -RequestedPort $Port -FallbackAllowed:$AllowPortFallback -TimeoutSeconds $UiStartupTimeoutSeconds -StdOutPath $uiStdOutPath -StdErrPath $uiStdErrPath
            $localUrl = [string]$uiChild.advertise_url
            $localStatus = Get-ProjectStatusProbe -BaseUrl $localUrl -TimeoutSeconds $ProbeTimeoutSeconds
        }

        if ($localStatus.ok) {
            $localInteraction = Invoke-MimCommandProbe -BaseUrl $localUrl -ObjectiveId $localStatus.selected_objective_id -TimeoutSeconds $ProbeTimeoutSeconds
            $localDriveAccess = Invoke-DriveAccessProbe -BaseUrl $localUrl -RequestedPath $driveAccessProbePath -TimeoutSeconds $ProbeTimeoutSeconds
        } else {
            $localInteraction = [pscustomobject]@{
                ok = $false
                base_url = $localUrl
                session_id = ''
                summary = ''
                error = 'Local project-status probe was unavailable.'
            }
            $localDriveAccess = New-FailedDriveAccessProbe -BaseUrl $localUrl -RequestedPath $driveAccessProbePath -ErrorMessage 'Local project-status probe was unavailable.'
        }

        if ($null -eq $tunnelChild -or $null -eq $tunnelChild.process -or $tunnelChild.process.HasExited -or [string]::IsNullOrWhiteSpace($publicUrl)) {
            $restartReasons += 'tunnel_process_exited'
            try {
                if ($tunnelChild) {
                    $tunnelChild = Restart-CloudflareQuickTunnel -ExistingProcess $tunnelChild.process -ExecutablePath $cloudflaredExe -LocalUrl $localUrl -HomeRoot $cloudflaredHomeRoot -TimeoutSeconds $TunnelStartupTimeoutSeconds -StdOutPath $cloudflaredStdOutPath -StdErrPath $cloudflaredStdErrPath
                } else {
                    $tunnelChild = Start-CloudflareQuickTunnel -ExecutablePath $cloudflaredExe -LocalUrl $localUrl -HomeRoot $cloudflaredHomeRoot -TimeoutSeconds $TunnelStartupTimeoutSeconds -StdOutPath $cloudflaredStdOutPath -StdErrPath $cloudflaredStdErrPath
                }
                $publicUrl = [string]$tunnelChild.public_url
            } catch {
                $publicUrl = ''
                $remoteStatus = New-FailedStatusProbe -BaseUrl '' -ErrorMessage ([string]$_.Exception.Message)
                $remoteInteraction = New-FailedInteractionProbe -BaseUrl '' -ErrorMessage ([string]$_.Exception.Message)
                $remoteDriveAccess = New-FailedDriveAccessProbe -BaseUrl '' -RequestedPath $driveAccessProbePath -ErrorMessage ([string]$_.Exception.Message)
                $status = 'degraded'
                $message = 'Remote access shell recovery is waiting for Cloudflare tunnel startup: ' + [string]$_.Exception.Message
                $rollingReport = New-RemoteAccessReport -Status $status -Message $message -LocalUrl $localUrl -PublicUrl $publicUrl -CloudflaredExe $cloudflaredExe -UiProcess $uiChild.process -TunnelProcess $null -LocalStatus $localStatus -LocalInteraction $localInteraction -LocalDriveAccess $localDriveAccess -RemoteStatus $remoteStatus -RemoteInteraction $remoteInteraction -RemoteDriveAccess $remoteDriveAccess -MobileEvidence $mobileEvidence -StdOutLog $cloudflaredStdOutPath -StdErrLog $cloudflaredStdErrPath -UiStdOutLog $uiStdOutPath -UiStdErrLog $uiStdErrPath
                Write-RemoteAccessArtifacts -Report $rollingReport -UiProcess $uiChild.process -TunnelProcess $null -StatusPath $statusPath -SummaryPath $summaryPath -PidPath $pidPath
                Start-Sleep -Seconds $HealthIntervalSeconds
                continue
            }
        }

        $remoteStatus = Wait-ProjectStatusProbe -BaseUrl $publicUrl -ProbeTimeoutSeconds $ProbeTimeoutSeconds -GraceSeconds $RemoteProbeGraceSeconds -PollSeconds $RemoteProbePollSeconds
        if (-not $remoteStatus.ok) {
            $restartReasons += 'remote_project_status_failed'
            try {
                $tunnelChild = Restart-CloudflareQuickTunnel -ExistingProcess $tunnelChild.process -ExecutablePath $cloudflaredExe -LocalUrl $localUrl -HomeRoot $cloudflaredHomeRoot -TimeoutSeconds $TunnelStartupTimeoutSeconds -StdOutPath $cloudflaredStdOutPath -StdErrPath $cloudflaredStdErrPath
                $publicUrl = [string]$tunnelChild.public_url
                $remoteStatus = Wait-ProjectStatusProbe -BaseUrl $publicUrl -ProbeTimeoutSeconds $ProbeTimeoutSeconds -GraceSeconds $RemoteProbeGraceSeconds -PollSeconds $RemoteProbePollSeconds
            } catch {
                $publicUrl = ''
                $remoteStatus = New-FailedStatusProbe -BaseUrl '' -ErrorMessage ([string]$_.Exception.Message)
            }
        }

        if ($remoteStatus.ok -and $localStatus.ok) {
            $remoteInteraction = Wait-MimCommandProbe -BaseUrl $publicUrl -ObjectiveId $localStatus.selected_objective_id -ProbeTimeoutSeconds $ProbeTimeoutSeconds -GraceSeconds $RemoteProbeGraceSeconds -PollSeconds $RemoteProbePollSeconds
            $remoteDriveAccess = Invoke-DriveAccessProbe -BaseUrl $publicUrl -RequestedPath $driveAccessProbePath -TimeoutSeconds $ProbeTimeoutSeconds
        } else {
            $remoteInteraction = New-FailedInteractionProbe -BaseUrl $publicUrl -ErrorMessage 'Remote project-status probe was unavailable.'
            $remoteDriveAccess = New-FailedDriveAccessProbe -BaseUrl $publicUrl -RequestedPath $driveAccessProbePath -ErrorMessage 'Remote project-status probe was unavailable.'
        }
        $status = if ($localStatus.ok -and $localDriveAccess.ok -and $remoteStatus.ok -and $remoteDriveAccess.ok) { 'healthy' } else { 'degraded' }
        $message = if ($restartReasons.Count -gt 0) {
            'Remote access shell recovered from: ' + ($restartReasons -join ', ')
        } elseif ($status -eq 'healthy') {
            'Remote access shell is active over a Cloudflare quick tunnel with read-only E drive access.'
        } else {
            'One or more remote access shell probes failed. Review logs.'
        }

        $rollingReport = New-RemoteAccessReport -Status $status -Message $message -LocalUrl $localUrl -PublicUrl $publicUrl -CloudflaredExe $cloudflaredExe -UiProcess $uiChild.process -TunnelProcess $(if ($tunnelChild) { $tunnelChild.process } else { $null }) -LocalStatus $localStatus -LocalInteraction $localInteraction -LocalDriveAccess $localDriveAccess -RemoteStatus $remoteStatus -RemoteInteraction $remoteInteraction -RemoteDriveAccess $remoteDriveAccess -MobileEvidence $mobileEvidence -StdOutLog $cloudflaredStdOutPath -StdErrLog $cloudflaredStdErrPath -UiStdOutLog $uiStdOutPath -UiStdErrLog $uiStdErrPath
        Write-RemoteAccessArtifacts -Report $rollingReport -UiProcess $uiChild.process -TunnelProcess $(if ($tunnelChild) { $tunnelChild.process } else { $null }) -StatusPath $statusPath -SummaryPath $summaryPath -PidPath $pidPath
        Start-Sleep -Seconds $HealthIntervalSeconds
    }
} catch {
    $failureMessage = [string]$_.Exception.Message
    $failureReport = New-RemoteAccessReport -Status 'failed' -Message $failureMessage -LocalUrl $(if ($uiChild) { [string]$uiChild.advertise_url } else { '' }) -PublicUrl $(if ($tunnelChild) { [string]$tunnelChild.public_url } else { '' }) -CloudflaredExe $cloudflaredExe -UiProcess $(if ($uiChild) { $uiChild.process } else { $null }) -TunnelProcess $(if ($tunnelChild) { $tunnelChild.process } else { $null }) -LocalStatus $null -LocalInteraction $null -LocalDriveAccess $null -RemoteStatus $null -RemoteInteraction $null -RemoteDriveAccess $null -MobileEvidence $mobileEvidence -StdOutLog $cloudflaredStdOutPath -StdErrLog $cloudflaredStdErrPath -UiStdOutLog $uiStdOutPath -UiStdErrLog $uiStdErrPath
    Write-RemoteAccessArtifacts -Report $failureReport -UiProcess $(if ($uiChild) { $uiChild.process } else { $null }) -TunnelProcess $(if ($tunnelChild) { $tunnelChild.process } else { $null }) -StatusPath $statusPath -SummaryPath $summaryPath -PidPath $pidPath
    Stop-TrackedProcess -Process $(if ($tunnelChild) { $tunnelChild.process } else { $null })
    Stop-TrackedProcess -Process $(if ($uiChild) { $uiChild.process } else { $null })
    throw
}