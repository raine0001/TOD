#!/usr/bin/env python3
from __future__ import annotations

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
STATUS_PATH = SHARED / "MIM_ARM_MARKER_AWARE_GRIP_TRAINER.latest.json"
ARM_HOST = "http://192.168.1.90:5000"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def load_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        return {"load_error": f"{type(exc).__name__}: {exc}", "path": str(path)}


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
                "motion_profile": "mim_marker_aware_slow",
                "step_degrees": step_degrees,
            },
            timeout=8.0,
        )
        commands.append({"angle": angle, "result": result})
        time.sleep(settle_seconds)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def run_command(command: list[str], timeout: int = 90) -> dict[str, Any]:
    try:
        completed = subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, timeout=timeout, check=False)
        return {
            "command": command,
            "returncode": completed.returncode,
            "stdout_tail": completed.stdout[-3000:],
            "stderr_tail": completed.stderr[-3000:],
            "ok": completed.returncode == 0,
        }
    except Exception as exc:
        return {"command": command, "returncode": None, "ok": False, "error": f"{type(exc).__name__}: {exc}"}


def capture_wrist(label: str) -> dict[str, Any]:
    try:
        req("/capture_frame", {}, timeout=10.0)
    except Exception as exc:
        return {"ok": False, "label": label, "error": f"capture_endpoint_{type(exc).__name__}: {exc}"}
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
    frame = str(status.get("local_frame_path") or "")
    return {"ok": bool(status.get("success")), "label": label, "frame_path": frame, "status": status, "command_result": result, "analysis": analyze_frame(frame)}


def components(mask: np.ndarray, *, min_area: int, max_area: int | None = None) -> list[dict[str, Any]]:
    count, _labels, stats, centers = cv2.connectedComponentsWithStats(mask, 8)
    out: list[dict[str, Any]] = []
    for idx in range(1, count):
        area = int(stats[idx, cv2.CC_STAT_AREA])
        if area < min_area:
            continue
        if max_area is not None and area > max_area:
            continue
        x = int(stats[idx, cv2.CC_STAT_LEFT])
        y = int(stats[idx, cv2.CC_STAT_TOP])
        w = int(stats[idx, cv2.CC_STAT_WIDTH])
        h = int(stats[idx, cv2.CC_STAT_HEIGHT])
        cx, cy = centers[idx]
        out.append(
            {
                "area": area,
                "bbox": {"x": x, "y": y, "width": w, "height": h},
                "center": {"x": round(float(cx), 2), "y": round(float(cy), 2)},
            }
        )
    out.sort(key=lambda item: int(item["area"]), reverse=True)
    return out


def analyze_frame(frame_path: str) -> dict[str, Any]:
    image = cv2.imread(frame_path)
    if image is None:
        return {"ok": False, "error": "cv2_imread_failed", "frame_path": frame_path}
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    blue_mask = cv2.inRange(hsv, np.array([92, 60, 110]), np.array([132, 255, 255]))
    yellow_mask = cv2.inRange(hsv, np.array([15, 10, 120]), np.array([50, 255, 255]))
    green_mask = cv2.inRange(hsv, np.array([43, 20, 90]), np.array([90, 255, 255]))

    blue = components(blue_mask, min_area=500)
    yellow = components(yellow_mask, min_area=80, max_area=9000)
    green = components(green_mask, min_area=80, max_area=9000)
    tip_markers = select_tip_pair(yellow)
    rear_markers = select_rear_pair(green or yellow, tip_markers)
    block = blue[0] if blue else {}
    guidance = build_guidance(block, tip_markers, rear_markers)
    return {
        "ok": bool(block and tip_markers),
        "frame_path": frame_path,
        "blue_block": block,
        "yellow_tip_markers": tip_markers,
        "green_rear_markers": rear_markers,
        "all_yellow_candidates": yellow[:8],
        "all_green_candidates": green[:8],
        "guidance": guidance,
    }


