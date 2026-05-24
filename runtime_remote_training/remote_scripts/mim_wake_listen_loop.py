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
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from vosk import KaldiRecognizer, Model


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
MODEL_PATH = Path(os.environ.get("MIM_WAKE_VOSK_MODEL", ROOT / "runtime" / "models" / "vosk-model-small-en-us-0.15"))
STATUS_PATH = SHARED / "MIM_WAKE_LISTENER_STATUS.latest.json"
INTERACTION_PATH = SHARED / "MIM_WAKE_WORD_INTERACTION.latest.json"
MEMORY_PATH = SHARED / "MIM_HUMAN_INTERACTION_MEMORY.latest.json"
DIAGNOSTIC_PATH = SHARED / "MIM_WAKE_DIAGNOSTIC.latest.json"
FOLLOWUP_PATH = SHARED / "MIM_WAKE_FOLLOWUP.latest.json"
TURN_STATE_PATH = SHARED / "MIM_VOICE_TURN_STATE.latest.json"
VAD_STATUS_PATH = SHARED / "MIM_VAD_SPEECH_SEGMENTATION_STATUS.latest.json"
FAUX_PAUSE_STATUS_PATH = SHARED / "MIM_FAUX_PAUSE_HANDLING_STATUS.latest.json"
VOICE_CHAT_BRIDGE_PATH = SHARED / "MIM_VOICE_UI_CHAT_BRIDGE.latest.json"
VOICE_TRANSCRIPT_LOG_PATH = SHARED / "MIM_VOICE_TRANSCRIPT_LOG.latest.jsonl"
VOICE_TRANSCRIPT_SUMMARY_PATH = SHARED / "MIM_VOICE_TRANSCRIPT_LOG_STATUS.latest.json"
VOICE_FRAGMENT_SUPPRESSION_PATH = SHARED / "MIM_VOICE_FRAGMENT_SUPPRESSION_STATUS.latest.json"
VOICE_CONTROL_OBJECTIVE_PATH = SHARED / "MIM_LAB_CONVERSATION_CONTROL_LAYER_OBJECTIVE.latest.json"
VOICE_ADDRESSING_DECISION_PATH = SHARED / "MIM_VOICE_ADDRESSING_DECISION.latest.json"
LAB_CONVERSATION_SCENE_PATH = SHARED / "MIM_LAB_CONVERSATION_SCENE.latest.json"
VOICE_INTERACTION_LEARNING_PATH = SHARED / "MIM_VOICE_INTERACTION_LEARNING.latest.json"
STATION_FILE_FETCH_REQUEST_PATH = SHARED / "MIM_STATION_FILE_FETCH_REQUEST.latest.json"
ARM_MOTION_PROPOSAL_PATH = SHARED / "MIM_ARM_MOTION_PROPOSAL.latest.json"
ARM_MOTION_EXECUTION_PATH = SHARED / "MIM_ARM_MOTION_EXECUTION.latest.json"
ARM_SYNC_ASSERTION_PATH = SHARED / "MIM_ARM_SYNC_OPERATOR_ASSERTION.latest.json"
ARM_HOST = os.environ.get("MIM_ARM_HOST", "http://192.168.1.90:5000").rstrip("/")
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
LAB_CONVERSATION_MODE = os.environ.get("MIM_LAB_CONVERSATION_MODE", "1").strip().lower() not in {"0", "false", "no", "off"}
VOICE_UI_CHAT_BRIDGE_ENABLED = os.environ.get("MIM_VOICE_UI_CHAT_BRIDGE", "1").strip().lower() not in {"0", "false", "no", "off"}
VOICE_UI_CHAT_SESSION_ID = os.environ.get("MIM_VOICE_UI_CHAT_SESSION_ID", "mim-ambient-lab-voice-ui-chat")
VOICE_UI_CHAT_ENDPOINT = os.environ.get("MIM_VOICE_UI_CHAT_ENDPOINT", "http://127.0.0.1:18001/gateway/intake/text")
VOICE_TRANSCRIPT_LOG_ENABLED = os.environ.get("MIM_VOICE_TRANSCRIPT_LOG", "1").strip().lower() not in {"0", "false", "no", "off"}
VOICE_TRANSCRIPT_LOG_MAX_LINES = int(os.environ.get("MIM_VOICE_TRANSCRIPT_LOG_MAX_LINES", "500"))
VOICE_FRAGMENT_SUPPRESSION_ENABLED = (
    os.environ.get("MIM_VOICE_FRAGMENT_SUPPRESSION", "1").strip().lower() not in {"0", "false", "no", "off"}
)
STT_ENGINE = os.environ.get("MIM_STT_ENGINE", "vosk").strip().lower()
WHISPER_MODEL_SIZE = os.environ.get("MIM_WHISPER_MODEL_SIZE", "small.en").strip()
WHISPER_DEVICE = os.environ.get("MIM_WHISPER_DEVICE", "cpu").strip()
WHISPER_COMPUTE_TYPE = os.environ.get("MIM_WHISPER_COMPUTE_TYPE", "int8").strip()
WHISPER_VAD_FILTER = os.environ.get("MIM_WHISPER_VAD_FILTER", "1").strip().lower() not in {"0", "false", "no", "off"}
WHISPER_BEAM_SIZE = int(os.environ.get("MIM_WHISPER_BEAM_SIZE", "5"))
VOICE_PIPER_SPEAKER = os.environ.get("MIM_VOICE_PIPER_SPEAKER", "").strip()
VOICE_PIPER_LENGTH_SCALE = os.environ.get("MIM_VOICE_PIPER_LENGTH_SCALE", "0.82").strip()
VOICE_PIPER_NOISE_SCALE = os.environ.get("MIM_VOICE_PIPER_NOISE_SCALE", "0.48").strip()
VOICE_PIPER_NOISE_W_SCALE = os.environ.get("MIM_VOICE_PIPER_NOISE_W_SCALE", "0.65").strip()
VOICE_PIPER_VOLUME = os.environ.get("MIM_VOICE_PIPER_VOLUME", "1.18").strip()
OPERATOR_TIMEZONE = os.environ.get("MIM_OPERATOR_TIMEZONE", "America/Los_Angeles").strip()
VOICE_ACTIVE_SESSION_SECONDS = int(os.environ.get("MIM_VOICE_ACTIVE_SESSION_SECONDS", "90"))

LOW_CONTENT_TOKENS = {
    "a",
    "an",
    "and",
    "but",
    "hmm",
    "mim",
    "no",
    "oh",
    "ok",
    "okay",
    "the",
    "uh",
    "um",
    "yeah",
    "yes",
}

MIM_REFERENCE_TOKENS = {
    "maam",
    "mam",
    "mem",
    "men",
    "memoir",
    "meme",
    "mim",
    "min",
    "mime",
    "mom",
}

FOLLOWUP_REFERENCE_TOKENS = {
    "again",
    "also",
    "do",
    "doing",
    "it",
    "know",
    "one",
    "that",
    "there",
    "this",
    "those",
    "too",
    "today",
}

LEARNING_SUPPRESSION_SECONDS = int(os.environ.get("MIM_VOICE_LEARNING_SUPPRESSION_SECONDS", "180"))

ACTIONABLE_TOKENS = {
    "answer",
    "camera",
    "cameras",
    "can",
    "check",
    "could",
    "details",
    "do",
    "help",
    "how",
    "lab",
    "listen",
    "remember",
    "sensor",
    "sensors",
    "should",
    "status",
    "tell",
    "training",
    "what",
    "when",
    "where",
    "who",
    "why",
    "working",
    "would",
}

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

WHISPER_MODEL: Any | None = None


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(path)


