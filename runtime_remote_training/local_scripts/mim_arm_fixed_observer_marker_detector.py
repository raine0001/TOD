#!/usr/bin/env python3
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_ARM_FIXED_OBSERVER_MARKER_DETECTOR.latest.json"
ANNOTATED_PATH = SHARED / "arm_table_observer" / "fixed_observer_marker_detector_annotated.latest.jpg"

# Fixed EMEET view geometry for the current arm table setup. The arm, blocks,
# and gripper contact markers are in this window; constraining the detector here
# prevents blue arm links, room objects, and background stickers from becoming
# false pickup targets.
TABLE_ROI = {"x": 1500, "y": 650, "width": 900, "height": 1400}


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


def components(
    mask: np.ndarray,
    *,
    min_area: int,
    max_area: int | None = None,
    offset_x: int = 0,
    offset_y: int = 0,
) -> list[dict[str, Any]]:
    count, _labels, stats, centers = cv2.connectedComponentsWithStats(mask, 8)
    out: list[dict[str, Any]] = []
    for idx in range(1, count):
        area = int(stats[idx, cv2.CC_STAT_AREA])
        if area < min_area:
            continue
        if max_area is not None and area > max_area:
            continue
        x = int(stats[idx, cv2.CC_STAT_LEFT]) + offset_x
        y = int(stats[idx, cv2.CC_STAT_TOP]) + offset_y
        w = int(stats[idx, cv2.CC_STAT_WIDTH])
        h = int(stats[idx, cv2.CC_STAT_HEIGHT])
        cx, cy = centers[idx]
        cx = float(cx) + offset_x
        cy = float(cy) + offset_y
        out.append(
            {
                "area": area,
                "bbox": {"x": x, "y": y, "width": w, "height": h},
                "center": {"x": round(float(cx), 2), "y": round(float(cy), 2)},
            }
        )
    out.sort(key=lambda item: int(item["area"]), reverse=True)
    return out


def in_roi(item: dict[str, Any], roi: dict[str, int]) -> bool:
    cx = float(item["center"]["x"])
    cy = float(item["center"]["y"])
    return (
        roi["x"] <= cx <= roi["x"] + roi["width"]
        and roi["y"] <= cy <= roi["y"] + roi["height"]
    )


def bbox_bottom(item: dict[str, Any]) -> float:
    bbox = item["bbox"]
    return float(bbox["y"] + bbox["height"])


def blue_contact_window(
    blue_mask: np.ndarray,
    roi: dict[str, int],
    tip_mid: dict[str, float],
) -> dict[str, Any]:
    # The blue cube can visually merge with blue arm plastic in the fixed view.
    # Measure only the local blue mass around/below the grip tips so pickup
    # logic is driven by the object-contact zone, not the full arm body.
    cx = int(round(float(tip_mid["x"]) - roi["x"]))
    cy = int(round(float(tip_mid["y"]) - roi["y"]))
    x0 = max(0, cx - 150)
    x1 = min(blue_mask.shape[1], cx + 260)
    y0 = max(0, cy - 80)
    y1 = min(blue_mask.shape[0], cy + 360)
    local = blue_mask[y0:y1, x0:x1]
    items = components(local, min_area=80, max_area=None, offset_x=roi["x"] + x0, offset_y=roi["y"] + y0)
    block_like = [
        item
        for item in items
        if 25 <= int(item["bbox"]["width"]) <= 240
        and 25 <= int(item["bbox"]["height"]) <= 240
        and int(item["area"]) >= 300
        and float(item["center"]["y"]) >= 980
    ]
    if not block_like:
        return {
            "ok": False,
            "reason": "no_block_sized_blue_component_in_grip_contact_window",
            "window": {"x": roi["x"] + x0, "y": roi["y"] + y0, "width": x1 - x0, "height": y1 - y0},
            "components": items[:8],
        }
    block_like.sort(
        key=lambda item: (
            -abs(float(item["center"]["x"]) - float(tip_mid["x"])),
            -abs(float(item["center"]["y"]) - float(tip_mid["y"])),
            int(item["area"]),
        ),
        reverse=True,
    )
    target = block_like[0]
    bbox = target["bbox"]
    center = target["center"]
    return {
        "ok": True,
        "window": {"x": roi["x"] + x0, "y": roi["y"] + y0, "width": x1 - x0, "height": y1 - y0},
        "area": int(target["area"]),
        "bbox": bbox,
        "center": center,
        "bottom_y": int(bbox["y"] + bbox["height"]),
        "components": items[:8],
        "selected_component": target,
    }


