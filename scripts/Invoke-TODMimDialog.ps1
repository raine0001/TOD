param(
    [ValidateSet('send', 'read-session', 'read-inbox', 'close-session', 'get-session-status')]
    [string]$Action = 'read-inbox',
    [string]$SharedStateDir = 'shared_state',
    [string]$DialogDir = 'shared_state/dialog',
    [string]$SessionId = '',
    [string]$Actor = 'TOD',
    [string]$PeerActor = 'MIM',
    [ValidateSet('diagnostic_query', 'diagnostic_reply', 'status_request', 'status_reply', 'blocker_notice', 'resolution_notice', 'handoff_request', 'handoff_response')]
    [string]$MessageType = 'diagnostic_query',
    [string]$Intent = '',
    [string]$TaskId = '',
    [string]$CorrelationId = '',
    [string]$Summary = '',
    [string]$PayloadJson = '{}',
    [switch]$RequiresReply,
    [int]$Tail = 25,
    [int]$MaxSummaryLength = 280,
    [int]$MaxPayloadChars = 12000,
    [int]$MaxOpenMinutes = 30,
    [string]$DotEnvPath = '.env',
    [string]$RemoteHost = '',
    [string]$RemoteUser = '',
    [int]$RemotePort = 0,
    [string]$RemotePassword = '',
    [string]$RemoteRoot = '',
    [int]$RemoteConnectionTimeoutMilliseconds = 15000,
    [switch]$PublishRemote,
    [switch]$RefreshFromRemote,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$channelVersion = 'mim-tod-dialog-v1'

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Ensure-ParentDirectoryForFile {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $dir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        Ensure-Directory -PathValue $dir
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        Ensure-Directory -PathValue $dir
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
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        Ensure-Directory -PathValue $dir
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $line = (($Payload | ConvertTo-Json -Depth $Depth -Compress) + "`n")
    [System.IO.File]::AppendAllText($PathValue, $line, $utf8NoBom)
}

function Get-DotEnvValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }
    if (-not (Test-Path -Path $Path)) {
        return ''
    }

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace([string]$line)) {
        return ''
    }

    return ([string]($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), '')).Trim()
}

function Resolve-MimSshSettingValue {
    param(
        [string]$ExplicitValue,
        [string]$EnvVarName,
        [string]$DotEnvPathValue
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitValue)) {
        return [string]$ExplicitValue
    }

    if (-not [string]::IsNullOrWhiteSpace($EnvVarName)) {
        $fromEnv = [string][Environment]::GetEnvironmentVariable($EnvVarName)
        if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
            return $fromEnv
        }

        $fromDotEnv = Get-DotEnvValue -Path $DotEnvPathValue -Name $EnvVarName
        if (-not [string]::IsNullOrWhiteSpace($fromDotEnv)) {
            return $fromDotEnv
        }
    }

    return ''
}

function Resolve-SshHostAlias {
    param([string]$RemoteHostValue)

    if ([string]::IsNullOrWhiteSpace($RemoteHostValue)) {
        return ''
    }

    if ($RemoteHostValue -match '^\d{1,3}(?:\.\d{1,3}){3}$' -or $RemoteHostValue -match '\.') {
        return $RemoteHostValue
    }

    $sshConfigPath = Join-Path $HOME '.ssh/config'
    if (-not (Test-Path -Path $sshConfigPath)) {
        return $RemoteHostValue
    }

    $matchedHost = $false
    $resolvedHostName = ''
    foreach ($rawLine in (Get-Content -Path $sshConfigPath)) {
        $trim = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith('#')) {
            continue
        }

        if ($trim -match '^(?i)Host\s+(.+)$') {
            $matchedHost = $false
            foreach ($token in @($matches[1] -split '\s+')) {
                if ([string]::Equals([string]$token, $RemoteHostValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchedHost = $true
                    break
                }
            }
            continue
        }

        if ($matchedHost -and $trim -match '^(?i)HostName\s+(.+)$') {
            $resolvedHostName = [string]$matches[1]
            break
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedHostName)) {
        return $resolvedHostName
    }

    return $RemoteHostValue
}

