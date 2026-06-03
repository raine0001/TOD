#!/usr/bin/env python3
from __future__ import annotations

import json
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_BASE94_HOLD_LIFT_RETRY.latest.json"
ARM_HOST = "http://192.168.1.90:5000"

STEP_DEGREES = 2
SETTLE_SECONDS = 0.28
BASE = 94
APPROACH_POSE = [BASE, 101, 2, 90, 90, 90]
LOWER_POSE = [BASE, 112, 14, 90, 90, 90]
LIFT_OPEN_POSE = [BASE, 78, 60, 90, 90, 90]
LIFT_CLOSED_POSE = [BASE, 78, 60, 90, 90, 0]
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
    return [int(value) for value in angles[:6]] if isinstance(angles, list) and len(angles) >= 6 else []


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
                "page": "mim_arm_blue_block_base94_hold_lift_retry",
                "motion_profile": "base94_hold_during_lift_slow",
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


def move_pose(target: list[int], source: str, order: list[int]) -> dict[str, Any]:
    moves: list[dict[str, Any]] = []
    for servo in order:
        result = slow_move_servo(servo, target[servo], source)
        moves.append({"servo": servo, "target": target[servo], "result": result})
        if not result.get("ok"):
            return {"ok": False, "target_pose": target, "moves": moves}
        time.sleep(0.18)
    return {"ok": True, "target_pose": target, "moves": moves}


def distance(label: str) -> dict[str, Any]:
    readings = []
    for _ in range(5):
        readings.append(request_json("/distance/status", timeout=8.0))
        time.sleep(0.18)
    values = []
    for item in readings:
        data = item.get("data") if isinstance(item.get("data"), dict) else {}
        if item.get("ok") and data.get("distance_mm") is not None:
            values.append(int(data["distance_mm"]))
    return {"label": label, "readings": readings, "distance_mm_values": values, "min_mm": min(values) if values else None, "median_mm": sorted(values)[len(values) // 2] if values else None}


def capture(label: str) -> dict[str, Any]:
    return {"label": label, "camera": request_json("/capture_frame", {}, timeout=12.0), "distance": distance(label), "pose": current_pose()}


def main() -> int:
    started_at = now_iso()
    start_pose = current_pose()
    blockers: list[str] = []
    actions: list[dict[str, Any]] = []
    evidence: list[dict[str, Any]] = []
    state = request_json("/arm_state")
    data = state.get("data") if isinstance(state.get("data"), dict) else {}
    serial = data.get("serial") if isinstance(data.get("serial"), dict) else {}
    if not state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if len(start_pose) < 6:
        blockers.append("current_pose_unavailable")
    if not blockers:
        evidence.append(capture("start_before_base94_hold_lift_retry"))
        actions.append({"action": "open_at_base94_lift", "result": move_pose(LIFT_OPEN_POSE, "mim_base94_open_at_lift", [5, 0, 1, 2, 3, 4])})
        actions.append({"action": "approach_base94", "result": move_pose(APPROACH_POSE, "mim_base94_approach", [0, 1, 2, 3, 4, 5])})
        actions.append({"action": "lower_base94", "result": move_pose(LOWER_POSE, "mim_base94_lower", [1, 2, 0, 3, 4, 5])})
        evidence.append(capture("base94_lower_before_close"))
        actions.append({"action": "full_close_base94", "result": slow_move_servo(5, 0, "mim_base94_full_close")})
        evidence.append(capture("base94_after_close_before_hold_lift"))
        actions.append({"action": "lift_holding_base94", "result": move_pose(LIFT_CLOSED_POSE, "mim_base94_hold_lift", [1, 2, 3, 4, 5])})
        evidence.append(capture("base94_after_lift_verify"))
    for action in actions:
        result = action.get("result")
        if isinstance(result, dict) and not result.get("ok"):
            blockers.append(f"{action.get('action')}_failed")
    final_pose = current_pose()
    final_distance = distance("final_base94_hold_lift_retry")
    verified = bool(not blockers and isinstance(final_distance.get("min_mm"), int) and final_distance["min_mm"] <= VERIFY_HELD_MAX_MM)
    payload = {
        "packet_type": "mim-arm-blue-block-base94-hold-lift-retry-v1",
        "generated_at": now_iso(),
        "started_at": started_at,
        "objective_id": "MIM-ARM-BLUE-BLOCK-BASE94-HOLD-LIFT-RETRY-V1",
        "learning_owner": "MIM",
        "status": "completed_with_verified_pickup_evidence" if verified else ("blocked_with_evidence" if blockers else "motion_completed_pickup_not_verified"),
        "success": verified,
        "goal": "Retry pickup at base 94 while preserving base angle during lift so a side hook is not unseated by base return.",
        "start_pose": start_pose,
        "final_pose": final_pose,
        "actions": actions,
        "evidence": evidence,
        "final_distance": final_distance,
        "blockers": blockers,
        "next_recovery_action": "If this still misses, the next attempt should bias shoulder/elbow deeper or use operator-provided visual feedback before further contact attempts.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if verified else (2 if blockers else 1)


if __name__ == "__main__":
    raise SystemExit(main())
