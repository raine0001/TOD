#!/usr/bin/env python3
"""Process a PC-uploaded Dave voice sample into MIM voice recognition evidence."""

from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"
MODEL_DIR = SHARED / "human_identity_models"
OBJECTIVE_ID = "MIM-HUMAN-IDENTITY-BINDING-V1"


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, payload: dict) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> None:
    sys.path.insert(0, str(ROOT / "scripts"))
    import mim_enroll_dave_voice_single_pass as single  # type: ignore

    if len(sys.argv) < 2:
        raise SystemExit("usage: mim_process_pc_voice_enrollment.py /path/to/sample.wav")
    sample_path = Path(sys.argv[1])
    generated_at = now_utc()
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    status = {
        "packet_type": "mim-dave-voice-enrollment-status-v1",
        "objective_id": OBJECTIVE_ID,
        "generated_at": generated_at,
        "human_name": "Dave",
        "source": "operator_pc_microphone_bridge",
        "source_wav": str(sample_path),
        "success": False,
    }
    try:
        raw = single.read_wav(sample_path)
        active, active_meta = single.active_audio(raw)
        if active.size < int(single.SAMPLE_RATE * 1.6):
            raise ValueError(f"not_enough_active_speech:{active_meta}")
        midpoint = active.size // 2
        first = active[:midpoint]
        second = active[midpoint:]
        enroll_path = MODEL_DIR / "dave_voice_enrollment.wav"
        verify_path = MODEL_DIR / "dave_voice_verification.wav"
        voiceprint_path = MODEL_DIR / "dave_voiceprint_v1.json"
        single.write_wav(enroll_path, first)
        single.write_wav(verify_path, second)
        first_features = single.features(first)
        second_features = single.features(second)
        similarity = single.cosine(first_features["vector"], second_features["vector"])
        verified = bool(first_features["quality_ok"] and second_features["quality_ok"] and similarity >= 0.86)
        voiceprint = {
            "packet_type": "mim-dave-voiceprint-v1",
            "objective_id": OBJECTIVE_ID,
            "generated_at": generated_at,
            "human_name": "Dave",
            "method": "pc_microphone_bridge_local_spectral_voiceprint_v1",
            "sample_rate": single.SAMPLE_RATE,
            "source_wav": str(sample_path),
            "enrollment_wav": str(enroll_path),
            "verification_wav": str(verify_path),
            "active_audio": active_meta,
            "enrollment_features": first_features,
            "verification_features": second_features,
            "similarity": similarity,
            "threshold": 0.86,
            "verified": verified,
            "truth_rule": "PC microphone bridge voiceprint is Dave-likely identity evidence for MIM interaction, not high-security authentication.",
        }
        write_json(voiceprint_path, voiceprint)
        status.update({
            "status": "completed_verified_voiceprint" if verified else "pc_voiceprint_enrolled_but_quality_or_similarity_blocked",
            "success": verified,
            "verified": verified,
            "similarity": similarity,
            "voiceprint_path": str(voiceprint_path),
            "active_audio": active_meta,
            "enrollment_features_summary": {
                "duration_s": first_features["duration_s"],
                "rms": first_features["rms"],
                "peak": first_features["peak"],
                "speech_ratio": first_features["speech_ratio"],
                "quality_ok": first_features["quality_ok"],
            },
            "verification_features_summary": {
                "duration_s": second_features["duration_s"],
                "rms": second_features["rms"],
                "peak": second_features["peak"],
                "speech_ratio": second_features["speech_ratio"],
                "quality_ok": second_features["quality_ok"],
            },
            "next_recovery_action": "" if verified else "Recapture from PC microphone while speaking continuously and closer to the mic.",
        })
    except Exception as exc:
        status.update({
            "status": "blocked_pc_voice_processing_failed",
            "error": f"{type(exc).__name__}: {exc}",
            "verified": False,
            "next_recovery_action": "Recapture PC microphone sample with continuous speech.",
        })
    write_json(SHARED / "MIM_DAVE_VOICE_ENROLLMENT_STATUS.latest.json", status)

    registry_path = SHARED / "MIM_HUMAN_IDENTITY_REGISTRY.latest.json"
    registry = load_json(registry_path)
    humans = registry.setdefault("humans", [])
    dave = next((h for h in humans if str(h.get("name", "")).lower() == "dave"), None)
    if dave is None:
        dave = {"name": "Dave", "roles": ["primary_operator"]}
        humans.append(dave)
    dave["voice_recognition"] = {
        "enrolled": bool(status.get("voiceprint_path")),
        "current_voice_match": bool(status.get("verified")),
        "similarity": status.get("similarity"),
        "method": "pc_microphone_bridge_local_spectral_voiceprint_v1",
        "model_path": status.get("voiceprint_path"),
        "evidence_artifact": "runtime/shared/MIM_DAVE_VOICE_ENROLLMENT_STATUS.latest.json",
        "status": status["status"],
    }
    registry["generated_at"] = generated_at
    registry["status"] = "face_and_voice_binding_started"
    write_json(registry_path, registry)
    print(json.dumps(status, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