function New-MimSshConnections {
    param(
        [Parameter(Mandatory = $true)][string]$HostAlias,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password,
        [int]$ConnectionTimeoutMilliseconds = 15000
    )

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        throw 'Posh-SSH is not installed. Install-Module -Name Posh-SSH -Scope CurrentUser'
    }

    Import-Module Posh-SSH -ErrorAction Stop | Out-Null

    $resolvedHost = Resolve-SshHostAlias -RemoteHostValue $HostAlias
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($UserName, $securePassword)

    $safeConnectionTimeoutMilliseconds = if ($ConnectionTimeoutMilliseconds -gt 0) { [int]$ConnectionTimeoutMilliseconds } else { 15000 }
    $sshSession = New-SSHSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout $safeConnectionTimeoutMilliseconds
    $sftpSession = New-SFTPSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout $safeConnectionTimeoutMilliseconds

    return [pscustomobject]@{
        host_alias = $HostAlias
        resolved_host = $resolvedHost
        ssh = $sshSession
        sftp = $sftpSession
    }
}

function Close-MimSshConnections {
    param($Connections)

    if ($null -eq $Connections) { return }

    try {
        if ($Connections.sftp) {
            Remove-SFTPSession -SessionId ([int]$Connections.sftp.SessionId) | Out-Null
        }
    }
    catch {
    }

    try {
        if ($Connections.ssh) {
            Remove-SSHSession -SessionId ([int]$Connections.ssh.SessionId) | Out-Null
        }
    }
    catch {
    }
}

function Copy-FromSftpIfAvailable {
    param(
        [Parameter(Mandatory = $true)][int]$SessionId,
        [Parameter(Mandatory = $true)][string]$RemotePathValue,
        [Parameter(Mandatory = $true)][string]$LocalPathValue
    )

    $result = [pscustomobject]@{
        ok = $false
        remote_path = $RemotePathValue
        local_path = $LocalPathValue
        error = ''
    }

    try {
        Ensure-ParentDirectoryForFile -FilePath $LocalPathValue
        $destinationDir = Split-Path -Parent $LocalPathValue
        if ([string]::IsNullOrWhiteSpace($destinationDir)) {
            $destinationDir = Get-Location
        }
        Get-SFTPItem -SessionId $SessionId -Path $RemotePathValue -Destination $destinationDir -Force -ErrorAction Stop | Out-Null
        if (Test-Path -Path $LocalPathValue -PathType Leaf) {
            $result.ok = $true
            return $result
        }
        $result.error = 'optional_missing'
    }
    catch {
        $result.error = [string]$_.Exception.Message
    }

    return $result
}

function Get-RemoteDialogSettings {
    $dotEnvAbs = ''
    if (-not [string]::IsNullOrWhiteSpace($DotEnvPath)) {
        $dotEnvAbs = Get-LocalPath -PathValue $DotEnvPath
    }

    $resolvedHost = Resolve-MimSshSettingValue -ExplicitValue $RemoteHost -EnvVarName 'MIM_SSH_HOST' -DotEnvPathValue $dotEnvAbs
    $resolvedUser = Resolve-MimSshSettingValue -ExplicitValue $RemoteUser -EnvVarName 'MIM_SSH_USER' -DotEnvPathValue $dotEnvAbs
    if ([string]::IsNullOrWhiteSpace($resolvedUser)) {
        $resolvedUser = 'testpilot'
    }
    $portText = if ($RemotePort -gt 0) { [string]$RemotePort } else { '' }
    $resolvedPortText = Resolve-MimSshSettingValue -ExplicitValue $portText -EnvVarName 'MIM_SSH_PORT' -DotEnvPathValue $dotEnvAbs
    $resolvedPort = 22
    if (-not [string]::IsNullOrWhiteSpace($resolvedPortText)) {
        $parsedPort = 0
        if ([int]::TryParse($resolvedPortText, [ref]$parsedPort) -and $parsedPort -gt 0) {
            $resolvedPort = $parsedPort
        }
    }
    $resolvedPassword = Resolve-MimSshSettingValue -ExplicitValue $RemotePassword -EnvVarName 'MIM_SSH_PASSWORD' -DotEnvPathValue $dotEnvAbs
    $resolvedRoot = Resolve-MimSshSettingValue -ExplicitValue $RemoteRoot -EnvVarName 'MIM_TOD_DIALOG_REMOTE_ROOT' -DotEnvPathValue $dotEnvAbs
    if ([string]::IsNullOrWhiteSpace($resolvedRoot)) {
        $resolvedRoot = '/home/testpilot/mim/runtime/shared/dialog'
    }

    return [pscustomobject]@{
        available = (-not [string]::IsNullOrWhiteSpace($resolvedHost)) -and (-not [string]::IsNullOrWhiteSpace($resolvedPassword))
        host = $resolvedHost
        user = $resolvedUser
        port = $resolvedPort
        password = $resolvedPassword
        root = $resolvedRoot.TrimEnd('/')
        dot_env_path = $dotEnvAbs
    }
}

