#!/usr/bin/env python3
from __future__ import annotations

import argparse
import io
import json
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from PIL import Image
except Exception:
    Image = None  # type: ignore[assignment]


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_PICKUP_TRAINING.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_PICKUP_OBJECTIVE.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
SLOW_MOVE_STEP_DEG = 2
SLOW_MOVE_SETTLE_SECONDS = 0.35
WRIST_SERVO = 3
HAND_SERVO = 4
IR_SENSOR_OFFSET_FROM_GRIP_TIPS_MM = 142


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict[str, Any]:
    try:
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8-sig"))
            return data if isinstance(data, dict) else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def get_json(endpoint: str, timeout: float = 5.0) -> dict[str, Any]:
    try:
        with urllib.request.urlopen(f"{ARM_HOST}{endpoint}", timeout=timeout) as response:
            return {"ok": True, "data": json.loads(response.read().decode("utf-8"))}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def post_json(endpoint: str, payload: dict[str, Any], timeout: float = 5.0) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{ARM_HOST}{endpoint}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return {"ok": True, "data": json.loads(response.read().decode("utf-8"))}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def slow_move_servo(servo: int, start_angle: int, target_angle: int, *, source: str) -> dict[str, Any]:
    start = max(0, min(180, int(start_angle)))
    target = max(0, min(180, int(target_angle)))
    if start == target:
        return {
            "ok": True,
            "servo": servo,
            "start_angle": start,
            "target_angle": target,
            "step_degrees": SLOW_MOVE_STEP_DEG,
            "settle_seconds": SLOW_MOVE_SETTLE_SECONDS,
            "commands": [],
        }
    direction = 1 if target > start else -1
    angle = start
    commands: list[dict[str, Any]] = []
    while angle != target:
        angle = angle + (direction * SLOW_MOVE_STEP_DEG)
        if (direction > 0 and angle > target) or (direction < 0 and angle < target):
            angle = target
        result = post_json(
            "/move",
            {
                "servo": servo,
                "angle": angle,
                "source": source,
                "motion_profile": "slow_operator_visible_probe",
                "step_degrees": SLOW_MOVE_STEP_DEG,
            },
            timeout=5.0,
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {
                "ok": False,
                "servo": servo,
                "start_angle": start,
                "target_angle": target,
                "failed_at_angle": angle,
                "commands": commands,
            }
        time.sleep(SLOW_MOVE_SETTLE_SECONDS)
    return {
        "ok": True,
        "servo": servo,
        "start_angle": start,
        "target_angle": target,
        "step_degrees": SLOW_MOVE_STEP_DEG,
        "settle_seconds": SLOW_MOVE_SETTLE_SECONDS,
        "commands": commands,
    }


def capture_arm_camera_blue_score() -> dict[str, Any]:
    if Image is None:
        return {"ok": False, "error": "pillow_unavailable"}
    capture = post_json("/capture_frame", {}, timeout=10.0)
    if not capture.get("ok") or not isinstance(capture.get("data"), dict):
        return {"ok": False, "error": "capture_frame_failed", "capture": capture}
    output_path = str(capture["data"].get("output_path") or "").strip()
    if not output_path:
        return {"ok": False, "error": "capture_frame_missing_output_path", "capture": capture}
    url = f"{ARM_HOST}/{output_path.lstrip('/')}"
    try:
        with urllib.request.urlopen(url, timeout=8.0) as response:
            image = Image.open(io.BytesIO(response.read())).convert("RGB")
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}", "capture": capture, "url": url}
    width, height = image.size
    blue_pixels = 0
    ignored_self_blue_pixels = 0
    strongest = {"x": 0, "y": 0, "score": 0}
    for y in range(0, height, 3):
        for x in range(0, width, 3):
            r, g, b = image.getpixel((x, y))
            if b >= 95 and b > r * 1.25 and b > g * 1.1:
                if (
                    x <= int(width * 0.12)
                    or x >= int(width * 0.88)
                    or y <= int(height * 0.08)
                    or y >= int(height * 0.82)
                    or (x >= int(width * 0.82) and y >= int(height * 0.68))
                ):
                    ignored_self_blue_pixels += 1
                    continue
                blue_pixels += 1
                score = int(b) - int(max(r, g))
                if score > strongest["score"]:
                    strongest = {"x": x, "y": y, "score": score}
    return {
        "ok": True,
        "capture": capture.get("data"),
        "url": url,
        "width": width,
        "height": height,
        "blue_sample_pixels": blue_pixels,
        "ignored_self_blue_sample_pixels": ignored_self_blue_pixels,
        "blue_pixel_ratio_sampled": round(blue_pixels / max(1, (width // 3) * (height // 3)), 6),
        "strongest_blue_sample": strongest,
        "self_blue_mask_policy": (
            "Ignore image edges, lower frame, and bottom-right wrist hardware region where the wrist-mounted camera "
            "can see MIM's own blue parts or nearby human clothing instead of the table target."
        ),
        "target_visible_in_gripper_camera": blue_pixels >= 20,
    }


def run_no_contact_visual_servo_probe(start_pose: list[Any]) -> dict[str, Any]:
    if len(start_pose) < 6:
        return {"ok": False, "error": "current_pose_unavailable", "probes": []}
    base_start = int(start_pose[0])
    offsets = [-6, -3, 0, 3, 6]
    probes: list[dict[str, Any]] = []
    best: dict[str, Any] = {}
    for offset in offsets:
        target_angle = max(0, min(180, base_start + offset))
        current_angle = int(probes[-1]["target_angle"]) if probes else base_start
        move = slow_move_servo(
            0,
            current_angle,
            target_angle,
            source="mim_blue_block_no_contact_visual_servo_probe",
        )
        time.sleep(0.6)
        score = capture_arm_camera_blue_score()
        probe = {
            "servo": 0,
            "offset": offset,
            "target_angle": target_angle,
            "move": move,
            "score": score,
        }
        probes.append(probe)
        if score.get("ok") and (
            not best
            or int(score.get("blue_sample_pixels") or 0) > int((best.get("score") or {}).get("blue_sample_pixels") or 0)
        ):
            best = probe
    return_move = slow_move_servo(
        0,
        int(probes[-1]["target_angle"]) if probes else base_start,
        base_start,
        source="mim_blue_block_no_contact_visual_servo_probe_return",
    )
    return {
        "ok": True,
        "probe_type": "bounded_base_sweep_no_contact",
        "start_base_angle": base_start,
        "returned_to_start": bool(return_move.get("ok")),
        "return_move": return_move,
        "probes": probes,
        "best_probe": best,
        "target_visible_in_any_probe": any((probe.get("score") or {}).get("target_visible_in_gripper_camera") for probe in probes),
    }


def run_wrist_hand_camera_view_scan(start_pose: list[Any]) -> dict[str, Any]:
    if len(start_pose) < 6:
        return {"ok": False, "error": "current_pose_unavailable", "probes": []}
    start = [int(value) for value in start_pose[:6]]
    wrist_start = start[WRIST_SERVO]
    hand_start = start[HAND_SERVO]
    scan_offsets = [
        {"wrist_offset": 0, "hand_offset": 0},
        {"wrist_offset": -10, "hand_offset": 0},
        {"wrist_offset": 10, "hand_offset": 0},
        {"wrist_offset": 0, "hand_offset": -10},
        {"wrist_offset": 0, "hand_offset": 10},
        {"wrist_offset": -10, "hand_offset": -10},
        {"wrist_offset": 10, "hand_offset": 10},
    ]
    probes: list[dict[str, Any]] = []
    best: dict[str, Any] = {}
    current_wrist = wrist_start
    current_hand = hand_start
    for item in scan_offsets:
        wrist_target = max(0, min(180, wrist_start + int(item["wrist_offset"])))
        hand_target = max(0, min(180, hand_start + int(item["hand_offset"])))
        wrist_move = slow_move_servo(
            WRIST_SERVO,
            current_wrist,
            wrist_target,
            source="mim_blue_block_wrist_mounted_camera_scan",
        )
        if wrist_move.get("ok"):
            current_wrist = wrist_target
        hand_move = slow_move_servo(
            HAND_SERVO,
            current_hand,
            hand_target,
            source="mim_blue_block_wrist_mounted_camera_scan",
        )
        if hand_move.get("ok"):
            current_hand = hand_target
        time.sleep(0.8)
        score = capture_arm_camera_blue_score()
        probe = {
            "wrist_servo": WRIST_SERVO,
            "hand_servo": HAND_SERVO,
            "wrist_offset": item["wrist_offset"],
            "hand_offset": item["hand_offset"],
            "wrist_target": wrist_target,
            "hand_target": hand_target,
            "wrist_move": wrist_move,
            "hand_move": hand_move,
            "score": score,
        }
        probes.append(probe)
        if score.get("ok") and (
            not best
            or int(score.get("blue_sample_pixels") or 0) > int((best.get("score") or {}).get("blue_sample_pixels") or 0)
        ):
            best = probe
    hand_return = slow_move_servo(
        HAND_SERVO,
        current_hand,
        hand_start,
        source="mim_blue_block_wrist_mounted_camera_scan_return",
    )
    if hand_return.get("ok"):
        current_hand = hand_start
    wrist_return = slow_move_servo(
        WRIST_SERVO,
        current_wrist,
        wrist_start,
        source="mim_blue_block_wrist_mounted_camera_scan_return",
    )
    return {
        "ok": True,
        "probe_type": "wrist_mounted_camera_orientation_scan",
        "camera_mount": {
            "description": "Arm camera is attached to the top of the wrist; use wrist and hand motions to steer the camera view.",
            "wrist_servo": WRIST_SERVO,
            "hand_servo": HAND_SERVO,
        },
        "motion_profile": {
            "name": "slow_operator_visible_probe",
            "step_degrees": SLOW_MOVE_STEP_DEG,
            "settle_seconds": SLOW_MOVE_SETTLE_SECONDS,
        },
        "start_wrist_angle": wrist_start,
        "start_hand_angle": hand_start,
        "returned_to_start": bool(hand_return.get("ok") and wrist_return.get("ok")),
        "hand_return": hand_return,
        "wrist_return": wrist_return,
        "probes": probes,
        "best_probe": best,
        "target_visible_in_any_probe": any((probe.get("score") or {}).get("target_visible_in_gripper_camera") for probe in probes),
    }


def move_pose_stepwise(
    current_pose: list[int],
    target_pose: list[int],
    *,
    source: str,
    settle: float = 0.8,
) -> list[dict[str, Any]]:
    moves: list[dict[str, Any]] = []
    for servo, angle in enumerate(target_pose[:6]):
        start_angle = int(current_pose[servo]) if servo < len(current_pose) else int(angle)
        result = slow_move_servo(servo, start_angle, int(angle), source=source)
        moves.append({"servo": servo, "target_angle": int(angle), "result": result})
        if result.get("ok"):
            current_pose[servo] = int(angle)
        time.sleep(settle)
    return moves


def saved_observation_pose(workspace_data: dict[str, Any]) -> list[int]:
    arm = workspace_data.get("arm") if isinstance(workspace_data.get("arm"), dict) else {}
    saved = arm.get("saved_poses") if isinstance(arm.get("saved_poses"), list) else []
    for item in saved:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip().lower()
        pose = item.get("pose")
        if "setup" in name and isinstance(pose, list) and len(pose) >= 6:
            return [int(value) for value in pose[:6]]
    default_pose = arm.get("default_pose")
    if isinstance(default_pose, list) and len(default_pose) >= 6:
        return [int(value) for value in default_pose[:6]]
    return []


def run_saved_observation_pose_probe(start_pose: list[Any], workspace_data: dict[str, Any]) -> dict[str, Any]:
    if len(start_pose) < 6:
        return {"ok": False, "error": "current_pose_unavailable"}
    target_pose = saved_observation_pose(workspace_data)
    if len(target_pose) < 6:
        return {"ok": False, "error": "saved_observation_pose_unavailable"}
    start = [int(value) for value in start_pose[:6]]
    working_pose = list(start)
    out_moves = move_pose_stepwise(
        working_pose,
        target_pose,
        source="mim_blue_block_saved_observation_pose_probe",
    )
    time.sleep(0.5)
    score = capture_arm_camera_blue_score()
    return_moves = move_pose_stepwise(
        working_pose,
        start,
        source="mim_blue_block_saved_observation_pose_probe_return",
    )
    return {
        "ok": True,
        "probe_type": "saved_observation_pose_no_contact",
        "start_pose": start,
        "target_pose": target_pose,
        "motion_profile": {
            "name": "slow_operator_visible_probe",
            "step_degrees": SLOW_MOVE_STEP_DEG,
            "settle_seconds": SLOW_MOVE_SETTLE_SECONDS,
        },
        "moved_to_observation_pose": all(move.get("result", {}).get("ok") for move in out_moves),
        "returned_to_start": all(move.get("result", {}).get("ok") for move in return_moves),
        "observation_score": score,
        "target_visible_in_gripper_camera": bool(score.get("target_visible_in_gripper_camera")),
        "out_moves": out_moves,
        "return_moves": return_moves,
    }


def sorted_blue_candidates(reference_map: dict[str, Any]) -> list[dict[str, Any]]:
    candidates = reference_map.get("blue_object_candidates")
    if not isinstance(candidates, list):
        return []
    def pickup_score(item: dict[str, Any]) -> float:
        bbox = item.get("bbox") if isinstance(item.get("bbox"), dict) else {}
        center = item.get("center") if isinstance(item.get("center"), dict) else {}
        width = float(bbox.get("width") or 9999)
        height = float(bbox.get("height") or 9999)
        cx = float(center.get("x") or 0)
        cy = float(center.get("y") or 0)
        # Current fixed Pi observer pickup target zone. This rejects blue arm hardware,
        # background objects, and very large blue false positives.
        in_pickup_zone = 430 <= cx <= 620 and 330 <= cy <= 440
        plausible_block_size = 18 <= width <= 85 and 18 <= height <= 90
        zone_bonus = 1_000_000 if in_pickup_zone else 0
        size_bonus = 250_000 if plausible_block_size else 0
        sample_score = float(item.get("sample_points") or 0)
        distance_penalty = ((cx - 546.0) ** 2 + (cy - 394.0) ** 2) ** 0.5
        return zone_bonus + size_bonus + sample_score - distance_penalty
    return sorted(
        [item for item in candidates if isinstance(item, dict)],
        key=pickup_score,
        reverse=True,
    )


def distance_sensor_status() -> dict[str, Any]:
    calibration = read_json(SHARED / "MIM_ARM_IR_SENSOR_CALIBRATION_STATUS.latest.json")
    status = get_json("/distance/status", timeout=5.0)
    data = status.get("data") if isinstance(status.get("data"), dict) else {}
    distance_mm = data.get("distance_mm")
    valid_reading = (
        bool(status.get("ok"))
        and bool(data.get("connected"))
        and isinstance(distance_mm, (int, float))
        and float(distance_mm) > 0
    )
    return {
        "ok": bool(status.get("ok")),
        "endpoint": "/distance/status",
        "mount": "top_of_hand_slightly_behind_grip_tips",
        "offset_from_grip_tips_mm": IR_SENSOR_OFFSET_FROM_GRIP_TIPS_MM,
        "use": "proximity and approach-limit evidence after calibration; not a replacement for camera/collision checks",
        "data": data,
        "calibration_artifact": {
            "artifact": "runtime/shared/MIM_ARM_IR_SENSOR_CALIBRATION_STATUS.latest.json",
            "exists": bool(calibration),
            "status": calibration.get("status"),
            "success": calibration.get("success"),
            "blockers": calibration.get("blockers") if isinstance(calibration.get("blockers"), list) else [],
        },
        "valid_distance_reading": valid_reading,
        "validation_status": "valid_live_reading" if valid_reading else "connected_but_unvalidated_or_zero_reading",
        "blocked_reason": ""
        if valid_reading
        else "distance_sensor_reports_zero_or_missing_distance; calibrate before using as grip/contact proof",
        "raw_status": status,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute-no-contact-validation", action="store_true")
    parser.add_argument("--execute-saved-observation-pose", action="store_true")
    parser.add_argument("--execute-wrist-camera-scan", action="store_true")
    parser.add_argument("--execute-grip", action="store_true")
    args = parser.parse_args()

    generated_at = now_iso()
    objective = {
        "packet_type": "mim-arm-blue-block-pickup-objective-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-TRAINING-V1",
        "status": "active",
        "goal": "Progress MIM from visible blue-block detection to a safe verified pickup.",
        "success_criteria": [
            "A blue block target is selected from current camera evidence.",
            "MIM has a trusted table coordinate or a validated visual servo approach.",
            "MIM uses wrist and hand motion first to aim the wrist-mounted arm camera.",
            "MIM validates the top-of-hand IR proximity sensor before using it as approach proof.",
            "MIM performs no-contact approach validation before gripping.",
            "MIM only closes the claw when the target is visible/reachable and collision checks pass.",
            "MIM publishes before/after evidence before claiming pickup success.",
        ],
        "hard_stop_conditions": [
            "No trusted table coordinate or visual-servo approach evidence.",
            "No collision-checked approach path.",
            "No fresh camera evidence.",
            "No verified gripper/target alignment.",
        ],
        "end_effector_sensor_model": {
            "ir_sensor": {
                "mount": "top_of_hand_slightly_behind_grip_tips",
                "offset_from_grip_tips_mm": IR_SENSOR_OFFSET_FROM_GRIP_TIPS_MM,
                "role": "approach proximity and contact-risk evidence after calibration",
            }
        },
    }
    write_json(OBJECTIVE_PATH, objective)

    reference_map = read_json(SHARED / "MIM_ARM_TABLE_REFERENCE_MAP.latest.json")
    scene = read_json(SHARED / "MIM_ARM_TABLE_SCENE.latest.json")
    calibration = read_json(SHARED / "MIM_ARM_CALIBRATION_TRAINING_STATUS.latest.json")
    arm_camera = read_json(SHARED / "MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json")
    pi_observer = read_json(SHARED / "MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json")
    pc_observer = read_json(SHARED / "MIM_ARM_TABLE_OBSERVER_STATUS.latest.json")
    visual_servo_probe = read_json(SHARED / "MIM_ARM_BLUE_BLOCK_VISUAL_SERVO_PROBE.latest.json")
    workspace_safety = read_json(SHARED / "MIM_ARM_BLUE_BLOCK_WORKSPACE_SAFETY.latest.json")
    arm_state = get_json("/arm_state")
    workspace = get_json("/workspace_setup_state")
    distance_sensor = distance_sensor_status()

    blue_candidates = sorted_blue_candidates(reference_map)
    target = blue_candidates[0] if blue_candidates else {}
    arm_data = arm_state.get("data") if isinstance(arm_state.get("data"), dict) else {}
    workspace_data = workspace.get("data") if isinstance(workspace.get("data"), dict) else {}
    pose = arm_data.get("current_pose") if isinstance(arm_data.get("current_pose"), list) else []
    serial = arm_data.get("serial") if isinstance(arm_data.get("serial"), dict) else {}
    label_policy = reference_map.get("label_policy") if isinstance(reference_map.get("label_policy"), dict) else {}
    fixed_observer_available = bool(pi_observer.get("success") or pc_observer.get("success"))
    camera_evidence_ready = bool(arm_camera.get("success") and fixed_observer_available)
    optional_camera_blockers: list[str] = []
    if pi_observer and pi_observer.get("success") is not True:
        optional_camera_blockers.append("pi_table_observer_unavailable")
    if pc_observer and pc_observer.get("success") is not True:
        optional_camera_blockers.append("pc_table_observer_unavailable")

    blockers: list[str] = []
    if not target:
        blockers.append("blue_block_target_not_selected")
    if not camera_evidence_ready:
        blockers.append("required_camera_evidence_missing")
    if calibration.get("success") is not True:
        blockers.append("calibration_not_successful")
    if not label_policy.get("numbered_pad_labels_trusted"):
        blockers.append("reference_labels_not_trusted")
    if not arm_state.get("ok") or not serial.get("serial_ready"):
        blockers.append("arm_or_serial_not_ready")
    if not pose or len(pose) < 6:
        blockers.append("current_pose_unavailable")
    if not distance_sensor.get("valid_distance_reading"):
        blockers.append("ir_proximity_sensor_connected_but_not_calibrated_for_grip_approach")
    human_policy = workspace_safety.get("human_policy") if isinstance(workspace_safety.get("human_policy"), dict) else {}
    if workspace_safety.get("human_inside_immediate_contact_envelope") is True:
        blockers.append("human_inside_immediate_contact_envelope")
    elif (
        workspace_safety.get("human_present_in_arm_workspace") is True
        and human_policy.get("visible_human_is_hard_stop") is True
    ):
        blockers.append("human_present_in_arm_workspace")
    best_visual_distance = None
    try:
        best_visual_distance = float((visual_servo_probe.get("best_probe_summary") or {}).get("distance_px"))
    except Exception:
        best_visual_distance = None
    if visual_servo_probe and best_visual_distance is not None and best_visual_distance <= 180:
        visual_alignment_blocker = ""
    else:
        visual_alignment_blocker = "visual_servo_target_alignment_not_validated"
    blockers.extend(
        [item for item in [
            visual_alignment_blocker,
            "collision_checked_approach_path_not_bound",
            "grasp_close_lift_verify_sequence_not_bound",
        ] if item]
    )

    dry_run_plan = {
        "target": target,
        "estimated_table_normalized": target.get("normalized_center") if target else {},
        "current_pose": pose[:6] if isinstance(pose, list) else [],
        "candidate_strategy": "largest_blue_reference_candidate_from_fixed_observer",
        "camera_mount_model": {
            "mount": "top_of_wrist",
            "primary_view_control_servos": {"wrist": WRIST_SERVO, "hand": HAND_SERVO},
            "policy": "Use wrist and hand motions to steer the arm-camera view before moving larger arm joints.",
        },
        "end_effector_sensor_model": {
            "ir_sensor": {
                "mount": "top_of_hand_slightly_behind_grip_tips",
                "offset_from_grip_tips_mm": IR_SENSOR_OFFSET_FROM_GRIP_TIPS_MM,
                "current_status": distance_sensor.get("validation_status"),
                "policy": "Use as a proximity/approach guard only after nonzero readings are validated against known distances.",
            }
        },
        "required_next_validation": [
            "Use slow wrist and hand movements to aim the wrist-mounted camera until the blue block appears in the arm camera.",
            "Validate the top-of-hand IR sensor against known clear/object distances before using it as approach proof.",
            "Verify target remains stationary and gripper is above/near target without contact.",
            "Publish a collision-checked approach pose and retreat pose.",
            "Only then allow a guarded claw close/lift attempt.",
        ],
    }

    attempted_actions: list[dict[str, Any]] = []
    live_pickup_allowed = not blockers
    no_contact_probe: dict[str, Any] = {}
    saved_pose_probe: dict[str, Any] = {}
    wrist_camera_scan: dict[str, Any] = {}
    if args.execute_saved_observation_pose:
        saved_pose_probe = run_saved_observation_pose_probe(pose, workspace_data if isinstance(workspace_data, dict) else {})
        attempted_actions.append(
            {
                "action": "execute_saved_observation_pose_probe",
                "executed": bool(saved_pose_probe.get("ok")),
                "result": saved_pose_probe,
            }
        )
        if saved_pose_probe.get("target_visible_in_gripper_camera"):
            blockers = [item for item in blockers if item != "visual_servo_target_alignment_not_validated"]
        else:
            blockers = list(dict.fromkeys(blockers + ["blue_target_not_visible_in_gripper_camera_after_saved_observation_pose"]))
        live_pickup_allowed = not blockers

    if args.execute_wrist_camera_scan:
        wrist_camera_scan = run_wrist_hand_camera_view_scan(pose)
        attempted_actions.append(
            {
                "action": "execute_wrist_camera_scan",
                "executed": bool(wrist_camera_scan.get("ok")),
                "result": wrist_camera_scan,
            }
        )
        if wrist_camera_scan.get("target_visible_in_any_probe"):
            blockers = [item for item in blockers if item != "visual_servo_target_alignment_not_validated"]
        else:
            blockers = list(dict.fromkeys(blockers + ["blue_target_not_visible_in_wrist_mounted_camera_scan"]))
        live_pickup_allowed = not blockers

    if args.execute_no_contact_validation:
        no_contact_probe = run_no_contact_visual_servo_probe(pose)
        attempted_actions.append(
            {
                "action": "execute_no_contact_validation",
                "executed": bool(no_contact_probe.get("ok")),
                "result": no_contact_probe,
            }
        )
        if no_contact_probe.get("target_visible_in_any_probe"):
            blockers = [item for item in blockers if item != "visual_servo_target_alignment_not_validated"]
        else:
            blockers = list(dict.fromkeys(blockers + ["blue_target_not_visible_in_gripper_camera_after_no_contact_probe"]))
        live_pickup_allowed = not blockers

    if args.execute_grip and not live_pickup_allowed:
        attempted_actions.append(
            {
                "action": "execute_grip",
                "executed": False,
                "reason": "blocked_before_live_grip",
                "blockers": blockers,
            }
        )
    elif args.execute_grip and live_pickup_allowed:
        attempted_actions.append({"action": "execute_grip", "executed": False, "reason": "not_implemented_without_validation"})

    payload = {
        "packet_type": "mim-arm-blue-block-pickup-training-v1",
        "generated_at": generated_at,
        "objective_id": objective["objective_id"],
        "status": "blocked_before_live_pickup" if blockers else "ready_for_guarded_no_contact_validation",
        "success": False,
        "requested_action": "pick_up_blue_block",
        "camera_mount_model": {
            "mount": "top_of_wrist",
            "primary_view_control_servos": {"wrist": WRIST_SERVO, "hand": HAND_SERVO},
            "lesson": "The arm camera view should be explored with wrist and hand movements before moving the whole arm toward an object.",
        },
        "end_effector_sensor_model": {
            "ir_sensor": {
                "mount": "top_of_hand_slightly_behind_grip_tips",
                "offset_from_grip_tips_mm": IR_SENSOR_OFFSET_FROM_GRIP_TIPS_MM,
                "status": distance_sensor,
            }
        },
        "motion_policy": {
            "name": "slow_operator_visible_probe",
            "step_degrees": SLOW_MOVE_STEP_DEG,
            "settle_seconds": SLOW_MOVE_SETTLE_SECONDS,
            "reason": "Operator reported prior arm probes were too fast; all future probes must use slow visible ramps.",
        },
        "target_selection": {
            "selected": bool(target),
            "target": target,
            "blue_candidate_count": len(blue_candidates),
            "source_artifact": "runtime/shared/MIM_ARM_TABLE_REFERENCE_MAP.latest.json",
        },
        "readiness": {
            "arm_state_ok": bool(arm_state.get("ok")),
            "serial_ready": bool(serial.get("serial_ready")),
            "current_pose": pose[:6] if isinstance(pose, list) else [],
            "ir_proximity_sensor": distance_sensor,
            "workspace_table": workspace_data.get("table") if isinstance(workspace_data, dict) else {},
            "camera_evidence": {
                "arm_camera": arm_camera.get("generated_at"),
                "pi_observer": pi_observer.get("generated_at"),
                "pc_observer": pc_observer.get("generated_at"),
                "policy": "Require the arm-mounted camera plus at least one fixed observer. Pi and PC observers are useful redundancy, but a missing optional observer must not stop visual learning when the other fixed observer is fresh.",
                "required_camera_evidence_ready": camera_evidence_ready,
                "fixed_observer_available": fixed_observer_available,
                "optional_camera_blockers": optional_camera_blockers,
            },
            "calibration_status": calibration.get("status"),
            "scene_status": scene.get("status"),
            "visual_servo_probe": {
                "artifact": "runtime/shared/MIM_ARM_BLUE_BLOCK_VISUAL_SERVO_PROBE.latest.json",
                "status": visual_servo_probe.get("status"),
                "best_probe_summary": visual_servo_probe.get("best_probe_summary", {}),
                "blockers": visual_servo_probe.get("blockers", []),
                "alignment_distance_px_threshold": 180,
                "alignment_ready": bool(best_visual_distance is not None and best_visual_distance <= 180),
            },
            "workspace_safety": {
                "artifact": "runtime/shared/MIM_ARM_BLUE_BLOCK_WORKSPACE_SAFETY.latest.json",
                "status": workspace_safety.get("status"),
                "human_present_in_arm_workspace": workspace_safety.get("human_present_in_arm_workspace"),
                "human_inside_immediate_contact_envelope": workspace_safety.get("human_inside_immediate_contact_envelope"),
                "human_policy": human_policy,
                "blockers": workspace_safety.get("blockers", []),
            },
        },
        "dry_run_plan": dry_run_plan,
        "no_contact_visual_servo_probe": no_contact_probe,
        "wrist_mounted_camera_scan": wrist_camera_scan,
        "saved_observation_pose_probe": saved_pose_probe,
        "attempted_actions": attempted_actions,
        "blockers": list(dict.fromkeys(blockers)),
        "next_recovery_action": (
            "Compute or learn a trusted visual-servo approach pose that brings the selected blue target into the arm camera, "
            "then run no-contact validation before any claw close."
        ),
        "evidence_artifacts": [
            "runtime/shared/MIM_ARM_BLUE_BLOCK_PICKUP_OBJECTIVE.latest.json",
            "runtime/shared/MIM_ARM_TABLE_REFERENCE_MAP.latest.json",
            "runtime/shared/MIM_ARM_CALIBRATION_TRAINING_STATUS.latest.json",
            "runtime/shared/MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json",
            "runtime/shared/MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json",
            "runtime/shared/MIM_ARM_TABLE_OBSERVER_STATUS.latest.json",
            "runtime/shared/MIM_ARM_BLUE_BLOCK_VISUAL_SERVO_PROBE.latest.json",
            "runtime/shared/MIM_ARM_BLUE_BLOCK_WORKSPACE_SAFETY.latest.json",
        ],
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["target_selection"]["selected"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
