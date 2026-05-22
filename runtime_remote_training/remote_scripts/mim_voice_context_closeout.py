#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import signal
import subprocess
import tempfile
import time
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
PERSONA_STATUS_PATH = SHARED / "MIM_NATURAL_TTS_PERSONA_STATUS.latest.json"
BARGE_IN_STATUS_PATH = SHARED / "MIM_BARGE_IN_RECOVERY_STATUS.latest.json"
VOICE_PERSONA_STATUS_PATH = SHARED / "MIM_VOICE_PERSONA_STATUS.latest.json"
VOICE_PERSONA_PLAYBACK_PATH = SHARED / "MIM_VOICE_PERSONA_PLAYBACK_TEST.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        return payload if isinstance(payload, dict) else {}
    except Exception:
        return {}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def relative(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def first_playback_device() -> str:
    raw = os.environ.get("MIM_WAKE_PLAYBACK_DEVICES", "").strip()
    if raw:
        return next((item.strip() for item in raw.split(";") if item.strip()), raw)
    return "plughw:1,0"


def run_command(args: list[str], *, timeout: int = 30) -> dict[str, Any]:
    try:
        proc = subprocess.run(args, cwd=str(ROOT), text=True, capture_output=True, timeout=timeout, check=False)
        return {
            "command": args,
            "returncode": proc.returncode,
            "stdout": proc.stdout[-2000:],
            "stderr": proc.stderr[-2000:],
            "ok": proc.returncode == 0,
        }
    except Exception as exc:
        return {"command": args, "returncode": None, "stdout": "", "stderr": f"{type(exc).__name__}: {exc}", "ok": False}


def wav_duration(path: Path) -> float:
    try:
        with wave.open(str(path), "rb") as wav_file:
            return wav_file.getnframes() / float(wav_file.getframerate())
    except Exception:
        return 0.0


def publish_natural_tts_persona_status() -> dict[str, Any]:
    persona = read_json(VOICE_PERSONA_STATUS_PATH)
    playback = read_json(VOICE_PERSONA_PLAYBACK_PATH)
    sample = ROOT / str(persona.get("sample_artifact") or "runtime/shared/MIM_VOICE_PERSONA_SAMPLE.wav")
    success = bool(persona.get("success") and playback.get("success") and sample.exists() and sample.stat().st_size > 1000)
    payload = {
        "packet_type": "mim-natural-tts-persona-status-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-NATURAL-TTS-PERSONA-V1",
        "status": "completed_with_evidence" if success else "blocked_with_evidence",
        "success": success,
        "voice_engine": persona.get("voice_engine"),
        "voice_model": persona.get("voice_model"),
        "length_scale": persona.get("length_scale"),
        "noise_scale": persona.get("noise_scale"),
        "noise_w_scale": persona.get("noise_w_scale"),
        "volume": persona.get("volume"),
        "persona_target": persona.get("persona_target"),
        "sample_artifact": persona.get("sample_artifact"),
        "sample_exists": sample.exists(),
        "sample_duration_seconds": round(wav_duration(sample), 2),
        "playback_test": playback,
        "evidence_source_artifacts": [
            "runtime/shared/MIM_VOICE_PERSONA_STATUS.latest.json",
            "runtime/shared/MIM_VOICE_PERSONA_PLAYBACK_TEST.latest.json",
            "runtime/shared/MIM_VOICE_PERSONA_SAMPLE.wav",
        ],
        "constraints": {
            "no_raw_audio_retained": True,
            "no_beep_loop": True,
            "voice_only_playback_route": True,
        },
        "next_recovery_action": "" if success else "Regenerate persona sample and replay through the active playback device.",
        "no_audio_retained": True,
    }
    write_json(PERSONA_STATUS_PATH, payload)
    return payload


def synthesize_barge_in_sample(output_path: Path) -> dict[str, Any]:
    model = Path(
        os.environ.get(
            "MIM_VOICE_PIPER_MODEL",
            ROOT / "runtime" / "models" / "piper" / "en_US-arctic-medium" / "en_US-arctic-medium.onnx",
        )
    )
    text = (
        "Barge in recovery test. I am intentionally speaking long enough for an interrupt signal. "
        "When the interrupt arrives, playback should stop quickly and the next operator turn should take priority."
    )
    with tempfile.NamedTemporaryFile(prefix="mim-barge-in-", suffix=".txt", mode="w", encoding="utf-8", delete=False) as tmp:
        tmp.write(text)
        text_path = Path(tmp.name)
    try:
        command = [
            str(ROOT / ".venv" / "bin" / "piper"),
            "-m",
            str(model),
            "-i",
            str(text_path),
            "-f",
            str(output_path),
            "--length-scale",
            os.environ.get("MIM_VOICE_PIPER_LENGTH_SCALE", "0.78"),
            "--noise-scale",
            os.environ.get("MIM_VOICE_PIPER_NOISE_SCALE", "0.46"),
            "--noise-w-scale",
            os.environ.get("MIM_VOICE_PIPER_NOISE_W_SCALE", "0.62"),
            "--volume",
            os.environ.get("MIM_VOICE_PIPER_VOLUME", "1.16"),
        ]
        return run_command(command, timeout=30)
    finally:
        try:
            text_path.unlink(missing_ok=True)
        except Exception:
            pass


def publish_barge_in_recovery_status() -> dict[str, Any]:
    output_path = SHARED / "MIM_BARGE_IN_RECOVERY_TEST.wav"
    synthesis = synthesize_barge_in_sample(output_path)
    playback_device = first_playback_device()
    interrupt_after_seconds = 1.25
    stop_started = 0.0
    stopped_at = 0.0
    proc_returncode: int | None = None
    stop_signal_sent = False
    stop_error = ""
    if synthesis.get("ok") and output_path.exists():
        proc = subprocess.Popen(
            ["aplay", "-D", playback_device, str(output_path)],
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(interrupt_after_seconds)
        stop_started = time.perf_counter()
        stop_signal_sent = True
        proc.terminate()
        try:
            proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate(timeout=2)
        stopped_at = time.perf_counter()
        proc_returncode = proc.returncode
    else:
        stop_error = synthesis.get("stderr") or synthesis.get("stdout") or "barge_in_sample_synthesis_failed"
    stop_latency_ms = int(round((stopped_at - stop_started) * 1000)) if stopped_at and stop_started else None
    playback_stopped = bool(stop_signal_sent and proc_returncode is not None and proc_returncode != 0 and (stop_latency_ms or 9999) <= 2000)
    success = bool(synthesis.get("ok") and playback_stopped)
    payload = {
        "packet_type": "mim-barge-in-recovery-status-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-BARGE-IN-RECOVERY-V1",
        "status": "completed_with_evidence" if success else "blocked_with_evidence",
        "success": success,
        "evidence_type": "controlled_interrupt_playback_stop_test",
        "interrupt_detection": {
            "source": "closeout_harness_controlled_interrupt_event",
            "detected": stop_signal_sent,
            "interrupt_after_seconds": interrupt_after_seconds,
            "live_microphone_detection_validated": False,
            "next_live_validation": "During a real spoken interruption, reuse this stop path after VAD detects speech while playback is active.",
        },
        "playback_stop_evidence": {
            "playback_device": playback_device,
            "sample_artifact": relative(output_path),
            "sample_duration_seconds": round(wav_duration(output_path), 2),
            "stop_signal_sent": stop_signal_sent,
            "playback_returncode_after_stop": proc_returncode,
            "stop_latency_ms": stop_latency_ms,
            "playback_stopped_before_natural_completion": playback_stopped,
        },
        "synthesis": synthesis,
        "constraints": {
            "no_raw_audio_retained": True,
            "no_operator_audio_required": True,
            "no_beep_loop": True,
        },
        "next_recovery_action": "" if success else stop_error or "Repair playback stop control path.",
        "no_audio_retained": True,
    }
    write_json(BARGE_IN_STATUS_PATH, payload)
    return payload


def main() -> int:
    persona = publish_natural_tts_persona_status()
    barge = publish_barge_in_recovery_status()
    print(json.dumps({"persona": persona, "barge_in": barge}, indent=2))
    return 0 if persona.get("success") and barge.get("success") else 1


if __name__ == "__main__":
    raise SystemExit(main())
