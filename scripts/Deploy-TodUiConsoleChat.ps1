param(
    [string]$LocalRouterPath = "e:\TOD\tmp_remote_mim\core\routers\tod_ui.py",
    [string]$RemoteRouterPath = "/home/testpilot/mim/core/routers/tod_ui.py",
    [string]$LocalMimUiPath = "e:\TOD\tmp_remote_mim\core\routers\mim_ui.py",
    [string]$RemoteMimUiPath = "/home/testpilot/mim/core/routers/mim_ui.py",
    [string]$LocalExecutionLoopPath = "e:\TOD\tmp_remote_mim\core\tod_execution_loop.py",
    [string]$RemoteExecutionLoopPath = "/home/testpilot/mim/core/tod_execution_loop.py",
    [string]$LocalAppPath = "e:\TOD\tmp_remote_mim\core\app.py",
    [string]$RemoteAppPath = "/home/testpilot/mim/core/app.py",
    [string]$LocalSharedStateSyncScriptPath = "e:\TOD\scripts\Invoke-TODSharedStateSync.ps1",
    [string]$RemoteSharedStateSyncScriptPath = "/home/testpilot/mim/scripts/Invoke-TODSharedStateSync.ps1",
    [string]$LocalSharedTruthRecouplingScriptPath = "e:\TOD\scripts\Invoke-TODCanonicalLatestArtifactRecoupling.ps1",
    [string]$RemoteSharedTruthRecouplingScriptPath = "/home/testpilot/mim/scripts/Invoke-TODCanonicalLatestArtifactRecoupling.ps1",
    [string]$LocalSharedTruthReconcilePythonPath = "e:\TOD\scripts\reconcile_tod_mim_shared_truth.py",
    [string]$RemoteSharedTruthReconcilePythonPath = "/home/testpilot/mim/scripts/reconcile_tod_mim_shared_truth.py",
    [string]$EnvFile = ".env"
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

    return ($line -replace "^\s*$Name\s*=\s*", '').Trim()
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

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$hostName = Get-DotEnvValue -Path $EnvFile -Name 'MIM_SSH_HOST'
$userName = Get-DotEnvValue -Path $EnvFile -Name 'MIM_SSH_USER'
$port = Get-DotEnvValue -Path $EnvFile -Name 'MIM_SSH_PORT'
$password = Get-DotEnvValue -Path $EnvFile -Name 'MIM_SSH_PASSWORD'

if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = 'mim' }
if ([string]::IsNullOrWhiteSpace($userName)) { $userName = 'testpilot' }
if ([string]::IsNullOrWhiteSpace($port)) { $port = '22' }

Import-Module Posh-SSH -ErrorAction Stop

$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)
$connectHost = Resolve-PreferredSshHost -HostName $hostName

$sftp = New-SFTPSession -ComputerName $connectHost -Port ([int]$port) -Credential $credential -AcceptKey
try {
    $remoteDirectory = ($RemoteRouterPath -replace '/[^/]+$', '').TrimEnd('/')
    Set-SFTPItem -SessionId $sftp.SessionId -Path $LocalRouterPath -Destination $remoteDirectory -Force
    $remoteMimUiDirectory = ($RemoteMimUiPath -replace '/[^/]+$', '').TrimEnd('/')
    Set-SFTPItem -SessionId $sftp.SessionId -Path $LocalMimUiPath -Destination $remoteMimUiDirectory -Force
    $remoteExecutionLoopDirectory = ($RemoteExecutionLoopPath -replace '/[^/]+$', '').TrimEnd('/')
    Set-SFTPItem -SessionId $sftp.SessionId -Path $LocalExecutionLoopPath -Destination $remoteExecutionLoopDirectory -Force
    $remoteAppDirectory = ($RemoteAppPath -replace '/[^/]+$', '').TrimEnd('/')
    Set-SFTPItem -SessionId $sftp.SessionId -Path $LocalAppPath -Destination $remoteAppDirectory -Force
    $remoteSharedStateSyncDirectory = ($RemoteSharedStateSyncScriptPath -replace '/[^/]+$', '').TrimEnd('/')
    Set-SFTPItem -SessionId $sftp.SessionId -Path $LocalSharedStateSyncScriptPath -Destination $remoteSharedStateSyncDirectory -Force
    $remoteSharedTruthRecouplingDirectory = ($RemoteSharedTruthRecouplingScriptPath -replace '/[^/]+$', '').TrimEnd('/')
    Set-SFTPItem -SessionId $sftp.SessionId -Path $LocalSharedTruthRecouplingScriptPath -Destination $remoteSharedTruthRecouplingDirectory -Force
    $remoteSharedTruthReconcilePythonDirectory = ($RemoteSharedTruthReconcilePythonPath -replace '/[^/]+$', '').TrimEnd('/')
    Set-SFTPItem -SessionId $sftp.SessionId -Path $LocalSharedTruthReconcilePythonPath -Destination $remoteSharedTruthReconcilePythonDirectory -Force
}
finally {
    if ($sftp) {
        Remove-SFTPSession -SessionId $sftp.SessionId | Out-Null
    }
}

$verifyCommand = @(
    'systemctl --user restart mim-mobile-web.service',
    'systemctl --user is-active mim-mobile-web.service',
    'ls -1 /home/testpilot/mim/scripts/Invoke-TODSharedStateSync.ps1 /home/testpilot/mim/scripts/Invoke-TODCanonicalLatestArtifactRecoupling.ps1 /home/testpilot/mim/scripts/reconcile_tod_mim_shared_truth.py',
    'grep -n -- "Permissions-Policy\|camera=(self)\|microphone=(self)" /home/testpilot/mim/core/app.py | head -n 20',
    'grep -n -- "build_execution_loop_contract_artifacts\|contract_version\|tod-execution-loop-v1" /home/testpilot/mim/core/tod_execution_loop.py | head -n 20',
    'grep -n -- "/tod/ui/chat/state\|/tod/ui/chat/message\|Copilot handoff summary\|Drift summary:" /home/testpilot/mim/core/routers/tod_ui.py | head -n 40',
    'grep -n -- "bridge_request_confirmed\|TOD has confirmed execution on the bridge request lane" /home/testpilot/mim/core/routers/mim_ui.py | head -n 20'
) -join '; '

& (Join-Path $repoRoot 'scripts/Connect-Mim.ps1') -Command $verifyCommand