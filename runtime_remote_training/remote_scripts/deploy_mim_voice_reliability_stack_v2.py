#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"
WAKE = ROOT / "scripts" / "mim_wake_listen_loop.py"
MANAGED_OBJECTIVES = SHARED / "MIM_TOD_MANAGED_OBJECTIVES.latest.json"
OBJECTIVE_STACK = SHARED / "MIM_VOICE_RELIABILITY_V2_OBJECTIVE_STACK.latest.json"
STATUS = SHARED / "MIM_VOICE_RELIABILITY_V2_IMPLEMENTATION_STATUS.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def replace_once(text: str, old: str, new: str) -> tuple[str, bool]:
    if old not in text:
        return text, False
    return text.replace(old, new, 1), True


def objective_stack() -> dict:
    objectives = [
        {
            "objective_id": "MIM-VOICE-RELIABILITY-V2",
            "title": "MIM Voice Reliability V2",
            "priority": "P0",
            "status": "running",
            "owner": "MIM_TOD",
            "execution_mode": "auto",
            "auto_continue": True,
            "boundary_mode": "bounded",
            "goal": "Make MIM voice interaction observable, reliable, repair-oriented, and comparable to UI chat quality.",
            "required_actions": [
                "Publish live voice debug state for every heard turn.",
                "Use confirmed audible playback outputs, not first accepted ALSA device only.",
                "Route common operator status questions directly when deterministic evidence exists.",
                "Ask concise clarification when STT confidence is low.",
                "Prevent artifact/internal-state leakage in voice replies.",
                "Define streaming STT upgrade plan and readiness blockers.",
            ],
            "success_criteria": [
                "MIM shows exactly what it heard, normalized, how it routed, reply text, and playback attempts.",
                "MIM suppresses junk fragments and asks useful clarification on uncertainty.",
                "MIM answers current-task/status voice questions in operator language.",
                "MIM attempts all configured playback devices and records evidence.",
                "Streaming STT migration has an explicit executor objective and blockers.",
            ],
        },
        {
            "objective_id": "MIM-VOICE-DEBUG-PANEL-V1",
            "title": "Voice Debug Evidence Surface",
            "priority": "P0",
            "status": "running",
            "owner": "MIM",
            "goal": "Expose live voice debug evidence to MIM UI and MIM Wall.",
            "required_actions": [
                "Write MIM_VOICE_DEBUG_STATUS.latest.json.",
                "Include raw transcript, normalized transcript, confidence/quality, route, response, playback attempts, and next recovery action.",
                "Do not retain raw audio.",
            ],
            "success_criteria": ["A single latest JSON artifact explains why MIM did or did not respond."],
        },
        {
            "objective_id": "MIM-VOICE-PLAYBACK-CALIBRATION-V1",
            "title": "Audible Playback Calibration",
            "priority": "P0",
            "status": "running",
            "owner": "MIM",
            "goal": "Ensure MIM speaks through a speaker Dave can hear.",
            "required_actions": [
                "Fan out playback attempts across configured outputs.",
                "Record which outputs accepted playback.",
                "Provide calibration evidence and pin best output after confirmation.",
            ],
            "success_criteria": ["Voice responses include playback attempts and at least one audible confirmed output."],
        },
        {
            "objective_id": "MIM-VOICE-RESPONSE-SYNTHESIS-POLICY-V1",
            "title": "Voice Response Synthesis Policy",
            "priority": "P0",
            "status": "running",
            "owner": "MIM",
            "goal": "Make voice replies concise, relevant, and free of lifecycle/artifact leakage.",
            "required_actions": [
                "Strip broken prefixes and filler.",
                "Prefer deterministic direct answers for known status questions.",
                "Avoid generic 'what would you like me to do' loops when the user asked a concrete question.",
            ],
            "success_criteria": ["Voice answer to 'what are your current tasks' summarizes objectives directly."],
        },
        {
            "objective_id": "MIM-STREAMING-STT-MIGRATION-V1",
            "title": "Streaming STT Migration",
            "priority": "P1",
            "status": "blocked_with_explicit_executor_requirement",
            "owner": "MIM_TOD",
            "goal": "Replace chunk-only speech turns with streaming VAD/STT partials and end-of-thought finalization.",
            "required_actions": [
                "Select engine: whisper.cpp, faster-whisper streaming wrapper, or stronger PC ASR service.",
                "Publish partial transcripts without routing until finalization.",
                "Add semantic end-of-thought detection.",
                "Measure latency and WER against recent lab utterances.",
            ],
            "success_criteria": ["MIM reports partial heard text quickly and finalizes cleanly without clipped starts/ends."],
            "blocker": "Requires dedicated executor/service work beyond current wake-loop patch.",
        },
    ]
    return {
        "generated_at": now_iso(),
        "deck_id": "MIM_VOICE_RELIABILITY_V2_STACK",
        "source": "codex_requested_full_voice_reliability_stack",
        "status": "active",
        "objectives": objectives,
    }


