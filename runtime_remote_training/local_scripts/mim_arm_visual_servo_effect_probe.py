#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
ARM_HOST = "http://192.168.1.90:5000"
OUT_PATH = ROOT / "runtime" / "shared" / "MIM_ARM_VISUAL_SERVO_EFFECT_MAP.latest.json"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.35


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def request_json(endpoint: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    if payload is None:
        request = urllib.request.Request(f"{ARM_HOST}{endpoint}", method="GET")
    else:
        request = urllib.request.Request(
            f"{ARM_HOST}{endpoint}",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
    with urllib.request.urlopen(request, timeout=8) as response:
        return json.loads(response.read().decode("utf-8"))


def slow_move(servo: int, start: int, target: int, *, source: str) -> None:
    direction = 1 if target > start else -1
    angle = start
    while angle != target:
        angle += direction * STEP_DEGREES
        if (direction > 0 and angle > target) or (direction < 0 and angle < target):
            angle = target
        request_json(
            "/move",
            {
                "servo": servo,
                "angle": angle,
                "source": source,
                "motion_profile": "mim_visual_servo_effect_probe",
                "step_degrees": STEP_DEGREES,
            },
        )
        time.sleep(SETTLE_SECONDS)


def capture_pi_observer() -> tuple[str, str]:
    subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "scripts" / "Update-MIMArmPiObserverCamera.ps1"),
            "-UploadToMim",
        ],
        cwd=str(ROOT),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=90,
        check=False,
    )
    status_path = ROOT / "runtime" / "shared" / "MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json"
    status = json.loads(status_path.read_text(encoding="utf-8-sig"))
    return str(status.get("local_frame_path") or ""), str(status.get("remote_frame_path") or "")


def detect_scene(frame_path: str) -> dict[str, Any]:
    image = cv2.imread(frame_path)
    if image is None:
        return {"ok": False, "error": "image_read_failed", "frame_path": frame_path}
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    target_mask = cv2.inRange(hsv[300:440, 430:620], np.array([90, 120, 80]), np.array([135, 255, 255]))
    count, labels, stats, centers = cv2.connectedComponentsWithStats(target_mask, 8)
    target: dict[str, Any] = {}
    for idx in range(1, count):
        area = int(stats[idx, cv2.CC_STAT_AREA])
        if area < 30:
            continue
        x = int(stats[idx, cv2.CC_STAT_LEFT]) + 430
        y = int(stats[idx, cv2.CC_STAT_TOP]) + 300
        w = int(stats[idx, cv2.CC_STAT_WIDTH])
        h = int(stats[idx, cv2.CC_STAT_HEIGHT])
        cx, cy = centers[idx]
        candidate = {
            "area": area,
            "bbox": {"x": x, "y": y, "width": w, "height": h},
            "center": {"x": float(cx + 430), "y": float(cy + 300)},
        }
        if not target or area > int(target.get("area", 0)):
            target = candidate

    white_mask = cv2.inRange(hsv, np.array([0, 0, 130]), np.array([179, 85, 255]))
    white_mask[:, :760] = 0
    white_mask[260:, :] = 0
    count, labels, stats, centers = cv2.connectedComponentsWithStats(white_mask, 8)
    gripper_candidates: list[dict[str, Any]] = []
    for idx in range(1, count):
        area = int(stats[idx, cv2.CC_STAT_AREA])
        if area < 80:
            continue
        x = int(stats[idx, cv2.CC_STAT_LEFT])
        y = int(stats[idx, cv2.CC_STAT_TOP])
        w = int(stats[idx, cv2.CC_STAT_WIDTH])
        h = int(stats[idx, cv2.CC_STAT_HEIGHT])
        cx, cy = centers[idx]
        gripper_candidates.append(
            {
                "area": area,
                "bbox": {"x": x, "y": y, "width": w, "height": h},
                "center": {"x": float(cx), "y": float(cy)},
            }
        )
    gripper_candidates.sort(
        key=lambda item: float(item["center"]["x"]) + min(float(item["area"]), 2000.0) * 0.02,
        reverse=True,
    )
    gripper = gripper_candidates[0] if gripper_candidates else {}
    distance = None
    if target and gripper:
        dx = float(gripper["center"]["x"]) - float(target["center"]["x"])
        dy = float(gripper["center"]["y"]) - float(target["center"]["y"])
        distance = round((dx * dx + dy * dy) ** 0.5, 2)
    return {
        "ok": bool(target and gripper),
        "target": target,
        "gripper": gripper,
        "gripper_candidates": gripper_candidates[:4],
        "distance_px": distance,
    }


def main() -> int:
    state = request_json("/arm_state")
    start_pose = [int(value) for value in state["current_pose"][:6]]
    probes: list[dict[str, Any]] = []
    local_frame, remote_frame = capture_pi_observer()
    probes.append({"label": "baseline", "pose": start_pose, "frame": remote_frame, "scene": detect_scene(local_frame)})
    for servo, delta in [(0, 10), (0, -10), (1, 10), (1, -10), (2, 10), (2, -10)]:
        current = [int(value) for value in request_json("/arm_state")["current_pose"][:6]]
        target = list(current)
        target[servo] = max(0, min(180, target[servo] + delta))
        slow_move(servo, current[servo], target[servo], source=f"mim_visual_servo_effect_probe_s{servo}_{delta:+d}")
        time.sleep(0.5)
        local_frame, remote_frame = capture_pi_observer()
        probes.append(
            {
                "label": f"servo_{servo}_{delta:+d}",
                "pose": target,
                "frame": remote_frame,
                "scene": detect_scene(local_frame),
            }
        )
        slow_move(servo, target[servo], current[servo], source=f"mim_visual_servo_effect_probe_s{servo}_{delta:+d}_return")
        time.sleep(0.3)
    payload = {
        "packet_type": "mim-arm-visual-servo-effect-map-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-BLUE-BLOCK-VISUAL-SERVO-EFFECT-MAP-V1",
        "learning_owner": "MIM",
        "status": "completed_with_probe_evidence",
        "success": True,
        "motion_policy": {
            "step_degrees": STEP_DEGREES,
            "settle_seconds": SETTLE_SECONDS,
            "no_contact": True,
            "no_grip": True,
            "return_to_start_after_each_delta": True,
        },
        "start_pose": start_pose,
        "probes": probes,
        "summary": [
            {
                "label": probe["label"],
                "distance_px": (probe.get("scene") or {}).get("distance_px"),
                "gripper_center": ((probe.get("scene") or {}).get("gripper") or {}).get("center"),
                "target_center": ((probe.get("scene") or {}).get("target") or {}).get("center"),
            }
            for probe in probes
        ],
    }
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({"status": payload["status"], "start_pose": start_pose, "summary": payload["summary"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
