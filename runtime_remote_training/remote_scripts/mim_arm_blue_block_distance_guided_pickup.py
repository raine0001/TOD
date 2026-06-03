#!/usr/bin/env python3
from __future__ import annotations

import json
import statistics
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_DISTANCE_GUIDED_PICKUP.latest.json"
ARM_HOST = "http://192.168.1.90:5000"

OBJECTIVE_ID = "MIM-ARM-BLUE-BLOCK-DISTANCE-GUIDED-PICKUP-V1"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.28

LIFT_OPEN_POSE = [90, 78, 60, 90, 90, 90]
APPROACH_TEMPLATE = [90, 101, 2, 90, 90, 90]
LOWER_TEMPLATE = [90, 112, 14, 90, 90, 90]
LIFT_CLOSED_POSE = [90, 78, 60, 90, 90, 22]
CLAW_CLOSE_TARGET = 22
NEAR_TARGET_MIN_MM = 55
NEAR_TARGET_MAX_MM = 360
VERIFY_HELD_MAX_MM = 520


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def request_json(endpoint: str, payload: dict[str, Any] | None = None, timeout: float = 10.0) -> dict[str, Any]:
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


def clamp(angle: int) -> int:
    return max(0, min(180, int(angle)))


def current_pose() -> list[int]:
    result = request_json("/get_current_position", timeout=6.0)
    data = result.get("data") if isinstance(result.get("data"), dict) else {}
    angles = data.get("angles")
    if isinstance(angles, list) and len(angles) >= 6:
        return [int(value) for value in angles[:6]]
    state = request_json("/arm_state", timeout=6.0)
    state_data = state.get("data") if isinstance(state.get("data"), dict) else {}
    pose = state_data.get("current_pose")
    if isinstance(pose, list) and len(pose) >= 6:
        return [int(value) for value in pose[:6]]
    return []


