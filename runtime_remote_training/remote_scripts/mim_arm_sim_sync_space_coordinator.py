#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
ARM_HOST = "http://192.168.1.90:5000"
GATEWAY_HOST = "http://127.0.0.1:18001"
OBJECTIVE_PATH = SHARED / "MIM_ARM_SIM_SYNC_SPACE_OBJECTIVE.latest.json"
STATUS_PATH = SHARED / "MIM_ARM_SIM_SYNC_SPACE_STATUS.latest.json"
SCAN_PATH = SHARED / "MIM_ARM_AUTONOMOUS_SPACE_SCAN.latest.json"
AREA_PATH = SHARED / "MIM_ARM_AREA_EXPLORATION.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def read_json(path: Path) -> dict[str, Any]:
    try:
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8-sig"))
            return data if isinstance(data, dict) else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def get_url(url: str, *, timeout: float = 5.0) -> dict[str, Any]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            raw = response.read().decode("utf-8", "replace")
        try:
            data = json.loads(raw) if raw else {}
        except Exception:
            data = {"raw": raw}
        return {"ok": True, "url": url, "status_code": response.status, "data": data, "error": ""}
    except Exception as exc:
        return {"ok": False, "url": url, "status_code": None, "data": {}, "error": f"{type(exc).__name__}: {exc}"}


def post_json(url: str, payload: dict[str, Any], *, timeout: float = 5.0) -> dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read().decode("utf-8", "replace")
        try:
            data = json.loads(raw) if raw else {}
        except Exception:
            data = {"raw": raw}
        return {"ok": True, "url": url, "status_code": response.status, "data": data, "error": ""}
    except Exception as exc:
        return {"ok": False, "url": url, "status_code": None, "data": {}, "error": f"{type(exc).__name__}: {exc}"}


def servo_limits(servo_config: list[Any]) -> dict[int, dict[str, int]]:
    limits: dict[int, dict[str, int]] = {}
    for item in servo_config:
        if not isinstance(item, dict):
            continue
        try:
            servo_id = int(item.get("id"))
            limits[servo_id] = {
                "min": int(item.get("min", 0)),
                "max": int(item.get("max", 180)),
            }
        except Exception:
            continue
    return limits


def clamp(value: int, lower: int, upper: int) -> int:
    return max(lower, min(upper, value))


def publish_objective() -> dict[str, Any]:
    payload = {
        "packet_type": "mim-arm-sim-sync-space-objective-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-SIM-SYNC-SPACE-COORDINATOR-V1",
        "status": "active",
        "goal": "Coordinate MIM with the simulation sync space so MIM can move the real arm using the same pose authority as the simulation.",
        "operator_authorization": {
            "source": "Dave",
            "statement": "The arm is in sync; coordinate MIM with the simulation sync space.",
            "autonomous_micro_movement_allowed": True,
        },
        "success_criteria": [
            "MIM reads live arm pose and workspace simulation state before motion.",
            "MIM maps planned motion to servo limits and workspace configuration.",
            "MIM executes a bounded autonomous movement without per-move human confirmation.",
            "MIM verifies the move using arm_state evidence.",
            "MIM reports whether arm camera exploration is live, stale, or blocked.",
        ],
        "safety_contract": {
            "movement_type": "bounded_micro_scan",
            "max_servo_delta_degrees": 5,
            "requires_serial_ready": True,
            "requires_current_pose": True,
            "requires_empty_workspace_obstacles_or_known_safe_path": True,
            "return_to_start_pose_after_probe": True,
            "no_blind_large_sweeps": True,
        },
    }
    write_json(OBJECTIVE_PATH, payload)
    return payload


