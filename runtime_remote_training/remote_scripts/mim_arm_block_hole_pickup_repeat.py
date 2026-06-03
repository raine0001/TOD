#!/usr/bin/env python3
from __future__ import annotations

import json
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_BLOCK_HOLE_PICKUP_REPEAT.latest.json"
ARM_HOST = "http://192.168.1.90:5000"

STEP_DEGREES = 2
SETTLE_SECONDS = 0.28
OBJECTIVE_ID = "MIM-ARM-BLOCK-HOLE-PICKUP-REPEAT-V1"

APPROACH_POSE = [90, 101, 2, 90, 90, 90]
LOWER_POSE = [90, 112, 14, 90, 90, 90]
CLOSE_POSE = [90, 112, 14, 90, 90, 22]
LIFT_POSE = [90, 78, 60, 90, 90, 22]


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


def current_pose() -> list[int]:
    result = request_json("/get_current_position")
    data = result.get("data") if isinstance(result.get("data"), dict) else {}
    angles = data.get("angles")
    if isinstance(angles, list) and len(angles) >= 6:
        return [int(value) for value in angles[:6]]
    state = request_json("/arm_state")
    state_data = state.get("data") if isinstance(state.get("data"), dict) else {}
    pose = state_data.get("current_pose")
    if isinstance(pose, list) and len(pose) >= 6:
        return [int(value) for value in pose[:6]]
    return []


def slow_move_servo(servo: int, target: int, source: str) -> dict[str, Any]:
    pose = current_pose()
    if len(pose) < 6:
        return {"ok": False, "servo": servo, "target": target, "reason": "current_pose_unavailable"}
    start = max(0, min(180, int(pose[servo])))
    target = max(0, min(180, int(target)))
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
                "page": "mim_arm_block_hole_pickup_repeat",
                "motion_profile": "mim_known_good_block_hole_pickup_slow_repeat",
                "step_degrees": STEP_DEGREES,
            },
            timeout=8.0,
        )
        commands.append({"angle": next_angle, "result": result})
        if not result.get("ok"):
            return {
                "ok": False,
                "servo": servo,
                "start": start,
                "target": target,
                "failed_at": next_angle,
                "commands": commands,
            }
        angle = next_angle
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def move_pose(target: list[int], source: str, order: list[int] | None = None) -> dict[str, Any]:
    order = order or [0, 1, 2, 3, 4, 5]
    moves = []
    for servo in order:
        result = slow_move_servo(servo, int(target[servo]), source)
        moves.append({"servo": servo, "target": int(target[servo]), "result": result})
        if not result.get("ok"):
            return {"ok": False, "target_pose": target, "moves": moves}
        time.sleep(0.25)
    return {"ok": True, "target_pose": target, "moves": moves}


def capture(label: str) -> dict[str, Any]:
    return {
        "label": label,
        "camera": request_json("/capture_frame", {}, timeout=12.0),
        "distance": request_json("/distance/status", timeout=8.0),
        "pose": current_pose(),
    }


def read_json(path: Path) -> dict[str, Any]:
    try:
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8-sig"))
            return data if isinstance(data, dict) else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def main() -> int:
    started_at = now_iso()
    start_pose = current_pose()
    blockers: list[str] = []
    actions: list[dict[str, Any]] = []
    evidence: list[dict[str, Any]] = []

    state = request_json("/arm_state")
    state_data = state.get("data") if isinstance(state.get("data"), dict) else {}
    serial = state_data.get("serial") if isinstance(state_data.get("serial"), dict) else {}
    if not state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if len(start_pose) < 6:
        blockers.append("current_pose_unavailable")

    if not blockers:
        evidence.append(capture("start_before_mim_repeat"))

        if start_pose[5] <= 30:
            actions.append({"action": "reset_open_claw_at_lift", "result": slow_move_servo(5, 90, "mim_repeat_reset_open_claw_at_lift")})
            evidence.append(capture("after_safe_open_at_lift"))

        actions.append({"action": "approach_pose", "result": move_pose(APPROACH_POSE, "mim_repeat_approach_pose", [0, 1, 2, 3, 4, 5])})
        evidence.append(capture("after_approach_pose"))
        actions.append({"action": "lower_pose", "result": move_pose(LOWER_POSE, "mim_repeat_lower_pose", [1, 2, 0, 3, 4, 5])})
        evidence.append(capture("after_lower_pose_before_close"))
        actions.append({"action": "close_to_block_hole_hook_angle", "result": slow_move_servo(5, 22, "mim_repeat_close_to_block_hole_hook_angle")})
        evidence.append(capture("after_close_before_lift"))
        actions.append({"action": "lift_pose", "result": move_pose(LIFT_POSE, "mim_repeat_lift_pose", [1, 2, 0, 3, 4, 5])})
        evidence.append(capture("after_lift_verify"))

        for action in actions:
            result = action.get("result")
            if isinstance(result, dict) and not result.get("ok"):
                blockers.append(f"{action.get('action')}_failed")

    final_pose = current_pose()
    final_distance = request_json("/distance/test", timeout=15.0)
    success = not blockers
    payload = {
        "packet_type": "mim-arm-block-hole-pickup-repeat-v1",
        "generated_at": now_iso(),
        "started_at": started_at,
        "objective_id": OBJECTIVE_ID,
        "learning_owner": "MIM",
        "status": "completed_with_evidence_needs_operator_visual_confirmation" if success else "blocked_with_evidence",
        "success": bool(success),
        "goal": "MIM repeats the known-good block pickup where the right claw extension hooks the block hole.",
        "known_good_sequence": {
            "approach_pose": APPROACH_POSE,
            "lower_pose": LOWER_POSE,
            "close_pose": CLOSE_POSE,
            "lift_pose": LIFT_POSE,
            "claw_hook_success_signal": "right claw extension catches inside the block hole; primary claw camera may not see the hook point",
        },
        "motion_policy": {
            "step_degrees": STEP_DEGREES,
            "settle_seconds": SETTLE_SECONDS,
            "source_tags": "mim_repeat_*",
            "no_transport_after_lift": True,
        },
        "start_pose": start_pose,
        "final_pose": final_pose,
        "actions": actions,
        "evidence": evidence,
        "final_distance_test": final_distance,
        "available_camera_evidence": {
            "arm_camera": read_json(SHARED / "MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json"),
            "pi_table_observer": read_json(SHARED / "MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json"),
            "pc_table_observer": read_json(SHARED / "MIM_ARM_TABLE_OBSERVER_STATUS.latest.json"),
            "policy": "Use every fresh available camera. If fixed observers are absent/blank, record the blocker and proceed only with arm camera plus distance sensor evidence.",
        },
        "blockers": blockers,
        "next_recovery_action": "Operator visually confirms whether the claw hook engaged the block hole after MIM's repeat attempt.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if success else 2


if __name__ == "__main__":
    raise SystemExit(main())