def select_marker_pair(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if len(candidates) < 2:
        return candidates
    # Use the two largest visible marker dots; sort left-to-right for stable geometry.
    pair = sorted(candidates[:4], key=lambda item: int(item.get("area", 0)), reverse=True)[:2]
    pair.sort(key=lambda item: float(item["center"]["x"]))
    return pair


def select_tip_pair(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    usable = [
        item
        for item in candidates
        if 20 <= float(item["center"]["x"]) <= 520
        and 240 <= float(item["center"]["y"]) <= 540
    ]
    if len(usable) < 2:
        usable = candidates
    best: tuple[float, list[dict[str, Any]]] | None = None
    for i, left in enumerate(usable):
        for right in usable[i + 1 :]:
            dx = abs(float(left["center"]["x"]) - float(right["center"]["x"]))
            dy = abs(float(left["center"]["y"]) - float(right["center"]["y"]))
            if dx < 120:
                continue
            score = dx * 2.0 - dy * 3.0 + min(float(left["area"]), 2500) + min(float(right["area"]), 2500)
            pair = sorted([left, right], key=lambda item: float(item["center"]["x"]))
            if best is None or score > best[0]:
                best = (score, pair)
    return best[1] if best else select_marker_pair(candidates)


def select_rear_pair(candidates: list[dict[str, Any]], tips: list[dict[str, Any]]) -> list[dict[str, Any]]:
    min_y = 0
    if tips:
        min_y = int(max(float(item["center"]["y"]) for item in tips) + 25)
    usable = [item for item in candidates if float(item["center"]["y"]) >= min_y]
    return select_marker_pair(usable)


def build_guidance(block: dict[str, Any], tips: list[dict[str, Any]], rears: list[dict[str, Any]]) -> dict[str, Any]:
    if not block or len(tips) < 2:
        return {"ok": False, "reason": "need_blue_block_and_two_yellow_tip_markers"}
    left, right = tips[0], tips[1]
    lc = left["center"]
    rc = right["center"]
    tip_mid = {"x": round((float(lc["x"]) + float(rc["x"])) / 2, 2), "y": round((float(lc["y"]) + float(rc["y"])) / 2, 2)}
    tip_gap = round(((float(lc["x"]) - float(rc["x"])) ** 2 + (float(lc["y"]) - float(rc["y"])) ** 2) ** 0.5, 2)
    bbox = block["bbox"]
    block_center = block["center"]
    block_bottom = float(bbox["y"] + bbox["height"])
    block_touches_bottom_edge = block_bottom >= 635
    dx = round(float(block_center["x"]) - tip_mid["x"], 2)
    dy = round(float(block_center["y"]) - tip_mid["y"], 2)
    lower_face_error = round(block_bottom - tip_mid["y"], 2)
    centered = abs(dx) <= 95
    depth_ready = -40 <= lower_face_error <= 165
    close_up_edge_ready = block_touches_bottom_edge and centered and 80 <= dy <= 180 and len(rears) >= 2
    gap_ready = tip_gap >= 90
    rear_mid = None
    if len(rears) >= 2:
        rear_mid = {
            "x": round((float(rears[0]["center"]["x"]) + float(rears[1]["center"]["x"])) / 2, 2),
            "y": round((float(rears[0]["center"]["y"]) + float(rears[1]["center"]["y"])) / 2, 2),
        }
    return {
        "ok": centered and (depth_ready or close_up_edge_ready) and gap_ready,
        "tip_mid": tip_mid,
        "tip_gap_px": tip_gap,
        "rear_mid": rear_mid,
        "block_center": block_center,
        "block_bottom_y": block_bottom,
        "block_to_tip_mid_dx_px": dx,
        "block_to_tip_mid_dy_px": dy,
        "block_bottom_minus_tip_mid_y_px": lower_face_error,
        "centered": centered,
        "depth_ready": depth_ready,
        "close_up_edge_ready": close_up_edge_ready,
        "block_touches_bottom_edge": block_touches_bottom_edge,
        "gap_ready": gap_ready,
        "policy": "Yellow markers define the active grip contact tips; green markers define rear gripper orientation reference.",
    }


def marker_guided_action(analysis: dict[str, Any]) -> dict[str, Any]:
    guidance = analysis.get("guidance", {})
    if not guidance.get("ok"):
        dx = float(guidance.get("block_to_tip_mid_dx_px") or 0)
        lower = float(guidance.get("block_bottom_minus_tip_mid_y_px") or 0)
        action: dict[str, Any] = {"reason": "not_aligned_for_marker_close", "moves": []}
        # Current empirical mapping from prior scans: base lower shifts the viewed block left-to-right
        # corridor enough to test; hand/wrist tune tip orientation. Keep this bounded.
        p = pose()
        if p:
            if dx < -95:
                action["moves"].append({"servo": 0, "target": max(0, p[0] - 6), "why": "block_left_of_tip_mid"})
            elif dx > 95:
                action["moves"].append({"servo": 0, "target": min(180, p[0] + 6), "why": "block_right_of_tip_mid"})
            if lower < -40:
                action["moves"].append({"servo": 1, "target": max(0, p[1] - 4), "why": "tip_line_below_block_lower_face"})
            elif lower > 200:
                action["moves"].append({"servo": 1, "target": max(0, p[1] - 4), "why": "shoulder_overshot_block_dropped_to_frame_edge"})
            elif lower > 165:
                action["moves"].append({"servo": 1, "target": min(180, p[1] + 4), "why": "tip_line_above_block_lower_face"})
        return action
    return {"reason": "aligned_for_test_close", "moves": [{"servo": 5, "target": 22, "why": "yellow_tip_geometry_ready"}]}


def main() -> int:
    captures: list[dict[str, Any]] = []
    moves: list[dict[str, Any]] = []
    start_pose = pose()
    cap = capture_wrist("marker_probe_start")
    captures.append(cap)
    action = marker_guided_action(cap.get("analysis", {}))
    for planned in action.get("moves", [])[:2]:
        moves.append({"planned": planned, "result": slow_move(int(planned["servo"]), int(planned["target"]), "mim_marker_aware_guided_action")})
    after = capture_wrist("marker_probe_after_action")
    captures.append(after)

    status = "completed_marker_guided_close_probe" if any(item.get("planned", {}).get("servo") == 5 for item in moves) else "completed_marker_alignment_probe"
    payload = {
        "packet_type": "mim-arm-marker-aware-grip-trainer-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-PERSIST-UNTIL-SUCCESS",
        "status": status,
        "success": False,
        "start_pose": start_pose,
        "final_pose": pose(),
        "marker_meaning": {
            "yellow": "active gripper contact tips; yellow-to-yellow closes on object",
            "green": "rear gripper reference; green-to-green closes behind tips",
        },
        "captures": captures,
        "action": action,
        "moves": moves,
        "next_recovery_action": "Use yellow tip midpoint and gap as gripper coordinates; learn servo-to-marker movement from repeated bounded probes.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2)[:6000])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
