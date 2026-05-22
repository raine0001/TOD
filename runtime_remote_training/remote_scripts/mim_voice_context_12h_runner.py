#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import time
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_VOICE_CONTEXT_12H_BUILD_STATUS.latest.json"
NEXT_OBJECTIVE_PATH = SHARED / "MIM_VOICE_CONTEXT_NEXT_OBJECTIVE.latest.json"
LESSONS_PATH = SHARED / "MIM_VOICE_CONTEXT_12H_LESSONS.latest.json"
SUMMARY_PATH = SHARED / "MIM_VOICE_CONTEXT_12H_OPERATOR_SUMMARY.latest.md"


OBJECTIVE_ID = "MIM-VALUE-ADDED-VOICE-ASSISTANT-12H-BUILD-V1"


CAPABILITY_CHECKS = [
    "voice_context_architecture_defined",
    "value_added_standard_defined",
    "ambient_lab_conversation_active",
    "stt_diagnostic_evidence_recent",
    "turn_state_memory_present",
    "concise_response_policy_present",
    "context_router_present",
    "vad_segmentation_evidence_present",
    "faux_pause_policy_evidence_present",
    "barge_in_evidence_present",
    "background_obligation_tracker_present",
    "natural_tts_persona_evidence_present",
]


NEXT_OBJECTIVES = [
    {
        "objective_id": "MIM-VAD-SPEECH-SEGMENTATION-V1",
        "capability": "vad_segmentation_evidence_present",
        "goal": "Add explicit speech segmentation before STT so MIM waits for complete utterances instead of fixed windows.",
        "success": "Publish MIM_VAD_SPEECH_SEGMENTATION_STATUS.latest.json with start/stop timing, no-speech filtering, and no raw audio retained.",
    },
    {
        "objective_id": "MIM-TURN-STATE-MEMORY-V1",
        "capability": "turn_state_memory_present",
        "goal": "Persist short-term conversation state, topic, referents, and recent turns for voice context.",
        "success": "Publish MIM_VOICE_TURN_STATE.latest.json and prove a follow-up can resolve implied context.",
    },
    {
        "objective_id": "MIM-LAB-CONTEXT-ROUTER-V1",
        "capability": "context_router_present",
        "goal": "Route lab utterances by context and intent, not wake words or one-off keywords.",
        "success": "Publish routed voice turns with intent/action/artifacts and concise responses.",
    },
    {
        "objective_id": "MIM-BARGE-IN-RECOVERY-V1",
        "capability": "barge_in_evidence_present",
        "goal": "Detect operator interruption while MIM is speaking and stop current playback before pivoting.",
        "success": "Publish MIM_BARGE_IN_RECOVERY_STATUS.latest.json with interrupt detection and playback-stop evidence.",
    },
    {
        "objective_id": "MIM-ASYNC-FOLLOW-THROUGH-V1",
        "capability": "background_obligation_tracker_present",
        "goal": "Allow voice-created delayed or conditional obligations and track them until completed or canceled.",
        "success": "Publish MIM_BACKGROUND_OBLIGATION_TRACKER.latest.json with at least one simulated obligation lifecycle.",
    },
    {
        "objective_id": "MIM-NATURAL-TTS-PERSONA-V1",
        "capability": "natural_tts_persona_evidence_present",
        "goal": "Improve MIM's voice quality/persona while preserving concise, useful responses.",
        "success": "Publish voice persona evidence and an audible route test without loops or beeps.",
    },
]


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso(value: object) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


def recent(value: object, seconds: int) -> bool:
    parsed = parse_iso(value)
    if parsed is None:
        return False
    return (datetime.now(timezone.utc) - parsed).total_seconds() <= seconds


def read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def run_command(args: list[str], *, timeout: int = 10) -> dict[str, Any]:
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


def file_status(name: str, *, recent_seconds: int | None = None) -> dict[str, Any]:
    path = SHARED / name
    exists = path.is_file()
    payload = read_json(path) if exists and path.suffix == ".json" else {}
    generated_at = payload.get("generated_at") or payload.get("updated_at")
    return {
        "artifact": f"runtime/shared/{name}",
        "exists": exists,
        "generated_at": generated_at,
        "recent": bool(exists and (recent_seconds is None or recent(generated_at, recent_seconds))),
        "status": payload.get("status"),
        "success": payload.get("success"),
    }


