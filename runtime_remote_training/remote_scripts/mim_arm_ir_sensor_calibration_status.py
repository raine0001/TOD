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
STATUS_PATH = SHARED / "MIM_ARM_IR_SENSOR_CALIBRATION_STATUS.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_IR_SENSOR_CALIBRATION_OBJECTIVE.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
IR_SENSOR_OFFSET_FROM_GRIP_TIPS_MM = 142


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


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


def request_json(endpoint: str, method: str = "GET", timeout: float = 5.0) -> dict[str, Any]:
    request = urllib.request.Request(f"{ARM_HOST}{endpoint}", method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return {"ok": True, "status_code": response.status, "data": json.loads(response.read().decode("utf-8"))}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def sample_distance(count: int = 12, interval_seconds: float = 0.35) -> list[dict[str, Any]]:
    samples: list[dict[str, Any]] = []
    for index in range(count):
        started_at = now_iso()
        reading = get_json("/distance/status", timeout=4.0)
        data = reading.get("data") if isinstance(reading.get("data"), dict) else {}
        distance_mm = data.get("distance_mm")
        valid_distance = (
            bool(reading.get("ok"))
            and bool(data.get("connected"))
            and isinstance(distance_mm, (int, float))
            and float(distance_mm) > 0
        )
        samples.append(
            {
                "index": index,
                "sampled_at": started_at,
                "ok": bool(reading.get("ok")),
                "connected": bool(data.get("connected")),
                "distance_mm": distance_mm,
                "last_distance_mm": data.get("last_distance_mm"),
                "signal_strength": data.get("signal_strength"),
                "temperature_c": data.get("temperature_c"),
                "port": data.get("port"),
                "valid_distance": valid_distance,
                "raw": reading,
            }
        )
        time.sleep(interval_seconds)
    return samples


def main() -> int:
    generated_at = now_iso()
    objective = {
        "packet_type": "mim-arm-ir-sensor-calibration-objective-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-ARM-IR-SENSOR-CALIBRATION-V1",
        "status": "active",
        "goal": "Calibrate the MIM arm top-of-hand IR proximity sensor before using it for approach or grip safety.",
        "sensor_model": {
            "type": "ir_or_distance_proximity_sensor",
            "mount": "top_of_hand_slightly_behind_grip_tips",
            "offset_from_grip_tips_mm": IR_SENSOR_OFFSET_FROM_GRIP_TIPS_MM,
            "endpoint": "/distance/status",
            "expected_use": "Approach guard and near-object evidence after calibration.",
        },
        "success_criteria": [
            "Endpoint returns connected=true.",
            "Multiple samples produce nonzero distance_mm readings when an object/clear surface is in range.",
            "Readings are stable enough to distinguish clear space from near-object space.",
            "MIM publishes how the 142 mm offset maps sensor distance to estimated grip-tip clearance.",
            "Pickup/grip planning cites this artifact before using IR as safety evidence.",
        ],
        "hard_stop_conditions": [
            "distance_mm remains zero across samples",
            "signal strength remains zero",
            "source implementation cannot be inspected or endpoint behavior cannot be explained",
        ],
    }

    source_inspection = {
        "inspected": True,
        "inspected_on": "arm_host:/home/testpilot/mim_arm",
        "inspected_files": [
            "app.py",
            "distance_routes.py",
            "tf_luna_driver.py",
            "shared.py",
        ],
        "route_summary": {
            "app_registration": "app.py registers distance_bp and initializes TF Luna on /dev/ttyAMA0 at 115200 baud.",
            "status_endpoint": "distance_routes.py /distance/status returns tf_luna.get_status plus last_distance_mm.",
            "test_endpoint": "distance_routes.py /distance/test attempts ten shared.tf_luna.read_distance() calls.",
            "driver_behavior": "tf_luna_driver.py reads 9-byte TF Luna frames headed by 0x59 0x59 and returns None if no valid frame is read.",
        },
        "device_layer_inspection": {
            "user_has_dialout_group": True,
            "configured_port": "/dev/ttyAMA0",
            "configured_port_exists": True,
            "serial0_symlink_seen": "/dev/serial0 -> ttyAMA0",
            "serial_getty_active": False,
            "enable_uart_configured": True,
            "dmesg_notes": [
                "ttyAMA0 is present as a PL011 UART.",
                "Bluetooth HCI UART activity is present in dmesg, so verify the TF Luna is actually wired to the selected UART.",
                "USB Arduino controller is on /dev/ttyACM0 and is separate from the TF Luna UART path.",
            ],
        },
    }

    clear_attempt = request_json("/distance/calibrate", method="POST", timeout=5.0)
    test_attempt = request_json("/distance/test", method="GET", timeout=4.0)
    samples = sample_distance()
    nonzero = [
        item
        for item in samples
        if isinstance(item.get("distance_mm"), (int, float)) and float(item.get("distance_mm") or 0) > 0
    ]
    connected_count = len([item for item in samples if item.get("connected")])
    signal_nonzero = [
        item
        for item in samples
        if isinstance(item.get("signal_strength"), (int, float)) and float(item.get("signal_strength") or 0) > 0
    ]
    distances = [float(item["distance_mm"]) for item in nonzero]

    blockers: list[str] = []
    if connected_count == 0:
        blockers.append("ir_distance_endpoint_not_connected")
    if not nonzero:
        blockers.append("ir_distance_reports_zero_for_all_samples")
    if not signal_nonzero:
        blockers.append("ir_signal_strength_zero_for_all_samples")
    blockers.append("ir_known_distance_calibration_not_performed")
    blockers.append("ir_uart_open_but_no_tf_luna_frames_detected")
    if not test_attempt.get("ok"):
        blockers.append("ir_distance_test_endpoint_timeout_or_error")
    else:
        test_data = test_attempt.get("data") if isinstance(test_attempt.get("data"), dict) else {}
        if int(test_data.get("samples_collected") or 0) == 0:
            blockers.append("ir_distance_test_endpoint_collected_zero_samples")

    usable = not blockers
    status = {
        "packet_type": "mim-arm-ir-sensor-calibration-status-v1",
        "generated_at": generated_at,
        "objective_id": objective["objective_id"],
        "status": "completed_with_calibration_evidence" if usable else "blocked_with_evidence",
        "success": usable,
        "sensor_model": objective["sensor_model"],
        "source_inspection": source_inspection,
        "clear_buffer_attempt": clear_attempt,
        "test_endpoint_attempt": test_attempt,
        "sample_summary": {
            "sample_count": len(samples),
            "connected_count": connected_count,
            "nonzero_distance_count": len(nonzero),
            "nonzero_signal_count": len(signal_nonzero),
            "min_nonzero_distance_mm": min(distances) if distances else None,
            "max_nonzero_distance_mm": max(distances) if distances else None,
            "estimated_grip_tip_clearance_formula": "sensor_distance_mm - 142",
            "current_grip_tip_clearance_mm": (distances[-1] - IR_SENSOR_OFFSET_FROM_GRIP_TIPS_MM) if distances else None,
        },
        "samples": samples,
        "blockers": list(dict.fromkeys(blockers)),
        "policy": {
            "may_use_for_pickup_approach": usable,
            "reason": (
                "IR sensor has calibrated nonzero readings."
                if usable
                else "Do not use IR as approach/contact proof until it reports nonzero values and known-distance calibration is performed."
            ),
        },
        "next_recovery_action": (
            "Repair the distance sensor source/binding on the arm host, then run a known-distance calibration: clear view, "
            "object at known distance, and object near grip tips. Likely checks: TF Luna wiring/power/UART pins, /dev/ttyAMA0 "
            "device assignment, baud rate, and driver frame synchronization. Apply the 142 mm offset after readings are nonzero."
        ),
        "evidence_artifacts": [
            "runtime/shared/MIM_ARM_IR_SENSOR_CALIBRATION_OBJECTIVE.latest.json",
            "runtime/shared/MIM_ARM_IR_SENSOR_CALIBRATION_STATUS.latest.json",
            "runtime/shared/MIM_ARM_BLUE_BLOCK_PICKUP_TRAINING.latest.json",
        ],
    }

    write_json(OBJECTIVE_PATH, objective)
    write_json(STATUS_PATH, status)
    print(json.dumps(status, indent=2, sort_keys=True))
    return 0 if usable else 2


if __name__ == "__main__":
    raise SystemExit(main())
