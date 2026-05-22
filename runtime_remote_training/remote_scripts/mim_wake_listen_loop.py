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
import audioop
import math
import struct
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
DIAGNOSTIC_PATH = SHARED / "MIM_WAKE_DIAGNOSTIC.latest.json"
FOLLOWUP_PATH = SHARED / "MIM_WAKE_FOLLOWUP.latest.json"
ALERT_WAV_PATH = ROOT / "runtime" / "shared" / "MIM_WAKE_ALERT.wav"
VOICE_WAV_PATH = ROOT / "runtime" / "shared" / "MIM_WAKE_VOICE_RESPONSE.wav"
COMBINED_RESPONSE_WAV_PATH = ROOT / "runtime" / "shared" / "MIM_WAKE_COMBINED_RESPONSE.wav"
PIPER_MODEL_PATH = Path(
    os.environ.get(
        "MIM_VOICE_PIPER_MODEL",
        ROOT / "runtime" / "models" / "piper" / "en_US-lessac-medium" / "en_US-lessac-medium.onnx",
    )
)

DEFAULT_DEVICES = [
    "plughw:2,0",
    "default",
    "plughw:0,0",
    "plughw:3,0",
    "plughw:3,2",
]

DEFAULT_PLAYBACK_DEVICES = [
    "plughw:1,0",
    "plughw:4,3",
    "default",
    "plughw:3,0",
    "plughw:4,7",
    "plughw:4,8",
    "plughw:4,9",
]

WAKE_PATTERNS = [
    re.compile(r"\b(hello|hey|okay|ok)\s+(mim|m\.?i\.?m\.?|ma'?am|mom|mem|meme)\b", re.I),
    re.compile(r"\bcan you hear me\b", re.I),
    re.compile(r"\bmim\b", re.I),
]

SELF_OUTPUT_PATTERNS = [
    re.compile(r"\bhey dave\b", re.I),
    re.compile(r"\bi heard you\b", re.I),
    re.compile(r"\btiny miracle\b", re.I),
    re.compile(r"\bstanding by\b", re.I),
]

RESPONSE_TEXT = os.environ.get("MIM_WAKE_RESPONSE_TEXT", "Hi Dave. I'm awake. What do you need?")
DIAGNOSTIC_ENABLED = os.environ.get("MIM_WAKE_DIAGNOSTIC", "1").strip().lower() not in {"0", "false", "no", "off"}
FOLLOWUP_ENABLED = os.environ.get("MIM_WAKE_FOLLOWUP", "1").strip().lower() not in {"0", "false", "no", "off"}
FOLLOWUP_SECONDS = int(os.environ.get("MIM_WAKE_FOLLOWUP_SECONDS", "8"))

WAKE_GRAMMAR = json.dumps(
    [
        "hello mim",
        "hey mim",
        "okay mim",
        "ok mim",
        "hello ma'am",
        "can you hear me",
        "mim can you hear me",
        "hello mim can you hear me",
        "[unk]",
    ]
)


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


def audio_level(path: Path) -> dict[str, int]:
    try:
        data = path.read_bytes()
        if not data:
            return {"bytes": 0, "rms": 0, "max": 0}
        return {"bytes": len(data), "rms": int(audioop.rms(data, 2)), "max": int(audioop.max(data, 2))}
    except Exception:
        return {"bytes": 0, "rms": 0, "max": 0}