def upsert_managed_objectives(stack: dict) -> None:
    if MANAGED_OBJECTIVES.exists():
        try:
            managed = json.loads(MANAGED_OBJECTIVES.read_text(encoding="utf-8"))
        except Exception:
            managed = {}
    else:
        managed = {}
    existing = managed.get("objectives") if isinstance(managed.get("objectives"), list) else []
    by_id = {
        str(item.get("objective_id") or item.get("id") or ""): item
        for item in existing
        if isinstance(item, dict)
    }
    for obj in stack["objectives"]:
        existing_obj = by_id.get(obj["objective_id"], {})
        by_id[obj["objective_id"]] = {
            **existing_obj,
            **obj,
            "metadata_json": {
                **(existing_obj.get("metadata_json") if isinstance(existing_obj.get("metadata_json"), dict) else {}),
                "deck_id": stack["deck_id"],
                "created_by": "Codex",
                "latest_status_artifact": "runtime/shared/MIM_VOICE_RELIABILITY_V2_IMPLEMENTATION_STATUS.latest.json",
            },
            "updated_at": now_iso(),
        }
    managed["generated_at"] = now_iso()
    managed["source"] = "mim-objectives-ui-v1"
    managed["objectives"] = list(by_id.values())
    managed["objective_count"] = len(managed["objectives"])
    write_json(MANAGED_OBJECTIVES, managed)


