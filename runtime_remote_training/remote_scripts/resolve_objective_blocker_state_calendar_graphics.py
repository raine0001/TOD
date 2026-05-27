#!/usr/bin/env python3
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(name: str, default):
    path = SHARED / name
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def write_json(name: str, payload):
    path = SHARED / name
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    return f"runtime/shared/{name}"


def update_execution(objective_id: str, entry: dict):
    status = read_json("MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json", {})
    objectives = status.setdefault("objectives", {})
    objectives[objective_id] = entry
    status["latest_action"] = entry
    status["generated_at"] = now_iso()
    write_json("MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json", status)

    managed = read_json("MIM_TOD_MANAGED_OBJECTIVES.latest.json", {})
    for obj in managed.get("objectives", []) if isinstance(managed.get("objectives"), list) else []:
        if str(obj.get("objective_id")) == str(objective_id):
            obj["status"] = entry.get("status", obj.get("status"))
            obj["updated_at"] = entry.get("generated_at")
            meta = obj.setdefault("metadata_json", {})
            if isinstance(meta, dict):
                meta["latest_execution"] = {
                    "artifact": entry.get("artifact"),
                    "generated_at": entry.get("generated_at"),
                    "reason_code": entry.get("reason_code"),
                    "status": entry.get("status"),
                }
                meta["next_recovery_action"] = entry.get("next_recovery_action")
    managed["generated_at"] = now_iso()
    write_json("MIM_TOD_MANAGED_OBJECTIVES.latest.json", managed)


def upsert_escalation(objective_id: str, patch: dict):
    center = read_json("MIM_TOD_ESCALATION_CENTER.latest.json", {"escalations": [], "results": []})
    escalations = center.setdefault("escalations", [])
    matched = False
    for esc in escalations:
        if str(esc.get("objective_id")) == objective_id and esc.get("status") == "open":
            esc.update(patch)
            esc["updated_at"] = now_iso()
            matched = True
            break
    if not matched:
        patch.setdefault("escalation_id", f"ESC-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}-{objective_id}")
        patch.setdefault("created_at", now_iso())
        patch.setdefault("objective_id", objective_id)
        patch.setdefault("status", "open")
        escalations.insert(0, patch)
    center["escalation_count"] = len(escalations)
    center["generated_at"] = now_iso()
    write_json("MIM_TOD_ESCALATION_CENTER.latest.json", center)


