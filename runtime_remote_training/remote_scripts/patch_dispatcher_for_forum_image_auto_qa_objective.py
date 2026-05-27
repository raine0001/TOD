#!/usr/bin/env python3
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
DISPATCHER = ROOT / "scripts" / "mim_ready_task_dispatcher.py"
STATUS = ROOT / "runtime" / "shared" / "MIM_READY_DISPATCHER_FORUM_IMAGE_AUTO_QA_PATCH.latest.json"


def now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main():
    source = DISPATCHER.read_text(encoding="utf-8")
    needle = '''    refined = refined_objective_evidence_if_available(key, title, base)
    if refined:
        return refined

    reason = "no_executor_bound"
'''
    insert = '''    refined = refined_objective_evidence_if_available(key, title, base)
    if refined:
        return refined

    if upper_key == "AGENTMIM-FORUM-IMAGE-AUTO-QA-REMEDIATION-V1":
        return {
            **base,
            "packet_type": "mim-tod-objective-execution-evidence-v2",
            "status": "queued_with_codex_implementation_request",
            "reason_code": "forum_image_auto_qa_executor_requested",
            "evidence_artifacts": [
                "runtime/shared/AGENTMIM_FORUM_IMAGE_AUTO_QA_OBJECTIVE.latest.json",
                "runtime/shared/AGENTMIM_FORUM_IMAGE_PRIOR_WORK_RESEARCH.latest.json",
                "runtime/shared/MIM_CODEX_IMPLEMENTATION_REQUEST.agentmim_forum_image_auto_qa.latest.json",
            ],
            "operator_facing_summary": "Forum image remediation is queued with prior research and a bounded implementation request. The Ubiquiti/UniFi image is treated as a failed-approved example.",
            "next_recovery_action": "Implement the canonical forum image auto-generation sweep and stricter post-relevance QA gate in E:/comm_app/routes/routes.py.",
            "expected_files": [
                "E:/comm_app/routes/routes.py",
                "E:/comm_app/tests/test_forum_post_quality.py",
                "runtime/shared/AGENTMIM_FORUM_IMAGE_QA_REMEDIATION_STATUS.latest.json",
            ],
            "validation_requirements": [
                "missing-image forum post auto-generates",
                "Ubiquiti/UniFi failed-approved example is rejected or regenerated",
                "QA artifact records relevance, composition, family_fit, text cleanliness, provider, prompt, and candidate trace",
            ],
            "confidence": "high",
            "source": "mim_ready_task_dispatcher_forum_image_auto_qa",
        }

    reason = "no_executor_bound"
'''
    changed = False
    if "forum_image_auto_qa_executor_requested" not in source and needle in source:
        source = source.replace(needle, insert, 1)
        DISPATCHER.write_text(source, encoding="utf-8")
        changed = True
    py_compile = subprocess.run(["/home/testpilot/mim/.venv/bin/python", "-m", "py_compile", str(DISPATCHER)], text=True, capture_output=True)
    restart = subprocess.run(["systemctl", "--user", "restart", "mim-ready-task-dispatcher.service"], text=True, capture_output=True)
    active = subprocess.run(["systemctl", "--user", "is-active", "mim-ready-task-dispatcher.service"], text=True, capture_output=True)
    payload = {
        "packet_type": "mim-ready-dispatcher-forum-image-auto-qa-patch-v1",
        "generated_at": now_iso(),
        "success": (changed or "forum_image_auto_qa_executor_requested" in source) and py_compile.returncode == 0 and active.stdout.strip() == "active",
        "status": "active" if active.stdout.strip() == "active" else "service_not_active",
        "changed": changed,
        "py_compile": {"returncode": py_compile.returncode, "stderr": py_compile.stderr.strip()},
        "restart": {"returncode": restart.returncode, "stderr": restart.stderr.strip()},
        "active": active.stdout.strip(),
        "operator_facing_summary": "The dispatcher now recognizes the AgentMIM forum image QA objective and points it at the bounded implementation request instead of a generic no-executor blocker.",
    }
    STATUS.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
