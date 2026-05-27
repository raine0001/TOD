param(
    [string]$EnvFile = ".env",
    [string]$CameraName = "EMEET SmartCam S600",
    [string]$OutputDir = "runtime\shared\arm_table_observer",
    [string]$RemoteDir = "/home/testpilot/mim/runtime/shared/arm_table_observer",
    [string]$RemoteStatusPath = "/home/testpilot/mim/runtime/shared/MIM_ARM_TABLE_OBSERVER_STATUS.latest.json",
    [switch]$AllowFallbackCamera,
    [switch]$UploadToMim
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$outputAbs = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
New-Item -ItemType Directory -Force -Path $outputAbs | Out-Null

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$safeName = ($CameraName -replace '[^A-Za-z0-9_.-]+', '_').Trim('_')
if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "camera" }
$framePath = Join-Path $outputAbs "$timestamp-$safeName.jpg"
$statusPath = Join-Path $repoRoot "runtime\shared\MIM_ARM_TABLE_OBSERVER_STATUS.latest.json"

function Write-ObserverStatus {
    param([Parameter(Mandatory = $true)][hashtable]$Payload)
    ($Payload | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $statusPath -Encoding UTF8
}

function Get-ImageStats {
    param([Parameter(Mandatory = $true)][string]$Path)
    $statsPy = @'
import cv2, json, numpy as np, sys
frame = cv2.imread(sys.argv[1])
if frame is None:
    raise SystemExit(2)
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
'@
    $tmp = Join-Path $env:TEMP "mim_image_stats.py"
    Set-Content -Path $tmp -Value $statsPy -Encoding UTF8
    $raw = & python $tmp $Path
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($raw | ConvertFrom-Json)
}

$ffmpegFramePath = $framePath
$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$ffmpegOutput = & ffmpeg -hide_banner -y -f dshow -i "video=$CameraName" -frames:v 1 $ffmpegFramePath 2>&1
$ffmpegExit = $LASTEXITCODE
$ErrorActionPreference = $oldErrorActionPreference
if ($ffmpegExit -eq 0 -and (Test-Path -LiteralPath $ffmpegFramePath)) {
    $hash = (Get-FileHash -LiteralPath $ffmpegFramePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $item = Get-Item -LiteralPath $ffmpegFramePath
    $stats = Get-ImageStats -Path $ffmpegFramePath
    $remoteFramePath = "$RemoteDir/$([System.IO.Path]::GetFileName($ffmpegFramePath))"
    $payload = @{
        packet_type = "mim-arm-table-observer-status-v1"
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        objective_id = "MIM-ARM-TABLE-OBSERVER-CAMERA-V1"
        status = "completed_with_evidence"
        success = $true
        source = "operator_pc_camera_bridge"
        role = "fixed_external_observer_for_arm_table"
        requested_camera_name = $CameraName
        selected_camera_index = $null
        selection_note = "Captured from the named DirectShow device, not a virtual fallback."
        local_frame_path = $ffmpegFramePath
        remote_frame_path = $remoteFramePath
        frame = @{
            exists = $true
            sha256 = $hash
            size_bytes = [int64]$item.Length
            stats = $stats
            error = ""
            remote_status_path = $RemoteStatusPath
        }
        capture_method = "ffmpeg dshow named device"
        ffmpeg_error = ""
        policy = "This observer gives MIM a fixed external view for motion verification and workspace reference; raw frame retention is limited to the latest operator-authorized observer frame."
        next_recovery_action = ""
    }
    Write-ObserverStatus -Payload $payload
    if ($UploadToMim) {
        $sendScript = Join-Path $repoRoot 'scripts\Send-TODMimScript.ps1'
        $frameUploadPath = $ffmpegFramePath
        if ($frameUploadPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $frameUploadPath = $frameUploadPath.Substring($repoRoot.Length).TrimStart('\', '/')
        }
        $statusUploadPath = $statusPath
        if ($statusUploadPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $statusUploadPath = $statusUploadPath.Substring($repoRoot.Length).TrimStart('\', '/')
        }
        & $sendScript -EnvFile $EnvFile -LocalPath $frameUploadPath -RemotePath $remoteFramePath | Out-Null
        & $sendScript -EnvFile $EnvFile -LocalPath $statusUploadPath -RemotePath $RemoteStatusPath | Out-Null
    }
    Get-Content -LiteralPath $statusPath -Raw
    return
}

if (-not $AllowFallbackCamera) {
    $payload = @{
        packet_type = "mim-arm-table-observer-status-v1"
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        objective_id = "MIM-ARM-TABLE-OBSERVER-CAMERA-V1"
        status = "blocked_with_evidence"
        success = $false
        source = "operator_pc_camera_bridge"
        role = "fixed_external_observer_for_arm_table"
        requested_camera_name = $CameraName
        selected_camera_index = $null
        local_frame_path = ""
        remote_frame_path = ""
        frame = @{
            exists = $false
            sha256 = ""
            size_bytes = 0
            stats = @{}
            error = "named_camera_capture_failed"
            remote_status_path = $RemoteStatusPath
        }
        capture_method = "ffmpeg dshow named device"
        ffmpeg_error = (($ffmpegOutput | Out-String).Trim())
        policy = "This observer must use the physical arm-table camera unless AllowFallbackCamera is set. Virtual/blank camera frames are not accepted as arm-table evidence."
        next_recovery_action = "Close the application currently using the EMEET SmartCam S600 or select the correct physical arm-table camera, then rerun this bridge."
    }
    Write-ObserverStatus -Payload $payload
    if ($UploadToMim) {
        $sendScript = Join-Path $repoRoot 'scripts\Send-TODMimScript.ps1'
        $statusUploadPath = $statusPath
        if ($statusUploadPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $statusUploadPath = $statusUploadPath.Substring($repoRoot.Length).TrimStart('\', '/')
        }
        & $sendScript -EnvFile $EnvFile -LocalPath $statusUploadPath -RemotePath $RemoteStatusPath | Out-Null
    }
    Get-Content -LiteralPath $statusPath -Raw
    return
}

$python = @'
import argparse
import hashlib
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import cv2
import numpy as np


def now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def image_stats(frame):
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 80, 160)
    return {
        "width": int(frame.shape[1]),
        "height": int(frame.shape[0]),
        "channels": int(frame.shape[2]) if len(frame.shape) > 2 else 1,
        "mean_brightness": round(float(np.mean(gray)), 3),
        "brightness_stddev": round(float(np.std(gray)), 3),
        "edge_pixel_ratio": round(float(np.count_nonzero(edges)) / float(edges.size), 6),
    }


def probe_camera(index):
    cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
    if not cap.isOpened():
        return {"index": index, "openable": False, "error": "cv2.VideoCapture_not_opened"}
    try:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        time.sleep(0.2)
        ok, frame = cap.read()
        if not ok or frame is None:
            return {"index": index, "openable": True, "frame_ok": False, "error": "frame_read_failed"}
        return {"index": index, "openable": True, "frame_ok": True, "stats": image_stats(frame)}
    finally:
        cap.release()


def capture(index, output):
    cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
    if not cap.isOpened():
        return None, "cv2.VideoCapture_not_opened"
    try:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        frame = None
        for _ in range(8):
            ok, candidate = cap.read()
            if ok and candidate is not None:
                frame = candidate
            time.sleep(0.08)
        if frame is None:
            return None, "frame_read_failed"
        output.parent.mkdir(parents=True, exist_ok=True)
        ok = cv2.imwrite(str(output), frame, [int(cv2.IMWRITE_JPEG_QUALITY), 88])
        if not ok:
            return None, "cv2.imwrite_failed"
        return image_stats(frame), ""
    finally:
        cap.release()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--camera-name", required=True)
    parser.add_argument("--frame-path", required=True)
    parser.add_argument("--status-path", required=True)
    args = parser.parse_args()

    probes = [probe_camera(index) for index in range(6)]
    frame_path = Path(args.frame_path)
    status_path = Path(args.status_path)

    selected_index = None
    capture_stats = None
    capture_error = ""
    viable = []
    for probe in probes:
        stats = probe.get("stats") if isinstance(probe.get("stats"), dict) else {}
        if probe.get("frame_ok"):
            # Reject virtual/blank placeholder frames. They can be technically
            # openable but provide no arm-table evidence.
            if (
                float(stats.get("mean_brightness", 0)) < 60.0
                or float(stats.get("brightness_stddev", 0)) < 40.0
                or float(stats.get("edge_pixel_ratio", 0)) < 0.01
            ):
                probe["frame_rejected"] = "blank_or_virtual_placeholder"
                continue
            score = (
                float(stats.get("brightness_stddev", 0)) * 2.0
                + float(stats.get("edge_pixel_ratio", 0)) * 5000.0
                + min(float(stats.get("mean_brightness", 0)), 180.0) * 0.2
            )
            viable.append((score, int(probe["index"])))
    if viable:
        viable.sort(reverse=True)
        selected_index = viable[0][1]
        capture_stats, capture_error = capture(selected_index, frame_path)
    if selected_index is None:
        capture_error = "no_openable_camera_with_frame"

    sha256 = ""
    size_bytes = 0
    if frame_path.exists():
        data = frame_path.read_bytes()
        sha256 = hashlib.sha256(data).hexdigest()
        size_bytes = len(data)

    payload = {
        "packet_type": "mim-arm-table-observer-status-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-TABLE-OBSERVER-CAMERA-V1",
        "status": "completed_with_evidence" if sha256 else "blocked_with_evidence",
        "success": bool(sha256),
        "source": "operator_pc_camera_bridge",
        "role": "fixed_external_observer_for_arm_table",
        "requested_camera_name": args.camera_name,
        "selected_camera_index": selected_index,
        "selection_note": "Selected the local camera index with the strongest visible frame score. Use operator feedback to pin this to the physical arm-table camera if needed.",
        "local_frame_path": str(frame_path),
        "remote_frame_path": "",
        "frame": {
            "exists": bool(sha256),
            "sha256": sha256,
            "size_bytes": size_bytes,
            "stats": capture_stats or {},
            "error": capture_error,
        },
        "camera_index_probes": probes,
        "policy": "This observer gives MIM a fixed external view for motion verification and workspace reference; raw frame retention is limited to the latest operator-authorized observer frame.",
        "next_recovery_action": "" if sha256 else "Close apps using the physical EMEET camera or specify a different physical arm-table camera; virtual/blank camera frames are not accepted.",
    }
    status_path.parent.mkdir(parents=True, exist_ok=True)
    status_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if sha256 else 2


if __name__ == "__main__":
    raise SystemExit(main())
'@

$tempPy = Join-Path $env:TEMP "mim_arm_table_observer_capture.py"
Set-Content -Path $tempPy -Value $python -Encoding UTF8

$capture = & python $tempPy --camera-name $CameraName --frame-path $framePath --status-path $statusPath
$exit = $LASTEXITCODE
$capture | Write-Output
if ($exit -ne 0) {
    throw "Camera observer capture failed with exit code $exit"
}

$status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
$remoteFramePath = "$RemoteDir/$([System.IO.Path]::GetFileName($framePath))"
$status.remote_frame_path = $remoteFramePath
$status.frame | Add-Member -NotePropertyName remote_status_path -NotePropertyValue $RemoteStatusPath -Force
$status | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statusPath -Encoding UTF8

if ($UploadToMim) {
    $sendScript = Join-Path $repoRoot 'scripts\Send-TODMimScript.ps1'
    if (-not (Test-Path -LiteralPath $sendScript)) { throw "Upload script not found: $sendScript" }
    $frameUploadPath = $framePath
    if ($frameUploadPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $frameUploadPath = $frameUploadPath.Substring($repoRoot.Length).TrimStart('\', '/')
    }
    $statusUploadPath = $statusPath
    if ($statusUploadPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $statusUploadPath = $statusUploadPath.Substring($repoRoot.Length).TrimStart('\', '/')
    }
    & $sendScript -EnvFile $EnvFile -LocalPath $frameUploadPath -RemotePath $remoteFramePath | Out-Null
    & $sendScript -EnvFile $EnvFile -LocalPath $statusUploadPath -RemotePath $RemoteStatusPath | Out-Null
}

Get-Content -LiteralPath $statusPath -Raw
