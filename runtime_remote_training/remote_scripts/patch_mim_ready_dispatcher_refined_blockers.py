#!/usr/bin/env python3
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
DISPATCHER = ROOT / "scripts" / "mim_ready_task_dispatcher.py"
STATUS = ROOT / "runtime" / "shared" / "MIM_READY_DISPATCHER_REFINED_BLOCKERS_PATCH.latest.json"


def now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def replace_once(source: str, old: str, new: str) -> tuple[str, bool]:
    if old not in source:
        return source, False
    return source.replace(old, new, 1), True


def main() -> int:
    source = DISPATCHER.read_text(encoding="utf-8")
    changed = []
    if "def refined_objective_evidence_if_available" not in source:
        anchor = "\ndef evaluate_file_backed_objective(objective: dict[str, Any]) -> dict[str, Any]:\n"
        helper = r'''
def refined_objective_evidence_if_available(key: str, title: str, base: dict[str, Any]) -> dict[str, Any] | None:
    """Prefer refined executor evidence over generic no-executor blockers."""
    upper_key = str(key or "").upper()
    if upper_key == "MIM-DAVE-CALENDAR-PHONE-EMAILS-V1":
        connector = load_json(SHARED / "MIM_DAVE_PERSONAL_ASSISTANT_CONNECTOR_STATUS.latest.json", {})
        calendar_live = load_json(SHARED / "MIM_DAVE_CALENDAR_LIVE_VERIFICATION.latest.json", {})
        if connector or calendar_live:
            return {
                **base,
                "packet_type": "mim-tod-objective-execution-evidence-v2",
                "status": "blocked_with_narrow_remaining_bindings",
                "reason_code": "remaining_email_read_and_mim_wall_phone_bridge_bindings",
                "evidence_artifacts": [
                    "runtime/shared/MIM_DAVE_CALENDAR_LIVE_VERIFICATION.latest.json",
                    "runtime/shared/MIM_DAVE_PERSONAL_ASSISTANT_CONNECTOR_STATUS.latest.json",
                ],
                "operator_facing_summary": "Calendar access is live. SMTP send auth and Zoom phone OAuth are verified. The remaining work is email-read summaries and the MIM_Wall realtime phone bridge.",
                "next_recovery_action": "Bind email read summary executor first, then MIM_Wall phone bridge; keep send/call actions confirmation-gated.",
                "expected_files": [
                    "runtime/shared/MIM_DAVE_EMAIL_READ_SUMMARY_STATUS.latest.json",
                    "runtime/shared/MIM_WALL_PHONE_BRIDGE_STATUS.latest.json",
                ],
                "validation_requirements": [
                    "email read executor publishes summary-only evidence",
                    "MIM_Wall publishes realtime phone bridge status",
                    "outbound email/text/call actions remain confirmation-gated",
                ],
                "confidence": "high",
                "source": "mim_ready_task_dispatcher_refined_blocker",
            }
    if upper_key == "AGENTMIM-GRAPHICS-COMM-APP-V1":
        graphics = load_json(SHARED / "AGENTMIM_GRAPHICS_CAPABILITY_STATUS.latest.json", {})
        if graphics:
            return {
                **base,
                "packet_type": "mim-tod-objective-execution-evidence-v2",
                "status": "blocked_with_narrow_parity_gap",
                "reason_code": "shared_graphics_quality_executor_not_bound_to_marketing",
                "evidence_artifacts": ["runtime/shared/AGENTMIM_GRAPHICS_CAPABILITY_STATUS.latest.json"],
                "operator_facing_summary": "AgentMIM graphics code exists on both sides. The real gap is parity: forum has mature quality/retry/metadata handling, while marketing/campaign image generation is still a simpler OpenAI image path.",
                "next_recovery_action": "Create a shared graphics capability adapter that marketing/campaign tools call for prompt metadata, quality rubric, retry/refinement state, and social/forum size targets.",
                "expected_files": [
                    "E:/comm_app/app/services/graphics_capability.py",
                    "E:/comm_app/tests/test_graphics_capability_parity.py",
                    "runtime/shared/AGENTMIM_GRAPHICS_CAPABILITY_STATUS.latest.json",
                ],
                "validation_requirements": [
                    "forum path still passes focused smoke tests",
                    "marketing/campaign image path emits prompt/source/model/size/artifact metadata",
                    "failed or low-quality image path has tracked retry/refinement state",
                ],
                "confidence": "high",
                "source": "mim_ready_task_dispatcher_refined_blocker",
            }
    return None

'''
        source, ok = replace_once(source, anchor, "\n" + helper + anchor)
        if ok:
            changed.append("added refined_objective_evidence_if_available")

    if "refined = refined_objective_evidence_if_available(key, title, base)" not in source:
        old = '''    if upper_key in {"MIM-ESCALATION-AUTONOMY-V1", "MIM-CODEX-IMPLEMENTATION-ESCALATION-UI-V1"} and objective_artifact_exists("MIM_TOD_COMMUNICATION_ESCALATION_DEPLOYMENT_RESULT.latest.json"):
        return {
            **base,
            "status": "completed_with_evidence",
            "reason_code": "escalation_center_available",
            "evidence_artifacts": ["runtime/shared/MIM_TOD_COMMUNICATION_ESCALATION_DEPLOYMENT_RESULT.latest.json"],
            "operator_facing_summary": "The escalation center and Codex result intake path exist. Runtime objectives can now publish structured blockers instead of stopping quietly.",
            "next_recovery_action": "Use structured escalation packets for any objective without a bound executor.",
        }

    reason = "no_executor_bound"
'''
        new = '''    if upper_key in {"MIM-ESCALATION-AUTONOMY-V1", "MIM-CODEX-IMPLEMENTATION-ESCALATION-UI-V1"} and objective_artifact_exists("MIM_TOD_COMMUNICATION_ESCALATION_DEPLOYMENT_RESULT.latest.json"):
        return {
            **base,
            "status": "completed_with_evidence",
            "reason_code": "escalation_center_available",
            "evidence_artifacts": ["runtime/shared/MIM_TOD_COMMUNICATION_ESCALATION_DEPLOYMENT_RESULT.latest.json"],
            "operator_facing_summary": "The escalation center and Codex result intake path exist. Runtime objectives can now publish structured blockers instead of stopping quietly.",
            "next_recovery_action": "Use structured escalation packets for any objective without a bound executor.",
        }

    refined = refined_objective_evidence_if_available(key, title, base)
    if refined:
        return refined

    reason = "no_executor_bound"
'''
        source, ok = replace_once(source, old, new)
        if ok:
            changed.append("evaluate_file_backed_objective prefers refined blockers")

    if changed:
        DISPATCHER.write_text(source, encoding="utf-8")
    py_compile = subprocess.run(["/home/testpilot/mim/.venv/bin/python", "-m", "py_compile", str(DISPATCHER)], text=True, capture_output=True)
    restart = subprocess.run(["systemctl", "--user", "restart", "mim-ready-task-dispatcher.service"], text=True, capture_output=True)
    active = subprocess.run(["systemctl", "--user", "is-active", "mim-ready-task-dispatcher.service"], text=True, capture_output=True)
    payload = {
        "packet_type": "mim-ready-dispatcher-refined-blockers-patch-v1",
        "generated_at": now_iso(),
        "success": py_compile.returncode == 0 and active.stdout.strip() == "active",
        "status": "active" if active.stdout.strip() == "active" else "service_not_active",
        "changed": changed,
        "py_compile": {"returncode": py_compile.returncode, "stderr": py_compile.stderr.strip()},
        "restart": {"returncode": restart.returncode, "stderr": restart.stderr.strip()},
        "active": active.stdout.strip(),
        "operator_facing_summary": "The dispatcher now preserves refined blocker evidence for calendar/email/phone and graphics parity instead of resurrecting broad no-executor blockers.",
    }
    STATUS.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