function Get-RemoteDialogPath {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    return ('{0}/{1}' -f [string]$Settings.root, [string]$FileName)
}

function Publish-DialogArtifactsRemote {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)]$Paths
    )

    $result = [pscustomobject]@{
        attempted = $true
        uploaded = $false
        status = 'pending'
        remote_root = [string]$Settings.root
        ssh_host = [string]$Settings.host
        ssh_port = [int]$Settings.port
        error = ''
    }

    if (-not [bool]$Settings.available) {
        $result.status = 'remote_not_configured'
        $result.error = 'remote_not_configured'
        return $result
    }

    $connections = $null
    try {
        $connections = New-MimSshConnections -HostAlias ([string]$Settings.host) -UserName ([string]$Settings.user) -Port ([int]$Settings.port) -Password ([string]$Settings.password) -ConnectionTimeoutMilliseconds $RemoteConnectionTimeoutMilliseconds
        $mkdirResult = Invoke-SSHCommand -SessionId ([int]$connections.ssh.SessionId) -Command ("mkdir -p '{0}'" -f [string]$Settings.root) -TimeOut 20
        if ($mkdirResult.ExitStatus -ne 0) {
            throw 'remote_dialog_root_create_failed'
        }

        foreach ($localPath in @($Paths.session_path, $Paths.session_state_path, $Paths.channel_path, $Paths.index_path)) {
            if (Test-Path -Path $localPath) {
                Set-SFTPItem -SessionId ([int]$connections.sftp.SessionId) -Path $localPath -Destination ([string]$Settings.root) -Force -ErrorAction Stop | Out-Null
            }
        }

        $result.uploaded = $true
        $result.status = 'uploaded'
    }
    catch {
        $result.status = 'upload_failed'
        $result.error = [string]$_.Exception.Message
    }
    finally {
        Close-MimSshConnections -Connections $connections
    }

    return $result
}

function Refresh-DialogArtifactsRemote {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)]$Paths,
        [switch]$IncludeSessionLog,
        [switch]$IncludeSessionState,
        [switch]$IncludeIndex,
        [switch]$IncludeChannel
    )

    $result = [pscustomobject]@{
        attempted = $true
        refreshed = $false
        status = 'pending'
        remote_root = [string]$Settings.root
        error = ''
    }

    if (-not [bool]$Settings.available) {
        $result.status = 'remote_not_configured'
        $result.error = 'remote_not_configured'
        return $result
    }

    $connections = $null
    try {
        $connections = New-MimSshConnections -HostAlias ([string]$Settings.host) -UserName ([string]$Settings.user) -Port ([int]$Settings.port) -Password ([string]$Settings.password) -ConnectionTimeoutMilliseconds $RemoteConnectionTimeoutMilliseconds
        $items = @()
        if ($IncludeSessionLog) {
            $items += [pscustomobject]@{ remote = (Get-RemoteDialogPath -Settings $Settings -FileName (Split-Path -Leaf $Paths.session_path)); local = $Paths.session_path }
        }
        if ($IncludeSessionState) {
            $items += [pscustomobject]@{ remote = (Get-RemoteDialogPath -Settings $Settings -FileName (Split-Path -Leaf $Paths.session_state_path)); local = $Paths.session_state_path }
        }
        if ($IncludeIndex) {
            $items += [pscustomobject]@{ remote = (Get-RemoteDialogPath -Settings $Settings -FileName (Split-Path -Leaf $Paths.index_path)); local = $Paths.index_path }
        }
        if ($IncludeChannel) {
            $items += [pscustomobject]@{ remote = (Get-RemoteDialogPath -Settings $Settings -FileName (Split-Path -Leaf $Paths.channel_path)); local = $Paths.channel_path }
        }

        foreach ($item in @($items)) {
            $pull = Copy-FromSftpIfAvailable -SessionId ([int]$connections.sftp.SessionId) -RemotePathValue ([string]$item.remote) -LocalPathValue ([string]$item.local)
            if ($pull.ok) {
                $result.refreshed = $true
            }
        }

        $result.status = if ($result.refreshed) { 'refreshed' } else { 'no_remote_updates' }
    }
    catch {
        $result.status = 'refresh_failed'
        $result.error = [string]$_.Exception.Message
    }
    finally {
        Close-MimSshConnections -Connections $connections
    }

    return $result
}

