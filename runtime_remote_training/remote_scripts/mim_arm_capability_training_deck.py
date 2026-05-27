#!/usr/bin/env python3
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_CAPABILITY_TRAINING_DECK.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_CAPABILITY_TRAINING_OBJECTIVE.latest.json"


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


def artifact_summary(name: str) -> dict[str, Any]:
    data = read_json(name)
    status = data.get("status")
    success = data.get("success")
    if success is None and data.get("dispatch_status") == "completed":
        success = True
    if status is None and data.get("dispatch_status"):
        status = data.get("dispatch_status")
    if success is None and data.get("completion_status") == "completed":
        success = True
    if success is None and status == "idle" and name == "MIM_READY_TASK_DISPATCHER_STATUS.latest.json":
        success = True
    return {
        "artifact": f"runtime/shared/{name}",
        "exists": bool(data),
        "status": status,
        "success": success,
        "generated_at": data.get("generated_at"),
        "objective_id": data.get("objective_id"),
        "blockers": data.get("blockers") if isinstance(data.get("blockers"), list) else [],
        "next_recovery_action": data.get("next_recovery_action"),
    }


def stage_status(*artifact_names: str) -> str:
    summaries = [artifact_summary(name) for name in artifact_names]
    if not any(item["exists"] for item in summaries):
        return "not_started"
    if any(item["blockers"] for item in summaries):
        return "blocked_or_training"
    if any(item["success"] is True for item in summaries):
        return "active_or_complete"
    return "needs_evidence"


