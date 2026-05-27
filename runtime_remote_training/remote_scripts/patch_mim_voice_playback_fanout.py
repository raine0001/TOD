#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
WAKE = ROOT / "scripts" / "mim_wake_listen_loop.py"
DROPIN_DIR = Path("/home/testpilot/.config/systemd/user/mim-speech-turn-engine.service.d")
DROPIN = DROPIN_DIR / "playback-fanout.conf"
ARTIFACT = ROOT / "runtime" / "shared" / "MIM_VOICE_PLAYBACK_FANOUT.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main() -> int:
    changed: list[str] = []
    source = WAKE.read_text(encoding="utf-8")
    old = "def play_wav_on_outputs(wav_path: Path, *, stop_after_first_success: bool = True) -> list[dict[str, Any]]:"
    new = "def play_wav_on_outputs(wav_path: Path, *, stop_after_first_success: bool = False) -> list[dict[str, Any]]:"
    if old in source:
        source = source.replace(old, new, 1)
        WAKE.write_text(source, encoding="utf-8")
        changed.append("playback now tries every configured output instead of stopping at first accepted aplay device")

    DROPIN_DIR.mkdir(parents=True, exist_ok=True)
    # Try the analog speaker path before USB/HDMI, but keep all candidates.
    dropin_text = """[Service]
Environment=MIM_WAKE_PLAYBACK_DEVICES=default;plughw:4,0;plughw:1,0;plughw:5,3;plughw:5,7;plughw:5,8;plughw:5,9
"""
    if not DROPIN.exists() or DROPIN.read_text(encoding="utf-8") != dropin_text:
        DROPIN.write_text(dropin_text, encoding="utf-8")
        changed.append("playback device order now includes default and analog output before USB/HDMI candidates")

    subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
    subprocess.run(["systemctl", "--user", "restart", "mim-speech-turn-engine.service"], check=False)

    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    ARTIFACT.write_text(
        json.dumps(
            {
                "generated_at": now_iso(),
                "status": "patched" if changed else "already_patched",
                "success": True,
                "changed": changed,
                "reason": "MIM generated voice audio but playback stopped after plughw:1,0 accepted output; that may be a silent or wrong sink.",
                "expected_effect": "For each response, MIM attempts all configured audio outputs so at least one audible lab speaker path should receive the voice.",
            },
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    print(ARTIFACT.read_text(encoding="utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
