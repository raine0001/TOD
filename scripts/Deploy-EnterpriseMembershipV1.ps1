param([string]$EnvFile = ".env")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$remoteRoot = "/home/testpilot/mim"
$expectedRemoteModels = "efe9de998fdb892083c7cd16532b709aabdffb604fbc00e722c8996f19b01055"
$expectedRemotePortal = "db1eb8e7127d22402793be067e72ec7208a24f61f9ddf65aa552e0027d51017f"
$expectedCandidatePortal = "ea9f25b29cba19a7a59330b70a49e13194c2ea492c8c0c5e0c3147884b69e074"

function Get-EnvValue {
    param([string]$Name)
    $line = Get-Content -LiteralPath $envPath | Where-Object { $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name)) } | Select-Object -First 1
    if (-not $line) { return "" }
    return (($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "").Trim().Trim('"'))
}
function Invoke-RemoteChecked {
    param([int]$SessionId, [string]$Command, [int]$TimeoutSeconds = 120)
    $result = Invoke-SSHCommand -SessionId $SessionId -Command $Command -TimeOut $TimeoutSeconds
    if ($result.ExitStatus -ne 0) { throw "Remote command failed $($result.ExitStatus): $($result.Output -join ' | ') $($result.Error -join '; ')" }
    return $result
}
function Send-RemoteFileB64 {
    param([int]$SessionId, [string]$LocalPath, [string]$RemotePath)
    $full = (Resolve-Path (Join-Path $repoRoot $LocalPath)).Path
    $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($full))
    $tempPath = "/tmp/codex_ent_membership_$([Guid]::NewGuid().ToString('N')).b64"
    for ($offset = 0; $offset -lt $encoded.Length; $offset += 12000) {
        $chunk = $encoded.Substring($offset, [Math]::Min(12000, $encoded.Length - $offset))
        Invoke-RemoteChecked $SessionId "printf '%s' '$chunk' >> '$tempPath'" | Out-Null
    }
    Invoke-RemoteChecked $SessionId "base64 -d '$tempPath' > '$RemotePath' && rm -f '$tempPath'" | Out-Null
}

Import-Module Posh-SSH -ErrorAction Stop
$credential = [pscredential]::new((Get-EnvValue "MIM_SSH_USER"), (ConvertTo-SecureString (Get-EnvValue "MIM_SSH_PASSWORD") -AsPlainText -Force))
$portText = Get-EnvValue "MIM_SSH_PORT"
$port = if ($portText) { [int]$portText } else { 22 }
$session = New-SSHSession -ComputerName (Get-EnvValue "MIM_SSH_HOST") -Port $port -Credential $credential -AcceptKey -Force
try {
    $portalCandidate = "$remoteRoot/scripts/project_portal_enterprise_membership_candidate.py"
    Send-RemoteFileB64 $session.SessionId "tmp_remote_mim/core/routers/project_portal.py" $portalCandidate
    Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/apply_enterprise_membership_model_v1.py" "$remoteRoot/scripts/apply_enterprise_membership_model_v1.py"
    Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_enterprise_membership_v1.py" "$remoteRoot/scripts/validate_enterprise_membership_v1.py"
    $remoteModels = ([string]((Invoke-RemoteChecked $session.SessionId "sha256sum '$remoteRoot/core/models.py' | awk '{print `$1}'").Output | Select-Object -First 1)).Trim()
    $remotePortal = ([string]((Invoke-RemoteChecked $session.SessionId "sha256sum '$remoteRoot/core/routers/project_portal.py' | awk '{print `$1}'").Output | Select-Object -First 1)).Trim()
    $candidatePortal = ([string]((Invoke-RemoteChecked $session.SessionId "sha256sum '$portalCandidate' | awk '{print `$1}'").Output | Select-Object -First 1)).Trim()
    if ($remoteModels -ne $expectedRemoteModels -or $remotePortal -ne $expectedRemotePortal) { throw "Remote hash guard failed: models=$remoteModels portal=$remotePortal" }
    if ($candidatePortal -ne $expectedCandidatePortal) { throw "Candidate hash guard failed: portal=$candidatePortal" }
    (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python -m py_compile '$portalCandidate' scripts/apply_enterprise_membership_model_v1.py scripts/validate_enterprise_membership_v1.py").Output
    (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python scripts/apply_enterprise_membership_model_v1.py").Output
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $portalBackup = "$remoteRoot/core/routers/project_portal.py.bak.enterprise-membership.$stamp"
    (Invoke-RemoteChecked $session.SessionId "cp '$remoteRoot/core/routers/project_portal.py' '$portalBackup' && cp '$portalCandidate' '$remoteRoot/core/routers/project_portal.py'").Output
    "portal_rollback=$portalBackup"
    (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python -m py_compile core/models.py core/routers/project_portal.py && .venv/bin/python -c 'import core.app'").Output
    (Invoke-RemoteChecked $session.SessionId "systemctl --user restart mim-mobile-web.service mim-training-web.service").Output
    (Invoke-RemoteChecked $session.SessionId "for i in `$(seq 1 20); do a=`$(systemctl --user is-active mim-mobile-web.service); b=`$(systemctl --user is-active mim-training-web.service); if [ `"`$a`" = active ] && [ `"`$b`" = active ]; then echo `"`$a`"; echo `"`$b`"; exit 0; fi; sleep 2; done; systemctl --user --no-pager --full status mim-mobile-web.service mim-training-web.service; exit 1" -TimeoutSeconds 60).Output
    (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' VALIDATE_LIVE_DB=1 .venv/bin/python scripts/validate_enterprise_membership_v1.py").Output
    (Invoke-RemoteChecked $session.SessionId "curl -fsS 'https://mim.mimtod.com/login' >/dev/null && curl -fsS -o /dev/null -w 'members_unauth=%{http_code}\n' 'https://mim.mimtod.com/enterprise/members' && sha256sum '$remoteRoot/core/models.py' '$remoteRoot/core/routers/project_portal.py'").Output
}
finally {
    if ($session) { Remove-SSHSession -SessionId $session.SessionId | Out-Null }
}
