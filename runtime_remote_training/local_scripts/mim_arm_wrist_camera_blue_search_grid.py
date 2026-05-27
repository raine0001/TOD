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
STATUS_PATH = SHARED / "MIM_ARM_WRIST_CAMERA_BLUE_SEARCH_GRID.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.35


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


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
    data = req("/arm_state")
    p = data.get("current_pose") if isinstance(data, dict) else []
    return [int(v) for v in p[:6]] if isinstance(p, list) and len(p) >= 6 else []


def slow_move(servo: int, target: int, source: str) -> dict[str, Any]:
    p = pose()
    if len(p) < 6:
        return {"ok": False, "error": "current_pose_unavailable"}
    start = int(p[servo])
    target = max(0, min(180, int(target)))
    if start == target:
        return {"ok": True, "servo": servo, "start": start, "target": target, "commands": []}
    step = 2 if target > start else -2
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
                "motion_profile": "mim_blue_search_grid_no_contact",
                "step_degrees": STEP_DEGREES,
            },
        )
        commands.append({"angle": angle, "result": result})
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def capture(label: str) -> dict[str, Any]:
    req("/capture_frame", {}, timeout=10.0)
    subprocess.run(
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
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        timeout=90,
        check=False,
    )
    status = json.loads((SHARED / "MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json").read_text(encoding="utf-8-sig"))
    frame_path = str(status.get("local_frame_path") or "")
    return {"label": label, "frame_path": frame_path, "remote_frame_path": status.get("remote_frame_path"), "analysis": analyze(frame_path)}


def analyze(path: str) -> dict[str, Any]:
    image = cv2.imread(path)
    if image is None:
        return {"ok": False, "error": "cv2_imread_failed"}
    h, w = image.shape[:2]
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(hsv, np.array([92, 60, 110]), np.array([132, 255, 255]))
    count, _labels, stats, centers = cv2.connectedComponentsWithStats(mask, 8)
    comps: list[dict[str, Any]] = []
    for idx in range(1, count):
        area = int(stats[idx, cv2.CC_STAT_AREA])
        if area < 80:
            continue
        x = int(stats[idx, cv2.CC_STAT_LEFT])
        y = int(stats[idx, cv2.CC_STAT_TOP])
        bw = int(stats[idx, cv2.CC_STAT_WIDTH])
        bh = int(stats[idx, cv2.CC_STAT_HEIGHT])
        cx, cy = centers[idx]
        # Ignore edge/self artifacts; the real blue block should be a broad,
        # in-frame object like Dave's known-good grip demonstration.
        touches_edge = x <= 10 or y <= 10 or (x + bw) >= (w - 10) or (y + bh) >= (h - 10)
        if bw < 45 or bh < 45 or touches_edge:
            continue
        comps.append({"area": area, "bbox": {"x": x, "y": y, "width": bw, "height": bh}, "center": {"x": round(float(cx), 2), "y": round(float(cy), 2)}})
    comps.sort(key=lambda c: int(c["area"]), reverse=True)
    largest = comps[0] if comps else {}
    dx = abs(float(largest.get("center", {}).get("x", 999)) - w / 2) if largest else 999
    dy = abs(float(largest.get("center", {}).get("y", 999)) - h / 2) if largest else 999
    score = (float(largest.get("area") or 0) - dx * 8 - dy * 3) if largest else -999999
    return {
        "ok": bool(largest),
        "largest_blue_component": largest,
        "component_count": len(comps),
        "score": round(score, 2),
        "usable_block_view": bool(largest and int(largest["area"]) >= 1500 and dx <= 260 and dy <= 210),
    }


def main() -> int:
    start = pose()
    blockers: list[str] = []
    if len(start) < 6:
        blockers.append("current_pose_unavailable")
    moves: list[dict[str, Any]] = []
    observations: list[dict[str, Any]] = []
    if not blockers:
        if start[5] != 99:
            moves.append({"action": "open_claw", "move": slow_move(5, 99, "mim_blue_search_grid_open_claw")})
        base_angles = [56, 68, 80, 92, 104, 116, 128]
        shoulder_angles = [84, 90, 96, 102]
        wrist_angles = [88, 108, 128]
        hand_angles = [69, 89, 109]
        for shoulder in shoulder_angles:
            moves.append({"action": f"shoulder_{shoulder}", "move": slow_move(1, shoulder, f"mim_blue_search_grid_shoulder_{shoulder}")})
            for wrist in wrist_angles:
                moves.append({"action": f"wrist_{wrist}", "move": slow_move(3, wrist, f"mim_blue_search_grid_wrist_{wrist}")})
                for hand in hand_angles:
                    moves.append({"action": f"hand_{hand}", "move": slow_move(4, hand, f"mim_blue_search_grid_hand_{hand}")})
                    for base in base_angles:
                        moves.append({"action": f"base_{base}", "move": slow_move(0, base, f"mim_blue_search_grid_base_{base}")})
                        time.sleep(0.5)
                        obs = capture(f"shoulder_{shoulder}_wrist_{wrist}_hand_{hand}_base_{base}")
                        observations.append({"pose": pose(), **obs})
                        checkpoint = build_payload(start, moves, observations, [], "running_search_checkpoint")
                        checkpoint["success"] = False
                        checkpoint["next_recovery_action"] = "Continue wrist-camera search; do not grip until usable_block_view is true on a fresh frame."
                        write_json(STATUS_PATH, checkpoint)
                        if obs["analysis"].get("usable_block_view"):
                            payload = build_payload(start, moves, observations, [], "completed_with_blue_block_reacquired")
                            write_json(STATUS_PATH, payload)
                            print(json.dumps({"status": payload["status"], "success": True, "final_pose": payload["final_pose"], "best": payload["best_observation"]}, indent=2))
                            return 0
        blockers.append("blue_block_not_found_in_search_grid")
    payload = build_payload(start, moves, observations, blockers, "blocked_with_evidence")
    write_json(STATUS_PATH, payload)
    print(json.dumps({"status": payload["status"], "success": False, "final_pose": payload["final_pose"], "best": payload["best_observation"], "blockers": blockers}, indent=2))
    return 2


def build_payload(start: list[int], moves: list[dict[str, Any]], observations: list[dict[str, Any]], blockers: list[str], status: str) -> dict[str, Any]:
    usable = [o for o in observations if o.get("analysis", {}).get("usable_block_view")]
    best_pool = usable or observations
    best = sorted(best_pool, key=lambda o: float(o.get("analysis", {}).get("score") or -999999), reverse=True)[0] if best_pool else {}
    return {
        "packet_type": "mim-arm-wrist-camera-blue-search-grid-v1",
        "generated_at": now_iso(),
        "objective_id": "OBJ-0100",
        "status": status,
        "success": status == "completed_with_blue_block_reacquired",
        "learning_owner": "MIM",
        "start_pose": start,
        "final_pose": pose(),
        "moves": moves,
        "observations": observations,
        "best_observation": {
            "label": best.get("label"),
            "pose": best.get("pose"),
            "frame_path": best.get("frame_path"),
            "analysis": best.get("analysis"),
        },
        "blockers": blockers,
        "next_recovery_action": "If reacquired, close to claw angle 22 only after the block is centered and visibly seated low between the jaws.",
    }


if __name__ == "__main__":
    raise SystemExit(main())
