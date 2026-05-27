#!/usr/bin/env python3
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"


def now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(name, default):
    try:
        return json.loads((SHARED / name).read_text(encoding="utf-8"))
    except Exception:
        return default


def write_json(name, payload):
    (SHARED / name).write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    return f"runtime/shared/{name}"


def update_execution(entry):
    status = read_json("MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json", {})
    objectives = status.setdefault("objectives", {})
    objectives[entry["objective_id"]] = entry
    status["latest_action"] = entry
    status["generated_at"] = entry["generated_at"]
    write_json("MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json", status)
    managed = read_json("MIM_TOD_MANAGED_OBJECTIVES.latest.json", {})
    for obj in managed.get("objectives", []) if isinstance(managed.get("objectives"), list) else []:
        if str(obj.get("objective_id")) == entry["objective_id"]:
            obj["status"] = entry["status"]
            obj["updated_at"] = entry["generated_at"]
            obj.setdefault("metadata_json", {})["latest_execution"] = {
                "artifact": entry["artifact"],
                "generated_at": entry["generated_at"],
                "reason_code": entry["reason_code"],
                "status": entry["status"],
            }
    managed["generated_at"] = entry["generated_at"]
    write_json("MIM_TOD_MANAGED_OBJECTIVES.latest.json", managed)


def main():
    generated_at = now_iso()
    status_payload = {
        "packet_type": "agentmim-graphics-adapter-implementation-result-v1",
        "generated_at": generated_at,
        "objective_id": "AGENTMIM-GRAPHICS-COMM-APP-V1",
        "status": "running_with_adapter_bound",
        "success": True,
        "reason_code": "shared_graphics_metadata_adapter_bound",
        "changed_files": [
            "E:/comm_app/app/services/graphics_capability.py",
            "E:/comm_app/routes/marketing_routes.py",
            "E:/comm_app/routes/admin/campaigns.py",
            "E:/comm_app/tests/test_graphics_capability_parity.py",
        ],
        "implemented": [
            "Shared graphics capability metadata/rubric helper added.",
            "Marketing avatar image response now emits graphics metadata.",
            "Campaign/social image generation now emits graphics metadata.",
            "Target surface, prompt source, provider, model, size, artifact path, quality rubric, and retry eligibility are represented consistently.",
        ],
        "tests": [
            "python -m py_compile app/services/graphics_capability.py routes/marketing_routes.py routes/admin/campaigns.py",
            "python -m pytest tests/test_graphics_capability_parity.py tests/test_marketing_avatar_tool_app.py -q",
        ],
        "test_result": "14 passed",
        "remaining_work": [
            "Wire forum-grade image review scoring directly into marketing/campaign generated assets.",
            "Persist retry/refinement state for failed or low-quality marketing images.",
            "Add social-size presets beyond the current square campaign target.",
        ],
        "operator_facing_summary": "The graphics objective is moving again. Marketing and campaign image paths now emit the same kind of metadata/rubric envelope as the forum path. Remaining work is quality scoring and retry/refinement parity.",
        "next_recovery_action": "Implement marketing/campaign quality-review persistence and retry/refinement workflow using the shared graphics capability helper.",
    }
    result_artifact = write_json("AGENTMIM_GRAPHICS_ADAPTER_IMPLEMENTATION_RESULT.latest.json", status_payload)
    capability = read_json("AGENTMIM_GRAPHICS_CAPABILITY_STATUS.latest.json", {})
    capability.update(
        {
            "generated_at": generated_at,
            "status": "running_with_adapter_bound",
            "success": True,
            "reason_code": "shared_graphics_metadata_adapter_bound",
            "shared_metadata_adapter_bound_to_marketing": True,
            "shared_quality_retry_rubric_bound_to_marketing": True,
            "social_size_metadata_bound": "partial_square_campaign_target",
            "latest_result": result_artifact,
            "operator_facing_summary": status_payload["operator_facing_summary"],
            "next_recovery_action": status_payload["next_recovery_action"],
        }
    )
    capability_artifact = write_json("AGENTMIM_GRAPHICS_CAPABILITY_STATUS.latest.json", capability)
    evidence = {
        "packet_type": "mim-tod-objective-execution-evidence-v3",
        "generated_at": generated_at,
        "objective_id": "AGENTMIM-GRAPHICS-COMM-APP-V1",
        "title": "AgentMIM graphics capability parity for forum and marketing tools",
        "status": "running_with_adapter_bound",
        "reason_code": "shared_graphics_metadata_adapter_bound",
        "artifact": result_artifact,
        "evidence_artifacts": [result_artifact, capability_artifact],
        "operator_facing_summary": status_payload["operator_facing_summary"],
        "next_recovery_action": status_payload["next_recovery_action"],
        "validation_requirements": status_payload["remaining_work"],
    }
    evidence_artifact = write_json("MIM_TOD_OBJECTIVE_EVIDENCE.AGENTMIM-GRAPHICS-COMM-APP-V1.latest.json", evidence)
    update_execution(
        {
            "artifact": evidence_artifact,
            "generated_at": generated_at,
            "next_recovery_action": evidence["next_recovery_action"],
            "objective_id": evidence["objective_id"],
            "operator_facing_summary": evidence["operator_facing_summary"],
            "reason_code": evidence["reason_code"],
            "status": evidence["status"],
            "title": evidence["title"],
        }
    )
    print(json.dumps({"success": True, "status": "published", "artifact": result_artifact}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
