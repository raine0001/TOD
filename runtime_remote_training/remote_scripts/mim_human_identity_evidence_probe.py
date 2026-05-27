#!/usr/bin/env python3
"""Publish fresh MIM human presence, face, and voice recognition evidence."""

from __future__ import annotations

import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
from typing import Any


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"
CAPTURE_DIR = SHARED / "human_identity_captures"
OBJECTIVE_ID = "MIM-HUMAN-INTERACTION-V1"


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def has_module(name: str) -> bool:
    try:
        return importlib.util.find_spec(name) is not None
    except ModuleNotFoundError:
        return False


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def tail_jsonl(path: Path, limit: int = 12) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[-limit:]
    rows: list[dict[str, Any]] = []
    for line in lines:
        try:
            rows.append(json.loads(line))
        except Exception:
            rows.append({"raw": line[:500], "parse_error": True})
    return rows


def find_enrollment_candidates() -> list[str]:
    names = [
        "face_memory.json",
        "MIM_HUMAN_IDENTITY_REGISTRY.latest.json",
        "MIM_FACE_ENROLLMENT.latest.json",
        "MIM_FACE_RECOGNITION_STATUS.latest.json",
    ]
    roots = [ROOT, SHARED, ROOT / "runtime", ROOT / "data", ROOT / "memory"]
    found: list[str] = []
    for root in roots:
        if not root.exists():
            continue
        for name in names:
            p = root / name
            if p.exists():
                found.append(str(p))
    return sorted(set(found))


def dave_face_model_path() -> Path:
    return SHARED / "human_identity_models" / "dave_lbph_face_model.yml"


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def inspect_cameras(modules: dict[str, bool]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    devices = ["/dev/video0", "/dev/video1", "/dev/video2", "/dev/video3"]
    inspections: list[dict[str, Any]] = []
    summary: dict[str, Any] = {
        "fresh_frame_count": 0,
        "max_face_count": None,
        "max_person_count": None,
        "best_human_count": "unknown",
        "best_human_count_basis": "no fresh detector evidence",
    }
    if not modules.get("cv2"):
        for device in devices:
            inspections.append({
                "device": device,
                "exists": os.path.exists(device),
                "openable": None,
                "fresh_frame": False,
                "blocked": True,
                "reason_code": "cv2_not_installed",
            })
        return inspections, summary

    import cv2  # type: ignore

    CAPTURE_DIR.mkdir(parents=True, exist_ok=True)
    def detect_faces(gray: Any) -> list[tuple[int, int, int, int]]:
        faces: list[tuple[int, int, int, int]] = []
        if face_cascade is not None:
            faces.extend([(int(x), int(y), int(w), int(h)) for x, y, w, h in face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(40, 40))])
        if profile_cascade is not None:
            faces.extend([(int(x), int(y), int(w), int(h)) for x, y, w, h in profile_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(40, 40))])
            flipped = cv2.flip(gray, 1)
            width = gray.shape[1]
            for fx, fy, fw, fh in profile_cascade.detectMultiScale(flipped, scaleFactor=1.1, minNeighbors=4, minSize=(40, 40)):
                faces.append((width - int(fx) - int(fw), int(fy), int(fw), int(fh)))
        return faces

    face_cascade = None
    profile_cascade = None
    face_cascade_path = getattr(cv2, "data", None)
    if face_cascade_path is not None:
        cascade_file = Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml"
        if cascade_file.exists():
            face_cascade = cv2.CascadeClassifier(str(cascade_file))
        profile_file = Path(cv2.data.haarcascades) / "haarcascade_profileface.xml"
        if profile_file.exists():
            profile_cascade = cv2.CascadeClassifier(str(profile_file))

    hog = None
    try:
        hog = cv2.HOGDescriptor()
        hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())
    except Exception:
        hog = None

    face_counts: list[int] = []
    person_counts: list[int] = []
    stamp = now_utc().replace(":", "").replace("-", "")
    for device in devices:
        entry: dict[str, Any] = {
            "device": device,
            "exists": os.path.exists(device),
            "openable": False,
            "fresh_frame": False,
            "frame_path": None,
            "face_detector": "opencv_haar_frontal_profile" if face_cascade is not None else None,
            "face_count": None,
            "person_detector": "opencv_hog" if hog is not None else None,
            "person_count": None,
            "error": None,
        }
        if not entry["exists"]:
            entry["error"] = "device_path_missing"
            inspections.append(entry)
            continue

        try:
            index = int(device.replace("/dev/video", ""))
            cap = cv2.VideoCapture(index, cv2.CAP_V4L2)
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
            entry["openable"] = bool(cap.isOpened())
            frame = None
            ok = False
            for _ in range(5):
                ok, frame = cap.read()
                if ok and frame is not None:
                    break
            cap.release()
            if not ok or frame is None:
                entry["error"] = "openable_but_no_frame" if entry["openable"] else "camera_not_openable"
                inspections.append(entry)
                continue

            entry["fresh_frame"] = True
            summary["fresh_frame_count"] += 1
            frame_path = CAPTURE_DIR / f"{stamp}_{Path(device).name}.jpg"
            cv2.imwrite(str(frame_path), frame)
            entry["frame_path"] = str(frame_path)
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

            if face_cascade is not None:
                faces = detect_faces(gray)
                entry["face_count"] = int(len(faces))
                entry["face_boxes"] = [{"x": int(x), "y": int(y), "w": int(w), "h": int(h)} for x, y, w, h in faces]
                face_counts.append(int(len(faces)))

            if hog is not None:
                rects, _weights = hog.detectMultiScale(frame, winStride=(8, 8), padding=(16, 16), scale=1.05)
                entry["person_count"] = int(len(rects))
                person_counts.append(int(len(rects)))
        except Exception as exc:
            entry["error"] = f"{type(exc).__name__}: {exc}"
        inspections.append(entry)

    if face_counts:
        summary["max_face_count"] = max(face_counts)
    if person_counts:
        summary["max_person_count"] = max(person_counts)
    candidates = [v for v in [summary["max_face_count"], summary["max_person_count"]] if isinstance(v, int)]
    if candidates:
        summary["best_human_count"] = max(candidates)
        summary["best_human_count_basis"] = "max(face_count, person_count) from fresh camera frames"
    return inspections, summary


