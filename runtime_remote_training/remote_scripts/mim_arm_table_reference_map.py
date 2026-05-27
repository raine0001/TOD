#!/usr/bin/env python3
from __future__ import annotations

import json
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from PIL import Image
except Exception as exc:  # pragma: no cover
    print(json.dumps({"status": "blocked_with_evidence", "reason_code": "pillow_unavailable", "error": f"{type(exc).__name__}: {exc}"}))
    raise


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_TABLE_REFERENCE_MAP.latest.json"
OBJECTIVE_PATH = SHARED / "MIM_ARM_TABLE_REFERENCE_MAP_OBJECTIVE.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(name: str) -> dict[str, Any]:
    path = SHARED / name
    try:
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8-sig"))
            return data if isinstance(data, dict) else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def parse_utc_timestamp(value: Any) -> datetime | None:
    try:
        text = str(value or "").strip()
        if not text:
            return None
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except Exception:
        return None


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def components(mask: set[tuple[int, int]], *, min_points: int) -> list[dict[str, Any]]:
    remaining = set(mask)
    found: list[dict[str, Any]] = []
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
            found.append(
                {
                    "sample_points": count,
                    "bbox": {
                        "x": min_x * 3,
                        "y": min_y * 3,
                        "width": (max_x - min_x + 1) * 3,
                        "height": (max_y - min_y + 1) * 3,
                    },
                    "center": {"x": int((min_x + max_x + 1) * 1.5), "y": int((min_y + max_y + 1) * 1.5)},
                }
            )
    return found


def observer_frame() -> tuple[Path, dict[str, Any], str]:
    now = datetime.now(timezone.utc)
    for artifact, label in (
        ("MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json", "pi_table_observer"),
        ("MIM_ARM_TABLE_OBSERVER_STATUS.latest.json", "operator_pc_table_observer"),
    ):
        status = read_json(artifact)
        generated_at = parse_utc_timestamp(status.get("generated_at"))
        age_seconds = (now - generated_at).total_seconds() if generated_at else None
        if status.get("success") is not True:
            continue
        if age_seconds is None or age_seconds > 900:
            continue
        frame = Path(str(status.get("remote_frame_path") or ""))
        if frame.exists():
            return frame, status, label
    return Path(""), {}, ""


