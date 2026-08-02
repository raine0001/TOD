param([string]$EnvFile = ".env")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$remoteRoot = "/home/testpilot/mim"
$targets = @(
    @{ Local = "tmp_remote_mim/core/enterprise_service.py"; Remote = "$remoteRoot/core/enterprise_service.py"; Expected = "8193a250534d9828fe892b848d29d4f2ab8ba0686aa59d456836fb30429a7d1e" },
    @{ Local = "tmp_remote_mim/core/routers/enterprises.py"; Remote = "$remoteRoot/core/routers/enterprises.py"; Expected = "298000641fe0734869702ed78c6e4fdf91b17e30f8b4651debfeb3427b501d27" },
    @{ Local = "tmp_remote_mim/core/routers/observatory.py"; Remote = "$remoteRoot/core/routers/observatory.py"; Expected = "264ec527c80b79b40c66a6bdfefa209473fa25437a26990cbe254d5d81908366" }
)

function Get-EnvValue {
    param([string]$Name)
    $line = Get-Content -LiteralPath $envPath | Where-Object { $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name)) } | Select-Object -First 1
    if (-not $line) { return "" }
    return (($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "").Trim().Trim('"'))
}
function Invoke-RemoteChecked {
    param([int]$SessionId, [string]$Command, [int]$TimeoutSeconds = 180)
    $result = Invoke-SSHCommand -SessionId $SessionId -Command $Command -TimeOut $TimeoutSeconds
    if ($result.ExitStatus -ne 0) { throw "Remote command failed $($result.ExitStatus): $($result.Error -join '; ')" }
    return $result
}
function Send-RemoteFileB64 {
    param([int]$SessionId, [string]$LocalPath, [string]$RemotePath)
    $fullPath = (Resolve-Path (Join-Path $repoRoot $LocalPath)).Path
    $encoded = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fullPath))
    $uploadId = [System.Guid]::NewGuid().ToString('N')
    $remoteB64 = "/tmp/codex_ent_crm_$uploadId.b64"
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
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    foreach ($target in $targets) {
        $preflight = Invoke-RemoteChecked $session.SessionId "sha256sum '$($target.Remote)' | awk '{print `$1}'"
        $actual = ([string]($preflight.Output | Select-Object -First 1)).Trim()
        if ($actual -ne $target.Expected) { throw "Guarded deployment stopped for $($target.Remote): expected $($target.Expected) but found $actual" }
    }
    foreach ($target in $targets) {
        Invoke-RemoteChecked $session.SessionId "cp '$($target.Remote)' '$($target.Remote).bak.shared-enterprise-discovery-crm.$timestamp'" | Out-Null
        Send-RemoteFileB64 $session.SessionId $target.Local $target.Remote
    }
    Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_shared_enterprise_discovery_crm_v1.py" "$remoteRoot/scripts/validate_shared_enterprise_discovery_crm_v1.py"
    Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_enterprise_discovery_observatory_v1.py" "$remoteRoot/scripts/validate_enterprise_discovery_observatory_v1.py"
    Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_progressive_enterprise_discovery_v1.py" "$remoteRoot/scripts/validate_progressive_enterprise_discovery_v1.py"
    (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python -m py_compile core/enterprise_service.py core/routers/enterprises.py core/routers/observatory.py").Output
    (Invoke-RemoteChecked $session.SessionId "systemctl --user restart mim-mobile-web.service mim-training-web.service && systemctl --user is-active mim-mobile-web.service mim-training-web.service").Output
    (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_shared_enterprise_discovery_crm_v1.py" 240).Output
    (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_enterprise_discovery_observatory_v1.py" 180).Output
    (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_progressive_enterprise_discovery_v1.py" 300).Output
    foreach ($target in $targets) { (Invoke-RemoteChecked $session.SessionId "sha256sum '$($target.Remote)'").Output }
}
finally {
    if ($session) { Remove-SSHSession -SessionId $session.SessionId | Out-Null }
}
