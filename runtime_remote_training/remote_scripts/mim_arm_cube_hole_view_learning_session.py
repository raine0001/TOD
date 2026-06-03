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
STATUS_PATH = SHARED / "MIM_ARM_CUBE_HOLE_VIEW_LEARNING_SESSION.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_CUBE_HOLE_VIEW_LEARNING_OBJECTIVE.latest.json"
ARM_HOST = "http://192.168.1.90:5000"

OBJECTIVE_ID = "MIM-ARM-CUBE-HOLE-VIEW-LEARNING-V1"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.28
SAFE_LIFT_OPEN_POSE = [94, 78, 60, 90, 90, 90]
BEST_CUBE_VIEW_POSE = [92, 112, 14, 90, 90, 90]
MIN_CLEARANCE_MM = 45

VIEW_VARIATIONS = [
    {"name": "baseline", "pose": [92, 112, 14, 90, 90, 90]},
    {"name": "wrist_left_8", "pose": [92, 112, 14, 82, 90, 90]},
    {"name": "wrist_right_8", "pose": [92, 112, 14, 98, 90, 90]},
    {"name": "hand_left_8", "pose": [92, 112, 14, 90, 82, 90]},
    {"name": "hand_right_8", "pose": [92, 112, 14, 90, 98, 90]},
    {"name": "wrist_left_hand_right", "pose": [92, 112, 14, 84, 98, 90]},
    {"name": "wrist_right_hand_left", "pose": [92, 112, 14, 98, 82, 90]},
]


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


def distance_sample(label: str, count: int = 5) -> dict[str, Any]:
    readings: list[dict[str, Any]] = []
    values: list[int] = []
    for _ in range(count):
        result = request_json("/distance/status", timeout=8.0)
        data = result.get("data") if isinstance(result.get("data"), dict) else {}
        if result.get("ok") and data.get("distance_mm") is not None:
            values.append(int(data["distance_mm"]))
        readings.append({"ok": result.get("ok"), "data": data, "error": result.get("error")})
        time.sleep(0.12)
    ordered = sorted(values)
    return {
        "label": label,
        "readings": readings,
        "distance_mm_values": values,
        "min_mm": min(values) if values else None,
        "median_mm": ordered[len(ordered) // 2] if ordered else None,
        "max_mm": max(values) if values else None,
    }


def capture(label: str) -> dict[str, Any]:
    return {"label": label, "pose": current_pose(), "distance": distance_sample(label), "camera": request_json("/capture_frame", {}, timeout=12.0)}


def slow_move_servo(servo: int, target: int, source: str) -> dict[str, Any]:
    pose = current_pose()
    if len(pose) < 6:
        return {"ok": False, "servo": servo, "target": target, "reason": "current_pose_unavailable"}
    start = clamp(pose[servo])
    target = clamp(target)
    if start == target:
        return {"ok": True, "servo": servo, "start": start, "target": target, "steps": 0, "skipped": True}
    step = STEP_DEGREES if target > start else -STEP_DEGREES
    angle = start
    sent: list[int] = []
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
                "page": "mim_arm_cube_hole_view_learning_session",
                "motion_profile": "mim_cube_hole_view_no_grip",
                "step_degrees": STEP_DEGREES,
            },
            timeout=8.0,
        )
        sent.append(next_angle)
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "start": start, "target": target, "failed_at": next_angle, "sent_angles": sent}
        angle = next_angle
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "steps": len(sent), "sent_angles": sent}


def move_pose(target: list[int], source: str, order: list[int]) -> dict[str, Any]:
    moves: list[dict[str, Any]] = []
    for servo in order:
        result = slow_move_servo(servo, target[servo], source)
        moves.append(result)
        if not result.get("ok"):
            return {"ok": False, "target_pose": target, "moves": moves}
        time.sleep(0.14)
    return {"ok": True, "target_pose": target, "moves": moves}


