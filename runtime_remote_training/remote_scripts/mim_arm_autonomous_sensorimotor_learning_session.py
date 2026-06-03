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
STATUS_PATH = SHARED / "MIM_ARM_AUTONOMOUS_SENSORIMOTOR_LEARNING_SESSION.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_AUTONOMOUS_SENSORIMOTOR_LEARNING_OBJECTIVE.latest.json"
ARM_HOST = "http://192.168.1.90:5000"

OBJECTIVE_ID = "MIM-ARM-AUTONOMOUS-SENSORIMOTOR-LEARNING-V1"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.25
CLEAR_DISTANCE_MIN_MM = 700
SAFE_LIFT_OPEN_POSE = [94, 78, 60, 90, 90, 90]

JOINTS = {
    0: "base",
    1: "shoulder",
    2: "elbow",
    3: "wrist",
    4: "hand",
    5: "claw",
}


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


def distance_sample(label: str, count: int = 3) -> dict[str, Any]:
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
        return {"ok": True, "servo": servo, "joint": JOINTS.get(servo), "start": start, "target": target, "steps": 0}
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
                "page": "mim_arm_autonomous_sensorimotor_learning_session",
                "motion_profile": "autonomous_no_contact_micro_probe",
                "step_degrees": STEP_DEGREES,
            },
            timeout=8.0,
        )
        sent.append(next_angle)
        if not result.get("ok"):
            return {
                "ok": False,
                "servo": servo,
                "joint": JOINTS.get(servo),
                "start": start,
                "target": target,
                "failed_at": next_angle,
                "sent_angles": sent,
                "error": result.get("error"),
                "response": result.get("data"),
            }
        angle = next_angle
        time.sleep(SETTLE_SECONDS)
    return {
        "ok": True,
        "servo": servo,
        "joint": JOINTS.get(servo),
        "start": start,
        "target": target,
        "steps": len(sent),
        "sent_angles": sent,
    }


def move_pose(target: list[int], source: str, order: list[int]) -> dict[str, Any]:
    moves: list[dict[str, Any]] = []
    for servo in order:
        result = slow_move_servo(servo, target[servo], source)
        moves.append(result)
        if not result.get("ok"):
            return {"ok": False, "target_pose": target, "moves": moves}
        time.sleep(0.12)
    return {"ok": True, "target_pose": target, "moves": moves}