def append_jsonl(path: Path, payload: dict[str, Any], *, max_lines: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    existing: list[str] = []
    try:
        if path.exists():
            existing = path.read_text(encoding="utf-8").splitlines()
    except Exception:
        existing = []
    lines = (existing + [line])[-max(1, max_lines):]
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
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
        with wave.open(str(path), "rb") as wav_file:
            width = wav_file.getsampwidth()
            frames = wav_file.readframes(wav_file.getnframes())
        if not frames:
            return {"bytes": 0, "rms": 0, "max": 0, "clipped": False}
        rms = int(audioop.rms(frames, width))
        max_level = int(audioop.max(frames, width))
        return {
            "bytes": len(frames),
            "rms": rms,
            "max": max_level,
            "clipped": max_level >= 32000,
            "noise_risk": "high" if rms >= 900 else "medium" if rms >= 500 else "low",
        }
    except Exception:
        return {"bytes": 0, "rms": 0, "max": 0, "clipped": False, "noise_risk": "unknown"}


def analyze_vad_segments(path: Path) -> dict[str, Any]:
    generated_at = now_iso()
    try:
        with wave.open(str(path), "rb") as wav_file:
            channels = wav_file.getnchannels()
            width = wav_file.getsampwidth()
            rate = wav_file.getframerate()
            frames = wav_file.readframes(wav_file.getnframes())
        if channels != 1 or width != 2 or rate <= 0:
            result = {
                "packet_type": "mim-vad-speech-segmentation-status-v1",
                "generated_at": generated_at,
                "status": "blocked_with_evidence",
                "success": False,
                "reason_code": "unsupported_wav_format",
                "format": {"channels": channels, "sample_width": width, "rate": rate},
                "no_audio_retained": True,
            }
            write_json(VAD_STATUS_PATH, result)
            return result
        frame_ms = 100
        samples_per_frame = max(1, int(rate * frame_ms / 1000))
        bytes_per_frame = samples_per_frame * width
        rms_values = []
        for offset in range(0, len(frames), bytes_per_frame):
            chunk = frames[offset : offset + bytes_per_frame]
            if len(chunk) >= width:
                rms_values.append(int(audioop.rms(chunk, width)))
        if not rms_values:
            result = {
                "packet_type": "mim-vad-speech-segmentation-status-v1",
                "generated_at": generated_at,
                "status": "blocked_with_evidence",
                "success": False,
                "reason_code": "empty_audio_window",
                "no_audio_retained": True,
            }
            write_json(VAD_STATUS_PATH, result)
            return result
        sorted_rms = sorted(rms_values)
        floor_slice = sorted_rms[: max(1, len(sorted_rms) // 3)]
        noise_floor = int(sum(floor_slice) / len(floor_slice))
        threshold = max(350, min(2400, int(noise_floor * 2.6)))
        hangover_frames = 5
        min_speech_frames = 2
        segments = []
        active_start: int | None = None
        quiet_run = 0
        speech_frames = 0
        for index, rms in enumerate(rms_values):
            is_speech = rms >= threshold
            if is_speech:
                if active_start is None:
                    active_start = index
                    speech_frames = 0
                speech_frames += 1
                quiet_run = 0
            elif active_start is not None:
                quiet_run += 1
                if quiet_run >= hangover_frames:
                    end_index = max(active_start, index - quiet_run + 1)
                    if speech_frames >= min_speech_frames:
                        segments.append(
                            {
                                "start_ms": active_start * frame_ms,
                                "end_ms": (end_index + 1) * frame_ms,
                                "duration_ms": (end_index - active_start + 1) * frame_ms,
                                "speech_frames": speech_frames,
                            }
                        )
                    active_start = None
                    quiet_run = 0
                    speech_frames = 0
        if active_start is not None and speech_frames >= min_speech_frames:
            end_index = len(rms_values) - 1
            segments.append(
                {
                    "start_ms": active_start * frame_ms,
                    "end_ms": (end_index + 1) * frame_ms,
                    "duration_ms": (end_index - active_start + 1) * frame_ms,
                    "speech_frames": speech_frames,
                }
            )
        result = {
            "packet_type": "mim-vad-speech-segmentation-status-v1",
            "generated_at": generated_at,
            "status": "completed_with_evidence",
            "success": True,
            "frame_ms": frame_ms,
            "noise_floor_rms": noise_floor,
            "speech_threshold_rms": threshold,
            "hangover_ms": hangover_frames * frame_ms,
            "min_speech_ms": min_speech_frames * frame_ms,
            "segments": segments,
            "speech_detected": bool(segments),
            "window_duration_ms": len(rms_values) * frame_ms,
            "no_audio_retained": True,
        }
        write_json(VAD_STATUS_PATH, result)
        write_json(
            FAUX_PAUSE_STATUS_PATH,
            {
                "packet_type": "mim-faux-pause-handling-status-v1",
                "generated_at": generated_at,
                "status": "completed_with_evidence",
                "success": True,
                "method": "energy_vad_hangover",
                "rule": "Do not finalize an utterance until speech falls below threshold for the hangover window.",
                "hangover_ms": hangover_frames * frame_ms,
                "input_artifact": str(VAD_STATUS_PATH.relative_to(ROOT)),
                "no_audio_retained": True,
            },
        )
        return result
    except Exception as exc:
        result = {
            "packet_type": "mim-vad-speech-segmentation-status-v1",
            "generated_at": generated_at,
            "status": "blocked_with_evidence",
            "success": False,
            "reason_code": "vad_exception",
            "error": f"{type(exc).__name__}: {exc}",
            "no_audio_retained": True,
        }
        write_json(VAD_STATUS_PATH, result)
        return result


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
                    "clipped": level.get("clipped", False),
                    "noise_risk": level.get("noise_risk", "unknown"),
                    "error": "" if probe["ok"] else probe.get("stderr") or probe.get("stdout"),
                }
            )
        finally:
            try:
                path.unlink(missing_ok=True)
            except Exception:
                pass
    openable = [item for item in attempts if item.get("ok")]
    clean = [
        item
        for item in openable
        if int(item.get("max") or 0) < 32760
        and int(item.get("rms") or 0) >= 20
        and int(item.get("rms") or 0) <= 700
    ]
    if clean:
        selected = clean[0]
        return str(selected["device"]), {"attempts": attempts, "selection_reason": "first_clean_low_noise_signal_in_priority_order"}
    usable = [
        item
        for item in openable
        if int(item.get("rms") or 0) >= 20 and int(item.get("max") or 0) < 32760
    ]
    if usable:
        selected = sorted(usable, key=lambda item: abs(int(item.get("rms") or 0) - 120))[0]
        return str(selected["device"]), {"attempts": attempts, "selection_reason": "nearest_quiet_usable_signal"}
    if openable:
        selected = sorted(openable, key=lambda item: (int(item.get("rms") or 0), int(item.get("max") or 0)), reverse=True)[0]
        return str(selected["device"]), {"attempts": attempts, "selection_reason": "highest_probe_rms"}
    return "", {"attempts": attempts}


def transcribe_wav(model: Model, wav_path: Path) -> dict[str, Any]:
    vosk = transcribe_wav_vosk(model, wav_path)
    if STT_ENGINE not in {"faster-whisper", "faster_whisper", "whisper", "auto"}:
        return vosk
    whisper = transcribe_wav_faster_whisper(wav_path)
    if whisper.get("ok") and str(whisper.get("text") or "").strip():
        return {
            **vosk,
            "text": str(whisper.get("text") or "").strip(),
            "stt_engine": "faster_whisper",
            "stt_primary": whisper,
            "stt_fallback": {"engine": "vosk", "text": vosk.get("text", ""), "wake_text": vosk.get("wake_text", "")},
        }
    return {
        **vosk,
        "stt_engine": "vosk",
        "stt_primary": {"engine": "faster_whisper", "ok": False, "error": whisper.get("error", "empty_whisper_transcript"), "text": whisper.get("text", "")},
        "stt_fallback": {"engine": "vosk", "reason": "faster_whisper_empty_or_failed"},
    }


def transcribe_wav_faster_whisper(wav_path: Path) -> dict[str, Any]:
    global WHISPER_MODEL
    started = time.time()
    try:
        from faster_whisper import WhisperModel
    except Exception as exc:
        return {
            "engine": "faster_whisper",
            "ok": False,
            "text": "",
            "error": f"import_failed: {type(exc).__name__}: {exc}",
            "duration_seconds": round(time.time() - started, 3),
        }
    try:
        if WHISPER_MODEL is None:
            WHISPER_MODEL = WhisperModel(WHISPER_MODEL_SIZE, device=WHISPER_DEVICE, compute_type=WHISPER_COMPUTE_TYPE)
        segments, info = WHISPER_MODEL.transcribe(
            str(wav_path),
            beam_size=WHISPER_BEAM_SIZE,
            vad_filter=WHISPER_VAD_FILTER,
            vad_parameters={"min_silence_duration_ms": 500},
            language="en",
            condition_on_previous_text=False,
        )
        text = " ".join(segment.text.strip() for segment in segments if segment.text.strip()).strip()
        return {
            "engine": "faster_whisper",
            "ok": True,
            "text": text,
            "model_size": WHISPER_MODEL_SIZE,
            "device": WHISPER_DEVICE,
            "compute_type": WHISPER_COMPUTE_TYPE,
            "beam_size": WHISPER_BEAM_SIZE,
            "vad_filter": WHISPER_VAD_FILTER,
            "language": getattr(info, "language", ""),
            "language_probability": getattr(info, "language_probability", None),
            "duration_seconds": round(time.time() - started, 3),
            "error": "",
        }
    except Exception as exc:
        return {
            "engine": "faster_whisper",
            "ok": False,
            "text": "",
            "model_size": WHISPER_MODEL_SIZE,
            "device": WHISPER_DEVICE,
            "compute_type": WHISPER_COMPUTE_TYPE,
            "beam_size": WHISPER_BEAM_SIZE,
            "vad_filter": WHISPER_VAD_FILTER,
            "duration_seconds": round(time.time() - started, 3),
            "error": f"{type(exc).__name__}: {exc}",
        }


def transcribe_wav_vosk(model: Model, wav_path: Path) -> dict[str, Any]:
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
    return {"ok": True, "text": text, "wake_text": wake_text, "raw_result": result, "wake_result": wake_result, "error": "", "stt_engine": "vosk"}


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
    lab_response = bool(result.get("lab_conversation_response"))
    voice_ok = result.get("voice_wav_output_accepted")
    if voice_ok is None:
        voice_ok = result.get("lab_conversation_voice_wav_output_accepted")
    self_output = bool(result.get("self_output_detected"))
    stt_error = str(result.get("stt_error") or "").strip()
    if not result.get("success"):
        reason_code = "capture_or_stt_blocked"
        summary = "MIM could not complete the microphone/STT cycle."
        next_action = "Inspect error, microphone device, and Vosk model path."
    elif lab_response and voice_ok:
        reason_code = "lab_conversation_responded"
        summary = "MIM heard ambient lab speech, routed it to an intent, and accepted voice playback."
        next_action = "If the operator did not hear MIM, inspect playback route and speaker volume."
    elif wake and voice_ok:
        reason_code = "wake_responded"
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
            "stt_engine": result.get("stt_engine"),
            "stt_primary": result.get("stt_primary", {}),
            "stt_fallback": result.get("stt_fallback", {}),
            "rms": rms,
            "max": max_level,
            "wake_phrase_detected": wake,
            "lab_conversation_response": lab_response,
            "lab_conversation_intent": result.get("lab_conversation_intent"),
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


def publish_transcript_log(result: dict[str, Any], *, device: str) -> None:
    if not VOICE_TRANSCRIPT_LOG_ENABLED:
        return
    transcript = str(result.get("transcript") or "").strip()
    general = str(result.get("general_transcript") or "").strip()
    wake_text = str(result.get("wake_transcript") or "").strip()
    vad = result.get("vad") if isinstance(result.get("vad"), dict) else {}
    level = result.get("audio_level") if isinstance(result.get("audio_level"), dict) else {}
    normalized_transcript = normalize_voice_transcript_for_intent(transcript)
    audio_condition = {
        "clipped": bool(level.get("clipped")),
        "noise_risk": str(level.get("noise_risk") or "unknown"),
        "music_or_noise_possible": bool(level.get("clipped")) or str(level.get("noise_risk") or "") in {"medium", "high"},
        "reason": "High RMS or clipped samples can make music/background audio look like speech to STT.",
    }
    entry = {
        "generated_at": now_iso(),
        "packet_type": "mim-voice-transcript-log-entry-v1",
        "audio_device": device,
        "status": result.get("status"),
        "transcript": transcript,
        "normalized_transcript": normalized_transcript,
        "general_transcript": general,
        "wake_transcript": wake_text,
        "stt_error": result.get("stt_error", ""),
        "stt_engine": result.get("stt_engine", ""),
        "stt_primary": result.get("stt_primary", {}),
        "stt_fallback": result.get("stt_fallback", {}),
        "audio_level": level,
        "audio_condition": audio_condition,
        "vad": vad,
        "self_output_detected": result.get("self_output_detected", False),
        "wake_phrase_detected": result.get("wake_phrase_detected", False),
        "lab_conversation_mode": result.get("lab_conversation_mode"),
        "lab_conversation_response": result.get("lab_conversation_response"),
        "lab_conversation_intent": result.get("lab_conversation_intent"),
        "lab_conversation_action": result.get("lab_conversation_action"),
        "lab_conversation_fragment_classification": result.get("lab_conversation_fragment_classification", {}),
        "lab_conversation_addressing_decision": result.get("lab_conversation_addressing_decision", {}),
        "voice_wav_output_accepted": result.get("voice_wav_output_accepted"),
        "lab_conversation_voice_wav_output_accepted": result.get("lab_conversation_voice_wav_output_accepted"),
        "no_audio_retained": True,
    }
    append_jsonl(VOICE_TRANSCRIPT_LOG_PATH, entry, max_lines=VOICE_TRANSCRIPT_LOG_MAX_LINES)
    try:
        line_count = len(VOICE_TRANSCRIPT_LOG_PATH.read_text(encoding="utf-8").splitlines())
    except Exception:
        line_count = None
    write_json(
        VOICE_TRANSCRIPT_SUMMARY_PATH,
        {
            "packet_type": "mim-voice-transcript-log-status-v1",
            "generated_at": entry["generated_at"],
            "status": "active",
            "success": True,
            "log_artifact": str(VOICE_TRANSCRIPT_LOG_PATH.relative_to(ROOT)),
            "max_lines": VOICE_TRANSCRIPT_LOG_MAX_LINES,
            "line_count": line_count,
            "last_entry": entry,
            "no_audio_retained": True,
        },
    )


def publish_cooldown_log(*, device: str, result: dict[str, Any], cooldown_seconds: int) -> None:
    if not VOICE_TRANSCRIPT_LOG_ENABLED:
        return
    entry = {
        "generated_at": now_iso(),
        "packet_type": "mim-voice-transcript-log-entry-v1",
        "audio_device": device,
        "status": "cooldown_after_response",
        "transcript": "",
        "normalized_transcript": "",
        "general_transcript": "",
        "wake_transcript": "",
        "stt_error": "",
        "audio_level": {},
        "audio_condition": {
            "clipped": False,
            "noise_risk": "unknown",
            "music_or_noise_possible": False,
            "reason": "Cooldown entry has no captured audio window.",
        },
        "vad": {"speech_detected": None, "segments": [], "artifact": str(VAD_STATUS_PATH.relative_to(ROOT))},
        "self_output_detected": False,
        "wake_phrase_detected": result.get("wake_phrase_detected", False),
        "lab_conversation_mode": result.get("lab_conversation_mode"),
        "lab_conversation_response": result.get("lab_conversation_response"),
        "lab_conversation_intent": result.get("lab_conversation_intent"),
        "lab_conversation_action": result.get("lab_conversation_action"),
        "voice_wav_output_accepted": result.get("voice_wav_output_accepted"),
        "lab_conversation_voice_wav_output_accepted": result.get("lab_conversation_voice_wav_output_accepted"),
        "cooldown_seconds": cooldown_seconds,
        "reason": "Listener is sleeping briefly after MIM speech to avoid self-triggering.",
        "no_audio_retained": True,
    }
    append_jsonl(VOICE_TRANSCRIPT_LOG_PATH, entry, max_lines=VOICE_TRANSCRIPT_LOG_MAX_LINES)
    write_json(
        VOICE_TRANSCRIPT_SUMMARY_PATH,
        {
            "packet_type": "mim-voice-transcript-log-status-v1",
            "generated_at": entry["generated_at"],
            "status": "active",
            "success": True,
            "log_artifact": str(VOICE_TRANSCRIPT_LOG_PATH.relative_to(ROOT)),
            "max_lines": VOICE_TRANSCRIPT_LOG_MAX_LINES,
            "last_entry": entry,
            "no_audio_retained": True,
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
            VOICE_PIPER_LENGTH_SCALE,
            "--noise-scale",
            VOICE_PIPER_NOISE_SCALE,
            "--noise-w-scale",
            VOICE_PIPER_NOISE_W_SCALE,
            "--volume",
            VOICE_PIPER_VOLUME,
        ]
        if VOICE_PIPER_SPEAKER:
            command.extend(["--speaker", VOICE_PIPER_SPEAKER])
        result = run_command(command, timeout=30)
        return {
            "ok": bool(result["ok"] and output_path.exists() and output_path.stat().st_size > 1000),
            "voice_engine": "piper",
            "voice_model": str(PIPER_MODEL_PATH.relative_to(ROOT)),
            "output_wav": str(output_path.relative_to(ROOT)),
            "command": result.get("command"),
            "returncode": result.get("returncode"),
            "speaker": VOICE_PIPER_SPEAKER,
            "length_scale": VOICE_PIPER_LENGTH_SCALE,
            "noise_scale": VOICE_PIPER_NOISE_SCALE,
            "noise_w_scale": VOICE_PIPER_NOISE_W_SCALE,
            "volume": VOICE_PIPER_VOLUME,
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


def load_shared_json(name: str) -> dict[str, Any]:
    path = SHARED / name
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def load_runtime_json(relative_path: str) -> dict[str, Any]:
    path = ROOT / relative_path
    try:
        if path.exists():
            payload = json.loads(path.read_text(encoding="utf-8-sig"))
            return payload if isinstance(payload, dict) else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def compact_status(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    text = str(value or "").strip()
    return text if text else "unknown"


def parse_utc_timestamp(value: Any) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def operator_timezone() -> ZoneInfo:
    try:
        return ZoneInfo(OPERATOR_TIMEZONE)
    except Exception:
        return ZoneInfo("America/Los_Angeles")


def format_operator_time(value: datetime | None) -> str:
    if value is None:
        return "unknown PT"
    local = value.astimezone(operator_timezone())
    hour = local.strftime("%I").lstrip("0") or "0"
    suffix = local.tzname() or "PT"
    return f"{hour}:{local.strftime('%M %p')} {suffix}"


def compact_duration(seconds: float | int | None) -> str:
    if seconds is None:
        return "unknown"
    remaining = max(0, int(seconds))
    hours, remainder = divmod(remaining, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours:
        return f"{hours} hours, {minutes} minutes"
    if minutes:
        return f"{minutes} minutes, {secs} seconds"
    return f"{secs} seconds"


def transcript_words(transcript: str) -> list[str]:
    return re.findall(r"[a-zA-Z0-9']+", str(transcript or "").lower())


def normalize_voice_transcript_for_intent(transcript: str) -> str:
    normalized = re.sub(r"[^a-zA-Z0-9.' ]+", " ", str(transcript or "")).strip().lower()
    normalized = re.sub(r"\bunk\b", " ", normalized)
    normalized = re.sub(r"\b(ma'?am|mam|mom|mem|men|min|mime|memoir)\b", "mim", normalized)
    normalized = re.sub(r"\btrying\s+on\b", "training on", normalized)
    normalized = re.sub(r"\btry\s+on\b", "training on", normalized)
    normalized = re.sub(r"\btaught\s+would\s+be\s+on\b", "training on", normalized)
    normalized = re.sub(r"\bnewborn\b", "mim", normalized)
    normalized = re.sub(r"\bmove\s+our\b", "improve", normalized)
    normalized = re.sub(r"\bwork\s+on\s+new\s+improve\b", "what do you need to improve", normalized)
    normalized = re.sub(r"\bthere\s+will\s+be\s+working\b", "what are you working on", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized


def is_training_topic(topic: str) -> bool:
    return str(topic or "").strip() in {"training_topic_status", "training_time_status"}


def select_effective_transcript(text: str, wake_text: str) -> str:
    general = str(text or "").strip()
    wake = str(wake_text or "").strip()
    if wake and has_mim_reference(wake) and general and not has_mim_reference(general):
        return f"{wake} {general}".strip()
    if wake and has_mim_reference(wake) and not general:
        return wake
    if general and wake and detect_wake(wake) and classify_voice_fragment(general).get("is_fragment"):
        return wake
    return general or wake


def has_mim_reference(transcript: str) -> bool:
    words = set(transcript_words(str(transcript or "").replace("ma'am", "maam")))
    if words.intersection(MIM_REFERENCE_TOKENS):
        return True
    normalized = re.sub(r"[^a-zA-Z0-9.' ]+", " ", str(transcript or "")).strip().lower()
    return bool(re.search(r"\bm[.\s]*i[.\s]*m\b", normalized))


def is_assistant_shaped(transcript: str) -> bool:
    normalized = re.sub(r"[^a-zA-Z0-9.' ]+", " ", str(transcript or "")).strip().lower()
    return bool(
        re.search(
            r"\b(can you|could you|would you|will you|please|what|how|why|when|where|who|"
            r"do you know|are you familiar|i'?m asking|tell me|show me|check|start|stop|pause|resume|remember|note this|status|"
            r"look|listen|find|open|close|run|execute|turn on|turn off)\b",
            normalized,
        )
    )


def classify_voice_fragment(transcript: str) -> dict[str, Any]:
    words = transcript_words(transcript)
    if not words:
        return {"is_fragment": True, "reason_code": "empty_transcript", "word_count": 0, "words": []}
    if has_mim_reference(transcript):
        return {"is_fragment": False, "reason_code": "mim_reference_is_addressing_signal", "word_count": len(words), "words": words}
    unique = set(words)
    if len(words) == 1 and words[0] in LOW_CONTENT_TOKENS:
        return {"is_fragment": True, "reason_code": "single_low_content_token", "word_count": 1, "words": words}
    if len(words) <= 2 and not unique.intersection(ACTIONABLE_TOKENS):
        return {"is_fragment": True, "reason_code": "short_non_actionable_transcript", "word_count": len(words), "words": words}
    return {"is_fragment": False, "reason_code": "actionable_or_contextual_transcript", "word_count": len(words), "words": words}


def classify_transcript_quality(transcript: str) -> dict[str, Any]:
    raw = str(transcript or "").strip()
    normalized = normalize_voice_transcript_for_intent(raw)
    raw_words = transcript_words(raw)
    words = transcript_words(normalized)
    unk_count = len(re.findall(r"\[unk\]|\bunk\b", raw, flags=re.I))
    meaningful = [
        word
        for word in words
        if word not in LOW_CONTENT_TOKENS and word not in MIM_REFERENCE_TOKENS and len(word) > 1
    ]
    suspicious_phrases = [
        "for you spell out no",
        "whoa elbow",
        "what bird roads other two",
        "or the move our",
        "the parents who we have",
        "you know if the newborn is",
    ]
    whisper_hallucination_phrases = [
        "thanks for watching",
        "thank you very much",
        "heh heh",
        "posho",
        "pizza with boys",
        "okay. okay",
        "okay okay",
        "we'll see you next week",
        "we will see you next week",
        "see you next week",
        "my little eye",
        "i'm all good i'm all good",
        "i'm all good. i'm all good",
        "easy easy",
    ]
    reasons: list[str] = []
    if unk_count >= 2:
        reasons.append("multiple_unknown_tokens")
    if unk_count >= 1 and len(meaningful) < 4:
        reasons.append("unknown_token_with_low_content")
    if any(phrase in normalized for phrase in suspicious_phrases):
        reasons.append("known_garbled_stt_phrase")
    if any(phrase in normalized for phrase in whisper_hallucination_phrases):
        reasons.append("known_whisper_hallucination_phrase")
    if re.search(r"\b(\w+)(?:[.!?, ]+\1){2,}\b", normalized):
        reasons.append("repeated_token_hallucination")
    sentence_parts = [part.strip() for part in re.split(r"[.!?]+", normalized) if part.strip()]
    if len(sentence_parts) >= 2 and len(set(sentence_parts)) < len(sentence_parts):
        reasons.append("repeated_sentence_hallucination")
    if len(raw_words) >= 4 and len(meaningful) <= 1:
        reasons.append("low_meaningful_word_count")
    if re.search(r"\b(the|a)\s+\w+\s+(who|what|where|when|why|how)\s+(we|you|i)\s+(have|do|are|is)\b", normalized):
        reasons.append("question_shaped_stt_gibberish")
    if len(words) >= 5:
        common_words = {"the", "to", "of", "and", "or", "is", "it", "you", "me", "what", "how", "would", "like"}
        odd_words = [word for word in words if word not in common_words and word not in MIM_REFERENCE_TOKENS]
        if len(odd_words) >= 4 and not set(words).intersection(ACTIONABLE_TOKENS):
            reasons.append("no_actionable_tokens_in_long_phrase")
    status = "low_confidence" if reasons else "usable"
    return {
        "status": status,
        "usable": status == "usable",
        "reason_codes": reasons,
        "unknown_token_count": unk_count,
        "word_count": len(words),
        "meaningful_word_count": len(meaningful),
        "normalized_transcript": normalized,
    }


def should_observe_low_confidence_transcript(transcript: str, quality: dict[str, Any]) -> bool:
    reasons = set(quality.get("reason_codes") or [])
    if has_mim_reference(transcript) or is_assistant_shaped(transcript):
        return False
    return bool(
        reasons.intersection(
            {
                "known_whisper_hallucination_phrase",
                "repeated_token_hallucination",
                "repeated_sentence_hallucination",
            }
        )
    )


def build_transcript_clarification_route(transcript: str, quality: dict[str, Any]) -> dict[str, Any]:
    write_json(
        SHARED / "MIM_VOICE_TRANSCRIPT_QUALITY.latest.json",
        {
            "packet_type": "mim-voice-transcript-quality-v1",
            "generated_at": now_iso(),
            "status": "clarification_required",
            "success": True,
            "transcript": transcript,
            "quality": quality,
            "policy": "Low-confidence STT is not forwarded to UI chat as if it were reliable operator intent.",
            "no_audio_retained": True,
        },
    )
    return {
        "intent": "voice_transcript_unclear",
        "action": "ask_operator_to_repeat_unclear_voice_turn",
        "response_text": "Dave, I caught pieces of that, but not enough to answer cleanly. Say that last part again.",
        "artifacts": ["runtime/shared/MIM_VOICE_TRANSCRIPT_QUALITY.latest.json"],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "low_confidence_transcript"},
        "fallback_used": True,
        "transcript_quality": quality,
    }


def should_suppress_fragment_before_chat(transcript: str, classification: dict[str, Any], addressing: dict[str, Any]) -> bool:
    if not classification.get("is_fragment"):
        return False
    if has_mim_reference(transcript):
        return False
    reason = str(addressing.get("reason_code") or "").strip()
    return reason in {
        "active_mim_conversation_window",
        "short_followup_to_existing_voice_topic",
        "assistant_shaped_speech_in_mim_lab",
    }


def classify_interaction_feedback(transcript: str) -> dict[str, Any]:
    normalized = re.sub(r"[^a-zA-Z0-9.' ]+", " ", str(transcript or "")).strip().lower()
    if not normalized:
        return {"is_feedback": False, "feedback_type": ""}
    if re.search(r"\b(off the phone|done with (the )?(phone|call)|call is over|you can talk now|back from (the )?call)\b", normalized):
        return {
            "is_feedback": True,
            "feedback_type": "phone_call_ended",
            "lesson": "When Dave says the call is over, clear phone-call quiet mode and resume normal voice participation.",
            "addressing_adjustment": "clear_phone_quiet_mode",
        }
    if re.search(r"\b(i did not say anything|i didn't say anything|didn't say anything|did not say anything)\b", normalized):
        return {
            "is_feedback": True,
            "feedback_type": "false_speech_detection",
            "lesson": "If Dave reports he did not speak, mark the prior transcript as likely false STT or self/noise capture.",
            "addressing_adjustment": "log_false_positive",
        }
    if re.search(r"\b(i did not say|i didn't say|not mom|didn't say mom|did not say mom).*\b(mim|m\.?i\.?m\.?)\b", normalized) or re.search(
        r"\bi said\s+(mim|m\.?i\.?m\.?)\b", normalized
    ):
        return {
            "is_feedback": True,
            "feedback_type": "mim_name_correction",
            "lesson": "When STT hears mom/mam/min near a direct-address phrase, treat it as likely MIM unless the speaker explicitly says otherwise.",
            "addressing_adjustment": "increase_mim_like_confidence",
        }
    if re.search(r"\b(on the phone|phone call|taking a call|in a call)\b", normalized):
        return {
            "is_feedback": True,
            "feedback_type": "not_for_mim_phone_call",
            "lesson": "When Dave says he is on the phone, suppress active-session participation unless he explicitly addresses MIM.",
            "addressing_adjustment": "suppress_active_session_until_expiry",
        }
    if re.search(r"\b(me and|i and|we are|we're)\s+([a-z][a-z]+).*\b(talking|having a conversation)\b", normalized) or re.search(
        r"\b(talking to|talking with)\s+([a-z][a-z]+)\b", normalized
    ):
        return {
            "is_feedback": True,
            "feedback_type": "human_to_human_conversation",
            "lesson": "When Dave identifies a human-to-human conversation, observe unless MIM is explicitly addressed.",
            "addressing_adjustment": "suppress_active_session_until_expiry",
        }
    if re.search(r"\b(thinking out loud|thinking outloud|just thinking|talking to myself)\b", normalized):
        return {
            "is_feedback": True,
            "feedback_type": "thinking_out_loud",
            "lesson": "Thinking-out-loud speech should be observed, not answered, unless MIM is explicitly addressed.",
            "addressing_adjustment": "suppress_active_session_until_expiry",
        }
    if re.search(r"\b(that was not|that wasn't|was not|wasn't).*\b(question|for you|intended for you)\b", normalized):
        return {
            "is_feedback": True,
            "feedback_type": "not_addressed_to_mim",
            "lesson": "If Dave says the prior utterance was not for MIM or not a question, reduce follow-up confidence for similar ambient statements.",
            "addressing_adjustment": "suppress_active_session_until_expiry",
        }
    return {"is_feedback": False, "feedback_type": ""}


def load_interaction_learning() -> dict[str, Any]:
    data = load_shared_json("MIM_VOICE_INTERACTION_LEARNING.latest.json")
    if isinstance(data, dict) and data:
        return data
    return {
        "packet_type": "mim-voice-interaction-learning-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1",
        "status": "active",
        "success": True,
        "lessons": [],
        "active_overrides": {},
        "no_audio_retained": True,
    }


def save_interaction_feedback(transcript: str, feedback: dict[str, Any]) -> dict[str, Any]:
    learning = load_interaction_learning()
    previous_lessons = learning.get("lessons") if isinstance(learning.get("lessons"), list) else []
    now_dt = datetime.now(timezone.utc)
    expires_at = now_dt.timestamp() + max(30, LEARNING_SUPPRESSION_SECONDS)
    expires_iso = datetime.fromtimestamp(expires_at, timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    active_overrides = learning.get("active_overrides") if isinstance(learning.get("active_overrides"), dict) else {}
    adjustment = str(feedback.get("addressing_adjustment") or "")
    if adjustment == "suppress_active_session_until_expiry":
        active_overrides["suppress_active_session_until"] = expires_iso
        active_overrides["suppress_reason"] = feedback.get("feedback_type")
        if feedback.get("feedback_type") == "not_for_mim_phone_call":
            active_overrides["phone_quiet_mode"] = True
            active_overrides["phone_quiet_started_at"] = now_iso()
    elif adjustment == "increase_mim_like_confidence":
        active_overrides["mim_like_reference_correction"] = True
    elif adjustment == "log_false_positive":
        active_overrides["last_false_speech_detection_at"] = now_iso()
    elif adjustment == "clear_phone_quiet_mode":
        active_overrides["phone_quiet_mode"] = False
        active_overrides["phone_quiet_cleared_at"] = now_iso()
        active_overrides.pop("suppress_active_session_until", None)
        active_overrides.pop("suppress_reason", None)
    lesson = {
        "generated_at": now_iso(),
        "speaker": "Dave",
        "transcript": transcript,
        "feedback_type": feedback.get("feedback_type"),
        "lesson": feedback.get("lesson"),
        "addressing_adjustment": adjustment,
        "expires_at": expires_iso if adjustment == "suppress_active_session_until_expiry" else "",
    }
    payload = {
        "packet_type": "mim-voice-interaction-learning-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1",
        "status": "updated",
        "success": True,
        "last_feedback": lesson,
        "lessons": (previous_lessons + [lesson])[-50:],
        "active_overrides": active_overrides,
        "policy": "Operator corrections are durable learning signals for future voice addressing decisions.",
        "no_audio_retained": True,
    }
    write_json(VOICE_INTERACTION_LEARNING_PATH, payload)
    return payload


def learning_suppresses_active_session(learning: dict[str, Any]) -> tuple[bool, str, str]:
    overrides = learning.get("active_overrides") if isinstance(learning.get("active_overrides"), dict) else {}
    if bool(overrides.get("do_not_disturb_mode")):
        return True, "do_not_disturb_mode", str(overrides.get("do_not_disturb_started_at") or "")
    if bool(overrides.get("phone_quiet_mode")):
        return True, "phone_quiet_mode", str(overrides.get("phone_quiet_started_at") or "")
    until = parse_utc_timestamp(overrides.get("suppress_active_session_until"))
    if until and until > datetime.now(timezone.utc):
        return True, str(overrides.get("suppress_reason") or "operator_feedback"), until.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return False, "", ""


def build_lab_conversation_scene(transcript: str, vad: dict[str, Any] | None = None, audio_level: dict[str, Any] | None = None) -> dict[str, Any]:
    awareness = load_shared_json("MIM_LAB_AWARENESS_STATUS.latest.json")
    camera = load_shared_json("MIM_LAB_CAMERA_CYCLE_STATUS.latest.json")
    memory = load_shared_json("MIM_HUMAN_INTERACTION_MEMORY.latest.json")
    generated_at = now_iso()
    awareness_at = parse_utc_timestamp(awareness.get("generated_at"))
    camera_at = parse_utc_timestamp(camera.get("generated_at"))
    now = datetime.now(timezone.utc)
    camera_age_seconds = (now - camera_at).total_seconds() if camera_at else None
    awareness_age_seconds = (now - awareness_at).total_seconds() if awareness_at else None
    known_humans = []
    for record in memory.get("memory_records", []) if isinstance(memory.get("memory_records"), list) else []:
        name = str(record.get("human_name") or "").strip()
        if name and name not in known_humans:
            known_humans.append(name)
    scene = {
        "packet_type": "mim-lab-conversation-scene-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1",
        "status": "observed_with_limited_scene_evidence",
        "success": True,
        "transcript": transcript,
        "human_count": "unknown",
        "known_humans": known_humans or ["Dave"],
        "primary_operator": "Dave",
        "conversation_mode": "single_speaker_or_unknown",
        "camera_fresh": bool(camera_age_seconds is not None and camera_age_seconds <= 120),
        "camera_age_seconds": camera_age_seconds,
        "awareness_fresh": bool(awareness_age_seconds is not None and awareness_age_seconds <= 120),
        "awareness_age_seconds": awareness_age_seconds,
        "vad": vad or {},
        "audio_level": audio_level or {},
        "source_artifacts": [
            "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
            "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
            "runtime/shared/MIM_HUMAN_INTERACTION_MEMORY.latest.json",
        ],
        "next_recovery_action": "Bind fresh camera human-count evidence so MIM can distinguish direct address from humans talking to each other.",
        "no_audio_retained": True,
    }
    write_json(LAB_CONVERSATION_SCENE_PATH, scene)
    return scene


def decide_voice_addressing(transcript: str, *, scene: dict[str, Any], source: str) -> dict[str, Any]:
    words = transcript_words(transcript)
    mim_reference = has_mim_reference(transcript)
    assistant_shape = is_assistant_shaped(transcript)
    feedback = classify_interaction_feedback(transcript)
    learning = load_interaction_learning()
    suppress_active, suppress_reason, suppress_until = learning_suppresses_active_session(learning)
    turn_state = load_turn_state()
    previous_topic = str(turn_state.get("current_topic") or "").strip()
    active_until = parse_utc_timestamp(turn_state.get("active_conversation_until"))
    active_session = bool(active_until and active_until > datetime.now(timezone.utc) and not suppress_active)
    followup_reference = bool(set(words).intersection(FOLLOWUP_REFERENCE_TOKENS))
    short_followup = bool(previous_topic and 1 <= len(words) <= 5 and followup_reference and not mim_reference)
    actionable_followup = assistant_shape or short_followup
    if feedback.get("is_feedback"):
        addressed = True
        confidence = 0.99
        reason = f"operator_feedback_{feedback.get('feedback_type')}"
        action = "learn_from_feedback"
    elif suppress_active:
        addressed = False
        confidence = 0.98
        reason = f"operator_learning_suppression_{suppress_reason}"
        action = "observe"
    elif mim_reference:
        addressed = True
        confidence = 0.995
        reason = "mim_or_mim_like_reference"
        action = "respond"
    elif active_session and actionable_followup:
        addressed = True
        confidence = 0.9 if assistant_shape else 0.78
        reason = "active_mim_conversation_window"
        action = "respond"
    elif active_session:
        addressed = False
        confidence = 0.62
        reason = "active_session_ambient_or_low_intent_speech"
        action = "observe"
    elif assistant_shape:
        addressed = True
        confidence = 0.82
        reason = "assistant_shaped_speech_in_mim_lab"
        action = "respond"
    elif short_followup:
        addressed = True
        confidence = 0.72
        reason = "short_followup_to_existing_voice_topic"
        action = "respond"
    elif scene.get("conversation_mode") == "multiple_humans_uncertain":
        addressed = False
        confidence = 0.55
        reason = "multiple_humans_without_mim_reference"
        action = "ask_if_addressed"
    else:
        addressed = False
        confidence = 0.35
        reason = "ambient_non_direct_speech"
        action = "observe"
    decision = {
        "packet_type": "mim-voice-addressing-decision-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1",
        "status": "addressed" if addressed else "not_addressed",
        "success": True,
        "source": source,
        "transcript": transcript,
        "addressed_to_mim": addressed,
        "confidence": confidence,
        "reason_code": reason,
        "recommended_action": action,
        "mim_reference_detected": mim_reference,
        "assistant_shaped": assistant_shape,
        "operator_feedback": feedback,
        "learning_suppressed_active_session": suppress_active,
        "learning_suppression_reason": suppress_reason,
        "learning_suppression_until": suppress_until,
        "learning_artifact": str(VOICE_INTERACTION_LEARNING_PATH.relative_to(ROOT)),
        "active_session": active_session,
        "active_conversation_until": active_until.replace(microsecond=0).isoformat().replace("+00:00", "Z") if active_until else "",
        "short_followup": short_followup,
        "followup_reference": followup_reference,
        "actionable_followup": actionable_followup,
        "scene_artifact": str(LAB_CONVERSATION_SCENE_PATH.relative_to(ROOT)),
        "policy": "MIM-like words are treated as direct address; assistant-shaped speech in the lab is presumed for MIM unless scene evidence shows humans talking to each other.",
        "no_audio_retained": True,
    }
    write_json(VOICE_ADDRESSING_DECISION_PATH, decision)
    return decision


def publish_conversation_control_objective() -> None:
    write_json(
        VOICE_CONTROL_OBJECTIVE_PATH,
        {
            "packet_type": "mim-lab-conversation-control-layer-objective-v1",
            "generated_at": now_iso(),
            "objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1",
            "status": "active",
            "success": True,
            "goal": "Route lab speech through a conversation control layer before response generation.",
            "required_outputs": [
                "MIM_VOICE_ADDRESSING_DECISION.latest.json",
                "MIM_LAB_CONVERSATION_SCENE.latest.json",
                "MIM_VOICE_INTERACTION_LEARNING.latest.json",
                "MIM_WAKE_FOLLOWUP.latest.json",
            ],
            "policies": [
                "Treat MIM-like words such as mom, mam, maam, mem, min, and meme as likely references to MIM.",
                "After MIM is addressed or responds, keep a short active conversation window so follow-ups do not require repeating MIM.",
                "When the operator says they are on a phone call, enter phone quiet mode until the operator explicitly says the call is over.",
                "Presume assistant-shaped speech in MIM's lab is addressed to MIM unless fresh scene evidence indicates a human-to-human conversation.",
                "Observe non-direct ambient speech without sending it to the UI chat brain.",
                "Ask a short clarification when scene evidence indicates multiple humans and the addressee is ambiguous.",
                "Treat operator corrections as learning data that can suppress or adjust future addressing decisions.",
            ],
            "success_criteria": [
                "Every heard lab utterance publishes an addressing decision.",
                "Every heard lab utterance publishes a conversation scene snapshot.",
                "Low-content MIM-name utterances are not suppressed as fragments.",
                "Follow-ups inside the active conversation window are addressed to MIM without repeating her name.",
                "Operator feedback such as phone-call, thinking-out-loud, not-for-MIM, and name-correction phrases updates the learning artifact.",
                "Non-addressed ambient speech is logged without a spoken generic clarification.",
            ],
            "no_audio_retained": True,
        },
    )


def publish_fragment_suppression(transcript: str, classification: dict[str, Any], *, source: str) -> None:
    if not VOICE_FRAGMENT_SUPPRESSION_ENABLED:
        return
    write_json(
        VOICE_FRAGMENT_SUPPRESSION_PATH,
        {
            "packet_type": "mim-voice-fragment-suppression-status-v1",
            "generated_at": now_iso(),
            "status": "suppressed_with_evidence",
            "success": True,
            "source": source,
            "transcript": transcript,
            "classification": classification,
            "policy": "Low-content STT fragments are logged but not forwarded to UI chat or spoken back as a full MIM turn.",
            "next_recovery_action": "Improve microphone placement/gain or STT segmentation when repeated suppression coincides with operator speech.",
            "no_audio_retained": True,
        },
    )


def concise_voice_text(text: str, *, max_chars: int = 260) -> str:
    cleaned = re.sub(r"\s+", " ", str(text or "")).strip()
    if not cleaned:
        return ""
    # UI chat sometimes prefixes the session display name; voice should not.
    cleaned = re.sub(r"^(giving some extra context|dave|operator)\s*,\s*", "", cleaned, flags=re.I)
    # Some gateway replies include a leaked planning/status prefix that sounds awful over TTS.
    cleaned = re.sub(r"^(thinking of it'?s not|thinking of its not)\s*,?\s*", "", cleaned, flags=re.I)
    cleaned = re.sub(r"^(thinking of it'?s not|thinking of its not)\b[:;,.-]?\s*", "", cleaned, flags=re.I)
    sentences = re.split(r"(?<=[.!?])\s+", cleaned)
    short = " ".join([item for item in sentences if item][:3]).strip()
    if len(short) > max_chars:
        short = short[: max_chars - 1].rstrip() + "."
    return short


def extract_mim_chat_reply(payload: dict[str, Any]) -> str:
    resolution = payload.get("resolution") if isinstance(payload.get("resolution"), dict) else {}
    metadata = resolution.get("metadata_json") if isinstance(resolution.get("metadata_json"), dict) else {}
    candidates = [
        metadata.get("mim_interface_reply_override"),
        metadata.get("reply_text"),
        resolution.get("clarification_prompt"),
        payload.get("reply_text"),
    ]
    for candidate in candidates:
        text = concise_voice_text(str(candidate or ""))
        if text:
            return text
    return ""


def build_training_time_route() -> dict[str, Any]:
    voice = load_shared_json("MIM_VOICE_CONTEXT_12H_BUILD_STATUS.latest.json")
    tod = load_shared_json("TOD_TRAINING_STATUS.latest.json")
    now = datetime.now(timezone.utc)
    artifacts = [
        "runtime/shared/MIM_VOICE_CONTEXT_12H_BUILD_STATUS.latest.json",
        "runtime/shared/MIM_VOICE_CONTEXT_NEXT_OBJECTIVE.latest.json",
        "runtime/shared/TOD_TRAINING_STATUS.latest.json",
    ]
    if isinstance(voice, dict) and voice:
        deadline = parse_utc_timestamp(voice.get("deadline_at"))
        remaining_seconds = (deadline - now).total_seconds() if deadline else None
        current = voice.get("current_objective") if isinstance(voice.get("current_objective"), dict) else {}
        missing = voice.get("missing") if isinstance(voice.get("missing"), list) else []
        if deadline and remaining_seconds <= 0:
            response = (
                f"The 12 hour voice build window hit its deadline at {format_operator_time(deadline)}. "
                f"Last status was {compact_status(voice.get('status'))} at {compact_status(voice.get('percent_complete'))} percent. "
                f"I'm still missing {', '.join(str(item) for item in missing) or 'no listed checks'}."
            )
        else:
            response = (
                f"About {compact_duration(remaining_seconds)} left in the 12 hour voice build. "
                f"Deadline is {format_operator_time(deadline)}. "
                f"I'm at {compact_status(voice.get('percent_complete'))} percent, working on "
                f"{compact_status(current.get('objective_id'))}."
            )
        return {
            "intent": "training_time_status",
            "action": "summarize_voice_context_training_time",
            "response_text": response[:260],
            "artifacts": artifacts,
            "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_local_training_time_route"},
            "fallback_used": True,
        }
    if isinstance(tod, dict) and tod:
        eta = tod.get("eta_seconds")
        response = (
            f"TOD training is at {compact_status(tod.get('percent_complete'))} percent. "
            f"Estimated time left is {compact_duration(eta)}."
        )
        return {
            "intent": "training_time_status",
            "action": "summarize_tod_training_time",
            "response_text": response[:260],
            "artifacts": ["runtime/shared/TOD_TRAINING_STATUS.latest.json"],
            "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_local_training_time_route"},
            "fallback_used": True,
        }
    return {
        "intent": "training_time_status",
        "action": "training_time_status_blocked",
        "response_text": "I do not have a fresh training-time artifact yet. I logged that as a training status visibility gap.",
        "artifacts": artifacts,
        "chat_bridge": {"ok": False, "skipped": True, "reason": "training_artifact_missing"},
        "fallback_used": True,
    }


def build_training_topic_route() -> dict[str, Any]:
    status = load_runtime_json("runtime/reports/mim_evolution_continuous_training.latest.json")
    summary = load_runtime_json("runtime/reports/mim_evolution_training_summary.json")
    conversation = summary.get("conversation") if isinstance(summary.get("conversation"), dict) else {}
    plan = status.get("cycle_plan") if isinstance(status.get("cycle_plan"), dict) else {}
    top_failures = conversation.get("top_failures") if isinstance(conversation.get("top_failures"), list) else []
    top_tags = [
        str(item.get("tag") or "").replace("_", " ")
        for item in top_failures
        if isinstance(item, dict) and str(item.get("tag") or "").strip()
    ][:3]
    profile = status.get("profile") if isinstance(status.get("profile"), dict) else {}
    label = compact_status(plan.get("label") or profile.get("label"))
    phase = compact_status(status.get("phase") or status.get("status"))
    cycle = compact_status(status.get("cycle"))
    overall = conversation.get("overall") if conversation.get("overall") is not None else plan.get("overall")
    failures = conversation.get("failure_count") if conversation.get("failure_count") is not None else plan.get("failure_count")
    scenario_count = conversation.get("scenario_count") if conversation.get("scenario_count") is not None else plan.get("scenario_count")
    if status:
        response = (
            f"I'm training cycle {cycle}: {label}. "
            f"Phase is {phase}; score is {compact_status(overall)} across {compact_status(scenario_count)} scenarios. "
            f"Main fixes: {', '.join(top_tags) if top_tags else compact_status(failures) + ' failures'}."
        )
        return {
            "intent": "training_topic_status",
            "action": "summarize_current_training_topic",
            "response_text": response[:260],
            "artifacts": [
                "runtime/reports/mim_evolution_continuous_training.latest.json",
                "runtime/reports/mim_evolution_training_summary.json",
            ],
            "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_local_training_topic_route"},
            "fallback_used": True,
        }
    return {
        "intent": "training_topic_status",
        "action": "training_topic_status_blocked",
        "response_text": "I do not have a fresh training summary artifact yet. I logged that as a training visibility gap.",
        "artifacts": ["runtime/reports/mim_evolution_continuous_training.latest.json"],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "training_artifact_missing"},
        "fallback_used": True,
    }


def build_training_quality_route() -> dict[str, Any]:
    status = load_runtime_json("runtime/reports/mim_evolution_continuous_training.latest.json")
    summary = load_runtime_json("runtime/reports/mim_evolution_training_summary.json")
    conversation = summary.get("conversation") if isinstance(summary.get("conversation"), dict) else {}
    plan = status.get("cycle_plan") if isinstance(status.get("cycle_plan"), dict) else {}
    overall = conversation.get("overall") if conversation.get("overall") is not None else plan.get("overall")
    failures = conversation.get("failure_count") if conversation.get("failure_count") is not None else plan.get("failure_count")
    scenario_count = conversation.get("scenario_count") if conversation.get("scenario_count") is not None else plan.get("scenario_count")
    top_failures = conversation.get("top_failures") if isinstance(conversation.get("top_failures"), list) else []
    top_tags = [
        str(item.get("tag") or "").replace("_", " ")
        for item in top_failures
        if isinstance(item, dict) and str(item.get("tag") or "").strip()
    ][:3]
    try:
        score = float(overall)
    except (TypeError, ValueError):
        score = 0.0
    verdict = "mixed but improving" if score >= 0.8 else "not good yet"
    response = (
        f"Mixed: score {compact_status(overall)} over {compact_status(scenario_count)} scenarios, "
        f"with {compact_status(failures)} failures. "
        f"So, {verdict}. Biggest issues are {', '.join(top_tags) if top_tags else 'not identified'}."
    )
    return {
        "intent": "training_topic_status",
        "action": "summarize_training_quality",
        "response_text": response[:260],
        "artifacts": [
            "runtime/reports/mim_evolution_continuous_training.latest.json",
            "runtime/reports/mim_evolution_training_summary.json",
        ],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_local_training_quality_route"},
        "fallback_used": True,
    }


def build_current_time_route() -> dict[str, Any]:
    now_local = datetime.now(timezone.utc).astimezone(operator_timezone())
    hour = now_local.strftime("%I").lstrip("0") or "0"
    response = f"It's {hour}:{now_local.strftime('%M %p')} {now_local.tzname() or 'PT'}."
    return {
        "intent": "current_time_status",
        "action": "answer_current_operator_time",
        "response_text": response,
        "artifacts": [],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_local_operator_time_route"},
        "fallback_used": True,
    }


def build_voice_presence_check_route(transcript: str) -> dict[str, Any]:
    normalized = normalize_voice_transcript_for_intent(transcript)
    if "see" in normalized:
        response = "I can hear this request. Camera presence is still limited by stale lab-awareness evidence, so I can't honestly say I see you yet."
        action = "answer_hear_and_camera_presence_status"
        artifacts = [
            "runtime/shared/MIM_WAKE_LISTENER_STATUS.latest.json",
            "runtime/shared/MIM_LAB_CONVERSATION_SCENE.latest.json",
            "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
        ]
    else:
        listener = load_shared_json("MIM_WAKE_LISTENER_STATUS.latest.json")
        response = f"I hear you through {compact_status(listener.get('audio_device'))}. Speech recognition is active, but still being tuned."
        action = "answer_voice_hearing_status"
        artifacts = ["runtime/shared/MIM_WAKE_LISTENER_STATUS.latest.json"]
    return {
        "intent": "voice_presence_check",
        "action": action,
        "response_text": response[:260],
        "artifacts": artifacts,
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_local_voice_presence_route"},
        "fallback_used": True,
    }


def build_voice_improvement_route() -> dict[str, Any]:
    listener = load_shared_json("MIM_WAKE_LISTENER_STATUS.latest.json")
    quality = load_shared_json("MIM_VOICE_TRANSCRIPT_QUALITY.latest.json")
    response = (
        "I need three things next: cleaner transcription, better repeat requests when STT is garbled, "
        "and fresher camera evidence so I know who is talking."
    )
    return {
        "intent": "voice_improvement_status",
        "action": "summarize_voice_improvement_priorities",
        "response_text": response,
        "artifacts": [
            "runtime/shared/MIM_WAKE_LISTENER_STATUS.latest.json",
            "runtime/shared/MIM_VOICE_TRANSCRIPT_QUALITY.latest.json",
            "runtime/shared/MIM_LAB_CONVERSATION_SCENE.latest.json",
        ],
        "chat_bridge": {
            "ok": False,
            "skipped": True,
            "reason": "handled_by_local_voice_improvement_route",
            "audio_device": listener.get("audio_device"),
            "last_quality_status": quality.get("status"),
        },
        "fallback_used": True,
    }


def build_arm_status_route() -> dict[str, Any]:
    support = load_shared_json("MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json")
    if support:
        app = support.get("arm_application") if isinstance(support.get("arm_application"), dict) else {}
        motion = support.get("motion_awareness") if isinstance(support.get("motion_awareness"), dict) else {}
        parts = support.get("parts_and_configuration") if isinstance(support.get("parts_and_configuration"), dict) else {}
        blockers = support.get("blockers") if isinstance(support.get("blockers"), list) else []
        warnings = support.get("warnings") if isinstance(support.get("warnings"), list) else []
        sync = app.get("sync_awareness") if isinstance(app.get("sync_awareness"), dict) else {}
        response = (
            f"Arm app is {compact_status(app.get('runtime'))}; serial is "
            f"{compact_status(((motion.get('serial') or {}) if isinstance(motion.get('serial'), dict) else {}).get('status'))}; "
            f"pose is {motion.get('current_pose')}. "
            f"Sync is {compact_status(sync.get('source') or app.get('sim_enabled'))}. "
            f"Parts index has {compact_status(parts.get('design_parts_count'))} design files."
        )
        if blockers:
            response += f" Watch item: {compact_status(blockers[0])}."
        elif warnings:
            response += f" Warning: {compact_status(warnings[0])}."
        return {
            "intent": "arm_development_status",
            "action": "summarize_arm_development_support_status",
            "response_text": response[:260],
            "artifacts": ["runtime/shared/MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json"],
            "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_arm_development_support_status"},
            "fallback_used": True,
        }
    camera = load_shared_json("MIM_LAB_CAMERA_CYCLE_STATUS.latest.json")
    inventory = load_shared_json("MIM_LAB_SENSOR_INVENTORY.latest.json")
    bridge = load_shared_json("MIM_ARM_CAMERA_BRIDGE_STATUS.latest.json")
    bridge_status = compact_status(bridge.get("status") if isinstance(bridge, dict) else "")
    if bridge_status == "unknown":
        bridge_status = compact_status(inventory.get("arm_camera_bridge_status") if isinstance(inventory, dict) else "")
    response = (
        "For the arm camera, I need to verify the bridge and include it in the camera cycle. "
        f"Current camera cycle is {compact_status(camera.get('status'))}; arm bridge is {bridge_status}."
    )
    return {
        "intent": "arm_camera_status",
        "action": "summarize_arm_camera_status",
        "response_text": response[:260],
        "artifacts": [
            "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
            "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json",
            "runtime/shared/MIM_ARM_CAMERA_BRIDGE_STATUS.latest.json",
        ],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_local_arm_camera_route"},
        "fallback_used": True,
    }


def build_arm_sync_assertion_route(transcript: str) -> dict[str, Any]:
    normalized = normalize_voice_transcript_for_intent(transcript)
    sync_enabled = not re.search(r"\b(off|disabled|not on|not enabled)\b", normalized)
    assertion = {
        "packet_type": "mim-arm-sync-operator-assertion-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-DEVELOPMENT-SUPPORT-V1",
        "sync_enabled": sync_enabled,
        "asserted_by": "Dave",
        "source": "mim_voice",
        "transcript": transcript,
        "policy": "Operator-visible sync assertions inform MIM's support layer, but live arm motion still requires explicit safety confirmation.",
    }
    write_json(ARM_SYNC_ASSERTION_PATH, assertion)
    support = load_shared_json("MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json")
    if isinstance(support, dict) and support:
        app = support.get("arm_application") if isinstance(support.get("arm_application"), dict) else {}
        sync_awareness = app.get("sync_awareness") if isinstance(app.get("sync_awareness"), dict) else {}
        sync_awareness.update(
            {
                "sync_confirmed": sync_enabled,
                "source": "fresh_operator_voice_assertion" if sync_enabled else "operator_voice_assertion_off",
                "operator_assertion": {
                    "present": True,
                    "sync_enabled": sync_enabled,
                    "generated_at": assertion["generated_at"],
                    "age_seconds": 0,
                    "transcript": transcript,
                },
            }
        )
        app["sync_awareness"] = sync_awareness
        support["arm_application"] = app
        warnings = support.get("warnings") if isinstance(support.get("warnings"), list) else []
        warnings = [item for item in warnings if item != "sync_mode_not_confirmed_by_arm_state"]
        if not sync_enabled and "operator_asserted_sync_off" not in warnings:
            warnings.append("operator_asserted_sync_off")
        support["warnings"] = warnings
        write_json(SHARED / "MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json", support)
    state = "on" if sync_enabled else "off"
    response = f"Got it. I will treat live sync as {state}, and I will still ask before any arm movement."
    return {
        "intent": "arm_sync_operator_assertion",
        "action": f"record_live_sync_{state}",
        "response_text": response,
        "artifacts": ["runtime/shared/MIM_ARM_SYNC_OPERATOR_ASSERTION.latest.json"],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "recorded_operator_sync_assertion"},
        "fallback_used": True,
    }


