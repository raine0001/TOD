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
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_VISUAL_SERVO_PROBE.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
SLOW_STEP_DEG = 2
SLOW_SETTLE_SECONDS = 0.35


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def request_json(endpoint: str, payload: dict[str, Any] | None = None, timeout: float = 8.0) -> dict[str, Any]:
    if payload is None:
        request = urllib.request.Request(f"{ARM_HOST}{endpoint}", method="GET")
    else:
        body = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            f"{ARM_HOST}{endpoint}",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return {"ok": True, "data": json.loads(response.read().decode("utf-8"))}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def slow_move_servo(servo: int, start_angle: int, target_angle: int, *, source: str) -> dict[str, Any]:
    start = max(0, min(180, int(start_angle)))
    target = max(0, min(180, int(target_angle)))
    direction = 1 if target > start else -1
    angle = start
    commands: list[dict[str, Any]] = []
    while angle != target:
        angle = angle + (direction * SLOW_STEP_DEG)
        if (direction > 0 and angle > target) or (direction < 0 and angle < target):
            angle = target
        result = request_json(
            "/move",
            {
                "servo": servo,
                "angle": angle,
                "source": source,
                "motion_profile": "slow_visual_servo_probe",
                "step_degrees": SLOW_STEP_DEG,
            },
            timeout=8.0,
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "failed_at_angle": angle, "commands": commands}
        time.sleep(SLOW_SETTLE_SECONDS)
    return {
        "ok": True,
        "servo": servo,
        "start_angle": start,
        "target_angle": target,
        "step_degrees": SLOW_STEP_DEG,
        "settle_seconds": SLOW_SETTLE_SECONDS,
        "commands": commands,
    }


def move_pose(current_pose: list[int], target_pose: list[int], *, source: str) -> list[dict[str, Any]]:
    moves: list[dict[str, Any]] = []
    for servo, target in enumerate(target_pose[:6]):
        start = int(current_pose[servo])
        if start == int(target):
            moves.append({"servo": servo, "target_angle": int(target), "result": {"ok": True, "commands": []}})
            continue
        result = slow_move_servo(servo, start, int(target), source=source)
        moves.append({"servo": servo, "target_angle": int(target), "result": result})
        if result.get("ok"):
            current_pose[servo] = int(target)
        else:
            break
        time.sleep(0.45)
    return moves


def capture_pi_observer() -> dict[str, Any]:
    command = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ROOT / "scripts" / "Update-MIMArmPiObserverCamera.ps1"),
        "-UploadToMim",
    ]
    completed = subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, timeout=90, check=False)
    status_path = SHARED / "MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json"
    status = json.loads(status_path.read_text(encoding="utf-8-sig")) if status_path.exists() else {}
    return {
        "ok": completed.returncode == 0 and bool(status.get("success")),
        "returncode": completed.returncode,
        "stdout_tail": completed.stdout[-1000:],
        "stderr_tail": completed.stderr[-1000:],
        "status": status,
        "frame_path": status.get("local_frame_path", ""),
    }


def components(mask: np.ndarray, *, min_area: int) -> list[dict[str, Any]]:
    count, labels, stats, centers = cv2.connectedComponentsWithStats(mask, 8)
    found: list[dict[str, Any]] = []
    for idx in range(1, count):
        area = int(stats[idx, cv2.CC_STAT_AREA])
        if area < min_area:
            continue
        x = int(stats[idx, cv2.CC_STAT_LEFT])
        y = int(stats[idx, cv2.CC_STAT_TOP])
        w = int(stats[idx, cv2.CC_STAT_WIDTH])
        h = int(stats[idx, cv2.CC_STAT_HEIGHT])
        cx, cy = centers[idx]
        found.append({"area": area, "bbox": {"x": x, "y": y, "width": w, "height": h}, "center": {"x": float(cx), "y": float(cy)}})
    return sorted(found, key=lambda item: int(item["area"]), reverse=True)


def detect_scene(frame_path: str) -> dict[str, Any]:
    image = cv2.imread(frame_path)
    if image is None:
        return {"ok": False, "error": "cv2_imread_failed", "frame_path": frame_path}
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)

    # The blue block is on the left/middle table region in the fixed Pi observer.
    tx1, ty1, tx2, ty2 = 430, 300, 620, 430
    target_mask = cv2.inRange(hsv[ty1:ty2, tx1:tx2], np.array([90, 120, 100]), np.array([135, 255, 255]))
    target_components = components(target_mask, min_area=40)
    for item in target_components:
        item["bbox"]["x"] += tx1
        item["bbox"]["y"] += ty1
        item["center"]["x"] += tx1
        item["center"]["y"] += ty1
    target = target_components[0] if target_components else {}

    # The claw is the largest bright/low-saturation end-effector component in the right half.
    gx1, gy1, gx2, gy2 = 560, 30, 1270, 500
    gripper_mask = cv2.inRange(hsv[gy1:gy2, gx1:gx2], np.array([0, 0, 145]), np.array([179, 80, 255]))
    gripper_components = [
        item
        for item in components(gripper_mask, min_area=180)
        if item["bbox"]["width"] >= 25 and item["bbox"]["height"] >= 8
    ]
    for item in gripper_components:
        item["bbox"]["x"] += gx1
        item["bbox"]["y"] += gy1
        item["center"]["x"] += gx1
        item["center"]["y"] += gy1
    # Prefer the end-effector/claw over the arm links: it is usually bright, wide, and far right.
    gripper_components.sort(
        key=lambda item: (
            float(item["center"]["x"]) * 2.0
            + min(float(item["area"]), 7000.0) * 0.02
            - abs(float(item["center"]["y"]) - 280.0) * 0.2
        ),
        reverse=True,
    )
    gripper = gripper_components[0] if gripper_components else {}

    distance_px = None
    if target and gripper:
        dx = float(gripper["center"]["x"]) - float(target["center"]["x"])
        dy = float(gripper["center"]["y"]) - float(target["center"]["y"])
        distance_px = round((dx * dx + dy * dy) ** 0.5, 2)

    return {
        "ok": bool(target and gripper),
        "frame_path": frame_path,
        "target": target,
        "target_candidates": target_components[:5],
        "gripper": gripper,
        "gripper_candidates": gripper_components[:6],
        "distance_px": distance_px,
        "target_detection_roi": {"x1": tx1, "y1": ty1, "x2": tx2, "y2": ty2},
        "gripper_detection_roi": {"x1": gx1, "y1": gy1, "x2": gx2, "y2": gy2},
    }


