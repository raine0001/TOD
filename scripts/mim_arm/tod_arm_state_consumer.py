import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a stable MIM ARM read-only state summary from TOD smoke receipts.")
    parser.add_argument("--input", required=True, help="Path to serial_health_smoke.latest.json")
    parser.add_argument("--output", required=True, help="Path to write TOD_ARM_STATE_SUMMARY.latest.json")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)
    payload = load_json(input_path)

    arm_state = payload.get("arm_state") or {}
    serial = arm_state.get("serial") or payload.get("serial_health") or {}
    camera = arm_state.get("camera") or {}
    estop = arm_state.get("estop") or {"supported": False, "active": None}
    last_command = arm_state.get("last_command_result") or {}
    pose = arm_state.get("current_pose")
    runtime_name = arm_state.get("runtime", "unknown")
    runtime_mode = arm_state.get("mode", "unknown")
    sim_enabled = bool(arm_state.get("sim_enabled", False))
    raw_estop_supported = bool(estop.get("supported", False))
    estop_supported_for_promotion = bool(raw_estop_supported or (runtime_name == "sim" and sim_enabled))
    estop_active = estop.get("active")
    if estop_active is None and estop_supported_for_promotion:
        estop_active = False

    promotion_blocking_caveats = []
    promotion_non_blocking_caveats = []
    if not raw_estop_supported:
        if estop_supported_for_promotion:
            promotion_non_blocking_caveats.append(
                {
                    "code": "estop_not_required_in_sim_runtime",
                    "reason": "runtime_is_sim_and_sim_enabled",
                }
            )
        else:
            promotion_blocking_caveats.append(
                {
                    "code": "estop_not_supported_for_promotion",
                    "reason": "runtime_requires_explicit_estop_support",
                }
            )

    promotion_ready = bool(
        bool(arm_state.get("app_alive", False))
        and bool(serial.get("serial_ready", False))
        and bool(camera.get("depthai_device_bound", False))
        and bool(camera.get("video_queue_ready", False))
        and not promotion_blocking_caveats
    )

    summary = {
        "generated_at": utc_now(),
        "source": "mim-arm-read-state-summary-v1",
        "input_path": str(input_path),
        "input_generated_at": payload.get("captured_at_utc", ""),
        "input_sha256": sha256_text(json.dumps(payload, sort_keys=True, separators=(",", ":"))),
        "app": {
            "alive": bool(arm_state.get("app_alive", False)),
            "status": arm_state.get("status", "unknown"),
        },
        "runtime": {
            "mode": runtime_mode,
            "runtime": runtime_name,
            "sim_enabled": sim_enabled,
        },
        "camera": {
            "status": camera.get("status", "unknown"),
            "depthai_device_bound": bool(camera.get("depthai_device_bound", False)),
            "video_queue_ready": bool(camera.get("video_queue_ready", False)),
            "detection_pipeline_enabled": bool(camera.get("detection_pipeline_enabled", False)),
            "detection_stream_configured": bool(camera.get("detection_stream_configured", False)),
            "detections_queue_ready": bool(camera.get("detections_queue_ready", False)),
            "frame_counter": int(camera.get("frame_counter", 0) or 0),
            "last_frame_age_seconds": camera.get("last_frame_age_seconds"),
            "detection_pipeline_error": camera.get("detection_pipeline_error"),
        },
        "serial": {
            "status": serial.get("status", "unknown"),
            "serial_bound": bool(serial.get("serial_bound", False)),
            "serial_ready": bool(serial.get("serial_ready", False)),
            "controller_port": serial.get("controller_port"),
            "controller_error": serial.get("controller_error"),
            "last_serial_event": serial.get("last_serial_event"),
            "last_serial_event_at": serial.get("last_serial_event_at"),
            "last_serial_age_seconds": serial.get("last_serial_age_seconds"),
            "serial_command_count": int(serial.get("serial_command_count", 0) or 0),
            "serial_ack_count": int(serial.get("serial_ack_count", 0) or 0),
            "last_command_sent": serial.get("last_command_sent"),
            "last_command_sent_at": serial.get("last_command_sent_at"),
            "last_command_ack_at": serial.get("last_command_ack_at"),
        },
        "estop": {
            "supported": estop_supported_for_promotion,
            "active": estop_active,
            "raw_supported": raw_estop_supported,
            "supported_for_promotion": estop_supported_for_promotion,
            "support_reason": "sim_runtime_exempt" if (not raw_estop_supported and estop_supported_for_promotion) else "explicit_support",
        },
        "pose": {
            "available": isinstance(pose, list),
            "angles": pose if isinstance(pose, list) else [],
        },
        "last_error": arm_state.get("last_error"),
        "promotion": {
            "ready": promotion_ready,
            "blocking": bool(promotion_blocking_caveats),
            "blocking_caveats": promotion_blocking_caveats,
            "non_blocking_caveats": promotion_non_blocking_caveats,
            "estop_requirement_mode": "sim_runtime_exempt" if (not raw_estop_supported and estop_supported_for_promotion) else "explicit_support_required",
        },
        "last_command_result": {
            "last_command_sent": last_command.get("last_command_sent"),
            "last_command_sent_at": last_command.get("last_command_sent_at"),
            "last_command_ack_at": last_command.get("last_command_ack_at"),
            "acks_total": int(last_command.get("acks_total", 0) or 0),
            "commands_total": int(last_command.get("commands_total", 0) or 0),
        },
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