def extract_arm_motion_request(transcript: str) -> dict[str, Any]:
    normalized = normalize_voice_transcript_for_intent(transcript)
    joint_aliases = {
        "base": "base",
        "shoulder": "shoulder",
        "elbow": "elbow",
        "forearm": "elbow",
        "wrist": "wrist",
        "hand": "hand",
        "grip": "claw",
        "gripper": "claw",
        "claw": "claw",
    }
    joint = ""
    for alias, canonical in joint_aliases.items():
        if re.search(rf"\b{re.escape(alias)}\b", normalized):
            joint = canonical
            break
    if not joint:
        return {}
    direction = ""
    if joint == "claw":
        if re.search(r"\b(open|opened|opening)\b", normalized):
            direction = "open"
        elif re.search(r"\b(close|closed|closing|shut)\b", normalized):
            direction = "close"
    for candidate in ["right", "left", "forward", "back", "up", "down", "open", "close"]:
        if direction:
            break
        if re.search(rf"\b{candidate}\b", normalized):
            direction = candidate
            break
    amount = 0
    match = re.search(r"\b(\d{1,3})\s*(?:degree|degrees|deg)?\b", normalized)
    if match:
        amount = int(match.group(1))
    if joint == "claw" and direction in {"open", "close"} and amount == 0:
        amount = 10
    if joint == "claw" and re.search(r"\b(all the way|fully|full)\b", normalized):
        amount = 10
    if not direction and re.search(r"\b(open|close)\b", normalized) and joint == "claw":
        direction = "open" if "open" in normalized else "close"
    if not direction:
        return {}
    return {"joint": joint, "direction": direction, "degrees": amount or 5}


