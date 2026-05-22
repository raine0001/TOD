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
VOICE_PIPER_SPEAKER = os.environ.get("MIM_VOICE_PIPER_SPEAKER", "").strip()
VOICE_PIPER_LENGTH_SCALE = os.environ.get("MIM_VOICE_PIPER_LENGTH_SCALE", "0.82").strip()
VOICE_PIPER_NOISE_SCALE = os.environ.get("MIM_VOICE_PIPER_NOISE_SCALE", "0.48").strip()
VOICE_PIPER_NOISE_W_SCALE = os.environ.get("MIM_VOICE_PIPER_NOISE_W_SCALE", "0.65").strip()
VOICE_PIPER_VOLUME = os.environ.get("MIM_VOICE_PIPER_VOLUME", "1.18").strip()

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
        data = path.read_bytes()
        if not data:
            return {"bytes": 0, "rms": 0, "max": 0}
        return {"bytes": len(data), "rms": int(audioop.rms(data, 2)), "max": int(audioop.max(data, 2))}
    except Exception:
        return {"bytes": 0, "rms": 0, "max": 0}


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
    entry = {
        "generated_at": now_iso(),
        "packet_type": "mim-voice-transcript-log-entry-v1",
        "audio_device": device,
        "status": result.get("status"),
        "transcript": transcript,
        "general_transcript": general,
        "wake_transcript": wake_text,
        "stt_error": result.get("stt_error", ""),
        "audio_level": level,
        "vad": vad,
        "self_output_detected": result.get("self_output_detected", False),
        "wake_phrase_detected": result.get("wake_phrase_detected", False),
        "lab_conversation_mode": result.get("lab_conversation_mode"),
        "lab_conversation_response": result.get("lab_conversation_response"),
        "lab_conversation_intent": result.get("lab_conversation_intent"),
        "lab_conversation_action": result.get("lab_conversation_action"),
        "lab_conversation_fragment_classification": result.get("lab_conversation_fragment_classification", {}),
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
        "general_transcript": "",
        "wake_transcript": "",
        "stt_error": "",
        "audio_level": {},
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
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return {"_error": f"{type(exc).__name__}: {exc}"}
    return {}


def compact_status(value: Any) -> str:
    text = str(value or "").strip()
    return text if text else "unknown"


def transcript_words(transcript: str) -> list[str]:
    return re.findall(r"[a-zA-Z0-9']+", str(transcript or "").lower())


def classify_voice_fragment(transcript: str) -> dict[str, Any]:
    words = transcript_words(transcript)
    if not words:
        return {"is_fragment": True, "reason_code": "empty_transcript", "word_count": 0, "words": []}
    unique = set(words)
    if len(words) == 1 and words[0] in LOW_CONTENT_TOKENS:
        return {"is_fragment": True, "reason_code": "single_low_content_token", "word_count": 1, "words": words}
    if len(words) <= 2 and not unique.intersection(ACTIONABLE_TOKENS):
        return {"is_fragment": True, "reason_code": "short_non_actionable_transcript", "word_count": len(words), "words": words}
    return {"is_fragment": False, "reason_code": "actionable_or_contextual_transcript", "word_count": len(words), "words": words}


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
    normalized = re.sub(r"[^a-zA-Z0-9.' ]+", " ", str(transcript or "")).strip().lower()
    turn_state = load_turn_state()
    previous_topic = str(turn_state.get("current_topic") or "").strip()
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
        stt = transcribe_wav(model, wav_path)
        transcript = stt.get("text", "") or stt.get("wake_text", "")
        self_output_detected = detect_self_output(stt.get("text", "")) or detect_self_output(stt.get("wake_text", ""))
        route = {"intent": "none", "action": "none", "artifacts": []}
        if not stt["ok"]:
            status = "stt_blocked"
            response_text = ""
        elif self_output_detected:
            status = "ignored_self_output"
            response_text = ""
        elif transcript:
            fragment = classify_voice_fragment(transcript)
            if fragment.get("is_fragment"):
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
    fragment = classify_voice_fragment(transcript)
    if fragment.get("is_fragment"):
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
            "turn_state_artifact": str(TURN_STATE_PATH.relative_to(ROOT)),
            "response_text": "",
            "voice_response": {},
            "voice_wav_output_accepted": None,
            "no_audio_retained": True,
            "policy": "MIM listens continuously, but low-content STT fragments are evidence only and do not trigger a spoken clarification.",
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
        "objective_id": "MIM-LISTENING-AND-VOICE-PERSONA-V1",
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
        "turn_state_artifact": str(TURN_STATE_PATH.relative_to(ROOT)),
        "response_text": response_text,
        "voice_response": voice_response,
        "voice_wav_output_accepted": bool(voice_response.get("any_output_accepted")) if response_text else None,
        "no_audio_retained": True,
        "policy": "MIM listens to lab audio continuously and responds to routed intents or direct questions; MIM is not triggered by her name.",
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
        stt = transcribe_wav(model, wav_path)
        transcript = stt.get("text", "") or stt.get("wake_text", "")
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
