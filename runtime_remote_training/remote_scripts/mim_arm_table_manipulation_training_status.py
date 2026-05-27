#!/usr/bin/env python3
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_TABLE_MANIPULATION_TRAINING_STATUS.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_TABLE_MANIPULATION_TRAINING_OBJECTIVE.latest.json"
SCENE_PATH = SHARED / "MIM_ARM_TABLE_SCENE.latest.json"
PROPOSAL_PATH = SHARED / "MIM_ARM_TABLE_MANIPULATION_PROPOSAL.latest.json"
INTERACTION_OBJECTIVE_PATH = SHARED / "MIM_ARM_TABLE_OBJECT_INTERACTION_OBJECTIVE.latest.json"
PICKUP_TRAINING_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_PICKUP_TRAINING.latest.json"


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


def blocker_present(blockers: list[Any], reason_code: str) -> bool:
    for blocker in blockers:
        if blocker == reason_code:
            return True
        if isinstance(blocker, dict) and blocker.get("reason_code") == reason_code:
            return True
    return False


def main() -> int:
    generated_at = now_iso()
    scene = read_json(SCENE_PATH)
    proposal = read_json(PROPOSAL_PATH)
    interaction_objective = read_json(INTERACTION_OBJECTIVE_PATH)
    reference_map = read_json(SHARED / "MIM_ARM_TABLE_REFERENCE_MAP.latest.json")
    pickup_training = read_json(PICKUP_TRAINING_PATH)

    scene_blockers = scene.get("blockers") if isinstance(scene.get("blockers"), list) else []
    proposal_blockers = proposal.get("blockers") if isinstance(proposal.get("blockers"), list) else []
    blockers = list(dict.fromkeys([str(item) for item in scene_blockers + proposal_blockers]))

    object_counts = {
        "blue_block_candidates": len(scene.get("blue_block_candidates") or []),
        "white_or_gray_candidates": len(scene.get("white_or_gray_candidates") or []),
        "pad_candidates": len(scene.get("pad_candidates") or []),
        "objects_total": len(scene.get("objects") or []),
        "reference_map_pad_candidates": len(reference_map.get("unlabeled_pad_candidates") or []),
        "reference_map_blue_candidates": len(reference_map.get("blue_object_candidates") or []),
    }

    stages = [
        {
            "stage": 1,
            "name": "table_scene_capture_and_object_candidates",
            "status": "partial_complete" if scene.get("status") else "blocked",
            "evidence": {
                "scene_status": scene.get("status"),
                "source_frame": scene.get("source_frame", {}),
                "object_counts": object_counts,
            },
            "next_action": "Keep publishing fresh table/arm camera frames and object candidates before every manipulation attempt.",
        },
        {
            "stage": 2,
            "name": "numbered_pad_recognition",
            "status": "blocked" if blocker_present(blockers, "number_pad_ocr_not_bound") else "ready",
            "reason_code": "number_pad_ocr_not_bound",
            "next_action": "Bind OCR, fiducial markers, or a calibrated pad map for number pads 1, 2, and 3.",
            "current_reference_map": {
                "status": reference_map.get("status"),
                "candidate_count": len(reference_map.get("unlabeled_pad_candidates") or []),
                "numbered_labels_trusted": bool((reference_map.get("label_policy") or {}).get("numbered_pad_labels_trusted"))
                if isinstance(reference_map.get("label_policy"), dict)
                else False,
            },
        },
        {
            "stage": 3,
            "name": "arm_camera_to_table_coordinate_calibration",
            "status": "blocked"
            if blocker_present(blockers, "arm_camera_to_table_coordinate_calibration_not_bound")
            else "ready",
            "reason_code": "arm_camera_to_table_coordinate_calibration_not_bound",
            "next_action": "Calibrate image pixels to table coordinates using known pad or marker positions.",
        },
        {
            "stage": 4,
            "name": "grasp_approach_lift_release_plan",
            "status": "blocked" if blocker_present(blockers, "grasp_planner_not_bound") else "ready",
            "reason_code": "grasp_planner_not_bound",
            "next_action": "Train a guarded block grasp routine: approach, close grip, lift, verify object moved, place, release.",
        },
        {
            "stage": 5,
            "name": "collision_checked_pick_and_place_path",
            "status": "blocked"
            if blocker_present(blockers, "collision_checked_pick_and_place_path_not_bound")
            else "ready",
            "reason_code": "collision_checked_pick_and_place_path_not_bound",
            "next_action": "Plan and validate a collision-checked path in the simulation sync space before live movement.",
        },
        {
            "stage": 6,
            "name": "conflict_and_goal_reasoning",
            "status": "not_started",
            "next_action": "Teach MIM to resolve requests such as moving a white block to pad 3 when another object already occupies pad 3.",
        },
    ]

    live_ready = all(stage.get("status") in {"ready", "partial_complete"} for stage in stages[:5])
    policy = {
        "live_pick_and_place_allowed": live_ready,
        "current_allowed_actions": [
            "describe visible table candidates",
            "report why manipulation is blocked",
            "request calibration/training evidence",
            "move arm only under existing guarded motion policy",
        ],
        "current_blocked_actions": [] if live_ready else ["live autonomous block pick-and-place"],
        "operator_message": (
            "I can see candidate objects, but I am not allowed to pick/place blocks until pad recognition, "
            "table coordinates, grasp planning, and collision checking are proven."
        ),
    }

    objective = {
        "packet_type": "mim-arm-table-manipulation-training-objective-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-ARM-TABLE-OBJECT-MANIPULATION-TRAINING-V1",
        "status": "active",
        "goal": "MIM learns to safely identify, reason about, pick up, and place table blocks using arm camera evidence and simulation-sync safety.",
        "known_lab_setup": {
            "operator": "Dave",
            "expected_objects": ["blue block", "white block", "gray block", "number pad 1", "number pad 2", "number pad 3"],
            "arm_sync_assumption": "Dave reports live simulation sync is on and working.",
        },
        "success_criteria": [
            "MIM can answer which numbered pad a colored block is on using current camera evidence.",
            "MIM can propose a pick-and-place path with source object, destination pad, grip pose, and collision evidence.",
            "MIM refuses unsafe or uncalibrated live manipulation with explicit blocker evidence.",
            "MIM can execute a confirmed block move and publish before/after visual evidence.",
            "MIM can reason through conflicts, such as a destination pad already being occupied.",
        ],
        "stage_plan": stages,
        "must_not_do": [
            "Do not mark manipulation complete from speech acknowledgement alone.",
            "Do not claim a block was moved without before/after visual or arm-state evidence.",
            "Do not run live pick-and-place while any safety stage remains blocked.",
        ],
    }

    status = {
        "packet_type": "mim-arm-table-manipulation-training-status-v1",
        "generated_at": generated_at,
        "objective_id": objective["objective_id"],
        "status": "blocked_pending_training" if not live_ready else "ready_for_guarded_pick_and_place",
        "success": live_ready,
        "latest_request": {
            "source_transcript": proposal.get("source_transcript"),
            "requested_action": proposal.get("requested_action"),
            "proposal_status": proposal.get("status"),
            "proposal_generated_at": proposal.get("generated_at"),
        },
        "blue_block_pickup_training": {
            "status": pickup_training.get("status"),
            "generated_at": pickup_training.get("generated_at"),
            "target_selection": pickup_training.get("target_selection", {}),
            "blockers": pickup_training.get("blockers", []),
        },
        "scene_summary": {
            "scene_status": scene.get("status"),
            "scene_generated_at": scene.get("generated_at"),
            "object_counts": object_counts,
            "relationships": scene.get("relationships", {}),
        },
        "blockers": blockers,
        "stage_plan": stages,
        "action_policy": policy,
        "next_recovery_action": "Start with numbered pad recognition and image-to-table coordinate calibration; then train a guarded single-block lift/place routine.",
        "evidence_artifacts": [
            "runtime/shared/MIM_ARM_TABLE_SCENE.latest.json",
            "runtime/shared/MIM_ARM_TABLE_MANIPULATION_PROPOSAL.latest.json",
            "runtime/shared/MIM_ARM_TABLE_OBJECT_INTERACTION_OBJECTIVE.latest.json",
            "runtime/shared/MIM_ARM_TABLE_MANIPULATION_TRAINING_OBJECTIVE.latest.json",
            "runtime/shared/MIM_ARM_TABLE_REFERENCE_MAP.latest.json",
            "runtime/shared/MIM_ARM_BLUE_BLOCK_PICKUP_TRAINING.latest.json",
        ],
        "related_objective": interaction_objective.get("objective_id"),
    }

    write_json(OBJECTIVE_PATH, objective)
    write_json(STATUS_PATH, status)
    print(json.dumps(status, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
