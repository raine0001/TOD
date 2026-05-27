#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_PERSISTENT_TRAINER.latest.json"
SESSION_PATH = SHARED / "MIM_ARM_BLUE_BLOCK_AUTONOMOUS_SESSION_STATUS.latest.json"
ARM_HOST = "http://192.168.1.90:5000"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        return {"load_error": f"{type(exc).__name__}: {exc}", "path": str(path)}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def req(endpoint: str, payload: dict[str, Any] | None = None, timeout: float = 8.0) -> dict[str, Any]:
    if payload is None:
        request = urllib.request.Request(f"{ARM_HOST}{endpoint}", method="GET")
    else:
        request = urllib.request.Request(
            f"{ARM_HOST}{endpoint}",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode())


def pose() -> list[int]:
    try:
        state = req("/arm_state", timeout=5.0)
    except Exception:
        return []
    p = state.get("current_pose") if isinstance(state, dict) else []
    return [int(v) for v in p[:6]] if isinstance(p, list) and len(p) >= 6 else []


def slow_move(servo: int, target: int, source: str, step_degrees: int = 2, settle_seconds: float = 0.35) -> dict[str, Any]:
    p = pose()
    if len(p) < 6:
        return {"ok": False, "error": "current_pose_unavailable"}
    start = int(p[servo])
    target = max(0, min(180, int(target)))
    if start == target:
        return {"ok": True, "servo": servo, "start": start, "target": target, "commands": []}
    step = step_degrees if target > start else -step_degrees
    angle = start
    commands: list[dict[str, Any]] = []
    while angle != target:
        angle += step
        if (step > 0 and angle > target) or (step < 0 and angle < target):
            angle = target
        result = req(
            "/move",
            {
                "servo": servo,
                "angle": angle,
                "source": source,
                "motion_profile": "mim_blue_block_persistent_trainer_slow",
                "step_degrees": step_degrees,
            },
            timeout=8.0,
        )
        commands.append({"angle": angle, "result": result})
        time.sleep(settle_seconds)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def run_command(command: list[str], timeout: int) -> dict[str, Any]:
    started = now_iso()
    try:
        completed = subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, timeout=timeout, check=False)
        return {
            "command": command,
            "started_at": started,
            "finished_at": now_iso(),
            "returncode": completed.returncode,
            "stdout_tail": completed.stdout[-4000:],
            "stderr_tail": completed.stderr[-4000:],
            "ok": completed.returncode == 0,
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "command": command,
            "started_at": started,
            "finished_at": now_iso(),
            "returncode": None,
            "stdout_tail": (exc.stdout or "")[-4000:] if isinstance(exc.stdout, str) else "",
            "stderr_tail": (exc.stderr or "")[-4000:] if isinstance(exc.stderr, str) else "",
            "ok": False,
            "error": "timeout_expired",
        }
    except Exception as exc:
        return {
            "command": command,
            "started_at": started,
            "finished_at": now_iso(),
            "returncode": None,
            "stdout_tail": "",
            "stderr_tail": "",
            "ok": False,
            "error": f"{type(exc).__name__}: {exc}",
        }


def capture_wrist(label: str) -> dict[str, Any]:
    try:
        req("/capture_frame", {}, timeout=10.0)
    except Exception as exc:
        return {"ok": False, "error": f"capture_endpoint_{type(exc).__name__}: {exc}", "label": label}
    result = run_command(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "scripts" / "Update-MIMArmCameraCapture.ps1"),
            "-EnvFile",
            ".env",
            "-UploadToMim",
        ],
        timeout=90,
    )
    status = load_json(SHARED / "MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json")
    return {"ok": bool(status.get("success")), "label": label, "command_result": result, "status": status}


