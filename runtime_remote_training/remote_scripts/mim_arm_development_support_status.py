#!/usr/bin/env python3
from __future__ import annotations

import json
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_DEVELOPMENT_SUPPORT_OBJECTIVE.latest.json"
SYNC_ASSERTION_PATH = SHARED / "MIM_ARM_SYNC_OPERATOR_ASSERTION.latest.json"
ARM_HOST = "http://192.168.1.90:5000"


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


def get_json(endpoint: str) -> dict[str, Any]:
    url = f"{ARM_HOST}{endpoint}"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            data = json.loads(response.read().decode("utf-8", "replace"))
        return {"ok": True, "url": url, "data": data if isinstance(data, dict) else {"value": data}, "error": ""}
    except Exception as exc:
        return {"ok": False, "url": url, "data": {}, "error": f"{type(exc).__name__}: {exc}"}


def parse_utc(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def main() -> int:
    arm_state = get_json("/arm_state")
    workspace = get_json("/workspace_setup_state")
    servo = get_json("/servo_config")
    station_index = read_json(SHARED / "MIM_STATION_FILE_INDEX.latest.json")
    station_mirror = read_json(SHARED / "MIM_STATION_FILE_MIRROR.latest.json")
    sensor_inventory = read_json(SHARED / "MIM_LAB_SENSOR_INVENTORY.latest.json")
    camera_cycle = read_json(SHARED / "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json")
    sync_assertion = read_json(SYNC_ASSERTION_PATH)

    arm_state_data = arm_state.get("data") if isinstance(arm_state.get("data"), dict) else {}
    workspace_data = workspace.get("data") if isinstance(workspace.get("data"), dict) else {}
    servo_data = servo.get("data") if isinstance(servo.get("data"), dict) else {}
    current_pose = arm_state_data.get("current_pose") or workspace_data.get("current_pose") or []
    serial = arm_state_data.get("serial") if isinstance(arm_state_data.get("serial"), dict) else {}
    camera = arm_state_data.get("camera") if isinstance(arm_state_data.get("camera"), dict) else {}
    setup_arm = workspace_data.get("arm") if isinstance(workspace_data.get("arm"), dict) else {}
    joint_map = setup_arm.get("joint_map") if isinstance(setup_arm.get("joint_map"), dict) else {}
    servo_list = servo_data.get("servos") if isinstance(servo_data.get("servos"), list) else []
    serial_ready = bool(serial.get("serial_ready"))
    assertion_at = parse_utc(sync_assertion.get("generated_at"))
    assertion_age_seconds = (
        (datetime.now(timezone.utc) - assertion_at).total_seconds() if assertion_at else None
    )
    fresh_operator_sync_assertion = (
        sync_assertion.get("sync_enabled") is True
        and assertion_age_seconds is not None
        and assertion_age_seconds <= 7200
    )
    sync_awareness = {
        "arm_state_sim_enabled": arm_state_data.get("sim_enabled"),
        "sync_confirmed": bool(arm_state_data.get("sim_enabled") is True or fresh_operator_sync_assertion),
        "source": (
            "arm_state"
            if arm_state_data.get("sim_enabled") is True
            else "fresh_operator_voice_assertion"
            if fresh_operator_sync_assertion
            else "unconfirmed"
        ),
        "operator_assertion": {
            "present": bool(sync_assertion),
            "sync_enabled": sync_assertion.get("sync_enabled"),
            "generated_at": sync_assertion.get("generated_at"),
            "age_seconds": assertion_age_seconds,
            "transcript": sync_assertion.get("transcript", ""),
        },
        "note": "The workspace UI has a Live Sync control, but /arm_state may not expose the operator-visible checkbox state.",
    }

    blockers: list[str] = []
    warnings: list[str] = []
    if not arm_state.get("ok"):
        blockers.append("arm_state_endpoint_unreachable")
    if not servo.get("ok"):
        blockers.append("servo_config_endpoint_unreachable")
    if not serial_ready:
        blockers.append("serial_not_ready")
    if not isinstance(current_pose, list) or len(current_pose) < 6:
        blockers.append("current_pose_unavailable")
    if not sync_awareness["sync_confirmed"]:
        if arm_state.get("ok") and serial_ready and current_pose:
            warnings.append("sync_mode_not_confirmed_by_arm_state")
        else:
            blockers.append("sync_mode_not_confirmed_by_arm_state")
    if not station_index:
        blockers.append("station_file_index_missing")

    motion_policy = {
        "direct_voice_motion": "proposal_only_until_operator_confirms",
        "small_test_move_max_degrees": 10,
        "requires_current_pose": True,
        "requires_serial_ready": True,
        "requires_operator_safety_confirmation": True,
        "safe_prompt_template": "Dave, I am going to move {joint} {degrees} degrees {direction}. Is that a safe move?",
    }

    objective = {
        "packet_type": "mim-arm-development-support-objective-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-DEVELOPMENT-SUPPORT-V1",
        "status": "active",
        "goal": "MIM acts as Dave's voice assistant while developing and testing the MIM arm.",
        "success_criteria": [
            "MIM knows arm app state, sync state, current pose, servo map, sensors, camera availability, and relevant design files.",
            "MIM can discuss arm development and propose improvements/objectives.",
            "MIM can queue safe, bounded movement proposals and ask Dave for confirmation before live motion.",
            "MIM can alert Dave when sync, serial, camera, or movement evidence looks wrong.",
            "MIM can request TOD help when the app, sync, or mirror/control bridge is blocked.",
        ],
        "safety_boundary": "No autonomous live arm motion from voice without explicit operator confirmation and fresh status evidence.",
    }
    write_json(OBJECTIVE_PATH, objective)

    payload = {
        "packet_type": "mim-arm-development-support-status-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-DEVELOPMENT-SUPPORT-V1",
        "status": "ready_for_operator_guarded_support" if not blockers else "blocked_or_needs_attention",
        "success": True,
        "arm_application": {
            "workspace_url": f"{ARM_HOST}/workspace",
            "arm_state_ok": bool(arm_state.get("ok")),
            "workspace_setup_ok": bool(workspace.get("ok")),
            "servo_config_ok": bool(servo.get("ok")),
            "runtime": arm_state_data.get("runtime"),
            "mode": arm_state_data.get("mode"),
            "sim_enabled": arm_state_data.get("sim_enabled"),
            "sync_awareness": sync_awareness,
            "app_alive": arm_state_data.get("app_alive"),
        },
        "motion_awareness": {
            "current_pose": current_pose,
            "joint_map": joint_map,
            "servo_config": servo_list,
            "last_command_result": arm_state_data.get("last_command_result", {}),
            "serial": serial,
            "motion_policy": motion_policy,
        },
        "camera_and_sensor_awareness": {
            "arm_state_camera": camera,
            "lab_sensor_inventory_status": sensor_inventory.get("status"),
            "lab_camera_cycle_status": camera_cycle.get("status"),
        },
        "parts_and_configuration": {
            "station_index_status": station_index.get("status"),
            "primary_working_path": (station_index.get("primary_working_context") or {}).get("path", ""),
            "design_parts_count": (station_index.get("totals") or {}).get("primary_working_files"),
            "latest_mirrored_file": (station_mirror.get("source") or {}).get("name", ""),
            "links": setup_arm.get("links", {}),
            "visual_calibration": setup_arm.get("visual_calibration", {}),
        },
        "blockers": blockers,
        "warnings": warnings,
        "recommended_next_step": "Use voice to ask for arm status, parts, sync state, or safe movement proposals. Confirm before live motion.",
        "source_endpoints": {
            "arm_state": arm_state.get("url"),
            "workspace_setup_state": workspace.get("url"),
            "servo_config": servo.get("url"),
        },
        "artifacts": [
            "runtime/shared/MIM_ARM_DEVELOPMENT_SUPPORT_OBJECTIVE.latest.json",
            "runtime/shared/MIM_STATION_FILE_INDEX.latest.json",
            "runtime/shared/MIM_STATION_FILE_MIRROR.latest.json",
            "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json",
            "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
        ],
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
