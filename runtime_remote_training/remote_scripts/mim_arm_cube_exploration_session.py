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
STATUS_PATH = SHARED / "MIM_ARM_CUBE_EXPLORATION_SESSION.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_CUBE_EXPLORATION_OBJECTIVE.latest.json"
ARM_HOST = "http://192.168.1.90:5000"

OBJECTIVE_ID = "MIM-ARM-CUBE-EXPLORATION-V1"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.28
SAFE_LIFT_OPEN_POSE = [94, 78, 60, 90, 90, 90]
MIN_CLEARANCE_MM = 45

INSPECT_POSES = [
    {
        "name": "safe_lift_overview",
        "pose": [94, 78, 60, 90, 90, 90],
        "intent": "Start from a known safe lifted/open pose.",
    },
    {
        "name": "known_cube_approach_high",
        "pose": [90, 101, 2, 90, 90, 90],
        "intent": "Move to the known cube approach line without closing the claw.",
    },
    {
        "name": "known_cube_near_left",
        "pose": [88, 110, 12, 90, 90, 90],
        "intent": "Inspect slightly left/shallower near the cube face.",
    },
    {
        "name": "known_cube_near_center",
        "pose": [90, 110, 12, 90, 90, 90],
        "intent": "Inspect central near view without contact.",
    },
    {
        "name": "known_cube_near_right",
        "pose": [94, 110, 12, 90, 90, 90],
        "intent": "Inspect right side and possible hole/reference feature.",
    },
    {
        "name": "slightly_deeper_distance_probe",
        "pose": [92, 112, 14, 90, 90, 90],
        "intent": "Take one cautious deeper distance/camera sample; abort if clearance gets too close.",
    },
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
    strengths: list[int] = []
    for _ in range(count):
        result = request_json("/distance/status", timeout=8.0)
        data = result.get("data") if isinstance(result.get("data"), dict) else {}
        if result.get("ok") and data.get("distance_mm") is not None:
            values.append(int(data["distance_mm"]))
        if result.get("ok") and data.get("signal_strength") is not None:
            strengths.append(int(data["signal_strength"]))
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
        "signal_strength_values": strengths,
    }


def capture(label: str) -> dict[str, Any]:
    return {
        "label": label,
        "pose": current_pose(),
        "distance": distance_sample(label),
        "camera": request_json("/capture_frame", {}, timeout=12.0),
    }


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
                "page": "mim_arm_cube_exploration_session",
                "motion_profile": "mim_cube_exploration_slow_no_grip",
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


def proximity_label(sample: dict[str, Any]) -> str:
    median = sample.get("median_mm")
    if median is None:
        return "unknown"
    median = int(median)
    if median < MIN_CLEARANCE_MM:
        return "too_close_abort"
    if median <= 160:
        return "cube_or_surface_close"
    if median <= 450:
        return "near_object"
    if median <= 900:
        return "midrange_object_or_table"
    return "clear_or_far"