def evaluate() -> dict[str, Any]:
    listener = read_json(SHARED / "MIM_WAKE_LISTENER_STATUS.latest.json")
    standard = read_json(SHARED / "MIM_VALUE_ADDED_VOICE_ASSISTANT_STANDARD.latest.json")
    architecture = read_json(SHARED / "MIM_MINIMUM_VOICE_CONTEXT_ARCHITECTURE.latest.json")
    turn_state = read_json(SHARED / "MIM_VOICE_TURN_STATE.latest.json")
    followup = read_json(SHARED / "MIM_WAKE_FOLLOWUP.latest.json")

    checks = {
        "voice_context_architecture_defined": bool(architecture.get("success")),
        "value_added_standard_defined": bool(standard.get("success")),
        "ambient_lab_conversation_active": bool(listener.get("lab_conversation_mode")),
        "stt_diagnostic_evidence_recent": file_status("MIM_WAKE_DIAGNOSTIC.latest.json", recent_seconds=30 * 60)["recent"],
        "turn_state_memory_present": bool(turn_state.get("success") and turn_state.get("recent_turns")),
        "concise_response_policy_present": standard.get("response_policy_updates", {}).get("default_response_length") == "one_to_three_sentences",
        "context_router_present": bool(followup.get("intent") or listener.get("lab_conversation_intent")),
        "vad_segmentation_evidence_present": bool(read_json(SHARED / "MIM_VAD_SPEECH_SEGMENTATION_STATUS.latest.json").get("success")),
        "faux_pause_policy_evidence_present": bool(read_json(SHARED / "MIM_FAUX_PAUSE_HANDLING_STATUS.latest.json").get("success")),
        "barge_in_evidence_present": bool(read_json(SHARED / "MIM_BARGE_IN_RECOVERY_STATUS.latest.json").get("success")),
        "background_obligation_tracker_present": bool(read_json(SHARED / "MIM_BACKGROUND_OBLIGATION_TRACKER.latest.json").get("success")),
        "natural_tts_persona_evidence_present": bool(read_json(SHARED / "MIM_NATURAL_TTS_PERSONA_STATUS.latest.json").get("success")),
    }
    passed = [key for key, value in checks.items() if value]
    missing = [key for key, value in checks.items() if not value]
    percent = round(100 * len(passed) / len(CAPABILITY_CHECKS), 1)
    return {
        "checks": checks,
        "passed": passed,
        "missing": missing,
        "percent_complete": percent,
        "listener_status": {
            "status": listener.get("status"),
            "audio_device": listener.get("audio_device"),
            "lab_conversation_mode": listener.get("lab_conversation_mode"),
            "last_transcript": listener.get("last_transcript"),
            "lab_conversation_intent": listener.get("lab_conversation_intent"),
        },
        "artifacts": {
            name: file_status(name, recent_seconds=30 * 60)
            for name in [
                "MIM_WAKE_LISTENER_STATUS.latest.json",
                "MIM_WAKE_DIAGNOSTIC.latest.json",
                "MIM_WAKE_FOLLOWUP.latest.json",
                "MIM_VOICE_TURN_STATE.latest.json",
                "MIM_VALUE_ADDED_VOICE_ASSISTANT_STANDARD.latest.json",
                "MIM_MINIMUM_VOICE_CONTEXT_ARCHITECTURE.latest.json",
            ]
        },
    }


def choose_next_objective(missing: list[str]) -> dict[str, Any]:
    for objective in NEXT_OBJECTIVES:
        if objective["capability"] in missing:
            return objective
    return {
        "objective_id": "MIM-VALUE-ADDED-VOICE-ASSISTANT-VALIDATION-V1",
        "capability": "final_validation",
        "goal": "Run a full voice assistant acceptance validation against all standards.",
        "success": "All capability checks pass and no blockers remain.",
    }


