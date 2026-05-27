#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
TRAINER_PATH = ROOT / "runtime_remote_training" / "local_scripts" / "mim_arm_marker_aware_grip_trainer.py"
STATUS_PATH = ROOT / "runtime" / "shared" / "MIM_ARM_FIXED_OBSERVER_VISUAL_SERVO_PICKUP.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_trainer() -> Any:
    spec = importlib.util.spec_from_file_location("marker_trainer", TRAINER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("marker trainer import failed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(payload: dict[str, Any]) -> None:
    STATUS_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload["generated_at"] = now_iso()
    tmp = STATUS_PATH.with_suffix(STATUS_PATH.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(STATUS_PATH)


def run_command(command: list[str], timeout: int = 120) -> dict[str, Any]:
    completed = subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, timeout=timeout, check=False)
    return {
        "command": command,
        "returncode": completed.returncode,
        "ok": completed.returncode == 0,
        "stdout_tail": completed.stdout[-1200:],
        "stderr_tail": completed.stderr[-1200:],
    }


def load_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        return {"load_error": f"{type(exc).__name__}: {exc}", "path": str(path)}


def fixed_metric(label: str) -> dict[str, Any]:
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
    analysis = status.get("analysis") if isinstance(status.get("analysis"), dict) else {}
    guidance = analysis.get("guidance") if isinstance(analysis.get("guidance"), dict) else {}
    tip = guidance.get("tip_mid") if isinstance(guidance.get("tip_mid"), dict) else {}
    block = guidance.get("block_center") if isinstance(guidance.get("block_center"), dict) else {}
    dx = guidance.get("block_to_tip_dx_px")
    dy = guidance.get("block_to_tip_dy_px")
    distance = None
    if isinstance(dx, (int, float)) and isinstance(dy, (int, float)):
        distance = round((float(dx) ** 2 + float(dy) ** 2) ** 0.5, 2)
    return {
        "label": label,
        "ok": bool(distance is not None),
        "capture": capture,
        "detector": detector,
        "frame_path": analysis.get("frame_path"),
        "tip_mid": tip,
        "block_center": block,
        "dx": dx,
        "dy": dy,
        "distance": distance,
        "status_success": status.get("success"),
    }


def score(metric: dict[str, Any]) -> float:
    distance = metric.get("distance")
    if not isinstance(distance, (int, float)):
        return 1_000_000.0
    dx = abs(float(metric.get("dx") or 0))
    dy = abs(float(metric.get("dy") or 0))
    return float(distance) + max(0.0, dx - 75.0) * 1.5 + max(0.0, dy - 90.0) * 0.6


def main() -> int:
    trainer = load_trainer()
    payload: dict[str, Any] = {
        "packet_type": "mim-arm-fixed-observer-visual-servo-pickup-v1",
        "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-PERSIST-UNTIL-SUCCESS",
        "status": "running",
        "success": False,
        "start_pose": trainer.pose(),
        "iterations": [],
        "lessons": [
            "Use the fixed observer as the authoritative table-space feedback loop.",
            "Optimize yellow tip midpoint toward the compact blue cube before closing.",
            "Reject wrist-camera-only success because it previously created false positives.",
        ],
    }
    write_json(payload)

    trainer.slow_move(5, 99, "mim_fixed_visual_servo_open_for_probe", step_degrees=1, settle_seconds=0.16)
    current = fixed_metric("baseline")
    payload["baseline"] = current
    write_json(payload)

    candidate_servos = [0, 1, 2, 3, 4]
    deltas = [-10, -6, 6, 10]
    for iteration in range(6):
        start_pose = trainer.pose()
        current = fixed_metric(f"iteration_{iteration}_current")
        best_metric = current
        best_move: dict[str, Any] | None = None
        tests: list[dict[str, Any]] = []
        for servo in candidate_servos:
            for delta in deltas:
                pose = trainer.pose()
                if len(pose) < 6:
                    continue
                target = max(0, min(180, int(pose[servo]) + delta))
                if target == int(pose[servo]):
                    continue
                move = trainer.slow_move(servo, target, f"mim_fixed_visual_servo_probe_i{iteration}_s{servo}_{delta}", step_degrees=2, settle_seconds=0.18)
                time.sleep(0.35)
                metric = fixed_metric(f"iteration_{iteration}_servo_{servo}_{delta}")
                restore = trainer.slow_move(servo, int(pose[servo]), f"mim_fixed_visual_servo_restore_i{iteration}_s{servo}_{delta}", step_degrees=2, settle_seconds=0.14)
                test = {"servo": servo, "delta": delta, "target": target, "move": move, "metric": metric, "restore": restore}
                tests.append(test)
                if score(metric) < score(best_metric):
                    best_metric = metric
                    best_move = {"servo": servo, "target": target, "delta": delta, "metric": metric}

        applied = None
        if best_move and score(best_metric) < score(current) - 8:
            applied = trainer.slow_move(
                int(best_move["servo"]),
                int(best_move["target"]),
                f"mim_fixed_visual_servo_apply_i{iteration}",
                step_degrees=1,
                settle_seconds=0.22,
            )
            time.sleep(0.6)
            current = fixed_metric(f"iteration_{iteration}_after_apply")
        record = {
            "iteration": iteration,
            "start_pose": start_pose,
            "current": current,
            "tests": tests,
            "best_move": best_move,
            "applied": applied,
            "end_pose": trainer.pose(),
        }
        payload["iterations"].append(record)
        write_json(payload)
        if isinstance(current.get("dx"), (int, float)) and isinstance(current.get("dy"), (int, float)):
            if abs(float(current["dx"])) <= 45 and abs(float(current["dy"])) <= 55:
                break
        if not applied:
            break

    before_close = fixed_metric("before_close_final")
    payload["before_close"] = before_close
    if not (
        isinstance(before_close.get("dx"), (int, float))
        and isinstance(before_close.get("dy"), (int, float))
        and abs(float(before_close["dx"])) <= 60
        and abs(float(before_close["dy"])) <= 80
    ):
        payload["status"] = "blocked_with_evidence"
        payload["blocker"] = {
            "reason_code": "visual_servo_could_not_reach_grip_contact_window",
            "before_close": before_close,
            "next_learning_objective": "Use simulation/IK or reposition table object into reachable known-good side-seat pose.",
        }
        write_json(payload)
        print(json.dumps(payload["blocker"], indent=2))
        return 2

    trainer.slow_move(5, 0, "mim_fixed_visual_servo_close_for_pickup", step_degrees=1, settle_seconds=0.18)
    time.sleep(0.8)
    after_close = fixed_metric("after_close")
    pose = trainer.pose()
    lift_moves = []
    if len(pose) >= 6:
        lift_moves.append(trainer.slow_move(1, max(0, int(pose[1]) - 6), "mim_fixed_visual_servo_lift_shoulder", step_degrees=1, settle_seconds=0.24))
        lift_moves.append(trainer.slow_move(2, max(0, int(pose[2]) - 6), "mim_fixed_visual_servo_lift_elbow", step_degrees=1, settle_seconds=0.24))
    time.sleep(0.8)
    after_lift = fixed_metric("after_lift")
    closed_bottom = (((after_close.get("block_center") or {}).get("y")) if isinstance(after_close.get("block_center"), dict) else None)
    lift_bottom = (((after_lift.get("block_center") or {}).get("y")) if isinstance(after_lift.get("block_center"), dict) else None)
    lifted = isinstance(closed_bottom, (int, float)) and isinstance(lift_bottom, (int, float)) and float(lift_bottom) <= float(closed_bottom) - 35
    payload.update(
        {
            "after_close": after_close,
            "lift_moves": lift_moves,
            "after_lift": after_lift,
            "success": bool(lifted),
            "status": "completed_with_pickup_evidence" if lifted else "blocked_with_evidence",
            "evaluation": {
                "closed_block_center_y": closed_bottom,
                "lifted_block_center_y": lift_bottom,
                "lifted_up_px": (round(float(closed_bottom) - float(lift_bottom), 2) if isinstance(closed_bottom, (int, float)) and isinstance(lift_bottom, (int, float)) else None),
            },
            "final_pose": trainer.pose(),
        }
    )
    if not lifted:
        payload["blocker"] = {
            "reason_code": "closed_but_no_fixed_observer_lift",
            "next_learning_objective": "Continue visual servo with a better contact target or use IK/simulation coordinates.",
        }
    write_json(payload)
    print(json.dumps({"status": payload["status"], "success": payload["success"], "evaluation": payload.get("evaluation")}, indent=2))
    return 0 if lifted else 2


if __name__ == "__main__":
    raise SystemExit(main())