def build_arm_motion_proposal_route(transcript: str) -> dict[str, Any]:
    request = extract_arm_motion_request(transcript)
    support = load_shared_json("MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json")
    app = support.get("arm_application") if isinstance(support.get("arm_application"), dict) else {}
    motion = support.get("motion_awareness") if isinstance(support.get("motion_awareness"), dict) else {}
    blockers = support.get("blockers") if isinstance(support.get("blockers"), list) else []
    warnings = support.get("warnings") if isinstance(support.get("warnings"), list) else []
    current_pose = motion.get("current_pose") if isinstance(motion.get("current_pose"), list) else []
    joint_map = motion.get("joint_map") if isinstance(motion.get("joint_map"), dict) else {}
    serial = motion.get("serial") if isinstance(motion.get("serial"), dict) else {}
    degrees = abs(int(request.get("degrees") or 5))
    joint = str(request.get("joint") or "")
    direction = str(request.get("direction") or "")
    joint_index = joint_map.get(joint)
    current_value = current_pose[joint_index] if isinstance(joint_index, int) and 0 <= joint_index < len(current_pose) else None
    direction_mapped = direction_delta_sign(direction, joint_index, motion.get("servo_config") if isinstance(motion.get("servo_config"), list) else []) is not None
    simulation_safety = evaluate_arm_sim_move_safety(
        joint_index,
        int(current_value) if isinstance(current_value, (int, float)) else None,
        direction,
        degrees,
        motion.get("servo_config") if isinstance(motion.get("servo_config"), list) else [],
    )
    status = "awaiting_operator_safety_confirmation"
    if blockers:
        status = "blocked_needs_attention_before_motion"
    elif not direction_mapped:
        status = "blocked_needs_direction_mapping"
    elif simulation_safety.get("blocked"):
        status = "blocked_by_sim_workspace_safety"
    proposal = {
        "packet_type": "mim-arm-motion-proposal-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-DEVELOPMENT-SUPPORT-V1",
        "status": status,
        "success": True,
        "source": "mim_voice",
        "transcript": transcript,
        "proposal": {
            "joint": joint,
            "joint_index": joint_index,
            "direction": direction,
            "degrees": degrees,
            "current_value": current_value,
            "execution": "not_executed",
            "requires_operator_confirmation": True,
            "direction_mapped": direction_mapped,
            "simulation_safety": simulation_safety,
        },
        "arm_application": app,
        "serial": serial,
        "blockers": blockers,
        "warnings": warnings,
        "policy": "Voice arm motion requests become proposals until Dave confirms; degrees are bounded by servo limits and sim-space safety, not a fixed 10 degree cap.",
    }
    write_json(ARM_MOTION_PROPOSAL_PATH, proposal)
    if blockers:
        response = f"I prepared the {joint} {degrees} degree {direction} proposal, but I see {compact_status(blockers[0])}. Let's troubleshoot before moving."
    elif not direction_mapped:
        response = f"I know {joint}, but {direction} is not mapped for that joint. Use one of the configured directions for that servo."
    elif simulation_safety.get("blocked"):
        reason = compact_status(simulation_safety.get("reason_code"))
        response = f"I blocked that {joint} move because sim-space safety reports {reason}."
        if simulation_safety.get("warning"):
            response += f" {simulation_safety.get('warning')}"
    else:
        response = f"Dave, I am going to move the {joint} {degrees} degrees {direction}. Is that a safe move?"
        if simulation_safety.get("warning"):
            response += f" {simulation_safety.get('warning')}"
        if warnings:
            response += f" I still see {compact_status(warnings[0])}."
    return {
        "intent": "arm_motion_safety_proposal",
        "action": status,
        "response_text": response[:260],
        "artifacts": [
            "runtime/shared/MIM_ARM_MOTION_PROPOSAL.latest.json",
            "runtime/shared/MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json",
        ],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "operator_confirmation_required_before_arm_motion"},
        "fallback_used": True,
    }


