param([string]$EnvFile = ".env")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$remoteRoot = "/home/testpilot/mim"
$remoteTarget = "$remoteRoot/core/routers/project_portal.py"
$expectedHash = "95754a42499a4fe77fe7ced3927a31b0d2cbf39099b606b11cd2d97e08bcb9b0"

function Get-EnvValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $line = Get-Content -LiteralPath $envPath | Where-Object { $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name)) } | Select-Object -First 1
    if (-not $line) { return "" }
    return (($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "").Trim().Trim('"'))
}

function Invoke-RemoteChecked {
    param([int]$SessionId, [string]$Command, [int]$TimeoutSeconds = 120)
    $result = Invoke-SSHCommand -SessionId $SessionId -Command $Command -TimeOut $TimeoutSeconds
    if ($result.ExitStatus -ne 0) { throw "Remote command failed $($result.ExitStatus): $($result.Error -join '; ')" }
    return $result
}

function Send-RemoteFileB64 {
    param([int]$SessionId, [string]$LocalPath, [string]$RemotePath)
    $fullPath = (Resolve-Path (Join-Path $repoRoot $LocalPath)).Path
    $encoded = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fullPath))
    $uploadId = [System.Guid]::NewGuid().ToString('N')
    $remoteB64 = "/tmp/codex_ent_demo_$uploadId.b64"
    $remoteTmp = "$RemotePath.codex-$uploadId.tmp"
    Invoke-RemoteChecked $SessionId "rm -f '$remoteB64' '$remoteTmp'" | Out-Null
    for ($offset = 0; $offset -lt $encoded.Length; $offset += 12000) {
        $chunk = $encoded.Substring($offset, [Math]::Min(12000, $encoded.Length - $offset))
        Invoke-RemoteChecked $SessionId "printf '%s' '$chunk' >> '$remoteB64'" | Out-Null
    }
    Invoke-RemoteChecked $SessionId "base64 -d '$remoteB64' > '$remoteTmp' && mv '$remoteTmp' '$RemotePath' && rm -f '$remoteB64'" | Out-Null
}

Import-Module Posh-SSH -ErrorAction Stop
$securePassword = ConvertTo-SecureString (Get-EnvValue "MIM_SSH_PASSWORD") -AsPlainText -Force
$credential = [pscredential]::new((Get-EnvValue "MIM_SSH_USER"), $securePassword)
$portText = Get-EnvValue "MIM_SSH_PORT"
$port = if ($portText) { [int]$portText } else { 22 }
$session = New-SSHSession -ComputerName (Get-EnvValue "MIM_SSH_HOST") -Port $port -Credential $credential -AcceptKey -Force
try {
    $preflight = Invoke-RemoteChecked $session.SessionId "sha256sum '$remoteTarget' | awk '{print `$1}'"
    $actualHash = ([string]($preflight.Output | Select-Object -First 1)).Trim()
    if ($actualHash -ne $expectedHash) { throw "Guarded deployment stopped: expected $expectedHash but found $actualHash" }
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $backupPath = "$remoteTarget.bak.enterprise-discovery-demo.$timestamp"
    Invoke-RemoteChecked $session.SessionId "cp '$remoteTarget' '$backupPath'" | Out-Null
    Send-RemoteFileB64 $session.SessionId "tmp_remote_mim/core/routers/project_portal.py" $remoteTarget
    Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_enterprise_discovery_demo_v1.py" "$remoteRoot/scripts/validate_enterprise_discovery_demo_v1.py"
    Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_enterprise_registration_simplification_v1.py" "$remoteRoot/scripts/validate_enterprise_registration_simplification_v1.py"
    Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_ent_unified_auth_routing_v1.py" "$remoteRoot/scripts/validate_ent_unified_auth_routing_v1.py"
    Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_ent_auth_recovery_v1.py" "$remoteRoot/scripts/validate_ent_auth_recovery_v1.py"
    $validation = Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python -m py_compile core/routers/project_portal.py && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_enterprise_discovery_demo_v1.py" 180
    $validation.Output
    $restart = Invoke-RemoteChecked $session.SessionId "systemctl --user restart mim-mobile-web.service mim-training-web.service && systemctl --user is-active mim-mobile-web.service mim-training-web.service"
    $restart.Output
    $registrationValidation = Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_enterprise_registration_simplification_v1.py" 180
    $registrationValidation.Output
    $unifiedAuthValidation = Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_ent_unified_auth_routing_v1.py" 180
    $unifiedAuthValidation.Output
    $authRecoveryValidation = Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_ent_auth_recovery_v1.py" 180
    $authRecoveryValidation.Output
    Write-Output "Backup: $backupPath"
    (Invoke-RemoteChecked $session.SessionId "sha256sum '$remoteTarget'").Output
}
finally {
    if ($session) { Remove-SSHSession -SessionId $session.SessionId | Out-Null }
}
