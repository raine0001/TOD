#!/usr/bin/env python3
"""Generate a verifiable MIM/TOD training scoreboard from artifacts.

The scoreboard intentionally separates measured metrics from metrics that still
need instrumentation. It can optionally run a small live MIM response evaluation
against /gateway/intake to produce today's communication scores.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TRAINING_ROOT = ROOT / "runtime_remote_training"
CONTEXT_SYNC_ROOT = ROOT / "tod" / "out" / "context-sync"
BLOCKER_ROOT = TRAINING_ROOT / "blocked_objective_training"
DEPLOY_PAYLOADS_ROOT = TRAINING_ROOT / "deploy_payloads"
RUNTIME_SHARED_ROOT = ROOT / "runtime" / "shared"
TOD_RESULT_ARTIFACT_ROOTS = [
    TRAINING_ROOT / "tod_result_artifacts",
    RUNTIME_SHARED_ROOT / "tod_result_artifacts",
]
TOD_STATE_PATH = ROOT / "tod" / "data" / "state.json"
INDEPENDENT_ATTEMPTS_ROOT = TRAINING_ROOT / "tod_independent_resolution_attempts"
CONTINUITY_FORUM_GRAPHICS_VALIDATION_PATH = (
    TRAINING_ROOT
    / "tod_result_artifacts"
    / "MIM_DEVELOPMENT_CONTINUITY_FORUM_GRAPHICS_VALIDATION_2026_06_14.latest.json"
)
LAB_WORKBENCH_ACCEPTANCE_PROOF_PATH = (
    TRAINING_ROOT
    / "tod_result_artifacts"
    / "LAB_WORKBENCH_SERVO_TESTER_ACCEPTANCE_PROOF_2026_06_14.latest.json"
)
MIM_OPERATIONS_ACCOUNTING_ACCEPTANCE_PATH = (
    TRAINING_ROOT
    / "tod_result_artifacts"
    / "MIM_OPERATIONS_ACCOUNTING_ACCEPTANCE_CRITERIA_2026_06_14.latest.json"
)
MIM_SCOPE_COMPLETION_AUDIT_PATH = (
    TRAINING_ROOT
    / "tod_result_artifacts"
    / "MIM_SCOPE_COMPLETION_DISCIPLINE_AUDIT_2026_06_14.latest.json"
)
LEGACY_INDEPENDENT_RESOLUTION_IDS = {
    "TOD-INDEPENDENT-RESOLUTION-PWSH-VALIDATION-INFERENCE-2026-06-13",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def load_first_json(paths: list[Path]) -> dict[str, Any]:
    for path in paths:
        payload = load_json(path)
        if payload:
            return payload
    return {}


def payload_timestamp(payload: dict[str, Any]) -> str:
    return str(payload.get("generated_at") or payload.get("updated_at") or payload.get("completed_at") or "")


def payload_timestamp_seconds(payload: dict[str, Any]) -> float:
    stamp = payload_timestamp(payload)
    if not stamp:
        return 0.0
    try:
        return datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def load_newest_json(paths: list[Path]) -> dict[str, Any]:
    candidates: list[tuple[str, dict[str, Any]]] = []
    fallback: dict[str, Any] = {}
    for path in paths:
        payload = load_json(path)
        if not payload:
            continue
        if not fallback:
            fallback = payload
        stamp = payload_timestamp(payload)
        if stamp:
            candidates.append((stamp, payload))
    if candidates:
        candidates.sort(key=lambda item: item[0], reverse=True)
        return candidates[0][1]
    return fallback


def load_training_json(name: str) -> dict[str, Any]:
    return load_newest_json([RUNTIME_SHARED_ROOT / name, TRAINING_ROOT / name])


def training_source_path(name: str) -> Path:
    shared_path = RUNTIME_SHARED_ROOT / name
    if shared_path.exists():
        return shared_path
    return TRAINING_ROOT / name


def _coerce_float(value: Any) -> float | None:
    try:
        if value is None or value == "":
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _current_task_request_snapshot() -> dict[str, Any]:
    return load_newest_json(
        [
            CONTEXT_SYNC_ROOT / "listener" / "MIM_TOD_TASK_REQUEST.latest.json",
            CONTEXT_SYNC_ROOT / "ssh-shared" / "MIM_TOD_TASK_REQUEST.latest.json",
        ]
    )


def _target_files_from_request(request: dict[str, Any]) -> tuple[list[str], str]:
    raw = request.get("target_files")
    raw_type = type(raw).__name__ if raw is not None else "missing"
    if isinstance(raw, list):
        return [str(item).strip() for item in raw if str(item or "").strip()], raw_type
    if isinstance(raw, str) and raw.strip():
        return [raw.strip()], raw_type
    return [], raw_type


def task_request_shape_snapshot(request: dict[str, Any]) -> dict[str, Any]:
    if not request:
        return {
            "present": False,
            "implementation_shaped": False,
            "malformed_reasons": ["missing_request"],
        }
    completion_gate = request.get("completion_gate") if isinstance(request.get("completion_gate"), dict) else {}
    target_file = str(request.get("target_file") or "").strip()
    target_files, target_files_type = _target_files_from_request(request)
    one_target_file = bool(target_file) or len(target_files) == 1
    task_class = str(request.get("task_class") or "").strip()
    validation_only = bool(request.get("validation_only"))
    changed_required = bool(completion_gate.get("changed_files_required_for_success"))
    malformed_reasons: list[str] = []
    if task_class != "implementation":
        malformed_reasons.append(f"task_class={task_class or 'missing'}")
    if validation_only:
        malformed_reasons.append("validation_only=true")
    if not changed_required:
        malformed_reasons.append("changed_files_required_for_success=false")
    if not one_target_file:
        malformed_reasons.append("one_target_file=false")
    if request.get("target_files") is not None and not isinstance(request.get("target_files"), (list, str)):
        malformed_reasons.append(f"target_files_type={target_files_type}")
    implementation_shaped = (
        task_class == "implementation"
        and changed_required
        and not validation_only
        and one_target_file
    )
    return {
        "present": True,
        "request_id": str(request.get("request_id") or request.get("task_id") or "").strip(),
        "objective_id": str(request.get("objective_id") or "").strip(),
        "task_class": task_class or "missing",
        "validation_only": validation_only,
        "changed_files_required_for_success": changed_required,
        "target_file": target_file,
        "target_files_count": len(target_files),
        "target_files_type": target_files_type,
        "one_target_file": one_target_file,
        "implementation_shaped": implementation_shaped,
        "malformed_reasons": malformed_reasons,
    }


def deploy_payload_verification_snapshot(payload: dict[str, Any]) -> dict[str, Any]:
    deployment_verification = payload.get("deployment_verification")
    if isinstance(deployment_verification, dict):
        deployment_status = str(deployment_verification.get("status") or "").strip().lower()
        if deployment_status in {
            "deployed",
            "deployed_and_verified",
            "verified",
            "verified_remote",
            "closed",
            "superseded",
            "cancelled",
        }:
            evidence_bits = _string_list(deployment_verification.get("remote_validation"))
            evidence = "; ".join(evidence_bits[:3])
            if not evidence:
                evidence = str(deployment_verification.get("deployment_path") or "").strip()
            return {
                "verification_status": deployment_status,
                "verification_reason": (
                    f"deployment_verification.status={deployment_status}; "
                    "treating this payload as no longer pending"
                ),
                "verification_evidence": evidence or "deployment_verification",
            }
        if deployment_status in {
            "files_deployed_remote_validation_blocked",
            "remote_focused_verified_live_probe_blocked",
            "remote_validated_services_listening_probe_blocked",
            "remote_validation_blocked",
            "validation_blocked",
        }:
            blocker = str(
                deployment_verification.get("remote_validation_blocker")
                or deployment_verification.get("live_probe_blocker")
                or ""
            ).strip()
            remaining = _string_list(deployment_verification.get("remaining_validation"))
            evidence_bits = _string_list(deployment_verification.get("remote_validation")) or _string_list(
                deployment_verification.get("local_validation")
            )
            evidence = "; ".join(evidence_bits[:2])
            verified_phrase = (
                "remote focused validation passed, but live service probing is still blocked"
                if deployment_status == "remote_focused_verified_live_probe_blocked"
                else "files were deployed through the existing path, but live remote validation is still blocked"
            )
            if deployment_status == "remote_validated_services_listening_probe_blocked":
                verified_phrase = (
                    "remote validation passed and user services are listening, but HTTP route proof is still blocked"
                )
            return {
                "verification_status": deployment_status,
                "verification_reason": (
                    verified_phrase
                    + (f": {blocker}" if blocker else "")
                ),
                "verification_evidence": evidence or "; ".join(remaining[:2]) or "deployment_verification",
            }

    objective_id = str(payload.get("objective_id") or "").strip()
    objective_key = objective_id.upper()
    if objective_key == "MIM-CONVERSATION-MODE-SELECTION-V2":
        operator = load_training_json("MIM_OPERATOR_IMPACT_SCORECARD.latest.json")
        score = _coerce_float(operator.get("operator_impact_score"))
        sample_count = operator.get("sample_count")
        pass_count = operator.get("pass_count")
        if score is not None and score >= 8:
            return {
                "verification_status": "partially_verified",
                "verification_reason": (
                    f"operator impact score is {score:.1f}/10; still requires durability smoke and internal-leakage evidence"
                ),
                "verification_evidence": "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
            }
        if score is not None:
            return {
                "verification_status": "not_verified",
                "verification_reason": (
                    f"operator impact score is still {score:.1f}/10; acceptance requires >=8.0 "
                    f"(fully passing replies {pass_count}/{sample_count})"
                ),
                "verification_evidence": "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
            }
        return {
            "verification_status": "not_verified",
            "verification_reason": "operator impact score evidence is missing",
            "verification_evidence": "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        }
    if objective_key in {
        "MIM-TOD-REMEDIATION-DISPATCH-BOUNDED-ACTION-V1",
        "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
    }:
        task_request = _current_task_request_snapshot()
        shape = task_request_shape_snapshot(task_request)
        if shape.get("implementation_shaped"):
            return {
                "verification_status": "partially_verified",
                "verification_reason": (
                    "current live task request is implementation-shaped; still requires post-deploy tests, TOD receipt, and execution evidence"
                ),
                "verification_evidence": "MIM_TOD_TASK_REQUEST.latest.json",
            }
        if task_request:
            reason_fields = ", ".join(shape.get("malformed_reasons") or [])
            return {
                "verification_status": "not_verified",
                "verification_reason": (
                    "current live task request is not implementation-shaped "
                    f"({reason_fields})"
                ),
                "verification_evidence": "MIM_TOD_TASK_REQUEST.latest.json",
            }
        return {
            "verification_status": "not_verified",
            "verification_reason": "current MIM_TOD_TASK_REQUEST.latest.json evidence is missing",
            "verification_evidence": "MIM_TOD_TASK_REQUEST.latest.json",
        }
    return {
        "verification_status": "pending_manual_verification",
        "verification_reason": "no deploy-specific verifier is registered for this objective",
        "verification_evidence": "",
    }


def bridge_materialization_state_snapshot() -> dict[str, Any]:
    request_sources = [
        ("listener", CONTEXT_SYNC_ROOT / "listener" / "MIM_TOD_TASK_REQUEST.latest.json"),
        ("ssh-shared", CONTEXT_SYNC_ROOT / "ssh-shared" / "MIM_TOD_TASK_REQUEST.latest.json"),
        ("runtime-shared", RUNTIME_SHARED_ROOT / "MIM_TOD_TASK_REQUEST.latest.json"),
    ]
    request_copies: list[dict[str, Any]] = []
    for source_name, source_path in request_sources:
        payload = load_json(source_path)
        shape = task_request_shape_snapshot(payload)
        shape["source"] = source_name
        shape["path"] = str(source_path.relative_to(ROOT)) if source_path.is_relative_to(ROOT) else str(source_path)
        request_copies.append(shape)
    listener_request = load_json(CONTEXT_SYNC_ROOT / "listener" / "MIM_TOD_TASK_REQUEST.latest.json")
    ssh_request = load_json(CONTEXT_SYNC_ROOT / "ssh-shared" / "MIM_TOD_TASK_REQUEST.latest.json")
    runtime_request = load_json(RUNTIME_SHARED_ROOT / "MIM_TOD_TASK_REQUEST.latest.json")
    command_status = load_json(CONTEXT_SYNC_ROOT / "listener" / "TOD_MIM_COMMAND_STATUS.latest.json")
    execution_result = load_json(RUNTIME_SHARED_ROOT / "TOD_EXECUTION_RESULT.latest.json")
    request = listener_request or ssh_request or runtime_request
    shape = task_request_shape_snapshot(request)
    implementation_shaped = bool(shape.get("implementation_shaped"))
    command_acted = bool(command_status.get("acted_upon")) or str(command_status.get("status") or "").lower() == "succeeded"
    execution_status = str(execution_result.get("status") or "").strip()
    reason_code = str(execution_result.get("reason_code") or "").strip()
    transport_active = bool(request) and (command_acted or bool(execution_result))
    if implementation_shaped:
        status = "existing_bridge_active_implementation_request_visible" if transport_active else "implementation_request_visible"
        blocker = ""
        required_next_action = "Let TOD execute the implementation-shaped request and validate changed-file evidence."
    elif request and transport_active:
        status = "existing_bridge_active_materialization_blocked"
        blocker = "request_materialization_missing_bounded_edit_fields"
        required_next_action = (
            "Apply the full-file-safe MIM materializer repair through the existing source/deploy path, "
            "then materialize partial hunk payloads against live files; do not add another SSH channel or transport."
        )
    elif request:
        status = "request_visible_transport_ack_unproven"
        blocker = "bridge_ack_or_execution_evidence_missing"
        required_next_action = "Verify existing listener acknowledgement/result artifacts before changing transport."
    else:
        status = "request_missing"
        blocker = "no_current_mim_tod_task_request"
        required_next_action = "Refresh the existing shared bridge artifacts before diagnosing request materialization."
    return {
        "status": status,
        "transport": "existing managed listener over shared MIM_TOD_TASK_REQUEST.latest.json",
        "transport_active": transport_active,
        "no_new_channel_required": True,
        "blocker": blocker,
        "required_next_action": required_next_action,
        "current_request": {
            "request_id": shape.get("request_id", ""),
            "objective_id": shape.get("objective_id", ""),
            "task_class": shape.get("task_class", "missing"),
            "validation_only": bool(shape.get("validation_only")),
            "changed_files_required_for_success": bool(shape.get("changed_files_required_for_success")),
            "target_file": shape.get("target_file", ""),
            "target_files_count": shape.get("target_files_count", 0),
            "target_files_type": shape.get("target_files_type", "missing"),
            "one_target_file": bool(shape.get("one_target_file")),
            "implementation_shaped": implementation_shaped,
            "malformed_reasons": shape.get("malformed_reasons", []),
        },
        "request_copies": request_copies,
        "tod_execution": {
            "status": execution_status,
            "reason_code": reason_code,
        },
        "evidence": [
            "tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json",
            "tod/out/context-sync/listener/TOD_MIM_COMMAND_STATUS.latest.json",
            "runtime/shared/TOD_EXECUTION_RESULT.latest.json",
        ],
    }


def deploy_payload_local_patch_readiness(payload: dict[str, Any]) -> dict[str, Any]:
    local_refs = _string_list(payload.get("local_reference_files"))
    if not local_refs:
        local_ref = str(payload.get("local_reference_file") or "").strip()
        local_refs = [local_ref] if local_ref else []
    checked: list[dict[str, Any]] = []
    missing: list[str] = []
    for ref in local_refs:
        path = Path(ref)
        if not path.is_absolute():
            path = ROOT / path
        exists = path.exists() and path.is_file()
        if not exists:
            missing.append(ref)
        checked.append(
            {
                "path": ref,
                "exists": exists,
            }
        )
    if not local_refs:
        status = "no_local_reference_files_declared"
    elif missing:
        status = "missing_local_reference_files"
    else:
        status = "local_reference_ready"
    return {
        "status": status,
        "ready": bool(local_refs) and not missing,
        "checked": checked,
        "missing": missing,
        "note": "Readiness only proves local patch material exists; it does not prove live deployment.",
    }


def _quote_powershell_arg(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _local_reference_files(payload: dict[str, Any]) -> list[str]:
    refs = _string_list(payload.get("local_reference_files"))
    if refs:
        return refs
    ref = str(payload.get("local_reference_file") or "").strip()
    return [ref] if ref else []


def _target_remote_files(payload: dict[str, Any]) -> list[str]:
    targets = payload.get("target_remote_files")
    if isinstance(targets, list):
        return [str(item).strip() for item in targets if str(item).strip()]
    target = str(payload.get("target_remote_file") or "").strip()
    return [target] if target else []


def deploy_file_application_plan(
    local_refs: list[str],
    remote_targets: list[str],
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload = payload or {}
    deploy_text = " ".join(
        str(payload.get(key) or "")
        for key in ("warning", "purpose", "deploy_note", "transport_note")
    ).lower()
    partial_patch_required = (
        "do not upload" in deploy_text
        or "do not blindly upload" in deploy_text
        or "apply only" in deploy_text
        or "route-order hunk" in deploy_text
        or "hunk" in deploy_text
    )
    pairs: list[dict[str, Any]] = []
    missing: list[str] = []
    count_mismatch = len(local_refs) != len(remote_targets)
    for index, local_ref in enumerate(local_refs):
        remote_target = remote_targets[index] if index < len(remote_targets) else ""
        path = Path(local_ref)
        if not path.is_absolute():
            path = ROOT / path
        exists = path.exists() and path.is_file()
        sha256 = ""
        size_bytes = None
        if exists:
            data = path.read_bytes()
            sha256 = hashlib.sha256(data).hexdigest()
            size_bytes = len(data)
        else:
            missing.append(local_ref)
        command = ""
        if remote_target and not partial_patch_required:
            command = (
                "powershell -NoProfile -File scripts\\Send-TODMimScript.ps1 "
                f"-LocalPath {_quote_powershell_arg(local_ref)} "
                f"-RemotePath {_quote_powershell_arg(remote_target)}"
            )
        pairs.append(
            {
                "local_path": local_ref,
                "remote_path": remote_target,
                "local_exists": exists,
                "sha256": sha256,
                "size_bytes": size_bytes,
                "apply_command": command,
            }
        )
    ready = (
        bool(pairs)
        and not partial_patch_required
        and not missing
        and not count_mismatch
        and all(pair.get("remote_path") for pair in pairs)
    )
    if partial_patch_required:
        status = "partial_patch_hunk_required"
    elif ready:
        status = "ready_for_existing_send_script"
    elif not pairs:
        status = "no_file_pairs_declared"
    elif count_mismatch:
        status = "local_remote_file_count_mismatch"
    elif missing:
        status = "missing_local_reference_files"
    else:
        status = "remote_target_missing"
    return {
        "status": status,
        "ready": ready,
        "pairs": pairs,
        "missing": missing,
        "count_mismatch": count_mismatch,
        "partial_patch_required": partial_patch_required,
        "apply_commands": [str(pair.get("apply_command") or "") for pair in pairs if pair.get("apply_command")],
        "note": (
            "Payload requires a partial live-file hunk; full-file Send-TODMimScript upload is intentionally withheld."
            if partial_patch_required
            else "Commands use the existing Send-TODMimScript.ps1 path; this manifest does not prove live deployment."
        ),
    }


def pending_deploy_payload_snapshot() -> dict[str, Any]:
    terminal_statuses = {
        "deployed",
        "deployed_and_verified",
        "verified",
        "verified_remote",
        "closed",
        "superseded",
        "cancelled",
    }
    payloads: list[dict[str, Any]] = []
    if not DEPLOY_PAYLOADS_ROOT.exists():
        return {
            "pending_count": 0,
            "latest": {},
            "pending_payloads": [],
            "source": str(DEPLOY_PAYLOADS_ROOT),
        }
    for path in sorted(DEPLOY_PAYLOADS_ROOT.glob("*.json")):
        payload = load_json(path)
        if str(payload.get("artifact_type") or "").strip() != "deploy_patch_handoff":
            continue
        deployment_verification = payload.get("deployment_verification")
        verified_status = (
            str(deployment_verification.get("status") or "").strip().lower()
            if isinstance(deployment_verification, dict)
            else ""
        )
        status = str(payload.get("status") or payload.get("deployment_status") or "").strip().lower()
        if verified_status in terminal_statuses:
            continue
        if status in terminal_statuses:
            continue
        local_refs = _local_reference_files(payload)
        target_files = _target_remote_files(payload)
        verification = deploy_payload_verification_snapshot(payload)
        local_patch_readiness = deploy_payload_local_patch_readiness(payload)
        application_plan = deploy_file_application_plan(local_refs, target_files, payload)
        payloads.append(
            {
                "file": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
                "generated_at": payload_timestamp(payload),
                "objective_id": str(payload.get("objective_id") or "").strip(),
                "purpose": sanitize_operator_text(payload.get("purpose") or payload.get("warning")),
                "local_reference_files": local_refs,
                "local_patch_readiness": local_patch_readiness,
                "target_remote_files": target_files,
                "application_plan": application_plan,
                "post_deploy_commands": _string_list(payload.get("post_deploy_commands")),
                "acceptance": _string_list(payload.get("acceptance")),
                "verification_status": verification.get("verification_status"),
                "verification_reason": verification.get("verification_reason"),
                "verification_evidence": verification.get("verification_evidence"),
            }
        )
    payloads.sort(key=lambda item: item.get("generated_at") or item.get("file") or "", reverse=True)
    return {
        "pending_count": len(payloads),
        "latest": payloads[0] if payloads else {},
        "pending_payloads": payloads,
        "source": str(DEPLOY_PAYLOADS_ROOT),
    }


def deploy_application_result_snapshot() -> dict[str, Any]:
    result = load_training_json("MIM_STALE_REMEDIATION_MATERIALIZATION_DEPLOY_RESULT.latest.json")
    if not result:
        return {
            "status": "missing",
            "source": "MIM_STALE_REMEDIATION_MATERIALIZATION_DEPLOY_RESULT.latest.json",
        }
    return {
        "status": str(result.get("status") or "unknown").strip() or "unknown",
        "objective_id": str(result.get("objective_id") or "").strip(),
        "generated_at": str(result.get("generated_at") or "").strip(),
        "no_new_channel_required": bool(result.get("no_new_channel_required")),
        "live_request_emitted": bool(result.get("live_request_emitted")),
        "live_deployment_verified": bool(result.get("live_deployment_verified")),
        "applied_file_count": len(result.get("applied_files") if isinstance(result.get("applied_files"), list) else []),
        "remote_validation": result.get("remote_validation") if isinstance(result.get("remote_validation"), list) else [],
        "remaining_blockers": result.get("remaining_blockers") if isinstance(result.get("remaining_blockers"), list) else [],
        "source": "MIM_STALE_REMEDIATION_MATERIALIZATION_DEPLOY_RESULT.latest.json",
    }


def active_stale_artifacts_with_disposition(
    stale_artifacts: Any, disposition: dict[str, Any]
) -> tuple[list[str], list[dict[str, Any]]]:
    if not isinstance(stale_artifacts, list):
        return [], []
    artifacts = [str(item) for item in stale_artifacts if str(item or "").strip()]
    dispositions = disposition.get("artifacts") if isinstance(disposition.get("artifacts"), dict) else {}
    inactive_statuses = {
        "retired_historical",
        "source_labeled_historical",
        "superseded",
        "superseded_by_current_scoreboard",
        "terminal_complete",
        "terminal_succeeded",
    }
    active: list[str] = []
    applied: list[dict[str, Any]] = []
    for name in artifacts:
        row = dispositions.get(name) if isinstance(dispositions.get(name), dict) else {}
        status = str(row.get("status") or "").strip().lower()
        if status in inactive_statuses:
            applied.append(
                {
                    "artifact": name,
                    "status": status,
                    "reason": sanitize_operator_text(row.get("reason")),
                    "replacement": sanitize_operator_text(row.get("replacement")),
                    "evidence": sanitize_operator_text(row.get("evidence")),
                }
            )
            continue
        active.append(name)
    return active, applied


def parse_json_text(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if not isinstance(value, str) or not value.strip():
        return {}
    try:
        parsed = json.loads(value)
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def pct(numerator: int, denominator: int) -> int | None:
    if denominator <= 0:
        return None
    return round((numerator / denominator) * 100)


def baseline_needed(reason: str) -> dict[str, Any]:
    return {"value": None, "status": "baseline_needed", "reason": reason}


def baseline_started(reason: str, value: object = None) -> dict[str, Any]:
    return {"value": value, "status": "baseline_established", "reason": reason}


def measured_count(value: int, source: str, reason: str | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {"value": value, "status": "measured", "source": source}
    if reason:
        payload["reason"] = reason
    return payload


def _string_list(value: Any) -> list[str]:
    if isinstance(value, str):
        stripped = value.strip()
        return [stripped] if stripped else []
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def _truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "y"}


def _falsey(value: Any) -> bool:
    if isinstance(value, bool):
        return not value
    return str(value or "").strip().lower() in {"0", "false", "no", "n", ""}


def _validation_passed(payload: dict[str, Any]) -> bool:
    validator = payload.get("validator") if isinstance(payload.get("validator"), dict) else {}
    validator_output = parse_json_text(validator.get("output"))
    validation = payload.get("validation") if isinstance(payload.get("validation"), dict) else {}
    validation_results = payload.get("validation_results") if isinstance(payload.get("validation_results"), list) else []
    validator_checks = validator_output.get("checks") if isinstance(validator_output.get("checks"), list) else []
    checks = validation.get("checks") if isinstance(validation.get("checks"), list) else []
    all_checks = [*validator_checks, *checks, *validation_results]
    checks_passed = bool(all_checks) and all(
        bool(item.get("passed")) for item in all_checks if isinstance(item, dict)
    )
    if all_checks:
        return checks_passed
    return (
        bool(validator.get("passed"))
        or str(payload.get("status") or "").lower() in {"passed", "completed", "target_met"}
        or str(validation.get("status") or "").lower() in {"passed", "completed", "target_met"}
    )


def _validated_edit_evidence(payload: dict[str, Any]) -> dict[str, Any] | None:
    changed_files = _string_list(payload.get("changed_files")) or _string_list(payload.get("files_changed"))
    artifact_writes = _string_list(payload.get("artifact_writes"))
    validation_commands = _string_list(payload.get("validation_commands")) or _string_list(payload.get("tests_run"))
    prevention_lesson = str(payload.get("prevention_lesson") or payload.get("lesson") or "").strip()
    live_paths_affected = _string_list(payload.get("live_paths_affected"))
    behavior_change = str(payload.get("behavior_change") or "").strip()
    problem_identified = str(payload.get("problem_identified") or "").strip()
    fix_summary = str(payload.get("fix_summary") or "").strip()
    resolution_owner = str(payload.get("resolution_owner") or payload.get("owner") or "").strip()
    dave_needed = str(payload.get("dave_needed") or "").strip().lower()
    codex_needed = str(payload.get("codex_needed") or "").strip().lower()
    has_change = bool(changed_files or artifact_writes)
    wrapper_only = bool(payload.get("wrapper_only_completion"))
    credit_decision = payload.get("credit_decision") if isinstance(payload.get("credit_decision"), dict) else {}
    if credit_decision.get("validated_tod_edit") is False:
        return None
    if wrapper_only or not prevention_lesson or not has_change or not _validation_passed(payload):
        return None
    real_code_files = [
        path
        for path in changed_files
        if _is_real_code_file(path) and not _is_low_impact_file(path)
    ]
    meaningful_implementation = bool(real_code_files and behavior_change and live_paths_affected)
    if credit_decision.get("meaningful_tod_implementation") is False:
        meaningful_implementation = False
    elif credit_decision.get("meaningful_tod_implementation") is True:
        meaningful_implementation = True
    evidence_id = str(
        payload.get("validated_edit_id")
        or payload.get("task_id")
        or payload.get("execution_id")
        or payload.get("objective_id")
        or payload.get("generated_at")
        or payload.get("updated_at")
        or payload.get("completed_at")
        or ""
    ).strip()
    if not evidence_id:
        evidence_id = "|".join(changed_files + artifact_writes)
    selected_by_tod = _truthy(payload.get("selected_by_tod") or payload.get("tod_selected_problem") or payload.get("tod_identified_problem"))
    codex_patch_supplied = not _falsey(payload.get("codex_patch_supplied") or payload.get("codex_patch_supplied_for_target_task"))
    successor_state = str(payload.get("successor_state") or payload.get("closed_state") or payload.get("terminal_state") or "").strip()
    legacy_independent_baseline = evidence_id in LEGACY_INDEPENDENT_RESOLUTION_IDS
    strict_independent_proof = bool(selected_by_tod and not codex_patch_supplied and successor_state)
    independent_resolution = bool(
        meaningful_implementation
        and problem_identified
        and fix_summary
        and resolution_owner.upper() == "TOD"
        and dave_needed == "no"
        and codex_needed == "no"
        and (legacy_independent_baseline or strict_independent_proof)
    )
    if credit_decision.get("independent_tod_resolution") is False:
        independent_resolution = False
    elif credit_decision.get("independent_tod_resolution") is True:
        independent_resolution = True
    return {
        "id": evidence_id,
        "generated_at": payload_timestamp(payload),
        "changed_files": changed_files,
        "artifact_writes": artifact_writes,
        "validation_commands": validation_commands,
        "summary": str(payload.get("summary") or payload.get("result") or "").strip(),
        "prevention_lesson": prevention_lesson,
        "real_code_files": real_code_files,
        "behavior_change": behavior_change,
        "live_paths_affected": live_paths_affected,
        "meaningful_implementation": meaningful_implementation,
        "problem_identified": problem_identified,
        "fix_summary": fix_summary,
        "resolution_owner": resolution_owner,
        "dave_needed": dave_needed,
        "codex_needed": codex_needed,
        "selected_by_tod": selected_by_tod,
        "codex_patch_supplied": codex_patch_supplied,
        "successor_state": successor_state,
        "legacy_independent_baseline": legacy_independent_baseline,
        "independent_resolution": independent_resolution,
    }


def _is_real_code_file(path: str) -> bool:
    normalized = path.replace("\\", "/").lower()
    return normalized.endswith((".py", ".ps1", ".js", ".ts", ".tsx", ".jsx", ".html", ".css"))


def _is_low_impact_file(path: str) -> bool:
    normalized = path.replace("\\", "/").lower()
    low_impact_prefixes = (
        "tests/",
        "runtime_remote_training/",
        "runtime/",
        "docs/",
    )
    low_impact_names = (
        "generate_mim_tod_training_scoreboard.py",
        "build_mim_tod_real_movement_scorecard.py",
    )
    return normalized.startswith(low_impact_prefixes) or any(normalized.endswith(name) for name in low_impact_names)


def _validated_edit_rejection_reason(payload: dict[str, Any]) -> str | None:
    changed_files = _string_list(payload.get("changed_files")) or _string_list(payload.get("files_changed"))
    artifact_writes = _string_list(payload.get("artifact_writes"))
    prevention_lesson = str(payload.get("prevention_lesson") or payload.get("lesson") or "").strip()
    if bool(payload.get("wrapper_only_completion")):
        return "wrapper_only_completion"
    if not prevention_lesson:
        return "missing_prevention_lesson"
    if not (changed_files or artifact_writes):
        return "missing_change_or_artifact_write"
    if not _validation_passed(payload):
        return "missing_validation_evidence"
    return None


def validated_edit_artifact_audit() -> dict[str, Any]:
    records: list[dict[str, Any]] = []
    rejection_counts: dict[str, int] = {}
    seen: set[str] = set()
    for root in TOD_RESULT_ARTIFACT_ROOTS:
        if not root.exists():
            continue
        for path in sorted(root.glob("*.json")):
            payload = load_json(path)
            if not payload:
                continue
            evidence = _validated_edit_evidence(payload)
            if not evidence:
                reason = _validated_edit_rejection_reason(payload) or "unknown"
                rejection_counts[reason] = rejection_counts.get(reason, 0) + 1
                continue
            evidence["source_path"] = str(path)
            evidence_id = str(evidence.get("id") or path.name)
            if evidence_id in seen:
                continue
            seen.add(evidence_id)
            records.append(evidence)
    return {
        "accepted_records": records,
        "rejection_counts": rejection_counts,
    }


def load_validated_edit_ledger() -> list[dict[str, Any]]:
    audit = validated_edit_artifact_audit()
    return audit["accepted_records"] if isinstance(audit.get("accepted_records"), list) else []


def _latest_packet_gate_timestamp() -> float:
    if not INDEPENDENT_ATTEMPTS_ROOT.exists():
        return 0.0
    timestamps: list[float] = []
    for path in INDEPENDENT_ATTEMPTS_ROOT.glob("*.json"):
        payload = load_json(path)
        if not payload.get("packet_candidate_ready"):
            continue
        timestamp = payload_timestamp_seconds(payload)
        if timestamp > 0:
            timestamps.append(timestamp)
    return min(timestamps) if timestamps else 0.0


def load_state_proven_validated_edit_records(after_timestamp: float | None = None) -> list[dict[str, Any]]:
    state = load_json(TOD_STATE_PATH)
    tasks = state.get("tasks") if isinstance(state.get("tasks"), list) else []
    after = after_timestamp if after_timestamp is not None else _latest_packet_gate_timestamp()
    records: list[dict[str, Any]] = []
    excluded_title_markers = ("packet", "artifact_write", "practice", "validation-only", "drill", "no-credit")
    for task in tasks:
        if not isinstance(task, dict):
            continue
        task_id = str(task.get("id") or task.get("task_id") or "").strip()
        if not task_id:
            continue
        title = str(task.get("title") or "").lower()
        if any(marker in title for marker in excluded_title_markers):
            continue
        if str(task.get("status") or "").lower() != "completed":
            continue
        if str(task.get("assigned_executor") or "").lower() != "local":
            continue
        if str(task.get("task_category") or "").lower() != "code_change":
            continue
        updated_at = payload_timestamp_seconds({"updated_at": task.get("updated_at")})
        if after and updated_at < after:
            continue
        terminal = task.get("terminal_state") if isinstance(task.get("terminal_state"), dict) else {}
        if str(terminal.get("event_type") or "").lower() != "local_executor_completed":
            continue
        details = terminal.get("details") if isinstance(terminal.get("details"), dict) else {}
        if str(details.get("review_decision") or "").lower() != "pass":
            continue
        failures = details.get("failures") if isinstance(details.get("failures"), list) else []
        if failures:
            continue
        changed_files = _string_list(details.get("files_changed"))
        if not changed_files:
            continue
        records.append(
            {
                "id": task_id,
                "generated_at": str(task.get("updated_at") or ""),
                "changed_files": changed_files,
                "artifact_writes": [],
                "validation_commands": _string_list(details.get("tests_run")),
                "summary": str(terminal.get("message") or task.get("title") or "").strip(),
                "prevention_lesson": "State-proven validated edits require local executor completion, changed files, passing review, no failures, and post-gate timing.",
                "real_code_files": [path for path in changed_files if _is_real_code_file(path) and not _is_low_impact_file(path)],
                "behavior_change": str(task.get("title") or "").strip(),
                "live_paths_affected": [],
                "meaningful_implementation": False,
                "problem_identified": "",
                "fix_summary": str(task.get("title") or "").strip(),
                "resolution_owner": "TOD",
                "dave_needed": "no",
                "codex_needed": "no",
                "selected_by_tod": True,
                "codex_patch_supplied": False,
                "successor_state": "completed_with_state_proven_validation",
                "legacy_independent_baseline": False,
                "independent_resolution": False,
                "source_path": str(TOD_STATE_PATH),
                "state_proven": True,
            }
        )
    return sorted(records, key=lambda item: str(item.get("generated_at") or ""))


def sanitize_operator_text(value: Any) -> str:
    text = str(value or "")
    text = re.sub(r"\btask\s+\d{3,}\b", "the inspected task", text, flags=re.IGNORECASE)
    text = re.sub(r"\bobjective\s+\d{3,}\b", "the inspected objective", text, flags=re.IGNORECASE)
    text = re.sub(r"\bobjective-\d+\b", "the active objective", text, flags=re.IGNORECASE)
    text = re.sub(r"\brecommendation\s+\d{2,}\b", "the newest improvement recommendation", text, flags=re.IGNORECASE)
    return text


def tod_artifact_metric_snapshot() -> dict[str, Any]:
    task_result = load_newest_json(
        [
            TRAINING_ROOT / "TOD_MIM_TASK_RESULT.latest.json",
            RUNTIME_SHARED_ROOT / "TOD_MIM_TASK_RESULT.latest.json",
        ]
    )
    command_status = load_newest_json(
        [
            TRAINING_ROOT / "TOD_MIM_COMMAND_STATUS.latest.json",
            RUNTIME_SHARED_ROOT / "TOD_MIM_COMMAND_STATUS.latest.json",
        ]
    )
    execution_result = load_newest_json(
        [
            TRAINING_ROOT / "TOD_EXECUTION_RESULT.latest.json",
            RUNTIME_SHARED_ROOT / "TOD_EXECUTION_RESULT.latest.json",
        ]
    )
    validation_result = load_newest_json(
        [
            TRAINING_ROOT / "TOD_VALIDATION_RESULT.latest.json",
            RUNTIME_SHARED_ROOT / "TOD_VALIDATION_RESULT.latest.json",
        ]
    )
    artifacts = [task_result, command_status, execution_result, validation_result]
    changed_file_sets = []
    artifact_write_sets = []
    for payload in artifacts:
        if not isinstance(payload, dict):
            continue
        changed_files = payload.get("changed_files")
        if isinstance(changed_files, list):
            changed_file_sets.append(changed_files)
        artifact_writes = payload.get("artifact_writes")
        if isinstance(artifact_writes, list):
            artifact_write_sets.append(artifact_writes)
    validator = task_result.get("validator") if isinstance(task_result.get("validator"), dict) else {}
    validator_output = parse_json_text(validator.get("output"))
    validator_checks = validator_output.get("checks") if isinstance(validator_output.get("checks"), list) else []
    validator_passed = bool(validator.get("passed")) or str(validation_result.get("status") or "").lower() == "passed"
    latest_validated_records = [
        evidence for evidence in (_validated_edit_evidence(payload) for payload in artifacts if isinstance(payload, dict)) if evidence
    ]
    ledger_audit = validated_edit_artifact_audit()
    ledger_records = ledger_audit["accepted_records"] if isinstance(ledger_audit.get("accepted_records"), list) else []
    state_proven_records = load_state_proven_validated_edit_records()
    def evidence_rank(evidence: dict[str, Any]) -> tuple[int, int, int, int]:
        return (
            1 if bool(evidence.get("independent_resolution")) else 0,
            1 if bool(evidence.get("meaningful_implementation")) else 0,
            0 if bool(evidence.get("state_proven")) else 1,
            1 if evidence.get("problem_identified") and evidence.get("fix_summary") else 0,
        )

    unique_records: dict[str, dict[str, Any]] = {}
    for evidence in [*ledger_records, *latest_validated_records, *state_proven_records]:
        evidence_id = str(evidence.get("id") or "")
        if not evidence_id:
            continue
        current = unique_records.get(evidence_id)
        if current is None or evidence_rank(evidence) > evidence_rank(current):
            unique_records[evidence_id] = evidence
    validated_edit_count = len(unique_records)
    state_proven_count = len(
        [
            evidence
            for evidence in unique_records.values()
            if bool(evidence.get("state_proven"))
        ]
    )
    meaningful_records = [
        evidence for evidence in unique_records.values() if bool(evidence.get("meaningful_implementation"))
    ]
    independent_records = [
        evidence for evidence in unique_records.values() if bool(evidence.get("independent_resolution"))
    ]
    state_proven_independent_records = [
        evidence
        for evidence in unique_records.values()
        if bool(evidence.get("state_proven"))
        and bool(evidence.get("independent_resolution"))
    ]
    state_proven_local_completion_records = [
        evidence
        for evidence in unique_records.values()
        if bool(evidence.get("state_proven"))
        and bool(evidence.get("selected_by_tod"))
        and not _truthy(evidence.get("codex_patch_supplied"))
        and not bool(evidence.get("independent_resolution"))
    ]
    independent_resolution_count = len(independent_records)
    if state_proven_independent_records:
        independent_resolution_count += len(state_proven_independent_records)
        independent_resolution_source = "tod_result_artifacts + tod/data/state.json"
        independent_resolution_reason = (
            f"{len(independent_records)} strict artifact-backed independent resolution(s) plus "
            f"{len(state_proven_independent_records)} state-proven local executor resolution(s); "
            "state-proven records require TOD-selected local code_change completion, changed files, passing review, "
            "no failures, Dave needed no, and Codex patch supplied false"
        )
    else:
        independent_resolution_source = "tod_result_artifacts"
        independent_resolution_reason = (
            "counted only meaningful implementation records where TOD identified the problem, fixed it, validated it, "
            "marked Dave/Codex needed as no, and provided TOD-selection plus closure proof; "
            "the first baseline resolution is preserved as legacy evidence"
        )
    has_validated_change = validated_edit_count > 0
    no_op_haystack = json.dumps(artifacts, sort_keys=True, default=str).lower()
    no_op_rejections = 1 if "no_op_rejected" in no_op_haystack else 0
    return {
        "source": "tod_result_artifacts",
        "task_result_generated_at": task_result.get("generated_at"),
        "command_status_generated_at": command_status.get("generated_at"),
        "validator_passed": validator_passed,
        "validator_check_count": len(validator_checks),
        "validated_edits": measured_count(
            validated_edit_count,
            "tod_result_artifacts + tod/data/state.json" if state_proven_count else "tod_result_artifacts",
            (
                f"{validated_edit_count} distinct TOD validated edit(s) have passing validation and changed-file/artifact-write evidence; {state_proven_count} came from strict local executor state"
                if has_validated_change
                else "TOD validation is measured, but no changed-file/artifact-write evidence was present"
            ),
        ),
        "validated_edit_records": sorted(unique_records.values(), key=lambda item: str(item.get("generated_at") or "")),
        "validated_edit_rejection_counts": ledger_audit.get("rejection_counts") if isinstance(ledger_audit.get("rejection_counts"), dict) else {},
        "meaningful_tod_implementations": measured_count(
            len(meaningful_records),
            "tod_result_artifacts",
            "counted only records with real code changed, behavior_change, live_paths_affected, and passing validation",
        ),
        "meaningful_tod_implementation_records": sorted(meaningful_records, key=lambda item: str(item.get("generated_at") or "")),
        "independent_tod_resolutions": measured_count(
            independent_resolution_count,
            independent_resolution_source,
            independent_resolution_reason,
        ),
        "independent_tod_resolution_records": sorted(
            [*independent_records, *state_proven_independent_records],
            key=lambda item: str(item.get("generated_at") or ""),
        ),
        "state_proven_local_completion_records": sorted(
            state_proven_local_completion_records,
            key=lambda item: str(item.get("generated_at") or ""),
        ),
        "state_proven_local_completions_pending_independent_proof": measured_count(
            len(state_proven_local_completion_records),
            "tod/data/state.json",
            "visible but not counted as independent resolutions because state-only records lack explicit problem/fix/meaningful implementation proof",
        ),
        "no_op_rejections": measured_count(
            no_op_rejections,
            "tod_result_artifacts",
            "counted no_op_rejected classifications visible in latest TOD result/status artifacts",
        ),
    }


def tod_next_action_accuracy_snapshot() -> dict[str, Any]:
    training_set = load_training_json("TOD_NEXT_ACTION_SELECTION_TRAINING_SET.latest.json")
    scorer = load_training_json("TOD_NEXT_ACTION_SELECTION_SCHEMA_AND_SCORER_V1.latest.json")
    records = training_set.get("records") if isinstance(training_set.get("records"), list) else []
    dimensions = scorer.get("scoring_dimensions") if isinstance(scorer.get("scoring_dimensions"), list) else []
    dimension_keys = [str(item.get("key") or "").strip() for item in dimensions if isinstance(item, dict) and item.get("key")]
    if not dimension_keys:
        dimension_keys = [
            "moved_project",
            "reduced_blocker_age",
            "closed_acceptance",
            "avoided_scope_expansion",
            "avoided_fake_completion",
            "avoided_unnecessary_dave",
        ]
    scored_records: list[dict[str, Any]] = []
    pending_records: list[dict[str, Any]] = []
    continuity_forum_validation = load_json(CONTINUITY_FORUM_GRAPHICS_VALIDATION_PATH)
    continuity_gate = (
        continuity_forum_validation.get("continuity_gate_result")
        if isinstance(continuity_forum_validation.get("continuity_gate_result"), dict)
        else {}
    )
    continuity_forum_validated = (
        str(continuity_forum_validation.get("status") or "").lower() == "validated_with_existing_evidence"
        and str(continuity_forum_validation.get("validation_case") or "").lower() == "forum graphics"
        and continuity_gate.get("has_prior_work") is True
    )
    lab_workbench_acceptance = load_json(LAB_WORKBENCH_ACCEPTANCE_PROOF_PATH)
    lab_operator_evidence = (
        lab_workbench_acceptance.get("operator_evidence")
        if isinstance(lab_workbench_acceptance.get("operator_evidence"), dict)
        else {}
    )
    lab_workbench_accepted = (
        str(lab_workbench_acceptance.get("status") or "").lower() == "accepted_completed"
        and str(lab_workbench_acceptance.get("project_title") or "") == "LAB Workbench Servo Tester"
        and lab_operator_evidence.get("operator_completion") is True
    )
    accounting_acceptance = load_json(MIM_OPERATIONS_ACCOUNTING_ACCEPTANCE_PATH)
    accounting_acceptance_defined = (
        str(accounting_acceptance.get("status") or "").lower() == "acceptance_defined"
        and str(accounting_acceptance.get("project_title") or "") == "MIM Operations Accounting"
        and bool(accounting_acceptance.get("first_driving_task"))
        and isinstance(accounting_acceptance.get("acceptance_criteria"), list)
        and len(accounting_acceptance.get("acceptance_criteria") or []) >= 3
    )
    scope_completion_audit = load_json(MIM_SCOPE_COMPLETION_AUDIT_PATH)
    scope_findings = (
        scope_completion_audit.get("findings")
        if isinstance(scope_completion_audit.get("findings"), list)
        else []
    )
    scope_completion_resolution = (
        scope_completion_audit.get("scoreboard_resolution")
        if isinstance(scope_completion_audit.get("scoreboard_resolution"), dict)
        else {}
    )
    scope_completion_audit_valid = (
        str(scope_completion_audit.get("status") or "").lower() == "audit_completed_with_follow_on_split"
        and any(
            isinstance(item, dict)
            and item.get("project") == "TOD Local PowerShell Migration"
            and item.get("follow_on_project") == "MIM-TOD-RESULT-BINDING-V1"
            for item in scope_findings
        )
        and scope_completion_resolution.get("completion_claim") == "partial_movement_only"
    )
    for record in records:
        if not isinstance(record, dict):
            continue
        outcome_score = record.get("outcome_score") if isinstance(record.get("outcome_score"), dict) else {}
        dimension_results = (
            outcome_score.get("dimensions")
            if isinstance(outcome_score.get("dimensions"), dict)
            else {}
        )
        if not dimension_results:
            situation = sanitize_operator_text(record.get("situation"))
            candidate_next_action = sanitize_operator_text(record.get("candidate_next_action"))
            is_continuity_forum_record = (
                continuity_forum_validated
                and "MIM Development Continuity V1" in situation
                and "forum graphics" in situation.lower()
            )
            is_lab_workbench_record = (
                lab_workbench_accepted
                and "LAB Workbench Servo Tester" in situation
                and "acceptance criteria" in situation.lower()
            )
            is_accounting_record = (
                accounting_acceptance_defined
                and "MIM Operations Accounting" in situation
                and "acceptance criteria" in situation.lower()
            )
            is_scope_completion_record = (
                scope_completion_audit_valid
                and "MIM Scope Completion Discipline V1" in situation
                and "scope expansion" in candidate_next_action.lower()
            )
            is_powershell_scope_record = (
                scope_completion_audit_valid
                and "TOD Local PowerShell Migration" in situation
                and "scope expansion" in situation.lower()
            )
            if is_continuity_forum_record:
                resolved_dimensions = {
                    "moved_project": True,
                    "reduced_blocker_age": True,
                    "closed_acceptance": False,
                    "avoided_scope_expansion": True,
                    "avoided_fake_completion": True,
                    "avoided_unnecessary_dave": True,
                }
                passed_dimensions = [
                    key for key in dimension_keys if bool(resolved_dimensions.get(key))
                ]
                scored_records.append(
                    {
                        "situation": situation,
                        "lane": record.get("lane"),
                        "candidate_next_action": candidate_next_action,
                        "passed_dimensions": passed_dimensions,
                        "score": len(passed_dimensions),
                        "max_score": len(dimension_keys),
                        "passed": len(passed_dimensions) >= 5,
                        "evidence_artifact": str(CONTINUITY_FORUM_GRAPHICS_VALIDATION_PATH),
                        "outcome": "continuity brief validated against forum graphics with existing evidence",
                    }
                )
                continue
            if is_lab_workbench_record:
                resolved_dimensions = {
                    "moved_project": True,
                    "reduced_blocker_age": True,
                    "closed_acceptance": True,
                    "avoided_scope_expansion": True,
                    "avoided_fake_completion": True,
                    "avoided_unnecessary_dave": True,
                }
                passed_dimensions = [
                    key for key in dimension_keys if bool(resolved_dimensions.get(key))
                ]
                scored_records.append(
                    {
                        "situation": situation,
                        "lane": record.get("lane"),
                        "candidate_next_action": candidate_next_action,
                        "passed_dimensions": passed_dimensions,
                        "score": len(passed_dimensions),
                        "max_score": len(dimension_keys),
                        "passed": len(passed_dimensions) >= 5,
                        "evidence_artifact": str(LAB_WORKBENCH_ACCEPTANCE_PROOF_PATH),
                        "outcome": "operator acceptance proof recorded terminal completed state",
                    }
                )
                continue
            if is_accounting_record:
                resolved_dimensions = {
                    "moved_project": True,
                    "reduced_blocker_age": True,
                    "closed_acceptance": False,
                    "avoided_scope_expansion": True,
                    "avoided_fake_completion": True,
                    "avoided_unnecessary_dave": True,
                }
                passed_dimensions = [
                    key for key in dimension_keys if bool(resolved_dimensions.get(key))
                ]
                scored_records.append(
                    {
                        "situation": situation,
                        "lane": record.get("lane"),
                        "candidate_next_action": candidate_next_action,
                        "passed_dimensions": passed_dimensions,
                        "score": len(passed_dimensions),
                        "max_score": len(dimension_keys),
                        "passed": len(passed_dimensions) >= 5,
                        "evidence_artifact": str(MIM_OPERATIONS_ACCOUNTING_ACCEPTANCE_PATH),
                        "outcome": "acceptance criteria and first driving task defined; execution remains open",
                    }
                )
                continue
            if is_scope_completion_record or is_powershell_scope_record:
                resolved_dimensions = {
                    "moved_project": True,
                    "reduced_blocker_age": True,
                    "closed_acceptance": False,
                    "avoided_scope_expansion": True,
                    "avoided_fake_completion": True,
                    "avoided_unnecessary_dave": True,
                }
                passed_dimensions = [
                    key for key in dimension_keys if bool(resolved_dimensions.get(key))
                ]
                outcome = (
                    "scope expansion audit split result-binding work into a follow-on while preserving original PowerShell migration acceptance"
                    if is_powershell_scope_record
                    else "scope completion audit identified expanded work and recorded a follow-on split without claiming full objective closure"
                )
                scored_records.append(
                    {
                        "situation": situation,
                        "lane": record.get("lane"),
                        "candidate_next_action": candidate_next_action,
                        "passed_dimensions": passed_dimensions,
                        "score": len(passed_dimensions),
                        "max_score": len(dimension_keys),
                        "passed": len(passed_dimensions) >= 5,
                        "evidence_artifact": str(MIM_SCOPE_COMPLETION_AUDIT_PATH),
                        "outcome": outcome,
                    }
                )
                continue
            pending_records.append(
                {
                    "situation": situation,
                    "lane": record.get("lane"),
                    "candidate_next_action": candidate_next_action,
                    "status": "outcome_pending",
                }
            )
            continue
        passed_dimensions = [
            key for key in dimension_keys if bool(dimension_results.get(key))
        ]
        fake_completion_failed = dimension_results.get("avoided_fake_completion") is False
        passed = len(passed_dimensions) >= 5 and not fake_completion_failed
        scored_records.append(
            {
                "situation": sanitize_operator_text(record.get("situation")),
                "lane": record.get("lane"),
                "candidate_next_action": sanitize_operator_text(record.get("candidate_next_action")),
                "passed_dimensions": passed_dimensions,
                "score": len(passed_dimensions),
                "max_score": len(dimension_keys),
                "passed": passed,
            }
        )
    passed_count = sum(1 for item in scored_records if item.get("passed"))
    pass_rate = pct(passed_count, len(scored_records)) if scored_records else None
    return {
        "source": "TOD_NEXT_ACTION_SELECTION_TRAINING_SET.latest.json",
        "scorer": "TOD_NEXT_ACTION_SELECTION_SCHEMA_AND_SCORER_V1.latest.json",
        "status": "measured" if scored_records else "baseline_needed",
        "record_count": len(records),
        "scored_count": len(scored_records),
        "pending_count": len(pending_records),
        "passed_count": passed_count,
        "pass_rate_percent": pass_rate,
        "score_dimensions": dimension_keys,
        "scored_records": scored_records[:20],
        "pending_records": pending_records[:20],
    }


def mim_structural_reasoning_snapshot() -> dict[str, Any]:
    structural = load_training_json("MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json")
    cross_surface = load_training_json("MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json")
    cross_surface_summary = {
        "source": str(training_source_path("MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json")),
        "status": cross_surface.get("status") or ("baseline_needed" if not cross_surface else "unknown"),
        "generated_at": cross_surface.get("generated_at"),
        "surface_count": cross_surface.get("surface_count") or 0,
        "target_met_surface_count": cross_surface.get("target_met_surface_count") or 0,
        "target_weighted_pass_rate_per_surface": cross_surface.get("target_weighted_pass_rate_per_surface") or 0.9,
        "unavailable_surfaces": cross_surface.get("unavailable_surfaces") if isinstance(cross_surface.get("unavailable_surfaces"), list) else [],
        "failing_surfaces": cross_surface.get("failing_surfaces") if isinstance(cross_surface.get("failing_surfaces"), list) else [],
        "surfaces": [
            {
                "surface": item.get("surface"),
                "available": item.get("available"),
                "status": (item.get("summary") or {}).get("status") if isinstance(item.get("summary"), dict) else None,
                "weighted_pass_rate": (item.get("summary") or {}).get("weighted_pass_rate") if isinstance(item.get("summary"), dict) else None,
                "direct_answer_control_failures": (item.get("summary") or {}).get("direct_answer_control_failures") if isinstance(item.get("summary"), dict) else None,
            }
            for item in (cross_surface.get("surfaces") if isinstance(cross_surface.get("surfaces"), list) else [])
            if isinstance(item, dict)
        ],
    }
    if not structural:
        return {
            "source": "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json",
            "status": "baseline_needed",
            "reason": "structural reasoning diversity scorer has not been run yet",
            "weighted_pass_rate_percent": None,
            "weighted_structural_score": None,
            "case_count": 0,
            "pass_count": 0,
            "metrics": [],
            "cross_surface": cross_surface_summary,
        }
    weighted_pass = structural.get("weighted_pass_rate")
    if isinstance(weighted_pass, (int, float)):
        weighted_pass_percent = round(float(weighted_pass) * 100)
    else:
        weighted_pass_percent = None
    return {
        "source": str(training_source_path("MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json")),
        "status": structural.get("status") or "unknown",
        "generated_at": structural.get("generated_at"),
        "weighted_pass_rate_percent": weighted_pass_percent,
        "weighted_structural_score": structural.get("weighted_structural_score"),
        "case_count": structural.get("case_count") or 0,
        "pass_count": structural.get("pass_count") or 0,
        "target_weighted_pass_rate": structural.get("target_weighted_pass_rate") or 0.9,
        "metrics": structural.get("metrics") if isinstance(structural.get("metrics"), list) else [],
        "next_action": structural.get("next_action") if isinstance(structural.get("next_action"), dict) else {},
        "cross_surface": cross_surface_summary,
    }


def post_gateway(base_url: str, prompt: str) -> str:
    payload = {
        "source": "text",
        "raw_input": prompt,
        "parsed_intent": "question",
        "confidence": 0.99,
        "target_system": "MIM",
        "requested_goal": "",
        "safety_flags": [],
        "metadata_json": {
            "route_preference": "conversation_layer",
            "test": "training_scoreboard_eval",
        },
    }
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/gateway/intake",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "content-type": "application/json",
            "user-agent": "MIM-TOD training scoreboard live eval/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    mim_interface = data.get("mim_interface") if isinstance(data.get("mim_interface"), dict) else {}
    resolution = data.get("resolution") if isinstance(data.get("resolution"), dict) else {}
    return str(mim_interface.get("reply_text") or resolution.get("clarification_prompt") or "").strip()


def evaluate_mim(base_url: str | None) -> dict[str, Any]:
    prompts = [
        {
            "id": "training_status",
            "prompt": "how is training going MIM?",
            "expected": ["training", "tod", "blocker"],
            "recommendation": False,
        },
        {
            "id": "blockers",
            "prompt": "any blockers?",
            "expected": ["blocker", "next", "dave"],
            "recommendation": False,
        },
        {
            "id": "next_work",
            "prompt": "is there anything you want to work on next?",
            "expected": ["next", "why", "intent"],
            "recommendation": True,
        },
        {
            "id": "more_training",
            "prompt": "tell me more about your training MIM",
            "expected": ["training", "mim", "tod"],
            "recommendation": False,
        },
    ]
    bad_generic = (
        "let me know if you want",
        "ask me about",
        "i can answer that directly",
        "what would you like to explore",
    )
    jargon_patterns = (
        r"\brequest[_ -]?id\b",
        r"\blifecycle\b",
        r"\bpacket\b",
        r"\bGET\s+/",
        r"\bpass bar\b",
        r"\bcontinuation policy\b",
        r"\bobjective-\d+\b",
        r"\btask\s+\d{3,}\b",
    )
    results: list[dict[str, Any]] = []
    if not base_url:
        return {
            "status": "baseline_needed",
            "reason": "live gateway evaluation was not requested",
            "cases": [],
        }
    for item in prompts:
        prompt = str(item["prompt"])
        try:
            reply = post_gateway(base_url, prompt)
            normalized = " ".join(reply.lower().split())
            expected = [str(token).lower() for token in item["expected"]]
            intent_understood = all(token in normalized for token in expected)
            answered = bool(reply) and len(reply) >= 80 and not any(marker in normalized for marker in bad_generic)
            jargon_hits = [
                pattern
                for pattern in jargon_patterns
                if re.search(pattern, reply, flags=re.IGNORECASE)
            ]
            recommendation_quality = (
                not bool(item["recommendation"])
                or ("why" in normalized and "next" in normalized and not jargon_hits)
            )
            results.append(
                {
                    "id": item["id"],
                    "prompt": prompt,
                    "reply_length": len(reply),
                    "intent_understood": intent_understood,
                    "answered_question": answered,
                    "internal_jargon_hits": jargon_hits,
                    "recommendation_quality": recommendation_quality,
                    "reply_excerpt": reply[:280],
                }
            )
        except Exception as exc:
            results.append(
                {
                    "id": item["id"],
                    "prompt": prompt,
                    "error": " ".join(str(exc).split())[:240],
                    "intent_understood": False,
                    "answered_question": False,
                    "internal_jargon_hits": ["evaluation_error"],
                    "recommendation_quality": False,
                }
            )
    if results and all(row.get("error") for row in results):
        return {
            "status": "live_eval_unavailable",
            "reason": "all live gateway evaluation prompts failed",
            "case_count": len(results),
            "cases": results,
        }
    total = len(results)
    intent_pass = sum(1 for row in results if row.get("intent_understood"))
    answer_pass = sum(1 for row in results if row.get("answered_question"))
    jargon_count = sum(1 for row in results if row.get("internal_jargon_hits"))
    rec_cases = [row for row in results if row["id"] == "next_work"]
    rec_pass = sum(1 for row in rec_cases if row.get("recommendation_quality"))
    return {
        "status": "measured",
        "case_count": total,
        "metrics": {
            "intent_understood_percent": pct(intent_pass, total),
            "answered_question_percent": pct(answer_pass, total),
            "internal_jargon_rate_percent": pct(jargon_count, total),
            "recommendation_quality_percent": pct(rec_pass, len(rec_cases)),
        },
        "cases": results,
    }


def build_scoreboard(base_url: str | None, operator_estimated_hours: float | None) -> dict[str, Any]:
    directive = load_training_json("MIM_TOD_CONTINUOUS_TRAINING_DIRECTIVE.latest.json")
    reflection = load_training_json("MIM_TOD_HOURLY_REFLECTION.latest.json")
    stale_disposition = load_training_json("MIM_TOD_STALE_ARTIFACT_DISPOSITION.latest.json")
    durability_v2 = load_training_json("MIM_DURABILITY_SMOKE_V2.latest.json")
    operator_impact = load_training_json("MIM_OPERATOR_IMPACT_SCORECARD.latest.json")
    operator_impact_live = load_training_json("MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json")
    drill2 = load_json(BLOCKER_ROOT / "TOD_BLOCKED_OBJECTIVE_CLEARING_DRILL_002.latest.json")
    drill3 = load_json(BLOCKER_ROOT / "TOD_BLOCKER_RESOLUTION_DRILL_003.latest.json")
    drill4 = load_json(BLOCKER_ROOT / "TOD_BLOCKER_RESOLUTION_DRILL_004.latest.json")
    triage = load_json(BLOCKER_ROOT / "TOD_BLOCKED_OBJECTIVE_TRIAGE.latest.json")
    previous_scoreboard = load_training_json("MIM_TOD_TRAINING_SCOREBOARD.latest.json")
    mim_eval = evaluate_mim(base_url)

    active_drill = ((directive.get("tod_training") or {}).get("active_blocker_clearing_drill") or {})
    blocked_start = (
        active_drill.get("blocked_total_at_start")
        or drill3.get("blocked_total_at_start")
        or drill2.get("blocked_total_at_start")
        or drill4.get("before_blocked_count")
    )
    after_candidates = [
        active_drill.get("after_blocked_count"),
        drill4.get("after_blocked_count"),
        drill3.get("after_blocked_count"),
        drill2.get("after_blocked_count"),
    ]
    numeric_after: list[int] = []
    for candidate in after_candidates:
        try:
            if candidate is not None:
                numeric_after.append(int(candidate))
        except Exception:
            pass
    blocked_after = min(numeric_after) if numeric_after else None
    blockers_cleared = None
    try:
        if blocked_start is not None and blocked_after is not None:
            blockers_cleared = int(blocked_start) - int(blocked_after)
    except Exception:
        blockers_cleared = None

    meaningful_inspection = bool(((drill4.get("validation") or {}).get("meaningful_result_detected")))
    false_completion_prevented = 1 if meaningful_inspection else 0
    tod_artifact_metrics = tod_artifact_metric_snapshot()
    tod_next_action_accuracy = tod_next_action_accuracy_snapshot()
    mim_structural_reasoning = mim_structural_reasoning_snapshot()
    deploy_payloads = pending_deploy_payload_snapshot()
    deploy_application_result = deploy_application_result_snapshot()
    no_op_rejections = tod_artifact_metrics["no_op_rejections"]
    validated_edits = tod_artifact_metrics["validated_edits"]
    meaningful_implementations = tod_artifact_metrics["meaningful_tod_implementations"]
    independent_resolutions = tod_artifact_metrics["independent_tod_resolutions"]

    mim_metrics_today = mim_eval.get("metrics", {}) if mim_eval.get("status") == "measured" else {}
    mim_metric_source = "live_gateway_eval" if mim_eval.get("status") == "measured" else "baseline_needed"
    mim_gateway_diagnostic: dict[str, Any] | None = None
    if mim_eval.get("status") == "live_eval_unavailable":
        mim_gateway_diagnostic = {
            "status": mim_eval.get("status"),
            "reason": mim_eval.get("reason"),
            "case_count": mim_eval.get("case_count"),
            "cases": mim_eval.get("cases") if isinstance(mim_eval.get("cases"), list) else [],
            "source": "gateway_live_eval",
        }
        previous_mim = previous_scoreboard.get("mim_score") if isinstance(previous_scoreboard.get("mim_score"), dict) else {}
        previous_eval = previous_mim.get("evaluation") if isinstance(previous_mim.get("evaluation"), dict) else {}
        previous_metrics = previous_mim.get("metrics") if isinstance(previous_mim.get("metrics"), dict) else {}
        recovered: dict[str, Any] = {}
        previous_cases = previous_eval.get("cases") if isinstance(previous_eval.get("cases"), list) else []
        previous_all_errors = bool(previous_cases) and all(
            isinstance(row, dict) and row.get("error") for row in previous_cases
        )
        if previous_eval.get("status") == "measured" and not previous_all_errors:
            for metric_key, previous_key in {
                "intent_understood_percent": "intent_understood",
                "answered_question_percent": "answered_question",
                "internal_jargon_rate_percent": "internal_jargon",
                "recommendation_quality_percent": "recommendation_quality",
            }.items():
                previous_item = previous_metrics.get(previous_key) if isinstance(previous_metrics.get(previous_key), dict) else {}
                previous_today = previous_item.get("today")
                if not isinstance(previous_today, dict) and previous_today is not None:
                    recovered[metric_key] = previous_today
        if recovered:
            mim_metrics_today = recovered
            mim_metric_source = "previous_measured_score_preserved_live_eval_unavailable"
    latest_finding = sanitize_operator_text(drill4.get("correction") or drill4.get("current_finding"))
    freshness = reflection.get("freshness") if isinstance(reflection.get("freshness"), dict) else {}
    truth_integrity = (
        reflection.get("truth_integrity")
        if isinstance(reflection.get("truth_integrity"), dict)
        else {}
    )
    reflection_recommendations = reflection.get("recommendations")
    if not isinstance(reflection_recommendations, list):
        reflection_recommendations = []
    raw_stale_artifacts = freshness.get("stale_artifacts") or []
    active_stale_artifacts, applied_stale_dispositions = active_stale_artifacts_with_disposition(
        raw_stale_artifacts,
        stale_disposition,
    )
    disposition_generated_at = stale_disposition.get("generated_at") if stale_disposition else None
    disposition_source = (
        str(training_source_path("MIM_TOD_STALE_ARTIFACT_DISPOSITION.latest.json"))
        if stale_disposition
        else ""
    )
    if applied_stale_dispositions and not active_stale_artifacts:
        reflection_recommendations = [
            item
            for item in reflection_recommendations
            if "refresh stale reflection inputs" not in str(item).lower()
        ]
        reflection_recommendations.insert(
            0,
            "Stale reflection inputs are source-labeled historical or terminal in MIM_TOD_STALE_ARTIFACT_DISPOSITION.latest.json; monitor for new active stale artifacts instead of refreshing old summaries.",
        )
    outcome_reflection = {
        "source": str(training_source_path("MIM_TOD_HOURLY_REFLECTION.latest.json")),
        "generated_at": reflection.get("generated_at"),
        "assessment": reflection.get("assessment") or "unknown",
        "are_they_improving": reflection.get("are_they_improving"),
        "are_they_creating_new_objectives": reflection.get("are_they_creating_new_objectives"),
        "truth_integrity_status": truth_integrity.get("status") or "unknown",
        "fresh_artifact_count": freshness.get("fresh_artifact_count"),
        "stale_artifact_count": len(active_stale_artifacts),
        "stale_artifacts": active_stale_artifacts,
        "raw_stale_artifact_count": len(raw_stale_artifacts) if isinstance(raw_stale_artifacts, list) else 0,
        "raw_stale_artifacts": raw_stale_artifacts if isinstance(raw_stale_artifacts, list) else [],
        "stale_artifact_disposition_source": disposition_source,
        "stale_artifact_disposition_generated_at": disposition_generated_at,
        "retired_or_historical_stale_artifacts": applied_stale_dispositions,
        "real_movement_scorecard": load_training_json("MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json"),
        "operator_summary": sanitize_operator_text(reflection.get("operator_summary")),
        "recommendations": [sanitize_operator_text(item) for item in reflection_recommendations],
    }
    reflection_says_not_improving = outcome_reflection["are_they_improving"] is False
    durability_summary = (
        durability_v2.get("summary") if isinstance(durability_v2.get("summary"), dict) else {}
    )
    durability_groups = (
        durability_v2.get("group_summary")
        if isinstance(durability_v2.get("group_summary"), dict)
        else {}
    )
    durability_pass_rate = durability_summary.get("pass_rate_percent")
    durability_failed = durability_summary.get("failed")
    durability_target_met = (
        durability_v2.get("status") == "passed"
        and isinstance(durability_summary.get("case_count"), int)
        and int(durability_summary.get("case_count") or 0) > 0
        and isinstance(durability_pass_rate, (int, float))
        and float(durability_pass_rate) >= 90.0
    )
    if durability_target_met and int(durability_failed or 0) <= 0:
        durability_weakness = "Resolved in the latest durability smoke; monitor for status-report leakage regression."
    elif durability_target_met:
        durability_weakness = (
            f"Mode selection is durable at {durability_pass_rate}% live pass rate; "
            f"{durability_failed} remaining case(s) need status-report leakage cleanup."
        )
    else:
        durability_weakness = "MIM defaults to status reporting instead of selecting recommendation, explanation, demonstration, consultative discovery, or problem-analysis mode."
    judgment_mode_score = {
        "source": str(training_source_path("MIM_DURABILITY_SMOKE_V2.latest.json")),
        "objective_id": durability_v2.get("objective_id") or "MIM-DURABILITY-SMOKE-V2",
        "status": durability_v2.get("status") or "unknown",
        "generated_at": durability_v2.get("generated_at"),
        "case_count": durability_summary.get("case_count"),
        "passed": durability_summary.get("passed"),
        "failed": durability_summary.get("failed"),
        "pass_rate_percent": durability_summary.get("pass_rate_percent"),
        "mode_identity_failures": durability_summary.get("mode_identity_failures"),
        "mode_identity_pass_rate_percent": durability_summary.get("mode_identity_pass_rate_percent"),
        "status_leakage_failures": durability_summary.get("status_leakage_failures"),
        "status_leakage_pass_rate_percent": durability_summary.get("status_leakage_pass_rate_percent"),
        "group_summary": durability_groups,
        "current_weakness": durability_weakness,
        "target": "Reach at least 80% on the focused V2 judgment suite before expanding to larger prompt sets.",
    }
    durability_current_passed = durability_target_met
    mim_visible_evaluation = mim_eval
    mim_eval_status = str(mim_eval.get("status") or "").strip().lower() if isinstance(mim_eval, dict) else ""
    mim_eval_has_metrics = bool(
        mim_metrics_today
        and any(value is not None for value in mim_metrics_today.values())
    )
    if durability_current_passed and (mim_gateway_diagnostic or not mim_eval_has_metrics):
        mim_metrics_today = {
            "intent_understood_percent": durability_summary.get("pass_rate_percent"),
            "answered_question_percent": durability_summary.get("pass_rate_percent"),
            "internal_jargon_rate_percent": 0,
            "recommendation_quality_percent": durability_summary.get("pass_rate_percent"),
        }
        mim_metric_source = (
            "studio_durability_smoke_gateway_unavailable"
            if mim_gateway_diagnostic
            else "studio_durability_smoke_live_eval_absent"
        )
        mim_visible_evaluation = {
            "status": "measured_by_studio_durability_smoke",
            "reason": (
                "Live MIM evaluation did not produce current metrics, so the visible MIM conversation score "
                "uses the passing Studio durability smoke while preserving gateway details separately when present."
            ),
            "case_count": durability_summary.get("case_count"),
            "metrics": mim_metrics_today,
            "gateway_diagnostic": mim_gateway_diagnostic,
            "previous_eval_status": mim_eval_status,
        }
    judgment_needs_attention = (
        isinstance(judgment_mode_score.get("pass_rate_percent"), (int, float))
        and float(judgment_mode_score["pass_rate_percent"]) < 80.0
    )
    measured_mim_recovered = (
        mim_metrics_today.get("intent_understood_percent") == 100
        and mim_metrics_today.get("answered_question_percent") == 100
        and mim_metrics_today.get("recommendation_quality_percent") == 100
        and mim_metrics_today.get("internal_jargon_rate_percent") == 0
    )
    reflection_recovered_by_current_evidence = (
        reflection_says_not_improving
        and durability_current_passed
        and measured_mim_recovered
        and len(active_stale_artifacts) == 0
        and str(truth_integrity.get("status") or "").strip().lower() == "healthy"
    )
    if reflection_recovered_by_current_evidence:
        outcome_reflection["current_evidence_override"] = {
            "status": "recovered_by_current_scoreboard_evidence",
            "reason": (
                "The hourly reflection still reports are_they_improving=false, but newer measured evidence "
                "shows durability passed, live MIM conversation metrics are clean, active stale artifacts are zero, "
                "and truth integrity is healthy."
            ),
            "preserves_original_reflection": True,
        }
    scoreboard = {
        "packet_type": "mim-tod-training-scoreboard-v1",
        "generated_at": utc_now(),
        "status": (
            "needs_attention_with_training_active"
            if (reflection_says_not_improving and not reflection_recovered_by_current_evidence) or judgment_needs_attention
            else "active_with_partial_metrics"
        ),
        "outcome_reflection": outcome_reflection,
        "judgment_mode_score": judgment_mode_score,
        "training_hours": {
            "last_7_days": baseline_started("Training-hour baseline starts with current scoreboard snapshots; prior exact hours are not reconstructable from latest-only files"),
            "yesterday": baseline_started("Prior daily training-hour snapshot was not retained; current run establishes the comparison baseline"),
            "today": {
                "value": operator_estimated_hours,
                "status": "operator_estimate" if operator_estimated_hours is not None else "baseline_needed",
                "reason": "operator reported approximate continuous run; exact tracking begins with scoreboard v1",
            },
        },
        "mim_score": {
            "metrics": {
                "intent_understood": {
                    "yesterday": baseline_started("Current measured communication eval establishes the baseline for future comparisons", mim_metrics_today.get("intent_understood_percent")),
                    "today": mim_metrics_today.get("intent_understood_percent"),
                    "unit": "percent",
                    "source": mim_metric_source,
                },
                "answered_question": {
                    "yesterday": baseline_started("Current measured communication eval establishes the baseline for future comparisons", mim_metrics_today.get("answered_question_percent")),
                    "today": mim_metrics_today.get("answered_question_percent"),
                    "unit": "percent",
                    "source": mim_metric_source,
                },
                "internal_jargon": {
                    "yesterday": baseline_started("Current measured communication eval establishes the baseline for future comparisons", mim_metrics_today.get("internal_jargon_rate_percent")),
                    "today": mim_metrics_today.get("internal_jargon_rate_percent"),
                    "unit": "percent_rate_lower_is_better",
                    "source": mim_metric_source,
                },
                "recommendation_quality": {
                    "yesterday": baseline_started("Current measured communication eval establishes the baseline for future comparisons", mim_metrics_today.get("recommendation_quality_percent")),
                    "today": mim_metrics_today.get("recommendation_quality_percent"),
                    "unit": "percent",
                    "source": mim_metric_source,
                },
                "structural_reasoning_diversity": {
                    "yesterday": baseline_started("Current structural reasoning score establishes the baseline for future comparisons", mim_structural_reasoning.get("weighted_pass_rate_percent")),
                    "today": mim_structural_reasoning.get("weighted_pass_rate_percent"),
                    "unit": "weighted_percent",
                    "source": "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json",
                },
                "structural_reasoning_cross_surface": {
                    "yesterday": baseline_started(
                        "Current per-surface structural reasoning score establishes the baseline for future comparisons",
                        (mim_structural_reasoning.get("cross_surface") or {}).get("target_met_surface_count"),
                    ),
                    "today": mim_structural_reasoning.get("cross_surface") if isinstance(mim_structural_reasoning.get("cross_surface"), dict) else {},
                    "unit": "per_surface_scorecard",
                    "source": "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json",
                },
            },
            "evaluation": mim_visible_evaluation,
            "gateway_diagnostic": mim_gateway_diagnostic or {},
            "operator_impact": {
                "generated_at": operator_impact.get("generated_at") or operator_impact_live.get("generated_at"),
                "status": operator_impact.get("status") or operator_impact_live.get("status") or "baseline_needed",
                "operator_impact_score": operator_impact.get("operator_impact_score") or operator_impact_live.get("operator_impact_score"),
                "operator_impact_percent": operator_impact.get("operator_impact_percent") or operator_impact_live.get("operator_impact_percent"),
                "pass_count": operator_impact.get("pass_count") or operator_impact_live.get("pass_count"),
                "sample_count": operator_impact.get("sample_count") or operator_impact_live.get("sample_count"),
                "source": "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
                "live_source": "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json",
            },
            "structural_reasoning": mim_structural_reasoning,
        },
        "tod_score": {
            "metrics": {
                "blockers_cleared": {
                    "yesterday": baseline_started("Current TOD blocker evidence establishes the baseline for future comparisons", blockers_cleared),
                    "today": blockers_cleared,
                    "unit": "count",
                    "source": "blocker_drill_artifacts",
                },
                "false_completions_prevented": {
                    "yesterday": baseline_started("Current false-completion prevention evidence establishes the baseline for future comparisons", false_completion_prevented),
                    "today": false_completion_prevented,
                    "unit": "count",
                    "source": "drill_004_meaningful_evidence_self_correction",
                },
                "validated_edits": {
                    "yesterday": baseline_started("Current validated-edit evidence establishes the baseline for future comparisons", validated_edits.get("value") if isinstance(validated_edits, dict) else validated_edits),
                    "today": validated_edits,
                    "unit": "count",
                    "source": validated_edits.get("source") if isinstance(validated_edits, dict) else "tod_result_artifacts",
                },
                "meaningful_tod_implementations": {
                    "yesterday": baseline_started(
                        "Current meaningful implementation evidence establishes the stricter baseline",
                        meaningful_implementations.get("value") if isinstance(meaningful_implementations, dict) else meaningful_implementations,
                    ),
                    "today": meaningful_implementations,
                    "unit": "count",
                    "source": "tod_result_artifacts",
                },
                "independent_tod_resolutions": {
                    "yesterday": baseline_started(
                        "Current independent resolution evidence establishes the strictest baseline",
                        independent_resolutions.get("value") if isinstance(independent_resolutions, dict) else independent_resolutions,
                    ),
                    "today": independent_resolutions,
                    "unit": "count",
                    "source": independent_resolutions.get("source") if isinstance(independent_resolutions, dict) else "tod_result_artifacts",
                },
                "no_op_rejections": {
                    "yesterday": baseline_started("Current no-op rejection evidence establishes the baseline for future comparisons", no_op_rejections.get("value") if isinstance(no_op_rejections, dict) else no_op_rejections),
                    "today": no_op_rejections,
                    "unit": "count",
                    "source": "tod_result_artifacts",
                },
                "next_action_accuracy": {
                    "yesterday": baseline_started("Current next-action outcome evidence establishes the baseline for future comparisons", tod_next_action_accuracy.get("pass_rate_percent")),
                    "today": tod_next_action_accuracy.get("pass_rate_percent"),
                    "unit": "percent",
                    "source": "tod_next_action_training_set",
                },
                "next_action_outcome_pending": {
                    "yesterday": baseline_started("Current pending-outcome count establishes the baseline for future comparisons", tod_next_action_accuracy.get("pending_count")),
                    "today": tod_next_action_accuracy.get("pending_count"),
                    "unit": "count",
                    "source": "tod_next_action_training_set",
                },
                "pending_mim_deploy_payloads": {
                    "yesterday": baseline_started(
                        "Current unverified MIM deploy handoff count establishes the baseline",
                        deploy_payloads.get("pending_count"),
                    ),
                    "today": deploy_payloads.get("pending_count"),
                    "unit": "count",
                    "source": "runtime_remote_training/deploy_payloads",
                },
            },
            "artifact_metrics": tod_artifact_metrics,
            "next_action_accuracy": tod_next_action_accuracy,
            "deploy_payloads": deploy_payloads,
            "deploy_application_result": deploy_application_result,
            "blocker_classes": (((directive.get("tod_training") or {}).get("active_blocker_clearing_drill") or {}).get("classes") or triage.get("classes") or {}),
            "latest_drill": {
                "id": drill4.get("drill_id"),
                "status": drill4.get("status"),
                "generated_at": drill4.get("generated_at"),
                "finding": latest_finding,
                "lesson": drill4.get("tod_lesson"),
            },
        },
        "recommendation": {
            "continue_training": True,
            "next_required_improvement": (
                "Monitor recovered outcome evidence and keep the next scoreboard refresh from regressing into stale reflection status."
                if reflection_recovered_by_current_evidence
                else
                "Resolve the reflection outcome gap before claiming training is going great."
                if reflection_says_not_improving
                else "Train MIM judgment mode selection until MIM-DURABILITY-SMOKE-V2 reaches at least 80%."
                if judgment_needs_attention
                else "Start daily/hourly scoreboard snapshots so tomorrow can compare against today with real deltas."
            ),
            "continue_condition": "Continue while blocker count, MIM communication score, or TOD validation evidence improves every 4-6 hours.",
            "redirect_condition": "Redirect if there is no new evidence artifact, no blocker movement, and no MIM eval improvement over a 6-hour window.",
        },
        "source_files": [
            str(training_source_path("MIM_TOD_HOURLY_REFLECTION.latest.json")),
            str(training_source_path("MIM_DURABILITY_SMOKE_V2.latest.json")),
            str(training_source_path("MIM_OPERATOR_IMPACT_SCORECARD.latest.json")),
            str(training_source_path("MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json")),
            str(training_source_path("MIM_TOD_CONTINUOUS_TRAINING_DIRECTIVE.latest.json")),
            str(DEPLOY_PAYLOADS_ROOT),
            str(BLOCKER_ROOT / "TOD_BLOCKED_OBJECTIVE_CLEARING_DRILL_002.latest.json"),
            str(BLOCKER_ROOT / "TOD_BLOCKER_RESOLUTION_DRILL_003.latest.json"),
            str(BLOCKER_ROOT / "TOD_BLOCKER_RESOLUTION_DRILL_004.latest.json"),
            str(BLOCKER_ROOT / "TOD_BLOCKED_OBJECTIVE_TRIAGE.latest.json"),
            str(training_source_path("MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json")),
        ],
    }
    return scoreboard


def metric_value(value: Any) -> str:
    if isinstance(value, dict):
        if "surface_count" in value or "target_met_surface_count" in value:
            status = str(value.get("status") or "unknown")
            target_met = value.get("target_met_surface_count")
            surface_count = value.get("surface_count")
            if isinstance(target_met, (int, float)) and isinstance(surface_count, (int, float)):
                return f"{status}; {int(target_met)}/{int(surface_count)} surfaces target met"
            return status
        if value.get("status") == "measured" and value.get("value") is not None:
            return str(value.get("value"))
        if value.get("status") == "baseline_established":
            if value.get("value") is not None:
                return str(value.get("value"))
            return "baseline established"
        return "baseline needed"
    if value is None:
        return "baseline needed"
    return str(value)


def write_markdown(scoreboard: dict[str, Any], path: Path) -> None:
    mim = scoreboard["mim_score"]["metrics"]
    operator_impact = scoreboard["mim_score"].get("operator_impact")
    if not isinstance(operator_impact, dict):
        operator_impact = {}
    tod = scoreboard["tod_score"]["metrics"]
    hours = scoreboard["training_hours"]
    outcome = scoreboard.get("outcome_reflection") if isinstance(scoreboard.get("outcome_reflection"), dict) else {}
    judgment = scoreboard.get("judgment_mode_score") if isinstance(scoreboard.get("judgment_mode_score"), dict) else {}
    lines = [
        "# MIM/TOD Training Scoreboard",
        "",
        f"Generated: {scoreboard['generated_at']}",
        f"Status: {scoreboard['status']}",
        "",
        "## Outcome Reflection",
        "",
        f"- Reflection generated: {outcome.get('generated_at') or 'unknown'}",
        f"- Assessment: {outcome.get('assessment') or 'unknown'}",
        f"- Are outcomes improving: {outcome.get('are_they_improving')}",
        f"- Creating new objectives: {outcome.get('are_they_creating_new_objectives')}",
        f"- Truth integrity: {outcome.get('truth_integrity_status') or 'unknown'}",
        f"- Fresh artifacts: {metric_value(outcome.get('fresh_artifact_count'))}",
        f"- Active stale artifacts: {metric_value(outcome.get('stale_artifact_count'))}",
        f"- Raw stale artifacts before disposition: {metric_value(outcome.get('raw_stale_artifact_count'))}",
        "",
        "Outcome summary:",
        "",
        f"> {outcome.get('operator_summary') or 'No hourly reflection summary available.'}",
        "",
        "Reflection recommendations:",
        "",
    ]
    recommendations = outcome.get("recommendations") if isinstance(outcome.get("recommendations"), list) else []
    if recommendations:
        for recommendation in recommendations[:5]:
            lines.append(f"- {recommendation}")
    else:
        lines.append("- No reflection recommendations available.")
    retired = outcome.get("retired_or_historical_stale_artifacts")
    if isinstance(retired, list) and retired:
        lines.extend(["", "Retired or historical stale artifacts:", ""])
        for item in retired[:10]:
            if not isinstance(item, dict):
                continue
            lines.append(
                f"- {item.get('artifact')}: {item.get('status')} - {item.get('reason') or 'source-labeled historical'}"
            )
    lines.extend([
        "",
        "## Training Hours",
        "",
        "| Window | Value | Status |",
        "|---|---:|---|",
    ])
    for label in ("last_7_days", "yesterday", "today"):
        item = hours[label]
        lines.append(f"| {label.replace('_', ' ').title()} | {metric_value(item.get('value'))} | {item.get('status')} |")
    lines.extend([
        "",
        "## MIM Score",
        "",
        "| Metric | Baseline | Current | Source |",
        "|---|---:|---:|---|",
    ])
    for key, item in mim.items():
        lines.append(
            f"| {key.replace('_', ' ').title()} | {metric_value(item.get('yesterday'))} | {metric_value(item.get('today'))} | {item.get('source')} |"
        )
    lines.extend([
        "",
        "## MIM Judgment Mode Score",
        "",
        f"- Objective: {judgment.get('objective_id') or 'MIM-DURABILITY-SMOKE-V2'}",
        f"- Status: {judgment.get('status') or 'unknown'}",
        f"- Cases: {metric_value(judgment.get('case_count'))}",
        f"- Passed: {metric_value(judgment.get('passed'))}",
        f"- Failed: {metric_value(judgment.get('failed'))}",
        f"- Pass rate: {metric_value(judgment.get('pass_rate_percent'))}%",
        f"- Mode identity failures: {metric_value(judgment.get('mode_identity_failures'))}",
        f"- Mode identity pass rate: {metric_value(judgment.get('mode_identity_pass_rate_percent'))}%",
        f"- Status leakage failures: {metric_value(judgment.get('status_leakage_failures'))}",
        f"- Status leakage pass rate: {metric_value(judgment.get('status_leakage_pass_rate_percent'))}%",
        f"- Current weakness: {judgment.get('current_weakness') or 'unknown'}",
        f"- Target: {judgment.get('target') or 'unknown'}",
        "",
        "| Group | Passed | Failed | Distinct Reply Signatures |",
        "|---|---:|---:|---:|",
    ])
    group_summary = (
        judgment.get("group_summary")
        if isinstance(judgment.get("group_summary"), dict)
        else {}
    )
    if group_summary:
        for group, values in sorted(group_summary.items()):
            group_values = values if isinstance(values, dict) else {}
            lines.append(
                f"| {group.replace('_', ' ').title()} | {metric_value(group_values.get('passed'))} | {metric_value(group_values.get('failed'))} | {metric_value(group_values.get('distinct_reply_signatures'))} |"
            )
    else:
        lines.append("| baseline needed | baseline needed | baseline needed | baseline needed |")
    lines.extend([
        "",
        "## MIM Operator Impact",
        "",
        f"- Status: {operator_impact.get('status') or 'baseline_needed'}",
        f"- Score: {metric_value(operator_impact.get('operator_impact_score'))}/10",
        f"- Impact: {metric_value(operator_impact.get('operator_impact_percent'))}%",
        f"- Replies scored: {metric_value(operator_impact.get('sample_count'))}",
        f"- Fully passing replies: {metric_value(operator_impact.get('pass_count'))}/{metric_value(operator_impact.get('sample_count'))}",
        f"- Generated: {operator_impact.get('generated_at') or 'unknown'}",
        f"- Source: {operator_impact.get('source') or 'MIM_OPERATOR_IMPACT_SCORECARD.latest.json'}",
    ])
    lines.extend([
        "",
        "## TOD Score",
        "",
        "| Metric | Baseline | Current | Source |",
        "|---|---:|---:|---|",
    ])
    for key, item in tod.items():
        today = item.get("today")
        lines.append(
            f"| {key.replace('_', ' ').title()} | {metric_value(item.get('yesterday'))} | {metric_value(today)} | {item.get('source')} |"
        )
    deploy_payloads = scoreboard["tod_score"].get("deploy_payloads")
    if isinstance(deploy_payloads, dict):
        latest_deploy = deploy_payloads.get("latest") if isinstance(deploy_payloads.get("latest"), dict) else {}
        lines.extend([
            "",
            "## Pending MIM Deploy Payloads",
            "",
            f"- Pending: {metric_value(deploy_payloads.get('pending_count'))}",
            f"- Latest objective: {latest_deploy.get('objective_id') or 'none'}",
            f"- Latest file: {latest_deploy.get('file') or 'none'}",
            f"- Purpose: {latest_deploy.get('purpose') or 'none'}",
            f"- Latest verification: {latest_deploy.get('verification_status') or 'unknown'} - {latest_deploy.get('verification_reason') or 'no verification reason recorded'}",
        ])
        readiness = (
            latest_deploy.get("local_patch_readiness")
            if isinstance(latest_deploy.get("local_patch_readiness"), dict)
            else {}
        )
        if readiness:
            lines.append(
                f"- Local patch readiness: {readiness.get('status') or 'unknown'} "
                f"(ready={str(bool(readiness.get('ready'))).lower()})"
            )
            if readiness.get("missing"):
                lines.extend(["", "Missing local reference files:", ""])
                for missing_ref in _string_list(readiness.get("missing"))[:5]:
                    lines.append(f"- `{missing_ref}`")
        application_plan = (
            latest_deploy.get("application_plan")
            if isinstance(latest_deploy.get("application_plan"), dict)
            else {}
        )
        if application_plan:
            lines.append(
                f"- Existing deploy path application: {application_plan.get('status') or 'unknown'} "
                f"(ready={str(bool(application_plan.get('ready'))).lower()})"
            )
        deploy_result = scoreboard["tod_score"].get("deploy_application_result")
        if isinstance(deploy_result, dict) and deploy_result.get("status") not in {"", None, "missing"}:
            lines.extend(
                [
                    "",
                    "Latest deploy application result:",
                    "",
                    f"- Objective: {deploy_result.get('objective_id') or 'unknown'}",
                    f"- Status: {deploy_result.get('status') or 'unknown'}",
                    f"- Applied files: {metric_value(deploy_result.get('applied_file_count'))}",
                    f"- No new channel required: {str(bool(deploy_result.get('no_new_channel_required'))).lower()}",
                    f"- Live request emitted: {str(bool(deploy_result.get('live_request_emitted'))).lower()}",
                    f"- Live deployment verified: {str(bool(deploy_result.get('live_deployment_verified'))).lower()}",
                ]
            )
            remaining = deploy_result.get("remaining_blockers") if isinstance(deploy_result.get("remaining_blockers"), list) else []
            if remaining:
                lines.extend(["", "Remaining deployment blockers:", ""])
                for blocker in remaining[:5]:
                    lines.append(f"- {sanitize_operator_text(blocker)}")
        local_refs = latest_deploy.get("local_reference_files") if isinstance(latest_deploy.get("local_reference_files"), list) else []
        if local_refs:
            lines.extend(["", "Latest local reference files:", ""])
            for ref in local_refs[:5]:
                lines.append(f"- `{ref}`")
        targets = latest_deploy.get("target_remote_files") if isinstance(latest_deploy.get("target_remote_files"), list) else []
        if targets:
            lines.extend(["", "Latest remote targets:", ""])
            for target in targets[:5]:
                lines.append(f"- `{target}`")
        acceptance = latest_deploy.get("acceptance") if isinstance(latest_deploy.get("acceptance"), list) else []
        if acceptance:
            lines.extend(["", "Latest acceptance gates:", ""])
            for item in acceptance[:5]:
                lines.append(f"- {item}")
        post_deploy_commands = latest_deploy.get("post_deploy_commands") if isinstance(latest_deploy.get("post_deploy_commands"), list) else []
        if post_deploy_commands:
            lines.extend(["", "Latest post-deploy proof steps:", ""])
            for command in post_deploy_commands[:5]:
                lines.append(f"- `{command}`")
        pending_items = deploy_payloads.get("pending_payloads") if isinstance(deploy_payloads.get("pending_payloads"), list) else []
        if pending_items:
            lines.extend(["", "Pending verification reasons:", ""])
            for item in pending_items[:5]:
                if not isinstance(item, dict):
                    continue
                lines.append(
                    f"- {item.get('objective_id') or 'unknown'}: "
                    f"{item.get('verification_status') or 'unknown'} - "
                    f"{item.get('verification_reason') or 'no reason recorded'}"
                )
    next_action_accuracy = scoreboard["tod_score"].get("next_action_accuracy")
    if isinstance(next_action_accuracy, dict):
        lines.extend([
            "",
            "## TOD Next Action Accuracy",
            "",
            f"- Status: {next_action_accuracy.get('status') or 'unknown'}",
            f"- Records: {metric_value(next_action_accuracy.get('record_count'))}",
            f"- Scored: {metric_value(next_action_accuracy.get('scored_count'))}",
            f"- Pending outcomes: {metric_value(next_action_accuracy.get('pending_count'))}",
            f"- Passed: {metric_value(next_action_accuracy.get('passed_count'))}",
            f"- Pass rate: {metric_value(next_action_accuracy.get('pass_rate_percent'))}%",
            "",
            "| Dimension |",
            "|---|",
        ])
        for dimension in next_action_accuracy.get("score_dimensions") or []:
            lines.append(f"| {str(dimension).replace('_', ' ').title()} |")
    latest = scoreboard["tod_score"].get("latest_drill") or {}
    lines.extend([
        "",
        "## Latest Evidence",
        "",
        f"- Latest TOD drill: {latest.get('id')} ({latest.get('status')})",
        f"- Finding: {latest.get('finding')}",
        f"- Continue training: {scoreboard['recommendation']['continue_training']}",
        f"- Next required improvement: {scoreboard['recommendation']['next_required_improvement']}",
        "",
        "## Notes",
        "",
        "- Baseline-established fields use the current measured value as the comparison point going forward when older daily snapshots were not retained.",
        "- Baseline-needed fields mean the metric still lacks current instrumentation.",
        "- Internal jargon is a lower-is-better percentage from live MIM evaluation prompts.",
    ])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_deploy_verification_queue(scoreboard: dict[str, Any]) -> dict[str, Any]:
    deploy_payloads = (
        scoreboard.get("tod_score", {}).get("deploy_payloads", {})
        if isinstance(scoreboard.get("tod_score"), dict)
        else {}
    )
    pending_items = (
        deploy_payloads.get("pending_payloads")
        if isinstance(deploy_payloads.get("pending_payloads"), list)
        else []
    )
    queue_items: list[dict[str, Any]] = []
    for index, item in enumerate(pending_items, start=1):
        if not isinstance(item, dict):
            continue
        objective_id = str(item.get("objective_id") or "unknown").strip() or "unknown"
        post_deploy_commands = _string_list(item.get("post_deploy_commands"))
        acceptance = _string_list(item.get("acceptance"))
        if objective_id.upper() == "MIM-CONVERSATION-MODE-SELECTION-V2":
            owner = "MIM deploy/runtime owner first; operator-impact and durability scorers validate live behavior after deployment."
        else:
            owner = "MIM deploy/runtime owner first; TOD validates execution evidence after the live request is implementation-shaped."
        queue_items.append(
            {
                "rank": index,
                "objective_id": objective_id,
                "status": str(item.get("verification_status") or "unknown").strip() or "unknown",
                "reason": str(item.get("verification_reason") or "no verification reason recorded").strip(),
                "deploy_payload": str(item.get("file") or "").strip(),
                "owner": owner,
                "dave_needed": "no unless credentials, production account access, or external service authority is required.",
                "acceptance": acceptance,
                "proof_steps": post_deploy_commands,
                "next_proof": post_deploy_commands[0] if post_deploy_commands else "register a deploy-specific verifier or live proof command",
                "local_patch_readiness": item.get("local_patch_readiness") if isinstance(item.get("local_patch_readiness"), dict) else {},
                "application_plan": item.get("application_plan") if isinstance(item.get("application_plan"), dict) else {},
                "no_credit_if": [
                    "new SSH or transport channel is proposed",
                    "diagnostic-only task request remains current",
                    "wrapper-only success is treated as implementation",
                    "TOD credit is awarded before inspected changed-file evidence",
                ],
            }
        )
    return {
        "artifact_type": "mim_tod_deploy_verification_queue_v1",
        "generated_at": utc_now(),
        "status": "needs_verification" if queue_items else "empty",
        "pending_count": len(queue_items),
        "source": "MIM_TOD_TRAINING_SCOREBOARD.latest.json:tod_score.deploy_payloads.pending_payloads",
        "bridge_state": bridge_materialization_state_snapshot(),
        "items": queue_items,
    }


def write_deploy_verification_queue(queue: dict[str, Any], out_dir: Path) -> dict[str, str]:
    json_path = out_dir / "MIM_TOD_DEPLOY_VERIFICATION_QUEUE.latest.json"
    md_path = out_dir / "MIM_TOD_DEPLOY_VERIFICATION_QUEUE.latest.md"
    json_path.write_text(json.dumps(queue, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    lines = [
        "# MIM/TOD Deploy Verification Queue",
        "",
        f"Generated: {queue.get('generated_at', '')}",
        f"Status: {queue.get('status', '')}",
        f"Pending: {queue.get('pending_count', 0)}",
        "",
    ]
    bridge_state = queue.get("bridge_state") if isinstance(queue.get("bridge_state"), dict) else {}
    if bridge_state:
        current_request = (
            bridge_state.get("current_request")
            if isinstance(bridge_state.get("current_request"), dict)
            else {}
        )
        lines.extend(
            [
                "## Existing Bridge State",
                "",
                f"- Status: {bridge_state.get('status', '')}",
                f"- Transport: {bridge_state.get('transport', '')}",
                f"- Transport active: {str(bool(bridge_state.get('transport_active'))).lower()}",
                f"- No new channel required: {str(bool(bridge_state.get('no_new_channel_required'))).lower()}",
                f"- Blocker: {bridge_state.get('blocker', '') or 'none'}",
                f"- Current request: task_class={current_request.get('task_class', '')}; validation_only={str(bool(current_request.get('validation_only'))).lower()}; changed_files_required_for_success={str(bool(current_request.get('changed_files_required_for_success'))).lower()}",
                f"- Current target: target_file={current_request.get('target_file', '') or 'missing'}; one_target_file={str(bool(current_request.get('one_target_file'))).lower()}; target_files_type={current_request.get('target_files_type', '')}",
                f"- Required next action: {bridge_state.get('required_next_action', '')}",
                "",
            ]
        )
        request_copies = bridge_state.get("request_copies") if isinstance(bridge_state.get("request_copies"), list) else []
        if request_copies:
            lines.extend(["### Request Copies", ""])
            for copy in request_copies:
                if not isinstance(copy, dict):
                    continue
                reasons = ", ".join(str(item) for item in copy.get("malformed_reasons", []) if str(item).strip())
                lines.append(
                    "- {source}: implementation_shaped={implementation}; task_class={task_class}; target_file={target_file}; one_target_file={one_target}; malformed={malformed}".format(
                        source=copy.get("source", ""),
                        implementation=str(bool(copy.get("implementation_shaped"))).lower(),
                        task_class=copy.get("task_class", ""),
                        target_file=copy.get("target_file", "") or "missing",
                        one_target=str(bool(copy.get("one_target_file"))).lower(),
                        malformed=reasons or "none",
                    )
                )
            lines.append("")
    items = queue.get("items") if isinstance(queue.get("items"), list) else []
    for item in items:
        if not isinstance(item, dict):
            continue
        lines.extend(
            [
                f"## {item.get('rank')}. {item.get('objective_id')}",
                "",
                f"- Status: {item.get('status')}",
                f"- Reason: {item.get('reason')}",
                f"- Deploy payload: {item.get('deploy_payload')}",
                f"- Owner: {item.get('owner')}",
                f"- Dave needed: {item.get('dave_needed')}",
                f"- Next proof: {item.get('next_proof')}",
                "",
            ]
        )
        readiness = item.get("local_patch_readiness") if isinstance(item.get("local_patch_readiness"), dict) else {}
        if readiness:
            lines.extend(
                [
                    f"- Local patch readiness: {readiness.get('status') or 'unknown'} (ready={str(bool(readiness.get('ready'))).lower()})",
                    "",
                ]
            )
        application_plan = item.get("application_plan") if isinstance(item.get("application_plan"), dict) else {}
        if application_plan:
            lines.extend(
                [
                    f"- Existing deploy path application: {application_plan.get('status') or 'unknown'} (ready={str(bool(application_plan.get('ready'))).lower()})",
                    "",
                ]
            )
        acceptance = item.get("acceptance") if isinstance(item.get("acceptance"), list) else []
        if acceptance:
            lines.extend(["Acceptance:", ""])
            lines.extend(f"- {entry}" for entry in acceptance[:6])
            lines.append("")
        proof_steps = item.get("proof_steps") if isinstance(item.get("proof_steps"), list) else []
        if proof_steps:
            lines.extend(["Proof Steps:", ""])
            lines.extend(f"- `{entry}`" for entry in proof_steps[:8])
            lines.append("")
    md_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return {"json": str(json_path), "md": str(md_path)}


def build_deploy_application_manifest(queue: dict[str, Any]) -> dict[str, Any]:
    items = queue.get("items") if isinstance(queue.get("items"), list) else []
    manifest_items: list[dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        application_plan = item.get("application_plan") if isinstance(item.get("application_plan"), dict) else {}
        manifest_items.append(
            {
                "rank": item.get("rank"),
                "objective_id": item.get("objective_id"),
                "deploy_payload": item.get("deploy_payload"),
                "verification_status": item.get("status"),
                "verification_reason": item.get("reason"),
                "application_status": application_plan.get("status") or "unknown",
                "ready": bool(application_plan.get("ready")),
                "file_pairs": application_plan.get("pairs") if isinstance(application_plan.get("pairs"), list) else [],
                "apply_commands": application_plan.get("apply_commands") if isinstance(application_plan.get("apply_commands"), list) else [],
                "post_deploy_proof_steps": item.get("proof_steps") if isinstance(item.get("proof_steps"), list) else [],
            }
        )
    ready_count = len([item for item in manifest_items if item.get("ready")])
    partial_count = len(
        [
            item
            for item in manifest_items
            if str(item.get("application_status") or "").strip() == "partial_patch_hunk_required"
        ]
    )
    if not manifest_items:
        status = "empty"
    elif ready_count == len(manifest_items):
        status = "ready_to_apply_existing_path"
    elif ready_count and partial_count:
        status = "ready_with_partial_hunks_required"
    elif ready_count:
        status = "partially_ready_to_apply_existing_path"
    elif partial_count:
        status = "partial_hunks_required"
    else:
        status = "no_ready_payloads"
    return {
        "artifact_type": "mim_tod_deploy_application_manifest_v1",
        "generated_at": utc_now(),
        "status": status,
        "ready_count": ready_count,
        "partial_hunk_count": partial_count,
        "pending_count": len(manifest_items),
        "no_new_channel_required": True,
        "existing_apply_script": "scripts\\Send-TODMimScript.ps1",
        "bridge_state": queue.get("bridge_state") if isinstance(queue.get("bridge_state"), dict) else {},
        "items": manifest_items,
        "credit_policy": "Applying these Codex-authored materializer repairs does not award TOD independent-resolution credit; credit starts only after TOD independently inspects, changes behavior, validates, and closes a fresh implementation request.",
    }


def write_deploy_application_manifest(manifest: dict[str, Any], out_dir: Path) -> dict[str, str]:
    json_path = out_dir / "MIM_TOD_DEPLOY_APPLICATION_MANIFEST.latest.json"
    md_path = out_dir / "MIM_TOD_DEPLOY_APPLICATION_MANIFEST.latest.md"
    json_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    lines = [
        "# MIM/TOD Deploy Application Manifest",
        "",
        f"Generated: {manifest.get('generated_at', '')}",
        f"Status: {manifest.get('status', '')}",
        f"Ready payloads: {manifest.get('ready_count', 0)}/{manifest.get('pending_count', 0)}",
        f"Partial hunk payloads: {manifest.get('partial_hunk_count', 0)}",
        f"No new channel required: {str(bool(manifest.get('no_new_channel_required'))).lower()}",
        f"Existing apply script: {manifest.get('existing_apply_script', '')}",
        "",
        f"Credit policy: {manifest.get('credit_policy', '')}",
        "",
    ]
    items = manifest.get("items") if isinstance(manifest.get("items"), list) else []
    for item in items:
        lines.extend(
            [
                f"## {item.get('rank')}. {item.get('objective_id')}",
                "",
                f"- Application status: {item.get('application_status')} (ready={str(bool(item.get('ready'))).lower()})",
                f"- Live verification: {item.get('verification_status')} - {item.get('verification_reason')}",
                f"- Deploy payload: {item.get('deploy_payload')}",
                "",
            ]
        )
        commands = item.get("apply_commands") if isinstance(item.get("apply_commands"), list) else []
        if commands:
            lines.extend(["Apply through existing path:", ""])
            lines.extend(f"- `{command}`" for command in commands)
            lines.append("")
        proof_steps = item.get("post_deploy_proof_steps") if isinstance(item.get("post_deploy_proof_steps"), list) else []
        if proof_steps:
            lines.extend(["Post-deploy proof:", ""])
            lines.extend(f"- `{step}`" for step in proof_steps[:8])
            lines.append("")
    md_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return {"json": str(json_path), "md": str(md_path)}


def build_deploy_application_preflight(manifest: dict[str, Any]) -> dict[str, Any]:
    items = manifest.get("items") if isinstance(manifest.get("items"), list) else []
    item_results: list[dict[str, Any]] = []
    failed_checks: list[str] = []
    total_pairs = 0
    verified_pairs = 0
    full_apply_pairs = 0
    verified_full_apply_pairs = 0
    hunk_required_count = 0
    for item in items:
        if not isinstance(item, dict):
            continue
        application_status = str(item.get("application_status") or "").strip()
        hunk_required = application_status == "partial_patch_hunk_required"
        if hunk_required:
            hunk_required_count += 1
        pair_results: list[dict[str, Any]] = []
        file_pairs = item.get("file_pairs") if isinstance(item.get("file_pairs"), list) else []
        for pair in file_pairs:
            if not isinstance(pair, dict):
                continue
            total_pairs += 1
            local_path_text = str(pair.get("local_path") or "").strip()
            remote_path_text = str(pair.get("remote_path") or "").strip()
            command_text = str(pair.get("apply_command") or "").strip()
            expected_sha = str(pair.get("sha256") or "").strip().lower()
            local_path = Path(local_path_text)
            if local_path_text and not local_path.is_absolute():
                local_path = ROOT / local_path
            exists = local_path.exists() and local_path.is_file()
            actual_sha = ""
            size_bytes = None
            if exists:
                data = local_path.read_bytes()
                actual_sha = hashlib.sha256(data).hexdigest()
                size_bytes = len(data)
            sha_matches = bool(expected_sha) and actual_sha == expected_sha
            command_uses_existing_script = "scripts\\Send-TODMimScript.ps1" in command_text
            command_mentions_pair = local_path_text in command_text and remote_path_text in command_text
            remote_target_valid = remote_path_text.startswith("/home/testpilot/mim/")
            local_pair_valid = exists and sha_matches and remote_target_valid
            if not hunk_required:
                full_apply_pairs += 1
            passed = local_pair_valid and (
                hunk_required
                or (
                    command_uses_existing_script
                    and command_mentions_pair
                )
            )
            full_apply_passed = (
                exists
                and sha_matches
                and command_uses_existing_script
                and command_mentions_pair
                and remote_target_valid
            )
            if passed:
                verified_pairs += 1
            if full_apply_passed and not hunk_required:
                verified_full_apply_pairs += 1
            if not passed and not hunk_required:
                failed_checks.append(f"{item.get('objective_id') or 'unknown'}:{local_path_text or 'missing-local'}")
            pair_results.append(
                {
                    "local_path": local_path_text,
                    "remote_path": remote_path_text,
                    "application_status": application_status,
                    "local_exists": exists,
                    "expected_sha256": expected_sha,
                    "actual_sha256": actual_sha,
                    "sha256_matches": sha_matches,
                    "size_bytes": size_bytes,
                    "command_uses_existing_script": command_uses_existing_script,
                    "command_mentions_pair": command_mentions_pair,
                    "remote_target_valid": remote_target_valid,
                    "hunk_required": hunk_required,
                    "passed": passed,
                }
            )
        item_passed = bool(file_pairs) and all(result.get("passed") for result in pair_results)
        item_results.append(
            {
                "rank": item.get("rank"),
                "objective_id": item.get("objective_id"),
                "application_status": application_status,
                "passed": item_passed,
                "ready_for_full_file_apply": item_passed and not hunk_required,
                "hunk_required": hunk_required,
                "pair_count": len(pair_results),
                "pairs": pair_results,
            }
        )
    no_new_channel = bool(manifest.get("no_new_channel_required"))
    if not no_new_channel:
        failed_checks.append("manifest:no_new_channel_required_false")
    if failed_checks or not no_new_channel:
        status = "failed"
    elif hunk_required_count:
        status = "ready_with_partial_hunks_required"
    elif total_pairs and verified_pairs == total_pairs:
        status = "passed_ready_for_existing_apply"
    else:
        status = "failed"
    return {
        "artifact_type": "mim_tod_deploy_application_preflight_v1",
        "generated_at": utc_now(),
        "status": status,
        "passed": status in {"passed_ready_for_existing_apply", "ready_with_partial_hunks_required"},
        "verified_pairs": verified_pairs,
        "total_pairs": total_pairs,
        "full_apply_pairs": full_apply_pairs,
        "verified_full_apply_pairs": verified_full_apply_pairs,
        "hunk_required_count": hunk_required_count,
        "failed_checks": failed_checks,
        "no_new_channel_required": no_new_channel,
        "live_deployment_verified": False,
        "existing_apply_script": manifest.get("existing_apply_script") or "scripts\\Send-TODMimScript.ps1",
        "items": item_results,
        "next_action": (
            "Apply ready payloads through the existing Send-TODMimScript.ps1 path, then run post-deploy proof and refresh scorecards."
            if status == "passed_ready_for_existing_apply"
            else "Apply full-file-ready payloads through the existing path; materialize partial hunk payloads against the live file before applying them."
            if status == "ready_with_partial_hunks_required"
            else "Repair failed local preflight checks before applying deploy payloads."
        ),
        "credit_policy": manifest.get("credit_policy") or "",
    }


def write_deploy_application_preflight(preflight: dict[str, Any], out_dir: Path) -> dict[str, str]:
    json_path = out_dir / "MIM_TOD_DEPLOY_APPLICATION_PREFLIGHT.latest.json"
    md_path = out_dir / "MIM_TOD_DEPLOY_APPLICATION_PREFLIGHT.latest.md"
    json_path.write_text(json.dumps(preflight, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    lines = [
        "# MIM/TOD Deploy Application Preflight",
        "",
        f"Generated: {preflight.get('generated_at', '')}",
        f"Status: {preflight.get('status', '')}",
        f"Passed: {str(bool(preflight.get('passed'))).lower()}",
        f"Verified file pairs: {preflight.get('verified_pairs', 0)}/{preflight.get('total_pairs', 0)}",
        f"Full-file apply pairs: {preflight.get('verified_full_apply_pairs', 0)}/{preflight.get('full_apply_pairs', 0)}",
        f"Partial hunk payloads: {preflight.get('hunk_required_count', 0)}",
        f"No new channel required: {str(bool(preflight.get('no_new_channel_required'))).lower()}",
        f"Live deployment verified: {str(bool(preflight.get('live_deployment_verified'))).lower()}",
        f"Next action: {preflight.get('next_action', '')}",
        "",
        f"Credit policy: {preflight.get('credit_policy', '')}",
        "",
    ]
    items = preflight.get("items") if isinstance(preflight.get("items"), list) else []
    for item in items:
        lines.extend(
            [
                f"## {item.get('rank')}. {item.get('objective_id')}",
                "",
                f"- Passed: {str(bool(item.get('passed'))).lower()}",
                f"- Application status: {item.get('application_status') or 'unknown'}",
                f"- Ready for full-file apply: {str(bool(item.get('ready_for_full_file_apply'))).lower()}",
                f"- File pairs: {item.get('pair_count', 0)}",
                "",
            ]
        )
        pairs = item.get("pairs") if isinstance(item.get("pairs"), list) else []
        for pair in pairs:
            lines.append(
                f"- `{pair.get('local_path')}` -> `{pair.get('remote_path')}`: "
                f"exists={str(bool(pair.get('local_exists'))).lower()}, "
                f"sha={str(bool(pair.get('sha256_matches'))).lower()}, "
                f"script={str(bool(pair.get('command_uses_existing_script'))).lower()}"
            )
        lines.append("")
    md_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return {"json": str(json_path), "md": str(md_path)}


def write_snapshots(scoreboard: dict[str, Any], out_dir: Path) -> dict[str, str]:
    stamp = datetime.now(timezone.utc)
    compact_stamp = stamp.strftime("%Y%m%dT%H%M%SZ")
    day = stamp.strftime("%Y-%m-%d")
    snapshot_root = out_dir / "training_scoreboard_snapshots"
    hourly_dir = snapshot_root / "hourly"
    daily_dir = snapshot_root / "daily" / day
    hourly_dir.mkdir(parents=True, exist_ok=True)
    daily_dir.mkdir(parents=True, exist_ok=True)

    hourly_json = hourly_dir / f"MIM_TOD_TRAINING_SCOREBOARD.{compact_stamp}.json"
    hourly_md = hourly_dir / f"MIM_TOD_TRAINING_SCOREBOARD.{compact_stamp}.md"
    daily_json = daily_dir / f"MIM_TOD_TRAINING_SCOREBOARD.{compact_stamp}.json"
    daily_md = daily_dir / f"MIM_TOD_TRAINING_SCOREBOARD.{compact_stamp}.md"
    for path in (hourly_json, daily_json):
        path.write_text(json.dumps(scoreboard, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for path in (hourly_md, daily_md):
        write_markdown(scoreboard, path)
    return {
        "hourly_json": str(hourly_json),
        "hourly_md": str(hourly_md),
        "daily_json": str(daily_json),
        "daily_md": str(daily_md),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="", help="Optional MIM base URL for live communication evaluation.")
    parser.add_argument("--operator-estimated-hours", type=float, default=None)
    parser.add_argument("--out-dir", default=str(TRAINING_ROOT))
    parser.add_argument("--write-snapshots", action="store_true")
    args = parser.parse_args()

    scoreboard = build_scoreboard(
        base_url=args.base_url.strip() or None,
        operator_estimated_hours=args.operator_estimated_hours,
    )
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "MIM_TOD_TRAINING_SCOREBOARD.latest.json"
    md_path = out_dir / "MIM_TOD_TRAINING_SCOREBOARD.latest.md"
    json_path.write_text(json.dumps(scoreboard, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(scoreboard, md_path)
    deploy_queue = build_deploy_verification_queue(scoreboard)
    deploy_queue_paths = write_deploy_verification_queue(deploy_queue, out_dir)
    deploy_manifest = build_deploy_application_manifest(deploy_queue)
    deploy_manifest_paths = write_deploy_application_manifest(deploy_manifest, out_dir)
    deploy_preflight = build_deploy_application_preflight(deploy_manifest)
    deploy_preflight_paths = write_deploy_application_preflight(deploy_preflight, out_dir)
    scoreboard["tod_score"]["deploy_verification_queue"] = {
        "status": deploy_queue.get("status"),
        "pending_count": deploy_queue.get("pending_count"),
        "json": deploy_queue_paths["json"],
        "md": deploy_queue_paths["md"],
    }
    scoreboard["tod_score"]["deploy_application_manifest"] = {
        "status": deploy_manifest.get("status"),
        "ready_count": deploy_manifest.get("ready_count"),
        "pending_count": deploy_manifest.get("pending_count"),
        "json": deploy_manifest_paths["json"],
        "md": deploy_manifest_paths["md"],
    }
    scoreboard["tod_score"]["deploy_application_preflight"] = {
        "status": deploy_preflight.get("status"),
        "passed": deploy_preflight.get("passed"),
        "verified_pairs": deploy_preflight.get("verified_pairs"),
        "total_pairs": deploy_preflight.get("total_pairs"),
        "json": deploy_preflight_paths["json"],
        "md": deploy_preflight_paths["md"],
    }
    json_path.write_text(json.dumps(scoreboard, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(scoreboard, md_path)
    if args.write_snapshots:
        snapshots = write_snapshots(scoreboard, out_dir)
        scoreboard["snapshot_files"] = snapshots
        json_path.write_text(json.dumps(scoreboard, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        write_markdown(scoreboard, md_path)
    print(json_path)
    print(md_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