def select_audio_device() -> tuple[str, dict[str, Any]]:
    attempts = []
    for device in configured_devices():
        with tempfile.NamedTemporaryFile(prefix="mim-wake-probe-", suffix=".wav", delete=False) as tmp:
            path = Path(tmp.name)
        try:
            probe = record_wav(device, path, seconds=1)
            level = audio_level(path)
            attempts.append(
                {
                    "device": device,
                    "ok": probe["ok"],
                    "rms": level["rms"],
                    "max": level["max"],
                    "bytes": level["bytes"],
                    "error": "" if probe["ok"] else probe.get("stderr") or probe.get("stdout"),
                }
            )
        finally:
            try:
                path.unlink(missing_ok=True)
            except Exception:
                pass
    openable = [item for item in attempts if item.get("ok")]
    usable = [
        item
        for item in openable
        if int(item.get("rms") or 0) >= 200 and int(item.get("max") or 0) < 32760
    ]
    if usable:
        selected = usable[0]
        return str(selected["device"]), {"attempts": attempts, "selection_reason": "first_nonclipped_signal_in_priority_order"}
    if openable:
        selected = sorted(openable, key=lambda item: (int(item.get("rms") or 0), int(item.get("max") or 0)), reverse=True)[0]
        return str(selected["device"]), {"attempts": attempts, "selection_reason": "highest_probe_rms"}
    return "", {"attempts": attempts}


def transcribe_wav(model: Model, wav_path: Path) -> dict[str, Any]:
    with wave.open(str(wav_path), "rb") as wav_file:
        if wav_file.getnchannels() != 1 or wav_file.getsampwidth() != 2 or wav_file.getframerate() != 16000:
            return {
                "ok": False,
                "text": "",
                "wake_text": "",
                "error": f"unsupported_wav_format channels={wav_file.getnchannels()} width={wav_file.getsampwidth()} rate={wav_file.getframerate()}",
            }
        recognizer = KaldiRecognizer(model, 16000)
        recognizer.SetWords(True)
        accepted_texts = []
        while True:
            data = wav_file.readframes(4000)
            if len(data) == 0:
                break
            if recognizer.AcceptWaveform(data):
                accepted = json.loads(recognizer.Result())
                if str(accepted.get("text") or "").strip():
                    accepted_texts.append(str(accepted.get("text")).strip())
        result = json.loads(recognizer.FinalResult())
        wav_file.rewind()
        wake_recognizer = KaldiRecognizer(model, 16000, WAKE_GRAMMAR)
        wake_texts = []
        while True:
            data = wav_file.readframes(4000)
            if len(data) == 0:
                break
            if wake_recognizer.AcceptWaveform(data):
                accepted = json.loads(wake_recognizer.Result())
                if str(accepted.get("text") or "").strip():
                    wake_texts.append(str(accepted.get("text")).strip())
        wake_result = json.loads(wake_recognizer.FinalResult())
    final_text = str(result.get("text") or "").strip()
    wake_final_text = str(wake_result.get("text") or "").strip()
    text = " ".join([*accepted_texts, final_text]).strip()
    wake_text = " ".join([*wake_texts, wake_final_text]).strip()
    return {"ok": True, "text": text, "wake_text": wake_text, "raw_result": result, "wake_result": wake_result, "error": ""}


def detect_wake(text: str) -> bool:
    normalized = re.sub(r"[^a-zA-Z0-9.' ]+", " ", text).strip().lower()
    return any(pattern.search(normalized) for pattern in WAKE_PATTERNS)


def detect_self_output(text: str) -> bool:
    normalized = re.sub(r"[^a-zA-Z0-9.' ]+", " ", str(text or "")).strip().lower()
    return any(pattern.search(normalized) for pattern in SELF_OUTPUT_PATTERNS)


def detect_probable_wake_check(*, general_text: str, wake_text: str, level: dict[str, int]) -> bool:
    normalized_wake = str(wake_text or "").strip().lower()
    normalized_general = str(general_text or "").strip().lower()
    if detect_self_output(normalized_general) or detect_self_output(normalized_wake):
        return False
    return False