def camera_evidence() -> dict[str, Any]:
    arm_state = get_url(f"{ARM_HOST}/arm_state")
    camera_state = get_url(f"{GATEWAY_HOST}/mim/arm/camera-state", timeout=2.0)
    capture_proposal = get_url(f"{GATEWAY_HOST}/mim/arm/proposals/capture-frame", timeout=2.0)
    table_observer = read_json(SHARED / "MIM_ARM_TABLE_OBSERVER_STATUS.latest.json")
    arm_camera = {}
    if arm_state.get("ok") and isinstance(arm_state.get("data"), dict):
        arm_camera = arm_state["data"].get("camera") if isinstance(arm_state["data"].get("camera"), dict) else {}
    current_frame = bool(
        arm_camera.get("last_frame_age_seconds") is not None
        or (camera_state.get("ok") and (camera_state.get("data") or {}).get("camera_online") is True)
    )
    return {
        "arm_state_camera": arm_camera,
        "gateway_camera_state": camera_state,
        "gateway_capture_proposal": capture_proposal,
        "arm_table_observer": {
            "status": table_observer.get("status"),
            "success": table_observer.get("success"),
            "generated_at": table_observer.get("generated_at"),
            "remote_frame_path": table_observer.get("remote_frame_path"),
            "selected_camera_index": table_observer.get("selected_camera_index"),
            "frame": table_observer.get("frame", {}),
            "next_recovery_action": table_observer.get("next_recovery_action", ""),
        },
        "current_camera_exploration_ready": current_frame,
        "blocker": "" if current_frame else "no_current_arm_camera_frame_bridge_evidence",
    }


def execute_micro_scan() -> dict[str, Any]:
    arm_state = get_url(f"{ARM_HOST}/arm_state")
    workspace = get_url(f"{ARM_HOST}/workspace_setup_state")
    servo = get_url(f"{ARM_HOST}/servo_config")
    blockers: list[str] = []
    if not arm_state.get("ok"):
        blockers.append("arm_state_unreachable")
    if not workspace.get("ok"):
        blockers.append("workspace_setup_state_unreachable")
    if not servo.get("ok"):
        blockers.append("servo_config_unreachable")

    arm_data = arm_state.get("data") if isinstance(arm_state.get("data"), dict) else {}
    workspace_data = workspace.get("data") if isinstance(workspace.get("data"), dict) else {}
    servo_data = servo.get("data") if isinstance(servo.get("data"), dict) else {}
    pose = arm_data.get("current_pose") if isinstance(arm_data.get("current_pose"), list) else []
    serial = arm_data.get("serial") if isinstance(arm_data.get("serial"), dict) else {}
    obstacles = workspace_data.get("obstacles") if isinstance(workspace_data.get("obstacles"), list) else []
    limits = servo_limits(servo_data.get("servos") if isinstance(servo_data.get("servos"), list) else [])

    if not serial.get("serial_ready"):
        blockers.append("serial_not_ready")
    if not pose or len(pose) < 6:
        blockers.append("current_pose_unavailable")
    if obstacles:
        blockers.append("workspace_obstacles_present_unhandled")
    if 0 not in limits:
        blockers.append("base_servo_limits_unavailable")

    camera = camera_evidence()
    start_pose = list(pose) if isinstance(pose, list) else []
    base_start = int(start_pose[0]) if start_pose else 0
    base_limit = limits.get(0, {"min": 0, "max": 180})
    step = 5
    target = clamp(base_start + step, base_limit["min"], base_limit["max"])
    if target == base_start:
        target = clamp(base_start - step, base_limit["min"], base_limit["max"])
    if target == base_start:
        blockers.append("no_safe_base_micro_delta_available")

    moves: list[dict[str, Any]] = []
    status = "blocked_with_evidence" if blockers else "ready"
    if not blockers:
        for label, angle in [("autonomous_base_micro_scan_out", target), ("autonomous_base_micro_scan_return", base_start)]:
            before = get_url(f"{ARM_HOST}/arm_state")
            result = post_json(f"{ARM_HOST}/move", {"servo": 0, "angle": angle})
            time.sleep(0.35)
            after = get_url(f"{ARM_HOST}/arm_state")
            after_pose = (after.get("data") or {}).get("current_pose") if isinstance(after.get("data"), dict) else []
            moves.append(
                {
                    "label": label,
                    "servo": 0,
                    "target_angle": angle,
                    "before_pose": (before.get("data") or {}).get("current_pose") if isinstance(before.get("data"), dict) else [],
                    "http_result": result,
                    "after_pose": after_pose,
                    "verified_pose_angle": after_pose[0] if isinstance(after_pose, list) and after_pose else None,
                    "verified": bool(result.get("ok") and isinstance(after_pose, list) and after_pose and int(after_pose[0]) == angle),
                }
            )
        status = "completed_with_evidence" if all(move.get("verified") for move in moves) else "blocked_with_evidence"

    payload = {
        "packet_type": "mim-arm-autonomous-space-scan-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-SIM-SYNC-SPACE-COORDINATOR-V1",
        "status": status,
        "success": status == "completed_with_evidence",
        "mode": "autonomous_bounded_micro_scan",
        "human_interaction_required_for_this_scan": False,
        "preflight": {
            "arm_state_ok": bool(arm_state.get("ok")),
            "workspace_setup_ok": bool(workspace.get("ok")),
            "servo_config_ok": bool(servo.get("ok")),
            "serial_ready": bool(serial.get("serial_ready")),
            "start_pose": start_pose,
            "obstacle_count": len(obstacles),
            "base_limits": base_limit,
            "max_servo_delta_degrees": step,
        },
        "simulation_sync_space": {
            "workspace_pose": workspace_data.get("current_pose"),
            "clean_ui_pose": (workspace_data.get("clean_ui") or {}).get("current_pose") if isinstance(workspace_data.get("clean_ui"), dict) else None,
            "table": workspace_data.get("table"),
            "obstacles": obstacles,
            "walls": workspace_data.get("walls", []),
            "markers": workspace_data.get("markers", []),
        },
        "camera_evidence": camera,
        "moves": moves,
        "blockers": blockers,
        "next_recovery_action": ""
        if status == "completed_with_evidence"
        else "Recover blockers, especially current arm-camera frame bridge evidence, before broader autonomous space exploration.",
    }
    write_json(SCAN_PATH, payload)
    return payload


