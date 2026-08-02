param(
    [Parameter(Mandatory = $true)][string]$MerchantApiKey,
    [string]$MerchantBaseUrl = "https://www.agentmim.com",
    [string]$EnvFile = ".env"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$remoteRoot = "/home/testpilot/mim"
$files = @(
    @{ local = "tmp_remote_mim/core/config.py"; remote = "core/config.py"; before = "66e5ce1a1a067d8ffee71967c5536832ac62a19ee26972b0238305b451fecaf3"; after = "83e9a98223319cdff4716385adcf51d4a448fdb90ae74b7b51ce22a0da538138" },
    @{ local = "tmp_remote_mim/core/routers/__init__.py"; remote = "core/routers/__init__.py"; before = "7ed72dc89808fa680399e41b9ba0fb7500ac7484f9d3349becc3e0fe488a4084"; after = "0d31da2dc5b4c38396e5e04d252537b09e0abc29fd33ad34b2fc525279124af6" },
    @{ local = "tmp_remote_mim/core/enterprise_billing_service.py"; remote = "core/enterprise_billing_service.py"; before = "MISSING"; after = "269ad689f5f79422f7cacb854bca624713abc368597649e94b625ce98efe5d75" },
    @{ local = "tmp_remote_mim/core/routers/enterprise_billing.py"; remote = "core/routers/enterprise_billing.py"; before = "MISSING"; after = "499f323ce89f79a8a12827e7c1599e5c39374fe391861382e5a71b7fa99450cf" }
)

function Read-Env([string]$Name) {
    $line = Get-Content -LiteralPath $envPath | Where-Object { $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name)) } | Select-Object -First 1
    if (-not $line) { return "" }
    return (($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "").Trim().Trim('"'))
}

function Invoke-Remote([int]$SessionId, [string]$Command, [int]$Timeout = 120) {
    $result = Invoke-SSHCommand -SessionId $SessionId -Command $Command -TimeOut $Timeout
    if ($result.ExitStatus -ne 0) {
        throw "Remote command failed ($($result.ExitStatus)): $($result.Output -join ' | ') $($result.Error -join '; ')"
    }
    return $result
}

function Send-File([int]$SessionId, [string]$Local, [string]$Destination) {
    $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path (Join-Path $repoRoot $Local))))
    $temp = "/tmp/ent205_$([guid]::NewGuid().ToString('N')).b64"
    for ($offset = 0; $offset -lt $encoded.Length; $offset += 12000) {
        $chunk = $encoded.Substring($offset, [Math]::Min(12000, $encoded.Length - $offset))
        Invoke-Remote $SessionId "printf '%s' '$chunk' >> '$temp'" | Out-Null
    }
    Invoke-Remote $SessionId "base64 -d '$temp' > '$Destination' && rm -f '$temp'" | Out-Null
}

