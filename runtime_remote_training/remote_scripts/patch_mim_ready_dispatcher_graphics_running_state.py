#!/usr/bin/env python3
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
DISPATCHER = ROOT / "scripts" / "mim_ready_task_dispatcher.py"
STATUS = ROOT / "runtime" / "shared" / "MIM_READY_DISPATCHER_GRAPHICS_RUNNING_STATE_PATCH.latest.json"


def now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main():
    source = DISPATCHER.read_text(encoding="utf-8")
    old = '''    if upper_key == "AGENTMIM-GRAPHICS-COMM-APP-V1":
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
'''
    new = '''    if upper_key == "AGENTMIM-GRAPHICS-COMM-APP-V1":
        graphics = load_json(SHARED / "AGENTMIM_GRAPHICS_CAPABILITY_STATUS.latest.json", {})
        if graphics:
            graphics_status = str(graphics.get("status") or "").strip() or "blocked_with_narrow_parity_gap"
            graphics_reason = str(graphics.get("reason_code") or "").strip() or "shared_graphics_quality_executor_not_bound_to_marketing"
            running = graphics_status == "running_with_adapter_bound" or bool(graphics.get("shared_metadata_adapter_bound_to_marketing"))
            return {
                **base,
                "packet_type": "mim-tod-objective-execution-evidence-v2",
                "status": "running_with_adapter_bound" if running else "blocked_with_narrow_parity_gap",
                "reason_code": "shared_graphics_metadata_adapter_bound" if running else graphics_reason,
                "evidence_artifacts": [
                    "runtime/shared/AGENTMIM_GRAPHICS_CAPABILITY_STATUS.latest.json",
                    "runtime/shared/AGENTMIM_GRAPHICS_ADAPTER_IMPLEMENTATION_RESULT.latest.json",
                ],
                "operator_facing_summary": str(graphics.get("operator_facing_summary") or "AgentMIM graphics code exists on both sides. Marketing now needs the remaining quality/retry parity work."),
                "next_recovery_action": str(graphics.get("next_recovery_action") or "Implement marketing/campaign quality-review persistence and retry/refinement workflow using the shared graphics capability helper."),
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
'''
    changed = old in source
    if changed:
        source = source.replace(old, new, 1)
        DISPATCHER.write_text(source, encoding="utf-8")
    py_compile = subprocess.run(["/home/testpilot/mim/.venv/bin/python", "-m", "py_compile", str(DISPATCHER)], text=True, capture_output=True)
    restart = subprocess.run(["systemctl", "--user", "restart", "mim-ready-task-dispatcher.service"], text=True, capture_output=True)
    active = subprocess.run(["systemctl", "--user", "is-active", "mim-ready-task-dispatcher.service"], text=True, capture_output=True)
    payload = {
        "packet_type": "mim-ready-dispatcher-graphics-running-state-patch-v1",
        "generated_at": now_iso(),
        "success": changed and py_compile.returncode == 0 and active.stdout.strip() == "active",
        "status": "active" if active.stdout.strip() == "active" else "service_not_active",
        "changed": changed,
        "py_compile": {"returncode": py_compile.returncode, "stderr": py_compile.stderr.strip()},
        "restart": {"returncode": restart.returncode, "stderr": restart.stderr.strip()},
        "active": active.stdout.strip(),
    }
    STATUS.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
