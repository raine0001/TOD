#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
TRAINER_PATH = ROOT / "runtime_remote_training" / "local_scripts" / "mim_arm_marker_aware_grip_trainer.py"
STATUS_PATH = ROOT / "runtime" / "shared" / "MIM_ARM_BLUE_BLOCK_CONTACT_LIFT_LEARNING.latest.json"


def load_trainer() -> Any:
    spec = importlib.util.spec_from_file_location("marker_trainer", TRAINER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("marker trainer import failed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_command(command: list[str], timeout: int = 120) -> dict[str, Any]:
    completed = subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, timeout=timeout, check=False)
    return {
        "command": command,
        "returncode": completed.returncode,
        "ok": completed.returncode == 0,
        "stdout_tail": completed.stdout[-3000:],
        "stderr_tail": completed.stderr[-3000:],
    }


def load_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        return {"load_error": f"{type(exc).__name__}: {exc}", "path": str(path)}


def fixed_capture() -> dict[str, Any]:
    capture = run_command(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "scripts" / "Update-MIMArmTableObserverCamera.ps1"),
            "-EnvFile",
            ".env",
            "-UploadToMim",
        ],
        timeout=120,
    )
    detector = run_command(["python", str(ROOT / "runtime_remote_training" / "local_scripts" / "mim_arm_fixed_observer_marker_detector.py")], timeout=60)
    status = load_json(ROOT / "runtime" / "shared" / "MIM_ARM_FIXED_OBSERVER_MARKER_DETECTOR.latest.json")
    guidance = ((status.get("analysis") or {}).get("guidance") or {}) if isinstance(status.get("analysis"), dict) else {}
    tips = ((status.get("analysis") or {}).get("yellow_tip_markers") or []) if isinstance(status.get("analysis"), dict) else []
    tip_mid_y = None
    if len(tips) >= 2:
        tip_mid_y = round((float(tips[0]["center"]["y"]) + float(tips[1]["center"]["y"])) / 2.0, 2)
    return {
        "ok": bool(status.get("success")),
        "capture_command": capture,
        "detector_command": detector,
        "status": status,
        "frame_path": ((status.get("analysis") or {}).get("frame_path") if isinstance(status.get("analysis"), dict) else ""),
        "annotated_frame_path": ((status.get("analysis") or {}).get("annotated_frame_path") if isinstance(status.get("analysis"), dict) else ""),
        "guidance": guidance,
        "tip_mid_y": tip_mid_y,
        "contact_bottom_y": (((guidance.get("contact_window_blue") or {}).get("bottom_y")) if isinstance(guidance, dict) else None),
        "contact_dx": guidance.get("contact_to_tip_dx_px") if isinstance(guidance, dict) else None,
        "contact_dy": guidance.get("contact_to_tip_dy_px") if isinstance(guidance, dict) else None,
    }


def save(trainer: Any, payload: dict[str, Any]) -> None:
    payload["generated_at"] = trainer.now_iso()
    payload["final_pose"] = trainer.pose()
    trainer.write_json(STATUS_PATH, payload)


def move_pose(trainer: Any, target: list[int], source: str) -> list[dict[str, Any]]:
    moves: list[dict[str, Any]] = []
    for servo, angle in enumerate(target[:6]):
        result = trainer.slow_move(servo, int(angle), source, step_degrees=1, settle_seconds=0.28)
        moves.append({"servo": servo, "target": int(angle), "result": result})
    return moves


def measure_lift(closed: dict[str, Any], lifted: dict[str, Any]) -> dict[str, Any]:
    closed_bottom = closed.get("contact_bottom_y")
    lifted_bottom = lifted.get("contact_bottom_y")
    closed_tip = closed.get("tip_mid_y")
    lifted_tip = lifted.get("tip_mid_y")
    bottom_delta = None
    tip_delta = None
    if isinstance(closed_bottom, (int, float)) and isinstance(lifted_bottom, (int, float)):
        bottom_delta = round(float(lifted_bottom) - float(closed_bottom), 2)
    if isinstance(closed_tip, (int, float)) and isinstance(lifted_tip, (int, float)):
        tip_delta = round(float(lifted_tip) - float(closed_tip), 2)
    # In this fixed camera, upward motion usually reduces y. Success requires
    # the blue contact mass to move upward with the gripper, not merely the
    # wrist camera continuing to see blue.
    return {
        "contact_bottom_delta_y": bottom_delta,
        "tip_mid_delta_y": tip_delta,
        "lift_evidence": bool(bottom_delta is not None and bottom_delta <= -35 and tip_delta is not None and tip_delta <= -20),
    }