Import-Module Posh-SSH
$credential = [pscredential]::new(
    (Read-Env "MIM_SSH_USER"),
    (ConvertTo-SecureString (Read-Env "MIM_SSH_PASSWORD") -AsPlainText -Force)
)
$portText = Read-Env "MIM_SSH_PORT"
$session = New-SSHSession -ComputerName (Read-Env "MIM_SSH_HOST") -Port $(if ($portText) { [int]$portText } else { 22 }) -Credential $credential -AcceptKey -Force
try {
    $candidates = @()
    foreach ($file in $files) {
        $candidate = "$remoteRoot/scripts/ent205_$([IO.Path]::GetFileName($file.remote))"
        Send-File $session.SessionId $file.local $candidate
        $currentCommand = "if [ -f '$remoteRoot/$($file.remote)' ]; then sha256sum '$remoteRoot/$($file.remote)' | awk '{print `$1}'; else echo MISSING; fi"
        $current = ([string]((Invoke-Remote $session.SessionId $currentCommand).Output | Select-Object -First 1)).Trim()
        $candidateHash = ([string]((Invoke-Remote $session.SessionId "sha256sum '$candidate' | awk '{print `$1}'").Output | Select-Object -First 1)).Trim()
        if ($current -ne $file.before) { throw "Remote guard failed for $($file.remote): $current" }
        if ($candidateHash -ne $file.after) { throw "Candidate guard failed for $($file.remote): $candidateHash" }
        $candidates += @{ spec = $file; path = $candidate }
    }

    Invoke-Remote $session.SessionId "cd '$remoteRoot' && .venv/bin/python -m py_compile $($candidates.path -join ' ')" | Out-Null
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    foreach ($candidate in $candidates) {
        $destination = "$remoteRoot/$($candidate.spec.remote)"
        if ($candidate.spec.before -ne "MISSING") {
            $backup = "$destination.bak.ent205-billing.$stamp"
            Invoke-Remote $session.SessionId "cp '$destination' '$backup'" | Out-Null
            Write-Output "rollback=$backup"
        }
        Invoke-Remote $session.SessionId "cp '$($candidate.path)' '$destination'" | Out-Null
    }

    $keyB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($MerchantApiKey))
    $urlB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($MerchantBaseUrl.TrimEnd('/')))
    $envBackup = "$remoteRoot/.env.bak.ent205-billing.$stamp"
    Invoke-Remote $session.SessionId "cp '$remoteRoot/.env' '$envBackup'" | Out-Null
    $updateCode = @'
import base64, os
from pathlib import Path
p = Path('/home/testpilot/mim/.env')
updates = {
    'AGENTMIM_MERCHANT_API_KEY': base64.b64decode(os.environ['ENT205_KEY_B64']).decode(),
    'AGENTMIM_MERCHANT_BASE_URL': base64.b64decode(os.environ['ENT205_URL_B64']).decode(),
}
lines = p.read_text(encoding='utf-8').splitlines()
seen = set()
out = []
for line in lines:
    key = line.split('=', 1)[0].strip() if '=' in line else ''
    if key in updates:
        out.append(f'{key}={updates[key]}')
        seen.add(key)
    else:
        out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f'{key}={value}')
p.write_text('\n'.join(out) + '\n', encoding='utf-8')
'@
    $encodedUpdate = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($updateCode))
    $remoteUpdate = "import base64;exec(base64.b64decode('$encodedUpdate'))"
    Invoke-Remote $session.SessionId "cd '$remoteRoot' && ENT205_KEY_B64='$keyB64' ENT205_URL_B64='$urlB64' .venv/bin/python -c `"$remoteUpdate`"" | Out-Null
    Write-Output "rollback=$envBackup"

    Invoke-Remote $session.SessionId "cd '$remoteRoot' && .venv/bin/python -m py_compile core/config.py core/enterprise_billing_service.py core/routers/enterprise_billing.py core/routers/__init__.py && .venv/bin/python -c 'import core.app'" | Out-Null
    Invoke-Remote $session.SessionId "systemctl --user restart mim-mobile-web.service mim-training-web.service" | Out-Null
    $health = Invoke-Remote $session.SessionId "for i in `$(seq 1 20); do a=`$(systemctl --user is-active mim-mobile-web.service); b=`$(systemctl --user is-active mim-training-web.service); if [ `"`$a`" = active ] && [ `"`$b`" = active ]; then echo `"`$a`"; echo `"`$b`"; exit 0; fi; sleep 2; done; exit 1" 60
    $health.Output
    (Invoke-Remote $session.SessionId "cd '$remoteRoot' && .venv/bin/python -c `"from core.config import settings; print('merchant_configured=' + str(bool(settings.agentmim_merchant_base_url and settings.agentmim_merchant_api_key)))`"").Output
    $remoteFileList = (($files | ForEach-Object { "'$remoteRoot/$($_.remote)'" }) -join ' ')
    (Invoke-Remote $session.SessionId "sha256sum $remoteFileList").Output
}
finally {
    if ($session) { Remove-SSHSession $session.SessionId | Out-Null }
}
