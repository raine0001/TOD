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
STATUS_PATH = SHARED / "MIM_ARM_PC_OBSERVER_SERVO_EFFECT_MAP.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.35
PROBE_DELTA = 4


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def request_json(endpoint: str, payload: dict[str, Any] | None = None, timeout: float = 8.0) -> dict[str, Any]:
    if payload is None:
        request = urllib.request.Request(f"{ARM_HOST}{endpoint}", method="GET")
    else:
        request = urllib.request.Request(
            f"{ARM_HOST}{endpoint}",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return {"ok": True, "data": json.loads(response.read().decode("utf-8"))}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def slow_move(servo: int, start: int, target: int, source: str) -> dict[str, Any]:
    start = max(0, min(180, int(start)))
    target = max(0, min(180, int(target)))
    if start == target:
        return {"ok": True, "servo": servo, "start": start, "target": target, "commands": []}
    direction = 1 if target > start else -1
    angle = start
    commands: list[dict[str, Any]] = []
    while angle != target:
        angle += direction * STEP_DEGREES
        if (direction > 0 and angle > target) or (direction < 0 and angle < target):
            angle = target
        result = request_json(
            "/move",
            {
                "servo": servo,
                "angle": angle,
                "source": source,
                "motion_profile": "mim_pc_observer_small_no_contact_effect_probe",
                "step_degrees": STEP_DEGREES,
            },
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "start": start, "target": target, "failed_at": angle, "commands": commands}
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def capture_pc_observer(label: str) -> dict[str, Any]:
    command = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ROOT / "scripts" / "Update-MIMArmTableObserverCamera.ps1"),
        "-EnvFile",
        ".env",
        "-UploadToMim",
    ]
    completed = subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, timeout=90, check=False)
    status = read_json(SHARED / "MIM_ARM_TABLE_OBSERVER_STATUS.latest.json")
    return {
        "label": label,
        "ok": completed.returncode == 0 and bool(status.get("success")),
        "returncode": completed.returncode,
        "stdout_tail": completed.stdout[-800:],
        "stderr_tail": completed.stderr[-800:],
        "status": status,
        "frame_path": status.get("local_frame_path", ""),
    }


def components(mask: np.ndarray, *, min_area: int) -> list[dict[str, Any]]:
    count, _labels, stats, centers = cv2.connectedComponentsWithStats(mask, 8)
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


def detect(frame_path: str) -> dict[str, Any]:
    image = cv2.imread(frame_path)
    if image is None:
        return {"ok": False, "error": "cv2_imread_failed", "frame_path": frame_path}
    height, width = image.shape[:2]
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    blue_mask = cv2.inRange(hsv, np.array([92, 90, 80]), np.array([132, 255, 255]))
    blue = components(blue_mask, min_area=80)

    block_candidates = [
        item for item in blue
        if item["center"]["x"] > width * 0.40 and item["center"]["y"] > height * 0.45
    ]
    block = block_candidates[0] if block_candidates else {}
    effector_candidates = [
        item for item in blue
        if (
            item is not block
            and item["center"]["x"] > width * 0.45
            and height * 0.25 < item["center"]["y"] < height * 0.74
            and (not block or item["center"]["x"] > block["center"]["x"] + 35)
        )
    ]
    effector = effector_candidates[0] if effector_candidates else {}
    vector = {}
    distance = None
    if block and effector:
        dx = float(block["center"]["x"]) - float(effector["center"]["x"])
        dy = float(block["center"]["y"]) - float(effector["center"]["y"])
        distance = round((dx * dx + dy * dy) ** 0.5, 2)
        vector = {"dx_px_block_minus_effector": round(dx, 2), "dy_px_block_minus_effector": round(dy, 2)}
    return {
        "ok": bool(block and effector),
        "frame_path": frame_path,
        "image": {"width": width, "height": height},
        "blue_components_considered": blue[:10],
        "blue_block": block,
        "wrist_or_gripper_blue_reference": effector,
        "block_minus_effector_vector_px": vector,
        "distance_px": distance,
        "detection_policy": "PC observer bootstrap: the largest lower-table blue component is treated as the block; a separate blue arm hardware component to its right is treated as wrist/gripper reference.",
    }