def main() -> int:
    trainer = load_trainer()
    payload: dict[str, Any] = {
        "packet_type": "mim-arm-blue-block-contact-lift-learning-v1",
        "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-PERSIST-UNTIL-SUCCESS",
        "status": "running",
        "success": False,
        "start_pose": trainer.pose(),
        "lessons": [
            "Previous attempts proved target acquisition and close-around-block, but not pickup.",
            "Closing harder alone failed; this run varies contact offset and lift vector.",
            "The IR distance sensor is not used as proof because it still reports zero samples.",
        ],
        "attempts": [],
    }
    save(trainer, payload)

    acquisition_open = 79
    legacy_open = 49
    base_pose = [66, 100, 24, 68, 84, acquisition_open]
    approach_candidates = [
        {"name": "learned_best_pose_wide_open", "pose": [66, 100, 24, 68, 84, acquisition_open], "close": 0},
        {"name": "tip_right_wrist80_wide_open", "pose": [66, 100, 24, 68, 80, acquisition_open], "close": 0},
        {"name": "base_left_tip_right_wide_open", "pose": [62, 100, 24, 68, 80, acquisition_open], "close": 0},
        {"name": "slightly_lower_contact_wide_open", "pose": [62, 104, 22, 68, 80, acquisition_open], "close": 0},
        {"name": "alternate_depth_contact_wide_open", "pose": [64, 104, 20, 68, 80, acquisition_open], "close": 0},
    ]
    lift_offsets = [
        {"name": "shoulder_back_4", "servo_targets": {1: 96}},
        {"name": "elbow_up_6", "servo_targets": {2: 18}},
        {"name": "combined_back_up", "servo_targets": {1: 96, 2: 18}},
    ]

    trainer.slow_move(5, acquisition_open, "mim_contact_lift_open_before_start_wide", step_degrees=1, settle_seconds=0.25)
    move_pose(trainer, base_pose, "mim_contact_lift_return_to_base_pose")
    save(trainer, payload)

    for candidate in approach_candidates:
        attempt: dict[str, Any] = {"candidate": candidate, "moves": [], "captures": {}, "lift_tests": []}
        payload["attempts"].append(attempt)
        save(trainer, payload)

        trainer.slow_move(5, acquisition_open, f"mim_contact_lift_{candidate['name']}_wide_open", step_degrees=1, settle_seconds=0.25)
        attempt["moves"].extend(move_pose(trainer, candidate["pose"], f"mim_contact_lift_{candidate['name']}_approach"))
        time.sleep(0.6)
        attempt["captures"]["wrist_before_close"] = trainer.capture_wrist(f"{candidate['name']}_before_close")
        attempt["captures"]["fixed_before_close"] = fixed_capture()
        save(trainer, payload)

        trainer.slow_move(5, int(candidate["close"]), f"mim_contact_lift_{candidate['name']}_close", step_degrees=1, settle_seconds=0.22)
        time.sleep(0.6)
        closed_fixed = fixed_capture()
        attempt["captures"]["wrist_after_close"] = trainer.capture_wrist(f"{candidate['name']}_after_close")
        attempt["captures"]["fixed_after_close"] = closed_fixed
        save(trainer, payload)

        for lift in lift_offsets:
            lift_pose = trainer.pose()
            lift_record: dict[str, Any] = {"lift": lift, "start_pose": lift_pose, "moves": []}
            for servo, target in lift["servo_targets"].items():
                lift_record["moves"].append(
                    {"servo": servo, "target": target, "result": trainer.slow_move(servo, target, f"mim_contact_lift_{candidate['name']}_{lift['name']}", step_degrees=1, settle_seconds=0.3)}
                )
            time.sleep(0.7)
            lifted_fixed = fixed_capture()
            lift_record["fixed_after_lift"] = lifted_fixed
            lift_record["wrist_after_lift"] = trainer.capture_wrist(f"{candidate['name']}_{lift['name']}_after_lift")
            lift_record["evaluation"] = measure_lift(closed_fixed, lifted_fixed)
            attempt["lift_tests"].append(lift_record)
            save(trainer, payload)
            if lift_record["evaluation"].get("lift_evidence"):
                payload["status"] = "completed_with_pickup_evidence"
                payload["success"] = True
                payload["success_attempt"] = attempt
                save(trainer, payload)
                print(json.dumps(payload, indent=2)[:8000])
                return 0
            # Return to the candidate contact pose while still closed before the
            # next lift-vector test, then re-close to account for small slip.
            move_pose(trainer, [*candidate["pose"][:5], int(candidate["close"])], f"mim_contact_lift_{candidate['name']}_reset_after_{lift['name']}")
            closed_fixed = fixed_capture()

        trainer.slow_move(5, acquisition_open, f"mim_contact_lift_{candidate['name']}_wide_release_after_failed_lifts", step_degrees=1, settle_seconds=0.25)
        move_pose(trainer, base_pose, f"mim_contact_lift_{candidate['name']}_return_open_base")
        save(trainer, payload)

    payload["status"] = "blocked_with_evidence"
    payload["success"] = False
    payload["blocker"] = {
        "reason_code": "gripper_contact_or_lift_vector_not_yet_learned",
        "evidence": "Approach/close/lift attempts were captured by wrist and fixed cameras, but no fixed-observer upward blue-block motion met threshold.",
        "next_learning_objective": "Use camera evidence to redesign contact strategy: lower/frontal side contact, verified vertical lift vector, or gripper tip sleeve/friction improvement.",
    }
    payload["learned_gripper_opening"] = {
        "legacy_open_angle": legacy_open,
        "new_block_acquisition_open_angle": acquisition_open,
        "lesson_source": "Dave observed the claw needs roughly 30 more degrees open to get around the block sides.",
    }
    trainer.slow_move(5, acquisition_open, "mim_contact_lift_complete_wide_open_safe", step_degrees=1, settle_seconds=0.25)
    save(trainer, payload)
    print(json.dumps(payload, indent=2)[:8000])
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
