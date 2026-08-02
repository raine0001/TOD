param(
    [string]$EnvFile = ".env"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$remoteRoot = "/home/testpilot/mim"
$remoteTarget = "$remoteRoot/core/routers/observatory.py"
$expectedHash = "727f1ff22639b7657dc94b7f5efac823ab8ae378b2cb4eb7135c353ef71ae693"

function Get-EnvValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $line = Get-Content -LiteralPath $envPath | Where-Object {
        $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))
    } | Select-Object -First 1
    if (-not $line) { return "" }
    return (($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "").Trim().Trim('"'))
}

function Invoke-RemoteChecked {
    param(
        [Parameter(Mandatory = $true)][int]$SessionId,
        [Parameter(Mandatory = $true)][string]$Command,
        [int]$TimeoutSeconds = 120
    )
    $result = Invoke-SSHCommand -SessionId $SessionId -Command $Command -TimeOut $TimeoutSeconds
    if ($result.ExitStatus -ne 0) {
        throw "Remote command failed $($result.ExitStatus): $($result.Error -join '; ')"
    }
    return $result
}

function Send-RemoteFileB64 {
    param(
        [Parameter(Mandatory = $true)][int]$SessionId,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath
    )
    $fullPath = (Resolve-Path (Join-Path $repoRoot $LocalPath)).Path
    $encoded = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fullPath))
    $uploadId = [System.Guid]::NewGuid().ToString('N')
    $remoteB64 = "/tmp/codex_ent_observatory_$uploadId.b64"
    $remoteTmp = "$RemotePath.codex-$uploadId.tmp"
    Invoke-RemoteChecked -SessionId $SessionId -Command "rm -f '$remoteB64' '$remoteTmp'" | Out-Null
    for ($offset = 0; $offset -lt $encoded.Length; $offset += 12000) {
        $chunk = $encoded.Substring($offset, [Math]::Min(12000, $encoded.Length - $offset))
        Invoke-RemoteChecked -SessionId $SessionId -Command "printf '%s' '$chunk' >> '$remoteB64'" | Out-Null
    }
    Invoke-RemoteChecked -SessionId $SessionId -Command "base64 -d '$remoteB64' > '$remoteTmp' && mv '$remoteTmp' '$RemotePath' && rm -f '$remoteB64'" | Out-Null
}

if (-not (Test-Path -LiteralPath $envPath)) { throw "Missing environment file: $envPath" }
Import-Module Posh-SSH -ErrorAction Stop
$securePassword = ConvertTo-SecureString (Get-EnvValue "MIM_SSH_PASSWORD") -AsPlainText -Force
$credential = [pscredential]::new((Get-EnvValue "MIM_SSH_USER"), $securePassword)
$hostName = Get-EnvValue "MIM_SSH_HOST"
$portText = Get-EnvValue "MIM_SSH_PORT"
$port = if ($portText) { [int]$portText } else { 22 }
$session = New-SSHSession -ComputerName $hostName -Port $port -Credential $credential -AcceptKey -Force

try {
    $preflight = Invoke-RemoteChecked -SessionId $session.SessionId -Command "sha256sum '$remoteTarget' | awk '{print `$1}'"
    $actualHash = [string]($preflight.Output | Select-Object -First 1)
    if ($actualHash.Trim() -ne $expectedHash) {
        throw "Guarded deployment stopped: expected $expectedHash but found $($actualHash.Trim())"
    }

    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $backupPath = "$remoteTarget.bak.enterprise-discovery-conversation.$timestamp"
    Invoke-RemoteChecked -SessionId $session.SessionId -Command "cp '$remoteTarget' '$backupPath'" | Out-Null
    Send-RemoteFileB64 -SessionId $session.SessionId -LocalPath "tmp_remote_mim/core/routers/observatory.py" -RemotePath $remoteTarget
    Send-RemoteFileB64 -SessionId $session.SessionId -LocalPath "runtime_remote_training/remote_scripts/validate_enterprise_discovery_observatory_v1.py" -RemotePath "$remoteRoot/scripts/validate_enterprise_discovery_observatory_v1.py"
    Send-RemoteFileB64 -SessionId $session.SessionId -LocalPath "runtime_remote_training/remote_scripts/validate_enterprise_public_private_gap_v1.py" -RemotePath "$remoteRoot/scripts/validate_enterprise_public_private_gap_v1.py"

    $validateCommand = "cd '$remoteRoot' && .venv/bin/python -m py_compile core/routers/observatory.py && PYTHONPATH='$remoteRoot' .venv/bin/python scripts/validate_enterprise_discovery_observatory_v1.py"
    $validation = Invoke-RemoteChecked -SessionId $session.SessionId -Command $validateCommand
    $validation.Output

    $restart = Invoke-RemoteChecked -SessionId $session.SessionId -Command "systemctl --user restart mim-mobile-web.service mim-training-web.service && systemctl --user is-active mim-mobile-web.service mim-training-web.service"
    $restart.Output

    $gapValidation = Invoke-RemoteChecked -SessionId $session.SessionId -Command "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_enterprise_public_private_gap_v1.py" -TimeoutSeconds 180
    $gapValidation.Output

    $postflight = Invoke-RemoteChecked -SessionId $session.SessionId -Command "sha256sum '$remoteTarget'"
    Write-Output "Backup: $backupPath"
    $postflight.Output
}
finally {
    if ($session) { Remove-SSHSession -SessionId $session.SessionId | Out-Null }
}