def current_pose() -> list[int]:
    state = request_json("/arm_state")
    data = state.get("data") if isinstance(state.get("data"), dict) else {}
    pose = data.get("current_pose") if isinstance(data.get("current_pose"), list) else []
    return [int(value) for value in pose[:6]] if len(pose) >= 6 else []


def main() -> int:
    blockers: list[str] = []
    start_pose = current_pose()
    if not start_pose:
        blockers.append("current_pose_unavailable")

    baseline_capture = capture_pc_observer("baseline")
    baseline_scene = detect(str(baseline_capture.get("frame_path") or "")) if baseline_capture.get("ok") else {}
    if not baseline_scene.get("ok"):
        blockers.append("baseline_pc_observer_detection_failed")

    probes: list[dict[str, Any]] = []
    servos = [0, 1, 2, 3, 4]
    if not blockers:
        for servo in servos:
            for direction in [1, -1]:
                pose_before = current_pose()
                if not pose_before:
                    blockers.append("pose_lost_during_probe")
                    break
                target = max(0, min(180, pose_before[servo] + direction * PROBE_DELTA))
                move = slow_move(servo, pose_before[servo], target, f"mim_pc_observer_effect_probe_s{servo}_{direction:+d}")
                time.sleep(0.7)
                capture = capture_pc_observer(f"servo_{servo}_{direction:+d}")
                scene = detect(str(capture.get("frame_path") or "")) if capture.get("ok") else {}
                return_move = slow_move(servo, target, pose_before[servo], f"mim_pc_observer_effect_probe_s{servo}_{direction:+d}_return")
                time.sleep(0.4)

                base_distance = baseline_scene.get("distance_px")
                probe_distance = scene.get("distance_px")
                distance_delta = None
                if base_distance is not None and probe_distance is not None:
                    distance_delta = round(float(probe_distance) - float(base_distance), 2)

                probes.append({
                    "servo": servo,
                    "direction": direction,
                    "delta_degrees": PROBE_DELTA,
                    "pose_before": pose_before,
                    "target_angle": target,
                    "move_ok": bool(move.get("ok")),
                    "return_ok": bool(return_move.get("ok")),
                    "capture": capture,
                    "scene": scene,
                    "distance_delta_px": distance_delta,
                })
            if "pose_lost_during_probe" in blockers:
                break

    valid = [item for item in probes if item.get("distance_delta_px") is not None and item.get("move_ok") and item.get("return_ok")]
    best = sorted(valid, key=lambda item: float(item["distance_delta_px"]))[0] if valid else {}
    if not best:
        blockers.append("no_valid_servo_effect_measurement")

    payload = {
        "packet_type": "mim-arm-pc-observer-servo-effect-map-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-BLOCK-PICKUP-LEARNING-V2",
        "status": "completed_with_learning_evidence" if not blockers else "blocked_with_evidence",
        "success": bool(not blockers),
        "learning_owner": "MIM",
        "motion_policy": {
            "probe_delta_degrees": PROBE_DELTA,
            "step_degrees": STEP_DEGREES,
            "settle_seconds": SETTLE_SECONDS,
            "return_after_each_probe": True,
            "no_grip": True,
            "no_contact": True,
        },
        "start_pose": start_pose,
        "baseline": {"capture": baseline_capture, "scene": baseline_scene},
        "best_direction_to_reduce_observer_distance": {
            "servo": best.get("servo"),
            "direction": best.get("direction"),
            "distance_delta_px": best.get("distance_delta_px"),
            "current_interpretation": "negative distance_delta means this small motion moved the visible wrist/gripper reference closer to the blue block in the PC observer.",
        },
        "probes": probes,
        "blockers": list(dict.fromkeys(blockers)),
        "next_recovery_action": (
            "Use the best measured servo direction for a smaller iterative no-contact alignment step, then recapture. "
            "Do not run a claw close until the wrist/gripper reference is near the blue block and the arm camera confirms the claw is above the object."
        ),
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps({
        "status": payload["status"],
        "success": payload["success"],
        "start_pose": start_pose,
        "baseline_distance_px": baseline_scene.get("distance_px"),
        "best": payload["best_direction_to_reduce_observer_distance"],
        "blockers": payload["blockers"],
    }, indent=2, sort_keys=True))
    return 0 if not blockers else 2


if __name__ == "__main__":
    raise SystemExit(main())