def image_quality_hint(obs: dict[str, Any]) -> dict[str, Any]:
    camera = obs.get("camera", {}).get("data") if isinstance(obs.get("camera"), dict) else {}
    distance = obs.get("distance") if isinstance(obs.get("distance"), dict) else {}
    median = distance.get("median_mm")
    min_mm = distance.get("min_mm")
    score = 0
    if isinstance(median, int):
        score += max(0, 300 - abs(median - 90))
    if isinstance(min_mm, int) and min_mm >= MIN_CLEARANCE_MM:
        score += 50
    if isinstance(camera, dict) and camera.get("jpeg_bytes"):
        score += min(100, int(camera["jpeg_bytes"]) // 1000)
    return {
        "score": score,
        "file_name": camera.get("file_name") if isinstance(camera, dict) else None,
        "median_mm": median,
        "min_mm": min_mm,
        "note": "Heuristic only: favors stable close cube views near 90 mm with a real captured frame.",
    }


def main() -> int:
    started_at = now_iso()
    blockers: list[str] = []
    actions: list[dict[str, Any]] = []
    observations: list[dict[str, Any]] = []

    write_json(
        OBJECTIVE_PATH,
        {
            "packet_type": "mim-arm-cube-hole-view-learning-objective-v1",
            "generated_at": started_at,
            "objective_id": OBJECTIVE_ID,
            "status": "active",
            "learning_owner": "MIM",
            "goal": "MIM learns which wrist/hand camera viewpoints best reveal the cube hole while keeping the claw open.",
            "success_criteria": [
                "Use the best cube exploration pose as baseline.",
                "Vary only wrist and hand angles near the cube.",
                "Capture distance and camera evidence for each variation.",
                "Do not close the claw or intentionally contact the cube.",
                "Return to safe lifted/open pose.",
            ],
        },
    )

    state = request_json("/arm_state")
    state_data = state.get("data") if isinstance(state.get("data"), dict) else {}
    serial = state_data.get("serial") if isinstance(state_data.get("serial"), dict) else {}
    start_pose = current_pose()
    if not state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if len(start_pose) < 6:
        blockers.append("current_pose_unavailable")

    if not blockers:
        actions.append({"action": "enter_safe_pose", "result": move_pose(SAFE_LIFT_OPEN_POSE, "mim_cube_hole_view_enter_safe_pose", [5, 0, 1, 2, 3, 4])})
        actions.append({"action": "enter_best_cube_view_pose", "result": move_pose(BEST_CUBE_VIEW_POSE, "mim_cube_hole_view_enter_best_pose", [5, 0, 1, 2, 3, 4])})
        for action in actions:
            if not action["result"].get("ok"):
                blockers.append(f"{action['action']}_failed")

    if not blockers:
        for idx, variation in enumerate(VIEW_VARIATIONS, start=1):
            move = move_pose(variation["pose"], f"mim_cube_hole_view_variation_{idx:02d}_{variation['name']}", [5, 3, 4, 0, 1, 2])
            actions.append({"action": f"view_variation_{variation['name']}", "result": move})
            if not move.get("ok"):
                blockers.append(f"view_variation_{variation['name']}_failed")
                break
            time.sleep(0.45)
            obs = capture(f"cube_hole_view_{idx:02d}_{variation['name']}")
            obs["view_variation"] = variation
            obs["quality_hint"] = image_quality_hint(obs)
            observations.append(obs)
            distance = obs.get("distance") if isinstance(obs.get("distance"), dict) else {}
            if distance.get("min_mm") is not None and int(distance["min_mm"]) < MIN_CLEARANCE_MM:
                blockers.append(f"view_variation_{variation['name']}_too_close_abort")
                break

    final_safe_move = move_pose(SAFE_LIFT_OPEN_POSE, "mim_cube_hole_view_return_safe_pose", [5, 1, 2, 0, 3, 4]) if actions or observations else {}
    final_pose = current_pose()
    final_distance = distance_sample("cube_hole_view_final")
    ranked = sorted(
        [
            {
                "label": obs.get("label"),
                "pose": obs.get("pose"),
                **obs.get("quality_hint", {}),
            }
            for obs in observations
        ],
        key=lambda row: int(row.get("score") or 0),
        reverse=True,
    )
    success = bool(observations and final_safe_move.get("ok") and not any("failed" in b for b in blockers))
    payload = {
        "packet_type": "mim-arm-cube-hole-view-learning-session-v1",
        "generated_at": now_iso(),
        "started_at": started_at,
        "objective_id": OBJECTIVE_ID,
        "learning_owner": "MIM",
        "status": "completed_with_cube_hole_view_evidence" if success else "blocked_with_cube_hole_view_evidence",
        "success": success,
        "goal": "Learn camera/sensor viewpoints for cube hole exploration before any contact/grasp work.",
        "start_pose": start_pose,
        "final_pose": final_pose,
        "final_distance": final_distance,
        "safety_policy": {
            "no_grip": True,
            "claw_angle": 90,
            "min_clearance_mm": MIN_CLEARANCE_MM,
            "safe_return_pose": SAFE_LIFT_OPEN_POSE,
        },
        "actions": actions,
        "observations": observations,
        "ranked_view_hints": ranked,
        "learning_summary": {
            "view_variations_tested": len(observations),
            "best_view_hint": ranked[0] if ranked else None,
            "next_learning_targets": [
                "Use the best cube-hole view as the baseline for side/height micro-probes.",
                "Train visual recognition of cube hole position in frame.",
                "Only after stable hole localization, run a guarded contact probe with the claw still open.",
            ],
        },
        "blockers": blockers,
        "next_recovery_action": "Review ranked frames and choose the next MIM-owned micro-probe around the best cube-hole view.",
    }
    write_json(STATUS_PATH, payload)
    print(
        json.dumps(
            {
                "status": payload["status"],
                "success": success,
                "view_variations_tested": len(observations),
                "best_view_hint": ranked[0] if ranked else None,
                "final_pose": final_pose,
                "final_distance_median_mm": final_distance.get("median_mm"),
                "blockers": blockers,
                "artifact": str(STATUS_PATH),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0 if success else 2


if __name__ == "__main__":
    raise SystemExit(main())