function Read-JsonLinesFile {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return @()
    }

    $items = @()
    foreach ($line in (Get-Content -Path $PathValue -ErrorAction SilentlyContinue)) {
        $text = ([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        try {
            $items += ($text | ConvertFrom-Json)
        }
        catch {
            $items += [pscustomobject]@{
                parse_error = $true
                raw = $text
            }
        }
    }

    return @($items)
}

function Normalize-Actor {
    param([string]$Value)

    $text = ([string]$Value).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'Actor must not be empty.'
    }

    return $text
}

function Get-SessionFileName {
    param([Parameter(Mandatory = $true)][string]$SessionValue)

    $safe = ([string]$SessionValue).Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) {
        throw 'SessionId must not be empty.'
    }

    $safe = $safe -replace '[^a-zA-Z0-9._-]', '_'
    return "MIM_TOD_DIALOG.session-$safe.jsonl"
}

function Get-SessionPaths {
    param(
        [Parameter(Mandatory = $true)][string]$DialogDirValue,
        [Parameter(Mandatory = $true)][string]$SessionValue
    )

    $sessionFileName = Get-SessionFileName -SessionValue $SessionValue
    $sessionPath = Join-Path $DialogDirValue $sessionFileName
    $sessionStatePath = Join-Path $DialogDirValue ($sessionFileName -replace '\.jsonl$', '.latest.json')
    $channelPath = Join-Path $DialogDirValue 'MIM_TOD_DIALOG.latest.jsonl'
    $indexPath = Join-Path $DialogDirValue 'MIM_TOD_DIALOG.sessions.latest.json'

    return [pscustomobject]@{
        session_path = $sessionPath
        session_state_path = $sessionStatePath
        channel_path = $channelPath
        index_path = $indexPath
    }
}

function ConvertTo-HashtableSafe {
    param($Value)

    if ($null -eq $Value) {
        return @{}
    }

    if ($Value -is [hashtable]) {
        return $Value
    }

    $result = @{}
    if ($Value.PSObject -and $Value.PSObject.Properties) {
        foreach ($prop in $Value.PSObject.Properties) {
            $result[[string]$prop.Name] = $prop.Value
        }
    }
    return $result
}

function Parse-PayloadJson {
    param([string]$PayloadText)

    $raw = if ([string]::IsNullOrWhiteSpace($PayloadText)) { '{}' } else { [string]$PayloadText }
    if ($raw.Length -gt $MaxPayloadChars) {
        throw "PayloadJson exceeds MaxPayloadChars ($MaxPayloadChars)."
    }

    try {
        $parsed = $raw | ConvertFrom-Json
    }
    catch {
        throw "PayloadJson is not valid JSON: $([string]$_.Exception.Message)"
    }

    return (ConvertTo-HashtableSafe -Value $parsed)
}

function Get-SessionMessages {
    param([Parameter(Mandatory = $true)][string]$SessionPath)

    return @(Read-JsonLinesFile -PathValue $SessionPath | Where-Object {
        -not ($_.PSObject.Properties['parse_error'] -and [bool]$_.parse_error)
    })
}

function Get-OpenReplyExpectation {
    param([object[]]$Messages)

    $open = $null
    foreach ($message in @($Messages)) {
        $fromActor = if ($message.PSObject.Properties['from']) { Normalize-Actor -Value ([string]$message.from) } else { '' }
        $toActor = if ($message.PSObject.Properties['to']) { Normalize-Actor -Value ([string]$message.to) } else { '' }
        $turnId = if ($message.PSObject.Properties['turn_id']) { [int]$message.turn_id } else { 0 }
        $requiresReply = [bool]($message.PSObject.Properties['requires_reply'] -and $message.requires_reply)

        if ($requiresReply) {
            $open = [pscustomobject]@{
                turn_id = $turnId
                from = $fromActor
                to = $toActor
                message_type = if ($message.PSObject.Properties['message_type']) { [string]$message.message_type } else { '' }
                summary = if ($message.PSObject.Properties['summary']) { [string]$message.summary } else { '' }
                timestamp = if ($message.PSObject.Properties['timestamp']) { [string]$message.timestamp } else { '' }
            }
            continue
        }

        $messageType = if ($message.PSObject.Properties['message_type']) { [string]$message.message_type } else { '' }

        if ($null -ne $open -and [string]::Equals($messageType, 'resolution_notice', [System.StringComparison]::OrdinalIgnoreCase) -and $turnId -gt [int]$open.turn_id) {
            $open = $null
            continue
        }

        if ($null -ne $open -and $fromActor -eq $open.to -and $toActor -eq $open.from -and $turnId -gt [int]$open.turn_id) {
            $open = $null
        }
    }

    return $open
}