def main() -> int:
    generated_at = now_iso()
    evidence = {
        "mechanical_structure_learning": artifact_summary("MIM_MECHANICAL_STRUCTURE_LEARNING_STATUS.latest.json"),
        "access_binding": artifact_summary("MIM_ARM_ACCESS_BINDING.latest.json"),
        "development_support": artifact_summary("MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json"),
        "joint_motion_training": artifact_summary("MIM_ARM_JOINT_MOTION_TRAINING_STATUS.latest.json"),
        "motion_execution": artifact_summary("MIM_ARM_MOTION_EXECUTION.latest.json"),
        "sim_sync_space": artifact_summary("MIM_ARM_SIM_SYNC_SPACE_STATUS.latest.json"),
        "area_exploration": artifact_summary("MIM_ARM_AREA_EXPLORATION.latest.json"),
        "arm_camera_capture": artifact_summary("MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json"),
        "camera_scene_training": artifact_summary("MIM_ARM_CAMERA_SCENE_TRAINING_STATUS.latest.json"),
        "ir_sensor_calibration": artifact_summary("MIM_ARM_IR_SENSOR_CALIBRATION_STATUS.latest.json"),
        "calibration_training": artifact_summary("MIM_ARM_CALIBRATION_TRAINING_STATUS.latest.json"),
        "table_reference_map": artifact_summary("MIM_ARM_TABLE_REFERENCE_MAP.latest.json"),
        "table_scene": artifact_summary("MIM_ARM_TABLE_SCENE.latest.json"),
        "blue_block_pickup_training": artifact_summary("MIM_ARM_BLUE_BLOCK_PICKUP_TRAINING.latest.json"),
        "table_manipulation_training": artifact_summary("MIM_ARM_TABLE_MANIPULATION_TRAINING_STATUS.latest.json"),
        "dispatch_telemetry": artifact_summary("MIM_ARM_DISPATCH_TELEMETRY.latest.json"),
        "ready_task_dispatcher": artifact_summary("MIM_READY_TASK_DISPATCHER_STATUS.latest.json"),
        "station_file_index": artifact_summary("MIM_STATION_FILE_INDEX.latest.json"),
        "station_file_mirror": artifact_summary("MIM_STATION_FILE_MIRROR.latest.json"),
    }

    training_tracks = [
        {
            "track_id": "ARM-01",
            "name": "authority_and_safety_envelope",
            "status": stage_status("MIM_ARM_ACCESS_BINDING.latest.json", "MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json"),
            "goal": "MIM knows when it is allowed to control the arm, what requires operator confirmation, and when to refuse.",
            "next_objectives": [
                "Publish a single arm authority ledger covering voice, UI, dispatcher, and simulation sync sources.",
                "Require every live motion to cite authority, current pose, limits, and stop condition.",
                "Add emergency stop and do-not-move state awareness to every arm route.",
            ],
        },
        {
            "track_id": "ARM-02",
            "name": "joint_motion_skill_library",
            "status": stage_status("MIM_ARM_JOINT_MOTION_TRAINING_STATUS.latest.json", "MIM_ARM_MOTION_EXECUTION.latest.json"),
            "goal": "MIM can reliably move base, shoulder, elbow, wrist, and grip by named intent and by degrees within configured limits.",
            "next_objectives": [
                "Train individual joint movement verification with before/after pose evidence.",
                "Train compound poses such as home, inspect table, inspect gripper, and present object.",
                "Detect no-motion, wrong-joint, and partial-motion failures from telemetry and camera evidence.",
            ],
        },
        {
            "track_id": "ARM-03",
            "name": "simulation_sync_spatial_awareness",
            "status": stage_status("MIM_ARM_SIM_SYNC_SPACE_STATUS.latest.json", "MIM_ARM_AREA_EXPLORATION.latest.json"),
            "goal": "MIM uses the simulation sync space as the primary map for safe movement, collision warnings, and reachable workspace.",
            "next_objectives": [
                "Bind current simulation object list and arm pose to MIM's voice answers.",
                "Add collision preflight: requested pose versus known sim objects and table bounds.",
                "Publish warnings when live arm and simulation pose diverge.",
            ],
        },
        {
            "track_id": "ARM-04",
            "name": "camera_and_scene_perception",
            "status": stage_status(
                "MIM_ARM_CAMERA_SCENE_TRAINING_STATUS.latest.json",
                "MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json",
                "MIM_ARM_TABLE_SCENE.latest.json",
                "MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json",
                "MIM_ARM_TABLE_OBSERVER_STATUS.latest.json",
            ),
            "goal": "MIM can use the wrist-mounted arm camera and fixed observer views to identify the table, blocks, pads, gripper, humans, and obstacles.",
            "next_objectives": [
                "Model the arm camera as mounted on top of the wrist; use wrist and hand movements as the first camera-view controls.",
                "Model the top-of-hand IR sensor as 142 mm behind the grip tips and validate it before using proximity readings.",
                "Capture fresh arm-camera frames on demand and mirror them to MIM shared runtime.",
                "Fuse fixed table observer with arm-mounted camera so object detections have confidence and viewpoint.",
                "Train object labels: blue block, white block, gray block, number pad 1, number pad 2, number pad 3.",
            ],
        },
        {
            "track_id": "ARM-05",
            "name": "calibration_and_coordinate_mapping",
            "status": stage_status("MIM_ARM_CALIBRATION_TRAINING_STATUS.latest.json", "MIM_ARM_TABLE_REFERENCE_MAP.latest.json"),
            "goal": "MIM converts camera pixels and simulation coordinates into real table coordinates that the arm can reach.",
            "next_objectives": [
                "Calibrate the top-of-hand IR proximity sensor against known distances and apply the 142 mm grip-tip offset.",
                "Calibrate number pads or fiducial markers as fixed table reference points.",
                "Publish image-to-table homography with confidence and last validation time.",
                "Validate coordinate mapping by moving the gripper near, not touching, each reference point.",
            ],
        },
        {
            "track_id": "ARM-06",
            "name": "object_manipulation",
            "status": stage_status("MIM_ARM_TABLE_MANIPULATION_TRAINING_STATUS.latest.json"),
            "goal": "MIM can pick, lift, place, and verify simple blocks with safe guarded motions.",
            "next_objectives": [
                "Train a single-block grasp routine with approach, close, lift, verify, place, and release.",
                "Add destination occupancy reasoning before moving a block to a numbered pad.",
                "Require before/after camera evidence before claiming a manipulation succeeded.",
            ],
        },
        {
            "track_id": "ARM-07",
            "name": "interactive_development_assistant",
            "status": stage_status(
                "MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json",
                "MIM_STATION_FILE_INDEX.latest.json",
                "MIM_STATION_FILE_MIRROR.latest.json",
            ),
            "goal": "MIM helps Dave develop the arm by reading design files, explaining configuration, and turning problems into TOD objectives.",
            "next_objectives": [
                "Index MIM Robotics design_parts and servo configuration references for voice recall.",
                "Teach MIM to answer arm build questions from mirrored station files with citations.",
                "Let MIM create targeted TOD tasks when it cannot resolve an arm failure itself.",
            ],
        },
        {
            "track_id": "ARM-08",
            "name": "autonomous_exploration_and_learning",
            "status": stage_status(
                "MIM_ARM_AREA_EXPLORATION.latest.json",
                "MIM_ARM_CAMERA_SCENE_TRAINING_STATUS.latest.json",
                "MIM_ARM_TABLE_MANIPULATION_TRAINING_STATUS.latest.json",
            ),
            "goal": "MIM can explore the table and room with the arm camera, ask questions about unknowns, and improve its future responses.",
            "next_objectives": [
                "Define explore table versus explore area as separate scan profiles and artifacts.",
                "Record unknown object candidates and ask Dave for labels only when needed.",
                "Convert failed interactions into new learning objectives with evidence and recovery steps.",
            ],
        },
        {
            "track_id": "ARM-09",
            "name": "task_dispatch_and_background_execution",
            "status": stage_status("MIM_READY_TASK_DISPATCHER_STATUS.latest.json", "MIM_ARM_DISPATCH_TELEMETRY.latest.json"),
            "goal": "MIM can queue, claim, execute, and report arm tasks without losing state or pretending success.",
            "next_objectives": [
                "Bind arm training tracks into MIM-owned queued tasks with explicit dispatcher status.",
                "Publish completed, running, or blocked_with_evidence for every arm task.",
                "Add periodic background health checks for sync, camera, serial, and voice routes.",
            ],
        },
    ]

    immediate_sequence = [
        "ARM-04 camera_and_scene_perception",
        "ARM-05 calibration_and_coordinate_mapping",
        "ARM-06 object_manipulation",
        "ARM-03 simulation_sync_spatial_awareness",
        "ARM-07 interactive_development_assistant",
        "ARM-08 autonomous_exploration_and_learning",
        "ARM-09 task_dispatch_and_background_execution",
    ]

    objective = {
        "packet_type": "mim-arm-capability-training-objective-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-ARM-CAPABILITY-TRAINING-DECK-V1",
        "status": "active",
        "goal": "Develop MIM into a capable arm development, perception, safety, and manipulation assistant.",
        "parent_objective": "MIM-MECHANICAL-STRUCTURE-LEARNING-V1",
        "operator": "Dave",
        "success_definition": [
            "MIM can explain the arm state, camera state, sync state, authority state, and current training state.",
            "MIM can move every joint safely when allowed and can detect/report motion failures.",
            "MIM can explore the table and room, recognize known objects, and ask for labels on unknown objects.",
            "MIM can map visible objects to reachable coordinates and execute verified pick/place routines.",
            "MIM can turn every blocked arm interaction into a new learning objective with evidence.",
        ],
        "training_tracks": training_tracks,
        "recommended_sequence": immediate_sequence,
        "guardrails": [
            "Do not claim physical success without telemetry or camera evidence.",
            "Do not pick/place objects until pad recognition, coordinate calibration, grasp planning, and collision checking are bound.",
            "Prefer simulation-sync safety checks before live motion.",
            "Ask Dave for confirmation before any movement with collision, reachability, or unknown-object risk.",
        ],
    }

    status = {
        "packet_type": "mim-arm-capability-training-deck-v1",
        "generated_at": generated_at,
        "objective_id": objective["objective_id"],
        "status": "active",
        "success": False,
        "summary": "MIM has guarded motion, sync-space exploration, and table-scene candidate perception; manipulation remains blocked pending calibration and grasp training.",
        "evidence": evidence,
        "parent_objective": {
            "objective_id": "MIM-MECHANICAL-STRUCTURE-LEARNING-V1",
            "artifact": "runtime/shared/MIM_MECHANICAL_STRUCTURE_LEARNING_OBJECTIVE.latest.json",
            "status_artifact": "runtime/shared/MIM_MECHANICAL_STRUCTURE_LEARNING_STATUS.latest.json",
        },
        "training_tracks": training_tracks,
        "recommended_next_objective": immediate_sequence[0],
        "recommended_sequence": immediate_sequence,
        "published_objective_artifact": "runtime/shared/MIM_ARM_CAPABILITY_TRAINING_OBJECTIVE.latest.json",
    }

    write_json(OBJECTIVE_PATH, objective)
    write_json(STATUS_PATH, status)
    print(json.dumps(status, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
