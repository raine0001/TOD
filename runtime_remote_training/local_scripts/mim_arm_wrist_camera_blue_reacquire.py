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
STATUS_PATH = SHARED / "MIM_ARM_WRIST_CAMERA_BLUE_REACQUIRE.latest.json"
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
                "motion_profile": "mim_wrist_camera_blue_reacquire_probe",
                "step_degrees": STEP_DEGREES,
            },
        )
        commands.append({"angle": angle, "result": result})
        if not result.get("ok"):
            return {"ok": False, "servo": servo, "start": start, "target": target, "failed_at": angle, "commands": commands}
        time.sleep(SETTLE_SECONDS)
    return {"ok": True, "servo": servo, "start": start, "target": target, "commands": commands}


def capture_latest(label: str) -> dict[str, Any]:
    request_json("/capture_frame", {}, timeout=10.0)
    completed = subprocess.run(
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
    status = {}
    try:
        status = json.loads((SHARED / "MIM_ARM_CAMERA_CAPTURE_STATUS.latest.json").read_text(encoding="utf-8-sig"))
    except Exception:
        status = {}
    frame_path = str(status.get("local_frame_path") or "")
    return {
        "label": label,
        "ok": completed.returncode == 0 and bool(status.get("success")),
        "frame_path": frame_path,
        "remote_frame_path": status.get("remote_frame_path", ""),
        "analysis": analyze(frame_path) if frame_path else {},
    }


def analyze(frame_path: str) -> dict[str, Any]:
    image = cv2.imread(frame_path)
    if image is None:
        return {"ok": False, "error": "cv2_imread_failed"}
    h, w = image.shape[:2]
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(hsv, np.array([92, 70, 60]), np.array([132, 255, 255]))
    count, _labels, stats, centers = cv2.connectedComponentsWithStats(mask, 8)
    components: list[dict[str, Any]] = []
    for idx in range(1, count):
        area = int(stats[idx, cv2.CC_STAT_AREA])
        if area < 50:
            continue
        x = int(stats[idx, cv2.CC_STAT_LEFT])
        y = int(stats[idx, cv2.CC_STAT_TOP])
        bw = int(stats[idx, cv2.CC_STAT_WIDTH])
        bh = int(stats[idx, cv2.CC_STAT_HEIGHT])
        cx, cy = centers[idx]
        # Ignore blue at extreme top/bottom edges from self or frame noise.
        if cy < h * 0.08 or cy > h * 0.92:
            continue
        components.append(
            {
                "area": area,
                "bbox": {"x": x, "y": y, "width": bw, "height": bh},
                "center": {"x": round(float(cx), 2), "y": round(float(cy), 2)},
            }
        )
    components.sort(key=lambda item: int(item["area"]), reverse=True)
    largest = components[0] if components else {}
    center_error = None
    if largest:
        center_error = {
            "dx_px": round(float(largest["center"]["x"]) - (w / 2), 2),
            "dy_px": round(float(largest["center"]["y"]) - (h / 2), 2),
        }
    score = 0.0
    if largest:
        dx = abs(float(largest["center"]["x"]) - (w / 2))
        dy = abs(float(largest["center"]["y"]) - (h / 2))
        score = float(largest["area"]) - (dx * 12.0) - (dy * 4.0)
    return {
        "ok": bool(largest),
        "largest_blue_component": largest,
        "component_count": len(components),
        "center_error": center_error,
        "score": round(score, 2),
        "reacquired": bool(largest and int(largest["area"]) >= 5000 and abs(center_error["dx_px"]) <= 180 and abs(center_error["dy_px"]) <= 220),
    }


def main() -> int:
    blockers: list[str] = []
    start_pose = current_pose()
    if len(start_pose) < 6:
        blockers.append("current_pose_unavailable")

    probes: list[dict[str, Any]] = []
    if not blockers:
        baseline = capture_latest("baseline")
        probes.append({"kind": "baseline", "pose": start_pose, "capture": baseline})

        candidates = [
            (0, -8), (0, 8),
            (3, -8), (3, 8),
            (4, -8), (4, 8),
            (1, -6), (1, 6),
            (2, -6), (2, 6),
        ]
        for index, (servo, delta) in enumerate(candidates, start=1):
            pose = current_pose()
            if len(pose) < 6:
                blockers.append("pose_lost_during_probe")
                break
            target = max(0, min(180, pose[servo] + delta))
            out = slow_move(servo, pose[servo], target, f"mim_blue_reacquire_probe_{index}_out")
            time.sleep(0.5)
            capture = capture_latest(f"candidate_{index}_servo_{servo}_{delta:+d}")
            back = slow_move(servo, target, pose[servo], f"mim_blue_reacquire_probe_{index}_return")
            probes.append(
                {
                    "kind": "candidate",
                    "index": index,
                    "servo": servo,
                    "delta": delta,
                    "target": target,
                    "out_ok": bool(out.get("ok")),
                    "return_ok": bool(back.get("ok")),
                    "capture": capture,
                }
            )
            if not out.get("ok") or not back.get("ok"):
                blockers.append(f"candidate_{index}_motion_failed")
                break

    valid = [
        item for item in probes
        if item.get("capture", {}).get("analysis", {}).get("ok")
    ]
    best = sorted(valid, key=lambda item: float(item["capture"]["analysis"].get("score") or -999999), reverse=True)[0] if valid else {}
    applied_move: dict[str, Any] = {}
    final_capture: dict[str, Any] = {}
    if not best:
        blockers.append("blue_block_not_reacquired_in_any_probe")
    elif best.get("kind") == "candidate":
        pose = current_pose()
        servo = int(best["servo"])
        delta = int(best["delta"])
        target = max(0, min(180, pose[servo] + delta))
        applied_move = slow_move(servo, pose[servo], target, "mim_blue_reacquire_apply_best_candidate")
        time.sleep(0.7)
        final_capture = capture_latest("after_apply_best_reacquire")
        if not applied_move.get("ok"):
            blockers.append("apply_best_reacquire_move_failed")
        elif not final_capture.get("analysis", {}).get("reacquired"):
            blockers.append("best_reacquire_candidate_not_stable_after_apply")
    else:
        final_capture = best.get("capture", {})

    payload = {
        "packet_type": "mim-arm-wrist-camera-blue-reacquire-v1",
        "generated_at": now_iso(),
        "objective_id": "OBJ-0100",
        "status": "completed_with_reacquire_evidence" if not blockers else "blocked_with_evidence",
        "success": bool(not blockers),
        "learning_owner": "MIM",
        "start_pose": start_pose,
        "final_pose": current_pose(),
        "best_probe": {
            "kind": best.get("kind"),
            "index": best.get("index"),
            "servo": best.get("servo"),
            "delta": best.get("delta"),
            "score": best.get("capture", {}).get("analysis", {}).get("score"),
            "analysis": best.get("capture", {}).get("analysis"),
        },
        "applied_move": applied_move,
        "final_capture": final_capture,
        "probes": probes,
        "blockers": list(dict.fromkeys(blockers)),
        "next_recovery_action": "Use final reacquired pose as the open approach pose, then close to claw angle 22 and verify side-seat grip.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(
        {
            "status": payload["status"],
            "success": payload["success"],
            "start_pose": start_pose,
            "final_pose": payload["final_pose"],
            "best_probe": payload["best_probe"],
            "blockers": payload["blockers"],
        },
        indent=2,
        sort_keys=True,
    ))
    return 0 if not blockers else 2


if __name__ == "__main__":
    raise SystemExit(main())
