from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import shutil
import threading
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Body, HTTPException, Query
from fastapi.responses import FileResponse, HTMLResponse

from core.config import PROJECT_ROOT, settings
from core.tod_execution_loop import build_execution_loop_contract_artifacts, execute_bounded_local_inspection


router = APIRouter(tags=["tod-ui"])

SHARED_RUNTIME_ROOT = PROJECT_ROOT / "runtime" / "shared"
TOD_CONSOLE_CHAT_ROOT = SHARED_RUNTIME_ROOT / "tod_console_chat"
TOD_CONSOLE_CHAT_MEDIA_ROOT = SHARED_RUNTIME_ROOT / "tod_console_chat_media"
DIALOG_ROOT = SHARED_RUNTIME_ROOT / "dialog"
TOD_COPILOT_HANDOFF_ROOT = SHARED_RUNTIME_ROOT / "tod_copilot_handoff"
REMOTE_RECOVERY_ROOT = SHARED_RUNTIME_ROOT / "remote_recovery"
TOD_OPERATOR_ACTION_ROOT = SHARED_RUNTIME_ROOT / "tod_operator_actions"
DIALOG_SCHEMA_VERSION = "mim-tod-dialog-v1"
TOD_UI_ALLOWED_IMAGE_TYPES = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/webp": ".webp",
}
TOD_UI_MAX_IMAGE_BYTES = 2 * 1024 * 1024
TOD_EXECUTION_FEEDBACK_DEFAULT_BASE_URL = "http://127.0.0.1:18001"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return payload if isinstance(payload, dict) else {}


def _first_existing_payload(*paths: Path) -> tuple[dict[str, Any], str]:
    for path in paths:
        payload = _load_json(path)
        if payload:
            return payload, str(path)
    return {}, ""


def _compact_text(value: Any, limit: int = 220) -> str:
    cleaned = " ".join(str(value or "").strip().split())
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 3].rstrip() + "..."


def _trim_message_text(value: Any, limit: int = 2000) -> str:
    text = str(value or "").strip()
    if len(text) <= limit:
        return text
    return text[: limit - 3].rstrip() + "..."


def _parse_timestamp(value: Any) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


def _age_seconds(value: Any) -> float | None:
    parsed = _parse_timestamp(value)
    if parsed is None:
        return None
    return max(0.0, (datetime.now(timezone.utc) - parsed).total_seconds())


def _format_age(value: Any) -> str:
    seconds = _age_seconds(value)
    if seconds is None:
        return "Unknown"
    if seconds < 90:
        return f"{int(round(seconds))}s ago"
    minutes = seconds / 60.0
    if minutes < 90:
        return f"{int(round(minutes))}m ago"
    hours = minutes / 60.0
    if hours < 48:
        return f"{hours:.1f}h ago"
    days = hours / 24.0
    return f"{days:.1f}d ago"


def _normalize_objective_token(value: Any) -> str:
    text = str(value or "").strip().lower()
    if not text:
        return ""
    match = re.search(r"(\d+)$", text)
    if match:
        return match.group(1)
    if text.startswith("objective-"):
        return text[len("objective-") :]
    return text


def _same_objective(left: Any, right: Any) -> bool:
    left_token = _normalize_objective_token(left)
    right_token = _normalize_objective_token(right)
    return bool(left_token and right_token and left_token == right_token)


def _should_reuse_live_task_identity(live_task: dict[str, Any], prompt_objective_id: str) -> bool:
    if not isinstance(live_task, dict) or not live_task:
        return False
    request_id = str(live_task.get("request_id") or "").strip()
    task_id = str(live_task.get("task_id") or "").strip()
    if not request_id and not task_id:
        return False
    if not prompt_objective_id:
        return True
    prompt_text = str(prompt_objective_id or "").strip().lower()
    live_objective_id = str(
        live_task.get("objective_id")
        or live_task.get("normalized_objective_id")
        or ""
    ).strip()
    if prompt_text:
        request_text = request_id.lower()
        task_text = task_id.lower()
        live_objective_text = live_objective_id.lower()
        if prompt_text in request_text or prompt_text in task_text or prompt_text == live_objective_text:
            return True
    if not live_objective_id:
        return True
    return _same_objective(prompt_objective_id, live_objective_id)


def _select_runtime_live_task_request(integration_live_task: dict[str, Any], active_task: dict[str, Any]) -> dict[str, Any]:
    live_task = integration_live_task if isinstance(integration_live_task, dict) else {}
    runtime_task = active_task if isinstance(active_task, dict) else {}
    runtime_request_id = str(runtime_task.get("request_id") or "").strip()
    runtime_task_id = str(runtime_task.get("task_id") or "").strip()
    if not runtime_request_id and not runtime_task_id:
        return live_task

    runtime_objective = str(
        runtime_task.get("objective_id")
        or runtime_task.get("normalized_objective_id")
        or ""
    ).strip()
    live_objective = str(
        live_task.get("objective_id")
        or live_task.get("normalized_objective_id")
        or ""
    ).strip()
    if live_task and _same_objective(runtime_objective, live_objective):
        return live_task

    runtime_generated_at = str(runtime_task.get("updated_at") or runtime_task.get("generated_at") or "").strip()
    return {
        **live_task,
        "request_id": runtime_request_id or str(live_task.get("request_id") or "").strip(),
        "task_id": runtime_task_id or str(live_task.get("task_id") or "").strip(),
        "objective_id": runtime_objective or str(live_task.get("objective_id") or "").strip(),
        "normalized_objective_id": str(
            runtime_task.get("normalized_objective_id")
            or _normalize_objective_token(runtime_objective)
            or live_task.get("normalized_objective_id")
            or ""
        ).strip(),
        "generated_at": runtime_generated_at or str(live_task.get("generated_at") or "").strip(),
        "promotion_applied": bool(live_task.get("promotion_applied") is True),
        "promotion_reason": str(live_task.get("promotion_reason") or "").strip(),
    }


def _detect_phase_label(active_task: dict[str, Any], execution_result: dict[str, Any]) -> str:
    for candidate in (
        active_task.get("objective_id"),
        active_task.get("title"),
        active_task.get("task_focus"),
        active_task.get("summary"),
        execution_result.get("objective_id"),
        execution_result.get("title"),
        execution_result.get("summary"),
    ):
        text = str(candidate or "").strip()
        if not text:
            continue
        match = re.search(r"\bphase[\s_-]*(\d+)\b", text, re.IGNORECASE)
        if match:
            return f"Phase {match.group(1)}"
    return "Phase 1"


def _load_remote_recovery_payload() -> tuple[dict[str, Any], str]:
    return _first_existing_payload(
        REMOTE_RECOVERY_ROOT / "TOD_MIM_REMOTE_RECOVERY.latest.json",
        SHARED_RUNTIME_ROOT / "TOD_MIM_REMOTE_RECOVERY.latest.json",
    )


def _load_existing_execution_runtime_payloads() -> dict[str, dict[str, Any]]:
    payloads = {
        "active_objective": _load_json(SHARED_RUNTIME_ROOT / "TOD_ACTIVE_OBJECTIVE.latest.json"),
        "active_task": _load_json(SHARED_RUNTIME_ROOT / "TOD_ACTIVE_TASK.latest.json"),
        "activity": _load_json(SHARED_RUNTIME_ROOT / "TOD_ACTIVITY_STREAM.latest.json"),
        "validation": _load_json(SHARED_RUNTIME_ROOT / "TOD_VALIDATION_RESULT.latest.json"),
        "execution_result": _load_json(SHARED_RUNTIME_ROOT / "TOD_EXECUTION_RESULT.latest.json"),
        "execution_truth": _load_json(SHARED_RUNTIME_ROOT / "TOD_EXECUTION_TRUTH.latest.json"),
    }
    return payloads


def _payload_matches_active_execution(payload: dict[str, Any], objective_id: str, task_id: str, execution_id: str) -> bool:
    if not isinstance(payload, dict) or not payload:
        return False
    payload_task_id = str(payload.get("task_id") or "").strip()
    payload_execution_id = str(payload.get("execution_id") or "").strip()
    payload_objective_id = str(payload.get("objective_id") or "").strip()
    if not _same_objective(payload_objective_id, objective_id):
        return False
    if payload_task_id and payload_task_id == task_id:
        return True
    if payload_execution_id and payload_execution_id == execution_id:
        return True
    return False


def _existing_runtime_matches_active_execution(runtime_payloads: dict[str, dict[str, Any]], objective_id: str, task_id: str, execution_id: str) -> bool:
    if not runtime_payloads or not all(isinstance(payload, dict) and payload for payload in runtime_payloads.values()):
        return False
    return all(
        _payload_matches_active_execution(payload, objective_id, task_id, execution_id)
        for payload in runtime_payloads.values()
    )


def _pick_latest_timestamp(*values: Any) -> str:
    latest_value = ""
    latest_parsed: datetime | None = None
    for value in values:
        parsed = _parse_timestamp(value)
        if parsed is None:
            continue
        if latest_parsed is None or parsed > latest_parsed:
            latest_parsed = parsed
            latest_value = str(value or "").strip()
    return latest_value


def _normalize_stage_status(value: Any) -> str:
    return str(value or "").strip().lower()


def _stage_is_complete(value: Any) -> bool:
    return _normalize_stage_status(value) in {"accepted", "complete", "completed", "passed", "success", "succeeded", "not_needed"}


def _stage_is_active(value: Any) -> bool:
    return _normalize_stage_status(value) in {"active", "accepted", "in_progress", "pending", "planned", "running", "waiting"}


def _derive_implementation_gate_percent(
    active_task: dict[str, Any],
    execution_result: dict[str, Any],
    validation: dict[str, Any],
    patch_status: str,
    command_status: str,
    result_publisher_status: str,
) -> int:
    execution_evidence = (
        execution_result.get("execution_evidence")
        if isinstance(execution_result.get("execution_evidence"), dict)
        else active_task.get("execution_evidence")
        if isinstance(active_task.get("execution_evidence"), dict)
        else {}
    )
    latest_update = _pick_latest_timestamp(
        execution_result.get("updated_at"),
        execution_result.get("generated_at"),
        validation.get("updated_at"),
        validation.get("generated_at"),
        active_task.get("updated_at"),
        active_task.get("generated_at"),
    )
    age_seconds = _age_seconds(latest_update)
    if age_seconds is None or age_seconds > 1800:
        return 60

    progress_points = 60
    if _stage_is_active(patch_status) or _stage_is_active(command_status):
        progress_points += 1

    detail_text = " ".join(
        str(item or "")
        for item in (
            execution_result.get("current_action"),
            execution_result.get("summary"),
            execution_result.get("next_step"),
            execution_result.get("wait_reason"),
            active_task.get("current_action"),
            active_task.get("summary"),
            active_task.get("next_step"),
            active_task.get("wait_reason"),
        )
    ).lower()
    if any(term in detail_text for term in ("implementation", "implement", "patch", "slice", "execution-loop")):
        progress_points += 1

    matched_files = execution_evidence.get("matched_files") if isinstance(execution_evidence.get("matched_files"), list) else []
    if matched_files:
        progress_points += min(2, len(matched_files))

    validation_checks = validation.get("checks") if isinstance(validation.get("checks"), list) else execution_evidence.get("validation_checks") if isinstance(execution_evidence.get("validation_checks"), list) else []
    passed_checks = sum(1 for item in validation_checks if isinstance(item, dict) and item.get("passed") is True)
    if passed_checks > 0:
        progress_points += min(3, max(1, (passed_checks + 1) // 2))

    files_changed = execution_result.get("files_changed") if isinstance(execution_result.get("files_changed"), list) else execution_evidence.get("files_changed") if isinstance(execution_evidence.get("files_changed"), list) else []
    if files_changed:
        progress_points += min(2, len(files_changed))

    command_output = str(execution_result.get("command_output") or execution_evidence.get("command_output") or "").strip()
    if command_output:
        progress_points += 1

    if _stage_is_complete(result_publisher_status):
        progress_points += 1

    return max(60, min(69, int(progress_points)))


def _derive_phase_progress(
    active_task: dict[str, Any],
    execution_result: dict[str, Any],
    validation: dict[str, Any],
    activity_state: str,
    next_step: str,
    wait_reason: str,
) -> dict[str, Any]:
    phase_label = _detect_phase_label(active_task, execution_result)
    contract = (
        active_task.get("execution_contract")
        if isinstance(active_task.get("execution_contract"), dict)
        else execution_result.get("execution_contract")
        if isinstance(execution_result.get("execution_contract"), dict)
        else {}
    )
    intake = contract.get("task_intake") if isinstance(contract.get("task_intake"), dict) else {}
    planner = contract.get("bounded_step_planner") if isinstance(contract.get("bounded_step_planner"), dict) else {}
    command_runner = contract.get("command_runner") if isinstance(contract.get("command_runner"), dict) else {}
    patch_writer = contract.get("patch_writer") if isinstance(contract.get("patch_writer"), dict) else {}
    validator = contract.get("validator") if isinstance(contract.get("validator"), dict) else {}
    result_publisher = contract.get("result_publisher") if isinstance(contract.get("result_publisher"), dict) else {}
    patch_status = _normalize_stage_status(patch_writer.get("status"))
    command_status = _normalize_stage_status(command_runner.get("status"))
    result_publisher_status = _normalize_stage_status(result_publisher.get("status"))
    implementation_complete = _stage_is_complete(patch_status) or (not patch_status and _stage_is_complete(command_status))

    milestones = [
        {
            "id": "task_intake",
            "label": "Task intake",
            "weight": 10,
            "status": _normalize_stage_status(intake.get("status")),
            "complete": _stage_is_complete(intake.get("status")),
        },
        {
            "id": "inspection",
            "label": "Inspection and planning",
            "weight": 20,
            "status": _normalize_stage_status(planner.get("status") or (planner.get("active_step") if isinstance(planner.get("active_step"), dict) else {}).get("status")),
            "complete": _stage_is_complete(planner.get("status")) or _stage_is_complete((planner.get("active_step") if isinstance(planner.get("active_step"), dict) else {}).get("status")),
        },
        {
            "id": "implementation",
            "label": "Implementation",
            "weight": 35,
            "status": patch_status or command_status,
            "complete": implementation_complete,
        },
        {
            "id": "validation",
            "label": "Focused validation",
            "weight": 20,
            "status": _normalize_stage_status(validator.get("status") or validation.get("status")),
            "complete": _stage_is_complete(validator.get("status")) or _stage_is_complete(validation.get("status")),
        },
        {
            "id": "publication",
            "label": "Evidence publish",
            "weight": 15,
            "status": result_publisher_status,
            "complete": _stage_is_complete(result_publisher_status),
        },
    ]

    percent_complete = sum(item["weight"] for item in milestones if item["complete"])
    implementation_pending = not milestones[2]["complete"] and any(
        phrase in f"{next_step} {wait_reason}".lower()
        for phrase in ("implementation", "patch", "bounded execution-loop slice", "bounded local implementation step")
    )
    if implementation_pending:
        percent_complete = _derive_implementation_gate_percent(
            active_task,
            execution_result,
            validation,
            patch_status,
            command_status,
            result_publisher_status,
        )
    if activity_state == "complete":
        percent_complete = 100

    completed_count = sum(1 for item in milestones if item["complete"])
    total_count = len(milestones)
    next_gate = "Phase 2 handoff" if percent_complete >= 100 else "Implementation" if implementation_pending else "Focused validation" if not milestones[3]["complete"] else "Evidence publish" if not milestones[4]["complete"] else "Phase 1 closeout"
    if percent_complete >= 100:
        summary = f"{phase_label} complete and verified."
    elif implementation_pending:
        summary = f"{phase_label} is about {percent_complete}% complete within the implementation gate. Inspection is done; implementation is the next gate."
    elif not milestones[3]["complete"]:
        summary = f"{phase_label} is about {percent_complete}% complete. Focused validation is the next gate."
    elif not milestones[4]["complete"]:
        summary = f"{phase_label} is about {percent_complete}% complete. Evidence publish is the next gate."
    else:
        summary = f"{phase_label} is about {percent_complete}% complete. Final closeout is the next gate."

    return {
        "available": bool(contract) or bool(active_task) or bool(execution_result),
        "label": f"{phase_label} progress",
        "percent_complete": max(0, min(100, int(percent_complete))),
        "completed_milestones": completed_count,
        "total_milestones": total_count,
        "next_gate": next_gate,
        "summary": summary,
        "milestones": milestones,
    }


def _derive_stall_signal(activity_state: str, age_seconds: float | None, phase_progress: dict[str, Any], next_step: str, wait_reason: str) -> dict[str, Any]:
    normalized_state = str(activity_state or "idle").strip().lower() or "idle"
    if age_seconds is None or normalized_state in {"complete", "blocked", "idle"}:
        return {
            "flagged": False,
            "level": "ok",
            "threshold_seconds": None,
            "age_seconds": age_seconds,
            "summary": "",
        }

    progress_percent = int(phase_progress.get("percent_complete") or 0)
    progress_label = _compact_text(phase_progress.get("label"), 80) or "Phase progress"
    phase_display = progress_label[:-9] if progress_label.lower().endswith(" progress") else progress_label
    progress_summary = str(phase_progress.get("summary") or "Phase progress is published.").strip()
    detail = _compact_text(wait_reason or next_step or "No next bounded step detail is published.", 160)
    threshold_seconds = 1200 if normalized_state == "waiting" else 900 if normalized_state == "working" else 600 if normalized_state == "stalled" else None
    flagged = bool(threshold_seconds is not None and age_seconds >= threshold_seconds)
    if not flagged:
        implementation_pending = normalized_state == "waiting" and str(phase_progress.get("next_gate") or "").strip().lower() == "implementation" and progress_percent >= 60
        if implementation_pending:
            delay_minutes = max(1, int(round(age_seconds / 60.0)))
            freshness_text = (
                f"Fresh execution evidence landed {delay_minutes}m ago, so this wait is for the next implementation slice rather than stale output."
                if age_seconds <= 180
                else f"Latest execution evidence is {delay_minutes}m old and still inside the implementation wait window."
            )
            summary = (
                f"Held at implementation gate: {phase_display} is at {progress_percent}% until the next implementation slice starts. "
                f"{freshness_text} {progress_summary} {detail}"
            )
            return {
                "flagged": False,
                "level": "implementation_pending",
                "threshold_seconds": threshold_seconds,
                "age_seconds": age_seconds,
                "summary": _compact_text(summary, 220),
            }
        return {
            "flagged": False,
            "level": "ok",
            "threshold_seconds": threshold_seconds,
            "age_seconds": age_seconds,
            "summary": "",
        }

    delay_minutes = max(1, int(round(age_seconds / 60.0)))
    summary = (
        f"Probable stall: {phase_display} is holding at {progress_percent}% for about {delay_minutes}m without a newer execution update. "
        f"{progress_summary} {detail}"
    )
    return {
        "flagged": True,
        "level": "probable_stall",
        "threshold_seconds": threshold_seconds,
        "age_seconds": age_seconds,
        "summary": _compact_text(summary, 220),
    }


def _normalize_execution_status(
    active_objective_payload: Any,
    active_task_payload: Any,
    activity_payload: Any,
    validation_payload: Any,
    execution_result_payload: Any,
    truth_payload: Any,
) -> dict[str, Any]:
    active_objective = active_objective_payload if isinstance(active_objective_payload, dict) else {}
    active_task = active_task_payload if isinstance(active_task_payload, dict) else {}
    activity = activity_payload if isinstance(activity_payload, dict) else {}
    validation = validation_payload if isinstance(validation_payload, dict) else {}
    execution_result = execution_result_payload if isinstance(execution_result_payload, dict) else {}
    truth = truth_payload if isinstance(truth_payload, dict) else {}

    available = any(bool(payload) for payload in (active_objective, active_task, activity, validation, execution_result, truth))
    updated_at = _pick_latest_timestamp(
        execution_result.get("updated_at"),
        execution_result.get("generated_at"),
        validation.get("updated_at"),
        validation.get("generated_at"),
        activity.get("updated_at"),
        activity.get("generated_at"),
        active_task.get("updated_at"),
        active_task.get("generated_at"),
    )
    if not updated_at:
        updated_at = _pick_latest_timestamp(
            active_objective.get("updated_at"),
            active_objective.get("generated_at"),
            truth.get("generated_at"),
        )
    status = str(
        execution_result.get("status")
        or activity.get("status")
        or active_task.get("status")
        or truth.get("status")
        or ""
    ).strip().lower()
    execution_state = str(
        execution_result.get("execution_state")
        or activity.get("execution_state")
        or active_task.get("execution_state")
        or active_task.get("status")
        or ""
    ).strip().lower()
    phase = str(activity.get("phase") or execution_result.get("phase") or validation.get("phase") or "").strip().lower()
    current_action = _compact_text(
        execution_result.get("current_action")
        or activity.get("current_action")
        or active_task.get("current_action")
        or "",
        220,
    )
    next_step = _compact_text(
        execution_result.get("next_step")
        or activity.get("next_step")
        or active_task.get("next_step")
        or "",
        220,
    )
    next_validation = _compact_text(
        validation.get("validation_target")
        or active_task.get("next_validation")
        or activity.get("next_validation")
        or "",
        220,
    )
    summary = _compact_text(
        execution_result.get("summary")
        or active_task.get("summary")
        or activity.get("summary")
        or current_action
        or "No TOD execution activity is currently published.",
        220,
    )
    validation_status = str(validation.get("status") or "").strip().lower()
    validation_summary = _compact_text(validation.get("summary") or "", 220)
    execution_evidence = (
        execution_result.get("execution_evidence")
        if isinstance(execution_result.get("execution_evidence"), dict)
        else active_task.get("execution_evidence")
        if isinstance(active_task.get("execution_evidence"), dict)
        else activity.get("execution_evidence")
        if isinstance(activity.get("execution_evidence"), dict)
        else {}
    )
    command_output = _compact_text(
        execution_result.get("command_output")
        or execution_evidence.get("command_output")
        or "",
        220,
    )
    files_changed = [
        _compact_text(item, 180)
        for item in (
            execution_result.get("files_changed")
            if isinstance(execution_result.get("files_changed"), list)
            else execution_evidence.get("files_changed")
            if isinstance(execution_evidence.get("files_changed"), list)
            else []
        )[:8]
        if _compact_text(item, 180)
    ]
    matched_files = [
        _compact_text(item, 180)
        for item in (
            execution_evidence.get("matched_files")
            if isinstance(execution_evidence.get("matched_files"), list)
            else []
        )[:8]
        if _compact_text(item, 180)
    ]
    validation_checks = (
        execution_evidence.get("validation_checks")
        if isinstance(execution_evidence.get("validation_checks"), list)
        else validation.get("checks")
        if isinstance(validation.get("checks"), list)
        else []
    )
    wait_target = _compact_text(
        execution_result.get("wait_target")
        or active_task.get("wait_target")
        or activity.get("wait_target")
        or execution_evidence.get("wait_target")
        or "",
        120,
    )
    wait_target_label = _compact_text(
        execution_result.get("wait_target_label")
        or active_task.get("wait_target_label")
        or activity.get("wait_target_label")
        or execution_evidence.get("wait_target_label")
        or wait_target,
        120,
    )
    wait_reason = _compact_text(
        execution_result.get("wait_reason")
        or active_task.get("wait_reason")
        or activity.get("wait_reason")
        or execution_evidence.get("wait_reason")
        or "",
        220,
    )
    rollback_state = _compact_text(
        execution_result.get("rollback_state") or execution_evidence.get("rollback_state") or "not_needed",
        120,
    )
    recovery_state = _compact_text(
        execution_result.get("recovery_state") or execution_evidence.get("recovery_state") or "not_needed",
        120,
    )
    age_seconds = _age_seconds(updated_at)

    activity_state = "idle"
    activity_label = "Idle"
    active = False
    if not available:
        activity_summary = "No TOD execution artifact is currently published."
    elif status in {"failed", "error", "blocked"} or execution_state in {"failed", "error", "blocked"}:
        activity_state = "stalled"
        activity_label = "Blocked"
        activity_summary = summary or "TOD hit a blocking execution error."
    elif validation_status in {"pending", "waiting"} and next_validation:
        activity_state = "waiting"
        activity_label = "Waiting"
        active = True
        activity_summary = wait_reason or validation_summary or f"TOD is waiting on validation: {next_validation}."
    elif status in {"waiting", "pending"} or execution_state in {"waiting", "waiting_on_next_step", "step_completed_waiting_next_selection"}:
        activity_state = "waiting"
        activity_label = "Waiting"
        active = True
        activity_summary = wait_reason or current_action or summary or "TOD completed the latest bounded step and is waiting on the next step."
    elif status in {"completed", "complete", "success", "succeeded"} or execution_state in {"completed", "complete", "success", "succeeded"}:
        activity_state = "complete"
        activity_label = "Complete"
        activity_summary = summary or "TOD completed the current execution slice."
    elif status in {"running", "active", "in_progress"} or execution_state in {"accepted", "planned", "running", "active", "in_progress"}:
        if age_seconds is not None and age_seconds > 900:
            activity_state = "stalled"
            activity_label = "Stale"
            activity_summary = current_action or summary or "TOD execution artifacts are stale and need review."
        else:
            activity_state = "working"
            activity_label = "Working"
            active = True
            activity_summary = current_action or summary or "TOD is actively working the current execution slice."
    else:
        activity_summary = summary

    phase_progress = _derive_phase_progress(
        active_task,
        execution_result,
        validation,
        activity_state,
        next_step,
        wait_reason,
    )
    stall_signal = _derive_stall_signal(activity_state, age_seconds, phase_progress, next_step, wait_reason)
    if stall_signal.get("flagged") and activity_state in {"waiting", "working", "stalled"}:
        activity_state = "stalled"
        activity_label = "Stalled"
        activity_summary = str(stall_signal.get("summary") or activity_summary).strip() or activity_summary
    elif stall_signal.get("level") == "implementation_pending" and activity_state == "waiting":
        activity_summary = str(stall_signal.get("summary") or activity_summary).strip() or activity_summary

    return {
        "available": available,
        "objective_id": str(active_objective.get("objective_id") or active_task.get("objective_id") or "").strip(),
        "task_id": str(active_task.get("task_id") or execution_result.get("task_id") or "").strip(),
        "execution_id": str(execution_result.get("execution_id") or active_task.get("execution_id") or "").strip(),
        "title": _compact_text(active_task.get("title") or active_objective.get("title") or "", 180),
        "task_focus": _compact_text(active_task.get("task_focus") or active_task.get("summary") or "", 220),
        "status": status,
        "execution_state": execution_state,
        "phase": phase,
        "current_action": current_action,
        "next_step": next_step,
        "next_validation": next_validation,
        "summary": summary,
        "validation_status": validation_status,
        "validation_summary": validation_summary,
        "command_output": command_output,
        "files_changed": files_changed,
        "matched_files": matched_files,
        "validation_checks": validation_checks,
        "wait_target": wait_target,
        "wait_target_label": wait_target_label,
        "wait_reason": wait_reason,
        "rollback_state": rollback_state,
        "recovery_state": recovery_state,
        "updated_at": updated_at,
        "updated_age": _format_age(updated_at),
        "last_update_age_seconds": age_seconds,
        "activity_state": activity_state,
        "activity_label": activity_label,
        "activity_summary": activity_summary,
        "phase_progress": phase_progress,
        "stall_signal": stall_signal,
        "active": active,
    }


def _normalize_guidance_items(values: Any) -> list[dict[str, str]]:
    if not isinstance(values, list):
        return []
    items: list[dict[str, str]] = []
    for item in values[:8]:
        if not isinstance(item, dict):
            continue
        items.append(
            {
                "code": str(item.get("code") or "").strip(),
                "severity": str(item.get("severity") or "info").strip(),
                "summary": _compact_text(item.get("summary"), 180),
                "recommended_action": _compact_text(item.get("recommended_action"), 220),
            }
        )
    return items


def _safe_int(value: Any, default: int = 0) -> int:
    try:
        if value is None:
            return default
        return int(value)
    except (TypeError, ValueError):
        return default


def _friendly_person_name(value: Any) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    parts = [part for part in re.split(r"[^A-Za-z0-9]+", text) if part]
    if not parts:
        return ""
    return " ".join(part[:1].upper() + part[1:] for part in parts[:3])


def _is_generic_public_name(value: Any) -> bool:
    tokens = [part.lower() for part in re.split(r"[^A-Za-z0-9]+", str(value or "").strip()) if part]
    if not tokens:
        return True
    generic_tokens = {
        "guest",
        "visitor",
        "public",
        "operator",
        "testpilot",
        "unknown",
        "anonymous",
        "user",
        "account",
        "local",
        "default",
    }
    return all(token in generic_tokens for token in tokens)


def _name_from_email(value: Any) -> str:
    text = str(value or "").strip()
    if "@" not in text:
        return ""
    return _friendly_person_name(text.split("@", 1)[0])


def _find_named_value(payload: Any, depth: int = 0) -> str:
    if depth > 4:
        return ""
    if isinstance(payload, dict):
        for key in ("display_name", "user_name", "username", "whoami", "user"):
            candidate = _friendly_person_name(payload.get(key))
            if candidate:
                return candidate
        for item in list(payload.values())[:16]:
            candidate = _find_named_value(item, depth + 1)
            if candidate:
                return candidate
    elif isinstance(payload, list):
        for item in payload[:16]:
            candidate = _find_named_value(item, depth + 1)
            if candidate:
                return candidate
    return ""


def _resolve_public_visitor_name() -> str:
    candidates = [
        os.getenv("TOD_PUBLIC_VISITOR_NAME"),
        _name_from_email(os.getenv("SUPER_USER_EMAIL")),
        os.getenv("SUPER_USER_NAME"),
    ]
    for candidate in candidates:
        friendly = _friendly_person_name(candidate)
        if friendly and not _is_generic_public_name(friendly):
            return friendly
    return "Dave"


def _normalize_string_list(values: Any, limit: int = 8, item_limit: int = 220) -> list[str]:
    if not isinstance(values, list):
        return []
    items: list[str] = []
    for item in values[:limit]:
        text = _compact_text(item, item_limit)
        if text:
            items.append(text)
    return items


def _normalize_training_events(values: Any, limit: int = 8) -> list[dict[str, str]]:
    if not isinstance(values, list):
        return []
    items: list[dict[str, str]] = []
    for item in values[-limit:]:
        if not isinstance(item, dict):
            continue
        items.append(
            {
                "generated_at": str(item.get("generated_at") or "").strip(),
                "generated_age": _format_age(item.get("generated_at")),
                "type": str(item.get("type") or "event").strip(),
                "summary": _compact_text(item.get("summary"), 220),
            }
        )
    return items


def _normalize_training_stages(values: Any, limit: int = 8) -> list[dict[str, str]]:
    if not isinstance(values, list):
        return []
    items: list[dict[str, str]] = []
    for item in values[:limit]:
        if not isinstance(item, dict):
            continue
        items.append(
            {
                "id": str(item.get("id") or "").strip(),
                "label": str(item.get("label") or item.get("id") or "stage").strip(),
                "status": str(item.get("status") or "unknown").strip(),
                "detail": _compact_text(item.get("detail"), 220),
                "started_at": str(item.get("started_at") or "").strip(),
                "completed_at": str(item.get("completed_at") or "").strip(),
            }
        )
    return items


def _normalize_training_status(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {
            "available": False,
            "generated_at": "",
            "generated_age": "Unknown",
            "source": "",
            "run_id": "",
            "state": "unknown",
            "state_label": "Unknown",
            "active": False,
            "started_at": "",
            "started_age": "Unknown",
            "updated_at": "",
            "updated_age": "Unknown",
            "runtime_seconds": 0,
            "percent_complete": 0,
            "completed_steps": 0,
            "failed_steps": 0,
            "total_steps": 0,
            "phase": "unknown",
            "phase_label": "Unknown",
            "phase_detail": "",
            "current_step": "",
            "eta_seconds": None,
            "expected_completion_utc": "",
            "latest_error": "",
            "latest_error_at": "",
            "latest_error_age": "Unknown",
            "latest_resolution": "",
            "latest_resolution_at": "",
            "latest_resolution_age": "Unknown",
            "summary": "No training status is currently published.",
            "warnings": [],
            "errors": [],
            "resolutions": [],
            "recent_events": [],
            "stages": [],
            "artifacts": {"output_dir": "", "trace_path": ""},
            "idle_policy": {},
        }

    state = str(value.get("state") or value.get("status") or "unknown").strip() or "unknown"
    state_label = str(value.get("state_label") or state.replace("_", " ").title()).strip() or "Unknown"
    phase = str(value.get("phase") or "unknown").strip() or "unknown"
    phase_label = str(value.get("phase_label") or phase.replace("_", " ").title()).strip() or "Unknown"
    eta_value = value.get("eta_seconds")
    eta_seconds = None if eta_value in (None, "") else _safe_int(eta_value, 0)
    artifacts = value.get("artifacts") if isinstance(value.get("artifacts"), dict) else {}

    return {
        "available": True,
        "generated_at": str(value.get("generated_at") or "").strip(),
        "generated_age": _format_age(value.get("generated_at")),
        "source": str(value.get("source") or "").strip(),
        "run_id": str(value.get("run_id") or "").strip(),
        "state": state,
        "state_label": state_label,
        "active": bool(value.get("active") is True or state in {"running", "active", "in_progress"}),
        "started_at": str(value.get("started_at") or "").strip(),
        "started_age": _format_age(value.get("started_at")),
        "updated_at": str(value.get("updated_at") or "").strip(),
        "updated_age": _format_age(value.get("updated_at")),
        "runtime_seconds": _safe_int(value.get("runtime_seconds"), 0),
        "percent_complete": max(0, min(100, _safe_int(value.get("percent_complete"), 0))),
        "completed_steps": _safe_int(value.get("completed_steps"), 0),
        "failed_steps": _safe_int(value.get("failed_steps"), 0),
        "total_steps": _safe_int(value.get("total_steps"), 0),
        "phase": phase,
        "phase_label": phase_label,
        "phase_detail": _compact_text(value.get("phase_detail"), 220),
        "current_step": _compact_text(value.get("current_step"), 160),
        "eta_seconds": eta_seconds,
        "expected_completion_utc": str(value.get("expected_completion_utc") or "").strip(),
        "latest_error": _compact_text(value.get("latest_error"), 220),
        "latest_error_at": str(value.get("latest_error_at") or "").strip(),
        "latest_error_age": _format_age(value.get("latest_error_at")),
        "latest_resolution": _compact_text(value.get("latest_resolution"), 220),
        "latest_resolution_at": str(value.get("latest_resolution_at") or "").strip(),
        "latest_resolution_age": _format_age(value.get("latest_resolution_at")),
        "summary": _compact_text(value.get("summary") or "No training status is currently published.", 220),
        "warnings": _normalize_string_list(value.get("warnings"), limit=8, item_limit=200),
        "errors": _normalize_string_list(value.get("errors"), limit=8, item_limit=200),
        "resolutions": _normalize_string_list(value.get("resolutions"), limit=8, item_limit=200),
        "recent_events": _normalize_training_events(value.get("recent_events") or value.get("events"), limit=8),
        "stages": _normalize_training_stages(value.get("stages"), limit=8),
        "artifacts": {
            "output_dir": str(artifacts.get("output_dir") or "").strip(),
            "trace_path": str(artifacts.get("trace_path") or "").strip(),
        },
        "idle_policy": {},
    }


def _normalize_idle_training_policy(value: Any, training_status: dict[str, Any]) -> dict[str, Any]:
    payload = value if isinstance(value, dict) else {}
    tod_did_this = str(payload.get("tod_did_this") or "").strip()
    tod_next_action = _compact_text(payload.get("tod_next_action"), 220)
    current_tod_state = str(payload.get("current_tod_state") or "unknown").strip() or "unknown"
    current_mim_state = str(payload.get("current_mim_state") or "unknown").strip() or "unknown"
    current_profile = ""
    current_profile_label = ""
    match = re.match(r"^idle_training_profile_(?:started|failed):(?P<profile>[A-Za-z0-9_.-]+)(?::(?P<reason>.*))?$", tod_did_this)
    if match:
        current_profile = str(match.group("profile") or "").strip().lower()
    elif bool(training_status.get("active")):
        current_profile = "runtime_safe_subset"

    if current_profile == "repo_edit_test_recover":
        current_profile_label = "Repo edit / test / recover pack"
    elif current_profile == "runtime_safe_subset":
        current_profile_label = "Runtime-safe validation subset"

    activity_summary = tod_next_action or _compact_text(tod_did_this, 220) or "No autonomy activity is currently published."
    return {
        "continuous_idle_enabled": True,
        "idle_threshold_minutes": 0,
        "simulation_cooldown_minutes": 0,
        "solicitation_cooldown_minutes": 60,
        "long_idle_profile_threshold_minutes": 30,
        "short_idle_profile": "runtime_safe_subset",
        "short_idle_profile_label": "Runtime-safe validation subset",
        "long_idle_profile": "repo_edit_test_recover",
        "long_idle_profile_label": "Repo edit / test / recover pack",
        "policy_summary": "TOD should train on every idle cycle. Short idle windows stay on the runtime-safe subset, and long idle windows escalate into the repo edit / test / recover pack.",
        "activity_summary": activity_summary,
        "current_tod_state": current_tod_state,
        "current_mim_state": current_mim_state,
        "current_profile": current_profile,
        "current_profile_label": current_profile_label,
    }


def _sanitize_session_key(value: Any) -> str:
    raw = str(value or "tod-console-public").strip() or "tod-console-public"
    collapsed = re.sub(r"[^A-Za-z0-9_.-]+", "-", raw).strip("-._")
    if not collapsed:
        collapsed = "tod-console-public"
    if len(collapsed) <= 96:
        return collapsed
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:12]
    return f"{collapsed[:72]}-{digest}"


def _chat_session_path(session_key: str) -> Path:
    return TOD_CONSOLE_CHAT_ROOT / f"{_sanitize_session_key(session_key)}.json"


def _chat_state_marker(state: dict[str, Any]) -> dict[str, str]:
    quick_facts = state.get("quick_facts") if isinstance(state.get("quick_facts"), dict) else {}
    status = state.get("status") if isinstance(state.get("status"), dict) else {}
    return {
        "canonical_objective": _normalize_objective_token(quick_facts.get("canonical_objective")),
        "status_code": str(status.get("code") or "").strip().lower(),
    }


def _tod_ui_media_url(asset_name: str) -> str:
    return f"/tod/ui/chat/media/{asset_name}"


def _normalize_chat_attachment(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    url = str(value.get("url") or value.get("thumbnail_url") or "").strip()
    if not url:
        return None
    return {
        "kind": str(value.get("kind") or "image").strip() or "image",
        "url": url,
        "thumbnail_url": str(value.get("thumbnail_url") or url).strip() or url,
        "mime_type": str(value.get("mime_type") or "").strip().lower(),
        "filename": str(value.get("filename") or "image").strip() or "image",
        "size_bytes": _safe_int(value.get("size_bytes"), 0),
        "sha256": str(value.get("sha256") or "").strip(),
        "local_path": str(value.get("local_path") or "").strip(),
    }


def _persist_public_chat_image(value: Any) -> dict[str, Any]:
    payload = value if isinstance(value, dict) else {}
    mime_type = str(payload.get("mime_type") or "").strip().lower()
    if mime_type not in TOD_UI_ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="unsupported_image_type")
    data_url = str(payload.get("data_url") or "").strip()
    match = re.match(r"^data:(?P<mime>[-\w.+/]+);base64,(?P<data>[A-Za-z0-9+/=\s]+)$", data_url, re.DOTALL)
    if not match:
        raise HTTPException(status_code=400, detail="invalid_image_payload")
    matched_mime = str(match.group("mime") or "").strip().lower()
    if matched_mime != mime_type:
        raise HTTPException(status_code=400, detail="image_mime_mismatch")
    try:
        raw_bytes = base64.b64decode(match.group("data"), validate=True)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail="invalid_image_payload") from exc
    if not raw_bytes:
        raise HTTPException(status_code=400, detail="empty_image_upload")
    if len(raw_bytes) > TOD_UI_MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="image_too_large")
    digest = hashlib.sha256(raw_bytes).hexdigest()
    filename = str(payload.get("filename") or "shared-image").strip() or "shared-image"
    safe_stem = re.sub(r"[^A-Za-z0-9_.-]+", "-", Path(filename).stem).strip("-._") or "shared-image"
    extension = TOD_UI_ALLOWED_IMAGE_TYPES[mime_type]
    asset_name = f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}-{digest[:12]}-{safe_stem[:48]}{extension}"
    TOD_CONSOLE_CHAT_MEDIA_ROOT.mkdir(parents=True, exist_ok=True)
    asset_path = TOD_CONSOLE_CHAT_MEDIA_ROOT / asset_name
    if not asset_path.exists():
        asset_path.write_bytes(raw_bytes)
    return {
        "kind": "image",
        "url": _tod_ui_media_url(asset_name),
        "thumbnail_url": _tod_ui_media_url(asset_name),
        "mime_type": mime_type,
        "filename": filename,
        "size_bytes": len(raw_bytes),
        "sha256": digest,
        "local_path": str(asset_path),
    }