def analyze_wrist_latest() -> dict[str, Any]:
    analyzer_path = ROOT / "runtime_remote_training" / "local_scripts" / "mim_arm_wrist_camera_blue_search_grid.py"
    spec = importlib.util.spec_from_file_location("mim_arm_wrist_camera_blue_search_grid", analyzer_path)
    if spec is None or spec.loader is None:
        return {"frame_path": "", "analysis": {"ok": False, "error": "analyzer_import_failed"}}
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    status = load_json(SHARED / "MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json")
    frame_path = str(status.get("local_frame_path") or "")
    analysis = module.analyze(frame_path)
    return {"frame_path": frame_path, "analysis": analysis, "grip_geometry": assess_grip_geometry(frame_path)}


def assess_grip_geometry(frame_path: str) -> dict[str, Any]:
    image = cv2.imread(frame_path)
    if image is None:
        return {"ok": False, "error": "cv2_imread_failed"}
    h, w = image.shape[:2]
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    blue = cv2.inRange(hsv, np.array([92, 60, 110]), np.array([132, 255, 255]))
    count, _labels, stats, centers = cv2.connectedComponentsWithStats(blue, 8)
    comps: list[tuple[int, int, int, int, int, Any]] = []
    for idx in range(1, count):
        x = int(stats[idx, cv2.CC_STAT_LEFT])
        y = int(stats[idx, cv2.CC_STAT_TOP])
        bw = int(stats[idx, cv2.CC_STAT_WIDTH])
        bh = int(stats[idx, cv2.CC_STAT_HEIGHT])
        area = int(stats[idx, cv2.CC_STAT_AREA])
        if area < 100 or x <= 10 or y <= 10 or x + bw >= w - 10 or y + bh >= h - 10:
            continue
        comps.append((area, x, y, bw, bh, centers[idx]))
    comps.sort(reverse=True)
    if not comps:
        return {"ok": False, "reason": "no_verified_blue_block_component"}

    _area, x, y, bw, bh, center = comps[0]
    white = cv2.inRange(hsv, np.array([0, 0, 145]), np.array([180, 75, 255]))
    yy1 = max(0, int(y + bh * 0.25))
    yy2 = min(h, y + bh + 80)
    left_region = white[yy1:yy2, max(0, x - 120):x]
    right_region = white[yy1:yy2, x + bw:min(w, x + bw + 120)]
    below_region = white[min(h, y + bh):min(h, y + bh + 90), max(0, x - 80):min(w, x + bw + 80)]
    left_white = int(np.count_nonzero(left_region))
    right_white = int(np.count_nonzero(right_region))
    below_white = int(np.count_nonzero(below_region))
    balance = round(min(left_white, right_white) / max(left_white, right_white, 1), 3)
    between_jaws = left_white >= 9000 and right_white >= 9000 and balance >= 0.45
    seated_low = below_white >= 7000
    return {
        "ok": bool(between_jaws and seated_low),
        "blue_bbox": {"x": x, "y": y, "width": bw, "height": bh},
        "blue_center": {"x": round(float(center[0]), 2), "y": round(float(center[1]), 2)},
        "left_white_pixels": left_white,
        "right_white_pixels": right_white,
        "below_white_pixels": below_white,
        "jaw_balance": balance,
        "between_jaws": between_jaws,
        "seated_low": seated_low,
        "policy": "Pickup proof requires the blue block to be visibly bracketed by both white grip jaws, not merely visible on the table.",
    }


def run_sensor_recovery() -> dict[str, Any]:
    pc = run_command(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "scripts" / "Update-MIMArmTableObserverCamera.ps1"),
            "-EnvFile",
            ".env",
            "-AllowFallbackCamera",
            "-UploadToMim",
        ],
        timeout=120,
    )
    pi = run_command(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "scripts" / "Update-MIMArmPiObserverCamera.ps1"),
            "-EnvFile",
            ".env",
            "-UploadToMim",
        ],
        timeout=120,
    )
    return {
        "pc_observer_command": pc,
        "pc_observer_status": load_json(SHARED / "MIM_ARM_TABLE_OBSERVER_STATUS.latest.json"),
        "pi_observer_command": pi,
        "pi_observer_status": load_json(SHARED / "MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json"),
    }


