#!/usr/bin/env python3
"""Evaluate the uploaded PC lab observer frame for Dave face recognition."""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
from typing import Any


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"
MODEL_PATH = SHARED / "human_identity_models" / "dave_lbph_face_model.yml"


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


def detect_faces(cv2: Any, gray: Any) -> list[tuple[int, int, int, int]]:
    faces: list[tuple[int, int, int, int]] = []
    frontal_file = Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml"
    if frontal_file.exists():
        frontal = cv2.CascadeClassifier(str(frontal_file))
        faces.extend([(int(x), int(y), int(w), int(h)) for x, y, w, h in frontal.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(60, 60))])
    profile_file = Path(cv2.data.haarcascades) / "haarcascade_profileface.xml"
    if profile_file.exists():
        profile = cv2.CascadeClassifier(str(profile_file))
        faces.extend([(int(x), int(y), int(w), int(h)) for x, y, w, h in profile.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(60, 60))])
        flipped = cv2.flip(gray, 1)
        width = gray.shape[1]
        for fx, fy, fw, fh in profile.detectMultiScale(flipped, scaleFactor=1.1, minNeighbors=4, minSize=(60, 60)):
            faces.append((width - int(fx) - int(fw), int(fy), int(fw), int(fh)))
    return faces


def main() -> None:
    import cv2  # type: ignore

    generated_at = now_utc()
    observer = load_json(SHARED / "MIM_PC_LAB_OBSERVER_STATUS.latest.json")
    frame_path = Path(str(observer.get("remote_frame_path", "")))
    payload: dict[str, Any] = {
        "packet_type": "mim-pc-lab-observer-face-status-v1",
        "objective_id": "MIM-PC-LAB-OBSERVER-CAMERA-V1",
        "generated_at": generated_at,
        "observer_status": "runtime/shared/MIM_PC_LAB_OBSERVER_STATUS.latest.json",
        "frame_path": str(frame_path) if str(frame_path) else "",
        "source": "operator_pc_camera_bridge",
        "camera_name": observer.get("requested_camera_name", ""),
        "success": False,
    }

    if not frame_path.exists():
        payload.update({
            "status": "blocked_frame_missing_on_mim",
            "next_recovery_action": "Upload the PC camera frame to MIM and rerun this probe.",
        })
        write_json(SHARED / "MIM_PC_LAB_OBSERVER_FACE_STATUS.latest.json", payload)
        return

    image = cv2.imread(str(frame_path))
    if image is None:
        payload.update({"status": "blocked_frame_unreadable"})
        write_json(SHARED / "MIM_PC_LAB_OBSERVER_FACE_STATUS.latest.json", payload)
        return

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    faces = detect_faces(cv2, gray)
    payload["face_count"] = len(faces)
    payload["face_boxes"] = [{"x": x, "y": y, "w": w, "h": h} for x, y, w, h in faces]

    recognized = []
    if MODEL_PATH.exists() and hasattr(cv2, "face") and hasattr(cv2.face, "LBPHFaceRecognizer_create"):
        recognizer = cv2.face.LBPHFaceRecognizer_create()
        recognizer.read(str(MODEL_PATH))
        for x, y, w, h in faces:
            crop = cv2.resize(gray[y:y + h, x:x + w], (160, 160))
            label, confidence = recognizer.predict(crop)
            if int(label) == 1 and float(confidence) <= 75.0:
                recognized.append({
                    "name": "Dave",
                    "method": "opencv_lbph",
                    "confidence": float(confidence),
                    "confidence_rule": "lower_is_better_match; threshold <= 75",
                    "box": {"x": x, "y": y, "w": w, "h": h},
                })
        pc_enrollment = load_json(SHARED / "MIM_DAVE_PC_CAMERA_FACE_ENROLLMENT_STATUS.latest.json")
        crop_box = pc_enrollment.get("crop_box", {})
        try:
            x = int(crop_box["x"])
            y = int(crop_box["y"])
            w = int(crop_box["w"])
            h = int(crop_box["h"])
            crop = cv2.resize(gray[y:y + h, x:x + w], (160, 160))
            label, confidence = recognizer.predict(crop)
            payload["operator_confirmed_pc_crop_match"] = {
                "box": {"x": x, "y": y, "w": w, "h": h},
                "confidence": float(confidence),
                "confidence_rule": "lower_is_better_match; threshold <= 75",
                "source": "MIM_DAVE_PC_CAMERA_FACE_ENROLLMENT_STATUS.latest.json",
            }
            if int(label) == 1 and float(confidence) <= 75.0:
                recognized.append({
                    "name": "Dave",
                    "method": "opencv_lbph_operator_confirmed_pc_crop",
                    "confidence": float(confidence),
                    "confidence_rule": "lower_is_better_match; threshold <= 75",
                    "box": {"x": x, "y": y, "w": w, "h": h},
                })
        except Exception as exc:
            payload["operator_confirmed_pc_crop_match"] = {"error": f"{type(exc).__name__}: {exc}"}

    payload["recognized_humans"] = recognized
    payload["status"] = "recognized_dave_from_pc_camera" if recognized else "pc_camera_face_detected_no_dave_match"
    payload["success"] = bool(recognized)
    payload["next_recovery_action"] = "" if recognized else "Use the PC camera frame for a frontal Dave enrollment or improve framing, then rerun."
    write_json(SHARED / "MIM_PC_LAB_OBSERVER_FACE_STATUS.latest.json", payload)
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
