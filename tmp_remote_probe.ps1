$envPath = Join-Path (Get-Location) '.env'
function Get-DotEnvValue([string]$Path,[string]$Name){ if(-not (Test-Path $Path)){ return '' }; $line = Get-Content $Path | Where-Object { $_ -match ('^\s*' + [regex]::Escape($Name) + '\s*=') } | Select-Object -First 1; if([string]::IsNullOrWhiteSpace([string]$line)){ return '' }; return ([string]($line -replace ('^\s*' + [regex]::Escape($Name) + '\s*=\s*'), '')).Trim() }
Import-Module Posh-SSH -ErrorAction Stop
$hostName = Get-DotEnvValue $envPath 'MIM_SSH_HOST'
$userName = Get-DotEnvValue $envPath 'MIM_SSH_USER'
$portText = Get-DotEnvValue $envPath 'MIM_SSH_PORT'
$password = Get-DotEnvValue $envPath 'MIM_SSH_PASSWORD'
$port = if([string]::IsNullOrWhiteSpace($portText)){22}else{[int]$portText}
$sec = ConvertTo-SecureString $password -AsPlainText -Force
$cred = [pscredential]::new($userName,$sec)
$session = New-SSHSession -ComputerName $hostName -Port $port -Credential $cred -AcceptKey
$paths = @('/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json','/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.json','/home/testpilot/mim/runtime/shared/MIM_CONTEXT_EXPORT.latest.json','/home/testpilot/mim/runtime/shared/MIM_TOD_HANDSHAKE_PACKET.latest.json')
foreach($p in $paths){
  $cmd = "python3 - <<'PY'\nimport hashlib, json, os\npath = " + [char]34 + $p + [char]34 + "\nif not os.path.exists(path):\n    print(json.dumps({'path': path, 'exists': False}))\nelse:\n    st = os.stat(path)\n    with open(path, 'rb') as f:\n        data = f.read()\n    try:\n        text = data.decode('utf-8')\n    except Exception:\n        text = ''\n    task_id = ''\n    objective_id = ''\n    try:\n        obj = json.loads(text) if text else {}\n        task_id = obj.get('task_id','')\n        objective_id = obj.get('objective_id','') or obj.get('objective_active','') or obj.get('current_next_objective','')\n    except Exception:\n        pass\n    print(json.dumps({'path': path, 'exists': True, 'mtime_epoch': st.st_mtime, 'size': st.st_size, 'sha256': hashlib.sha256(data).hexdigest(), 'task_id': task_id, 'objective_id': objective_id}))\nPY"
  $result = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
  $result.Output
}
Remove-SSHSession -SessionId $session.SessionId | Out-Null