def classify_diagnostic(result: dict[str, Any]) -> dict[str, Any]:
    transcript = str(result.get("transcript") or "").strip()
    general_transcript = str(result.get("general_transcript") or "").strip()
    wake_transcript = str(result.get("wake_transcript") or "").strip()
    level = result.get("audio_level") or {}
    rms = int(level.get("rms") or 0)
    max_level = int(level.get("max") or 0)
    wake = bool(result.get("wake_phrase_detected"))
    voice_ok = result.get("voice_wav_output_accepted")
    self_output = bool(result.get("self_output_detected"))
    stt_error = str(result.get("stt_error") or "").strip()
    if not result.get("success"):
        reason_code = "capture_or_stt_blocked"
        summary = "MIM could not complete the microphone/STT cycle."
        next_action = "Inspect error, microphone device, and Vosk model path."
    elif wake and voice_ok:
        reason_code = "responded"
        summary = "MIM detected explicit wake language and accepted voice playback."
        next_action = "If the operator did not hear MIM, inspect playback route and speaker volume."
    elif wake and not voice_ok:
        reason_code = "response_playback_blocked"
        summary = "MIM detected wake language but did not prove voice playback accepted."
        next_action = "Inspect Piper generation and aplay device attempts in the interaction artifact."
    elif self_output:
        reason_code = "ignored_self_output"
        summary = "MIM heard a phrase matching her own recent output and ignored it."
        next_action = "No action unless this was actually the operator speaking the same phrase."
    elif stt_error:
        reason_code = "stt_error"
        summary = "Audio capture completed but STT reported an error."
        next_action = "Inspect stt_error and Vosk model/runtime logs."
    elif not transcript and rms < 180:
        reason_code = "no_speech_or_too_quiet"
        summary = "MIM did not see enough speech energy to transcribe operator intent."
        next_action = "Move closer to the active mic or select a better input device."
    elif not transcript:
        reason_code = "audio_without_transcript"
        summary = "MIM saw audio energy but Vosk did not produce text."
        next_action = "Tune microphone gain/noise, try a clearer phrase, or test a different microphone."
    else:
        reason_code = "heard_but_no_explicit_wake"
        summary = "MIM transcribed speech but strict wake rules did not match it."
        next_action = "Say 'hello MIM' or 'MIM can you hear me'; if this phrase was used, add the observed transcript as a safe alias."
    return {
        "reason_code": reason_code,
        "summary": summary,
        "next_action": next_action,
        "observed": {
            "transcript": transcript,
            "general_transcript": general_transcript,
            "wake_transcript": wake_transcript,
            "rms": rms,
            "max": max_level,
            "wake_phrase_detected": wake,
            "probable_wake_check": bool(result.get("probable_wake_check")),
            "self_output_detected": self_output,
            "voice_wav_output_accepted": voice_ok,
            "stt_error": stt_error,
        },
    }


def publish_diagnostic(result: dict[str, Any], *, device: str, selection: dict[str, Any]) -> None:
    if not DIAGNOSTIC_ENABLED:
        return
    diagnosis = classify_diagnostic(result)
    write_json(
        DIAGNOSTIC_PATH,
        {
            "packet_type": "mim-wake-diagnostic-v1",
            "generated_at": now_iso(),
            "objective_id": "MIM-LISTENING-AND-VOICE-PERSONA-V1",
            "status": "observed",
            "success": True,
            "no_audio_retained": True,
            "audio_device": device,
            "device_selection": selection,
            "diagnosis": diagnosis,
            "operator_test_instruction": "Say 'hello MIM' or 'MIM can you hear me' while this artifact is being monitored.",
            "related_artifacts": {
                "listener_status": str(STATUS_PATH.relative_to(ROOT)),
                "wake_interaction": str(INTERACTION_PATH.relative_to(ROOT)),
            },
        },
    )


def speak(text: str) -> dict[str, Any]:
    return run_command(["spd-say", text], timeout=8)


def playback_devices() -> list[str]:
    raw = os.environ.get("MIM_WAKE_PLAYBACK_DEVICES", "").strip()
    if raw:
        if ";" in raw:
            return [item.strip() for item in raw.split(";") if item.strip()]
        return [raw]
    return DEFAULT_PLAYBACK_DEVICES


