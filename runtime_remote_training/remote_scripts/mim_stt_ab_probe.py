#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
WAKE_SCRIPT = ROOT / "scripts" / "mim_wake_listen_loop.py"
ARTIFACT = SHARED / "MIM_STT_AB_PROBE.latest.json"


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


def run_vosk(wake: Any, wav_path: Path) -> dict[str, Any]:
    started = time.time()
    try:
        model = wake.Model(str(wake.MODEL_PATH))
        result = wake.transcribe_wav(model, wav_path)
        result["duration_seconds"] = round(time.time() - started, 3)
        return result
    except Exception as exc:
        return {
            "ok": False,
            "text": "",
            "wake_text": "",
            "error": f"{type(exc).__name__}: {exc}",
            "duration_seconds": round(time.time() - started, 3),
        }


def run_faster_whisper(
    wav_path: Path,
    *,
    model_size: str,
    device: str,
    compute_type: str,
    vad_filter: bool = True,
) -> dict[str, Any]:
    started = time.time()
    try:
        from faster_whisper import WhisperModel
    except Exception as exc:
        return {
            "ok": False,
            "text": "",
            "error": f"faster_whisper_import_failed: {type(exc).__name__}: {exc}",
            "duration_seconds": round(time.time() - started, 3),
        }
    try:
        model = WhisperModel(model_size, device=device, compute_type=compute_type)
        segments, info = model.transcribe(
            str(wav_path),
            beam_size=5,
            vad_filter=vad_filter,
            vad_parameters={"min_silence_duration_ms": 500},
            language="en",
            condition_on_previous_text=False,
        )
        text = " ".join(segment.text.strip() for segment in segments if segment.text.strip()).strip()
        return {
            "ok": True,
            "text": text,
            "language": getattr(info, "language", ""),
            "language_probability": getattr(info, "language_probability", None),
            "duration_seconds": round(time.time() - started, 3),
            "model_size": model_size,
            "device": device,
            "compute_type": compute_type,
            "vad_filter": vad_filter,
            "error": "",
        }
    except Exception as exc:
        fallback_device = "cpu" if device != "cpu" else ""
        if fallback_device:
            fallback = run_faster_whisper(wav_path, model_size=model_size, device="cpu", compute_type="int8", vad_filter=vad_filter)
            fallback["fallback_from"] = {"device": device, "compute_type": compute_type, "error": f"{type(exc).__name__}: {exc}"}
            return fallback
        return {
            "ok": False,
            "text": "",
            "error": f"{type(exc).__name__}: {exc}",
            "duration_seconds": round(time.time() - started, 3),
            "model_size": model_size,
            "device": device,
            "compute_type": compute_type,
            "vad_filter": vad_filter,
        }


def main() -> int:
    parser = argparse.ArgumentParser(description="Record one MIM mic sample and compare Vosk vs faster-whisper STT.")
    parser.add_argument("--device", default="", help="ALSA capture device. Defaults to listener-selected device.")
    parser.add_argument("--seconds", type=int, default=8, help="Capture duration.")
    parser.add_argument("--model-size", default="small.en", help="faster-whisper model size.")
    parser.add_argument("--whisper-device", default="cuda", help="cuda or cpu.")
    parser.add_argument("--compute-type", default="float16", help="faster-whisper compute type.")
    parser.add_argument("--expected", default="", help="Optional expected phrase for operator-visible evidence.")
    args = parser.parse_args()

    wake = load_wake_module()
    device = args.device.strip()
    selection: dict[str, Any] = {}
    if not device:
        device, selection = wake.select_audio_device(wake.configured_devices())
    if not device:
        payload = {
            "packet_type": "mim-stt-ab-probe-v1",
            "generated_at": now_iso(),
            "status": "blocked_with_evidence",
            "success": False,
            "error": "no_openable_audio_device",
            "selection": selection,
            "no_audio_retained": True,
        }
        write_json(ARTIFACT, payload)
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 2

    with tempfile.NamedTemporaryFile(prefix="mim-stt-ab-", suffix=".wav", delete=False) as tmp:
        wav_path = Path(tmp.name)
    try:
        rec = wake.record_wav(device, wav_path, seconds=max(1, args.seconds))
        level = wake.audio_level(wav_path) if rec.get("ok") else {}
        vad = wake.analyze_vad_segments(wav_path) if rec.get("ok") else {}
        vosk = run_vosk(wake, wav_path) if rec.get("ok") else {"ok": False, "text": "", "error": "record_failed"}
        whisper = (
            run_faster_whisper(
                wav_path,
                model_size=args.model_size,
                device=args.whisper_device,
                compute_type=args.compute_type,
            )
            if rec.get("ok")
            else {"ok": False, "text": "", "error": "record_failed"}
        )
        if rec.get("ok") and whisper.get("ok") and not str(whisper.get("text") or "").strip():
            whisper_no_vad = run_faster_whisper(
                wav_path,
                model_size=args.model_size,
                device=args.whisper_device,
                compute_type=args.compute_type,
                vad_filter=False,
            )
        else:
            whisper_no_vad = {"ok": False, "skipped": True, "reason": "vad_filtered_result_was_not_empty_or_record_failed"}
        payload = {
            "packet_type": "mim-stt-ab-probe-v1",
            "generated_at": now_iso(),
            "objective_id": "MIM-LAB-STT-UPGRADE-V1",
            "status": "completed_with_evidence" if rec.get("ok") else "blocked_with_evidence",
            "success": bool(rec.get("ok")),
            "audio_device": device,
            "capture_seconds": max(1, args.seconds),
            "expected_phrase": args.expected,
            "audio_level": level,
            "vad": vad,
            "vosk": vosk,
            "faster_whisper": whisper,
            "faster_whisper_no_vad": whisper_no_vad,
            "recommendation": "promote_faster_whisper" if whisper.get("ok") and whisper.get("text") and whisper.get("text") != vosk.get("text") else "collect_more_samples",
            "record_command": rec.get("command"),
            "record_error": rec.get("stderr") or rec.get("stdout") or "",
            "selection": selection,
            "no_audio_retained": True,
        }
        write_json(ARTIFACT, payload)
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0 if payload["success"] else 1
    finally:
        try:
            wav_path.unlink(missing_ok=True)
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