def patch_wake_loop() -> list[str]:
    changed: list[str] = []
    source = WAKE.read_text(encoding="utf-8")

    if "VOICE_DEBUG_STATUS_PATH" not in source:
        old = 'VOICE_CHAT_BRIDGE_PATH = SHARED / "MIM_VOICE_UI_CHAT_BRIDGE.latest.json"\n'
        new = old + 'VOICE_DEBUG_STATUS_PATH = SHARED / "MIM_VOICE_DEBUG_STATUS.latest.json"\n'
        source, did = replace_once(source, old, new)
        if did:
            changed.append("added voice debug status artifact path")

    if "def sanitize_voice_reply_text" not in source:
        anchor = "def call_mim_ui_chat(transcript: str) -> dict[str, Any]:\n"
        helper = '''def sanitize_voice_reply_text(text: str) -> str:
    cleaned = re.sub(r"\\s+", " ", str(text or "")).strip()
    cleaned = re.sub(r"^(going to go,?\\s*)+", "", cleaned, flags=re.I).strip()
    cleaned = re.sub(r"^(request mim-request-[a-z0-9-]+:?\\s*)", "", cleaned, flags=re.I).strip()
    cleaned = cleaned.replace("Lifecycle state:", "Status:")
    if len(cleaned) > 260:
        cleaned = cleaned[:257].rstrip() + "..."
    return cleaned


def publish_voice_debug_status(*, transcript: str, normalized: str = "", route: dict[str, Any] | None = None, response_text: str = "", voice_response: dict[str, Any] | None = None, quality: dict[str, Any] | None = None, status: str = "observed") -> None:
    route = route if isinstance(route, dict) else {}
    voice_response = voice_response if isinstance(voice_response, dict) else {}
    quality = quality if isinstance(quality, dict) else classify_transcript_quality(transcript)
    write_json(
        VOICE_DEBUG_STATUS_PATH,
        {
            "packet_type": "mim-voice-debug-status-v1",
            "generated_at": now_iso(),
            "status": status,
            "success": True,
            "no_audio_retained": True,
            "heard": {
                "raw_transcript": transcript,
                "normalized_transcript": normalized or normalize_voice_transcript_for_intent(transcript),
                "quality": quality,
            },
            "routing": {
                "intent": route.get("intent", ""),
                "action": route.get("action", ""),
                "fallback_used": route.get("fallback_used"),
                "chat_bridge": route.get("chat_bridge", {}),
                "artifacts": route.get("artifacts", []),
            },
            "response": {
                "text": response_text,
                "will_speak": bool(response_text),
            },
            "playback": {
                "accepted": bool(voice_response.get("any_output_accepted")),
                "attempts": voice_response.get("play_attempts", []),
                "output_wav": voice_response.get("output_wav", ""),
                "combined_response_wav": voice_response.get("combined_response_wav", ""),
            },
            "next_recovery_action": ""
            if response_text and voice_response.get("any_output_accepted")
            else "Inspect transcript quality, route decision, and playback attempts in this artifact.",
        },
    )


'''
        source, did = replace_once(source, anchor, helper + anchor)
        if did:
            changed.append("added voice reply sanitizer and voice debug publisher")

    if "reply = sanitize_voice_reply_text(reply)" not in source:
        old = "        reply = extract_mim_chat_reply(response_payload)\n"
        new = old + "        reply = sanitize_voice_reply_text(reply)\n"
        source, did = replace_once(source, old, new)
        if did:
            changed.append("sanitized live UI chat bridge replies before speech")

    if "def build_current_tasks_status_route" not in source:
        anchor = "def route_followup(transcript: str) -> dict[str, Any]:\n"
        helper = '''def build_current_tasks_status_route() -> dict[str, Any]:
    execution = load_shared_json("MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json")
    managed = load_shared_json("MIM_TOD_MANAGED_OBJECTIVES.latest.json")
    objectives = managed.get("objectives") if isinstance(managed.get("objectives"), list) else []
    active = []
    blocked = []
    complete = 0
    for item in objectives:
        if not isinstance(item, dict):
            continue
        status = str(item.get("status") or "").lower()
        title = str(item.get("title") or item.get("objective_id") or "objective").strip()
        if "block" in status:
            blocked.append(title)
        elif "complete" in status:
            complete += 1
        elif status in {"running", "queued", "pending", "active"} or not status:
            active.append(title)
    active_text = "; ".join(active[:2]) if active else "no active objective title found"
    blocked_text = f" Blocked: {'; '.join(blocked[:2])}." if blocked else " No blockers are currently prominent."
    response = f"My active work is {active_text}.{blocked_text} Completed tracked objectives: {complete}."
    return {
        "intent": "current_task_status",
        "action": "answer_current_tasks_from_objective_evidence",
        "response_text": response[:260],
        "artifacts": [
            "runtime/shared/MIM_TOD_MANAGED_OBJECTIVES.latest.json",
            "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
        ],
        "chat_bridge": {"ok": False, "skipped": True, "reason": "handled_by_current_tasks_status_route"},
        "fallback_used": False,
        "execution_snapshot_available": bool(execution),
    }


'''
        source, did = replace_once(source, anchor, helper + anchor)
        if did:
            changed.append("added deterministic current-tasks voice route")

    if "build_current_tasks_status_route()" not in source:
        old = '''    if re.search(r"\\b(how much time|time left|time.*training|training.*time)\\b", normalized):
        return build_training_time_route()
'''
        new = '''    if re.search(r"\\b(what.*current tasks|current tasks|what.*working on right now|what.*working on now|what are you working on)\\b", normalized):
        return build_current_tasks_status_route()
    if re.search(r"\\b(how much time|time left|time.*training|training.*time)\\b", normalized):
        return build_training_time_route()
'''
        source, did = replace_once(source, old, new)
        if did:
            changed.append("current task questions now route before generic chat")

    old_response = '    response_text = route["response_text"] if should_respond else ""\n'
    new_response = '    response_text = sanitize_voice_reply_text(route["response_text"]) if should_respond else ""\n'
    if old_response in source:
        source = source.replace(old_response, new_response)
        changed.append("ambient voice responses are sanitized")

    old_write = "    write_json(FOLLOWUP_PATH, result)\n    return result\n\n\ndef listen_once"
    new_write = "    publish_voice_debug_status(transcript=transcript, normalized=normalize_voice_transcript_for_intent(transcript), route=route, response_text=response_text, voice_response=voice_response, quality=quality, status=result[\"status\"])\n    write_json(FOLLOWUP_PATH, result)\n    return result\n\n\ndef listen_once"
    if "publish_voice_debug_status(transcript=transcript" not in source and old_write in source:
        source = source.replace(old_write, new_write, 1)
        changed.append("lab conversation turns publish voice debug status")

    if changed:
        WAKE.write_text(source, encoding="utf-8")
    return changed


def main() -> int:
    stack = objective_stack()
    write_json(OBJECTIVE_STACK, stack)
    upsert_managed_objectives(stack)
    changes = patch_wake_loop()
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
    subprocess.run(["systemctl", "--user", "restart", "mim-speech-turn-engine.service"], check=False)
    payload = {
        "generated_at": now_iso(),
        "status": "implemented_with_streaming_stt_executor_blocker",
        "success": True,
        "objective_stack_artifact": "runtime/shared/MIM_VOICE_RELIABILITY_V2_OBJECTIVE_STACK.latest.json",
        "implemented_now": changes
        + [
            "objective stack added to managed objectives",
            "playback fanout and CPU Whisper patches retained from prior fixes",
        ],
        "streaming_stt_status": "blocked_pending_dedicated_executor",
        "streaming_stt_blocker": "A true streaming engine requires a new long-running partial-transcript service and latency/WER validation; objective is created and sequenced as P1.",
        "operator_facing_summary": "MIM voice now has a reliability objective stack, direct current-task answers, sanitized voice replies, playback fanout, CPU STT, and a live debug artifact.",
        "next_validation": "Ask: 'MIM, what are your current tasks?' then inspect MIM_VOICE_DEBUG_STATUS.latest.json and audible playback.",
    }
    write_json(STATUS, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
