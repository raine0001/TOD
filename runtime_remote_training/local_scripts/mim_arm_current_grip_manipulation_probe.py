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
STATUS_PATH = SHARED / "MIM_ARM_CURRENT_GRIP_MANIPULATION_PROBE.latest.json"
ARM_HOST = "http://192.168.1.90:5000"
STEP_DEGREES = 2
SETTLE_SECONDS = 0.35


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def request_json(endpoint: str, payload: dict[str, Any] | None = None, timeout: float = 8.0) -> dict[str, Any]:
    if payload is None:
        request = urllib.request.Request(f"{ARM_HOST}{endpoint}", method="GET")
    else:
        request = urllib.request.Request(
            f"{ARM_HOST}{endpoint}",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return {"ok": True, "data": json.loads(response.read().decode("utf-8"))}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def current_pose() -> list[int]:
    state = request_json("/arm_state")
    data = state.get("data") if isinstance(state.get("data"), dict) else {}
    pose = data.get("current_pose") if isinstance(data.get("current_pose"), list) else []
    return [int(value) for value in pose[:6]] if len(pose) >= 6 else []


def slow_move(servo: int, start: int, target: int, source: str) -> dict[str, Any]:
    start = max(0, min(180, int(start)))
    target = max(0, min(180, int(target)))
    if start == target:
        return {"ok": True, "servo": servo, "start": start, "target": target, "commands": []}
    direction = 1 if target > start else -1
    angle = start
    commands: list[dict[str, Any]] = []
    while angle != target:
        angle += direction * STEP_DEGREES
        if (direction > 0 and angle > target) or (direction < 0 and angle < target):
            angle = target
        result = request_json(
            "/move",
            {
                "servo": servo,
                "angle": angle,
                "source": source,
                "motion_profile": "mim_current_grip_small_manipulation_probe",
                "step_degrees": STEP_DEGREES,
            },
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "start": start, "target": target, "failed_at": angle, "commands": commands}
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def capture_arm_camera(label: str) -> dict[str, Any]:
    result = request_json("/capture_frame", {}, timeout=10.0)
    return {"label": label, "ok": bool(result.get("ok")), "result": result}


def capture_pc_observer(label: str) -> dict[str, Any]:
    command = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ROOT / "scripts" / "Update-MIMArmTableObserverCamera.ps1"),
        "-EnvFile",
        ".env",
        "-UploadToMim",
    ]
    completed = subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, timeout=90, check=False)
    status = read_json(SHARED / "MIM_ARM_TABLE_OBSERVER_STATUS.latest.json")
    return {
        "label": label,
        "ok": completed.returncode == 0 and bool(status.get("success")),
        "returncode": completed.returncode,
        "frame_path": status.get("local_frame_path", ""),
        "remote_frame_path": status.get("remote_frame_path", ""),
        "status_generated_at": status.get("generated_at"),
    }


def blue_components(frame_path: str) -> list[dict[str, Any]]:
    image = cv2.imread(frame_path)
    if image is None:
        return []
    height, width = image.shape[:2]
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(hsv, np.array([92, 80, 70]), np.array([132, 255, 255]))
    count, _labels, stats, centers = cv2.connectedComponentsWithStats(mask, 8)
    found: list[dict[str, Any]] = []
    for idx in range(1, count):
        area = int(stats[idx, cv2.CC_STAT_AREA])
        if area < 100:
            continue
        x = int(stats[idx, cv2.CC_STAT_LEFT])
        y = int(stats[idx, cv2.CC_STAT_TOP])
        w = int(stats[idx, cv2.CC_STAT_WIDTH])
        h = int(stats[idx, cv2.CC_STAT_HEIGHT])
        cx, cy = centers[idx]
        if cx < width * 0.40 or cy < height * 0.40:
            continue
        found.append(
            {
                "area": area,
                "bbox": {"x": x, "y": y, "width": w, "height": h},
                "center": {"x": round(float(cx), 2), "y": round(float(cy), 2)},
            }
        )
    return sorted(found, key=lambda item: int(item["area"]), reverse=True)[:8]