def _should_reset_public_chat_session(payload: dict[str, Any], state: dict[str, Any]) -> bool:
    current_marker = _chat_state_marker(state)
    current_objective = current_marker.get("canonical_objective") or ""
    current_status = current_marker.get("status_code") or ""
    stored_marker = payload.get("state_marker") if isinstance(payload.get("state_marker"), dict) else {}
    stored_objective = _normalize_objective_token(stored_marker.get("canonical_objective"))
    stored_status = str(stored_marker.get("status_code") or "").strip().lower()

    if current_objective and stored_objective and current_objective != stored_objective:
        return True
    if current_status == "aligned" and stored_status and stored_status != "aligned":
        return True
    if current_status == "aligned" and not stored_marker:
        return True
    return False


def _normalize_chat_entries(values: Any, limit: int = 40) -> list[dict[str, Any]]:
    values = values if isinstance(values, list) else []
    messages: list[dict[str, Any]] = []
    for item in values[-limit:]:
        if not isinstance(item, dict):
            continue
        role = str(item.get("role") or item.get("actor") or "tod").strip().lower() or "tod"
        content = _compact_text(item.get("content") or item.get("message") or item.get("text"), 4000)
        created_at = str(item.get("created_at") or item.get("generated_at") or item.get("timestamp") or "").strip()
        if not content:
            continue
        normalized: dict[str, Any] = {
            "role": role,
            "content": content,
            "created_at": created_at or _utc_now_iso(),
        }
        author_name = _friendly_person_name(item.get("author_name"))
        if author_name:
            normalized["author_name"] = author_name
        attachment = _normalize_chat_attachment(item.get("attachment"))
        if attachment:
            normalized["attachment"] = attachment
        messages.append(normalized)
    return messages


def _load_chat_session_payload(session_key: str, state: dict[str, Any] | None = None) -> dict[str, Any]:
    payload = _load_json(_chat_session_path(session_key))
    if state and _sanitize_session_key(session_key) == "tod-console-public" and _should_reset_public_chat_session(payload, state):
        payload = {}
    return {
        "session_key": _sanitize_session_key(session_key),
        "updated_at": str(payload.get("updated_at") or "").strip(),
        "messages": _normalize_chat_entries(payload.get("messages"), limit=40),
        "pending_progress": _normalize_chat_entries(payload.get("pending_progress"), limit=12),
    }


def _save_chat_session_payload(session_key: str, payload: dict[str, Any], state: dict[str, Any] | None = None) -> None:
    path = _chat_session_path(session_key)
    path.parent.mkdir(parents=True, exist_ok=True)
    document = {
        "session_key": _sanitize_session_key(session_key),
        "updated_at": _utc_now_iso(),
        "messages": _normalize_chat_entries(payload.get("messages"), limit=40),
        "pending_progress": _normalize_chat_entries(payload.get("pending_progress"), limit=12),
    }
    if state:
        document["state_marker"] = _chat_state_marker(state)
    path.write_text(json.dumps(document, indent=2), encoding="utf-8")


def _load_chat_messages(session_key: str, state: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    payload = _load_chat_session_payload(session_key, state)
    return list(payload.get("messages") or [])


def _save_chat_messages(session_key: str, messages: list[dict[str, Any]], state: dict[str, Any] | None = None) -> None:
    _save_chat_session_payload(
        session_key,
        {
            "messages": messages[-40:],
            "pending_progress": [],
        },
        state,
    )


def _summarize_requested_task(message: str, limit: int = 180) -> str:
    cleaned = re.sub(r"^\s*tod[\s,:-]*", "", str(message or ""), flags=re.IGNORECASE).strip()
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .")
    return _compact_text(cleaned or message or "the requested repair", limit)


def _recent_chat_attachments(messages: list[dict[str, Any]], limit: int = 1) -> list[dict[str, Any]]:
    attachments: list[dict[str, Any]] = []
    for item in reversed(messages):
        if not isinstance(item, dict):
            continue
        attachment = _normalize_chat_attachment(item.get("attachment"))
        if not attachment:
            continue
        attachments.append(attachment)
        if len(attachments) >= limit:
            break
    attachments.reverse()
    return attachments


def _advance_pending_chat_progress(session_key: str, state: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    payload = _load_chat_session_payload(session_key, state)
    pending = list(payload.get("pending_progress") or [])
    messages = list(payload.get("messages") or [])
    if not pending:
        return messages
    next_item = dict(pending.pop(0))
    next_item["created_at"] = str(next_item.get("created_at") or _utc_now_iso()).strip() or _utc_now_iso()
    messages.append(next_item)
    payload["messages"] = messages[-40:]
    payload["pending_progress"] = pending
    _save_chat_session_payload(session_key, payload, state)
    return list(payload.get("messages") or [])


def _candidate_script_paths(script_name: str) -> list[Path]:
    return [
        PROJECT_ROOT / "scripts" / script_name,
        PROJECT_ROOT.parent / "scripts" / script_name,
    ]


def _first_existing_path(*paths: Path) -> Path | None:
    for path in paths:
        try:
            if path.exists():
                return path
        except OSError:
            continue
    return None


def _powershell_runner() -> str:
    for candidate in ("pwsh", "powershell", "powershell.exe"):
        resolved = shutil.which(candidate)
        if resolved:
            return resolved
    return ""


def _systemctl_runner() -> str:
    return shutil.which("systemctl") or ""


def _resolve_training_objective_id(state: dict[str, Any]) -> str:
    quick_facts = state.get("quick_facts") if isinstance(state.get("quick_facts"), dict) else {}
    alignment = state.get("objective_alignment") if isinstance(state.get("objective_alignment"), dict) else {}
    live_task = state.get("live_task_request") if isinstance(state.get("live_task_request"), dict) else {}
    objective_text = _pick_first_text(
        live_task.get("objective_id"),
        live_task.get("normalized_objective_id"),
        quick_facts.get("live_request_objective"),
        quick_facts.get("canonical_objective"),
        alignment.get("tod_current_objective"),
        alignment.get("mim_objective_active"),
    )
    objective_token = _normalize_objective_token(objective_text)
    return f"objective-{objective_token}" if objective_token else ""


def _resolve_training_request() -> dict[str, Any]:
    request_path = SHARED_RUNTIME_ROOT / "MIM_TOD_TASK_REQUEST.latest.json"
    trigger_path = SHARED_RUNTIME_ROOT / "MIM_TO_TOD_TRIGGER.latest.json"
    return {
        "available": True,
        "reason": "ready",
        "launcher_type": "mim_to_tod_bridge_request",
        "request_path": str(request_path),
        "trigger_path": str(trigger_path),
        "tod_action": "start-training-runbook",
    }


def _publish_task_execution_request(message: str, state: dict[str, Any], surface: str, session_key: str) -> dict[str, Any]:
    started_at = _utc_now_iso()
    request_path = SHARED_RUNTIME_ROOT / "MIM_TOD_TASK_REQUEST.latest.json"
    trigger_path = SHARED_RUNTIME_ROOT / "MIM_TO_TOD_TRIGGER.latest.json"
    live_task = state.get("live_task_request") if isinstance(state.get("live_task_request"), dict) else {}
    quick_facts = state.get("quick_facts") if isinstance(state.get("quick_facts"), dict) else {}
    prompt_objective_id = _extract_labeled_prompt_value(message, "OBJECTIVE_ID")
    prompt_title = _extract_labeled_prompt_value(message, "TITLE")
    prompt_mission = _extract_labeled_prompt_value(message, "MISSION")
    prompt_primary_outcome = _extract_labeled_prompt_value(message, "PRIMARY OUTCOME")
    objective_id = _pick_first_text(
        prompt_objective_id,
        str(live_task.get("objective_id") or "").strip(),
        str(live_task.get("normalized_objective_id") or "").strip(),
        str(quick_facts.get("canonical_objective") or "").strip(),
    ) or "objective-unknown"
    normalized_objective = _normalize_objective_token(objective_id) or objective_id.lower().replace(" ", "-")
    request_sequence = int(datetime.now(timezone.utc).timestamp() * 1000)
    reuse_live_identity = _should_reuse_live_task_identity(live_task, prompt_objective_id)
    request_id = (
        str(live_task.get("request_id") or "").strip()
        if reuse_live_identity
        else ""
    ) or f"{normalized_objective}-task-{request_sequence}"
    task_id = (
        str(live_task.get("task_id") or "").strip()
        if reuse_live_identity
        else ""
    ) or request_id
    correlation_id = f"tod-chat-task-{request_sequence}"
    title = _pick_first_text(prompt_title, _summarize_requested_task(message, 180), "TOD chat execution task")
    task_focus = _pick_first_text(prompt_title, title, _summarize_requested_task(message, 180), "the requested local execution task")
    next_validation = _next_validation_check(state)
    acceptance = _pick_first_text(prompt_primary_outcome, next_validation, "Publish bounded execution evidence and validation output.")
    description = _pick_first_text(prompt_mission, task_focus, _compact_text(message, 220), title)
    request_payload = {
        "packet_type": "mim-tod-task-request-v1",
        "generated_at": started_at,
        "source": f"tod-ui-{surface}-operator-v1",
        "target": "TOD",
        "request_id": request_id,
        "task_id": task_id,
        "objective_id": objective_id,
        "correlation_id": correlation_id,
        "sequence": request_sequence,
        "tod_action": "execute-chat-task",
        "title": title,
        "description": description,
        "priority": "high",
        "scope": task_focus,
        "acceptance_criteria": acceptance,
        "success_criteria": acceptance,
        "requested_outcome": acceptance,
        "task_classification": "programming",
        "capability_name": "tod_local_execution_chat_task",
        "assigned_executor": "codex",
        "content": _compact_text(message, 4000),
        "session_key": _sanitize_session_key(session_key),
    }
    request_text = json.dumps(request_payload, indent=2, ensure_ascii=True)
    request_sha256 = hashlib.sha256(request_text.encode("utf-8")).hexdigest()
    trigger_payload = {
        "packet_type": "mim-to-tod-trigger-v1",
        "generated_at": started_at,
        "emitted_at": started_at,
        "source_actor": "MIM",
        "target_actor": "TOD",
        "source_service": f"tod-ui-{surface}",
        "trigger": request_id,
        "artifact": request_path.name,
        "artifact_path": str(request_path),
        "artifact_sha256": request_sha256,
        "task_id": task_id,
        "correlation_id": correlation_id,
    }
    record: dict[str, Any] = {
        "generated_at": started_at,
        "action": "publish_task_execution_request",
        "surface": surface,
        "session_key": _sanitize_session_key(session_key),
        "request_id": request_id,
        "task_id": task_id,
        "objective_id": objective_id,
        "tod_action": "execute-chat-task",
        "ok": False,
        "status": "failed",
    }
    try:
        _write_shared_json(request_path, request_payload)
        _write_shared_json(trigger_path, trigger_payload)
        record.update(
            {
                "ok": True,
                "status": "published",
                "request_path": str(request_path),
                "trigger_path": str(trigger_path),
                "scope": task_focus,
                "acceptance_criteria": acceptance,
            }
        )
    except Exception as exc:
        record.update({"error": _compact_text(exc, 220)})
    _record_operator_action(record)
    return record


def _record_operator_action(record: dict[str, Any]) -> None:
    TOD_OPERATOR_ACTION_ROOT.mkdir(parents=True, exist_ok=True)
    latest_path = TOD_OPERATOR_ACTION_ROOT / "TOD_OPERATOR_ACTION.latest.json"
    log_path = TOD_OPERATOR_ACTION_ROOT / "TOD_OPERATOR_ACTION.log.jsonl"
    latest_path.write_text(json.dumps(record, indent=2), encoding="utf-8")
    _append_jsonl_record(log_path, record)


def _extract_labeled_prompt_value(message: str, label: str) -> str:
    text = str(message or "")
    lines = text.splitlines()
    label_pattern = re.compile(rf"^\s*{re.escape(label)}\s*:\s*(.*)$", re.IGNORECASE)
    next_label_pattern = re.compile(r"^\s*[A-Z][A-Z0-9_ -]{2,}\s*:\s*(.*)$")
    for index, line in enumerate(lines):
        match = label_pattern.match(line)
        if not match:
            continue
        collected = [str(match.group(1) or "").strip()]
        for next_line in lines[index + 1 :]:
            if next_label_pattern.match(next_line):
                break
            stripped = str(next_line or "").strip()
            if stripped:
                collected.append(stripped)
        return _compact_text(" ".join(item for item in collected if item), 220)
    pattern = re.compile(rf"{re.escape(label)}\s*:\s*(.+?)(?=\s+[A-Z][A-Z0-9_ -]{{2,}}\s*:|$)", re.IGNORECASE | re.DOTALL)
    match = pattern.search(text)
    if not match:
        return ""
    return _compact_text(match.group(1), 220)


def _write_shared_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=True), encoding="utf-8")


def _load_execution_feedback_config() -> dict[str, Any]:
    config_path = PROJECT_ROOT / "tod" / "config" / "tod-config.json"
    payload = _load_json(config_path)
    feedback = payload.get("execution_feedback") if isinstance(payload.get("execution_feedback"), dict) else {}
    base_url = str(payload.get("mim_base_url") or "").strip() or TOD_EXECUTION_FEEDBACK_DEFAULT_BASE_URL
    timeout_seconds = payload.get("timeout_seconds")
    try:
        resolved_timeout = max(1, int(timeout_seconds))
    except Exception:
        resolved_timeout = 15
    return {
        "base_url": base_url.rstrip("/"),
        "source": str(feedback.get("source") or "tod").strip() or "tod",
        "auth_token": str(feedback.get("auth_token") or "").strip(),
        "timeout_seconds": resolved_timeout,
    }


def _post_execution_feedback(base_url: str, execution_id: str, payload: dict[str, Any], auth_token: str = "", timeout_seconds: int = 15) -> dict[str, Any]:
    normalized_base = str(base_url or "").strip().rstrip("/") or TOD_EXECUTION_FEEDBACK_DEFAULT_BASE_URL
    normalized_execution_id = str(execution_id or "").strip()
    if not normalized_execution_id:
        return {"ok": False, "reason": "missing_execution_id"}
    request_url = f"{normalized_base}/gateway/capabilities/executions/{normalized_execution_id}/feedback"
    body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if auth_token:
        headers["Authorization"] = f"Bearer {auth_token}"
    request = urllib.request.Request(request_url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=max(1, int(timeout_seconds))) as response:
            response_body = response.read().decode("utf-8", errors="replace")
            return {
                "ok": True,
                "status_code": int(getattr(response, "status", 200) or 200),
                "url": request_url,
                "response": _compact_text(response_body, 220),
            }
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        return {
            "ok": False,
            "status_code": int(exc.code),
            "url": request_url,
            "reason": "http_error",
            "error": _compact_text(error_body or exc.reason, 220),
        }
    except Exception as exc:
        return {
            "ok": False,
            "url": request_url,
            "reason": "error",
            "error": _compact_text(exc, 220),
        }


def _publish_execution_feedback_async(execution_id: str, task_id: str, objective_id: str, source: str, summary: str, current_action: str) -> dict[str, Any]:
    normalized_execution_id = str(execution_id or "").strip()
    if not normalized_execution_id:
        return {"queued": False, "reason": "missing_execution_id"}
    if not normalized_execution_id.isdigit():
        return {"queued": False, "reason": "non_numeric_execution_id", "execution_id": normalized_execution_id}

    config = _load_execution_feedback_config()
    accepted_payload = {
        "status": "accepted",
        "source": source,
        "task_id": task_id,
        "timestamp": _utc_now_iso(),
        "details": {
            "objective_id": objective_id,
            "reason": "tod accepted execution",
            "runtime_outcome": "",
            "recovery_state": "",
            "summary": summary,
        },
    }
    running_payload = {
        "status": "running",
        "source": source,
        "task_id": task_id,
        "timestamp": _utc_now_iso(),
        "details": {
            "objective_id": objective_id,
            "reason": current_action,
            "runtime_outcome": "",
            "recovery_state": "",
            "summary": summary,
        },
    }

    def _worker() -> None:
        attempts = [
            _post_execution_feedback(
                config["base_url"],
                normalized_execution_id,
                accepted_payload,
                auth_token=str(config.get("auth_token") or ""),
                timeout_seconds=int(config.get("timeout_seconds") or 15),
            ),
            _post_execution_feedback(
                config["base_url"],
                normalized_execution_id,
                running_payload,
                auth_token=str(config.get("auth_token") or ""),
                timeout_seconds=int(config.get("timeout_seconds") or 15),
            ),
        ]
        _record_operator_action(
            {
                "generated_at": _utc_now_iso(),
                "action": "publish_execution_feedback",
                "execution_id": normalized_execution_id,
                "task_id": task_id,
                "objective_id": objective_id,
                "ok": all(bool(item.get("ok")) for item in attempts),
                "status": "published" if all(bool(item.get("ok")) for item in attempts) else "partial_failure",
                "attempts": attempts,
            }
        )

    thread = threading.Thread(target=_worker, name=f"tod-ui-feedback-{normalized_execution_id}", daemon=True)
    thread.start()
    return {
        "queued": True,
        "base_url": config["base_url"],
        "execution_id": normalized_execution_id,
    }


def _publish_local_execution_ack(message: str, state: dict[str, Any], surface: str, session_key: str) -> dict[str, Any]:
    started_at = _utc_now_iso()
    live_task = state.get("live_task_request") if isinstance(state.get("live_task_request"), dict) else {}
    quick_facts = state.get("quick_facts") if isinstance(state.get("quick_facts"), dict) else {}
    prompt_objective_id = _extract_labeled_prompt_value(message, "OBJECTIVE_ID")
    prompt_title = _extract_labeled_prompt_value(message, "TITLE")
    prompt_mission = _extract_labeled_prompt_value(message, "MISSION")
    prompt_primary_outcome = _extract_labeled_prompt_value(message, "PRIMARY OUTCOME")
    objective_id = _pick_first_text(
        prompt_objective_id,
        str(live_task.get("objective_id") or "").strip(),
        str(live_task.get("normalized_objective_id") or "").strip(),
        str(quick_facts.get("canonical_objective") or "").strip(),
    ) or "objective-unknown"
    normalized_objective = _normalize_objective_token(objective_id) or objective_id.lower().replace(" ", "-")
    request_sequence = int(datetime.now(timezone.utc).timestamp() * 1000)
    reuse_live_identity = _should_reuse_live_task_identity(live_task, prompt_objective_id)
    request_id = (
        str(live_task.get("request_id") or "").strip()
        if reuse_live_identity
        else ""
    ) or f"{normalized_objective}-task-{request_sequence}"
    task_id = (
        str(live_task.get("task_id") or "").strip()
        if reuse_live_identity
        else ""
    ) or request_id
    execution_id = (
        str(live_task.get("execution_id") or "").strip()
        if reuse_live_identity
        else ""
    ) or request_id
    existing_runtime = _load_existing_execution_runtime_payloads()
    if _existing_runtime_matches_active_execution(existing_runtime, objective_id, task_id, execution_id):
        existing_execution = existing_runtime.get("execution_result") if isinstance(existing_runtime.get("execution_result"), dict) else {}
        existing_active_task = existing_runtime.get("active_task") if isinstance(existing_runtime.get("active_task"), dict) else {}
        existing_summary = _compact_text(
            existing_execution.get("summary")
            or existing_active_task.get("summary")
            or "TOD preserved the current local execution runtime state for the active task.",
            220,
        )
        existing_current_action = _compact_text(
            existing_execution.get("current_action")
            or existing_active_task.get("current_action")
            or "Preserving the current local execution runtime state.",
            220,
        )
        existing_next_step = _compact_text(
            existing_execution.get("next_step")
            or existing_active_task.get("next_step")
            or "Continue the active bounded local execution without resetting runtime progress.",
            220,
        )
        existing_next_validation = str(
            existing_execution.get("next_validation")
            or existing_active_task.get("next_validation")
            or _next_validation_check(state)
        ).strip()
        feedback_publish = _publish_execution_feedback_async(
            execution_id=execution_id,
            task_id=task_id,
            objective_id=objective_id,
            source=f"tod-ui-{surface}-operator-v1",
            summary=existing_summary,
            current_action=existing_current_action,
        )
        record = {
            "generated_at": started_at,
            "action": "publish_local_execution_ack",
            "surface": surface,
            "request_id": request_id,
            "task_id": task_id,
            "execution_id": execution_id,
            "objective_id": objective_id,
            "ok": True,
            "status": "preserved",
            "summary": existing_summary,
            "current_action": existing_current_action,
            "next_step": existing_next_step,
            "next_validation": existing_next_validation,
            "execution_summary": existing_summary,
            "execution_evidence": existing_execution.get("execution_evidence")
            if isinstance(existing_execution.get("execution_evidence"), dict)
            else existing_active_task.get("execution_evidence")
            if isinstance(existing_active_task.get("execution_evidence"), dict)
            else {},
            "gateway_feedback": feedback_publish,
            "preserved_existing_execution": True,
        }
        _record_operator_action(record)
        return record
    title = _pick_first_text(prompt_title, _summarize_requested_task(message, 180), "TOD local execution task")
    task_focus = _pick_first_text(_summarize_requested_task(message, 180), title, "the requested local execution task")
    next_validation = _next_validation_check(state)
    evidence = _strongest_evidence(state)
    summary = f"TOD accepted {task_focus} and published execution confirmation for the active objective."
    current_action = "Publishing local execution confirmation and phase-1 execution artifacts."
    next_step = "Continue the task through bounded step execution, validation, evidence publication, and next-step selection."
    artifacts = build_execution_loop_contract_artifacts(
        started_at=started_at,
        source=f"tod-ui-{surface}-operator-v1",
        surface=surface,
        session_key=_sanitize_session_key(session_key),
        request_id=request_id,
        task_id=task_id,
        execution_id=execution_id,
        objective_id=objective_id,
        normalized_objective_id=normalized_objective,
        title=title,
        summary=summary,
        task_focus=task_focus,
        mission=prompt_mission,
        primary_outcome=prompt_primary_outcome,
        strongest_evidence=evidence,
        next_validation=next_validation,
    )
    base_payload = artifacts["base_payload"]
    active_objective_payload = artifacts["active_objective_payload"]
    active_task_payload = artifacts["active_task_payload"]
    activity_event = artifacts["activity_event"]
    validation_payload = artifacts["validation_payload"]
    execution_result_payload = artifacts["execution_result_payload"]
    execution_truth_payload = artifacts["execution_truth_payload"]
    inspection_result = execute_bounded_local_inspection(
        workspace_root=PROJECT_ROOT.parent,
        project_root=PROJECT_ROOT,
        task_focus=task_focus,
        next_validation=next_validation,
    )
    inspection_status = str(inspection_result.get("status") or "blocked").strip().lower()
    inspection_ok = bool(inspection_result.get("validation_passed")) and inspection_status == "completed"
    inspection_updated_at = _utc_now_iso()
    current_action = _compact_text(inspection_result.get("current_action"), 220)
    next_step = _compact_text(inspection_result.get("next_step"), 220)
    execution_summary = _compact_text(inspection_result.get("summary"), 220)
    active_task_payload.update(
        {
            "status": "running" if inspection_ok else "blocked",
            "execution_state": "waiting_on_next_step" if inspection_ok else "blocked",
            "current_action": current_action,
            "next_step": next_step,
            "next_validation": str(inspection_result.get("next_validation") or next_validation).strip(),
            "wait_target": str(inspection_result.get("wait_target") or "").strip(),
            "wait_target_label": str(inspection_result.get("wait_target_label") or "").strip(),
            "wait_reason": _compact_text(inspection_result.get("wait_reason"), 220),
            "summary": execution_summary,
            "updated_at": inspection_updated_at,
            "execution_evidence": inspection_result,
        }
    )
    active_objective_payload.update(
        {
            "updated_at": inspection_updated_at,
            "summary": execution_summary,
            "execution_evidence": inspection_result,
        }
    )
    execution_contract = active_task_payload.get("execution_contract") if isinstance(active_task_payload.get("execution_contract"), dict) else {}
    if execution_contract:
        bounded_step_planner = execution_contract.get("bounded_step_planner") if isinstance(execution_contract.get("bounded_step_planner"), dict) else {}
        active_step = bounded_step_planner.get("active_step") if isinstance(bounded_step_planner.get("active_step"), dict) else {}
        if active_step:
            active_step.update(
                {
                    "status": inspection_status,
                    "summary": execution_summary,
                    "observed_files": inspection_result.get("matched_files") or [],
                }
            )
        bounded_step_planner.update(
            {
                "status": inspection_status,
                "next_validation": str(inspection_result.get("next_validation") or next_validation).strip(),
            }
        )
        command_runner = execution_contract.get("command_runner") if isinstance(execution_contract.get("command_runner"), dict) else {}
        command_runner.update(
            {
                "status": "completed" if inspection_ok else "blocked",
                "summary": _compact_text(inspection_result.get("command_output"), 220),
                "mode": "filesystem_inspection",
            }
        )
        patch_writer = execution_contract.get("patch_writer") if isinstance(execution_contract.get("patch_writer"), dict) else {}
        patch_writer.update(
            {
                "status": "pending",
                "summary": "No patch has been prepared yet; the local execution loop completed workspace inspection first.",
            }
        )
        validator = execution_contract.get("validator") if isinstance(execution_contract.get("validator"), dict) else {}
        validator.update(
            {
                "status": "passed" if inspection_ok else "blocked",
                "target": str(inspection_result.get("next_validation") or next_validation).strip(),
                "summary": execution_summary,
                "checks": inspection_result.get("validation_checks") or [],
            }
        )
        result_publisher = execution_contract.get("result_publisher") if isinstance(execution_contract.get("result_publisher"), dict) else {}
        result_publisher.update(
            {
                "status": "completed" if inspection_ok else "blocked",
                "latest_summary": execution_summary,
            }
        )
        execution_contract["status"] = "running" if inspection_ok else "blocked"
        active_task_payload["execution_contract"] = execution_contract
        active_objective_payload["execution_contract"] = execution_contract
    activity_event.update(
        {
            "event": "bounded_step_completed" if inspection_ok else "bounded_step_blocked",
            "status": "waiting" if inspection_ok else "blocked",
            "phase": "workspace_inspection",
            "current_action": current_action,
            "next_step": next_step,
            "next_validation": str(inspection_result.get("next_validation") or next_validation).strip(),
            "wait_target": str(inspection_result.get("wait_target") or "").strip(),
            "wait_target_label": str(inspection_result.get("wait_target_label") or "").strip(),
            "wait_reason": _compact_text(inspection_result.get("wait_reason"), 220),
            "summary": execution_summary,
            "updated_at": inspection_updated_at,
            "execution_state": "waiting_on_next_step" if inspection_ok else "blocked",
            "execution_evidence": inspection_result,
        }
    )
    validation_payload.update(
        {
            "status": "passed" if inspection_ok else "blocked",
            "phase": "workspace_inspection",
            "validation_target": str(inspection_result.get("next_validation") or next_validation).strip(),
            "summary": execution_summary,
            "updated_at": inspection_updated_at,
            "checks": inspection_result.get("validation_checks") or [],
            "evidence": {
                "matched_files": inspection_result.get("matched_files") or [],
                "command_output": inspection_result.get("command_output") or "",
            },
        }
    )
    execution_result_payload.update(
        {
            "execution_state": "waiting_on_next_step" if inspection_ok else "blocked",
            "status": "waiting" if inspection_ok else "blocked",
            "phase": "workspace_inspection",
            "summary": execution_summary,
            "current_action": current_action,
            "next_step": next_step,
            "wait_target": str(inspection_result.get("wait_target") or "").strip(),
            "wait_target_label": str(inspection_result.get("wait_target_label") or "").strip(),
            "wait_reason": _compact_text(inspection_result.get("wait_reason"), 220),
            "updated_at": inspection_updated_at,
            "validation_summary": execution_summary,
            "command_output": inspection_result.get("command_output") or "",
            "files_changed": inspection_result.get("files_changed") or [],
            "rollback_state": inspection_result.get("rollback_state") or "not_needed",
            "recovery_state": inspection_result.get("recovery_state") or "not_needed",
            "execution_evidence": inspection_result,
        }
    )
    truth_summary = execution_truth_payload.get("summary") if isinstance(execution_truth_payload.get("summary"), dict) else {}
    truth_summary.update(
        {
            "latest_execution_at": inspection_updated_at,
            "summary": execution_summary,
            "current_action": current_action,
            "next_step": next_step,
            "validation_passed": inspection_ok,
        }
    )
    execution_truth_payload["generated_at"] = inspection_updated_at
    execution_truth_payload["summary"] = truth_summary
    recent_truth = execution_truth_payload.get("recent_execution_truth") if isinstance(execution_truth_payload.get("recent_execution_truth"), list) else []
    if recent_truth and isinstance(recent_truth[0], dict):
        recent_truth[0].update(
            {
                "generated_at": inspection_updated_at,
                "execution_state": "waiting_on_next_step" if inspection_ok else "blocked",
                "status": "waiting" if inspection_ok else "blocked",
                "summary": execution_summary,
                "current_action": current_action,
                "next_step": next_step,
                "next_validation": str(inspection_result.get("next_validation") or next_validation).strip(),
                "validation_passed": inspection_ok,
                "execution_evidence": inspection_result,
            }
        )
    record = {
        "generated_at": started_at,
        "action": "publish_local_execution_ack",
        "surface": surface,
        "request_id": request_id,
        "task_id": task_id,
        "execution_id": execution_id,
        "objective_id": objective_id,
        "ok": False,
        "status": "failed",
        "summary": summary,
    }
    try:
        _write_shared_json(SHARED_RUNTIME_ROOT / "TOD_ACTIVE_OBJECTIVE.latest.json", active_objective_payload)
        _write_shared_json(SHARED_RUNTIME_ROOT / "TOD_ACTIVE_TASK.latest.json", active_task_payload)
        _write_shared_json(SHARED_RUNTIME_ROOT / "TOD_ACTIVITY_STREAM.latest.json", activity_event)
        _write_shared_json(SHARED_RUNTIME_ROOT / "TOD_VALIDATION_RESULT.latest.json", validation_payload)
        _write_shared_json(SHARED_RUNTIME_ROOT / "TOD_EXECUTION_RESULT.latest.json", execution_result_payload)
        _write_shared_json(SHARED_RUNTIME_ROOT / "TOD_EXECUTION_TRUTH.latest.json", execution_truth_payload)
        feedback_publish = _publish_execution_feedback_async(
            execution_id=execution_id,
            task_id=task_id,
            objective_id=objective_id,
            source=str(base_payload["source"]),
            summary=summary,
            current_action=current_action,
        )
        record.update({
            "ok": True,
            "status": "published",
            "current_action": current_action,
            "next_step": next_step,
            "next_validation": str(inspection_result.get("next_validation") or next_validation).strip(),
            "execution_summary": execution_summary,
            "execution_evidence": inspection_result,
            "gateway_feedback": feedback_publish,
        })
    except Exception as exc:
        record.update({
            "error": _compact_text(exc, 220),
            "message": "TOD execution confirmation could not be published.",
        })
    _record_operator_action(record)
    return record


