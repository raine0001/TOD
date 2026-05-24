#!/usr/bin/env python3
from __future__ import annotations

import json
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
ARM_HOST = "http://192.168.1.90:5000"
ACCESS_PATH = SHARED / "MIM_ARM_ACCESS_BINDING.latest.json"


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


def get_json(endpoint: str) -> dict[str, Any]:
    url = f"{ARM_HOST}{endpoint}"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            raw = response.read().decode("utf-8", "replace")
        data = json.loads(raw) if raw else {}
        return {"ok": True, "url": url, "status_code": response.status, "data": data, "error": ""}
    except Exception as exc:
        return {"ok": False, "url": url, "status_code": None, "data": {}, "error": f"{type(exc).__name__}: {exc}"}


def servo_summary(servo_config: dict[str, Any]) -> list[dict[str, Any]]:
    servos = servo_config.get("servos") if isinstance(servo_config.get("servos"), list) else []
    summary: list[dict[str, Any]] = []
    for servo in servos:
        if not isinstance(servo, dict):
            continue
        summary.append(
            {
                "id": servo.get("id"),
                "name": servo.get("name") or servo.get("label"),
                "min": servo.get("min"),
                "max": servo.get("max"),
                "left_label": servo.get("left_label") or servo.get("left"),
                "right_label": servo.get("right_label") or servo.get("right"),
                "safe_pos": servo.get("safe_pos"),
            }
        )
    return summary


def fresh_success(payload: dict[str, Any]) -> bool:
    return payload.get("success") is True and payload.get("status") in {
        "completed_with_evidence",
        "success",
        "active_with_evidence",
    }