def select_block(blue: list[dict[str, Any]], yellow: list[dict[str, Any]], green: list[dict[str, Any]]) -> dict[str, Any]:
    # Prefer the blue object directly below the gripper markers. The blue cube
    # sometimes joins visually with other blue parts, so the largest component
    # is acceptable only after ROI and vertical-position checks.
    marker_centers = yellow + green
    marker_mid_x = None
    if marker_centers:
        marker_mid_x = sum(float(item["center"]["x"]) for item in marker_centers) / len(marker_centers)

    candidates = []
    for item in blue:
        bbox = item["bbox"]
        cx = float(item["center"]["x"])
        cy = float(item["center"]["y"])
        area = float(item["area"])
        if area < 500:
            continue
        block_sized = 35 <= bbox["width"] <= 220 and 35 <= bbox["height"] <= 220 and 700 <= area <= 45000
        # The blue cube lives on/near the table surface during approach and
        # should remain near the gripper during a lift. Blue components high on
        # the arm are camera brackets or links, not pickup evidence.
        if not block_sized or cy < 980:
            continue
        score = 0.0
        if block_sized:
            score += 6000
        if cy >= 1000:
            score += 2000
        if bbox_bottom(item) >= 1150:
            score += 1000
        if 1600 <= cx <= 2150:
            score += 800
        if marker_mid_x is not None:
            score -= abs(cx - marker_mid_x) * 0.7
        # The real cube is a compact component. Huge components are usually the
        # arm body, wiring, or merged blue regions and must not drive pickup
        # proof, even if they are close to the gripper.
        score += min(area, 30000) / 35.0
        score -= max(0, bbox["width"] - 260) * 8.0
        score -= max(0, bbox["height"] - 260) * 8.0
        candidates.append((score, item))
    candidates.sort(key=lambda pair: pair[0], reverse=True)
    return candidates[0][1] if candidates else {}


def select_pair(
    items: list[dict[str, Any]],
    *,
    y_min: int,
    x_min: int,
    x_max: int,
    y_max: int = 1520,
) -> list[dict[str, Any]]:
    candidates = [
        item
        for item in items
        if y_min <= float(item["center"]["y"]) <= y_max
        and x_min <= float(item["center"]["x"]) <= x_max
    ]
    if len(candidates) < 2:
        candidates = [item for item in items if y_min - 150 <= float(item["center"]["y"]) <= y_max]
    if len(candidates) < 2:
        return candidates[:2]
    # Use the two strongest similarly-height markers. The gripper stickers form
    # a left/right pair with close y values.
    best: tuple[float, list[dict[str, Any]]] | None = None
    for i, left in enumerate(candidates):
        for right in candidates[i + 1 :]:
            dx = abs(float(left["center"]["x"]) - float(right["center"]["x"]))
            dy = abs(float(left["center"]["y"]) - float(right["center"]["y"]))
            area_score = min(float(left["area"]), 2000) + min(float(right["area"]), 2000)
            score = area_score + dx * 2.0 - dy * 12.0
            if dx < 45:
                score -= 1000
            pair = sorted([left, right], key=lambda item: float(item["center"]["x"]))
            if best is None or score > best[0]:
                best = (score, pair)
    return best[1] if best else candidates[:2]


