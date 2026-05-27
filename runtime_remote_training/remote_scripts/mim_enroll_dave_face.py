#!/usr/bin/env python3
"""Enroll Dave's face for MIM using a confirmed lab face frame."""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
from typing import Any


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"
MODEL_DIR = SHARED / "human_identity_models"
OBJECTIVE_ID = "MIM-HUMAN-IDENTITY-BINDING-V1"


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def detect_faces(cv2: Any, gray: Any) -> list[tuple[int, int, int, int]]:
    faces: list[tuple[int, int, int, int]] = []
    frontal_file = Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml"
    if frontal_file.exists():
        frontal = cv2.CascadeClassifier(str(frontal_file))
        faces.extend([(int(x), int(y), int(w), int(h)) for x, y, w, h in frontal.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(40, 40))])
    profile_file = Path(cv2.data.haarcascades) / "haarcascade_profileface.xml"
    if profile_file.exists():
        profile = cv2.CascadeClassifier(str(profile_file))
        faces.extend([(int(x), int(y), int(w), int(h)) for x, y, w, h in profile.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(40, 40))])
        flipped = cv2.flip(gray, 1)
        width = gray.shape[1]
        for fx, fy, fw, fh in profile.detectMultiScale(flipped, scaleFactor=1.1, minNeighbors=4, minSize=(40, 40)):
            faces.append((width - int(fx) - int(fw), int(fy), int(fw), int(fh)))
    return faces


def main() -> None:
    import cv2  # type: ignore
    import numpy as np  # type: ignore

    status = load_json(SHARED / "MIM_FACE_RECOGNITION_STATUS.latest.json")
    candidates = (
        status.get("enrollment_candidates", {})
        .get("candidate_face_frame_paths", [])
    )
    frame_path = Path(candidates[0]) if candidates else None
    generated_at = now_utc()

    if not frame_path or not frame_path.exists():
        write_json(SHARED / "MIM_DAVE_FACE_ENROLLMENT_STATUS.latest.json", {
            "packet_type": "mim-dave-face-enrollment-status-v1",
            "objective_id": OBJECTIVE_ID,
            "generated_at": generated_at,
            "status": "blocked_no_candidate_frame",
            "success": False,
            "candidate_paths": candidates,
            "next_recovery_action": "Run the human identity evidence probe until it detects one face in a fresh lab frame.",
        })
        return

    if not hasattr(cv2, "face") or not hasattr(cv2.face, "LBPHFaceRecognizer_create"):
        write_json(SHARED / "MIM_DAVE_FACE_ENROLLMENT_STATUS.latest.json", {
            "packet_type": "mim-dave-face-enrollment-status-v1",
            "objective_id": OBJECTIVE_ID,
            "generated_at": generated_at,
            "status": "blocked_missing_opencv_lbph",
            "success": False,
            "candidate_frame": str(frame_path),
            "next_recovery_action": "Install opencv-contrib-python-headless in MIM's runtime environment.",
        })
        return

    image = cv2.imread(str(frame_path))
    if image is None:
        write_json(SHARED / "MIM_DAVE_FACE_ENROLLMENT_STATUS.latest.json", {
            "packet_type": "mim-dave-face-enrollment-status-v1",
            "objective_id": OBJECTIVE_ID,
            "generated_at": generated_at,
            "status": "blocked_candidate_frame_unreadable",
            "success": False,
            "candidate_frame": str(frame_path),
        })
        return

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    faces = detect_faces(cv2, gray)

    if len(faces) != 1:
        write_json(SHARED / "MIM_DAVE_FACE_ENROLLMENT_STATUS.latest.json", {
            "packet_type": "mim-dave-face-enrollment-status-v1",
            "objective_id": OBJECTIVE_ID,
            "generated_at": generated_at,
            "status": "blocked_candidate_must_have_exactly_one_face",
            "success": False,
            "candidate_frame": str(frame_path),
            "detected_face_count": int(len(faces)),
            "next_recovery_action": "Capture a clearer single-person Dave frame before enrollment.",
        })
        return

    x, y, w, h = [int(v) for v in faces[0]]
    face = gray[y:y + h, x:x + w]
    face = cv2.resize(face, (160, 160))

    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    model_path = MODEL_DIR / "dave_lbph_face_model.yml"
    crop_path = MODEL_DIR / "dave_face_enrollment_crop.jpg"
    cv2.imwrite(str(crop_path), face)

    recognizer = cv2.face.LBPHFaceRecognizer_create()
    recognizer.train([face], np.array([1], dtype=np.int32))
    recognizer.write(str(model_path))

    enrollment = {
        "packet_type": "mim-dave-face-enrollment-status-v1",
        "objective_id": OBJECTIVE_ID,
        "generated_at": generated_at,
        "status": "completed_with_single_confirmed_candidate",
        "success": True,
        "human_name": "Dave",
        "human_role": "primary_operator",
        "operator_consent_basis": "operator asked Codex/MIM to begin human identity binding after fresh face evidence was shown",
        "source_frame": str(frame_path),
        "face_box": {"x": x, "y": y, "w": w, "h": h},
        "model_path": str(model_path),
        "crop_path": str(crop_path),
        "recognizer": "opencv_lbph",
        "truth_rule": "This enrolls Dave from the confirmed current lab context; future matches still require confidence evidence.",
    }
    write_json(SHARED / "MIM_DAVE_FACE_ENROLLMENT_STATUS.latest.json", enrollment)

    registry_path = SHARED / "MIM_HUMAN_IDENTITY_REGISTRY.latest.json"
    registry = load_json(registry_path)
    humans = registry.setdefault("humans", [])
    dave = None
    for human in humans:
        if str(human.get("name", "")).lower() == "dave":
            dave = human
            break
    if dave is None:
        dave = {"name": "Dave", "roles": ["primary_operator"]}
        humans.append(dave)
    dave["face_recognition"] = {
        "enrolled": True,
        "current_visual_match": False,
        "confidence": None,
        "model_path": str(model_path),
        "enrollment_crop_path": str(crop_path),
        "evidence_artifact": "runtime/shared/MIM_DAVE_FACE_ENROLLMENT_STATUS.latest.json",
        "status": "enrolled_pending_fresh_match",
    }
    registry["status"] = "face_enrollment_bound_pending_fresh_match"
    registry["generated_at"] = generated_at
    registry["success_claimed"] = False
    write_json(registry_path, registry)

    print(json.dumps(enrollment, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
