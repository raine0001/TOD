param([string]$EnvFile = ".env")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$remoteRoot = "/home/testpilot/mim"
function Get-EnvValue { param([string]$Name) $line=Get-Content -LiteralPath $envPath|Where-Object{$_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))}|Select-Object -First 1; if(-not $line){return ""}; return (($line-replace("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)),"").Trim().Trim('"')) }
function Invoke-RemoteChecked { param([int]$SessionId,[string]$Command,[int]$TimeoutSeconds=120) $r=Invoke-SSHCommand -SessionId $SessionId -Command $Command -TimeOut $TimeoutSeconds; if($r.ExitStatus-ne 0){throw "Remote command failed $($r.ExitStatus): $($r.Error -join '; ')"}; return $r }
function Send-RemoteFileB64 { param([int]$SessionId,[string]$LocalPath,[string]$RemotePath) $full=(Resolve-Path(Join-Path $repoRoot $LocalPath)).Path;$encoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes($full));$tmp="/tmp/codex_ent_plan_reg_$([Guid]::NewGuid().ToString('N')).b64";for($o=0;$o-lt$encoded.Length;$o+=12000){$c=$encoded.Substring($o,[Math]::Min(12000,$encoded.Length-$o));Invoke-RemoteChecked $SessionId "printf '%s' '$c' >> '$tmp'"|Out-Null};Invoke-RemoteChecked $SessionId "base64 -d '$tmp' > '$RemotePath' && rm -f '$tmp'"|Out-Null }
Import-Module Posh-SSH -ErrorAction Stop
$credential=[pscredential]::new((Get-EnvValue "MIM_SSH_USER"),(ConvertTo-SecureString(Get-EnvValue "MIM_SSH_PASSWORD") -AsPlainText -Force));$portText=Get-EnvValue "MIM_SSH_PORT";$port=if($portText){[int]$portText}else{22};$session=New-SSHSession -ComputerName(Get-EnvValue "MIM_SSH_HOST") -Port $port -Credential $credential -AcceptKey -Force
try {
  Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/apply_ent_plan_registration_v1.py" "$remoteRoot/scripts/apply_ent_plan_registration_v1.py"
  Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_ent_plan_registration_v1.py" "$remoteRoot/scripts/validate_ent_plan_registration_v1.py"
  $hash=([string]((Invoke-RemoteChecked $session.SessionId "sha256sum '$remoteRoot/core/routers/project_portal.py' | awk '{print `$1}'").Output|Select-Object -First 1)).Trim()
  if($hash-eq"75f35fe71af7b5ca219b4139b39fa3ff9c0d82c34dd98eeb13fcc285dfec3d50"){(Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python scripts/apply_ent_plan_registration_v1.py").Output}elseif($hash-ne"fe16cb32720038fb7cf20fc0214e05b64593ed700b3dd17706df8044a7d5df6f"){throw "Guarded deployment stopped at unexpected remote hash $hash"}
  (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python -m py_compile core/routers/project_portal.py").Output
  (Invoke-RemoteChecked $session.SessionId "systemctl --user restart mim-mobile-web.service mim-training-web.service && systemctl --user is-active mim-mobile-web.service mim-training-web.service").Output
  (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_ent_plan_registration_v1.py").Output
  (Invoke-RemoteChecked $session.SessionId "sha256sum '$remoteRoot/core/routers/project_portal.py'").Output
} finally {if($session){Remove-SSHSession -SessionId $session.SessionId|Out-Null}}