function Get-NextTurnId {
    param([object[]]$Messages)

    $maxTurnId = 0
    foreach ($message in @($Messages)) {
        if ($message.PSObject.Properties['turn_id']) {
            try {
                $turnId = [int]$message.turn_id
                if ($turnId -gt $maxTurnId) {
                    $maxTurnId = $turnId
                }
            }
            catch {
            }
        }
    }

    return ($maxTurnId + 1)
}

function Update-SessionIndex {
    param(
        [Parameter(Mandatory = $true)][string]$IndexPath,
        [Parameter(Mandatory = $true)][string]$SessionIdValue,
        [Parameter(Mandatory = $true)]$SessionState
    )

    $existing = @()
    if (Test-Path -Path $IndexPath) {
        try {
            $doc = Get-Content -Path $IndexPath -Raw | ConvertFrom-Json
            if ($doc -and $doc.PSObject.Properties['sessions']) {
                $existing = @($doc.sessions)
            }
        }
        catch {
            $existing = @()
        }
    }

    $sessions = @()
    $replaced = $false
    foreach ($entry in @($existing)) {
        if ($entry.PSObject.Properties['session_id'] -and [string]::Equals([string]$entry.session_id, $SessionIdValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            $sessions += $SessionState
            $replaced = $true
        }
        else {
            $sessions += $entry
        }
    }

    if (-not $replaced) {
        $sessions += $SessionState
    }

    $payload = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = $channelVersion
        sessions = @($sessions | Sort-Object {
            if ($_.PSObject.Properties['updated_at']) { [string]$_.updated_at } else { '' }
        } -Descending)
    }

    Write-Utf8NoBomJson -PathValue $IndexPath -Payload $payload -Depth 12
}

function Get-SessionState {
    param(
        [Parameter(Mandatory = $true)][string]$SessionIdValue,
        [Parameter(Mandatory = $true)][object[]]$Messages,
        [Parameter(Mandatory = $true)][string]$SessionPath,
        [int]$MaxOpenMinutesValue = 30
    )

    $lastMessage = if (@($Messages).Count -gt 0) { @($Messages)[-1] } else { $null }
    $openReply = Get-OpenReplyExpectation -Messages $Messages
    $lastUpdatedAt = if ($lastMessage -and $lastMessage.PSObject.Properties['timestamp']) { [string]$lastMessage.timestamp } else { '' }
    $status = 'idle'
    $inactive = $false

    if ($openReply) {
        $status = 'awaiting_reply'
        try {
            $openAt = [datetime]::Parse([string]$openReply.timestamp).ToUniversalTime()
            $inactive = (((Get-Date).ToUniversalTime() - $openAt).TotalMinutes -ge $MaxOpenMinutesValue)
            if ($inactive) {
                $status = 'timed_out'
            }
        }
        catch {
        }
    }
    elseif ($lastMessage -and $lastMessage.PSObject.Properties['message_type'] -and [string]::Equals([string]$lastMessage.message_type, 'resolution_notice', [System.StringComparison]::OrdinalIgnoreCase)) {
        $status = 'closed'
    }
    elseif ($lastMessage) {
        $status = 'resolved'
    }

    return [pscustomobject]@{
        session_id = $SessionIdValue
        status = $status
        timed_out = $inactive
        message_count = @($Messages).Count
        updated_at = $lastUpdatedAt
        session_path = $SessionPath
        open_reply = $openReply
        last_message = if ($lastMessage) {
            [pscustomobject]@{
                turn_id = if ($lastMessage.PSObject.Properties['turn_id']) { [int]$lastMessage.turn_id } else { 0 }
                from = if ($lastMessage.PSObject.Properties['from']) { [string]$lastMessage.from } else { '' }
                to = if ($lastMessage.PSObject.Properties['to']) { [string]$lastMessage.to } else { '' }
                message_type = if ($lastMessage.PSObject.Properties['message_type']) { [string]$lastMessage.message_type } else { '' }
                summary = if ($lastMessage.PSObject.Properties['summary']) { [string]$lastMessage.summary } else { '' }
                task_id = if ($lastMessage.PSObject.Properties['task_id']) { [string]$lastMessage.task_id } else { '' }
                correlation_id = if ($lastMessage.PSObject.Properties['correlation_id']) { [string]$lastMessage.correlation_id } else { '' }
                timestamp = if ($lastMessage.PSObject.Properties['timestamp']) { [string]$lastMessage.timestamp } else { '' }
            }
        } else {
            $null
        }
    }
}