def _start_training_runbook(state: dict[str, Any]) -> dict[str, Any]:
    details = _resolve_training_request()
    started_at = _utc_now_iso()
    objective_id = _resolve_training_objective_id(state)
    request_timestamp = started_at.replace("-", "").replace(":", "").replace("Z", "")
    request_sequence = int(datetime.now(timezone.utc).timestamp() * 1000)
    request_id = f"{objective_id or 'objective-0'}-task-{request_sequence}"
    correlation_id = f"training-runbook-{request_timestamp}"
    sequence = request_sequence
    record: dict[str, Any] = {
        "generated_at": started_at,
        "action": "start_training_runbook",
        "details": details,
        "ok": False,
        "status": "unavailable",
    }
    if not details.get("available"):
        record["message"] = "Training request lane is not available from this host."
        _record_operator_action(record)
        return record

    request_path = Path(str(details.get("request_path") or "").strip())
    trigger_path = Path(str(details.get("trigger_path") or "").strip())
    request_payload = {
        "packet_type": "mim-tod-task-request-v1",
        "generated_at": started_at,
        "source": "tod-ui-chat-operator-v1",
        "target": "TOD",
        "request_id": request_id,
        "task_id": request_id,
        "objective_id": objective_id,
        "correlation_id": correlation_id,
        "sequence": sequence,
        "tod_action": str(details.get("tod_action") or "start-training-runbook").strip(),
        "title": "Start TOD 6h training runbook",
        "description": "Launch the bounded TOD 6-hour training runbook asynchronously from the operator chat surface.",
        "priority": "high",
        "success_criteria": "The TOD host launches the 6-hour training runbook and begins updating training status artifacts.",
    }
    request_text = json.dumps(request_payload, indent=2, ensure_ascii=True)
    request_sha256 = hashlib.sha256(request_text.encode("utf-8")).hexdigest()
    trigger_payload = {
        "packet_type": "mim-to-tod-trigger-v1",
        "generated_at": started_at,
        "emitted_at": started_at,
        "source_actor": "MIM",
        "target_actor": "TOD",
        "source_service": "tod-ui-chat",
        "trigger": request_id,
        "artifact": request_path.name,
        "artifact_path": str(request_path),
        "artifact_sha256": request_sha256,
        "task_id": request_id,
        "correlation_id": correlation_id,
        "action_required": "execute",
        "ack_file_expected": "TOD_TO_MIM_TRIGGER_ACK.latest.json",
        "sequence": sequence,
    }
    try:
        request_path.parent.mkdir(parents=True, exist_ok=True)
        trigger_path.parent.mkdir(parents=True, exist_ok=True)
        request_path.write_text(request_text, encoding="utf-8")
        trigger_path.write_text(json.dumps(trigger_payload, indent=2, ensure_ascii=True), encoding="utf-8")
        record.update(
            {
                "ok": True,
                "status": "queued",
                "message": "Training request published to the canonical MIM->TOD listener lane.",
                "request_id": request_id,
                "task_id": request_id,
                "objective_id": objective_id,
                "correlation_id": correlation_id,
                "request_sha256": request_sha256,
            }
        )
    except Exception as exc:
        record.update(
            {
                "status": "failed_to_queue",
                "error": _compact_text(exc, 220),
                "message": "Training request could not be published to the canonical listener lane.",
            }
        )
    _record_operator_action(record)
    return record


def _format_training_start_reply(result: dict[str, Any]) -> str:
    if result.get("ok"):
        return "\n".join(
            [
                "Training request queued.",
                f"Queued at: {str(result.get('generated_at') or '').strip() or _utc_now_iso()}",
                f"Request ID: {str(result.get('request_id') or 'unknown').strip() or 'unknown'}",
                f"Objective: {str(result.get('objective_id') or 'unknown').strip() or 'unknown'}",
                f"Launcher: {str((result.get('details') or {}).get('launcher_type') or 'unknown').strip() or 'unknown'}",
                f"Action: {str((result.get('details') or {}).get('tod_action') or 'unknown').strip() or 'unknown'}",
                "Next validation: wait for listener ACK/result activity, then refresh training status and verify the newest TOD training artifacts update on this surface.",
            ]
        )
    return "\n".join(
        [
            "Training request did not queue.",
            f"Reason: {str((result.get('details') or {}).get('reason') or result.get('status') or 'unknown').strip() or 'unknown'}",
            f"Request path: {str((result.get('details') or {}).get('request_path') or 'missing').strip() or 'missing'}",
            f"Trigger path: {str((result.get('details') or {}).get('trigger_path') or 'missing').strip() or 'missing'}",
            f"Detail: {str(result.get('error') or result.get('message') or 'No launch detail is available.').strip() or 'No launch detail is available.'}",
        ]
    )


def _append_jsonl_record(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(record, ensure_ascii=True, separators=(",", ":")))
        handle.write("\n")


def _session_preview(message: dict[str, Any]) -> dict[str, Any]:
    return {
        "turn_id": message.get("turn_id"),
        "from": message.get("from"),
        "to": message.get("to"),
        "message_type": message.get("message_type"),
        "summary": message.get("summary"),
        "task_id": message.get("task_id"),
        "correlation_id": message.get("correlation_id"),
        "timestamp": message.get("timestamp"),
    }


def _dialog_session_paths(session_id: str) -> dict[str, Path]:
    safe_session_id = _sanitize_session_key(session_id)
    return {
        "session": DIALOG_ROOT / f"MIM_TOD_DIALOG.session-{safe_session_id}.jsonl",
        "latest": DIALOG_ROOT / f"MIM_TOD_DIALOG.session-{safe_session_id}.latest.json",
        "index": DIALOG_ROOT / "MIM_TOD_DIALOG.sessions.latest.json",
        "log": DIALOG_ROOT / "MIM_TOD_DIALOG.latest.jsonl",
    }


def _next_dialog_turn_id(session_path: Path) -> int:
    if not session_path.exists():
        return 1
    try:
        lines = session_path.read_text(encoding="utf-8").splitlines()
    except Exception:
        return 1
    for line in reversed(lines):
        try:
            payload = json.loads(line)
        except Exception:
            continue
        turn_id = payload.get("turn_id")
        if isinstance(turn_id, int) and turn_id >= 1:
            return turn_id + 1
    return 1


def _upsert_dialog_session_index(session_state: dict[str, Any]) -> None:
    index_path = _dialog_session_paths(str(session_state.get("session_id") or "unknown"))["index"]
    payload = _load_json(index_path)
    sessions = payload.get("sessions") if isinstance(payload.get("sessions"), list) else []
    filtered = [
        item
        for item in sessions
        if isinstance(item, dict) and str(item.get("session_id") or "") != str(session_state.get("session_id") or "")
    ]
    updated = {
        "generated_at": _utc_now_iso(),
        "source": DIALOG_SCHEMA_VERSION,
        "sessions": [session_state, *filtered][:200],
    }
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(json.dumps(updated, indent=2), encoding="utf-8")


def _build_copilot_handoff_paths(session_id: str) -> dict[str, Path]:
    safe_session_id = _sanitize_session_key(session_id)
    return {
        "session": TOD_COPILOT_HANDOFF_ROOT / f"TOD_COPILOT_HANDOFF.{safe_session_id}.json",
        "latest": TOD_COPILOT_HANDOFF_ROOT / "TOD_COPILOT_HANDOFF.latest.json",
    }


def _handoff_status_label(session_state: dict[str, Any]) -> str:
    status = str(session_state.get("status") or "unknown").strip().lower()
    last_message = session_state.get("last_message") if isinstance(session_state.get("last_message"), dict) else {}
    last_from = str(last_message.get("from") or "").strip().upper()
    if last_from == "MIM":
        return "Replied"
    if status == "timed_out":
        return "Timed Out"
    if status == "closed":
        return "Closed"
    if session_state.get("open_reply"):
        return "Awaiting MIM"
    if status:
        return status.replace("_", " ").title()
    return "Unknown"