def observe(label: str) -> dict[str, Any]:
    arm = capture_arm_camera(label)
    pc = capture_pc_observer(label)
    return {
        "label": label,
        "arm_camera": arm,
        "pc_observer": pc,
        "pc_blue_components": blue_components(str(pc.get("frame_path") or "")) if pc.get("ok") else [],
    }


def main() -> int:
    blockers: list[str] = []
    start_pose = current_pose()
    if not start_pose:
        blockers.append("current_pose_unavailable")

    observations: list[dict[str, Any]] = []
    moves: list[dict[str, Any]] = []
    if not blockers:
        observations.append(observe("baseline_open_current_grips"))

        close = slow_move(5, start_pose[5], 0, "mim_current_grip_probe_full_close")
        moves.append({"action": "full_close_current_grips", "move": close})
        if not close.get("ok"):
            blockers.append("full_close_failed")
        else:
            observations.append(observe("after_full_close_no_lift"))

        working_pose = current_pose()
        if not blockers and len(working_pose) >= 6:
            for action, servo, delta in [
                ("wrist_right_small_nudge", 3, 4),
                ("wrist_left_small_nudge", 3, -4),
                ("hand_right_small_nudge", 4, 4),
                ("hand_left_small_nudge", 4, -4),
            ]:
                before = current_pose()
                target = max(0, min(180, before[servo] + delta))
                out = slow_move(servo, before[servo], target, f"mim_current_grip_probe_{action}")
                moves.append({"action": action, "move": out})
                time.sleep(0.5)
                observations.append(observe(f"after_{action}"))
                back = slow_move(servo, target, before[servo], f"mim_current_grip_probe_{action}_return")
                moves.append({"action": f"{action}_return", "move": back})
                if not out.get("ok") or not back.get("ok"):
                    blockers.append(f"{action}_failed")
                    break

        final_pose = current_pose()
        if final_pose:
            if final_pose[5] != start_pose[5]:
                moves.append({"action": "restore_claw_open", "move": slow_move(5, final_pose[5], start_pose[5], "mim_current_grip_probe_restore_open")})
            final_pose = current_pose()
            if len(final_pose) >= 6 and final_pose[2] != start_pose[2]:
                moves.append({"action": "restore_elbow", "move": slow_move(2, final_pose[2], start_pose[2], "mim_current_grip_probe_restore_elbow")})
        observations.append(observe("final_restored_open"))

    payload = {
        "packet_type": "mim-arm-current-grip-manipulation-probe-v1",
        "generated_at": now_iso(),
        "objective_id": "OBJ-0100",
        "status": "completed_with_current_grip_learning_evidence" if not blockers else "blocked_with_evidence",
        "success": bool(not blockers),
        "learning_owner": "MIM",
        "goal": "Learn what the currently installed rigid grips can do without TPU tips.",
        "motion_policy": {
            "no_transport": True,
            "no_large_sweeps": True,
            "small_nudge_degrees": 4,
            "step_degrees": STEP_DEGREES,
            "settle_seconds": SETTLE_SECONDS,
            "restore_open_pose": True,
        },
        "start_pose": start_pose,
        "final_pose": current_pose(),
        "moves": moves,
        "observations": observations,
        "blockers": list(dict.fromkeys(blockers)),
        "next_recovery_action": (
            "Use this evidence to decide whether the current grip can slide/rotate objects reliably. "
            "If lift remains impossible, train push-place and side-trap maneuvers until grip tips are redesigned."
        ),
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(
        {
            "status": payload["status"],
            "success": payload["success"],
            "start_pose": payload["start_pose"],
            "final_pose": payload["final_pose"],
            "observation_count": len(observations),
            "move_count": len(moves),
            "blockers": payload["blockers"],
        },
        indent=2,
        sort_keys=True,
    ))
    return 0 if not blockers else 2


if __name__ == "__main__":
    raise SystemExit(main())