def main() -> int:
    started_at = now_iso()
    blockers: list[str] = []
    observations: list[dict[str, Any]] = []
    actions: list[dict[str, Any]] = []

    write_json(
        OBJECTIVE_PATH,
        {
            "packet_type": "mim-arm-cube-exploration-objective-v1",
            "generated_at": started_at,
            "objective_id": OBJECTIVE_ID,
            "status": "active",
            "learning_owner": "MIM",
            "goal": "MIM explores the cube using arm camera and distance perception without gripping or claiming pickup success.",
            "success_criteria": [
                "Move through cautious inspect poses.",
                "Publish camera frame and distance readings for each viewpoint.",
                "Classify cube proximity from sensor readings.",
                "Stop before unsafe contact.",
                "Return to lifted/open safe pose.",
            ],
        },
    )

    state = request_json("/arm_state", timeout=8.0)
    state_data = state.get("data") if isinstance(state.get("data"), dict) else {}
    serial = state_data.get("serial") if isinstance(state_data.get("serial"), dict) else {}
    start_pose = current_pose()
    if not state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if len(start_pose) < 6:
        blockers.append("current_pose_unavailable")

    if not blockers:
        actions.append({"action": "enter_safe_lift_open_pose", "result": move_pose(SAFE_LIFT_OPEN_POSE, "mim_cube_explore_enter_safe_pose", [5, 0, 1, 2, 3, 4])})
        if not actions[-1]["result"].get("ok"):
            blockers.append("enter_safe_lift_open_pose_failed")

    if not blockers:
        for idx, item in enumerate(INSPECT_POSES, start=1):
            move = move_pose(item["pose"], f"mim_cube_explore_pose_{idx:02d}_{item['name']}", [5, 0, 1, 2, 3, 4])
            actions.append({"action": f"move_{item['name']}", "result": move})
            if not move.get("ok"):
                blockers.append(f"move_{item['name']}_failed")
                break
            time.sleep(0.45)
            observation = capture(f"cube_explore_{idx:02d}_{item['name']}")
            distance = observation.get("distance") if isinstance(observation.get("distance"), dict) else {}
            observation["viewpoint"] = item
            observation["proximity_label"] = proximity_label(distance)
            observations.append(observation)
            if observation["proximity_label"] == "too_close_abort":
                blockers.append(f"{item['name']}_too_close_abort")
                break

    final_safe_move = move_pose(SAFE_LIFT_OPEN_POSE, "mim_cube_explore_return_safe_pose", [5, 1, 2, 0, 3, 4]) if observations or actions else {}
    final_pose = current_pose()
    final_distance = distance_sample("cube_explore_final")
    close_observations = [
        {
            "label": obs.get("label"),
            "pose": obs.get("pose"),
            "file_name": (((obs.get("camera") or {}).get("data") or {}).get("file_name") if isinstance(obs.get("camera"), dict) else None),
            "median_mm": (obs.get("distance") or {}).get("median_mm") if isinstance(obs.get("distance"), dict) else None,
            "min_mm": (obs.get("distance") or {}).get("min_mm") if isinstance(obs.get("distance"), dict) else None,
            "proximity_label": obs.get("proximity_label"),
        }
        for obs in observations
        if obs.get("proximity_label") in {"cube_or_surface_close", "near_object"}
    ]
    success = bool(observations and final_safe_move.get("ok") and not any("failed" in b for b in blockers))
    payload = {
        "packet_type": "mim-arm-cube-exploration-session-v1",
        "generated_at": now_iso(),
        "started_at": started_at,
        "objective_id": OBJECTIVE_ID,
        "learning_owner": "MIM",
        "status": "completed_with_cube_exploration_evidence" if success else "blocked_with_cube_exploration_evidence",
        "success": success,
        "goal": "Start MIM exploring the cube as a body/sensor/world learning task, not a pickup task.",
        "start_pose": start_pose,
        "final_pose": final_pose,
        "final_distance": final_distance,
        "safety_policy": {
            "no_grip": True,
            "no_intentional_contact": True,
            "min_clearance_mm": MIN_CLEARANCE_MM,
            "return_safe_pose": SAFE_LIFT_OPEN_POSE,
            "step_degrees": STEP_DEGREES,
        },
        "actions": actions,
        "observations": observations,
        "close_observations": close_observations,
        "learning_summary": {
            "viewpoints_tested": len(observations),
            "closest_observation": min(
                close_observations,
                key=lambda row: int(row["min_mm"]) if row.get("min_mm") is not None else 999999,
            ) if close_observations else None,
            "next_learning_targets": [
                "Repeat cube exploration with wrist/hand angle variations to learn which motion reveals the cube hole.",
                "Build a per-viewpoint cube proximity map from distance medians.",
                "Graduate to guarded touch probes only after MIM can predict cube position from sensor/camera evidence.",
            ],
        },
        "blockers": blockers,
        "next_recovery_action": "Review close observation frames, then let MIM run wrist/hand-only view probes around the best cube viewpoint.",
    }
    write_json(STATUS_PATH, payload)
    print(
        json.dumps(
            {
                "status": payload["status"],
                "success": payload["success"],
                "viewpoints_tested": len(observations),
                "close_observations": close_observations,
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
