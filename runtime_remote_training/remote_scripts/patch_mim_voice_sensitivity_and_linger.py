#!/usr/bin/env python3
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
DROPIN_DIR = Path("/home/testpilot/.config/systemd/user/mim-speech-turn-engine.service.d")
DROPIN = DROPIN_DIR / "voice-sensitivity-and-linger.conf"
ARTIFACT = ROOT / "runtime" / "shared" / "MIM_VOICE_SENSITIVITY_AND_LINGER.latest.json"


def now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def run(cmd):
    completed = subprocess.run(cmd, text=True, capture_output=True)
    return {
        "cmd": cmd,
        "returncode": completed.returncode,
        "stdout": completed.stdout.strip(),
        "stderr": completed.stderr.strip(),
    }


def main():
    DROPIN_DIR.mkdir(parents=True, exist_ok=True)
    DROPIN.write_text(
        "\n".join(
            [
                "[Service]",
                "# Voice reliability tuning: catch quieter direct speech, but stop lingering",
                "# in conversation long enough to interrupt unrelated lab chatter.",
                "Environment=MIM_VOICE_ACTIVE_SESSION_SECONDS=12",
                "Environment=MIM_TURN_MIN_STT_RMS=95",
                "Environment=MIM_TURN_MIN_STT_MAX=600",
                "Environment=MIM_TURN_MIN_STT_SPEECH_MS=80",
                "Environment=MIM_TURN_FORCE_STT_MAX=900",
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
    active = commands[-2]["stdout"].strip() == "active"
    payload = {
        "packet_type": "mim-voice-sensitivity-and-linger-v1",
        "generated_at": now_iso(),
        "success": active,
        "status": "active" if active else "service_not_active",
        "objective_id": "MIM-VOICE-RELIABILITY-V2",
        "changes": {
            "MIM_VOICE_ACTIVE_SESSION_SECONDS": 12,
            "MIM_TURN_MIN_STT_RMS": 95,
            "MIM_TURN_MIN_STT_MAX": 600,
            "MIM_TURN_MIN_STT_SPEECH_MS": 80,
            "MIM_TURN_FORCE_STT_MAX": 900,
        },
        "reason": "Direct questions were sometimes skipped before STT, while long active-session carryover caused interruptions after unrelated speech.",
        "commands": commands,
        "artifact": str(ARTIFACT.relative_to(ROOT)),
        "next_validation": [
            "Ask: MIM, can you hear me?",
            "Ask: MIM, what are you working on right now?",
            "Speak unrelated phone-style chatter without saying MIM; MIM should observe without speaking.",
        ],
    }
    ARTIFACT.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if active else 1


if __name__ == "__main__":
    raise SystemExit(main())