def post_objective_to_gateway(objective: dict[str, Any]) -> dict[str, Any]:
    prompt = f"""OBJECTIVE: {objective['objective_id']}

GOAL:
{objective['goal']}

SUCCESS:
{objective['success']}

CONSTRAINTS:
- No raw audio retention.
- Treat tools as replaceable; preserve context behavior.
- Continue without human intervention.
- Do not mark complete from planning alone.
- Publish evidence artifacts in runtime/shared.
"""
    payload = {
        "text": prompt,
        "parsed_intent": "conversation",
        "safety_flags": [],
        "metadata_json": {
            "source": "mim_voice_context_12h_runner",
            "interaction_mode": "autonomous_objective",
            "message_type": "user",
            "conversation_session_id": f"voice-context-12h-{uuid.uuid4()}",
            "route_preference": "conversation_layer",
        },
    }
    request = urllib.request.Request(
        "http://127.0.0.1:18001/gateway/intake/text",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return {"ok": True, "status": getattr(response, "status", None), "payload": json.loads(response.read().decode("utf-8"))}
    except Exception as exc:
        return {"ok": False, "status": None, "error": f"{type(exc).__name__}: {exc}"}


def publish_summary(status: dict[str, Any]) -> None:
    lines = [
        "# MIM Voice Context 12h Build",
        "",
        f"- Updated: {status['generated_at']}",
        f"- Status: {status['status']}",
        f"- Percent complete: {status['percent_complete']}%",
        f"- Current objective: {status['current_objective']['objective_id']}",
        f"- Missing capabilities: {', '.join(status['missing']) if status['missing'] else 'none'}",
        "",
        "This run continues without human intervention until all checks pass or the configured duration ends.",
    ]
    SUMMARY_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--duration-hours", type=float, default=12.0)
    parser.add_argument("--interval-seconds", type=int, default=300)
    parser.add_argument("--post-interval-seconds", type=int, default=1800)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    started = datetime.now(timezone.utc)
    deadline = started.timestamp() + max(1, args.duration_hours * 3600)
    last_post_at = 0.0
    lesson_entries: list[dict[str, Any]] = []

    while True:
        now = datetime.now(timezone.utc)
        evaluation = evaluate()
        next_objective = choose_next_objective(evaluation["missing"])
        should_post = time.time() - last_post_at >= max(60, args.post_interval_seconds)
        dispatch = {"ok": False, "skipped": not should_post}
        if should_post and evaluation["missing"]:
            dispatch = post_objective_to_gateway(next_objective)
            last_post_at = time.time()

        status = {
            "packet_type": "mim-voice-context-12h-build-status-v1",
            "generated_at": now_iso(),
            "objective_id": OBJECTIVE_ID,
            "status": "completed_with_evidence" if not evaluation["missing"] else "running",
            "success": not evaluation["missing"],
            "started_at": started.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "deadline_at": datetime.fromtimestamp(deadline, timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "percent_complete": evaluation["percent_complete"],
            "passed": evaluation["passed"],
            "missing": evaluation["missing"],
            "checks": evaluation["checks"],
            "listener_status": evaluation["listener_status"],
            "current_objective": next_objective,
            "last_dispatch": dispatch,
            "artifacts": evaluation["artifacts"],
            "no_audio_retained": True,
        }
        write_json(STATUS_PATH, status)
        write_json(NEXT_OBJECTIVE_PATH, {"packet_type": "mim-voice-context-next-objective-v1", "generated_at": now_iso(), **next_objective})
        lesson_entries.append(
            {
                "generated_at": now_iso(),
                "missing": evaluation["missing"],
                "objective": next_objective["objective_id"],
                "lesson": "Convert the first missing capability into a concrete objective with evidence, then re-evaluate.",
            }
        )
        write_json(
            LESSONS_PATH,
            {
                "packet_type": "mim-voice-context-12h-lessons-v1",
                "generated_at": now_iso(),
                "objective_id": OBJECTIVE_ID,
                "entries": lesson_entries[-100:],
            },
        )
        publish_summary(status)

        if args.once or status["success"] or time.time() >= deadline:
            if time.time() >= deadline and not status["success"]:
                status["status"] = "blocked_with_evidence"
                status["success"] = False
                status["reason_code"] = "duration_elapsed_before_100_percent"
                write_json(STATUS_PATH, status)
                publish_summary(status)
            return 0
        time.sleep(max(10, args.interval_seconds))


if __name__ == "__main__":
    raise SystemExit(main())
