#!/usr/bin/env python3
"""Enroll and verify a lightweight Dave voiceprint for MIM."""

from __future__ import annotations

import datetime as dt
import json
import math
import subprocess
import wave
from pathlib import Path
from typing import Any

import numpy as np  # type: ignore


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"
MODEL_DIR = SHARED / "human_identity_models"
OBJECTIVE_ID = "MIM-HUMAN-IDENTITY-BINDING-V1"
AUDIO_DEVICES = [
    "pipewire-target:81",
    "dsnoop:CARD=AUDIO,DEV=0",
    "plughw:CARD=AUDIO,DEV=0",
    "dsnoop:CARD=S600,DEV=0",
    "plughw:CARD=S600,DEV=0",
    "dsnoop:CARD=C960,DEV=0",
    "plughw:CARD=C960,DEV=0",
]
SAMPLE_RATE = 16000


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


def say(text: str) -> None:
    subprocess.run(["spd-say", "-w", text], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def record_with_device(path: Path, seconds: int, device: str) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    if device.startswith("pipewire-target:"):
        target = device.split(":", 1)[1]
        cmd = [
            "timeout",
            str(seconds + 1),
            "pw-record",
            "--target",
            target,
            "--rate",
            str(SAMPLE_RATE),
            "--channels",
            "1",
            "--format",
            "s16",
            str(path),
        ]
        accepted_returncodes = {0, 124}
    else:
        cmd = [
            "arecord",
            "-q",
            "-D",
            device,
            "-f",
            "S16_LE",
            "-r",
            str(SAMPLE_RATE),
            "-c",
            "1",
            "-d",
            str(seconds),
            str(path),
        ]
        accepted_returncodes = {0}
    started = now_utc()
    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    accepted = proc.returncode in accepted_returncodes and path.exists() and path.stat().st_size > 44
    return {
        "command": cmd,
        "device": device,
        "accepted": accepted,
        "started_at": started,
        "returncode": proc.returncode,
        "stderr": proc.stderr[-1000:],
        "path": str(path),
        "exists": path.exists(),
        "size": path.stat().st_size if path.exists() else 0,
    }


def record(path: Path, seconds: int) -> dict[str, Any]:
    attempts = []
    for device in AUDIO_DEVICES:
        result = record_with_device(path, seconds, device)
        attempts.append(result)
        if result.get("accepted"):
            return {**result, "attempts": list(attempts)}
    return {
        "returncode": attempts[-1]["returncode"] if attempts else 1,
        "exists": path.exists(),
        "size": path.stat().st_size if path.exists() else 0,
        "path": str(path),
        "attempts": attempts,
        "stderr": attempts[-1].get("stderr", "") if attempts else "no_devices_attempted",
    }


def read_wav_mono(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as wf:
        frames = wf.readframes(wf.getnframes())
        data = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
        if wf.getnchannels() > 1:
            data = data.reshape((-1, wf.getnchannels())).mean(axis=1)
    return data


def voice_features(path: Path) -> dict[str, Any]:
    data = read_wav_mono(path)
    if data.size == 0:
        raise ValueError("empty_wav")
    frame_len = max(400, int(SAMPLE_RATE * 0.05))
    frames = []
    for start in range(0, data.size - frame_len + 1, frame_len):
        frame = data[start:start + frame_len]
        frames.append((start, float(math.sqrt(float(np.mean(frame * frame))))))
    if frames:
        rms_values = np.array([r for _start, r in frames], dtype=np.float32)
        threshold = max(float(np.percentile(rms_values, 30)) * 2.5, 0.0018)
        active_chunks = [data[start:start + frame_len] for start, rms_v in frames if rms_v >= threshold]
        if active_chunks:
            active = np.concatenate(active_chunks)
        else:
            top_count = max(1, int(len(frames) * 0.2))
            top_starts = [start for start, _rms_v in sorted(frames, key=lambda item: item[1], reverse=True)[:top_count]]
            active = np.concatenate([data[start:start + frame_len] for start in sorted(top_starts)])
    else:
        threshold = 0.0
        active = data
    active_duration_s = float(active.size / SAMPLE_RATE)
    if active.size >= int(SAMPLE_RATE * 0.35):
        data = active
    abs_data = np.abs(data)
    rms = float(math.sqrt(float(np.mean(data * data))))
    peak = float(np.max(abs_data))
    zcr = float(np.mean(np.abs(np.diff(np.signbit(data).astype(np.int8)))))
    speech_ratio = float(np.mean(abs_data > 0.012))

    n = min(data.size, SAMPLE_RATE * 8)
    segment = data[:n]
    if segment.size < 1024:
        raise ValueError("wav_too_short")
    window = np.hanning(segment.size)
    spectrum = np.abs(np.fft.rfft(segment * window))
    freqs = np.fft.rfftfreq(segment.size, d=1.0 / SAMPLE_RATE)
    total = float(np.sum(spectrum) + 1e-9)
    centroid = float(np.sum(freqs * spectrum) / total)
    cumulative = np.cumsum(spectrum) / total
    rolloff = float(freqs[int(np.searchsorted(cumulative, 0.85))])

    bands = []
    for low, high in [(80, 250), (250, 500), (500, 1000), (1000, 2000), (2000, 4000), (4000, 7600)]:
        mask = (freqs >= low) & (freqs < high)
        bands.append(float(np.sum(spectrum[mask]) / total))

    vector = np.array([rms, peak, zcr, speech_ratio, centroid / 4000.0, rolloff / 8000.0] + bands, dtype=np.float32)
    norm = float(np.linalg.norm(vector) + 1e-9)
    vector = vector / norm
    return {
        "rms": rms,
        "peak": peak,
        "zcr": zcr,
        "speech_ratio": speech_ratio,
        "centroid_hz": centroid,
        "rolloff_hz": rolloff,
        "band_energy_ratios": bands,
        "vector": [float(v) for v in vector.tolist()],
        "active_duration_s": active_duration_s,
        "active_frame_threshold": threshold,
        "quality_ok": bool(active_duration_s >= 0.35 and rms >= 0.002 and peak >= 0.012 and speech_ratio >= 0.002 and peak < 0.98),
    }


def cosine(a: list[float], b: list[float]) -> float:
    va = np.array(a, dtype=np.float32)
    vb = np.array(b, dtype=np.float32)
    return float(np.dot(va, vb) / ((np.linalg.norm(va) * np.linalg.norm(vb)) + 1e-9))


def main() -> None:
    generated_at = now_utc()
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    enroll_wav = MODEL_DIR / "dave_voice_enrollment.wav"
    verify_wav = MODEL_DIR / "dave_voice_verification.wav"
    voiceprint_path = MODEL_DIR / "dave_voiceprint_v1.json"

    subprocess.run(["amixer", "-c", "AUDIO", "sset", "Mic", "100%"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    say("Dave, voice enrollment starting. Recording now. Please say clearly: MIM, this is Dave, your primary operator.")
    enroll_capture = record(enroll_wav, 8)
    say("Thank you. Verification pass. Recording now. Please say clearly: MIM, confirm this is Dave.")
    verify_capture = record(verify_wav, 8)

    try:
        enroll_features = voice_features(enroll_wav)
        verify_features = voice_features(verify_wav)
        similarity = cosine(enroll_features["vector"], verify_features["vector"])
        quality_ok = bool(enroll_features["quality_ok"] and verify_features["quality_ok"])
        verified = bool(quality_ok and similarity >= 0.86)
        status = "completed_verified_voiceprint" if verified else "enrolled_pending_better_verification_sample"
        voiceprint = {
            "packet_type": "mim-dave-voiceprint-v1",
            "objective_id": OBJECTIVE_ID,
            "generated_at": generated_at,
            "human_name": "Dave",
            "method": "local_spectral_voiceprint_v1",
            "devices_attempted": AUDIO_DEVICES,
            "sample_rate": SAMPLE_RATE,
            "enrollment_wav": str(enroll_wav),
            "verification_wav": str(verify_wav),
            "enrollment_features": enroll_features,
            "verification_features": verify_features,
            "similarity": similarity,
            "threshold": 0.86,
            "verified": verified,
            "truth_rule": "This is a lightweight local speaker signature; it should gate Dave-likely identity, not high-security authentication.",
        }
        write_json(voiceprint_path, voiceprint)
    except Exception as exc:
        status = "blocked_audio_feature_extraction_failed"
        verified = False
        similarity = None
        voiceprint = {
            "error": f"{type(exc).__name__}: {exc}",
            "enrollment_capture": enroll_capture,
            "verification_capture": verify_capture,
        }

    artifact = {
        "packet_type": "mim-dave-voice-enrollment-status-v1",
        "objective_id": OBJECTIVE_ID,
        "generated_at": generated_at,
        "status": status,
        "success": verified,
        "human_name": "Dave",
        "devices_attempted": AUDIO_DEVICES,
        "enrollment_capture": enroll_capture,
        "verification_capture": verify_capture,
        "voiceprint_path": str(voiceprint_path) if voiceprint_path.exists() else None,
        "similarity": similarity,
        "verified": verified,
        "next_recovery_action": "Use this voiceprint for Dave-likely matching; recapture in quiet lab conditions if verification failed.",
    }
    write_json(SHARED / "MIM_DAVE_VOICE_ENROLLMENT_STATUS.latest.json", artifact)

    registry_path = SHARED / "MIM_HUMAN_IDENTITY_REGISTRY.latest.json"
    registry = load_json(registry_path)
    humans = registry.setdefault("humans", [])
    dave = next((h for h in humans if str(h.get("name", "")).lower() == "dave"), None)
    if dave is None:
        dave = {"name": "Dave", "roles": ["primary_operator"]}
        humans.append(dave)
    dave["voice_recognition"] = {
        "enrolled": voiceprint_path.exists(),
        "current_voice_match": verified,
        "similarity": similarity,
        "method": "local_spectral_voiceprint_v1",
        "model_path": str(voiceprint_path) if voiceprint_path.exists() else None,
        "evidence_artifact": "runtime/shared/MIM_DAVE_VOICE_ENROLLMENT_STATUS.latest.json",
        "status": status,
    }
    registry["status"] = "face_and_voice_binding_started"
    registry["generated_at"] = generated_at
    write_json(registry_path, registry)
    print(json.dumps(artifact, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
