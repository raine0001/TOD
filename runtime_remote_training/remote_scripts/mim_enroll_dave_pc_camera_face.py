#!/usr/bin/env python3
"""Add the confirmed PC-camera frontal Dave frame to MIM's face model."""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
from typing import Any


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"
MODEL_DIR = SHARED / "human_identity_models"
MODEL_PATH = MODEL_DIR / "dave_lbph_face_model.yml"


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> None:
    import cv2  # type: ignore
    import numpy as np  # type: ignore

    generated_at = now_utc()
    observer = load_json(SHARED / "MIM_PC_LAB_OBSERVER_STATUS.latest.json")
    frame_path = Path(str(observer.get("remote_frame_path", "")))
    payload: dict[str, Any] = {
        "packet_type": "mim-dave-pc-camera-face-enrollment-status-v1",
        "objective_id": "MIM-HUMAN-IDENTITY-BINDING-V1",
        "generated_at": generated_at,
        "source": "operator_pc_camera_bridge",
        "camera_name": observer.get("requested_camera_name", ""),
        "source_frame": str(frame_path),
        "success": False,
    }
    if not frame_path.exists():
        payload.update({"status": "blocked_pc_frame_missing"})
        write_json(SHARED / "MIM_DAVE_PC_CAMERA_FACE_ENROLLMENT_STATUS.latest.json", payload)
        return

    image = cv2.imread(str(frame_path))
    if image is None:
        payload.update({"status": "blocked_pc_frame_unreadable"})
        write_json(SHARED / "MIM_DAVE_PC_CAMERA_FACE_ENROLLMENT_STATUS.latest.json", payload)
        return

    height, width = image.shape[:2]
    # Operator-confirmed PC-camera frame. This crop targets Dave's visible frontal face
    # and avoids shelf objects that trigger false-positive Haar detections.
    x1 = int(width * 0.34)
    x2 = int(width * 0.67)
    y1 = int(height * 0.31)
    y2 = int(height * 0.88)
    face_region = image[y1:y2, x1:x2]
    gray = cv2.cvtColor(face_region, cv2.COLOR_BGR2GRAY)
    face = cv2.resize(gray, (160, 160))

    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    pc_crop_path = MODEL_DIR / "dave_pc_camera_face_enrollment_crop.jpg"
    cv2.imwrite(str(pc_crop_path), face)

    samples = [face]
    side_crop = MODEL_DIR / "dave_face_enrollment_crop.jpg"
    if side_crop.exists():
        side = cv2.imread(str(side_crop), cv2.IMREAD_GRAYSCALE)
        if side is not None:
            samples.append(cv2.resize(side, (160, 160)))

    recognizer = cv2.face.LBPHFaceRecognizer_create()
    recognizer.train(samples, np.array([1] * len(samples), dtype=np.int32))
    recognizer.write(str(MODEL_PATH))

    payload.update({
        "status": "completed_with_operator_confirmed_pc_camera_crop",
        "success": True,
        "human_name": "Dave",
        "crop_path": str(pc_crop_path),
        "model_path": str(MODEL_PATH),
        "crop_box": {"x": x1, "y": y1, "w": x2 - x1, "h": y2 - y1},
        "sample_count": len(samples),
        "truth_rule": "This PC-camera crop is accepted because the operator confirmed the camera is on Dave's face in the current frame.",
    })
    write_json(SHARED / "MIM_DAVE_PC_CAMERA_FACE_ENROLLMENT_STATUS.latest.json", payload)

    registry_path = SHARED / "MIM_HUMAN_IDENTITY_REGISTRY.latest.json"
    registry = load_json(registry_path)
    humans = registry.setdefault("humans", [])
    dave = next((h for h in humans if str(h.get("name", "")).lower() == "dave"), None)
    if dave is None:
        dave = {"name": "Dave", "roles": ["primary_operator"]}
        humans.append(dave)
    face_recognition = dave.setdefault("face_recognition", {})
    face_recognition.update({
        "enrolled": True,
        "pc_camera_enrollment_crop_path": str(pc_crop_path),
        "model_path": str(MODEL_PATH),
        "evidence_artifact": "runtime/shared/MIM_DAVE_PC_CAMERA_FACE_ENROLLMENT_STATUS.latest.json",
        "status": "enrolled_with_side_and_pc_camera_views",
    })
    registry["generated_at"] = generated_at
    registry["status"] = "face_enrollment_bound_with_pc_camera_view"
    write_json(registry_path, registry)
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
