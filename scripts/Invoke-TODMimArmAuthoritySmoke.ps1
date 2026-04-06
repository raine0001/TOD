param(
    [string]$SharedStateSyncScriptPath = "scripts/Invoke-TODSharedStateSync.ps1",
    [string]$DotEnvPath = ".env",
    [string]$OutputPath = "shared_state/TOD_MIM_ARM_AUTHORITY_SMOKE.latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Get-DotEnvValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }
    if (-not (Test-Path -Path $Path)) {
        return ""
    }

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace([string]$line)) {
        return ""
    }

    return ([string]($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "")).Trim()
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

    return ""
}

function Resolve-SshHostAlias {
    param([string]$RemoteHost)

    if ([string]::IsNullOrWhiteSpace($RemoteHost)) {
        return ""
    }

    if ($RemoteHost -match '^\d{1,3}(?:\.\d{1,3}){3}$' -or $RemoteHost -match '\.') {
        return $RemoteHost
    }

    $sshConfigPath = Join-Path $HOME ".ssh/config"
    if (-not (Test-Path -Path $sshConfigPath)) {
        return $RemoteHost
    }

    $inHostBlock = $false
    $matchedHost = $false
    $resolvedHostName = ""

    foreach ($rawLine in (Get-Content -Path $sshConfigPath)) {
        $line = [string]$rawLine
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith('#')) {
            continue
        }

        if ($trim -match '^(?i)Host\s+(.+)$') {
            $inHostBlock = $true
            $matchedHost = $false
            $resolvedHostName = ""

            $hostTokens = @($matches[1] -split '\s+')
            foreach ($token in $hostTokens) {
                if ([string]::Equals([string]$token, $RemoteHost, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchedHost = $true
                    break
                }
            }
            continue
        }

        if ($inHostBlock -and $matchedHost -and $trim -match '^(?i)HostName\s+(.+)$') {
            $resolvedHostName = [string]$matches[1]
            break
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedHostName)) {
        return $resolvedHostName
    }

    return $RemoteHost
}

function New-MimSshConnections {
    param(
        [Parameter(Mandatory = $true)][string]$HostAlias,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password
    )

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        throw "Posh-SSH is not installed. Install-Module -Name Posh-SSH -Scope CurrentUser"
    }

    Import-Module Posh-SSH -ErrorAction Stop | Out-Null

    $resolvedHost = Resolve-SshHostAlias -RemoteHost $HostAlias
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($UserName, $securePassword)

    $sshSession = New-SSHSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000
    $sftpSession = New-SFTPSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000

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

$syncAbs = Get-LocalPath -PathValue $SharedStateSyncScriptPath
$dotEnvAbs = Get-LocalPath -PathValue $DotEnvPath
$outputAbs = Get-LocalPath -PathValue $OutputPath

if (-not (Test-Path -Path $syncAbs)) {
    throw "Shared-state sync script not found: $syncAbs"
}

if (-not (Test-Path -Path $dotEnvAbs)) {
    throw "Dotenv file not found: $dotEnvAbs"
}

$syncRaw = & $syncAbs -PublishTodStatusToMimArm -DotEnvPath $dotEnvAbs
$syncResult = if ($syncRaw -is [string]) { $syncRaw | ConvertFrom-Json } else { $syncRaw }

$integrationStatusPath = Join-Path $repoRoot "shared_state/integration_status.json"
$receiptPath = Join-Path $repoRoot "shared_state/TOD_MIM_ARM_STATUS_UPLOAD_RECEIPT.latest.json"

$integration = Get-Content -Path $integrationStatusPath -Raw | ConvertFrom-Json
$receipt = Get-Content -Path $receiptPath -Raw | ConvertFrom-Json

$resolvedHost = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_HOST" -DotEnvPathValue $dotEnvAbs
if ([string]::IsNullOrWhiteSpace($resolvedHost)) {
    $resolvedHost = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_HOST" -DotEnvPathValue $dotEnvAbs
}

$resolvedUser = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_USER" -DotEnvPathValue $dotEnvAbs
if ([string]::IsNullOrWhiteSpace($resolvedUser)) {
    $resolvedUser = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_USER" -DotEnvPathValue $dotEnvAbs
}
if ([string]::IsNullOrWhiteSpace($resolvedUser)) {
    $resolvedUser = "testpilot"
}

$resolvedPortText = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_PORT" -DotEnvPathValue $dotEnvAbs
if ([string]::IsNullOrWhiteSpace($resolvedPortText)) {
    $resolvedPortText = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_PORT" -DotEnvPathValue $dotEnvAbs
}

$resolvedPort = 22
if (-not [string]::IsNullOrWhiteSpace($resolvedPortText)) {
    $parsedPort = 0
    if ([int]::TryParse($resolvedPortText, [ref]$parsedPort) -and $parsedPort -gt 0) {
        $resolvedPort = $parsedPort
    }
}

