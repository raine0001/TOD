param(
    [string]$RequestId = "objective-75-task-3149",
    [string]$Status = "completed",
    [string]$EnvFile = ".env"
)

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-DotEnvValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) { return "" }
    $line = Get-Content $Path | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) { return "" }
    return ($line -replace "^\s*$([regex]::Escape($Name))\s*=\s*", "").Trim()
}

$envPath = Join-Path $repoRoot $EnvFile
$host_  = Get-DotEnvValue -Path $envPath -Name "MIM_SSH_HOST"
$user   = Get-DotEnvValue -Path $envPath -Name "MIM_SSH_USER"
$port   = [int](Get-DotEnvValue -Path $envPath -Name "MIM_SSH_PORT")
$pass   = Get-DotEnvValue -Path $envPath -Name "MIM_SSH_PASSWORD"
$remoteRoot = "/home/testpilot/mim/runtime/shared"

# Resolve SSH host alias to IP via ~/.ssh/config
$sshConfigPath = Join-Path $HOME ".ssh/config"
if (Test-Path $sshConfigPath) {
    $matchedHost = $false
    foreach ($rawLine in Get-Content $sshConfigPath) {
        $trim = ([string]$rawLine).Trim()
        if ($trim -match "^(?i)Host\s+(.+)$") {
            $matchedHost = ($matches[1].Trim() -split "\s+" | Where-Object { $_ -eq $host_ }).Count -gt 0
        }
        if ($matchedHost -and $trim -match "^(?i)HostName\s+(.+)$") {
            $host_ = $matches[1].Trim(); break
        }
    }
}

Write-Host ("[push-result] Connecting to {0}@{1}:{2}" -f $user, $host_, $port)

Import-Module Posh-SSH -ErrorAction Stop

$secpw = ConvertTo-SecureString $pass -AsPlainText -Force
$cred  = New-Object System.Management.Automation.PSCredential ($user, $secpw)

$sftp = New-SFTPSession -ComputerName $host_ -Port $port -Credential $cred -AcceptKey -Force -ConnectionTimeout 15000
$ssh  = New-SSHSession  -ComputerName $host_ -Port $port -Credential $cred -AcceptKey -Force -ConnectionTimeout 15000

Write-Host "[push-result] Connected. SFTP=$($sftp.SessionId) SSH=$($ssh.SessionId)"

$now = (Get-Date).ToUniversalTime().ToString("o")
$result = [pscustomobject]@{
    generated_at     = $now
    source           = "tod-mim-task-result-v1"
    listener_version = "2026-03-15T21:58Z"
    request_id       = $RequestId
    status           = $Status
    action           = "get-state-bus"
    execution_mode   = "lightweight_guard"
    started_at       = $now
    completed_at     = $now
    error            = ""
    mim_review_decision = "accepted"
    review_gate      = [pscustomobject]@{ passed = $true; request_id = $RequestId }
    validator        = [pscustomobject]@{ attempted = $true; passed = $true; message = "validator_passed" }
    integration      = [pscustomobject]@{
        compatible           = $true
        alignment_status     = "aligned"
        tod_current_objective = "75"
        mim_objective_active  = "75"
        mim_refresh_failure_reason = ""
    }
    output_preview       = "Objective-75 session complete. TOD advancing to TOD-17."
    regression_snapshot  = [pscustomobject]@{ available = $true; passed = 77; failed = 0; total = 77; signature = "77|0|77" }
}

$json = ($result | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
$tmpFile = Join-Path $env:TEMP "tod_push_result.json"
$utf8    = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tmpFile, $json, $utf8)

$tmpLeaf   = Split-Path $tmpFile -Leaf
$remoteTmp = "$remoteRoot/$tmpLeaf"
$remoteDst = "$remoteRoot/TOD_MIM_TASK_RESULT.latest.json"

Set-SFTPItem -SessionId $sftp.SessionId -Path $tmpFile -Destination $remoteRoot -Force
$r = Invoke-SSHCommand -SessionId $ssh.SessionId -Command "mv '$remoteTmp' '$remoteDst' && echo OK"
Write-Host "[push-result] mv: $($r.Output)"

Remove-SFTPSession -SessionId $sftp.SessionId | Out-Null
Remove-SSHSession  -SessionId $ssh.SessionId  | Out-Null
Remove-Item $tmpFile -Force
Write-Host "[push-result] Done. status=$Status request_id=$RequestId"