def attempt_pickup_if_visible(cycle_id: int) -> dict[str, Any]:
    before_capture = capture_wrist(f"cycle_{cycle_id}_pre_grip")
    before = analyze_wrist_latest()
    if not before.get("analysis", {}).get("usable_block_view"):
        return {
            "attempted": False,
            "reason": "no_verified_blue_block_in_wrist_camera",
            "before_capture": before_capture,
            "before_analysis": before,
        }
    refinement = refine_jaw_alignment(cycle_id, before)
    if refinement.get("applied"):
        before_capture = capture_wrist(f"cycle_{cycle_id}_pre_grip_after_alignment_refine")
        before = analyze_wrist_latest()

    close = slow_move(5, 22, f"mim_persistent_trainer_cycle_{cycle_id}_close_to_known_good")
    after_close_capture = capture_wrist(f"cycle_{cycle_id}_after_close")
    after_close = analyze_wrist_latest()
    if not after_close.get("analysis", {}).get("usable_block_view") or not after_close.get("grip_geometry", {}).get("ok"):
        slow_move(5, 99, f"mim_persistent_trainer_cycle_{cycle_id}_release_after_bad_close")
        return {
            "attempted": True,
            "success": False,
            "reason": "block_not_verified_between_jaws_after_close",
            "before_capture": before_capture,
            "before_analysis": before,
            "alignment_refinement": refinement,
            "close": close,
            "after_close_capture": after_close_capture,
            "after_close_analysis": after_close,
        }

    current = pose()
    lift_target = min(180, int(current[2]) + 6) if len(current) >= 6 else 30
    lift = slow_move(2, lift_target, f"mim_persistent_trainer_cycle_{cycle_id}_tiny_lift")
    after_lift_capture = capture_wrist(f"cycle_{cycle_id}_after_lift")
    after_lift = analyze_wrist_latest()
    success = bool(after_lift.get("analysis", {}).get("usable_block_view") and after_lift.get("grip_geometry", {}).get("ok"))
    return {
        "attempted": True,
        "success": success,
        "reason": "" if success else "block_not_verified_between_jaws_after_tiny_lift",
        "before_capture": before_capture,
        "before_analysis": before,
        "alignment_refinement": refinement,
        "close": close,
        "after_close_capture": after_close_capture,
        "after_close_analysis": after_close,
        "lift": lift,
        "after_lift_capture": after_lift_capture,
        "after_lift_analysis": after_lift,
    }


def alignment_score(observation: dict[str, Any]) -> float:
    analysis = observation.get("analysis", {})
    grip = observation.get("grip_geometry", {})
    if not analysis.get("usable_block_view"):
        return -999999.0
    score = float(analysis.get("score") or 0)
    score += float(grip.get("jaw_balance") or 0) * 30000.0
    score += min(float(grip.get("left_white_pixels") or 0), 20000.0) * 0.2
    score += min(float(grip.get("right_white_pixels") or 0), 20000.0) * 0.8
    if grip.get("between_jaws"):
        score += 50000.0
    if grip.get("seated_low"):
        score += 10000.0
    return round(score, 3)


