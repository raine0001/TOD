from pathlib import Path
p = Path('/home/testpilot/mim/scripts/mim_ready_task_dispatcher.py')
s = p.read_text()
if 'def load_json(path: Path, default: dict[str, Any] | None = None)' not in s:
    s = s.replace('def load_json_file(path: Path) -> dict[str, Any]:\n    try:\n        return json.loads(path.read_text(encoding="utf-8"))\n    except Exception:\n        return {}\n', 'def load_json_file(path: Path) -> dict[str, Any]:\n    try:\n        return json.loads(path.read_text(encoding="utf-8"))\n    except Exception:\n        return {}\n\n\ndef load_json(path: Path, default: dict[str, Any] | None = None) -> dict[str, Any]:\n    data = load_json_file(path)\n    if data:\n        return data\n    return dict(default or {})\n')
marker = '\ndef refined_objective_evidence_if_available(key: str, title: str, base: dict[str, Any]) -> dict[str, Any] | None:\n'
insert = r'''

def implementation_result_evidence_if_available(key: str, title: str, base: dict[str, Any]) -> dict[str, Any] | None:
    """Close objective loop when Codex/TOD implementation result artifacts exist."""
    upper_key = str(key or "").upper()
    mappings = {
        "AGENTMIM-FORUM-IMAGE-AUTO-QA-REMEDIATION-V1": {
            "artifact": "AGENTMIM_FORUM_IMAGE_AUTO_QA_IMPLEMENTATION_RESULT.latest.json",
            "summary": "Forum image QA implementation is complete locally: weak generated editorial/MIM Opinion images now fail relevance and quality gates, and the remediation runner exists.",
            "status": "implementation_completed_with_local_validation",
            "reason_code": "codex_result_ingested_database_apply_blocked",
            "next": "Run forum-image-auto-qa-remediate --apply from the deployed AgentMIM environment with database access, then verify remediated post evidence.",
        },
        "AGENTMIM-GRAPHICS-COMM-APP-V1": {
            "artifact": "AGENTMIM_GRAPHICS_ADAPTER_IMPLEMENTATION_RESULT.latest.json",
            "summary": "Marketing and campaign image paths now emit shared graphics metadata. Remaining work is quality-review persistence and retry/refinement parity.",
            "status": "running_with_adapter_bound",
            "reason_code": "shared_graphics_metadata_adapter_bound",
            "next": "Implement marketing/campaign quality-review persistence and retry/refinement workflow using the shared graphics capability helper.",
        },
    }
    config = mappings.get(upper_key)
    if not config:
        return None
    result_path = SHARED / config["artifact"]
    result = load_json(result_path, {})
    if not result:
        return None
    return {
        **base,
        "packet_type": "mim-tod-objective-execution-evidence-v2",
        "status": config["status"],
        "reason_code": config["reason_code"],
        "evidence_artifacts": [f"runtime/shared/{config['artifact']}"],
        "codex_result_artifact": f"runtime/shared/{config['artifact']}",
        "implementation_result": result,
        "operator_facing_summary": config["summary"],
        "next_recovery_action": config["next"],
        "expected_files": result.get("implementation", {}).get("changed_files", []) if isinstance(result.get("implementation"), dict) else result.get("changed_files", []),
        "validation_requirements": result.get("validation", []) if isinstance(result.get("validation"), list) else result.get("tests", []),
        "confidence": result.get("confidence", "high"),
        "source": "mim_ready_task_dispatcher_codex_result_intake",
    }

'''
if 'def implementation_result_evidence_if_available' not in s:
    s = s.replace(marker, insert + marker)
needle = '    refined = refined_objective_evidence_if_available(key, title, base)\n    if refined:\n        return refined\n\n    if upper_key == "AGENTMIM-FORUM-IMAGE-AUTO-QA-REMEDIATION-V1":\n'
replacement = '    implementation_result = implementation_result_evidence_if_available(key, title, base)\n    if implementation_result:\n        return implementation_result\n\n    refined = refined_objective_evidence_if_available(key, title, base)\n    if refined:\n        return refined\n\n    if upper_key == "MIM-STREAMING-STT-MIGRATION-V1":\n        speech = load_json(SHARED / "MIM_SPEECH_TURN_ENGINE_STATUS.latest.json", {})\n        transcript = load_json(SHARED / "MIM_VOICE_TRANSCRIPT_LOG_STATUS.latest.json", {})\n        patch = load_json(SHARED / "MIM_VOICE_ROUTE_STT_PATCH.latest.json", {})\n        if speech or transcript or patch:\n            last = transcript.get("last_entry", {}) if isinstance(transcript.get("last_entry"), dict) else {}\n            empty_transcript = bool(last) and not str(last.get("transcript") or last.get("normalized_transcript") or "").strip()\n            return {\n                **base,\n                "packet_type": "mim-tod-objective-execution-evidence-v2",\n                "status": "running_with_executor_bound" if not empty_transcript else "blocked_with_evidence",\n                "reason_code": "speech_turn_engine_bound" if not empty_transcript else "speech_detected_but_stt_empty",\n                "evidence_artifacts": [\n                    "runtime/shared/MIM_SPEECH_TURN_ENGINE_STATUS.latest.json",\n                    "runtime/shared/MIM_VOICE_TRANSCRIPT_LOG_STATUS.latest.json",\n                    "runtime/shared/MIM_VOICE_ROUTE_STT_PATCH.latest.json",\n                ],\n                "operator_facing_summary": "MIM has a full-time speech turn engine bound and listening, but the latest captured speech produced an empty transcript." if empty_transcript else "MIM has a full-time speech turn engine bound and listening; STT/router evidence is being refreshed.",\n                "next_recovery_action": "Tune STT/VAD against fresh spoken samples and prefer the clean low-noise device that produces non-empty transcripts." if empty_transcript else "Continue validating live spoken turns through the UI-chat-equivalent route.",\n                "expected_files": [\n                    "runtime/shared/MIM_SPEECH_TURN_ENGINE_STATUS.latest.json",\n                    "runtime/shared/MIM_VOICE_TRANSCRIPT_LOG_STATUS.latest.json",\n                ],\n                "validation_requirements": [\n                    "speech turn creates non-empty transcript",\n                    "transcript routes to UI-chat-equivalent response path",\n                    "empty/noise fragments are logged without interrupting Dave",\n                ],\n                "confidence": "high",\n                "source": "mim_ready_task_dispatcher_stt_executor_evidence",\n            }\n\n    if upper_key == "AGENTMIM-FORUM-IMAGE-AUTO-QA-REMEDIATION-V1":\n'
if needle in s:
    s = s.replace(needle, replacement)
else:
    raise SystemExit('needle not found')
p.write_text(s)
print('patched dispatcher result intake/stt/load_json')
