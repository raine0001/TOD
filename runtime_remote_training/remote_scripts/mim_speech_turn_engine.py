#!/usr/bin/env python3
from __future__ import annotations

import argparse
import audioop
import importlib.util
import json
import os
import subprocess
import tempfile
import time
import wave
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
WAKE_SCRIPT = ROOT / "scripts" / "mim_wake_listen_loop.py"
STATUS_PATH = SHARED / "MIM_SPEECH_TURN_ENGINE_STATUS.latest.json"
TURN_PATH = SHARED / "MIM_SPEECH_TURN_ENGINE_TURN.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(path)


def load_wake_module() -> Any:
    spec = importlib.util.spec_from_file_location("mim_wake_listen_loop", WAKE_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {WAKE_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_wav(path: Path, frames: bytes, *, rate: int = 16000) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(rate)
        wav_file.writeframes(frames)


def rms_of(frame: bytes) -> int:
    if not frame:
        return 0
    return int(audioop.rms(frame, 2))


def max_of(frame: bytes) -> int:
    if not frame:
        return 0
    return int(audioop.max(frame, 2))


def summarize_audio(frames: bytes) -> dict[str, Any]:
    return {
        "bytes": len(frames),
        "rms": rms_of(frames),
        "max": max_of(frames),
        "clipped": max_of(frames) >= 32000,
        "noise_risk": "high" if rms_of(frames) >= 900 else "medium" if rms_of(frames) >= 500 else "low",
    }


def start_arecord(device: str) -> subprocess.Popen[bytes]:
    return subprocess.Popen(
        [
            "arecord",
            "-D",
            device,
            "-f",
            "S16_LE",
            "-r",
            "16000",
            "-c",
            "1",
            "-t",
            "raw",
        ],
        cwd=str(ROOT),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def publish_status(**kwargs: Any) -> None:
    payload = {
        "packet_type": "mim-speech-turn-engine-status-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-FULL-TIME-SPEECH-RECOGNITION-ENGINE-V1",
        "status": kwargs.pop("status", "listening"),
        "success": kwargs.pop("success", True),
        "policy": "Continuous listener assembles complete speech turns before STT and routing.",
        "no_audio_retained": True,
        **kwargs,
    }
    write_json(STATUS_PATH, payload)


def route_turn(wake: Any, model: Any, device: str, frames: bytes, turn_meta: dict[str, Any]) -> dict[str, Any]:
    with tempfile.NamedTemporaryFile(prefix="mim-speech-turn-", suffix=".wav", delete=False) as tmp:
        wav_path = Path(tmp.name)
    started = time.time()
    try:
        write_wav(wav_path, frames)
        level = wake.audio_level(wav_path)
        vad = wake.analyze_vad_segments(wav_path)
        total_vad_speech_ms = sum(int(segment.get("duration_ms") or 0) for segment in vad.get("segments", []))
        min_stt_rms = int(os.environ.get("MIM_TURN_MIN_STT_RMS", "280"))
        min_stt_max = int(os.environ.get("MIM_TURN_MIN_STT_MAX", "2500"))
        min_stt_speech_ms = int(os.environ.get("MIM_TURN_MIN_STT_SPEECH_MS", "700"))
        force_stt_max = int(os.environ.get("MIM_TURN_FORCE_STT_MAX", "8000"))
        skip_reason = ""
        if int(level.get("rms") or 0) < min_stt_rms and int(level.get("max") or 0) < min_stt_max:
            skip_reason = "low_energy_turn_below_stt_gate"
        elif total_vad_speech_ms < min_stt_speech_ms and int(level.get("max") or 0) < force_stt_max:
            skip_reason = "short_vad_speech_below_stt_gate"
        if skip_reason:
            result = {
                "status": "observed_prespeech_noise",
                "success": True,
                "audio_device": device,
                "audio_level": level,
                "vad": {
                    "speech_detected": bool(vad.get("segments")),
                    "segments": vad.get("segments", []),
                    "total_speech_ms": total_vad_speech_ms,
                    "artifact": str(wake.VAD_STATUS_PATH.relative_to(ROOT)),
                },
                "transcript": "",
                "general_transcript": "",
                "wake_transcript": "",
                "stt_engine": "skipped_prespeech_gate",
                "stt_primary": {
                    "engine": "prespeech_gate",
                    "ok": False,
                    "reason": skip_reason,
                    "min_stt_rms": min_stt_rms,
                    "min_stt_max": min_stt_max,
                    "min_stt_speech_ms": min_stt_speech_ms,
                    "force_stt_max": force_stt_max,
                },
                "stt_fallback": {},
                "wake_phrase_detected": False,
                "probable_wake_check": False,
                "self_output_detected": False,
                "stt_error": "",
                "lab_conversation_mode": True,
                "lab_conversation_response": False,
                "lab_conversation_intent": "prespeech_noise",
                "lab_conversation_action": "observe_without_response",
                "lab_conversation_fragment_classification": {},
                "lab_conversation_addressing_decision": {},
                "lab_conversation_voice_wav_output_accepted": None,
                "no_audio_retained": True,
            }
            wake.publish_transcript_log(result, device=device)
            wake.publish_diagnostic(result, device=device, selection={})
            payload = {
                "packet_type": "mim-speech-turn-engine-turn-v1",
                "generated_at": now_iso(),
                "objective_id": "MIM-FULL-TIME-SPEECH-RECOGNITION-ENGINE-V1",
                "status": result["status"],
                "success": True,
                "audio_device": device,
                "turn": turn_meta,
                "latency_seconds": round(time.time() - started, 3),
                "transcript": "",
                "general_transcript": "",
                "wake_transcript": "",
                "stt_engine": result["stt_engine"],
                "stt_primary": result["stt_primary"],
                "stt_fallback": {},
                "lab_conversation_intent": result["lab_conversation_intent"],
                "lab_conversation_action": result["lab_conversation_action"],
                "lab_conversation_response": False,
                "voice_wav_output_accepted": None,
                "audio_level": level,
                "vad": result["vad"],
                "no_audio_retained": True,
            }
            write_json(TURN_PATH, payload)
            return payload
        stt = wake.transcribe_wav(model, wav_path)
        transcript = wake.select_effective_transcript(stt.get("text", ""), stt.get("wake_text", ""))
        self_output_detected = wake.detect_self_output(stt.get("text", "")) or wake.detect_self_output(stt.get("wake_text", ""))
        lab_turn: dict[str, Any] = {}
        if transcript and not self_output_detected:
            lab_turn = wake.handle_lab_conversation(transcript)
        result = {
            "status": lab_turn.get("status") if lab_turn else "heard_no_route",
            "success": True,
            "audio_device": device,
            "audio_level": level,
            "vad": {
                "speech_detected": True,
                "segments": vad.get("segments", []),
                "artifact": str(wake.VAD_STATUS_PATH.relative_to(ROOT)),
            },
            "transcript": transcript,
            "general_transcript": stt.get("text", ""),
            "wake_transcript": stt.get("wake_text", ""),
            "stt_engine": stt.get("stt_engine", ""),
            "stt_primary": stt.get("stt_primary", {}),
            "stt_fallback": stt.get("stt_fallback", {}),
            "wake_phrase_detected": False,
            "probable_wake_check": False,
            "self_output_detected": self_output_detected,
            "stt_error": stt.get("error", ""),
            "lab_conversation_mode": True,
            "lab_conversation_response": bool(lab_turn.get("response_text")),
            "lab_conversation_intent": lab_turn.get("intent"),
            "lab_conversation_action": lab_turn.get("action"),
            "lab_conversation_fragment_classification": lab_turn.get("fragment_classification", {}),
            "lab_conversation_addressing_decision": lab_turn.get("addressing_decision", {}),
            "lab_conversation_voice_wav_output_accepted": lab_turn.get("voice_wav_output_accepted"),
            "no_audio_retained": True,
        }
        wake.publish_transcript_log(result, device=device)
        wake.publish_diagnostic(result, device=device, selection={})
        payload = {
            "packet_type": "mim-speech-turn-engine-turn-v1",
            "generated_at": now_iso(),
            "objective_id": "MIM-FULL-TIME-SPEECH-RECOGNITION-ENGINE-V1",
            "status": result["status"],
            "success": True,
            "audio_device": device,
            "turn": turn_meta,
            "latency_seconds": round(time.time() - started, 3),
            "transcript": transcript,
            "general_transcript": stt.get("text", ""),
            "wake_transcript": stt.get("wake_text", ""),
            "stt_engine": result.get("stt_engine"),
            "stt_primary": result.get("stt_primary"),
            "stt_fallback": result.get("stt_fallback"),
            "lab_conversation_intent": result.get("lab_conversation_intent"),
            "lab_conversation_action": result.get("lab_conversation_action"),
            "lab_conversation_response": result.get("lab_conversation_response"),
            "voice_wav_output_accepted": result.get("lab_conversation_voice_wav_output_accepted"),
            "audio_level": level,
            "no_audio_retained": True,
        }
        write_json(TURN_PATH, payload)
        return payload
    finally:
        try:
            wav_path.unlink(missing_ok=True)
        except Exception:
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default="")
    parser.add_argument("--frame-ms", type=int, default=int(os.environ.get("MIM_TURN_FRAME_MS", "100")))
    parser.add_argument("--start-frames", type=int, default=int(os.environ.get("MIM_TURN_START_FRAMES", "3")))
    parser.add_argument("--end-silence-ms", type=int, default=int(os.environ.get("MIM_TURN_END_SILENCE_MS", "850")))
    parser.add_argument("--min-turn-ms", type=int, default=int(os.environ.get("MIM_TURN_MIN_MS", "600")))
    parser.add_argument("--max-turn-ms", type=int, default=int(os.environ.get("MIM_TURN_MAX_MS", "12000")))
    parser.add_argument("--preroll-ms", type=int, default=int(os.environ.get("MIM_TURN_PREROLL_MS", "300")))
    parser.add_argument("--threshold-multiplier", type=float, default=float(os.environ.get("MIM_TURN_THRESHOLD_MULTIPLIER", "2.4")))
    parser.add_argument("--min-threshold-rms", type=int, default=int(os.environ.get("MIM_TURN_MIN_THRESHOLD_RMS", "220")))
    parser.add_argument("--max-threshold-rms", type=int, default=int(os.environ.get("MIM_TURN_MAX_THRESHOLD_RMS", "1800")))
    parser.add_argument("--start-max-level", type=int, default=int(os.environ.get("MIM_TURN_START_MAX_LEVEL", "650")))
    parser.add_argument("--status-interval-seconds", type=float, default=float(os.environ.get("MIM_TURN_STATUS_INTERVAL_SECONDS", "2.0")))
    args = parser.parse_args()

    wake = load_wake_module()
    device = args.device.strip()
    selection: dict[str, Any] = {}
    if not device:
        device, selection = wake.select_audio_device()
    if not device:
        publish_status(status="blocked_with_evidence", success=False, reason_code="no_openable_microphone", device_selection=selection)
        return 2

    model = wake.Model(str(wake.MODEL_PATH))
    bytes_per_frame = max(1, int(16000 * args.frame_ms / 1000) * 2)
    silence_frames_to_end = max(1, int(args.end_silence_ms / args.frame_ms))
    min_frames = max(1, int(args.min_turn_ms / args.frame_ms))
    max_frames = max(1, int(args.max_turn_ms / args.frame_ms))
    preroll_frames = max(0, int(args.preroll_ms / args.frame_ms))

    noise_window: deque[int] = deque(maxlen=50)
    preroll: deque[bytes] = deque(maxlen=preroll_frames)
    in_turn = False
    turn_frames: list[bytes] = []
    speech_run = 0
    silence_run = 0
    turn_started_at = ""
    proc: subprocess.Popen[bytes] | None = None
    last_status_at = 0.0
    publish_status(status="starting", audio_device=device, device_selection=selection)

    while True:
        if proc is None or proc.poll() is not None:
            proc = start_arecord(device)
            publish_status(status="listening", audio_device=device, device_selection=selection, recorder_pid=proc.pid)
            time.sleep(0.2)
        assert proc.stdout is not None
        frame = proc.stdout.read(bytes_per_frame)
        if len(frame) < bytes_per_frame:
            publish_status(status="recorder_restarting", audio_device=device, recorder_returncode=proc.poll())
            try:
                proc.kill()
            except Exception:
                pass
            proc = None
            time.sleep(1)
            continue

        rms = rms_of(frame)
        max_level = max_of(frame)
        if not in_turn:
            noise_window.append(rms)
        sorted_noise = sorted(noise_window) or [0]
        floor = int(sum(sorted_noise[: max(1, len(sorted_noise) // 2)]) / max(1, len(sorted_noise[: max(1, len(sorted_noise) // 2)])))
        threshold = max(args.min_threshold_rms, min(args.max_threshold_rms, int(floor * args.threshold_multiplier)))
        is_speech = rms >= threshold and max_level >= args.start_max_level

        now = time.time()
        if not in_turn and now - last_status_at >= args.status_interval_seconds:
            publish_status(
                status="listening",
                audio_device=device,
                recorder_pid=proc.pid,
                live_capture={
                    "frame_ms": args.frame_ms,
                    "rms": rms,
                    "max": max_level,
                    "noise_floor_rms": floor,
                    "speech_threshold_rms": threshold,
                    "speech_run": speech_run,
                    "is_speech_frame": is_speech,
                    "threshold_multiplier": args.threshold_multiplier,
                    "min_threshold_rms": args.min_threshold_rms,
                    "max_threshold_rms": args.max_threshold_rms,
                    "start_max_level": args.start_max_level,
                },
                device_selection=selection,
            )
            last_status_at = now

        if not in_turn:
            preroll.append(frame)
            if is_speech:
                speech_run += 1
            else:
                speech_run = 0
            if speech_run >= args.start_frames:
                in_turn = True
                turn_started_at = now_iso()
                turn_frames = list(preroll)
                silence_run = 0
                publish_status(
                    status="speech_turn_active",
                    audio_device=device,
                    turn_started_at=turn_started_at,
                    noise_floor_rms=floor,
                    speech_threshold_rms=threshold,
                    start_rms=rms,
                    start_max=max_level,
                )
            continue

        turn_frames.append(frame)
        if is_speech:
            silence_run = 0
        else:
            silence_run += 1
        frame_count = len(turn_frames)
        should_end = (frame_count >= min_frames and silence_run >= silence_frames_to_end) or frame_count >= max_frames
        if not should_end:
            continue

        frames_blob = b"".join(turn_frames)
        duration_ms = frame_count * args.frame_ms
        turn_meta = {
            "started_at": turn_started_at,
            "ended_at": now_iso(),
            "duration_ms": duration_ms,
            "frame_ms": args.frame_ms,
            "frames": frame_count,
            "end_reason": "max_turn_ms" if frame_count >= max_frames else "silence_after_speech",
            "noise_floor_rms": floor,
            "speech_threshold_rms": threshold,
            "audio_level": summarize_audio(frames_blob),
        }
        publish_status(status="speech_turn_transcribing", audio_device=device, turn=turn_meta)
        try:
            turn_payload = route_turn(wake, model, device, frames_blob, turn_meta)
            publish_status(
                status="listening",
                audio_device=device,
                last_turn=turn_payload,
                device_selection=selection,
            )
        except Exception as exc:
            publish_status(
                status="turn_failed_with_evidence",
                success=False,
                audio_device=device,
                turn=turn_meta,
                error=f"{type(exc).__name__}: {exc}",
            )
        in_turn = False
        turn_frames = []
        speech_run = 0
        silence_run = 0
        preroll.clear()


if __name__ == "__main__":
    raise SystemExit(main())
