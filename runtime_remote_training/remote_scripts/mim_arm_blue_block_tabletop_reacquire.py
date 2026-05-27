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
STATUS_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_TABLETOP_REACQUIRE.latest.json"
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


def slow_move(servo: int, start: int, target: int, source: str) -> dict[str, Any]:
    start = clamp(start)
    target = clamp(target)
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
                "motion_profile": "mim_blue_block_slow_no_contact_tabletop_reacquire",
                "step_degrees": STEP_DEGREES,
            },
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "start": start, "target": target, "failed_at": angle, "commands": commands}
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def capture_frame() -> dict[str, Any]:
    return request_json("/capture_frame", {}, timeout=10.0)


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

    start_pose = [int(value) for value in pose[:6]] if not blockers else []
    target_pose = list(start_pose)
    if target_pose:
        # Current evidence has base at max and wrist camera off-table. Reacquire
        # the tabletop by moving shoulder forward and elbow down, leaving claw open.
        target_pose[0] = 180
        target_pose[1] = 125
        target_pose[2] = 46
        target_pose[3] = 93
        target_pose[4] = 103
        target_pose[5] = 0

    moves: list[dict[str, Any]] = []
    if not blockers:
        working_pose = list(start_pose)
        for servo in (1, 2, 3, 4, 5):
            move = slow_move(servo, working_pose[servo], target_pose[servo], "mim_blue_block_tabletop_reacquire")
            moves.append(move)
            if not move.get("ok"):
                blockers.append(f"servo_{servo}_move_failed")
                break
            working_pose[servo] = target_pose[servo]

    time.sleep(0.8)
    after = request_json("/arm_state")
    after_pose = (after.get("data") or {}).get("current_pose") if isinstance(after.get("data"), dict) else []
    wrist_capture = capture_frame() if not blockers else {}
    success = bool(not blockers and isinstance(after_pose, list) and [int(v) for v in after_pose[:6]] == target_pose)
    payload = {
        "packet_type": "mim-arm-blue-block-tabletop-reacquire-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-BLUE-BLOCK-TABLETOP-REACQUIRE-V1",
        "status": "completed_with_motion_evidence" if success else "blocked_with_evidence",
        "success": success,
        "learning_owner": "MIM",
        "goal": "Move from off-table wrist-camera view back to a slow no-contact tabletop view before attempting blue block alignment.",
        "motion_policy": {
            "no_contact": True,
            "no_grip": True,
            "claw_open": True,
            "step_degrees": STEP_DEGREES,
            "settle_seconds": SETTLE_SECONDS,
            "human_visible_is_contextual_caution_not_hard_stop": True,
        },
        "start_pose": start_pose,
        "target_pose": target_pose,
        "after_pose": after_pose[:6] if isinstance(after_pose, list) else [],
        "moves": moves,
        "wrist_capture": wrist_capture,
        "blockers": blockers,
        "next_recovery_action": "Refresh fixed Pi observer and wrist camera; use fixed observer as truth for blue block alignment.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if success else 2


if __name__ == "__main__":
    raise SystemExit(main())
