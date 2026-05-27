#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
STATUS_PATH = ROOT / "runtime" / "shared" / "MIM_ARM_MARKER_SERVO_EFFECT_PROBE.latest.json"
TRAINER_PATH = ROOT / "runtime_remote_training" / "local_scripts" / "mim_arm_marker_aware_grip_trainer.py"


def load_trainer() -> Any:
    spec = importlib.util.spec_from_file_location("marker_trainer", TRAINER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("marker trainer import failed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def metric(capture: dict[str, Any]) -> dict[str, Any]:
    guidance = capture.get("analysis", {}).get("guidance", {})
    return {
        "frame_path": capture.get("frame_path"),
        "tip_mid": guidance.get("tip_mid"),
        "block_center": guidance.get("block_center"),
        "block_bottom_y": guidance.get("block_bottom_y"),
        "dx": guidance.get("block_to_tip_mid_dx_px"),
        "dy": guidance.get("block_to_tip_mid_dy_px"),
        "lower": guidance.get("block_bottom_minus_tip_mid_y_px"),
        "ok": guidance.get("ok"),
    }


def main() -> int:
    trainer = load_trainer()
    start_pose = trainer.pose()
    captures: list[dict[str, Any]] = []
    moves: list[dict[str, Any]] = []

    # Re-open to the learned TPU acquisition gap; the old 49-degree opening is
    # too narrow for this block.
    if len(start_pose) >= 6 and start_pose[5] < 79:
        moves.append({"action": "open_to_tpu_acquisition_gap", "result": trainer.slow_move(5, 79, "mim_marker_effect_open_observation_tpu")})

    baseline = trainer.capture_wrist("effect_probe_baseline")
    captures.append({"label": "baseline", "pose": trainer.pose(), "metric": metric(baseline)})
    servo_deltas = [(0, -6), (0, 6), (1, -4), (1, 4), (2, -4), (2, 4), (3, -8), (3, 8), (4, -8), (4, 8)]
    effects: list[dict[str, Any]] = []
    for servo, delta in servo_deltas:
        pose = trainer.pose()
        if len(pose) < 6:
            break
        target = max(0, min(180, pose[servo] + delta))
        out = trainer.slow_move(servo, target, f"mim_marker_effect_servo_{servo}_{delta:+d}")
        cap = trainer.capture_wrist(f"effect_probe_servo_{servo}_{delta:+d}")
        m = metric(cap)
        back = trainer.slow_move(servo, pose[servo], f"mim_marker_effect_return_servo_{servo}_{delta:+d}")
        effects.append(
            {
                "servo": servo,
                "delta": delta,
                "start_pose": pose,
                "target": target,
                "move": out,
                "return": back,
                "metric": m,
            }
        )
        captures.append({"label": f"servo_{servo}_{delta:+d}", "pose": trainer.pose(), "metric": m})

    base = captures[0]["metric"]
    ranked = []
    for effect in effects:
        m = effect["metric"]
        try:
            tip_y_delta = float(m["tip_mid"]["y"]) - float(base["tip_mid"]["y"])
            lower_delta = float(m["lower"]) - float(base["lower"])
        except Exception:
            tip_y_delta = 0.0
            lower_delta = 0.0
        ranked.append({**effect, "tip_mid_y_delta": round(tip_y_delta, 2), "lower_delta": round(lower_delta, 2)})
    ranked.sort(key=lambda item: float(item["tip_mid_y_delta"]), reverse=True)

    payload = {
        "packet_type": "mim-arm-marker-servo-effect-probe-v1",
        "generated_at": trainer.now_iso(),
        "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-PERSIST-UNTIL-SUCCESS",
        "status": "completed_with_marker_effect_evidence",
        "success": True,
        "start_pose": start_pose,
        "final_pose": trainer.pose(),
        "baseline": base,
        "effects_ranked_by_tip_mid_y_increase": ranked,
        "captures": captures,
        "next_recovery_action": "Use the servo effect that moves yellow tip midpoint downward toward the blue block, then retry marker-guided close.",
    }
    STATUS_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATUS_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"baseline": base, "top_effects": ranked[:4], "final_pose": payload["final_pose"]}, indent=2)[:6000])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