def refine_jaw_alignment(cycle_id: int, initial_observation: dict[str, Any]) -> dict[str, Any]:
    current = pose()
    if len(current) < 6:
        return {"attempted": False, "reason": "current_pose_unavailable"}
    if initial_observation.get("grip_geometry", {}).get("ok"):
        return {"attempted": False, "reason": "already_aligned"}

    moves: list[dict[str, Any]] = []
    observations: list[dict[str, Any]] = [
        {
            "label": "initial",
            "pose": current,
            "frame_path": initial_observation.get("frame_path"),
            "analysis": initial_observation.get("analysis"),
            "grip_geometry": initial_observation.get("grip_geometry"),
            "score": alignment_score(initial_observation),
        }
    ]
    best = observations[0]
    base_targets = sorted({max(0, min(180, current[0] + delta)) for delta in (-18, -9, 0, 9, 18)})
    wrist_targets = sorted({max(0, min(180, current[3] + delta)) for delta in (-20, 0, 20)})
    hand_targets = sorted({max(0, min(180, current[4] + delta)) for delta in (-30, -15, 0, 15, 30)})

    # Keep the claw open during alignment; this is a no-contact refinement pass.
    if current[5] != 99:
        moves.append({"action": "open_claw_for_alignment", "move": slow_move(5, 99, f"mim_align_cycle_{cycle_id}_open_claw")})

    for wrist_target in wrist_targets:
        moves.append({"action": f"wrist_{wrist_target}", "move": slow_move(3, wrist_target, f"mim_align_cycle_{cycle_id}_wrist_{wrist_target}")})
        for hand_target in hand_targets:
            moves.append({"action": f"hand_{hand_target}", "move": slow_move(4, hand_target, f"mim_align_cycle_{cycle_id}_hand_{hand_target}")})
            for base_target in base_targets:
                moves.append({"action": f"base_{base_target}", "move": slow_move(0, base_target, f"mim_align_cycle_{cycle_id}_base_{base_target}")})
                capture_wrist(f"cycle_{cycle_id}_alignment_w{wrist_target}_h{hand_target}_b{base_target}")
                obs = analyze_wrist_latest()
                item = {
                    "label": f"wrist_{wrist_target}_hand_{hand_target}_base_{base_target}",
                    "pose": pose(),
                    "frame_path": obs.get("frame_path"),
                    "analysis": obs.get("analysis"),
                    "grip_geometry": obs.get("grip_geometry"),
                    "score": alignment_score(obs),
                }
                observations.append(item)
                if float(item["score"]) > float(best["score"]):
                    best = item
                publish_alignment_checkpoint(cycle_id, item, best, len(observations))
                if item.get("grip_geometry", {}).get("ok"):
                    break
            if best.get("grip_geometry", {}).get("ok"):
                break
        if best.get("grip_geometry", {}).get("ok"):
            break

    applied: dict[str, Any] = {}
    best_pose = best.get("pose") if isinstance(best.get("pose"), list) else []
    if len(best_pose) >= 6:
        for servo in (0, 3, 4):
            applied[f"servo_{servo}"] = slow_move(servo, int(best_pose[servo]), f"mim_align_cycle_{cycle_id}_apply_best_servo_{servo}")

    return {
        "attempted": True,
        "applied": bool(best_pose),
        "success": bool(best.get("grip_geometry", {}).get("ok")),
        "best": best,
        "moves": moves[-40:],
        "observation_count": len(observations),
        "observations_tail": observations[-12:],
    }


def publish_alignment_checkpoint(cycle_id: int, latest: dict[str, Any], best: dict[str, Any], observation_count: int) -> None:
    payload = {
        "packet_type": "mim-arm-blue-block-persistent-trainer-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-PERSIST-UNTIL-SUCCESS",
        "status": "running_alignment_checkpoint",
        "success": False,
        "learning_owner": "MIM",
        "operator_policy": "Do not give up; every blocker becomes the next recovery/training step.",
        "cycle": cycle_id,
        "live_pose": pose(),
        "latest_alignment_observation": latest,
        "best_alignment_observation": best,
        "alignment_observation_count": observation_count,
        "next_recovery_action": "Continue jaw-corridor refinement; close only after both jaws bracket the blue block.",
    }
    publish_status(payload)


def publish_status(payload: dict[str, Any]) -> None:
    write_json(STATUS_PATH, payload)
    try:
        run_command(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT / "scripts" / "Send-TODMimScript.ps1"),
                "-EnvFile",
                ".env",
                "-LocalPath",
                str(STATUS_PATH.relative_to(ROOT)),
                "-RemotePath",
                "/home/testpilot/mim/runtime/shared/MIM_ARM_BLUE_BLOCK_PERSISTENT_TRAINER.latest.json",
            ],
            timeout=120,
        )
    except Exception:
        pass


