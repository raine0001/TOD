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
STATUS_PATH = SHARED / "MIM_ARM_OPERATOR_GUIDED_FOREARM_DOWN_CORRECTION.latest.json"
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
                "source": "mim_operator_guided_forearm_down_correction",
                "motion_profile": "slow_no_contact_direction_correction",
                "step_degrees": STEP_DEGREES,
            },
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "failed_at_angle": angle, "commands": commands}
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def main() -> int:
    state = request_json("/arm_state")
    data = state.get("data") if isinstance(state.get("data"), dict) else {}
    pose = data.get("current_pose") if isinstance(data.get("current_pose"), list) else []
    serial = data.get("serial") if isinstance(data.get("serial"), dict) else {}
    blockers: list[str] = []
    if not state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if not isinstance(pose, list) or len(pose) < 6:
        blockers.append("current_pose_unavailable")
    start_pose = [int(v) for v in pose[:6]] if not blockers else []
    target_pose = list(start_pose)
    if target_pose:
        # Servo config says elbow lower-angle direction is down. Correct the
        # prior operator-language mapping by moving elbow from 86 back down.
        target_pose[2] = clamp(start_pose[2] - 30)
    moves = []
    if not blockers:
        moves.append(slow_move(2, start_pose[2], target_pose[2]))
        if not moves[-1].get("ok"):
            blockers.append("forearm_down_correction_move_failed")
    after = request_json("/arm_state")
    after_pose = (after.get("data") or {}).get("current_pose") if isinstance(after.get("data"), dict) else []
    success = bool(not blockers and isinstance(after_pose, list) and int(after_pose[2]) == target_pose[2])
    payload = {
        "packet_type": "mim-arm-operator-guided-forearm-down-correction-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-BLUE-BLOCK-OPERATOR-LANGUAGE-DIRECTION-CORRECTION-V1",
        "status": "completed_with_motion_evidence" if success else "blocked_with_evidence",
        "success": success,
        "learning_owner": "MIM",
        "lesson": "Dave said forearm down. Servo config maps elbow down to lower angle, so the previous +30 interpretation was wrong.",
        "operator_language_mapping": {
            "phrase": "forearm down",
            "servo": 2,
            "correct_delta_direction": "negative",
            "applied_delta_degrees": -30,
        },
        "motion_policy": {"step_degrees": STEP_DEGREES, "settle_seconds": SETTLE_SECONDS, "no_contact": True, "no_grip": True},
        "start_pose": start_pose,
        "target_pose": target_pose,
        "after_pose": after_pose[:6] if isinstance(after_pose, list) else [],
        "moves": moves,
        "blockers": blockers,
        "next_recovery_action": "Capture wrist and fixed observer frames, then continue MIM-owned camera positioning toward the blue block.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if success else 2


if __name__ == "__main__":
    raise SystemExit(main())