def load_json(name: str) -> dict[str, Any]:
    path = SHARED / name
    try:
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8-sig"))
            return data if isinstance(data, dict) else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def observation_delta(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    before_pose = before.get("pose") if isinstance(before.get("pose"), list) else []
    after_pose = after.get("pose") if isinstance(after.get("pose"), list) else []
    before_distance = before.get("distance") if isinstance(before.get("distance"), dict) else {}
    after_distance = after.get("distance") if isinstance(after.get("distance"), dict) else {}
    before_camera = before.get("camera", {}).get("data") if isinstance(before.get("camera"), dict) else {}
    after_camera = after.get("camera", {}).get("data") if isinstance(after.get("camera"), dict) else {}
    return {
        "pose_delta": [
            int(after_pose[idx]) - int(before_pose[idx])
            for idx in range(min(len(before_pose), len(after_pose), 6))
        ],
        "distance_median_delta_mm": (
            int(after_distance["median_mm"]) - int(before_distance["median_mm"])
            if before_distance.get("median_mm") is not None and after_distance.get("median_mm") is not None
            else None
        ),
        "camera_frame_before": before_camera.get("file_name") if isinstance(before_camera, dict) else None,
        "camera_frame_after": after_camera.get("file_name") if isinstance(after_camera, dict) else None,
    }


def main() -> int:
    started_at = now_iso()
    blockers: list[str] = []
    probes: list[dict[str, Any]] = []
    evidence: list[dict[str, Any]] = []

    write_json(
        OBJECTIVE_PATH,
        {
            "packet_type": "mim-arm-autonomous-sensorimotor-learning-objective-v1",
            "generated_at": started_at,
            "objective_id": OBJECTIVE_ID,
            "status": "active",
            "learning_owner": "MIM",
            "goal": "MIM learns how her arm motions change camera and distance perception without contact or operator hand-driving.",
            "success_criteria": [
                "Publish current pose and sensor health.",
                "Run small no-contact self-directed joint probes from a lifted/open pose.",
                "Capture before/after camera and distance evidence.",
                "Return to a safe lifted/open pose.",
                "Do not claim manipulation success; this is body/world learning only.",
            ],
        },
    )

    state = request_json("/arm_state", timeout=8.0)
    state_data = state.get("data") if isinstance(state.get("data"), dict) else {}
    serial = state_data.get("serial") if isinstance(state_data.get("serial"), dict) else {}
    start_pose = current_pose()
    start_distance = distance_sample("preflight_clearance")
    if not state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if len(start_pose) < 6:
        blockers.append("current_pose_unavailable")
    if start_distance.get("median_mm") is None:
        blockers.append("distance_sensor_unavailable")
    elif int(start_distance["median_mm"]) < CLEAR_DISTANCE_MIN_MM:
        blockers.append("clearance_too_close_for_autonomous_no_contact_probe")

    if not blockers:
        evidence.append({"label": "preflight", "pose": start_pose, "distance": start_distance, "arm_state": state})
        safe_move = move_pose(SAFE_LIFT_OPEN_POSE, "mim_autonomous_learning_enter_safe_lift_open_pose", [5, 0, 1, 2, 3, 4])
        evidence.append({"label": "enter_safe_lift_open_pose", "move": safe_move, "pose": current_pose(), "distance": distance_sample("after_safe_pose")})
        if not safe_move.get("ok"):
            blockers.append("enter_safe_lift_open_pose_failed")

    probe_plan = [
        {"servo": 0, "delta": -6, "hypothesis": "base negative changes lateral camera view while distance should stay clear"},
        {"servo": 0, "delta": 6, "hypothesis": "base positive changes lateral camera view while distance should stay clear"},
        {"servo": 1, "delta": -4, "hypothesis": "shoulder backward changes camera height/tilt while staying lifted"},
        {"servo": 1, "delta": 4, "hypothesis": "shoulder forward changes camera height/tilt while staying lifted"},
        {"servo": 2, "delta": -4, "hypothesis": "elbow lower/extend changes foreground and distance cone"},
        {"servo": 2, "delta": 4, "hypothesis": "elbow raise/retract changes foreground and distance cone"},
        {"servo": 3, "delta": -6, "hypothesis": "wrist rotation changes camera framing without changing table distance much"},
        {"servo": 3, "delta": 6, "hypothesis": "opposite wrist rotation changes camera framing without changing table distance much"},
        {"servo": 5, "delta": -20, "hypothesis": "claw close/open changes gripper silhouette while lifted and clear"},
    ]

    if not blockers:
        for idx, planned in enumerate(probe_plan, start=1):
            base_pose = current_pose()
            if len(base_pose) < 6:
                blockers.append("current_pose_unavailable_during_probe")
                break
            before = capture(f"probe_{idx:02d}_before_{JOINTS[planned['servo']]}")
            target = clamp(base_pose[planned["servo"]] + planned["delta"])
            move = slow_move_servo(
                planned["servo"],
                target,
                f"mim_autonomous_learning_probe_{idx:02d}_{JOINTS[planned['servo']]}",
            )
            time.sleep(0.35)
            after = capture(f"probe_{idx:02d}_after_{JOINTS[planned['servo']]}")
            return_move = slow_move_servo(
                planned["servo"],
                base_pose[planned["servo"]],
                f"mim_autonomous_learning_probe_{idx:02d}_{JOINTS[planned['servo']]}_return",
            )
            probe = {
                "probe_id": f"probe_{idx:02d}",
                "joint": JOINTS[planned["servo"]],
                "servo": planned["servo"],
                "delta_degrees": planned["delta"],
                "hypothesis": planned["hypothesis"],
                "before": before,
                "move": move,
                "after": after,
                "return_move": return_move,
                "observed_delta": observation_delta(before, after),
                "learned_rule_candidate": (
                    f"{JOINTS[planned['servo']]} {planned['delta']:+d} deg changed pose by "
                    f"{observation_delta(before, after).get('pose_delta')} and distance median by "
                    f"{observation_delta(before, after).get('distance_median_delta_mm')} mm"
                ),
            }
            probes.append(probe)
            after_distance = after.get("distance") if isinstance(after.get("distance"), dict) else {}
            if move.get("ok") is not True or return_move.get("ok") is not True:
                blockers.append(f"probe_{idx:02d}_motion_failed")
                break
            if after_distance.get("median_mm") is not None and int(after_distance["median_mm"]) < CLEAR_DISTANCE_MIN_MM:
                blockers.append(f"probe_{idx:02d}_clearance_became_too_close")
                break

    final_safe_move = {}
    if not blockers or probes:
        final_safe_move = move_pose(SAFE_LIFT_OPEN_POSE, "mim_autonomous_learning_return_safe_lift_open_pose", [5, 0, 1, 2, 3, 4])
    final_pose = current_pose()
    final_distance = distance_sample("final_clearance")

    success = bool(probes and not blockers and final_safe_move.get("ok") and len(final_pose) >= 6)
    payload = {
        "packet_type": "mim-arm-autonomous-sensorimotor-learning-session-v1",
        "generated_at": now_iso(),
        "started_at": started_at,
        "objective_id": OBJECTIVE_ID,
        "learning_owner": "MIM",
        "status": "completed_with_learning_evidence" if success else "blocked_with_learning_evidence",
        "success": success,
        "goal": "Let MIM autonomously learn arm motion effects using camera and distance perception, without manipulating objects.",
        "operator_directive": "This is a 100% MIM learning experience for movement, sensors, object interaction, and environmental exploration.",
        "future_sensor_note": "A 360 lidar is expected next; this artifact is the baseline body/sensor learner that lidar can plug into.",
        "safety_policy": {
            "no_contact": True,
            "safe_lift_open_pose": SAFE_LIFT_OPEN_POSE,
            "clear_distance_min_mm": CLEAR_DISTANCE_MIN_MM,
            "step_degrees": STEP_DEGREES,
            "settle_seconds": SETTLE_SECONDS,
            "stop_on_close_distance": True,
        },
        "start_pose": start_pose,
        "final_pose": final_pose,
        "final_safe_move": final_safe_move,
        "final_distance": final_distance,
        "evidence": evidence,
        "probes": probes,
        "available_sensor_evidence": {
            "arm_camera": load_json("MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json"),
            "pi_table_observer": load_json("MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json"),
            "pc_table_observer": load_json("MIM_ARM_TABLE_OBSERVER_STATUS.latest.json"),
            "distance_source": "arduino_i2c_0x10",
        },
        "learning_summary": {
            "probe_count": len(probes),
            "rules": [probe.get("learned_rule_candidate") for probe in probes],
            "next_autonomous_learning_targets": [
                "Build a camera-motion effect map from repeated probes.",
                "Learn approach versus inspect poses before touching objects.",
                "Add object-contact probes only after MIM can predict no-contact motion effects.",
                "Integrate 360 lidar as an environment occupancy map when the sensor arrives.",
            ],
        },
        "blockers": blockers,
        "next_recovery_action": "Run another no-contact session from a different safe viewpoint, then graduate to guarded object-contact probes.",
    }
    write_json(STATUS_PATH, payload)
    print(
        json.dumps(
            {
                "status": payload["status"],
                "success": payload["success"],
                "probe_count": len(probes),
                "start_pose": start_pose,
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
