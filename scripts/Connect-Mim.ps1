param(
    [string]$EnvFile = ".env",
    [string]$Command
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match "^\s*$Name\s*="
    } | Select-Object -First 1

    if (-not $line) {
        return $null
    }

    return ($line -replace "^\s*$Name\s*=\s*", "").Trim()
}

function Resolve-PreferredSshHost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName
    )

    # Prefer IPv4 to avoid slow/failed IPv6 attempts causing Posh-SSH timeouts.
    try {
        $v4 = @(Resolve-DnsName -Name $HostName -Type A -ErrorAction Stop | Select-Object -ExpandProperty IPAddress)
        if (@($v4).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$v4[0])) {
            return [string]$v4[0]
        }
    }
    catch {
    }

    return $HostName
}

function Ensure-PoshSshModulePath {
    $candidateRoots = @(
        (Join-Path $HOME 'OneDrive\Documents\WindowsPowerShell\Modules'),
        (Join-Path $HOME 'Documents\WindowsPowerShell\Modules'),
        (Join-Path $HOME 'OneDrive\Documents\PowerShell\Modules'),
        (Join-Path $HOME 'Documents\PowerShell\Modules')
    )

    foreach ($root in $candidateRoots) {
        if ((Test-Path -Path (Join-Path $root 'Posh-SSH')) -and ($env:PSModulePath -notlike "*$root*")) {
            $env:PSModulePath = $root + [System.IO.Path]::PathSeparator + $env:PSModulePath
        }
    }
}

if (-not (Test-Path -Path $EnvFile)) {
    throw "Missing $EnvFile. Copy .env.example to .env and set MIM_SSH_PASSWORD."
}

$hostName = Get-DotEnvValue -Path $EnvFile -Name "MIM_SSH_HOST"
$userName = Get-DotEnvValue -Path $EnvFile -Name "MIM_SSH_USER"
$port = Get-DotEnvValue -Path $EnvFile -Name "MIM_SSH_PORT"
$password = Get-DotEnvValue -Path $EnvFile -Name "MIM_SSH_PASSWORD"

if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = "mim" }
if ([string]::IsNullOrWhiteSpace($userName)) { $userName = "testpilot" }
if ([string]::IsNullOrWhiteSpace($port)) { $port = "22" }

if ([string]::IsNullOrWhiteSpace($password) -or $password -eq "CHANGE_ME") {
    throw "Set MIM_SSH_PASSWORD in $EnvFile before connecting."
}

Ensure-PoshSshModulePath
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    throw "Posh-SSH is not installed. Run: Install-Module -Name Posh-SSH -Scope CurrentUser"
}

Import-Module Posh-SSH -ErrorAction Stop

$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)

$connectHost = Resolve-PreferredSshHost -HostName $hostName

$session = New-SSHSession -ComputerName $connectHost -Port ([int]$port) -Credential $credential -AcceptKey -ConnectionTimeout 30000

try {
    Write-Host "Connected to $userName@${hostName}:$port" -ForegroundColor Green
    if ($connectHost -ne $hostName) {
        Write-Host "Using IPv4 endpoint $connectHost for reliable SSH connect." -ForegroundColor DarkGray
    }
    if ($PSBoundParameters.ContainsKey("Command") -and -not [string]::IsNullOrWhiteSpace($Command)) {
        $result = Invoke-SSHCommand -SessionId $session.SessionId -Command $Command -TimeOut 120
        if ($result.Output) { $result.Output }
        if ($result.ExitStatus -ne 0) {
            if ($result.Error) { $result.Error | Write-Error }
            throw "Remote command failed with exit status $($result.ExitStatus)."
        }
        if ($result.Error) { $result.Error }
        return
    }

    Write-Host "Interactive mode: enter remote commands, type 'exit' to disconnect." -ForegroundColor Green
    while ($true) {
        $remoteCommand = Read-Host "mim"
        if ([string]::IsNullOrWhiteSpace($remoteCommand)) { continue }
        if ($remoteCommand.Trim().ToLowerInvariant() -in @("exit", "quit")) { break }

        if (Get-Command -Name Invoke-SSHCommandStream -ErrorAction SilentlyContinue) {
            $result = Invoke-SSHCommandStream -SessionId $session.SessionId -Command $remoteCommand -TimeOut 120
            if ($result) { $result }
            continue
        }
        $result = Invoke-SSHCommand -SessionId $session.SessionId -Command $remoteCommand -TimeOut 120
        if ($result.Output) { $result.Output }
        if ($result.ExitStatus -ne 0) {
            if ($result.Error) { $result.Error | Write-Error }
            Write-Warning "Remote command failed with exit status $($result.ExitStatus)."
        }
        elseif ($result.Error) { $result.Error }
    }
}
finally {
    if ($session) {
        Remove-SSHSession -SessionId $session.SessionId | Out-Null
    }
}
