#!/usr/bin/env python3
from __future__ import annotations

import audioop
import datetime
import importlib.util
import json
import subprocess
import time
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
OUT_PATH = SHARED / "MIM_AUDIO_OUTPUT_ACOUSTIC_PROBE.latest.json"


def load_wake_module():
    spec = importlib.util.spec_from_file_location("wake", ROOT / "scripts" / "mim_wake_listen_loop.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("wake_module_load_failed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def rms_of(path: Path) -> dict[str, int | str]:
    try:
        with wave.open(str(path), "rb") as wav:
            data = wav.readframes(wav.getnframes())
        return {
            "bytes": len(data),
            "rms": int(audioop.rms(data, 2)) if data else 0,
            "max": int(audioop.max(data, 2)) if data else 0,
        }
    except Exception as exc:
        return {"bytes": 0, "rms": 0, "max": 0, "error": f"{type(exc).__name__}: {exc}"}


def record_level(mic: str, path: Path, *, seconds: int) -> tuple[subprocess.Popen, Path]:
    proc = subprocess.Popen(
        [
            "arecord",
            "-D",
            mic,
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
            str(path),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return proc, path


def main() -> int:
    wake = load_wake_module()
    wav_path = str(wake.ensure_alert_wav())
    mic = "plughw:2,0"
    outputs = ["plughw:1,0", "plughw:3,0", "plughw:4,3", "plughw:4,7", "plughw:4,8", "plughw:4,9", "default"]

    baseline_path = Path("/tmp/mim_acoustic_baseline.wav")
    base = subprocess.run(
        ["arecord", "-D", mic, "-d", "2", "-f", "S16_LE", "-r", "16000", "-c", "1", "-t", "wav", str(baseline_path)],
        capture_output=True,
        text=True,
        timeout=6,
        check=False,
    )
    baseline = rms_of(baseline_path)
    baseline["record_returncode"] = base.returncode
    baseline["record_error"] = base.stderr[-500:]

    results = []
    for output in outputs:
        rec_path = Path(f"/tmp/mim_acoustic_{output.replace(':', '_').replace(',', '_')}.wav")
        rec, _ = record_level(mic, rec_path, seconds=3)
        time.sleep(0.35)
        try:
            play = subprocess.run(["timeout", "4", "aplay", "-D", output, wav_path], capture_output=True, text=True, timeout=6, check=False)
        except Exception as exc:
            play = subprocess.CompletedProcess(args=["aplay", output], returncode=99, stdout="", stderr=f"{type(exc).__name__}: {exc}")
        try:
            _, rec_err = rec.communicate(timeout=6)
        except subprocess.TimeoutExpired:
            rec.kill()
            _, rec_err = rec.communicate()
        level = rms_of(rec_path)
        results.append(
            {
                "output_device": output,
                "play_returncode": play.returncode,
                "play_error": play.stderr[-500:],
                "record_returncode": rec.returncode,
                "record_error": rec_err[-500:],
                "record_level": level,
                "rms_delta_from_baseline": int(level.get("rms", 0)) - int(baseline.get("rms", 0)),
            }
        )

    payload = {
        "packet_type": "mim-audio-output-acoustic-loopback-probe-v1",
        "generated_at": now_iso(),
        "mic_device": mic,
        "baseline": baseline,
        "results": results,
        "likely_audible_outputs": [item["output_device"] for item in results if item["rms_delta_from_baseline"] > 500],
        "operator_confirmed_audible_signal": {
            "confirmed": True,
            "signal": "multi-output alert beeps",
            "note": "Dave reported hearing the dots/beeps after the multi-output alert probe.",
        },
        "next_recovery_action": "Use multi-output alert as immediate acknowledgement while binding a higher-quality voice to the confirmed audible route.",
    }
    OUT_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
