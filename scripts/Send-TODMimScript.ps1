param(
    [Parameter(Mandatory = $true)]
    [string]$LocalPath,

    [string]$RemotePath = "",
    [string]$RemoteRoot = "",
    [string]$EnvFile = ".env",
    [switch]$MakeExecutable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $line = Get-Content -Path $Path | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -First 1
    if (-not $line) {
        return $null
    }

    return ($line -replace "^\s*$Name\s*=\s*", '').Trim().Trim('"').Trim("'")
}

function Resolve-PreferredSshHost {
    param([Parameter(Mandatory = $true)][string]$HostName)

    try {
        $ipv4 = @(Resolve-DnsName -Name $HostName -Type A -ErrorAction Stop | Select-Object -ExpandProperty IPAddress)
        if (@($ipv4).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$ipv4[0])) {
            return [string]$ipv4[0]
        }
    }
    catch {
    }

    return $HostName
}

function Quote-RemoteDouble {
    param([Parameter(Mandatory = $true)][string]$Value)

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace('$', '\$').Replace('`', '\`')
    return '"' + $escaped + '"'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$localFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $LocalPath))
if (-not (Test-Path -Path $localFullPath -PathType Leaf)) {
    throw "Local file not found: $localFullPath"
}

$envFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $EnvFile))
if (-not (Test-Path -Path $envFullPath -PathType Leaf)) {
    throw "Env file not found: $envFullPath"
}

$hostName = Get-DotEnvValue -Path $envFullPath -Name 'MIM_SSH_HOST'
$userName = Get-DotEnvValue -Path $envFullPath -Name 'MIM_SSH_USER'
$port = Get-DotEnvValue -Path $envFullPath -Name 'MIM_SSH_PORT'
$password = Get-DotEnvValue -Path $envFullPath -Name 'MIM_SSH_PASSWORD'

if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = 'mim' }
if ([string]::IsNullOrWhiteSpace($userName)) { $userName = 'testpilot' }
if ([string]::IsNullOrWhiteSpace($port)) { $port = '22' }
if ([string]::IsNullOrWhiteSpace($password) -or $password -eq 'CHANGE_ME') {
    throw "Set MIM_SSH_PASSWORD in $envFullPath before sending files."
}

if ([string]::IsNullOrWhiteSpace($RemoteRoot)) {
    $RemoteRoot = Get-DotEnvValue -Path $envFullPath -Name 'MIM_ARM_SSH_TOOLS_ROOT'
}
if ([string]::IsNullOrWhiteSpace($RemoteRoot)) {
    $RemoteRoot = '/home/testpilot/mim_arm/runtime/tools'
}

$remoteFullPath = $RemotePath
if ([string]::IsNullOrWhiteSpace($remoteFullPath)) {
    $remoteFullPath = ('{0}/{1}' -f $RemoteRoot.TrimEnd('/'), [System.IO.Path]::GetFileName($localFullPath))
}

$remoteDirectory = ($remoteFullPath -replace '/[^/]+$', '').TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($remoteDirectory)) {
    throw "Unable to determine remote directory from path: $remoteFullPath"
}

Import-Module Posh-SSH -ErrorAction Stop

$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)
$connectHost = Resolve-PreferredSshHost -HostName $hostName

$ssh = $null
$sftp = $null
try {
    $ssh = New-SSHSession -ComputerName $connectHost -Port ([int]$port) -Credential $credential -AcceptKey -ConnectionTimeout 30000
    $sftp = New-SFTPSession -ComputerName $connectHost -Port ([int]$port) -Credential $credential -AcceptKey -ConnectionTimeout 30000

    $mkdirCommand = 'mkdir -p ' + (Quote-RemoteDouble -Value $remoteDirectory)
    $mkdirResult = Invoke-SSHCommand -SessionId ([int]$ssh.SessionId) -Command $mkdirCommand -TimeOut 30
    if ($mkdirResult.ExitStatus -ne 0) {
        throw "Remote directory create failed: $remoteDirectory"
    }

    Set-SFTPItem -SessionId ([int]$sftp.SessionId) -Path $localFullPath -Destination $remoteDirectory -Force -ErrorAction Stop | Out-Null

    if ($MakeExecutable.IsPresent) {
        $chmodCommand = 'chmod +x ' + (Quote-RemoteDouble -Value $remoteFullPath)
        $chmodResult = Invoke-SSHCommand -SessionId ([int]$ssh.SessionId) -Command $chmodCommand -TimeOut 30
        if ($chmodResult.ExitStatus -ne 0) {
            throw "Remote chmod failed: $remoteFullPath"
        }
    }

    $verifyTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('tod-mim-verify-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $verifyTempDir -Force | Out-Null
    try {
        Get-SFTPItem -SessionId ([int]$sftp.SessionId) -Path $remoteFullPath -Destination $verifyTempDir -Force -ErrorAction Stop | Out-Null
        $downloadedPath = Join-Path $verifyTempDir ([System.IO.Path]::GetFileName($remoteFullPath))
        if (-not (Test-Path -Path $downloadedPath -PathType Leaf)) {
            throw "Remote verification download missing: $remoteFullPath"
        }

        $localHash = (Get-FileHash -Path $localFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $downloadedHash = (Get-FileHash -Path $downloadedPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not [string]::Equals($localHash, $downloadedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Remote verification hash mismatch: $remoteFullPath"
        }
    }
    finally {
        if (Test-Path -Path $verifyTempDir) {
            Remove-Item -Path $verifyTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    [pscustomobject]@{
        host = $hostName
        resolved_host = $connectHost
        user = $userName
        port = [int]$port
        local_path = $localFullPath
        remote_path = $remoteFullPath
        make_executable = [bool]$MakeExecutable.IsPresent
        verification = [pscustomobject]@{
            method = 'sftp_roundtrip_sha256'
            sha256 = $localHash
        }
    } | ConvertTo-Json -Depth 4
}
finally {
    if ($sftp) {
        Remove-SFTPSession -SessionId ([int]$sftp.SessionId) | Out-Null
    }
    if ($ssh) {
        Remove-SSHSession -SessionId ([int]$ssh.SessionId) | Out-Null
    }
}