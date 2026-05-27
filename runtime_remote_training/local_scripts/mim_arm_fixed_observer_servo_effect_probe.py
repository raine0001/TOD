#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_FIXED_OBSERVER_SERVO_EFFECT_PROBE.latest.json"
TRAINER_PATH = ROOT / "runtime_remote_training" / "local_scripts" / "mim_arm_marker_aware_grip_trainer.py"
DETECTOR_PATH = ROOT / "runtime_remote_training" / "local_scripts" / "mim_arm_fixed_observer_marker_detector.py"


def load_module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"module import failed: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_command(command: list[str], timeout: int = 90) -> dict[str, Any]:
    completed = subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, timeout=timeout, check=False)
    return {
        "command": command,
        "returncode": completed.returncode,
        "ok": completed.returncode == 0,
        "stdout_tail": completed.stdout[-2500:],
        "stderr_tail": completed.stderr[-2500:],
    }


def fixed_capture_and_metric(detector: Any, label: str) -> dict[str, Any]:
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
        timeout=90,
    )
    detector_rc = detector.main()
    status = detector.load_json(SHARED / "MIM_ARM_FIXED_OBSERVER_MARKER_DETECTOR.latest.json")
    guidance = status.get("analysis", {}).get("guidance", {})
    return {
        "label": label,
        "capture_command": capture,
        "detector_returncode": detector_rc,
        "frame_path": status.get("analysis", {}).get("frame_path"),
        "annotated_frame_path": status.get("analysis", {}).get("annotated_frame_path"),
        "block_center": guidance.get("block_center"),
        "tip_mid": guidance.get("tip_mid"),
        "dx": guidance.get("block_to_tip_dx_px"),
        "dy": guidance.get("block_to_tip_dy_px"),
        "aligned_for_close": guidance.get("aligned_for_close"),
        "ok": guidance.get("ok"),
    }


def metric_delta(metric: dict[str, Any], baseline: dict[str, Any]) -> dict[str, Any]:
    try:
        dx_delta = float(metric["dx"]) - float(baseline["dx"])
        dy_delta = float(metric["dy"]) - float(baseline["dy"])
    except Exception:
        dx_delta = 0.0
        dy_delta = 0.0
    return {"dx_delta": round(dx_delta, 2), "dy_delta": round(dy_delta, 2)}


def main() -> int:
    trainer = load_module("marker_trainer", TRAINER_PATH)
    detector = load_module("fixed_detector", DETECTOR_PATH)
    start_pose = trainer.pose()
    if len(start_pose) < 6:
        payload = {
            "packet_type": "mim-arm-fixed-observer-servo-effect-probe-v1",
            "generated_at": trainer.now_iso(),
            "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-PERSIST-UNTIL-SUCCESS",
            "status": "blocked_with_evidence",
            "success": False,
            "error": "arm_pose_unavailable",
        }
        trainer.write_json(STATUS_PATH, payload)
        print(json.dumps(payload, indent=2))
        return 2

    if start_pose[5] < 79:
        trainer.slow_move(5, 79, "mim_fixed_observer_probe_open_tpu_acquisition", step_degrees=1, settle_seconds=0.25)
        time.sleep(0.5)

    baseline = fixed_capture_and_metric(detector, "baseline")
    effects: list[dict[str, Any]] = []
    # Small, reversible probes. Servo 5 is claw only, so it is excluded here.
    for servo, delta in [(0, -4), (0, 4), (1, -3), (1, 3), (2, -3), (2, 3), (3, -4), (3, 4), (4, -4), (4, 4)]:
        before = trainer.pose()
        target = max(0, min(180, int(before[servo]) + delta))
        move = trainer.slow_move(
            servo,
            target,
            f"mim_fixed_observer_probe_servo_{servo}_{delta:+d}",
            step_degrees=1,
            settle_seconds=0.45,
        )
        time.sleep(0.8)
        metric = fixed_capture_and_metric(detector, f"servo_{servo}_{delta:+d}")
        restore = trainer.slow_move(
            servo,
            int(before[servo]),
            f"mim_fixed_observer_probe_restore_servo_{servo}_{delta:+d}",
            step_degrees=1,
            settle_seconds=0.35,
        )
        time.sleep(0.5)
        effects.append(
            {
                "servo": servo,
                "delta": delta,
                "start_pose": before,
                "target": target,
                "move": move,
                "metric": metric,
                "restore": restore,
                **metric_delta(metric, baseline),
            }
        )

    ranked_for_dx_correction = sorted(
        effects,
        key=lambda item: abs(float(baseline.get("dx") or 0) + float(item.get("dx_delta") or 0)),
    )
    payload = {
        "packet_type": "mim-arm-fixed-observer-servo-effect-probe-v1",
        "generated_at": trainer.now_iso(),
        "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-PERSIST-UNTIL-SUCCESS",
        "status": "completed_with_evidence",
        "success": True,
        "start_pose": start_pose,
        "final_pose": trainer.pose(),
        "baseline": baseline,
        "effects": effects,
        "ranked_for_dx_correction": ranked_for_dx_correction,
        "next_recovery_action": "Use the best fixed-observer servo effect to reduce block_to_tip_dx_px, then confirm close-up with wrist camera before closing.",
    }
    trainer.write_json(STATUS_PATH, payload)
    print(json.dumps({"baseline": baseline, "top_effects": ranked_for_dx_correction[:4], "final_pose": payload["final_pose"]}, indent=2)[:6000])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
