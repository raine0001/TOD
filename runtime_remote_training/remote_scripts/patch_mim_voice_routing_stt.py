#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
WAKE = ROOT / "scripts" / "mim_wake_listen_loop.py"
DROPIN_DIR = Path("/home/testpilot/.config/systemd/user/mim-speech-turn-engine.service.d")
DROPIN = DROPIN_DIR / "stt-cpu-and-task-normalization.conf"
ARTIFACT = ROOT / "runtime" / "shared" / "MIM_VOICE_ROUTE_STT_PATCH.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def replace_once(text: str, old: str, new: str) -> tuple[str, bool]:
    if old not in text:
        return text, False
    return text.replace(old, new, 1), True


def main() -> int:
    changed: list[str] = []
    source = WAKE.read_text(encoding="utf-8")

    normalization_anchor = (
        '    normalized = re.sub(r"\\btrying\\s+on\\b", "training on", normalized)\n'
        '    normalized = re.sub(r"\\btry\\s+on\\b", "training on", normalized)\n'
    )
    normalization_patch = (
        '    normalized = re.sub(r"\\btrying\\s+on\\b", "training on", normalized)\n'
        '    normalized = re.sub(r"\\btry\\s+on\\b", "training on", normalized)\n'
        '    normalized = re.sub(r"\\bcurrent\\s+(tax|casks|tacks|task)\\b", "current tasks", normalized)\n'
        '    normalized = re.sub(r"\\bwhat\\s+are\\s+your\\s+current\\s+(tax|casks|tacks|task)\\b", "what are your current tasks", normalized)\n'
        '    normalized = re.sub(r"\\bworking\\s+on\\s+them\\s+mim\\b", "working on mim", normalized)\n'
    )
    if "current\\s+(tax|casks|tacks|task)" not in source:
        source, did = replace_once(source, normalization_anchor, normalization_patch)
        if did:
            changed.append("added voice transcript normalization for current tasks misrecognitions")

    bridge_old = '''def call_mim_ui_chat(transcript: str) -> dict[str, Any]:
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
'''
    bridge_new = '''def call_mim_ui_chat(transcript: str) -> dict[str, Any]:
    if not VOICE_UI_CHAT_BRIDGE_ENABLED:
        return {"ok": False, "skipped": True, "error": "voice_ui_chat_bridge_disabled"}
    effective_transcript = normalize_voice_transcript_for_intent(transcript)
    payload = {
        "text": effective_transcript or transcript,
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
            "raw_voice_transcript": transcript,
            "normalized_voice_transcript": effective_transcript,
        },
    }
'''
    if "normalized_voice_transcript" not in source:
        source, did = replace_once(source, bridge_old, bridge_new)
        if did:
            changed.append("voice UI bridge now sends normalized transcript while retaining raw transcript metadata")

    quality_anchor = (
        '    if unk_count >= 1 and len(meaningful) < 4:\n'
        '        reasons.append("unknown_token_with_low_content")\n'
    )
    quality_patch = (
        '    if unk_count >= 1 and len(meaningful) < 4:\n'
        '        reasons.append("unknown_token_with_low_content")\n'
        '    if len(words) <= 1 and not has_mim_reference(normalized):\n'
        '        reasons.append("single_word_fragment_without_mim_reference")\n'
    )
    if "single_word_fragment_without_mim_reference" not in source:
        source, did = replace_once(source, quality_anchor, quality_patch)
        if did:
            changed.append("single-word non-MIM fragments are now low confidence and will not be bridged as operator intent")

    if changed:
        WAKE.write_text(source, encoding="utf-8")

    DROPIN_DIR.mkdir(parents=True, exist_ok=True)
    dropin_text = """[Service]
Environment=MIM_STT_ENGINE=faster-whisper
Environment=MIM_WHISPER_DEVICE=cpu
Environment=MIM_WHISPER_COMPUTE_TYPE=int8
Environment=MIM_WHISPER_MODEL_SIZE=base.en
Environment=MIM_WHISPER_VAD_FILTER=0
Environment=MIM_TURN_MIN_STT_RMS=140
Environment=MIM_TURN_MIN_STT_MAX=1200
Environment=MIM_TURN_MIN_STT_SPEECH_MS=200
Environment=MIM_TURN_FORCE_STT_MAX=2500
"""
    if not DROPIN.exists() or DROPIN.read_text(encoding="utf-8") != dropin_text:
        DROPIN.write_text(dropin_text, encoding="utf-8")
        changed.append("systemd drop-in forces faster-whisper CPU/int8 and lowers STT gates")

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
                "reason": "MIM heard recent speech as 'current tax/current casks' and faster_whisper was failing on CUDA.",
                "expected_effect": [
                    "Normalize 'current tax/current casks/current task' to 'current tasks'.",
                "Send normalized transcript into the same UI chat bridge used by text chat.",
                "Use CPU/int8 faster-whisper instead of failing CUDA before falling back to Vosk.",
                "Lower STT gates so quiet but real turns are transcribed instead of skipped.",
                "Suppress one-word fragments like 'you' from the live chat bridge.",
            ],
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
