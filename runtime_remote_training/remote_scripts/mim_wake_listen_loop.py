#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import tempfile
import time
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from vosk import KaldiRecognizer, Model


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
MODEL_PATH = Path(os.environ.get("MIM_WAKE_VOSK_MODEL", ROOT / "runtime" / "models" / "vosk-model-small-en-us-0.15"))
STATUS_PATH = SHARED / "MIM_WAKE_LISTENER_STATUS.latest.json"
INTERACTION_PATH = SHARED / "MIM_WAKE_WORD_INTERACTION.latest.json"
MEMORY_PATH = SHARED / "MIM_HUMAN_INTERACTION_MEMORY.latest.json"

DEFAULT_DEVICES = [
    "plughw:0,0",
    "plughw:2,0",
    "plughw:3,0",
    "plughw:3,2",
    "default",
]

WAKE_PATTERNS = [
    re.compile(r"\b(hello|hey|okay|ok)\s+(mim|m\.?i\.?m\.?|ma'?am|mom|mem|meme|them)\b", re.I),
    re.compile(r"\bmim\b", re.I),
]


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(path)


def run_command(args: list[str], *, timeout: int = 10) -> dict[str, Any]:
    try:
        proc = subprocess.run(args, cwd=str(ROOT), text=True, capture_output=True, timeout=timeout, check=False)
        return {
            "command": args,
            "returncode": proc.returncode,
            "stdout": proc.stdout[-4000:],
            "stderr": proc.stderr[-4000:],
            "ok": proc.returncode == 0,
        }
    except Exception as exc:
        return {
            "command": args,
            "returncode": None,
            "stdout": "",
            "stderr": f"{type(exc).__name__}: {exc}",
            "ok": False,
        }


def configured_devices() -> list[str]:
    raw = os.environ.get("MIM_WAKE_AUDIO_DEVICE", "").strip()
    if raw:
        if ";" in raw:
            return [item.strip() for item in raw.split(";") if item.strip()]
        return [raw]
    return DEFAULT_DEVICES


def record_wav(device: str, output_path: Path, *, seconds: int) -> dict[str, Any]:
    return run_command(
        [
            "arecord",
            "-D",
            device,
            "-d",
            str(seconds),
            "-f",
            "S16_LE",
            "-r",
            "16000",
            "-c",
            "1",
            "-t",
            "wav",
            str(output_path),
        ],
        timeout=seconds + 5,
    )


def select_audio_device() -> tuple[str, dict[str, Any]]:
    attempts = []
    for device in configured_devices():
        with tempfile.NamedTemporaryFile(prefix="mim-wake-probe-", suffix=".wav", delete=False) as tmp:
            path = Path(tmp.name)
        try:
            probe = record_wav(device, path, seconds=1)
            attempts.append({"device": device, "ok": probe["ok"], "error": "" if probe["ok"] else probe.get("stderr") or probe.get("stdout")})
            if probe["ok"]:
                return device, {"attempts": attempts}
        finally:
            try:
                path.unlink(missing_ok=True)
            except Exception:
                pass
    return "", {"attempts": attempts}


def transcribe_wav(model: Model, wav_path: Path) -> dict[str, Any]:
    with wave.open(str(wav_path), "rb") as wav_file:
        if wav_file.getnchannels() != 1 or wav_file.getsampwidth() != 2 or wav_file.getframerate() != 16000:
            return {
                "ok": False,
                "text": "",
                "error": f"unsupported_wav_format channels={wav_file.getnchannels()} width={wav_file.getsampwidth()} rate={wav_file.getframerate()}",
            }
        recognizer = KaldiRecognizer(model, 16000)
        recognizer.SetWords(True)
        while True:
            data = wav_file.readframes(4000)
            if len(data) == 0:
                break
            recognizer.AcceptWaveform(data)
        result = json.loads(recognizer.FinalResult())
    text = str(result.get("text") or "").strip()
    return {"ok": True, "text": text, "raw_result": result, "error": ""}


def detect_wake(text: str) -> bool:
    normalized = re.sub(r"[^a-zA-Z0-9.' ]+", " ", text).strip().lower()
    return any(pattern.search(normalized) for pattern in WAKE_PATTERNS)


def speak(text: str) -> dict[str, Any]:
    return run_command(["spd-say", text], timeout=8)


