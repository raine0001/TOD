#!/usr/bin/env python3
"""Single-pass Dave voice enrollment: record once, split active speech, verify halves."""

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
SAMPLE_RATE = 16000
DEVICE = "pipewire-target:81"
AUDIO_DEVICES = [
    "plughw:CARD=AUDIO,DEV=0",
    "dsnoop:CARD=AUDIO,DEV=0",
    "plughw:CARD=S600,DEV=0",
    "dsnoop:CARD=S600,DEV=0",
    "plughw:CARD=C960,DEV=0",
    "dsnoop:CARD=C960,DEV=0",
    "pipewire-target:81",
]


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8-sig"))


def say(text: str) -> None:
    subprocess.run(
        ["timeout", "6", "spd-say", text],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


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
    return {
        "device": DEVICE,
        "command": cmd,
        "started_at": started,
        "returncode": proc.returncode,
        "accepted": proc.returncode in accepted_returncodes and path.exists() and path.stat().st_size > 44,
        "stderr": proc.stderr[-1000:],
        "path": str(path),
        "exists": path.exists(),
        "size": path.stat().st_size if path.exists() else 0,
    }


def record(path: Path, seconds: int) -> dict[str, Any]:
    subprocess.run(["amixer", "-c", "AUDIO", "sset", "Mic", "100%"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    attempts = []
    for device in AUDIO_DEVICES:
        result = record_with_device(path, seconds, device)
        result["device"] = device
        attempts.append(result)
        if result.get("accepted"):
            return {**result, "attempts": attempts}
    fallback = attempts[-1] if attempts else {}
    return {
        "device": "",
        "command": [],
        "started_at": now_utc(),
        "returncode": fallback.get("returncode"),
        "accepted": False,
        "stderr": fallback.get("stderr") or "no_audio_devices_attempted",
        "path": str(path),
        "exists": path.exists(),
        "size": path.stat().st_size if path.exists() else 0,
        "attempts": attempts,
    }


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as wf:
        data = np.frombuffer(wf.readframes(wf.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
        if wf.getnchannels() > 1:
            data = data.reshape((-1, wf.getnchannels())).mean(axis=1)
    return data


def write_wav(path: Path, data: np.ndarray) -> None:
    clipped = np.clip(data, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm.tobytes())


def active_audio(data: np.ndarray) -> tuple[np.ndarray, dict[str, Any]]:
    frame_len = int(SAMPLE_RATE * 0.05)
    frames = []
    for start in range(0, data.size - frame_len + 1, frame_len):
        frame = data[start:start + frame_len]
        frames.append((start, float(math.sqrt(float(np.mean(frame * frame))))))
    if not frames:
        return data, {"active_duration_s": float(data.size / SAMPLE_RATE), "threshold": 0}
    rms_values = np.array([r for _start, r in frames], dtype=np.float32)
    threshold = max(float(np.percentile(rms_values, 35)) * 2.2, 0.0018)
    active_chunks = [data[start:start + frame_len] for start, rms in frames if rms >= threshold]
    active = np.concatenate(active_chunks) if active_chunks else np.array([], dtype=np.float32)
    return active, {
        "active_duration_s": float(active.size / SAMPLE_RATE),
        "threshold": threshold,
        "frame_count": len(frames),
        "active_frame_count": len(active_chunks),
        "recording_rms": float(math.sqrt(float(np.mean(data * data)))) if data.size else 0.0,
        "recording_peak": float(np.max(np.abs(data))) if data.size else 0.0,
    }


def features(data: np.ndarray) -> dict[str, Any]:
    if data.size < int(SAMPLE_RATE * 0.25):
        raise ValueError("not_enough_active_speech")
    abs_data = np.abs(data)
    rms = float(math.sqrt(float(np.mean(data * data))))
    peak = float(np.max(abs_data))
    zcr = float(np.mean(np.abs(np.diff(np.signbit(data).astype(np.int8)))))
    speech_ratio = float(np.mean(abs_data > 0.006))
    n = min(data.size, SAMPLE_RATE * 6)
    segment = data[:n]
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
    vector = vector / float(np.linalg.norm(vector) + 1e-9)
    return {
        "duration_s": float(data.size / SAMPLE_RATE),
        "rms": rms,
        "peak": peak,
        "zcr": zcr,
        "speech_ratio": speech_ratio,
        "centroid_hz": centroid,
        "rolloff_hz": rolloff,
        "band_energy_ratios": bands,
        "vector": [float(v) for v in vector.tolist()],
        "quality_ok": bool(data.size / SAMPLE_RATE >= 0.8 and rms >= 0.002 and peak >= 0.012 and speech_ratio >= 0.05),
    }


def cosine(a: list[float], b: list[float]) -> float:
    va = np.array(a, dtype=np.float32)
    vb = np.array(b, dtype=np.float32)
    return float(np.dot(va, vb) / ((np.linalg.norm(va) * np.linalg.norm(vb)) + 1e-9))


def main() -> None:
    generated_at = now_utc()
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    raw_path = MODEL_DIR / "dave_voice_single_pass.wav"
    enroll_path = MODEL_DIR / "dave_voice_enrollment.wav"
    verify_path = MODEL_DIR / "dave_voice_verification.wav"
    voiceprint_path = MODEL_DIR / "dave_voiceprint_v1.json"

    say("Dave, single pass voice enrollment. Recording now. Please say: MIM, this is Dave, your primary operator. MIM, confirm this is Dave. You can repeat it twice.")
    capture = record(raw_path, 14)
    status_payload: dict[str, Any] = {
        "packet_type": "mim-dave-voice-enrollment-status-v1",
        "objective_id": OBJECTIVE_ID,
        "generated_at": generated_at,
        "human_name": "Dave",
        "device": DEVICE,
        "capture": capture,
        "success": False,
    }

    try:
        data = read_wav(raw_path)
        active, active_meta = active_audio(data)
        midpoint = active.size // 2
        first = active[:midpoint]
        second = active[midpoint:]
        write_wav(enroll_path, first)
        write_wav(verify_path, second)
        first_features = features(first)
        second_features = features(second)
        similarity = cosine(first_features["vector"], second_features["vector"])
        verified = bool(first_features["quality_ok"] and second_features["quality_ok"] and similarity >= 0.86)
        voiceprint = {
            "packet_type": "mim-dave-voiceprint-v1",
            "objective_id": OBJECTIVE_ID,
            "generated_at": generated_at,
            "human_name": "Dave",
            "method": "local_spectral_voiceprint_v1_single_pass_split",
            "sample_rate": SAMPLE_RATE,
            "device": DEVICE,
            "raw_wav": str(raw_path),
            "enrollment_wav": str(enroll_path),
            "verification_wav": str(verify_path),
            "active_audio": active_meta,
            "enrollment_features": first_features,
            "verification_features": second_features,
            "similarity": similarity,
            "threshold": 0.86,
            "verified": verified,
            "truth_rule": "This is a lightweight local speaker signature; it should gate Dave-likely identity, not high-security authentication.",
        }
        write_json(voiceprint_path, voiceprint)
        status_payload.update({
            "status": "completed_verified_voiceprint" if verified else "enrolled_pending_better_single_pass_sample",
            "success": verified,
            "verified": verified,
            "similarity": similarity,
            "voiceprint_path": str(voiceprint_path),
            "active_audio": active_meta,
            "next_recovery_action": "" if verified else "Repeat single-pass enrollment while speaking continuously for the whole recording window.",
        })
    except Exception as exc:
        status_payload.update({
            "status": "blocked_single_pass_feature_extraction_failed",
            "error": f"{type(exc).__name__}: {exc}",
            "verified": False,
            "next_recovery_action": "Repeat single-pass enrollment while speaking continuously and closer to the selected mic.",
        })
    write_json(SHARED / "MIM_DAVE_VOICE_ENROLLMENT_STATUS.latest.json", status_payload)

    registry_path = SHARED / "MIM_HUMAN_IDENTITY_REGISTRY.latest.json"
    registry = load_json(registry_path)
    humans = registry.setdefault("humans", [])
    dave = next((h for h in humans if str(h.get("name", "")).lower() == "dave"), None)
    if dave is None:
        dave = {"name": "Dave", "roles": ["primary_operator"]}
        humans.append(dave)
    dave["voice_recognition"] = {
        "enrolled": bool(status_payload.get("voiceprint_path")),
        "current_voice_match": bool(status_payload.get("verified")),
        "similarity": status_payload.get("similarity"),
        "method": "local_spectral_voiceprint_v1_single_pass_split",
        "model_path": status_payload.get("voiceprint_path"),
        "evidence_artifact": "runtime/shared/MIM_DAVE_VOICE_ENROLLMENT_STATUS.latest.json",
        "status": status_payload["status"],
    }
    registry["generated_at"] = generated_at
    registry["status"] = "face_and_voice_binding_started"
    write_json(registry_path, registry)
    print(json.dumps(status_payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
