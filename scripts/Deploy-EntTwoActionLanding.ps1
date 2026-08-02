param([string]$EnvFile = ".env")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$remoteRoot = "/home/testpilot/mim"
function Get-EnvValue { param([string]$Name) $line = Get-Content -LiteralPath $envPath | Where-Object { $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name)) } | Select-Object -First 1; if (-not $line) { return "" }; return (($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "").Trim().Trim('"')) }
function Invoke-RemoteChecked { param([int]$SessionId,[string]$Command,[int]$TimeoutSeconds=120) $result=Invoke-SSHCommand -SessionId $SessionId -Command $Command -TimeOut $TimeoutSeconds; if($result.ExitStatus -ne 0){throw "Remote command failed $($result.ExitStatus): $($result.Error -join '; ')"}; return $result }
function Send-RemoteFileB64 { param([int]$SessionId,[string]$LocalPath,[string]$RemotePath) $full=(Resolve-Path (Join-Path $repoRoot $LocalPath)).Path; $encoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes($full)); $id=[Guid]::NewGuid().ToString('N'); $tmp="/tmp/codex_ent_landing_$id.b64"; for($offset=0;$offset -lt $encoded.Length;$offset+=12000){$chunk=$encoded.Substring($offset,[Math]::Min(12000,$encoded.Length-$offset)); Invoke-RemoteChecked $SessionId "printf '%s' '$chunk' >> '$tmp'"|Out-Null}; Invoke-RemoteChecked $SessionId "base64 -d '$tmp' > '$RemotePath' && rm -f '$tmp'"|Out-Null }
Import-Module Posh-SSH -ErrorAction Stop
$securePassword=ConvertTo-SecureString (Get-EnvValue "MIM_SSH_PASSWORD") -AsPlainText -Force
$credential=[pscredential]::new((Get-EnvValue "MIM_SSH_USER"),$securePassword)
$portText=Get-EnvValue "MIM_SSH_PORT"; $port=if($portText){[int]$portText}else{22}
$session=New-SSHSession -ComputerName (Get-EnvValue "MIM_SSH_HOST") -Port $port -Credential $credential -AcceptKey -Force
try {
  Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/apply_ent_two_action_landing_v1.py" "$remoteRoot/scripts/apply_ent_two_action_landing_v1.py"
  Send-RemoteFileB64 $session.SessionId "runtime_remote_training/remote_scripts/validate_ent_two_action_landing_v1.py" "$remoteRoot/scripts/validate_ent_two_action_landing_v1.py"
  $currentHash = ([string]((Invoke-RemoteChecked $session.SessionId "sha256sum '$remoteRoot/core/routers/observatory.py' | awk '{print `$1}'").Output | Select-Object -First 1)).Trim()
  if ($currentHash -eq "727f1ff22639b7657dc94b7f5efac823ab8ae378b2cb4eb7135c353ef71ae693") {
    (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python scripts/apply_ent_two_action_landing_v1.py").Output
  } elseif ($currentHash -ne "f47dfcb52636680d534432ee8a320c0dd67618cfdb4a97a131cc0cca4b6e1b13") {
    throw "Guarded deployment stopped at unexpected remote hash $currentHash"
  }
  (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && .venv/bin/python -m py_compile core/routers/observatory.py").Output
  (Invoke-RemoteChecked $session.SessionId "systemctl --user restart mim-mobile-web.service mim-training-web.service && systemctl --user is-active mim-mobile-web.service mim-training-web.service").Output
  (Invoke-RemoteChecked $session.SessionId "cd '$remoteRoot' && PYTHONPATH='$remoteRoot' MIM_ROOT='$remoteRoot' .venv/bin/python scripts/validate_ent_two_action_landing_v1.py").Output
  (Invoke-RemoteChecked $session.SessionId "sha256sum '$remoteRoot/core/routers/observatory.py'").Output
} finally { if($session){Remove-SSHSession -SessionId $session.SessionId|Out-Null} }