def publish_wake_interaction(*, transcript: str, device: str, tts: dict[str, Any]) -> None:
    generated_at = now_iso()
    payload = {
        "packet_type": "mim-wake-word-interaction-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-LISTENING-AND-VOICE-PERSONA-V1",
        "owner": "MIM",
        "status": "completed_with_evidence" if tts["ok"] else "blocked_with_evidence",
        "success": bool(tts["ok"]),
        "wake_phrase_detected": True,
        "transcript": transcript,
        "audio_device": device,
        "response": {
            "mode": "voice_tts",
            "text": "Hey Dave. I heard you.",
            "tts_command": tts.get("command"),
            "tts_returncode": tts.get("returncode"),
            "tts_error": "" if tts["ok"] else tts.get("stderr") or tts.get("stdout") or "tts_failed",
        },
        "memory_update": {
            "human_name": "Dave",
            "human_role": "primary_operator",
            "interaction_type": "wake_word_voice",
            "last_interaction_time": generated_at,
        },
        "no_audio_retained": True,
    }
    write_json(INTERACTION_PATH, payload)
    write_json(
        MEMORY_PATH,
        {
            "packet_type": "mim-human-interaction-memory-v1",
            "generated_at": generated_at,
            "source": "mim_wake_listen_loop",
            "objective_id": "MIM-LISTENING-AND-VOICE-PERSONA-V1",
            "status": payload["status"],
            "success": payload["success"],
            "interaction": {
                "human_name": "Dave",
                "human_role": "primary_operator",
                "presence_trigger_source": "wake_word_stt",
                "presence_trigger_evidence": transcript,
                "interaction_mode": "voice_tts",
                "tts_message": payload["response"]["text"],
                "tts_command": tts.get("command"),
                "tts_dispatch_mode": "speech-dispatcher async queue; command success means utterance accepted",
                "tts_returncode": tts.get("returncode"),
                "tts_error": payload["response"]["tts_error"],
                "last_interaction_time": generated_at if tts["ok"] else None,
            },
            "memory_records": [
                {
                    "human_name": "Dave",
                    "remembered_fact": "Dave is MIM's primary operator.",
                    "source": "operator-provided objective context",
                    "confidence": "operator_asserted",
                    "updated_at": generated_at,
                },
                {
                    "human_name": "Dave",
                    "remembered_fact": "Dave can wake MIM by saying hello MIM.",
                    "source": "wake-word STT evidence",
                    "confidence": "observed",
                    "updated_at": generated_at,
                },
            ],
            "next_recovery_action": "" if tts["ok"] else "Repair speech-dispatcher or default audio output.",
        },
    )


def listen_once(model: Model, device: str, *, seconds: int) -> dict[str, Any]:
    with tempfile.NamedTemporaryFile(prefix="mim-wake-listen-", suffix=".wav", delete=False) as tmp:
        wav_path = Path(tmp.name)
    try:
        rec = record_wav(device, wav_path, seconds=seconds)
        if not rec["ok"]:
            return {
                "status": "blocked_with_evidence",
                "success": False,
                "audio_device": device,
                "transcript": "",
                "wake_phrase_detected": False,
                "error": rec.get("stderr") or rec.get("stdout") or "arecord_failed",
            }
        stt = transcribe_wav(model, wav_path)
        wake = bool(stt["ok"] and detect_wake(stt["text"]))
        tts = {"ok": True, "command": [], "returncode": 0, "stderr": "", "stdout": ""}
        if wake:
            tts = speak("Hey Dave. I heard you.")
            publish_wake_interaction(transcript=stt["text"], device=device, tts=tts)
        return {
            "status": "wake_detected" if wake else "listening",
            "success": True,
            "audio_device": device,
            "transcript": stt.get("text", ""),
            "wake_phrase_detected": wake,
            "stt_error": stt.get("error", ""),
            "tts_ok": tts["ok"] if wake else None,
            "no_audio_retained": True,
        }
    finally:
        try:
            wav_path.unlink(missing_ok=True)
        except Exception:
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--chunk-seconds", type=int, default=int(os.environ.get("MIM_WAKE_CHUNK_SECONDS", "4")))
    parser.add_argument("--idle-seconds", type=float, default=float(os.environ.get("MIM_WAKE_IDLE_SECONDS", "0.5")))
    args = parser.parse_args()

    if not MODEL_PATH.exists():
        write_json(
            STATUS_PATH,
            {
                "packet_type": "mim-wake-listener-status-v1",
                "generated_at": now_iso(),
                "status": "blocked_with_evidence",
                "success": False,
                "reason_code": "vosk_model_missing",
                "model_path": str(MODEL_PATH),
                "next_recovery_action": "Install a Vosk English model, then restart mim-wake-listener.service.",
            },
        )
        return 2

    device, selection = select_audio_device()
    if not device:
        write_json(
            STATUS_PATH,
            {
                "packet_type": "mim-wake-listener-status-v1",
                "generated_at": now_iso(),
                "status": "blocked_with_evidence",
                "success": False,
                "reason_code": "no_openable_microphone",
                "device_selection": selection,
                "next_recovery_action": "Repair ALSA/PipeWire microphone access and restart mim-wake-listener.service.",
            },
        )
        return 3

    model = Model(str(MODEL_PATH))
    while True:
        result = listen_once(model, device, seconds=max(1, args.chunk_seconds))
        write_json(
            STATUS_PATH,
            {
                "packet_type": "mim-wake-listener-status-v1",
                "generated_at": now_iso(),
                "status": result["status"],
                "success": result["success"],
                "objective_id": "MIM-LISTENING-AND-VOICE-PERSONA-V1",
                "audio_device": device,
                "device_selection": selection,
                "last_transcript": result.get("transcript", ""),
                "wake_phrase_detected": result.get("wake_phrase_detected", False),
                "stt_error": result.get("stt_error", ""),
                "tts_ok": result.get("tts_ok"),
                "no_audio_retained": True,
                "interaction_artifact": str(INTERACTION_PATH.relative_to(ROOT)) if INTERACTION_PATH.exists() else "",
            },
        )
        if args.once:
            return 0
        time.sleep(max(0.1, args.idle_seconds))


if __name__ == "__main__":
    raise SystemExit(main())
