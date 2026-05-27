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
STATUS_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_COARSE_REPOSITION.latest.json"
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
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            return {"ok": True, "data": json.loads(response.read().decode("utf-8"))}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def clamp(angle: int) -> int:
    return max(0, min(180, int(angle)))


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
                "source": "mim_blue_block_coarse_reposition",
                "motion_profile": "slow_no_contact_blue_block_coarse_reposition",
                "step_degrees": STEP_DEGREES,
            },
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "failed_at_angle": angle, "commands": commands}
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def main() -> int:
    arm_state = request_json("/arm_state")
    data = arm_state.get("data") if isinstance(arm_state.get("data"), dict) else {}
    pose = data.get("current_pose") if isinstance(data.get("current_pose"), list) else []
    serial = data.get("serial") if isinstance(data.get("serial"), dict) else {}
    blockers: list[str] = []
    if not arm_state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if not isinstance(pose, list) or len(pose) < 6:
        blockers.append("current_pose_unavailable")
    start_pose = [int(v) for v in pose[:6]] if not blockers else []
    target_pose = list(start_pose)
    if target_pose:
        # Learned from MIM_ARM_VISUAL_SERVO_EFFECT_MAP: base + moves leftward
        # in fixed observer, elbow negative moves toward the blue target.
        target_pose[0] = clamp(start_pose[0] + 30)
        target_pose[2] = clamp(start_pose[2] - 10)
        target_pose[5] = 0

    moves: list[dict[str, Any]] = []
    if not blockers:
        for servo in (0, 2, 5):
            if start_pose[servo] == target_pose[servo]:
                continue
            result = slow_move(servo, start_pose[servo], target_pose[servo])
            moves.append(result)
            if not result.get("ok"):
                blockers.append(f"servo_{servo}_move_failed")
                break
            start_pose[servo] = target_pose[servo]

    after = request_json("/arm_state")
    after_pose = (after.get("data") or {}).get("current_pose") if isinstance(after.get("data"), dict) else []
    success = bool(not blockers and isinstance(after_pose, list) and after_pose[:6] == target_pose[:6])
    payload = {
        "packet_type": "mim-arm-blue-block-coarse-reposition-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-BLUE-BLOCK-COARSE-REPOSITION-V1",
        "learning_owner": "MIM",
        "status": "completed_with_motion_evidence" if success else "blocked_with_evidence",
        "success": success,
        "source_evidence": "runtime/shared/MIM_ARM_VISUAL_SERVO_EFFECT_MAP.latest.json",
        "motion_policy": {"step_degrees": STEP_DEGREES, "settle_seconds": SETTLE_SECONDS, "no_contact": True, "no_grip": True},
        "original_pose": pose[:6] if isinstance(pose, list) else [],
        "target_pose": target_pose,
        "after_pose": after_pose[:6] if isinstance(after_pose, list) else [],
        "moves": moves,
        "blockers": blockers,
        "next_recovery_action": "Capture fixed observer and wrist camera frames, then recompute gripper-to-blue-block alignment.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if success else 2


if __name__ == "__main__":
    raise SystemExit(main())