def move_servo_verified(servo: int, angle: int, *, settle_seconds: float = 0.35) -> dict[str, Any]:
    before = get_url(f"{ARM_HOST}/arm_state")
    result = post_json(f"{ARM_HOST}/move", {"servo": servo, "angle": angle})
    time.sleep(settle_seconds)
    after = get_url(f"{ARM_HOST}/arm_state")
    after_pose = (after.get("data") or {}).get("current_pose") if isinstance(after.get("data"), dict) else []
    return {
        "servo": servo,
        "target_angle": angle,
        "before_pose": (before.get("data") or {}).get("current_pose") if isinstance(before.get("data"), dict) else [],
        "http_result": result,
        "after_pose": after_pose,
        "verified_pose_angle": after_pose[servo] if isinstance(after_pose, list) and len(after_pose) > servo else None,
        "verified": bool(result.get("ok") and isinstance(after_pose, list) and len(after_pose) > servo and int(after_pose[servo]) == angle),
    }


def move_pose_stepwise(target_pose: list[int], limits: dict[int, dict[str, int]]) -> list[dict[str, Any]]:
    steps: list[dict[str, Any]] = []
    for servo, angle in enumerate(target_pose):
        limit = limits.get(servo, {"min": 0, "max": 180})
        safe_angle = clamp(int(angle), limit["min"], limit["max"])
        steps.append(move_servo_verified(servo, safe_angle))
        if not steps[-1].get("verified"):
            break
    return steps


