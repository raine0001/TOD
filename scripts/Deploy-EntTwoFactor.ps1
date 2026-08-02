param([string]$EnvFile = ".env")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$remoteRoot = "/home/testpilot/mim"
$expectedHash = "13aee72a7086730d7ac575dab29b326650a483acdc6ac196f36304c600b3904a"
$deployedHash = "606d6a52daeaa6e03c0f99e2a20dbe703bdc12c2928cff946c1e10e606f0fa79"
function Get-EnvValue { param([string]$Name) $line=Get-Content -LiteralPath $envPath|Where-Object{$_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))}|Select-Object -First 1; if(-not $line){return ""}; return (($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)),"").Trim().Trim('"')) }
function Invoke-RemoteChecked { param([int]$SessionId,[string]$Command,[int]$TimeoutSeconds=120) $r=Invoke-SSHCommand -SessionId $SessionId -Command $Command -TimeOut $TimeoutSeconds; if($r.ExitStatus -ne 0){throw "Remote command failed $($r.ExitStatus): $($r.Error -join '; ')"}; return $r }
function Send-RemoteFileB64 { param([int]$SessionId,[string]$LocalPath,[string]$RemotePath) $full=(Resolve-Path(Join-Path $repoRoot $LocalPath)).Path;$encoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes($full));$tmp="/tmp/codex_ent_2fa_$([Guid]::NewGuid().ToString('N')).b64";for($o=0;$o-lt$encoded.Length;$o+=12000){$c=$encoded.Substring($o,[Math]::Min(12000,$encoded.Length-$o));Invoke-RemoteChecked $SessionId "printf '%s' '$c' >> '$tmp'"|Out-Null};Invoke-RemoteChecked $SessionId "base64 -d '$tmp' > '$RemotePath' && rm -f '$tmp'"|Out-Null }
Import-Module Posh-SSH -ErrorAction Stop
$credential=[pscredential]::new((Get-EnvValue "MIM_SSH_USER"),(ConvertTo-SecureString (Get-EnvValue "MIM_SSH_PASSWORD") -AsPlainText -Force));$pt=Get-EnvValue "MIM_SSH_PORT";$port=if($pt){[int]$pt}else{22};$session=New-SSHSession -ComputerName (Get-EnvValue "MIM_SSH_HOST") -Port $port -Credential $credential -AcceptKey -Force
try {
  $candidate="$remoteRoot/scripts/project_portal_ent_two_factor_candidate.py"
  Send-RemoteFileB64 $session.SessionId "tmp_remote_mim/core/routers/project_portal.py" $candidate
  Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_ent_two_factor_v1.py" "$remoteRoot/scripts/validate_ent_two_factor_v1.py"
  $current=([string]((Invoke-RemoteChecked $session.SessionId "sha256sum '$remoteRoot/core/routers/project_portal.py' | awk '{print `$1}'").Output|Select-Object -First 1)).Trim()
  $candidateHash=([string]((Invoke-RemoteChecked $session.SessionId "sha256sum '$candidate' | awk '{print `$1}'").Output|Select-Object -First 1)).Trim()
  if($candidateHash -ne $deployedHash){throw "Candidate hash mismatch $candidateHash"}
  (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python -m py_compile '$candidate'").Output
  if($current -eq $expectedHash){
    $stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ');$backup="$remoteRoot/core/routers/project_portal.py.bak.ent-two-factor.$stamp"
    (Invoke-RemoteChecked $session.SessionId "cp '$remoteRoot/core/routers/project_portal.py' '$backup' && cp '$candidate' '$remoteRoot/core/routers/project_portal.py'").Output
    "rollback=$backup"
  } elseif($current -ne $deployedHash){throw "Guarded deployment stopped at unexpected remote hash $current"}
  (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python -m py_compile core/routers/project_portal.py").Output
  (Invoke-RemoteChecked $session.SessionId "systemctl --user restart mim-mobile-web.service mim-training-web.service && sleep 2 && systemctl --user is-active mim-mobile-web.service mim-training-web.service").Output
  (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_ent_two_factor_v1.py").Output
  (Invoke-RemoteChecked $session.SessionId "curl -sS -o /dev/null -D - 'https://mim.mimtod.com/account/security' | head -n 8").Output
  (Invoke-RemoteChecked $session.SessionId "curl -sS -o /tmp/ent_2fa_unauth.json -w '%{http_code}' -X POST 'https://mim.mimtod.com/projects/security/two-factor/start'").Output
  (Invoke-RemoteChecked $session.SessionId "cat /tmp/ent_2fa_unauth.json && rm -f /tmp/ent_2fa_unauth.json").Output
  (Invoke-RemoteChecked $session.SessionId "sha256sum '$remoteRoot/core/routers/project_portal.py'").Output
} finally {if($session){Remove-SSHSession -SessionId $session.SessionId|Out-Null}}
