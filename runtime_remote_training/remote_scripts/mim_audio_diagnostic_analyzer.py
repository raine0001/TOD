#!/usr/bin/env python3
from __future__ import annotations

import audioop
import json
import sys
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"
STATUS = SHARED / "MIM_AUDIO_DIAGNOSTIC_STATUS.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> None:
    wav_path = Path(sys.argv[1]) if len(sys.argv) > 1 else SHARED / "audio_diagnostics" / "mim_direct_audio_diag_latest.wav"
    payload: dict[str, Any] = {
        "packet_type": "mim-audio-diagnostic-status-v1",
        "generated_at": now_iso(),
        "wav_path": str(wav_path),
        "exists": wav_path.exists(),
        "success": False,
    }
    if not wav_path.exists():
        payload["status"] = "blocked_wav_missing"
        write_json(STATUS, payload)
        return

    try:
        with wave.open(str(wav_path), "rb") as wf:
            frames = wf.readframes(wf.getnframes())
            rate = wf.getframerate()
            channels = wf.getnchannels()
            width = wf.getsampwidth()
        payload["audio_level"] = {
            "bytes": len(frames),
            "sample_rate": rate,
            "channels": channels,
            "sample_width": width,
            "duration_s": round(len(frames) / max(1, width) / max(1, channels) / max(1, rate), 3),
            "rms": int(audioop.rms(frames, width)),
            "max": int(audioop.max(frames, width)),
            "clipped": int(audioop.max(frames, width)) >= 32000,
        }
        sys.path.insert(0, str(ROOT / "scripts"))
        import mim_wake_listen_loop as wake  # type: ignore

        vad = wake.analyze_vad_segments(wav_path)
        model = wake.Model(str(wake.MODEL_PATH))
        stt = wake.transcribe_wav(model, wav_path)
        payload["vad"] = vad
        payload["stt"] = stt
        payload["selected_transcript"] = wake.select_effective_transcript(stt.get("text", ""), stt.get("wake_text", ""))
        payload["status"] = "completed_with_transcript" if payload["selected_transcript"] else "completed_empty_transcript"
        payload["success"] = True
    except Exception as exc:
        payload["status"] = "blocked_exception"
        payload["error"] = f"{type(exc).__name__}: {exc}"
    write_json(STATUS, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
