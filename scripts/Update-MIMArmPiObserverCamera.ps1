param(
    [string]$EnvFile = ".env",
    [string]$Device = "/dev/video0",
    [string]$OutputDir = "runtime\shared\arm_table_observer_pi",
    [string]$RemoteArmDir = "/home/testpilot/mim_arm/runtime/shared/arm_table_observer_pi",
    [string]$RemoteMimDir = "/home/testpilot/mim/runtime/shared/arm_table_observer_pi",
    [string]$RemoteMimStatusPath = "/home/testpilot/mim/runtime/shared/MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json",
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

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$leaf = "$timestamp-pi-arm-observer.jpg"
$remoteArmFrame = "$RemoteArmDir/$leaf"
$localFrame = Join-Path $outputAbs $leaf
$localStatus = Join-Path $repoRoot "runtime\shared\MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json"
$remoteMimFrame = "$RemoteMimDir/$leaf"

Import-Module Posh-SSH -ErrorAction Stop
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = [pscredential]::new($userName, $securePassword)
$ssh = New-SSHSession -ComputerName $hostName -Port ([int]$port) -Credential $credential -AcceptKey -ConnectionTimeout 30000
$sftp = New-SFTPSession -ComputerName $hostName -Port ([int]$port) -Credential $credential -AcceptKey -ConnectionTimeout 30000

try {
    $captureCommand = @"
mkdir -p '$RemoteArmDir'
ffmpeg -hide_banner -y -f v4l2 -input_format mjpeg -video_size 1280x720 -i '$Device' -frames:v 1 '$remoteArmFrame' >/tmp/mim_pi_observer_ffmpeg.out 2>/tmp/mim_pi_observer_ffmpeg.err
rc=`$?
sha=`$(sha256sum '$remoteArmFrame' 2>/dev/null | awk '{print `$1}')
size=`$(stat -c%s '$remoteArmFrame' 2>/dev/null || echo 0)
python3 - '$remoteArmFrame' <<'PY'
import json, sys
try:
    import cv2, numpy as np
    frame = cv2.imread(sys.argv[1])
    if frame is None:
        raise RuntimeError("cv2.imread_failed")
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 80, 160)
    print(json.dumps({
        "width": int(frame.shape[1]),
        "height": int(frame.shape[0]),
        "channels": int(frame.shape[2]) if len(frame.shape) > 2 else 1,
        "mean_brightness": round(float(np.mean(gray)), 3),
        "brightness_stddev": round(float(np.std(gray)), 3),
        "edge_pixel_ratio": round(float(np.count_nonzero(edges)) / float(edges.size), 6),
    }))
except Exception as exc:
    print(json.dumps({"error": f"{type(exc).__name__}: {exc}"}))
PY
echo __CAPTURE_META__
echo rc:`$rc
echo sha:`$sha
echo size:`$size
echo stderr:
cat /tmp/mim_pi_observer_ffmpeg.err
"@
    $capture = Invoke-SSHCommand -SessionId $ssh.SessionId -Command $captureCommand -TimeOut 60
    $output = @($capture.Output)
    $joined = ($output -join "`n")
    $statsLine = ($output | Where-Object { $_ -match '^\{' } | Select-Object -First 1)
    $stats = if ($statsLine) { $statsLine | ConvertFrom-Json } else { [pscustomobject]@{} }
    $rc = if ($joined -match 'rc:(\d+)') { [int]$Matches[1] } else { 999 }
    $sha = if ($joined -match 'sha:([a-fA-F0-9]{64})') { $Matches[1].ToLowerInvariant() } else { "" }
    $size = if ($joined -match 'size:(\d+)') { [int64]$Matches[1] } else { 0 }

    if ($rc -eq 0 -and $size -gt 0) {
        Get-SFTPItem -SessionId $sftp.SessionId -Path $remoteArmFrame -Destination $outputAbs -Force | Out-Null
    }

    $payload = [ordered]@{
        packet_type = "mim-arm-pi-table-observer-status-v1"
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        objective_id = "MIM-ARM-PI-TABLE-OBSERVER-CAMERA-V1"
        status = if ($rc -eq 0 -and $size -gt 0) { "completed_with_evidence" } else { "blocked_with_evidence" }
        success = [bool]($rc -eq 0 -and $size -gt 0)
        source = "mim_arm_pi_camera_bridge"
        role = "fixed_external_observer_for_arm_table"
        device = $Device
        camera_name = "EMEET SmartCam S600 on arm Pi"
        local_frame_path = if (Test-Path -LiteralPath $localFrame) { $localFrame } else { "" }
        arm_host_frame_path = $remoteArmFrame
        remote_frame_path = if ($UploadToMim -and $rc -eq 0 -and $size -gt 0) { $remoteMimFrame } else { "" }
        frame = @{
            exists = [bool]($rc -eq 0 -and $size -gt 0)
            sha256 = $sha
            size_bytes = $size
            stats = $stats
            error = if ($rc -eq 0 -and $size -gt 0) { "" } else { "pi_camera_capture_failed" }
            remote_status_path = $RemoteMimStatusPath
        }
        capture_method = "ffmpeg v4l2 mjpeg /dev/video0 on arm Pi"
        capture_output = $joined
        policy = "This Pi camera is the preferred fixed arm/table observer for MIM motion verification and workspace reference."
        next_recovery_action = if ($rc -eq 0 -and $size -gt 0) { "" } else { "Verify the Pi camera is connected and not busy, then rerun this bridge." }
    }
    $payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $localStatus -Encoding UTF8
}
finally {
    Remove-SFTPSession -SessionId $sftp.SessionId | Out-Null
    Remove-SSHSession -SessionId $ssh.SessionId | Out-Null
}

if ($UploadToMim) {
    $sendScript = Join-Path $repoRoot "scripts\Send-TODMimScript.ps1"
    if ((Test-Path -LiteralPath $localFrame) -and ((Get-Item -LiteralPath $localFrame).Length -gt 0)) {
        $frameUploadPath = $localFrame.Substring($repoRoot.Length).TrimStart('\', '/')
        & $sendScript -EnvFile $EnvFile -LocalPath $frameUploadPath -RemotePath $remoteMimFrame | Out-Null
    }
    $statusUploadPath = $localStatus.Substring($repoRoot.Length).TrimStart('\', '/')
    & $sendScript -EnvFile $EnvFile -LocalPath $statusUploadPath -RemotePath $RemoteMimStatusPath | Out-Null
}

Get-Content -LiteralPath $localStatus -Raw
