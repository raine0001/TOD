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
STATUS_PATH = SHARED / "MIM_ARM_SIDE_SEAT_GRIP_REPRODUCTION.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.35
KNOWN_GOOD_POSE = [72, 90, 24, 108, 89, 22]
OPEN_CLAW_ANGLE = 99
GRIP_CLAW_ANGLE = 22
LIFT_ELBOW_DELTA = 10


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


def current_pose() -> list[int]:
    state = request_json("/arm_state")
    data = state.get("data") if isinstance(state.get("data"), dict) else {}
    pose = data.get("current_pose") if isinstance(data.get("current_pose"), list) else []
    return [int(value) for value in pose[:6]] if len(pose) >= 6 else []


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
                "motion_profile": "mim_side_seat_grip_reproduction_slow",
                "step_degrees": STEP_DEGREES,
            },
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "start": start, "target": target, "failed_at": angle, "commands": commands}
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def move_pose(target_pose: list[int], source: str) -> list[dict[str, Any]]:
    moves: list[dict[str, Any]] = []
    pose = current_pose()
    if len(pose) < 6:
        return [{"ok": False, "error": "current_pose_unavailable"}]
    # Move larger joints before claw; keep motions small because target is near current.
    for servo in [0, 1, 2, 3, 4, 5]:
        if pose[servo] == int(target_pose[servo]):
            continue
        result = slow_move(servo, pose[servo], int(target_pose[servo]), f"{source}_servo_{servo}")
        moves.append(result)
        if not result.get("ok"):
            break
        pose[servo] = int(target_pose[servo])
    return moves


def capture_arm(label: str) -> dict[str, Any]:
    result = request_json("/capture_frame", {}, timeout=10.0)
    output_path = ""
    if result.get("ok") and isinstance(result.get("data"), dict):
        output_path = str(result["data"].get("output_path") or "")
    local_path = ""
    if output_path:
        # Local bridge pulls latest capture for durable local/MIM evidence.
        subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT / "scripts" / "Update-MIMArmCameraCapture.ps1"),
                "-EnvFile",
                ".env",
                "-UploadToMim",
            ],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=90,
            check=False,
        )
        status_path = SHARED / "MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json"
        try:
            status = json.loads(status_path.read_text(encoding="utf-8-sig"))
            local_path = str(status.get("local_frame_path") or "")
        except Exception:
            local_path = ""
    return {
        "label": label,
        "ok": bool(result.get("ok")),
        "capture_result": result,
        "local_frame_path": local_path,
        "analysis": analyze_arm_frame(local_path) if local_path else {},
    }


def analyze_arm_frame(path: str) -> dict[str, Any]:
    image = cv2.imread(path)
    if image is None:
        return {"ok": False, "error": "cv2_imread_failed"}
    h, w = image.shape[:2]
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(hsv, np.array([92, 75, 70]), np.array([132, 255, 255]))
    count, _labels, stats, centers = cv2.connectedComponentsWithStats(mask, 8)
    components: list[dict[str, Any]] = []
    for idx in range(1, count):
        area = int(stats[idx, cv2.CC_STAT_AREA])
        if area < 100:
            continue
        x = int(stats[idx, cv2.CC_STAT_LEFT])
        y = int(stats[idx, cv2.CC_STAT_TOP])
        bw = int(stats[idx, cv2.CC_STAT_WIDTH])
        bh = int(stats[idx, cv2.CC_STAT_HEIGHT])
        cx, cy = centers[idx]
        components.append(
            {
                "area": area,
                "bbox": {"x": x, "y": y, "width": bw, "height": bh},
                "center": {"x": round(float(cx), 2), "y": round(float(cy), 2)},
            }
        )
    components.sort(key=lambda item: int(item["area"]), reverse=True)
    largest = components[0] if components else {}
    centered = bool(largest and 160 <= largest["center"]["x"] <= 480 and 190 <= largest["center"]["y"] <= 560)
    large_enough = bool(largest and int(largest["area"]) >= 18000)
    return {
        "ok": bool(largest),
        "image": {"width": w, "height": h},
        "largest_blue_component": largest,
        "component_count": len(components),
        "block_visible_and_centered": bool(centered and large_enough),
        "policy": "Wrist-camera verifier: blue block should be large and centered between jaw tips.",
    }


def all_moves_ok(moves: list[dict[str, Any]]) -> bool:
    return all(item.get("ok") for item in moves)