def _load_recent_copilot_handoffs(
    limit: int = 6,
    current_objective_id: str = "",
    current_request_id: str = "",
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    if not DIALOG_ROOT.exists():
        return items
    current_objective_token = _normalize_objective_token(current_objective_id)
    current_request = str(current_request_id or "").strip()
    for session_state_path in sorted(DIALOG_ROOT.glob("MIM_TOD_DIALOG.session-tod-ui-copilot-*.latest.json"), reverse=True):
        session_state = _load_json(session_state_path)
        if not session_state:
            continue
        session_id = str(session_state.get("session_id") or "").strip()
        if not session_id:
            continue
        handoff_paths = _build_copilot_handoff_paths(session_id)
        handoff_artifact = _load_json(handoff_paths["session"])
        handoff_payload = handoff_artifact.get("handoff") if isinstance(handoff_artifact.get("handoff"), dict) else {}
        issue = handoff_payload.get("issue") if isinstance(handoff_payload.get("issue"), dict) else {}
        ids = handoff_payload.get("ids") if isinstance(handoff_payload.get("ids"), dict) else {}
        last_message = session_state.get("last_message") if isinstance(session_state.get("last_message"), dict) else {}
        request_id = str(ids.get("request_id") or "").strip()
        objective_id = str(ids.get("objective_id") or "").strip()
        objective_token = _normalize_objective_token(objective_id)
        if current_objective_token and objective_token and objective_token != current_objective_token:
            continue
        if current_objective_token and not objective_token and current_request and request_id and request_id != current_request:
            continue
        items.append(
            {
                "session_id": session_id,
                "status": str(session_state.get("status") or "unknown").strip(),
                "status_label": _handoff_status_label(session_state),
                "updated_at": str(session_state.get("updated_at") or "").strip(),
                "updated_age": _format_age(session_state.get("updated_at")),
                "message_count": _safe_int(session_state.get("message_count"), 0),
                "session_path": str(session_state.get("session_path") or session_state_path).strip(),
                "dialog_index_path": str(handoff_artifact.get("dialog_index_path") or _dialog_session_paths(session_id)["index"]).strip(),
                "copilot_artifact_path": str(handoff_paths["session"]),
                "request_id": request_id,
                "task_id": str(ids.get("task_id") or "").strip(),
                "objective_id": objective_id,
                "issue_summary": _pick_first_text(issue.get("summary"), last_message.get("summary")),
                "bounded_repair_request": _pick_first_text(issue.get("bounded_repair_request")),
                "next_validation": _pick_first_text(issue.get("next_validation")),
                "last_message_from": str(last_message.get("from") or "").strip(),
                "last_message_type": str(last_message.get("message_type") or "").strip(),
            }
        )
        if len(items) >= limit:
            break
    return items


def _create_copilot_handoff(
    message: str,
    state: dict[str, Any],
    session_key: str,
    attachments: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    status = state.get("status") if isinstance(state.get("status"), dict) else {}
    quick_facts = state.get("quick_facts") if isinstance(state.get("quick_facts"), dict) else {}
    alignment = state.get("objective_alignment") if isinstance(state.get("objective_alignment"), dict) else {}
    evidence = state.get("bridge_canonical_evidence") if isinstance(state.get("bridge_canonical_evidence"), dict) else {}
    live_task = state.get("live_task_request") if isinstance(state.get("live_task_request"), dict) else {}
    listener = state.get("listener_decision") if isinstance(state.get("listener_decision"), dict) else {}
    publish = state.get("publish") if isinstance(state.get("publish"), dict) else {}
    training = state.get("training_status") if isinstance(state.get("training_status"), dict) else {}
    authority = state.get("authority_reset") if isinstance(state.get("authority_reset"), dict) else {}

    request_id = str(live_task.get("request_id") or "").strip()
    task_id = str(live_task.get("task_id") or "").strip()
    objective_id = str(live_task.get("objective_id") or live_task.get("normalized_objective_id") or "").strip()
    correlation_id = str(live_task.get("correlation_id") or "").strip()
    seed = "|".join(
        [
            request_id or "no-request",
            task_id or "no-task",
            objective_id or "no-objective",
            session_key,
            _compact_text(message, 240),
            _utc_now_iso(),
        ]
    )
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    digest = hashlib.sha1(seed.encode("utf-8")).hexdigest()[:8]
    session_id = _sanitize_session_key(f"tod-ui-copilot-{timestamp}-{digest}")
    paths = _dialog_session_paths(session_id)
    turn_id = _next_dialog_turn_id(paths["session"])
    issue_summary = _pick_first_text(status.get("headline"), status.get("summary")) or "TOD needs review."
    repair_request = _next_bounded_repair_request(state)
    validation = _next_validation_check(state)
    strongest_evidence = _strongest_evidence(state)

    handoff_payload = {
        "source": "tod-ui-copilot-handoff-v1",
        "request_kind": "tod_ui_copilot_handoff",
        "operator_request": _compact_text(message, 1200),
        "attachments": attachments or [],
        "issue": {
            "status_code": str(status.get("code") or "unknown").strip(),
            "status_label": str(status.get("label") or "unknown").strip(),
            "summary": issue_summary,
            "strongest_evidence": strongest_evidence,
            "current_repair_step": _current_repair_step(state),
            "bounded_repair_request": repair_request,
            "next_validation": validation,
        },
        "ids": {
            "request_id": request_id,
            "task_id": task_id,
            "objective_id": objective_id,
            "correlation_id": correlation_id,
        },
        "quick_facts": quick_facts,
        "objective_alignment": alignment,
        "bridge_canonical_evidence": evidence,
        "listener_decision": listener,
        "publish": publish,
        "training_status": {
            "state": training.get("state"),
            "state_label": training.get("state_label"),
            "summary": training.get("summary"),
            "current_step": training.get("current_step"),
            "latest_error": training.get("latest_error"),
            "latest_resolution": training.get("latest_resolution"),
            "percent_complete": training.get("percent_complete"),
        },
        "authority_reset": authority,
        "conversation": {
            "session_key": _sanitize_session_key(session_key),
            "surface": "tod-ui-public-console",
        },
        "requested_reply": {
            "actor": "MIM",
            "message_type": "handoff_response",
            "fields": ["summary", "repair_step", "validation", "missing_artifacts", "next_update"],
        },
    }

    handoff_paths = _build_copilot_handoff_paths(session_id)
    artifact = {
        "generated_at": _utc_now_iso(),
        "source": "tod-ui-copilot-handoff-v1",
        "session_id": session_id,
        "dialog_session_path": str(paths["session"]),
        "dialog_index_path": str(paths["index"]),
        "handoff": handoff_payload,
    }
    handoff_paths["session"].parent.mkdir(parents=True, exist_ok=True)
    handoff_paths["session"].write_text(json.dumps(artifact, indent=2), encoding="utf-8")
    handoff_paths["latest"].write_text(json.dumps(artifact, indent=2), encoding="utf-8")

    summary = f"TOD UI requests Copilot handoff for {request_id or task_id or 'current TOD issue'}."
    dialog_message = {
        "session_id": session_id,
        "turn_id": turn_id,
        "timestamp": _utc_now_iso(),
        "from": "TOD",
        "to": "MIM",
        "message_type": "handoff_request",
        "intent": "tod_ui_copilot_handoff",
        "correlation_id": correlation_id,
        "task_id": task_id,
        "summary": summary,
        "payload": {
            **handoff_payload,
            "artifact_path": str(handoff_paths["session"]),
        },
        "requires_reply": True,
        "schema_version": DIALOG_SCHEMA_VERSION,
    }
    _append_jsonl_record(paths["session"], dialog_message)
    _append_jsonl_record(paths["log"], dialog_message)

    session_state = {
        "session_id": session_id,
        "status": "open",
        "timed_out": False,
        "message_count": turn_id,
        "updated_at": dialog_message["timestamp"],
        "session_path": str(paths["session"]),
        "open_reply": {
            "turn_id": dialog_message["turn_id"],
            "from": dialog_message["from"],
            "to": dialog_message["to"],
            "message_type": dialog_message["message_type"],
            "summary": dialog_message["summary"],
            "timestamp": dialog_message["timestamp"],
        },
        "last_message": _session_preview(dialog_message),
        "awaiting_reply_to": "MIM",
        "reply_to": "",
    }
    paths["latest"].write_text(json.dumps(session_state, indent=2), encoding="utf-8")
    _upsert_dialog_session_index(session_state)

    return {
        "ok": True,
        "session_id": session_id,
        "turn_id": turn_id,
        "summary": summary,
        "artifact_path": str(handoff_paths["session"]),
        "latest_artifact_path": str(handoff_paths["latest"]),
        "dialog_session_path": str(paths["session"]),
        "dialog_session_latest_path": str(paths["latest"]),
        "dialog_index_path": str(paths["index"]),
        "reply_contract": "MIM should answer this session with handoff_response.",
        "request_id": request_id,
        "task_id": task_id,
        "objective_id": objective_id,
    }


def _pick_first_text(*values: Any) -> str:
    for value in values:
        text = _compact_text(value, 320)
        if text and text.lower() not in {"unknown", "none", "inactive", "no publish summary", "no listener decision summary"}:
            return text
    return ""


def _next_bounded_repair_request(state: dict[str, Any]) -> str:
    guidance = state.get("operator_guidance") if isinstance(state.get("operator_guidance"), list) else []
    for item in guidance:
        if isinstance(item, dict):
            text = _pick_first_text(item.get("recommended_action"), item.get("summary"))
            if text:
                return text
    listener = state.get("listener_decision") if isinstance(state.get("listener_decision"), dict) else {}
    training = state.get("training_status") if isinstance(state.get("training_status"), dict) else {}
    publish = state.get("publish") if isinstance(state.get("publish"), dict) else {}
    return _pick_first_text(
        listener.get("next_step_recommendation"),
        training.get("latest_resolution"),
        training.get("current_step"),
        publish.get("summary"),
        "Re-run the bounded bridge diagnosis and validate listener, publish, and canonical objective alignment before changing authority again.",
    )


def _current_repair_step(state: dict[str, Any]) -> str:
    training = state.get("training_status") if isinstance(state.get("training_status"), dict) else {}
    publish = state.get("publish") if isinstance(state.get("publish"), dict) else {}
    listener = state.get("listener_decision") if isinstance(state.get("listener_decision"), dict) else {}
    return _pick_first_text(
        training.get("latest_resolution"),
        training.get("phase_detail"),
        listener.get("next_step_recommendation"),
        publish.get("summary"),
        "No confirmed automated repair step is currently published on this surface.",
    )


def _strongest_evidence(state: dict[str, Any]) -> str:
    evidence = state.get("bridge_canonical_evidence") if isinstance(state.get("bridge_canonical_evidence"), dict) else {}
    listener = state.get("listener_decision") if isinstance(state.get("listener_decision"), dict) else {}
    publish = state.get("publish") if isinstance(state.get("publish"), dict) else {}
    authority = state.get("authority_reset") if isinstance(state.get("authority_reset"), dict) else {}
    training = state.get("training_status") if isinstance(state.get("training_status"), dict) else {}
    signals = evidence.get("failure_signals") if isinstance(evidence.get("failure_signals"), list) else []
    return _pick_first_text(
        "; ".join([_compact_text(item, 140) for item in signals if _compact_text(item, 140)]),
        listener.get("summary"),
        publish.get("summary"),
        authority.get("reason"),
        training.get("latest_error"),
        training.get("summary"),
        state.get("status", {}).get("summary") if isinstance(state.get("status"), dict) else "",
    ) or "No single dominant evidence item is currently published."


def _next_validation_check(state: dict[str, Any]) -> str:
    live_task = state.get("live_task_request") if isinstance(state.get("live_task_request"), dict) else {}
    listener = state.get("listener_decision") if isinstance(state.get("listener_decision"), dict) else {}
    alignment = state.get("objective_alignment") if isinstance(state.get("objective_alignment"), dict) else {}
    publish = state.get("publish") if isinstance(state.get("publish"), dict) else {}
    request_id = str(live_task.get("request_id") or "").strip() or "unknown request"
    task_id = str(live_task.get("task_id") or "").strip() or "unknown task"
    objective_id = str(live_task.get("objective_id") or live_task.get("normalized_objective_id") or "").strip() or "unknown objective"
    return _pick_first_text(
        listener.get("next_step_recommendation"),
        f"Re-check alignment={str(alignment.get('status') or 'unknown').strip()} and publish={str(publish.get('status') or 'unknown').strip()} for request_id={request_id}, task_id={task_id}, objective_id={objective_id}.",
    )


def _classify_prompt(message: str) -> str:
    text = message.lower()
    normalized = re.sub(r"\s+", " ", text)
    if "copilot-style" in text or "handoff" in text or "package the current issue" in text:
        return "handoff"
    if any(
        re.search(pattern, normalized)
        for pattern in (
            r"\bstart(?: your| the| a| next)?\s+(?:bounded\s+)?(?:6h|six[- ]hour\s+)?training(?:\s+(?:cycle|run|runbook|loop))?\b",
            r"\blaunch(?: the| a| your| next)?\s+(?:bounded\s+)?(?:6h|six[- ]hour\s+)?training(?:\s+(?:cycle|run|runbook|loop))?\b",
            r"\bbegin(?: the| a| your| next)?\s+(?:bounded\s+)?(?:6h|six[- ]hour\s+)?training(?:\s+(?:cycle|run|runbook|loop))?\b",
            r"\brun(?: the| a| your| next)?\s+(?:bounded\s+)?(?:6h|six[- ]hour\s+)?training(?:\s+(?:cycle|run|runbook|loop))?\b",
        )
    ):
        return "training"
    if any(token in text for token in ("objective_id", "objective", "active task", "implement", "build", "execution loop contract")):
        return "task"
    if "resolve" in text and ("drift" in text or "mismatch" in text or "out of sync" in text or "out-of-sync" in text):
        return "drift"
    if "out of sync" in text or "out-of-sync" in text or "mismatch" in text:
        return "sync"
    if "attention" in text or "needs review" in text or "blocking" in text or "blocker" in text:
        return "blockers"
    if any(token in text for token in ("can you fix", "fix this", "please fix", "troubleshoot", "debug this", "begin to troubleshoot")):
        return "task"
    return "status"


def _compose_task_worklog(
    task_focus: str,
    strongest_evidence: str,
    current_repair: str,
    next_repair: str,
    next_validation: str,
    request_id: str,
    task_id: str,
    objective_id: str,
) -> str:
    return "\n".join(
        [
            f"Accepted. TOD opened a live troubleshooting lane for {task_focus}.",
            f"Thinking: grounding on the strongest published signal first. {strongest_evidence}",
            f"Working now: {current_repair}",
            f"Applying next: {next_repair}",
            f"Testing next: {next_validation}",
            f"Tracking: request_id={request_id}; task_id={task_id}; objective_id={objective_id}",
        ]
    )


_GENERATED_PROGRESS_PREFIXES = (
    "Accepted. TOD opened a live troubleshooting lane for",
    "Thinking:",
    "Working now:",
    "Applying next:",
    "Testing next:",
    "Tracking:",
    "Dispatch now:",
    "Waiting on:",
    "Execution confirmation was published",
    "Executable task request published",
    "Live execution feed:",
    "Status now:",
    "Execution evidence:",
    "Validation checks:",
    "Validation summary:",
    "Files changed:",
    "Matched surfaces:",
    "Updated:",
)


def _is_generated_progress_message(message: Any) -> bool:
    if not isinstance(message, dict):
        return False
    content = str(message.get("content") or "").strip()
    if not content:
        return False
    return any(content.startswith(prefix) for prefix in _GENERATED_PROGRESS_PREFIXES)


def _trim_trailing_generated_progress(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    trimmed = list(messages)
    while trimmed and _is_generated_progress_message(trimmed[-1]):
        trimmed.pop()
    return trimmed


def _summarize_execution_slice(summary: Any) -> str:
    text = _compact_text(summary, 220)
    if not text:
        return ""
    return _compact_text(text, 140)


def _describe_execution_validation_target(execution: dict[str, Any]) -> str:
    next_validation = _compact_text(execution.get("next_validation"), 220)
    if not next_validation:
        return ""
    normalized = next_validation.strip().lower()
    if normalized in {"execute_now", "run_now"}:
        next_step = _compact_text(execution.get("next_step"), 180)
        if next_step:
            return f"Focused check after: {next_step}"
        return "Run the published focused check now"
    return _compact_text(next_validation, 140)


def _build_task_progress_messages(message: str, state: dict[str, Any], execution_ack: dict[str, Any] | None = None, dispatch_record: dict[str, Any] | None = None) -> list[dict[str, str]]:
    status = state.get("status") if isinstance(state.get("status"), dict) else {}
    live_task = state.get("live_task_request") if isinstance(state.get("live_task_request"), dict) else {}
    strongest_evidence = _strongest_evidence(state)
    current_repair = str((execution_ack or {}).get("current_action") or "").strip() or _current_repair_step(state)
    next_repair = str((execution_ack or {}).get("next_step") or "").strip() or _next_bounded_repair_request(state)
    next_validation = str((execution_ack or {}).get("next_validation") or "").strip() or _next_validation_check(state)
    request_id = str((execution_ack or {}).get("request_id") or live_task.get("request_id") or "").strip() or "Unknown"
    task_id = str((execution_ack or {}).get("task_id") or live_task.get("task_id") or "").strip() or "Unknown"
    objective_id = str((execution_ack or {}).get("objective_id") or live_task.get("objective_id") or live_task.get("normalized_objective_id") or "").strip() or "Unknown"
    task_focus = _pick_first_text(
        _summarize_requested_task(message, 180),
        str((execution_ack or {}).get("summary") or "").strip(),
        str(live_task.get("issue_summary") or "").strip(),
        str(live_task.get("title") or "").strip(),
        str(status.get("summary") or "").strip(),
        "the requested repair",
    )
    created_at = _utc_now_iso()
    progress_messages = [
        {
            "role": "tod",
            "content": f"Accepted. TOD opened a live troubleshooting lane for {task_focus}.",
            "created_at": created_at,
        },
        {
            "role": "system",
            "content": f"Thinking: grounding on the strongest published signal first. {strongest_evidence}",
            "created_at": created_at,
        },
        {
            "role": "system",
            "content": f"Working now: {current_repair}",
            "created_at": created_at,
        },
        {
            "role": "system",
            "content": f"Applying next: {next_repair}",
            "created_at": created_at,
        },
        {
            "role": "system",
            "content": f"Testing next: {next_validation}",
            "created_at": created_at,
        },
        {
            "role": "system",
            "content": f"Tracking: request_id={request_id}; task_id={task_id}; objective_id={objective_id}",
            "created_at": created_at,
        },
    ]
    if dispatch_record and dispatch_record.get("ok"):
        progress_messages.append(
            {
                "role": "tod",
                "content": "Executable task request published to the shared TOD bridge surface. The local TOD listener can now create, package, and run the bounded task instead of stopping at inspection.",
                "created_at": created_at,
            }
        )
        request_path = str(dispatch_record.get("request_path") or "").strip()
        if request_path:
            progress_messages.append(
                {
                    "role": "system",
                    "content": f"Dispatch now: wrote execute-chat-task request to {request_path}.",
                    "created_at": created_at,
                }
            )
        progress_messages.append(
            {
                "role": "system",
                "content": f"Waiting on: TOD local listener to consume request {task_id} and transition the bounded task into package and run-task execution.",
                "created_at": created_at,
            }
        )
    elif execution_ack and execution_ack.get("ok"):
        progress_messages.append(
            {
                "role": "tod",
                "content": "Execution confirmation was published to the shared TOD truth surface, but no executable task request was emitted for the local listener.",
                "created_at": created_at,
            }
        )
    return progress_messages


def _build_execution_feed_messages(state: dict[str, Any]) -> list[dict[str, str]]:
    execution = state.get("execution") if isinstance(state.get("execution"), dict) else {}
    if not execution or not execution.get("available"):
        return []
    created_at = str(execution.get("updated_at") or state.get("generated_at") or _utc_now_iso()).strip() or _utc_now_iso()
    title = (_pick_first_text(execution.get("title"), execution.get("task_focus"), execution.get("task_id")) or "the active TOD execution").rstrip(". ")
    activity_label = _pick_first_text(execution.get("activity_label"), execution.get("execution_state"), execution.get("status")) or "Working"
    activity_summary = _compact_text(execution.get("activity_summary") or execution.get("summary"), 220)
    objective_id = _compact_text(execution.get("objective_id"), 140)
    task_id = _compact_text(execution.get("task_id"), 140)
    summary = _summarize_execution_slice(execution.get("summary"))
    phase_progress = execution.get("phase_progress") if isinstance(execution.get("phase_progress"), dict) else {}
    stall_signal = execution.get("stall_signal") if isinstance(execution.get("stall_signal"), dict) else {}
    messages: list[dict[str, str]] = [
        {
            "role": "tod",
            "content": f"Live execution feed: TOD is {activity_label.lower()} on {title}.",
            "created_at": created_at,
        }
    ]
    execution_lane = ""
    if objective_id and title:
        execution_lane = f"Objective now: {objective_id} -> {title}"
    elif objective_id:
        execution_lane = f"Objective now: {objective_id}"
    elif title:
        execution_lane = f"Task now: {title}"
    elif task_id:
        execution_lane = f"Task now: {task_id}"
    if execution_lane:
        messages.append(
            {
                "role": "system",
                "content": execution_lane,
                "created_at": created_at,
            }
        )
    if summary:
        messages.append(
            {
                "role": "system",
                "content": f"Current slice: {summary}",
                "created_at": created_at,
            }
        )
    if phase_progress.get("available"):
        progress_percent = int(phase_progress.get("percent_complete") or 0)
        phase_label = _compact_text(phase_progress.get("label"), 80) or "Phase progress"
        next_gate = _compact_text(phase_progress.get("next_gate"), 80) or "Unknown"
        progress_summary = _compact_text(phase_progress.get("summary"), 180)
        messages.append(
            {
                "role": "system",
                "content": f"{phase_label}: {progress_percent}% complete. Next gate: {next_gate}.",
                "created_at": created_at,
            }
        )
        if progress_summary:
            messages.append(
                {
                    "role": "system",
                    "content": f"Progress detail: {progress_summary}",
                    "created_at": created_at,
                }
            )
    if activity_summary:
        messages.append(
            {
                "role": "system",
                "content": f"Status now: {activity_label}. {activity_summary}",
                "created_at": created_at,
            }
        )
    if stall_signal.get("flagged") or str(stall_signal.get("level") or "ok").strip().lower() != "ok":
        messages.append(
            {
                "role": "system",
                "content": f"Stall watch: {str(stall_signal.get('summary') or '').strip()}",
                "created_at": created_at,
            }
        )
    current_action = _compact_text(execution.get("current_action"), 220)
    if current_action:
        messages.append(
            {
                "role": "system",
                "content": f"Working now: {current_action}",
                "created_at": created_at,
            }
        )
    wait_reason = _compact_text(execution.get("wait_reason"), 220)
    wait_target = _pick_first_text(execution.get("wait_target_label"), execution.get("wait_target")) or "No explicit wait target published"
    if wait_reason or wait_target:
        messages.append(
            {
                "role": "system",
                "content": f"Waiting on: {wait_target}. {wait_reason or 'No explicit wait reason published.'}",
                "created_at": created_at,
            }
        )
    next_step = _compact_text(execution.get("next_step"), 220)
    if next_step:
        messages.append(
            {
                "role": "system",
                "content": f"Applying next: {next_step}",
                "created_at": created_at,
            }
        )
    next_validation = _describe_execution_validation_target(execution)
    if next_validation:
        messages.append(
            {
                "role": "system",
                "content": f"Testing next: {next_validation}",
                "created_at": created_at,
            }
        )
    command_output = _compact_text(execution.get("command_output"), 220)
    if command_output:
        messages.append(
            {
                "role": "system",
                "content": f"Execution evidence: {command_output}",
                "created_at": created_at,
            }
        )
    validation_summary = _compact_text(execution.get("validation_summary"), 220)
    if validation_summary:
        messages.append(
            {
                "role": "system",
                "content": f"Validation summary: {validation_summary}",
                "created_at": created_at,
            }
        )
    checks = execution.get("validation_checks") if isinstance(execution.get("validation_checks"), list) else []
    if checks:
        check_summary = ", ".join(
            f"{_compact_text(item.get('name'), 80)}={'passed' if bool(item.get('passed')) else 'failed'}"
            for item in checks
            if isinstance(item, dict)
        )
        if check_summary:
            messages.append(
                {
                    "role": "system",
                    "content": f"Validation checks: {check_summary}",
                    "created_at": created_at,
                }
            )
    files_changed = execution.get("files_changed") if isinstance(execution.get("files_changed"), list) else []
    if files_changed:
        messages.append(
            {
                "role": "system",
                "content": f"Files changed: {', '.join(_compact_text(item, 120) for item in files_changed if _compact_text(item, 120))}",
                "created_at": created_at,
            }
        )
    matched_files = execution.get("matched_files") if isinstance(execution.get("matched_files"), list) else []
    if matched_files:
        messages.append(
            {
                "role": "system",
                "content": f"Matched surfaces: {', '.join(_compact_text(item, 120) for item in matched_files if _compact_text(item, 120))}",
                "created_at": created_at,
            }
        )
    updated_age = _pick_first_text(execution.get("updated_age"))
    if updated_age:
        messages.append(
            {
                "role": "system",
                "content": f"Updated: {updated_age}",
                "created_at": created_at,
            }
        )
    return messages


def _messages_include_execution_feed(messages: list[dict[str, Any]], execution_updated_at: str) -> bool:
    if not execution_updated_at:
        return False
    for item in messages:
        if not isinstance(item, dict):
            continue
        if str(item.get("created_at") or "").strip() != execution_updated_at:
            continue
        content = str(item.get("content") or "").strip()
        if content.startswith("Live execution feed:") or content.startswith("Working now:") or content.startswith("Waiting on:"):
            return True
    return False


def _compose_tod_reply(message: str, state: dict[str, Any]) -> str:
    status = state.get("status") if isinstance(state.get("status"), dict) else {}
    alignment = state.get("objective_alignment") if isinstance(state.get("objective_alignment"), dict) else {}
    live_task = state.get("live_task_request") if isinstance(state.get("live_task_request"), dict) else {}
    training = state.get("training_status") if isinstance(state.get("training_status"), dict) else {}
    canonical_objective = _pick_first_text(
        state.get("quick_facts", {}).get("canonical_objective") if isinstance(state.get("quick_facts"), dict) else "",
        alignment.get("mim_objective_active"),
    ) or "Unknown"
    live_objective = _pick_first_text(
        state.get("quick_facts", {}).get("live_request_objective") if isinstance(state.get("quick_facts"), dict) else "",
        live_task.get("objective_id"),
        alignment.get("tod_current_objective"),
    ) or "Unknown"
    issue_summary = _pick_first_text(status.get("headline"), status.get("summary")) or "TOD has no published issue summary."
    strongest_evidence = _strongest_evidence(state)
    current_repair = _current_repair_step(state)
    next_repair = _next_bounded_repair_request(state)
    next_validation = _next_validation_check(state)
    request_id = str(live_task.get("request_id") or "").strip() or "Unknown"
    task_id = str(live_task.get("task_id") or "").strip() or "Unknown"
    objective_id = str(live_task.get("objective_id") or live_task.get("normalized_objective_id") or "").strip() or "Unknown"

    intent = _classify_prompt(message)
    if intent == "training":
        training_state = _pick_first_text(training.get("state_label"), training.get("state")) or "Unknown"
        current_gate = _pick_first_text(training.get("current_step"), training.get("phase_detail"), next_repair)
        first_blocker = _pick_first_text(training.get("latest_error"), status.get("summary"), strongest_evidence)
        return "\n".join(
            [
                "Training execution cannot be started from this public /tod surface.",
                f"Runbook status: {training_state}",
                f"Current gate: {current_gate}",
                f"First blocker: {first_blocker}",
                f"Next bounded action: {next_repair}",
                f"Next validation: {next_validation}",
            ]
        )
    if intent == "drift":
        return "\n".join(
            [
                f"Drift summary: canonical objective={canonical_objective}; live objective={live_objective}; status={str(status.get('label') or 'Unknown').strip() or 'Unknown'}.",
                f"Mismatch detail: {_pick_first_text(alignment.get('summary'), issue_summary)}",
                f"Strongest evidence: {strongest_evidence}",
                f"Current repair step: {current_repair}",
                f"Next validation: {next_validation}",
            ]
        )
    if intent == "handoff":
        return "\n".join(
            [
                "Copilot handoff summary:",
                f"Issue: {issue_summary}",
                f"Evidence: {strongest_evidence}",
                f"Bounded repair request: {next_repair}",
                f"Validation after repair: {next_validation}",
                f"Active IDs: request_id={request_id}; task_id={task_id}; objective_id={objective_id}",
            ]
        )
    if intent == "task":
        task_focus = _pick_first_text(
            _summarize_requested_task(message, 180),
            str(live_task.get("issue_summary") or "").strip(),
            str(live_task.get("title") or "").strip(),
            str(status.get("summary") or "").strip(),
            "the requested repair",
        )
        return _compose_task_worklog(
            task_focus=task_focus,
            strongest_evidence=strongest_evidence,
            current_repair=current_repair,
            next_repair=next_repair,
            next_validation=next_validation,
            request_id=request_id,
            task_id=task_id,
            objective_id=objective_id,
        )
    if intent == "sync":
        return "\n".join(
            [
                f"Current sync gap: canonical objective={canonical_objective}; live objective={live_objective}; listener state={str(state.get('quick_facts', {}).get('listener_state') or 'unknown').strip()}.",
                f"Issue summary: {issue_summary}",
                f"Strongest evidence: {strongest_evidence}",
                f"Next bounded repair: {next_repair}",
                f"Next validation: {next_validation}",
            ]
        )
    if intent == "blockers":
        return "\n".join(
            [
                f"Current blocker posture: {issue_summary}",
                f"Strongest evidence: {strongest_evidence}",
                f"Current repair step: {current_repair}",
                f"Next bounded repair: {next_repair}",
                f"Next validation: {next_validation}",
            ]
        )
    return "\n".join(
        [
            f"TOD status: {issue_summary}",
            f"Strongest evidence: {strongest_evidence}",
            f"Next bounded repair: {next_repair}",
            f"Next validation: {next_validation}",
        ]
    )


def _compose_operator_reply(message: str, state: dict[str, Any], surface_label: str = "/chat") -> str:
    if _classify_prompt(message) == "training":
        return _format_training_start_reply(_start_training_runbook(state))

    base_reply = _compose_tod_reply(message, state)
    if any(token in message.lower() for token in ("execute", "run", "start", "launch")):
        return "\n".join(
            [
                base_reply,
                f"Operator execution is enabled on {surface_label} for bounded actions.",
                "Direct actions available here: Start 6h Training and Send To Codex.",
            ]
        )
    return base_reply


def _build_chat_payload(session_key: str, messages: list[dict[str, Any]], state: dict[str, Any], surface: str = "tod") -> dict[str, Any]:
    status = state.get("status") if isinstance(state.get("status"), dict) else {}
    quick_facts = state.get("quick_facts") if isinstance(state.get("quick_facts"), dict) else {}
    normalized_surface = "chat" if str(surface or "tod").strip().lower() == "chat" else "tod"
    direct_chat_surface = normalized_surface == "chat"
    execution_enabled = True
    training_launcher = _resolve_training_request()
    visitor_name = "Operator" if direct_chat_surface else _resolve_public_visitor_name()
    session_payload = _load_chat_session_payload(session_key, state)
    pending_progress = list(session_payload.get("pending_progress") or [])
    pending_count = len(pending_progress)
    execution = state.get("execution") if isinstance(state.get("execution"), dict) else {}
    execution_feed_messages = _build_execution_feed_messages(state) if not direct_chat_surface else []
    execution_updated_at = str(execution.get("updated_at") or "").strip()
    display_messages = list(messages)
    if not display_messages:
        display_messages = execution_feed_messages
    elif execution_feed_messages and pending_count == 0:
        trimmed_messages = _trim_trailing_generated_progress(display_messages)
        execution_age_seconds = _age_seconds(execution_updated_at)
        last_message_at = str(trimmed_messages[-1].get("created_at") or "").strip() if trimmed_messages else ""
        last_message_age_seconds = _age_seconds(last_message_at)
        last_trimmed_role = str(trimmed_messages[-1].get("role") or "").strip().lower() if trimmed_messages else ""
        should_append_execution_feed = False
        replaced_prior_progress = len(trimmed_messages) != len(display_messages)
        if replaced_prior_progress:
            should_append_execution_feed = True
        if execution_age_seconds is not None and last_message_age_seconds is not None:
            should_append_execution_feed = execution_age_seconds <= last_message_age_seconds
        elif execution_updated_at and not replaced_prior_progress:
            should_append_execution_feed = True
        if last_trimmed_role in {"tod", "assistant", "copilot"}:
            should_append_execution_feed = False
        if should_append_execution_feed:
            display_messages = [*trimmed_messages, *execution_feed_messages]
    last_message = display_messages[-1] if display_messages and isinstance(display_messages[-1], dict) else {}
    last_activity_at = str(last_message.get("created_at") or state.get("generated_at") or _utc_now_iso()).strip() or _utc_now_iso()
    last_activity_age_seconds = _age_seconds(last_activity_at)
    last_role = str(last_message.get("role") or "").strip().lower()
    activity_state = "idle"
    activity_label = "Idle"
    activity_summary = "No queued TOD activity is pending in this session."
    activity_pulse = False
    if pending_count > 0:
        if last_activity_age_seconds is not None and last_activity_age_seconds > 45:
            activity_state = "stalled"
            activity_label = "Stalled"
            activity_summary = f"TOD still has {pending_count} queued update(s), but the last activity was {_format_age(last_activity_at)}."
            activity_pulse = True
        else:
            activity_state = "working"
            activity_label = "Working"
            activity_summary = f"TOD is progressing and has {pending_count} queued update(s) left to publish into this thread."
            activity_pulse = True
    elif last_role == "system":
        if last_activity_age_seconds is not None and last_activity_age_seconds > 300:
            activity_state = "stalled"
            activity_label = "Stalled"
            activity_summary = f"TOD was waiting on the next validation or result, but this session has not updated since {_format_age(last_activity_at)}."
            activity_pulse = True
        else:
            activity_state = "waiting"
            activity_label = "Waiting"
            activity_summary = "TOD published the latest working step and is waiting on the next validation or result."
    elif last_role in {"tod", "copilot", "assistant"}:
        activity_state = "complete"
        activity_label = "Replied"
        activity_summary = "TOD has posted the latest reply for this session."
    if not messages and execution_feed_messages and isinstance(execution, dict) and execution.get("available"):
        activity_state = str(execution.get("activity_state") or activity_state).strip() or activity_state
        activity_label = str(execution.get("activity_label") or activity_label).strip() or activity_label
        activity_summary = str(execution.get("activity_summary") or execution.get("wait_reason") or activity_summary).strip() or activity_summary
    return {
        "session": {
            "session_key": _sanitize_session_key(session_key),
            "mode": normalized_surface,
            "message_count": len(display_messages),
            "updated_at": display_messages[-1].get("created_at") if display_messages else state.get("generated_at", _utc_now_iso()),
            "activity": {
                "state": activity_state,
                "label": activity_label,
                "summary": activity_summary,
                "pulse": activity_pulse,
                "pending_progress_count": pending_count,
                "last_activity_at": last_activity_at,
                "last_activity_age_seconds": last_activity_age_seconds,
            },
        },
        "messages": display_messages,
        "state_marker": _chat_state_marker(state),
        "status": status,
        "quick_facts": quick_facts,
        "visitor": {
            "name": visitor_name,
            "memory_summary": _pick_first_text(
                "TOD execution is enabled on this surface.",
                status.get("summary"),
                _next_bounded_repair_request(state),
                "TOD console chat is ready.",
            ),
        },
        "guardrails": {
            "commands_blocked": not execution_enabled,
            "live_execution_blocked": not execution_enabled,
            "execution_enabled": execution_enabled,
        },
        "capabilities": {
            "training_start": training_launcher,
            "codex_handoff": True,
            "image_upload": normalized_surface == "tod",
        },
        "links": [
            {"label": "Open Direct Chat", "href": "/chat"},
            {"label": "Open TOD Console", "href": "/tod"},
            {"label": "Open MIM Codex Chat", "href": "/mim"},
            {"label": "Logout", "href": "/mim/logout"},
        ],
        "actions": {
            "message_url": "/chat/ui/message" if direct_chat_surface else "/tod/ui/chat/message",
            "handoff_url": "/chat/ui/handoff" if direct_chat_surface else "/tod/ui/chat/handoff",
            "upload_url": "" if direct_chat_surface else "/tod/ui/chat/upload-image",
            "training_url": "/chat/ui/action/training",
        },
    }


def _build_tod_console_state() -> dict[str, Any]:
    integration_payload, integration_path = _first_existing_payload(
        SHARED_RUNTIME_ROOT / "TOD_INTEGRATION_STATUS.latest.json",
        SHARED_RUNTIME_ROOT / "TOD_integration_status.latest.json",
    )
    training_payload, training_path = _first_existing_payload(
        SHARED_RUNTIME_ROOT / "TOD_TRAINING_STATUS.latest.json",
        SHARED_RUNTIME_ROOT / "TOD_training_status.latest.json",
    )
    autonomy_payload, autonomy_path = _first_existing_payload(
        SHARED_RUNTIME_ROOT / "TOD_AUTONOMY_STATUS.latest.json",
        SHARED_RUNTIME_ROOT / "TOD_autonomy_status.latest.json",
        SHARED_RUNTIME_ROOT / "tod_autonomy_status.latest.json",
    )
    decision_payload = _load_json(SHARED_RUNTIME_ROOT / "TOD_MIM_EXECUTION_DECISION.latest.json")
    active_objective_payload, active_objective_path = _first_existing_payload(
        SHARED_RUNTIME_ROOT / "TOD_ACTIVE_OBJECTIVE.latest.json",
    )
    active_task_payload, active_task_path = _first_existing_payload(
        SHARED_RUNTIME_ROOT / "TOD_ACTIVE_TASK.latest.json",
    )
    activity_payload, activity_path = _first_existing_payload(
        SHARED_RUNTIME_ROOT / "TOD_ACTIVITY_STREAM.latest.json",
    )
    validation_payload, validation_path = _first_existing_payload(
        SHARED_RUNTIME_ROOT / "TOD_VALIDATION_RESULT.latest.json",
    )
    execution_result_payload, execution_result_path = _first_existing_payload(
        SHARED_RUNTIME_ROOT / "TOD_EXECUTION_RESULT.latest.json",
    )
    truth_payload, truth_path = _first_existing_payload(
        SHARED_RUNTIME_ROOT / "TOD_EXECUTION_TRUTH.latest.json",
        SHARED_RUNTIME_ROOT / "TOD_execution_truth.latest.json",
    )
    probe_payload = _load_json(SHARED_RUNTIME_ROOT / "TOD_CONSOLE_PROBE.latest.json")
    recovery_payload, recovery_path = _load_remote_recovery_payload()

    alignment = (
        integration_payload.get("objective_alignment")
        if isinstance(integration_payload.get("objective_alignment"), dict)
        else {}
    )
    evidence = (
        integration_payload.get("bridge_canonical_evidence")
        if isinstance(integration_payload.get("bridge_canonical_evidence"), dict)
        else {}
    )
    publish = (
        integration_payload.get("tod_status_publish")
        if isinstance(integration_payload.get("tod_status_publish"), dict)
        else {}
    )
    live_task_request = (
        integration_payload.get("live_task_request")
        if isinstance(integration_payload.get("live_task_request"), dict)
        else {}
    )
    live_task_request = _select_runtime_live_task_request(live_task_request, active_task_payload)
    listener_decision = (
        integration_payload.get("listener_decision")
        if isinstance(integration_payload.get("listener_decision"), dict)
        else {}
    )
    mim_status = (
        integration_payload.get("mim_status")
        if isinstance(integration_payload.get("mim_status"), dict)
        else {}
    )
    authority_reset = (
        integration_payload.get("objective_authority_reset")
        if isinstance(integration_payload.get("objective_authority_reset"), dict)
        else {}
    )
    handshake = (
        integration_payload.get("mim_handshake")
        if isinstance(integration_payload.get("mim_handshake"), dict)
        else {}
    )
    training_source = integration_payload.get("training_status")
    if not isinstance(training_source, dict):
        training_source = training_payload
    training_status = _normalize_training_status(training_source)
    training_status["idle_policy"] = _normalize_idle_training_policy(autonomy_payload, training_status)
    execution_status = _normalize_execution_status(
        active_objective_payload,
        active_task_payload,
        activity_payload,
        validation_payload,
        execution_result_payload,
        truth_payload,
    )
    guidance = _normalize_guidance_items(integration_payload.get("bridge_operator_guidance"))

    canonical_objective = str(
        handshake.get("current_next_objective")
        or mim_status.get("objective_active")
        or alignment.get("mim_objective_active")
        or ""
    ).strip()
    live_objective = str(
        live_task_request.get("normalized_objective_id")
        or live_task_request.get("objective_id")
        or alignment.get("tod_current_objective")
        or ""
    ).strip()
    alignment_status = str(alignment.get("status") or "unknown").strip().lower() or "unknown"
    evidence_status = str(evidence.get("status") or "unknown").strip().lower() or "unknown"
    publish_status = str(publish.get("status") or "unknown").strip().lower() or "unknown"
    publish_consumer_status = str(publish.get("consumer_status") or "").strip().lower()
    decision_state = str(
        listener_decision.get("execution_state")
        or decision_payload.get("execution_state")
        or "unknown"
    ).strip().lower() or "unknown"
    decision_outcome = str(
        listener_decision.get("decision_outcome")
        or decision_payload.get("decision_outcome")
        or "unknown"
    ).strip().lower() or "unknown"
    decision_reason = str(
        listener_decision.get("reason_code")
        or decision_payload.get("reason_code")
        or "unknown"
    ).strip().lower() or "unknown"
    decision_summary = _compact_text(
        listener_decision.get("summary") or decision_payload.get("summary") or "",
        220,
    ).lower()
    probe_status = str(probe_payload.get("status") or "unknown").strip().lower() or "unknown"
    authority_reset_active = bool(authority_reset.get("active") is True)
    canonical_token = _normalize_objective_token(canonical_objective)
    live_token = _normalize_objective_token(live_objective)
    if canonical_token and live_token and canonical_token != live_token:
        alignment_status = "mismatch"
    current_objective_token = canonical_token or live_token
    live_request_token = _normalize_objective_token(
        live_task_request.get("normalized_objective_id") or live_task_request.get("objective_id")
    )
    listener_objective_token = _normalize_objective_token(
        listener_decision.get("normalized_objective_id")
        or listener_decision.get("objective_id")
        or decision_payload.get("normalized_objective_id")
        or decision_payload.get("objective_id")
    )
    failure_signals = [
        str(item).strip()
        for item in evidence.get("failure_signals", [])
        if str(item).strip()
    ] if isinstance(evidence.get("failure_signals"), list) else []
    stale_residue_codes = {
        "live_task_request_objective_mismatch",
        "live_task_request_not_promoted",
    }
    alignment_is_current = alignment_status in {"match", "aligned", "in_sync", "ok"} and _same_objective(canonical_objective, live_objective)
    listener_residue_stale = bool(
        alignment_is_current
        and current_objective_token
        and listener_objective_token
        and listener_objective_token != current_objective_token
    )
    live_request_residue_stale = bool(
        alignment_is_current
        and current_objective_token
        and live_request_token
        and live_request_token != current_objective_token
    )
    promoted_live_request_current = bool(
        alignment_is_current
        and bool(live_task_request.get("promotion_applied") is True)
        and current_objective_token
        and live_token == current_objective_token
    )
    listener_alignment_wait_residue = bool(
        alignment_is_current
        and promoted_live_request_current
        and decision_reason in {"external_coordination_blocker", "objective_mismatch"}
        and decision_outcome in {"acknowledge_and_wait_on_dependency", "reject_with_specific_policy_reason"}
        and (
            decision_state == "waiting_on_dependency"
            or decision_state == "rejected"
            or "alignment" in decision_summary
            or "authoritative objective" in decision_summary
        )
    )
    residue_signals_only = bool(failure_signals) and all(signal in stale_residue_codes for signal in failure_signals)
    recovery_validation = recovery_payload.get("validation") if isinstance(recovery_payload.get("validation"), dict) else {}
    recovery_target_matches = _same_objective(recovery_payload.get("objective_id"), current_objective_token)
    recovery_confirms_alignment = bool(
        recovery_payload
        and recovery_target_matches
        and recovery_validation.get("passed") is True
        and recovery_validation.get("mismatch_cleared") is True
        and recovery_validation.get("remote_publish_verified") is True
    )
    remote_publish_verified = bool(
        evidence.get("remote_publish_verified") is True
        or recovery_confirms_alignment
        or promoted_live_request_current
        or str(publish.get("mim_mirror_status") or "").strip().lower() in {"mirrored", "uploaded"}
    )
    local_publish_ready = bool(
        alignment_is_current
        and publish_status == "local_rebuilt"
        and publish_consumer_status == "local_rebuild"
        and decision_outcome == "execute"
        and decision_state in {"ready_to_execute", "ready", "execute_now"}
        and not authority_reset_active
    )
    stale_residue_suppressed = bool(
        alignment_is_current
        and remote_publish_verified
        and (listener_residue_stale or listener_alignment_wait_residue or live_request_residue_stale or residue_signals_only)
    )

    effective_guidance = guidance
    if stale_residue_suppressed:
        stale_summary = (
            f"Canonical objective {canonical_objective or live_objective or 'unknown'} is current, but older listener or publish residue still references objective "
            f"{listener_objective_token or live_request_token or 'unknown'}."
        )
        effective_guidance = [
            {
                "code": "stale_objective_residue_suppressed",
                "severity": "info",
                "summary": _compact_text(stale_summary, 180),
                "recommended_action": _compact_text(
                    "Treat the stale listener or publication artifact as superseded on this console. Only regenerate it if a downstream consumer still requires the older file.",
                    220,
                ),
            }
        ]

    effective_listener_decision = {
        "decision_outcome": str(
            listener_decision.get("decision_outcome")
            or decision_payload.get("decision_outcome")
            or ""
        ).strip(),
        "reason_code": str(
            listener_decision.get("reason_code")
            or decision_payload.get("reason_code")
            or ""
        ).strip(),
        "execution_state": str(
            listener_decision.get("execution_state")
            or decision_payload.get("execution_state")
            or ""
        ).strip(),
        "next_step_recommendation": str(
            listener_decision.get("next_step_recommendation")
            or decision_payload.get("next_step_recommendation")
            or ""
        ).strip(),
        "generated_at": str(
            listener_decision.get("generated_at")
            or decision_payload.get("generated_at")
            or ""
        ).strip(),
        "summary": _compact_text(
            listener_decision.get("summary") or decision_payload.get("summary") or "No listener decision summary is available.",
            220,
        ),
    }
    if stale_residue_suppressed:
        effective_listener_decision = {
            "decision_outcome": "superseded_stale_listener_residue",
            "reason_code": "stale_listener_objective_residue",
            "execution_state": "aligned_after_recovery",
            "next_step_recommendation": "continue_current_objective_execution",
            "generated_at": str(recovery_payload.get("generated_at") or effective_listener_decision.get("generated_at") or integration_payload.get("generated_at") or "").strip(),
            "summary": _compact_text(
                f"Canonical objective {canonical_objective or live_objective or 'unknown'} is aligned and the promoted live request is current. Listener coordination residue for objective {listener_objective_token or live_request_token or current_objective_token or 'unknown'} is not authoritative on this console.",
                220,
            ),
        }

    effective_publish = {
        "status": str(publish.get("status") or "unknown").strip(),
        "remote_access_status": str(publish.get("remote_access_status") or "").strip(),
        "mim_mirror_status": str(publish.get("mim_mirror_status") or "").strip(),
        "consumer_status": str(publish.get("consumer_status") or "").strip(),
        "uploaded_at": str(publish.get("uploaded_at") or "").strip(),
        "error": str(publish.get("error") or "").strip(),
        "summary": _compact_text(
            publish.get("error")
            or f"status={publish.get('status') or 'unknown'}; mirror={publish.get('mim_mirror_status') or 'unknown'}; consumer={publish.get('consumer_status') or 'unknown'}",
            220,
        ),
    }
    if stale_residue_suppressed:
        effective_publish = {
            **effective_publish,
            "status": "uploaded" if promoted_live_request_current else "remote_verified",
            "uploaded_at": str(recovery_payload.get("generated_at") or effective_publish.get("uploaded_at") or integration_payload.get("generated_at") or "").strip(),
            "error": "",
            "summary": _compact_text(
                f"The live task request is promoted to canonical objective {canonical_objective or live_objective or 'unknown'}. Older local publication residue for objective {live_request_token or current_objective_token or 'unknown'} is suppressed on this console.",
                220,
            ),
        }

    status_code = "attention"
    status_label = "ATTENTION"
    headline = "ATTENTION - TOD needs review"
    summary = "TOD bridge state is available, but it needs operator review."

    if not integration_payload:
        status_code = "unknown"
        status_label = "UNKNOWN"
        headline = "UNKNOWN - TOD integration status missing"
        summary = "The shared TOD integration artifact is missing or unreadable."
    elif stale_residue_suppressed:
        status_code = "aligned"
        status_label = "ALIGNED"
        headline = "ALIGNED - canonical objective is current"
        summary = _compact_text(
            effective_listener_decision.get("summary")
            or effective_publish.get("summary")
            or "Canonical and live TOD state agree; older residue has been downgraded on this console.",
            220,
        )
    elif alignment_is_current and local_publish_ready and evidence_status != "fail":
        status_code = "aligned"
        status_label = "ALIGNED"
        headline = "ALIGNED - canonical and live TOD state agree"
        summary = "TOD and MIM objectives are in sync, and the listener is ready to execute from the locally rebuilt publish surface."
    elif alignment_status in {"match", "aligned", "in_sync", "ok"} and evidence_status == "pass" and publish_status in {"uploaded", "mirrored", "ok"}:
        status_code = "aligned"
        status_label = "ALIGNED"
        headline = "ALIGNED - canonical and live TOD state agree"
        summary = "TOD publication, objective alignment, and canonical bridge evidence are all in sync."
    elif alignment_status in {"mismatch", "drift", "out_of_sync"} or evidence_status == "fail":
        status_code = "drifted"
        status_label = "DRIFTED"
        headline = "DRIFTED - canonical and live objective disagree"
        summary = _compact_text(
            guidance[0].get("summary") if guidance else evidence.get("failure_signals") or alignment,
            220,
        ) or "The canonical objective and the live request surface do not agree."
    elif publish_status in {"failed", "error", "blocked"} or decision_state in {"blocked", "failed", "stale"} or probe_status in {"unreachable", "failed"}:
        status_code = "blocked"
        status_label = "BLOCKED"
        headline = "BLOCKED - TOD can see the work but cannot advance it cleanly"
        summary = _compact_text(
            listener_decision.get("summary")
            or decision_payload.get("summary")
            or publish.get("error")
            or "One or more TOD bridge stages are blocked.",
            220,
        )
    elif authority_reset_active:
        status_code = "authority_reset"
        status_label = "AUTHORITY RESET"
        headline = "AUTHORITY RESET - TOD is holding a stricter canonical baseline"
        summary = _compact_text(authority_reset.get("reason") or "Objective authority reset is active.", 220)

    if authority_reset_active and status_code == "aligned":
        status_code = "authority_reset"
        status_label = "AUTHORITY RESET"
        headline = "AUTHORITY RESET - alignment is constrained by active reset policy"
        summary = _compact_text(authority_reset.get("reason") or summary, 220)

    quick_facts = {
        "canonical_objective": canonical_objective or "Unknown",
        "live_request_objective": live_objective or "Unknown",
        "listener_state": str(
            effective_listener_decision.get("execution_state")
            or "unknown"
        ).strip().replace("_", " "),
        "publish_status": str(effective_publish.get("status") or "unknown").strip().replace("_", " "),
        "decision_outcome": str(
            effective_listener_decision.get("decision_outcome")
            or "unknown"
        ).strip().replace("_", " "),
        "authority_reset": "Active" if authority_reset_active else "Inactive",
        "training_state": training_status.get("state_label") or "Unknown",
        "training_progress": f"{training_status.get('percent_complete', 0)}%" if training_status.get("available") else "Unknown",
    }

    return {
        "generated_at": _utc_now_iso(),
        "source_paths": {
            "integration_status": integration_path,
            "training_status": training_path,
            "autonomy_status": autonomy_path,
            "active_objective": active_objective_path,
            "active_task": active_task_path,
            "activity_stream": activity_path,
            "validation_result": validation_path,
            "execution_result": execution_result_path,
            "execution_truth": truth_path,
            "execution_decision": str(SHARED_RUNTIME_ROOT / "TOD_MIM_EXECUTION_DECISION.latest.json"),
            "console_probe": str(SHARED_RUNTIME_ROOT / "TOD_CONSOLE_PROBE.latest.json"),
            "remote_recovery": recovery_path,
        },
        "conversation": {
          "enabled": True,
          "mode": "tod",
                    "state_url": "/tod/ui/chat/state",
                    "message_url": "/tod/ui/chat/message",
                                        "handoff_url": "/tod/ui/chat/handoff",
          "upload_url": "/tod/ui/chat/upload-image",
          "default_session_key": "tod-console-public",
                    "summary": "TOD operator chat is evidence-backed from live bridge, listener, publish, and training artifacts, with direct execution, uploads, training launch, and Codex handoffs available on this surface.",
                    "auto_trigger": {
                            "enabled": True,
                            "status_codes": ["attention"],
                            "once_per_session": True,
                            "prompt": "TOD, the console status is ATTENTION and requires review. Diagnose the current issue from live bridge, listener, maintenance, watchdog, and canonical objective evidence. Then report: 1. the issue summary, 2. the strongest evidence, 3. the next bounded repair request for Codex-style resolution, and 4. whether operator intervention is still required.",
                            "success_text": "TOD auto-resolution request sent.",
                    },
          "quick_actions": [
              {
                  "id": "start-training",
                  "label": "TOD Training",
                  "description": "Send the bounded six-hour training request through TOD chat and capture TOD's training reply in the thread.",
                  "prompt": "TOD, start your next bounded 6-hour training cycle and report the exact runbook status, current gate, and first blocker if it cannot proceed.",
              },
              {
                  "id": "resolve-drift",
                  "label": "Resolve Drift",
                  "description": "Send a bounded prompt asking TOD to explain and resolve current objective drift.",
                  "prompt": "TOD, resolve the current drift between canonical and live objective state. Report the mismatch, the repair step already underway, and the next validation check.",
              },
              {
                  "id": "send-to-copilot",
                  "label": "Send To Codex",
                  "description": "Create a real handoff artifact and publish it into the TOD/MIM dialog lane for Codex-style troubleshooting.",
                  "action_type": "handoff",
                  "prompt": "TOD, package the current issue, evidence, and next bounded repair request for Copilot-style troubleshooting and report the handoff summary in this thread.",
              },
          ],
        },
        "status": {
            "code": status_code,
            "label": status_label,
            "headline": headline,
            "summary": summary,
        },
        "quick_facts": quick_facts,
        "training_status": training_status,
        "execution": execution_status,
        "mim_status": {
            "available": bool(mim_status.get("available")),
            "objective_active": str(mim_status.get("objective_active") or "").strip(),
            "phase": str(mim_status.get("phase") or "").strip(),
            "generated_at": str(mim_status.get("generated_at") or "").strip(),
            "generated_age": _format_age(mim_status.get("generated_at")),
            "blockers": str(mim_status.get("blockers") or "").strip(),
        },
        "objective_alignment": {
            "status": "mismatch" if alignment_status in {"mismatch", "drift", "out_of_sync"} else str(alignment.get("status") or "unknown").strip(),
            "aligned": bool(alignment_status in {"match", "aligned", "in_sync", "ok"} and canonical_token and live_token and canonical_token == live_token),
            "tod_current_objective": str(live_task_request.get("normalized_objective_id") or live_task_request.get("objective_id") or alignment.get("tod_current_objective") or "").strip(),
            "mim_objective_active": str(alignment.get("mim_objective_active") or "").strip(),
            "delta": alignment.get("delta"),
            "summary": (
                "TOD and MIM objectives are in sync."
                if alignment_status in {"match", "aligned", "in_sync", "ok"} and canonical_token and live_token and canonical_token == live_token
                else f"TOD sees {live_objective or 'unknown'}, while MIM canonical state points at {canonical_objective or 'unknown'}."
            ),
        },
        "bridge_canonical_evidence": {
            "status": "pass" if stale_residue_suppressed else str(evidence.get("status") or "unknown").strip(),
            "canonical_refresh_satisfied": bool(evidence.get("canonical_refresh_satisfied") is True),
            "live_bridge_publish_satisfied": bool(evidence.get("live_bridge_publish_satisfied") is True or promoted_live_request_current),
            "remote_publish_verified": remote_publish_verified,
            "failure_signals": [] if stale_residue_suppressed else failure_signals,
            "summary": _compact_text(
                effective_publish.get("summary") if stale_residue_suppressed else (
                    "; ".join(failure_signals) if failure_signals else evidence.get("status")
                ),
                220,
            ) or "No canonical bridge evidence summary is available.",
        },
        "live_task_request": {
            "request_id": str(live_task_request.get("request_id") or "").strip(),
            "task_id": str(live_task_request.get("task_id") or "").strip(),
            "objective_id": str(live_task_request.get("objective_id") or "").strip(),
            "normalized_objective_id": str(live_task_request.get("normalized_objective_id") or "").strip(),
            "generated_at": str(live_task_request.get("generated_at") or "").strip(),
            "generated_age": _format_age(live_task_request.get("generated_at")),
            "promotion_applied": bool(live_task_request.get("promotion_applied") is True),
            "promotion_reason": str(live_task_request.get("promotion_reason") or "").strip(),
        },
        "listener_decision": {
            "decision_outcome": effective_listener_decision.get("decision_outcome") or "",
            "reason_code": effective_listener_decision.get("reason_code") or "",
            "execution_state": effective_listener_decision.get("execution_state") or "",
            "next_step_recommendation": effective_listener_decision.get("next_step_recommendation") or "",
            "generated_at": effective_listener_decision.get("generated_at") or "",
            "generated_age": _format_age(effective_listener_decision.get("generated_at")),
            "summary": effective_listener_decision.get("summary") or "No listener decision summary is available.",
        },
        "operator_guidance": effective_guidance,
        "publish": {
            "status": effective_publish.get("status") or "unknown",
            "remote_access_status": effective_publish.get("remote_access_status") or "",
            "mim_mirror_status": effective_publish.get("mim_mirror_status") or "",
            "consumer_status": effective_publish.get("consumer_status") or "",
            "uploaded_at": effective_publish.get("uploaded_at") or "",
            "uploaded_age": _format_age(effective_publish.get("uploaded_at")),
            "error": effective_publish.get("error") or "",
            "summary": effective_publish.get("summary") or "No publish summary",
        },
        "authority_reset": {
            "active": authority_reset_active,
            "authoritative_current_objective": str(authority_reset.get("authoritative_current_objective") or "").strip() if authority_reset_active else "",
            "max_valid_objective": str(authority_reset.get("max_valid_objective") or "").strip() if authority_reset_active else "",
            "effective_at": str(authority_reset.get("effective_at") or "").strip() if authority_reset_active else "",
            "effective_age": _format_age(authority_reset.get("effective_at")) if authority_reset_active else "Inactive",
            "reason": _compact_text(authority_reset.get("reason"), 260) if authority_reset_active else "",
            "invalidated_objectives": [str(item).strip() for item in authority_reset.get("invalidated_objectives", []) if str(item).strip()] if authority_reset_active and isinstance(authority_reset.get("invalidated_objectives"), list) else [],
        },
        "console_probe": {
            "available": bool(probe_payload),
            "status": str(probe_payload.get("status") or "unknown").strip(),
            "http_status": probe_payload.get("http_status"),
            "generated_at": str(probe_payload.get("generated_at") or "").strip(),
            "generated_age": _format_age(probe_payload.get("generated_at")),
            "authority_role": str(
                (probe_payload.get("authority") if isinstance(probe_payload.get("authority"), dict) else {}).get("role") or ""
            ).strip(),
        },
        "execution_truth": {
            "available": bool(truth_payload),
            "generated_at": str(truth_payload.get("generated_at") or "").strip(),
            "generated_age": _format_age(truth_payload.get("generated_at")),
            "status": str(truth_payload.get("status") or truth_payload.get("truth_status") or "").strip(),
            "summary": _compact_text(
                truth_payload.get("summary") or truth_payload.get("truth_summary") or "",
                220,
            ),
        },
        "recent_handoffs": _load_recent_copilot_handoffs(
            limit=6,
            current_objective_id=canonical_objective or live_objective,
            current_request_id=str(live_task_request.get("request_id") or "").strip(),
        ),
    }


@router.get("/tod/ui/chat/state")
async def tod_ui_chat_state(
    session_key: str = Query("tod-console-public"),
    mode: str = Query("tod"),
) -> dict[str, Any]:
    del mode
    state = _build_tod_console_state()
    messages = _advance_pending_chat_progress(session_key, state)
    return _build_chat_payload(session_key, messages, state)


@router.post("/tod/ui/chat/message")
async def tod_ui_chat_message(payload: dict[str, Any] = Body(default_factory=dict)) -> dict[str, Any]:
    session_key = str(payload.get("session_key") or "tod-console-public").strip() or "tod-console-public"
    message = _trim_message_text(payload.get("message"), 2000)
    state = _build_tod_console_state()
    session_payload = _load_chat_session_payload(session_key, state)
    messages = list(session_payload.get("messages") or [])
    visitor_name = _resolve_public_visitor_name()
    if message:
        messages.append({"role": "visitor", "author_name": visitor_name, "content": message, "created_at": _utc_now_iso()})
        if _classify_prompt(message) == "task":
            execution_ack = _publish_local_execution_ack(message, state, surface="tod", session_key=session_key)
            dispatch_record = _publish_task_execution_request(message, state, surface="tod", session_key=session_key)
            state = _build_tod_console_state()
            progress_messages = _build_task_progress_messages(message, state, execution_ack=execution_ack, dispatch_record=dispatch_record)
            messages.extend(progress_messages[:2])
            session_payload["pending_progress"] = progress_messages[2:]
        else:
            messages.append({"role": "tod", "content": _compose_operator_reply(message, state, surface_label="/tod"), "created_at": _utc_now_iso()})
            session_payload["pending_progress"] = []
        session_payload["messages"] = messages[-40:]
        _save_chat_session_payload(session_key, session_payload, state)
    return _build_chat_payload(session_key, messages, state)


@router.get("/tod/ui/chat/media/{asset_name}")
async def tod_ui_chat_media(asset_name: str) -> FileResponse:
    safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "", str(asset_name or "")).strip()
    if not safe_name or safe_name != asset_name:
        raise HTTPException(status_code=404, detail="media_not_found")
    asset_path = TOD_CONSOLE_CHAT_MEDIA_ROOT / safe_name
    if not asset_path.exists() or not asset_path.is_file():
        raise HTTPException(status_code=404, detail="media_not_found")
    return FileResponse(asset_path)


@router.post("/tod/ui/chat/upload-image")
async def tod_ui_chat_upload_image(payload: dict[str, Any] = Body(default_factory=dict)) -> dict[str, Any]:
    session_key = str(payload.get("session_key") or "tod-console-public").strip() or "tod-console-public"
    prompt = _compact_text(payload.get("prompt"), 2000)
    state = _build_tod_console_state()
    messages = _load_chat_messages(session_key, state)
    attachment = _persist_public_chat_image(payload.get("attachment"))
    visitor_name = _resolve_public_visitor_name()
    user_text = prompt or f"Shared image: {attachment['filename']}"
    messages.append(
        {
            "role": "visitor",
            "author_name": visitor_name,
            "content": user_text,
            "created_at": _utc_now_iso(),
            "attachment": attachment,
        }
    )
    issue_focus = _summarize_requested_task(prompt or f"review {attachment['filename']}", 180)
    messages.append(
        {
            "role": "tod",
            "content": "\n".join(
                [
                    f"Accepted. TOD attached the screenshot for {issue_focus}.",
                    f"Image: {attachment['filename']} · {max(1, round(attachment['size_bytes'] / 1024))} KB · {attachment['mime_type']}",
                    "Send To Codex packages the current request, strongest evidence, next bounded repair, next validation, and the latest screenshot from this thread into a real handoff artifact.",
                    "Add a short note about what you want reviewed, or press Send To Codex now for deeper troubleshooting." if not prompt else "Ask a bounded follow-up or press Send To Codex to publish this screenshot into the TOD/MIM dialog lane.",
                ]
            ),
            "created_at": _utc_now_iso(),
        }
    )
    _save_chat_messages(session_key, messages, state)
    chat_payload = _build_chat_payload(session_key, messages, state)
    chat_payload["image_upload"] = {"ok": True, "attachment": _normalize_chat_attachment(attachment)}
    return chat_payload


@router.post("/tod/ui/chat/handoff")
async def tod_ui_chat_handoff(payload: dict[str, Any] = Body(default_factory=dict)) -> dict[str, Any]:
    session_key = str(payload.get("session_key") or "tod-console-public").strip() or "tod-console-public"
    message = _compact_text(
        payload.get("message")
        or "TOD, package the current issue, evidence, and next bounded repair request for Copilot-style troubleshooting and report the handoff summary in this thread.",
        2000,
    )
    state = _build_tod_console_state()
    messages = _load_chat_messages(session_key, state)
    messages.append({"role": "visitor", "author_name": _resolve_public_visitor_name(), "content": message, "created_at": _utc_now_iso()})
    attachments = _recent_chat_attachments(messages)
    handoff = _create_copilot_handoff(message, state, session_key, attachments=attachments)
    status = state.get("status") if isinstance(state.get("status"), dict) else {}
    reply = "\n".join(
        [
            "Copilot handoff created:",
            f"Issue: {_pick_first_text(status.get('headline'), status.get('summary'))}",
            f"Evidence: {_strongest_evidence(state)}",
            f"Bounded repair request: {_next_bounded_repair_request(state)}",
            f"Validation after repair: {_next_validation_check(state)}",
            f"Latest screenshot attached: {'yes' if attachments else 'no'}",
            f"Artifact: {handoff['artifact_path']}",
            f"Dialog session: {handoff['session_id']}",
            f"Dialog inbox: {handoff['dialog_index_path']}",
            f"Next expected reply: {handoff['reply_contract']}",
        ]
    )
    messages.append({"role": "tod", "content": reply, "created_at": _utc_now_iso()})
    _save_chat_messages(session_key, messages, state)
    chat_payload = _build_chat_payload(session_key, messages, state)
    chat_payload["handoff"] = handoff
    return chat_payload


@router.get("/chat/ui/state")
async def chat_ui_state(
    session_key: str = Query("copilot-operator-chat"),
    mode: str = Query("chat"),
) -> dict[str, Any]:
    del mode
    state = _build_tod_console_state()
    messages = _advance_pending_chat_progress(session_key, state)
    return _build_chat_payload(session_key, messages, state, surface="chat")


@router.post("/chat/ui/message")
async def chat_ui_message(payload: dict[str, Any] = Body(default_factory=dict)) -> dict[str, Any]:
    session_key = str(payload.get("session_key") or "copilot-operator-chat").strip() or "copilot-operator-chat"
    message = _trim_message_text(payload.get("message"), 2000)
    state = _build_tod_console_state()
    session_payload = _load_chat_session_payload(session_key, state)
    messages = list(session_payload.get("messages") or [])
    if message:
        messages.append({"role": "operator", "content": message, "created_at": _utc_now_iso()})
        if _classify_prompt(message) == "task":
            execution_ack = _publish_local_execution_ack(message, state, surface="chat", session_key=session_key)
            dispatch_record = _publish_task_execution_request(message, state, surface="chat", session_key=session_key)
            state = _build_tod_console_state()
            progress_messages = _build_task_progress_messages(message, state, execution_ack=execution_ack, dispatch_record=dispatch_record)
            immediate_progress_count = 6 if len(progress_messages) >= 6 else len(progress_messages)
            immediate_messages = [dict(item) for item in progress_messages[:immediate_progress_count]] if progress_messages else [{"role": "copilot", "content": _compose_operator_reply(message, state), "created_at": _utc_now_iso()}]
            for item in immediate_messages:
                if str(item.get("role") or "").strip().lower() == "tod":
                    item["role"] = "copilot"
            messages.extend(immediate_messages)
            session_payload["pending_progress"] = progress_messages[immediate_progress_count:]
        else:
            messages.append({"role": "copilot", "content": _compose_operator_reply(message, state), "created_at": _utc_now_iso()})
            session_payload["pending_progress"] = []
        session_payload["messages"] = messages[-40:]
        _save_chat_session_payload(session_key, session_payload, state)
    return _build_chat_payload(session_key, messages, state, surface="chat")


@router.post("/chat/ui/handoff")
async def chat_ui_handoff(payload: dict[str, Any] = Body(default_factory=dict)) -> dict[str, Any]:
    session_key = str(payload.get("session_key") or "copilot-operator-chat").strip() or "copilot-operator-chat"
    message = _compact_text(
        payload.get("message")
        or "Package the current issue, evidence, and next bounded repair request for Codex-style troubleshooting.",
        2000,
    )
    state = _build_tod_console_state()
    messages = _load_chat_messages(session_key, state)
    messages.append({"role": "operator", "content": message, "created_at": _utc_now_iso()})
    handoff = _create_copilot_handoff(message, state, session_key)
    messages.append(
        {
            "role": "copilot",
            "content": "\n".join(
                [
                    "Codex handoff created.",
                    f"Issue: {_pick_first_text(state.get('status', {}).get('headline') if isinstance(state.get('status'), dict) else '', state.get('status', {}).get('summary') if isinstance(state.get('status'), dict) else '')}",
                    f"Artifact: {handoff['artifact_path']}",
                    f"Dialog session: {handoff['session_id']}",
                    f"Next expected reply: {handoff['reply_contract']}",
                ]
            ),
            "created_at": _utc_now_iso(),
        }
    )
    _save_chat_messages(session_key, messages, state)
    chat_payload = _build_chat_payload(session_key, messages, state, surface="chat")
    chat_payload["handoff"] = handoff
    return chat_payload


@router.post("/chat/ui/action/training")
async def chat_ui_start_training(payload: dict[str, Any] = Body(default_factory=dict)) -> dict[str, Any]:
    session_key = str(payload.get("session_key") or "copilot-operator-chat").strip() or "copilot-operator-chat"
    state = _build_tod_console_state()
    messages = _load_chat_messages(session_key, state)
    messages.append({"role": "operator", "content": "Start 6h Training", "created_at": _utc_now_iso()})
    result = _start_training_runbook(state)
    messages.append({"role": "copilot", "content": _format_training_start_reply(result), "created_at": _utc_now_iso()})
    _save_chat_messages(session_key, messages, state)
    chat_payload = _build_chat_payload(session_key, messages, state, surface="chat")
    chat_payload["training_action"] = result
    return chat_payload


@router.get("/tod/ui/state")
async def tod_ui_state() -> dict[str, Any]:
    return _build_tod_console_state()


@router.get("/tod", response_class=HTMLResponse)
async def tod_console() -> HTMLResponse:
    title = f"TOD Console | {settings.app_name}"
    return HTMLResponse(
        f"""
<!doctype html>
<html lang=\"en\">
<head>
            <style>
                :root {{
                    --bg-0: #030709;
                    --bg-1: #071014;
                    --bg: #071014;
                    --ink: #d7ffe8;
                    --muted: #7dbfa1;
                    --panel: rgba(8,18,22,0.86);
                    --line: rgba(102,255,188,0.28);
                    --line-strong: rgba(102,255,188,0.70);
                    --accent: #2dff9d;
                    --accent-strong: #bfffdc;
                    --good: #2dff9d;
                    --warn: #ffd166;
                    --bad: #ff5c7a;
                    --shadow: 0 0 30px rgba(0,255,160,0.12);
                    --font: "Space Mono", "Consolas", "Cascadia Mono", monospace;
                }}
                * {{ box-sizing: border-box; }}
                body {{
                    margin: 0;
                    min-height: 100vh;
                    color: var(--ink);
                    font-family: var(--font);
                    background:
                        radial-gradient(circle at 15% 10%, rgba(40,160,90,0.22), transparent 42%),
                        radial-gradient(circle at 92% 80%, rgba(0,200,255,0.14), transparent 40%),
                        linear-gradient(160deg, var(--bg-0), var(--bg-1));
                    overflow-x: hidden;
                }}
                body::before {{
                    content: "";
                    position: fixed;
                    inset: 0;
                    pointer-events: none;
                    background-image: repeating-linear-gradient(to bottom, rgba(130,255,180,0.045), rgba(130,255,180,0.045) 1px, transparent 1px, transparent 5px);
                    opacity: 0.3;
                    animation: scan 9s linear infinite;
                }}
                @keyframes scan {{
                    from {{ transform: translateY(0); }}
                    to {{ transform: translateY(5px); }}
                }}
                .page {{ max-width: 1440px; margin: 0 auto; padding: 24px 16px 40px; }}
                .shell {{
                    border: 1px solid var(--line);
                    background: var(--panel);
                    backdrop-filter: blur(2px);
                    border-radius: 14px;
                    box-shadow: var(--shadow);
                    overflow: hidden;
                }}
                .hero {{
                    padding: 24px;
                    border-bottom: 1px solid var(--line);
                    background: linear-gradient(120deg, rgba(45,255,157,0.15), rgba(0,120,90,0.05));
                }}
                .console-nav {{ display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-bottom: 12px; }}
                .console-link {{
                    display: inline-flex;
                    align-items: center;
                    gap: 8px;
                    padding: 8px 12px;
                    border-radius: 999px;
                    border: 1px solid var(--line);
                    background: rgba(4,18,16,0.75);
                    color: var(--ink);
                    text-decoration: none;
                    font-size: 12px;
                    font-weight: 800;
                    letter-spacing: 0.08em;
                    text-transform: uppercase;
                    transition: transform 120ms ease, border-color 120ms ease, box-shadow 120ms ease;
                }}
                .console-link:hover {{ border-color: var(--line-strong); box-shadow: 0 0 12px rgba(45,255,157,0.18); transform: translateY(-1px); }}
                .console-link.active {{ border-color: var(--line-strong); box-shadow: inset 0 0 0 1px rgba(45,255,157,0.14), 0 0 12px rgba(45,255,157,0.12); }}
                .console-link.utility {{ background: rgba(4,18,16,0.62); }}
                .console-link-light {{ width: 9px; height: 9px; border-radius: 999px; background: #4b6f62; box-shadow: 0 0 0 rgba(45,255,157,0); }}
                .console-link-light.ok {{ background: var(--good); box-shadow: 0 0 14px rgba(45,255,157,0.40); }}
                .console-link-light.err {{ background: var(--bad); box-shadow: 0 0 14px rgba(255,92,122,0.28); }}
                .eyebrow {{ font-size: 12px; text-transform: uppercase; letter-spacing: 0.16em; color: var(--accent); font-weight: 700; }}
                .hero-row {{ display: flex; gap: 18px; align-items: flex-start; justify-content: space-between; flex-wrap: wrap; }}
                h1 {{ margin: 8px 0 6px; font-size: clamp(28px, 5vw, 48px); line-height: 0.98; text-transform: uppercase; text-shadow: 0 0 12px rgba(45,255,157,0.40); }}
                .hero-copy {{ max-width: 860px; color: var(--muted); font-size: 15px; line-height: 1.5; }}
                .status-chip {{ border-radius: 999px; padding: 10px 14px; font-size: 13px; font-weight: 800; letter-spacing: 0.08em; text-transform: uppercase; background: rgba(4,18,16,0.78); border: 1px solid var(--line); }}
                .status-chip[data-tone="aligned"], .status-chip[data-tone="working"], .status-chip[data-tone="complete"] {{ background: rgba(7,42,24,0.60); color: var(--good); border-color: rgba(45,255,157,0.55); }}
                .status-chip[data-tone="drifted"], .status-chip[data-tone="blocked"] {{ background: rgba(56,14,24,0.55); color: var(--bad); border-color: rgba(255,92,122,0.55); }}
                .status-chip[data-tone="authority_reset"], .status-chip[data-tone="attention"], .status-chip[data-tone="waiting"] {{ background: rgba(58,43,10,0.52); color: var(--warn); border-color: rgba(255,209,102,0.55); }}
                .status-chip[data-tone="stalled"] {{ background: rgba(56,14,24,0.55); color: var(--bad); border-color: rgba(255,92,122,0.55); }}
                .status-chip[data-tone="unknown"] {{ background: rgba(4,18,16,0.72); color: var(--muted); }}
                .headline {{ margin-top: 14px; font-size: 22px; font-weight: 800; }}
                .summary {{ margin-top: 6px; color: var(--muted); font-size: 14px; line-height: 1.5; }}
                .primary-chat-panel {{ padding: 0 24px 22px; }}
                .facts {{ display: grid; grid-template-columns: repeat(8, minmax(0, 1fr)); gap: 12px; padding: 22px 24px; border-bottom: 1px solid var(--line); }}
                .fact {{ border: 1px solid rgba(97,219,191,0.16); border-radius: 14px; background: rgba(2,12,10,0.75); padding: 14px; min-height: 108px; box-shadow: inset 0 0 0 1px rgba(120,255,190,0.06); }}
                .fact-label {{ font-size: 12px; text-transform: uppercase; letter-spacing: 0.12em; color: var(--muted); }}
                .fact-value {{ margin-top: 8px; font-size: 20px; font-weight: 800; line-height: 1.15; }}
                .fact-meta {{ margin-top: 8px; color: var(--muted); font-size: 13px; line-height: 1.45; }}
                .grid {{ display: grid; grid-template-columns: minmax(0, 1.22fr) minmax(0, 0.98fr); gap: 18px; padding: 22px 24px 24px; }}
                .stack {{ display: grid; gap: 18px; }}
                .panel {{ border: 1px solid rgba(97,219,191,0.22); border-radius: 14px; background: rgba(3,15,13,0.86); padding: 18px; box-shadow: 0 0 24px rgba(45,255,157,0.08); }}
                .panel h2 {{ margin: 0 0 12px; font-size: 16px; }}
                .panel-copy {{ color: var(--muted); font-size: 14px; line-height: 1.5; }}
                .kv {{ display: grid; grid-template-columns: 180px 1fr; gap: 8px 14px; margin-top: 14px; }}
                .kv-label {{ color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.10em; }}
                .kv-value {{ font-size: 14px; line-height: 1.45; word-break: break-word; }}
                .guidance-list {{ display: grid; gap: 12px; margin-top: 14px; }}
                .guidance-item {{ border: 1px solid rgba(97,219,191,0.16); border-radius: 10px; padding: 14px; background: rgba(2,12,10,0.75); }}
                .guidance-code {{ font-size: 12px; text-transform: uppercase; letter-spacing: 0.12em; color: var(--accent); font-weight: 700; }}
                .guidance-summary {{ margin-top: 6px; font-weight: 700; line-height: 1.4; }}
                .guidance-action {{ margin-top: 6px; color: var(--muted); font-size: 14px; line-height: 1.45; }}
                .training-band {{ display: grid; grid-template-columns: auto 1fr auto; gap: 12px; align-items: center; }}
                .training-pill {{ display: inline-flex; align-items: center; gap: 8px; padding: 8px 12px; border-radius: 999px; background: rgba(4,18,16,0.78); border: 1px solid var(--line); font-size: 12px; font-weight: 800; letter-spacing: 0.08em; text-transform: uppercase; }}
                .training-pill[data-tone="running"], .training-pill[data-tone="completed"] {{ background: rgba(7,42,24,0.60); color: var(--good); border-color: rgba(45,255,157,0.55); }}
                .training-pill[data-tone="failed"], .training-pill[data-tone="error"] {{ background: rgba(56,14,24,0.55); color: var(--bad); border-color: rgba(255,92,122,0.55); }}
                .training-pill[data-tone="paused"], .training-pill[data-tone="pending"] {{ background: rgba(58,43,10,0.52); color: var(--warn); border-color: rgba(255,209,102,0.55); }}
                .training-stats {{ text-align: right; font-size: 13px; color: var(--muted); }}
                .progress-track {{ margin-top: 14px; height: 12px; border-radius: 999px; background: rgba(4,18,16,0.88); border: 1px solid rgba(97,219,191,0.18); overflow: hidden; }}
                .progress-bar {{ height: 100%; width: 0%; border-radius: 999px; background: linear-gradient(90deg, rgba(84,255,168,0.82), rgba(39,216,139,0.95)); box-shadow: 0 0 10px rgba(45,255,157,0.25); transition: width 220ms ease; }}
                .collection-list {{ display: grid; gap: 10px; margin-top: 14px; }}
                .collection-item {{ border: 1px solid rgba(97,219,191,0.16); border-radius: 10px; background: rgba(2,12,10,0.75); padding: 12px 14px; }}
                .collection-top {{ display: flex; justify-content: space-between; gap: 12px; align-items: baseline; flex-wrap: wrap; }}
                .collection-label {{ font-size: 12px; text-transform: uppercase; letter-spacing: 0.12em; color: var(--accent); font-weight: 700; }}
                .collection-meta {{ font-size: 12px; color: var(--muted); }}
                .collection-text {{ margin-top: 6px; font-size: 14px; line-height: 1.45; }}
                .pill-row {{ display: flex; flex-wrap: wrap; gap: 8px; margin-top: 14px; }}
                .mini-pill {{ display: inline-flex; align-items: center; gap: 6px; padding: 7px 10px; border-radius: 999px; border: 1px solid rgba(97,219,191,0.24); background: rgba(4,20,17,0.78); font-size: 12px; color: var(--muted); }}
                .chat-shell {{ display: grid; gap: 12px; }}
                .primary-chat-panel .panel {{ padding: 20px; }}
                .primary-chat-panel .chat-thread {{ min-height: 320px; max-height: 560px; }}
                .chat-meta {{ display: flex; justify-content: space-between; gap: 10px; flex-wrap: wrap; font-size: 12px; color: var(--muted); }}
                .chat-thread {{ min-height: 260px; max-height: 440px; overflow-y: auto; border: 1px solid rgba(97,219,191,0.22); border-radius: 10px; padding: 14px; background: rgba(3,15,13,0.86); display: grid; gap: 12px; }}
                .chat-bubble {{ max-width: 90%; border-radius: 12px; padding: 12px 14px; border: 1px solid rgba(97,219,191,0.18); background: rgba(4,18,16,0.85); }}
                .chat-bubble.user {{ margin-left: auto; background: linear-gradient(145deg, rgba(8,34,30,0.9), rgba(4,16,14,0.95)); border-color: rgba(45,255,157,0.30); }}
                .chat-bubble.assistant {{ margin-right: auto; }}
                .chat-bubble.system {{ max-width: 100%; background: rgba(2,12,10,0.75); }}
                .chat-role {{ font-size: 12px; text-transform: uppercase; letter-spacing: 0.12em; color: var(--accent); font-weight: 700; }}
                .chat-time {{ font-size: 12px; color: var(--muted); margin-top: 4px; }}
                .chat-message {{ margin-top: 8px; font-size: 14px; line-height: 1.55; white-space: pre-wrap; word-break: break-word; }}
                .chat-form {{ display: grid; gap: 10px; }}
                .chat-dropzone {{ border: 1px dashed rgba(97,219,191,0.24); border-radius: 10px; padding: 10px 12px; color: var(--muted); font-size: 12px; background: rgba(3,15,13,0.72); }}
                .chat-dropzone.active {{ border-color: var(--line-strong); color: var(--ink); box-shadow: 0 0 0 1px rgba(45,255,157,0.18); }}
                .chat-preview {{ display: grid; grid-template-columns: 120px minmax(0, 1fr); gap: 12px; align-items: start; border: 1px solid rgba(97,219,191,0.18); border-radius: 10px; padding: 10px; background: rgba(3,15,13,0.76); }}
                .chat-preview[hidden] {{ display: none; }}
                .chat-preview img {{ width: 120px; max-width: 100%; border-radius: 8px; border: 1px solid rgba(97,219,191,0.16); background: rgba(4,18,16,0.88); }}
                .chat-preview-meta {{ display: grid; gap: 6px; }}
                .chat-preview-name {{ font-size: 13px; font-weight: 700; color: var(--accent-strong); }}
                .chat-preview-copy {{ color: var(--muted); font-size: 12px; line-height: 1.5; }}
                .chat-input {{ width: 100%; min-height: 108px; resize: vertical; border-radius: 10px; border: 1px solid rgba(97,219,191,0.24); background: rgba(3,14,12,0.92); padding: 14px; font: inherit; color: var(--ink); outline: none; }}
                .chat-input:focus-visible {{ border-color: var(--line-strong); box-shadow: 0 0 0 2px rgba(45,255,157,0.14); }}
                .chat-actions {{ display: flex; justify-content: space-between; gap: 10px; align-items: center; flex-wrap: wrap; }}
                .chat-action-buttons {{ display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }}
                .panel-actions {{ display: flex; gap: 10px; flex-wrap: wrap; margin-top: 14px; }}
                .panel-actions[hidden] {{ display: none; }}
                .chat-activity {{ display: inline-flex; align-items: center; gap: 8px; padding: 8px 10px; border-radius: 999px; border: 1px solid rgba(97,219,191,0.20); background: rgba(4,20,17,0.76); font-size: 12px; color: var(--muted); }}
                .chat-activity-dot {{ width: 10px; height: 10px; border-radius: 999px; background: #4b6f62; box-shadow: 0 0 0 rgba(45,255,157,0); }}
                .chat-activity[data-state="working"] .chat-activity-dot {{ background: var(--good); box-shadow: 0 0 12px rgba(45,255,157,0.42); animation: todPulse 1.1s ease-in-out infinite; }}
                .chat-activity[data-state="waiting"] .chat-activity-dot {{ background: var(--warn); box-shadow: 0 0 10px rgba(255,209,102,0.32); animation: todPulse 1.8s ease-in-out infinite; }}
                .chat-activity[data-state="stalled"] .chat-activity-dot {{ background: var(--bad); box-shadow: 0 0 12px rgba(255,92,122,0.34); animation: todPulse 0.9s ease-in-out infinite; }}
                .chat-activity[data-state="complete"] .chat-activity-dot {{ background: var(--good); box-shadow: 0 0 10px rgba(45,255,157,0.24); }}
                .chat-activity-text {{ font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; color: var(--ink); }}
                @keyframes todPulse {{ 0% {{ transform: scale(0.88); opacity: 0.78; }} 50% {{ transform: scale(1.08); opacity: 1; }} 100% {{ transform: scale(0.88); opacity: 0.78; }} }}
                .chat-button {{ appearance: none; border: 1px solid var(--line); border-radius: 10px; padding: 11px 16px; background: linear-gradient(120deg, rgba(11,110,79,0.9), rgba(45,255,157,0.33)); color: #e8fff2; font: inherit; font-size: 13px; font-weight: 700; cursor: pointer; box-shadow: 0 0 14px rgba(45,255,157,0.2); transition: transform 120ms ease, background 120ms ease, box-shadow 120ms ease; }}
                .chat-button:hover {{ background: linear-gradient(120deg, rgba(0,96,81,0.65), rgba(0,140,120,0.24)); transform: translateY(-1px); }}
                .chat-button:disabled {{ cursor: wait; opacity: 0.65; transform: none; }}
                .chat-button.secondary {{ background: rgba(4,20,17,0.78); color: var(--ink); box-shadow: none; }}
                .chat-button.secondary:hover {{ background: rgba(7,28,23,0.92); }}
                .chat-quick-actions {{ display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; }}
                .chat-quick-btn {{ appearance: none; border: 1px solid rgba(97,219,191,0.28); border-radius: 999px; padding: 9px 12px; background: rgba(4,20,17,0.78); color: #d5ffea; font: inherit; font-size: 12px; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; cursor: pointer; transition: transform 120ms ease, background 120ms ease, border-color 120ms ease, box-shadow 120ms ease; }}
                .chat-quick-btn:hover {{ border-color: var(--line-strong); box-shadow: 0 0 10px rgba(45,255,157,0.14); transform: translateY(-1px); }}
                .chat-quick-btn:disabled {{ cursor: wait; opacity: 0.60; transform: none; }}
                .chat-quick-copy {{ font-size: 12px; color: var(--muted); line-height: 1.45; margin-top: 2px; }}
                .status-inline {{ font-size: 12px; color: var(--muted); }}
                .muted {{ color: var(--muted); }}
                .footer {{ padding: 0 24px 24px; color: var(--muted); font-size: 12px; display: flex; justify-content: space-between; gap: 12px; flex-wrap: wrap; }}
                @media (max-width: 1100px) {{
                    .facts {{ grid-template-columns: repeat(4, minmax(0, 1fr)); }}
                    .grid {{ grid-template-columns: 1fr; }}
                }}
                @media (max-width: 720px) {{
                    .facts {{ grid-template-columns: 1fr 1fr; }}
                    .kv {{ grid-template-columns: 1fr; }}
                    .training-band {{ grid-template-columns: 1fr; }}
                }}
                        </style>
</head>
<body>
  <main class=\"page\">
    <section class=\"shell\">
      <header class=\"hero\">
        <div class=\"console-nav\">
          <a class=\"console-link utility\" href=\"/\"><span>Public Home</span></a>
          <a class=\"console-link\" href=\"/mim\"><span id=\"mimConsoleLight\" class=\"console-link-light\"></span><span>MIM Primary Operator Surface</span></a>
          <a class=\"console-link active\" href=\"/tod\"><span id=\"todConsoleLight\" class=\"console-link-light\"></span><span>TOD Console</span></a>
                    <a class=\"console-link utility\" href=\"/chat\"><span>Direct Chat</span></a>
          <a class=\"console-link utility\" href=\"/mim/logout\"><span>Logout</span></a>
        </div>
                <div class=\"eyebrow\">TOD Console</div>
                <div class=\"hero-row\">
                    <div></div>
                    <div id=\"todStatusChip\" class=\"status-chip\" data-tone=\"unknown\">Loading</div>
                </div>
                <div id=\"todStatusHeadline\" class=\"headline\">Loading TOD state...</div>
                <div id=\"todStatusSummary\" class=\"summary\">Checking shared TOD artifacts and publication evidence.</div>
                <div id=\"chatActivityIndicator\" class=\"chat-activity\" data-state=\"idle\"><span class=\"chat-activity-dot\" aria-hidden=\"true\"></span><span id=\"chatActivityText\" class=\"chat-activity-text\">Idle</span><span id=\"chatActivitySummary\">Waiting for TOD activity.</span></div>
      </header>
            <section class=\"primary-chat-panel\">
                <section class=\"panel\">
                    <div class=\"chat-shell\">
                        <div class=\"chat-meta\"><div id=\"chatSessionMeta\">Session: loading</div></div>
                        <div id=\"chatThread\" class=\"chat-thread\"></div>
                        <form id=\"chatForm\" class=\"chat-form\">
                            <div id=\"chatDropzone\" class=\"chat-dropzone\">Paste or drop a screenshot here, or use Image to attach png, jpg, or webp before sending.</div>
                            <div id=\"chatImagePreview\" class=\"chat-preview\" hidden>
                                <img id=\"chatImagePreviewImg\" alt=\"Selected TOD screenshot preview\" />
                                <div class=\"chat-preview-meta\">
                                    <div id=\"chatImagePreviewName\" class=\"chat-preview-name\">Selected image</div>
                                    <div id=\"chatImagePreviewMeta\" class=\"chat-preview-copy\">Send adds the screenshot to this TOD thread. Send To Codex then packages the latest screenshot into the handoff.</div>
                                </div>
                            </div>
                            <textarea id=\"chatInput\" class=\"chat-input\" placeholder=\"Ask TOD about training status, progress, blockers, or next steps.\"></textarea>
                            <input id=\"chatImageUploadInput\" type=\"file\" accept=\"image/png,image/jpeg,image/webp\" hidden />
                            <div class=\"chat-actions\"><div id=\"chatStatus\" class=\"status-inline\">Waiting for TOD chat state.</div><div class=\"chat-action-buttons\"><button id=\"chatImageUploadButton\" class=\"chat-button secondary\" type=\"button\">Image</button><button id=\"chatImageRemoveButton\" class=\"chat-button secondary\" type=\"button\">Remove Image</button><button id=\"copyLastTodResponseButton\" class=\"chat-button secondary\" type=\"button\">Copy Last TOD Reply</button><button id=\"chatSendButton\" class=\"chat-button\" type=\"submit\">Send To TOD</button></div></div>
                        </form>
                    </div>
                </section>
            </section>
      <section class=\"facts\">
        <article class=\"fact\"><div class=\"fact-label\">Canonical Objective</div><div id=\"factCanonicalObjective\" class=\"fact-value\">-</div><div id=\"factCanonicalMeta\" class=\"fact-meta\">Waiting for MIM handshake truth.</div></article>
        <article class=\"fact\"><div class=\"fact-label\">Live Request</div><div id=\"factLiveObjective\" class=\"fact-value\">-</div><div id=\"factLiveMeta\" class=\"fact-meta\">Waiting for listener request state.</div></article>
        <article class=\"fact\"><div class=\"fact-label\">Alignment</div><div id=\"factAlignment\" class=\"fact-value\">-</div><div id=\"factAlignmentMeta\" class=\"fact-meta\">Waiting for objective comparison.</div></article>
        <article class=\"fact\"><div class=\"fact-label\">Listener State</div><div id=\"factListenerState\" class=\"fact-value\">-</div><div id=\"factListenerMeta\" class=\"fact-meta\">Waiting for execution decision.</div></article>
        <article class=\"fact\"><div id=\"factPhaseProgressLabel\" class=\"fact-label\">Phase Progress</div><div id=\"factPhaseProgress\" class=\"fact-value\">-</div><div id=\"factPhaseProgressMeta\" class=\"fact-meta\">Waiting for bounded execution progress.</div></article>
        <article class=\"fact\"><div class=\"fact-label\">Stall Watch</div><div id=\"factStallWatch\" class=\"fact-value\">-</div><div id=\"factStallWatchMeta\" class=\"fact-meta\">Waiting for execution freshness evidence.</div></article>
        <article class=\"fact\"><div class=\"fact-label\">Publish Status</div><div id=\"factPublishStatus\" class=\"fact-value\">-</div><div id=\"factPublishMeta\" class=\"fact-meta\">Waiting for mirror and upload state.</div></article>
        <article class=\"fact\"><div class=\"fact-label\">Authority Reset</div><div id=\"factAuthorityReset\" class=\"fact-value\">-</div><div id=\"factAuthorityMeta\" class=\"fact-meta\">Waiting for reset policy state.</div></article>
        <article class=\"fact\"><div class=\"fact-label\">Training State</div><div id=\"factTrainingState\" class=\"fact-value\">-</div><div id=\"factTrainingMeta\" class=\"fact-meta\">Waiting for training telemetry.</div></article>
        <article class=\"fact\"><div class=\"fact-label\">Training Progress</div><div id=\"factTrainingProgress\" class=\"fact-value\">-</div><div id=\"factTrainingProgressMeta\" class=\"fact-meta\">Waiting for runtime and ETA.</div></article>
      </section>
      <section class=\"grid\">
        <div class=\"stack\">
          <section class=\"panel\">
            <h2>Training Status</h2>
            <div class=\"training-band\">
              <div id=\"trainingStateBadge\" class=\"training-pill\" data-tone=\"pending\">Unknown</div>
              <div>
                <div id=\"trainingSummary\" class=\"panel-copy\">Waiting for training status.</div>
                <div id=\"trainingPhaseDetail\" class=\"summary\">No phase detail is available yet.</div>
                                <div id="trainingPolicySummary" class="summary">Waiting for idle training policy.</div>
              </div>
              <div id=\"trainingStats\" class=\"training-stats\">Runtime: -<br />ETA: -</div>
            </div>
                        <div class=\"panel-actions\"><button id=\"trainingQuickActionButton\" class=\"chat-button\" type=\"button\">Start Training</button></div>
            <div class=\"progress-track\"><div id=\"trainingProgressBar\" class=\"progress-bar\"></div></div>
            <div id=\"trainingStagePills\" class=\"pill-row\"></div>
            <div class=\"kv\">
              <div class=\"kv-label\">Phase</div><div id=\"trainingPhase\" class=\"kv-value\">-</div>
              <div class=\"kv-label\">Current Step</div><div id=\"trainingCurrentStep\" class=\"kv-value\">-</div>
              <div class=\"kv-label\">Started</div><div id=\"trainingStarted\" class=\"kv-value\">-</div>
              <div class=\"kv-label\">Updated</div><div id=\"trainingUpdated\" class=\"kv-value\">-</div>
              <div class=\"kv-label\">Expected Complete</div><div id=\"trainingExpectedCompletion\" class=\"kv-value\">-</div>
                            <div class="kv-label">Idle Policy</div><div id="trainingIdlePolicy" class="kv-value">-</div>
                            <div class="kv-label">Idle Profiles</div><div id="trainingIdleProfiles" class="kv-value">-</div>
                            <div class="kv-label">Autonomy State</div><div id="trainingAutonomyState" class="kv-value">-</div>
              <div class=\"kv-label\">Warnings</div><div id=\"trainingWarnings\" class=\"kv-value\">-</div>
              <div class=\"kv-label\">Latest Error</div><div id=\"trainingLatestError\" class=\"kv-value\">-</div>
              <div class=\"kv-label\">Latest Resolution</div><div id=\"trainingLatestResolution\" class=\"kv-value\">-</div>
              <div class=\"kv-label\">Output Dir</div><div id=\"trainingOutputDir\" class=\"kv-value\">-</div>
              <div class=\"kv-label\">Trace Path</div><div id=\"trainingTracePath\" class=\"kv-value\">-</div>
            </div>
            <div id=\"trainingEvents\" class=\"collection-list\"></div>
          </section>
          <section class=\"panel\"><h2>Operator Guidance</h2><div class=\"panel-copy\">These are the bridge-level actions TOD should trust right now, ranked by severity in the shared status artifact.</div><div id=\"guidanceList\" class=\"guidance-list\"></div></section>
          <section class=\"panel\"><h2>Publish Pipeline</h2><div id=\"publishSummary\" class=\"panel-copy\">Waiting for publish details.</div><div class=\"kv\"><div class=\"kv-label\">Mirror</div><div id=\"publishMirror\" class=\"kv-value\">-</div><div class=\"kv-label\">Remote Access</div><div id=\"publishAccess\" class=\"kv-value\">-</div><div class=\"kv-label\">Consumer</div><div id=\"publishConsumer\" class=\"kv-value\">-</div><div class=\"kv-label\">Uploaded</div><div id=\"publishTime\" class=\"kv-value\">-</div><div class=\"kv-label\">Error</div><div id=\"publishError\" class=\"kv-value\">-</div></div></section>
        </div>
        <div class=\"stack\">
                    <section class=\"panel\"><h2>Execution Lane</h2><div id=\"executionSummary\" class=\"panel-copy\">Waiting for TOD execution status.</div><div class=\"kv\"><div class=\"kv-label\">Objective</div><div id=\"executionObjective\" class=\"kv-value\">-</div><div class=\"kv-label\">Task</div><div id=\"executionTask\" class=\"kv-value\">-</div><div class=\"kv-label\">Execution State</div><div id=\"executionState\" class=\"kv-value\">-</div><div class=\"kv-label\">Waiting On</div><div id=\"executionWaitTarget\" class=\"kv-value\">-</div><div class=\"kv-label\">Wait Reason</div><div id=\"executionWaitReason\" class=\"kv-value\">-</div><div class=\"kv-label\">Current Action</div><div id=\"executionAction\" class=\"kv-value\">-</div><div class=\"kv-label\">Next Step</div><div id=\"executionNextStep\" class=\"kv-value\">-</div><div class=\"kv-label\">Next Validation</div><div id=\"executionValidation\" class=\"kv-value\">-</div><div class=\"kv-label\">Command Output</div><div id=\"executionCommandOutput\" class=\"kv-value\">-</div><div class=\"kv-label\">Files Changed</div><div id=\"executionFilesChanged\" class=\"kv-value\">-</div><div class=\"kv-label\">Matched Files</div><div id=\"executionMatchedFiles\" class=\"kv-value\">-</div><div class=\"kv-label\">Rollback</div><div id=\"executionRollback\" class=\"kv-value\">-</div><div class=\"kv-label\">Recovery</div><div id=\"executionRecovery\" class=\"kv-value\">-</div><div class=\"kv-label\">Validation Checks</div><div id=\"executionChecks\" class=\"kv-value\">-</div><div class=\"kv-label\">Updated</div><div id=\"executionUpdated\" class=\"kv-value\">-</div></div></section>
          <section class=\"panel\"><h2>Alignment Detail</h2><div id=\"alignmentSummary\" class=\"panel-copy\">Waiting for alignment evidence.</div><div id=\"alignmentQuickActionPanel\" class=\"panel-actions\" hidden><button id=\"alignmentQuickActionButton\" class=\"chat-button secondary\" type=\"button\">Resolve Drift</button></div><div class=\"kv\"><div class=\"kv-label\">TOD Objective</div><div id=\"alignmentTodObjective\" class=\"kv-value\">-</div><div class=\"kv-label\">MIM Objective</div><div id=\"alignmentMimObjective\" class=\"kv-value\">-</div><div class=\"kv-label\">Bridge Evidence</div><div id=\"alignmentEvidence\" class=\"kv-value\">-</div><div class=\"kv-label\">Failure Signals</div><div id=\"alignmentSignals\" class=\"kv-value\">-</div></div></section>
          <section class=\"panel\"><h2>Listener Decision</h2><div id=\"decisionSummary\" class=\"panel-copy\">Waiting for listener decision state.</div><div class=\"kv\"><div class=\"kv-label\">Outcome</div><div id=\"decisionOutcome\" class=\"kv-value\">-</div><div class=\"kv-label\">Reason Code</div><div id=\"decisionReason\" class=\"kv-value\">-</div><div class=\"kv-label\">Execution State</div><div id=\"decisionState\" class=\"kv-value\">-</div><div class=\"kv-label\">Next Step</div><div id=\"decisionNextStep\" class=\"kv-value\">-</div><div class=\"kv-label\">Decision Age</div><div id=\"decisionAge\" class=\"kv-value\">-</div></div></section>
                    <section class=\"panel\"><h2>Authority Reset</h2><div id=\"authoritySummary\" class=\"panel-copy\">Waiting for authority reset state.</div><div class=\"kv\"><div class=\"kv-label\">Current Objective</div><div id=\"authorityCurrent\" class=\"kv-value\">-</div><div class=\"kv-label\">Max Valid</div><div id=\"authorityMaxValid\" class=\"kv-value\">-</div><div class=\"kv-label\">Effective</div><div id=\"authorityEffective\" class=\"kv-value\">-</div><div class=\"kv-label\">Invalidated</div><div id=\"authorityInvalidated\" class=\"kv-value\">-</div></div></section>
                    <section class=\"panel\"><h2>Codex Handoffs</h2><div class=\"panel-copy\">Recent real handoffs created from this TOD console and published into the shared TOD/MIM dialog lane.</div><div class=\"panel-actions\"><button id=\"handoffQuickActionButton\" class=\"chat-button secondary\" type=\"button\">Send To Codex</button></div><div id=\"handoffList\" class=\"collection-list\"></div></section>
        </div>
      </section>
      <div class=\"footer\"><div id=\"footerGenerated\">Loading state timestamp...</div><div>/tod/ui/state</div></div>
    </section>
  </main>
  <script>
    const statusChip = document.getElementById('todStatusChip');
    const statusHeadline = document.getElementById('todStatusHeadline');
    const statusSummary = document.getElementById('todStatusSummary');
    const mimConsoleLight = document.getElementById('mimConsoleLight');
    const todConsoleLight = document.getElementById('todConsoleLight');
    const guidanceList = document.getElementById('guidanceList');
    const footerGenerated = document.getElementById('footerGenerated');
    const factCanonicalObjective = document.getElementById('factCanonicalObjective');
    const factCanonicalMeta = document.getElementById('factCanonicalMeta');
    const factLiveObjective = document.getElementById('factLiveObjective');
    const factLiveMeta = document.getElementById('factLiveMeta');
    const factAlignment = document.getElementById('factAlignment');
    const factAlignmentMeta = document.getElementById('factAlignmentMeta');
    const factListenerState = document.getElementById('factListenerState');
    const factListenerMeta = document.getElementById('factListenerMeta');
    const factPhaseProgressLabel = document.getElementById('factPhaseProgressLabel');
    const factPhaseProgress = document.getElementById('factPhaseProgress');
    const factPhaseProgressMeta = document.getElementById('factPhaseProgressMeta');
    const factStallWatch = document.getElementById('factStallWatch');
    const factStallWatchMeta = document.getElementById('factStallWatchMeta');
    const factPublishStatus = document.getElementById('factPublishStatus');
    const factPublishMeta = document.getElementById('factPublishMeta');
    const factAuthorityReset = document.getElementById('factAuthorityReset');
    const factAuthorityMeta = document.getElementById('factAuthorityMeta');
    const factTrainingState = document.getElementById('factTrainingState');
    const factTrainingMeta = document.getElementById('factTrainingMeta');
    const factTrainingProgress = document.getElementById('factTrainingProgress');
    const factTrainingProgressMeta = document.getElementById('factTrainingProgressMeta');
    const trainingStateBadge = document.getElementById('trainingStateBadge');
    const trainingSummary = document.getElementById('trainingSummary');
    const trainingPhaseDetail = document.getElementById('trainingPhaseDetail');
    const trainingPolicySummary = document.getElementById('trainingPolicySummary');
    const trainingStats = document.getElementById('trainingStats');
    const trainingProgressBar = document.getElementById('trainingProgressBar');
    const trainingStagePills = document.getElementById('trainingStagePills');
    const trainingPhase = document.getElementById('trainingPhase');
    const trainingCurrentStep = document.getElementById('trainingCurrentStep');
    const trainingStarted = document.getElementById('trainingStarted');
    const trainingUpdated = document.getElementById('trainingUpdated');
    const trainingExpectedCompletion = document.getElementById('trainingExpectedCompletion');
    const trainingIdlePolicy = document.getElementById('trainingIdlePolicy');
    const trainingIdleProfiles = document.getElementById('trainingIdleProfiles');
    const trainingAutonomyState = document.getElementById('trainingAutonomyState');
    const trainingWarnings = document.getElementById('trainingWarnings');
    const trainingLatestError = document.getElementById('trainingLatestError');
    const trainingLatestResolution = document.getElementById('trainingLatestResolution');
    const trainingOutputDir = document.getElementById('trainingOutputDir');
    const trainingTracePath = document.getElementById('trainingTracePath');
    const trainingEvents = document.getElementById('trainingEvents');
    const trainingQuickActionButton = document.getElementById('trainingQuickActionButton');
    const chatSessionMeta = document.getElementById('chatSessionMeta');
    const chatActivityIndicator = document.getElementById('chatActivityIndicator');
    const chatActivityText = document.getElementById('chatActivityText');
    const chatActivitySummary = document.getElementById('chatActivitySummary');
    const chatThread = document.getElementById('chatThread');
    const chatForm = document.getElementById('chatForm');
    const chatInput = document.getElementById('chatInput');
    const chatStatus = document.getElementById('chatStatus');
    const chatSendButton = document.getElementById('chatSendButton');
    const chatImageUploadInput = document.getElementById('chatImageUploadInput');
    const chatImageUploadButton = document.getElementById('chatImageUploadButton');
    const chatImageRemoveButton = document.getElementById('chatImageRemoveButton');
    const chatImagePreview = document.getElementById('chatImagePreview');
    const chatImagePreviewImg = document.getElementById('chatImagePreviewImg');
    const chatImagePreviewName = document.getElementById('chatImagePreviewName');
    const chatImagePreviewMeta = document.getElementById('chatImagePreviewMeta');
    const chatDropzone = document.getElementById('chatDropzone');
    const copyLastTodResponseButton = document.getElementById('copyLastTodResponseButton');
    const publishSummary = document.getElementById('publishSummary');
    const publishMirror = document.getElementById('publishMirror');
    const publishAccess = document.getElementById('publishAccess');
    const publishConsumer = document.getElementById('publishConsumer');
    const publishTime = document.getElementById('publishTime');
    const publishError = document.getElementById('publishError');
    const executionSummary = document.getElementById('executionSummary');
    const executionObjective = document.getElementById('executionObjective');
    const executionTask = document.getElementById('executionTask');
    const executionState = document.getElementById('executionState');
    const executionWaitTarget = document.getElementById('executionWaitTarget');
    const executionWaitReason = document.getElementById('executionWaitReason');
    const executionAction = document.getElementById('executionAction');
    const executionNextStep = document.getElementById('executionNextStep');
    const executionValidation = document.getElementById('executionValidation');
    const executionCommandOutput = document.getElementById('executionCommandOutput');
    const executionFilesChanged = document.getElementById('executionFilesChanged');
    const executionMatchedFiles = document.getElementById('executionMatchedFiles');
    const executionRollback = document.getElementById('executionRollback');
    const executionRecovery = document.getElementById('executionRecovery');
    const executionChecks = document.getElementById('executionChecks');
    const executionUpdated = document.getElementById('executionUpdated');
    const alignmentSummary = document.getElementById('alignmentSummary');
    const alignmentTodObjective = document.getElementById('alignmentTodObjective');
    const alignmentMimObjective = document.getElementById('alignmentMimObjective');
    const alignmentEvidence = document.getElementById('alignmentEvidence');
    const alignmentSignals = document.getElementById('alignmentSignals');
    const alignmentQuickActionPanel = document.getElementById('alignmentQuickActionPanel');
    const alignmentQuickActionButton = document.getElementById('alignmentQuickActionButton');
    const decisionSummary = document.getElementById('decisionSummary');
    const decisionOutcome = document.getElementById('decisionOutcome');
    const decisionReason = document.getElementById('decisionReason');
    const decisionState = document.getElementById('decisionState');
    const decisionNextStep = document.getElementById('decisionNextStep');
    const decisionAge = document.getElementById('decisionAge');
    const authoritySummary = document.getElementById('authoritySummary');
    const authorityCurrent = document.getElementById('authorityCurrent');
    const authorityMaxValid = document.getElementById('authorityMaxValid');
    const authorityEffective = document.getElementById('authorityEffective');
    const authorityInvalidated = document.getElementById('authorityInvalidated');
    const handoffList = document.getElementById('handoffList');
    const handoffQuickActionButton = document.getElementById('handoffQuickActionButton');
    const CHAT_STORAGE_KEY = 'todPublicChatSessionKeyV1';
    let latestConversation = null;
    let latestChatMessages = [];
    let latestVisitor = {{ name: 'Dave' }};
    let latestExecution = {{}};
    let latestTraining = {{}};
    let latestSessionActivity = {{}};
    let chatQuickActionMap = new Map();
    let currentStatusCode = 'unknown';
    let selectedComposerImage = null;
    const autoTriggeredSessions = new Set();
    function safeText(value, fallback = '-') {{ const text = String(value || '').trim(); return text || fallback; }}
    function safeJoin(values, fallback = 'None') {{ return Array.isArray(values) && values.length ? values.map((item) => safeText(item, '')).filter(Boolean).join(', ') : fallback; }}
    function formatSeconds(value) {{ const numeric = Number(value); if (!Number.isFinite(numeric) || numeric < 0) return 'Unknown'; const total = Math.round(numeric); const days = Math.floor(total / 86400); const hours = Math.floor((total % 86400) / 3600); const minutes = Math.floor((total % 3600) / 60); const seconds = total % 60; const parts = []; if (days) parts.push(`${{days}}d`); if (hours || parts.length) parts.push(`${{hours}}h`); if (minutes || parts.length) parts.push(`${{minutes}}m`); if (!parts.length) parts.push(`${{seconds}}s`); return parts.join(' '); }}
    function trainingTone(training) {{ const state = safeText(training && (training.state || training.state_label), 'unknown').toLowerCase(); if (state.includes('complete')) return 'completed'; if (state.includes('run') || state.includes('active') || training && training.active) return 'running'; if (state.includes('fail') || state.includes('error')) return 'failed'; if (state.includes('pause')) return 'paused'; return 'pending'; }}
    function createChatSessionKey(defaultKey) {{ const seed = Math.random().toString(36).slice(2, 10); return `${{safeText(defaultKey, 'tod-console-public')}}-${{seed}}`; }}
    function setChatSessionKey(sessionKey) {{ try {{ if (sessionKey) window.localStorage.setItem(CHAT_STORAGE_KEY, sessionKey); }} catch (_error) {{ }} return sessionKey; }}
    function getChatSessionKey(defaultKey) {{ try {{ const existing = window.localStorage.getItem(CHAT_STORAGE_KEY); if (existing) return existing; const created = createChatSessionKey(defaultKey); window.localStorage.setItem(CHAT_STORAGE_KEY, created); return created; }} catch (_error) {{ return createChatSessionKey(defaultKey); }} }}
    function shouldRotateStaleChatSession(session, messages) {{ const activity = session && typeof session.activity === 'object' ? session.activity : {{}}; const activityState = safeText(activity.state, 'idle').toLowerCase(); const ageSeconds = Number(activity.last_activity_age_seconds); if (!Array.isArray(messages) || !messages.length) return false; if (!Number.isFinite(ageSeconds) || ageSeconds < 0) return false; if (selectedComposerImage instanceof File) return false; if (chatInput && String(chatInput.value || '').trim()) return false; if (activityState === 'stalled' && ageSeconds >= 600) return true; if (activityState === 'complete' && ageSeconds >= 1800) return true; return false; }}
    function rotateChatSession(defaultKey) {{ const sessionKey = setChatSessionKey(createChatSessionKey(defaultKey)); latestChatMessages = []; return sessionKey; }}
    function getAutoTriggerStorageKey(sessionKey, statusCode, prompt) {{ return `todAutoTrigger:${{safeText(sessionKey, 'unknown')}}:${{safeText(statusCode, 'unknown')}}:${{safeText(prompt, '').slice(0, 96)}}`; }}
    function hasAutoTriggered(storageKey) {{ try {{ return window.sessionStorage.getItem(storageKey) === '1'; }} catch (_error) {{ return autoTriggeredSessions.has(storageKey); }} }}
    function markAutoTriggered(storageKey) {{ try {{ window.sessionStorage.setItem(storageKey, '1'); }} catch (_error) {{ }} autoTriggeredSessions.add(storageKey); }}
    function clearAutoTriggered(storageKey) {{ try {{ window.sessionStorage.removeItem(storageKey); }} catch (_error) {{ }} autoTriggeredSessions.delete(storageKey); }}
    function clearNode(node) {{ while (node && node.firstChild) node.removeChild(node.firstChild); }}
    function setConsoleLight(node, ok) {{ if (!node) return; node.classList.remove('ok', 'err'); node.classList.add(ok ? 'ok' : 'err'); }}
    function appendCollectionItem(node, label, meta, text) {{ const item = document.createElement('article'); item.className = 'collection-item'; const top = document.createElement('div'); top.className = 'collection-top'; const labelNode = document.createElement('div'); labelNode.className = 'collection-label'; labelNode.textContent = safeText(label, 'Item'); const metaNode = document.createElement('div'); metaNode.className = 'collection-meta'; metaNode.textContent = safeText(meta, ''); const textNode = document.createElement('div'); textNode.className = 'collection-text'; textNode.textContent = safeText(text, 'No detail published.'); top.appendChild(labelNode); top.appendChild(metaNode); item.appendChild(top); item.appendChild(textNode); node.appendChild(item); }}
    function setChatButtonsDisabled(disabled) {{ chatSendButton.disabled = disabled; if (chatImageUploadButton) chatImageUploadButton.disabled = disabled; if (chatImageRemoveButton) chatImageRemoveButton.disabled = disabled; if (copyLastTodResponseButton) copyLastTodResponseButton.disabled = disabled; if (trainingQuickActionButton) trainingQuickActionButton.disabled = disabled; if (alignmentQuickActionButton) alignmentQuickActionButton.disabled = disabled; if (handoffQuickActionButton) handoffQuickActionButton.disabled = disabled; }}
    function updateCopyButtonState() {{ if (!copyLastTodResponseButton) return; const hasTodReply = latestChatMessages.some((message) => messageRole(message) === 'assistant' && messageBody(message)); copyLastTodResponseButton.disabled = !hasTodReply; }}
    function messageAttachment(message) {{ return message && typeof message.attachment === 'object' ? message.attachment : null; }}
    function resetComposerImage() {{ selectedComposerImage = null; if (chatImageUploadInput) chatImageUploadInput.value = ''; if (chatImagePreviewImg) chatImagePreviewImg.removeAttribute('src'); if (chatImagePreviewName) chatImagePreviewName.textContent = 'Selected image'; if (chatImagePreviewMeta) chatImagePreviewMeta.textContent = 'Send adds the screenshot to this TOD thread. Send To Codex then packages the latest screenshot into the handoff.'; if (chatImagePreview) chatImagePreview.hidden = true; if (chatDropzone) chatDropzone.classList.remove('active'); }}
    function setComposerImage(file) {{ if (!(file instanceof File)) return false; const allowed = ['image/png', 'image/jpeg', 'image/webp']; if (!allowed.includes(String(file.type || '').toLowerCase())) {{ chatStatus.textContent = 'Only png, jpg, jpeg, and webp screenshots are supported here.'; return false; }} if (Number(file.size || 0) > 2 * 1024 * 1024) {{ chatStatus.textContent = 'Screenshots on /tod must be 2 MB or smaller.'; return false; }} selectedComposerImage = file; if (chatImagePreviewName) chatImagePreviewName.textContent = file.name || 'Selected image'; if (chatImagePreviewMeta) chatImagePreviewMeta.textContent = `${{Math.max(1, Math.round((Number(file.size || 0)) / 1024))}} KB · ${{safeText(file.type, 'image file')}}`; if (chatImagePreviewImg) {{ const previewUrl = URL.createObjectURL(file); chatImagePreviewImg.src = previewUrl; }} if (chatImagePreview) chatImagePreview.hidden = false; chatStatus.textContent = 'Screenshot attached. Add an optional note and send, or use Send To Codex after it lands in the thread.'; return true; }}
    function fileToDataUrl(file) {{ return new Promise((resolve, reject) => {{ const reader = new FileReader(); reader.onload = () => resolve(String(reader.result || '')); reader.onerror = () => reject(reader.error || new Error('file_read_failed')); reader.readAsDataURL(file); }}); }}
    function renderGuidance(items) {{ clearNode(guidanceList); if (!Array.isArray(items) || !items.length) {{ appendCollectionItem(guidanceList, 'Guidance', '', 'No operator guidance is currently published.'); return; }} items.forEach((item) => {{ const card = document.createElement('article'); card.className = 'guidance-item'; const code = document.createElement('div'); code.className = 'guidance-code'; code.textContent = `${{safeText(item.severity, 'info')}} · ${{safeText(item.code, 'guidance')}}`; const summary = document.createElement('div'); summary.className = 'guidance-summary'; summary.textContent = safeText(item.summary, 'No summary'); const action = document.createElement('div'); action.className = 'guidance-action'; action.textContent = safeText(item.recommended_action, 'No action published'); card.appendChild(code); card.appendChild(summary); card.appendChild(action); guidanceList.appendChild(card); }}); }}
    function renderHandoffs(items) {{ clearNode(handoffList); if (!Array.isArray(items) || !items.length) {{ appendCollectionItem(handoffList, 'No recent handoffs', '', 'Send To Codex will create a dialog session and it will appear here after publication.'); return; }} items.forEach((item) => {{ const card = document.createElement('article'); card.className = 'collection-item'; const top = document.createElement('div'); top.className = 'collection-top'; const labelNode = document.createElement('div'); labelNode.className = 'collection-label'; labelNode.textContent = `${{safeText(item.status_label, 'Unknown')}} · ${{safeText(item.session_id, 'unknown session')}}`; const metaNode = document.createElement('div'); metaNode.className = 'collection-meta'; metaNode.textContent = `${{safeText(item.updated_age, 'Unknown')}} · messages=${{safeText(item.message_count, '0')}}`; const summaryNode = document.createElement('div'); summaryNode.className = 'collection-text'; summaryNode.textContent = safeText(item.issue_summary, 'No issue summary published.'); const idsNode = document.createElement('div'); idsNode.className = 'collection-text muted'; idsNode.textContent = `request=${{safeText(item.request_id, 'n/a')}} · task=${{safeText(item.task_id, 'n/a')}} · objective=${{safeText(item.objective_id, 'n/a')}}`; const detailNode = document.createElement('div'); detailNode.className = 'collection-text muted'; detailNode.textContent = `Last: ${{safeText(item.last_message_from, 'unknown')}}/${{safeText(item.last_message_type, 'unknown')}} · Artifact: ${{safeText(item.copilot_artifact_path, 'not published')}}`; top.appendChild(labelNode); top.appendChild(metaNode); card.appendChild(top); card.appendChild(summaryNode); card.appendChild(idsNode); card.appendChild(detailNode); if (item.bounded_repair_request) {{ const repairNode = document.createElement('div'); repairNode.className = 'collection-text'; repairNode.textContent = `Repair: ${{safeText(item.bounded_repair_request)}}`; card.appendChild(repairNode); }} if (item.next_validation) {{ const validationNode = document.createElement('div'); validationNode.className = 'collection-text'; validationNode.textContent = `Validation: ${{safeText(item.next_validation)}}`; card.appendChild(validationNode); }} handoffList.appendChild(card); }}); }}
    function renderTraining(training) {{ const payload = training && typeof training === 'object' ? training : {{}}; latestTraining = payload; const available = Boolean(payload.available); const percent = Math.max(0, Math.min(100, Number(payload.percent_complete || 0))); const runtimeText = formatSeconds(payload.runtime_seconds); const etaText = payload.eta_seconds == null ? 'Unknown' : formatSeconds(payload.eta_seconds); const idlePolicy = payload.idle_policy && typeof payload.idle_policy === 'object' ? payload.idle_policy : {{}}; factTrainingState.textContent = safeText(payload.state_label || payload.state, 'Unknown'); factTrainingMeta.textContent = available ? `${{safeText(payload.summary, 'No training summary')}} · ${{safeText(idlePolicy.policy_summary, 'Idle training policy not published.')}}` : 'No training telemetry is published.'; factTrainingProgress.textContent = available ? `${{Math.round(percent)}}%` : 'Unknown'; factTrainingProgressMeta.textContent = available ? `Runtime: ${{runtimeText}} · ETA: ${{etaText}}` : 'No runtime estimate is available.'; trainingStateBadge.textContent = safeText(payload.state_label || payload.state, 'Unknown'); trainingStateBadge.dataset.tone = trainingTone(payload); trainingSummary.textContent = safeText(payload.summary, 'No training summary is available.'); trainingPhaseDetail.textContent = safeText(payload.phase_detail, 'No phase detail is available yet.'); trainingPolicySummary.textContent = safeText(idlePolicy.policy_summary, 'Idle training policy not published.'); trainingStats.innerHTML = `Runtime: ${{runtimeText}}<br />ETA: ${{etaText}}`; trainingProgressBar.style.width = `${{percent}}%`; trainingPhase.textContent = safeText(payload.phase_label || payload.phase, 'Unknown'); trainingCurrentStep.textContent = safeText(payload.current_step, 'Not published'); trainingStarted.textContent = payload.started_at ? `${{safeText(payload.started_at)}} · ${{safeText(payload.started_age, 'Unknown')}}` : 'Unknown'; trainingUpdated.textContent = payload.updated_at ? `${{safeText(payload.updated_at)}} · ${{safeText(payload.updated_age, 'Unknown')}}` : 'Unknown'; trainingExpectedCompletion.textContent = payload.expected_completion_utc ? safeText(payload.expected_completion_utc) : 'Unknown'; trainingIdlePolicy.textContent = idlePolicy.continuous_idle_enabled ? `Always train when idle · threshold ${{safeText(idlePolicy.idle_threshold_minutes, '0')}}m` : 'Disabled'; trainingIdleProfiles.textContent = `Short < ${{safeText(idlePolicy.long_idle_profile_threshold_minutes, '30')}}m: ${{safeText(idlePolicy.short_idle_profile_label, 'Runtime-safe validation subset')}} · Long >= ${{safeText(idlePolicy.long_idle_profile_threshold_minutes, '30')}}m: ${{safeText(idlePolicy.long_idle_profile_label, 'Repo edit / test / recover pack')}}`; trainingAutonomyState.textContent = `${{safeText(idlePolicy.current_tod_state, 'unknown')}} · ${{safeText(idlePolicy.activity_summary, 'No autonomy activity is published.')}}`; trainingWarnings.textContent = safeJoin(payload.warnings, 'None'); trainingLatestError.textContent = payload.latest_error ? `${{safeText(payload.latest_error)}}${{payload.latest_error_at ? ` · ${{safeText(payload.latest_error_at)}}` : ''}}` : 'None'; trainingLatestResolution.textContent = payload.latest_resolution ? `${{safeText(payload.latest_resolution)}}${{payload.latest_resolution_at ? ` · ${{safeText(payload.latest_resolution_at)}}` : ''}}` : 'None'; trainingOutputDir.textContent = safeText(payload.artifacts && payload.artifacts.output_dir, 'Not published'); trainingTracePath.textContent = safeText(payload.artifacts && payload.artifacts.trace_path, 'Not published'); clearNode(trainingStagePills); if (Array.isArray(payload.stages) && payload.stages.length) {{ payload.stages.forEach((stage) => {{ const pill = document.createElement('div'); pill.className = 'mini-pill'; pill.textContent = `${{safeText(stage.label, 'Stage')}}: ${{safeText(stage.status, 'unknown')}}`; trainingStagePills.appendChild(pill); }}); }} else {{ const pill = document.createElement('div'); pill.className = 'mini-pill'; pill.textContent = 'No stage telemetry'; trainingStagePills.appendChild(pill); }} clearNode(trainingEvents); if (Array.isArray(payload.recent_events) && payload.recent_events.length) {{ payload.recent_events.forEach((item) => appendCollectionItem(trainingEvents, safeText(item.type, 'event'), safeText(item.generated_age || item.generated_at, ''), safeText(item.summary, 'No event summary'))); }} else if (Array.isArray(payload.resolutions) && payload.resolutions.length) {{ payload.resolutions.forEach((item) => appendCollectionItem(trainingEvents, 'Resolution', '', item)); }} else {{ appendCollectionItem(trainingEvents, 'Training Feed', '', 'No training events are currently published.'); }} }}
    function messageRole(message) {{ const role = safeText(message && (message.role || message.actor || message.source || message.type), 'message').toLowerCase(); if (role.includes('visitor') || role.includes('user')) return 'user'; if (role.includes('tod') || role.includes('assistant') || role.includes('reply')) return 'assistant'; return 'system'; }}
    function messageLabel(message, role) {{ if (role === 'user') return safeText(message && message.author_name, safeText(latestVisitor && latestVisitor.name, 'Dave')); if (role === 'assistant') return 'TOD'; return 'TOD Activity'; }}
    function messageBody(message) {{ return safeText(message && (message.content || message.message || message.text || message.body || message.summary), ''); }}
    function getLastTodExchange(messages) {{ if (!Array.isArray(messages) || !messages.length) return null; for (let todIndex = messages.length - 1; todIndex >= 0; todIndex -= 1) {{ const todMessage = messages[todIndex]; if (messageRole(todMessage) !== 'assistant' || !messageBody(todMessage)) continue; let userMessage = null; for (let userIndex = todIndex - 1; userIndex >= 0; userIndex -= 1) {{ const candidate = messages[userIndex]; if (messageRole(candidate) === 'user' && messageBody(candidate)) {{ userMessage = candidate; break; }} }} return {{ user: userMessage, tod: todMessage }}; }} return null; }}
    function buildLastTodExchangeCopy(messages) {{ const exchange = getLastTodExchange(messages); if (!exchange || !exchange.tod) return ''; const lines = []; if (exchange.user && messageBody(exchange.user)) {{ lines.push('User action:'); lines.push(messageBody(exchange.user)); lines.push(''); }} lines.push('TOD response:'); lines.push(messageBody(exchange.tod)); return lines.join('\\n'); }}
    async function copyTextToClipboard(value) {{ const text = String(value || ''); if (!text.trim()) return false; if (navigator.clipboard && navigator.clipboard.writeText) {{ await navigator.clipboard.writeText(text); return true; }} const textArea = document.createElement('textarea'); textArea.value = text; textArea.setAttribute('readonly', 'readonly'); textArea.style.position = 'fixed'; textArea.style.opacity = '0'; textArea.style.pointerEvents = 'none'; document.body.appendChild(textArea); textArea.focus(); textArea.select(); const copied = document.execCommand('copy'); document.body.removeChild(textArea); return copied; }}
    async function handleCopyLastTodResponse() {{ const transcript = buildLastTodExchangeCopy(latestChatMessages); if (!transcript) {{ chatStatus.textContent = 'No TOD reply is available to copy yet.'; return; }} try {{ copyLastTodResponseButton.disabled = true; await copyTextToClipboard(transcript); chatStatus.textContent = 'Copied the last user action and TOD reply.'; }} catch (error) {{ chatStatus.textContent = `Copy failed: ${{safeText(error && error.message, 'clipboard unavailable')}}`; }} finally {{ updateCopyButtonState(); }} }}
    function renderQuickActions(conversation) {{ chatQuickActionMap = new Map(); const actions = conversation && Array.isArray(conversation.quick_actions) ? conversation.quick_actions : []; actions.forEach((action) => {{ const prompt = safeText(action && action.prompt, ''); const id = safeText(action && action.id, 'quick-action'); const label = safeText(action && action.label, 'Quick Action'); const description = safeText(action && action.description, ''); const actionType = safeText(action && action.action_type, 'prompt'); chatQuickActionMap.set(id, {{ prompt, label, description, actionType }}); }}); const trainingAction = chatQuickActionMap.get('start-training'); if (trainingQuickActionButton) {{ trainingQuickActionButton.textContent = safeText(trainingAction && trainingAction.label, 'Start Training'); trainingQuickActionButton.title = safeText(trainingAction && trainingAction.description, 'Start the bounded training request.'); trainingQuickActionButton.hidden = !trainingAction; }} const driftAction = chatQuickActionMap.get('resolve-drift'); if (alignmentQuickActionButton) {{ alignmentQuickActionButton.textContent = safeText(driftAction && driftAction.label, 'Resolve Drift'); alignmentQuickActionButton.title = safeText(driftAction && driftAction.description, 'Send a bounded drift resolution request.'); alignmentQuickActionButton.hidden = !driftAction; }} const handoffAction = chatQuickActionMap.get('send-to-copilot'); if (handoffQuickActionButton) {{ handoffQuickActionButton.textContent = safeText(handoffAction && handoffAction.label, 'Send To Codex'); handoffQuickActionButton.title = safeText(handoffAction && handoffAction.description, 'Create a Codex handoff from the current TOD thread.'); handoffQuickActionButton.hidden = !handoffAction; }} }}
    function renderExecution(execution) {{ const payload = execution && typeof execution === 'object' ? execution : {{}}; latestExecution = payload; executionSummary.textContent = safeText(payload.summary, 'No TOD execution activity is currently published.'); executionObjective.textContent = safeText(payload.objective_id, 'Unknown'); executionTask.textContent = safeText(payload.title || payload.task_focus || payload.task_id, 'No active task'); executionState.textContent = safeText(payload.activity_label || payload.execution_state || payload.status, 'Idle'); executionWaitTarget.textContent = safeText(payload.wait_target_label, 'Not waiting on an external dependency.'); executionWaitReason.textContent = safeText(payload.wait_reason, 'No specific wait reason published.'); executionAction.textContent = safeText(payload.current_action, 'No current action published.'); executionNextStep.textContent = safeText(payload.next_step, 'No next step published.'); executionValidation.textContent = safeText(payload.next_validation || payload.validation_summary, 'No validation target published.'); executionCommandOutput.textContent = safeText(payload.command_output, 'No command output published.'); executionFilesChanged.textContent = safeJoin(payload.files_changed, 'None'); executionMatchedFiles.textContent = safeJoin(payload.matched_files, 'None'); executionRollback.textContent = safeText(payload.rollback_state, 'not_needed'); executionRecovery.textContent = safeText(payload.recovery_state, 'not_needed'); const checks = Array.isArray(payload.validation_checks) ? payload.validation_checks.map((item) => item && typeof item === 'object' ? `${{safeText(item.name, 'check')}}=${{item.passed ? 'passed' : 'failed'}}` : '').filter(Boolean) : []; executionChecks.textContent = checks.length ? checks.join(', ') : 'None'; executionUpdated.textContent = payload.updated_at ? `${{safeText(payload.updated_at)}} · ${{safeText(payload.updated_age, 'Unknown')}}` : 'Unknown'; }}
    function renderPrimaryStatus(status, execution) {{ const statusPayload = status && typeof status === 'object' ? status : {{}}; const executionPayload = execution && typeof execution === 'object' ? execution : {{}}; const trainingPayload = latestTraining && typeof latestTraining === 'object' ? latestTraining : {{}}; const trainingActive = Boolean(trainingPayload.available) && Boolean(trainingPayload.active); if (trainingActive) {{ const trainingState = safeText(trainingPayload.state_label || trainingPayload.state, 'Training Active'); const trainingSummary = safeText(trainingPayload.summary, 'TOD training is active.'); const trainingStep = safeText(trainingPayload.current_step, 'Current step not published.'); const executionSlice = Boolean(executionPayload.available) ? safeText(executionPayload.summary, '') : ''; statusChip.textContent = trainingState.toUpperCase(); statusChip.dataset.tone = safeText(trainingTone(trainingPayload), 'pending').toLowerCase(); statusHeadline.textContent = 'TOD training is active'; statusSummary.textContent = safeText([trainingSummary, `Current step: ${{trainingStep}}.`, executionSlice ? `Latest execution slice: ${{executionSlice}}` : ''].filter(Boolean).join(' '), 'TOD training is active.'); return; }} const useExecution = Boolean(executionPayload.available) && ['working', 'waiting', 'complete', 'stalled'].includes(safeText(executionPayload.activity_state, 'idle').toLowerCase()); if (useExecution) {{ const phaseProgress = executionPayload.phase_progress && typeof executionPayload.phase_progress === 'object' ? executionPayload.phase_progress : {{}}; const stallSignal = executionPayload.stall_signal && typeof executionPayload.stall_signal === 'object' ? executionPayload.stall_signal : {{}}; const stallLevel = safeText(stallSignal.level, 'ok').toLowerCase(); const phaseLabel = safeText(phaseProgress.label, 'Phase progress'); const phaseSummary = Boolean(phaseProgress.available) ? `${{phaseLabel}} ${{Math.max(0, Math.min(100, Number(phaseProgress.percent_complete || 0)))}}% complete; next gate ${{safeText(phaseProgress.next_gate, 'Unknown')}}.` : ''; const stallSummary = stallLevel !== 'ok' ? safeText(stallSignal.summary, '') : executionPayload.available ? 'Stall watch clear.' : ''; const activityState = safeText(executionPayload.activity_state, 'unknown').toLowerCase(); const activityLabel = safeText(executionPayload.activity_label, 'UNKNOWN'); statusChip.textContent = activityLabel.toUpperCase(); statusChip.dataset.tone = activityState; statusHeadline.textContent = activityState === 'complete' ? 'Latest TOD execution slice is complete' : `TOD execution is ${{activityLabel.toLowerCase()}}`; statusSummary.textContent = safeText([safeText(executionPayload.activity_summary || executionPayload.summary, ''), phaseSummary, stallSummary].filter(Boolean).join(' '), 'No shared TOD execution summary is available.'); return; }} statusChip.textContent = safeText(statusPayload.label, 'UNKNOWN'); statusChip.dataset.tone = safeText(statusPayload.code, 'unknown').toLowerCase(); statusHeadline.textContent = safeText(statusPayload.headline, 'TOD state unavailable'); statusSummary.textContent = safeText(statusPayload.summary, 'No shared TOD summary is available.'); }}
    function renderTopActivity() {{ const execution = latestExecution && typeof latestExecution === 'object' ? latestExecution : {{}}; const trainingPayload = latestTraining && typeof latestTraining === 'object' ? latestTraining : {{}}; const sessionActivity = latestSessionActivity && typeof latestSessionActivity === 'object' ? latestSessionActivity : {{}}; const trainingActive = Boolean(trainingPayload.available) && Boolean(trainingPayload.active); const useExecution = !trainingActive && Boolean(execution.available) && safeText(execution.activity_state, 'idle').toLowerCase() !== 'idle'; const state = trainingActive ? 'working' : useExecution ? safeText(execution.activity_state, 'idle').toLowerCase() : safeText(sessionActivity.state, 'idle').toLowerCase(); const label = trainingActive ? 'Training' : useExecution ? safeText(execution.activity_label, 'Idle') : safeText(sessionActivity.label, 'Idle'); const summary = trainingActive ? safeText([safeText(trainingPayload.summary, ''), safeText(trainingPayload.current_step, '')].filter(Boolean).join(' · '), 'TOD training is active.') : useExecution ? safeText(execution.activity_summary, 'Waiting for TOD activity.') : safeText(sessionActivity.summary, 'Waiting for TOD activity.'); const ageText = trainingActive ? (trainingPayload.updated_at ? ` · updated ${{safeText(trainingPayload.updated_age, 'Unknown')}}` : '') : (() => {{ const ageSeconds = useExecution ? Number(execution.last_update_age_seconds) : Number(sessionActivity.last_activity_age_seconds); return Number.isFinite(ageSeconds) && ageSeconds >= 0 ? ` · last update ${{formatSeconds(ageSeconds)}} ago` : ''; }})(); if (chatActivityIndicator) chatActivityIndicator.dataset.state = state; if (chatActivityText) chatActivityText.textContent = label; if (chatActivitySummary) chatActivitySummary.textContent = `${{summary}}${{ageText}}`; }}
    function snapshotChatScroll() {{ if (!chatThread) return {{ hadMessages: false, atBottom: true, top: 0 }}; const maxTop = Math.max(0, chatThread.scrollHeight - chatThread.clientHeight); const top = Number(chatThread.scrollTop || 0); return {{ hadMessages: chatThread.childElementCount > 0, atBottom: maxTop - top <= 48, top }}; }}
    function isSyntheticExecutionOnlyThread(messages) {{ if (!Array.isArray(messages) || !messages.length) return false; const hasUserMessages = messages.some((message) => messageRole(message) === 'user'); const firstBody = messageBody(messages[0]); return !hasUserMessages && firstBody.startsWith('Live execution feed:'); }}
    function restoreChatScroll(snapshot, messages) {{ if (!chatThread) return; if (!snapshot || !snapshot.hadMessages) {{ chatThread.scrollTop = isSyntheticExecutionOnlyThread(messages) ? 0 : chatThread.scrollHeight; return; }} if (snapshot.atBottom) {{ chatThread.scrollTop = chatThread.scrollHeight; return; }} chatThread.scrollTop = snapshot.top; }}
    function renderChatState(data) {{ const session = data && typeof data.session === 'object' ? data.session : {{}}; const messages = Array.isArray(data && data.messages) ? data.messages : []; latestChatMessages = messages; const visitor = data && typeof data.visitor === 'object' ? data.visitor : {{}}; latestVisitor = visitor; const sessionKey = safeText(session.session_key || getChatSessionKey(latestConversation && latestConversation.default_session_key), 'unknown'); if (shouldRotateStaleChatSession(session, messages)) {{ rotateChatSession(latestConversation && latestConversation.default_session_key); chatStatus.textContent = 'Started a fresh TOD chat session because the previous thread was stale.'; clearNode(chatThread); appendCollectionItem(chatThread, 'TOD Chat', '', 'Started a fresh TOD session because the previous thread was stale. Ask for current status, next steps, or send a new request.'); renderChatActivity({{ activity: {{ state: 'idle', label: 'Fresh Session', summary: 'Started a fresh TOD session after the previous thread went stale.' }} }}); updateCopyButtonState(); setTimeout(() => {{ refreshChatState().catch((error) => {{ chatStatus.textContent = safeText(error && error.message, 'Unable to refresh fresh TOD session.'); }}); }}, 0); return; }} chatSessionMeta.textContent = `Session: ${{sessionKey}} · User: ${{safeText(visitor.name, 'Dave')}}`; clearNode(chatThread); if (!messages.length) {{ appendCollectionItem(chatThread, 'TOD Chat', '', 'No TOD messages are in this session yet. Ask for status, blockers, training progress, execution work, or attach a screenshot.'); }} else {{ messages.forEach((message) => {{ const bubble = document.createElement('article'); const role = messageRole(message); bubble.className = `chat-bubble ${{role}}`; const roleNode = document.createElement('div'); roleNode.className = 'chat-role'; roleNode.textContent = messageLabel(message, role); const timeNode = document.createElement('div'); timeNode.className = 'chat-time'; timeNode.textContent = safeText(message.created_at || message.generated_at || message.timestamp, ''); const contentNode = document.createElement('div'); contentNode.className = 'chat-message'; contentNode.textContent = messageBody(message) || 'No message content'; bubble.appendChild(roleNode); if (timeNode.textContent) bubble.appendChild(timeNode); bubble.appendChild(contentNode); const attachment = messageAttachment(message); if (attachment && attachment.url) {{ const previewImg = document.createElement('img'); previewImg.src = safeText(attachment.thumbnail_url || attachment.url, ''); previewImg.alt = safeText(attachment.filename || 'Attached screenshot', 'Attached screenshot'); previewImg.style.marginTop = '10px'; previewImg.style.maxWidth = '320px'; previewImg.style.width = '100%'; previewImg.style.borderRadius = '10px'; previewImg.style.border = '1px solid rgba(97,219,191,0.18)'; previewImg.style.background = 'rgba(3,15,13,0.82)'; const attachmentMeta = document.createElement('div'); attachmentMeta.className = 'chat-time'; attachmentMeta.textContent = `${{safeText(attachment.filename, 'image')}} · ${{Math.max(1, Math.round(Number(attachment.size_bytes || 0) / 1024))}} KB`; bubble.appendChild(previewImg); bubble.appendChild(attachmentMeta); }} chatThread.appendChild(bubble); }}); }} chatThread.scrollTop = chatThread.scrollHeight; updateCopyButtonState(); chatStatus.textContent = visitor.memory_summary ? safeText(visitor.memory_summary) : 'TOD operator chat is ready.'; renderChatActivity(session); const autoTrigger = latestConversation && typeof latestConversation.auto_trigger === 'object' ? latestConversation.auto_trigger : null; const enabled = Boolean(autoTrigger && autoTrigger.enabled); const statusCodes = autoTrigger && Array.isArray(autoTrigger.status_codes) ? autoTrigger.status_codes.map((value) => safeText(value, '').toLowerCase()).filter(Boolean) : []; const autoPrompt = autoTrigger ? safeText(autoTrigger.prompt, '') : ''; const shouldAutoTrigger = enabled && autoPrompt && statusCodes.includes(safeText(currentStatusCode, 'unknown').toLowerCase()) && messages.length === 0; if (shouldAutoTrigger) {{ const storageKey = getAutoTriggerStorageKey(sessionKey, currentStatusCode, autoPrompt); if (!hasAutoTriggered(storageKey)) {{ markAutoTriggered(storageKey); sendChatPrompt(autoPrompt, safeText(autoTrigger && autoTrigger.success_text, 'TOD auto-resolution request sent.')).then((ok) => {{ if (!ok) clearAutoTriggered(storageKey); }}); }} }} }}
    function renderChatState(data) {{ const session = data && typeof data.session === 'object' ? data.session : {{}}; const messages = Array.isArray(data && data.messages) ? data.messages : []; latestChatMessages = messages; const visitor = data && typeof data.visitor === 'object' ? data.visitor : {{}}; latestVisitor = visitor; latestSessionActivity = session && typeof session.activity === 'object' ? session.activity : {{}}; const sessionKey = safeText(session.session_key || getChatSessionKey(latestConversation && latestConversation.default_session_key), 'unknown'); if (shouldRotateStaleChatSession(session, messages)) {{ rotateChatSession(latestConversation && latestConversation.default_session_key); chatStatus.textContent = 'Started a fresh TOD chat session because the previous thread was stale.'; clearNode(chatThread); appendCollectionItem(chatThread, 'TOD Chat', '', 'Started a fresh TOD session because the previous thread was stale. Ask for current status, next steps, or send a new request.'); latestSessionActivity = {{ state: 'idle', label: 'Fresh Session', summary: 'Started a fresh TOD session after the previous thread went stale.' }}; renderTopActivity(); updateCopyButtonState(); setTimeout(() => {{ refreshChatState().catch((error) => {{ chatStatus.textContent = safeText(error && error.message, 'Unable to refresh fresh TOD session.'); }}); }}, 0); return; }} chatSessionMeta.textContent = `Session: ${{sessionKey}} · User: ${{safeText(visitor.name, 'Dave')}}`; const scrollSnapshot = snapshotChatScroll(); clearNode(chatThread); if (!messages.length) {{ appendCollectionItem(chatThread, 'TOD Chat', '', 'No TOD messages are in this session yet. Ask for status, blockers, training progress, execution work, or attach a screenshot.'); }} else {{ messages.forEach((message) => {{ const bubble = document.createElement('article'); const role = messageRole(message); bubble.className = `chat-bubble ${{role}}`; const roleNode = document.createElement('div'); roleNode.className = 'chat-role'; roleNode.textContent = messageLabel(message, role); const timeNode = document.createElement('div'); timeNode.className = 'chat-time'; timeNode.textContent = safeText(message.created_at || message.generated_at || message.timestamp, ''); const contentNode = document.createElement('div'); contentNode.className = 'chat-message'; contentNode.textContent = messageBody(message) || 'No message content'; bubble.appendChild(roleNode); if (timeNode.textContent) bubble.appendChild(timeNode); bubble.appendChild(contentNode); const attachment = messageAttachment(message); if (attachment && attachment.url) {{ const previewImg = document.createElement('img'); previewImg.src = safeText(attachment.thumbnail_url || attachment.url, ''); previewImg.alt = safeText(attachment.filename || 'Attached screenshot', 'Attached screenshot'); previewImg.style.marginTop = '10px'; previewImg.style.maxWidth = '320px'; previewImg.style.width = '100%'; previewImg.style.borderRadius = '10px'; previewImg.style.border = '1px solid rgba(97,219,191,0.18)'; previewImg.style.background = 'rgba(3,15,13,0.82)'; const attachmentMeta = document.createElement('div'); attachmentMeta.className = 'chat-time'; attachmentMeta.textContent = `${{safeText(attachment.filename, 'image')}} · ${{Math.max(1, Math.round(Number(attachment.size_bytes || 0) / 1024))}} KB`; bubble.appendChild(previewImg); bubble.appendChild(attachmentMeta); }} chatThread.appendChild(bubble); }}); }} restoreChatScroll(scrollSnapshot, messages); updateCopyButtonState(); chatStatus.textContent = visitor.memory_summary ? safeText(visitor.memory_summary) : 'TOD operator chat is ready.'; renderTopActivity(); const autoTrigger = latestConversation && typeof latestConversation.auto_trigger === 'object' ? latestConversation.auto_trigger : null; const enabled = Boolean(autoTrigger && autoTrigger.enabled); const statusCodes = autoTrigger && Array.isArray(autoTrigger.status_codes) ? autoTrigger.status_codes.map((value) => safeText(value, '').toLowerCase()).filter(Boolean) : []; const autoPrompt = autoTrigger ? safeText(autoTrigger.prompt, '') : ''; const shouldAutoTrigger = enabled && autoPrompt && statusCodes.includes(safeText(currentStatusCode, 'unknown').toLowerCase()) && messages.length === 0; if (shouldAutoTrigger) {{ const storageKey = getAutoTriggerStorageKey(sessionKey, currentStatusCode, autoPrompt); if (!hasAutoTriggered(storageKey)) {{ markAutoTriggered(storageKey); sendChatPrompt(autoPrompt, safeText(autoTrigger && autoTrigger.success_text, 'TOD auto-resolution request sent.')).then((ok) => {{ if (!ok) clearAutoTriggered(storageKey); }}); }} }} }}
    async function refreshChatState() {{ if (!latestConversation || !latestConversation.enabled) {{ chatStatus.textContent = 'TOD operator chat is disabled on this surface.'; return; }} const sessionKey = getChatSessionKey(latestConversation.default_session_key); const url = `${{safeText(latestConversation.state_url, '/tod/ui/chat/state')}}?session_key=${{encodeURIComponent(sessionKey)}}&mode=${{encodeURIComponent(safeText(latestConversation.mode, 'tod'))}}`; const response = await fetch(url, {{ cache: 'no-store' }}); if (!response.ok) throw new Error(`chat-state-${{response.status}}`); const data = await response.json(); renderChatState(data); }}
    async function sendChatPrompt(message, successText) {{ if (!latestConversation || !latestConversation.enabled) {{ chatStatus.textContent = 'TOD chat is unavailable.'; return false; }} const trimmedMessage = String(message || '').trim(); if (!trimmedMessage) {{ chatStatus.textContent = 'Enter a message for TOD first.'; return false; }} setChatButtonsDisabled(true); chatStatus.textContent = 'Sending to TOD...'; try {{ const response = await fetch(safeText(latestConversation.message_url, '/tod/ui/chat/message'), {{ method: 'POST', headers: {{ 'Content-Type': 'application/json' }}, body: JSON.stringify({{ message: trimmedMessage, mode: safeText(latestConversation.mode, 'tod'), session_key: getChatSessionKey(latestConversation.default_session_key) }}) }}); if (!response.ok) throw new Error(`chat-send-${{response.status}}`); chatInput.value = ''; await refreshChatState(); chatStatus.textContent = safeText(successText, 'TOD replied on this operator channel.'); return true; }} catch (error) {{ chatStatus.textContent = `TOD chat failed: ${{safeText(error && error.message, 'unknown error')}}`; return false; }} finally {{ setChatButtonsDisabled(false); }} }}
    async function uploadComposerImage() {{ if (!(selectedComposerImage instanceof File)) return false; if (!latestConversation || !latestConversation.enabled) {{ chatStatus.textContent = 'TOD image upload is unavailable.'; return false; }} const uploadUrl = safeText((latestConversation.actions && latestConversation.actions.upload_url) || latestConversation.upload_url, '/tod/ui/chat/upload-image'); setChatButtonsDisabled(true); chatStatus.textContent = 'Uploading screenshot to TOD...'; try {{ const dataUrl = await fileToDataUrl(selectedComposerImage); const response = await fetch(uploadUrl, {{ method: 'POST', headers: {{ 'Content-Type': 'application/json' }}, body: JSON.stringify({{ session_key: getChatSessionKey(latestConversation.default_session_key), mode: safeText(latestConversation.mode, 'tod'), prompt: String(chatInput && chatInput.value || '').trim(), attachment: {{ filename: selectedComposerImage.name || 'shared-image', mime_type: selectedComposerImage.type || 'image/png', size_bytes: Number(selectedComposerImage.size || 0), data_url: dataUrl }} }}) }}); if (!response.ok) throw new Error(`chat-upload-${{response.status}}`); const data = await response.json(); renderChatState(data); if (chatInput) chatInput.value = ''; resetComposerImage(); chatStatus.textContent = 'Screenshot attached to the TOD thread. Use Send To Codex to package it for deeper review.'; return true; }} catch (error) {{ chatStatus.textContent = `TOD image upload failed: ${{safeText(error && error.message, 'unknown error')}}`; return false; }} finally {{ setChatButtonsDisabled(false); }} }}
    async function createCopilotHandoff(message, successText) {{ if (!latestConversation || !latestConversation.enabled) {{ chatStatus.textContent = 'TOD handoff is unavailable.'; return false; }} const trimmedMessage = String(message || '').trim(); if (!trimmedMessage) {{ chatStatus.textContent = 'Enter a handoff request first.'; return false; }} setChatButtonsDisabled(true); chatStatus.textContent = 'Creating Codex handoff...'; try {{ const response = await fetch(safeText(latestConversation.handoff_url, '/tod/ui/chat/handoff'), {{ method: 'POST', headers: {{ 'Content-Type': 'application/json' }}, body: JSON.stringify({{ message: trimmedMessage, mode: safeText(latestConversation.mode, 'tod'), session_key: getChatSessionKey(latestConversation.default_session_key) }}) }}); if (!response.ok) throw new Error(`handoff-send-${{response.status}}`); const data = await response.json(); renderChatState(data); chatInput.value = ''; const handoff = data && typeof data.handoff === 'object' ? data.handoff : null; chatStatus.textContent = handoff && handoff.session_id ? `${{safeText(successText, 'Codex handoff created.')}} Session: ${{safeText(handoff.session_id)}} · Codex receives the current request, strongest evidence, next validation target, and the latest screenshot from this thread when present.` : safeText(successText, 'Codex handoff created.'); return true; }} catch (error) {{ chatStatus.textContent = `TOD handoff failed: ${{safeText(error && error.message, 'unknown error')}}`; return false; }} finally {{ setChatButtonsDisabled(false); }} }}
    async function sendChatMessage(event) {{ event.preventDefault(); if (selectedComposerImage instanceof File) {{ await uploadComposerImage(); return; }} await sendChatPrompt(chatInput.value, 'TOD replied on this operator channel.'); }}
    async function handleQuickAction(actionId) {{ const action = chatQuickActionMap.get(String(actionId || '')); if (!action || !action.prompt) {{ chatStatus.textContent = 'That TOD quick action is not available right now.'; return; }} if (chatInput) chatInput.value = action.prompt; if (safeText(action.actionType, 'prompt') === 'handoff') {{ await createCopilotHandoff(action.prompt, `${{safeText(action.label, 'Quick action')}} created a Codex handoff.`); return; }} await sendChatPrompt(action.prompt, `${{safeText(action.label, 'Quick action')}} sent to TOD.`); }}
    function renderState(data) {{ const status = data && typeof data.status === 'object' ? data.status : {{}}; const quickFacts = data && typeof data.quick_facts === 'object' ? data.quick_facts : {{}}; const execution = data && typeof data.execution === 'object' ? data.execution : {{}}; const training = data && typeof data.training_status === 'object' ? data.training_status : {{}}; const phaseProgress = execution.phase_progress && typeof execution.phase_progress === 'object' ? execution.phase_progress : {{}}; const stallSignal = execution.stall_signal && typeof execution.stall_signal === 'object' ? execution.stall_signal : {{}}; const stallLevel = safeText(stallSignal.level, 'ok').toLowerCase(); const alignment = data && typeof data.objective_alignment === 'object' ? data.objective_alignment : {{}}; const evidence = data && typeof data.bridge_canonical_evidence === 'object' ? data.bridge_canonical_evidence : {{}}; const liveTask = data && typeof data.live_task_request === 'object' ? data.live_task_request : {{}}; const decision = data && typeof data.listener_decision === 'object' ? data.listener_decision : {{}}; const publish = data && typeof data.publish === 'object' ? data.publish : {{}}; const authority = data && typeof data.authority_reset === 'object' ? data.authority_reset : {{}}; latestConversation = data && typeof data.conversation === 'object' ? data.conversation : null; currentStatusCode = safeText(status.code, 'unknown').toLowerCase(); renderQuickActions(latestConversation); renderExecution(execution); renderTraining(training); renderTopActivity(); renderPrimaryStatus(status, execution); if (alignmentQuickActionPanel) alignmentQuickActionPanel.hidden = ['aligned'].includes(safeText(status.code, 'unknown').toLowerCase()); setConsoleLight(todConsoleLight, ['aligned'].includes(safeText(status.code, 'unknown').toLowerCase())); setConsoleLight(mimConsoleLight, Boolean(data.mim_status && data.mim_status.available)); factCanonicalObjective.textContent = safeText(quickFacts.canonical_objective, 'Unknown'); factCanonicalMeta.textContent = safeText(data.mim_status && data.mim_status.generated_age, 'Unknown'); factLiveObjective.textContent = safeText(quickFacts.live_request_objective, 'Unknown'); factLiveMeta.textContent = `Request age: ${{safeText(liveTask.generated_age, 'Unknown')}}`; factAlignment.textContent = safeText(alignment.status, 'unknown').replaceAll('_', ' '); factAlignmentMeta.textContent = safeText(alignment.summary, 'No alignment summary'); factListenerState.textContent = safeText(quickFacts.listener_state, 'unknown'); factListenerMeta.textContent = safeText(decision.summary, 'No listener decision summary'); if (factPhaseProgressLabel) factPhaseProgressLabel.textContent = Boolean(phaseProgress.available) ? safeText(phaseProgress.label, 'Phase Progress') : 'Phase Progress'; factPhaseProgress.textContent = Boolean(phaseProgress.available) ? `${{Math.max(0, Math.min(100, Number(phaseProgress.percent_complete || 0)))}}%` : 'Unknown'; factPhaseProgressMeta.textContent = Boolean(phaseProgress.available) ? safeText(phaseProgress.summary, 'No phase progress summary.') : 'Waiting for bounded execution progress.'; factStallWatch.textContent = stallSignal.flagged ? 'Probable stall' : stallLevel === 'implementation_pending' ? 'Held at gate' : execution.available ? 'Clear' : 'Unknown'; factStallWatchMeta.textContent = stallLevel !== 'ok' ? safeText(stallSignal.summary, stallSignal.flagged ? 'Probable stall detected.' : 'Implementation is pending.') : execution.available ? `Last update: ${{formatSeconds(execution.last_update_age_seconds)}} ago.` : 'Waiting for execution freshness evidence.'; factPublishStatus.textContent = safeText(quickFacts.publish_status, 'unknown'); factPublishMeta.textContent = safeText(publish.summary, 'No publish summary'); factAuthorityReset.textContent = safeText(quickFacts.authority_reset, 'Inactive'); factAuthorityMeta.textContent = authority.active ? safeText(authority.reason, 'Authority reset active') : 'No authority reset is active.'; renderGuidance(data.operator_guidance || []); renderHandoffs(data.recent_handoffs || []); publishSummary.textContent = safeText(publish.summary, 'No publish summary'); publishMirror.textContent = safeText(publish.mim_mirror_status, 'Unknown'); publishAccess.textContent = safeText(publish.remote_access_status, 'Unknown'); publishConsumer.textContent = safeText(publish.consumer_status, 'Unknown'); publishTime.textContent = `${{safeText(publish.uploaded_at, 'Unknown')}} · ${{safeText(publish.uploaded_age, 'Unknown')}}`; publishError.textContent = safeText(publish.error, 'None'); alignmentSummary.textContent = safeText(alignment.summary, 'No alignment summary'); alignmentTodObjective.textContent = safeText(alignment.tod_current_objective, 'Unknown'); alignmentMimObjective.textContent = safeText(alignment.mim_objective_active, 'Unknown'); alignmentEvidence.textContent = safeText(evidence.status, 'Unknown'); alignmentSignals.textContent = Array.isArray(evidence.failure_signals) && evidence.failure_signals.length ? evidence.failure_signals.join(', ') : 'None'; decisionSummary.textContent = safeText(decision.summary, 'No listener decision summary'); decisionOutcome.textContent = safeText(decision.decision_outcome, 'Unknown'); decisionReason.textContent = safeText(decision.reason_code, 'Unknown'); decisionState.textContent = safeText(decision.execution_state, 'Unknown'); decisionNextStep.textContent = safeText(decision.next_step_recommendation, 'Unknown'); decisionAge.textContent = safeText(decision.generated_age, 'Unknown'); authoritySummary.textContent = authority.active ? safeText(authority.reason, 'Authority reset is active.') : 'Authority reset is inactive.'; authorityCurrent.textContent = safeText(authority.authoritative_current_objective, 'Unknown'); authorityMaxValid.textContent = safeText(authority.max_valid_objective, 'Unknown'); authorityEffective.textContent = authority.active ? `${{safeText(authority.effective_at, 'Unknown')}} · ${{safeText(authority.effective_age, 'Unknown')}}` : 'Inactive'; authorityInvalidated.textContent = Array.isArray(authority.invalidated_objectives) && authority.invalidated_objectives.length ? authority.invalidated_objectives.join(', ') : 'None'; footerGenerated.textContent = `Generated: ${{safeText(data.generated_at, 'Unknown')}}`; }}
    async function refresh() {{ const res = await fetch('/tod/ui/state', {{ cache: 'no-store' }}); if (!res.ok) throw new Error(`tod-ui-state-${{res.status}}`); const data = await res.json(); renderState(data); await refreshChatState(); }}
    chatForm.addEventListener('submit', sendChatMessage);
    if (chatImageUploadButton && chatImageUploadInput) {{ chatImageUploadButton.addEventListener('click', () => chatImageUploadInput.click()); chatImageUploadInput.addEventListener('change', () => {{ const file = chatImageUploadInput.files && chatImageUploadInput.files[0] ? chatImageUploadInput.files[0] : null; if (file) setComposerImage(file); }}); }}
    if (chatImageRemoveButton) chatImageRemoveButton.addEventListener('click', resetComposerImage);
    if (chatInput) {{ chatInput.addEventListener('paste', (event) => {{ const items = event.clipboardData && event.clipboardData.items ? Array.from(event.clipboardData.items) : []; for (const item of items) {{ if (String(item.type || '').toLowerCase().startsWith('image/')) {{ const file = item.getAsFile(); if (file) {{ event.preventDefault(); setComposerImage(file); return; }} }} }} }}); }}
    if (chatDropzone) {{ ['dragenter', 'dragover'].forEach((eventName) => {{ chatDropzone.addEventListener(eventName, (event) => {{ event.preventDefault(); chatDropzone.classList.add('active'); }}); }}); ['dragleave', 'drop'].forEach((eventName) => {{ chatDropzone.addEventListener(eventName, (event) => {{ event.preventDefault(); if (eventName !== 'drop') chatDropzone.classList.remove('active'); }}); }}); chatDropzone.addEventListener('drop', (event) => {{ chatDropzone.classList.remove('active'); const file = event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files[0] ? event.dataTransfer.files[0] : null; if (file) setComposerImage(file); }}); }}
    copyLastTodResponseButton.addEventListener('click', handleCopyLastTodResponse);
    if (trainingQuickActionButton) trainingQuickActionButton.addEventListener('click', () => handleQuickAction('start-training'));
    if (alignmentQuickActionButton) alignmentQuickActionButton.addEventListener('click', () => handleQuickAction('resolve-drift'));
    if (handoffQuickActionButton) handoffQuickActionButton.addEventListener('click', () => handleQuickAction('send-to-copilot'));
    async function refreshLoop() {{ try {{ await refresh(); }} catch (error) {{ statusChip.textContent = 'ERROR'; statusChip.dataset.tone = 'blocked'; statusHeadline.textContent = 'TOD console refresh failed'; statusSummary.textContent = safeText(error && error.message, 'Unknown refresh failure'); chatStatus.textContent = safeText(error && error.message, 'Unknown refresh failure'); }} }}
    refreshLoop();
    setInterval(refreshLoop, 5000);
  </script>
</body>
</html>
        """
    )


@router.get("/chat", response_class=HTMLResponse)
async def chat_console() -> HTMLResponse:
        title = f"Direct Chat | {settings.app_name}"
        return HTMLResponse(
                f"""
<!doctype html>
<html lang=\"en\">
<head>
    <meta charset=\"utf-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
    <title>{title}</title>
    <style>
        :root {{ --bg-0:#04070a; --bg-1:#09131a; --panel:rgba(7,18,22,0.88); --line:rgba(102,255,188,0.28); --line-strong:rgba(102,255,188,0.65); --ink:#ddfff0; --muted:#88c9af; --accent:#2dff9d; --warn:#ffd166; --good:#2dff9d; --bad:#ff5c7a; --font:"Space Mono","Consolas","Cascadia Mono",monospace; }}
        * {{ box-sizing:border-box; }}
        body {{ margin:0; min-height:100vh; color:var(--ink); font-family:var(--font); background:radial-gradient(circle at 15% 12%, rgba(45,255,157,0.18), transparent 34%), radial-gradient(circle at 88% 10%, rgba(0,174,255,0.14), transparent 32%), linear-gradient(160deg, var(--bg-0), var(--bg-1)); }}
        .page {{ max-width:1320px; margin:0 auto; padding:24px 16px 40px; }}
        .shell {{ border:1px solid var(--line); border-radius:16px; background:var(--panel); overflow:hidden; box-shadow:0 0 28px rgba(45,255,157,0.10); }}
        .hero {{ padding:24px; border-bottom:1px solid var(--line); background:linear-gradient(120deg, rgba(45,255,157,0.14), rgba(0,120,90,0.05)); }}
        .console-nav {{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; margin-bottom:14px; }}
        .console-link {{ display:inline-flex; align-items:center; gap:8px; padding:8px 12px; border-radius:999px; border:1px solid var(--line); background:rgba(4,18,16,0.78); color:var(--ink); text-decoration:none; font-size:12px; font-weight:800; letter-spacing:0.08em; text-transform:uppercase; }}
        .console-link.active {{ border-color:var(--line-strong); box-shadow:inset 0 0 0 1px rgba(45,255,157,0.14), 0 0 12px rgba(45,255,157,0.12); }}
        .console-link.utility {{ background:rgba(4,18,16,0.64); }}
        .eyebrow {{ font-size:12px; text-transform:uppercase; letter-spacing:0.16em; color:var(--accent); font-weight:700; }}
        h1 {{ margin:10px 0 8px; font-size:clamp(28px, 4vw, 44px); line-height:1; text-transform:uppercase; text-shadow:0 0 10px rgba(45,255,157,0.32); }}
        .hero-copy {{ max-width:880px; color:var(--muted); font-size:15px; line-height:1.5; }}
        .hero-meta {{ margin-top:16px; display:grid; grid-template-columns:repeat(4, minmax(0, 1fr)); gap:12px; }}
        .fact {{ border:1px solid rgba(97,219,191,0.16); border-radius:12px; background:rgba(2,12,10,0.72); padding:14px; }}
        .fact-label {{ font-size:12px; text-transform:uppercase; letter-spacing:0.12em; color:var(--muted); }}
        .fact-value {{ margin-top:8px; font-size:18px; font-weight:800; line-height:1.2; }}
        .fact-meta {{ margin-top:8px; color:var(--muted); font-size:13px; line-height:1.45; }}
        .grid {{ display:grid; grid-template-columns:minmax(0, 0.9fr) minmax(0, 1.1fr); gap:18px; padding:22px 24px 24px; }}
        .panel {{ border:1px solid rgba(97,219,191,0.20); border-radius:14px; background:rgba(3,15,13,0.86); padding:18px; }}
        .panel h2 {{ margin:0 0 12px; font-size:16px; }}
        .panel-copy {{ color:var(--muted); font-size:14px; line-height:1.5; }}
        .launch-grid {{ display:grid; gap:12px; grid-template-columns:repeat(2, minmax(0, 1fr)); margin-top:14px; }}
        .launch-card {{ border:1px solid rgba(97,219,191,0.18); border-radius:12px; background:rgba(2,12,10,0.76); padding:14px; }}
        .launch-card strong {{ display:block; font-size:13px; text-transform:uppercase; letter-spacing:0.10em; color:var(--accent); }}
        .launch-card p {{ margin:10px 0 12px; color:var(--muted); font-size:13px; line-height:1.5; }}
        .button-row {{ display:flex; gap:10px; flex-wrap:wrap; }}
        .btn {{ appearance:none; border:1px solid var(--line); border-radius:10px; padding:11px 15px; background:linear-gradient(120deg, rgba(11,110,79,0.9), rgba(45,255,157,0.33)); color:#ebfff4; font:inherit; font-size:13px; font-weight:700; cursor:pointer; text-decoration:none; }}
        .btn.secondary {{ background:rgba(4,20,17,0.78); color:var(--ink); }}
        .btn:disabled {{ opacity:0.65; cursor:wait; }}
        .chat-meta {{ display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap; font-size:12px; color:var(--muted); margin-top:12px; }}
        .chat-thread {{ min-height:320px; max-height:520px; overflow-y:auto; border:1px solid rgba(97,219,191,0.22); border-radius:10px; padding:14px; background:rgba(3,15,13,0.86); display:grid; gap:12px; margin-top:12px; }}
        .chat-bubble {{ max-width:92%; border-radius:12px; padding:12px 14px; border:1px solid rgba(97,219,191,0.18); background:rgba(4,18,16,0.85); }}
        .chat-bubble.user {{ margin-left:auto; background:linear-gradient(145deg, rgba(8,34,30,0.9), rgba(4,16,14,0.95)); border-color:rgba(45,255,157,0.30); }}
        .chat-bubble.assistant {{ margin-right:auto; }}
        .chat-role {{ font-size:12px; text-transform:uppercase; letter-spacing:0.12em; color:var(--accent); font-weight:700; }}
        .chat-time {{ font-size:12px; color:var(--muted); margin-top:4px; }}
        .chat-message {{ margin-top:8px; font-size:14px; line-height:1.55; white-space:pre-wrap; word-break:break-word; }}
        .chat-form {{ display:grid; gap:10px; margin-top:12px; }}
        .chat-input {{ width:100%; min-height:128px; resize:vertical; border-radius:10px; border:1px solid rgba(97,219,191,0.24); background:rgba(3,14,12,0.92); padding:14px; font:inherit; color:var(--ink); outline:none; }}
        .status-inline {{ font-size:12px; color:var(--muted); }}
        .chat-actions {{ display:flex; justify-content:space-between; gap:10px; align-items:center; flex-wrap:wrap; }}
        .chat-action-buttons {{ display:flex; gap:10px; flex-wrap:wrap; }}
        @media (max-width: 980px) {{ .grid {{ grid-template-columns:1fr; }} .hero-meta {{ grid-template-columns:repeat(2, minmax(0, 1fr)); }} .launch-grid {{ grid-template-columns:1fr; }} }}
        @media (max-width: 640px) {{ .hero-meta {{ grid-template-columns:1fr; }} }}
    </style>
</head>
<body>
    <main class=\"page\">
        <section class=\"shell\">
            <header class=\"hero\">
                <div class=\"console-nav\">
                    <a class=\"console-link utility\" href=\"/\">Public Home</a>
                    <a class=\"console-link utility\" href=\"/mim\">MIM Codex Chat</a>
                    <a class=\"console-link utility\" href=\"/tod\">TOD Console</a>
                    <a class=\"console-link active\" href=\"/chat\">Direct Chat</a>
                    <a class=\"console-link utility\" href=\"/mim/logout\">Logout</a>
                </div>
                <div class=\"eyebrow\">Operator Surface</div>
                <h1>Direct Copilot And Codex Bridge</h1>
                <div id=\"heroCopy\" class=\"hero-copy\">Use this page to stay on mimtod.com, send bounded operator chat messages, launch the 6-hour training runbook, or publish a direct Codex handoff without remote-login friction.</div>
                <div class=\"hero-meta\">
                    <article class=\"fact\"><div class=\"fact-label\">Status</div><div id=\"factStatus\" class=\"fact-value\">Loading</div><div id=\"factStatusMeta\" class=\"fact-meta\">Waiting for live status.</div></article>
                    <article class=\"fact\"><div class=\"fact-label\">Canonical Objective</div><div id=\"factObjective\" class=\"fact-value\">-</div><div id=\"factObjectiveMeta\" class=\"fact-meta\">Waiting for current objective.</div></article>
                    <article class=\"fact\"><div class=\"fact-label\">Listener</div><div id=\"factListener\" class=\"fact-value\">-</div><div id=\"factListenerMeta\" class=\"fact-meta\">Waiting for execution posture.</div></article>
                    <article class=\"fact\"><div class=\"fact-label\">Training</div><div id=\"factTraining\" class=\"fact-value\">-</div><div id=\"factTrainingMeta\" class=\"fact-meta\">Waiting for training telemetry.</div></article>
                </div>
            </header>
            <section class=\"grid\">
                <section class=\"panel\">
                    <h2>Launch Pads</h2>
                    <div class=\"panel-copy\">This tab is the shared bridge. Use it for direct operator actions, or jump into the dedicated TOD and MIM surfaces when you want the full console context.</div>
                    <div class=\"launch-grid\">
                        <article class=\"launch-card\"><strong>Direct Copilot Bridge</strong><p>Stay on this page to send bounded messages, launch training, or publish a Codex handoff from one place.</p><div class=\"button-row\"><button id=\"startTrainingButton\" class=\"btn\" type=\"button\">Start 6h Training</button><button id=\"sendToCodexButton\" class=\"btn secondary\" type=\"button\">Send To Codex</button></div></article>
                        <article class=\"launch-card\"><strong>Other Surfaces</strong><p>Jump straight into the TOD console or the MIM Codex chat when you want their dedicated layouts.</p><div class=\"button-row\"><a class=\"btn secondary\" href=\"/tod\">Open TOD Console</a><a class=\"btn secondary\" href=\"/mim\">Open MIM Codex Chat</a></div></article>
                    </div>
                </section>
                <section class=\"panel\">
                    <h2>Direct Chat</h2>
                    <div id=\"chatSummary\" class=\"panel-copy\">Loading direct operator chat.</div>
                    <div class=\"chat-meta\"><div id=\"chatSessionMeta\">Session: loading</div><div id=\"chatGuardrails\">Guardrails: loading</div></div>
                    <div id=\"chatThread\" class=\"chat-thread\"></div>
                    <form id=\"chatForm\" class=\"chat-form\">
                        <textarea id=\"chatInput\" class=\"chat-input\" placeholder=\"Ask for status, request a bounded repair, or tell Copilot to start the next training runbook.\"></textarea>
                        <div class=\"chat-actions\"><div id=\"chatStatus\" class=\"status-inline\">Waiting for direct chat state.</div><div class=\"chat-action-buttons\"><button id=\"copyLastReplyButton\" class=\"btn secondary\" type=\"button\">Copy Last Reply</button><button id=\"chatSendButton\" class=\"btn\" type=\"submit\">Send Message</button></div></div>
                    </form>
                </section>
            </section>
        </section>
    </main>
    <script>
        const factStatus = document.getElementById('factStatus');
        const factStatusMeta = document.getElementById('factStatusMeta');
        const factObjective = document.getElementById('factObjective');
        const factObjectiveMeta = document.getElementById('factObjectiveMeta');
        const factListener = document.getElementById('factListener');
        const factListenerMeta = document.getElementById('factListenerMeta');
        const factTraining = document.getElementById('factTraining');
        const factTrainingMeta = document.getElementById('factTrainingMeta');
        const chatSummary = document.getElementById('chatSummary');
        const chatSessionMeta = document.getElementById('chatSessionMeta');
        const chatGuardrails = document.getElementById('chatGuardrails');
        const chatThread = document.getElementById('chatThread');
        const chatForm = document.getElementById('chatForm');
        const chatInput = document.getElementById('chatInput');
        const chatStatus = document.getElementById('chatStatus');
        const chatSendButton = document.getElementById('chatSendButton');
        const copyLastReplyButton = document.getElementById('copyLastReplyButton');
        const startTrainingButton = document.getElementById('startTrainingButton');
        const sendToCodexButton = document.getElementById('sendToCodexButton');
        const CHAT_STORAGE_KEY = 'todDirectChatSessionKeyV1';
        let latestPayload = null;
        function safeText(value, fallback = '-') {{ const text = String(value || '').trim(); return text || fallback; }}
        function clearNode(node) {{ while (node && node.firstChild) node.removeChild(node.firstChild); }}
        function getSessionKey() {{ try {{ const existing = window.localStorage.getItem(CHAT_STORAGE_KEY); if (existing) return existing; const created = `copilot-operator-chat-${{Math.random().toString(36).slice(2, 10)}}`; window.localStorage.setItem(CHAT_STORAGE_KEY, created); return created; }} catch (_error) {{ return `copilot-operator-chat-${{Math.random().toString(36).slice(2, 10)}}`; }} }}
        function messageRole(message) {{ const role = safeText(message && (message.role || message.actor || message.source || message.type), 'message').toLowerCase(); if (role.includes('operator') || role.includes('visitor') || role.includes('user')) return 'user'; return 'assistant'; }}
        function messageBody(message) {{ return safeText(message && (message.content || message.message || message.text || message.body || message.summary), ''); }}
        function setButtonsDisabled(disabled) {{ chatSendButton.disabled = disabled; copyLastReplyButton.disabled = disabled; startTrainingButton.disabled = disabled; sendToCodexButton.disabled = disabled; }}
        function renderThread(messages) {{ clearNode(chatThread); if (!Array.isArray(messages) || !messages.length) {{ const empty = document.createElement('article'); empty.className = 'chat-bubble assistant'; empty.innerHTML = '<div class="chat-role">Copilot</div><div class="chat-message">No direct messages yet. Send a message, launch training, or create a Codex handoff.</div>'; chatThread.appendChild(empty); return; }} messages.forEach((message) => {{ const bubble = document.createElement('article'); const role = messageRole(message); bubble.className = `chat-bubble ${{role}}`; const roleNode = document.createElement('div'); roleNode.className = 'chat-role'; roleNode.textContent = role === 'user' ? 'Operator' : 'Copilot'; const timeNode = document.createElement('div'); timeNode.className = 'chat-time'; timeNode.textContent = safeText(message.created_at, ''); const contentNode = document.createElement('div'); contentNode.className = 'chat-message'; contentNode.textContent = messageBody(message); bubble.appendChild(roleNode); if (timeNode.textContent) bubble.appendChild(timeNode); bubble.appendChild(contentNode); chatThread.appendChild(bubble); }}); chatThread.scrollTop = chatThread.scrollHeight; }}
        function getLastExchangeText() {{ const messages = latestPayload && Array.isArray(latestPayload.messages) ? latestPayload.messages : []; if (!messages.length) return ''; let lastAssistant = null; for (let index = messages.length - 1; index >= 0; index -= 1) {{ const candidate = messages[index]; if (messageRole(candidate) !== 'assistant' || !messageBody(candidate)) continue; lastAssistant = candidate; let lastUser = null; for (let userIndex = index - 1; userIndex >= 0; userIndex -= 1) {{ const prior = messages[userIndex]; if (messageRole(prior) === 'user' && messageBody(prior)) {{ lastUser = prior; break; }} }} const lines = []; if (lastUser) {{ lines.push('User action:'); lines.push(messageBody(lastUser)); lines.push(''); }} lines.push('Assistant response:'); lines.push(messageBody(lastAssistant)); return lines.join('\\n'); }} return ''; }}
        async function copyLastExchange() {{ const transcript = getLastExchangeText(); if (!transcript) {{ chatStatus.textContent = 'No assistant reply is available to copy yet.'; return; }} if (navigator.clipboard && navigator.clipboard.writeText) {{ await navigator.clipboard.writeText(transcript); chatStatus.textContent = 'Copied the last user action and assistant reply.'; return; }} const area = document.createElement('textarea'); area.value = transcript; area.style.position = 'fixed'; area.style.opacity = '0'; document.body.appendChild(area); area.focus(); area.select(); document.execCommand('copy'); document.body.removeChild(area); chatStatus.textContent = 'Copied the last user action and assistant reply.'; }}
        function renderPayload(payload) {{ latestPayload = payload || {{}}; const status = payload && typeof payload.status === 'object' ? payload.status : {{}}; const quickFacts = payload && typeof payload.quick_facts === 'object' ? payload.quick_facts : {{}}; const guardrails = payload && typeof payload.guardrails === 'object' ? payload.guardrails : {{}}; const session = payload && typeof payload.session === 'object' ? payload.session : {{}}; const capabilities = payload && typeof payload.capabilities === 'object' ? payload.capabilities : {{}}; factStatus.textContent = safeText(status.label, 'UNKNOWN'); factStatusMeta.textContent = safeText(status.summary, 'No status summary is available.'); factObjective.textContent = safeText(quickFacts.canonical_objective, 'Unknown'); factObjectiveMeta.textContent = `Live request: ${{safeText(quickFacts.live_request_objective, 'Unknown')}}`; factListener.textContent = safeText(quickFacts.listener_state, 'Unknown'); factListenerMeta.textContent = `Decision: ${{safeText(quickFacts.decision_outcome, 'Unknown')}}`; factTraining.textContent = safeText(quickFacts.training_state, 'Unknown'); factTrainingMeta.textContent = `Progress: ${{safeText(quickFacts.training_progress, 'Unknown')}} · Training start ${{capabilities.training_start && capabilities.training_start.available ? 'ready' : 'unavailable'}}`; chatSummary.textContent = safeText(payload && payload.visitor && payload.visitor.memory_summary, 'Direct operator chat is ready.'); chatSessionMeta.textContent = `Session: ${{safeText(session.session_key, getSessionKey())}} · Messages: ${{safeText(session.message_count, '0')}}`; chatGuardrails.textContent = `Guardrails: commands blocked = ${{guardrails.commands_blocked ? 'yes' : 'no'}}, live execution blocked = ${{guardrails.live_execution_blocked ? 'yes' : 'no'}}`; renderThread(payload && payload.messages); copyLastReplyButton.disabled = !(payload && Array.isArray(payload.messages) && payload.messages.length); }}
        async function fetchState() {{ const response = await fetch(`/chat/ui/state?session_key=${{encodeURIComponent(getSessionKey())}}&mode=chat`, {{ cache: 'no-store' }}); if (!response.ok) throw new Error(`chat-state-${{response.status}}`); renderPayload(await response.json()); }}
        async function postJson(path, body, successText) {{ setButtonsDisabled(true); chatStatus.textContent = 'Sending request...'; try {{ const response = await fetch(path, {{ method: 'POST', headers: {{ 'Content-Type': 'application/json' }}, body: JSON.stringify(body) }}); if (!response.ok) throw new Error(`${{path}}-${{response.status}}`); const payload = await response.json(); renderPayload(payload); chatStatus.textContent = successText; return true; }} catch (error) {{ chatStatus.textContent = `Request failed: ${{safeText(error && error.message, 'unknown error')}}`; return false; }} finally {{ setButtonsDisabled(false); }} }}
        async function sendMessage(event) {{ event.preventDefault(); const message = String(chatInput.value || '').trim(); if (!message) {{ chatStatus.textContent = 'Enter a message first.'; return; }} const sent = await postJson('/chat/ui/message', {{ session_key: getSessionKey(), mode: 'chat', message }}, 'Direct operator message delivered.'); if (sent) chatInput.value = ''; }}
        async function startTraining() {{ await postJson('/chat/ui/action/training', {{ session_key: getSessionKey(), mode: 'chat' }}, 'Training action submitted.'); }}
        async function sendToCodex() {{ const message = String(chatInput.value || '').trim() || 'Package the current issue, evidence, and next bounded repair request for Codex-style troubleshooting.'; const sent = await postJson('/chat/ui/handoff', {{ session_key: getSessionKey(), mode: 'chat', message }}, 'Codex handoff created.'); if (sent) chatInput.value = ''; }}
        chatForm.addEventListener('submit', sendMessage);
        copyLastReplyButton.addEventListener('click', copyLastExchange);
        startTrainingButton.addEventListener('click', startTraining);
        sendToCodexButton.addEventListener('click', sendToCodex);
        fetchState().catch((error) => {{ chatStatus.textContent = safeText(error && error.message, 'Unable to load direct chat state.'); }});
        setInterval(() => fetchState().catch(() => {{}}), 5000);
    </script>
</body>
</html>
                """
        )