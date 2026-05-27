#!/usr/bin/env python3
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
OBJECTIVE_PATH = SHARED / "MIM_MECHANICAL_STRUCTURE_LEARNING_OBJECTIVE.latest.json"
STATUS_PATH = SHARED / "MIM_MECHANICAL_STRUCTURE_LEARNING_STATUS.latest.json"
DIRECT_ORDER_PATH = SHARED / "MIM_MECHANICAL_STRUCTURE_LEARNING_DIRECT_ORDER.latest.json"
NEXT_OBJECTIVE_PATH = SHARED / "MIM_TOD_NEXT_OBJECTIVE.latest.json"


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
    return {
        "artifact": f"runtime/shared/{name}",
        "exists": bool(data),
        "status": data.get("status") or data.get("dispatch_status"),
        "success": data.get("success"),
        "generated_at": data.get("generated_at"),
        "objective_id": data.get("objective_id"),
        "blockers": data.get("blockers") if isinstance(data.get("blockers"), list) else [],
        "next_recovery_action": data.get("next_recovery_action"),
    }


def main() -> int:
    generated_at = now_iso()
    evidence = {
        "arm_capability_deck": artifact_summary("MIM_ARM_CAPABILITY_TRAINING_DECK.latest.json"),
        "arm_access_binding": artifact_summary("MIM_ARM_ACCESS_BINDING.latest.json"),
        "arm_sim_sync_space": artifact_summary("MIM_ARM_SIM_SYNC_SPACE_STATUS.latest.json"),
        "arm_joint_motion_training": artifact_summary("MIM_ARM_JOINT_MOTION_TRAINING_STATUS.latest.json"),
        "arm_camera_scene_training": artifact_summary("MIM_ARM_CAMERA_SCENE_TRAINING_STATUS.latest.json"),
        "arm_table_reference_map": artifact_summary("MIM_ARM_TABLE_REFERENCE_MAP.latest.json"),
        "arm_blue_block_pickup_training": artifact_summary("MIM_ARM_BLUE_BLOCK_PICKUP_TRAINING.latest.json"),
        "station_file_index": artifact_summary("MIM_STATION_FILE_INDEX.latest.json"),
        "station_file_mirror": artifact_summary("MIM_STATION_FILE_MIRROR.latest.json"),
    }

    learning_loop = [
        {
            "stage_id": "MSL-01",
            "name": "discover_and_inventory",
            "goal": "Identify the mechanical unit, joints, actuators, sensors, controllers, cameras, simulation state, files, and known manuals.",
            "required_evidence": [
                "current live hardware state",
                "available local/project files",
                "simulation/sync state",
                "camera and sensor inventory",
                "operator-provided purpose and constraints",
            ],
        },
        {
            "stage_id": "MSL-02",
            "name": "research_and_model",
            "goal": "Map what the system is, how it should work, and what sources describe it.",
            "required_evidence": [
                "file index and mirrored relevant design/config files",
                "manuals or web/manual research when local sources are insufficient",
                "kinematic or functional model",
                "named capabilities and forbidden actions",
            ],
        },
        {
            "stage_id": "MSL-03",
            "name": "safe_limit_exploration",
            "goal": "Learn ranges, rates, dead zones, response delay, no-motion failures, and practical limits using slow bounded probes.",
            "required_evidence": [
                "preflight state",
                "slow motion profile",
                "before/after telemetry",
                "camera verification",
                "explicit stop condition",
            ],
        },
        {
            "stage_id": "MSL-04",
            "name": "sensor_fusion_and_workspace_mapping",
            "goal": "Use cameras, distance sensors, simulation, and observed outcomes to build a useful workspace map.",
            "required_evidence": [
                "fixed observer frames",
                "on-unit camera frames",
                "known object candidates",
                "unknown object candidates",
                "human/obstacle presence checks",
            ],
        },
        {
            "stage_id": "MSL-05",
            "name": "capability_training",
            "goal": "Turn primitive controls into intent-level capabilities such as inspect, point, approach, grip, lift, place, scan, and recover.",
            "required_evidence": [
                "capability name",
                "input intent",
                "execution plan",
                "verification method",
                "success/failure artifact",
            ],
        },
        {
            "stage_id": "MSL-06",
            "name": "purpose_oriented_interaction",
            "goal": "Apply the mechanical unit to its intended purpose, reason about requests, and ask for clarification only when needed.",
            "required_evidence": [
                "operator intent",
                "current environment state",
                "task feasibility",
                "safety and collision checks",
                "completion proof",
            ],
        },
        {
            "stage_id": "MSL-07",
            "name": "learning_from_barriers",
            "goal": "Convert every off-course moment, stall, unsafe condition, or failed action into a new objective with recovery evidence.",
            "required_evidence": [
                "what was attempted",
                "what was expected",
                "what actually happened",
                "root blocker",
                "next learning objective",
            ],
        },
    ]

    arm_instance = {
        "mechanical_unit_id": "MIM_ARM",
        "mechanical_unit_type": "robotic_arm_with_gripper_and_camera",
        "operator": "Dave",
        "purpose": [
            "assist arm development",
            "explore table and nearby room area",
            "identify blocks/pads/objects",
            "perform safe manipulation tasks such as picking up the blue block",
        ],
        "known_strengths": [
            "live joint control works",
            "joint motion telemetry is available",
            "arm camera is mounted on top of the wrist and should be aimed with wrist/hand movement first",
            "IR proximity sensor is mounted on top of the hand slightly behind the grip tips with a 142 mm offset/reference distance",
            "fixed Pi observer sees the arm and table",
            "operator PC observer sees the wider arm/table space",
            "simulation sync is reported by Dave as accurate enough to be a primary safety map",
        ],
        "current_blockers": [
            "coordinate calibration from camera/simulation to real table is not yet trusted",
            "wrist-mounted camera aiming model to the blue block is not yet fully validated",
            "top-of-hand IR proximity sensor is connected but still needs nonzero-distance calibration before contact/approach use",
            "gripper approach geometry to the blue block is not yet validated",
            "collision-checked approach/retreat path is not yet bound",
            "live grasp-close-lift-verify sequence is not yet proven",
        ],
        "active_applied_test": "pick_up_blue_block",
    }

    objective = {
        "packet_type": "mim-mechanical-structure-learning-objective-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-MECHANICAL-STRUCTURE-LEARNING-V1",
        "status": "active",
        "intent": "MIM/TOD must learn mechanical structures they are granted access to by discovering, modeling, probing, verifying, and improving through evidence.",
        "goal": "Create a repeatable learning loop for mechanical systems, starting with the MIM arm.",
        "primary_instance": arm_instance,
        "learning_loop": learning_loop,
        "success_criteria": [
            "MIM can describe the mechanical unit, its resources, its workspace, and its current operating state.",
            "MIM can use local files, mirrored design/config files, manuals, web research when needed, cameras, sensors, and simulation state to build a working model.",
            "MIM can explore limitations with slow bounded probes and never claim success without evidence.",
            "MIM can turn primitive controls into intent-level capabilities.",
            "MIM can identify when a request is feasible, unsafe, blocked, or requires new training.",
            "MIM can complete the applied MIM_ARM blue-block pickup only after perception, calibration, collision checks, approach, grip, lift, and verification are proven.",
        ],
        "movement_policy": {
            "default_for_learning": "slow_bounded_visible_probe",
            "max_unverified_step_degrees": 2,
            "minimum_settle_seconds": 0.35,
            "camera_verification_required": True,
            "wrist_mounted_camera_policy": "use wrist and hand movements as the primary camera-view controls before moving larger arm joints",
            "top_of_hand_ir_sensor_policy": "use the IR sensor as a proximity guard only after validating nonzero readings and applying its 142 mm offset behind the grip tips",
            "human_or_obstacle_near_workspace_policy": "pause_live_motion_and_publish_blocker",
        },
        "guardrails": [
            "Do not treat acknowledgement or speech as physical success.",
            "Do not skip calibration because a single motion happened to work.",
            "Do not close a gripper on an object until the approach path, target alignment, collision envelope, and retreat are verified.",
            "If MIM/TOD are blocked, publish explicit blocker evidence and the next learning objective.",
            "Use the live sync simulation as a safety and planning resource whenever available.",
        ],
    }

    status = {
        "packet_type": "mim-mechanical-structure-learning-status-v1",
        "generated_at": generated_at,
        "objective_id": objective["objective_id"],
        "status": "active_applied_to_mim_arm",
        "success": False,
        "summary": "Mechanical structure learning objective is now bound to the MIM arm. The blue-block pickup remains an applied capability test blocked on calibration, visual approach, collision checking, and grasp verification.",
        "primary_instance": arm_instance,
        "evidence": evidence,
        "active_learning_loop": learning_loop,
        "recommended_next_objectives": [
            "Refresh and trust the MIM_ARM simulation-sync state as the planning map.",
            "Bind slow wrist/hand camera-view scan learning for the wrist-mounted arm camera.",
            "Calibrate the top-of-hand IR proximity sensor using its 142 mm grip-tip offset.",
            "Bind slow-probe visual servo learning between Pi observer, arm camera, and joint motions.",
            "Calibrate table coordinates and reachable approach poses for the blue block.",
            "Train guarded grip-close/lift/verify only after alignment and collision checks pass.",
        ],
        "published_objective_artifact": "runtime/shared/MIM_MECHANICAL_STRUCTURE_LEARNING_OBJECTIVE.latest.json",
    }

    direct_order = {
        "packet_type": "mim-direct-execution-order-v1",
        "generated_at": generated_at,
        "request_id": "mim-direct-mechanical-structure-learning-20260524",
        "objective_id": objective["objective_id"],
        "task_id": "mim-mechanical-structure-learning-mim-arm-task-001",
        "target": "MIM",
        "status": "published",
        "action": "execute_objective_until_success",
        "title": "Mechanical structure learning for the MIM arm",
        "summary": (
            "MIM owns the mechanical learning loop for the arm. TOD/Codex monitor, intervene only on off-course "
            "evidence, and convert blockers into new learning objectives."
        ),
        "objective_ref": "runtime/shared/MIM_MECHANICAL_STRUCTURE_LEARNING_OBJECTIVE.latest.json",
        "status_ref": "runtime/shared/MIM_MECHANICAL_STRUCTURE_LEARNING_STATUS.latest.json",
        "required_first_outputs": [
            "runtime/shared/MIM_ARM_SIM_SYNC_SPACE_STATUS.latest.json",
            "runtime/shared/MIM_ARM_CAMERA_SCENE_TRAINING_STATUS.latest.json",
            "runtime/shared/MIM_ARM_TABLE_REFERENCE_MAP.latest.json",
            "runtime/shared/MIM_ARM_BLUE_BLOCK_PICKUP_TRAINING.latest.json",
            "runtime/shared/MIM_MECHANICAL_STRUCTURE_LEARNING_STATUS.latest.json",
        ],
        "no_stall_rule": (
            "After each physical or simulated probe, publish completed, running, or blocked_with_evidence. "
            "Never claim capability from acknowledgement alone."
        ),
        "movement_policy": objective["movement_policy"],
    }

    next_objective = {
        "packet_type": "mim-next-objective-v1",
        "generated_at": generated_at,
        "objective_id": objective["objective_id"],
        "task_id": direct_order["task_id"],
        "status": "published",
        "goal": objective["goal"],
        "owner": "MIM",
        "next_action": "Use wrist and hand movements to aim the wrist-mounted arm camera, bind slow visual-servo learning with simulation/camera evidence, then continue the blue-block pickup capability test.",
        "evidence_files": [
            "runtime/shared/MIM_MECHANICAL_STRUCTURE_LEARNING_OBJECTIVE.latest.json",
            "runtime/shared/MIM_MECHANICAL_STRUCTURE_LEARNING_STATUS.latest.json",
            "runtime/shared/MIM_MECHANICAL_STRUCTURE_LEARNING_DIRECT_ORDER.latest.json",
            "runtime/shared/MIM_ARM_CAPABILITY_TRAINING_DECK.latest.json",
        ],
    }

    write_json(OBJECTIVE_PATH, objective)
    write_json(STATUS_PATH, status)
    write_json(DIRECT_ORDER_PATH, direct_order)
    write_json(NEXT_OBJECTIVE_PATH, next_objective)
    print(json.dumps(status, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