def main() -> int:
    blockers: list[str] = []
    observations: list[dict[str, Any]] = []
    moves: list[dict[str, Any]] = []

    start_pose = current_pose()
    if len(start_pose) < 6:
        blockers.append("current_pose_unavailable")

    if not blockers:
        observations.append(capture_arm("baseline_operator_known_good_hold"))

        open_pose = list(KNOWN_GOOD_POSE)
        open_pose[5] = OPEN_CLAW_ANGLE
        open_moves = move_pose(open_pose, "mim_side_seat_release_to_open_training_pose")
        moves.append({"action": "release_to_open_training_pose", "moves": open_moves})
        if not all_moves_ok(open_moves):
            blockers.append("release_to_open_training_pose_failed")
        time.sleep(0.8)
        observations.append(capture_arm("after_release_open_pose"))

    if not blockers:
        close_pose = list(KNOWN_GOOD_POSE)
        close_pose[5] = GRIP_CLAW_ANGLE
        close_moves = move_pose(close_pose, "mim_side_seat_reclose_to_known_good_22")
        moves.append({"action": "reclose_to_known_good_22", "moves": close_moves})
        if not all_moves_ok(close_moves):
            blockers.append("reclose_to_known_good_failed")
        time.sleep(0.8)
        grip_obs = capture_arm("after_reclose_to_22_before_lift")
        observations.append(grip_obs)
        if not grip_obs.get("analysis", {}).get("block_visible_and_centered"):
            blockers.append("wrist_camera_did_not_verify_seated_block_before_lift")

    if not blockers:
        pose = current_pose()
        lift_target = min(180, int(pose[2]) + LIFT_ELBOW_DELTA)
        lift = slow_move(2, int(pose[2]), lift_target, "mim_side_seat_grip_tiny_lift_verify")
        moves.append({"action": "tiny_lift_verify", "moves": [lift]})
        if not lift.get("ok"):
            blockers.append("tiny_lift_failed")
        time.sleep(0.8)
        lift_obs = capture_arm("after_tiny_lift_verify")
        observations.append(lift_obs)
        if not lift_obs.get("analysis", {}).get("block_visible_and_centered"):
            blockers.append("block_not_retained_in_wrist_camera_after_lift")

    final_success_pose = current_pose()

    # Do not leave the servo holding load unattended; preserve proof, then lower and release.
    cleanup_moves: list[dict[str, Any]] = []
    if final_success_pose and len(final_success_pose) >= 6:
        lower_pose = list(final_success_pose)
        lower_pose[2] = KNOWN_GOOD_POSE[2]
        if lower_pose[2] != final_success_pose[2]:
            cleanup_moves.extend(move_pose(lower_pose, "mim_side_seat_cleanup_lower_after_training"))
        open_pose = list(lower_pose)
        open_pose[5] = OPEN_CLAW_ANGLE
        cleanup_moves.extend(move_pose(open_pose, "mim_side_seat_cleanup_release_after_training"))
        moves.append({"action": "cleanup_lower_and_release", "moves": cleanup_moves})
        time.sleep(0.8)
        observations.append(capture_arm("final_cleanup_released_open_pose"))

    payload = {
        "packet_type": "mim-arm-side-seat-grip-reproduction-v1",
        "generated_at": now_iso(),
        "objective_id": "OBJ-0100",
        "status": "completed_pickup_with_wrist_camera_evidence" if not blockers else "blocked_with_evidence",
        "success": bool(not blockers),
        "learning_owner": "MIM using Dave's demonstrated known-good grip.",
        "known_good_pose": KNOWN_GOOD_POSE,
        "open_claw_angle": OPEN_CLAW_ANGLE,
        "target_claw_angle": GRIP_CLAW_ANGLE,
        "motion_policy": {
            "bounded_to_known_good_neighborhood": True,
            "step_degrees": STEP_DEGREES,
            "settle_seconds": SETTLE_SECONDS,
            "tiny_lift_elbow_delta": LIFT_ELBOW_DELTA,
            "cleanup_release_after_proof": True,
            "pc_fixed_observer_required_for_final_external_proof": False,
            "pc_fixed_observer_blocked": True,
        },
        "start_pose": start_pose,
        "final_success_pose_before_cleanup": final_success_pose,
        "final_pose_after_cleanup": current_pose(),
        "moves": moves,
        "observations": observations,
        "blockers": list(dict.fromkeys(blockers)),
        "success_definition": "MIM reproduced Dave's side-seat grip, closed to claw angle 22, and retained the blue block during a tiny lift in wrist-camera evidence.",
        "next_recovery_action": (
            "Recover fixed PC observer for external proof, then repeat this same side-seat grip reproduction with fixed-observer confirmation."
            if not blockers
            else "Use Dave's side-seat demonstration to adjust approach depth/orientation, then rerun from open pose."
        ),
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(
        {
            "status": payload["status"],
            "success": payload["success"],
            "start_pose": start_pose,
            "final_success_pose_before_cleanup": final_success_pose,
            "final_pose_after_cleanup": payload["final_pose_after_cleanup"],
            "blockers": payload["blockers"],
        },
        indent=2,
        sort_keys=True,
    ))
    return 0 if not blockers else 2


if __name__ == "__main__":
    raise SystemExit(main())