def main() -> int:
    generated_at = now_iso()

    calendar_live = read_json("MIM_DAVE_CALENDAR_LIVE_VERIFICATION.latest.json", {})
    connector = read_json("MIM_DAVE_PERSONAL_ASSISTANT_CONNECTOR_STATUS.latest.json", {})
    connector.update(
        {
            "packet_type": "mim-dave-personal-assistant-connector-status-v2",
            "generated_at": generated_at,
            "objective_id": "MIM-DAVE-CALENDAR-PHONE-EMAILS-V1",
            "status": "blocked_with_narrow_remaining_bindings",
            "success": False,
            "reason_code": "remaining_email_read_and_mim_wall_phone_bridge_bindings",
            "calendar": {
                "live_write_verified": bool(calendar_live.get("success")),
                "used_refresh_token": bool(calendar_live.get("used_refresh_token")),
                "calendar_id": calendar_live.get("calendar_id") or "primary",
            },
            "email": {
                "smtp_auth_verified": bool((connector.get("email") or {}).get("smtp", {}).get("auth_verified")),
                "read_connector_verified": False,
                "safe_next_step": "Bind existing inbound IMAP/email read connector with summary-only audit artifacts; do not write email bodies or secrets to runtime artifacts.",
            },
            "phone": {
                "zoom_oauth_verified": bool((connector.get("phone") or {}).get("zoom_oauth_verified")),
                "mim_wall_realtime_bridge_verified": False,
                "safe_next_step": "Have MIM_Wall publish call/message screening state to MIM shared state, then verify round trip.",
            },
            "remaining_blockers": [
                "email_read_connector_not_bound_to_MIM_runtime",
                "mim_wall_realtime_phone_bridge_not_verified",
            ],
            "operator_facing_summary": "Calendar access is live. SMTP send auth and Zoom phone OAuth are verified. The remaining work is email-read summaries and the MIM_Wall realtime phone bridge.",
            "next_recovery_action": "Bind email read summary executor first, then MIM_Wall phone bridge; keep send/call actions confirmation-gated.",
            "secret_policy": "Only key presence and endpoint outcomes are reported; no tokens, passwords, message bodies, or personal email content are written here.",
            "evidence_artifacts": [
                "runtime/shared/MIM_DAVE_CALENDAR_LIVE_VERIFICATION.latest.json",
                "runtime/shared/MIM_DAVE_PERSONAL_ASSISTANT_CONNECTOR_STATUS.latest.json",
            ],
        }
    )
    connector_artifact = write_json("MIM_DAVE_PERSONAL_ASSISTANT_CONNECTOR_STATUS.latest.json", connector)
    calendar_evidence = {
        "packet_type": "mim-tod-objective-execution-evidence-v2",
        "generated_at": generated_at,
        "objective_id": "MIM-DAVE-CALENDAR-PHONE-EMAILS-V1",
        "title": "Dave calendar, phone, and email assistant integration",
        "status": "blocked_with_narrow_remaining_bindings",
        "reason_code": "remaining_email_read_and_mim_wall_phone_bridge_bindings",
        "artifact": connector_artifact,
        "attempted_paths": [
            "verified live Google Calendar artifact",
            "verified SMTP send-auth evidence",
            "verified Zoom phone OAuth evidence",
            "inspected remaining email read and MIM_Wall phone bridge state",
        ],
        "canonical_solutions_checked": [
            "MIM_DAVE_CALENDAR_LIVE_VERIFICATION.latest.json",
            "MIM_DAVE_PERSONAL_ASSISTANT_CONNECTOR_STATUS.latest.json",
        ],
        "expected_files": [
            "runtime/shared/MIM_DAVE_EMAIL_READ_SUMMARY_STATUS.latest.json",
            "runtime/shared/MIM_WALL_PHONE_BRIDGE_STATUS.latest.json",
        ],
        "operator_facing_summary": connector["operator_facing_summary"],
        "next_recovery_action": connector["next_recovery_action"],
        "validation_requirements": [
            "email read executor publishes summary-only evidence",
            "MIM_Wall publishes realtime phone bridge status",
            "outbound email/text/call actions remain confirmation-gated",
        ],
    }
    calendar_evidence_artifact = write_json("MIM_TOD_OBJECTIVE_EVIDENCE.MIM-DAVE-CALENDAR-PHONE-EMAILS-V1.latest.json", calendar_evidence)
    update_execution(
        "MIM-DAVE-CALENDAR-PHONE-EMAILS-V1",
        {
            "artifact": calendar_evidence_artifact,
            "generated_at": generated_at,
            "next_recovery_action": calendar_evidence["next_recovery_action"],
            "objective_id": "MIM-DAVE-CALENDAR-PHONE-EMAILS-V1",
            "operator_facing_summary": calendar_evidence["operator_facing_summary"],
            "reason_code": calendar_evidence["reason_code"],
            "status": calendar_evidence["status"],
            "title": calendar_evidence["title"],
        },
    )
    upsert_escalation(
        "MIM-DAVE-CALENDAR-PHONE-EMAILS-V1",
        {
            "problem_class": "remaining_email_read_and_mim_wall_phone_bridge_bindings",
            "current_objective": "Dave calendar, phone, and email assistant integration",
            "requested_action": "Bind email-read summary executor and MIM_Wall realtime phone bridge. Calendar, SMTP auth, and Zoom OAuth are already verified.",
            "expected_files": calendar_evidence["expected_files"],
            "latest_evidence": connector_artifact,
            "target": "TOD",
            "confidence": "high",
        },
    )

    graphics = {
        "packet_type": "agentmim-graphics-capability-status-v1",
        "generated_at": generated_at,
        "objective_id": "AGENTMIM-GRAPHICS-COMM-APP-V1",
        "status": "blocked_with_narrow_parity_gap",
        "success": False,
        "reason_code": "shared_graphics_quality_executor_not_bound_to_marketing",
        "inspected_paths": {
            "forum": [
                "E:/comm_app/routes/routes.py::_generate_forum_post_image",
                "E:/comm_app/routes/routes.py::forum_regenerate_image",
                "E:/comm_app/tests/test_forum_post_quality.py",
            ],
            "marketing": [
                "E:/comm_app/routes/marketing_routes.py::_generate_avatar_image",
                "E:/comm_app/routes/marketing_routes.py::_generate_scene_background",
                "E:/comm_app/routes/admin/campaigns.py::_generate_campaign_image_asset",
                "E:/comm_app/app/static/js/content_automation.js::generateImageFromContext",
            ],
        },
        "capability_summary": {
            "forum_graphics_executor_found": True,
            "forum_quality_retry_metadata_found": True,
            "marketing_image_generation_found": True,
            "campaign_image_generation_found": True,
            "shared_quality_retry_rubric_bound_to_marketing": False,
            "social_size_metadata_bound": False,
        },
        "operator_facing_summary": "AgentMIM graphics code exists on both sides. The real gap is parity: forum has mature quality/retry/metadata handling, while marketing/campaign image generation is still a simpler OpenAI image path.",
        "next_recovery_action": "Create a shared graphics capability adapter that marketing/campaign tools call for prompt metadata, quality rubric, retry/refinement state, and social/forum size targets.",
        "secret_policy": "No provider API keys or generated image prompt secrets are written to this artifact.",
    }
    graphics_artifact = write_json("AGENTMIM_GRAPHICS_CAPABILITY_STATUS.latest.json", graphics)
    graphics_evidence = {
        "packet_type": "mim-tod-objective-execution-evidence-v2",
        "generated_at": generated_at,
        "objective_id": "AGENTMIM-GRAPHICS-COMM-APP-V1",
        "title": "AgentMIM graphics capability parity for forum and marketing tools",
        "status": "blocked_with_narrow_parity_gap",
        "reason_code": "shared_graphics_quality_executor_not_bound_to_marketing",
        "artifact": graphics_artifact,
        "attempted_paths": [
            "located forum graphics executor",
            "located forum retry/review/metadata path",
            "located marketing avatar and scene image generation",
            "located campaign content image generation",
        ],
        "canonical_solutions_checked": [
            "routes/routes.py::_generate_forum_post_image",
            "routes/marketing_routes.py::_generate_avatar_image",
            "routes/admin/campaigns.py::_generate_campaign_image_asset",
            "tests/test_forum_post_quality.py",
            "tests/test_marketing_avatar_tool_app.py",
        ],
        "expected_files": [
            "E:/comm_app/app/services/graphics_capability.py",
            "E:/comm_app/tests/test_graphics_capability_parity.py",
            "runtime/shared/AGENTMIM_GRAPHICS_CAPABILITY_STATUS.latest.json",
        ],
        "operator_facing_summary": graphics["operator_facing_summary"],
        "next_recovery_action": graphics["next_recovery_action"],
        "validation_requirements": [
            "forum path still passes focused smoke tests",
            "marketing/campaign image path emits prompt/source/model/size/artifact metadata",
            "failed or low-quality image path has tracked retry/refinement state",
        ],
    }
    graphics_evidence_artifact = write_json("MIM_TOD_OBJECTIVE_EVIDENCE.AGENTMIM-GRAPHICS-COMM-APP-V1.latest.json", graphics_evidence)
    update_execution(
        "AGENTMIM-GRAPHICS-COMM-APP-V1",
        {
            "artifact": graphics_evidence_artifact,
            "generated_at": generated_at,
            "next_recovery_action": graphics_evidence["next_recovery_action"],
            "objective_id": "AGENTMIM-GRAPHICS-COMM-APP-V1",
            "operator_facing_summary": graphics_evidence["operator_facing_summary"],
            "reason_code": graphics_evidence["reason_code"],
            "status": graphics_evidence["status"],
            "title": graphics_evidence["title"],
        },
    )
    upsert_escalation(
        "AGENTMIM-GRAPHICS-COMM-APP-V1",
        {
            "problem_class": "shared_graphics_quality_executor_not_bound_to_marketing",
            "current_objective": "AgentMIM graphics capability parity for forum and marketing tools",
            "requested_action": graphics["next_recovery_action"],
            "expected_files": graphics_evidence["expected_files"],
            "latest_evidence": graphics_artifact,
            "target": "TOD",
            "confidence": "high",
        },
    )

    implementation_request = {
        "packet_type": "mim-codex-implementation-request-v1",
        "generated_at": generated_at,
        "source": "resolve-objective-blocker-state-calendar-graphics",
        "requests": [
            {
                "objective_id": "MIM-DAVE-CALENDAR-PHONE-EMAILS-V1",
                "problem_class": "remaining_email_read_and_mim_wall_phone_bridge_bindings",
                "requested_action": "Implement summary-only email read executor and MIM_Wall phone bridge status publisher.",
                "expected_files": calendar_evidence["expected_files"],
                "validation_requirements": calendar_evidence["validation_requirements"],
            },
            {
                "objective_id": "AGENTMIM-GRAPHICS-COMM-APP-V1",
                "problem_class": "shared_graphics_quality_executor_not_bound_to_marketing",
                "requested_action": graphics["next_recovery_action"],
                "expected_files": graphics_evidence["expected_files"],
                "validation_requirements": graphics_evidence["validation_requirements"],
            },
        ],
    }
    impl_artifact = write_json("MIM_CODEX_IMPLEMENTATION_REQUEST.calendar_graphics.latest.json", implementation_request)
    write_json("MIM_TOD_BLOCKER_REFINEMENT.calendar_graphics.latest.json", {
        "packet_type": "mim-tod-blocker-refinement-calendar-graphics-v1",
        "generated_at": generated_at,
        "success": True,
        "status": "completed_with_refined_blockers",
        "artifacts": [calendar_evidence_artifact, connector_artifact, graphics_evidence_artifact, graphics_artifact, impl_artifact],
        "operator_facing_summary": "The two blocked objectives are no longer vague. Calendar is live; email read and MIM_Wall bridge remain. Graphics code exists; marketing needs the forum-grade quality/retry adapter.",
    })
    print(json.dumps({"success": True, "status": "completed_with_refined_blockers", "artifacts": [calendar_evidence_artifact, graphics_evidence_artifact, impl_artifact]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