function Write-SessionStateArtifacts {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)]$SessionState
    )

    Write-Utf8NoBomJson -PathValue $Paths.session_state_path -Payload $SessionState -Depth 12
    Update-SessionIndex -IndexPath $Paths.index_path -SessionIdValue ([string]$SessionState.session_id) -SessionState $SessionState
}

function Get-RefreshedSessionState {
    param(
        [Parameter(Mandatory = $true)][string]$DialogDirValue,
        [Parameter(Mandatory = $true)][string]$SessionIdValue,
        [int]$MaxOpenMinutesValue = 30
    )

    $paths = Get-SessionPaths -DialogDirValue $DialogDirValue -SessionValue $SessionIdValue
    $messages = @(Get-SessionMessages -SessionPath $paths.session_path)
    $sessionState = Get-SessionState -SessionIdValue $SessionIdValue -Messages $messages -SessionPath $paths.session_path -MaxOpenMinutesValue $MaxOpenMinutesValue
    Write-SessionStateArtifacts -Paths $paths -SessionState $sessionState
    return $sessionState
}

function Require-SessionId {
    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        throw 'SessionId is required for this action.'
    }
}

$dialogDirAbs = Get-LocalPath -PathValue $DialogDir
$sharedStateAbs = Get-LocalPath -PathValue $SharedStateDir
Ensure-Directory -PathValue $sharedStateAbs
Ensure-Directory -PathValue $dialogDirAbs

$remoteDialogSettings = $null
if ($PublishRemote -or $RefreshFromRemote) {
    $remoteDialogSettings = Get-RemoteDialogSettings
}

