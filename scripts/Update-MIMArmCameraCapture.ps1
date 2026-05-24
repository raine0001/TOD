param(
    [string]$EnvFile = ".env",
    [string]$ArmHost = "http://192.168.1.90:5000",
    [string]$OutputDir = "runtime\shared\arm_camera_captures",
    [string]$RemoteMimDir = "/home/testpilot/mim/runtime/shared/arm_camera_captures",
    [string]$RemoteMimStatusPath = "/home/testpilot/mim/runtime/shared/MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json",
    [switch]$UploadToMim
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DotEnvValue {
    param([string]$Path, [string]$Name)
    $line = Get-Content -Path $Path | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -First 1
    if (-not $line) { return "" }
    return ($line -replace "^\s*$Name\s*=\s*", "").Trim().Trim('"').Trim("'")
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$outputAbs = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
New-Item -ItemType Directory -Force -Path $outputAbs | Out-Null

$hostName = Get-DotEnvValue -Path $envPath -Name "MIM_ARM_SSH_HOST"
$userName = Get-DotEnvValue -Path $envPath -Name "MIM_ARM_SSH_USER"
$port = Get-DotEnvValue -Path $envPath -Name "MIM_ARM_SSH_PORT"
$password = Get-DotEnvValue -Path $envPath -Name "MIM_ARM_SSH_HOST_PASS"
if ([string]::IsNullOrWhiteSpace($port)) { $port = "22" }
if ([string]::IsNullOrWhiteSpace($hostName) -or [string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($password)) {
    throw "Missing MIM_ARM_SSH_HOST/MIM_ARM_SSH_USER/MIM_ARM_SSH_HOST_PASS in $envPath"
}

$statusPath = Join-Path $repoRoot "runtime\shared\MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json"
$captureUrl = $ArmHost.TrimEnd("/") + "/capture_frame"
$capture = $null
$captureError = ""
try {
    $capture = Invoke-RestMethod -Method Post -Uri $captureUrl -TimeoutSec 20
}
catch {
    $captureError = $_.Exception.Message
}

$remoteArmRelative = ""
$remoteArmFrame = ""
$localFrame = ""
$remoteMimFrame = ""
$size = 0
$sha = ""
$stats = @{}
$pullError = ""

if ($capture -and $capture.status -eq "ok" -and -not [string]::IsNullOrWhiteSpace([string]$capture.output_path)) {
    $remoteArmRelative = [string]$capture.output_path
    $remoteArmFrame = "/home/testpilot/mim_arm/" + $remoteArmRelative.TrimStart("/")
    $leaf = [System.IO.Path]::GetFileName($remoteArmFrame)
    $localFrame = Join-Path $outputAbs $leaf
    $remoteMimFrame = "$RemoteMimDir/$leaf"

    Import-Module Posh-SSH -ErrorAction Stop
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $credential = [pscredential]::new($userName, $securePassword)
    $sftp = New-SFTPSession -ComputerName $hostName -Port ([int]$port) -Credential $credential -AcceptKey -ConnectionTimeout 30000
    try {
        Get-SFTPItem -SessionId $sftp.SessionId -Path $remoteArmFrame -Destination $outputAbs -Force | Out-Null
    }
    catch {
        $pullError = $_.Exception.Message
    }
    finally {
        Remove-SFTPSession -SessionId $sftp.SessionId | Out-Null
    }

    if ((Test-Path -LiteralPath $localFrame) -and ((Get-Item -LiteralPath $localFrame).Length -gt 0)) {
        $item = Get-Item -LiteralPath $localFrame
        $size = [int64]$item.Length
        $sha = (Get-FileHash -LiteralPath $localFrame -Algorithm SHA256).Hash.ToLowerInvariant()
        $statsRaw = & python -c "import cv2,json,numpy as np,sys; f=cv2.imread(sys.argv[1]); g=cv2.cvtColor(f, cv2.COLOR_BGR2GRAY); e=cv2.Canny(g,80,160); print(json.dumps({'width':int(f.shape[1]),'height':int(f.shape[0]),'channels':int(f.shape[2]),'mean_brightness':round(float(np.mean(g)),3),'brightness_stddev':round(float(np.std(g)),3),'edge_pixel_ratio':round(float(np.count_nonzero(e))/float(e.size),6)}))" $localFrame
        if ($LASTEXITCODE -eq 0 -and $statsRaw) {
            $stats = $statsRaw | ConvertFrom-Json
        }
    }
}

$success = [bool]($capture -and $capture.status -eq "ok" -and $size -gt 0)
$payload = [ordered]@{
    packet_type = "mim-arm-camera-capture-status-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    objective_id = "MIM-ARM-CAMERA-CAPTURE-BRIDGE-V1"
    status = if ($success) { "completed_with_evidence" } else { "blocked_with_evidence" }
    success = $success
    source = "mim_arm_capture_frame_endpoint"
    role = "arm_mounted_camera_for_workspace_exploration"
    capture_url = $captureUrl
    capture_response = $capture
    capture_error = $captureError
    arm_host_frame_path = $remoteArmFrame
    local_frame_path = if ($success) { $localFrame } else { "" }
    remote_frame_path = if ($UploadToMim -and $success) { $remoteMimFrame } else { "" }
    frame = @{
        exists = $success
        sha256 = $sha
        size_bytes = $size
        stats = $stats
        error = if ($success) { "" } elseif ($captureError) { "capture_endpoint_failed" } elseif ($pullError) { "sftp_pull_failed" } else { "capture_frame_missing" }
        pull_error = $pullError
        remote_status_path = $RemoteMimStatusPath
    }
    policy = "This bridge gives MIM direct arm-mounted camera evidence for table/area exploration and motion verification."
    next_recovery_action = if ($success) { "" } else { "Verify /capture_frame works on the arm host and that the capture path is readable over SFTP." }
}

$payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statusPath -Encoding UTF8

if ($UploadToMim) {
    $sendScript = Join-Path $repoRoot "scripts\Send-TODMimScript.ps1"
    if ($success) {
        $frameUploadPath = $localFrame.Substring($repoRoot.Length).TrimStart('\', '/')
        & $sendScript -EnvFile $EnvFile -LocalPath $frameUploadPath -RemotePath $remoteMimFrame | Out-Null
    }
    $statusUploadPath = $statusPath.Substring($repoRoot.Length).TrimStart('\', '/')
    & $sendScript -EnvFile $EnvFile -LocalPath $statusUploadPath -RemotePath $RemoteMimStatusPath | Out-Null
}

Get-Content -LiteralPath $statusPath -Raw