def slow_move_servo(servo: int, target: int, source: str) -> dict[str, Any]:
    pose = current_pose()
    if len(pose) < 6:
        return {"ok": False, "servo": servo, "target": target, "reason": "current_pose_unavailable"}
    start = clamp(pose[servo])
    target = clamp(target)
    if start == target:
        return {"ok": True, "servo": servo, "start": start, "target": target, "commands": [], "skipped": True}
    step = STEP_DEGREES if target > start else -STEP_DEGREES
    angle = start
    commands: list[dict[str, Any]] = []
    while angle != target:
        next_angle = angle + step
        if (step > 0 and next_angle > target) or (step < 0 and next_angle < target):
            next_angle = target
        result = request_json(
            "/move",
            {
                "servo": servo,
                "angle": next_angle,
                "source": source,
                "page": "mim_arm_blue_block_distance_guided_pickup",
                "motion_profile": "mim_distance_guided_slow_pickup",
                "step_degrees": STEP_DEGREES,
            },
            timeout=8.0,
        )
        commands.append({"angle": next_angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "start": start, "target": target, "failed_at": next_angle, "commands": commands}
        angle = next_angle
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def move_pose(target: list[int], source: str, order: list[int] | None = None) -> dict[str, Any]:
    moves: list[dict[str, Any]] = []
    for servo in order or [0, 1, 2, 3, 4, 5]:
        result = slow_move_servo(servo, int(target[servo]), source)
        moves.append({"servo": servo, "target": int(target[servo]), "result": result})
        if not result.get("ok"):
            return {"ok": False, "target_pose": target, "moves": moves}
        time.sleep(0.18)
    return {"ok": True, "target_pose": target, "moves": moves}


def distance_sample(label: str, count: int = 3) -> dict[str, Any]:
    readings: list[dict[str, Any]] = []
    for _ in range(count):
        result = request_json("/distance/status", timeout=8.0)
        data = result.get("data") if isinstance(result.get("data"), dict) else {}
        readings.append({"ok": result.get("ok"), "data": data, "error": result.get("error")})
        time.sleep(0.18)
    mm_values = [
        int(item["data"]["distance_mm"])
        for item in readings
        if item.get("ok") and isinstance(item.get("data"), dict) and item["data"].get("distance_mm") is not None
    ]
    return {
        "label": label,
        "readings": readings,
        "distance_mm_values": mm_values,
        "median_mm": int(statistics.median(mm_values)) if mm_values else None,
        "min_mm": min(mm_values) if mm_values else None,
        "max_mm": max(mm_values) if mm_values else None,
    }


def capture(label: str) -> dict[str, Any]:
    return {
        "label": label,
        "camera": request_json("/capture_frame", {}, timeout=12.0),
        "distance": distance_sample(label, count=3),
        "pose": current_pose(),
    }


def load_json(path: Path) -> dict[str, Any]:
    try:
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8-sig"))
            return data if isinstance(data, dict) else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def lower_candidate(base: int, shoulder: int = 112, elbow: int = 14) -> dict[str, Any]:
    approach = list(APPROACH_TEMPLATE)
    lower = list(LOWER_TEMPLATE)
    approach[0] = base
    lower[0] = base
    lower[1] = shoulder
    lower[2] = elbow
    return {"base": base, "shoulder": shoulder, "elbow": elbow, "approach": approach, "lower": lower}


def candidate_score(scan: dict[str, Any]) -> int | None:
    distance = scan.get("distance")
    median = distance.get("median_mm") if isinstance(distance, dict) else None
    if not isinstance(median, int):
        return None
    if median < NEAR_TARGET_MIN_MM or median > NEAR_TARGET_MAX_MM:
        return None
    return median


def main() -> int:
    started_at = now_iso()
    blockers: list[str] = []
    actions: list[dict[str, Any]] = []
    evidence: list[dict[str, Any]] = []
    scans: list[dict[str, Any]] = []

    state = request_json("/arm_state", timeout=8.0)
    state_data = state.get("data") if isinstance(state.get("data"), dict) else {}
    serial = state_data.get("serial") if isinstance(state_data.get("serial"), dict) else {}
    start_pose = current_pose()
    if not state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if len(start_pose) < 6:
        blockers.append("current_pose_unavailable")

    if not blockers:
        evidence.append(capture("start_lift_pose_before_distance_guided_attempt"))
        actions.append({"action": "open_at_lift", "result": move_pose(LIFT_OPEN_POSE, "mim_distance_guided_open_at_lift", [5, 1, 2, 0, 3, 4])})
        if not actions[-1]["result"].get("ok"):
            blockers.append("open_at_lift_failed")

    candidates = [
        lower_candidate(90, 112, 14),
        lower_candidate(88, 112, 14),
        lower_candidate(92, 112, 14),
        lower_candidate(86, 112, 14),
        lower_candidate(94, 112, 14),
        lower_candidate(90, 110, 12),
        lower_candidate(90, 114, 16),
    ]
    best_scan: dict[str, Any] | None = None

    if not blockers:
        for candidate in candidates:
            actions.append(
                {
                    "action": "scan_candidate_approach",
                    "candidate": candidate,
                    "result": move_pose(candidate["approach"], "mim_distance_guided_scan_approach", [5, 0, 1, 2, 3, 4]),
                }
            )
            if not actions[-1]["result"].get("ok"):
                blockers.append("scan_candidate_approach_failed")
                break
            actions.append(
                {
                    "action": "scan_candidate_lower",
                    "candidate": candidate,
                    "result": move_pose(candidate["lower"], "mim_distance_guided_scan_lower", [1, 2, 0, 3, 4, 5]),
                }
            )
            if not actions[-1]["result"].get("ok"):
                blockers.append("scan_candidate_lower_failed")
                break
            time.sleep(0.4)
            scan_capture = capture(f"scan_base_{candidate['base']}_shoulder_{candidate['shoulder']}_elbow_{candidate['elbow']}")
            scan = {"candidate": candidate, "distance": scan_capture["distance"], "camera": scan_capture["camera"], "pose": scan_capture["pose"]}
            scan["score_mm"] = candidate_score(scan)
            scans.append(scan)
            if isinstance(scan["score_mm"], int) and (best_scan is None or scan["score_mm"] < int(best_scan["score_mm"])):
                best_scan = scan

    if not blockers and best_scan is None:
        blockers.append("no_close_distance_target_found_in_guarded_scan")

    if not blockers and best_scan is not None:
        best_candidate = best_scan["candidate"]
        actions.append(
            {
                "action": "return_to_best_lower_pose",
                "candidate": best_candidate,
                "result": move_pose(best_candidate["lower"], "mim_distance_guided_best_lower_pose", [5, 0, 1, 2, 3, 4]),
            }
        )
        if not actions[-1]["result"].get("ok"):
            blockers.append("return_to_best_lower_pose_failed")
        else:
            evidence.append(capture("best_lower_pose_before_close"))

    if not blockers:
        actions.append({"action": "close_claw_for_hole_hook", "result": slow_move_servo(5, CLAW_CLOSE_TARGET, "mim_distance_guided_close_for_hole_hook")})
        if not actions[-1]["result"].get("ok"):
            blockers.append("close_claw_failed")
        evidence.append(capture("after_close_before_lift"))

    if not blockers:
        actions.append({"action": "lift_for_pickup_verification", "result": move_pose(LIFT_CLOSED_POSE, "mim_distance_guided_lift_verify", [1, 2, 0, 3, 4, 5])})
        if not actions[-1]["result"].get("ok"):
            blockers.append("lift_for_pickup_verification_failed")
        evidence.append(capture("after_lift_verification"))

    final_pose = current_pose()
    final_distance = distance_sample("final_distance_after_lift", count=5)
    verified_pickup = bool(
        not blockers
        and isinstance(final_distance.get("min_mm"), int)
        and int(final_distance["min_mm"]) <= VERIFY_HELD_MAX_MM
    )
    status = "completed_with_verified_pickup_evidence" if verified_pickup else "motion_completed_pickup_not_verified"
    if blockers:
        status = "blocked_with_evidence"

    payload = {
        "packet_type": "mim-arm-blue-block-distance-guided-pickup-v1",
        "generated_at": now_iso(),
        "started_at": started_at,
        "objective_id": OBJECTIVE_ID,
        "learning_owner": "MIM",
        "status": status,
        "success": verified_pickup,
        "goal": "Use all available cameras plus I2C distance perception to pick up the blue block with the ARM claw.",
        "motion_policy": {
            "step_degrees": STEP_DEGREES,
            "settle_seconds": SETTLE_SECONDS,
            "guarded_scan_only_near_known_good_pose": True,
            "near_target_window_mm": [NEAR_TARGET_MIN_MM, NEAR_TARGET_MAX_MM],
            "verified_held_max_mm": VERIFY_HELD_MAX_MM,
            "no_transport_after_lift": True,
        },
        "start_pose": start_pose,
        "final_pose": final_pose,
        "actions": actions,
        "scan_candidates": candidates,
        "scans": scans,
        "best_scan": best_scan,
        "evidence": evidence,
        "final_distance": final_distance,
        "available_camera_evidence": {
            "arm_camera": load_json(SHARED / "MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json"),
            "pi_table_observer": load_json(SHARED / "MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json"),
            "pc_table_observer": load_json(SHARED / "MIM_ARM_TABLE_OBSERVER_STATUS.latest.json"),
            "policy": "Use every fresh available camera; if fixed observers are absent or blank, carry those blockers explicitly and proceed with arm camera plus I2C distance.",
        },
        "blockers": blockers,
        "next_recovery_action": (
            "Operator can visually confirm whether the claw hooked the block; if not, use best_scan and final captures to bias the next base/shoulder offset."
            if not verified_pickup
            else "Hold position; pickup is distance-verified, operator can decide whether to place or release."
        ),
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if verified_pickup else (2 if blockers else 1)


if __name__ == "__main__":
    raise SystemExit(main())
