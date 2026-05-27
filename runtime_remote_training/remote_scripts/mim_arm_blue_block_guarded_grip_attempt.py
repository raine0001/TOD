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
STATUS_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_GUARDED_GRIP_ATTEMPT.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.35
CLAW_OPEN_MIN_ANGLE = 70
GUARDED_CLOSE_TARGET = 64


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
                "motion_profile": "mim_blue_block_guarded_slow_grip_attempt",
                "step_degrees": STEP_DEGREES,
            },
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "start": start, "target": target, "failed_at": angle, "commands": commands}
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def capture(label: str) -> dict[str, Any]:
    result = request_json("/capture_frame", {}, timeout=10.0)
    return {"label": label, "result": result}


def main() -> int:
    blockers: list[str] = []
    state = request_json("/arm_state")
    data = state.get("data") if isinstance(state.get("data"), dict) else {}
    pose = data.get("current_pose") if isinstance(data.get("current_pose"), list) else []
    serial = data.get("serial") if isinstance(data.get("serial"), dict) else {}
    if not state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if not isinstance(pose, list) or len(pose) < 6:
        blockers.append("current_pose_unavailable")
    start_pose = [int(value) for value in pose[:6]] if not blockers else []
    if start_pose and int(start_pose[5]) < CLAW_OPEN_MIN_ANGLE:
        blockers.append("claw_not_visibly_open_at_start")

    captures: list[dict[str, Any]] = []
    moves: list[dict[str, Any]] = []
    if not blockers:
        captures.append(capture("before_close_aligned_blue_block_visible_between_claw_tips"))
        close = slow_move(5, start_pose[5], GUARDED_CLOSE_TARGET, "mim_blue_block_guarded_grip_close")
        moves.append({"action": "close_claw_to_guarded_hold", "move": close})
        if not close.get("ok"):
            blockers.append("claw_close_failed")
        time.sleep(0.8)
        captures.append(capture("after_close_before_lift"))

    after_close_state = request_json("/arm_state")
    after_close_pose = (after_close_state.get("data") or {}).get("current_pose") if isinstance(after_close_state.get("data"), dict) else []

    if not blockers:
        # Lift a tiny amount by moving elbow upward. This is a verification lift,
        # not a transport move.
        current_elbow = int(after_close_pose[2]) if isinstance(after_close_pose, list) and len(after_close_pose) > 2 else start_pose[2]
        lift_target = clamp(current_elbow + 8)
        lift = slow_move(2, current_elbow, lift_target, "mim_blue_block_guarded_micro_lift")
        moves.append({"action": "micro_lift_elbow", "move": lift})
        if not lift.get("ok"):
            blockers.append("micro_lift_failed")
        time.sleep(0.8)
        captures.append(capture("after_micro_lift"))

    after = request_json("/arm_state")
    after_pose = (after.get("data") or {}).get("current_pose") if isinstance(after.get("data"), dict) else []
    success = bool(not blockers)
    payload = {
        "packet_type": "mim-arm-blue-block-guarded-grip-attempt-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-PICK-UP-BLUE-BLOCK",
        "status": "motion_attempt_completed_needs_visual_review" if success else "blocked_with_evidence",
        "success": False,
        "learning_owner": "MIM",
        "goal": "Guarded attempt to close on the blue block and perform a tiny lift after Dave repositioned the workspace into camera view.",
        "motion_policy": {
            "operator_authorized_goal": "MIM pick up the blue block",
            "blue_block_visible_in_wrist_camera_before_attempt": True,
            "step_degrees": STEP_DEGREES,
            "settle_seconds": SETTLE_SECONDS,
            "claw_open_min_angle": CLAW_OPEN_MIN_ANGLE,
            "guarded_close_target": GUARDED_CLOSE_TARGET,
            "micro_lift_elbow_delta": 8,
            "no_transport": True,
            "human_visible_is_contextual_caution_not_hard_stop": True,
        },
        "start_pose": start_pose,
        "after_close_pose": after_close_pose[:6] if isinstance(after_close_pose, list) else [],
        "after_pose": after_pose[:6] if isinstance(after_pose, list) else [],
        "moves": moves,
        "captures": captures,
        "blockers": blockers,
        "next_recovery_action": "Review before/after wrist and Pi observer images. Mark success only if the blue block visibly moved/lifted with the claw.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if success else 2


if __name__ == "__main__":
    raise SystemExit(main())