def ensure_alert_wav(path: Path = ALERT_WAV_PATH) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    rate = 48_000
    duration = 0.35
    pauses = 0.10
    tones = [880, 1320, 1760]
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(rate)
        for frequency in tones:
            for i in range(int(rate * duration)):
                value = int(22_000 * math.sin(2 * math.pi * frequency * i / rate))
                wav_file.writeframesraw(struct.pack("<hh", value, value))
            for _ in range(int(rate * pauses)):
                wav_file.writeframesraw(struct.pack("<hh", 0, 0))
    return path


def read_pcm16_wav(path: Path) -> tuple[int, int, list[int]]:
    with wave.open(str(path), "rb") as wav_file:
        channels = wav_file.getnchannels()
        sample_width = wav_file.getsampwidth()
        rate = wav_file.getframerate()
        data = wav_file.readframes(wav_file.getnframes())
    if sample_width != 2:
        raise ValueError(f"unsupported_sample_width:{sample_width}")
    samples = list(struct.unpack("<" + "h" * (len(data) // 2), data))
    return rate, channels, samples


def to_stereo_48k(rate: int, channels: int, samples: list[int]) -> list[tuple[int, int]]:
    if channels == 1:
        mono = samples
    else:
        mono = [int((samples[i] + samples[i + 1]) / 2) for i in range(0, len(samples) - 1, channels)]
    if rate == 48_000:
        resampled = mono
    else:
        target_len = max(1, int(len(mono) * 48_000 / rate))
        resampled = []
        for i in range(target_len):
            src_pos = i * (len(mono) - 1) / max(1, target_len - 1)
            left = int(src_pos)
            right = min(left + 1, len(mono) - 1)
            frac = src_pos - left
            value = int(mono[left] * (1 - frac) + mono[right] * frac)
            resampled.append(value)
    peak = max((abs(item) for item in resampled), default=1)
    gain = min(2.2, 28500 / peak) if peak else 1.0
    stereo = []
    for sample in resampled:
        value = max(-30000, min(30000, int(sample * gain)))
        stereo.append((value, value))
    return stereo


def write_stereo_48k(path: Path, frames: list[tuple[int, int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(48_000)
        for left, right in frames:
            wav_file.writeframesraw(struct.pack("<hh", left, right))


def build_combined_response_wav(voice_path: Path = VOICE_WAV_PATH, output_path: Path = COMBINED_RESPONSE_WAV_PATH) -> Path:
    voice_rate, voice_channels, voice_samples = read_pcm16_wav(voice_path)
    voice = to_stereo_48k(voice_rate, voice_channels, voice_samples)
    write_stereo_48k(output_path, voice)
    return output_path


def play_alert() -> list[dict[str, Any]]:
    wav_path = ensure_alert_wav()
    return play_wav_on_outputs(wav_path)


def play_wav_on_outputs(wav_path: Path, *, stop_after_first_success: bool = True) -> list[dict[str, Any]]:
    timeout_seconds = 8
    try:
        with wave.open(str(wav_path), "rb") as wav_file:
            duration = wav_file.getnframes() / float(wav_file.getframerate())
        timeout_seconds = max(8, int(duration) + 4)
    except Exception:
        pass
    attempts = []
    for device in playback_devices():
        probe = run_command(["timeout", str(timeout_seconds), "aplay", "-D", device, str(wav_path)], timeout=timeout_seconds + 2)
        attempts.append(
            {
                "device": device,
                "ok": probe["ok"],
                "returncode": probe.get("returncode"),
                "error": "" if probe["ok"] else probe.get("stderr") or probe.get("stdout") or "aplay_failed",
            }
        )
        if probe["ok"] and stop_after_first_success:
            break
    return attempts


def synthesize_voice_response(text: str, output_path: Path = VOICE_WAV_PATH) -> dict[str, Any]:
    if not PIPER_MODEL_PATH.exists():
        return {
            "ok": False,
            "voice_engine": "piper",
            "voice_model": str(PIPER_MODEL_PATH),
            "output_wav": str(output_path.relative_to(ROOT)),
            "error": "piper_model_missing",
            "command": [],
            "returncode": None,
        }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix="mim-voice-", suffix=".txt", mode="w", encoding="utf-8", delete=False) as tmp:
        tmp.write(text)
        text_path = Path(tmp.name)
    try:
        command = [
            str(ROOT / ".venv" / "bin" / "piper"),
            "-m",
            str(PIPER_MODEL_PATH),
            "-i",
            str(text_path),
            "-f",
            str(output_path),
            "--length-scale",
            "0.92",
            "--noise-scale",
            "0.55",
            "--noise-w-scale",
            "0.75",
            "--volume",
            "1.25",
        ]
        result = run_command(command, timeout=30)
        return {
            "ok": bool(result["ok"] and output_path.exists() and output_path.stat().st_size > 1000),
            "voice_engine": "piper",
            "voice_model": str(PIPER_MODEL_PATH.relative_to(ROOT)),
            "output_wav": str(output_path.relative_to(ROOT)),
            "command": result.get("command"),
            "returncode": result.get("returncode"),
            "error": "" if result["ok"] else result.get("stderr") or result.get("stdout") or "piper_failed",
        }
    finally:
        try:
            text_path.unlink(missing_ok=True)
        except Exception:
            pass


def play_voice_response(text: str) -> dict[str, Any]:
    synthesis = synthesize_voice_response(text)
    combined_path = build_combined_response_wav() if synthesis["ok"] else COMBINED_RESPONSE_WAV_PATH
    attempts = play_wav_on_outputs(combined_path) if synthesis["ok"] else []
    return {
        **synthesis,
        "combined_response_wav": str(combined_path.relative_to(ROOT)),
        "combined_format": "48kHz stereo PCM16 voice-only playback stream",
        "play_attempts": attempts,
        "any_output_accepted": any(bool(item.get("ok")) for item in attempts),
        "operator_audible_confirmed": False,
    }


def publish_wake_interaction(
    *,
    transcript: str,
    device: str,
    tts: dict[str, Any],
    alert_attempts: list[dict[str, Any]],
    voice_response: dict[str, Any],
) -> None:
    generated_at = now_iso()
    voice_ok = bool(voice_response.get("ok") and voice_response.get("any_output_accepted"))
    alert_ok = any(bool(item.get("ok")) for item in alert_attempts) or bool(
        voice_response.get("combined_response_wav") and voice_response.get("any_output_accepted")
    )
    payload = {
        "packet_type": "mim-wake-word-interaction-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-LISTENING-AND-VOICE-PERSONA-V1",
        "owner": "MIM",
        "status": "completed_with_evidence" if tts["ok"] or alert_ok or voice_ok else "blocked_with_evidence",
        "success": bool(tts["ok"] or alert_ok or voice_ok),
        "wake_phrase_detected": True,
        "transcript": transcript,
        "audio_device": device,
        "response": {
            "mode": "voice_tts_only",
            "text": RESPONSE_TEXT,
            "audible_acknowledgement": "voice-only acknowledgement; three-tone alert removed after operator reported repeated beep-plus-voice loop",
            "audible_acknowledgement_delivery": "combined_response_wav" if voice_response.get("combined_response_wav") else "separate_alert_wav",
            "tts_command": tts.get("command"),
            "tts_returncode": tts.get("returncode"),
            "tts_error": "" if tts["ok"] else tts.get("stderr") or tts.get("stdout") or "tts_failed",
            "tts_operator_audible_confirmed": False,
            "alert_wav": str(ALERT_WAV_PATH.relative_to(ROOT)),
            "alert_attempts": alert_attempts,
            "alert_any_output_accepted": alert_ok,
            "voice_response": voice_response,
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
                "alert_attempts": alert_attempts,
                "voice_response": voice_response,
                "last_interaction_time": generated_at if tts["ok"] or alert_ok or voice_ok else None,
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
            "next_recovery_action": "" if tts["ok"] or alert_ok or voice_ok else "Repair speech-dispatcher or playback output routing.",
        },
    )


def listen_for_followup(model: Model, device: str, *, seconds: int) -> dict[str, Any]:
    with tempfile.NamedTemporaryFile(prefix="mim-wake-followup-", suffix=".wav", delete=False) as tmp:
        wav_path = Path(tmp.name)
    try:
        rec = record_wav(device, wav_path, seconds=seconds)
        if not rec["ok"]:
            return {
                "status": "blocked_with_evidence",
                "success": False,
                "audio_device": device,
                "transcript": "",
                "error": rec.get("stderr") or rec.get("stdout") or "arecord_failed",
                "no_audio_retained": True,
            }
        level = audio_level(wav_path)
        stt = transcribe_wav(model, wav_path)
        transcript = stt.get("text", "") or stt.get("wake_text", "")
        self_output_detected = detect_self_output(stt.get("text", "")) or detect_self_output(stt.get("wake_text", ""))
        if not stt["ok"]:
            status = "stt_blocked"
            response_text = ""
        elif self_output_detected:
            status = "ignored_self_output"
            response_text = ""
        elif transcript:
            status = "operator_followup_heard"
            clean = transcript[:140].strip()
            response_text = f"I heard: {clean}. I logged that for the next work step."
        else:
            status = "no_followup_heard"
            response_text = ""
        voice_response = play_voice_response(response_text) if response_text else {}
        result = {
            "packet_type": "mim-wake-followup-v1",
            "generated_at": now_iso(),
            "objective_id": "MIM-LISTENING-AND-VOICE-PERSONA-V1",
            "status": status,
            "success": bool(stt["ok"]),
            "audio_device": device,
            "listen_seconds": seconds,
            "transcript": transcript,
            "general_transcript": stt.get("text", ""),
            "wake_transcript": stt.get("wake_text", ""),
            "audio_level": level,
            "self_output_detected": self_output_detected,
            "stt_error": stt.get("error", ""),
            "response_text": response_text,
            "voice_response": voice_response,
            "voice_wav_output_accepted": bool(voice_response.get("any_output_accepted")) if response_text else None,
            "no_audio_retained": True,
            "next_recovery_action": ""
            if transcript
            else "If the operator spoke after MIM's prompt, inspect microphone gain/device selection or increase followup listen seconds.",
        }
        write_json(FOLLOWUP_PATH, result)
        return result
    finally:
        try:
            wav_path.unlink(missing_ok=True)
        except Exception:
            pass


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
        level = audio_level(wav_path)
        stt = transcribe_wav(model, wav_path)
        transcript = stt.get("text", "") or stt.get("wake_text", "")
        probable_wake = detect_probable_wake_check(general_text=stt.get("text", ""), wake_text=stt.get("wake_text", ""), level=level)
        self_output_detected = detect_self_output(stt.get("text", "")) or detect_self_output(stt.get("wake_text", ""))
        wake = bool(
            stt["ok"]
            and not self_output_detected
            and (
                detect_wake(stt.get("text", ""))
                or detect_wake(stt.get("wake_text", ""))
                or probable_wake
            )
        )
        tts = {"ok": True, "command": [], "returncode": 0, "stderr": "", "stdout": ""}
        voice_response = {}
        if wake:
            alert_attempts = []
            voice_response = play_voice_response(RESPONSE_TEXT)
            followup = (
                listen_for_followup(model, device, seconds=max(1, FOLLOWUP_SECONDS))
                if FOLLOWUP_ENABLED and voice_response.get("any_output_accepted")
                else {}
            )
            tts = {
                "ok": False,
                "command": [],
                "returncode": None,
                "stderr": "speech-dispatcher skipped; generated WAV is the primary response",
                "stdout": "",
            }
            publish_wake_interaction(
                transcript=transcript,
                device=device,
                tts=tts,
                alert_attempts=alert_attempts,
                voice_response=voice_response,
            )
        else:
            followup = {}
        return {
            "status": "wake_detected" if wake else "listening",
            "success": True,
            "audio_device": device,
            "audio_level": level,
            "transcript": transcript,
            "general_transcript": stt.get("text", ""),
            "wake_transcript": stt.get("wake_text", ""),
            "wake_phrase_detected": wake,
            "probable_wake_check": probable_wake,
            "self_output_detected": self_output_detected,
            "stt_error": stt.get("error", ""),
            "tts_ok": tts["ok"] if wake else None,
            "alert_any_output_accepted": any(bool(item.get("ok")) for item in alert_attempts) if wake else None,
            "voice_wav_output_accepted": bool(voice_response.get("any_output_accepted")) if wake else None,
            "followup_status": followup.get("status") if wake else None,
            "followup_transcript": followup.get("transcript") if wake else "",
            "followup_voice_wav_output_accepted": followup.get("voice_wav_output_accepted") if wake else None,
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
    parser.add_argument("--cooldown-seconds", type=int, default=int(os.environ.get("MIM_WAKE_COOLDOWN_SECONDS", "45")))
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
        publish_diagnostic(result, device=device, selection=selection)
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
                "last_general_transcript": result.get("general_transcript", ""),
                "last_wake_transcript": result.get("wake_transcript", ""),
                "last_audio_level": result.get("audio_level", {}),
                "wake_phrase_detected": result.get("wake_phrase_detected", False),
                "probable_wake_check": result.get("probable_wake_check", False),
                "self_output_detected": result.get("self_output_detected", False),
                "stt_error": result.get("stt_error", ""),
                "tts_ok": result.get("tts_ok"),
                "alert_any_output_accepted": result.get("alert_any_output_accepted"),
                "voice_wav_output_accepted": result.get("voice_wav_output_accepted"),
                "followup_status": result.get("followup_status"),
                "followup_transcript": result.get("followup_transcript", ""),
                "followup_voice_wav_output_accepted": result.get("followup_voice_wav_output_accepted"),
                "no_audio_retained": True,
                "interaction_artifact": str(INTERACTION_PATH.relative_to(ROOT)) if INTERACTION_PATH.exists() else "",
                "followup_artifact": str(FOLLOWUP_PATH.relative_to(ROOT)) if FOLLOWUP_PATH.exists() else "",
            },
        )
        if args.once:
            return 0
        if result.get("wake_phrase_detected"):
            cooldown_until = now_iso()
            write_json(
                STATUS_PATH,
                {
                    "packet_type": "mim-wake-listener-status-v1",
                    "generated_at": cooldown_until,
                    "status": "cooldown_after_response",
                    "success": True,
                    "objective_id": "MIM-LISTENING-AND-VOICE-PERSONA-V1",
                    "audio_device": device,
                    "cooldown_seconds": max(1, args.cooldown_seconds),
                    "reason": "Prevent repeated playback and self-triggering after audible response.",
                    "last_transcript": result.get("transcript", ""),
                    "wake_phrase_detected": True,
                    "voice_wav_output_accepted": result.get("voice_wav_output_accepted"),
                    "followup_status": result.get("followup_status"),
                    "followup_transcript": result.get("followup_transcript", ""),
                    "followup_voice_wav_output_accepted": result.get("followup_voice_wav_output_accepted"),
                    "interaction_artifact": str(INTERACTION_PATH.relative_to(ROOT)) if INTERACTION_PATH.exists() else "",
                    "followup_artifact": str(FOLLOWUP_PATH.relative_to(ROOT)) if FOLLOWUP_PATH.exists() else "",
                },
            )
            time.sleep(max(1, args.cooldown_seconds))
        time.sleep(max(0.1, args.idle_seconds))


if __name__ == "__main__":
    raise SystemExit(main())