$resolvedPassword = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_HOST_PASS" -DotEnvPathValue $dotEnvAbs
if ([string]::IsNullOrWhiteSpace($resolvedPassword)) {
    $resolvedPassword = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_PASSWORD" -DotEnvPathValue $dotEnvAbs
}

$remoteSummaryPath = if ($integration.tod_status_publish -and $integration.tod_status_publish.PSObject.Properties['remote_summary_path']) {
    [string]$integration.tod_status_publish.remote_summary_path
}
else {
    ""
}

$remoteDoc = $null
$connections = $null
$downloadedSummaryPath = ""

try {
    if (-not [string]::IsNullOrWhiteSpace($remoteSummaryPath) -and -not [string]::IsNullOrWhiteSpace($resolvedHost) -and -not [string]::IsNullOrWhiteSpace($resolvedPassword)) {
        $connections = New-MimSshConnections -HostAlias $resolvedHost -UserName $resolvedUser -Port $resolvedPort -Password $resolvedPassword

        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "tod-mim-arm-authority-smoke"
        if (-not (Test-Path -Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }

        Get-SFTPItem -SessionId ([int]$connections.sftp.SessionId) -Path $remoteSummaryPath -Destination $tempDir -Force -ErrorAction Stop | Out-Null
        $downloadedSummaryPath = Join-Path $tempDir (Split-Path -Leaf $remoteSummaryPath)

        if (Test-Path -Path $downloadedSummaryPath) {
            $remoteDoc = Get-Content -Path $downloadedSummaryPath -Raw | ConvertFrom-Json
        }
    }
}
finally {
    Close-MimSshConnections -Connections $connections
}

$pathsMatch = $false
if ($null -ne $remoteDoc -and $remoteDoc.PSObject.Properties['input_path']) {
    $pathsMatch = [string]$remoteDoc.input_path -eq [string]$integration.tod_status_publish.remote_primary_path
}

$authorityUploaded = ($null -ne $remoteDoc -and $remoteDoc.authority -and [string]$remoteDoc.authority.status -eq 'uploaded')
$alignmentOk = ($null -ne $remoteDoc -and $remoteDoc.objective -and [bool]$remoteDoc.objective.aligned)
$consumerExecuted = [string]$integration.tod_status_publish.consumer_status -eq 'executed'

$result = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-mim-arm-authority-smoke-v1"
    sync = [pscustomobject]@{
        attempted = $true
        ok = ($null -ne $syncResult)
        integration_status_path = $integrationStatusPath
        receipt_path = $receiptPath
    }
    local_publish = [pscustomobject]@{
        status = [string]$integration.tod_status_publish.status
        compatible = [bool]$integration.compatible
        aligned = [bool]$integration.objective_alignment.aligned
        consumer_status = [string]$integration.tod_status_publish.consumer_status
        remote_summary_path = [string]$integration.tod_status_publish.remote_summary_path
        remote_consumer_script_path = [string]$integration.tod_status_publish.remote_consumer_script_path
    }
    remote_summary = [pscustomobject]@{
        available = ($null -ne $remoteDoc)
        path = $remoteSummaryPath
        downloaded_path = $downloadedSummaryPath
        authority_status = if ($remoteDoc -and $remoteDoc.authority) { [string]$remoteDoc.authority.status } else { "" }
        authority_enabled = if ($remoteDoc -and $remoteDoc.authority) { [bool]$remoteDoc.authority.enabled } else { $false }
        authority_compatible = if ($remoteDoc -and $remoteDoc.authority) { [bool]$remoteDoc.authority.compatible } else { $false }
        uploaded_at = if ($remoteDoc -and $remoteDoc.authority) { [string]$remoteDoc.authority.uploaded_at } else { "" }
        objective_tod_current = if ($remoteDoc -and $remoteDoc.objective) { [string]$remoteDoc.objective.tod_current } else { "" }
        objective_mim_current = if ($remoteDoc -and $remoteDoc.objective) { [string]$remoteDoc.objective.mim_current } else { "" }
        objective_aligned = if ($remoteDoc -and $remoteDoc.objective) { [bool]$remoteDoc.objective.aligned } else { $false }
        alignment_source = if ($remoteDoc -and $remoteDoc.objective) { [string]$remoteDoc.objective.alignment_source } else { "" }
        live_request_id = if ($remoteDoc -and $remoteDoc.objective) { [string]$remoteDoc.objective.live_request_id } else { "" }
    }
    validation = [pscustomobject]@{
        paths_match = $pathsMatch
        authority_uploaded = $authorityUploaded
        alignment_ok = $alignmentOk
        consumer_executed = $consumerExecuted
        passed = [bool]($pathsMatch -and $authorityUploaded -and $alignmentOk -and $consumerExecuted)
    }
}

$outputDir = Split-Path -Parent $outputAbs
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$result | ConvertTo-Json -Depth 20 | Set-Content -Path $outputAbs
$result | ConvertTo-Json -Depth 20 | Write-Output