def build_status(status: str, cycle: int, cycles: list[dict[str, Any]], blockers: list[str]) -> dict[str, Any]:
    payload = {
        "packet_type": "mim-arm-blue-block-persistent-trainer-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-PERSIST-UNTIL-SUCCESS",
        "status": status,
        "success": status == "completed_verified_pickup",
        "learning_owner": "MIM",
        "operator_policy": "Do not give up; every blocker becomes the next recovery/training step.",
        "cycle": cycle,
        "live_pose": pose(),
        "blockers": blockers,
        "cycles": cycles[-8:],
        "next_recovery_action": "Continue autonomous sensor recovery, wrist-camera search, and verified grip attempts until pickup succeeds.",
    }
    return payload


def run(cycles_limit: int, cooldown_seconds: int, search_timeout_seconds: int) -> int:
    cycles: list[dict[str, Any]] = []
    cycle = 0
    while cycles_limit <= 0 or cycle < cycles_limit:
        cycle += 1
        blockers: list[str] = []
        publish_status(build_status("running", cycle, cycles, blockers))

        sensors = run_sensor_recovery()
        direct_capture = capture_wrist(f"cycle_{cycle}_direct_visibility_probe")
        direct_observation = analyze_wrist_latest()
        if direct_observation.get("analysis", {}).get("usable_block_view"):
            search = {"ok": True, "skipped": True, "reason": "blue_block_already_visible_in_wrist_camera", "direct_capture": direct_capture}
            search_artifact = {
                "status": "completed_with_blue_block_reacquired",
                "success": True,
                "best_observation": {
                    "label": "direct_visibility_probe",
                    "pose": pose(),
                    "frame_path": direct_observation.get("frame_path"),
                    "analysis": direct_observation.get("analysis"),
                    "grip_geometry": direct_observation.get("grip_geometry"),
                },
                "blockers": [],
            }
        else:
            search = run_command(
                ["python", str(ROOT / "runtime_remote_training" / "local_scripts" / "mim_arm_wrist_camera_blue_search_grid.py")],
                timeout=search_timeout_seconds,
            )
            search_artifact = load_json(SHARED / "MIM_ARM_WRIST_CAMERA_BLUE_SEARCH_GRID.latest.json")
        pickup = attempt_pickup_if_visible(cycle)

        if not search.get("ok"):
            blockers.append("wrist_search_did_not_complete_successfully")
        if not pickup.get("success"):
            blockers.append(str(pickup.get("reason") or "pickup_not_verified"))

        cycle_result = {
            "cycle": cycle,
            "generated_at": now_iso(),
            "start_pose": search_artifact.get("start_pose"),
            "end_pose": pose(),
            "sensor_recovery": sensors,
            "search_command": search,
            "search_artifact_summary": {
                "status": search_artifact.get("status"),
                "success": search_artifact.get("success"),
                "best_observation": search_artifact.get("best_observation"),
                "blockers": search_artifact.get("blockers"),
            },
            "pickup_attempt": pickup,
            "blockers": blockers,
        }
        cycles.append(cycle_result)

        if pickup.get("success"):
            publish_status(build_status("completed_verified_pickup", cycle, cycles, []))
            return 0

        publish_status(build_status("running_recovery_retry_scheduled", cycle, cycles, blockers))
        time.sleep(max(1, cooldown_seconds))

    publish_status(build_status("running_recovery_retry_scheduled", cycle, cycles, ["cycle_limit_reached_for_this_process_invocation"]))
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cycles", type=int, default=1, help="0 means keep retrying indefinitely.")
    parser.add_argument("--cooldown-seconds", type=int, default=60)
    parser.add_argument("--search-timeout-seconds", type=int, default=1500)
    args = parser.parse_args()
    return run(args.cycles, args.cooldown_seconds, args.search_timeout_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