def detect_reference_map(frame_path: Path, camera_label: str) -> dict[str, Any]:
    image = Image.open(frame_path).convert("RGB")
    width, height = image.size
    if camera_label == "operator_pc_table_observer":
        roi = {"x_min": int(width * 0.58), "x_max": width, "y_min": int(height * 0.52), "y_max": height}
    else:
        roi = {"x_min": 180, "x_max": min(width, 820), "y_min": 260, "y_max": min(height, 710)}

    blue_mask: set[tuple[int, int]] = set()
    light_mask: set[tuple[int, int]] = set()
    for y in range(roi["y_min"], roi["y_max"], 3):
        for x in range(roi["x_min"], roi["x_max"], 3):
            r, g, b = image.getpixel((x, y))
            if b >= 95 and b > r * 1.25 and b > g * 1.1:
                blue_mask.add((x // 3, y // 3))
            if r >= 135 and g >= 135 and b >= 135 and max(r, g, b) - min(r, g, b) <= 65:
                light_mask.add((x // 3, y // 3))

    blue_components = components(blue_mask, min_points=16)
    light_components = components(light_mask, min_points=28)

    def normalize(item: dict[str, Any]) -> dict[str, Any]:
        center = item["center"]
        bbox = item["bbox"]
        return {
            **item,
            "normalized_center": {
                "x": round(center["x"] / width, 5),
                "y": round(center["y"] / height, 5),
            },
            "roi_relative_center": {
                "x": round((center["x"] - roi["x_min"]) / max(1, roi["x_max"] - roi["x_min"]), 5),
                "y": round((center["y"] - roi["y_min"]) / max(1, roi["y_max"] - roi["y_min"]), 5),
            },
            "area_px_estimate": int(bbox["width"] * bbox["height"]),
        }

    blue = [
        {"id": f"blue_candidate_{idx+1}", "type": "blue_object_candidate", **normalize(item)}
        for idx, item in enumerate(
            sorted(
                [
                    c
                    for c in blue_components
                    if 10 <= c["bbox"]["width"] <= width * 0.16 and 10 <= c["bbox"]["height"] <= height * 0.16
                ],
                key=lambda c: c["sample_points"],
                reverse=True,
            )[:8]
        )
    ]
    pads = [
        {"id": f"unlabeled_pad_slot_{idx+1}", "type": "unlabeled_pad_or_light_reference", **normalize(item)}
        for idx, item in enumerate(
            sorted(
                [
                    c
                    for c in light_components
                    if 18 <= c["bbox"]["width"] <= width * 0.18
                    and 18 <= c["bbox"]["height"] <= height * 0.18
                    and 0.35 <= c["bbox"]["width"] / max(1, c["bbox"]["height"]) <= 2.4
                ],
                key=lambda c: (c["center"]["y"], c["center"]["x"]),
            )[:12]
        )
    ]

    table_bounds = {
        "coordinate_space": "observer_image_normalized",
        "x_min": round(roi["x_min"] / width, 5),
        "x_max": round(roi["x_max"] / width, 5),
        "y_min": round(roi["y_min"] / height, 5),
        "y_max": round(roi["y_max"] / height, 5),
        "source": "roi_bootstrap_not_metric_table_plane",
    }
    return {
        "frame_width": width,
        "frame_height": height,
        "roi": roi,
        "table_bounds": table_bounds,
        "blue_object_candidates": blue,
        "unlabeled_pad_candidates": pads,
    }


def main() -> int:
    generated_at = now_iso()
    write_json(
        OBJECTIVE_PATH,
        {
            "packet_type": "mim-arm-table-reference-map-objective-v1",
            "generated_at": generated_at,
            "objective_id": "MIM-ARM-TABLE-REFERENCE-MAP-V1",
            "status": "active",
            "goal": "Create a camera-derived table reference map without pretending unlabeled pads are numbered.",
            "success_criteria": [
                "Publish current fixed-observer frame source.",
                "Publish visible blue object candidates.",
                "Publish visible pad/reference candidates.",
                "Keep numbered labels blocked until OCR, fiducials, or a trusted label map exists.",
            ],
        },
    )
    frame, status, camera_label = observer_frame()
    blockers: list[str] = []
    if not frame.exists():
        blockers.append("fixed_observer_frame_missing")
        detected = {"blue_object_candidates": [], "unlabeled_pad_candidates": []}
    else:
        detected = detect_reference_map(frame, camera_label)
    if len(detected.get("unlabeled_pad_candidates") or []) < 3:
        blockers.append("fewer_than_three_pad_reference_candidates")
    blockers.extend(
        [
            "numbered_pad_labels_not_trusted",
            "metric_table_plane_not_calibrated",
            "arm_pose_solver_not_bound_to_reference_map",
        ]
    )
    payload = {
        "packet_type": "mim-arm-table-reference-map-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-ARM-TABLE-REFERENCE-MAP-V1",
        "status": "provisional_reference_map_with_blockers" if detected.get("unlabeled_pad_candidates") else "blocked_with_evidence",
        "success": False,
        "source_frame": {
            "camera_label": camera_label,
            "observer_status_generated_at": status.get("generated_at"),
            "remote_frame_path": str(frame),
            "observer_artifact": (
                "runtime/shared/MIM_ARM_TABLE_OBSERVER_STATUS.latest.json"
                if camera_label == "operator_pc_table_observer"
                else "runtime/shared/MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json"
            ),
        },
        **detected,
        "label_policy": {
            "numbered_pad_labels_trusted": False,
            "reason": "No OCR/fiducial/operator-approved label map is bound. Pad slots are geometry references only.",
            "provisional_ordering": "image_top_to_bottom_then_left_to_right",
        },
        "blockers": list(dict.fromkeys(blockers)),
        "next_recovery_action": "Bind numbered pad labels using OCR, fiducial markers, or a trusted calibration map; then compute metric table coordinates.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if detected.get("unlabeled_pad_candidates") else 2


if __name__ == "__main__":
    raise SystemExit(main())