def build_arm_workspace_exploration_route(transcript: str) -> dict[str, Any]:
    coordinator = ROOT / "scripts" / "mim_arm_sim_sync_space_coordinator.py"
    perception = ROOT / "scripts" / "mim_arm_table_scene_perception.py"
    python_bin = ROOT / ".venv" / "bin" / "python"
    command = [str(python_bin if python_bin.exists() else "python3"), str(coordinator), "--explore-area"]
    run_result: dict[str, Any] = {
        "command": command,
        "returncode": None,
        "stdout_tail": "",
        "stderr_tail": "",
        "error": "",
    }
    try:
        completed = subprocess.run(command, capture_output=True, text=True, timeout=75, check=False)
        run_result.update(
            {
                "returncode": completed.returncode,
                "stdout_tail": completed.stdout[-2000:],
                "stderr_tail": completed.stderr[-2000:],
            }
        )
    except Exception as exc:
        run_result["error"] = f"{type(exc).__name__}: {exc}"
    normalized = normalize_voice_transcript_for_intent(transcript)
    perception_result: dict[str, Any] = {}
    if re.search(r"\b(table|workspace|arm workspace)\b", normalized) and perception.exists():
        perception_command = ["python3", str(perception), "--query", transcript]
        try:
            completed = subprocess.run(perception_command, capture_output=True, text=True, timeout=30, check=False)
            perception_result = {
                "command": perception_command,
                "returncode": completed.returncode,
                "stdout_tail": completed.stdout[-1200:],
                "stderr_tail": completed.stderr[-1200:],
            }
        except Exception as exc:
            perception_result = {"command": perception_command, "error": f"{type(exc).__name__}: {exc}"}

    exploration = load_shared_json("MIM_ARM_AREA_EXPLORATION.latest.json")
    table_scene = load_shared_json("MIM_ARM_TABLE_SCENE.latest.json")
    status = str(exploration.get("status") or "unknown")
    success = exploration.get("success") is True
    blockers = exploration.get("blockers") if isinstance(exploration.get("blockers"), list) else []
    viewpoints = exploration.get("viewpoints") if isinstance(exploration.get("viewpoints"), list) else []
    final_pose = exploration.get("final_pose")
    returned_home = exploration.get("returned_to_start_pose")
    objects = table_scene.get("objects") if isinstance(table_scene.get("objects"), list) else []
    blue_blocks = table_scene.get("blue_block_candidates") if isinstance(table_scene.get("blue_block_candidates"), list) else []
    response = (
        f"I ran the bounded table workspace exploration. Status is {compact_status(status)}; "
        f"{len(viewpoints)} viewpoints; final pose {compact_status(final_pose)}."
    )
    if objects:
        response += f" I also mapped {len(objects)} table object candidates."
    if blue_blocks:
        response += " I see a blue block candidate."
    if success:
        response += " The scan completed and returned home."
    elif blockers:
        response += f" Blocked by {compact_status(blockers[0])}."
    elif run_result.get("error"):
        response += f" Runner error: {compact_status(run_result.get('error'))}."
    if returned_home is True and not success:
        response += " I returned to the start pose, but I still need physical/camera verification before calling it success."

    status_payload = {
        "packet_type": "mim-arm-workspace-exploration-voice-route-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-WORKSPACE-EXPLORATION-VOICE-ROUTE-V1",
        "status": "completed_with_evidence" if success else "blocked_with_evidence",
        "success": success,
        "source_transcript": transcript,
        "runner": run_result,
        "perception_runner": perception_result,
        "exploration_artifact": "runtime/shared/MIM_ARM_AREA_EXPLORATION.latest.json",
        "table_scene_artifact": "runtime/shared/MIM_ARM_TABLE_SCENE.latest.json",
        "exploration_status": status,
        "blockers": blockers,
        "viewpoint_count": len(viewpoints),
        "final_pose": final_pose,
        "returned_to_start_pose": returned_home,
        "object_candidate_count": len(objects),
        "blue_block_candidate_count": len(blue_blocks),
    }
    write_json(SHARED / "MIM_ARM_WORKSPACE_EXPLORATION_VOICE_ROUTE.latest.json", status_payload)
    return {
        "intent": "arm_workspace_exploration",
        "action": "execute_bounded_workspace_exploration",
        "response_text": response[:260],
        "artifacts": [
            "runtime/shared/MIM_ARM_WORKSPACE_EXPLORATION_VOICE_ROUTE.latest.json",
            "runtime/shared/MIM_ARM_AREA_EXPLORATION.latest.json",
            "runtime/shared/MIM_ARM_SIM_SYNC_SPACE_STATUS.latest.json",
            "runtime/shared/MIM_ARM_TABLE_SCENE.latest.json",
        ],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_arm_workspace_exploration_route"},
        "fallback_used": True,
    }


def run_arm_table_scene_perception(transcript: str) -> dict[str, Any]:
    perception = ROOT / "scripts" / "mim_arm_table_scene_perception.py"
    command = ["python3", str(perception), "--query", transcript]
    if not perception.exists():
        return {"ok": False, "error": "mim_arm_table_scene_perception.py_missing", "command": command}
    try:
        completed = subprocess.run(command, capture_output=True, text=True, timeout=30, check=False)
        return {
            "ok": completed.returncode in {0, 2},
            "returncode": completed.returncode,
            "command": command,
            "stdout_tail": completed.stdout[-1200:],
            "stderr_tail": completed.stderr[-1200:],
        }
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}", "command": command}


def build_arm_table_object_query_route(transcript: str) -> dict[str, Any]:
    run_result = run_arm_table_scene_perception(transcript)
    scene = load_shared_json("MIM_ARM_TABLE_SCENE.latest.json")
    normalized = normalize_voice_transcript_for_intent(transcript)
    blue_blocks = scene.get("blue_block_candidates") if isinstance(scene.get("blue_block_candidates"), list) else []
    pads = scene.get("pad_candidates") if isinstance(scene.get("pad_candidates"), list) else []
    blockers = scene.get("blockers") if isinstance(scene.get("blockers"), list) else []
    if re.search(r"\b(what|which).*number|number.*(blue|block)|blue.*number\b", normalized):
        if blue_blocks:
            response = "I see a blue block candidate, but I cannot read which number pad it is on yet. Number-pad OCR or fiducial labels are not bound."
        else:
            response = "I do not have a reliable blue block detection yet from the table camera."
    elif re.search(r"\b(find|where|locate|see).*(blue|block)|blue block\b", normalized):
        if blue_blocks:
            b = blue_blocks[0].get("bbox", {})
            response = f"I see a blue block candidate in the table view near pixel {b.get('x')}, {b.get('y')}."
            if blockers:
                response += f" Remaining blocker: {compact_status(blockers[0])}."
        else:
            response = "I looked at the table scene, but I do not have a reliable blue block candidate yet."
    else:
        response = f"I mapped {len(scene.get('objects') or [])} table object candidates, including {len(blue_blocks)} blue candidates and {len(pads)} light pad or block candidates."
        if blockers:
            response += f" Next blocker: {compact_status(blockers[0])}."
    return {
        "intent": "arm_table_object_query",
        "action": "perceive_table_objects",
        "response_text": response[:260],
        "artifacts": [
            "runtime/shared/MIM_ARM_TABLE_SCENE.latest.json",
            "runtime/shared/MIM_ARM_TABLE_OBJECT_INTERACTION_OBJECTIVE.latest.json",
            "runtime/shared/MIM_ARM_PI_TABLE_OBSERVER_STATUS.latest.json",
        ],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_arm_table_scene_perception", "perception_runner": run_result},
        "fallback_used": True,
    }


def build_arm_table_manipulation_route(transcript: str) -> dict[str, Any]:
    run_result = run_arm_table_scene_perception(transcript)
    scene = load_shared_json("MIM_ARM_TABLE_SCENE.latest.json")
    proposal = {
        "packet_type": "mim-arm-table-manipulation-proposal-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-TABLE-OBJECT-INTERACTION-V1",
        "status": "blocked_with_evidence",
        "success": False,
        "source_transcript": transcript,
        "requested_action": "pick_and_place_or_object_interaction",
        "scene_artifact": "runtime/shared/MIM_ARM_TABLE_SCENE.latest.json",
        "blockers": [
            "number_pad_ocr_not_bound",
            "arm_camera_to_table_coordinate_calibration_not_bound",
            "grasp_planner_not_bound",
            "collision_checked_pick_and_place_path_not_bound",
        ],
        "scene_summary": {
            "object_candidate_count": len(scene.get("objects") if isinstance(scene.get("objects"), list) else []),
            "blue_block_candidate_count": len(scene.get("blue_block_candidates") if isinstance(scene.get("blue_block_candidates"), list) else []),
            "pad_candidate_count": len(scene.get("pad_candidates") if isinstance(scene.get("pad_candidates"), list) else []),
        },
        "perception_runner": run_result,
        "next_recovery_action": "Train/calibrate numbered pad recognition, object table coordinates, grip approach poses, and safe lift/place routines before live pick-and-place.",
    }
    write_json(SHARED / "MIM_ARM_TABLE_MANIPULATION_PROPOSAL.latest.json", proposal)
    response = (
        "I understand the table manipulation request, but I am blocking live pick-and-place for now. "
        "I need numbered-pad recognition, table coordinates, and a proven grasp plan first."
    )
    return {
        "intent": "arm_table_manipulation",
        "action": "blocked_pending_grasp_training",
        "response_text": response[:260],
        "artifacts": [
            "runtime/shared/MIM_ARM_TABLE_MANIPULATION_PROPOSAL.latest.json",
            "runtime/shared/MIM_ARM_TABLE_SCENE.latest.json",
        ],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "manipulation_requires_grasp_training"},
        "fallback_used": True,
    }


def latest_pending_arm_motion_proposal(max_age_seconds: int = 180) -> tuple[dict[str, Any], str]:
    proposal = load_shared_json("MIM_ARM_MOTION_PROPOSAL.latest.json")
    if not proposal:
        return {}, "no_pending_motion_proposal"
    if proposal.get("status") != "awaiting_operator_safety_confirmation":
        return {}, "motion_proposal_not_awaiting_confirmation"
    generated_at = parse_utc_timestamp(proposal.get("generated_at"))
    if not generated_at:
        return {}, "motion_proposal_missing_timestamp"
    age = (datetime.now(timezone.utc) - generated_at.astimezone(timezone.utc)).total_seconds()
    if age > max_age_seconds:
        return {}, "motion_proposal_expired"
    if proposal.get("blockers"):
        return {}, "motion_proposal_has_blockers"
    return proposal, ""


def arm_motion_confirmation_kind(transcript: str) -> str:
    normalized = normalize_voice_transcript_for_intent(transcript)
    if re.fullmatch(r"(yes|yeah|yep|correct|confirmed|confirm|approved|safe|safe move|go ahead|do it|that is safe|it is safe|yes it is)[\.\s]*", normalized):
        return "confirm"
    if re.fullmatch(r"(no|nope|cancel|stop|do not|don't|dont|not safe|hold|wait)[\.\s]*", normalized):
        return "cancel"
    if re.search(r"\b(yes|yeah|yep|confirm|confirmed|approved|safe|go ahead|do it)\b", normalized) and len(transcript_words(normalized)) <= 5:
        return "confirm"
    if re.search(r"\b(no|nope|cancel|stop|not safe|hold|wait)\b", normalized) and len(transcript_words(normalized)) <= 5:
        return "cancel"
    return ""


def direction_delta_sign(direction: str, joint_index: int | None, servo_config: list[Any]) -> int | None:
    direction = direction.lower().strip()
    for item in servo_config:
        if not isinstance(item, dict):
            continue
        if int(item.get("id", -1)) != joint_index:
            continue
        left_label = str(item.get("left") or "").lower().strip()
        right_label = str(item.get("right") or "").lower().strip()
        if direction == right_label:
            return 1
        if direction == left_label:
            return -1
    if direction in {"open", "up"}:
        return 1
    if direction in {"close", "down"}:
        return -1
    return None


def get_arm_workspace_state() -> dict[str, Any]:
    try:
        with urllib.request.urlopen(f"{ARM_HOST}/workspace_setup_state", timeout=5) as response:
            data = json.loads(response.read().decode("utf-8", "replace"))
        return data if isinstance(data, dict) else {}
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}


