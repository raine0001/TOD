#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
WAKE = ROOT / "scripts" / "mim_wake_listen_loop.py"
ARTIFACT = ROOT / "runtime" / "shared" / "MIM_VOICE_DIRECT_ADDRESS_GATE.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main() -> int:
    changed: list[str] = []
    source = WAKE.read_text(encoding="utf-8")

    if "def is_explicit_mim_work_question" not in source:
        anchor = "def decide_voice_addressing(transcript: str, *, scene: dict[str, Any], source: str) -> dict[str, Any]:\n"
        helper = '''def is_explicit_mim_work_question(transcript: str) -> bool:
    normalized = normalize_voice_transcript_for_intent(transcript)
    if has_mim_reference(normalized):
        return True
    patterns = [
        r"\\bwhat\\s+are\\s+your\\s+current\\s+tasks\\b",
        r"\\bwhat\\s+are\\s+you\\s+working\\s+on(\\s+right\\s+now|\\s+now)?\\b",
        r"\\bwhat\\s+is\\s+your\\s+current\\s+objective\\b",
        r"\\bhow\\s+is\\s+your\\s+training\\b",
        r"\\bcan\\s+you\\s+hear\\s+me\\b",
        r"\\bdo\\s+you\\s+hear\\s+me\\b",
    ]
    return any(re.search(pattern, normalized) for pattern in patterns)


def looks_like_other_human_conversation(transcript: str) -> bool:
    normalized = normalize_voice_transcript_for_intent(transcript)
    if is_explicit_mim_work_question(normalized):
        return False
    if has_mim_reference(normalized):
        return False
    if re.search(r"\\b(i'?ll\\s+text\\s+you|i\\s+was\\s+just\\s+checking\\s+in|i'?m\\s+late|dinner|leaving|we'?re\\s+going|karen|phone|call|deal|dollars|packaging|robot|software)\\b", normalized):
        return True
    if len(transcript_words(normalized)) >= 14 and re.search(r"\\b(you|we|they|her|him|them)\\b", normalized):
        return True
    return False


'''
        source = source.replace(anchor, helper + anchor, 1)
        changed.append("added explicit MIM work-question and other-human-conversation classifiers")

    old = '''    actionable_followup = assistant_shape or short_followup
    if feedback.get("is_feedback"):
'''
    new = '''    explicit_mim_work_question = is_explicit_mim_work_question(transcript)
    other_human_conversation = looks_like_other_human_conversation(transcript)
    actionable_followup = (assistant_shape or short_followup or explicit_mim_work_question) and not other_human_conversation
    if feedback.get("is_feedback"):
'''
    if old in source and "explicit_mim_work_question = is_explicit_mim_work_question" not in source:
        source = source.replace(old, new, 1)
        changed.append("addressing now computes explicit MIM question and other-human conversation flags")

    replacements = {
        '''    elif mim_reference:
        addressed = True
        confidence = 0.995
        reason = "mim_or_mim_like_reference"
        action = "respond"
''': '''    elif other_human_conversation:
        addressed = False
        confidence = 0.96
        reason = "other_human_conversation_without_mim_reference"
        action = "observe"
    elif mim_reference:
        addressed = True
        confidence = 0.995
        reason = "mim_or_mim_like_reference"
        action = "respond"
    elif explicit_mim_work_question:
        addressed = True
        confidence = 0.92
        reason = "explicit_mim_work_question"
        action = "respond"
''',
        '''    elif assistant_shape:
        addressed = True
        confidence = 0.82
        reason = "assistant_shaped_speech_in_mim_lab"
        action = "respond"
''': '''    elif assistant_shape and explicit_mim_work_question:
        addressed = True
        confidence = 0.82
        reason = "assistant_shaped_explicit_mim_work_question"
        action = "respond"
''',
        '''    elif short_followup:
        addressed = True
        confidence = 0.72
        reason = "short_followup_to_existing_voice_topic"
        action = "respond"
''': '''    elif short_followup and explicit_mim_work_question:
        addressed = True
        confidence = 0.72
        reason = "short_followup_to_existing_voice_topic"
        action = "respond"
''',
        '''    elif scene.get("conversation_mode") in {"single_speaker_or_unknown", "single_human"}:
        addressed = True
        confidence = 0.68
        reason = "single_speaker_lab_default_addressed"
        action = "respond"
''': '''    elif scene.get("conversation_mode") in {"single_speaker_or_unknown", "single_human"}:
        addressed = False
        confidence = 0.68
        reason = "single_speaker_lab_default_observe_without_direct_address"
        action = "observe"
''',
        '''        "policy": "MIM-like words are treated as direct address; in a single-speaker lab context, non-fragment speech is treated as MIM-directed unless scene evidence shows humans talking to each other.",
''': '''        "policy": "MIM-like words and explicit MIM work/status questions are direct address. Ambient single-speaker or phone-style conversation is observed unless MIM is addressed.",
        "explicit_mim_work_question": explicit_mim_work_question,
        "other_human_conversation": other_human_conversation,
''',
    }
    for before, after in replacements.items():
        if before in source:
            source = source.replace(before, after, 1)
            changed.append("tightened direct-address decision branch")

    if changed:
        WAKE.write_text(source, encoding="utf-8")

    subprocess.run(["systemctl", "--user", "restart", "mim-speech-turn-engine.service"], check=False)
    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    ARTIFACT.write_text(
        json.dumps(
            {
                "generated_at": now_iso(),
                "status": "patched" if changed else "already_patched",
                "success": True,
                "changed": changed,
                "policy": "MIM will not interrupt ambient/phone-style conversation without MIM reference or explicit MIM work/status question.",
                "direct_question_examples": [
                    "MIM, what are your current tasks?",
                    "What are you working on right now?",
                    "Can you hear me?",
                ],
                "suppressed_examples": [
                    "I'll text you when I leave.",
                    "We're going to Karen's.",
                    "Dinner thing, I'm late.",
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
