#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
TRAINER_PATH = ROOT / "runtime_remote_training" / "local_scripts" / "mim_arm_marker_aware_grip_trainer.py"
STATUS_PATH = ROOT / "runtime" / "shared" / "MIM_ARM_BLUE_BLOCK_POSE_GRID.latest.json"


def load_trainer() -> Any:
    spec = importlib.util.spec_from_file_location("marker_trainer", TRAINER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("marker trainer import failed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def score(row: dict[str, Any]) -> float:
    dx = abs(float(row.get("dx") or 999))
    dy = float(row.get("dy") or 999)
    lower = float(row.get("lower") or 999)
    score_value = dx * 2.0 + abs(dy - 130) + abs(lower - 180) * 0.4
    if row.get("centered"):
        score_value -= 30
    if row.get("edge"):
        score_value += 20
    return round(score_value, 2)


def save(trainer: Any, payload: dict[str, Any]) -> None:
    rows = payload.get("rows", [])
    payload["ranked"] = sorted(rows, key=score)[:10]
    payload["final_pose"] = trainer.pose()
    payload["generated_at"] = trainer.now_iso()
    trainer.write_json(STATUS_PATH, payload)


def capture_row(trainer: Any, shoulder: int, elbow: int, wrist: int) -> dict[str, Any]:
    cap = trainer.capture_wrist(f"pose_grid_s{shoulder}_e{elbow}_w{wrist}")
    g = cap.get("analysis", {}).get("guidance", {})
    row = {
        "pose": trainer.pose(),
        "shoulder": shoulder,
        "elbow": elbow,
        "wrist": wrist,
        "frame": cap.get("frame_path"),
        "ok": g.get("ok"),
        "dx": g.get("block_to_tip_mid_dx_px"),
        "dy": g.get("block_to_tip_mid_dy_px"),
        "lower": g.get("block_bottom_minus_tip_mid_y_px"),
        "centered": g.get("centered"),
        "gap_ready": g.get("gap_ready"),
        "edge": g.get("block_touches_bottom_edge"),
        "score": None,
    }
    row["score"] = score(row)
    return row


def main() -> int:
    trainer = load_trainer()
    payload: dict[str, Any] = {
        "packet_type": "mim-arm-blue-block-pose-grid-v1",
        "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-PERSIST-UNTIL-SUCCESS",
        "status": "running_incremental_pose_grid",
        "success": False,
        "start_pose": trainer.pose(),
        "rows": [],
        "notes": [
            "Every row is persisted immediately so a PC restart does not erase the learning pass.",
            "Lower scores are better; target is centered block with dy around 130 and lower around 180 before close.",
        ],
    }

    trainer.slow_move(5, 49, "mim_resume_pose_grid_open_claw", step_degrees=1, settle_seconds=0.25)
    trainer.slow_move(0, 66, "mim_resume_pose_grid_base66", step_degrees=1, settle_seconds=0.35)

    for wrist in [84, 76, 92]:
        trainer.slow_move(4, wrist, f"mim_resume_pose_grid_wrist_{wrist}", step_degrees=1, settle_seconds=0.35)
        for shoulder in [104, 108, 100, 112, 96]:
            trainer.slow_move(1, shoulder, f"mim_resume_pose_grid_shoulder_{shoulder}", step_degrees=1, settle_seconds=0.35)
            for elbow in [32, 28, 24, 36, 40, 44]:
                trainer.slow_move(2, elbow, f"mim_resume_pose_grid_elbow_{elbow}", step_degrees=1, settle_seconds=0.35)
                time.sleep(0.4)
                row = capture_row(trainer, shoulder, elbow, wrist)
                payload["rows"].append(row)
                save(trainer, payload)
                print(json.dumps({k: row[k] for k in ["pose", "dx", "dy", "lower", "score", "frame"]}, sort_keys=True))

    payload["status"] = "completed_incremental_pose_grid"
    save(trainer, payload)
    print(json.dumps({"status": payload["status"], "ranked": payload["ranked"][:5], "final_pose": payload["final_pose"]}, indent=2)[:5000])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