def servo_limit_for(servo: int | None, servo_config: list[Any]) -> dict[str, Any]:
    for item in servo_config:
        if not isinstance(item, dict):
            continue
        try:
            if int(item.get("id", -1)) == servo:
                return {
                    "min": int(item.get("min", 0)),
                    "max": int(item.get("max", 180)),
                    "source": "servo_config",
                }
        except Exception:
            continue
    return {"min": 0, "max": 180, "source": "default"}


def evaluate_arm_sim_move_safety(
    joint_index: int | None,
    current_value: int | None,
    direction: str,
    degrees: int,
    servo_config: list[Any],
) -> dict[str, Any]:
    workspace = get_arm_workspace_state()
    obstacles = workspace.get("obstacles") if isinstance(workspace.get("obstacles"), list) else []
    markers = workspace.get("markers") if isinstance(workspace.get("markers"), list) else []
    limit = servo_limit_for(joint_index, servo_config)
    sign = direction_delta_sign(direction, joint_index, servo_config)
    target_angle = None
    clamped = False
    if isinstance(current_value, int) and sign is not None:
        requested = current_value + (sign * abs(int(degrees)))
        target_angle = max(int(limit["min"]), min(int(limit["max"]), requested))
        clamped = target_angle != requested

    blocked = False
    reason_code = ""
    warning = ""
    if workspace.get("_error"):
        blocked = True
        reason_code = "workspace_setup_state_unreachable"
    elif obstacles:
        blocked = True
        reason_code = "workspace_obstacles_present_collision_model_missing"
        warning = "That movement may impact objects within the sim model, so I need object-aware collision clearance first."
    elif joint_index is None or current_value is None or sign is None:
        blocked = True
        reason_code = "motion_target_incomplete_for_sim_safety"
    elif clamped:
        warning = f"Requested movement reaches the servo limit; target is clamped to {target_angle} degrees."
    else:
        warning = "Sim workspace reports no registered obstacles for this move."

    return {
        "status": "blocked" if blocked else "clear_with_evidence",
        "blocked": blocked,
        "reason_code": reason_code,
        "warning": warning,
        "workspace_source": f"{ARM_HOST}/workspace_setup_state",
        "obstacle_count": len(obstacles),
        "marker_count": len(markers),
        "known_obstacles": obstacles,
        "known_markers": markers,
        "servo_limit": limit,
        "current_angle": current_value,
        "target_angle": target_angle,
        "requested_degrees": degrees,
        "clamped_to_servo_limit": clamped,
        "collision_policy": "Block if the sim reports obstacles and no object-aware path clearance exists; otherwise warn and require Dave confirmation.",
    }


def post_arm_move(servo: int, angle: int) -> dict[str, Any]:
    payload = json.dumps({"servo": servo, "angle": angle}).encode("utf-8")
    request = urllib.request.Request(
        f"{ARM_HOST}/move",
        data=payload,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            raw = response.read().decode("utf-8", "replace")
        try:
            data = json.loads(raw) if raw else {}
        except Exception:
            data = {"raw": raw}
        return {"ok": True, "status_code": response.status, "data": data, "error": ""}
    except Exception as exc:
        return {"ok": False, "status_code": None, "data": {}, "error": f"{type(exc).__name__}: {exc}"}


def get_live_arm_pose() -> list[Any]:
    try:
        with urllib.request.urlopen(f"{ARM_HOST}/arm_state", timeout=5) as response:
            data = json.loads(response.read().decode("utf-8", "replace"))
        pose = data.get("current_pose") if isinstance(data, dict) else []
        return pose if isinstance(pose, list) else []
    except Exception:
        return []


def build_arm_motion_confirmation_route(transcript: str) -> dict[str, Any]:
    kind = arm_motion_confirmation_kind(transcript)
    proposal, reason = latest_pending_arm_motion_proposal()
    if not proposal:
        return {
            "intent": "arm_motion_confirmation",
            "action": "no_fresh_pending_arm_motion",
            "response_text": "I do not have a fresh pending arm move to confirm. Ask for the move again and I will stage it safely.",
            "artifacts": ["runtime/shared/MIM_ARM_MOTION_PROPOSAL.latest.json"],
            "chat_bridge": {"ok": False, "skipped": True, "reason": reason},
            "fallback_used": True,
        }
    proposal_body = proposal.get("proposal") if isinstance(proposal.get("proposal"), dict) else {}
    if kind == "cancel":
        proposal["status"] = "cancelled_by_operator"
        proposal["cancelled_at"] = now_iso()
        proposal["confirmation_transcript"] = transcript
        write_json(ARM_MOTION_PROPOSAL_PATH, proposal)
        return {
            "intent": "arm_motion_confirmation",
            "action": "cancel_arm_motion_proposal",
            "response_text": "Cancelled. I will not move the arm.",
            "artifacts": ["runtime/shared/MIM_ARM_MOTION_PROPOSAL.latest.json"],
            "chat_bridge": {"ok": False, "skipped": True, "reason": "operator_cancelled_arm_motion"},
            "fallback_used": True,
        }
    support = load_shared_json("MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json")
    motion = support.get("motion_awareness") if isinstance(support.get("motion_awareness"), dict) else {}
    servo_config = motion.get("servo_config") if isinstance(motion.get("servo_config"), list) else []
    live_pose = get_live_arm_pose()
    current_pose = live_pose or (motion.get("current_pose") if isinstance(motion.get("current_pose"), list) else [])
    joint = str(proposal_body.get("joint") or "")
    direction = str(proposal_body.get("direction") or "")
    joint_index = proposal_body.get("joint_index")
    if not isinstance(joint_index, int):
        execution = {"status": "blocked_with_evidence", "reason_code": "missing_joint_index"}
        write_json(ARM_MOTION_EXECUTION_PATH, execution)
        response = "I cannot execute that arm move because the joint index is missing."
    else:
        current_value = (
            int(current_pose[joint_index])
            if 0 <= joint_index < len(current_pose) and isinstance(current_pose[joint_index], (int, float))
            else int(proposal_body.get("current_value") or 0)
        )
        degrees = abs(int(proposal_body.get("degrees") or 0))
        sign = direction_delta_sign(direction, joint_index, servo_config)
        cfg = next((item for item in servo_config if isinstance(item, dict) and int(item.get("id", -1)) == joint_index), {})
        min_angle = int(cfg.get("min", 0)) if isinstance(cfg, dict) else 0
        max_angle = int(cfg.get("max", 180)) if isinstance(cfg, dict) else 180
        simulation_safety = evaluate_arm_sim_move_safety(joint_index, current_value, direction, degrees, servo_config)
        if sign is None:
            execution = {"status": "blocked_with_evidence", "reason_code": "direction_not_mapped", "direction": direction}
            write_json(ARM_MOTION_EXECUTION_PATH, execution)
            response = f"I cannot safely map {direction} for the {joint} yet, so I did not move it."
        elif simulation_safety.get("blocked"):
            execution = {
                "status": "blocked_with_evidence",
                "reason_code": simulation_safety.get("reason_code"),
                "simulation_safety": simulation_safety,
            }
            write_json(ARM_MOTION_EXECUTION_PATH, execution)
            response = f"I did not move the {joint}; sim-space safety reports {compact_status(simulation_safety.get('reason_code'))}."
        else:
            target_angle = max(min_angle, min(max_angle, current_value + (sign * degrees)))
            result = post_arm_move(joint_index, target_angle)
            status = "completed_with_evidence" if result.get("ok") else "blocked_with_evidence"
            execution = {
                "packet_type": "mim-arm-motion-execution-v1",
                "generated_at": now_iso(),
                "objective_id": "MIM-ARM-DEVELOPMENT-SUPPORT-V1",
                "status": status,
                "success": bool(result.get("ok")),
                "source": "operator_voice_confirmation",
                "confirmation_transcript": transcript,
                "proposal_generated_at": proposal.get("generated_at"),
                "joint": joint,
                "servo": joint_index,
                "direction": direction,
                "degrees": degrees,
                "from_angle": current_value,
                "target_angle": target_angle,
                "pose_source": "live_arm_state" if live_pose else "support_status_artifact",
                "http_result": result,
                "simulation_safety": simulation_safety,
            }
            write_json(ARM_MOTION_EXECUTION_PATH, execution)
            proposal["status"] = "executed_with_evidence" if result.get("ok") else "blocked_with_evidence"
            proposal["execution"] = execution
            write_json(ARM_MOTION_PROPOSAL_PATH, proposal)
            if result.get("ok"):
                response = f"Confirmed. I moved the {joint} from {current_value} to {target_angle}."
            else:
                response = f"I tried to move the {joint}, but the arm API blocked it: {compact_status(result.get('error'))}."
    return {
        "intent": "arm_motion_confirmation",
        "action": "execute_confirmed_arm_motion" if kind == "confirm" else "cancel_arm_motion_proposal",
        "response_text": response[:260],
        "artifacts": [
            "runtime/shared/MIM_ARM_MOTION_PROPOSAL.latest.json",
            "runtime/shared/MIM_ARM_MOTION_EXECUTION.latest.json",
        ],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_arm_motion_confirmation"},
        "fallback_used": True,
    }


def pending_arm_confirmation_route_if_any(transcript: str) -> dict[str, Any]:
    if arm_motion_confirmation_kind(transcript) and latest_pending_arm_motion_proposal()[0]:
        return build_arm_motion_confirmation_route(transcript)
    return {}


def build_arm_troubleshoot_route(transcript: str) -> dict[str, Any]:
    proposal = load_shared_json("MIM_ARM_MOTION_PROPOSAL.latest.json")
    execution = load_shared_json("MIM_ARM_MOTION_EXECUTION.latest.json")
    arm_state = {}
    try:
        with urllib.request.urlopen(f"{ARM_HOST}/arm_state", timeout=5) as response:
            arm_state = json.loads(response.read().decode("utf-8", "replace"))
    except Exception as exc:
        arm_state = {"status": "error", "error": f"{type(exc).__name__}: {exc}"}
    last_sent = ((execution.get("http_result") or {}).get("data") or {}).get("sent") if isinstance(execution, dict) else ""
    latest_proposal_status = proposal.get("status") if isinstance(proposal, dict) else ""
    latest_joint = ((proposal.get("proposal") or {}) if isinstance(proposal.get("proposal"), dict) else {}).get("joint", "")
    response = (
        f"Arm troubleshooting: latest proposal is {compact_status(latest_proposal_status)} for {compact_status(latest_joint)}. "
        f"Last executed command was {compact_status(last_sent)}. "
        f"Live pose is {compact_status(arm_state.get('current_pose'))}."
    )
    if latest_proposal_status == "awaiting_operator_safety_confirmation":
        response += " I am still waiting for a clear yes or cancel."
    return {
        "intent": "arm_motion_troubleshooting",
        "action": "summarize_arm_motion_evidence",
        "response_text": response[:260],
        "artifacts": [
            "runtime/shared/MIM_ARM_MOTION_PROPOSAL.latest.json",
            "runtime/shared/MIM_ARM_MOTION_EXECUTION.latest.json",
            "runtime/shared/MIM_ARM_DEVELOPMENT_SUPPORT_STATUS.latest.json",
        ],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_arm_motion_troubleshooting"},
        "fallback_used": True,
    }


def build_station_file_index_route(transcript: str) -> dict[str, Any]:
    index = load_shared_json("MIM_STATION_FILE_INDEX.latest.json")
    requested = index.get("requested_access") if isinstance(index.get("requested_access"), dict) else {}
    totals = index.get("totals") if isinstance(index.get("totals"), dict) else {}
    context = index.get("primary_working_context") if isinstance(index.get("primary_working_context"), dict) else {}
    recent = context.get("recent_files") if isinstance(context.get("recent_files"), list) else []
    candidates = context.get("arm_component_candidates") if isinstance(context.get("arm_component_candidates"), list) else []
    if not index:
        response = "I do not have the station file index yet. TOD needs to publish MIM_STATION_FILE_INDEX.latest.json from this PC."
        status = "blocked_missing_station_file_index"
    else:
        names = []
        for item in candidates[:5]:
            if isinstance(item, dict) and item.get("name"):
                names.append(str(item.get("name")))
        if not names:
            for item in recent[:5]:
                if isinstance(item, dict) and item.get("name"):
                    names.append(str(item.get("name")))
        current_path = str(context.get("path") or requested.get("primary_working_path") or "")
        response = (
            f"Yes. I have the station index for {current_path}. "
            f"It shows {compact_status(totals.get('primary_working_files'))} design-parts files and "
            f"{compact_status(totals.get('files_indexed'))} MIM station files indexed. "
            f"Likely arm files include: {', '.join(names[:4])}."
        )
        status = "summarized_station_file_index"
    return {
        "intent": "mim_station_file_access",
        "action": status,
        "response_text": response[:260],
        "artifacts": ["runtime/shared/MIM_STATION_FILE_INDEX.latest.json"],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_station_file_index"},
        "fallback_used": True,
        "source_transcript": transcript,
    }


def build_station_file_fetch_request_route(transcript: str) -> dict[str, Any]:
    filename_match = re.search(
        r"([A-Za-z0-9][A-Za-z0-9 _.,&()#+'-]{0,120}\.(?:stl|3mf|skp|skb|obj|step|stp|f3d|jpg|jpeg|png|pdf|docx|txt|md|json|csv))",
        transcript,
        flags=re.I,
    )
    query = filename_match.group(1).strip(" .,") if filename_match else transcript.strip()
    query = re.sub(r"^(?:mim|hey mim|okay mim|ok mim|ma'?am|mom)?\s*,?\s*(?:fetch|mirror|copy|upload|pull|send|get)\s+", "", query, flags=re.I).strip()
    index = load_shared_json("MIM_STATION_FILE_INDEX.latest.json")
    context = index.get("primary_working_context") if isinstance(index.get("primary_working_context"), dict) else {}
    request = {
        "packet_type": "mim-station-file-fetch-request-v1",
        "generated_at": now_iso(),
        "status": "queued_for_tod_station_mirror",
        "success": True,
        "source": "mim_voice",
        "transcript": transcript,
        "query": query,
        "primary_working_path": context.get("path", ""),
        "requested_artifact": "runtime/shared/MIM_STATION_FILE_MIRROR.latest.json",
        "expected_executor": "scripts/Invoke-MIMStationFileMirror.ps1 -Query <query> -UploadToMim",
        "policy": "MIM queues station-file fetch requests; TOD validates the path against approved station roots before mirroring.",
        "no_audio_retained": True,
    }
    write_json(STATION_FILE_FETCH_REQUEST_PATH, request)
    return {
        "intent": "mim_station_file_fetch_request",
        "action": "queue_station_file_fetch_request",
        "response_text": f"I queued a station-file fetch request for {query[:120]}. TOD needs to mirror it from the station index.",
        "artifacts": ["runtime/shared/MIM_STATION_FILE_FETCH_REQUEST.latest.json"],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "queued_station_file_fetch_request"},
        "fallback_used": True,
    }


def build_news_route() -> dict[str, Any]:
    return {
        "intent": "current_news_request",
        "action": "blocked_no_live_news_executor",
        "response_text": "I heard the news request, but I do not have a live news executor bound in voice yet. I should route that through a web-backed tool next.",
        "artifacts": ["runtime/shared/MIM_VOICE_UI_CHAT_BRIDGE.latest.json"],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "no_live_news_executor_bound"},
        "fallback_used": True,
    }


def build_address_ack_route() -> dict[str, Any]:
    return {
        "intent": "mim_address_acknowledgement",
        "action": "acknowledge_direct_address",
        "response_text": "Yeah Dave?",
        "artifacts": ["runtime/shared/MIM_VOICE_ADDRESSING_DECISION.latest.json"],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "direct_mim_reference_acknowledged_locally"},
        "fallback_used": True,
    }


def build_voice_repeat_or_continue_route(transcript: str) -> dict[str, Any]:
    return {
        "intent": "voice_fragment_continue",
        "action": "ask_operator_to_finish_fragment",
        "response_text": "I heard part of that, Dave. Finish the thought and I’ll stay with it.",
        "artifacts": ["runtime/shared/MIM_VOICE_TURN_STATE.latest.json"],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "active_conversation_fragment"},
        "fallback_used": True,
    }


