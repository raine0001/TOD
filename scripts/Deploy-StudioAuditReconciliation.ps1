param(
    [string]$EnvFile = ".env"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }

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
        [int]$TimeoutSeconds = 20
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
    $full = (Resolve-Path (Join-Path $repoRoot $LocalPath)).Path
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($full))
    $remoteB64 = "/tmp/codex_upload_$([System.Guid]::NewGuid().ToString('N')).b64"
    Invoke-RemoteChecked -SessionId $SessionId -Command "rm -f '$remoteB64' '$RemotePath.tmp'" | Out-Null
    for ($i = 0; $i -lt $b64.Length; $i += 12000) {
        $chunk = $b64.Substring($i, [Math]::Min(12000, $b64.Length - $i))
        Invoke-RemoteChecked -SessionId $SessionId -Command "printf '%s' '$chunk' >> '$remoteB64'" | Out-Null
    }
    Invoke-RemoteChecked -SessionId $SessionId -Command "base64 -d '$remoteB64' > '$RemotePath.tmp' && mv '$RemotePath.tmp' '$RemotePath' && rm -f '$remoteB64'" | Out-Null
}

Import-Module Posh-SSH
$secure = ConvertTo-SecureString (Get-EnvValue "MIM_SSH_PASSWORD") -AsPlainText -Force
$cred = [pscredential]::new((Get-EnvValue "MIM_SSH_USER"), $secure)
$hostName = Get-EnvValue "MIM_SSH_HOST"
$portText = Get-EnvValue "MIM_SSH_PORT"
$port = if ($portText) { [int]$portText } else { 22 }
$session = New-SSHSession -ComputerName $hostName -Port $port -Credential $cred -AcceptKey -Force
try {
    Send-RemoteFileB64 -SessionId $session.SessionId -LocalPath "tmp_remote_mim/core/routers/studio.py" -RemotePath "/home/testpilot/mim/core/routers/studio.py"
    Send-RemoteFileB64 -SessionId $session.SessionId -LocalPath "runtime_remote_training/MIM_STUDIO_DATA_AUDIT_AND_RECONCILIATION_V1.latest.json" -RemotePath "/home/testpilot/mim/runtime/shared/MIM_STUDIO_DATA_AUDIT_AND_RECONCILIATION_V1.latest.json"
    Send-RemoteFileB64 -SessionId $session.SessionId -LocalPath "runtime_remote_training/MIM_STUDIO_DATA_AUDIT_AND_RECONCILIATION_RESULT.latest.json" -RemotePath "/home/testpilot/mim/runtime/shared/MIM_STUDIO_DATA_AUDIT_AND_RECONCILIATION_RESULT.latest.json"
    Send-RemoteFileB64 -SessionId $session.SessionId -LocalPath "runtime_remote_training/MIM_STUDIO_DATA_AUDIT_AND_RECONCILIATION_RESULT.latest.md" -RemotePath "/home/testpilot/mim/runtime/shared/MIM_STUDIO_DATA_AUDIT_AND_RECONCILIATION_RESULT.latest.md"
    $verifyCommand = "python3 -c 'from pathlib import Path; p=Path(""/home/testpilot/mim/core/routers/studio.py""); t=p.read_text(); print(p.stat().st_size); print(t.find(""_studio_data_audit_state"")); print(t.find(""_data_sources_html(state, \""training\"")""))'"
    $verify = Invoke-RemoteChecked -SessionId $session.SessionId -Command $verifyCommand
    $verify.Output
}
finally {
    Remove-SSHSession -SessionId $session.SessionId | Out-Null
}
