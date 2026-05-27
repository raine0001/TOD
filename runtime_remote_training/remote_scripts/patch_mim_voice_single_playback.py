#!/usr/bin/env python3
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
DROPIN = Path("/home/testpilot/.config/systemd/user/mim-speech-turn-engine.service.d/playback-fanout.conf")
ARTIFACT = ROOT / "runtime" / "shared" / "MIM_VOICE_SINGLE_PLAYBACK_OUTPUT.latest.json"


def run(cmd):
    p = subprocess.run(cmd, text=True, capture_output=True)
    return {"cmd": cmd, "returncode": p.returncode, "stdout": p.stdout.strip(), "stderr": p.stderr.strip()}


def main():
    DROPIN.parent.mkdir(parents=True, exist_ok=True)
    selected = "plughw:1,0"
    DROPIN.write_text(
        "\n".join(
            [
                "[Service]",
                "# Single output after fanout proved audio path; prevents duplicate spoken answers.",
                f"Environment=MIM_WAKE_PLAYBACK_DEVICES={selected}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    commands = [
        run(["systemctl", "--user", "daemon-reload"]),
        run(["systemctl", "--user", "restart", "mim-speech-turn-engine.service"]),
        run(["systemctl", "--user", "is-active", "mim-speech-turn-engine.service"]),
        run(["systemctl", "--user", "show", "mim-speech-turn-engine.service", "-p", "Environment", "--no-pager"]),
    ]
    active = commands[2]["stdout"] == "active"
    payload = {
        "packet_type": "mim-voice-single-playback-output-v1",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "success": active,
        "status": "active" if active else "service_not_active",
        "objective_id": "MIM-VOICE-RELIABILITY-V2",
        "selected_playback_device": selected,
        "reason": "MIM was configured to play each response through multiple devices; that can sound like the same answer twice.",
        "previous_mode": "fanout_to_default_analog_usb_and_hdmi",
        "commands": commands,
        "next_validation": "Ask one direct question. MIM should speak once. If silent, switch selected_playback_device to plughw:4,0 or default.",
    }
    ARTIFACT.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if active else 1


if __name__ == "__main__":
    raise SystemExit(main())