def build_interaction_feedback_route(transcript: str, feedback: dict[str, Any]) -> dict[str, Any]:
    learning = save_interaction_feedback(transcript, feedback)
    feedback_type = str(feedback.get("feedback_type") or "")
    if feedback_type == "mim_name_correction":
        response = "Got it. If I hear mom or something close in here, I'll treat it as MIM unless you correct me."
    elif feedback_type in {"not_for_mim_phone_call", "human_to_human_conversation"}:
        response = "Understood. I'll stay quiet until you tell me the call is over."
    elif feedback_type == "phone_call_ended":
        response = "Got it. I'm back."
    elif feedback_type == "thinking_out_loud":
        response = "Got it. I'll treat that as thinking out loud unless you bring me in."
    elif feedback_type == "not_addressed_to_mim":
        response = "Understood. I'll log that as not for me."
    elif feedback_type == "false_speech_detection":
        response = "Got it. I'll mark that as a false hear."
    else:
        response = "Got it. I'll use that feedback for future voice decisions."
    return {
        "intent": "voice_interaction_learning_feedback",
        "action": "learn_from_operator_feedback",
        "response_text": response[:260],
        "artifacts": ["runtime/shared/MIM_VOICE_INTERACTION_LEARNING.latest.json"],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_voice_interaction_learning"},
        "fallback_used": True,
        "interaction_learning": learning,
    }


