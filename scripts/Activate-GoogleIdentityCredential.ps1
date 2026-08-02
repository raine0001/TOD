param(
    [string]$EnvFile = ".env"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $env:GOOGLE_IDENTITY_CLIENT_ID -or -not $env:GOOGLE_IDENTITY_CLIENT_SECRET) {
    throw "Protected Google Identity credential environment variables are required."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$remoteRoot = "/home/testpilot/mim"

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

Import-Module Posh-SSH
$credential = [pscredential]::new(
    (Read-Env "MIM_SSH_USER"),
    (ConvertTo-SecureString (Read-Env "MIM_SSH_PASSWORD") -AsPlainText -Force)
)
$portText = Read-Env "MIM_SSH_PORT"
$session = New-SSHSession -ComputerName (Read-Env "MIM_SSH_HOST") -Port $(if ($portText) { [int]$portText } else { 22 }) -Credential $credential -AcceptKey -Force
try {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $backup = "$remoteRoot/.env.bak.google-identity-activation.$stamp"
    Invoke-Remote $session.SessionId "cp '$remoteRoot/.env' '$backup'" | Out-Null

    $clientIdB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:GOOGLE_IDENTITY_CLIENT_ID))
    $clientSecretB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:GOOGLE_IDENTITY_CLIENT_SECRET))
    $redirectB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("https://mim.mimtod.com/auth/google/callback"))
    $updateCode = @'
import base64, os
from pathlib import Path
p = Path('/home/testpilot/mim/.env')
updates = {
    'GOOGLE_IDENTITY_CLIENT_ID': base64.b64decode(os.environ['GOOGLE_ID_CLIENT_B64']).decode(),
    'GOOGLE_IDENTITY_CLIENT_SECRET': base64.b64decode(os.environ['GOOGLE_ID_SECRET_B64']).decode(),
    'GOOGLE_IDENTITY_REDIRECT_URI': base64.b64decode(os.environ['GOOGLE_ID_REDIRECT_B64']).decode(),
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
    Invoke-Remote $session.SessionId "cd '$remoteRoot' && GOOGLE_ID_CLIENT_B64='$clientIdB64' GOOGLE_ID_SECRET_B64='$clientSecretB64' GOOGLE_ID_REDIRECT_B64='$redirectB64' .venv/bin/python -c `"$remoteUpdate`"" | Out-Null

    Invoke-Remote $session.SessionId "systemctl --user restart mim-mobile-web.service mim-training-web.service" | Out-Null
    $health = Invoke-Remote $session.SessionId "for i in `$(seq 1 20); do a=`$(systemctl --user is-active mim-mobile-web.service); b=`$(systemctl --user is-active mim-training-web.service); if [ `"`$a`" = active ] && [ `"`$b`" = active ]; then echo `"`$a`"; echo `"`$b`"; exit 0; fi; sleep 2; done; exit 1" 60
    $health.Output
    Invoke-Remote $session.SessionId "for i in `$(seq 1 20); do if curl -fsS 'http://127.0.0.1:18001/health' >/dev/null; then exit 0; fi; sleep 2; done; exit 1" 60 | Out-Null
    (Invoke-Remote $session.SessionId "cd '$remoteRoot' && .venv/bin/python -c `"from core.config import settings; print('google_identity_configured=' + str(bool(settings.google_identity_client_id and settings.google_identity_client_secret))); print('redirect_exact=' + str(settings.google_identity_redirect_uri == 'https://mim.mimtod.com/auth/google/callback'))`"").Output
    (Invoke-Remote $session.SessionId "cd '$remoteRoot' && .venv/bin/python -c `"import httpx,urllib.parse; r=httpx.get('https://mim.mimtod.com/auth/google/start',follow_redirects=False,timeout=20); host=urllib.parse.urlparse(r.headers.get('location','')).hostname or ''; print('start_status='+str(r.status_code)); print('location_host='+host)`"").Output
    Write-Output "rollback=$backup"
}
finally {
    if ($session) { Remove-SSHSession $session.SessionId | Out-Null }
    Remove-Item Env:GOOGLE_IDENTITY_CLIENT_ID -ErrorAction SilentlyContinue
    Remove-Item Env:GOOGLE_IDENTITY_CLIENT_SECRET -ErrorAction SilentlyContinue
}
