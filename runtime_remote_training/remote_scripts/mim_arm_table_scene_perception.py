#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from PIL import Image
except Exception as exc:  # pragma: no cover - published as runtime evidence.
    print(json.dumps({"status": "blocked_with_evidence", "reason_code": "pillow_unavailable", "error": f"{type(exc).__name__}: {exc}"}))
    raise


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
SCENE_PATH = SHARED / "MIM_ARM_TABLE_SCENE.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_TABLE_OBJECT_INTERACTION_OBJECTIVE.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict[str, Any]:
    try:
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8-sig"))
            return data if isinstance(data, dict) else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def connected_components(mask: set[tuple[int, int]], *, min_points: int = 12) -> list[dict[str, Any]]:
    remaining = set(mask)
    components: list[dict[str, Any]] = []
    while remaining:
        seed = remaining.pop()
        q: deque[tuple[int, int]] = deque([seed])
        xs = [seed[0]]
        ys = [seed[1]]
        count = 1
        while q:
            x, y = q.popleft()
            for neighbor in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    q.append(neighbor)
                    xs.append(neighbor[0])
                    ys.append(neighbor[1])
                    count += 1
        if count >= min_points:
            min_x, max_x = min(xs), max(xs)
            min_y, max_y = min(ys), max(ys)
            components.append(
                {
                    "sample_points": count,
                    "bbox": {
                        "x": min_x * 2,
                        "y": min_y * 2,
                        "width": (max_x - min_x + 1) * 2,
                        "height": (max_y - min_y + 1) * 2,
                    },
                    "center": {"x": int((min_x + max_x + 1)), "y": int((min_y + max_y + 1))},
                }
            )
    return components


def detect_scene(frame_path: Path) -> dict[str, Any]:
    image = Image.open(frame_path).convert("RGB")
    width, height = image.size
    # Fixed observer ROI covers the visible arm table in the current camera placement.
    roi = {"x_min": 200, "x_max": 780, "y_min": 250, "y_max": min(690, height)}
    blue_mask: set[tuple[int, int]] = set()
    light_mask: set[tuple[int, int]] = set()
    for y in range(roi["y_min"], roi["y_max"], 2):
        for x in range(roi["x_min"], roi["x_max"], 2):
            r, g, b = image.getpixel((x, y))
            if b >= 80 and b > r * 1.35 and b > g * 1.15:
                blue_mask.add((x // 2, y // 2))
            if r >= 95 and g >= 95 and b >= 95 and max(r, g, b) - min(r, g, b) <= 55:
                light_mask.add((x // 2, y // 2))

    blue_components = connected_components(blue_mask, min_points=20)
    light_components = connected_components(light_mask, min_points=40)

    blue_blocks = []
    for i, comp in enumerate(sorted(blue_components, key=lambda c: c["sample_points"], reverse=True)[:6], start=1):
        bbox = comp["bbox"]
        if 12 <= bbox["width"] <= 140 and 12 <= bbox["height"] <= 140:
            blue_blocks.append(
                {
                    "id": f"blue_block_candidate_{i}",
                    "type": "block",
                    "color": "blue",
                    "bbox": bbox,
                    "center": comp["center"],
                    "confidence": "color_candidate",
                }
            )

    pad_candidates = []
    for i, comp in enumerate(sorted(light_components, key=lambda c: c["sample_points"], reverse=True)[:10], start=1):
        bbox = comp["bbox"]
        aspect = bbox["width"] / max(1, bbox["height"])
        if 20 <= bbox["width"] <= 180 and 20 <= bbox["height"] <= 180 and 0.45 <= aspect <= 2.2:
            pad_candidates.append(
                {
                    "id": f"light_pad_or_block_candidate_{i}",
                    "type": "pad_or_light_block",
                    "color": "white_or_gray",
                    "bbox": bbox,
                    "center": comp["center"],
                    "number": None,
                    "confidence": "shape_color_candidate_no_ocr",
                }
            )

    known_objects = blue_blocks + pad_candidates
    blockers = []
    if not blue_blocks:
        blockers.append("blue_block_not_detected_from_fixed_observer")
    blockers.append("number_pad_ocr_not_bound")
    blockers.append("arm_camera_to_table_coordinate_calibration_not_bound")
    blockers.append("grasp_planner_not_bound")

    return {
        "frame_width": width,
        "frame_height": height,
        "table_roi": roi,
        "objects": known_objects,
        "blue_block_candidates": blue_blocks,
        "pad_candidates": pad_candidates,
        "relationships": {
            "blue_block_on_number_pad": {
                "status": "unknown",
                "reason_code": "number_pad_ocr_not_bound",
            }
        },
        "blockers": blockers,
    }


def publish_objective() -> None:
    write_json(
        OBJECTIVE_PATH,
        {
            "packet_type": "mim-arm-table-object-interaction-objective-v1",
            "generated_at": now_iso(),
            "objective_id": "MIM-ARM-TABLE-OBJECT-INTERACTION-V1",
            "status": "active",
            "goal": "MIM distinguishes table exploration from room exploration, detects colored blocks and numbered pads, answers table object questions, and only attempts manipulation after perception, calibration, and grasp planning are proven.",
            "expected_scene": {
                "blocks": ["gray", "blue", "white"],
                "number_pads": ["1", "2", "3"],
            },
            "success_criteria": [
                "MIM can identify the blue, gray, and white blocks in camera evidence.",
                "MIM can identify number pads 1, 2, and 3.",
                "MIM can answer which numbered pad a block is on.",
                "MIM blocks manipulation until object pose, pad pose, grasp plan, and collision path are available.",
            ],
        },
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--query", default="")
    args = parser.parse_args()
    publish_objective()
    observer = read_json(SHARED / "MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json")
    frame_path = Path(str(observer.get("remote_frame_path") or ""))
    blockers: list[str] = []
    if not frame_path.exists():
        blockers.append("latest_pi_observer_frame_missing_on_mim")
    scene = detect_scene(frame_path) if not blockers else {"objects": [], "blockers": blockers}
    blockers.extend(scene.get("blockers") or [])
    payload = {
        "packet_type": "mim-arm-table-scene-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-TABLE-OBJECT-INTERACTION-V1",
        "status": "observed_with_blockers" if blockers else "completed_with_evidence",
        "success": not blockers,
        "source_frame": {
            "observer_status_artifact": "runtime/shared/MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json",
            "remote_frame_path": str(frame_path),
            "generated_at": observer.get("generated_at"),
            "camera_name": observer.get("camera_name"),
        },
        "query": args.query,
        **scene,
        "next_recovery_action": "Bind arm-camera/table calibration, OCR or fiducial labels for number pads, and a grasp planner before pick-and-place.",
    }
    write_json(SCENE_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["objects"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