def has_opencv_face_recognizer(modules: dict[str, bool]) -> bool:
    if not modules.get("cv2"):
        return False
    try:
        import cv2  # type: ignore

        return bool(hasattr(cv2, "face") and hasattr(cv2.face, "LBPHFaceRecognizer_create"))
    except Exception:
        return False


def main() -> None:
    generated_at = now_utc()
    modules = {
        name: has_module(name)
        for name in [
            "cv2",
            "numpy",
            "face_recognition",
            "speechbrain",
            "resemblyzer",
            "pyannote.audio",
            "sklearn",
            "whisper",
        ]
    }
    cameras, camera_summary = inspect_cameras(modules)
    opencv_face_recognizer_ready = has_opencv_face_recognizer(modules)
    enrollments = find_enrollment_candidates()
    transcripts = tail_jsonl(SHARED / "MIM_VOICE_TRANSCRIPT_LOG.latest.jsonl")

    person_status = {
        "packet_type": "mim-lab-person-detection-status-v1",
        "objective_id": OBJECTIVE_ID,
        "generated_at": generated_at,
        "status": "fresh_evidence_published" if camera_summary["fresh_frame_count"] else "blocked_no_fresh_camera_frame",
        "success": bool(camera_summary["fresh_frame_count"]),
        "human_count": camera_summary["best_human_count"],
        "human_count_basis": camera_summary["best_human_count_basis"],
        "camera_summary": camera_summary,
        "camera_inspections": cameras,
        "policy_hint": "If human_count >= 2, MIM should require an explicit MIM-directed prompt before joining conversation.",
    }

    face_runtime_ready = modules["face_recognition"] or opencv_face_recognizer_ready
    face_count = camera_summary.get("max_face_count")
    face_frame_candidates = [
        str(item.get("frame_path"))
        for item in cameras
        if item.get("fresh_frame") and isinstance(item.get("face_count"), int) and item.get("face_count") > 0 and item.get("frame_path")
    ]
    recognized_humans: list[dict[str, Any]] = []
    dave_confidence: Any = "memory_only_not_face_verified"
    dave_model = dave_face_model_path()
    if opencv_face_recognizer_ready and dave_model.exists():
        try:
            import cv2  # type: ignore

            recognizer = cv2.face.LBPHFaceRecognizer_create()
            recognizer.read(str(dave_model))
            for item in cameras:
                if not item.get("fresh_frame") or not item.get("frame_path") or item.get("face_count") != 1:
                    continue
                image = cv2.imread(str(item["frame_path"]))
                if image is None:
                    continue
                gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
                cascade_file = Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml"
                cascade = cv2.CascadeClassifier(str(cascade_file))
                faces = [(int(x), int(y), int(w), int(h)) for x, y, w, h in cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(40, 40))]
                profile_file = Path(cv2.data.haarcascades) / "haarcascade_profileface.xml"
                if profile_file.exists():
                    profile_cascade = cv2.CascadeClassifier(str(profile_file))
                    faces.extend([(int(x), int(y), int(w), int(h)) for x, y, w, h in profile_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(40, 40))])
                    flipped = cv2.flip(gray, 1)
                    width = gray.shape[1]
                    for fx, fy, fw, fh in profile_cascade.detectMultiScale(flipped, scaleFactor=1.1, minNeighbors=4, minSize=(40, 40)):
                        faces.append((width - int(fx) - int(fw), int(fy), int(fw), int(fh)))
                if len(faces) != 1:
                    continue
                x, y, w, h = [int(v) for v in faces[0]]
                face = cv2.resize(gray[y:y + h, x:x + w], (160, 160))
                label, confidence = recognizer.predict(face)
                dave_confidence = float(confidence)
                if int(label) == 1 and float(confidence) <= 75.0:
                    recognized_humans.append({
                        "name": "Dave",
                        "method": "opencv_lbph",
                        "confidence": float(confidence),
                        "confidence_rule": "lower_is_better_match; threshold <= 75",
                        "frame_path": item["frame_path"],
                    })
        except Exception as exc:
            dave_confidence = f"recognition_error:{type(exc).__name__}:{exc}"

    face_success = bool(recognized_humans)
    pc_face_status = load_json(SHARED / "MIM_PC_LAB_OBSERVER_FACE_STATUS.latest.json")
    pc_face_success = bool(pc_face_status.get("success"))
    if pc_face_success and not any(item.get("name") == "Dave" for item in recognized_humans):
        recognized_humans.append({
            "name": "Dave",
            "method": "pc_lab_observer_bridge",
            "confidence": pc_face_status.get("operator_confirmed_pc_crop_match", {}).get("confidence"),
            "evidence_artifact": "runtime/shared/MIM_PC_LAB_OBSERVER_FACE_STATUS.latest.json",
        })
        face_success = True
    face_status = {
        "packet_type": "mim-face-recognition-status-v1",
        "objective_id": OBJECTIVE_ID,
        "generated_at": generated_at,
        "status": "recognized_dave_with_fresh_face_evidence" if face_success else ("blocked_missing_face_recognition_runtime" if not face_runtime_ready else "blocked_no_verified_face_enrollment"),
        "success": face_success,
        "runtime": {
            "face_recognition_installed": face_runtime_ready,
            "face_recognition_package_installed": modules["face_recognition"],
            "opencv_lbph_face_recognizer_installed": opencv_face_recognizer_ready,
            "opencv_installed": modules["cv2"],
            "fresh_face_detector_count": face_count,
        },
        "identity_registry_candidates": enrollments,
        "known_humans_from_memory": ["Dave"],
        "recognition_result": {
            "recognized_humans": recognized_humans,
            "unrecognized_face_count": face_count if isinstance(face_count, int) else "unknown",
            "dave_identity_confidence": dave_confidence,
        },
        "enrollment_candidates": {
            "candidate_face_frame_paths": face_frame_candidates,
            "candidate_status": "unverified_do_not_treat_as_dave_until_confirmed",
            "reason": "A face was detected in a fresh lab frame, but recognition requires a verified enrollment binding.",
        },
        "next_recovery_action": "Install/bind face recognition runtime and enroll one verified Dave face image from a confirmed lab greeting frame.",
    }
    if face_success:
        face_status["next_recovery_action"] = "Wire this fresh Dave face-recognition evidence into greeting and conversation policy."
    elif face_runtime_ready and dave_model.exists():
        face_status["status"] = "face_runtime_and_dave_model_bound_no_current_match"
        face_status["next_recovery_action"] = "Capture a clearer current Dave face frame or lower confidence only after repeated verified matches."
    elif face_runtime_ready and enrollments:
        face_status["status"] = "blocked_no_verified_face_embedding_for_dave"
        face_status["next_recovery_action"] = "Inspect existing registry candidates and bind a verified Dave face embedding before claiming recognition."

    voice_enrollment = load_json(SHARED / "MIM_DAVE_VOICE_ENROLLMENT_STATUS.latest.json")
    voiceprint_path = voice_enrollment.get("voiceprint_path")
    if not voiceprint_path and (SHARED / "human_identity_models" / "dave_voiceprint_v1.json").exists():
        voiceprint_path = str(SHARED / "human_identity_models" / "dave_voiceprint_v1.json")
    local_voiceprint_bound = bool(voiceprint_path and Path(str(voiceprint_path)).exists())
    speaker_runtime = modules["speechbrain"] or modules["resemblyzer"] or modules["pyannote.audio"] or local_voiceprint_bound
    voice_verified = bool(voice_enrollment.get("verified"))
    if voice_verified:
        voice_status_name = "recognized_dave_with_voiceprint_evidence"
    elif local_voiceprint_bound:
        voice_status_name = "voiceprint_bound_but_verification_quality_blocked"
    else:
        voice_status_name = "blocked_missing_speaker_recognition_runtime"
    voice_status = {
        "packet_type": "mim-voice-recognition-status-v1",
        "objective_id": OBJECTIVE_ID,
        "generated_at": generated_at,
        "status": voice_status_name if speaker_runtime else "blocked_missing_speaker_recognition_runtime",
        "success": voice_verified,
        "runtime": {
            "speechbrain_installed": modules["speechbrain"],
            "resemblyzer_installed": modules["resemblyzer"],
            "pyannote_audio_installed": modules["pyannote.audio"],
            "whisper_installed": modules["whisper"],
            "local_spectral_voiceprint_bound": local_voiceprint_bound,
        },
        "voice_enrollment": voice_enrollment,
        "transcript_log": {
            "path": str(SHARED / "MIM_VOICE_TRANSCRIPT_LOG.latest.jsonl"),
            "exists": (SHARED / "MIM_VOICE_TRANSCRIPT_LOG.latest.jsonl").exists(),
            "recent_entry_count": len(transcripts),
            "recent_entries": transcripts,
        },
        "recognition_result": {
            "recognized_speakers": [{"name": "Dave", "method": "local_spectral_voiceprint_v1"}] if voice_verified else [],
            "dave_identity_confidence": voice_enrollment.get("similarity") if local_voiceprint_bound else "conversation_context_only_not_voice_verified",
        },
        "next_recovery_action": "Recapture Dave voice with higher speech level on the FDUCE/PipeWire source, then rerun evidence probe." if local_voiceprint_bound else "Bind speaker embedding runtime and enroll Dave with a confirmed short voice sample; until then, transcripts are hearing evidence, not speaker identity evidence.",
    }

    blockers = []
    if not face_success:
        blockers.append(face_status["status"])
    if not voice_verified:
        blockers.append(voice_status["status"])

    human_status = {
        "packet_type": "mim-human-interaction-v1-status",
        "objective_id": OBJECTIVE_ID,
        "generated_at": generated_at,
        "phase": "fresh_person_face_voice_evidence_published",
        "percent_complete": 65 if face_success and speaker_runtime else (50 if face_success else (35 if camera_summary["fresh_frame_count"] else 30)),
        "success": bool(face_success and voice_verified),
        "evidence": {
            "person_detection": "runtime/shared/MIM_LAB_PERSON_DETECTION_STATUS.latest.json",
            "face_recognition": "runtime/shared/MIM_FACE_RECOGNITION_STATUS.latest.json",
            "voice_recognition": "runtime/shared/MIM_VOICE_RECOGNITION_STATUS.latest.json",
        },
        "current_capability": {
            "fresh_person_count_available": bool(camera_summary["fresh_frame_count"]),
            "face_recognition_available": face_runtime_ready,
            "voice_recognition_available": speaker_runtime,
            "dave_known_by_memory": True,
            "dave_face_verified": face_success,
            "dave_voice_verified": voice_verified,
        },
        "blockers": blockers,
        "next_recovery_action": "Convert the fresh detector evidence into real identity recognition by binding/enrolling face and speaker models, then wire greeting policy to person entry events.",
    }

    write_json(SHARED / "MIM_LAB_PERSON_DETECTION_STATUS.latest.json", person_status)
    write_json(SHARED / "MIM_FACE_RECOGNITION_STATUS.latest.json", face_status)
    write_json(SHARED / "MIM_VOICE_RECOGNITION_STATUS.latest.json", voice_status)
    write_json(SHARED / "MIM_HUMAN_INTERACTION_V1_STATUS.latest.json", human_status)
    print(json.dumps({
        "generated_at": generated_at,
        "person_status": person_status["status"],
        "human_count": person_status["human_count"],
        "face_status": face_status["status"],
        "voice_status": voice_status["status"],
        "written": list(human_status["evidence"].values()) + ["runtime/shared/MIM_HUMAN_INTERACTION_V1_STATUS.latest.json"],
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
