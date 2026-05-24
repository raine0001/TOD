#!/usr/bin/env python3
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_JOINT_MOTION_TRAINING_STATUS.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_JOINT_MOTION_TRAINING_OBJECTIVE.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
DELTA = 2


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def get_json(path: str, timeout: float = 5.0) -> dict[str, Any]:
    try:
        with urllib.request.urlopen(f"{ARM_HOST}{path}", timeout=timeout) as response:
            return {"ok": True, "data": json.loads(response.read().decode("utf-8"))}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def post_json(path: str, payload: dict[str, Any], timeout: float = 5.0) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{ARM_HOST}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return {"ok": True, "data": json.loads(response.read().decode("utf-8"))}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return {"ok": False, "status": exc.code, "error": body}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def clamp(value: int, minimum: int, maximum: int) -> int:
    return max(minimum, min(maximum, value))


def main() -> int:
    generated_at = now_iso()
    objective = {
        "packet_type": "mim-arm-joint-motion-training-objective-v1",
        "generated_at": generated_at,
        "objective_id": "ARM-02-JOINT-MOTION-SKILL-LIBRARY",
        "status": "active",
        "goal": "Verify that each arm joint accepts a tiny bounded move and can return to its starting pose.",
        "safety_contract": {
            "delta_degrees": DELTA,
            "requires_serial_ready": True,
            "requires_current_pose": True,
            "returns_each_joint_to_start": True,
            "does_not_perform_object_contact_or_pick_place": True,
        },
        "success_criteria": [
            "Arm state is reachable.",
            "Serial controller is ready.",
            "Servo config is reachable.",
            "Each servo changes by the requested tiny amount and returns to the starting value.",
        ],
    }
    write_json(OBJECTIVE_PATH, objective)

    arm_state = get_json("/arm_state")
    servo_config = get_json("/servo_config")
    blockers: list[str] = []
    tests: list[dict[str, Any]] = []
    if not arm_state.get("ok"):
        blockers.append("arm_state_unreachable")
    if not servo_config.get("ok"):
        blockers.append("servo_config_unreachable")

    arm_data = arm_state.get("data") if isinstance(arm_state.get("data"), dict) else {}
    pose = arm_data.get("current_pose") if isinstance(arm_data.get("current_pose"), list) else []
    serial = arm_data.get("serial") if isinstance(arm_data.get("serial"), dict) else {}
    if not serial.get("serial_ready"):
        blockers.append("serial_not_ready")
    if len(pose) < 6:
        blockers.append("current_pose_unavailable")

    servos = (servo_config.get("data") or {}).get("servos") if isinstance(servo_config.get("data"), dict) else []
    limits = {
        int(item.get("id")): {
            "label": item.get("label"),
            "min": int(item.get("min", 0)),
            "max": int(item.get("max", 180)),
        }
        for item in servos
        if isinstance(item, dict) and item.get("id") is not None
    }
    if len(limits) < 6:
        blockers.append("servo_limits_incomplete")

    if not blockers:
        start_pose = [int(value) for value in pose[:6]]
        for servo_id in range(6):
            limit = limits.get(servo_id, {"label": f"servo_{servo_id}", "min": 0, "max": 180})
            start_angle = start_pose[servo_id]
            target = clamp(start_angle + DELTA, int(limit["min"]), int(limit["max"]))
            if target == start_angle:
                target = clamp(start_angle - DELTA, int(limit["min"]), int(limit["max"]))
            before = get_json("/arm_state")
            move_out = post_json("/move", {"servo": servo_id, "angle": target})
            time.sleep(0.25)
            after_out = get_json("/arm_state")
            move_back = post_json("/move", {"servo": servo_id, "angle": start_angle})
            time.sleep(0.25)
            after_back = get_json("/arm_state")
            after_out_pose = (after_out.get("data") or {}).get("current_pose") if isinstance(after_out.get("data"), dict) else []
            after_back_pose = (after_back.get("data") or {}).get("current_pose") if isinstance(after_back.get("data"), dict) else []
            changed = len(after_out_pose) > servo_id and int(after_out_pose[servo_id]) == target
            returned = len(after_back_pose) > servo_id and int(after_back_pose[servo_id]) == start_angle
            tests.append(
                {
                    "servo": servo_id,
                    "label": limit.get("label"),
                    "start_angle": start_angle,
                    "target_angle": target,
                    "before_pose": (before.get("data") or {}).get("current_pose") if isinstance(before.get("data"), dict) else [],
                    "move_out": move_out,
                    "after_out_pose": after_out_pose,
                    "move_back": move_back,
                    "after_back_pose": after_back_pose,
                    "changed_to_target": changed,
                    "returned_to_start": returned,
                    "success": bool(move_out.get("ok") and move_back.get("ok") and changed and returned),
                }
            )
        if any(not item["success"] for item in tests):
            blockers.append("one_or_more_servo_micro_tests_failed")

    success = not blockers and len(tests) == 6 and all(item["success"] for item in tests)
    payload = {
        "packet_type": "mim-arm-joint-motion-training-status-v1",
        "generated_at": now_iso(),
        "objective_id": objective["objective_id"],
        "status": "completed_with_telemetry_evidence" if success else "blocked_with_evidence",
        "success": success,
        "preflight": {
            "arm_state_ok": bool(arm_state.get("ok")),
            "servo_config_ok": bool(servo_config.get("ok")),
            "serial_ready": bool(serial.get("serial_ready")),
            "start_pose": pose[:6] if isinstance(pose, list) else [],
            "delta_degrees": DELTA,
        },
        "tests": tests,
        "blockers": blockers,
        "next_recovery_action": "" if success else "Inspect failed servo test telemetry, confirm no physical obstruction, and rerun a smaller bounded joint test.",
        "evidence_artifacts": ["runtime/shared/MIM_ARM_JOINT_MOTION_TRAINING_OBJECTIVE.latest.json"],
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if success else 2


if __name__ == "__main__":
    raise SystemExit(main())
