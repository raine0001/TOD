#!/usr/bin/env python3
from __future__ import annotations

import json
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_CONTACT_LEARNING_OBSERVATION.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_CONTACT_LEARNING_OBJECTIVE.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
OBJECTIVE_ID = "MIM-ARM-CONTACT-LEARNING-V1"


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


def load_json(path: Path) -> dict[str, Any]:
    try:
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8-sig"))
            return data if isinstance(data, dict) else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def camera_file_from_status(status: dict[str, Any]) -> str:
    response = status.get("capture_response")
    if isinstance(response, dict):
        return str(response.get("file_name") or "")
    return ""


def main() -> int:
    generated_at = now_iso()
    camera_status = load_json(SHARED / "MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json")
    current_pose = request_json("/get_current_position")
    arm_state = request_json("/arm_state")
    distance_status = request_json("/distance/status")
    i2c_scan = request_json("/sensor/i2c_scan")

    pose_data = current_pose.get("data") if isinstance(current_pose.get("data"), dict) else {}
    pose = pose_data.get("angles") if isinstance(pose_data.get("angles"), list) else []
    distance_data = distance_status.get("data") if isinstance(distance_status.get("data"), dict) else {}
    i2c_data = i2c_scan.get("data") if isinstance(i2c_scan.get("data"), dict) else {}

    distance_available = bool(distance_data.get("ok") is True and distance_data.get("source") == "arduino_i2c_0x10")
    i2c_present = bool(i2c_data.get("addresses"))

    camera_interpretation = {
        "contact_visible": "inconclusive",
        "reason": (
            "The arm-mounted camera frame shows gripper pad/self and table surface, but does not clearly expose "
            "the actual claw tip/table interface or compression point."
        ),
        "frame_file": camera_file_from_status(camera_status),
        "frame_path": camera_status.get("local_frame_path"),
    }
    sensor_interpretation = {
        "distance_available": distance_available,
        "i2c_present": i2c_present,
        "distance_status": distance_data,
        "i2c_scan": i2c_data,
        "meaning": (
            "Distance cannot confirm or deny table contact because the authoritative Arduino I2C channel is offline."
            if not distance_available
            else "Distance channel is available and should be compared against visual contact evidence."
        ),
    }
    pose_interpretation = {
        "current_pose": pose,
        "meaning": (
            "Pose is a body-state clue only. Without force feedback or reliable distance, pose alone cannot prove contact."
        ),
    }

    write_json(
        OBJECTIVE_PATH,
        {
            "packet_type": "mim-arm-contact-learning-objective-v1",
            "generated_at": generated_at,
            "objective_id": OBJECTIVE_ID,
            "status": "active",
            "learning_owner": "MIM",
            "goal": "Learn from the operator-observed grip/table press by comparing camera, pose, and distance evidence.",
            "success_criteria": [
                "Record operator contact label as supervised learning evidence.",
                "Separate camera-visible contact from camera-inconclusive contact.",
                "Separate sensor unavailable from sensor-confirmed contact.",
                "Create a recovery/tuning target without erasing the learning event.",
            ],
        },
    )

    payload = {
        "packet_type": "mim-arm-contact-learning-observation-v1",
        "generated_at": generated_at,
        "objective_id": OBJECTIVE_ID,
        "status": "completed_with_supervised_contact_learning_evidence",
        "success": True,
        "learning_owner": "MIM",
        "operator_observation": {
            "label": "grip_pressed_into_table",
            "confidence": "high_from_operator",
            "notes": "Dave observed the grip pressed into the table during MIM cube exploration.",
        },
        "multimodal_evidence": {
            "camera": camera_interpretation,
            "distance_sensor": sensor_interpretation,
            "pose": pose_interpretation,
            "arm_state": arm_state.get("data") if isinstance(arm_state.get("data"), dict) else arm_state,
        },
        "learning_not_rule": {
            "principle": (
                "This is a negative contact example, not merely a prohibition. MIM should learn the evidence pattern "
                "that preceded and followed table contact."
            ),
            "hot_surface_analogy": (
                "The useful lesson is not 'never touch anything'; it is 'recognize harmful contact early, back out, "
                "and improve the next approach using all available senses.'"
            ),
        },
        "lessons": [
            "Operator contact labels are valuable ground truth when camera/sensor evidence is incomplete.",
            "Camera evidence from the current arm mount may be inconclusive for the actual claw/table contact point.",
            "Distance evidence cannot be trusted while the Arduino I2C bus reports no devices or no read.",
            "MIM needs a pre-contact visual model: table plane, claw tip silhouette, and expected clearance before approach.",
        ],
        "next_learning_targets": [
            "Recover I2C distance sensing, then compare sensor distance against camera-visible table contact.",
            "Add a camera-only table-contact classifier using supervised labels: contact, near-contact, clear, inconclusive.",
            "Add a MIM-owned retreat behavior: if contact is suspected, open/lift slightly and record before/after evidence.",
            "When lidar arrives, fuse lidar occupancy with camera and I2C distance instead of using a single hard gate.",
        ],
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps({
        "status": payload["status"],
        "pose": pose,
        "camera_contact_visible": camera_interpretation["contact_visible"],
        "distance_available": distance_available,
        "i2c_present": i2c_present,
        "artifact": str(STATUS_PATH),
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