def execute_area_exploration() -> dict[str, Any]:
    arm_state = get_url(f"{ARM_HOST}/arm_state")
    workspace = get_url(f"{ARM_HOST}/workspace_setup_state")
    servo = get_url(f"{ARM_HOST}/servo_config")
    blockers: list[str] = []
    if not arm_state.get("ok"):
        blockers.append("arm_state_unreachable")
    if not workspace.get("ok"):
        blockers.append("workspace_setup_state_unreachable")
    if not servo.get("ok"):
        blockers.append("servo_config_unreachable")

    arm_data = arm_state.get("data") if isinstance(arm_state.get("data"), dict) else {}
    workspace_data = workspace.get("data") if isinstance(workspace.get("data"), dict) else {}
    servo_data = servo.get("data") if isinstance(servo.get("data"), dict) else {}
    start_pose_raw = arm_data.get("current_pose") if isinstance(arm_data.get("current_pose"), list) else []
    start_pose = [int(value) for value in start_pose_raw[:6]] if len(start_pose_raw) >= 6 else []
    serial = arm_data.get("serial") if isinstance(arm_data.get("serial"), dict) else {}
    obstacles = workspace_data.get("obstacles") if isinstance(workspace_data.get("obstacles"), list) else []
    limits = servo_limits(servo_data.get("servos") if isinstance(servo_data.get("servos"), list) else [])

    if not serial.get("serial_ready"):
        blockers.append("serial_not_ready")
    if not start_pose:
        blockers.append("current_pose_unavailable")
    if obstacles:
        blockers.append("workspace_obstacles_present_unhandled")
    if len(limits) < 6:
        blockers.append("servo_limits_incomplete")

    max_delta = 5
    viewpoints: list[dict[str, Any]] = []
    if not blockers:
        candidates = [
            ("look_left", {0: start_pose[0] + max_delta}),
            ("look_right", {0: start_pose[0] - max_delta}),
            ("look_slightly_higher", {1: start_pose[1] + 3, 2: start_pose[2] - 3}),
            ("look_slightly_lower", {1: start_pose[1] - 3, 2: start_pose[2] + 3}),
        ]
        for label, changes in candidates:
            target = list(start_pose)
            for servo_id, angle in changes.items():
                limit = limits.get(servo_id, {"min": 0, "max": 180})
                target[servo_id] = clamp(int(angle), limit["min"], limit["max"])
            steps = move_pose_stepwise(target, limits)
            camera = camera_evidence()
            after = get_url(f"{ARM_HOST}/arm_state")
            viewpoints.append(
                {
                    "label": label,
                    "target_pose": target,
                    "move_steps": steps,
                    "verified": bool(steps and all(step.get("verified") for step in steps)),
                    "arm_state_after_view": (after.get("data") or {}).get("current_pose") if isinstance(after.get("data"), dict) else [],
                    "camera_checkpoint": camera,
                }
            )
            return_steps = move_pose_stepwise(start_pose, limits)
            viewpoints[-1]["return_steps"] = return_steps
            viewpoints[-1]["returned_home"] = bool(return_steps and all(step.get("verified") for step in return_steps))
            if not viewpoints[-1]["verified"] or not viewpoints[-1]["returned_home"]:
                blockers.append(f"viewpoint_{label}_verification_failed")
                break

    final_state = get_url(f"{ARM_HOST}/arm_state")
    final_pose = (final_state.get("data") or {}).get("current_pose") if isinstance(final_state.get("data"), dict) else []
    completed = not blockers and bool(viewpoints) and all(v.get("verified") and v.get("returned_home") for v in viewpoints)
    payload = {
        "packet_type": "mim-arm-area-exploration-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-SIM-SYNC-SPACE-COORDINATOR-V1",
        "status": "completed_with_evidence" if completed else "blocked_with_evidence",
        "success": completed,
        "mode": "autonomous_bounded_area_exploration",
        "human_interaction_required_for_this_scan": False,
        "preflight": {
            "arm_state_ok": bool(arm_state.get("ok")),
            "workspace_setup_ok": bool(workspace.get("ok")),
            "servo_config_ok": bool(servo.get("ok")),
            "serial_ready": bool(serial.get("serial_ready")),
            "start_pose": start_pose,
            "max_delta_degrees": max_delta,
            "obstacle_count": len(obstacles),
            "workspace_pose": workspace_data.get("current_pose"),
            "table": workspace_data.get("table"),
            "obstacles": obstacles,
        },
        "viewpoints": viewpoints,
        "final_pose": final_pose,
        "returned_to_start_pose": bool(start_pose and final_pose[:6] == start_pose),
        "blockers": blockers,
        "next_recovery_action": ""
        if completed
        else "Inspect the failed viewpoint and recover camera/frame bridge or motion verification before wider exploration.",
    }
    write_json(AREA_PATH, payload)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute-micro-scan", action="store_true")
    parser.add_argument("--explore-area", action="store_true")
    args = parser.parse_args()
    objective = publish_objective()
    scan = execute_area_exploration() if args.explore_area else execute_micro_scan() if args.execute_micro_scan else {}
    camera = camera_evidence()
    status = {
        "packet_type": "mim-arm-sim-sync-space-status-v1",
        "generated_at": now_iso(),
        "objective_id": objective["objective_id"],
        "status": scan.get("status") if scan else "objective_published",
        "success": bool(scan.get("success")) if scan else False,
        "objective_artifact": "runtime/shared/MIM_ARM_SIM_SYNC_SPACE_OBJECTIVE.latest.json",
        "scan_artifact": (
            "runtime/shared/MIM_ARM_AREA_EXPLORATION.latest.json"
            if args.explore_area and scan
            else "runtime/shared/MIM_ARM_AUTONOMOUS_SPACE_SCAN.latest.json"
            if scan
            else ""
        ),
        "camera_evidence": camera,
        "next_step": "Use the completed bounded scan as the proof slice, then bind current arm-camera frame capture before object-aware exploration.",
    }
    write_json(STATUS_PATH, status)
    print(json.dumps(status if not scan else scan, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