def analyze(frame_path: str) -> dict[str, Any]:
    image = cv2.imread(frame_path)
    if image is None:
        return {"ok": False, "error": "cv2_imread_failed", "frame_path": frame_path}
    roi = TABLE_ROI
    crop = image[roi["y"] : roi["y"] + roi["height"], roi["x"] : roi["x"] + roi["width"]]
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    # Use a strict saturated-blue mask for the fixed observer. A broader mask
    # previously merged dark table grain, blue arm plastic, and the cube into a
    # giant component, which caused false pickup success.
    b, g, r = cv2.split(crop)
    hsv_blue = cv2.inRange(hsv, np.array([92, 80, 120]), np.array([122, 255, 255]))
    b_dominant = (
        (b.astype(np.int16) > 105)
        & (b.astype(np.int16) > g.astype(np.int16) + 18)
        & (b.astype(np.int16) > r.astype(np.int16) + 38)
    ).astype(np.uint8) * 255
    blue_mask = cv2.bitwise_and(hsv_blue, b_dominant)
    blue = components(
        blue_mask,
        min_area=70,
        max_area=350000,
        offset_x=roi["x"],
        offset_y=roi["y"],
    )
    yellow = components(
        cv2.inRange(hsv, np.array([18, 40, 90]), np.array([45, 255, 255])),
        min_area=20,
        max_area=50000,
        offset_x=roi["x"],
        offset_y=roi["y"],
    )
    green = components(
        cv2.inRange(hsv, np.array([43, 30, 60]), np.array([90, 255, 255])),
        min_area=20,
        max_area=50000,
        offset_x=roi["x"],
        offset_y=roi["y"],
    )

    block = select_block(blue, yellow, green)
    tip_markers = select_pair(yellow, y_min=1080, x_min=1780, x_max=2100)
    rear_markers = select_pair(green, y_min=1000, x_min=1800, x_max=2050)
    guidance: dict[str, Any] = {"ok": False, "reason": "need_blue_block_and_yellow_tip_markers"}
    if block and len(tip_markers) >= 2:
        tip_mid = {
            "x": round((float(tip_markers[0]["center"]["x"]) + float(tip_markers[-1]["center"]["x"])) / 2, 2),
            "y": round((float(tip_markers[0]["center"]["y"]) + float(tip_markers[-1]["center"]["y"])) / 2, 2),
        }
        block_center = block["center"]
        contact = blue_contact_window(blue_mask, roi, tip_mid)
        object_center = contact["center"] if contact.get("ok") else block_center
        guidance = {
            "ok": True,
            "tip_mid": tip_mid,
            "block_center": block_center,
            "contact_window_blue": contact,
            "contact_center": object_center,
            "block_to_tip_dx_px": round(float(block_center["x"]) - tip_mid["x"], 2),
            "block_to_tip_dy_px": round(float(block_center["y"]) - tip_mid["y"], 2),
            "contact_to_tip_dx_px": round(float(object_center["x"]) - tip_mid["x"], 2),
            "contact_to_tip_dy_px": round(float(object_center["y"]) - tip_mid["y"], 2),
            "aligned_for_close": abs(float(block_center["x"]) - tip_mid["x"]) <= 45
            and -40 <= float(block_center["y"]) - tip_mid["y"] <= 180,
            "contact_aligned_for_close": contact.get("ok")
            and abs(float(object_center["x"]) - tip_mid["x"]) <= 55
            and -30 <= float(object_center["y"]) - tip_mid["y"] <= 190,
            "purpose": "Use fixed observer to learn table-space approach vector; wrist camera is only close-up verification.",
        }
    annotated = image.copy()
    cv2.rectangle(
        annotated,
        (roi["x"], roi["y"]),
        (roi["x"] + roi["width"], roi["y"] + roi["height"]),
        (255, 255, 255),
        3,
    )
    for name, items, color in [
        ("block", [block] if block else [], (255, 0, 0)),
        ("yellow_tip", tip_markers, (0, 255, 255)),
        ("green_rear", rear_markers, (0, 255, 0)),
    ]:
        for idx, item in enumerate(items):
            bbox = item["bbox"]
            x = int(bbox["x"])
            y = int(bbox["y"])
            w = int(bbox["width"])
            h = int(bbox["height"])
            cv2.rectangle(annotated, (x, y), (x + w, y + h), color, 4)
            cv2.putText(
                annotated,
                f"{name}{idx}",
                (x, max(24, y - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.85,
                color,
                2,
            )
    ANNOTATED_PATH.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(ANNOTATED_PATH), annotated)
    return {
        "ok": bool(block),
        "frame_path": frame_path,
        "annotated_frame_path": str(ANNOTATED_PATH),
        "table_roi": roi,
        "blue_block": block,
        "all_blue_candidates": blue[:12],
        "all_yellow_candidates": yellow[:12],
        "all_green_candidates": green[:12],
        "yellow_tip_markers": tip_markers,
        "green_rear_markers": rear_markers,
        "guidance": guidance,
    }


def main() -> int:
    observer = load_json(SHARED / "MIM_ARM_TABLE_OBSERVER_STATUS.latest.json")
    frame_path = str(observer.get("local_frame_path") or "")
    analysis = analyze(frame_path) if frame_path else {"ok": False, "error": "no_fixed_observer_frame"}
    payload = {
        "packet_type": "mim-arm-fixed-observer-marker-detector-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-BLUE-BLOCK-PICKUP-PERSIST-UNTIL-SUCCESS",
        "status": "completed_with_evidence" if analysis.get("ok") else "blocked_with_evidence",
        "success": bool(analysis.get("ok")),
        "observer_status": observer,
        "analysis": analysis,
        "next_recovery_action": "Recover EMEET fixed observer, then use yellow/green markers plus blue block to learn approach vector in table space.",
    }
    write_json(STATUS_PATH, payload)
    print(json.dumps(payload, indent=2)[:5000])
    return 0 if analysis.get("ok") else 2


if __name__ == "__main__":
    raise SystemExit(main())