switch ($Action) {
    'send' {
        Require-SessionId

        $fromActor = Normalize-Actor -Value $Actor
        $toActor = Normalize-Actor -Value $PeerActor
        if ($fromActor -eq $toActor) {
            throw 'Actor and PeerActor must differ.'
        }
        if ([string]::IsNullOrWhiteSpace($Summary)) {
            throw 'Summary is required for send.'
        }
        if ($Summary.Length -gt $MaxSummaryLength) {
            throw "Summary exceeds MaxSummaryLength ($MaxSummaryLength)."
        }

        $paths = Get-SessionPaths -DialogDirValue $dialogDirAbs -SessionValue $SessionId
        $messages = @(Get-SessionMessages -SessionPath $paths.session_path)
        $openReply = Get-OpenReplyExpectation -Messages $messages
        if ($RequiresReply -and $openReply) {
            throw "Session $SessionId already has an open reply expectation on turn $([int]$openReply.turn_id)."
        }
        if ($openReply -and -not $RequiresReply) {
            $expectedFrom = Normalize-Actor -Value ([string]$openReply.to)
            $expectedTo = Normalize-Actor -Value ([string]$openReply.from)
            $isRequesterFollowUp = $fromActor -eq (Normalize-Actor -Value ([string]$openReply.from)) -and $toActor -eq (Normalize-Actor -Value ([string]$openReply.to))
            $allowsRequesterFollowUp = $isRequesterFollowUp -and @('status_request', 'blocker_notice') -contains [string]$MessageType
            if (($fromActor -ne $expectedFrom -or $toActor -ne $expectedTo) -and -not $allowsRequesterFollowUp) {
                throw "Session $SessionId is awaiting a reply from $expectedFrom to $expectedTo on turn $([int]$openReply.turn_id)."
            }
        }

        $payload = Parse-PayloadJson -PayloadText $PayloadJson
        $turnId = Get-NextTurnId -Messages $messages
        $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        $message = [pscustomobject]@{
            session_id = [string]$SessionId
            turn_id = $turnId
            timestamp = $timestamp
            from = $fromActor
            to = $toActor
            message_type = [string]$MessageType
            intent = [string]$Intent
            correlation_id = [string]$CorrelationId
            task_id = [string]$TaskId
            summary = [string]$Summary
            payload = [pscustomobject]$payload
            requires_reply = [bool]$RequiresReply
            schema_version = $channelVersion
        }

        Append-Utf8NoBomJsonLine -PathValue $paths.session_path -Payload $message -Depth 16
        Append-Utf8NoBomJsonLine -PathValue $paths.channel_path -Payload $message -Depth 16

        $updatedMessages = @(Get-SessionMessages -SessionPath $paths.session_path)
        $sessionState = Get-SessionState -SessionIdValue $SessionId -Messages $updatedMessages -SessionPath $paths.session_path -MaxOpenMinutesValue $MaxOpenMinutes
        Write-SessionStateArtifacts -Paths $paths -SessionState $sessionState

        $remotePublish = $null
        if ($PublishRemote) {
            $remotePublish = Publish-DialogArtifactsRemote -Settings $remoteDialogSettings -Paths $paths
        }

        $result = [pscustomobject]@{
            ok = $true
            action = 'send'
            message = $message
            session_state = $sessionState
            remote = $remotePublish
        }

        if ($EmitJson) {
            $result | ConvertTo-Json -Depth 16
        }
        else {
            $result
        }
        break
    }
    'read-session' {
        Require-SessionId

        $paths = Get-SessionPaths -DialogDirValue $dialogDirAbs -SessionValue $SessionId
        $remoteRefresh = $null
        if ($RefreshFromRemote) {
            $remoteRefresh = Refresh-DialogArtifactsRemote -Settings $remoteDialogSettings -Paths $paths -IncludeSessionLog -IncludeSessionState -IncludeIndex
        }
        $messages = @(Get-SessionMessages -SessionPath $paths.session_path)
        $sessionState = Get-SessionState -SessionIdValue $SessionId -Messages $messages -SessionPath $paths.session_path -MaxOpenMinutesValue $MaxOpenMinutes
        Write-SessionStateArtifacts -Paths $paths -SessionState $sessionState

        $tailMessages = if ($Tail -gt 0 -and @($messages).Count -gt $Tail) { @($messages | Select-Object -Last $Tail) } else { @($messages) }
        $result = [pscustomobject]@{
            ok = $true
            action = 'read-session'
            session_state = $sessionState
            messages = @($tailMessages)
            remote = $remoteRefresh
        }

        if ($EmitJson) {
            $result | ConvertTo-Json -Depth 16
        }
        else {
            $result
        }
        break
    }
    'get-session-status' {
        Require-SessionId

        $paths = Get-SessionPaths -DialogDirValue $dialogDirAbs -SessionValue $SessionId
        $remoteRefresh = $null
        if ($RefreshFromRemote) {
            $remoteRefresh = Refresh-DialogArtifactsRemote -Settings $remoteDialogSettings -Paths $paths -IncludeSessionState -IncludeIndex
        }
        $messages = @(Get-SessionMessages -SessionPath $paths.session_path)
        $sessionState = Get-SessionState -SessionIdValue $SessionId -Messages $messages -SessionPath $paths.session_path -MaxOpenMinutesValue $MaxOpenMinutes
        Write-SessionStateArtifacts -Paths $paths -SessionState $sessionState

        if ($EmitJson) {
            [pscustomobject]@{
                session_state = $sessionState
                remote = $remoteRefresh
            } | ConvertTo-Json -Depth 12
        }
        else {
            [pscustomobject]@{
                session_state = $sessionState
                remote = $remoteRefresh
            }
        }
        break
    }
    'read-inbox' {
        $actorName = Normalize-Actor -Value $Actor
        $inbox = @()
        $remoteRefresh = $null
        if ($RefreshFromRemote) {
            $refreshPaths = Get-SessionPaths -DialogDirValue $dialogDirAbs -SessionValue ("inbox-{0}" -f $actorName.ToLowerInvariant())
            $remoteRefresh = Refresh-DialogArtifactsRemote -Settings $remoteDialogSettings -Paths $refreshPaths -IncludeIndex
        }

        $indexPath = Join-Path $dialogDirAbs 'MIM_TOD_DIALOG.sessions.latest.json'
        if (Test-Path -Path $indexPath) {
            try {
                $indexDoc = Get-Content -Path $indexPath -Raw | ConvertFrom-Json
                foreach ($sessionState in @($indexDoc.sessions)) {
                    $sessionIdValue = if ($sessionState.PSObject.Properties['session_id']) { [string]$sessionState.session_id } else { '' }
                    if ([string]::IsNullOrWhiteSpace($sessionIdValue)) {
                        continue
                    }

                    $refreshedState = Get-RefreshedSessionState -DialogDirValue $dialogDirAbs -SessionIdValue $sessionIdValue -MaxOpenMinutesValue $MaxOpenMinutes
                    if ($refreshedState.open_reply -and [string]::Equals([string]$refreshedState.open_reply.to, $actorName, [System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$refreshedState.status, 'awaiting_reply', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $inbox += $refreshedState
                    }
                }
            }
            catch {
                $inbox = @()
            }
        }

        if (@($inbox).Count -eq 0) {
            $sessionFiles = @(Get-ChildItem -Path $dialogDirAbs -Filter 'MIM_TOD_DIALOG.session-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
            foreach ($file in $sessionFiles) {
                $sessionIdValue = [string]($file.BaseName -replace '^MIM_TOD_DIALOG\.session-', '')
                $sessionState = Get-RefreshedSessionState -DialogDirValue $dialogDirAbs -SessionIdValue $sessionIdValue -MaxOpenMinutesValue $MaxOpenMinutes
                if ($sessionState.open_reply -and [string]::Equals([string]$sessionState.open_reply.to, $actorName, [System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$sessionState.status, 'awaiting_reply', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $inbox += $sessionState
                }
            }
        }

        $result = [pscustomobject]@{
            ok = $true
            action = 'read-inbox'
            actor = $actorName
            open_sessions = @($inbox | Sort-Object {
                if ($_.PSObject.Properties['updated_at']) { [string]$_.updated_at } else { '' }
            } -Descending)
            remote = $remoteRefresh
        }

        if ($EmitJson) {
            $result | ConvertTo-Json -Depth 14
        }
        else {
            $result
        }
        break
    }
    'close-session' {
        Require-SessionId

        $fromActor = Normalize-Actor -Value $Actor
        $toActor = Normalize-Actor -Value $PeerActor
        $paths = Get-SessionPaths -DialogDirValue $dialogDirAbs -SessionValue $SessionId
        $messages = @(Get-SessionMessages -SessionPath $paths.session_path)
        $turnId = Get-NextTurnId -Messages $messages
        $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        $summaryText = if ([string]::IsNullOrWhiteSpace($Summary)) { 'Session closed by explicit resolution notice.' } else { [string]$Summary }
        if ($summaryText.Length -gt $MaxSummaryLength) {
            throw "Summary exceeds MaxSummaryLength ($MaxSummaryLength)."
        }
        $payload = Parse-PayloadJson -PayloadText $PayloadJson
        $message = [pscustomobject]@{
            session_id = [string]$SessionId
            turn_id = $turnId
            timestamp = $timestamp
            from = $fromActor
            to = $toActor
            message_type = 'resolution_notice'
            intent = if ([string]::IsNullOrWhiteSpace($Intent)) { 'session_close' } else { [string]$Intent }
            correlation_id = [string]$CorrelationId
            task_id = [string]$TaskId
            summary = $summaryText
            payload = [pscustomobject]$payload
            requires_reply = $false
            schema_version = $channelVersion
        }

        Append-Utf8NoBomJsonLine -PathValue $paths.session_path -Payload $message -Depth 16
        Append-Utf8NoBomJsonLine -PathValue $paths.channel_path -Payload $message -Depth 16

        $updatedMessages = @(Get-SessionMessages -SessionPath $paths.session_path)
        $sessionState = Get-SessionState -SessionIdValue $SessionId -Messages $updatedMessages -SessionPath $paths.session_path -MaxOpenMinutesValue $MaxOpenMinutes
        Write-SessionStateArtifacts -Paths $paths -SessionState $sessionState

        $remotePublish = $null
        if ($PublishRemote) {
            $remotePublish = Publish-DialogArtifactsRemote -Settings $remoteDialogSettings -Paths $paths
        }

        $result = [pscustomobject]@{
            ok = $true
            action = 'close-session'
            message = $message
            session_state = $sessionState
            remote = $remotePublish
        }

        if ($EmitJson) {
            $result | ConvertTo-Json -Depth 16
        }
        else {
            $result
        }
        break
    }
}