def main() -> int:
    generated_at = now_iso()
    arm_state = get_json("/arm_state")
    workspace = get_json("/workspace_setup_state")
    servo = get_json("/servo_config")

    arm_data = arm_state.get("data") if isinstance(arm_state.get("data"), dict) else {}
    workspace_data = workspace.get("data") if isinstance(workspace.get("data"), dict) else {}
    servo_data = servo.get("data") if isinstance(servo.get("data"), dict) else {}
    serial = arm_data.get("serial") if isinstance(arm_data.get("serial"), dict) else {}
    current_pose = arm_data.get("current_pose") or workspace_data.get("current_pose") or []
    obstacles = workspace_data.get("obstacles") if isinstance(workspace_data.get("obstacles"), list) else []

    pi_observer = read_json(SHARED / "MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json")
    pc_observer = read_json(SHARED / "MIM_ARM_TABLE_OBSERVER_STATUS.latest.json")
    sync_status = read_json(SHARED / "MIM_ARM_SIM_SYNC_SPACE_STATUS.latest.json")
    area_exploration = read_json(SHARED / "MIM_ARM_AREA_EXPLORATION.latest.json")
    autonomous_scan = read_json(SHARED / "MIM_ARM_AUTONOMOUS_SPACE_SCAN.latest.json")
    sync_assertion = read_json(SHARED / "MIM_ARM_SYNC_OPERATOR_ASSERTION.latest.json")
    development_status = read_json(SHARED / "MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json")
    physical_observation = read_json(SHARED / "MIM_ARM_PHYSICAL_MOTION_OBSERVATION.latest.json")

    blockers: list[str] = []
    warnings: list[str] = []
    if not arm_state.get("ok"):
        blockers.append("arm_state_unreachable")
    if not workspace.get("ok"):
        blockers.append("workspace_setup_state_unreachable")
    if not servo.get("ok"):
        blockers.append("servo_config_unreachable")
    if serial.get("serial_ready") is not True:
        blockers.append("serial_not_ready")
    if not isinstance(current_pose, list) or len(current_pose) < 6:
        blockers.append("current_pose_unavailable")
    if not servo_summary(servo_data):
        blockers.append("servo_map_unavailable")
    if obstacles:
        warnings.append("workspace_obstacles_present_requires_object_aware_planning")
    if not fresh_success(pi_observer) and not fresh_success(pc_observer):
        warnings.append("no_fixed_observer_frame_success_currently_bound")
    if physical_observation.get("physical_motion_observed") is False:
        blockers.append("operator_reported_no_physical_motion_after_software_ack")

    preferred_observer = ""
    if fresh_success(pi_observer):
        preferred_observer = "pi_arm_table_observer"
    elif fresh_success(pc_observer):
        preferred_observer = "pc_arm_table_observer"

    access_status = "active_with_evidence" if not blockers else "blocked_with_evidence"
    payload = {
        "packet_type": "mim-arm-access-binding-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-ARM-ACCESS-BINDING-V1",
        "status": access_status,
        "success": not blockers,
        "owner": "MIM",
        "operator_authorization": {
            "operator": "Dave",
            "role": "primary_operator",
            "statement": "MIM is granted bounded access to the MIM arm for development support, monitoring, troubleshooting, and safe sync-space exploration.",
            "granted_at": generated_at,
        },
        "arm_api": {
            "host": ARM_HOST,
            "status_endpoint": f"{ARM_HOST}/arm_state",
            "workspace_endpoint": f"{ARM_HOST}/workspace_setup_state",
            "servo_config_endpoint": f"{ARM_HOST}/servo_config",
            "move_endpoint": f"{ARM_HOST}/move",
            "arm_state_ok": arm_state.get("ok"),
            "workspace_setup_ok": workspace.get("ok"),
            "servo_config_ok": servo.get("ok"),
        },
        "current_evidence": {
            "runtime": arm_data.get("runtime"),
            "mode": arm_data.get("mode"),
            "sim_enabled_api_flag": arm_data.get("sim_enabled"),
            "operator_sync_assertion": {
                "present": bool(sync_assertion),
                "sync_enabled": sync_assertion.get("sync_enabled"),
                "generated_at": sync_assertion.get("generated_at"),
                "transcript": sync_assertion.get("transcript", ""),
            },
            "current_pose": current_pose,
            "serial": serial,
            "workspace_obstacle_count": len(obstacles),
            "servo_map": servo_summary(servo_data),
            "last_command_result": arm_data.get("last_command_result", {}),
            "last_motion_execution": read_json(SHARED / "MIM_ARM_MOTION_EXECUTION.latest.json"),
            "latest_physical_motion_observation": physical_observation,
        },
        "vision_access": {
            "preferred_fixed_observer": preferred_observer,
            "pi_arm_table_observer": {
                "status": pi_observer.get("status"),
                "success": pi_observer.get("success"),
                "generated_at": pi_observer.get("generated_at"),
                "device": pi_observer.get("device"),
                "camera_name": pi_observer.get("camera_name"),
                "remote_frame_path": pi_observer.get("remote_frame_path"),
                "arm_host_frame_path": pi_observer.get("arm_host_frame_path"),
                "frame": pi_observer.get("frame", {}),
                "next_recovery_action": pi_observer.get("next_recovery_action", ""),
            },
            "pc_arm_table_observer": {
                "status": pc_observer.get("status"),
                "success": pc_observer.get("success"),
                "generated_at": pc_observer.get("generated_at"),
                "remote_frame_path": pc_observer.get("remote_frame_path"),
                "selected_camera_index": pc_observer.get("selected_camera_index"),
                "frame": pc_observer.get("frame", {}),
                "next_recovery_action": pc_observer.get("next_recovery_action", ""),
            },
        },
        "autonomy_profile": {
            "allowed_without_per_move_operator_confirmation": [
                "read_arm_state",
                "read_workspace_setup",
                "read_servo_config",
                "refresh_observer_evidence",
                "publish_status_and_blockers",
                "bounded_micro_scan",
                "bounded_area_exploration",
            ],
            "requires_operator_confirmation": [
                "large_motion",
                "motion_near_unknown_object",
                "motion_outside_known_servo_limits",
                "forceful_grip_or_contact_task",
                "start_or_stop_external_processes",
            ],
            "movement_limits": {
                "max_unconfirmed_delta_degrees_per_joint": 5,
                "return_to_start_after_exploratory_scan": True,
                "requires_serial_ready": True,
                "requires_current_pose": True,
                "requires_servo_limits": True,
                "no_blind_large_sweeps": True,
            },
            "stop_conditions": [
                "arm_state_unreachable",
                "serial_not_ready",
                "current_pose_unavailable",
                "servo_map_unavailable",
                "unexpected_pose_after_move",
                "operator_reported_no_physical_motion_after_software_ack",
                "operator_says_stop_or_do_not_disturb",
            ],
        },
        "available_actions": {
            "voice_confirmed_joint_move": "handled by mim_wake_listen_loop.py using live arm_state and /move",
            "sync_space_status": "handled by mim_arm_sim_sync_space_coordinator.py",
            "bounded_area_exploration": "mim_arm_sim_sync_space_coordinator.py --explore-area",
            "pi_observer_refresh": "TOD script Update-MIMArmPiObserverCamera.ps1 -UploadToMim",
            "development_support_status": "mim_arm_development_support_status.py",
        },
        "recent_autonomous_proofs": {
            "sync_space_status": {
                "status": sync_status.get("status"),
                "success": sync_status.get("success"),
                "generated_at": sync_status.get("generated_at"),
                "preferred_fixed_observer": sync_status.get("preferred_fixed_observer"),
            },
            "area_exploration": {
                "status": area_exploration.get("status"),
                "success": area_exploration.get("success"),
                "generated_at": area_exploration.get("generated_at"),
                "move_count": len(area_exploration.get("moves", [])) if isinstance(area_exploration.get("moves"), list) else None,
            },
            "autonomous_scan": {
                "status": autonomous_scan.get("status"),
                "success": autonomous_scan.get("success"),
                "generated_at": autonomous_scan.get("generated_at"),
            },
            "development_support": {
                "status": development_status.get("status"),
                "success": development_status.get("success"),
                "generated_at": development_status.get("generated_at"),
            },
        },
        "not_yet_bound": [
            "object detection and labeling from observer frames",
            "collision-aware trajectory planning",
            "inverse kinematics for arbitrary end-effector targets",
            "continuous visual servoing against the live arm camera",
        ],
        "blockers": blockers,
        "warnings": warnings,
    }
    write_json(ACCESS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if not blockers else 2


if __name__ == "__main__":
    raise SystemExit(main())
