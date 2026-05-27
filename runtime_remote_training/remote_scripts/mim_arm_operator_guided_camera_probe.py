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
STATUS_PATH = SHARED / "MIM_ARM_OPERATOR_GUIDED_CAMERA_PROBE.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.35


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def request_json(endpoint: str, payload: dict[str, Any] | None = None, timeout: float = 8.0) -> dict[str, Any]:
    if payload is None:
        req = urllib.request.Request(f"{ARM_HOST}{endpoint}", method="GET")
    else:
        req = urllib.request.Request(
            f"{ARM_HOST}{endpoint}",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return {"ok": True, "data": json.loads(response.read().decode("utf-8"))}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def clamp(value: int) -> int:
    return max(0, min(180, int(value)))


def slow_move(servo: int, start: int, target: int) -> dict[str, Any]:
    start = clamp(start)
    target = clamp(target)
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
                "source": "mim_operator_guided_camera_probe",
                "motion_profile": "slow_no_contact_operator_guided_probe",
                "step_degrees": STEP_DEGREES,
            },
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "target": target, "failed_at_angle": angle, "commands": commands}
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def main() -> int:
    generated_at = now_iso()
    arm_state = request_json("/arm_state")
    arm_data = arm_state.get("data") if isinstance(arm_state.get("data"), dict) else {}
    pose = arm_data.get("current_pose") if isinstance(arm_data.get("current_pose"), list) else []
    serial = arm_data.get("serial") if isinstance(arm_data.get("serial"), dict) else {}
    blockers: list[str] = []
    if not arm_state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if not isinstance(pose, list) or len(pose) < 6:
        blockers.append("current_pose_unavailable")

    start_pose = [int(value) for value in pose[:6]] if isinstance(pose, list) and len(pose) >= 6 else []
    target_pose = list(start_pose) if start_pose else []
    if target_pose:
        target_pose[0] = clamp(target_pose[0] + 45)
        target_pose[2] = clamp(target_pose[2] + 30)

    moves: list[dict[str, Any]] = []
    if not blockers:
        moves.append(slow_move(0, start_pose[0], target_pose[0]))
        if moves[-1].get("ok"):
            moves.append(slow_move(2, start_pose[2], target_pose[2]))
        if not all(move.get("ok") for move in moves):
            blockers.append("operator_guided_probe_move_failed")

    after_state = request_json("/arm_state")
    after_pose = (after_state.get("data") or {}).get("current_pose") if isinstance(after_state.get("data"), dict) else []
    success = bool(not blockers and isinstance(after_pose, list) and after_pose[:6] == target_pose[:6])
    payload = {
        "packet_type": "mim-arm-operator-guided-camera-probe-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-ARM-BLUE-BLOCK-OPERATOR-GUIDED-CAMERA-POSITIONING-V1",
        "status": "completed_with_motion_evidence" if success else "blocked_with_evidence",
        "success": success,
        "learning_owner": "MIM",
        "operator_guidance": {
            "speaker": "Dave",
            "instruction": "Turn the arm left about 45 degrees, then move the forearm down about 30 degrees. Start there and report what you see.",
            "interpreted_as": {
                "base_delta_degrees": 45,
                "elbow_delta_degrees": 30,
                "contact_allowed": False,
                "grip_allowed": False,
            },
        },
        "motion_policy": {
            "step_degrees": STEP_DEGREES,
            "settle_seconds": SETTLE_SECONDS,
            "no_contact": True,
            "no_grip": True,
        },
        "start_pose": start_pose,
        "target_pose": target_pose,
        "after_pose": after_pose[:6] if isinstance(after_pose, list) else [],
        "moves": moves,
        "blockers": blockers,
        "next_recovery_action": "Capture wrist and fixed observer camera evidence from this pose, then let MIM decide whether the blue block is visible and what no-contact refinement is needed.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if success else 2


if __name__ == "__main__":
    raise SystemExit(main())
