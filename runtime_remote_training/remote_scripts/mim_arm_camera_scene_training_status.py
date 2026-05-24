#!/usr/bin/env python3
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_CAMERA_SCENE_TRAINING_STATUS.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_CAMERA_SCENE_TRAINING_OBJECTIVE.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(name: str) -> dict[str, Any]:
    path = SHARED / name
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


def camera_status(name: str, role: str) -> dict[str, Any]:
    data = read_json(name)
    frame = data.get("frame") if isinstance(data.get("frame"), dict) else {}
    return {
        "artifact": f"runtime/shared/{name}",
        "role": role,
        "exists": bool(data),
        "status": data.get("status"),
        "success": data.get("success") is True,
        "generated_at": data.get("generated_at"),
        "remote_frame_path": data.get("remote_frame_path"),
        "frame_exists": frame.get("exists") is True,
        "frame_stats": frame.get("stats") if isinstance(frame.get("stats"), dict) else {},
        "error": frame.get("error") or data.get("capture_error") or "",
    }


def main() -> int:
    generated_at = now_iso()
    table_scene = read_json("MIM_ARM_TABLE_SCENE.latest.json")
    cameras = [
        camera_status("MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json", "arm_mounted_gripper_view"),
        camera_status("MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json", "fixed_pi_table_observer"),
        camera_status("MIM_ARM_TABLE_OBSERVER_STATUS.latest.json", "fixed_operator_pc_table_observer"),
    ]
    camera_blockers = [
        f"{item['role']}_missing_or_failed"
        for item in cameras
        if not (item["success"] and item["frame_exists"])
    ]
    scene_blockers = table_scene.get("blockers") if isinstance(table_scene.get("blockers"), list) else []
    object_counts = {
        "objects_total": len(table_scene.get("objects") or []),
        "blue_block_candidates": len(table_scene.get("blue_block_candidates") or []),
        "pad_candidates": len(table_scene.get("pad_candidates") or []),
        "white_or_gray_candidates": len(table_scene.get("white_or_gray_candidates") or []),
    }

    recognition_blockers = []
    if object_counts["blue_block_candidates"] < 1:
        recognition_blockers.append("blue_block_detection_missing")
    if object_counts["pad_candidates"] < 3:
        recognition_blockers.append("three_number_pad_detection_incomplete")
    if "number_pad_ocr_not_bound" in scene_blockers:
        recognition_blockers.append("number_pad_ocr_not_bound")

    blockers = list(dict.fromkeys(camera_blockers + recognition_blockers))
    status = "completed_with_camera_evidence_needs_label_training"
    success = not camera_blockers and object_counts["blue_block_candidates"] >= 1
    if camera_blockers:
        status = "blocked_with_camera_evidence"
        success = False
    elif recognition_blockers:
        status = "partial_success_needs_scene_label_training"

    objective = {
        "packet_type": "mim-arm-camera-scene-training-objective-v1",
        "generated_at": generated_at,
        "objective_id": "ARM-04-CAMERA-AND-SCENE-PERCEPTION",
        "status": "active",
        "goal": "MIM uses arm-mounted and fixed observer cameras to verify arm actions and perceive table objects.",
        "success_criteria": [
            "Arm-mounted camera capture is live and mirrored to MIM.",
            "Fixed Pi table observer capture is live and mirrored to MIM.",
            "Fixed operator PC table observer capture is live and mirrored to MIM.",
            "MIM detects known table objects with current frame evidence.",
            "MIM identifies numbered pads 1, 2, and 3 or publishes an explicit OCR/calibration blocker.",
        ],
        "guardrails": [
            "Do not claim object identity from stale frames.",
            "Do not infer numbered pad labels without OCR, fiducials, or calibrated operator-provided map.",
            "Use fixed observers for whole-table verification and arm camera for gripper/approach verification.",
        ],
    }

    payload = {
        "packet_type": "mim-arm-camera-scene-training-status-v1",
        "generated_at": generated_at,
        "objective_id": "ARM-04-CAMERA-AND-SCENE-PERCEPTION",
        "status": status,
        "success": success,
        "camera_sources": cameras,
        "scene": {
            "artifact": "runtime/shared/MIM_ARM_TABLE_SCENE.latest.json",
            "status": table_scene.get("status"),
            "success": table_scene.get("success"),
            "generated_at": table_scene.get("generated_at"),
            "source_frame": table_scene.get("source_frame", {}),
            "object_counts": object_counts,
            "relationships": table_scene.get("relationships", {}),
        },
        "blockers": blockers,
        "next_recovery_action": (
            "Bind numbered pad OCR/fiducials or a calibrated pad map, then rerun scene perception."
            if recognition_blockers
            else ""
        ),
        "evidence_artifacts": [
            "runtime/shared/MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json",
            "runtime/shared/MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json",
            "runtime/shared/MIM_ARM_TABLE_OBSERVER_STATUS.latest.json",
            "runtime/shared/MIM_ARM_TABLE_SCENE.latest.json",
            "runtime/shared/MIM_ARM_CAMERA_SCENE_TRAINING_OBJECTIVE.latest.json",
        ],
    }

    write_json(OBJECTIVE_PATH, objective)
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
