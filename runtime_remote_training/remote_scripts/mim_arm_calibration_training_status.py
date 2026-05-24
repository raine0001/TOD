#!/usr/bin/env python3
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_CALIBRATION_TRAINING_STATUS.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_CALIBRATION_TRAINING_OBJECTIVE.latest.json"


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


def main() -> int:
    generated_at = now_iso()
    scene = read_json("MIM_ARM_TABLE_SCENE.latest.json")
    camera_scene = read_json("MIM_ARM_CAMERA_SCENE_TRAINING_STATUS.latest.json")
    sim_sync = read_json("MIM_ARM_SIM_SYNC_SPACE_STATUS.latest.json")
    area = read_json("MIM_ARM_AREA_EXPLORATION.latest.json")
    manipulation = read_json("MIM_ARM_TABLE_MANIPULATION_TRAINING_STATUS.latest.json")

    object_counts = ((camera_scene.get("scene") or {}).get("object_counts") or {}) if isinstance(camera_scene.get("scene"), dict) else {}
    pad_candidates = scene.get("pad_candidates") if isinstance(scene.get("pad_candidates"), list) else []
    blockers = []
    if not camera_scene.get("success"):
        blockers.append("camera_scene_training_not_ready")
    if len(pad_candidates) < 3:
        blockers.append("insufficient_pad_candidates_for_calibration")
    if "number_pad_ocr_not_bound" in (scene.get("blockers") if isinstance(scene.get("blockers"), list) else []):
        blockers.append("number_pad_ocr_not_bound")
    blockers.extend(
        [
            "fiducial_marker_map_not_bound",
            "image_to_table_homography_not_bound",
            "table_coordinate_to_arm_pose_solver_not_bound",
            "calibration_validation_motion_not_run",
        ]
    )

    objective = {
        "packet_type": "mim-arm-calibration-training-objective-v1",
        "generated_at": generated_at,
        "objective_id": "ARM-05-CALIBRATION-AND-COORDINATE-MAPPING",
        "status": "active",
        "goal": "Bind camera pixels, table reference points, simulation coordinates, and arm poses into one verified calibration layer.",
        "success_criteria": [
            "MIM recognizes at least three fixed reference points on the table.",
            "Each reference point has a stable label, image coordinate, and table coordinate.",
            "MIM publishes image-to-table transform evidence with confidence and timestamp.",
            "MIM validates calibration by moving the gripper near reference points without touching objects.",
            "MIM refuses pick/place if calibration is stale or unvalidated.",
        ],
        "training_sequence": [
            "Use fixed observer camera to detect three numbered pads or fiducials.",
            "Use arm-mounted camera to verify gripper view and approach alignment.",
            "Compute and publish a table-plane coordinate map.",
            "Run no-contact validation moves to each reference point.",
            "Feed validated map into grasp and collision planners.",
        ],
    }

    status = {
        "packet_type": "mim-arm-calibration-training-status-v1",
        "generated_at": generated_at,
        "objective_id": objective["objective_id"],
        "status": "blocked_pending_reference_map",
        "success": False,
        "current_evidence": {
            "camera_scene_status": camera_scene.get("status"),
            "camera_scene_success": camera_scene.get("success"),
            "object_counts": object_counts,
            "pad_candidate_count": len(pad_candidates),
            "sim_sync_status": sim_sync.get("status"),
            "area_exploration_status": area.get("status"),
            "manipulation_status": manipulation.get("status"),
        },
        "blockers": list(dict.fromkeys(blockers)),
        "action_policy": {
            "safe_to_use_for_pick_place": False,
            "safe_to_use_for_no_contact_validation": False,
            "reason": "No labeled reference map or validated image-to-table transform exists yet.",
        },
        "next_recovery_action": "Bind pad labels via OCR/fiducials/calibrated map, then compute image-to-table coordinates and run no-contact validation moves.",
        "evidence_artifacts": [
            "runtime/shared/MIM_ARM_CAMERA_SCENE_TRAINING_STATUS.latest.json",
            "runtime/shared/MIM_ARM_TABLE_SCENE.latest.json",
            "runtime/shared/MIM_ARM_SIM_SYNC_SPACE_STATUS.latest.json",
            "runtime/shared/MIM_ARM_CALIBRATION_TRAINING_OBJECTIVE.latest.json",
        ],
    }

    write_json(OBJECTIVE_PATH, objective)
    write_json(STATUS_PATH, status)
    print(json.dumps(status, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