def main() -> int:
    generated_at = now_iso()
    arm_state = request_json("/arm_state")
    pose = (arm_state.get("data") or {}).get("current_pose") if isinstance(arm_state.get("data"), dict) else []
    serial = (arm_state.get("data") or {}).get("serial") if isinstance(arm_state.get("data"), dict) else {}
    blockers: list[str] = []
    if not arm_state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if not isinstance(pose, list) or len(pose) < 6:
        blockers.append("current_pose_unavailable")
    start_pose = [int(value) for value in pose[:6]] if isinstance(pose, list) and len(pose) >= 6 else []

    objective = {
        "packet_type": "mim-arm-blue-block-visual-servo-probe-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-ARM-BLUE-BLOCK-VISUAL-SERVO-PROBE-V1",
        "goal": "Learn a no-contact visual approach map from fixed Pi observer evidence before any grip attempt.",
        "motion_policy": {
            "movement_type": "high_clearance_no_contact_candidate_pose_probe",
            "step_degrees": SLOW_STEP_DEG,
            "settle_seconds": SLOW_SETTLE_SECONDS,
            "return_to_start_after_each_candidate": True,
            "no_claw_close": True,
        },
    }

    candidates = [
        [89, 120, 110, 93, 103, 0],
        [75, 120, 110, 93, 103, 0],
        [105, 120, 110, 93, 103, 0],
        [89, 130, 130, 93, 103, 0],
        [75, 130, 130, 93, 103, 0],
        [105, 130, 130, 93, 103, 0],
    ]
    probes: list[dict[str, Any]] = []
    best: dict[str, Any] = {}

    if not blockers:
        baseline_capture = capture_pi_observer()
        baseline_scene = detect_scene(str(baseline_capture.get("frame_path") or "")) if baseline_capture.get("ok") else {}
        probes.append({"kind": "baseline", "pose": start_pose, "capture": baseline_capture, "scene": baseline_scene})
        if baseline_scene.get("distance_px") is not None:
            best = probes[-1]

        for index, target_pose in enumerate(candidates, start=1):
            working_pose = list(start_pose)
            out_moves = move_pose(working_pose, target_pose, source=f"mim_blue_block_visual_servo_candidate_{index}")
            time.sleep(0.8)
            capture = capture_pi_observer()
            scene = detect_scene(str(capture.get("frame_path") or "")) if capture.get("ok") else {}
            return_moves = move_pose(working_pose, start_pose, source=f"mim_blue_block_visual_servo_candidate_{index}_return")
            probe = {
                "kind": "candidate",
                "index": index,
                "target_pose": target_pose,
                "out_moves_ok": all((move.get("result") or {}).get("ok") for move in out_moves),
                "return_moves_ok": all((move.get("result") or {}).get("ok") for move in return_moves),
                "capture": capture,
                "scene": scene,
                "out_moves": out_moves,
                "return_moves": return_moves,
            }
            probes.append(probe)
            if scene.get("distance_px") is not None and (
                not best or float(scene["distance_px"]) < float((best.get("scene") or {}).get("distance_px") or 999999)
            ):
                best = probe

    if not best:
        blockers.append("visual_servo_probe_no_valid_target_and_gripper_detection")
    elif float((best.get("scene") or {}).get("distance_px") or 999999) > 180:
        blockers.append("no_candidate_pose_aligned_close_enough_for_grip")

    payload = {
        **objective,
        "status": "blocked_with_probe_evidence" if blockers else "candidate_alignment_ready_for_refinement",
        "success": False,
        "start_pose": start_pose,
        "candidate_count": len(candidates),
        "best_probe_summary": {
            "kind": best.get("kind"),
            "index": best.get("index"),
            "target_pose": best.get("target_pose") or best.get("pose"),
            "distance_px": (best.get("scene") or {}).get("distance_px"),
            "frame_path": ((best.get("capture") or {}).get("status") or {}).get("remote_frame_path"),
        },
        "probes": probes,
        "blockers": list(dict.fromkeys(blockers)),
        "next_recovery_action": (
            "Use the best candidate as a starting point for smaller visual-servo refinement, or bind a better gripper detector "
            "if gripper detection is unstable. Do not close claw until alignment is centered and collision/clearance is verified."
        ),
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
