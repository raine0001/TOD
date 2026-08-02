param([string]$EnvFile = ".env")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$remoteRoot = "/home/testpilot/mim"
$expectedServiceHash = "cc4dd63ee32405e957873d92d1f98d81a6e020c94f67f07dc67de803fdf346f3"
function Env([string]$Name) { $line = Get-Content $envPath | Where-Object { $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name)) } | Select-Object -First 1; if (-not $line) { return "" }; (($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "").Trim().Trim('"')) }
function Remote([int]$Id, [string]$Command, [int]$Timeout = 120) { $result = Invoke-SSHCommand -SessionId $Id -Command $Command -TimeOut $Timeout; if ($result.ExitStatus -ne 0) { throw "Remote failed $($result.ExitStatus): $($result.Output -join ' | ') $($result.Error -join '; ')" }; $result }
function Upload([int]$Id, [string]$Local, [string]$RemotePath) { $bytes = [IO.File]::ReadAllBytes((Resolve-Path (Join-Path $repoRoot $Local))); $encoded = [Convert]::ToBase64String($bytes); $temp = "/tmp/ent212_$([guid]::NewGuid().ToString('N')).b64"; for ($offset=0; $offset -lt $encoded.Length; $offset+=12000) { $chunk=$encoded.Substring($offset,[Math]::Min(12000,$encoded.Length-$offset)); Remote $Id "printf '%s' '$chunk' >> '$temp'" | Out-Null }; Remote $Id "base64 -d '$temp' > '$RemotePath' && rm -f '$temp'" | Out-Null }
Import-Module Posh-SSH -ErrorAction Stop
$credential=[pscredential]::new((Env "MIM_SSH_USER"),(ConvertTo-SecureString (Env "MIM_SSH_PASSWORD") -AsPlainText -Force)); $portText=Env "MIM_SSH_PORT"; $session=New-SSHSession -ComputerName (Env "MIM_SSH_HOST") -Port $(if($portText){[int]$portText}else{22}) -Credential $credential -AcceptKey -Force
try {
    $serviceCandidate="$remoteRoot/scripts/enterprise_experience_governance_candidate.py"
    Upload $session.SessionId "tmp_remote_mim/core/enterprise_experience_governance.py" $serviceCandidate
    Upload $session.SessionId "runtime_remote_training/remote_scripts/apply_enterprise_philosophy_task_gate_v1.py" "$remoteRoot/scripts/apply_enterprise_philosophy_task_gate_v1.py"
    $candidateHash=([string]((Remote $session.SessionId "sha256sum '$serviceCandidate' | awk '{print `$1}'").Output|Select-Object -First 1)).Trim()
    if($candidateHash -ne $expectedServiceHash){throw "Service candidate hash mismatch $candidateHash"}
    (Remote $session.SessionId "test ! -e '$remoteRoot/core/enterprise_experience_governance.py' && cd '$remoteRoot' && .venv/bin/python -m py_compile '$serviceCandidate' scripts/apply_enterprise_philosophy_task_gate_v1.py").Output
    (Remote $session.SessionId "cd '$remoteRoot' && .venv/bin/python scripts/apply_enterprise_philosophy_task_gate_v1.py").Output
    (Remote $session.SessionId "cp '$serviceCandidate' '$remoteRoot/core/enterprise_experience_governance.py' && cd '$remoteRoot' && .venv/bin/python -m py_compile core/enterprise_experience_governance.py core/routers/tasks.py && .venv/bin/python -c 'import core.app'").Output
    (Remote $session.SessionId "systemctl --user restart mim-mobile-web.service mim-training-web.service").Output
    (Remote $session.SessionId "for i in `$(seq 1 20); do a=`$(systemctl --user is-active mim-mobile-web.service); b=`$(systemctl --user is-active mim-training-web.service); if [ `"`$a`" = active ] && [ `"`$b`" = active ]; then echo `"`$a`"; echo `"`$b`"; exit 0; fi; sleep 2; done; exit 1" 60).Output
    (Remote $session.SessionId "curl -fsS 'https://mim.mimtod.com/tasks/enterprise-product-philosophy'; sha256sum '$remoteRoot/core/enterprise_experience_governance.py' '$remoteRoot/core/routers/tasks.py'").Output
}
finally { if($session){Remove-SSHSession -SessionId $session.SessionId|Out-Null} }