def call_mim_ui_chat(transcript: str) -> dict[str, Any]:
    if not VOICE_UI_CHAT_BRIDGE_ENABLED:
        return {"ok": False, "skipped": True, "error": "voice_ui_chat_bridge_disabled"}
    payload = {
        "text": transcript,
        "parsed_intent": "conversation",
        "safety_flags": [],
        "metadata_json": {
            "source": "mim_ambient_voice",
            "interaction_mode": "voice",
            "message_type": "user",
            "conversation_session_id": VOICE_UI_CHAT_SESSION_ID,
            "route_preference": "conversation_layer",
            "voice_bridge": True,
            "response_style": "voice_concise",
        },
    }
    request = urllib.request.Request(
        VOICE_UI_CHAT_ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            response_payload = json.loads(response.read().decode("utf-8"))
        reply = extract_mim_chat_reply(response_payload)
        result = {
            "ok": bool(reply),
            "endpoint": VOICE_UI_CHAT_ENDPOINT,
            "status": response_payload.get("resolution", {}).get("resolution_status"),
            "outcome": response_payload.get("resolution", {}).get("outcome"),
            "request_id": response_payload.get("request_id"),
            "input_id": response_payload.get("input_id"),
            "reply_text": reply,
            "raw_reply_available": bool(reply),
            "error": "" if reply else "no_reply_text_extracted",
        }
    except Exception as exc:
        result = {
            "ok": False,
            "endpoint": VOICE_UI_CHAT_ENDPOINT,
            "reply_text": "",
            "error": f"{type(exc).__name__}: {exc}",
        }
    write_json(
        VOICE_CHAT_BRIDGE_PATH,
        {
            "packet_type": "mim-voice-ui-chat-bridge-v1",
            "generated_at": now_iso(),
            "status": "completed_with_evidence" if result.get("ok") else "blocked_with_evidence",
            "success": bool(result.get("ok")),
            "transcript": transcript,
            "bridge": result,
            "policy": "Voice uses the same MIM conversation path as UI chat; local lab routing is fallback only.",
            "no_audio_retained": True,
        },
    )
    return result


def load_turn_state() -> dict[str, Any]:
    state = load_shared_json("MIM_VOICE_TURN_STATE.latest.json")
    return state if isinstance(state, dict) else {}


def save_turn_state(*, transcript: str, route: dict[str, Any], response_text: str) -> None:
    previous = load_turn_state()
    history = previous.get("recent_turns") if isinstance(previous.get("recent_turns"), list) else []
    now = now_iso()
    active_until = (
        datetime.now(timezone.utc).timestamp() + max(5, VOICE_ACTIVE_SESSION_SECONDS)
        if response_text or route.get("intent") == "mim_address_acknowledgement"
        else None
    )
    active_until_iso = (
        datetime.fromtimestamp(active_until, timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        if active_until
        else str(previous.get("active_conversation_until") or "")
    )
    current_topic = str(route.get("intent") or "").strip()
    if current_topic in {"unknown", "none", ""}:
        current_topic = str(previous.get("current_topic") or "").strip()
    payload = {
        "packet_type": "mim-voice-turn-state-v1",
        "generated_at": now,
        "status": "updated",
        "success": True,
        "current_topic": current_topic,
        "last_intent": route.get("intent"),
        "last_action": route.get("action"),
        "last_transcript": transcript,
        "last_response_text": response_text,
        "last_artifacts": route.get("artifacts", []),
        "active_conversation": bool(active_until_iso),
        "active_conversation_until": active_until_iso,
        "active_conversation_seconds": VOICE_ACTIVE_SESSION_SECONDS,
        "active_conversation_policy": "After MIM is addressed or responds, follow-up utterances in this window are treated as part of the same conversation.",
        "recent_turns": (
            history
            + [
                {
                    "generated_at": now,
                    "transcript": transcript,
                    "intent": route.get("intent"),
                    "action": route.get("action"),
                    "response_text": response_text,
                }
            ]
        )[-12:],
        "no_audio_retained": True,
    }
    write_json(TURN_STATE_PATH, payload)


def route_followup(transcript: str) -> dict[str, Any]:
    normalized = normalize_voice_transcript_for_intent(transcript)
    turn_state = load_turn_state()
    previous_topic = str(turn_state.get("current_topic") or "").strip()
    feedback = classify_interaction_feedback(transcript)
    if feedback.get("is_feedback"):
        return build_interaction_feedback_route(transcript, feedback)
    if has_mim_reference(transcript) and len(transcript_words(transcript)) <= 2:
        if re.search(r"\b(remember|note|save|know|familiar)\b", normalized):
            return build_voice_repeat_or_continue_route(transcript)
        return build_address_ack_route()
    if (
        previous_topic
        and re.search(r"\b(do you know|are you familiar|i'?m asking|doing today|what.*today)\b", normalized)
        and classify_voice_fragment(transcript).get("is_fragment")
    ):
        return build_voice_repeat_or_continue_route(transcript)
    if re.search(r"\b(how much time|time left|time.*training|training.*time)\b", normalized):
        return build_training_time_route()
    if re.search(r"\b(good or bad|bad or good|is (that|it) good|is (that|it) bad|how.*going|how.*doing)\b", normalized) and is_training_topic(previous_topic):
        return build_training_quality_route()
    if re.search(r"\b(what time is it|current time|time now)\b", normalized):
        return build_current_time_route()
    if re.search(r"\b(can you hear me|do you hear me|hear me clearly|can you see me|do you see me)\b", normalized):
        return build_voice_presence_check_route(transcript)
    pending_confirmation = pending_arm_confirmation_route_if_any(transcript)
    if pending_confirmation:
        return pending_confirmation
    if re.search(r"\b(live\s+sync|sync)\b", normalized) and re.search(
        r"\b(on|enabled|off|disabled|not on|not enabled)\b", normalized
    ):
        return build_arm_sync_assertion_route(transcript)
    if re.search(r"\b(move|nudge|open|close)\b", normalized) and re.search(r"\b(base|shoulder|elbow|forearm|wrist|hand|grip|gripper|claw)\b", normalized):
        return build_arm_motion_proposal_route(transcript)
    if re.search(r"\b(pick up|pickup|grab|grip|move|place|put)\b", normalized) and re.search(
        r"\b(block|cube|pad|number\s*[123]|one|two|three|blue|white|gray|grey)\b", normalized
    ):
        return build_arm_table_manipulation_route(transcript)
    if re.search(r"\b(find|where|locate|see|identify|what number|which number|what.*on|object|objects|block|blocks|pad|pads)\b", normalized) and re.search(
        r"\b(table|blue|white|gray|grey|block|cube|pad|number\s*[123]|one|two|three)\b", normalized
    ):
        return build_arm_table_object_query_route(transcript)
    if re.search(r"\b(explore|scan|look around|survey|inspect)\b", normalized) and re.search(
        r"\b(workspace|table|area|surroundings|arm space|arm workspace)\b", normalized
    ):
        return build_arm_workspace_exploration_route(transcript)
    if re.search(r"\b(troubleshoot|no movement|no movements|not moving|didn'?t move|doesn'?t move|showing no movement)\b", normalized) and re.search(r"\b(arm|base|shoulder|elbow|wrist|hand|grip|claw|movement|movements)\b", normalized):
        return build_arm_troubleshoot_route(transcript)
    if re.search(r"\b(arm status|sync mode|arm sync|is.*arm.*sync|arm.*moving|arm.*expected|troubleshoot.*arm)\b", normalized):
        return build_arm_status_route()
    if re.search(r"\b(fetch|mirror|copy|upload|pull|send|get)\b", normalized) and re.search(
        r"\b(file|files|part|parts|component|components|stl|3mf|skp|skb|design[_ ]?parts|design parts)\b", normalized
    ):
        return build_station_file_fetch_request_route(transcript)
    if re.search(r"\b(file|files|part|parts|component|components|design[_ ]?parts|design parts)\b", normalized) and re.search(
        r"\b(mim arm|mid arm|middle arm|arm|servo|claw|gear|base)\b", normalized
    ):
        return build_station_file_index_route(transcript)
    if re.search(r"\b(are you familiar|do you know|what do you know|tell me about)\b", normalized):
        chat_bridge = call_mim_ui_chat(transcript)
        if chat_bridge.get("ok"):
            return {
                "intent": "mim_ui_chat",
                "action": "voice_to_ui_chat_bridge",
                "response_text": str(chat_bridge.get("reply_text") or "")[:260],
                "artifacts": ["runtime/shared/MIM_VOICE_UI_CHAT_BRIDGE.latest.json"],
                "chat_bridge": chat_bridge,
                "fallback_used": False,
            }
    if re.search(r"\b(current training|current.*cycle|during cycle|cycle.*going|your training|what.*working on|you'?re working on|you are working on|what.*training\s+on|training.*right now|what.*training)\b", normalized):
        return build_training_topic_route()
    if re.search(r"\b(arm|middle arm|arm camera|robot arm|wrist|claw)\b", normalized):
        return build_arm_status_route()
    if re.search(r"\b(top news|news today|today'?s news|latest news)\b", normalized):
        return build_news_route()
    if re.search(r"\b(improve|better|current state|what.*work on|would you like.*work|need.*improve|priorit(y|ies))\b", normalized):
        return build_voice_improvement_route()
    quality = classify_transcript_quality(transcript)
    if not quality.get("usable"):
        return build_transcript_clarification_route(transcript, quality)
    chat_bridge = call_mim_ui_chat(transcript)
    if chat_bridge.get("ok"):
        return {
            "intent": "mim_ui_chat",
            "action": "voice_to_ui_chat_bridge",
            "response_text": str(chat_bridge.get("reply_text") or "")[:260],
            "artifacts": ["runtime/shared/MIM_VOICE_UI_CHAT_BRIDGE.latest.json"],
            "chat_bridge": chat_bridge,
            "fallback_used": False,
        }
    artifacts: list[str] = []
    intent = "unknown"
    action = "clarify"
    response = "I heard you, but I don't know how to act on that yet. Try cameras, sensors, lab status, objects, or remember this."

    if re.search(r"\b(what can you do|what do you do|help|commands|options)\b", normalized):
        intent = "capability_help"
        action = "explain_voice_routes"
        artifacts = ["runtime/shared/MIM_WAKE_FOLLOWUP.latest.json"]
        response = "I can report lab status, cameras, sensors, object memory, and remember notes. Ask naturally; you do not need to say my name."
    elif re.search(r"\b(how are you|how you doing|how's it going|status|are you ok|are you okay)\b", normalized):
        intent = "status_check"
        action = "summarize_listener_status"
        status = load_shared_json("MIM_WAKE_LISTENER_STATUS.latest.json")
        diag = load_shared_json("MIM_WAKE_DIAGNOSTIC.latest.json")
        artifacts = ["runtime/shared/MIM_WAKE_LISTENER_STATUS.latest.json", "runtime/shared/MIM_WAKE_DIAGNOSTIC.latest.json"]
        response = (
            "I'm awake, listening, and my voice route is working. "
            f"Last diagnostic says {compact_status((diag.get('diagnosis') or {}).get('reason_code'))}. "
            f"My active input is {compact_status(status.get('audio_device'))}."
        )
    elif re.search(r"\b(camera|cameras|cam|see|look|vision)\b", normalized) or (
        previous_topic == "camera_status" and re.search(r"\b(arm|one|that|it|that one|arm one)\b", normalized)
    ):
        intent = "camera_status"
        action = "summarize_camera_cycle"
        camera = load_shared_json("MIM_LAB_CAMERA_CYCLE_STATUS.latest.json")
        awareness = load_shared_json("MIM_LAB_AWARENESS_STATUS.latest.json")
        artifacts = ["runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json", "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json"]
        response = (
            "I can summarize camera evidence from the latest lab cycle. "
            f"Camera cycle status is {compact_status(camera.get('status'))}; "
            f"lab awareness status is {compact_status(awareness.get('status'))}."
        )
    elif re.search(r"\b(sensor|sensors|microphone|microphones|mic|mics|audio)\b", normalized):
        intent = "sensor_status"
        action = "summarize_sensor_inventory"
        inventory = load_shared_json("MIM_LAB_SENSOR_INVENTORY.latest.json")
        listener = load_shared_json("MIM_WAKE_LISTENER_STATUS.latest.json")
        artifacts = ["runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json", "runtime/shared/MIM_WAKE_LISTENER_STATUS.latest.json"]
        response = (
            "For sensors, my wake listener is using "
            f"{compact_status(listener.get('audio_device'))}. "
            f"The lab sensor inventory artifact status is {compact_status(inventory.get('status'))}."
        )
    elif re.search(r"\b(object|objects|what.*know|inventory)\b", normalized):
        intent = "object_memory"
        action = "summarize_object_memory"
        objects = load_shared_json("MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json")
        artifacts = ["runtime/shared/MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json"]
        response = f"My object memory artifact status is {compact_status(objects.get('status'))}. I can use it to ask about unknown lab objects next."
    elif re.search(r"\b(lab|space|room|awareness|aware)\b", normalized):
        intent = "lab_awareness"
        action = "summarize_lab_awareness"
        evidence = load_shared_json("MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json")
        status = load_shared_json("MIM_LAB_AWARENESS_STATUS.latest.json")
        artifacts = ["runtime/shared/MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json", "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json"]
        response = (
            "Latest lab awareness evidence is available. "
            f"Execution evidence status is {compact_status(evidence.get('status'))}; "
            f"current awareness status is {compact_status(status.get('status'))}."
        )
    elif re.search(r"\b(remember|note this|save this)\b", normalized):
        intent = "memory_note"
        action = "write_operator_memory_note"
        memory = load_shared_json("MIM_HUMAN_INTERACTION_MEMORY.latest.json")
        notes = memory.get("voice_notes") if isinstance(memory.get("voice_notes"), list) else []
        notes.append({"generated_at": now_iso(), "speaker": "Dave", "transcript": transcript})
        memory["voice_notes"] = notes[-20:]
        memory["generated_at"] = now_iso()
        memory["status"] = "updated_from_voice_followup"
        write_json(MEMORY_PATH, memory)
        artifacts = ["runtime/shared/MIM_HUMAN_INTERACTION_MEMORY.latest.json"]
        response = "Got it. I saved that as a Dave voice note in my interaction memory."

    return {
        "intent": intent,
        "action": action,
        "response_text": response[:240],
        "artifacts": artifacts,
        "chat_bridge": chat_bridge,
        "fallback_used": True,
    }


def should_clarify_unknown(transcript: str) -> bool:
    normalized = re.sub(r"[^a-zA-Z0-9.' ]+", " ", str(transcript or "")).strip().lower()
    return bool(
        re.search(r"\b(what|how|why|when|where|who|can you|could you|would you|should i|do you|are you|tell me|help)\b", normalized)
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
        vad = analyze_vad_segments(wav_path)
        if not vad.get("speech_detected") and int(level.get("rms") or 0) < 250:
            stt = {
                "ok": True,
                "text": "",
                "wake_text": "",
                "raw_result": {},
                "wake_result": {},
                "error": "",
                "stt_engine": "skipped_no_speech",
                "stt_primary": {
                    "engine": STT_ENGINE,
                    "ok": False,
                    "text": "",
                    "reason": "vad_no_speech_low_energy_window",
                },
                "stt_fallback": {},
            }
        else:
            stt = transcribe_wav(model, wav_path)
        transcript = select_effective_transcript(stt.get("text", ""), stt.get("wake_text", ""))
        self_output_detected = detect_self_output(stt.get("text", "")) or detect_self_output(stt.get("wake_text", ""))
        route = {"intent": "none", "action": "none", "artifacts": []}
        pending_confirmation = {}
        scene = build_lab_conversation_scene(transcript, vad=vad, audio_level=level) if transcript and not self_output_detected else {}
        addressing = (
            decide_voice_addressing(transcript, scene=scene, source="followup")
            if transcript and not self_output_detected
            else {}
        )
        if not stt["ok"]:
            status = "stt_blocked"
            response_text = ""
        elif self_output_detected:
            status = "ignored_self_output"
            response_text = ""
        else:
            pending_confirmation = pending_arm_confirmation_route_if_any(transcript)
        if not stt["ok"]:
            pass
        elif self_output_detected:
            pass
        elif pending_confirmation:
            route = pending_confirmation
            status = "operator_followup_routed"
            response_text = route["response_text"]
        elif addressing and not addressing.get("addressed_to_mim"):
            status = "operator_followup_observed_not_addressed"
            route = {
                "intent": "not_addressed_to_mim",
                "action": "observe_without_response",
                "artifacts": [
                    "runtime/shared/MIM_VOICE_ADDRESSING_DECISION.latest.json",
                    "runtime/shared/MIM_LAB_CONVERSATION_SCENE.latest.json",
                ],
                "fallback_used": False,
            }
            response_text = ""
        elif transcript:
            fragment = classify_voice_fragment(transcript)
            if fragment.get("is_fragment") and (
                not addressing.get("addressed_to_mim")
                or should_suppress_fragment_before_chat(transcript, fragment, addressing)
            ):
                publish_fragment_suppression(transcript, fragment, source="followup")
                route = {
                    "intent": "voice_fragment_suppressed",
                    "action": "observe_without_response",
                    "artifacts": ["runtime/shared/MIM_VOICE_FRAGMENT_SUPPRESSION_STATUS.latest.json"],
                    "fragment_classification": fragment,
                }
                status = "operator_followup_fragment_suppressed"
                response_text = ""
            else:
                route = route_followup(transcript)
                status = "operator_followup_routed" if route["intent"] != "unknown" else "operator_followup_needs_clarification"
                response_text = route["response_text"]
        else:
            status = "no_followup_heard"
            response_text = ""
        voice_response = play_voice_response(response_text) if response_text else {}
        if transcript and not self_output_detected and route.get("intent") != "voice_fragment_suppressed":
            save_turn_state(transcript=transcript, route=route, response_text=response_text)
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
            "intent": route.get("intent"),
            "action": route.get("action"),
            "artifacts": route.get("artifacts", []),
            "chat_bridge": route.get("chat_bridge", {}),
            "fallback_used": route.get("fallback_used"),
            "fragment_classification": route.get("fragment_classification", {}),
            "addressing_decision": addressing,
            "scene_artifact": str(LAB_CONVERSATION_SCENE_PATH.relative_to(ROOT)) if scene else "",
            "addressing_artifact": str(VOICE_ADDRESSING_DECISION_PATH.relative_to(ROOT)) if addressing else "",
            "turn_state_artifact": str(TURN_STATE_PATH.relative_to(ROOT)),
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


def handle_lab_conversation(transcript: str) -> dict[str, Any]:
    publish_conversation_control_objective()
    scene = build_lab_conversation_scene(transcript)
    addressing = decide_voice_addressing(transcript, scene=scene, source="ambient_lab_conversation")
    pending_confirmation = pending_arm_confirmation_route_if_any(transcript)
    if pending_confirmation:
        response_text = pending_confirmation["response_text"]
        voice_response = play_voice_response(response_text) if response_text else {}
        result = {
            "packet_type": "mim-lab-conversation-turn-v1",
            "generated_at": now_iso(),
            "objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1",
            "status": "responded" if response_text else "observed_no_response",
            "success": True,
            "mode": "ambient_lab_conversation",
            "transcript": transcript,
            "intent": pending_confirmation.get("intent"),
            "action": pending_confirmation.get("action"),
            "artifacts": pending_confirmation.get("artifacts", []),
            "chat_bridge": pending_confirmation.get("chat_bridge", {}),
            "fallback_used": pending_confirmation.get("fallback_used"),
            "addressing_decision": addressing,
            "scene_artifact": str(LAB_CONVERSATION_SCENE_PATH.relative_to(ROOT)),
            "addressing_artifact": str(VOICE_ADDRESSING_DECISION_PATH.relative_to(ROOT)),
            "turn_state_artifact": str(TURN_STATE_PATH.relative_to(ROOT)),
            "response_text": response_text,
            "voice_response": voice_response,
            "voice_wav_output_accepted": bool(voice_response.get("any_output_accepted")) if response_text else None,
            "no_audio_retained": True,
            "policy": "Fresh arm movement confirmations are routed before ambient-addressing suppression.",
        }
        save_turn_state(transcript=transcript, route=pending_confirmation, response_text=response_text)
        write_json(FOLLOWUP_PATH, result)
        return result
    if not addressing.get("addressed_to_mim"):
        result = {
            "packet_type": "mim-lab-conversation-turn-v1",
            "generated_at": now_iso(),
            "objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1",
            "status": "observed_not_addressed",
            "success": True,
            "mode": "ambient_lab_conversation",
            "transcript": transcript,
            "intent": "not_addressed_to_mim",
            "action": "observe_without_response",
            "artifacts": [
                "runtime/shared/MIM_VOICE_ADDRESSING_DECISION.latest.json",
                "runtime/shared/MIM_LAB_CONVERSATION_SCENE.latest.json",
                "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_OBJECTIVE.latest.json",
            ],
            "chat_bridge": {},
            "fallback_used": False,
            "addressing_decision": addressing,
            "scene_artifact": str(LAB_CONVERSATION_SCENE_PATH.relative_to(ROOT)),
            "addressing_artifact": str(VOICE_ADDRESSING_DECISION_PATH.relative_to(ROOT)),
            "turn_state_artifact": str(TURN_STATE_PATH.relative_to(ROOT)),
            "response_text": "",
            "voice_response": {},
            "voice_wav_output_accepted": None,
            "no_audio_retained": True,
            "policy": "MIM observes ambient lab speech that is not addressed to MIM and does not send it to UI chat.",
        }
        write_json(FOLLOWUP_PATH, result)
        return result
    fragment = classify_voice_fragment(transcript)
    if fragment.get("is_fragment") and (
        not addressing.get("addressed_to_mim")
        or should_suppress_fragment_before_chat(transcript, fragment, addressing)
    ):
        publish_fragment_suppression(transcript, fragment, source="ambient_lab_conversation")
        route = {
            "intent": "voice_fragment_suppressed",
            "action": "observe_without_response",
            "artifacts": ["runtime/shared/MIM_VOICE_FRAGMENT_SUPPRESSION_STATUS.latest.json"],
            "fragment_classification": fragment,
            "fallback_used": False,
        }
        result = {
            "packet_type": "mim-lab-conversation-turn-v1",
            "generated_at": now_iso(),
            "objective_id": "MIM-LISTENING-AND-VOICE-PERSONA-V1",
            "status": "voice_fragment_suppressed",
            "success": True,
            "mode": "ambient_lab_conversation",
            "transcript": transcript,
            "intent": route.get("intent"),
            "action": route.get("action"),
            "artifacts": route.get("artifacts", []),
            "chat_bridge": {},
            "fallback_used": route.get("fallback_used"),
            "fragment_classification": fragment,
            "addressing_decision": addressing,
            "scene_artifact": str(LAB_CONVERSATION_SCENE_PATH.relative_to(ROOT)),
            "addressing_artifact": str(VOICE_ADDRESSING_DECISION_PATH.relative_to(ROOT)),
            "turn_state_artifact": str(TURN_STATE_PATH.relative_to(ROOT)),
            "response_text": "",
            "voice_response": {},
            "voice_wav_output_accepted": None,
            "no_audio_retained": True,
            "policy": "MIM listens continuously, but low-content STT fragments are evidence only and do not trigger a spoken clarification.",
        }
        write_json(FOLLOWUP_PATH, result)
        return result
    quality = classify_transcript_quality(transcript)
    if should_observe_low_confidence_transcript(transcript, quality):
        write_json(
            SHARED / "MIM_VOICE_TRANSCRIPT_QUALITY.latest.json",
            {
                "packet_type": "mim-voice-transcript-quality-v1",
                "generated_at": now_iso(),
                "status": "observed_probable_stt_hallucination",
                "success": True,
                "transcript": transcript,
                "quality": quality,
                "policy": "Known ASR hallucination patterns are observed silently instead of being routed to chat or spoken back.",
                "no_audio_retained": True,
            },
        )
        result = {
            "packet_type": "mim-lab-conversation-turn-v1",
            "generated_at": now_iso(),
            "objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1",
            "status": "observed_probable_stt_hallucination",
            "success": True,
            "mode": "ambient_lab_conversation",
            "transcript": transcript,
            "intent": "probable_stt_hallucination",
            "action": "observe_without_response",
            "artifacts": ["runtime/shared/MIM_VOICE_TRANSCRIPT_QUALITY.latest.json"],
            "chat_bridge": {"ok": False, "skipped": True, "reason": "probable_stt_hallucination"},
            "fallback_used": False,
            "fragment_classification": fragment,
            "addressing_decision": addressing,
            "scene_artifact": str(LAB_CONVERSATION_SCENE_PATH.relative_to(ROOT)),
            "addressing_artifact": str(VOICE_ADDRESSING_DECISION_PATH.relative_to(ROOT)),
            "turn_state_artifact": str(TURN_STATE_PATH.relative_to(ROOT)),
            "response_text": "",
            "voice_response": {},
            "voice_wav_output_accepted": None,
            "no_audio_retained": True,
            "policy": "Suppress likely ASR hallucinations unless MIM is clearly addressed.",
        }
        write_json(FOLLOWUP_PATH, result)
        return result
    route = route_followup(transcript)
    should_respond = route["intent"] != "unknown" or should_clarify_unknown(transcript)
    response_text = route["response_text"] if should_respond else ""
    voice_response = play_voice_response(response_text) if response_text else {}
    result = {
        "packet_type": "mim-lab-conversation-turn-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1",
        "status": "responded" if response_text else "observed_no_response",
        "success": True,
        "mode": "ambient_lab_conversation",
        "transcript": transcript,
        "intent": route.get("intent"),
        "action": route.get("action"),
        "artifacts": route.get("artifacts", []),
        "chat_bridge": route.get("chat_bridge", {}),
        "fallback_used": route.get("fallback_used"),
        "fragment_classification": route.get("fragment_classification", {}),
        "addressing_decision": addressing,
        "scene_artifact": str(LAB_CONVERSATION_SCENE_PATH.relative_to(ROOT)),
        "addressing_artifact": str(VOICE_ADDRESSING_DECISION_PATH.relative_to(ROOT)),
        "turn_state_artifact": str(TURN_STATE_PATH.relative_to(ROOT)),
        "response_text": response_text,
        "voice_response": voice_response,
        "voice_wav_output_accepted": bool(voice_response.get("any_output_accepted")) if response_text else None,
        "no_audio_retained": True,
        "policy": "MIM routes lab speech through an addressing decision before response generation; MIM-like words are direct address signals.",
    }
    if transcript:
        save_turn_state(transcript=transcript, route=route, response_text=response_text)
    write_json(FOLLOWUP_PATH, result)
    return result


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
        vad = analyze_vad_segments(wav_path)
        if not vad.get("speech_detected") and int(level.get("rms") or 0) < 250:
            stt = {
                "ok": True,
                "text": "",
                "wake_text": "",
                "raw_result": {},
                "wake_result": {},
                "error": "",
                "stt_engine": "skipped_no_speech",
                "stt_primary": {
                    "engine": STT_ENGINE,
                    "ok": False,
                    "text": "",
                    "reason": "vad_no_speech_low_energy_window",
                },
                "stt_fallback": {},
            }
        else:
            stt = transcribe_wav(model, wav_path)
        transcript = select_effective_transcript(stt.get("text", ""), stt.get("wake_text", ""))
        probable_wake = detect_probable_wake_check(general_text=stt.get("text", ""), wake_text=stt.get("wake_text", ""), level=level)
        self_output_detected = detect_self_output(stt.get("text", "")) or detect_self_output(stt.get("wake_text", ""))
        wake = bool(
            stt["ok"]
            and not LAB_CONVERSATION_MODE
            and not self_output_detected
            and (
                detect_wake(stt.get("text", ""))
                or detect_wake(stt.get("wake_text", ""))
                or probable_wake
            )
        )
        tts = {"ok": True, "command": [], "returncode": 0, "stderr": "", "stdout": ""}
        voice_response = {}
        lab_turn = {}
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
            if LAB_CONVERSATION_MODE and stt["ok"] and transcript and not self_output_detected:
                lab_turn = handle_lab_conversation(transcript)
        return {
            "status": lab_turn.get("status")
            if lab_turn
            else ("wake_detected" if wake else "listening"),
            "success": True,
            "audio_device": device,
            "audio_level": level,
            "vad": {
                "speech_detected": vad.get("speech_detected"),
                "segments": vad.get("segments", []),
                "artifact": str(VAD_STATUS_PATH.relative_to(ROOT)),
            },
            "transcript": transcript,
            "general_transcript": stt.get("text", ""),
            "wake_transcript": stt.get("wake_text", ""),
            "stt_engine": stt.get("stt_engine", ""),
            "stt_primary": stt.get("stt_primary", {}),
            "stt_fallback": stt.get("stt_fallback", {}),
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
            "lab_conversation_mode": LAB_CONVERSATION_MODE,
            "lab_conversation_response": bool(lab_turn.get("response_text")),
            "lab_conversation_intent": lab_turn.get("intent"),
            "lab_conversation_action": lab_turn.get("action"),
            "lab_conversation_fragment_classification": lab_turn.get("fragment_classification", {}),
            "lab_conversation_addressing_decision": lab_turn.get("addressing_decision", {}),
            "lab_conversation_voice_wav_output_accepted": lab_turn.get("voice_wav_output_accepted"),
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
        publish_transcript_log(result, device=device)
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
                "stt_engine": result.get("stt_engine", ""),
                "stt_primary": result.get("stt_primary", {}),
                "stt_fallback": result.get("stt_fallback", {}),
                "tts_ok": result.get("tts_ok"),
                "alert_any_output_accepted": result.get("alert_any_output_accepted"),
                "voice_wav_output_accepted": result.get("voice_wav_output_accepted"),
                "followup_status": result.get("followup_status"),
                "followup_transcript": result.get("followup_transcript", ""),
                "followup_voice_wav_output_accepted": result.get("followup_voice_wav_output_accepted"),
                "lab_conversation_mode": result.get("lab_conversation_mode"),
                "lab_conversation_response": result.get("lab_conversation_response"),
                "lab_conversation_intent": result.get("lab_conversation_intent"),
                "lab_conversation_action": result.get("lab_conversation_action"),
                "lab_conversation_addressing_decision": result.get("lab_conversation_addressing_decision", {}),
                "lab_conversation_voice_wav_output_accepted": result.get("lab_conversation_voice_wav_output_accepted"),
                "no_audio_retained": True,
                "interaction_artifact": str(INTERACTION_PATH.relative_to(ROOT)) if INTERACTION_PATH.exists() else "",
                "followup_artifact": str(FOLLOWUP_PATH.relative_to(ROOT)) if FOLLOWUP_PATH.exists() else "",
            },
        )
        if args.once:
            return 0
        if result.get("wake_phrase_detected") or result.get("lab_conversation_response"):
            cooldown_until = now_iso()
            cooldown_seconds = max(1, args.cooldown_seconds)
            write_json(
                STATUS_PATH,
                {
                    "packet_type": "mim-wake-listener-status-v1",
                    "generated_at": cooldown_until,
                    "status": "cooldown_after_response",
                    "success": True,
                    "objective_id": "MIM-LISTENING-AND-VOICE-PERSONA-V1",
                    "audio_device": device,
                    "cooldown_seconds": cooldown_seconds,
                    "reason": "Prevent repeated playback and self-triggering after audible response.",
                    "last_transcript": result.get("transcript", ""),
                    "wake_phrase_detected": result.get("wake_phrase_detected", False),
                    "voice_wav_output_accepted": result.get("voice_wav_output_accepted"),
                    "followup_status": result.get("followup_status"),
                    "followup_transcript": result.get("followup_transcript", ""),
                    "followup_voice_wav_output_accepted": result.get("followup_voice_wav_output_accepted"),
                    "lab_conversation_mode": result.get("lab_conversation_mode"),
                    "lab_conversation_response": result.get("lab_conversation_response"),
                    "lab_conversation_intent": result.get("lab_conversation_intent"),
                    "lab_conversation_action": result.get("lab_conversation_action"),
                    "lab_conversation_voice_wav_output_accepted": result.get("lab_conversation_voice_wav_output_accepted"),
                    "interaction_artifact": str(INTERACTION_PATH.relative_to(ROOT)) if INTERACTION_PATH.exists() else "",
                    "followup_artifact": str(FOLLOWUP_PATH.relative_to(ROOT)) if FOLLOWUP_PATH.exists() else "",
                },
            )
            publish_cooldown_log(device=device, result=result, cooldown_seconds=cooldown_seconds)
            time.sleep(cooldown_seconds)
        time.sleep(max(0.1, args.idle_seconds))


if __name__ == "__main__":
    raise SystemExit(main())
